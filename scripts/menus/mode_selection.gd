# scripts/menus/mode_selection.gd

## ModeSelection: 模式选择界面的UI控制器。
##
## 该脚本负责动态加载所有可用的游戏模式，为每个模式创建一个
## ModeCard 实例，并处理选择、配置与启动游戏的完整流程。
class_name ModeSelection
extends Control


# --- 常量 ---

## 单个模式卡片UI场景的引用。
const MODE_CARD_SCENE: PackedScene = preload("res://scenes/ui/mode_card.tscn")


# --- 导出变量 ---

## 游戏主场景的 PackedScene 引用，用于启动游戏。
@export var game_play_scene: PackedScene

## 在编辑器中配置的所有可玩模式的资源文件数组。
@export var mode_configs: Array[Resource] = []


# --- 私有变量 ---

## 当前被选中或聚焦的模式配置。
var _selected_mode_config: GameModeConfig = null

## 当前在UI上选择的棋盘尺寸。
var _current_grid_size: int = 4

## 模式列表每页显示的项目数量。
var _items_per_page: int = 5

## 模式列表的当前页码。
var _current_page: int = 0

## 模式列表的总页数。
var _total_pages: int = 0

## 左侧信息面板 - 模式名称标签。
var _info_name_label: Label

## 左侧信息面板 - 分隔线。
var _info_separator: HSeparator

## 左侧信息面板 - 模式描述标签。
var _info_desc_label: Label

## 左侧信息面板 - 最高分标签。
var _info_score_label: Label


# --- @onready 变量 (节点引用) ---

@onready var _mode_list_container: VBoxContainer = %ModeListContainer
@onready var _back_button: Button = %BackButton
@onready var _left_panel_container: VBoxContainer = $CenterContainer/MainLayout/LeftPanel
@onready var _right_panel_container: VBoxContainer = $CenterContainer/MainLayout/RightPanelContainer
@onready var _start_game_button: Button = $CenterContainer/MainLayout/RightPanelContainer/StartGameButton
@onready var _grid_size_option_button: OptionButton = %GridSizeOptionButton
@onready var _seed_line_edit: LineEdit = $CenterContainer/MainLayout/RightPanelContainer/HBoxContainer2/SeedLineEdit
@onready var _refresh_seed_button: Button = $CenterContainer/MainLayout/RightPanelContainer/HBoxContainer2/RefreshSeedButton
@onready var _info_default_label: Label = $CenterContainer/MainLayout/LeftPanel/Label
@onready var _prev_page_button: Button = %PrevPageButton
@onready var _next_page_button: Button = %NextPageButton
@onready var _pagination_container: HBoxContainer = _prev_page_button.get_parent()


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_create_persistent_info_panel()
	_populate_mode_list()

	_back_button.pressed.connect(_on_back_button_pressed)
	_grid_size_option_button.item_selected.connect(_on_grid_size_selected)
	_start_game_button.pressed.connect(_on_start_game_button_pressed)
	_refresh_seed_button.pressed.connect(_on_refresh_seed_button_pressed)
	_prev_page_button.pressed.connect(_on_prev_page_pressed)
	_next_page_button.pressed.connect(_on_next_page_pressed)
	_grid_size_option_button.get_popup().id_focused.connect(_on_grid_size_focused)

	_generate_and_display_new_seed()

	var cards: Array = _mode_list_container.get_children()
	if not cards.is_empty():
		var first_card: ModeCard = cards[0]
		await get_tree().process_frame
		_on_mode_card_focused(first_card.get_config_path())
		first_card.grab_focus()
	else:
		_info_default_label.visible = true
		_right_panel_container.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_left"):
		var focused_control: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused_control) and _right_panel_container.is_ancestor_of(focused_control):
			_focus_last_selected_card()
			get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

func _focus_last_selected_card() -> void:
	if not is_instance_valid(_selected_mode_config):
		return

	for card in _mode_list_container.get_children():
		if card is ModeCard and card.get_config_path() == _selected_mode_config.resource_path:
			card.grab_focus()
			break


func _create_persistent_info_panel() -> void:
	_info_name_label = Label.new()
	_info_name_label.add_theme_font_size_override("font_size", 24)
	_left_panel_container.add_child(_info_name_label)

	_info_separator = HSeparator.new()
	_left_panel_container.add_child(_info_separator)

	_info_desc_label = Label.new()
	_info_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc_label.size_flags_horizontal = Control.SIZE_FILL
	_left_panel_container.add_child(_info_desc_label)

	_info_score_label = Label.new()
	_left_panel_container.add_child(_info_score_label)


func _populate_mode_list() -> void:
	for child in _mode_list_container.get_children():
		child.queue_free()

	_total_pages = 0 if mode_configs.is_empty() else int(ceil(float(mode_configs.size()) / _items_per_page))
	_update_pagination_buttons_visibility()

	if _total_pages == 0:
		return

	var start_index: int = _current_page * _items_per_page
	var modes_for_this_page: Array = mode_configs.slice(start_index, start_index + _items_per_page)

	for mode_config_resource in modes_for_this_page:
		if not is_instance_valid(mode_config_resource):
			continue

		var card := MODE_CARD_SCENE.instantiate() as ModeCard
		_mode_list_container.add_child(card)
		card.setup(mode_config_resource.resource_path)
		card.card_focused.connect(_on_mode_card_focused)

	var cards: Array = _mode_list_container.get_children()
	if not cards.is_empty():
		for i in range(cards.size()):
			var current_card: Control = cards[i]
			if i > 0:
				current_card.focus_neighbor_top = cards[i - 1].get_path()
			if i < cards.size() - 1:
				current_card.focus_neighbor_bottom = cards[i + 1].get_path()


func _update_ui_for_selection() -> void:
	if not is_instance_valid(_selected_mode_config):
		_info_default_label.visible = true
		_info_name_label.visible = false
		_info_separator.visible = false
		_info_desc_label.visible = false
		_info_score_label.visible = false
		_right_panel_container.visible = false
		return

	_info_default_label.visible = false
	_info_name_label.visible = true
	_info_separator.visible = true
	_info_desc_label.visible = true
	_info_score_label.visible = true
	_right_panel_container.visible = true

	_populate_left_panel()
	_populate_right_panel()


func _populate_left_panel() -> void:
	_info_name_label.text = _selected_mode_config.mode_name
	_info_desc_label.text = _selected_mode_config.mode_description
	_update_high_score_label()


func _populate_right_panel() -> void:
	_grid_size_option_button.clear()
	var default_size_index: int = -1

	for grid_s in range(_selected_mode_config.min_grid_size, _selected_mode_config.max_grid_size + 1):
		var text: String = "%dx%d" % [grid_s, grid_s]
		_grid_size_option_button.add_item(text)
		_grid_size_option_button.set_item_metadata(-1, grid_s)

		if grid_s == _selected_mode_config.default_grid_size:
			default_size_index = _grid_size_option_button.item_count - 1

	if default_size_index != -1:
		_grid_size_option_button.select(default_size_index)
		_on_grid_size_selected(default_size_index)

	_start_game_button.disabled = false


func _update_high_score_label() -> void:
	var mode_id: String = _selected_mode_config.resource_path.get_file().get_basename()
	var high_score: int = SaveManager.get_high_score(mode_id, _current_grid_size)
	_info_score_label.text = "\n在 %dx%d 尺寸下的最高分：%d" % [_current_grid_size, _current_grid_size, high_score]


func _update_pagination_buttons_visibility() -> void:
	_pagination_container.visible = _total_pages > 1


func _generate_and_display_new_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_line_edit.text = str(rng.randi())


func _update_grid_size_and_ui(index: int) -> void:
	if index < 0 or index >= _grid_size_option_button.item_count:
		return
	_current_grid_size = _grid_size_option_button.get_item_metadata(index)
	if is_instance_valid(_selected_mode_config):
		_update_high_score_label()


# --- 信号处理函数 ---

func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()


func _on_mode_card_focused(config_path: String) -> void:
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	_selected_mode_config = load(config_path)
	_update_ui_for_selection()


func _on_grid_size_focused(index: int) -> void:
	_grid_size_option_button.select(index)
	_update_grid_size_and_ui(index)


func _on_grid_size_selected(index: int) -> void:
	_update_grid_size_and_ui(index)


func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("无法开始游戏：没有选中的模式。")
		return

	var seed_text: String = _seed_line_edit.text
	var seed_value: int = 0
	if seed_text.is_empty():
		seed_value = int(Time.get_unix_time_from_system())
	else:
		seed_value = int(seed_text) if seed_text.is_valid_int() else seed_text.hash()

	GlobalGameManager.select_mode_and_start(
		_selected_mode_config.resource_path,
		game_play_scene,
		_current_grid_size,
		seed_value
	)


func _on_refresh_seed_button_pressed() -> void:
	_generate_and_display_new_seed()


func _on_prev_page_pressed() -> void:
	if _total_pages <= 1:
		return

	_current_page = (_current_page - 1 + _total_pages) % _total_pages
	_populate_mode_list()


func _on_next_page_pressed() -> void:
	if _total_pages <= 1:
		return

	_current_page = (_current_page + 1) % _total_pages
	_populate_mode_list()
