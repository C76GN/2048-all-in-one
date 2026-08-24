## BoardMotionBackdrop: 棋盘后方的低成本局部纸片棋格反馈。
##
## 它只消费已经提交的回合方向和主题反馈参数，不参与棋盘状态、随机流或回放。
## 常态保留很淡的局部棋格，回合冲击时短暂增强并沿方向错版，呼应棋盘受力。
class_name BoardMotionBackdrop
extends Node2D


# --- 常量 ---

const _PAPER_LIGHT: Color = Color(1.0, 0.972549, 0.909804, 1.0)
const _PAPER_MID: Color = Color(0.913725, 0.901961, 0.862745, 1.0)
const _CYAN: Color = Color(0.619608, 0.858824, 0.835294, 1.0)
const _GOLD: Color = Color(0.937255, 0.819608, 0.364706, 1.0)
const _INK: Color = Color(0.184314, 0.188235, 0.215686, 1.0)
const _BASE_MARGIN: float = 34.0
const _MIN_CHECKER_SIZE: float = 52.0
const _CHECKER_DIVISOR: float = 7.0
const _BACKDROP_Z_INDEX: int = 0
const _SQUARE_ASPECT_TOLERANCE: float = 0.08
const _RECTANGULAR_ROTATION_DEGREES: float = 6.0


# --- 私有变量 ---

var _board_size: Vector2 = Vector2.ZERO
var _elapsed: float = 1.0
var _duration: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _motion_scale: float = 0.0
var _tier: int = 0
var _accent_color: Color = _CYAN
var _rotation_start: float = 0.0
var _rotation_target: float = 0.0
var _rotation_returns_to_start: bool = false
var _fragment_count: int = 0
var _impulse_seed: int = 0


# --- Godot 生命周期方法 ---

func _ready() -> void:
	z_index = _BACKDROP_Z_INDEX
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, _duration)
	if _tier > 0 and _motion_scale > 0.0:
		if _rotation_returns_to_start:
			_update_rectangular_rotation()
		else:
			var rotation_duration: float = minf(_duration * 0.58, 0.32)
			var rotation_progress: float = clampf(_elapsed / rotation_duration, 0.0, 1.0)
			var eased_rotation_progress: float = 1.0 - pow(1.0 - rotation_progress, 5.0)
			rotation = lerp_angle(
				_rotation_start,
				_rotation_target,
				eased_rotation_progress
			)
	queue_redraw()
	if _elapsed >= _duration:
		rotation = _rotation_start if _rotation_returns_to_start else _rotation_target
		set_process(false)


func _draw() -> void:
	if _board_size.x <= 0.0 or _board_size.y <= 0.0:
		return

	var progress: float = (
		clampf(_elapsed / _duration, 0.0, 1.0)
		if _duration > 0.0
		else 1.0
	)
	var impulse: float = sin(progress * PI) * _motion_scale
	var settle: float = sin(progress * PI * 2.0) * (1.0 - progress) * _motion_scale
	var margin: float = _BASE_MARGIN + impulse * (18.0 + float(_tier) * 5.0)
	var draw_offset: Vector2 = (
		-_direction * impulse * (10.0 + float(_tier) * 2.0)
		+ Vector2(-_direction.y, _direction.x) * settle * 4.0
	)
	var field_rect: Rect2 = Rect2(
		-_board_size * 0.5 - Vector2.ONE * margin + draw_offset,
		_board_size + Vector2.ONE * margin * 2.0
	)
	var cell_size: float = maxf(
		minf(_board_size.x, _board_size.y) / _CHECKER_DIVISOR,
		_MIN_CHECKER_SIZE
	)
	var column_count: int = ceili(field_rect.size.x / cell_size)
	var row_count: int = ceili(field_rect.size.y / cell_size)
	# 常态只保留纸张上的极弱校样格；明显的错版只在已提交回合反馈期间出现。
	var base_alpha: float = 0.026 + impulse * 0.12

	for row: int in range(row_count):
		for column: int in range(column_count):
			var checker_rect: Rect2 = Rect2(
				field_rect.position + Vector2(column, row) * cell_size,
				Vector2.ONE * (cell_size + 0.5)
			)
			var checker_color: Color = _get_checker_color(column, row)
			checker_color.a = base_alpha * (0.86 if (column + row) % 2 == 0 else 1.0)
			draw_rect(checker_rect, checker_color)

	var outline_color: Color = _INK
	outline_color.a = 0.018 + impulse * 0.06
	draw_rect(field_rect, outline_color, false, 2.0, true)
	_draw_paper_fragments(progress)


# --- 公共方法 ---

## 更新局部棋盘尺寸；外层视口仍独占最终缩放。
## @param board_size: 棋盘稳定局部世界尺寸。
func set_board_size(board_size: Vector2) -> void:
	_board_size = Vector2(maxf(board_size.x, 0.0), maxf(board_size.y, 0.0))
	if not _is_effectively_square():
		rotation = 0.0
		_rotation_start = 0.0
		_rotation_target = 0.0
	queue_redraw()


## 播放一次不写回逻辑状态的局部背景受力反馈。
## @param direction: 已提交回合的移动方向。
## @param tier: 已分类的回合反馈等级。
## @param duration: 背景反馈持续时间。
## @param motion_scale: 当前无障碍反馈预算的动态倍率。
## @param accent_color: 当前主题或合并方块的强调色。
## @param fragment_count: 后层纸片数量。
func play_turn_impulse(
	direction: Vector2,
	tier: int,
	duration: float,
	motion_scale: float,
	accent_color: Color,
	fragment_count: int
) -> void:
	if direction.is_zero_approx() or _board_size.is_zero_approx():
		return
	_direction = direction.normalized()
	_tier = maxi(tier, 0)
	_duration = maxf(duration, 0.01)
	_motion_scale = maxf(motion_scale, 0.0)
	_fragment_count = maxi(fragment_count, 0)
	_accent_color = accent_color
	_accent_color.a = 1.0
	_impulse_seed += 1
	_rotation_start = rotation
	_rotation_returns_to_start = _tier > 0 and not _is_effectively_square()
	if _rotation_returns_to_start:
		rotation = 0.0
		_rotation_start = 0.0
	var rotation_sign: float = -1.0 if direction.x + direction.y < 0.0 else 1.0
	var normalized_motion_scale: float = clampf(_motion_scale, 0.0, 1.0)
	_rotation_target = (
		_rotation_start
		+ rotation_sign
		* (
			deg_to_rad(_RECTANGULAR_ROTATION_DEGREES)
			if _rotation_returns_to_start
			else PI * 0.5
		)
		* normalized_motion_scale
		if _tier > 0
		else _rotation_start
	)
	_elapsed = 0.0
	if _motion_scale <= 0.0:
		_elapsed = _duration
		rotation = 0.0
		_rotation_start = 0.0
		_rotation_target = 0.0
		_rotation_returns_to_start = false
		set_process(false)
		queue_redraw()
		return
	set_process(true)
	queue_redraw()


## 清除动态冲击，但保留不运动的低对比局部棋格。
func reset_feedback() -> void:
	_elapsed = _duration
	_motion_scale = 0.0
	rotation = 0.0
	_rotation_start = 0.0
	_rotation_target = 0.0
	_rotation_returns_to_start = false
	_fragment_count = 0
	set_process(false)
	queue_redraw()


# --- 私有/辅助方法 ---

func _update_rectangular_rotation() -> void:
	var attack_duration: float = minf(_duration * 0.24, 0.12)
	if _elapsed <= attack_duration:
		var attack_progress: float = clampf(_elapsed / maxf(attack_duration, 0.01), 0.0, 1.0)
		var eased_attack: float = 1.0 - pow(1.0 - attack_progress, 4.0)
		rotation = lerp_angle(_rotation_start, _rotation_target, eased_attack)
		return
	var settle_duration: float = maxf(_duration - attack_duration, 0.01)
	var settle_progress: float = clampf(
		(_elapsed - attack_duration) / settle_duration,
		0.0,
		1.0
	)
	var eased_settle: float = 1.0 - pow(1.0 - settle_progress, 3.0)
	rotation = lerp_angle(_rotation_target, _rotation_start, eased_settle)


func _is_effectively_square() -> bool:
	var longest_side: float = maxf(_board_size.x, _board_size.y)
	if longest_side <= 0.0:
		return true
	return absf(_board_size.x - _board_size.y) / longest_side <= _SQUARE_ASPECT_TOLERANCE


func _get_checker_color(column: int, row: int) -> Color:
	var selector: int = (column + row * 3) % 6
	match selector:
		1:
			return _PAPER_MID.lerp(_accent_color, 0.16)
		3:
			return _CYAN.lerp(_PAPER_LIGHT, 0.48)
		5:
			return _GOLD.lerp(_PAPER_LIGHT, 0.58)
		_:
			return _PAPER_LIGHT if (column + row) % 2 == 0 else _PAPER_MID


func _draw_paper_fragments(progress: float) -> void:
	if _fragment_count <= 0 or _motion_scale <= 0.0:
		return
	var travel_progress: float = 1.0 - pow(1.0 - progress, 3.0)
	var alpha: float = (
		smoothstep(0.0, 0.08, progress)
		* (1.0 - smoothstep(0.42, 1.0, progress))
	)
	var half_size: Vector2 = _board_size * 0.5
	var estimated_cell_size: float = minf(
		115.0,
		minf(_board_size.x, _board_size.y) * 0.25
	)
	for index: int in range(_fragment_count):
		var angle: float = (
			float(index) * 2.39996323
			+ _hash01(float(_impulse_seed * 31 + index * 17)) * 0.72
		)
		var radial_direction: Vector2 = Vector2.RIGHT.rotated(angle)
		var safe_x: float = maxf(absf(radial_direction.x), 0.001)
		var safe_y: float = maxf(absf(radial_direction.y), 0.001)
		var edge_distance: float = minf(
			half_size.x / safe_x,
			half_size.y / safe_y
		)
		var start: Vector2 = radial_direction * edge_distance * 0.93
		var travel_distance: float = estimated_cell_size * lerpf(
			0.35,
			0.90,
			_hash01(float(index * 47 + _impulse_seed * 13))
		)
		var tangent: Vector2 = Vector2(-radial_direction.y, radial_direction.x)
		var drift: float = (
			_hash01(float(index * 23 + _impulse_seed * 7)) - 0.5
		) * estimated_cell_size * 0.32
		var center: Vector2 = (
			start
			+ radial_direction * travel_distance * travel_progress * _motion_scale
			+ tangent * drift * sin(progress * PI) * _motion_scale
		)
		var fragment_size: float = estimated_cell_size * lerpf(
			0.22,
			0.50,
			_hash01(float(index * 59 + 5))
		)
		var aspect_ratio: float = lerpf(
			0.58,
			1.0,
			_hash01(float(index * 71 + 9))
		)
		var fragment_color: Color = (
			_PAPER_LIGHT.lerp(_accent_color, 0.62)
			if index % 3 == 0
			else _PAPER_MID.lerp(_accent_color, 0.18)
		)
		fragment_color.a = alpha * (0.62 + float(index % 4) * 0.09)
		var fragment_rotation: float = (
			angle
			+ (progress * (-2.0 if index % 2 == 0 else 2.0))
		)
		_draw_rotated_rect(
			center,
			Vector2(fragment_size, fragment_size * aspect_ratio),
			fragment_rotation,
			fragment_color
		)


func _draw_rotated_rect(
	center: Vector2,
	rect_size: Vector2,
	angle: float,
	color: Color
) -> void:
	var half_size: Vector2 = rect_size * 0.5
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y).rotated(angle),
		center + Vector2(half_size.x, -half_size.y).rotated(angle),
		center + Vector2(half_size.x, half_size.y).rotated(angle),
		center + Vector2(-half_size.x, half_size.y).rotated(angle),
	])
	draw_colored_polygon(points, color)


func _hash01(value: float) -> float:
	return fposmod(sin(value * 12.9898 + 78.233) * 43758.5453, 1.0)
