## BoardEditorDialog: 玩家绘制、校验、保存并选择自定义棋盘的 GF UI 路由面板。
class_name BoardEditorDialog
extends GameUiController


# --- 信号 ---

signal topology_applied(topology: BoardTopology)


# --- 常量 ---

const _HISTORY_LIMIT: int = 128
const _INPUT_CONTEXT: GFInputContext = preload(
	"res://features/board_editor/resources/input/board_editor_input_context.tres"
)
const _UNDO_ACTION: StringName = &"board_editor_undo"
const _REDO_ACTION: StringName = &"board_editor_redo"


# --- 私有变量 ---

var _topology_template: BoardTopologyTemplate
var _initial_topology: BoardTopology
var _draft: BoardTopologyDraftModel
var _history: GFCommandHistoryUtility
var _custom_board_system: CustomBoardSystem
var _input_mapping: GFInputMappingUtility
var _signal_utility: GFSignalUtility
var _saved_boards: Array[CustomBoardData] = []
var _selected_saved_board_id: String = ""
var _configured: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = %TitleLabel
@onready var _canvas_hint_label: Label = %CanvasHintLabel
@onready var _tool_title_label: Label = %ToolTitle
@onready var _tool_info_label: Label = %ToolInfo
@onready var _brush_button: Button = %BrushButton
@onready var _eraser_button: Button = %EraserButton
@onready var _undo_button: Button = %UndoButton
@onready var _redo_button: Button = %RedoButton
@onready var _rectangle_button: Button = %RectangleButton
@onready var _cross_button: Button = %CrossButton
@onready var _normalize_button: Button = %NormalizeButton
@onready var _clear_button: Button = %ClearButton
@onready var _canvas: BoardEditorCanvas = %BoardEditorCanvas
@onready var _validation_label: Label = %ValidationLabel
@onready var _library_title_label: Label = %LibraryTitleLabel
@onready var _saved_board_list: ItemList = %SavedBoardList
@onready var _saved_board_detail_label: Label = %SavedBoardDetailLabel
@onready var _board_name_edit: LineEdit = %BoardNameEdit
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _delete_button: Button = %DeleteButton
@onready var _cancel_button: Button = %CancelButton
@onready var _apply_button: Button = %ApplyButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_history = GFCommandHistoryUtility.new()
	_history.max_history_size = _HISTORY_LIMIT
	_history.init()
	_custom_board_system = _get_custom_board_system()
	_input_mapping = _get_input_mapping_utility()
	_signal_utility = _get_signal_utility()
	if is_instance_valid(_input_mapping):
		_input_mapping.enable_context(_INPUT_CONTEXT, 600)
	_setup_tool_button_group()
	_connect_signals()
	_apply_canvas_theme()
	_update_ui_text()
	_initialize_editor()


func _exit_tree() -> void:
	if is_instance_valid(_input_mapping):
		_input_mapping.disable_context(_INPUT_CONTEXT)
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	if is_instance_valid(_history):
		_history.dispose()
	_history = null
	_custom_board_system = null
	_input_mapping = null
	_signal_utility = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_button_pressed()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_instance_valid(_input_mapping) or _is_text_editing_focused():
		return
	if _input_mapping.consume_action(_UNDO_ACTION):
		_on_undo_button_pressed()
	elif _input_mapping.consume_action(_REDO_ACTION):
		_on_redo_button_pressed()


# --- 公共方法 ---

## 由 GFUIRouterUtility 在面板入栈前注入本次编辑上下文。
## @param topology_template: 当前模式允许的棋盘拓扑范围。
## @param initial_topology: 本次编辑的初始棋盘形状。
func configure(
	topology_template: BoardTopologyTemplate,
	initial_topology: BoardTopology
) -> void:
	_topology_template = topology_template
	_initial_topology = initial_topology
	_configured = is_instance_valid(topology_template)
	if is_node_ready():
		_initialize_editor()


# --- 私有/辅助方法 ---

func _initialize_editor() -> void:
	if not is_node_ready() or not _configured:
		return
	_draft = BoardTopologyDraftModel.new()
	if not _draft.configure(_topology_template, _initial_topology):
		_apply_button.disabled = true
		_validation_label.text = tr("BOARD_EDITOR_INVALID_TEMPLATE")
		return
	_connect_managed_signal(_draft.changed, _on_draft_changed)
	_history.clear()
	_canvas.set_grid_size(_draft.get_canvas_size())
	_canvas.set_active_cells(_draft.get_active_cells())
	_brush_button.set_pressed_no_signal(true)
	_canvas.set_brush_active(true)
	_board_name_edit.text = tr("BOARD_EDITOR_DEFAULT_NAME")
	_refresh_saved_boards()
	_refresh_draft_state()
	_canvas.grab_focus()


func _setup_tool_button_group() -> void:
	var tool_group: ButtonGroup = ButtonGroup.new()
	tool_group.allow_unpress = false
	_brush_button.button_group = tool_group
	_eraser_button.button_group = tool_group
	_brush_button.toggle_mode = true
	_eraser_button.toggle_mode = true


func _connect_signals() -> void:
	_connect_managed_signal(_brush_button.pressed, _on_brush_button_pressed)
	_connect_managed_signal(_eraser_button.pressed, _on_eraser_button_pressed)
	_connect_managed_signal(_undo_button.pressed, _on_undo_button_pressed)
	_connect_managed_signal(_redo_button.pressed, _on_redo_button_pressed)
	_connect_managed_signal(_rectangle_button.pressed, _on_rectangle_button_pressed)
	_connect_managed_signal(_cross_button.pressed, _on_cross_button_pressed)
	_connect_managed_signal(_normalize_button.pressed, _on_normalize_button_pressed)
	_connect_managed_signal(_clear_button.pressed, _on_clear_button_pressed)
	_connect_managed_signal(_canvas.cells_edited, _on_canvas_cells_edited)
	_connect_managed_signal(_saved_board_list.item_selected, _on_saved_board_selected)
	_connect_managed_signal(_saved_board_list.item_activated, _on_saved_board_activated)
	_connect_managed_signal(_save_button.pressed, _on_save_button_pressed)
	_connect_managed_signal(_load_button.pressed, _on_load_button_pressed)
	_connect_managed_signal(_delete_button.pressed, _on_delete_button_pressed)
	_connect_managed_signal(_cancel_button.pressed, _on_cancel_button_pressed)
	_connect_managed_signal(_apply_button.pressed, _on_apply_button_pressed)


func _connect_managed_signal(source_signal: Signal, callback: Callable) -> void:
	if not is_instance_valid(_signal_utility):
		push_error("[BoardEditorDialog] 缺少 GFSignalUtility，无法连接编辑器控件。")
		return
	var _connection: GFSignalConnection = _signal_utility.connect_signal(
		source_signal,
		callback,
		self
	)


func _is_text_editing_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _apply_canvas_theme() -> void:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if not is_instance_valid(theme_utility):
		return
	var game_theme: GameTheme = theme_utility.get_current_visual_theme()
	if not is_instance_valid(game_theme):
		return
	_canvas.apply_visual_theme(game_theme.board_theme, game_theme.ui_palette)


func _execute_cells_edit(next_cells: Array[Vector2i], action_name: String) -> void:
	if not is_instance_valid(_draft) or not is_instance_valid(_history):
		return
	var command: BoardDraftEditCommand = BoardDraftEditCommand.new().configure(
		_draft,
		next_cells,
		action_name
	)
	var _execute_result: Variant = await _history.execute_command(command)
	_refresh_history_buttons()


func _make_edited_cells(cells: Array[Vector2i], active: bool) -> Array[Vector2i]:
	var lookup: Dictionary = {}
	for cell: Vector2i in _draft.get_active_cells():
		lookup[cell] = true
	for cell: Vector2i in cells:
		if active:
			lookup[cell] = true
		else:
			var _cell_removed: bool = lookup.erase(cell)
	var result: Array[Vector2i] = []
	for cell_value: Variant in lookup.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			result.append(cell)
	result.sort_custom(_is_row_major_before)
	return result


func _make_default_rectangle_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_instance_valid(_topology_template):
		return result
	var rectangle_size: Vector2i = _topology_template.default_size
	for y: int in range(rectangle_size.y):
		for x: int in range(rectangle_size.x):
			result.append(Vector2i(x, y))
	return result


func _make_cross_cells() -> Array[Vector2i]:
	if not is_instance_valid(_topology_template):
		return []
	var maximum_side: int = mini(_topology_template.max_size.x, _topology_template.max_size.y)
	var preferred_side: int = maxi(_topology_template.default_size.x, _topology_template.default_size.y)
	if preferred_side % 2 == 0:
		preferred_side += 1
	var minimum_side: int = maxi(_topology_template.min_size.x, _topology_template.min_size.y)
	var side: int = clampi(preferred_side, minimum_side, maximum_side)
	if side % 2 == 0:
		side -= 1
	if side <= 0:
		return []
	return BoardTopology.create_cross(floori(float(side - 1) / 2.0)).get_active_cells()


func _refresh_draft_state() -> void:
	if not is_instance_valid(_draft):
		return
	_canvas.set_active_cells(_draft.get_active_cells())
	var state: Dictionary = _draft.get_validation_state()
	var valid: bool = GFVariantData.get_option_bool(state, "valid")
	var reason: StringName = GFVariantData.get_option_string_name(state, "reason")
	var bounds: Vector2i = GFVariantData.get_option_value(state, "bounds_size", Vector2i.ZERO)
	var cell_count: int = GFVariantData.get_option_int(state, "cell_count")
	var component_count: int = GFVariantData.get_option_int(state, "component_count")
	match reason:
		&"empty":
			_validation_label.text = tr("BOARD_EDITOR_STATUS_EMPTY")
		&"template_rejected":
			_validation_label.text = tr("BOARD_EDITOR_STATUS_REJECTED") % [bounds.x, bounds.y, cell_count]
		&"disconnected":
			_validation_label.text = tr("BOARD_EDITOR_STATUS_DISCONNECTED") % [bounds.x, bounds.y, cell_count, component_count]
		_:
			_validation_label.text = tr("BOARD_EDITOR_STATUS_VALID") % [bounds.x, bounds.y, cell_count]
	_apply_button.disabled = not valid
	_save_button.disabled = not valid or not is_instance_valid(_custom_board_system)
	_refresh_history_buttons()


func _refresh_history_buttons() -> void:
	if not is_instance_valid(_history):
		_undo_button.disabled = true
		_redo_button.disabled = true
		return
	_undo_button.disabled = not _history.can_undo()
	_redo_button.disabled = not _history.can_redo()


func _refresh_saved_boards(preferred_id: String = "") -> void:
	_saved_boards.clear()
	if is_instance_valid(_custom_board_system):
		_saved_boards = _custom_board_system.load_custom_boards()
	var items: Array[Dictionary] = []
	var preferred_index: int = -1
	for custom_board: CustomBoardData in _saved_boards:
		var compatible: bool = _topology_template.accepts_topology(custom_board.topology)
		var suffix: String = "" if compatible else tr("BOARD_EDITOR_INCOMPATIBLE_SUFFIX")
		items.append({
			"text": "%s  ·  %s%s" % [custom_board.display_name, custom_board.topology.get_size_label(), suffix],
			"id": items.size(),
			"metadata": custom_board.custom_board_id,
		})
		if custom_board.custom_board_id == preferred_id:
			preferred_index = items.size() - 1
	var _written_count: int = GFItemListBinder.write_items(_saved_board_list, items, {
		"text_key": &"text",
		"id_key": &"id",
		"metadata_key": &"metadata",
	})
	_selected_saved_board_id = ""
	if preferred_index >= 0:
		_saved_board_list.select(preferred_index)
		_on_saved_board_selected(preferred_index)
	else:
		_update_saved_board_controls(null)


func _get_selected_saved_board() -> CustomBoardData:
	if _selected_saved_board_id.is_empty():
		return null
	for custom_board: CustomBoardData in _saved_boards:
		if custom_board.custom_board_id == _selected_saved_board_id:
			return custom_board
	return null


func _update_saved_board_controls(custom_board: CustomBoardData) -> void:
	var exists: bool = custom_board != null
	var compatible: bool = exists and _topology_template.accepts_topology(custom_board.topology)
	_load_button.disabled = not compatible
	_delete_button.disabled = not exists
	if not exists:
		_saved_board_detail_label.text = tr("BOARD_EDITOR_LIBRARY_EMPTY")
		return
	_saved_board_detail_label.text = tr("BOARD_EDITOR_LIBRARY_DETAIL") % [
		custom_board.topology.get_size_label(),
		custom_board.topology.get_cell_count(),
		_draft_component_count(custom_board.topology),
	]


func _draft_component_count(topology: BoardTopology) -> int:
	var probe: BoardTopologyDraftModel = BoardTopologyDraftModel.new()
	if not probe.configure(_topology_template, topology):
		return 0
	return probe.get_connected_component_count()


func _update_ui_text() -> void:
	if not is_node_ready():
		return
	_title_label.text = tr("BOARD_EDITOR_TITLE")
	_canvas_hint_label.text = tr("BOARD_EDITOR_CANVAS_HINT")
	_tool_title_label.text = tr("BOARD_EDITOR_TOOL_TITLE")
	_tool_info_label.text = tr("BOARD_EDITOR_COMPONENT_HINT")
	_brush_button.text = tr("BOARD_EDITOR_TOOL_BRUSH")
	_eraser_button.text = tr("BOARD_EDITOR_TOOL_ERASER")
	_undo_button.text = tr("BOARD_EDITOR_UNDO")
	_redo_button.text = tr("BOARD_EDITOR_REDO")
	_rectangle_button.text = tr("BOARD_EDITOR_PRESET_RECTANGLE")
	_cross_button.text = tr("BOARD_EDITOR_PRESET_CROSS")
	_normalize_button.text = tr("BOARD_EDITOR_NORMALIZE")
	_clear_button.text = tr("BOARD_EDITOR_CLEAR")
	_library_title_label.text = tr("BOARD_EDITOR_LIBRARY_TITLE")
	_board_name_edit.placeholder_text = tr("BOARD_EDITOR_NAME_PLACEHOLDER")
	_save_button.text = tr("BOARD_EDITOR_SAVE")
	_load_button.text = tr("BOARD_EDITOR_LOAD")
	_delete_button.text = tr("BOARD_EDITOR_DELETE")
	_cancel_button.text = tr("UI_CANCEL")
	_apply_button.text = tr("BOARD_EDITOR_APPLY")
	if is_instance_valid(_draft):
		_refresh_saved_boards(_selected_saved_board_id)
		_refresh_draft_state()


func _get_custom_board_system() -> CustomBoardSystem:
	var system_value: Object = get_system(CustomBoardSystem)
	if system_value is CustomBoardSystem:
		var system: CustomBoardSystem = system_value
		return system
	return null


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)


# --- 信号处理函数 ---

func _on_draft_changed() -> void:
	_refresh_draft_state()


func _on_brush_button_pressed() -> void:
	_canvas.set_brush_active(true)


func _on_eraser_button_pressed() -> void:
	_canvas.set_brush_active(false)


func _on_canvas_cells_edited(cells: Array[Vector2i], active: bool) -> void:
	await _execute_cells_edit(
		_make_edited_cells(cells, active),
		tr("BOARD_EDITOR_ACTION_DRAW") if active else tr("BOARD_EDITOR_ACTION_ERASE")
	)


func _on_undo_button_pressed() -> void:
	if is_instance_valid(_history):
		var _undone: bool = _history.undo_last()
	_refresh_history_buttons()


func _on_redo_button_pressed() -> void:
	if is_instance_valid(_history):
		var _redone: bool = _history.redo()
	_refresh_history_buttons()


func _on_rectangle_button_pressed() -> void:
	await _execute_cells_edit(_make_default_rectangle_cells(), tr("BOARD_EDITOR_ACTION_RECTANGLE"))


func _on_cross_button_pressed() -> void:
	await _execute_cells_edit(_make_cross_cells(), tr("BOARD_EDITOR_ACTION_CROSS"))


func _on_normalize_button_pressed() -> void:
	await _execute_cells_edit(_draft.get_normalized_cells(), tr("BOARD_EDITOR_ACTION_NORMALIZE"))


func _on_clear_button_pressed() -> void:
	await _execute_cells_edit([], tr("BOARD_EDITOR_ACTION_CLEAR"))


func _on_saved_board_selected(index: int) -> void:
	if index < 0 or index >= _saved_board_list.item_count:
		return
	_selected_saved_board_id = GFVariantData.to_text(_saved_board_list.get_item_metadata(index))
	_update_saved_board_controls(_get_selected_saved_board())


func _on_saved_board_activated(index: int) -> void:
	_on_saved_board_selected(index)
	await _on_load_button_pressed()


func _on_save_button_pressed() -> void:
	if not is_instance_valid(_custom_board_system) or not is_instance_valid(_draft):
		return
	var topology: BoardTopology = _draft.create_topology()
	if topology == null:
		return
	var custom_board: CustomBoardData = CustomBoardData.new()
	custom_board.display_name = _board_name_edit.text
	custom_board.topology = topology
	var save_error: Error = _custom_board_system.save_custom_board(custom_board)
	if save_error != OK:
		_saved_board_detail_label.text = tr("BOARD_EDITOR_SAVE_FAILED") % save_error
		return
	_board_name_edit.text = custom_board.display_name
	_refresh_saved_boards(custom_board.custom_board_id)


func _on_load_button_pressed() -> void:
	var custom_board: CustomBoardData = _get_selected_saved_board()
	if custom_board == null or not _topology_template.accepts_topology(custom_board.topology):
		return
	_board_name_edit.text = custom_board.display_name
	await _execute_cells_edit(custom_board.topology.get_active_cells(), tr("BOARD_EDITOR_ACTION_LOAD"))


func _on_delete_button_pressed() -> void:
	if not is_instance_valid(_custom_board_system) or _selected_saved_board_id.is_empty():
		return
	var delete_error: Error = _custom_board_system.delete_custom_board(_selected_saved_board_id)
	if delete_error != OK:
		_saved_board_detail_label.text = tr("BOARD_EDITOR_DELETE_FAILED") % delete_error
		return
	_refresh_saved_boards()


func _on_cancel_button_pressed() -> void:
	var _closed: bool = _close_current_popup_route(GameUiRouterUtility.ROUTE_BOARD_EDITOR)


func _on_apply_button_pressed() -> void:
	if not is_instance_valid(_draft):
		return
	var topology: BoardTopology = _draft.create_topology()
	if topology == null:
		return
	topology_applied.emit(topology)
	var _closed: bool = _close_current_popup_route(GameUiRouterUtility.ROUTE_BOARD_EDITOR)
