# scripts/ui/mode_selection.gd

## ModeSelection: 模式选择界面的UI控制器。
##
## 该脚本负责动态加载所有可用的游戏模式，为每个模式创建一个
## ModeCard 实例，并处理选择、配置与启动游戏的完整流程。
extends Control

# --- 导出变量 ---
@export var game_play_scene: PackedScene
## 在编辑器中配置所有可玩模式的资源文件路径。
@export var mode_configs: Array[Resource] = []

# --- 预加载资源 ---
const ModeCardScene = preload("res://scenes/ui/mode_card.tscn")

# --- 节点引用 ---
@onready var mode_list_container: VBoxContainer = %ModeListContainer
@onready var back_button: Button = %BackButton
@onready var left_panel_container: VBoxContainer = $CenterContainer/MainLayout/LeftPanel
@onready var right_panel_container: VBoxContainer = $CenterContainer/MainLayout/RightPanelContainer
@onready var start_game_button: Button = $CenterContainer/MainLayout/RightPanelContainer/StartGameButton
@onready var grid_size_spinbox: SpinBox = $CenterContainer/MainLayout/RightPanelContainer/HBoxContainer/SpinBox

# --- 内部状态 ---
var _selected_mode_config: GameModeConfig = null
var _current_grid_size: int = 4

## Godot生命周期函数：当节点及其子节点进入场景树时调用。
func _ready() -> void:
	_populate_mode_list()
	_reset_panels_to_default()
	back_button.pressed.connect(GlobalGameManager.return_to_main_menu)
	
	# 连接SpinBox的信号，实现配置联动
	grid_size_spinbox.value_changed.connect(_on_grid_size_changed)
	
	# 连接“开始游戏”按钮的信号
	start_game_button.pressed.connect(_on_start_game_button_pressed)


# --- 内部核心函数 ---

## 动态生成模式卡片列表。
func _populate_mode_list() -> void:
	# 清空容器，以防万一
	for child in mode_list_container.get_children():
		child.queue_free()

	# 遍历配置好的模式列表
	for mode_config_resource in mode_configs:
		if not is_instance_valid(mode_config_resource):
			continue
			
		var card: ModeCard = ModeCardScene.instantiate()
		mode_list_container.add_child(card)
		card.setup(mode_config_resource.resource_path)
		card.mode_selected.connect(_on_mode_card_selected)

## 重置左右面板到未选择模式时的默认状态。
func _reset_panels_to_default() -> void:
	for child in left_panel_container.get_children():
		child.queue_free()
	
	var default_label = Label.new()
	default_label.text = "请从中间选择一个游戏模式，查看详细信息并进行配置。"
	default_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	default_label.size_flags_horizontal = Control.SIZE_FILL
	left_panel_container.add_child(default_label)

	for child in right_panel_container.get_children():
		child.visible = false
	start_game_button.disabled = true

## 当一个模式被选中时，更新整个界面的核心函数。
func _update_ui_for_selection() -> void:
	if not is_instance_valid(_selected_mode_config):
		_reset_panels_to_default()
		return
	
	_populate_left_panel()
	_populate_right_panel()
	
	for child in right_panel_container.get_children():
		child.visible = true
	start_game_button.disabled = false

## 根据当前选中的模式和配置，填充左侧信息面板。
func _populate_left_panel() -> void:
	for child in left_panel_container.get_children():
		child.queue_free()
	
	# 模式名称
	var name_label = Label.new()
	name_label.text = _selected_mode_config.mode_name
	name_label.add_theme_font_size_override("font_size", 24)
	left_panel_container.add_child(name_label)
	
	# 分隔符
	left_panel_container.add_child(HSeparator.new())
	
	# 模式描述
	var desc_label = Label.new()
	desc_label.text = _selected_mode_config.mode_description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size_flags_horizontal = Control.SIZE_FILL
	left_panel_container.add_child(desc_label)
	
	# 最高分 (现在只创建标签，内容由 _update_high_score_label 更新)
	var score_label = Label.new()
	score_label.name = "HighScoreLabel" # 给它一个名字方便查找
	left_panel_container.add_child(score_label)
	
	_update_high_score_label()


## 根据当前选中的模式，填充右侧配置面板。
func _populate_right_panel() -> void:
	# 设置SpinBox的范围和默认值
	grid_size_spinbox.min_value = _selected_mode_config.min_grid_size
	grid_size_spinbox.max_value = _selected_mode_config.max_grid_size
	grid_size_spinbox.value = _selected_mode_config.default_grid_size
	_current_grid_size = _selected_mode_config.default_grid_size

## 单独更新最高分标签的文本，现在会调用 SaveManager。
func _update_high_score_label() -> void:
	var score_label = left_panel_container.find_child("HighScoreLabel", true, false)
	if is_instance_valid(score_label):
		var mode_id = _selected_mode_config.resource_path.get_file().get_basename()
		var high_score = SaveManager.get_high_score(mode_id, _current_grid_size)
		score_label.text = "\n在 %dx%d 尺寸下的最高分：%d" % [_current_grid_size, _current_grid_size, high_score]


# --- 信号处理函数 ---

## 响应任一模式卡片的点击事件。
func _on_mode_card_selected(config_path: String) -> void:
	_selected_mode_config = load(config_path)
	_update_ui_for_selection()

## 响应棋盘大小SpinBox的值改变事件。
func _on_grid_size_changed(new_value: float) -> void:
	_current_grid_size = int(new_value)
	_update_high_score_label()

## 响应“开始游戏”按钮的点击事件。
func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("无法开始游戏：没有选中的模式。")
		return
	
	# 调用 GlobalGameManager，并传递所有需要的配置
	GlobalGameManager.select_mode_and_start(
		_selected_mode_config.resource_path,
		game_play_scene,
		_current_grid_size
	)
