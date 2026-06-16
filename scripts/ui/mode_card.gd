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

# --- 常量 ---

const _CARD_RADIUS: int = 8
const _REST_SURFACE_COLOR: Color = Color(0.055, 0.090, 0.120, 0.58)
const _REST_BORDER_COLOR: Color = Color(0.95, 0.88, 0.72, 0.08)
const _FOCUS_BORDER_COLOR: Color = Color(0.93, 0.82, 0.58, 0.72)
const _SELECTED_SURFACE_COLOR: Color = Color(0.62, 0.35, 0.45, 0.88)
const _SELECTED_BORDER_COLOR: Color = Color(0.98, 0.88, 0.68, 0.24)
const _TEXT_PRIMARY_COLOR: Color = Color(0.96, 0.92, 0.84, 1.0)
const _TEXT_SECONDARY_COLOR: Color = Color(0.72, 0.78, 0.76, 0.86)
const _TEXT_SELECTED_SECONDARY_COLOR: Color = Color(0.98, 0.86, 0.72, 0.80)

# --- 私有变量 ---

var _config_path: String
var _is_selected: bool = false
var _original_stylebox: StyleBox
var _focused_stylebox: StyleBox
var _selected_stylebox: StyleBox
var _selected_focused_stylebox: StyleBox

# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel
@onready var _panel: Panel = $Panel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_styles()

	var _connect_result_50: int = focus_entered.connect(_on_focus_entered)
	var _connect_result_51: int = focus_exited.connect(_on_focus_exited)
	var _connect_result_52: int = pressed.connect(_on_pressed)


# --- 公共方法 ---

## 初始化卡片内容。
## @param config_path: 指向 GameModeConfig 资源文件的路径。
func setup(config_path: String) -> void:
	_config_path = config_path
	update_text()


## 更新卡片文本（用于初始化或语言切换）。
func update_text() -> void:
	var mode_config: GameModeConfig = GameModeConfigCacheUtility.get_config(_config_path)

	if is_instance_valid(mode_config):
		_title_label.text = tr(mode_config.mode_name)
		_description_label.text = tr("DESC_SELECT_MODE_PREFIX") + tr(mode_config.mode_name)
	else:
		_title_label.text = tr("UI_ERROR")
		_description_label.text = tr("ERR_LOAD_CONFIG")


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
	_original_stylebox = _create_card_style(_REST_SURFACE_COLOR, _REST_BORDER_COLOR, 1)
	_focused_stylebox = _create_card_style(_REST_SURFACE_COLOR.lightened(0.035), _FOCUS_BORDER_COLOR, 2)
	_selected_stylebox = _create_card_style(_SELECTED_SURFACE_COLOR, _SELECTED_BORDER_COLOR, 1)
	_selected_focused_stylebox = _create_card_style(_SELECTED_SURFACE_COLOR.lightened(0.04), _FOCUS_BORDER_COLOR, 2)
	_update_label_colors()


func _update_style() -> void:
	if has_focus() and _is_selected:
		_panel.add_theme_stylebox_override("panel", _selected_focused_stylebox)
	elif has_focus():
		_panel.add_theme_stylebox_override("panel", _focused_stylebox)
	elif _is_selected:
		_panel.add_theme_stylebox_override("panel", _selected_stylebox)
	else:
		_panel.add_theme_stylebox_override("panel", _original_stylebox)
	_update_label_colors()


func _create_card_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(_CARD_RADIUS)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


func _update_label_colors() -> void:
	_title_label.add_theme_color_override("font_color", _TEXT_PRIMARY_COLOR)
	if _is_selected or has_focus():
		_description_label.add_theme_color_override("font_color", _TEXT_SELECTED_SECONDARY_COLOR)
	else:
		_description_label.add_theme_color_override("font_color", _TEXT_SECONDARY_COLOR)


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
		var right_neighbor: Node = get_node_or_null(neighbor_path)

		if right_neighbor is Control:
			(right_neighbor as Control).grab_focus()
