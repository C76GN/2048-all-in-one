## TilePatternOverlay: 绘制方块家族的低密度识别符号与能力组合标记。
##
## 家族符号只占用边缘和角部，中央数字区保持安静；Recipe 标记沿左侧形成可拆卸
## 的能力轨道，避免把多个规则直接叠成一张复杂纹理。
class_name TilePatternOverlay
extends Control


# --- 枚举 ---

enum PatternType {
	NONE,
	CONSTELLATION,
	SPIRAL_ARC,
	SPLIT_TABS,
	ORBIT,
	QUOTIENT_BARS,
	FACTOR_CROSS,
}


# --- 常量 ---

const _INK_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _PAPER_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 1.0)
const _CYAN_COLOR: Color = Color(0.61960787, 0.8235294, 0.80784315, 1.0)
const _GOLD_COLOR: Color = Color(0.83137256, 0.7529412, 0.48235294, 1.0)
const _CORAL_COLOR: Color = Color(0.7176471, 0.47843137, 0.45882353, 1.0)
const _MAGENTA_COLOR: Color = Color(0.9607843, 0.6392157, 0.7882353, 1.0)
const _INNER_MARGIN: float = 12.0


# --- 私有变量 ---

var _pattern_type: PatternType = PatternType.NONE
var _pattern_color: Color = Color.TRANSPARENT
var _accent_color: Color = Color.TRANSPARENT
var _visual_layer_ids: Array[StringName] = []
var _motif_opacity: float = 0.14


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	match _pattern_type:
		PatternType.CONSTELLATION:
			_draw_constellation()
		PatternType.SPIRAL_ARC:
			_draw_spiral_arc()
		PatternType.SPLIT_TABS:
			_draw_split_tabs()
		PatternType.ORBIT:
			_draw_orbit()
		PatternType.QUOTIENT_BARS:
			_draw_quotient_bars()
		PatternType.FACTOR_CROSS:
			_draw_factor_cross()
		_:
			pass
	_draw_capability_rail()


# --- 公共方法 ---

## @param visual_style: 当前主题为方块家族声明的视觉配置。
## @param base_color: 当前数值色阶的方块底色。
## @param visual_layer_ids: Recipe 组合投影出的能力标记层。
func setup(
	visual_style: TileVisualFamilyStyle,
	base_color: Color,
	visual_layer_ids: Array[StringName]
) -> void:
	_visual_layer_ids = visual_layer_ids.duplicate()
	_pattern_type = _resolve_pattern_type(
		visual_style.motif_id if visual_style != null else &""
	)
	_motif_opacity = visual_style.motif_opacity if visual_style != null else 0.12
	_accent_color = visual_style.accent_color if visual_style != null else _CYAN_COLOR
	_resolve_pattern_color(base_color)
	queue_redraw()


func get_pattern_type() -> PatternType:
	return _pattern_type


# --- 私有/辅助方法 ---

# 家族符号

func _draw_constellation() -> void:
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(_INNER_MARGIN + 3.0, _INNER_MARGIN + 5.0),
		Vector2(_INNER_MARGIN + 18.0, _INNER_MARGIN + 10.0),
		Vector2(size.x - _INNER_MARGIN - 7.0, _INNER_MARGIN + 5.0),
		Vector2(size.x - _INNER_MARGIN - 15.0, size.y - _INNER_MARGIN - 8.0),
		Vector2(_INNER_MARGIN + 8.0, size.y - _INNER_MARGIN - 6.0),
	])
	draw_line(points[0], points[1], _pattern_color, 1.5, true)
	for index: int in range(points.size()):
		var radius: float = 2.4 if index == 1 else 1.7
		draw_circle(points[index], radius, _pattern_color)


func _draw_spiral_arc() -> void:
	var center: Vector2 = Vector2(_INNER_MARGIN + 12.0, size.y - _INNER_MARGIN - 11.0)
	for index: int in range(3):
		var radius: float = 7.0 + float(index) * 6.5
		draw_arc(
			center,
			radius,
			-PI * 0.42,
			PI * (0.72 + float(index) * 0.12),
			18,
			_pattern_color,
			1.8,
			true
		)
	draw_arc(
		Vector2(size.x - _INNER_MARGIN - 7.0, _INNER_MARGIN + 7.0),
		7.0,
		PI * 0.55,
		PI * 1.45,
		10,
		_accent_color,
		2.0,
		true
	)


func _draw_split_tabs() -> void:
	var top_tab: PackedVector2Array = PackedVector2Array([
		Vector2(size.x - 34.0, _INNER_MARGIN),
		Vector2(size.x - _INNER_MARGIN, _INNER_MARGIN),
		Vector2(size.x - _INNER_MARGIN, 36.0),
	])
	var bottom_tab: PackedVector2Array = PackedVector2Array([
		Vector2(_INNER_MARGIN, size.y - 34.0),
		Vector2(34.0, size.y - _INNER_MARGIN),
		Vector2(_INNER_MARGIN, size.y - _INNER_MARGIN),
	])
	draw_colored_polygon(top_tab, _pattern_color)
	var bottom_outline: PackedVector2Array = bottom_tab.duplicate()
	var _outline_append_result: bool = bottom_outline.append(bottom_tab[0])
	draw_polyline(bottom_outline, _accent_color, 2.0, true)


func _draw_orbit() -> void:
	var top_center: Vector2 = Vector2(size.x * 0.5, _INNER_MARGIN + 2.0)
	var bottom_center: Vector2 = Vector2(size.x * 0.5, size.y - _INNER_MARGIN - 2.0)
	draw_arc(top_center, 26.0, 0.12, PI - 0.12, 24, _pattern_color, 2.0, true)
	draw_arc(bottom_center, 26.0, PI + 0.12, TAU - 0.12, 24, _pattern_color, 2.0, true)
	draw_circle(Vector2(size.x - _INNER_MARGIN - 5.0, size.y * 0.5), 3.0, _accent_color)


func _draw_quotient_bars() -> void:
	var center_y: float = size.y * 0.5
	draw_line(
		Vector2(_INNER_MARGIN, center_y - 14.0),
		Vector2(_INNER_MARGIN + 15.0, center_y - 14.0),
		_pattern_color,
		3.0,
		true
	)
	draw_line(
		Vector2(size.x - _INNER_MARGIN - 15.0, center_y + 14.0),
		Vector2(size.x - _INNER_MARGIN, center_y + 14.0),
		_pattern_color,
		3.0,
		true
	)
	draw_circle(Vector2(_INNER_MARGIN + 4.0, center_y + 13.0), 2.2, _accent_color)
	draw_circle(Vector2(size.x - _INNER_MARGIN - 4.0, center_y - 13.0), 2.2, _accent_color)


func _draw_factor_cross() -> void:
	for center: Vector2 in [
		Vector2(_INNER_MARGIN + 5.0, _INNER_MARGIN + 5.0),
		Vector2(size.x - _INNER_MARGIN - 5.0, _INNER_MARGIN + 5.0),
		Vector2(size.x - _INNER_MARGIN - 5.0, size.y - _INNER_MARGIN - 5.0),
		Vector2(_INNER_MARGIN + 5.0, size.y - _INNER_MARGIN - 5.0),
	]:
		draw_line(center - Vector2(4.0, 0.0), center + Vector2(4.0, 0.0), _pattern_color, 2.0, true)
		draw_line(center - Vector2(0.0, 4.0), center + Vector2(0.0, 4.0), _pattern_color, 2.0, true)


# 能力组合标记

func _draw_capability_rail() -> void:
	var marker_count: int = mini(_visual_layer_ids.size(), 3)
	if marker_count <= 0:
		return
	var spacing: float = 13.0
	var start_y: float = size.y * 0.5 - float(marker_count - 1) * spacing * 0.5
	for index: int in range(marker_count):
		_draw_capability_marker(
			_visual_layer_ids[index],
			Vector2(_INNER_MARGIN - 3.0, start_y + float(index) * spacing)
		)


func _draw_capability_marker(layer_id: StringName, center: Vector2) -> void:
	var marker_color: Color = _get_capability_color(layer_id)
	marker_color.a = maxf(marker_color.a, 0.68)
	match layer_id:
		&"tile.visual_trait.classic_merge":
			draw_rect(Rect2(center - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), marker_color, false, 1.8)
		&"tile.visual_trait.fibonacci_merge":
			_draw_diamond(center, 4.0, marker_color)
		&"tile.visual_trait.lucas_merge":
			draw_arc(center, 4.0, 0.0, TAU, 12, marker_color, 1.8, true)
		&"tile.visual_trait.lucas_bridge":
			draw_line(center - Vector2(4.0, 0.0), center + Vector2(4.0, 0.0), marker_color, 1.8, true)
		&"tile.visual_trait.ratio":
			var triangle: PackedVector2Array = PackedVector2Array([
				center + Vector2(0.0, -4.0),
				center + Vector2(4.0, 3.0),
				center + Vector2(-4.0, 3.0),
				center + Vector2(0.0, -4.0),
			])
			draw_polyline(triangle, marker_color, 1.8, true)
		_:
			draw_circle(center, 2.4, marker_color)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, -radius),
	])
	draw_polyline(points, color, 1.8, true)


func _get_capability_color(layer_id: StringName) -> Color:
	match layer_id:
		&"tile.visual_trait.classic_merge":
			return _CYAN_COLOR
		&"tile.visual_trait.fibonacci_merge":
			return _GOLD_COLOR
		&"tile.visual_trait.lucas_merge", &"tile.visual_trait.lucas_bridge":
			return _MAGENTA_COLOR
		&"tile.visual_trait.ratio":
			return _CORAL_COLOR
		_:
			return _accent_color


func _resolve_pattern_color(base_color: Color) -> void:
	var luminance: float = base_color.get_luminance()
	var source: Color = _INK_COLOR if luminance > 0.52 else _PAPER_COLOR
	_pattern_color = Color(source.r, source.g, source.b, _motif_opacity)
	_accent_color.a = clampf(_motif_opacity * 1.55, 0.16, 0.30)


func _resolve_pattern_type(motif_id: StringName) -> PatternType:
	match motif_id:
		&"constellation":
			return PatternType.CONSTELLATION
		&"spiral_arc":
			return PatternType.SPIRAL_ARC
		&"split_tabs":
			return PatternType.SPLIT_TABS
		&"orbit":
			return PatternType.ORBIT
		&"quotient_bars":
			return PatternType.QUOTIENT_BARS
		&"factor_cross":
			return PatternType.FACTOR_CROSS
	return PatternType.NONE
