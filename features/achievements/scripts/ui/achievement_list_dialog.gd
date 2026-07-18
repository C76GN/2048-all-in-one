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


# --- @onready 变量 (节点引用) ---

@onready var _outer_margin: MarginContainer = %OuterMargin
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
	_bind_runtime_signals()
	_update_ui_text()
	_queue_layout_update()
	_search_input.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_dialog()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


# --- 私有/辅助方法 ---

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


func _rebuild_list() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	if not is_instance_valid(_achievement_system):
		_empty_label.visible = true
		_summary_label.text = tr("ACHIEVEMENTS_PROGRESS") % [0, 0]
		return

	var entries: Array[Dictionary] = _achievement_system.get_entries()
	var visible_count: int = 0
	for entry: Dictionary in entries:
		if not _matches_filters(entry):
			continue
		var card_node: Node = ACHIEVEMENT_CARD_SCENE.instantiate()
		if not card_node is AchievementCard:
			card_node.queue_free()
			continue
		var card: AchievementCard = card_node
		_list.add_child(card)
		card.configure(entry)
		visible_count += 1
	_empty_label.visible = visible_count == 0
	var summary: Dictionary = _achievement_system.get_summary()
	_summary_label.text = tr("ACHIEVEMENTS_PROGRESS") % [
		GFVariantData.get_option_int(summary, "unlocked_count", 0),
		GFVariantData.get_option_int(summary, "achievement_count", 0),
	]


func _matches_filters(entry: Dictionary) -> bool:
	var completed: bool = GFVariantData.get_option_bool(entry, &"completed")
	match _state_filter.selected:
		1:
			if not completed:
				return false
		2:
			if completed:
				return false
	var query: String = _search_input.text.strip_edges().to_lower()
	if query.is_empty():
		return true
	if (
		GFVariantData.get_option_bool(entry, &"hidden_until_unlocked")
		and not completed
	):
		return false
	var searchable: String = "%s %s" % [
		tr(GFVariantData.get_option_string_name(entry, &"title_key")),
		tr(GFVariantData.get_option_string_name(entry, &"description_key")),
	]
	return searchable.to_lower().contains(query)


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
