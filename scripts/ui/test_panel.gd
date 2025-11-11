# scripts/ui/test_panel.gd

## TestPanel: 一个动态的、由规则驱动的测试和调试工具面板。
##
## 该脚本负责管理测试面板的UI交互。它不再硬编码任何数值或类型，
## 而是通过外部数据来动态填充选项。它允许开发者在运行时手动生成
## 符合当前游戏模式规则的方块，或调整棋盘大小。
class_name TestPanel
extends VBoxContainer


# --- 信号 ---

## 当用户点击“生成方块”按钮时发出。
## @param grid_pos: 方块在棋盘上的目标网格坐标。
## @param value: 要生成的方块的数值。
## @param type_id: 方块类型的ID，与TypeOptionButton中被选中项的ID对应。
signal spawn_requested(grid_pos: Vector2i, value: int, type_id: int)

## 当用户在类型下拉菜单中选择了新的一项时发出。
## @param type_id: 被选中的类型的ID。
signal values_requested_for_type(type_id: int)

## 当用户请求重置棋盘并使用新尺寸时发出。
## @param new_size: 棋盘的新尺寸。
signal reset_and_resize_requested(new_size: int)

## 当用户请求在游戏过程中扩建棋盘时发出。
## @param new_size: 棋盘扩建后的新尺寸。
signal live_expand_requested(new_size: int)


# --- @onready 变量 (节点引用) ---

@onready var _pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var _pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var _value_option_button: OptionButton = %ValueOptionButton
@onready var _type_option_button: OptionButton = %TypeOptionButton
@onready var _spawn_button: Button = %SpawnButton
@onready var _grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var _reset_resize_button: Button = %ResetResizeButton
@onready var _live_expand_button: Button = %LiveExpandButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	# 连接UI控件的信号到处理函数。
	_spawn_button.pressed.connect(_on_spawn_button_pressed)
	_reset_resize_button.pressed.connect(_on_reset_resize_button_pressed)
	_live_expand_button.pressed.connect(_on_live_expand_button_pressed)
	_type_option_button.item_selected.connect(_on_type_selected)


# --- 公共方法 ---

## 初始化并设置测试面板的所有选项。由 GamePlay 在游戏开始时调用。
##
## @param types: 一个字典 {id: "name", ...} 用于填充类型下拉菜单。
func setup_panel(types: Dictionary) -> void:
	_type_option_button.clear()

	var type_ids: Array = types.keys()
	type_ids.sort()

	for type_id in type_ids:
		_type_option_button.add_item(types[type_id], type_id)

	# 初始时，自动为第一个类型请求数值列表。
	if not type_ids.is_empty():
		_on_type_selected(0)


## 更新“数值”下拉列表的内容。由 GamePlay 在收到新数值时调用。
##
## @param values: 一个包含所有可选数值(int)的数组。
func update_value_options(values: Array[int]) -> void:
	_value_option_button.clear()
	for v in values:
		_value_option_button.add_item(str(v))


## 更新生成方块坐标选择器的上限值。
##
## @param new_grid_size: 当前棋盘的尺寸。
func update_coordinate_limits(new_grid_size: int) -> void:
	var max_coord: int = new_grid_size - 1
	_pos_x_spinbox.max_value = max_coord
	_pos_y_spinbox.max_value = max_coord

	# 同时限制当前值，防止因缩小棋盘导致值超出范围。
	_pos_x_spinbox.value = min(_pos_x_spinbox.value, max_coord)
	_pos_y_spinbox.value = min(_pos_y_spinbox.value, max_coord)


# --- 信号处理函数 ---

## 响应“生成方块”按钮的点击事件。
func _on_spawn_button_pressed() -> void:
	# 检查数值和类型下拉框是否有有效选项
	if _value_option_button.item_count == 0:
		push_warning("TestPanel: 没有可选的生成数值。")
		return
	if _type_option_button.item_count == 0:
		push_warning("TestPanel: 没有可选的生成类型。")
		return

	# 收集用户输入
	var pos := Vector2i(int(_pos_x_spinbox.value), int(_pos_y_spinbox.value))
	var value_text: String = _value_option_button.get_item_text(_value_option_button.selected)
	var value := int(value_text)
	var type_id: int = _type_option_button.get_item_id(_type_option_button.selected)

	# 发出信号
	spawn_requested.emit(pos, value, type_id)


## 响应“重置并调整大小”按钮的点击事件。
func _on_reset_resize_button_pressed() -> void:
	var new_size := int(_grid_size_spinbox.value)
	reset_and_resize_requested.emit(new_size)


## 响应“游戏中扩建棋盘”按钮的点击事件。
func _on_live_expand_button_pressed() -> void:
	var new_size := int(_grid_size_spinbox.value)
	live_expand_requested.emit(new_size)


## 当类型下拉菜单中的选项被改变时调用。
## @param index: 被选中项的索引。
func _on_type_selected(index: int) -> void:
	if index < 0 or index >= _type_option_button.item_count:
		return

	var type_id: int = _type_option_button.get_item_id(index)
	values_requested_for_type.emit(type_id)
