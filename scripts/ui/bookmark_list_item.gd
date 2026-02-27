# scripts/ui/bookmark_list_item.gd

## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息。
## 继承自 Button 以利用原生焦点和样式支持。
class_name BookmarkListItem
extends BaseListMenuItem

# --- 信号 ---

## 当一个书签被确认选中时发出。
## 兼容旧版信号名。
signal bookmark_selected(bookmark_data: BookmarkData)


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel


# --- 公共方法 ---

## 使用 BookmarkData 资源来配置此列表项。
## @param bookmark_data: 用于填充UI的书签数据资源。
func setup(bookmark_data: BookmarkData) -> void:
	# 设置基类数据并触发刷新
	setup_item(bookmark_data)


## 获取关联的 BookmarkData。
func get_bookmark_data() -> BookmarkData:
	return _item_data as BookmarkData


# --- 虚方法重写 ---

func _update_display() -> void:
	var bookmark_data := _item_data as BookmarkData
	if not is_instance_valid(bookmark_data):
		return

	_mode_name_label.text = tr("UNKNOWN_MODE")

	if not bookmark_data.mode_config_path.is_empty():
		var mode_config := load(bookmark_data.mode_config_path) as GameModeConfig
		if is_instance_valid(mode_config):
			_mode_name_label.text = tr(mode_config.mode_name)
		else:
			_mode_name_label.text = tr("CONFIG_MISSING")

	var datetime := tr("TIME_PARSE_ERROR")
	if bookmark_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(bookmark_data.timestamp).replace("T", " ")

	var grid_size: int = bookmark_data.board_snapshot.get("grid_size", 0)

	var score_label := tr("SCORE_LABEL").replace(": %d", "").strip_edges()
	var size_label := tr("SIZE_LABEL")
	var info_format := tr("BOOKMARK_INFO_FORMAT")
	_info_label.text = info_format % [
		datetime,
		score_label,
		bookmark_data.score,
		size_label,
		grid_size,
		grid_size
	]


# --- 信号处理函数 ---

func _on_pressed() -> void:
	super._on_pressed()
	bookmark_selected.emit(_item_data as BookmarkData)
