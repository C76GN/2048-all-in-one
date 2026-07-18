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
var _mode_config: GameModeConfig = null
var _is_selected: bool = false
var _style_utility: GameUiStyleUtility = null

# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel
@onready var _panel: Panel = $Panel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _connect_result_50: int = focus_entered.connect(_on_focus_entered)
	var _connect_result_51: int = focus_exited.connect(_on_focus_exited)
	var _connect_result_52: int = pressed.connect(_on_pressed)


# --- 公共方法 ---

## 初始化卡片内容。
## @param config_path: 指向 GameModeConfig 资源文件的路径。
## @param mode_config: 已由父控制器通过 GF 架构解析出的模式配置。
## @param style_utility: 父控制器注入的主题静态样式服务。
func setup(
	config_path: String,
	mode_config: GameModeConfig,
	style_utility: GameUiStyleUtility
) -> void:
	_config_path = config_path
	_mode_config = mode_config
	_style_utility = style_utility
	if not is_instance_valid(_style_utility):
		push_error("[ModeCard] 缺少 GameUiStyleUtility，无法应用卡片语义样式。")
	update_text()
	_update_style()


## 更新卡片文本（用于初始化或语言切换）。
func update_text() -> void:
	if is_instance_valid(_mode_config):
		_title_label.text = tr(_mode_config.mode_name)
		_description_label.text = tr("DESC_SELECT_MODE_PREFIX") + tr(_mode_config.mode_name)
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

func _update_style() -> void:
	if not is_instance_valid(_style_utility):
		return
	var surface_role: GameUiStyleUtility.SurfaceRole = (
		GameUiStyleUtility.SurfaceRole.SELECTED
		if _is_selected
		else GameUiStyleUtility.SurfaceRole.PANEL
	)
	var border_role: GameUiStyleUtility.BorderRole = GameUiStyleUtility.BorderRole.DEFAULT
	var border_width: int = 2
	if has_focus():
		border_role = GameUiStyleUtility.BorderRole.FOCUS
		border_width = 4 if _is_selected else 3
	elif _is_selected:
		border_role = GameUiStyleUtility.BorderRole.SELECTED
		border_width = 3
	_style_utility.style_panel(_panel, surface_role, border_role, border_width)
	_update_label_colors()


func _update_label_colors() -> void:
	if not is_instance_valid(_style_utility):
		return
	_style_utility.style_label(_title_label, GameUiStyleUtility.TextRole.PRIMARY)
	var description_role: GameUiStyleUtility.TextRole = (
		GameUiStyleUtility.TextRole.PRIMARY
		if _is_selected or has_focus()
		else GameUiStyleUtility.TextRole.SECONDARY
	)
	_style_utility.style_label(_description_label, description_role)


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
			var right_control: Control = right_neighbor
			right_control.grab_focus()
