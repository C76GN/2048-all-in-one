## ModeSelection: 模式选择界面的 UI 控制器。
##
## 负责动态展示可用模式、更新选中态、配置棋盘参数并启动游戏。
class_name ModeSelection
extends GFUIController


# --- 常量 ---

## 单个模式卡片 UI 场景。
const MODE_CARD_SCENE: PackedScene = preload("res://scenes/ui/mode_card.tscn")
const GAME_MODE_CONFIG_CACHE = preload("res://scripts/utilities/game_mode_config_cache.gd")


# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_play_scene_path: String = ""

## 可玩模式配置资源路径列表。
@export var mode_config_paths: Array[String] = []


# --- 私有变量 ---

var _selected_mode_config: GameModeConfig = null
var _current_grid_size: int = 4
var _items_per_page: int = 5
var _current_page: int = 0
var _total_pages: int = 0

var _info_name_label: Label
var _info_separator: HSeparator
var _info_desc_label: Label
var _info_score_label: Label


# --- @onready 变量 (节点引用) ---

@onready var _left_panel_container: VBoxContainer = %LeftColumn
@onready var _right_panel_container: VBoxContainer = %RightColumn
@onready var _page_title: Label = %PageTitle
@onready var _mode_list_container: VBoxContainer = %ModeListContainer
@onready var _back_button: Button = %BackButton
@onready var _start_game_button: Button = %StartGameButton
@onready var _grid_size_option_button: OptionButton = %GridSizeOptionButton
@onready var _seed_line_edit: LineEdit = %SeedLineEdit
@onready var _refresh_seed_button: Button = %RefreshSeedButton
@onready var _prev_page_button: Button = %PrevPageButton
@onready var _next_page_button: Button = %NextPageButton
@onready var _pagination_container: HBoxContainer = _prev_page_button.get_parent()

@onready var _config_header_label: Label = _right_panel_container.get_node("Label")
@onready var _grid_size_label: Label = _grid_size_option_button.get_parent().get_node("Label")
@onready var _seed_label: Label = _seed_line_edit.get_parent().get_node("Label")


# --- Godot 生命周期方法 ---

func _ready() -> void:
	if is_instance_valid(_seed_line_edit):
		_seed_line_edit.placeholder_text = tr("HINT_SEED_PLACEHOLDER")

	_sanitize_mode_config_paths()
	_create_persistent_info_panel()
	_update_pagination_buttons_visibility()

	_back_button.pressed.connect(_on_back_button_pressed)
	_grid_size_option_button.item_selected.connect(_on_grid_size_selected)
	_start_game_button.pressed.connect(_on_start_game_button_pressed)
	_refresh_seed_button.pressed.connect(_on_refresh_seed_button_pressed)
	_prev_page_button.pressed.connect(func(): _change_page(-1))
	_next_page_button.pressed.connect(func(): _change_page(1))
	_grid_size_option_button.get_popup().id_focused.connect(_on_grid_size_focused)

	_generate_and_display_new_seed()
	_update_ui_text()
	_update_list_and_focus(true)


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

func _update_list_and_focus(is_initial_load: bool = false) -> void:
	for child in _mode_list_container.get_children():
		child.queue_free()

	await get_tree().process_frame

	if _total_pages > 0:
		var start_index: int = _current_page * _items_per_page
		var end_index: int = mini(start_index + _items_per_page, mode_config_paths.size())
		for i in range(start_index, end_index):
			var config_path: String = mode_config_paths[i]
			if config_path.is_empty():
				continue

			var card := MODE_CARD_SCENE.instantiate() as ModeCard
			_mode_list_container.add_child(card)
			card.setup(config_path)
			card.card_focused.connect(_set_selected_mode_by_path)

	await get_tree().process_frame

	_setup_focus_neighbors()

	var cards: Array = _mode_list_container.get_children()
	if cards.is_empty():
		_selected_mode_config = null
		_show_default_info()
		_start_game_button.disabled = true
		return

	var first_card := cards[0] as ModeCard
	_set_selected_mode_by_path(first_card.get_config_path())
	if is_initial_load:
		first_card.grab_focus()


func _focus_last_selected_card() -> void:
	if not is_instance_valid(_selected_mode_config):
		return

	for card in _mode_list_container.get_children():
		if card is ModeCard and card.get_config_path() == _selected_mode_config.resource_path:
			card.grab_focus()
			break


func _sanitize_mode_config_paths() -> void:
	var valid_paths: Array[String] = []
	for config_path in mode_config_paths:
		if config_path.is_empty():
			continue

		if ResourceLoader.exists(config_path):
			valid_paths.append(config_path)
		else:
			push_warning("ModeSelection: Missing mode config resource: %s" % config_path)

	mode_config_paths = valid_paths


func _create_persistent_info_panel() -> void:
	for child in _left_panel_container.get_children():
		child.queue_free()

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


func _setup_focus_neighbors() -> void:
	var cards: Array = _mode_list_container.get_children()
	if cards.is_empty():
		_back_button.focus_neighbor_bottom = _back_button.get_path()
		_prev_page_button.focus_neighbor_top = _back_button.get_path()
		_next_page_button.focus_neighbor_top = _back_button.get_path()
		return

	var first_card: Control = cards[0]
	var last_card: Control = cards[-1]

	for i in range(cards.size()):
		var current_card: Control = cards[i]
		current_card.focus_neighbor_top = cards[i - 1].get_path() if i > 0 else _back_button.get_path()
		current_card.focus_neighbor_bottom = cards[i + 1].get_path() if i < cards.size() - 1 else _prev_page_button.get_path()
		current_card.focus_neighbor_right = _grid_size_option_button.get_path()

	_back_button.focus_neighbor_bottom = first_card.get_path()
	_prev_page_button.focus_neighbor_top = last_card.get_path()
	_next_page_button.focus_neighbor_top = last_card.get_path()


func _set_selected_mode_by_path(config_path: String) -> void:
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	var loaded_config: GameModeConfig = GAME_MODE_CONFIG_CACHE.get_config(config_path)
	if not is_instance_valid(loaded_config):
		_selected_mode_config = null
		_show_default_info()
		return

	_selected_mode_config = loaded_config

	for card_node in _mode_list_container.get_children():
		if card_node is ModeCard:
			var card := card_node as ModeCard
			card.set_selected(card.get_config_path() == config_path)

	_update_ui_for_selection()


func _update_ui_for_selection() -> void:
	if not is_instance_valid(_selected_mode_config):
		_show_default_info()
		return

	if not is_instance_valid(_info_name_label) or not is_instance_valid(_right_panel_container):
		return

	_info_name_label.visible = true
	if is_instance_valid(_info_separator):
		_info_separator.visible = true
	if is_instance_valid(_info_desc_label):
		_info_desc_label.visible = true
	if is_instance_valid(_info_score_label):
		_info_score_label.visible = true
	_right_panel_container.visible = true

	_populate_left_panel()
	_populate_right_panel()


func _show_default_info() -> void:
	if not is_instance_valid(_info_name_label) or not is_instance_valid(_right_panel_container):
		return

	_info_name_label.visible = false
	if is_instance_valid(_info_separator):
		_info_separator.visible = false
	if is_instance_valid(_info_desc_label):
		_info_desc_label.visible = false
	if is_instance_valid(_info_score_label):
		_info_score_label.visible = false
	_right_panel_container.visible = false
	if is_instance_valid(_start_game_button):
		_start_game_button.disabled = true


func _update_ui_text() -> void:
	if is_instance_valid(_page_title):
		_page_title.text = tr("TITLE_MODE_SELECTION")
	if is_instance_valid(_seed_line_edit):
		_seed_line_edit.placeholder_text = tr("HINT_SEED_PLACEHOLDER")
	if is_instance_valid(_prev_page_button):
		_prev_page_button.text = tr("UI_PREV_PAGE")
	if is_instance_valid(_next_page_button):
		_next_page_button.text = tr("UI_NEXT_PAGE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("UI_BACK")
	if is_instance_valid(_start_game_button):
		_start_game_button.text = tr("BTN_START_GAME")
	if is_instance_valid(_config_header_label):
		_config_header_label.text = tr("LABEL_MODE_CONFIG")
	if is_instance_valid(_grid_size_label):
		_grid_size_label.text = tr("LABEL_GRID_SIZE")
	if is_instance_valid(_seed_label):
		_seed_label.text = tr("LABEL_GAME_SEED")

	if is_instance_valid(_mode_list_container):
		for card in _mode_list_container.get_children():
			if card is ModeCard:
				card.update_text()

	_update_ui_for_selection()


func _populate_left_panel() -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(_info_name_label):
		return

	_info_name_label.text = tr(_selected_mode_config.mode_name)
	if is_instance_valid(_info_desc_label):
		_info_desc_label.text = tr(_selected_mode_config.mode_description)

	_update_high_score_label()


func _populate_right_panel() -> void:
	if not is_instance_valid(_selected_mode_config):
		return
	if not is_instance_valid(_grid_size_option_button) or not is_instance_valid(_start_game_button):
		return

	_grid_size_option_button.clear()
	var default_size_index: int = -1

	for grid_size in range(_selected_mode_config.min_grid_size, _selected_mode_config.max_grid_size + 1):
		var text: String = "%dx%d" % [grid_size, grid_size]
		_grid_size_option_button.add_item(text)
		var item_index: int = _grid_size_option_button.item_count - 1
		_grid_size_option_button.set_item_metadata(item_index, grid_size)
		if grid_size == _selected_mode_config.default_grid_size:
			default_size_index = item_index

	if default_size_index != -1:
		_grid_size_option_button.select(default_size_index)
		_on_grid_size_selected(default_size_index)

	_start_game_button.disabled = false


func _update_high_score_label() -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(_info_score_label):
		return

	var mode_id: String = _selected_mode_config.resource_path.get_file().get_basename()
	var save_system := get_system(SaveSystem) as SaveSystem
	var high_score: int = save_system.get_high_score(mode_id, _current_grid_size) if save_system else 0
	_info_score_label.text = "\n" + tr("INFO_HIGH_SCORE_AT_SIZE") % [_current_grid_size, _current_grid_size, high_score]


func _update_pagination_buttons_visibility() -> void:
	if mode_config_paths.is_empty():
		_total_pages = 0
	else:
		_total_pages = int(ceil(float(mode_config_paths.size()) / _items_per_page))

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


func _change_page(direction: int) -> void:
	if _total_pages <= 1:
		return

	if direction == -1:
		_current_page = (_current_page - 1 + _total_pages) % _total_pages
		_prev_page_button.grab_focus()
	else:
		_current_page = (_current_page + 1) % _total_pages
		_next_page_button.grab_focus()

	await _update_list_and_focus()


# --- 信号处理函数 ---

func _on_back_button_pressed() -> void:
	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.return_to_main_menu()


func _on_grid_size_focused(index: int) -> void:
	_grid_size_option_button.select(index)
	_update_grid_size_and_ui(index)


func _on_grid_size_selected(index: int) -> void:
	_update_grid_size_and_ui(index)


func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error(tr("ERR_NO_MODE_SELECTED"))
		return
	if game_play_scene_path.is_empty():
		push_error("ModeSelection: game_play_scene_path is not configured.")
		return

	var seed_text: String = _seed_line_edit.text
	var seed_value: int = 0

	if seed_text.is_empty():
		seed_value = int(Time.get_unix_time_from_system())
	else:
		seed_value = int(seed_text) if seed_text.is_valid_int() else seed_text.hash()

	var app_config := get_model(AppConfigModel) as AppConfigModel
	if app_config:
		app_config.selected_mode_config_path.set_value(_selected_mode_config.resource_path)
		app_config.selected_grid_size.set_value(_current_grid_size)
		app_config.selected_seed.set_value(seed_value)

	var seed_util := get_utility(GFSeedUtility) as GFSeedUtility
	if seed_util:
		seed_util.set_global_seed(seed_value)

	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.goto_scene(game_play_scene_path)


func _on_refresh_seed_button_pressed() -> void:
	_generate_and_display_new_seed()
