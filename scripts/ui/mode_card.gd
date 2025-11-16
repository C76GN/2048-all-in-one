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

## 存储此卡片关联的模式配置资源路径。
var _config_path: String

## 标记此卡片是否处于“已选择”状态。
var _is_selected: bool = false

## 用于存储原始的StyleBox，以便在失去焦点时恢复。
var _original_stylebox: StyleBox

## 用于在获得焦点时显示高亮效果的StyleBox。
var _focused_stylebox: StyleBox

## 用于在“已选择”但未聚焦时显示高亮效果的StyleBox。
var _selected_stylebox: StyleBox


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel
@onready var _panel: Panel = $Panel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	# 从 Panel 子节点获取原始样式
	_original_stylebox = _panel.get_theme_stylebox("panel")

	# 基于原始样式创建高亮样式
	if _original_stylebox is StyleBoxFlat:
		var original_flat_style: StyleBoxFlat = _original_stylebox as StyleBoxFlat

		# 定义统一的高亮边框样式
		var highlight_style := original_flat_style.duplicate() as StyleBoxFlat
		highlight_style.border_width_top = 2
		highlight_style.border_width_right = 2
		highlight_style.border_width_bottom = 2
		highlight_style.border_width_left = 2
		highlight_style.border_color = Color(1.0, 1.0, 1.0, 1.0) # 白色

		# 让“选中”和“聚焦”样式都使用这个统一样式
		_selected_stylebox = highlight_style
		_focused_stylebox = highlight_style
	else:
		# 为非 StyleBoxFlat 的情况提供安全的回退
		_selected_stylebox = _original_stylebox.duplicate()
		_focused_stylebox = _original_stylebox.duplicate()

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)


# --- 公共方法 ---

## 初始化卡片内容。
## @param p_config_path: 指向 GameModeConfig 资源文件的路径。
func setup(p_config_path: String) -> void:
	_config_path = p_config_path
	var mode_config: GameModeConfig = load(_config_path)

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


## 设置卡片的“已选择”状态，并更新其视觉样式。
## @param is_selected: true 表示设为选中，false 表示取消选中。
func set_selected(is_selected: bool) -> void:
	_is_selected = is_selected
	_update_style()


# --- 私有/辅助方法 ---

## 根据当前状态（是否聚焦，是否选中）更新卡片的StyleBox。
func _update_style() -> void:
	# 将样式应用到 _panel 子节点上
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
	var neighbor_path: NodePath = get_focus_neighbor(SIDE_RIGHT)

	if not neighbor_path.is_empty():
		var right_neighbor: Node = get_node_or_null(neighbor_path)

		if right_neighbor is Control:
			(right_neighbor as Control).grab_focus()
