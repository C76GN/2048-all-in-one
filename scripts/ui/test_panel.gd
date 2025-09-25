# scripts/ui/test_panel.gd

## TestPanel: 一个动态的、由规则驱动的测试和调试工具面板。
##
## 该脚本负责管理测试面板的UI交互。它不再硬编码任何数值或类型，
## 而是通过外部数据来动态填充选项。它允许开发者在运行时手动生成
## 符合当前游戏模式规则的方块，或调整棋盘大小。
extends VBoxContainer

# --- 信号定义 ---

## 当用户点击“生成方块”按钮时发出。
## 它会携带生成方块所需的所有信息，供监听者（GamePlay）使用。
## type_id 是 TypeOptionButton 中被选中项的ID。
signal spawn_requested(grid_pos: Vector2i, value: int, type_id: int)

## 当用户在类型下拉菜单中选择了新的一项时发出。
## GamePlay 会监听此信号，并为 TestPanel 提供新的数值列表。
signal values_requested_for_type(type_id: int)
## 当用户请求重置棋盘并使用新尺寸时发出。
signal reset_and_resize_requested(new_size: int)
## 当用户请求在游戏过程中扩建棋盘时发出。
signal live_expand_requested(new_size: int)

# --- 节点引用 ---

## 对测试面板中各个UI控件的引用（使用唯一名称%）。
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var value_option_button: OptionButton = %ValueOptionButton
@onready var type_option_button: OptionButton = %TypeOptionButton
@onready var spawn_button: Button = %SpawnButton
@onready var grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var reset_resize_button: Button = %ResetResizeButton
@onready var live_expand_button: Button = %LiveExpandButton


## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 连接“生成方块”按钮的 `pressed` 信号到处理函数。
	spawn_button.pressed.connect(_on_spawn_button_pressed)
	# 连接棋盘大小调整相关按钮的信号
	reset_resize_button.pressed.connect(_on_reset_resize_button_pressed)
	live_expand_button.pressed.connect(_on_live_expand_button_pressed)
	# 连接类型下拉菜单的 item_selected 信号，实现数值列表的联动更新。
	type_option_button.item_selected.connect(_on_type_selected)

# --- 公共接口 ---

## 初始化并设置测试面板的所有选项。由 GamePlay 在游戏开始时调用。
## @param types: 一个字典 {id: "name", ...} 用于填充类型下拉菜单。
func setup_panel(types: Dictionary) -> void:
	type_option_button.clear()
	
	var type_ids = types.keys()
	type_ids.sort()
	
	for type_id in type_ids:
		type_option_button.add_item(types[type_id], type_id)
	
	# 初始时，自动为第一个类型请求数值
	if not type_ids.is_empty():
		_on_type_selected(0)

## 更新“数值”下拉列表的内容。由 GamePlay 在收到新数值时调用。
## @param values: 一个包含所有可选数值(int)的数组。
func update_value_options(values: Array[int]) -> void:
	value_option_button.clear()
	for v in values:
		value_option_button.add_item(str(v))

## 更新生成方块坐标选择器的上限值。
func update_coordinate_limits(new_grid_size: int) -> void:
	var max_coord = new_grid_size - 1
	pos_x_spinbox.max_value = max_coord
	pos_y_spinbox.max_value = max_coord
	
	# 同时限制当前值，防止因缩小棋盘导致值超出范围
	pos_x_spinbox.value = min(pos_x_spinbox.value, max_coord)
	pos_y_spinbox.value = min(pos_y_spinbox.value, max_coord)

# --- 信号处理函数 ---

## 响应“生成方块”按钮的点击事件。
func _on_spawn_button_pressed() -> void:
	# 步骤1: 收集用户输入。
	var pos = Vector2i(int(pos_x_spinbox.value), int(pos_y_spinbox.value))
	
	# 检查数值下拉框是否有选项
	if value_option_button.item_count == 0:
		push_warning("TestPanel: 没有可选的生成数值。")
		return
	
	var value_text = value_option_button.get_item_text(value_option_button.selected)
	var value = int(value_text)
	
	# 检查类型下拉框是否有选项
	if type_option_button.item_count == 0:
		push_warning("TestPanel: 没有可选的生成类型。")
		return
	
	var type_id = type_option_button.get_item_id(type_option_button.selected)
	
	# 步骤2: 发出 `spawn_requested` 信号。
	spawn_requested.emit(pos, value, type_id)

## 响应“重置并调整大小”按钮的点击事件。
func _on_reset_resize_button_pressed() -> void:
	var new_size = int(grid_size_spinbox.value)
	reset_and_resize_requested.emit(new_size)

## 响应“游戏中扩建棋盘”按钮的点击事件。
func _on_live_expand_button_pressed() -> void:
	var new_size = int(grid_size_spinbox.value)
	live_expand_requested.emit(new_size)

## 当类型下拉菜单中的选项被改变时调用。
func _on_type_selected(index: int) -> void:
	if index < 0 or index >= type_option_button.item_count:
		return
	var type_id = type_option_button.get_item_id(index)
	values_requested_for_type.emit(type_id)
