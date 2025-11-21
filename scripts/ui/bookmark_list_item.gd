# scripts/ui/bookmark_list_item.gd

## BookmarkListItem: 在书签列表中代表单个书签记录的UI组件。
##
## 负责显示书签的概要信息。
## 支持键盘和手柄通过焦点和 "ui_accept" 动作进行交互。
class_name BookmarkListItem
extends PanelContainer

# --- 信号 ---

## 当一个书签被确认选中（点击或按键确认）时发出。
## @param bookmark_data: 被选中的书签的数据资源。
signal bookmark_selected(bookmark_data: BookmarkData)

## 当此列表项获得焦点时发出，用于实时预览。
## @param bookmark_data: 当前获得焦点的书签数据资源。
signal item_focused(bookmark_data: BookmarkData)

# --- 私有变量 ---

var _bookmark_data: BookmarkData
var _original_stylebox: StyleBox
var _focused_stylebox: StyleBox
var _selected_stylebox: StyleBox
var _is_selected: bool = false

# --- @onready 变量 (节点引用) ---

@onready var _mode_name_label: Label = %ModeNameLabel
@onready var _info_label: Label = %InfoLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_styles()

	gui_input.connect(_on_gui_input)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)


# --- 公共方法 ---

## 使用 BookmarkData 资源来配置此列表项的显示内容。
## @param new_bookmark_data: 用于填充UI的书签数据资源。
func setup(new_bookmark_data: BookmarkData) -> void:
	_bookmark_data = new_bookmark_data

	_mode_name_label.text = "（未知模式）"

	if not _bookmark_data.mode_config_path.is_empty():
		var mode_config := load(_bookmark_data.mode_config_path) as GameModeConfig
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


## 设置列表项的“已选择”状态，并更新视觉样式。
## @param is_selected: true 表示设为选中，false 表示取消选中。
func set_selected(is_selected: bool) -> void:
	_is_selected = is_selected
	_update_style()


## 获取关联的数据。
## @return: 关联的 BookmarkData 资源。
func get_data() -> BookmarkData:
	return _bookmark_data


# --- 私有/辅助方法 ---

func _setup_styles() -> void:
	_original_stylebox = get_theme_stylebox("panel")

	var base_style: StyleBoxFlat
	if _original_stylebox is StyleBoxFlat:
		base_style = _original_stylebox.duplicate()
	else:
		base_style = StyleBoxFlat.new()
		base_style.bg_color = Color(0.2, 0.2, 0.2, 1)
		base_style.set_corner_radius_all(4)

	_focused_stylebox = base_style.duplicate()
	_focused_stylebox.border_width_top = 4
	_focused_stylebox.border_width_right = 4
	_focused_stylebox.border_width_bottom = 4
	_focused_stylebox.border_width_left = 4
	_focused_stylebox.bg_color = base_style.bg_color.lightened(0.1)

	var accent_color: Color
	if has_theme_color("accent_color", "Theme"):
		accent_color = get_theme_color("accent_color", "Theme")
	else:
		accent_color = Color(0.4, 0.7, 1.0)

	_focused_stylebox.border_color = accent_color

	_selected_stylebox = base_style.duplicate()
	_selected_stylebox.border_width_top = 2
	_selected_stylebox.border_width_right = 2
	_selected_stylebox.border_width_bottom = 2
	_selected_stylebox.border_width_left = 2
	_selected_stylebox.bg_color = base_style.bg_color

	var dimmed_color := accent_color
	dimmed_color.a = 0.5
	_selected_stylebox.border_color = dimmed_color


func _update_style() -> void:
	if has_focus():
		add_theme_stylebox_override("panel", _focused_stylebox)
	elif _is_selected:
		add_theme_stylebox_override("panel", _selected_stylebox)
	else:
		add_theme_stylebox_override("panel", _original_stylebox)


# --- 信号处理函数 ---

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		bookmark_selected.emit(_bookmark_data)

	if event.is_action_pressed("ui_accept"):
		bookmark_selected.emit(_bookmark_data)
		get_viewport().set_input_as_handled()


func _on_focus_entered() -> void:
	item_focused.emit(_bookmark_data)
	_update_style()


func _on_focus_exited() -> void:
	_update_style()
