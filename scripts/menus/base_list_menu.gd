# scripts/menus/base_list_menu.gd

## BaseListMenu: 列表类菜单的历史基类。
##
## 封装了加载数据列表、实例化列表项、焦点导航、预览更新以及通用按钮处理的核心逻辑。
## 子类需继承此类并实现特定的数据加载和预览格式化方法。
class_name BaseListMenu
extends Control


# --- 私有变量 ---

## 用于实例化列表项的场景资源。由子类在 _ready 中初始化。
var _item_scene: PackedScene

## 当前选中的资源数据（如 BookmarkData 或 ReplayData）。
var _selected_resource: Resource = null

## 主动作按钮（如“加载”或“播放”）。由子类在 _ready 中初始化。
var _primary_button: Button

## 删除动作按钮。由子类在 _ready 中初始化。
var _delete_button: Button


# --- @onready 变量 (节点引用) ---

@onready var ItemsContainer: VBoxContainer = %ReplayItemsContainer
@onready var BoardPreviewNode: BoardPreview = find_child("BoardPreview", true, false)
@onready var DetailInfoLabel: RichTextLabel = find_child("DetailInfoLabel", true, false)
@onready var BackButton: Button = %BackButton
@onready var PageTitle: Label = %PageTitle


# --- Godot 生命周期方法 ---

func _ready() -> void:
	if is_instance_valid(BackButton):
		BackButton.pressed.connect(_on_back_button_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

## 统一连接基础按钮信号。子类在设置完按钮引用后应调用此方法。
func _setup_base_signals() -> void:
	if is_instance_valid(_primary_button):
		_primary_button.pressed.connect(_on_primary_button_pressed)
	if is_instance_valid(_delete_button):
		_delete_button.pressed.connect(_on_delete_button_pressed)


## 重新填充列表内容。
func _populate_list() -> void:
	if not _item_scene:
		push_error("错误: _item_scene 未在子类中初始化。")
		return

	for child in ItemsContainer.get_children():
		child.queue_free()

	# 等待一帧确保 queue_free 完成
	await get_tree().process_frame

	var data_list: Array = _get_data_list()

	if data_list.is_empty():
		_handle_empty_list()
		return

	var items: Array[Control] = []
	for data in data_list:
		var item = _item_scene.instantiate() as Control
		ItemsContainer.add_child(item)
		
		# 调用子类提供的设置逻辑
		_setup_item(item, data)
		items.append(item)
		
		# 统一连接列表项信号 (假设列表项具有这些信号)
		_connect_item_signals(item, data)

	# 设置循环导航
	if items.size() > 1:
		items[0].focus_neighbor_top = items[-1].get_path()
		items[-1].focus_neighbor_bottom = items[0].get_path()

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(data_list[0])


## 处理列表为空的情况。
func _handle_empty_list() -> void:
	var label := Label.new()
	label.text = _get_empty_message()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 50
	ItemsContainer.add_child(label)
	_clear_preview()
	_update_focus_neighbors(null)


## 集中处理选中逻辑。
func _set_selected_item(data: Resource) -> void:
	_selected_resource = data
	_update_preview(data)
	_update_action_buttons()

	var target_node: Control = null
	for child in ItemsContainer.get_children():
		if child.has_method("get_data") and child.get_data() == data:
			child.set_selected(true)
			target_node = child
		elif child.has_method("set_selected"):
			child.set_selected(false)

	_update_focus_neighbors(target_node)


## 动态更新按钮的导航路径，实现焦点记忆。
func _update_focus_neighbors(target_node: Control) -> void:
	var target_path: NodePath = NodePath("")

	if is_instance_valid(target_node):
		target_path = target_node.get_path()
	elif ItemsContainer.get_child_count() > 0:
		var first = ItemsContainer.get_child(0)
		if first is Control: target_path = first.get_path()

	if is_instance_valid(_primary_button):
		_primary_button.focus_neighbor_left = target_path
	if is_instance_valid(_delete_button):
		_delete_button.focus_neighbor_left = target_path
	if is_instance_valid(BackButton):
		BackButton.focus_neighbor_left = target_path


## 更新按钮可用状态。
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_resource != null
	if is_instance_valid(_primary_button):
		_primary_button.disabled = not has_selection
	if is_instance_valid(_delete_button):
		_delete_button.disabled = not has_selection


## 清空预览区域。
func _clear_preview() -> void:
	DetailInfoLabel.text = _get_select_hint_message()
	if is_instance_valid(BoardPreviewNode):
		BoardPreviewNode.clear()
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
	GlobalGameManager.return_to_main_menu()


# --- 虚方法 (需子类覆写) ---

## 返回数据列表。
func _get_data_list() -> Array:
	return []


## 设置列表项显示。
func _setup_item(_item: Control, _data: Resource) -> void:
	pass


## 连接列表项信号。
func _connect_item_signals(_item: Control, _data: Resource) -> void:
	pass


## 更新预览面板详情。
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
