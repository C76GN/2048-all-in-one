## BoardEditorCanvas: 绘制稀疏棋盘草稿的稳定世界画布。
##
## 输入仲裁由 BoardEditorViewportController 负责；本节点只维护可取消的笔画预览、
## 局部坐标到格子的映射和主题化绘制，因此可以安全置于缩放/平移世界节点下。
class_name BoardEditorCanvas
extends Control


# --- 信号 ---

signal cells_edited(cells: Array[Vector2i], active: bool)
signal content_rect_changed(content_rect: Rect2)


# --- 常量 ---

const _INVALID_CELL: Vector2i = Vector2i(-1, -1)


# --- 导出变量 ---

@export_range(24.0, 160.0, 1.0) var cell_size: float = 64.0
@export_range(0.0, 64.0, 1.0) var content_padding: float = 12.0
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
var _stroke_cells: Dictionary = {}
var _stroke_last_cell: Vector2i = _INVALID_CELL


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_sync_canvas_extent()
	queue_redraw()


func _draw() -> void:
	var board_rect: Rect2 = get_board_rect()
	if cell_size <= 0.0:
		return

	draw_rect(board_rect, canvas_surface_color, true)
	for cell_value: Variant in _active_cells.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			_draw_cell(cell, active_cell_color, board_rect.position)
	for cell_value: Variant in _stroke_cells.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value
		var preview_color: Color = preview_cell_color
		if not _stroke_value:
			preview_color = inactive_cell_color
		_draw_cell(cell, preview_color, board_rect.position)

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

## 设置画布可编辑网格的宽高，并更新稳定世界尺寸。
## @param value: 画布可编辑网格的宽高。
func set_grid_size(value: Vector2i) -> void:
	_grid_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
	cancel_stroke()
	_sync_canvas_extent()
	queue_redraw()


## 返回当前画布网格尺寸。
func get_grid_size() -> Vector2i:
	return _grid_size


## 返回包含留白的完整世界内容矩形。
func get_content_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size)


## 返回实际棋盘格区域，不包含外围留白。
func get_board_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * content_padding,
		Vector2(_grid_size) * cell_size
	)


## 返回指定格子的画布局部中心点。
## @param cell: 要查询中心点的网格坐标。
func get_cell_center(cell: Vector2i) -> Vector2:
	return get_board_rect().position + (Vector2(cell) + Vector2.ONE * 0.5) * cell_size


## 返回局部位置对应的格子；画布外返回 (-1, -1)。
## @param pointer_position: 编辑画布的局部指针位置。
func cell_at_position(pointer_position: Vector2) -> Vector2i:
	var board_rect: Rect2 = get_board_rect()
	if cell_size <= 0.0 or not board_rect.has_point(pointer_position):
		return _INVALID_CELL
	var local_position: Vector2 = pointer_position - board_rect.position
	var cell: Vector2i = Vector2i(
		floori(local_position.x / cell_size),
		floori(local_position.y / cell_size)
	)
	if cell.x >= _grid_size.x or cell.y >= _grid_size.y:
		return _INVALID_CELL
	return cell


## 替换当前草稿的完整活跃单元快照。
## @param cells: 当前草稿的完整活跃单元列表。
func set_active_cells(cells: Array[Vector2i]) -> void:
	_active_cells.clear()
	for cell: Vector2i in cells:
		_active_cells[cell] = true
	queue_redraw()


## true 使用画笔，false 使用橡皮擦。
## @param value: true 使用画笔，false 使用橡皮擦。
func set_brush_active(value: bool) -> void:
	_brush_active = value


## 返回当前工具是否为画笔。
func is_brush_active() -> bool:
	return _brush_active


## 开始一条可取消笔画。active 为 true 时绘制，否则擦除。
## @param pointer_position: 笔画起点的画布局部坐标。
## @param active: true 绘制格子，false 擦除格子。
func begin_stroke(pointer_position: Vector2, active: bool) -> bool:
	var first_cell: Vector2i = cell_at_position(pointer_position)
	if first_cell == _INVALID_CELL:
		return false
	_stroke_active = true
	_stroke_value = active
	_stroke_cells.clear()
	_stroke_last_cell = _INVALID_CELL
	append_stroke(pointer_position)
	return true


## 把当前位置及上一采样点之间经过的格子追加到当前笔画。
## @param pointer_position: 新采样点的画布局部坐标。
func append_stroke(pointer_position: Vector2) -> void:
	if not _stroke_active:
		return
	var next_cell: Vector2i = cell_at_position(pointer_position)
	if next_cell == _INVALID_CELL:
		return
	if _stroke_last_cell == _INVALID_CELL:
		_stroke_cells[next_cell] = true
	else:
		for cell: Vector2i in rasterize_grid_line(_stroke_last_cell, next_cell):
			_stroke_cells[cell] = true
	_stroke_last_cell = next_cell
	queue_redraw()


## 提交当前笔画并发出一次原子编辑请求。
func finish_stroke() -> void:
	if not _stroke_active:
		return
	var cells: Array[Vector2i] = []
	for cell_value: Variant in _stroke_cells.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			cells.append(cell)
	cells.sort_custom(_is_row_major_before)
	var stroke_value: bool = _stroke_value
	_reset_stroke()
	queue_redraw()
	if not cells.is_empty():
		cells_edited.emit(cells, stroke_value)


## 放弃当前笔画预览，不产生编辑命令。
func cancel_stroke() -> void:
	if not _stroke_active and _stroke_cells.is_empty():
		return
	_reset_stroke()
	queue_redraw()


## 返回当前是否存在尚未提交的笔画。
func is_stroke_active() -> bool:
	return _stroke_active


## 将两个格点之间的采样补全为连续 Bresenham 格线。
## @param start: 连续格线的起点。
## @param end: 连续格线的终点。
static func rasterize_grid_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var current: Vector2i = start
	var delta_x: int = absi(end.x - start.x)
	var delta_y: int = absi(end.y - start.y)
	var step_x: int = 1 if start.x < end.x else -1
	var step_y: int = 1 if start.y < end.y else -1
	var error: int = delta_x - delta_y
	while true:
		result.append(current)
		if current == end:
			break
		var doubled_error: int = error * 2
		if doubled_error > -delta_y:
			error -= delta_y
			current.x += step_x
		if doubled_error < delta_x:
			error += delta_x
			current.y += step_y
	return result


## 应用当前主题的棋盘视觉资源和 UI 色板。
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

func _sync_canvas_extent() -> void:
	var extent: Vector2 = Vector2(_grid_size) * cell_size + Vector2.ONE * content_padding * 2.0
	custom_minimum_size = extent
	size = extent
	content_rect_changed.emit(get_content_rect())


func _reset_stroke() -> void:
	_stroke_active = false
	_stroke_cells.clear()
	_stroke_last_cell = _INVALID_CELL


func _draw_cell(cell: Vector2i, color: Color, origin: Vector2) -> void:
	var inset: float = clampf(cell_size * 0.08, 1.0, 5.0)
	var cell_position: Vector2 = origin + Vector2(cell) * cell_size + Vector2(inset, inset)
	var cell_extent: Vector2 = Vector2.ONE * maxf(cell_size - inset * 2.0, 0.0)
	draw_rect(Rect2(cell_position, cell_extent), color, true)


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)
