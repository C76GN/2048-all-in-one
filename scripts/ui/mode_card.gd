# scripts/ui/mode_card.gd

## ModeCard: 在模式选择界面中代表单个游戏模式的UI卡片。
##
## 负责加载并显示模式的名称和描述，并在获得焦点时发出信号，
## 以便主界面更新模式详情。它支持一个独立的“选中”状态，
## 即使在焦点离开后也能保持高亮。
class_name ModeCard
extends Button

# --- 信号 ---

## 当此卡片获得UI焦点时发出。
## @param config_path: 卡片所代表的 GameModeConfig 资源路径。
signal card_focused(config_path: String)

# --- 私有变量 ---

var _config_path: String
var _is_selected: bool = false
var _original_stylebox: StyleBox
var _focused_stylebox: StyleBox
var _selected_stylebox: StyleBox

# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel
@onready var _panel: Panel = $Panel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_styles()

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)


# --- 公共方法 ---

## 初始化卡片内容。
## @param config_path: 指向 GameModeConfig 资源文件的路径。
func setup(config_path: String) -> void:
	_config_path = config_path
	var mode_config := load(_config_path) as GameModeConfig

	if is_instance_valid(mode_config):
		_title_label.text = mode_config.mode_name
		_description_label.text = "选择 " + mode_config.mode_name
	else:
		_title_label.text = "错误"
		_description_label.text = "无法加载模式"


## 获取此卡片关联的配置路径。
## @return: GameModeConfig 资源的路径字符串。
func get_config_path() -> String:
	return _config_path


## 设置卡片的“已选择”状态，并更新视觉样式。
## @param is_selected: true 表示设为选中，false 表示取消选中。
func set_selected(is_selected: bool) -> void:
	_is_selected = is_selected
	_update_style()


# --- 私有/辅助方法 ---

func _setup_styles() -> void:
	_original_stylebox = _panel.get_theme_stylebox("panel")

	# 确保有一个 StyleBoxFlat 作为基础
	var base_style: StyleBoxFlat
	if _original_stylebox is StyleBoxFlat:
		base_style = _original_stylebox.duplicate()
	else:
		base_style = StyleBoxFlat.new()
		base_style.bg_color = Color(0.2, 0.2, 0.2, 1)
		base_style.set_corner_radius_all(8)

	# 获取主题色
	var accent_color: Color
	if has_theme_color("accent_color", "Theme"):
		accent_color = get_theme_color("accent_color", "Theme")
	else:
		accent_color = Color(0.4, 0.7, 1.0)

	# 1. 聚焦样式 (Active Focus)
	_focused_stylebox = base_style.duplicate()
	_focused_stylebox.border_width_top = 4
	_focused_stylebox.border_width_right = 4
	_focused_stylebox.border_width_bottom = 4
	_focused_stylebox.border_width_left = 4
	_focused_stylebox.border_color = accent_color
	_focused_stylebox.bg_color = base_style.bg_color.lightened(0.1)

	# 2. 选中但未聚焦样式 (Passive Selection)
	_selected_stylebox = base_style.duplicate()
	_selected_stylebox.border_width_top = 2
	_selected_stylebox.border_width_right = 2
	_selected_stylebox.border_width_bottom = 2
	_selected_stylebox.border_width_left = 2

	var dimmed_color := accent_color
	dimmed_color.a = 0.5
	_selected_stylebox.border_color = dimmed_color


func _update_style() -> void:
	# 优先级：聚焦 > 选中 > 普通
	if has_focus():
		_panel.add_theme_stylebox_override("panel", _focused_stylebox)
	elif _is_selected:
		_panel.add_theme_stylebox_override("panel", _selected_stylebox)
	else:
		_panel.add_theme_stylebox_override("panel", _original_stylebox)


# --- 信号处理函数 ---

func _on_focus_entered() -> void:
	card_focused.emit(_config_path)
	_update_style()


func _on_focus_exited() -> void:
	_update_style()


func _on_pressed() -> void:
	# 点击时尝试将焦点移向右侧（如 GridSize 选项），模仿配置流程的下一步
	var neighbor_path: NodePath = get_focus_neighbor(SIDE_RIGHT)

	if not neighbor_path.is_empty():
		var right_neighbor := get_node_or_null(neighbor_path)

		if right_neighbor is Control:
			(right_neighbor as Control).grab_focus()
