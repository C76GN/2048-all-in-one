## TilePatternOverlay: 在方块表面绘制低对比度像素纹理。
##
## 纹理只承担类型识别和材质感，不参与文字可读性表达。
class_name TilePatternOverlay
extends Control


# --- 枚举 ---

enum PatternType {
	NONE,
	DIAMOND,
	CHECKER,
	SCALES,
	HALFTONE,
	DIAGONAL_HATCH,
	SPLIT_DIAGONAL,
	CONCENTRIC,
}


# --- 常量 ---

const _INK_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _PAPER_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 1.0)
const _CYAN_REGISTER_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
const _MAGENTA_REGISTER_COLOR: Color = Color(0.9607843, 0.6392157, 0.7882353, 1.0)
const _INNER_MARGIN: float = 8.0


# --- 私有变量 ---

var _pattern_type: PatternType = PatternType.NONE
var _pattern_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _highlight_color: Color = Color(1.0, 1.0, 1.0, 0.0)
var _registration_shadow_color: Color = Color(1.0, 1.0, 1.0, 0.0)
var _visual_layer_ids: Array[StringName] = []


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _pattern_type == PatternType.NONE and _visual_layer_ids.is_empty():
		return

	if _pattern_type != PatternType.NONE:
		match _pattern_type:
			PatternType.DIAMOND:
				_draw_diamond_pattern()
			PatternType.CHECKER:
				_draw_checker_pattern()
			PatternType.SCALES:
				_draw_scales_pattern()
			PatternType.HALFTONE:
				_draw_halftone_pattern()
			PatternType.DIAGONAL_HATCH:
				_draw_diagonal_hatch_pattern()
			PatternType.SPLIT_DIAGONAL:
				_draw_split_diagonal_pattern()
			PatternType.CONCENTRIC:
				_draw_concentric_pattern()
			_:
				pass

	_draw_inner_highlight()
	_draw_visual_layer_markers()


# --- 公共方法 ---

## 设置纹理类型和颜色基准。
## @param pattern_type: 要绘制的纹理类型。
## @param base_color: 方块底色，用于计算纹理明暗。
## @param visual_layer_ids: Recipe 提供的稳定视觉标记 ID。
func setup(
	pattern_type: PatternType,
	base_color: Color,
	visual_layer_ids: Array[StringName] = []
) -> void:
	_pattern_type = pattern_type
	_visual_layer_ids = visual_layer_ids.duplicate()
	_resolve_pattern_colors(base_color)
	queue_redraw()


# --- 私有/辅助方法 ---

func _resolve_pattern_colors(base_color: Color) -> void:
	var luminance: float = (
		base_color.r * 0.299
		+ base_color.g * 0.587
		+ base_color.b * 0.114
	)
	if luminance > 0.58:
		_pattern_color = Color(_INK_COLOR.r, _INK_COLOR.g, _INK_COLOR.b, 0.22)
		_highlight_color = Color(_CYAN_REGISTER_COLOR.r, _CYAN_REGISTER_COLOR.g, _CYAN_REGISTER_COLOR.b, 0.20)
		_registration_shadow_color = Color(_MAGENTA_REGISTER_COLOR.r, _MAGENTA_REGISTER_COLOR.g, _MAGENTA_REGISTER_COLOR.b, 0.16)
	else:
		_pattern_color = Color(_PAPER_COLOR.r, _PAPER_COLOR.g, _PAPER_COLOR.b, 0.25)
		_highlight_color = Color(_CYAN_REGISTER_COLOR.r, _CYAN_REGISTER_COLOR.g, _CYAN_REGISTER_COLOR.b, 0.24)
		_registration_shadow_color = Color(_MAGENTA_REGISTER_COLOR.r, _MAGENTA_REGISTER_COLOR.g, _MAGENTA_REGISTER_COLOR.b, 0.18)


func _draw_diamond_pattern() -> void:
	var step_size: float = 26.0
	var diamond_radius: float = 6.0
	var y: float = _INNER_MARGIN + diamond_radius
	while y < size.y - _INNER_MARGIN:
		var x: float = _INNER_MARGIN + diamond_radius
		while x < size.x - _INNER_MARGIN:
			_draw_diamond(Vector2(x, y), diamond_radius)
			x += step_size
		y += step_size


func _draw_diamond(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, _pattern_color)


func _draw_checker_pattern() -> void:
	var cell_size: float = 18.0
	var row: int = 0
	var y: float = _INNER_MARGIN
	while y < size.y - _INNER_MARGIN:
		var column: int = 0
		var x: float = _INNER_MARGIN
		while x < size.x - _INNER_MARGIN:
			if (row + column) % 2 == 0:
				var rect_width: float = minf(cell_size, size.x - _INNER_MARGIN - x)
				var rect_height: float = minf(cell_size, size.y - _INNER_MARGIN - y)
				var rect: Rect2 = Rect2(
					Vector2(x, y),
					Vector2(rect_width, rect_height)
				)
				draw_rect(rect, _pattern_color, true)
			column += 1
			x += cell_size
		row += 1
		y += cell_size


func _draw_scales_pattern() -> void:
	var radius: float = 11.0
	var row_spacing: float = 10.0
	var y: float = _INNER_MARGIN + radius
	var row: int = 0
	while y <= size.y - _INNER_MARGIN - radius:
		var x_offset: float = 0.0 if row % 2 == 0 else radius
		var x: float = _INNER_MARGIN + radius + x_offset
		while x <= size.x - _INNER_MARGIN - radius:
			draw_arc(
				Vector2(x, y),
				radius,
				PI,
				TAU,
				12,
				_pattern_color,
				2.0,
				false
			)
			x += radius * 2.0
		row += 1
		y += row_spacing


func _draw_halftone_pattern() -> void:
	var spacing: float = 13.0
	var radius: float = 2.35
	var row: int = 0
	var y: float = _INNER_MARGIN + radius
	while y < size.y - _INNER_MARGIN:
		var x_offset: float = 0.0 if row % 2 == 0 else spacing * 0.5
		var x: float = _INNER_MARGIN + radius + x_offset
		while x < size.x - _INNER_MARGIN:
			draw_circle(Vector2(x, y), radius, _pattern_color)
			x += spacing
		row += 1
		y += spacing


func _draw_diagonal_hatch_pattern() -> void:
	var spacing: float = 13.0
	var inner_rect: Rect2 = Rect2(
		Vector2.ONE * _INNER_MARGIN,
		size - Vector2.ONE * _INNER_MARGIN * 2.0
	)
	var start: float = inner_rect.position.x - inner_rect.size.y
	var end: float = inner_rect.end.x
	var position_value: float = start
	while position_value < end:
		var clipped_start_x: float = maxf(position_value, inner_rect.position.x)
		var clipped_end_x: float = minf(
			position_value + inner_rect.size.y,
			inner_rect.end.x
		)
		if clipped_start_x <= clipped_end_x:
			var from_point: Vector2 = Vector2(
				clipped_start_x,
				inner_rect.end.y - (clipped_start_x - position_value)
			)
			var to_point: Vector2 = Vector2(
				clipped_end_x,
				inner_rect.end.y - (clipped_end_x - position_value)
			)
			draw_line(from_point, to_point, _pattern_color, 2.0)
		position_value += spacing


func _draw_split_diagonal_pattern() -> void:
	var inner_rect: Rect2 = Rect2(
		Vector2.ONE * _INNER_MARGIN,
		size - Vector2.ONE * _INNER_MARGIN * 2.0
	)
	var split_fill: PackedVector2Array = PackedVector2Array([
		inner_rect.position,
		Vector2(inner_rect.end.x, inner_rect.position.y),
		Vector2(inner_rect.position.x, inner_rect.end.y),
	])
	draw_colored_polygon(split_fill, _pattern_color)
	var diagonal_color: Color = _registration_shadow_color
	draw_line(
		inner_rect.position + Vector2(0.0, inner_rect.size.y),
		inner_rect.position + Vector2(inner_rect.size.x, 0.0),
		diagonal_color,
		4.0
	)


func _draw_concentric_pattern() -> void:
	var center: Vector2 = size * 0.5
	var half_extent: float = minf(size.x, size.y) * 0.5 - _INNER_MARGIN
	var inset: float = 3.0
	var ring_index: int = 0
	while inset < half_extent:
		var extent: float = half_extent - inset
		var ring_rect: Rect2 = Rect2(
			center - Vector2.ONE * extent,
			Vector2.ONE * extent * 2.0
		)
		draw_rect(ring_rect, _pattern_color, false, 2.0)
		inset += 10.0 + float(ring_index % 2) * 3.0
		ring_index += 1


func _draw_inner_highlight() -> void:
	var top_left: Vector2 = Vector2(_INNER_MARGIN, _INNER_MARGIN)
	var top_right: Vector2 = Vector2(size.x - _INNER_MARGIN, _INNER_MARGIN)
	var bottom_left: Vector2 = Vector2(_INNER_MARGIN, size.y - _INNER_MARGIN)
	var bottom_right: Vector2 = Vector2(size.x - _INNER_MARGIN, size.y - _INNER_MARGIN)
	draw_line(top_left, top_right, _highlight_color, 2.0)
	draw_line(top_left, bottom_left, _highlight_color, 2.0)
	draw_line(bottom_left, bottom_right, _registration_shadow_color, 2.0)
	draw_line(top_right, bottom_right, _registration_shadow_color, 2.0)


func _draw_visual_layer_markers() -> void:
	var marker_count: int = mini(_visual_layer_ids.size(), 4)
	if marker_count <= 0:
		return
	var marker_spacing: float = 15.0
	var total_width: float = float(marker_count - 1) * marker_spacing
	var start_x: float = size.x * 0.5 - total_width * 0.5
	var marker_y: float = size.y - _INNER_MARGIN - 5.0
	for index: int in range(marker_count):
		_draw_visual_layer_marker(
			_visual_layer_ids[index],
			Vector2(start_x + float(index) * marker_spacing, marker_y)
		)


func _draw_visual_layer_marker(layer_id: StringName, center: Vector2) -> void:
	match layer_id:
		&"tile.visual_trait.classic_merge":
			draw_rect(Rect2(center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), _registration_shadow_color, false, 2.0)
		&"tile.visual_trait.fibonacci_merge":
			_draw_diamond(center, 5.0)
		&"tile.visual_trait.lucas_merge":
			draw_arc(center, 5.0, 0.0, TAU, 12, _registration_shadow_color, 2.0, false)
		&"tile.visual_trait.lucas_bridge":
			draw_line(center - Vector2(5.0, 0.0), center + Vector2(5.0, 0.0), _registration_shadow_color, 2.0)
			draw_line(center - Vector2(0.0, 5.0), center + Vector2(0.0, 5.0), _registration_shadow_color, 2.0)
		&"tile.visual_trait.ratio":
			var points: PackedVector2Array = PackedVector2Array([
				center + Vector2(0.0, -5.0),
				center + Vector2(5.0, 4.0),
				center + Vector2(-5.0, 4.0),
			])
			draw_polyline(points, _registration_shadow_color, 2.0)
		_:
			draw_circle(center, 3.0, _registration_shadow_color)
