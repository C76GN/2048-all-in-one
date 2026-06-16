## ModeSelection: 模式选择界面的 UI 控制器。
##
## 负责动态展示可用模式、更新选中态、配置棋盘参数并启动游戏。
class_name ModeSelection
extends "res://scripts/ui/base/game_ui_controller.gd"


# --- 常量 ---

## 单个模式卡片 UI 场景。
const MODE_CARD_SCENE: PackedScene = preload("res://scenes/ui/mode_card.tscn")
const _CARD_REVEAL_OFFSET: Vector2 = Vector2(18.0, 0.0)
const _DETAIL_REVEAL_OFFSET: Vector2 = Vector2(10.0, 0.0)
const _DETAIL_REVEAL_STAGGER: float = 0.02
const _TEXT_PRIMARY_COLOR: Color = Color(0.96, 0.92, 0.84, 1.0)
const _TEXT_SECONDARY_COLOR: Color = Color(0.78, 0.82, 0.78, 0.92)
const _TEXT_MUTED_COLOR: Color = Color(0.68, 0.73, 0.72, 0.82)
const _TEXT_SHADOW_COLOR: Color = Color(0.025, 0.035, 0.060, 0.24)
const _FIELD_SURFACE_COLOR: Color = Color(0.055, 0.080, 0.120, 0.46)
const _FIELD_FOCUS_SURFACE_COLOR: Color = Color(0.075, 0.120, 0.150, 0.62)
const _FIELD_BORDER_COLOR: Color = Color(0.95, 0.88, 0.72, 0.10)
const _FIELD_FOCUS_BORDER_COLOR: Color = Color(0.93, 0.82, 0.58, 0.64)


# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_play_scene_path: String = ""

# --- 私有变量 ---

var _selected_mode_config: GameModeConfig = null
var _mode_config_paths: PackedStringArray = PackedStringArray()
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

	_load_mode_config_paths()
	_create_persistent_info_panel()
	_update_pagination_buttons_visibility()
	call_deferred(&"_apply_mode_selection_visual_system")

	var _connect_result_77: int = _back_button.pressed.connect(_on_back_button_pressed)
	var _connect_result_78: int = _grid_size_option_button.item_selected.connect(_on_grid_size_selected)
	var _connect_result_79: int = _start_game_button.pressed.connect(_on_start_game_button_pressed)
	var _connect_result_80: int = _refresh_seed_button.pressed.connect(_on_refresh_seed_button_pressed)
	var _connect_result_81: int = _prev_page_button.pressed.connect(_on_prev_page_button_pressed)
	var _connect_result_82: int = _next_page_button.pressed.connect(_on_next_page_button_pressed)
	var _connect_result_83: int = _grid_size_option_button.get_popup().id_focused.connect(_on_grid_size_focused)

	_generate_and_display_new_seed()
	_update_ui_text()
	await _update_list_and_focus(true)


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
	for child: Node in _mode_list_container.get_children():
		child.queue_free()

	await get_tree().process_frame

	if _total_pages > 0:
		var start_index: int = _current_page * _items_per_page
		var end_index: int = mini(start_index + _items_per_page, _mode_config_paths.size())
		for i: int in range(start_index, end_index):
			var config_path: String = _mode_config_paths[i]
			if config_path.is_empty():
				continue

			var card: ModeCard = MODE_CARD_SCENE.instantiate() as ModeCard
			_mode_list_container.add_child(card)
			card.setup(config_path)
			var _connect_result_121: int = card.card_focused.connect(_set_selected_mode_by_path)

	await get_tree().process_frame

	_setup_focus_neighbors()

	var cards: Array[ModeCard] = _get_mode_cards()
	if cards.is_empty():
		_selected_mode_config = null
		_show_default_info()
		_start_game_button.disabled = true
		return

	var first_card: ModeCard = cards[0]
	_set_selected_mode_by_path(first_card.get_config_path())
	if is_initial_load:
		first_card.grab_focus()
	_bind_and_reveal_mode_cards()


func _focus_last_selected_card() -> void:
	if not is_instance_valid(_selected_mode_config):
		return

	for card: ModeCard in _get_mode_cards():
		if card.get_config_path() == _selected_mode_config.resource_path:
			card.grab_focus()
			break


func _load_mode_config_paths() -> void:
	_mode_config_paths = GameModeConfigCacheUtility.get_config_paths()


func _create_persistent_info_panel() -> void:
	for child: Node in _left_panel_container.get_children():
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


func _apply_mode_selection_visual_system() -> void:
	_style_label(_page_title, _TEXT_PRIMARY_COLOR, 44, true)
	_style_label(_info_name_label, _TEXT_PRIMARY_COLOR, 24, true)
	_style_label(_info_desc_label, _TEXT_SECONDARY_COLOR, 16, false)
	_style_label(_info_score_label, _TEXT_MUTED_COLOR, 15, false)
	_style_label(_config_header_label, _TEXT_PRIMARY_COLOR, 24, true)
	_style_label(_grid_size_label, _TEXT_SECONDARY_COLOR, 16, false)
	_style_label(_seed_label, _TEXT_SECONDARY_COLOR, 16, false)
	_style_line_edit(_seed_line_edit)
	if is_instance_valid(_info_separator):
		_info_separator.modulate = Color(0.95, 0.88, 0.72, 0.28)


func _style_label(label: Label, color: Color, font_size: int, use_shadow: bool) -> void:
	if not is_instance_valid(label):
		return

	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if use_shadow:
		label.add_theme_color_override("font_shadow_color", _TEXT_SHADOW_COLOR)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 1)


func _style_line_edit(line_edit: LineEdit) -> void:
	if not is_instance_valid(line_edit):
		return

	line_edit.add_theme_stylebox_override(
		"normal",
		_create_field_style(_FIELD_SURFACE_COLOR, _FIELD_BORDER_COLOR, 1)
	)
	line_edit.add_theme_stylebox_override(
		"focus",
		_create_field_style(_FIELD_FOCUS_SURFACE_COLOR, _FIELD_FOCUS_BORDER_COLOR, 2)
	)
	line_edit.add_theme_stylebox_override(
		"read_only",
		_create_field_style(_FIELD_SURFACE_COLOR.darkened(0.08), _FIELD_BORDER_COLOR, 1)
	)
	line_edit.add_theme_color_override("font_color", _TEXT_PRIMARY_COLOR)
	line_edit.add_theme_color_override("font_placeholder_color", _TEXT_MUTED_COLOR)
	line_edit.add_theme_color_override("caret_color", _FIELD_FOCUS_BORDER_COLOR)


func _create_field_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	style.set_content_margin(SIDE_LEFT, 10.0)
	style.set_content_margin(SIDE_TOP, 7.0)
	style.set_content_margin(SIDE_RIGHT, 10.0)
	style.set_content_margin(SIDE_BOTTOM, 7.0)
	return style


func _setup_focus_neighbors() -> void:
	var cards: Array[ModeCard] = _get_mode_cards()
	if cards.is_empty():
		_back_button.focus_neighbor_bottom = _back_button.get_path()
		_prev_page_button.focus_neighbor_top = _back_button.get_path()
		_next_page_button.focus_neighbor_top = _back_button.get_path()
		return

	var first_card: ModeCard = cards[0]
	var last_card: ModeCard = cards[-1]

	for i: int in range(cards.size()):
		var current_card: ModeCard = cards[i]
		current_card.focus_neighbor_top = cards[i - 1].get_path() if i > 0 else _back_button.get_path()
		current_card.focus_neighbor_bottom = cards[i + 1].get_path() if i < cards.size() - 1 else _prev_page_button.get_path()
		current_card.focus_neighbor_right = _grid_size_option_button.get_path()

	_back_button.focus_neighbor_bottom = first_card.get_path()
	_prev_page_button.focus_neighbor_top = last_card.get_path()
	_next_page_button.focus_neighbor_top = last_card.get_path()


func _set_selected_mode_by_path(config_path: String) -> void:
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	var loaded_config: GameModeConfig = GameModeConfigCacheUtility.get_config(config_path)
	if not is_instance_valid(loaded_config):
		_selected_mode_config = null
		_show_default_info()
		return

	_selected_mode_config = loaded_config

	for card: ModeCard in _get_mode_cards():
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
	_reveal_selection_panels()


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
		for card: ModeCard in _get_mode_cards():
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

	for grid_size: int in range(_selected_mode_config.min_grid_size, _selected_mode_config.max_grid_size + 1):
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
	var save_system: SaveSystem = get_system(SaveSystem) as SaveSystem
	var high_score: int = save_system.get_high_score(mode_id, _current_grid_size) if save_system else 0
	_info_score_label.text = "\n" + tr("INFO_HIGH_SCORE_AT_SIZE") % [_current_grid_size, _current_grid_size, high_score]


func _update_pagination_buttons_visibility() -> void:
	if _mode_config_paths.is_empty():
		_total_pages = 0
	else:
		_total_pages = ceili(float(_mode_config_paths.size()) / float(_items_per_page))

	_pagination_container.visible = _total_pages > 1


func _generate_and_display_new_seed() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_seed_line_edit.text = str(rng.randi())


func _update_grid_size_and_ui(index: int) -> void:
	if index < 0 or index >= _grid_size_option_button.item_count:
		return

	_current_grid_size = GFVariantData.to_int(_grid_size_option_button.get_item_metadata(index), _current_grid_size)

	if is_instance_valid(_selected_mode_config):
		_update_high_score_label()


func _bind_and_reveal_mode_cards() -> void:
	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	if motion_utility.has_method("bind_interactive_controls"):
		var _bound_count: int = motion_utility.bind_interactive_controls(_mode_list_container)
	if motion_utility.has_method("play_children_reveal"):
		var _reveal_count: int = motion_utility.play_children_reveal(_mode_list_container, _CARD_REVEAL_OFFSET)


func _get_mode_cards() -> Array[ModeCard]:
	var cards: Array[ModeCard] = []
	for child: Node in _mode_list_container.get_children():
		if child is ModeCard:
			cards.append(child)
	return cards


func _reveal_selection_panels() -> void:
	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return
	if not motion_utility.has_method("play_children_reveal"):
		return

	var _left_reveal_count: int = motion_utility.play_children_reveal(_left_panel_container, _DETAIL_REVEAL_OFFSET, _DETAIL_REVEAL_STAGGER)
	var _right_reveal_count: int = motion_utility.play_children_reveal(_right_panel_container, _DETAIL_REVEAL_OFFSET, _DETAIL_REVEAL_STAGGER)


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
	var router: SceneRouterSystem = get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.return_to_main_menu()


func _on_grid_size_focused(index: int) -> void:
	_grid_size_option_button.select(index)
	_update_grid_size_and_ui(index)


func _on_grid_size_selected(index: int) -> void:
	_update_grid_size_and_ui(index)


func _on_prev_page_button_pressed() -> void:
	await _change_page(-1)


func _on_next_page_button_pressed() -> void:
	await _change_page(1)


func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("[ModeSelection] %s" % tr("ERR_NO_MODE_SELECTED"))
		return
	if game_play_scene_path.is_empty():
		push_error("[ModeSelection] game_play_scene_path 未配置。")
		return

	var seed_text: String = _seed_line_edit.text
	var seed_value: int = 0

	if seed_text.is_empty():
		seed_value = int(Time.get_unix_time_from_system())
	else:
		seed_value = seed_text.to_int() if seed_text.is_valid_int() else seed_text.hash()

	var app_config: AppConfigModel = get_model(AppConfigModel) as AppConfigModel
	if app_config:
		app_config.selected_mode_config_path.set_value(_selected_mode_config.resource_path)
		app_config.selected_grid_size.set_value(_current_grid_size)
		app_config.selected_seed.set_value(seed_value)

	var seed_util: GFSeedUtility = get_utility(GFSeedUtility) as GFSeedUtility
	if seed_util:
		seed_util.set_global_seed(seed_value)

	var router: SceneRouterSystem = get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.goto_scene(game_play_scene_path)


func _on_refresh_seed_button_pressed() -> void:
	_generate_and_display_new_seed()
