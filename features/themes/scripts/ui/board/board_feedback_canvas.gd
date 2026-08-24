## BoardFeedbackCanvas: 用一个常驻 CanvasItem 批量绘制棋盘冲击和合并反馈。
##
## 高频操作期间不创建临时 Control、StyleBox 或 Tween。所有短命碎片与飘字都保存在
## 小型数据记录中，由单一 _process/_draw 周期更新，避免首帧资源上传和节点分配抖动。
class_name BoardFeedbackCanvas
extends Node2D


# --- 常量 ---

const _FEEDBACK_FONT: Font = preload("res://shared/assets/fonts/ui_sans_display.tres")
const _PAPER_COLOR: Color = Color(0.95686275, 0.94509804, 0.9098039, 1.0)
const _INK_COLOR: Color = Color(0.19215687, 0.2, 0.21568628, 1.0)
const _CYAN_COLOR: Color = Color(0.36078432, 0.7176471, 0.7254902, 1.0)
const _CORAL_COLOR: Color = Color(0.827451, 0.38431373, 0.29411766, 1.0)
const _GOLD_COLOR: Color = Color(0.8745098, 0.6901961, 0.3019608, 1.0)
const _TURN_Z_INDEX: int = 104
const _SCORE_LABEL_COUNT: int = 1
const _WARMUP_FRAME_COUNT: int = 2


# --- 私有变量 ---

var _turn_elapsed: float = 1.0
var _turn_duration: float = 0.0
var _turn_direction: Vector2 = Vector2.RIGHT
var _turn_rect: Rect2 = Rect2()
var _turn_color: Color = _CYAN_COLOR
var _turn_tier: int = 0
var _turn_fragment_count: int = 0
var _turn_motion_scale: float = 1.0
var _turn_seed: int = 0
var _merge_seed: int = 0
var _warmup_frames: int = _WARMUP_FRAME_COUNT
var _merge_bursts: Array[MergeBurst] = []


# --- Godot 生命周期方法 ---

func _ready() -> void:
	z_index = _TURN_Z_INDEX
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var has_active_effect: bool = false
	if _turn_elapsed < _turn_duration:
		_turn_elapsed = minf(_turn_elapsed + delta, _turn_duration)
		has_active_effect = true

	for index: int in range(_merge_bursts.size() - 1, -1, -1):
		var burst: MergeBurst = _merge_bursts[index]
		burst.elapsed += delta
		if burst.elapsed >= burst.duration:
			_merge_bursts.remove_at(index)
		else:
			has_active_effect = true

	if _warmup_frames > 0:
		_warmup_frames -= 1
		has_active_effect = true

	if has_active_effect:
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	if _warmup_frames > 0:
		_draw_warmup_primitives()
	if _turn_elapsed < _turn_duration and _turn_duration > 0.0:
		_draw_turn_impact()
	for burst: MergeBurst in _merge_bursts:
		_draw_merge_burst(burst)


# --- 公共方法 ---

## 清除所有尚未结束的反馈，供棋盘换局或重建时复用。
func reset_feedback() -> void:
	_turn_elapsed = _turn_duration
	_merge_bursts.clear()
	queue_redraw()
	set_process(false)


## 播放一次棋盘边缘冲击，返回本次绘制的碎片数量。
## @param board_rect: 棋盘在反馈画布本地坐标中的边界。
## @param direction: 本次有效移动的方向。
## @param tier: 反馈强度等级。
## @param fragment_count: 沿受力边缘绘制的碎片数。
## @param accent_color: 当前主题提供的强调色。
## @param duration: 本次边缘反馈的总持续时间。
## @param motion_scale: 无障碍与质量档位解析后的位移倍率。
func play_turn_impact(
	board_rect: Rect2,
	direction: Vector2,
	tier: int,
	fragment_count: int,
	accent_color: Color,
	duration: float,
	motion_scale: float
) -> int:
	if direction.is_zero_approx() or board_rect.size.x <= 0.0 or board_rect.size.y <= 0.0:
		return 0
	_turn_rect = board_rect
	_turn_direction = direction.normalized()
	_turn_tier = maxi(tier, 0)
	_turn_fragment_count = maxi(fragment_count, 0)
	_turn_duration = maxf(duration, 0.01)
	_turn_motion_scale = maxf(motion_scale, 0.0)
	_turn_elapsed = 0.0
	_turn_color = accent_color.lerp(_get_tier_color(_turn_tier), 0.48)
	_turn_color.a = 1.0
	_turn_seed += 1
	set_process(true)
	queue_redraw()
	return _turn_fragment_count


## 播放单方块碰撞反馈；分数文本会沿不规则的全方向轨迹散开。
## @param local_position: 方块中心在反馈画布中的本地坐标。
## @param feedback_type: `spawn`、`merge` 或 `transform` 反馈类型。
## @param label_text: 可选分数或状态文本。
## @param color: 当前方块提供的反馈基色。
## @param shard_count: 本次允许绘制的碎片数量。
## @param duration: 本次 burst 的持续时间。
## @param motion_scale: 无障碍与质量档位解析后的位移倍率。
## @param max_active_bursts: 画布允许同时保留的 burst 上限。
func play_tile_burst(
	local_position: Vector2,
	feedback_type: StringName,
	label_text: String,
	color: Color,
	shard_count: int,
	duration: float,
	motion_scale: float,
	max_active_bursts: int
) -> int:
	var active_limit: int = maxi(max_active_bursts, 1)
	while _merge_bursts.size() >= active_limit:
		_merge_bursts.pop_front()

	var burst: MergeBurst = MergeBurst.new()
	burst.position = local_position
	burst.feedback_type = feedback_type
	burst.label_text = _normalize_label(feedback_type, label_text)
	burst.color = color
	burst.color.a = 1.0
	burst.duration = maxf(duration, 0.01)
	burst.shard_count = maxi(shard_count, 0)
	burst.motion_scale = maxf(motion_scale, 0.0)
	_merge_seed += 1
	burst.random_seed = _merge_seed
	_merge_bursts.append(burst)
	set_process(true)
	queue_redraw()
	return burst.shard_count + (
		_SCORE_LABEL_COUNT if not burst.label_text.is_empty() else 0
	)


func get_active_burst_count() -> int:
	return _merge_bursts.size()


func has_active_score_burst() -> bool:
	for burst: MergeBurst in _merge_bursts:
		if not burst.label_text.is_empty():
			return true
	return false


## 暴露一轮稳定的全向向量，供回归测试验证连续飘字不会只沿单一方向运动。
func get_score_particle_directions() -> PackedVector2Array:
	var directions: PackedVector2Array = PackedVector2Array()
	for sequence_seed: int in range(1, 9):
		var _append_result: bool = directions.append(
			get_score_direction_for_seed(sequence_seed)
		)
	return directions


## 使用黄金角序列为每次合并分配全角度方向；无需随机节点，也不会长期偏向某一象限。
## @param sequence_seed: 从 1 开始递增的稳定反馈序号。
func get_score_direction_for_seed(sequence_seed: int) -> Vector2:
	const GOLDEN_ANGLE_RADIANS: float = 2.39996323
	return Vector2.RIGHT.rotated(
		float(maxi(sequence_seed - 1, 0)) * GOLDEN_ANGLE_RADIANS
	)


# --- 私有/辅助方法 ---

func _draw_warmup_primitives() -> void:
	var transparent: Color = Color(1.0, 1.0, 1.0, 0.0)
	draw_colored_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE]),
		transparent
	)
	draw_string(
		_FEEDBACK_FONT,
		Vector2.ZERO,
		"+0",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		transparent
	)


func _draw_turn_impact() -> void:
	var progress: float = clampf(_turn_elapsed / _turn_duration, 0.0, 1.0)
	var travel_progress: float = _ease_out_cubic(progress)
	var alpha: float = (1.0 - smoothstep(0.44, 1.0, progress)) * smoothstep(0.0, 0.08, progress)
	var tangent: Vector2 = Vector2(-_turn_direction.y, _turn_direction.x)
	var edge_center: Vector2 = _turn_rect.get_center()
	var span: float = 0.0
	if absf(_turn_direction.x) >= absf(_turn_direction.y):
		edge_center.x = _turn_rect.end.x if _turn_direction.x > 0.0 else _turn_rect.position.x
		span = _turn_rect.size.y * 0.82
	else:
		edge_center.y = _turn_rect.end.y if _turn_direction.y > 0.0 else _turn_rect.position.y
		span = _turn_rect.size.x * 0.82

	_draw_impact_edge(edge_center, tangent, span, progress, alpha)
	for index: int in range(_turn_fragment_count):
		var normalized: float = (
			0.0
			if _turn_fragment_count <= 1
			else float(index) / float(_turn_fragment_count - 1) - 0.5
		)
		var jitter: float = (
			(_hash01(float(index * 37 + _turn_seed * 19)) - 0.5)
			* 18.0
			* _turn_motion_scale
		)
		var start: Vector2 = edge_center + tangent * (normalized * span + jitter)
		var outward_distance: float = (
			24.0 + float(_turn_tier) * 11.0 + float(index % 4) * 6.0
		) * _turn_motion_scale
		var tangent_drift: float = (
			(-1.0 if index % 2 == 0 else 1.0)
			* (8.0 + float(index % 3) * 5.0)
			* _turn_motion_scale
		)
		var center: Vector2 = (
			start
			+ _turn_direction * outward_distance * travel_progress
			+ tangent * tangent_drift * sin(progress * PI)
		)
		var size_value: float = 9.0 + float(index % 4) * 4.0 + float(_turn_tier) * 1.5
		var angle_radians: float = (
			_turn_direction.angle()
			+ float(index % 5 - 2) * 0.24
			+ progress * (-1.2 if index % 2 == 0 else 1.2)
		)
		var fragment_color: Color = _get_fragment_color(index).lerp(_turn_color, 0.34)
		fragment_color.a = alpha * (0.72 + float(index % 3) * 0.12)
		_draw_paper_fragment(center, size_value, angle_radians, fragment_color, index % 3 == 0)


func _draw_impact_edge(
	edge_center: Vector2,
	tangent: Vector2,
	span: float,
	progress: float,
	alpha: float
) -> void:
	var line_color: Color = _turn_color
	line_color.a = alpha * (1.0 - progress) * 0.92
	var half_span: float = span * (0.28 + _ease_out_cubic(progress) * 0.22)
	draw_line(
		edge_center - tangent * half_span,
		edge_center + tangent * half_span,
		line_color,
		maxf(8.0 - progress * 5.0, 2.0),
		true
	)
	var echo_color: Color = _PAPER_COLOR
	echo_color.a = alpha * 0.58
	draw_line(
		edge_center - tangent * half_span + _turn_direction * 5.0,
		edge_center + tangent * half_span + _turn_direction * 5.0,
		echo_color,
		2.0,
		true
	)


func _draw_merge_burst(burst: MergeBurst) -> void:
	var progress: float = clampf(burst.elapsed / burst.duration, 0.0, 1.0)
	var travel_progress: float = _ease_out_cubic(progress)
	var fade: float = 1.0 - smoothstep(0.48, 1.0, progress)
	var pop: float = smoothstep(0.0, 0.10, progress)
	var shard_count: int = burst.shard_count
	var phase: float = _hash01(float(burst.random_seed * 13)) * TAU

	if burst.feedback_type == &"merge" or burst.feedback_type == &"transform":
		var ring_color: Color = burst.color.lerp(_PAPER_COLOR, 0.42)
		ring_color.a = fade * pop * 0.74
		draw_arc(
			burst.position,
			lerpf(10.0, 62.0, travel_progress * burst.motion_scale),
			0.0,
			TAU,
			32,
			ring_color,
			maxf(7.0 - progress * 5.5, 1.0),
			true
		)

	for index: int in range(shard_count):
		var angle: float = phase + TAU * float(index) / float(maxi(shard_count, 1))
		var direction: Vector2 = Vector2.RIGHT.rotated(angle)
		var distance: float = (
			(22.0 + float(index % 3) * 10.0)
			* travel_progress
			* burst.motion_scale
		)
		var center: Vector2 = burst.position + direction * distance
		var shard_color: Color = burst.color.lerp(_get_fragment_color(index), 0.36)
		shard_color.a = fade * pop * (0.70 + float(index % 3) * 0.10)
		_draw_paper_fragment(
			center,
			8.0 + float(index % 3) * 3.5,
			angle + progress * (-1.4 if index % 2 == 0 else 1.4),
			shard_color,
			index % 2 == 0
		)

	if burst.label_text.is_empty():
		return
	var score_direction: Vector2 = get_score_direction_for_seed(burst.random_seed)
	var score_distance: float = lerpf(
		62.0,
		98.0,
		_hash01(float(burst.random_seed * 47 + 11))
	)
	var score_center: Vector2 = (
		burst.position
		+ score_direction * score_distance * travel_progress * burst.motion_scale
	)
	var main_label_color: Color = _INK_COLOR.lerp(burst.color, 0.34)
	main_label_color.a = fade * pop
	var main_label_outline: Color = _PAPER_COLOR
	main_label_outline.a = fade * pop * 0.92
	draw_string(
		_FEEDBACK_FONT,
		score_center + Vector2(-52.0, 10.0) + Vector2(2.0, 2.0),
		burst.label_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		104.0,
		30,
		main_label_outline
	)
	draw_string(
		_FEEDBACK_FONT,
		score_center + Vector2(-52.0, 10.0),
		burst.label_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		104.0,
		30,
		main_label_color
	)


func _draw_paper_fragment(
	center: Vector2,
	size_value: float,
	angle_radians: float,
	color: Color,
	is_triangle: bool
) -> void:
	var local_points: PackedVector2Array
	if is_triangle:
		local_points = PackedVector2Array([
			Vector2(size_value * 0.72, 0.0),
			Vector2(-size_value * 0.48, -size_value * 0.42),
			Vector2(-size_value * 0.34, size_value * 0.52),
		])
	else:
		local_points = PackedVector2Array([
			Vector2(-size_value * 0.62, -size_value * 0.24),
			Vector2(size_value * 0.62, -size_value * 0.36),
			Vector2(size_value * 0.52, size_value * 0.30),
			Vector2(-size_value * 0.48, size_value * 0.38),
		])
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in local_points:
		var _append_result: bool = points.append(center + point.rotated(angle_radians))
	draw_colored_polygon(points, color)
	var outline: PackedVector2Array = points.duplicate()
	var _outline_append_result: bool = outline.append(points[0])
	var outline_color: Color = _INK_COLOR
	outline_color.a = color.a * 0.42
	draw_polyline(outline, outline_color, 1.0, true)


func _get_fragment_color(index: int) -> Color:
	match index % 4:
		0:
			return _PAPER_COLOR
		1:
			return _CYAN_COLOR
		2:
			return _GOLD_COLOR
		_:
			return _CORAL_COLOR


func _get_tier_color(tier: int) -> Color:
	if tier >= 3:
		return _CORAL_COLOR
	if tier >= 2:
		return _GOLD_COLOR
	if tier >= 1:
		return _CYAN_COLOR
	return _PAPER_COLOR


func _normalize_label(feedback_type: StringName, label_text: String) -> String:
	if label_text.is_empty():
		return "!" if feedback_type == &"transform" else ""
	if feedback_type == &"merge" and not label_text.begins_with("+") and not label_text.begins_with("-"):
		return "+" + label_text
	return label_text


func _hash01(value: float) -> float:
	return fposmod(sin(value * 12.9898 + 78.233) * 43758.5453, 1.0)


func _ease_out_cubic(value: float) -> float:
	var inverse: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


# --- 内部类型 ---

class MergeBurst:
	var position: Vector2 = Vector2.ZERO
	var elapsed: float = 0.0
	var duration: float = 0.42
	var feedback_type: StringName = &"merge"
	var label_text: String = ""
	var color: Color = Color.WHITE
	var random_seed: int = 0
	var shard_count: int = 0
	var motion_scale: float = 1.0
