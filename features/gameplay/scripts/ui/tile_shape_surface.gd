## TileShapeSurface: 绘制可主题化的方块轮廓与印刷错版边缘。
##
## 数字保持水平稳定，只有承载数字的实体表面发生轻微形变，确保身份差异清晰且
## 不牺牲读数速度。
class_name TileShapeSurface
extends Control


# --- 常量 ---

const _DEFAULT_BORDER_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _DEFAULT_ACCENT_COLOR: Color = Color(0.61960787, 0.8235294, 0.80784315, 1.0)
const _DEFAULT_SCALE: Vector2 = Vector2(0.94, 0.94)
const _HIGHLIGHT_ALPHA: float = 0.34
const _REGISTRATION_ALPHA: float = 0.20


# --- 私有变量 ---

var _visual_style: TileVisualFamilyStyle
var _fill_color: Color = Color.WHITE
var _shape_points: PackedVector2Array = PackedVector2Array()


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _resize_connection: int = resized.connect(_on_resized)
	_rebuild_shape()


func _draw() -> void:
	if _shape_points.size() < 3:
		return

	var registration_color: Color = _get_accent_color()
	registration_color.a = _REGISTRATION_ALPHA
	var registration_points: PackedVector2Array = PackedVector2Array()
	var registration_offset: Vector2 = _get_registration_offset()
	for point: Vector2 in _shape_points:
		var _registration_append_result: bool = registration_points.append(
			point + registration_offset
		)
	draw_colored_polygon(registration_points, registration_color)

	draw_colored_polygon(_shape_points, _fill_color)
	var outline: PackedVector2Array = _shape_points.duplicate()
	var _outline_append_result: bool = outline.append(_shape_points[0])
	draw_polyline(outline, _get_border_color(), _get_border_width(), true)

	var highlight_color: Color = _get_accent_color()
	highlight_color.a = _HIGHLIGHT_ALPHA
	if _shape_points.size() >= 4:
		draw_line(_shape_points[0], _shape_points[1], highlight_color, 2.0, true)
		draw_line(_shape_points[1], _shape_points[2], highlight_color, 2.0, true)


# --- 公共方法 ---

## @param visual_style: 当前主题为方块家族声明的轮廓配置。
## @param fill_color: 当前数值色阶的方块底色。
func setup(visual_style: TileVisualFamilyStyle, fill_color: Color) -> void:
	_visual_style = visual_style
	_fill_color = fill_color
	_rebuild_shape()
	queue_redraw()


## @param fill_color: 要应用到方块实体表面的新底色。
func set_fill_color(fill_color: Color) -> void:
	_fill_color = fill_color
	queue_redraw()


func get_fill_color() -> Color:
	return _fill_color


func get_shape_points() -> PackedVector2Array:
	return _shape_points.duplicate()


func get_silhouette_id() -> StringName:
	return _visual_style.silhouette_id if _visual_style != null else &"soft_square"


# --- 私有/辅助方法 ---

func _rebuild_shape() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var scale_value: Vector2 = _visual_style.shape_scale if _visual_style != null else _DEFAULT_SCALE
	var half_size: Vector2 = size * scale_value * 0.5
	var center: Vector2 = size * 0.5
	var local_points: PackedVector2Array = _build_local_shape_points(
		get_silhouette_id(),
		half_size
	)
	var rotation_radians: float = deg_to_rad(
		_visual_style.shape_rotation_degrees if _visual_style != null else 0.0
	)
	_shape_points = PackedVector2Array()
	for local_point: Vector2 in local_points:
		var _shape_append_result: bool = _shape_points.append(
			center + local_point.rotated(rotation_radians)
		)
	queue_redraw()


func _build_local_shape_points(
	silhouette_id: StringName,
	half_size: Vector2
) -> PackedVector2Array:
	match silhouette_id:
		&"leaf_cut":
			return _build_asymmetric_cut_shape(half_size, 0.25, 0.08, 0.25, 0.08)
		&"diagonal_cut":
			return _build_asymmetric_cut_shape(half_size, 0.08, 0.30, 0.08, 0.30)
		&"octagon":
			return _build_asymmetric_cut_shape(half_size, 0.22, 0.22, 0.22, 0.22)
		&"bracket":
			return _build_bracket_shape(half_size)
		&"ticket":
			return _build_ticket_shape(half_size)
		_:
			return _build_asymmetric_cut_shape(half_size, 0.09, 0.09, 0.09, 0.09)


func _build_asymmetric_cut_shape(
	half_size: Vector2,
	top_left_ratio: float,
	top_right_ratio: float,
	bottom_right_ratio: float,
	bottom_left_ratio: float
) -> PackedVector2Array:
	var extent: float = minf(half_size.x, half_size.y)
	var tl: float = extent * top_left_ratio
	var top_right_cut: float = extent * top_right_ratio
	var br: float = extent * bottom_right_ratio
	var bl: float = extent * bottom_left_ratio
	return PackedVector2Array([
		Vector2(-half_size.x + tl, -half_size.y),
		Vector2(half_size.x - top_right_cut, -half_size.y),
		Vector2(half_size.x, -half_size.y + top_right_cut),
		Vector2(half_size.x, half_size.y - br),
		Vector2(half_size.x - br, half_size.y),
		Vector2(-half_size.x + bl, half_size.y),
		Vector2(-half_size.x, half_size.y - bl),
		Vector2(-half_size.x, -half_size.y + tl),
	])


func _build_bracket_shape(half_size: Vector2) -> PackedVector2Array:
	var cut: float = minf(half_size.x, half_size.y) * 0.12
	var notch_depth: float = half_size.x * 0.10
	var notch_half_height: float = half_size.y * 0.12
	return PackedVector2Array([
		Vector2(-half_size.x + cut, -half_size.y),
		Vector2(half_size.x - cut, -half_size.y),
		Vector2(half_size.x, -half_size.y + cut),
		Vector2(half_size.x, -notch_half_height),
		Vector2(half_size.x - notch_depth, 0.0),
		Vector2(half_size.x, notch_half_height),
		Vector2(half_size.x, half_size.y - cut),
		Vector2(half_size.x - cut, half_size.y),
		Vector2(-half_size.x + cut, half_size.y),
		Vector2(-half_size.x, half_size.y - cut),
		Vector2(-half_size.x, notch_half_height),
		Vector2(-half_size.x + notch_depth, 0.0),
		Vector2(-half_size.x, -notch_half_height),
		Vector2(-half_size.x, -half_size.y + cut),
	])


func _build_ticket_shape(half_size: Vector2) -> PackedVector2Array:
	var cut: float = minf(half_size.x, half_size.y) * 0.16
	var notch_depth: float = half_size.y * 0.12
	var notch_half_width: float = half_size.x * 0.10
	return PackedVector2Array([
		Vector2(-half_size.x + cut, -half_size.y),
		Vector2(-notch_half_width, -half_size.y),
		Vector2(0.0, -half_size.y + notch_depth),
		Vector2(notch_half_width, -half_size.y),
		Vector2(half_size.x - cut, -half_size.y),
		Vector2(half_size.x, -half_size.y + cut),
		Vector2(half_size.x, half_size.y - cut),
		Vector2(half_size.x - cut, half_size.y),
		Vector2(notch_half_width, half_size.y),
		Vector2(0.0, half_size.y - notch_depth),
		Vector2(-notch_half_width, half_size.y),
		Vector2(-half_size.x + cut, half_size.y),
		Vector2(-half_size.x, half_size.y - cut),
		Vector2(-half_size.x, -half_size.y + cut),
	])


func _get_border_color() -> Color:
	return _visual_style.border_color if _visual_style != null else _DEFAULT_BORDER_COLOR


func _get_accent_color() -> Color:
	return _visual_style.accent_color if _visual_style != null else _DEFAULT_ACCENT_COLOR


func _get_border_width() -> float:
	return _visual_style.border_width if _visual_style != null else 4.0


func _get_registration_offset() -> Vector2:
	return _visual_style.registration_offset if _visual_style != null else Vector2(2.0, 2.0)


func _on_resized() -> void:
	_rebuild_shape()
