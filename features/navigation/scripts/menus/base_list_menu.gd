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


# --- @onready 变量 (节点引用) ---

@onready var items_container: VBoxContainer = %ReplayItemsContainer
@onready var board_preview_node: BoardPreview = _find_board_preview_node()
@onready var detail_info_label: RichTextLabel = _find_detail_info_label()
@onready var back_button: Button = %BackButton
@onready var page_title: Label = %PageTitle


# --- Godot 生命周期方法 ---

func _ready() -> void:
	if is_instance_valid(back_button):
		var _connect_result_43: int = back_button.pressed.connect(_on_back_button_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


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


## 执行具体的删除逻辑。
func _do_delete_logic(_data: Resource) -> void:
	pass


## 执行主按钮逻辑。
func _on_primary_action_triggered(_data: Resource) -> void:
	pass


## 获取列表为空时的提示。
func _get_empty_message() -> String:
	return tr("MSG_NO_DATA")


## 获取未选中时的提示。
func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_ITEM")


# --- 私有/辅助方法 ---

## 统一连接基础按钮信号。子类在设置完按钮引用后应调用此方法。
func _setup_base_signals() -> void:
	if is_instance_valid(_primary_button):
		var _connect_result_109: int = _primary_button.pressed.connect(_on_primary_button_pressed)
	if is_instance_valid(_delete_button):
		var _connect_result_111: int = _delete_button.pressed.connect(_on_delete_button_pressed)


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

	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(items, {
		"axis": GFControlFocusUtility.AXIS_VERTICAL,
		"wrap": true,
		"wire_tab_order": true,
		"preserve_unwired_directional_neighbors": true,
	})
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[BaseListMenu] GF 列表焦点顺序应用失败：%s" % str(focus_report.get("issues", [])))

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(data_list[0])
		_bind_and_reveal_list_items()
	else:
		_handle_empty_list()


## 处理列表为空的情况。
func _handle_empty_list() -> void:
	var label: Label = Label.new()
	label.text = _get_empty_message()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 180
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if is_instance_valid(style_utility):
		style_utility.style_label(label, GameUiStyleUtility.TextRole.MUTED, 18)
	items_container.add_child(label)
	_clear_preview()
	_update_action_focus_return_target(null)
	_bind_and_reveal_list_items()


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
func _clear_preview() -> void:
	detail_info_label.text = _get_select_hint_message()
	if is_instance_valid(board_preview_node):
		board_preview_node.clear()
	_selected_resource = null
	_update_action_buttons()


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
	if _selected_resource:
		_do_delete_logic(_selected_resource)
		_selected_resource = null
		await _populate_list()


func _on_back_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()
