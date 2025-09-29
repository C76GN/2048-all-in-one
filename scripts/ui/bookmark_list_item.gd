# scripts/ui/bookmark_list_item.gd

## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息，并在用户点击加载或请求删除时发出信号。
class_name BookmarkListItem
extends PanelContainer

signal bookmark_selected(bookmark_data: BookmarkData)
signal bookmark_deleted(bookmark_data: BookmarkData)

# --- 节点引用 ---
@onready var mode_name_label: Label = %ModeNameLabel
@onready var info_label: Label = %InfoLabel
@onready var delete_button: Button = %DeleteButton

var _bookmark_data: BookmarkData

func _ready() -> void:
	# 连接自身的GUI输入事件，以便整个条目都可以被点击以选中。
	gui_input.connect(_on_gui_input)
	delete_button.pressed.connect(func(): bookmark_deleted.emit(_bookmark_data))

## 使用 BookmarkData 资源来配置此列表项的显示内容。
func setup(p_bookmark_data: BookmarkData) -> void:
	_bookmark_data = p_bookmark_data

	mode_name_label.text = "（未知模式）"

	if not _bookmark_data.mode_config_path.is_empty():
		var mode_config: GameModeConfig = load(_bookmark_data.mode_config_path)
		if is_instance_valid(mode_config):
			mode_name_label.text = mode_config.mode_name
		else:
			mode_name_label.text = "（模式配置丢失）"

	var datetime = "无法解析时间"
	if _bookmark_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(_bookmark_data.timestamp)

	var grid_size = _bookmark_data.board_snapshot.get("grid_size", 0)
	var info_str = "时间: %s | 分数: %d | 尺寸: %dx%d\n种子: %s" % [
		datetime,
		_bookmark_data.score,
		grid_size,
		grid_size,
		_bookmark_data.initial_seed
	]
	info_label.text = info_str

## 响应 GUI输入以选中此列表项。
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		bookmark_selected.emit(_bookmark_data)
