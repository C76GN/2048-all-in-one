# scripts/ui/test_panel.gd

## TestPanel: 一个仅在编辑器中使用的测试和调试工具面板。
##
## 该脚本负责管理测试面板的UI交互。它允许开发者在运行时手动指定
## 方块的坐标、数值和类型，然后通过发出一个信号来请求在棋盘上生成该方块。
## 游戏控制器 (TestMode1) 会监听此信号并执行相应的操作。
extends VBoxContainer

# --- 信号定义 ---

## 当用户点击“生成方块”按钮时发出。
## 它会携带生成方块所需的所有信息，供监听者使用。
signal spawn_requested(grid_pos: Vector2i, value: int, type_index: int)

# --- 节点引用 ---

## 对测试面板中各个UI控件的引用（使用唯一名称%）。
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var value_option_button: OptionButton = %ValueOptionButton
@onready var type_option_button: OptionButton = %TypeOptionButton
@onready var spawn_button: Button = %SpawnButton


## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 连接“生成方块”按钮的 `pressed` 信号到处理函数。
	spawn_button.pressed.connect(_on_spawn_button_pressed)
	# 动态地用2的幂次方数值填充“数值”下拉列表。
	_populate_value_options()

# --- 内部辅助函数 ---

## 动态填充“数值”下拉列表的选项。
func _populate_value_options() -> void:
	var current_power_of_two = 2
	while current_power_of_two <= 65536:
		value_option_button.add_item(str(current_power_of_two))
		current_power_of_two *= 2

# --- 信号处理函数 ---

## 响应“生成方块”按钮的点击事件。
func _on_spawn_button_pressed() -> void:
	# 步骤1: 从各个UI控件中收集用户输入的生成参数。
	var pos = Vector2i(int(pos_x_spinbox.value), int(pos_y_spinbox.value))
	var value_text = value_option_button.get_item_text(value_option_button.selected)
	var value = int(value_text)
	var type_index = type_option_button.selected
	
	# 步骤2: 发出 `spawn_requested` 信号，并将收集到的数据作为参数广播出去。
	spawn_requested.emit(pos, value, type_index)
