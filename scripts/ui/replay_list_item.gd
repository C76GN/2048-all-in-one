# scripts/ui/replay_list_item.gd

## ReplayListItem: 在回放列表中代表单个回放记录的UI组件。
##
## 负责显示回放的概要信息，并在用户点击加载或请求删除时发出信号。
class_name ReplayListItem
extends PanelContainer


# --- 信号 ---

## 当一个回放列表项被选中（点击）时发出。
## @param replay_data: 被选中的回放的数据资源。
signal replay_selected(replay_data: ReplayData)

## 当删除按钮被点击时发出。
## @param replay_data: 请求删除的回放的数据资源。
signal replay_deleted(replay_data: ReplayData)


# --- 私有变量 ---

## 存储此列表项关联的回放数据。
var _replay_data: ReplayData


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _delete_button: Button = %DeleteButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_delete_button.pressed.connect(_on_delete_button_pressed)


# --- 公共方法 ---

## 使用 ReplayData 资源来配置此列表项的显示内容。
##
## @param p_replay_data: 用于填充UI的回放数据资源。
func setup(p_replay_data: ReplayData) -> void:
	_replay_data = p_replay_data

	# 为了确保UI的健壮性，即使关联的模式配置文件丢失，
	# 此列表项也应能正常显示其他有效信息（如时间和分数）。
	_mode_name_label.text = "（未知模式）"

	# 尝试加载模式配置以获取更具体的模式名称。
	if not _replay_data.mode_config_path.is_empty():
		var mode_config: GameModeConfig = load(_replay_data.mode_config_path)
		if is_instance_valid(mode_config):
			_mode_name_label.text = mode_config.mode_name
		else:
			# 如果加载失败，则显示一个明确的提示信息。
			_mode_name_label.text = "（模式配置丢失）"

	# 设置并格式化时间和分数等信息。
	var datetime: String = "无法解析时间"
	if _replay_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(_replay_data.timestamp)

	var info_str: String = "时间: %s | 分数: %d | 尺寸: %dx%d\n种子: %s" % [
		datetime,
		_replay_data.final_score,
		_replay_data.grid_size,
		_replay_data.grid_size,
		_replay_data.initial_seed
	]
	_info_label.text = info_str


# --- 信号处理函数 ---

## 响应整个控件的GUI输入事件，以处理选中操作。
##
## @param event: 输入事件对象。
func _on_gui_input(event: InputEvent) -> void:
	# 检查输入事件是否为鼠标左键的按下操作。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		replay_selected.emit(_replay_data)


## 响应“删除”按钮的点击事件。
func _on_delete_button_pressed() -> void:
	replay_deleted.emit(_replay_data)
