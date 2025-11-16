# scripts/ui/mode_card.gd

## ModeCard: 在模式选择界面中代表单个游戏模式的UI卡片。
##
## 负责加载并显示模式的名称和描述，并在获得焦点时发出信号，
## 以便主界面更新模式详情。
class_name ModeCard
extends Button


# --- 信号 ---

## 当此卡片获得UI焦点时发出。
## @param config_path: 卡片所代表的 GameModeConfig 资源路径。
signal card_focused(config_path: String)


# --- 私有变量 ---

## 存储此卡片关联的模式配置资源路径。
var _config_path: String


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	pressed.connect(_on_pressed)


# --- 公共方法 ---

## 初始化卡片内容。
## @param p_config_path: 指向 GameModeConfig 资源文件的路径。
func setup(p_config_path: String) -> void:
	_config_path = p_config_path
	var mode_config: GameModeConfig = load(_config_path)

	if is_instance_valid(mode_config):
		_title_label.text = mode_config.mode_name
		_description_label.text = "选择 " + mode_config.mode_name
	else:
		_title_label.text = "错误"
		_description_label.text = "无法加载模式"


## 获取此卡片关联的配置路径。
## @return: GameModeConfig 资源的路径字符串。
func get_config_path() -> String:
	return _config_path


# --- 信号处理函数 ---

## 当卡片获得焦点时，发出信号通知父节点。
func _on_focus_entered() -> void:
	card_focused.emit(_config_path)


## 响应按钮自身的 `pressed` 信号。
## 用于在点击或确认卡片时，将焦点快速转移到右侧的配置面板。
func _on_pressed() -> void:
	var neighbor_path: NodePath = get_focus_neighbor(SIDE_RIGHT)

	if not neighbor_path.is_empty():
		var right_neighbor: Node = get_node_or_null(neighbor_path)

		if right_neighbor is Control:
			(right_neighbor as Control).grab_focus()
