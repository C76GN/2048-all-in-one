## AchievementListDialog: 响应式成就列表 GF UI Route。
class_name AchievementListDialog
extends GameUiController


const ACHIEVEMENT_CARD_SCENE: PackedScene = preload(
	"res://features/achievements/scenes/ui/achievement_card.tscn"
)
const _COMPACT_BREAKPOINT: float = 720.0


# --- 私有变量 ---

var _achievement_system: AchievementSystem = null
var _signal_utility: GFSignalUtility = null
var _viewport_utility: GFViewportUtility = null
var _layout_update_queued: bool = false
var _has_revealed_achievement_list: bool = false
var _cards_by_id: Dictionary = {}
var _achievement_view: GFTableDataView = GFTableDataView.new()
var _state_predicate: _AchievementStatePredicate = _AchievementStatePredicate.new()


# --- @onready 变量 (节点引用) ---

@onready var _outer_margin: MarginContainer = %OuterMargin
@onready var _surface: PanelContainer = $OuterMargin/Surface
@onready var _header: BoxContainer = %Header
@onready var _title_label: Label = %TitleLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _back_button: Button = %BackButton
@onready var _filters: BoxContainer = %Filters
@onready var _search_input: LineEdit = %SearchInput
@onready var _state_filter: OptionButton = %StateFilter
@onready var _list: VBoxContainer = %AchievementList
@onready var _empty_label: Label = %EmptyLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_dependencies()
	_configure_achievement_projection()
	_bind_runtime_signals()
	_apply_semantic_styles()
	_update_ui_text()
	_queue_layout_update()
	call_deferred(&"_focus_initial_control")


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


# --- 私有/辅助方法 ---

func _focus_initial_control() -> void:
	if is_inside_tree() and is_instance_valid(_search_input):
		_search_input.grab_focus()


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_panel_container(
		_surface,
		GameUiStyleUtility.SurfaceRole.SHELL,
		GameUiStyleUtility.BorderRole.DEFAULT,
		2
	)
	style.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_summary_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_empty_label, GameUiStyleUtility.TextRole.MUTED)
	style.style_button(_back_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	for value: Variant in _cards_by_id.values():
		if value is AchievementCard and is_instance_valid(value):
			var card: AchievementCard = value
			card.apply_semantic_styles(style)


func _update_ui_text() -> void:
	if not is_node_ready():
		return
	_title_label.text = tr("ACHIEVEMENTS_TITLE")
	_back_button.text = tr("BACK_BUTTON")
	_search_input.placeholder_text = tr("ACHIEVEMENTS_SEARCH_PLACEHOLDER")
	_empty_label.text = tr("ACHIEVEMENTS_EMPTY")
	_setup_state_filter()
	_rebuild_list()


func _resolve_dependencies() -> void:
	var system_value: Object = get_system(AchievementSystem)
	if system_value is AchievementSystem:
		_achievement_system = system_value
	var signal_value: Object = get_utility(GFSignalUtility)
	if signal_value is GFSignalUtility:
		_signal_utility = signal_value
	var viewport_value: Object = get_utility(GFViewportUtility)
	if viewport_value is GFViewportUtility:
		_viewport_utility = viewport_value


func _bind_runtime_signals() -> void:
	if not is_instance_valid(_signal_utility):
		push_error("[AchievementListDialog] 缺少 GFSignalUtility。")
		return
	var _back_connection: GFSignalConnection = _signal_utility.connect_signal(
		_back_button.pressed,
		_close_dialog,
		self
	)
	var _search_connection: GFSignalConnection = _signal_utility.connect_signal(
		_search_input.text_changed,
		_on_filter_changed,
		self
	)
	var _filter_connection: GFSignalConnection = _signal_utility.connect_signal(
		_state_filter.item_selected,
		_on_state_filter_changed,
		self
	)
	var _resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		resized,
		_queue_layout_update,
		self
	)
	if is_instance_valid(_achievement_system):
		var _progress_connection: GFSignalConnection = _signal_utility.connect_signal(
			_achievement_system.achievement_progress_changed,
			_on_achievement_progress_changed,
			self
		)


func _setup_state_filter() -> void:
	var selected_index: int = maxi(_state_filter.selected, 0)
	_state_filter.clear()
	_state_filter.add_item(tr("ACHIEVEMENTS_FILTER_ALL"), 0)
	_state_filter.add_item(tr("ACHIEVEMENTS_FILTER_UNLOCKED"), 1)
	_state_filter.add_item(tr("ACHIEVEMENTS_FILTER_IN_PROGRESS"), 2)
	_state_filter.select(clampi(selected_index, 0, _state_filter.item_count - 1))


func _configure_achievement_projection() -> void:
	var completed_column: GFTableColumnDefinition = (
		GFTableColumnDefinition.new().configure(&"completed")
	)
	completed_column.visible = false
	completed_column.sortable = false
	completed_column.filterable = false
	var search_column: GFTableColumnDefinition = (
		GFTableColumnDefinition.new().configure(&"search_text")
	)
	# GFTableDataView 的全文过滤只遍历 visible 且 filterable 的列。
	# 此处的 visible 是数据视图语义；项目 Card 渲染不会显示这列。
	search_column.visible = true
	search_column.sortable = false
	var columns_result: GFTableViewRebuildResult = _achievement_view.set_columns([
		completed_column,
		search_column,
	])
	var row_id_result: GFTableViewRebuildResult = (
		_achievement_view.set_row_id_column(&"achievement_id")
	)
	var predicate_result: GFTableViewRebuildResult = (
		_achievement_view.set_row_predicates([
			GFTableRowPredicateRegistration.create(
				&"achievement_state",
				_state_predicate
			),
		])
	)
	if not (
		columns_result.is_successful()
		and row_id_result.is_successful()
		and predicate_result.is_successful()
	):
		push_error("[AchievementListDialog] GF table 成就投影配置失败。")


func _rebuild_list() -> void:
	if not is_instance_valid(_achievement_system):
		_clear_cached_cards()
		_empty_label.visible = true
		_summary_label.text = tr("ACHIEVEMENTS_PROGRESS") % [0, 0]
		return

	var entries: Array[Dictionary] = _achievement_system.get_entries()
	_state_predicate.filter_index = _state_filter.selected
	var filter_result: GFTableViewRebuildResult = _achievement_view.set_filter_query(
		_search_input.text.strip_edges()
	)
	var rows: Array = []
	for entry: Dictionary in entries:
		var achievement_id: StringName = GFVariantData.get_option_string_name(
			entry,
			&"achievement_id"
		)
		if achievement_id == &"":
			continue
		rows.append({
			&"achievement_id": achievement_id,
			&"completed": GFVariantData.get_option_bool(entry, &"completed"),
			&"search_text": _make_achievement_search_text(entry),
			&"entry": entry,
		})
	var rows_result: GFTableViewRebuildResult = _achievement_view.set_rows(rows)
	if not filter_result.is_successful() or not rows_result.is_successful():
		push_error("[AchievementListDialog] GF table 成就过滤事务失败。")
		return
	var desired_ids: Dictionary = {}
	var created_cards: Array[Control] = []
	for visible_index: int in range(_achievement_view.get_visible_row_count()):
		var row_value: Variant = _achievement_view.get_visible_row(visible_index)
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var achievement_id: StringName = GFVariantData.get_option_string_name(
			row,
			&"achievement_id"
		)
		if achievement_id == &"":
			continue
		var entry: Dictionary = GFVariantData.get_option_dictionary(row, &"entry")
		if entry.is_empty():
			continue
		desired_ids[achievement_id] = true
		var card: AchievementCard = _get_cached_card(achievement_id)
		if not is_instance_valid(card):
			card = _create_card(achievement_id)
			if not is_instance_valid(card):
				continue
			created_cards.append(card)
		if card.get_index() != visible_index:
			_list.move_child(
				card,
				mini(visible_index, _list.get_child_count() - 1)
			)
		card.configure(entry)
	_remove_stale_cards(desired_ids)
	var visible_count: int = _achievement_view.get_visible_row_count()
	_empty_label.visible = visible_count == 0
	var summary: Dictionary = _achievement_system.get_summary()
	_summary_label.text = tr("ACHIEVEMENTS_PROGRESS") % [
		GFVariantData.get_option_int(summary, "unlocked_count", 0),
		GFVariantData.get_option_int(summary, "achievement_count", 0),
	]
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(motion):
		var _bound_count: int = motion.bind_interactive_controls(_list)
		if not _has_revealed_achievement_list:
			_has_revealed_achievement_list = true
			var _reveal_count: int = motion.play_children_reveal(
				_list,
				Vector2.ZERO,
				0.020,
				0.0,
				0.14
			)
		else:
			for index: int in range(created_cards.size()):
				var card: Control = created_cards[index]
				if not card.visible:
					continue
				var _reveal_tween: Tween = motion.play_control_reveal(
					card,
					Vector2(8.0, 0.0),
					0.14,
					minf(float(index) * 0.020, 0.12)
				)


func _get_cached_card(achievement_id: StringName) -> AchievementCard:
	var value: Variant = _cards_by_id.get(achievement_id)
	return value if value is AchievementCard and is_instance_valid(value) else null


func _create_card(achievement_id: StringName) -> AchievementCard:
	var card_node: Node = ACHIEVEMENT_CARD_SCENE.instantiate()
	if not card_node is AchievementCard:
		card_node.queue_free()
		return null
	var card: AchievementCard = card_node
	card.set_meta(&"achievement_id", achievement_id)
	_list.add_child(card)
	card.apply_semantic_styles(_get_ui_style_utility())
	_cards_by_id[achievement_id] = card
	return card


func _remove_stale_cards(desired_ids: Dictionary) -> void:
	for id_value: Variant in _cards_by_id.keys():
		var achievement_id: StringName = StringName(GFVariantData.to_text(id_value))
		if desired_ids.has(achievement_id):
			continue
		var card: AchievementCard = _get_cached_card(achievement_id)
		if is_instance_valid(card):
			if card.get_parent() == _list:
				_list.remove_child(card)
			card.queue_free()
		var _erased: bool = _cards_by_id.erase(achievement_id)


func _clear_cached_cards() -> void:
	for value: Variant in _cards_by_id.values():
		if value is AchievementCard and is_instance_valid(value):
			var card: AchievementCard = value
			if card.get_parent() == _list:
				_list.remove_child(card)
			card.queue_free()
	_cards_by_id.clear()


func _make_achievement_search_text(entry: Dictionary) -> String:
	var completed: bool = GFVariantData.get_option_bool(entry, &"completed")
	if (
		GFVariantData.get_option_bool(entry, &"hidden_until_unlocked")
		and not completed
	):
		return ""
	return "%s %s" % [
		tr(GFVariantData.get_option_string_name(entry, &"title_key")),
		tr(GFVariantData.get_option_string_name(entry, &"description_key")),
	]


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var compact: bool = size.x < _COMPACT_BREAKPOINT
	_header.vertical = compact
	_filters.vertical = compact
	var margins: Dictionary = (
		{"top": 10.0, "left": 10.0, "bottom": 10.0, "right": 10.0}
		if compact
		else {"top": 24.0, "left": 28.0, "bottom": 24.0, "right": 28.0}
	)
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_outer_margin,
			get_viewport(),
			margins
		)


func _close_dialog() -> void:
	var _closed: bool = _close_current_popup_route(
		GameUiRouterUtility.ROUTE_ACHIEVEMENTS
	)


# --- 信号处理函数 ---

func _on_filter_changed(_text: String) -> void:
	_rebuild_list()


func _on_state_filter_changed(_index: int) -> void:
	_rebuild_list()


func _on_achievement_progress_changed(
	_achievement_id: StringName,
	_current_value: int,
	_target_value: int
) -> void:
	_rebuild_list()


# --- 内部类 ---

class _AchievementStatePredicate extends GFTableRowPredicate:
	var filter_index: int = 0


	func _evaluate(row_view: GFTableRowView) -> GFTableRowPredicateResult:
		var completed: bool = GFVariantData.to_bool(
			row_view.get_value(&"completed", false)
		)
		if filter_index == 1 and not completed:
			return GFTableRowPredicateResult.excluded()
		if filter_index == 2 and completed:
			return GFTableRowPredicateResult.excluded()
		return GFTableRowPredicateResult.included()
