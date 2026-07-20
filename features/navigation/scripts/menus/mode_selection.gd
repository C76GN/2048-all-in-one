## ModeSelection: 模式选择界面的 UI 控制器。
##
## 负责动态展示可用模式、更新选中态、配置棋盘参数并启动游戏。
class_name ModeSelection
extends GameUiController


# --- 常量 ---

## 单个模式卡片 UI 场景。
const MODE_CARD_SCENE: PackedScene = preload("res://features/navigation/scenes/ui/mode_card.tscn")
const _CARD_REVEAL_OFFSET: Vector2 = Vector2(18.0, 0.0)
const _DETAIL_REVEAL_OFFSET: Vector2 = Vector2(10.0, 0.0)
const _DETAIL_REVEAL_STAGGER: float = 0.02
const _STATS_EMPTY_FORMAT_FALLBACK: String = "在 %dx%d 尺寸下的最高分：%d\n暂无完整对局统计"
const _STATS_SUMMARY_FORMAT_FALLBACK: String = "在 %dx%d 尺寸下的最高分：%d\n游玩 %d 局 · 最佳步数 %s · 最大方块 %s\n平均：%s 分 · %s 步\n最近一局：%d 分 · %s 步"
const _STATS_SUMMARY_WITH_TARGET_FORMAT_FALLBACK: String = "在 %dx%d 尺寸下的最高分：%d\n游玩 %d 局 · 最佳步数 %s · 最大方块 %s\n目标 %d：达成 %d 次 · %d%%\n平均：%s 分 · %s 步\n最近一局：%d 分 · %s 步"
# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_play_scene_path: String = ""

# --- 私有变量 ---

var _selected_mode_config: GameModeConfig = null
var _mode_config_paths: PackedStringArray = PackedStringArray()
var _current_board_size: Vector2i = Vector2i(4, 4)
var _current_board_topology: BoardTopology = null
var _custom_board_option_index: int = -1
var _items_per_page: int = 5
var _current_page: int = 0
var _total_pages: int = 0
var _mode_catalog: GameModeCatalogUtility = null

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
@onready var _edit_board_button: Button = %EditBoardButton
@onready var _seed_line_edit: LineEdit = %SeedLineEdit
@onready var _refresh_seed_button: Button = %RefreshSeedButton
@onready var _prev_page_button: Button = %PrevPageButton
@onready var _next_page_button: Button = %NextPageButton
@onready var _pagination_container: HBoxContainer = _get_parent_hbox(_prev_page_button)

@onready var _config_header_label: Label = _get_child_label(_right_panel_container, "Label")
@onready var _grid_size_label: Label = _get_sibling_label(_grid_size_option_button)
@onready var _seed_label: Label = _get_sibling_label(_seed_line_edit)


# --- Godot 生命周期方法 ---

func _ready() -> void:
	if is_instance_valid(_seed_line_edit):
		_seed_line_edit.placeholder_text = tr("HINT_SEED_PLACEHOLDER")

	_mode_catalog = _get_mode_catalog_utility()
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
	var _connect_result_84: int = _edit_board_button.pressed.connect(_on_edit_board_button_pressed)

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

			var card: ModeCard = _create_mode_card()
			if not is_instance_valid(card):
				continue
			var mode_config: GameModeConfig = _get_mode_config(config_path)
			if not is_instance_valid(mode_config):
				continue
			_mode_list_container.add_child(card)
			card.setup(config_path, mode_config, _get_ui_style_utility())
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
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog()
	if not is_instance_valid(mode_catalog):
		push_error("[ModeSelection] GameModeCatalogUtility 未注册，无法加载模式列表。")
		_mode_config_paths = PackedStringArray()
		return

	_mode_config_paths = mode_catalog.get_registered_config_paths()


func _create_persistent_info_panel() -> void:
	for child: Node in _left_panel_container.get_children():
		child.queue_free()

	_info_name_label = Label.new()
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
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style_utility):
		push_error("[ModeSelection] 缺少 GameUiStyleUtility，无法应用模式选择语义样式。")
		return

	style_utility.style_label(_page_title, GameUiStyleUtility.TextRole.PRIMARY, 44, true)
	style_utility.style_label(_info_name_label, GameUiStyleUtility.TextRole.PRIMARY, 24, true)
	style_utility.style_label(_info_desc_label, GameUiStyleUtility.TextRole.SECONDARY, 16)
	style_utility.style_label(_info_score_label, GameUiStyleUtility.TextRole.MUTED, 15)
	style_utility.style_label(_config_header_label, GameUiStyleUtility.TextRole.PRIMARY, 24, true)
	style_utility.style_label(_grid_size_label, GameUiStyleUtility.TextRole.SECONDARY, 16)
	style_utility.style_label(_seed_label, GameUiStyleUtility.TextRole.SECONDARY, 16)
	style_utility.style_line_edit(_seed_line_edit)
	style_utility.prepare_button(_grid_size_option_button)
	style_utility.style_button(
		_refresh_seed_button,
		GameUiStyleUtility.ButtonRole.ICON
	)
	var _dice_icon_applied: bool = style_utility.set_button_icon_from_asset(
		_refresh_seed_button,
		&"asset.texture.icon.randomize",
		24
	)
	style_utility.style_separator(_info_separator)


func _setup_focus_neighbors() -> void:
	var cards: Array[Control] = []
	for card: ModeCard in _get_mode_cards():
		cards.append(card)
	_apply_mode_focus_graph(cards)


func _apply_mode_focus_graph(cards: Array[Control]) -> void:
	var vertical_order: Array[Control] = [_back_button]
	for card: Control in cards:
		vertical_order.append(card)
		card.focus_neighbor_right = card.get_path_to(_grid_size_option_button)

	var uses_pagination: bool = is_instance_valid(_pagination_container) and _pagination_container.visible
	if uses_pagination:
		vertical_order.append(_prev_page_button)

	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(vertical_order, {
		"axis": GFControlFocusUtility.AXIS_VERTICAL,
		"wrap": true,
		"wire_tab_order": false,
		"preserve_unwired_directional_neighbors": true,
	})
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[ModeSelection] GF 模式焦点顺序应用失败：%s" % str(focus_report.get("issues", [])))

	if uses_pagination and not cards.is_empty():
		var last_card: Control = cards[-1]
		_next_page_button.focus_neighbor_top = _next_page_button.get_path_to(last_card)
		_next_page_button.focus_neighbor_bottom = _next_page_button.get_path_to(_back_button)
	else:
		_next_page_button.focus_neighbor_top = NodePath("")
		_next_page_button.focus_neighbor_bottom = NodePath("")


func _set_selected_mode_by_path(config_path: String) -> void:
	if is_instance_valid(_selected_mode_config) and _selected_mode_config.resource_path == config_path:
		return

	var loaded_config: GameModeConfig = _get_mode_config(config_path)
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

	_populate_right_panel()
	_populate_left_panel()
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
	if is_instance_valid(_edit_board_button):
		_edit_board_button.text = tr("BOARD_EDITOR_OPEN")
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
	_current_board_topology = null
	_current_board_size = Vector2i.ZERO
	_custom_board_option_index = -1
	_start_game_button.disabled = true
	_edit_board_button.disabled = true

	var default_size_index: int = -1
	var grid_size_items: Array[Dictionary] = []
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template):
		_write_option_items(_grid_size_option_button, grid_size_items)
		return
	_edit_board_button.disabled = not topology_template.allow_custom_topology

	var square_sizes: Array[int] = topology_template.get_square_size_options()
	if not square_sizes.is_empty():
		for side_length: int in square_sizes:
			var topology: BoardTopology = topology_template.create_topology(
				Vector2i(side_length, side_length)
			)
			if topology == null:
				continue
			var item_index: int = grid_size_items.size()
			grid_size_items.append(_make_option_item(topology.get_size_label(), topology, item_index))
			if side_length == topology_template.get_default_square_size():
				default_size_index = item_index
	else:
		var topology: BoardTopology = topology_template.create_topology()
		if topology != null:
			grid_size_items.append(_make_option_item(topology.get_size_label(), topology, 0))
			default_size_index = 0

	_write_option_items(_grid_size_option_button, grid_size_items)
	if default_size_index < 0:
		return
	_grid_size_option_button.select(default_size_index)
	_on_grid_size_selected(default_size_index)
	_start_game_button.disabled = not is_instance_valid(_current_board_topology)


func _update_high_score_label() -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(_info_score_label):
		return

	var mode_id: String = _selected_mode_config.resource_path.get_file().get_basename()
	var save_system: SaveSystem = _get_save_system()
	var board_key: String = _current_board_topology.get_stable_key() if is_instance_valid(_current_board_topology) else ""
	var high_score: int = save_system.get_high_score(mode_id, board_key) if is_instance_valid(save_system) else 0
	var stats: Dictionary = save_system.get_game_stats(mode_id, board_key) if is_instance_valid(save_system) else {}
	_info_score_label.text = _format_stats_text(high_score, stats)


func _update_pagination_buttons_visibility() -> void:
	if _mode_config_paths.is_empty():
		_total_pages = 0
	else:
		_total_pages = ceili(float(_mode_config_paths.size()) / float(_items_per_page))

	_pagination_container.visible = _total_pages > 1


func _generate_and_display_new_seed() -> void:
	var seed_utility: GFSeedUtility = _get_seed_utility()
	var clock_utility: GameClockUtility = _get_clock_utility()
	if not is_instance_valid(seed_utility) or not is_instance_valid(clock_utility):
		push_error("[ModeSelection] 缺少 GFSeedUtility 或 GameClockUtility，无法生成游戏种子。")
		return

	var seed_value: int = GFSeedUtility.make_stable_seed([
		"mode_selection",
		clock_utility.get_unix_timestamp(),
		clock_utility.get_tick_msec(),
		seed_utility.next_uint32(),
	])
	_seed_line_edit.text = str(seed_value)


func _update_grid_size_and_ui(index: int) -> void:
	if index < 0 or index >= _grid_size_option_button.item_count:
		return

	var topology_value: Variant = _grid_size_option_button.get_item_metadata(index)
	if not topology_value is BoardTopology:
		return
	_current_board_topology = topology_value
	_current_board_size = _current_board_topology.get_bounds_size()

	if is_instance_valid(_selected_mode_config):
		_update_high_score_label()


func _configure_board_editor(panel: Node) -> void:
	if not panel is BoardEditorDialog:
		push_error("[ModeSelection] 棋盘编辑器路由返回了错误面板类型。")
		return
	var editor: BoardEditorDialog = panel
	editor.configure(_selected_mode_config.board_topology_template, _current_board_topology)
	var _connect_result: int = editor.topology_applied.connect(_on_custom_board_topology_applied)


func _on_custom_board_topology_applied(topology: BoardTopology) -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(topology):
		return
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template) or not topology_template.accepts_topology(topology):
		push_error("[ModeSelection] 棋盘编辑器返回了当前模式不接受的拓扑。")
		return

	var topology_copy: BoardTopology = BoardTopology.from_dict(topology.to_dict())
	if topology_copy == null:
		return
	var items: Array[Dictionary] = []
	for index: int in range(_grid_size_option_button.item_count):
		items.append(_make_option_item(
			_grid_size_option_button.get_item_text(index),
			_grid_size_option_button.get_item_metadata(index),
			index
		))
	var custom_index: int = _custom_board_option_index
	if custom_index < 0 or custom_index >= items.size():
		custom_index = items.size()
		items.append({})
	items[custom_index] = _make_option_item(
		tr("BOARD_EDITOR_OPTION_FORMAT") % topology_copy.get_size_label(),
		topology_copy,
		custom_index
	)
	_custom_board_option_index = custom_index
	_write_option_items(_grid_size_option_button, items)
	_grid_size_option_button.select(custom_index)
	_update_grid_size_and_ui(custom_index)
	_start_game_button.disabled = false


func _write_option_items(option: OptionButton, items: Array[Dictionary]) -> void:
	var _written_count: int = GFItemListBinder.write_items(option, items, {
		"text_key": &"text",
		"id_key": &"id",
		"metadata_key": &"metadata",
	})


static func _make_option_item(text: String, metadata: Variant, id: int) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata,
		"id": id,
	}


func _bind_and_reveal_mode_cards() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var _bound_count: int = motion_utility.bind_interactive_controls(_mode_list_container)
	var _reveal_count: int = motion_utility.play_children_reveal(_mode_list_container, _CARD_REVEAL_OFFSET)


func _get_mode_cards() -> Array[ModeCard]:
	var cards: Array[ModeCard] = []
	for child: Node in _mode_list_container.get_children():
		if child is ModeCard:
			cards.append(child)
	return cards


func _get_parent_hbox(control: Control) -> HBoxContainer:
	if not is_instance_valid(control):
		return null

	var parent: Node = control.get_parent()
	if parent is HBoxContainer:
		var container: HBoxContainer = parent
		return container
	return null


func _get_sibling_label(control: Control) -> Label:
	if not is_instance_valid(control):
		return null

	var parent: Node = control.get_parent()
	return _get_child_label(parent, "Label")


func _get_child_label(parent: Node, child_path: NodePath) -> Label:
	if not is_instance_valid(parent):
		return null

	var label_node: Node = parent.get_node_or_null(child_path)
	if label_node is Label:
		var label: Label = label_node
		return label
	return null


func _format_stats_text(high_score: int, stats: Dictionary) -> String:
	var plays: int = GFVariantData.to_int(stats.get("plays", 0), 0)
	if plays <= 0:
		return "\n" + GameTextFormatUtility.format_template(
			tr("INFO_MODE_STATS_EMPTY"),
			_STATS_EMPTY_FORMAT_FALLBACK,
			[_current_board_size.x, _current_board_size.y, high_score]
		)

	var best_steps: int = GFVariantData.to_int(stats.get("best_steps", 0), 0)
	var max_tile: int = GFVariantData.to_int(stats.get("max_tile", 0), 0)
	var average_score: int = GFVariantData.to_int(stats.get("average_score", 0), 0)
	var average_steps: int = GFVariantData.to_int(stats.get("average_steps", 0), 0)
	var target_value: int = GFVariantData.to_int(stats.get("target_value", 0), 0)
	var target_reached_count: int = GFVariantData.to_int(stats.get("target_reached_count", 0), 0)
	var target_reached_rate: int = GFVariantData.to_int(stats.get("target_reached_rate", 0), 0)
	var last_score: int = GFVariantData.to_int(stats.get("last_score", 0), 0)
	var last_steps: int = GFVariantData.to_int(stats.get("last_steps", 0), 0)
	if target_value > 0:
		return "\n" + GameTextFormatUtility.format_template(
			tr("INFO_MODE_STATS_SUMMARY_WITH_TARGET"),
			_STATS_SUMMARY_WITH_TARGET_FORMAT_FALLBACK,
			[
				_current_board_size.x,
				_current_board_size.y,
				high_score,
				plays,
				_format_optional_stat(best_steps),
				_format_optional_stat(max_tile),
				target_value,
				target_reached_count,
				target_reached_rate,
				_format_optional_stat(average_score),
				_format_optional_stat(average_steps),
				last_score,
				_format_optional_stat(last_steps),
			]
		)
	return "\n" + GameTextFormatUtility.format_template(
		tr("INFO_MODE_STATS_SUMMARY"),
		_STATS_SUMMARY_FORMAT_FALLBACK,
		[
			_current_board_size.x,
			_current_board_size.y,
			high_score,
			plays,
			_format_optional_stat(best_steps),
			_format_optional_stat(max_tile),
			_format_optional_stat(average_score),
			_format_optional_stat(average_steps),
			last_score,
			_format_optional_stat(last_steps),
		]
	)


func _format_optional_stat(value: int) -> String:
	if value <= 0:
		return tr("UI_NONE")
	return str(value)


func _reveal_selection_panels() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
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


func _create_mode_card() -> ModeCard:
	var card_node: Node = MODE_CARD_SCENE.instantiate()
	if card_node is ModeCard:
		var card: ModeCard = card_node
		return card

	if is_instance_valid(card_node):
		push_error("[ModeSelection] 模式卡片场景必须实例化为 ModeCard。")
		card_node.queue_free()
	return null


func _get_game_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = _get_ui_motion_utility()
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_save_system() -> SaveSystem:
	var system_value: Object = get_system(SaveSystem)
	if system_value is SaveSystem:
		var save_system: SaveSystem = system_value
		return save_system
	return null


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_unix_timestamp() -> int:
	var clock: GameClockUtility = _get_clock_utility()
	if is_instance_valid(clock):
		return clock.get_unix_timestamp()

	push_error("[ModeSelection] 缺少 GameClockUtility，无法生成默认游戏种子。")
	return 0


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_mode_catalog() -> GameModeCatalogUtility:
	if is_instance_valid(_mode_catalog):
		return _mode_catalog

	_mode_catalog = _get_mode_catalog_utility()
	return _mode_catalog


func _get_mode_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog()
	if not is_instance_valid(mode_catalog):
		push_error("[ModeSelection] GameModeCatalogUtility 未注册，无法加载模式配置：%s。" % config_path)
		return null

	return mode_catalog.get_config(config_path)


# --- 信号处理函数 ---

func _on_back_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()


func _on_grid_size_focused(index: int) -> void:
	_grid_size_option_button.select(index)
	_update_grid_size_and_ui(index)


func _on_grid_size_selected(index: int) -> void:
	_update_grid_size_and_ui(index)


func _on_edit_board_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config) or not is_instance_valid(_current_board_topology):
		return
	var topology_template: BoardTopologyTemplate = _selected_mode_config.board_topology_template
	if not is_instance_valid(topology_template) or not topology_template.allow_custom_topology:
		return
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[ModeSelection] 缺少 GFUIRouterUtility，无法打开棋盘编辑器。")
		return
	var editor_panel: Node = ui_router.push_route(
		GameUiRouterUtility.ROUTE_BOARD_EDITOR,
		{},
		{},
		_configure_board_editor
	)
	if not is_instance_valid(editor_panel):
		push_error("[ModeSelection] GF UI 路由未能打开棋盘编辑器。")


func _on_prev_page_button_pressed() -> void:
	await _change_page(-1)


func _on_next_page_button_pressed() -> void:
	await _change_page(1)


func _on_start_game_button_pressed() -> void:
	if not is_instance_valid(_selected_mode_config):
		push_error("[ModeSelection] %s" % tr("ERR_NO_MODE_SELECTED"))
		return
	if not is_instance_valid(_current_board_topology):
		push_error("[ModeSelection] 当前模式没有可用的棋盘拓扑。")
		return
	if game_play_scene_path.is_empty():
		push_error("[ModeSelection] game_play_scene_path 未配置。")
		return

	var seed_text: String = _seed_line_edit.text
	var seed_value: int = 0

	if seed_text.is_empty():
		seed_value = _get_unix_timestamp()
	else:
		seed_value = seed_text.to_int() if seed_text.is_valid_int() else seed_text.hash()

	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.selected_mode_config_path.set_value(_selected_mode_config.resource_path)
		var selected_topology: Resource = _current_board_topology.duplicate(true)
		app_config.selected_board_topology.set_value(selected_topology)
		app_config.selected_seed.set_value(seed_value)

	var seed_util: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_util):
		seed_util.set_global_seed(seed_value)

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(game_play_scene_path)


func _on_refresh_seed_button_pressed() -> void:
	_generate_and_display_new_seed()
