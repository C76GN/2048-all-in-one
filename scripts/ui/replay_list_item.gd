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

const _GAME_TEXT_FORMATTER: GDScript = preload("res://scripts/utilities/game_text_format_utility.gd")
const _INFO_FORMAT_FALLBACK: String = "%s | %s %d | %s %dx%d"


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel


# --- 公共方法 ---

## 使用 ReplayData 资源来配置此列表项。
## @param replay_data: 用于填充UI的回放数据资源。
func setup(replay_data: ReplayData) -> void:
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

	_mode_name_label.text = tr("UNKNOWN_MODE")

	if not replay_data.mode_config_path.is_empty():
		var mode_config: GameModeConfig = GameModeConfigCacheUtility.get_config(replay_data.mode_config_path)
		if is_instance_valid(mode_config):
			_mode_name_label.text = tr(mode_config.mode_name)
		else:
			_mode_name_label.text = tr("CONFIG_MISSING")

	var datetime: String = tr("TIME_PARSE_ERROR")
	if replay_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(replay_data.timestamp).replace("T", " ")

	var score_label: String = tr("SCORE_LABEL").replace(": %d", "").strip_edges()
	var size_label: String = tr("SIZE_LABEL")
	_info_label.text = _GAME_TEXT_FORMATTER.format_template(
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
