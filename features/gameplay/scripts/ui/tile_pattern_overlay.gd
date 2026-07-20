## TilePatternOverlay: 绘制克制、可解释的方块家族识别符号。
##
## 母题只占角部或边缘安全区，中央数字区保持完全安静。组合规则只在底边显示细分色段，
## 不再用散点、轨道或全卡面斜纹堆叠信息。
class_name TilePatternOverlay
extends Control


# --- 枚举 ---

enum PatternType {
	NONE,
	FIBONACCI_CORNER,
	DIAGONAL_FOLD,
	PAIRED_BRACKETS,
	DIVISION_MARK,
	FACTOR_MARK,
}


# --- 常量 ---

const _INK_COLOR: Color = Color(0.19215687, 0.2, 0.21568628, 1.0)
const _PAPER_COLOR: Color = Color(0.95686275, 0.94509804, 0.9098039, 1.0)
const _CYAN_COLOR: Color = Color(0.36078432, 0.7176471, 0.7254902, 1.0)
const _GOLD_COLOR: Color = Color(0.8745098, 0.6901961, 0.3019608, 1.0)
const _CORAL_COLOR: Color = Color(0.827451, 0.38431373, 0.29411766, 1.0)
const _INNER_MARGIN: float = 8.0


# --- 私有变量 ---

var _pattern_type: PatternType = PatternType.NONE
var _pattern_color: Color = Color.TRANSPARENT
var _accent_color: Color = Color.TRANSPARENT
var _visual_layer_ids: Array[StringName] = []
var _motif_opacity: float = 0.10


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	match _pattern_type:
		PatternType.FIBONACCI_CORNER:
			_draw_fibonacci_corner()
		PatternType.DIAGONAL_FOLD:
			_draw_diagonal_fold()
		PatternType.PAIRED_BRACKETS:
			_draw_paired_brackets()
		PatternType.DIVISION_MARK:
			_draw_division_mark()
		PatternType.FACTOR_MARK:
			_draw_factor_mark()
		_:
			pass
	_draw_composition_edge()


# --- 公共方法 ---

## 配置当前方块的稀疏家族母题与组合边缘标记。
## @param visual_style: 主题为方块家族提供的稳定视觉配置。
## @param base_color: 方块底色，用于计算可读的母题颜色。
## @param visual_layer_ids: 规则组合提供的语义视觉层。
func setup(
	visual_style: TileVisualFamilyStyle,
	base_color: Color,
	visual_layer_ids: Array[StringName]
) -> void:
	_visual_layer_ids = _get_unique_layers(visual_layer_ids)
	_pattern_type = _resolve_pattern_type(
		visual_style.motif_id if visual_style != null else &""
	)
	_motif_opacity = visual_style.motif_opacity if visual_style != null else 0.10
	_accent_color = visual_style.accent_color if visual_style != null else _CYAN_COLOR
	_resolve_pattern_color(base_color)
	queue_redraw()


func get_pattern_type() -> PatternType:
	return _pattern_type


func get_safe_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * _INNER_MARGIN,
		size - Vector2.ONE * _INNER_MARGIN * 2.0
	)


func has_composition_edge() -> bool:
	return _visual_layer_ids.size() > 1


# --- 私有/辅助方法 ---

func _draw_fibonacci_corner() -> void:
	var corner: Vector2 = Vector2(size.x - _INNER_MARGIN - 1.0, _INNER_MARGIN + 1.0)
	draw_arc(corner, 18.0, PI * 0.50, PI, 14, _pattern_color, 2.0, true)
	draw_arc(corner - Vector2(10.5, 10.5), 7.5, 0.0, PI * 0.50, 10, _accent_color, 2.0, true)


func _draw_diagonal_fold() -> void:
	var top_right: Vector2 = Vector2(size.x - _INNER_MARGIN, _INNER_MARGIN)
	var fold_size: float = 18.0
	var fold: PackedVector2Array = PackedVector2Array([
		top_right,
		top_right + Vector2(-fold_size, 0.0),
		top_right + Vector2(0.0, fold_size),
	])
	var fill_color: Color = _accent_color
	fill_color.a *= 0.72
	draw_colored_polygon(fold, fill_color)
	draw_line(
		top_right + Vector2(-fold_size, 0.0),
		top_right + Vector2(0.0, fold_size),
		_pattern_color,
		2.0,
		true
	)
	var bottom_left: Vector2 = Vector2(_INNER_MARGIN, size.y - _INNER_MARGIN)
	draw_line(
		bottom_left,
		bottom_left + Vector2(15.0, -15.0),
		_pattern_color,
		2.0,
		true
	)


func _draw_paired_brackets() -> void:
	var arm: float = 15.0
	var top_left: Vector2 = Vector2(_INNER_MARGIN, _INNER_MARGIN)
	_draw_corner_bracket(top_left, Vector2.RIGHT, Vector2.DOWN, arm, _pattern_color)
	var bottom_right: Vector2 = Vector2(size.x - _INNER_MARGIN, size.y - _INNER_MARGIN)
	_draw_corner_bracket(bottom_right, Vector2.LEFT, Vector2.UP, arm, _accent_color)


func _draw_division_mark() -> void:
	var start: Vector2 = Vector2(_INNER_MARGIN, _INNER_MARGIN + 6.0)
	var mark_color: Color = _pattern_color
	draw_line(start, start + Vector2(19.0, 0.0), mark_color, 2.5, true)
	draw_line(start + Vector2(5.0, -6.0), start + Vector2(13.0, -6.0), _accent_color, 2.0, true)
	draw_line(start + Vector2(5.0, 6.0), start + Vector2(13.0, 6.0), _accent_color, 2.0, true)


func _draw_factor_mark() -> void:
	var center: Vector2 = Vector2(size.x - _INNER_MARGIN - 7.0, _INNER_MARGIN + 7.0)
	var radius: float = 7.0
	draw_line(
		center - Vector2(radius, radius),
		center + Vector2(radius, radius),
		_pattern_color,
		2.6,
		true
	)
	draw_line(
		center + Vector2(radius, -radius),
		center - Vector2(radius, -radius),
		_accent_color,
		2.6,
		true
	)


func _draw_corner_bracket(
	corner: Vector2,
	horizontal_direction: Vector2,
	vertical_direction: Vector2,
	arm: float,
	color: Color
) -> void:
	draw_line(corner, corner + horizontal_direction * arm, color, 2.2, true)
	draw_line(corner, corner + vertical_direction * arm, color, 2.2, true)


func _draw_composition_edge() -> void:
	if not has_composition_edge():
		return
	var segment_count: int = mini(_visual_layer_ids.size(), 3)
	var available_width: float = size.x - _INNER_MARGIN * 2.0
	var segment_width: float = available_width / float(segment_count)
	for index: int in range(segment_count):
		var color: Color = _get_capability_color(_visual_layer_ids[index])
		color.a = 0.68
		var start_x: float = _INNER_MARGIN + float(index) * segment_width
		draw_line(
			Vector2(start_x + 2.0, size.y - _INNER_MARGIN),
			Vector2(start_x + segment_width - 2.0, size.y - _INNER_MARGIN),
			color,
			2.0,
			true
		)


func _get_unique_layers(layer_ids: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for layer_id: StringName in layer_ids:
		if not result.has(layer_id):
			result.append(layer_id)
	return result


func _get_capability_color(layer_id: StringName) -> Color:
	match layer_id:
		&"tile.visual_trait.classic_merge":
			return _CYAN_COLOR
		&"tile.visual_trait.fibonacci_merge":
			return _GOLD_COLOR
		&"tile.visual_trait.lucas_merge", &"tile.visual_trait.lucas_bridge":
			return _CORAL_COLOR
		&"tile.visual_trait.ratio":
			return _INK_COLOR
		_:
			return _accent_color


func _resolve_pattern_color(base_color: Color) -> void:
	var source: Color = _INK_COLOR if base_color.get_luminance() > 0.50 else _PAPER_COLOR
	_pattern_color = Color(source.r, source.g, source.b, _motif_opacity)
	_accent_color.a = clampf(_motif_opacity * 1.32, 0.12, 0.22)


func _resolve_pattern_type(motif_id: StringName) -> PatternType:
	match motif_id:
		&"fibonacci_corner":
			return PatternType.FIBONACCI_CORNER
		&"diagonal_fold":
			return PatternType.DIAGONAL_FOLD
		&"paired_brackets":
			return PatternType.PAIRED_BRACKETS
		&"division_mark":
			return PatternType.DIVISION_MARK
		&"factor_mark":
			return PatternType.FACTOR_MARK
	return PatternType.NONE
