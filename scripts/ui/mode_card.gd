# scripts/ui/mode_card.gd

## ModeCard: 在模式选择界面中代表单个游戏模式的UI卡片。
##
## 负责加载并显示模式的名称和描述，并在被点击时发出信号。
class_name ModeCard
extends Button


# --- 信号 ---

## 当卡片被点击时发出。
## @param config_path: 卡片所代表的模式配置文件的资源路径。
signal mode_selected(config_path: String)


# --- 私有变量 ---

## 存储此卡片关联的模式配置资源路径。
var _config_path: String


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	pressed.connect(_on_pressed)


# --- 公共方法 ---

## 设置卡片内容。
## @param p_config_path: 指向 GameModeConfig 资源文件的路径。
func setup(p_config_path: String) -> void:
	_config_path = p_config_path
	var mode_config: GameModeConfig = load(_config_path)

	if is_instance_valid(mode_config):
		_title_label.text = mode_config.mode_name
		_description_label.text = "点击开始 " + mode_config.mode_name
	else:
		_title_label.text = "错误"
		_description_label.text = "无法加载模式"


# --- 信号处理函数 ---

## 响应按钮自身的 `pressed` 信号。
func _on_pressed() -> void:
	mode_selected.emit(_config_path)
