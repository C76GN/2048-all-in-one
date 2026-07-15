## ReplayListItem: 在回放列表中代表单个回放记录的UI组件。
##
## 负责显示回放的概要信息。
## 继承自 Button 以利用原生焦点和样式支持。
class_name ReplayListItem
extends BaseListMenuItem


# --- 信号 ---

## 当一个回放列表项被确认选中时发出。
signal replay_selected(replay_data: ReplayData)


# --- 常量 ---

const _INFO_FORMAT_FALLBACK: String = "%s | %s %d | %s %dx%d"


# --- 私有变量 ---

var _mode_display_name: String = ""


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel


# --- 公共方法 ---

## 使用 ReplayData 资源来配置此列表项。
## @param replay_data: 用于填充UI的回放数据资源。
## @param mode_display_name: 已由父菜单通过 GF 架构解析出的模式名称。
func setup(replay_data: ReplayData, mode_display_name: String) -> void:
	_mode_display_name = mode_display_name
	# 设置基类数据并触发刷新
	setup_item(replay_data)


## 获取关联的回放数据。
func get_replay_data() -> ReplayData:
	if _item_data is ReplayData:
		return _item_data
	return null


# --- 虚方法重写 ---

func _update_display() -> void:
	var replay_data: ReplayData = get_replay_data()
	if not is_instance_valid(replay_data):
		return

	if _mode_display_name.is_empty():
		_mode_name_label.text = tr("UNKNOWN_MODE")
	else:
		_mode_name_label.text = _mode_display_name

	var datetime: String = tr("TIME_PARSE_ERROR")
	if replay_data.timestamp > 0:
		datetime = GameClockUtility.format_datetime_value(replay_data.timestamp)

	var score_label: String = tr("SCORE_LABEL").replace(": %d", "").strip_edges()
	var size_label: String = tr("SIZE_LABEL")
	_info_label.text = GameTextFormatUtility.format_template(
		tr("REPLAY_INFO_FORMAT"),
		_INFO_FORMAT_FALLBACK,
		[
			datetime,
			score_label,
			replay_data.final_score,
			size_label,
			replay_data.grid_size,
			replay_data.grid_size,
		]
	)


# --- 信号处理函数 ---

func _on_pressed() -> void:
	super._on_pressed()
	var replay_data: ReplayData = get_replay_data()
	if is_instance_valid(replay_data):
		replay_selected.emit(replay_data)
