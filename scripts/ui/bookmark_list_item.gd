# scripts/ui/bookmark_list_item.gd

## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息。
## 继承自 Button 以利用原生焦点和样式支持。
class_name BookmarkListItem
extends Button

# --- 信号 ---

## 当一个书签被确认选中（点击或按键确认）时发出。
## @param bookmark_data: 被选中的书签的数据资源。
signal bookmark_selected(bookmark_data: BookmarkData)

## 当此列表项获得焦点时发出，用于实时预览。
## @param bookmark_data: 当前获得焦点的书签数据资源。
signal item_focused(bookmark_data: BookmarkData)

# --- 私有变量 ---

var _bookmark_data: BookmarkData
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

## 使用 BookmarkData 资源来配置此列表项的显示内容。
## @param new_bookmark_data: 用于填充UI的书签数据资源。
func setup(new_bookmark_data: BookmarkData) -> void:
	_bookmark_data = new_bookmark_data

	_mode_name_label.text = tr("UNKNOWN_MODE")

	if not _bookmark_data.mode_config_path.is_empty():
		var mode_config := load(_bookmark_data.mode_config_path) as GameModeConfig
		if is_instance_valid(mode_config):
			# 注意：mode_name 这里假设是翻译键或直接文本，建议后续在 ModeConfig 中使用翻译键
			_mode_name_label.text = mode_config.mode_name
		else:
			_mode_name_label.text = tr("CONFIG_MISSING")

	var datetime: String = tr("TIME_PARSE_ERROR")
	if _bookmark_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(_bookmark_data.timestamp).replace("T", " ")

	var grid_size: int = _bookmark_data.board_snapshot.get("grid_size", 0)

	# 使用格式化字符串进行本地化
	var info_format: String = tr("BOOKMARK_INFO_FORMAT") # 需在翻译文件中定义: "%s | 分数: %d | 尺寸: %dx%d"
	# 如果还没有翻译文件，暂时使用默认格式
	if info_format == "BOOKMARK_INFO_FORMAT":
		info_format = "%s | " + tr("SCORE_LABEL") + ": %d | " + tr("SIZE_LABEL") + ": %dx%d"

	_info_label.text = info_format % [
		datetime,
		_bookmark_data.score,
		grid_size,
		grid_size
	]


## 设置列表项的选中状态。
## 通过独立的 SelectionHighlight 节点来显示选中态，与焦点状态解耦。
## @param is_selected: true 表示设为选中。
func set_selected(is_selected: bool) -> void:
	_is_selected_manually = is_selected
	if _selection_highlight:
		_selection_highlight.visible = is_selected


## 获取关联的数据。
## @return: 关联的 BookmarkData 资源。
func get_data() -> BookmarkData:
	return _bookmark_data


# --- 信号处理函数 ---

func _on_pressed() -> void:
	bookmark_selected.emit(_bookmark_data)


func _on_focus_entered() -> void:
	item_focused.emit(_bookmark_data)
