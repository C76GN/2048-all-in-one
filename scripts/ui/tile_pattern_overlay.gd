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


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _pattern_type == PatternType.NONE:
		return

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
		_:
			pass

	_draw_inner_highlight()


# --- 公共方法 ---

## 设置纹理类型和颜色基准。
## @param pattern_type: 要绘制的纹理类型。
## @param base_color: 方块底色，用于计算纹理明暗。
func setup(pattern_type: PatternType, base_color: Color) -> void:
	_pattern_type = pattern_type
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
		_pattern_color = Color(_INK_COLOR.r, _INK_COLOR.g, _INK_COLOR.b, 0.12)
		_highlight_color = Color(_CYAN_REGISTER_COLOR.r, _CYAN_REGISTER_COLOR.g, _CYAN_REGISTER_COLOR.b, 0.20)
		_registration_shadow_color = Color(_MAGENTA_REGISTER_COLOR.r, _MAGENTA_REGISTER_COLOR.g, _MAGENTA_REGISTER_COLOR.b, 0.16)
	else:
		_pattern_color = Color(_PAPER_COLOR.r, _PAPER_COLOR.g, _PAPER_COLOR.b, 0.15)
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
	while y < size.y - _INNER_MARGIN + radius:
		var x_offset: float = 0.0 if row % 2 == 0 else radius
		var x: float = _INNER_MARGIN - radius + x_offset
		while x < size.x - _INNER_MARGIN + radius:
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
	var start: float = -size.y
	var end: float = size.x + size.y
	var position_value: float = start
	while position_value < end:
		var from_point: Vector2 = Vector2(position_value, size.y - _INNER_MARGIN)
		var to_point: Vector2 = Vector2(position_value + size.y, _INNER_MARGIN)
		draw_line(from_point, to_point, _pattern_color, 2.0)
		position_value += spacing


func _draw_inner_highlight() -> void:
	var top_left: Vector2 = Vector2(_INNER_MARGIN, _INNER_MARGIN)
	var top_right: Vector2 = Vector2(size.x - _INNER_MARGIN, _INNER_MARGIN)
	var bottom_left: Vector2 = Vector2(_INNER_MARGIN, size.y - _INNER_MARGIN)
	var bottom_right: Vector2 = Vector2(size.x - _INNER_MARGIN, size.y - _INNER_MARGIN)
	draw_line(top_left, top_right, _highlight_color, 2.0)
	draw_line(top_left, bottom_left, _highlight_color, 2.0)
	draw_line(bottom_left, bottom_right, _registration_shadow_color, 2.0)
	draw_line(top_right, bottom_right, _registration_shadow_color, 2.0)
