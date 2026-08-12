## ModeSelection: 模式选择界面的 UI 控制器。
##
## 负责动态展示可用模式、更新选中态、配置棋盘参数并启动游戏。
class_name ModeSelection
extends GameUiController


# --- 常量 ---

## 单个模式卡片 UI 场景。
const MODE_CARD_SCENE: PackedScene = preload("res://features/navigation/scenes/ui/mode_card.tscn")
const MODE_RULE_PROOF_DESCRIPTORS: Array[ModeRuleProofDescriptor] = [
	preload("res://features/navigation/resources/mode_rule_proofs/classic_rule_proof.tres"),
	preload("res://features/navigation/resources/mode_rule_proofs/fibonacci_rule_proof.tres"),
	preload("res://features/navigation/resources/mode_rule_proofs/lucas_fibonacci_rule_proof.tres"),
	preload("res://features/navigation/resources/mode_rule_proofs/progressive_rule_proof.tres"),
	preload("res://features/navigation/resources/mode_rule_proofs/step_by_step_rule_proof.tres"),
	preload("res://features/navigation/resources/mode_rule_proofs/ratio_rule_proof.tres"),
]
const _CARD_REVEAL_OFFSET: Vector2 = Vector2(18.0, 0.0)
const _COMPETITION_CONFIG_STATUS_FORMAT_FALLBACK: String = "本地比赛榜：%s · 当前配置最佳 %s"
const _COMPETITION_STATUS_ELIGIBLE_FALLBACK: String = "合格"
const _COMPETITION_STATUS_INELIGIBLE_FORMAT_FALLBACK: String = "不计入（%s）"
const _DESKTOP_SAFE_AREA_MARGINS: Dictionary = {
	"top": 54.0,
	"left": 56.0,
	"bottom": 54.0,
	"right": 56.0,
}
## 单列时右侧纸面会向容器外扩并投下硬阴影，需要比通用紧凑页更宽的裁切余量。
const _STACKED_SAFE_AREA_MARGINS: Dictionary = {
	"top": 22.0,
	"left": 28.0,
	"bottom": 22.0,
	"right": 28.0,
}
## ScrollContainer 会裁切子节点越界绘制；为单列纸面保留完整外扩边、阴影和文字阴影。
const _STACKED_SURFACE_OVERFLOW_MARGINS: Dictionary = {
	"top": 16,
	"left": 20,
	"bottom": 24,
	"right": 28,
}
## 近方形窗口必须提前堆叠；双栏表面的外扩纸边与阴影也需要安全余量。
## 960×540 仍能承载紧凑的双栏主任务；更窄或竖屏才按顺序堆叠。
const _COMPACT_TWO_PANE_MINIMUM_WIDTH: float = 920.0
const _COMPACT_TWO_PANE_HORIZONTAL_MARGIN: float = 24.0
const _COMPACT_TWO_PANE_SEPARATION: float = 18.0
const _COMPACT_TWO_PANE_SCROLLBAR_RESERVE: float = 14.0
const _COMPACT_RIGHT_COLUMN_RATIO: float = 0.38
const _COMPACT_RIGHT_COLUMN_MINIMUM_WIDTH: float = 300.0
const _COMPACT_RIGHT_COLUMN_MAXIMUM_WIDTH: float = 340.0
const _DESKTOP_COLUMN_SEPARATION: float = 34.0
const _DESKTOP_WORK_AREA_MAXIMUM_WIDTH: float = 1240.0
const _DESKTOP_CENTER_MINIMUM_WIDTH: float = 620.0
const _DESKTOP_CENTER_MAXIMUM_WIDTH: float = 760.0
const _DESKTOP_RIGHT_COLUMN_WIDTH: float = 360.0
const _MODE_CARD_SEPARATION: float = 12.0
const _CENTER_SECTION_SEPARATION: float = 14.0
## 当前产品只有六个模式；一页完整呈现，避免为少量条目引入翻页认知成本。
const _MODE_ITEMS_PER_PAGE: int = 6


# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_play_scene_path: String = ""

# --- 私有变量 ---

var _selected_mode_config: GameModeConfig = null
var _mode_config_paths: PackedStringArray = PackedStringArray()
var _current_board_topology: BoardTopology = null
var _current_board_is_custom: bool = false
var _seed_source: StringName = GameSessionMetadata.SEED_SOURCE_RANDOM
var _is_updating_seed_text: bool = false
var _custom_board_option_index: int = -1
var _items_per_page: int = _MODE_ITEMS_PER_PAGE
var _current_page: int = 0
var _total_pages: int = 0
var _mode_catalog: GameModeCatalogUtility = null
var _viewport_utility: GFViewportUtility = null
var _page_scroll: ScrollContainer = null
var _right_panel_stack_margin: MarginContainer = null
var _layout_mode: int = GameTaskPageLayoutUtility.LayoutMode.DESKTOP
var _layout_reference_size: Vector2 = Vector2.ZERO
var _side_by_side_layout_active: bool = true
var _layout_update_queued: bool = false
var _mode_card_slots: Array[ModeCard] = []


# --- @onready 变量 (节点引用) ---

@onready var _left_panel_container: VBoxContainer = %LeftColumn
@onready var _mode_rule_proof: ModeRuleProof = %ModeRuleProof
@onready var _right_panel_container: VBoxContainer = %RightColumn
@onready var _margin_container: MarginContainer = GameTaskPageLayoutUtility.get_margin_container(
	self,
	NodePath("MarginContainer")
)
@onready var _columns_container: HBoxContainer = GameTaskPageLayoutUtility.get_hbox_container(
	self,
	NodePath("MarginContainer/ColumnsContainer")
)
@onready var _center_column: VBoxContainer = %CenterColumn
@onready var _center_content_holder: CenterContainer = %CenterContentHolder
@onready var _center_content_vbox: VBoxContainer = %CenterContentVBox
@onready var _page_title: Label = %PageTitle
@onready var _mode_list_container: GridContainer = %ModeListContainer
@onready var _back_button: Button = %BackButton
@onready var _start_game_button: Button = %StartGameButton
@onready var _grid_size_option_button: OptionButton = %GridSizeOptionButton
@onready var _edit_board_button: Button = %EditBoardButton
@onready var _seed_line_edit: LineEdit = %SeedLineEdit
@onready var _refresh_seed_button: Button = %RefreshSeedButton
@onready var _competition_status_label: Label = %CompetitionStatusLabel
@onready var _advanced_settings_button: Button = %AdvancedSettingsButton
@onready var _advanced_settings_container: VBoxContainer = %AdvancedSettingsContainer
@onready var _prev_page_button: Button = %PrevPageButton
@onready var _next_page_button: Button = %NextPageButton
@onready var _pagination_container: HBoxContainer = _get_parent_hbox(_prev_page_button)

@onready var _config_header_label: Label = _get_child_label(_right_panel_container, "Label")
@onready var _grid_size_label: Label = _get_sibling_label(_grid_size_option_button)
@onready var _seed_label: Label = _get_sibling_label(_seed_line_edit)


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_viewport_utility = _get_viewport_utility()
	_page_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		_columns_container,
		&"ModeSelectionScroll"
	)
	var _resize_connection: int = resized.connect(_queue_layout_update)
	var host_window: Window = get_window()
	if (
		is_instance_valid(host_window)
		and not host_window.size_changed.is_connected(_queue_layout_update)
	):
		var _window_resize_connection: int = host_window.size_changed.connect(
			_queue_layout_update
		)
	_apply_responsive_layout()
	if is_instance_valid(_seed_line_edit):
		_seed_line_edit.placeholder_text = tr("HINT_SEED_PLACEHOLDER")

	_mode_catalog = _get_mode_catalog_utility()
	_load_mode_config_paths()
	_update_pagination_buttons_visibility()
	call_deferred(&"_apply_mode_selection_visual_system")

	var _connect_result_77: int = _back_button.pressed.connect(_on_back_button_pressed)
	var _connect_result_78: int = _grid_size_option_button.item_selected.connect(_on_grid_size_selected)
	var _connect_result_79: int = _start_game_button.pressed.connect(_on_start_game_button_pressed)
	var _connect_result_79b: int = _start_game_button.focus_entered.connect(
		_prime_gameplay_scene
	)
	var _connect_result_79c: int = _start_game_button.mouse_entered.connect(
		_prime_gameplay_scene
	)
	var _connect_result_80: int = _refresh_seed_button.pressed.connect(_on_refresh_seed_button_pressed)
	var _connect_result_80b: int = _seed_line_edit.text_changed.connect(
		_on_seed_text_changed
	)
	var _connect_result_81: int = _prev_page_button.pressed.connect(_on_prev_page_button_pressed)
	var _connect_result_82: int = _next_page_button.pressed.connect(_on_next_page_button_pressed)
	var _connect_result_83: int = _grid_size_option_button.get_popup().id_focused.connect(_on_grid_size_focused)
	var _connect_result_84: int = _edit_board_button.pressed.connect(_on_edit_board_button_pressed)
	var _connect_result_85: int = _advanced_settings_button.toggled.connect(
		_on_advanced_settings_toggled
	)

	_generate_and_display_new_seed()
	_set_advanced_settings_visible(false)
	_update_ui_text()
	_refresh_mode_page_and_focus(true)


func _unhandled_input(event: InputEvent) -> void:
	if _try_handle_top_modal_cancel(event):
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		var viewport: Viewport = get_viewport()
		if is_instance_valid(viewport):
			viewport.set_input_as_handled()

	if event.is_action_pressed("ui_left"):
		var focused_control: Control = get_viewport().gui_get_focus_owner()
		if (
			_layout_mode == GameTaskPageLayoutUtility.LayoutMode.DESKTOP
			and is_instance_valid(focused_control)
			and _right_panel_container.is_ancestor_of(focused_control)
		):
			_focus_last_selected_card()
			get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var focused_control: Control = _get_page_focus_owner()
	_layout_reference_size = _get_layout_reference_size()
	_layout_mode = GameTaskPageLayoutUtility.classify_layout(_layout_reference_size)
	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	_side_by_side_layout_active = _uses_side_by_side_layout(
		_layout_reference_size
	)
	_set_page_scroll_enabled(not _side_by_side_layout_active)
	var compact_horizontal_margins: float = (
		32.0
		if _layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		else 24.0
	)
	var layout_geometry_width: float = minf(
		size.x,
		_layout_reference_size.x
	) if _layout_reference_size.x > 0.0 else size.x
	var compact_content_width: float = clampf(
		layout_geometry_width - compact_horizontal_margins,
		320.0,
		760.0
	)
	_set_right_panel_stacked(not _side_by_side_layout_active)
	var center_content_width: float = compact_content_width
	var right_panel_width: float = 0.0
	var column_separation: int = 0
	if _layout_mode == GameTaskPageLayoutUtility.LayoutMode.DESKTOP:
		column_separation = roundi(_DESKTOP_COLUMN_SEPARATION)
		var desktop_work_area_width: float = minf(
			maxf(layout_geometry_width - _get_desktop_horizontal_safe_margin(), 0.0),
			_DESKTOP_WORK_AREA_MAXIMUM_WIDTH
		)
		right_panel_width = _DESKTOP_RIGHT_COLUMN_WIDTH
		center_content_width = clampf(
			desktop_work_area_width - right_panel_width - float(column_separation),
			_DESKTOP_CENTER_MINIMUM_WIDTH,
			_DESKTOP_CENTER_MAXIMUM_WIDTH
		)
	elif _side_by_side_layout_active:
		var compact_widths: Vector2 = _get_compact_two_pane_widths(
			layout_geometry_width
		)
		center_content_width = compact_widths.x
		right_panel_width = compact_widths.y
		column_separation = roundi(_COMPACT_TWO_PANE_SEPARATION)
	_columns_container.add_theme_constant_override("separation", column_separation)
	_center_column.add_theme_constant_override("separation", 12 if compact else 5)
	_center_content_vbox.add_theme_constant_override(
		"separation",
		12 if compact else roundi(_CENTER_SECTION_SEPARATION)
	)
	_mode_list_container.columns = _get_mode_grid_columns(
		layout_geometry_width,
		_layout_mode
	)
	_mode_list_container.add_theme_constant_override("h_separation", roundi(_MODE_CARD_SEPARATION))
	_mode_list_container.add_theme_constant_override("v_separation", 10 if compact else roundi(_MODE_CARD_SEPARATION))
	_center_content_vbox.custom_minimum_size.x = center_content_width
	_center_content_vbox.size_flags_vertical = (
		Control.SIZE_SHRINK_BEGIN
		if not _side_by_side_layout_active
		else Control.SIZE_FILL
	)
	# 模式索引与右侧开始工单共同组成一条任务带；两栏也必须顶对齐，
	# 不能让 CenterContainer 把短网格垂直居中成标题下方的大空洞。
	_center_content_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_left_panel_container.visible = false
	_left_panel_container.custom_minimum_size.x = 0.0
	_right_panel_container.custom_minimum_size.x = right_panel_width
	_right_panel_container.size_flags_horizontal = (
		Control.SIZE_FILL
		if _side_by_side_layout_active
		else Control.SIZE_EXPAND_FILL
	)
	_right_panel_container.add_theme_constant_override(
		"separation",
		6 if compact else 10
	)
	_apply_responsive_typography()
	var extra_margins: Dictionary = GameTaskPageLayoutUtility.get_safe_area_extra_margins(
		_layout_mode,
		_DESKTOP_SAFE_AREA_MARGINS
	)
	if _layout_mode == GameTaskPageLayoutUtility.LayoutMode.DESKTOP:
		var desktop_horizontal_margin: float = maxf(
			GFVariantData.get_option_float(_DESKTOP_SAFE_AREA_MARGINS, &"left"),
			(layout_geometry_width - _DESKTOP_WORK_AREA_MAXIMUM_WIDTH) * 0.5
		)
		extra_margins[&"left"] = desktop_horizontal_margin
		extra_margins[&"right"] = desktop_horizontal_margin
	if not _side_by_side_layout_active:
		extra_margins = _STACKED_SAFE_AREA_MARGINS.duplicate(true)
	_apply_safe_area_margins(extra_margins)
	_place_back_button_for_layout(not _side_by_side_layout_active)
	if is_instance_valid(_page_scroll) and not compact:
		_page_scroll.scroll_vertical = 0
	_setup_focus_neighbors()
	_restore_focus_after_responsive_layout(focused_control)


func _get_page_focus_owner() -> Control:
	var focused_control: Control = get_viewport().gui_get_focus_owner()
	if (
		is_instance_valid(focused_control)
		and (focused_control == self or is_ancestor_of(focused_control))
	):
		return focused_control
	return null


func _get_layout_reference_size() -> Vector2:
	if not is_instance_valid(_viewport_utility):
		return size
	var display_report: Dictionary = _viewport_utility.get_display_safe_area_margins(
		get_viewport()
	)
	return _resolve_physical_layout_size(size, display_report)


## 从 GF 的物理窗口/安全区报告中解析响应式断点尺寸。
## 视觉几何仍使用逻辑 Control 尺寸；只有断点与首屏预算使用物理可用尺寸。
static func _resolve_physical_layout_size(
	logical_size: Vector2,
	display_report: Dictionary
) -> Vector2:
	var window_value: Variant = GFVariantData.get_option_value(
		display_report,
		&"window_size"
	)
	if not window_value is Vector2i:
		return logical_size
	var window_size: Vector2i = window_value
	if window_size.x <= 0 or window_size.y <= 0:
		return logical_size

	var safe_area_value: Variant = GFVariantData.get_option_value(
		display_report,
		&"safe_area"
	)
	if safe_area_value is Rect2i:
		var safe_area: Rect2i = safe_area_value
		if (
			safe_area.size.x > 0
			and safe_area.size.y > 0
			and safe_area.position.x >= 0
			and safe_area.position.y >= 0
			and safe_area.end.x <= window_size.x
			and safe_area.end.y <= window_size.y
		):
			return Vector2(safe_area.size)
	return Vector2(window_size)


func _restore_focus_after_responsive_layout(focused_control: Control) -> void:
	if (
		is_instance_valid(focused_control)
		and focused_control.focus_mode != Control.FOCUS_NONE
		and focused_control.is_visible_in_tree()
	):
		focused_control.grab_focus()
		return
	if not is_instance_valid(focused_control):
		return
	_focus_last_selected_card()
	if not is_instance_valid(get_viewport().gui_get_focus_owner()):
		_back_button.grab_focus()


## 桌面两栏在首屏完整呈现；只有真正堆叠的窄屏任务流使用页面滚动。
func _set_page_scroll_enabled(enabled: bool) -> void:
	if not is_instance_valid(_page_scroll) or not is_instance_valid(_margin_container):
		return
	if enabled:
		if _columns_container.get_parent() != _page_scroll:
			_columns_container.reparent(_page_scroll)
		_page_scroll.visible = true
		_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_page_scroll.follow_focus = true
		return

	if _columns_container.get_parent() == _page_scroll:
		var scroll_index: int = _page_scroll.get_index()
		_columns_container.reparent(_margin_container)
		_margin_container.move_child(_columns_container, scroll_index)
	_page_scroll.visible = false
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.follow_focus = false


func _set_right_panel_stacked(stacked: bool) -> void:
	if stacked:
		var stack_margin: MarginContainer = _ensure_right_panel_stack_margin()
		stack_margin.visible = true
		if _right_panel_container.get_parent() != stack_margin:
			_reparent_preserving_scene_owner(_right_panel_container, stack_margin)
		_center_column.move_child(
			stack_margin,
			_center_content_holder.get_index() + 1
		)
		return
	if _right_panel_container.get_parent() != _columns_container:
		_reparent_preserving_scene_owner(_right_panel_container, _columns_container)
	if is_instance_valid(_right_panel_stack_margin):
		_right_panel_stack_margin.visible = false
	_columns_container.move_child(
		_right_panel_container,
		_columns_container.get_child_count() - 1
	)


## 堆叠任务流中“返回”属于页级导航，不得夹在“选择→设置→开始”之间。
func _place_back_button_for_layout(stacked: bool) -> void:
	if not is_instance_valid(_back_button) or not is_instance_valid(_center_column):
		return
	var target_parent: Node = _center_column if stacked else _center_content_vbox
	if _back_button.get_parent() != target_parent:
		_reparent_preserving_scene_owner(_back_button, target_parent)
	if stacked:
		_center_column.move_child(_back_button, 1)
	else:
		_center_content_vbox.move_child(
			_back_button,
			_center_content_vbox.get_child_count() - 1
		)

func _ensure_right_panel_stack_margin() -> MarginContainer:
	if is_instance_valid(_right_panel_stack_margin):
		return _right_panel_stack_margin
	var stack_margin: MarginContainer = MarginContainer.new()
	stack_margin.name = &"RightPanelStackMargin"
	stack_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for margin_name: String in _STACKED_SURFACE_OVERFLOW_MARGINS:
		stack_margin.add_theme_constant_override(
			"margin_%s" % margin_name,
			GFVariantData.get_option_int(
				_STACKED_SURFACE_OVERFLOW_MARGINS,
				margin_name
			)
		)
	_center_column.add_child(stack_margin)
	var scene_owner: Node = _center_column.owner
	if is_instance_valid(scene_owner) and scene_owner.is_ancestor_of(stack_margin):
		stack_margin.owner = scene_owner
	_right_panel_stack_margin = stack_margin
	return stack_margin


func _reparent_preserving_scene_owner(control: Control, next_parent: Node) -> void:
	if not is_instance_valid(control) or not is_instance_valid(next_parent):
		return
	var scene_owner: Node = control.owner
	control.owner = null
	control.reparent(next_parent)
	if is_instance_valid(scene_owner) and scene_owner.is_ancestor_of(control):
		control.owner = scene_owner


static func _get_desktop_horizontal_safe_margin() -> float:
	return (
		GFVariantData.get_option_float(_DESKTOP_SAFE_AREA_MARGINS, &"left")
		+ GFVariantData.get_option_float(_DESKTOP_SAFE_AREA_MARGINS, &"right")
	)


static func _uses_side_by_side_layout(viewport_size: Vector2) -> bool:
	var mode: int = GameTaskPageLayoutUtility.classify_layout(viewport_size)
	if mode == GameTaskPageLayoutUtility.LayoutMode.DESKTOP:
		return true
	return (
		mode == GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
		and viewport_size.x >= _COMPACT_TWO_PANE_MINIMUM_WIDTH
	)


static func _get_compact_two_pane_widths(viewport_width: float) -> Vector2:
	var available_width: float = maxf(
		viewport_width
		- _COMPACT_TWO_PANE_HORIZONTAL_MARGIN
		- _COMPACT_TWO_PANE_SEPARATION
		- _COMPACT_TWO_PANE_SCROLLBAR_RESERVE,
		0.0
	)
	var right_width: float = clampf(
		available_width * _COMPACT_RIGHT_COLUMN_RATIO,
		_COMPACT_RIGHT_COLUMN_MINIMUM_WIDTH,
		_COMPACT_RIGHT_COLUMN_MAXIMUM_WIDTH
	)
	return Vector2(maxf(available_width - right_width, 0.0), right_width)


static func _get_mode_grid_columns(viewport_width: float, target_layout_mode: int) -> int:
	if target_layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT:
		return 1
	return 2 if viewport_width >= 600.0 else 1


func _is_compact_two_pane_layout() -> bool:
	return (
		_layout_mode == GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
		and _side_by_side_layout_active
	)


func _apply_responsive_typography() -> void:
	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	var compact_two_pane: bool = _is_compact_two_pane_layout()
	if is_instance_valid(_page_title):
		_page_title.add_theme_font_size_override("font_size", 32 if compact else 40)
	if is_instance_valid(_config_header_label):
		_config_header_label.add_theme_font_size_override(
			"font_size",
			22 if compact_two_pane else 24
		)
	if compact_two_pane:
		for card: ModeCard in _get_mode_cards():
			card.custom_minimum_size.y = 82.0
		_grid_size_option_button.custom_minimum_size.y = 48.0
		_start_game_button.custom_minimum_size.y = 52.0
		_advanced_settings_button.custom_minimum_size.y = 46.0
	else:
		for card: ModeCard in _get_mode_cards():
			card.custom_minimum_size.y = 72.0
		_grid_size_option_button.custom_minimum_size.y = 44.0
		_start_game_button.custom_minimum_size.y = 48.0
		_advanced_settings_button.custom_minimum_size.y = 44.0

func _apply_safe_area_margins(extra_margins: Dictionary) -> void:
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_margin_container,
			get_viewport(),
			extra_margins
		)
		return
	GameTaskPageLayoutUtility.apply_margin_fallback(_margin_container, extra_margins)


func _refresh_mode_page_and_focus(is_initial_load: bool = false) -> void:
	var preferred_config_path: String = (
		_selected_mode_config.resource_path
		if is_instance_valid(_selected_mode_config)
		else ""
	)
	var focused_control: Control = get_viewport().gui_get_focus_owner()
	var restore_card_focus: bool = (
		is_initial_load
		or (
			is_instance_valid(focused_control)
			and _mode_list_container.is_ancestor_of(focused_control)
		)
	)
	_ensure_mode_card_slots(_items_per_page)
	var start_index: int = _current_page * _items_per_page
	for slot_index: int in range(_mode_card_slots.size()):
		var card: ModeCard = _mode_card_slots[slot_index]
		if slot_index >= _items_per_page:
			card.visible = false
			card.set_selected(false)
			continue
		var config_index: int = start_index + slot_index
		if config_index >= _mode_config_paths.size():
			card.visible = false
			card.set_selected(false)
			continue
		var config_path: String = _mode_config_paths[config_index]
		var mode_config: GameModeConfig = _get_mode_config(config_path)
		if config_path.is_empty() or not is_instance_valid(mode_config):
			card.visible = false
			card.set_selected(false)
			continue
		card.visible = true
		card.setup(
			config_path,
			mode_config,
			_get_ui_style_utility(),
			_get_rule_proof_descriptor(mode_config.ruleset_id)
		)
		card.custom_minimum_size.y = 82.0 if _is_compact_two_pane_layout() else 72.0

	_setup_focus_neighbors()

	var cards: Array[ModeCard] = _get_mode_cards()
	if cards.is_empty():
		_selected_mode_config = null
		_show_default_info()
		_start_game_button.disabled = true
		return

	var target_card: ModeCard = cards[0]
	if not preferred_config_path.is_empty():
		for card: ModeCard in cards:
			if card.get_config_path() == preferred_config_path:
				target_card = card
				break
	if (
		is_instance_valid(_selected_mode_config)
		and target_card.get_config_path() == _selected_mode_config.resource_path
	):
		for card: ModeCard in cards:
			card.set_selected(card == target_card)
	else:
		_set_selected_mode_by_path(target_card.get_config_path())
	if restore_card_focus:
		target_card.grab_focus()
	_bind_and_reveal_mode_cards()


func _focus_last_selected_card() -> void:
	if not is_instance_valid(_selected_mode_config):
		return

	for card: ModeCard in _get_mode_cards():
		if card.get_config_path() == _selected_mode_config.resource_path:
			card.grab_focus()
			break


func _load_mode_config_paths() -> void:
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog()
	if not is_instance_valid(mode_catalog):
		push_error("[ModeSelection] GameModeCatalogUtility 未注册，无法加载模式列表。")
		_mode_config_paths = PackedStringArray()
		return

	_mode_config_paths = mode_catalog.get_registered_config_paths()


func _apply_mode_selection_visual_system() -> void:
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style_utility):
		push_error("[ModeSelection] 缺少 GameUiStyleUtility，无法应用模式选择语义样式。")
		return

	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	var compact_two_pane: bool = _is_compact_two_pane_layout()
	style_utility.style_label(
		_page_title,
		GameUiStyleUtility.TextRole.DISPLAY,
		32 if compact else 40,
		false
	)
	style_utility.style_label(
		_config_header_label,
		GameUiStyleUtility.TextRole.PRIMARY,
		20 if compact_two_pane else 24,
		true
	)
	style_utility.style_label(_grid_size_label, GameUiStyleUtility.TextRole.SECONDARY, 16)
	style_utility.style_label(_seed_label, GameUiStyleUtility.TextRole.SECONDARY, 16)
	style_utility.style_label(
		_competition_status_label,
		GameUiStyleUtility.TextRole.MUTED,
		14
	)
	style_utility.style_line_edit(_seed_line_edit)
	style_utility.prepare_button(_grid_size_option_button)
	style_utility.style_button(
		_edit_board_button,
		GameUiStyleUtility.ButtonRole.SECONDARY
	)
	style_utility.style_button(
		_advanced_settings_button,
		GameUiStyleUtility.ButtonRole.QUIET
	)
	style_utility.style_button(
		_prev_page_button,
		GameUiStyleUtility.ButtonRole.SECONDARY
	)
	style_utility.style_button(
		_next_page_button,
		GameUiStyleUtility.ButtonRole.SECONDARY
	)
	style_utility.style_button(
		_back_button,
		GameUiStyleUtility.ButtonRole.QUIET
	)
	style_utility.style_button(
		_start_game_button,
		GameUiStyleUtility.ButtonRole.PRIMARY
	)
	style_utility.style_button(
		_refresh_seed_button,
		GameUiStyleUtility.ButtonRole.ICON
	)
	var _dice_icon_applied: bool = style_utility.set_button_icon_from_asset(
		_refresh_seed_button,
		&"asset.texture.icon.randomize",
		24
	)


func _setup_focus_neighbors() -> void:
	var cards: Array[Control] = []
	for card: ModeCard in _get_mode_cards():
		cards.append(card)
	_apply_mode_focus_graph(cards)


func _apply_mode_focus_graph(cards: Array[Control]) -> void:
	var vertical_order: Array[Control] = [_back_button]
	# 焦点图必须消费本轮物理安全区已经解析出的布局状态，不能再用
	# EXPAND 后的逻辑 Control.size 重算一次断点。
	var stacked: bool = not _side_by_side_layout_active
	for card: Control in cards:
		vertical_order.append(card)
		card.focus_neighbor_right = (
			NodePath("")
			if stacked
			else card.get_path_to(_grid_size_option_button)
		)

	var uses_pagination: bool = is_instance_valid(_pagination_container) and _pagination_container.visible
	if uses_pagination:
		vertical_order.append(_prev_page_button)
		if stacked:
			vertical_order.append(_next_page_button)
	if stacked:
		for detail_control: Control in _get_visible_configuration_controls():
			if not is_instance_valid(detail_control):
				continue
			vertical_order.append(detail_control)
			detail_control.focus_neighbor_left = NodePath("")
	elif not cards.is_empty():
		var first_card: Control = cards[0]
		for detail_control: Control in _get_visible_configuration_controls():
			if not is_instance_valid(detail_control):
				continue
			detail_control.focus_neighbor_left = detail_control.get_path_to(first_card)

	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(vertical_order, {
		"axis": GFControlFocusUtility.AXIS_VERTICAL,
		"wrap": true,
		"wire_tab_order": stacked,
		"preserve_unwired_directional_neighbors": true,
	})
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[ModeSelection] GF 模式焦点顺序应用失败：%s" % str(focus_report.get("issues", [])))
	_wire_mode_grid_directional_focus(cards, stacked)

	if uses_pagination and not cards.is_empty():
		var last_card: Control = cards[-1]
		_next_page_button.focus_neighbor_top = _next_page_button.get_path_to(last_card)
		_next_page_button.focus_neighbor_bottom = _next_page_button.get_path_to(_back_button)
	else:
		_next_page_button.focus_neighbor_top = NodePath("")
		_next_page_button.focus_neighbor_bottom = NodePath("")


## 二维模式索引需要与视觉排布一致；GF 通用线性焦点序列仍负责 Tab/回环，
## 项目适配层只补充同行和同列的方向导航。
func _wire_mode_grid_directional_focus(cards: Array[Control], stacked: bool) -> void:
	if cards.is_empty():
		return
	var column_count: int = maxi(_mode_list_container.columns, 1)
	var stacked_exit_control: Control = _grid_size_option_button
	if (
		stacked
		and is_instance_valid(_pagination_container)
		and _pagination_container.visible
	):
		stacked_exit_control = _prev_page_button
	for index: int in range(cards.size()):
		var card: Control = cards[index]
		var column: int = index % column_count
		var row_start: int = index - column
		var row_end: int = mini(row_start + column_count, cards.size()) - 1
		var up_index: int = index - column_count
		var down_index: int = index + column_count
		card.focus_neighbor_left = (
			card.get_path_to(cards[index - 1])
			if index > row_start
			else NodePath("")
		)
		card.focus_neighbor_right = (
			card.get_path_to(cards[index + 1])
			if index < row_end
			else (
				NodePath("")
				if stacked
				else card.get_path_to(_grid_size_option_button)
			)
		)
		card.focus_neighbor_top = (
			card.get_path_to(cards[up_index])
			if up_index >= 0
			else card.get_path_to(_back_button)
		)
		card.focus_neighbor_bottom = (
			card.get_path_to(cards[down_index])
			if down_index < cards.size()
			else card.get_path_to(
				stacked_exit_control
				if stacked
				else _back_button
			)
		)


func _get_visible_configuration_controls() -> Array[Control]:
	var controls: Array[Control] = [
		_grid_size_option_button,
		_start_game_button,
		_advanced_settings_button,
	]
	if is_instance_valid(_advanced_settings_container) and _advanced_settings_container.visible:
		controls.append(_edit_board_button)
		controls.append(_seed_line_edit)
		controls.append(_refresh_seed_button)
	return controls


func _set_advanced_settings_visible(should_show: bool) -> void:
	if not is_instance_valid(_advanced_settings_container):
		return
	_advanced_settings_container.visible = should_show
	if is_instance_valid(_advanced_settings_button):
		_advanced_settings_button.set_pressed_no_signal(should_show)
	if should_show:
		_update_competition_status()
	if is_instance_valid(_right_panel_container):
		_right_panel_container.queue_sort()


func _set_selected_mode_by_path(config_path: String) -> void:
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	var loaded_config: GameModeConfig = _get_mode_config(config_path)
	if not is_instance_valid(loaded_config):
		_selected_mode_config = null
		_show_default_info()
		return

	_selected_mode_config = loaded_config

	for card: ModeCard in _get_mode_cards():
		card.set_selected(card.get_config_path() == config_path)

	_update_ui_for_selection()


func _update_ui_for_selection(animate_detail: bool = true) -> void:
	if not is_instance_valid(_selected_mode_config):
		_show_default_info()
		return

	if not is_instance_valid(_right_panel_container):
		return

	_right_panel_container.visible = true

	_populate_right_panel()
	_populate_rule_preview()
	if animate_detail:
		_reveal_selection_detail()
	_update_competition_status()


func _show_default_info() -> void:
	if not is_instance_valid(_right_panel_container):
		return
	_right_panel_container.visible = false
	if is_instance_valid(_start_game_button):
		_start_game_button.disabled = true


func _update_ui_text() -> void:
	if is_instance_valid(_page_title):
		_page_title.text = tr("TITLE_MODE_SELECTION")
	if is_instance_valid(_seed_line_edit):
		_seed_line_edit.placeholder_text = tr("HINT_SEED_PLACEHOLDER")
	if is_instance_valid(_prev_page_button):
		_prev_page_button.text = tr("UI_PREV_PAGE")
	if is_instance_valid(_next_page_button):
		_next_page_button.text = tr("UI_NEXT_PAGE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("UI_BACK")
	if is_instance_valid(_start_game_button):
		_start_game_button.text = tr("BTN_START_GAME")
	if is_instance_valid(_edit_board_button):
		_edit_board_button.text = tr("BOARD_EDITOR_OPEN")
	if is_instance_valid(_advanced_settings_button):
		_advanced_settings_button.text = tr("BTN_ADVANCED_SETTINGS")
	if is_instance_valid(_config_header_label):
		_config_header_label.text = tr("LABEL_START_SETUP")
	if is_instance_valid(_grid_size_label):
		_grid_size_label.text = tr("LABEL_GRID_SIZE")
	if is_instance_valid(_seed_label):
		_seed_label.text = tr("LABEL_GAME_SEED")

	if is_instance_valid(_mode_list_container):
		for card: ModeCard in _get_mode_cards():
			card.update_text()

	_update_ui_for_selection(false)


func _populate_rule_preview() -> void:
	if not is_instance_valid(_selected_mode_config):
		return
	if is_instance_valid(_mode_rule_proof):
		var proof_descriptor: ModeRuleProofDescriptor = _get_rule_proof_descriptor(
			_selected_mode_config.ruleset_id
		)
		_mode_rule_proof.present(
			proof_descriptor,
			_selected_mode_config,
			_get_ui_style_utility()
		)
		if not is_instance_valid(proof_descriptor):
			push_error(
				"[ModeSelection] 缺少规则集的导航样张：%s。" %
				String(_selected_mode_config.ruleset_id)
			)


func _populate_right_panel() -> void:
	if not is_instance_valid(_selected_mode_config):
		return
	if not is_instance_valid(_grid_size_option_button) or not is_instance_valid(_start_game_button):
		return
	_current_board_topology = null
	_current_board_is_custom = false
	_custom_board_option_index = -1
	_start_game_button.disabled = true
	_edit_board_button.disabled = true

	var default_size_index: int = -1
	var grid_size_items: Array[Dictionary] = []
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template):
		_write_option_items(_grid_size_option_button, grid_size_items)
		return
	_edit_board_button.disabled = not topology_template.allow_custom_topology

	var square_sizes: Array[int] = topology_template.get_square_size_options()
	if not square_sizes.is_empty():
		for side_length: int in square_sizes:
			var topology: BoardTopology = topology_template.create_topology(
				Vector2i(side_length, side_length)
			)
			if topology == null:
				continue
			var item_index: int = grid_size_items.size()
			grid_size_items.append(_make_option_item(topology.get_size_label(), topology, item_index))
			if side_length == topology_template.get_default_square_size():
				default_size_index = item_index
	else:
		var topology: BoardTopology = topology_template.create_topology()
		if topology != null:
			grid_size_items.append(_make_option_item(topology.get_size_label(), topology, 0))
			default_size_index = 0

	_write_option_items(_grid_size_option_button, grid_size_items)
	if default_size_index < 0:
		return
	_grid_size_option_button.select(default_size_index)
	_on_grid_size_selected(default_size_index)
	_start_game_button.disabled = not is_instance_valid(_current_board_topology)


func _update_pagination_buttons_visibility() -> void:
	if _mode_config_paths.is_empty():
		_total_pages = 0
	else:
		_total_pages = ceili(float(_mode_config_paths.size()) / float(_items_per_page))

	_pagination_container.visible = _total_pages > 1


func _generate_and_display_new_seed() -> void:
	var seed_utility: GFSeedUtility = _get_seed_utility()
	var clock_utility: GameClockUtility = _get_clock_utility()
	if not is_instance_valid(seed_utility) or not is_instance_valid(clock_utility):
		push_error("[ModeSelection] 缺少 GFSeedUtility 或 GameClockUtility，无法生成游戏种子。")
		return

	var seed_value: int = GFSeedUtility.make_stable_seed([
		"mode_selection",
		clock_utility.get_unix_timestamp(),
		clock_utility.get_tick_msec(),
		seed_utility.next_uint32(),
	])
	_is_updating_seed_text = true
	_seed_line_edit.text = str(seed_value)
	_is_updating_seed_text = false
	_seed_source = GameSessionMetadata.SEED_SOURCE_RANDOM
	_update_competition_status()


func _update_grid_size_and_ui(index: int) -> void:
	if index < 0 or index >= _grid_size_option_button.item_count:
		return

	var topology_value: Variant = _grid_size_option_button.get_item_metadata(index)
	if not topology_value is BoardTopology:
		return
	_current_board_topology = topology_value
	_current_board_is_custom = (
		_custom_board_option_index >= 0
		and index == _custom_board_option_index
	)

	if is_instance_valid(_selected_mode_config):
		_update_competition_status()


func _configure_board_editor(panel: Node) -> void:
	if not panel is BoardEditorDialog:
		push_error("[ModeSelection] 棋盘编辑器路由返回了错误面板类型。")
		return
	var editor: BoardEditorDialog = panel
	editor.configure(_selected_mode_config.board_topology_template, _current_board_topology)
	var _connect_result: int = editor.topology_applied.connect(_on_custom_board_topology_applied)


func _on_custom_board_topology_applied(topology: BoardTopology) -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(topology):
		return
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template) or not topology_template.accepts_topology(topology):
		push_error("[ModeSelection] 棋盘编辑器返回了当前模式不接受的拓扑。")
		return

	var topology_copy: BoardTopology = BoardTopology.from_dict(topology.to_dict())
	if topology_copy == null:
		return
	var items: Array[Dictionary] = []
	for index: int in range(_grid_size_option_button.item_count):
		items.append(_make_option_item(
			_grid_size_option_button.get_item_text(index),
			_grid_size_option_button.get_item_metadata(index),
			index
		))
	var custom_index: int = _custom_board_option_index
	if custom_index < 0 or custom_index >= items.size():
		custom_index = items.size()
		items.append({})
	items[custom_index] = _make_option_item(
		tr("BOARD_EDITOR_OPTION_FORMAT") % topology_copy.get_size_label(),
		topology_copy,
		custom_index
	)
	_custom_board_option_index = custom_index
	_write_option_items(_grid_size_option_button, items)
	_grid_size_option_button.select(custom_index)
	_update_grid_size_and_ui(custom_index)
	_start_game_button.disabled = false


func _write_option_items(option: OptionButton, items: Array[Dictionary]) -> void:
	var _written_count: int = GFItemListBinder.write_items(option, items, {
		"text_key": &"text",
		"id_key": &"id",
		"metadata_key": &"metadata",
	})


static func _make_option_item(text: String, metadata: Variant, id: int) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata,
		"id": id,
	}


func _bind_and_reveal_mode_cards() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var _bound_count: int = motion_utility.bind_interactive_controls(_mode_list_container)
	var _reveal_count: int = motion_utility.play_children_reveal(_mode_list_container, _CARD_REVEAL_OFFSET)


func _get_mode_cards() -> Array[ModeCard]:
	var cards: Array[ModeCard] = []
	for card: ModeCard in _mode_card_slots:
		if is_instance_valid(card) and card.visible:
			cards.append(card)
	return cards


func _ensure_mode_card_slots(required_count: int) -> void:
	while _mode_card_slots.size() < required_count:
		var card: ModeCard = _create_mode_card()
		if not is_instance_valid(card):
			return
		_mode_list_container.add_child(card)
		var _focus_connection: int = card.card_focused.connect(
			_set_selected_mode_by_path
		)
		_mode_card_slots.append(card)


func _get_parent_hbox(control: Control) -> HBoxContainer:
	if not is_instance_valid(control):
		return null

	var parent: Node = control.get_parent()
	if parent is HBoxContainer:
		var container: HBoxContainer = parent
		return container
	return null


func _get_sibling_label(control: Control) -> Label:
	if not is_instance_valid(control):
		return null

	var parent: Node = control.get_parent()
	return _get_child_label(parent, "Label")


func _get_child_label(parent: Node, child_path: NodePath) -> Label:
	if not is_instance_valid(parent):
		return null

	var label_node: Node = parent.get_node_or_null(child_path)
	if label_node is Label:
		var label: Label = label_node
		return label
	return null


func _reveal_selection_detail() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	if is_instance_valid(_mode_rule_proof):
		var _proof_tween: Tween = motion_utility.play_content_switch(
			_mode_rule_proof
		)


static func _get_rule_proof_descriptor(
	ruleset_id: StringName
) -> ModeRuleProofDescriptor:
	for descriptor: ModeRuleProofDescriptor in MODE_RULE_PROOF_DESCRIPTORS:
		if is_instance_valid(descriptor) and descriptor.ruleset_id == ruleset_id:
			return descriptor
	return null


func _advance_mode_page(direction: int) -> void:
	if _total_pages <= 1:
		return

	if direction == -1:
		_current_page = (_current_page - 1 + _total_pages) % _total_pages
		_prev_page_button.grab_focus()
	else:
		_current_page = (_current_page + 1) % _total_pages
		_next_page_button.grab_focus()

	_refresh_mode_page_and_focus()


func _create_mode_card() -> ModeCard:
	var card_node: Node = MODE_CARD_SCENE.instantiate()
	if card_node is ModeCard:
		var card: ModeCard = card_node
		return card

	if is_instance_valid(card_node):
		push_error("[ModeSelection] 模式卡片场景必须实例化为 ModeCard。")
		card_node.queue_free()
	return null


func _get_game_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = _get_ui_motion_utility()
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_progress_stats_system() -> ProgressStatsSystem:
	var system_value: Object = get_system(ProgressStatsSystem)
	if system_value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = system_value
		return progress_stats_system
	return null


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _prime_gameplay_scene() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	var _preload_error: Error = _prime_scene_with_router(
		router,
		game_play_scene_path
	)


static func _prime_scene_with_router(
	router: SceneRouterSystem,
	scene_path: String
) -> Error:
	if not is_instance_valid(router):
		return ERR_UNCONFIGURED
	if scene_path.is_empty():
		return ERR_INVALID_PARAMETER
	return router.prime_scene(scene_path)


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_determinism_utility() -> GameDeterminismUtility:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		return utility_value
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_mode_catalog() -> GameModeCatalogUtility:
	if is_instance_valid(_mode_catalog):
		return _mode_catalog

	_mode_catalog = _get_mode_catalog_utility()
	return _mode_catalog


func _get_mode_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog()
	if not is_instance_valid(mode_catalog):
		push_error("[ModeSelection] GameModeCatalogUtility 未注册，无法加载模式配置：%s。" % config_path)
		return null

	return mode_catalog.get_config(config_path)


func _update_competition_status() -> void:
	if not is_instance_valid(_competition_status_label):
		return
	if (
		not is_instance_valid(_advanced_settings_container)
		or not _advanced_settings_container.visible
	):
		_competition_status_label.text = ""
		return
	if (
		not is_instance_valid(_selected_mode_config)
		or not is_instance_valid(_current_board_topology)
	):
		_competition_status_label.text = ""
		return
	var determinism: GameDeterminismUtility = _get_determinism_utility()
	if not is_instance_valid(determinism):
		_competition_status_label.text = ""
		return

	var local_best_text: String = tr("UI_NONE")
	var progress_stats: ProgressStatsSystem = _get_progress_stats_system()
	if is_instance_valid(progress_stats):
		var mode_id: String = _selected_mode_config.resource_path.get_file().get_basename()
		var leaderboard: Array[GameResultRecordedData] = (
			progress_stats.get_local_leaderboard(
				mode_id,
				_current_board_topology.get_stable_key(),
				_selected_mode_config.ruleset_id,
				_selected_mode_config.ruleset_version,
				determinism.calculate_ruleset_fingerprint(_selected_mode_config)
			)
		)
		if not leaderboard.is_empty():
			local_best_text = str(leaderboard[0].score)

	var reason_labels: PackedStringArray = PackedStringArray()
	if _current_board_is_custom:
		var _custom_reason_appended: bool = reason_labels.append(
			tr("ELIGIBILITY_REASON_CUSTOM_BOARD")
		)
	if _seed_source == GameSessionMetadata.SEED_SOURCE_MANUAL:
		var _manual_reason_appended: bool = reason_labels.append(
			tr("ELIGIBILITY_REASON_MANUAL_SEED")
		)
	var eligibility_text: String = GameTextFormatUtility.format_template(
		tr("COMPETITION_STATUS_ELIGIBLE"),
		_COMPETITION_STATUS_ELIGIBLE_FALLBACK,
		[]
	)
	if not reason_labels.is_empty():
		var separator: String = tr("ELIGIBILITY_REASON_SEPARATOR")
		if separator == "ELIGIBILITY_REASON_SEPARATOR":
			separator = "、"
		eligibility_text = GameTextFormatUtility.format_template(
			tr("COMPETITION_STATUS_INELIGIBLE_FORMAT"),
			_COMPETITION_STATUS_INELIGIBLE_FORMAT_FALLBACK,
			[separator.join(reason_labels)]
		)
	_competition_status_label.text = GameTextFormatUtility.format_template(
		tr("COMPETITION_CONFIG_STATUS_FORMAT"),
		_COMPETITION_CONFIG_STATUS_FORMAT_FALLBACK,
		[eligibility_text, local_best_text]
	)


func _parse_seed_text(seed_text: String) -> int:
	if seed_text.is_valid_int():
		return seed_text.to_int()
	return GFSeedUtility.make_stable_text_seed(seed_text)


func _start_selected_game(seed_source: StringName) -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("[ModeSelection] %s" % tr("ERR_NO_MODE_SELECTED"))
		return
	if not is_instance_valid(_current_board_topology):
		push_error("[ModeSelection] 当前模式没有可用的棋盘拓扑。")
		return
	if game_play_scene_path.is_empty():
		push_error("[ModeSelection] game_play_scene_path 未配置。")
		return

	var seed_text: String = _seed_line_edit.text.strip_edges()
	if seed_text.is_empty():
		_generate_and_display_new_seed()
		seed_text = _seed_line_edit.text
		seed_source = GameSessionMetadata.SEED_SOURCE_RANDOM
	var seed_value: int = _parse_seed_text(seed_text)

	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.selected_mode_config_path.set_value(
			_selected_mode_config.resource_path
		)
		var selected_topology: Resource = _current_board_topology.duplicate(true)
		app_config.selected_board_topology.set_value(selected_topology)
		app_config.selected_board_is_custom.set_value(_current_board_is_custom)
		app_config.selected_seed_source.set_value(seed_source)
		app_config.selected_seed.set_value(seed_value)

	var seed_util: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_util):
		seed_util.set_global_seed(seed_value)

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(game_play_scene_path)


# --- 信号处理函数 ---

func _on_back_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()


func _on_grid_size_focused(index: int) -> void:
	_grid_size_option_button.select(index)
	_update_grid_size_and_ui(index)


func _on_grid_size_selected(index: int) -> void:
	_update_grid_size_and_ui(index)


func _on_advanced_settings_toggled(pressed: bool) -> void:
	_set_advanced_settings_visible(pressed)
	_setup_focus_neighbors()


func _on_edit_board_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(_current_board_topology):
		return
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template) or not topology_template.allow_custom_topology:
		return
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[ModeSelection] 缺少 GFUIRouterUtility，无法打开棋盘编辑器。")
		return
	var result: GFUIRouteResult = await ui_router.push_owned_route_async(
		self,
		GameUiRouterUtility.ROUTE_BOARD_EDITOR,
		{},
		{},
		_configure_board_editor,
		GFUIRouterUtility.PRELOAD_REQUIRED
	)
	if result != null and not result.is_successful():
		push_error(
			"[ModeSelection] GF UI 路由未能打开棋盘编辑器：status=%s, reason=%s。" % [
				result.get_status(),
				result.get_reason(),
			]
		)


func _on_prev_page_button_pressed() -> void:
	_advance_mode_page(-1)


func _on_next_page_button_pressed() -> void:
	_advance_mode_page(1)


func _on_start_game_button_pressed() -> void:
	_start_selected_game(_seed_source)


func _on_refresh_seed_button_pressed() -> void:
	_generate_and_display_new_seed()


func _on_seed_text_changed(_new_text: String) -> void:
	if _is_updating_seed_text:
		return
	_seed_source = GameSessionMetadata.SEED_SOURCE_MANUAL
	_update_competition_status()
