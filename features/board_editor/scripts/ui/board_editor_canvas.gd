## BoardEditorCanvas: 绘制并编辑稀疏棋盘草稿的轻量画布。
class_name BoardEditorCanvas
extends Control


# --- 信号 ---

signal cells_edited(cells: Array[Vector2i], active: bool)


# --- 导出变量 ---

@export var canvas_surface_color: Color = Color(0.9137255, 0.9019608, 0.8627451, 1.0)
@export var inactive_cell_color: Color = Color(0.11372549, 0.3254902, 0.3764706, 0.22)
@export var active_cell_color: Color = Color(0.94509804, 0.8862745, 0.74509805, 1.0)
@export var preview_cell_color: Color = Color(0.7529412, 0.5921569, 0.47843137, 0.9)
@export var grid_color: Color = Color(0.16470589, 0.10588235, 0.17254902, 0.72)


# --- 私有变量 ---

var _grid_size: Vector2i = Vector2i(8, 8)
var _active_cells: Dictionary = {}
var _brush_active: bool = true
var _stroke_active: bool = false
var _stroke_value: bool = true
var _stroke_button: MouseButton = MOUSE_BUTTON_NONE
var _stroke_cells: Dictionary = {}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _stroke_active:
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.button_index == _stroke_button and not mouse_button.pressed:
			_finish_stroke()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if (
			mouse_button.pressed
			and (mouse_button.button_index == MOUSE_BUTTON_LEFT or mouse_button.button_index == MOUSE_BUTTON_RIGHT)
		):
			_begin_stroke(mouse_button.position, mouse_button.button_index)
			accept_event()
	elif event is InputEventMouseMotion and _stroke_active:
		var mouse_motion: InputEventMouseMotion = event
		_append_stroke_cell(mouse_motion.position)
		accept_event()


func _draw() -> void:
	var geometry: Dictionary = _get_board_geometry()
	var board_rect: Rect2 = GFVariantData.get_option_value(geometry, "rect", Rect2())
	var cell_size: float = GFVariantData.get_option_float(geometry, "cell_size")
	if cell_size <= 0.0:
		return

	draw_rect(board_rect, canvas_surface_color, true)
	for cell_value: Variant in _active_cells.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			_draw_cell(cell, active_cell_color, board_rect.position, cell_size)
	for cell_value: Variant in _stroke_cells.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value
		var preview_color: Color = preview_cell_color
		if not _stroke_value:
			preview_color = inactive_cell_color
		_draw_cell(cell, preview_color, board_rect.position, cell_size)

	var line_width: float = 2.0 if cell_size >= 18.0 else 1.0
	for x: int in range(_grid_size.x + 1):
		var x_position: float = board_rect.position.x + float(x) * cell_size
		draw_line(
			Vector2(x_position, board_rect.position.y),
			Vector2(x_position, board_rect.end.y),
			grid_color,
			line_width
		)
	for y: int in range(_grid_size.y + 1):
		var y_position: float = board_rect.position.y + float(y) * cell_size
		draw_line(
			Vector2(board_rect.position.x, y_position),
			Vector2(board_rect.end.x, y_position),
			grid_color,
			line_width
		)
	draw_rect(board_rect, grid_color, false, maxf(line_width, 2.0))


# --- 公共方法 ---

## @param value: 画布可编辑网格的宽高。
func set_grid_size(value: Vector2i) -> void:
	_grid_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
	queue_redraw()


## @param cells: 当前草稿的完整活跃单元快照。
func set_active_cells(cells: Array[Vector2i]) -> void:
	_active_cells.clear()
	for cell: Vector2i in cells:
		_active_cells[cell] = true
	queue_redraw()


## @param value: true 使用画笔，false 使用橡皮擦。
func set_brush_active(value: bool) -> void:
	_brush_active = value


## @param board_theme: 当前主题的棋盘视觉资源。
## @param palette: 当前主题的 UI 色板。
func apply_visual_theme(board_theme: BoardTheme, palette: GameUiPalette) -> void:
	if is_instance_valid(board_theme):
		canvas_surface_color = board_theme.board_panel_color
		inactive_cell_color = board_theme.empty_cell_color.darkened(0.12)
		inactive_cell_color.a = 0.72
		active_cell_color = board_theme.board_highlight_color
		if active_cell_color.a < 0.7:
			active_cell_color.a = 0.92
		grid_color = board_theme.board_border_color
	if is_instance_valid(palette):
		preview_cell_color = palette.selected_surface_color
		preview_cell_color.a = 0.94
	queue_redraw()


# --- 私有/辅助方法 ---

func _begin_stroke(pointer_position: Vector2, button_index: MouseButton) -> void:
	_stroke_active = true
	_stroke_button = button_index
	_stroke_value = _brush_active if button_index == MOUSE_BUTTON_LEFT else false
	_stroke_cells.clear()
	grab_focus()
	_append_stroke_cell(pointer_position)


func _append_stroke_cell(pointer_position: Vector2) -> void:
	var cell: Vector2i = _position_to_cell(pointer_position)
	if cell.x < 0 or _stroke_cells.has(cell):
		return
	_stroke_cells[cell] = true
	queue_redraw()


func _finish_stroke() -> void:
	if not _stroke_active:
		return
	var cells: Array[Vector2i] = []
	for cell_value: Variant in _stroke_cells.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			cells.append(cell)
	cells.sort_custom(_is_row_major_before)
	var stroke_value: bool = _stroke_value
	_stroke_active = false
	_stroke_button = MOUSE_BUTTON_NONE
	_stroke_cells.clear()
	queue_redraw()
	if not cells.is_empty():
		cells_edited.emit(cells, stroke_value)


func _position_to_cell(pointer_position: Vector2) -> Vector2i:
	var geometry: Dictionary = _get_board_geometry()
	var board_rect: Rect2 = GFVariantData.get_option_value(geometry, "rect", Rect2())
	var cell_size: float = GFVariantData.get_option_float(geometry, "cell_size")
	if cell_size <= 0.0 or not board_rect.has_point(pointer_position):
		return Vector2i(-1, -1)
	var local_position: Vector2 = pointer_position - board_rect.position
	var cell: Vector2i = Vector2i(
		floori(local_position.x / cell_size),
		floori(local_position.y / cell_size)
	)
	if cell.x >= _grid_size.x or cell.y >= _grid_size.y:
		return Vector2i(-1, -1)
	return cell


func _get_board_geometry() -> Dictionary:
	var padding: float = 12.0
	var available_size: Vector2 = Vector2(
		maxf(size.x - padding * 2.0, 1.0),
		maxf(size.y - padding * 2.0, 1.0)
	)
	var cell_size: float = minf(
		available_size.x / float(_grid_size.x),
		available_size.y / float(_grid_size.y)
	)
	var board_size: Vector2 = Vector2(_grid_size) * cell_size
	return {
		"cell_size": cell_size,
		"rect": Rect2((size - board_size) * 0.5, board_size),
	}


func _draw_cell(cell: Vector2i, color: Color, origin: Vector2, cell_size: float) -> void:
	var inset: float = clampf(cell_size * 0.08, 1.0, 5.0)
	var cell_position: Vector2 = origin + Vector2(cell) * cell_size + Vector2(inset, inset)
	var cell_extent: Vector2 = Vector2.ONE * maxf(cell_size - inset * 2.0, 0.0)
	draw_rect(Rect2(cell_position, cell_extent), color, true)


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)
