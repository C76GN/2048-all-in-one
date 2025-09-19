# scripts/ui/test_panel.gd

extends VBoxContainer

# 定义一个信号，当用户请求生成一个方块时发出。
# 它会携带生成所需的所有信息。
signal spawn_requested(grid_pos: Vector2i, value: int, type: int)

# --- 节点引用 ---
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var value_option_button: OptionButton = %ValueOptionButton
@onready var type_option_button: OptionButton = %TypeOptionButton
@onready var spawn_button: Button = %SpawnButton


func _ready() -> void:
	# 连接按钮的 pressed 信号到内部处理函数
	spawn_button.pressed.connect(_on_spawn_button_pressed)
	# 动态填充数值下拉列表
	var current_power_of_two = 2
	while current_power_of_two <= 65536:
		value_option_button.add_item(str(current_power_of_two))
		current_power_of_two *= 2

# 当“生成方块”按钮被点击时调用的函数
func _on_spawn_button_pressed() -> void:
	# 从UI控件获取所有输入值
	var pos = Vector2i(int(pos_x_spinbox.value), int(pos_y_spinbox.value))
	var value_text = value_option_button.get_item_text(value_option_button.selected)
	var value = int(value_text)
	var type_index = type_option_button.selected
	
	# 发出信号，将收集到的数据广播出去
	spawn_requested.emit(pos, value, type_index)
