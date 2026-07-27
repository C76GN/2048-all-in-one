## BaseListMenu: 列表类菜单的通用基类。
##
## 封装了加载数据列表、实例化列表项、焦点导航、预览更新以及通用按钮处理的核心逻辑。
## 子类需继承此类并实现特定的数据加载和预览格式化方法。
class_name BaseListMenu
extends GameUiController


# --- 常量 ---

const _LIST_REVEAL_OFFSET: Vector2 = Vector2(16.0, 0.0)
const _LIST_REVEAL_STAGGER: float = 0.03
const _LIST_REPEATER_GROUP: StringName = &"base_list_menu_items"
const _LIST_ITEM_DUPLICATE_FLAGS: int = (
	Node.DUPLICATE_GROUPS
	| Node.DUPLICATE_SCRIPTS
	| Node.DUPLICATE_USE_INSTANTIATION
)
const _DESKTOP_SAFE_AREA_MARGINS: Dictionary = {
	"top": 54.0,
	"left": 56.0,
	"bottom": 54.0,
	"right": 56.0,
}
const _DESKTOP_LIST_SURFACE_MINIMUM: Vector2 = Vector2(580.0, 540.0)
const _COMPACT_LIST_SURFACE_HEIGHT: float = 300.0
const _PORTRAIT_LIST_SURFACE_HEIGHT: float = 440.0
const _DESKTOP_PREVIEW_HEIGHT: float = 248.0
const _COMPACT_PREVIEW_HEIGHT: float = 210.0
const _COMPACT_HORIZONTAL_MARGINS: float = 24.0
const _PORTRAIT_HORIZONTAL_MARGINS: float = 32.0
const _COMPACT_SCROLLBAR_RESERVE: float = 14.0


# --- 私有变量 ---

## 用于实例化列表项的场景资源。由子类在 _ready 中初始化。
var _item_scene: PackedScene

## 当前选中的资源数据（如 BookmarkData 或 ReplayData）。
var _selected_resource: Resource = null

## 主动作按钮（如“加载”或“播放”）。由子类在 _ready 中初始化。
var _primary_button: Button

## 删除动作按钮。由子类在 _ready 中初始化。
var _delete_button: Button

## GFRepeaterBinder 使用的离树模板节点。
var _repeater_template: Control = null
var _viewport_utility: GFViewportUtility = null
var _page_scroll: ScrollContainer = null
var _list_scroll: ScrollContainer = null
var _layout_mode: int = GameTaskPageLayoutUtility.LayoutMode.DESKTOP
var _layout_update_queued: bool = false
var _delete_confirmation_dialog: ConfirmationDialog = null
var _delete_error_dialog: AcceptDialog = null
var _pending_delete_resource: Resource = null


# --- @onready 变量 (节点引用) ---

@onready var items_container: VBoxContainer = %ItemsContainer
@onready var board_preview_node: BoardPreview = _find_board_preview_node()
@onready var detail_info_label: RichTextLabel = _find_detail_info_label()
@onready var back_button: Button = %BackButton
@onready var page_title: Label = %PageTitle
@onready var _margin_container: MarginContainer = GameTaskPageLayoutUtility.get_margin_container(
	self,
	NodePath("MarginContainer")
)
@onready var _columns_container: HBoxContainer = GameTaskPageLayoutUtility.get_hbox_container(
	self,
	NodePath("MarginContainer/ColumnsContainer")
)
@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _center_column: VBoxContainer = %CenterColumn
@onready var _center_content_holder: CenterContainer = %CenterContentHolder
@onready var _list_surface: PanelContainer = _find_panel_container("ListSurface")
@onready var _preview_container: PanelContainer = _find_panel_container("PreviewContainer")


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_viewport_utility = _get_viewport_utility()
	_setup_delete_dialogs()
	_page_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		_columns_container,
		&"HistoryListPageScroll"
	)
	_list_scroll = _find_scroll_container("ScrollContainer")
	_apply_responsive_layout()
	if is_instance_valid(back_button):
		var _connect_result_43: int = back_button.pressed.connect(_on_back_button_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_delete_dialog_text()
		_update_ui_text()
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		_queue_layout_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 公共方法 ---

## 返回历史任务页是否应采用紧凑单列布局。
## @param viewport_size: 当前逻辑视口尺寸。
static func is_compact_layout(viewport_size: Vector2) -> bool:
	return GameTaskPageLayoutUtility.is_compact_layout(viewport_size)


## 返回紧凑布局中列表面板应占用的稳定宽度。
##
## 页面级滚动条由当前页拥有，因此宽度预算需要同时扣除安全区留白和滚动条，
## 避免 CenterContainer 在重排瞬间把列表压缩成仅剩文字最小宽度。
static func get_compact_list_surface_width(
	viewport_width: float,
	target_layout_mode: int
) -> float:
	var horizontal_margins: float = (
		_PORTRAIT_HORIZONTAL_MARGINS
		if target_layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		else _COMPACT_HORIZONTAL_MARGINS
	)
	return maxf(
		viewport_width - horizontal_margins - _COMPACT_SCROLLBAR_RESERVE,
		320.0
	)


# --- 虚方法 (需子类覆写) ---

## 获取数据列表。
func _get_data_list() -> Array:
	return []


## 设置列表项显示。
func _setup_item(_item: Control, _data: Resource) -> void:
	pass


## 连接列表项的统一交互信号。
func _connect_item_signals(item: Control, _data: Resource) -> void:
	if not item is BaseListMenuItem:
		push_error("[BaseListMenu] 列表项必须继承 BaseListMenuItem。")
		return

	var list_item: BaseListMenuItem = item
	if not list_item.item_selected.is_connected(_on_item_confirmed):
		var _selected_connect_result: int = list_item.item_selected.connect(_on_item_confirmed)
	if not list_item.item_focused.is_connected(_on_item_focused):
		var _focused_connect_result: int = list_item.item_focused.connect(_on_item_focused)


## 更新预览。
func _update_preview(_data: Resource) -> void:
	pass


## 更新静态 UI 文本。
func _update_ui_text() -> void:
	pass


## 执行具体的删除逻辑并返回持久化结果。
func _do_delete_logic(_data: Resource) -> Error:
	return ERR_UNAVAILABLE


## 执行主按钮逻辑。
func _on_primary_action_triggered(_data: Resource) -> void:
	pass


## 获取列表为空时的提示。
func _get_empty_message() -> String:
	return tr("MSG_NO_DATA")


## 获取未选中时的提示。
func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_ITEM")


## 获取列表为空时显示在预览说明区的引导。
func _get_empty_detail_message() -> String:
	return _get_empty_message()


## 允许具体列表切换仅在有数据时才有意义的视觉元素。
func _on_empty_state_changed(_is_empty: bool) -> void:
	pass


## 获取删除确认提示。
func _get_delete_confirmation_message(_data: Resource) -> String:
	return tr("DELETE_ITEM_CONFIRMATION")


## 获取删除失败提示。
func _get_delete_failure_message(error: Error) -> String:
	return tr("DELETE_ITEM_FAILED") % int(error)


# --- 私有/辅助方法 ---

## 统一连接基础按钮信号。子类在设置完按钮引用后应调用此方法。
func _setup_base_signals() -> void:
	if is_instance_valid(_primary_button):
		var _connect_result_109: int = _primary_button.pressed.connect(_on_primary_button_pressed)
	if is_instance_valid(_delete_button):
		var _connect_result_111: int = _delete_button.pressed.connect(_on_delete_button_pressed)


func _setup_delete_dialogs() -> void:
	_delete_confirmation_dialog = ConfirmationDialog.new()
	_delete_confirmation_dialog.name = "DeleteConfirmationDialog"
	_delete_confirmation_dialog.exclusive = true
	add_child(_delete_confirmation_dialog)
	var _confirmed_connection: int = _delete_confirmation_dialog.confirmed.connect(
		_on_delete_confirmed
	)
	var _canceled_connection: int = _delete_confirmation_dialog.canceled.connect(
		_on_delete_canceled
	)

	_delete_error_dialog = AcceptDialog.new()
	_delete_error_dialog.name = "DeleteErrorDialog"
	_delete_error_dialog.exclusive = true
	add_child(_delete_error_dialog)
	_update_delete_dialog_text()


func _update_delete_dialog_text() -> void:
	if is_instance_valid(_delete_confirmation_dialog):
		_delete_confirmation_dialog.title = tr("DELETE_CONFIRM_TITLE")
		_delete_confirmation_dialog.ok_button_text = tr("DELETE_CONFIRM_ACTION")
		_delete_confirmation_dialog.cancel_button_text = tr("DELETE_CANCEL_ACTION")
		if is_instance_valid(_pending_delete_resource):
			_delete_confirmation_dialog.dialog_text = (
				_get_delete_confirmation_message(_pending_delete_resource)
			)
	if is_instance_valid(_delete_error_dialog):
		_delete_error_dialog.title = tr("DELETE_FAILED_TITLE")


func _find_board_preview_node() -> BoardPreview:
	var node_value: Node = find_child("BoardPreview", true, false)
	if node_value is BoardPreview:
		var board_preview: BoardPreview = node_value
		return board_preview
	return null


func _find_detail_info_label() -> RichTextLabel:
	var node_value: Node = find_child("DetailInfoLabel", true, false)
	if node_value is RichTextLabel:
		var detail_label: RichTextLabel = node_value
		return detail_label
	return null


func _find_panel_container(node_name: String) -> PanelContainer:
	var node_value: Node = find_child(node_name, true, false)
	if node_value is PanelContainer:
		var panel_container: PanelContainer = node_value
		return panel_container
	return null


func _find_scroll_container(node_name: String) -> ScrollContainer:
	var node_value: Node = find_child(node_name, true, false)
	if node_value is ScrollContainer:
		var scroll_container: ScrollContainer = node_value
		return scroll_container
	return null


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	_layout_mode = GameTaskPageLayoutUtility.classify_layout(size)
	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	_set_page_scroll_enabled(compact)
	if is_instance_valid(_list_scroll):
		_list_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_DISABLED
			if compact
			else ScrollContainer.SCROLL_MODE_AUTO
		)
		_list_scroll.follow_focus = not compact
	_set_preview_column_compact(compact)
	_columns_container.add_theme_constant_override("separation", 0 if compact else 34)
	_center_column.add_theme_constant_override("separation", 12 if compact else 5)
	_left_column.custom_minimum_size.x = 0.0 if compact else 380.0
	_left_column.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	)
	_center_content_holder.size_flags_vertical = (
		Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	)
	if is_instance_valid(_list_surface):
		var list_height: float = (
			_PORTRAIT_LIST_SURFACE_HEIGHT
			if _layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
			else _COMPACT_LIST_SURFACE_HEIGHT
		)
		var compact_list_width: float = get_compact_list_surface_width(
			size.x,
			_layout_mode
		)
		_list_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_surface.custom_minimum_size = (
			Vector2(compact_list_width, list_height)
			if compact
			else _DESKTOP_LIST_SURFACE_MINIMUM
		)
	if is_instance_valid(_preview_container):
		_preview_container.custom_minimum_size.y = (
			_COMPACT_PREVIEW_HEIGHT if compact else _DESKTOP_PREVIEW_HEIGHT
		)
	if is_instance_valid(board_preview_node):
		board_preview_node.preview_size = 194.0 if compact else 232.0
	if is_instance_valid(detail_info_label):
		detail_info_label.custom_minimum_size.y = 90.0 if compact else 106.0
	if is_instance_valid(page_title):
		page_title.add_theme_font_size_override("font_size", 32 if compact else 40)
	var extra_margins: Dictionary = GameTaskPageLayoutUtility.get_safe_area_extra_margins(
		_layout_mode,
		_DESKTOP_SAFE_AREA_MARGINS
	)
	_apply_safe_area_margins(extra_margins)
	if is_instance_valid(_page_scroll) and not compact:
		_page_scroll.scroll_vertical = 0
	_apply_list_focus_order(_get_list_item_controls())


## 桌面双栏由内部记录列表独占滚动；紧凑单栏则由整页滚动独占。
## 这样同一轴线上不会同时出现页面和列表两根滚动条。
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


func _set_preview_column_compact(compact: bool) -> void:
	if compact:
		if _left_column.get_parent() != _center_column:
			_left_column.reparent(_center_column)
		_center_column.move_child(
			_left_column,
			_center_content_holder.get_index() + 1
		)
		return
	if _left_column.get_parent() != _columns_container:
		_left_column.reparent(_columns_container)
	_columns_container.move_child(_left_column, 0)


func _apply_safe_area_margins(extra_margins: Dictionary) -> void:
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_margin_container,
			get_viewport(),
			extra_margins
		)
		return
	GameTaskPageLayoutUtility.apply_margin_fallback(_margin_container, extra_margins)


func _get_list_item_controls() -> Array[Control]:
	var items: Array[Control] = []
	if not is_instance_valid(items_container):
		return items
	for child: Node in items_container.get_children():
		if child is BaseListMenuItem:
			var item_control: Control = child
			items.append(item_control)
	return items


func _apply_list_focus_order(items: Array[Control]) -> void:
	if items.is_empty():
		return
	var focus_order: Array[Control] = items.duplicate()
	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	if compact:
		for action_control: Control in [_primary_button, _delete_button, back_button]:
			if is_instance_valid(action_control):
				focus_order.append(action_control)
	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(focus_order, {
		"axis": GFControlFocusUtility.AXIS_VERTICAL,
		"wrap": true,
		"wire_tab_order": true,
		"preserve_unwired_directional_neighbors": true,
	})
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[BaseListMenu] GF 列表焦点顺序应用失败：%s" % str(focus_report.get("issues", [])))


## 重新填充列表内容。
func _populate_list() -> void:
	if not _item_scene:
		push_error("[BaseListMenu] _item_scene 未在子类中初始化。")
		return

	await _clear_list_content()

	var raw_data_list: Array = _get_data_list()
	var data_list: Array[Resource] = []
	for data_value: Variant in raw_data_list:
		if data_value is Resource:
			data_list.append(data_value)

	if data_list.is_empty():
		_handle_empty_list()
		return
	_on_empty_state_changed(false)

	var template: Control = _get_repeater_template()
	if not is_instance_valid(template):
		_handle_empty_list()
		return

	var created_nodes: Array[Node] = GFRepeaterBinder.rebuild_container(items_container, template, data_list, {
		"group_key": _LIST_REPEATER_GROUP,
		"hide_template": false,
		"clear_existing": true,
		"duplicate_flags": _LIST_ITEM_DUPLICATE_FLAGS,
		"configure_callable": Callable(self, "_configure_repeated_list_item"),
	})

	var items: Array[Control] = []
	for node: Node in created_nodes:
		if node is Control:
			var item_control: Control = node
			items.append(item_control)

	_apply_list_focus_order(items)

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(data_list[0])
		_bind_and_reveal_list_items()
	else:
		_handle_empty_list()


## 处理列表为空的情况。
func _handle_empty_list() -> void:
	var label: Label = Label.new()
	label.name = "EmptyStateLabel"
	label.text = _get_empty_message()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 180
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if is_instance_valid(style_utility):
		style_utility.style_label(label, GameUiStyleUtility.TextRole.MUTED, 18)
	items_container.add_child(label)
	_clear_preview(false)
	_on_empty_state_changed(true)
	_update_action_focus_return_target(null)
	_bind_and_reveal_list_items()
	if is_instance_valid(back_button):
		back_button.grab_focus()


func _clear_list_content() -> void:
	var _cleared_clones: int = GFRepeaterBinder.clear_clones(items_container, {
		"group_key": _LIST_REPEATER_GROUP,
	})

	for child: Node in items_container.get_children():
		child.queue_free()

	await get_tree().process_frame


func _configure_repeated_list_item(node: Node, item: Variant, _index: int) -> void:
	if not node is Control or not item is Resource:
		return

	var item_control: Control = node
	var data: Resource = item
	_setup_item(item_control, data)
	_connect_item_signals(item_control, data)


## 集中处理选中逻辑。
func _set_selected_item(data: Resource) -> void:
	_selected_resource = data
	_update_preview(data)
	_update_action_buttons()

	var target_node: Control = null
	for child: Node in items_container.get_children():
		if not child is BaseListMenuItem:
			continue
		var list_item: BaseListMenuItem = child
		if list_item.get_data() == data:
			list_item.set_selected(true)
			target_node = list_item
		else:
			list_item.set_selected(false)

	_update_action_focus_return_target(target_node)


## 让右侧动作完成后返回当前选中项；纵向列表顺序由 GFControlFocusUtility 拥有。
func _update_action_focus_return_target(target_node: Control) -> void:
	var target: Control = target_node
	if not is_instance_valid(target) and items_container.get_child_count() > 0:
		var first: Node = items_container.get_child(0)
		if first is Control:
			var first_control: Control = first
			target = first_control

	_set_left_focus_target(_primary_button, target)
	_set_left_focus_target(_delete_button, target)
	_set_left_focus_target(back_button, target)


func _set_left_focus_target(source: Control, target: Control) -> void:
	if not is_instance_valid(source):
		return
	if not is_instance_valid(target):
		source.focus_neighbor_left = NodePath("")
		return
	source.focus_neighbor_left = source.get_path_to(target)


## 更新按钮可用状态。
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_resource != null
	if is_instance_valid(_primary_button):
		_primary_button.disabled = not has_selection
	if is_instance_valid(_delete_button):
		_delete_button.disabled = not has_selection


func _bind_and_reveal_list_items() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var _bound_count: int = motion_utility.bind_interactive_controls(items_container)
	var _reveal_count: int = motion_utility.play_children_reveal(items_container, _LIST_REVEAL_OFFSET, _LIST_REVEAL_STAGGER)


func _get_game_ui_motion_utility() -> GameUiMotionUtility:
	var motion_value: Object = _get_ui_motion_utility()
	if motion_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = motion_value
		return motion_utility
	return null


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _format_datetime(timestamp: int) -> String:
	var clock: GameClockUtility = _get_clock_utility()
	if is_instance_valid(clock):
		return clock.format_datetime(timestamp)
	return GameClockUtility.format_datetime_value(timestamp)


func _get_mode_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog_utility()
	if not is_instance_valid(mode_catalog):
		push_error("[BaseListMenu] GameModeCatalogUtility 未注册，无法加载模式配置：%s。" % config_path)
		return null

	return mode_catalog.get_config(config_path)


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _get_repeater_template() -> Control:
	if is_instance_valid(_repeater_template):
		return _repeater_template

	var item_node: Node = _item_scene.instantiate()
	if item_node is Control:
		var item_control: Control = item_node
		_repeater_template = item_control
		return _repeater_template

	if is_instance_valid(item_node):
		push_error("[BaseListMenu] 列表项场景必须实例化为 Control。")
		item_node.free()
	return null


## 清空预览区域。
## @param show_selection_hint: true 显示“请选择”提示；空列表时改用空态引导。
func _clear_preview(show_selection_hint: bool = true) -> void:
	detail_info_label.text = (
		_get_select_hint_message()
		if show_selection_hint
		else _get_empty_detail_message()
	)
	if is_instance_valid(board_preview_node):
		board_preview_node.clear()
	_selected_resource = null
	_update_action_buttons()


func _show_delete_error(error: Error) -> void:
	if not is_instance_valid(_delete_error_dialog):
		return
	_delete_error_dialog.dialog_text = _get_delete_failure_message(error)
	_delete_error_dialog.popup_centered_clamped(Vector2i(520, 220), 0.9)


# --- 信号处理函数 ---

func _on_item_focused(data: Resource) -> void:
	if _selected_resource != data:
		_set_selected_item(data)


func _on_item_confirmed(data: Resource) -> void:
	_set_selected_item(data)


func _on_primary_button_pressed() -> void:
	if _selected_resource:
		_on_primary_action_triggered(_selected_resource)


func _on_delete_button_pressed() -> void:
	if not is_instance_valid(_selected_resource):
		return
	if not is_instance_valid(_delete_confirmation_dialog):
		return
	_pending_delete_resource = _selected_resource
	_delete_confirmation_dialog.dialog_text = _get_delete_confirmation_message(
		_pending_delete_resource
	)
	_delete_confirmation_dialog.popup_centered_clamped(Vector2i(520, 220), 0.9)


func _on_delete_confirmed() -> void:
	var resource_to_delete: Resource = _pending_delete_resource
	_pending_delete_resource = null
	if not is_instance_valid(resource_to_delete):
		return
	var delete_error: Error = _do_delete_logic(resource_to_delete)
	if delete_error != OK:
		push_error("[BaseListMenu] 删除操作失败，错误码：%d。" % int(delete_error))
		_show_delete_error(delete_error)
		return
	_selected_resource = null
	await _populate_list()


func _on_delete_canceled() -> void:
	_pending_delete_resource = null


func _on_back_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()
