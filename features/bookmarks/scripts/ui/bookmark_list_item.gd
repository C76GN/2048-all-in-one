## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息。
## 继承自 Button 以利用原生焦点和样式支持。
class_name BookmarkListItem
extends BaseListMenuItem


# --- 常量 ---

const _INFO_FORMAT_FALLBACK: String = "%s | %s %d | %s %dx%d"


# --- 私有变量 ---

var _mode_display_name: String = ""


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel


# --- 公共方法 ---

## 使用 BookmarkData 资源来配置此列表项。
## @param bookmark_data: 用于填充UI的书签数据资源。
## @param mode_display_name: 已由父菜单通过 GF 架构解析出的模式名称。
func setup(bookmark_data: BookmarkData, mode_display_name: String) -> void:
	_mode_display_name = mode_display_name
	# 设置基类数据并触发刷新
	setup_item(bookmark_data)


## 获取关联的 BookmarkData。
func get_bookmark_data() -> BookmarkData:
	if _item_data is BookmarkData:
		return _item_data
	return null


# --- 虚方法重写 ---

func _update_display() -> void:
	var bookmark_data: BookmarkData = get_bookmark_data()
	if not is_instance_valid(bookmark_data):
		return

	if _mode_display_name.is_empty():
		_mode_name_label.text = tr("UNKNOWN_MODE")
	else:
		_mode_name_label.text = _mode_display_name

	var datetime: String = tr("TIME_PARSE_ERROR")
	if bookmark_data.timestamp > 0:
		datetime = GameClockUtility.format_datetime_value(bookmark_data.timestamp)

	var grid_size: int = GFVariantData.to_int(
		bookmark_data.board_snapshot.get(&"grid_size", bookmark_data.board_snapshot.get("grid_size", 0)),
		0
	)

	var score_label: String = tr("SCORE_LABEL").replace(": %d", "").strip_edges()
	var size_label: String = tr("SIZE_LABEL")
	_info_label.text = GameTextFormatUtility.format_template(
		tr("BOOKMARK_INFO_FORMAT"),
		_INFO_FORMAT_FALLBACK,
		[
			datetime,
			score_label,
			bookmark_data.score,
			size_label,
			grid_size,
			grid_size,
		]
	)
