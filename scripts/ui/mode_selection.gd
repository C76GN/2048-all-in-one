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
@onready var seed_line_edit: LineEdit = $CenterContainer/MainLayout/RightPanelContainer/HBoxContainer2/SeedLineEdit
@onready var refresh_seed_button: Button = $CenterContainer/MainLayout/RightPanelContainer/HBoxContainer2/RefreshSeedButton
@onready var _info_default_label: Label = $CenterContainer/MainLayout/LeftPanel/Label

# --- 内部状态 ---
var _selected_mode_config: GameModeConfig = null
var _current_grid_size: int = 4

# --- 用于左侧面板的持久化UI元素 ---
var _info_name_label: Label
var _info_separator: HSeparator
var _info_desc_label: Label
var _info_score_label: Label


## Godot生命周期函数：当节点及其子节点进入场景树时调用。
func _ready() -> void:
	_create_persistent_info_panel()
	_populate_mode_list()
	_reset_panels_to_default()
	back_button.pressed.connect(GlobalGameManager.return_to_main_menu)
	
	# 连接SpinBox的信号，实现配置联动
	grid_size_spinbox.value_changed.connect(_on_grid_size_changed)
	
	# 连接“开始游戏”按钮的信号
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	# 连接刷新按钮的 pressed 信号到新的处理函数
	refresh_seed_button.pressed.connect(_generate_and_display_new_seed)
	# 首次进入界面时，调用一次以生成初始种子
	_generate_and_display_new_seed()

# --- 内部核心函数 ---

## 在启动时创建一次左侧面板的所有UI元素（除了已存在的默认标签）。
func _create_persistent_info_panel() -> void:
	# 模式名称标签
	_info_name_label = Label.new()
	_info_name_label.add_theme_font_size_override("font_size", 24)
	left_panel_container.add_child(_info_name_label)
	
	# 分隔符
	_info_separator = HSeparator.new()
	left_panel_container.add_child(_info_separator)
	
	# 模式描述标签
	_info_desc_label = Label.new()
	_info_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_desc_label.size_flags_horizontal = Control.SIZE_FILL
	left_panel_container.add_child(_info_desc_label)
	
	# 最高分标签
	_info_score_label = Label.new()
	left_panel_container.add_child(_info_score_label)
	

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
	# 显示默认提示，隐藏详细信息
	_info_default_label.visible = true
	_info_name_label.visible = false
	_info_separator.visible = false
	_info_desc_label.visible = false
	_info_score_label.visible = false

	# 隐藏右侧配置面板
	for child in right_panel_container.get_children():
		child.visible = false
	start_game_button.disabled = true

## 当一个模式被选中时，更新整个界面的核心函数。
func _update_ui_for_selection() -> void:
	if not is_instance_valid(_selected_mode_config):
		_reset_panels_to_default()
		return
	
	# 隐藏默认提示，显示详细信息
	_info_default_label.visible = false
	_info_name_label.visible = true
	_info_separator.visible = true
	_info_desc_label.visible = true
	_info_score_label.visible = true
	
	# 更新左侧面板内容（只更新文本，不重建节点）
	_populate_left_panel()
	
	# 更新右侧面板内容
	_populate_right_panel()
	
	for child in right_panel_container.get_children():
		child.visible = true
	start_game_button.disabled = false

## 根据当前选中的模式和配置，填充左侧信息面板。
func _populate_left_panel() -> void:
	# 只更新已存在标签的文本
	_info_name_label.text = _selected_mode_config.mode_name
	_info_desc_label.text = _selected_mode_config.mode_description
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
	if is_instance_valid(_info_score_label):
		var mode_id = _selected_mode_config.resource_path.get_file().get_basename()
		# 即使没有记录，SaveManager.get_high_score 也会返回
		var high_score = SaveManager.get_high_score(mode_id, _current_grid_size)
		_info_score_label.text = "\n在 %dx%d 尺寸下的最高分：%d" % [_current_grid_size, _current_grid_size, high_score]


# --- 信号处理函数 ---

## 响应任一模式卡片的点击事件。
func _on_mode_card_selected(config_path: String) -> void:
	# 如果点击的是当前已选中的模式，则不执行任何操作，防止闪烁
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	_selected_mode_config = load(config_path)
	_update_ui_for_selection()

## 响应棋盘大小SpinBox的值改变事件。
func _on_grid_size_changed(new_value: float) -> void:
	_current_grid_size = int(new_value)
	# 确保在改变尺寸时，如果已有模式被选中，则立即更新最高分显示
	if is_instance_valid(_selected_mode_config):
		_update_high_score_label()

## 响应“开始游戏”按钮的点击事件。
func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("无法开始游戏：没有选中的模式。")
		return
	
	var seed_text = seed_line_edit.text
	var seed_value = 0
	if seed_text.is_empty():
		# 如果输入为空，则使用当前时间生成一个随机种子
		seed_value = Time.get_unix_time_from_system()
	else:
		# 确保输入的是有效的数字
		if seed_text.is_valid_int():
			seed_value = int(seed_text)
		else:
			# 如果输入的不是有效整数，则使用其哈希值作为种子
			seed_value = seed_text.hash()

	# 调用 GlobalGameManager，并传递所有需要的配置
	GlobalGameManager.select_mode_and_start(
		_selected_mode_config.resource_path,
		game_play_scene,
		_current_grid_size,
		seed_value
	)

## 生成一个新的随机种子并将其显示在输入框中。
func _generate_and_display_new_seed() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize() # 确保每次生成的随机数都不同
	# 使用 randi() 生成一个完整的32位整数作为种子
	seed_line_edit.text = str(rng.randi())
