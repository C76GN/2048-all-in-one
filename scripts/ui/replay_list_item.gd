# scripts/ui/replay_list_item.gd

## ReplayListItem: 在回放列表中代表单个回放记录的UI组件。
##
## 负责显示回放的概要信息。
## 继承自 Button 以利用原生焦点和样式支持。
class_name ReplayListItem
extends Button

# --- 信号 ---

## 当一个回放列表项被确认选中（点击或按键确认）时发出。
## @param replay_data: 被选中的回放数据资源。
signal replay_selected(replay_data: ReplayData)

## 当此列表项获得焦点时发出，用于实时预览。
## @param replay_data: 当前获得焦点的回放数据资源。
signal item_focused(replay_data: ReplayData)

# --- 私有变量 ---

var _replay_data: ReplayData
var _is_selected_manually: bool = false

# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _selection_highlight: Control = $SelectionHighlight


# --- Godot 生命周期方法 ---

func _ready() -> void:
	toggle_mode = true
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)


# --- 公共方法 ---

## 使用 ReplayData 资源来配置此列表项的显示内容。
## @param new_replay_data: 用于填充UI的回放数据资源。
func setup(new_replay_data: ReplayData) -> void:
	_replay_data = new_replay_data

	_mode_name_label.text = tr("UNKNOWN_MODE")

	if not _replay_data.mode_config_path.is_empty():
		var mode_config := load(_replay_data.mode_config_path) as GameModeConfig
		if is_instance_valid(mode_config):
			_mode_name_label.text = mode_config.mode_name
		else:
			_mode_name_label.text = tr("CONFIG_MISSING")

	var datetime: String = tr("TIME_PARSE_ERROR")
	if _replay_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(_replay_data.timestamp).replace("T", " ")

	# 使用格式化字符串进行本地化
	var info_format: String = tr("REPLAY_INFO_FORMAT")
	if info_format == "REPLAY_INFO_FORMAT":
		info_format = "%s | " + tr("SCORE_LABEL") + ": %d | " + tr("SIZE_LABEL") + ": %dx%d"

	_info_label.text = info_format % [
		datetime,
		_replay_data.final_score,
		_replay_data.grid_size,
		_replay_data.grid_size
	]


## 设置列表项的“已选择”状态。
func set_selected(is_selected: bool) -> void:
	_is_selected_manually = is_selected
	if _selection_highlight:
		_selection_highlight.visible = is_selected


## 获取关联的数据。
## @return: 关联的 ReplayData 资源。
func get_data() -> ReplayData:
	return _replay_data


# --- 信号处理函数 ---

func _on_pressed() -> void:
	replay_selected.emit(_replay_data)


func _on_focus_entered() -> void:
	item_focused.emit(_replay_data)
