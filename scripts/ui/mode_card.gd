# scripts/ui/mode_card.gd

## ModeCard: 在模式选择界面中代表单个游戏模式的UI卡片。
##
## 负责加载并显示模式的名称和描述，并在被点击时发出信号。
class_name ModeCard
extends Button

# --- 信号定义 ---

## 当卡片被点击时发出，携带其代表的模式配置文件的路径。
signal mode_selected(config_path: String)

# --- 节点引用 ---
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel

# --- 内部状态 ---
var _config_path: String

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 连接自身的 pressed 信号到处理函数。
	pressed.connect(func(): mode_selected.emit(_config_path))

# --- 公共接口 ---

## 设置卡片内容。
## @param p_config_path: 指向 GameModeConfig 资源文件的路径。
func setup(p_config_path: String) -> void:
	_config_path = p_config_path
	var mode_config: GameModeConfig = load(_config_path)
	
	if is_instance_valid(mode_config):
		title_label.text = mode_config.mode_name
		# 可以在GameModeConfig中新增一个 description 变量来显示
		# 这里我们暂时用模式名称代替描述
		description_label.text = "点击开始 " + mode_config.mode_name
	else:
		title_label.text = "错误"
		description_label.text = "无法加载模式"

# --- 信号处理函数 ---

## 当按钮被按下时调用。
func _on_pressed() -> void:
	mode_selected.emit(_config_path)
