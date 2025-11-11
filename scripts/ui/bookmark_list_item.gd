# scripts/ui/bookmark_list_item.gd

## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息，并在用户点击加载或请求删除时发出信号。
class_name BookmarkListItem
extends PanelContainer


# --- 信号 ---

## 当一个书签被选中（点击）时发出。
## @param bookmark_data: 被选中的书签的数据资源。
signal bookmark_selected(bookmark_data: BookmarkData)

## 当删除按钮被点击时发出。
## @param bookmark_data: 请求删除的书签的数据资源。
signal bookmark_deleted(bookmark_data: BookmarkData)


# --- 私有变量 ---

## 存储此列表项关联的书签数据。
var _bookmark_data: BookmarkData


# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _delete_button: Button = %DeleteButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_delete_button.pressed.connect(_on_delete_button_pressed)


# --- 公共方法 ---

## 使用 BookmarkData 资源来配置此列表项的显示内容。
## @param p_bookmark_data: 用于填充UI的书签数据资源。
func setup(p_bookmark_data: BookmarkData) -> void:
	_bookmark_data = p_bookmark_data

	_mode_name_label.text = "（未知模式）"

	if not _bookmark_data.mode_config_path.is_empty():
		var mode_config: GameModeConfig = load(_bookmark_data.mode_config_path)
		if is_instance_valid(mode_config):
			_mode_name_label.text = mode_config.mode_name
		else:
			_mode_name_label.text = "（模式配置丢失）"

	var datetime: String = "无法解析时间"
	if _bookmark_data.timestamp > 0:
		datetime = Time.get_datetime_string_from_unix_time(_bookmark_data.timestamp)

	var grid_size: int = _bookmark_data.board_snapshot.get("grid_size", 0)
	var info_str: String = "时间: %s | 分数: %d | 尺寸: %dx%d\n种子: %s" % [
		datetime,
		_bookmark_data.score,
		grid_size,
		grid_size,
		_bookmark_data.initial_seed
	]
	_info_label.text = info_str


# --- 信号处理函数 ---

## 响应整个控件的GUI输入事件，以处理选中操作。
## @param event: 输入事件对象。
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		bookmark_selected.emit(_bookmark_data)


## 响应“删除”按钮的点击事件。
func _on_delete_button_pressed() -> void:
	bookmark_deleted.emit(_bookmark_data)
