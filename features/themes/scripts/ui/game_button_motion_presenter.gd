## GameButtonMotionPresenter: 在稳定的按钮命中框内呈现纸片式交互动效。
##
## Presenter 只移动内部视觉纸片，不改变 BaseButton 的布局矩形、命中范围或文字。
## 因此 hover/focus 可以具有明显的展开和受力倾斜，同时不会被 ScrollContainer 裁边。
class_name GameButtonMotionPresenter
extends Control


# --- 枚举 ---

enum MotionState {
	REST,
	ACTIVE,
	SELECTED,
	PRESSED,
	DISABLED,
}


# --- 常量 ---

const FACE_NODE_NAME: String = "PaperFace"
const _ACTIVE_OVERSHOOT_DURATION: float = 0.058
const _ACTIVE_SETTLE_DURATION: float = 0.092
const _RESTORE_DURATION: float = 0.092
const _PRESS_DURATION: float = 0.052
const _DEAL_DURATION: float = 0.180
const _MAX_TILT_RADIANS: float = 0.020
const _MIN_FACE_DIMENSION: float = 6.0
const _SAFE_EDGE_INSET: float = 1.0
const _STYLE_NAME: StringName = &"panel"


# --- 私有变量 ---

var _button: BaseButton = null
var _face: Panel = null
var _rest_style: StyleBox = null
var _active_style: StyleBox = null
var _selected_style: StyleBox = null
var _pressed_style: StyleBox = null
var _disabled_style: StyleBox = null
var _motion_state: MotionState = MotionState.REST
var _motion_tween: Tween = null
var _tilt_direction: float = -1.0
var _configured: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_ensure_face()
	var _resize_connection: int = resized.connect(_on_presenter_resized)
	call_deferred(&"_refresh_after_layout")


# --- 公共方法 ---

## 配置按钮语义状态对应的 StyleBox。
## @param button: Presenter 所属的稳定布局按钮。
## @param rest_style: 静止态纸片样式。
## @param active_style: hover 或 focus 的强调态纸片样式。
## @param selected_style: toggle 选中态纸片样式。
## @param pressed_style: 按下态纸片样式。
## @param disabled_style: 禁用态纸片样式。
func configure(
	button: BaseButton,
	rest_style: StyleBox,
	active_style: StyleBox,
	selected_style: StyleBox,
	pressed_style: StyleBox,
	disabled_style: StyleBox
) -> void:
	_kill_motion_tween()
	_button = button
	_rest_style = rest_style
	_active_style = active_style
	_selected_style = selected_style
	_pressed_style = pressed_style
	_disabled_style = disabled_style
	_tilt_direction = -1.0 if button.get_instance_id() % 2 == 0 else 1.0
	_configured = true
	_ensure_face()
	_apply_style_for_state(_motion_state)
	_apply_geometry_immediately(_motion_state)


## 切换纸片的语义状态。
## @param state: 目标语义状态。
## @param animated: 是否播放状态过渡。
## @param reduced_motion: 是否直接落到减少动态后的终态。
func set_motion_state(
	state: MotionState,
	animated: bool = true,
	reduced_motion: bool = false
) -> void:
	if not _configured:
		return
	_motion_state = state
	_kill_motion_tween()
	_apply_style_for_state(state)
	if reduced_motion or not animated or not is_inside_tree():
		_apply_geometry_immediately(state)
		return
	if state == MotionState.ACTIVE:
		_play_active_overshoot()
	elif state == MotionState.PRESSED:
		_play_single_phase(_get_target_rect(state), _PRESS_DURATION, Tween.TRANS_QUAD)
	else:
		_play_single_phase(_get_target_rect(state), _RESTORE_DURATION, Tween.TRANS_BACK)


## 让纸片从指定方向错峰“发牌”进入，但保持按钮命中框原地不动。
## @param offset: 纸片相对终点的起始偏移。
## @param target_state: 入场完成后应保持的当前语义状态。
## @param delay: 开始入场前的等待时间。
## @param reduced_motion: 是否跳过位移、缩放和旋转。
func play_deal_in(
	offset: Vector2,
	target_state: MotionState,
	delay: float = 0.0,
	reduced_motion: bool = false
) -> void:
	if not _configured:
		return
	_motion_state = target_state
	_kill_motion_tween()
	_apply_style_for_state(_motion_state)
	var target_rect: Rect2 = _get_target_rect(_motion_state)
	if reduced_motion or not is_inside_tree():
		_apply_face_rect(target_rect)
		_face.rotation = 0.0
		_face.modulate = Color.WHITE
		return

	var start_rect: Rect2 = target_rect
	start_rect.position += offset
	start_rect.size *= Vector2(0.82, 0.72)
	start_rect.position += (target_rect.size - start_rect.size) * 0.5
	var start_rotation: float = _tilt_direction * _MAX_TILT_RADIANS
	start_rect = _clamp_rect_to_visual_envelope(
		start_rect,
		start_rotation
	)
	_apply_face_rect(start_rect)
	_face.rotation = start_rotation
	_face.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween: Tween = create_tween()
	_motion_tween = tween
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var position_tweener: PropertyTweener = tween.tween_property(
		_face,
		"position",
		target_rect.position,
		_DEAL_DURATION
	)
	var _position_delay_result: Tweener = position_tweener.set_delay(maxf(delay, 0.0))
	var _position_curve: Tweener = position_tweener.set_trans(Tween.TRANS_BACK)
	var _position_ease: Tweener = position_tweener.set_ease(Tween.EASE_OUT)
	var size_tweener: PropertyTweener = tween.tween_property(
		_face,
		"size",
		target_rect.size,
		_DEAL_DURATION
	)
	var _size_delay_result: Tweener = size_tweener.set_delay(maxf(delay, 0.0))
	var _size_curve: Tweener = size_tweener.set_trans(Tween.TRANS_BACK)
	var _size_ease: Tweener = size_tweener.set_ease(Tween.EASE_OUT)
	var rotation_tweener: PropertyTweener = tween.tween_property(
		_face,
		"rotation",
		0.0,
		_DEAL_DURATION
	)
	var _rotation_delay_result: Tweener = rotation_tweener.set_delay(maxf(delay, 0.0))
	var _rotation_curve: Tweener = rotation_tweener.set_trans(Tween.TRANS_BACK)
	var _rotation_ease: Tweener = rotation_tweener.set_ease(Tween.EASE_OUT)
	var modulate_tweener: PropertyTweener = tween.tween_property(
		_face,
		"modulate",
		Color.WHITE,
		_DEAL_DURATION * 0.62
	)
	var _modulate_delay_result: Tweener = modulate_tweener.set_delay(maxf(delay, 0.0))
	var _modulate_curve: Tweener = modulate_tweener.set_trans(Tween.TRANS_QUAD)
	var _modulate_ease: Tweener = modulate_tweener.set_ease(Tween.EASE_OUT)


## 立即结束当前动效并落到当前语义终态。
func complete_motion() -> void:
	_kill_motion_tween()
	_apply_geometry_immediately(_motion_state)


## 返回实际绘制纸片，供集中样式刷新与视觉验收使用。
func get_face() -> Panel:
	_ensure_face()
	return _face


## 返回纸片当前语义状态。
func get_motion_state() -> MotionState:
	return _motion_state


## 使用指针接触侧决定纸片受力倾斜方向；键盘路径保留稳定的交错方向。
## @param local_position: 指针相对于按钮命中框的位置。
func set_contact_position(local_position: Vector2) -> void:
	if size.x <= 0.0:
		return
	_tilt_direction = -1.0 if local_position.x <= size.x * 0.5 else 1.0


# --- 私有/辅助方法 ---

func _ensure_face() -> void:
	if is_instance_valid(_face):
		return
	var existing_node: Node = get_node_or_null(FACE_NODE_NAME)
	if existing_node is Panel:
		_face = existing_node
	else:
		_face = Panel.new()
		_face.name = FACE_NODE_NAME
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.focus_mode = Control.FOCUS_NONE
		_face.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(_face)
	var _face_resize_connection: int = _face.resized.connect(
		_on_face_resized
	)


func _apply_style_for_state(state: MotionState) -> void:
	if not is_instance_valid(_face):
		return
	var style: StyleBox = _rest_style
	if state == MotionState.ACTIVE:
		style = _active_style
	elif state == MotionState.SELECTED:
		style = _selected_style
	elif state == MotionState.PRESSED:
		style = _pressed_style
	elif state == MotionState.DISABLED:
		style = _disabled_style
	if is_instance_valid(style):
		_face.add_theme_stylebox_override(_STYLE_NAME, style)


func _apply_geometry_immediately(state: MotionState) -> void:
	if not is_instance_valid(_face):
		return
	_apply_face_rect(_get_target_rect(state))
	_face.rotation = 0.0
	_face.modulate = Color.WHITE


func _play_active_overshoot() -> void:
	var target_rect: Rect2 = _get_target_rect(MotionState.ACTIVE)
	# 只在水平方向做轻微过冲，保留上下旋转余量；这样既有“被顶开”的
	# 纸片受力感，也不会让倾斜角被安全包络压缩到几乎不可见。
	var overshoot_rect: Rect2 = Rect2(
		target_rect.position - Vector2(1.0, 0.0),
		target_rect.size + Vector2(2.0, 0.0)
	)
	overshoot_rect = _clamp_rect_to_safe_envelope(overshoot_rect)
	var tween: Tween = create_tween()
	_motion_tween = tween
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var position_tweener: PropertyTweener = tween.tween_property(
		_face,
		"position",
		overshoot_rect.position,
		_ACTIVE_OVERSHOOT_DURATION
	)
	var _position_curve: Tweener = position_tweener.set_trans(Tween.TRANS_QUAD)
	var _position_ease: Tweener = position_tweener.set_ease(Tween.EASE_OUT)
	var size_tweener: PropertyTweener = tween.tween_property(
		_face,
		"size",
		overshoot_rect.size,
		_ACTIVE_OVERSHOOT_DURATION
	)
	var _size_curve: Tweener = size_tweener.set_trans(Tween.TRANS_QUAD)
	var _size_ease: Tweener = size_tweener.set_ease(Tween.EASE_OUT)
	var rotation_tweener: PropertyTweener = tween.tween_property(
		_face,
		"rotation",
		_tilt_direction * _get_safe_tilt_radians(overshoot_rect),
		_ACTIVE_OVERSHOOT_DURATION
	)
	var _rotation_curve: Tweener = rotation_tweener.set_trans(Tween.TRANS_QUAD)
	var _rotation_ease: Tweener = rotation_tweener.set_ease(Tween.EASE_OUT)
	var modulate_tweener: PropertyTweener = tween.tween_property(
		_face,
		"modulate",
		Color.WHITE,
		_ACTIVE_OVERSHOOT_DURATION
	)
	var _modulate_curve: Tweener = modulate_tweener.set_trans(Tween.TRANS_QUAD)
	var _modulate_ease: Tweener = modulate_tweener.set_ease(Tween.EASE_OUT)
	var _finished_connection: int = tween.finished.connect(
		_settle_active.bind(target_rect),
		CONNECT_ONE_SHOT
	)


func _settle_active(target_rect: Rect2) -> void:
	if _motion_state != MotionState.ACTIVE or not is_instance_valid(_face):
		return
	var tween: Tween = create_tween()
	_motion_tween = tween
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var position_tweener: PropertyTweener = tween.tween_property(
		_face,
		"position",
		target_rect.position,
		_ACTIVE_SETTLE_DURATION
	)
	var _position_curve: Tweener = position_tweener.set_trans(Tween.TRANS_BACK)
	var _position_ease: Tweener = position_tweener.set_ease(Tween.EASE_OUT)
	var size_tweener: PropertyTweener = tween.tween_property(
		_face,
		"size",
		target_rect.size,
		_ACTIVE_SETTLE_DURATION
	)
	var _size_curve: Tweener = size_tweener.set_trans(Tween.TRANS_BACK)
	var _size_ease: Tweener = size_tweener.set_ease(Tween.EASE_OUT)
	var rotation_tweener: PropertyTweener = tween.tween_property(
		_face,
		"rotation",
		0.0,
		_ACTIVE_SETTLE_DURATION
	)
	var _rotation_curve: Tweener = rotation_tweener.set_trans(Tween.TRANS_BACK)
	var _rotation_ease: Tweener = rotation_tweener.set_ease(Tween.EASE_OUT)


func _play_single_phase(
	target_rect: Rect2,
	duration: float,
	transition: Tween.TransitionType
) -> void:
	var tween: Tween = create_tween()
	_motion_tween = tween
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var position_tweener: PropertyTweener = tween.tween_property(
		_face,
		"position",
		target_rect.position,
		duration
	)
	var _position_curve: Tweener = position_tweener.set_trans(transition)
	var _position_ease: Tweener = position_tweener.set_ease(Tween.EASE_OUT)
	var size_tweener: PropertyTweener = tween.tween_property(
		_face,
		"size",
		target_rect.size,
		duration
	)
	var _size_curve: Tweener = size_tweener.set_trans(transition)
	var _size_ease: Tweener = size_tweener.set_ease(Tween.EASE_OUT)
	var rotation_tweener: PropertyTweener = tween.tween_property(
		_face,
		"rotation",
		0.0,
		duration
	)
	var _rotation_curve: Tweener = rotation_tweener.set_trans(transition)
	var _rotation_ease: Tweener = rotation_tweener.set_ease(Tween.EASE_OUT)
	var modulate_tweener: PropertyTweener = tween.tween_property(
		_face,
		"modulate",
		Color.WHITE,
		duration
	)
	var _modulate_curve: Tweener = modulate_tweener.set_trans(Tween.TRANS_QUAD)
	var _modulate_ease: Tweener = modulate_tweener.set_ease(Tween.EASE_OUT)


func _get_target_rect(state: MotionState) -> Rect2:
	var presenter_size: Vector2 = size
	if presenter_size.x <= 0.0 or presenter_size.y <= 0.0:
		if is_instance_valid(_button):
			presenter_size = _button.size
	var rest_left: float = clampf(presenter_size.x * 0.050, 8.0, 32.0)
	var rest_top: float = clampf(presenter_size.y * 0.12, 5.0, 9.0)
	var active_left: float = (
		clampf(presenter_size.x * 0.010, 3.0, 5.0) + 1.0
	)
	var active_top: float = clampf(presenter_size.y * 0.060, 3.0, 5.0)
	var left: float = rest_left
	var top: float = rest_top
	var right: float = rest_left + 3.0
	var bottom: float = rest_top + 5.0
	if state == MotionState.ACTIVE or state == MotionState.SELECTED:
		left = active_left
		top = active_top
		right = active_left + 4.0
		bottom = active_top + 7.0
	elif state == MotionState.PRESSED:
		top += 2.0
		bottom = maxf(bottom - 2.0, 3.0)
	return _rect_from_insets(presenter_size, left, top, right, bottom)


func _rect_from_insets(
	envelope_size: Vector2,
	left: float,
	top: float,
	right: float,
	bottom: float
) -> Rect2:
	var available_width: float = maxf(
		envelope_size.x - left - right,
		_MIN_FACE_DIMENSION
	)
	var available_height: float = maxf(
		envelope_size.y - top - bottom,
		_MIN_FACE_DIMENSION
	)
	return Rect2(
		Vector2(left, top),
		Vector2(available_width, available_height)
	)


func _clamp_rect_to_safe_envelope(rect: Rect2) -> Rect2:
	var safe_rect: Rect2 = Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
	if safe_rect.size.x < _MIN_FACE_DIMENSION or safe_rect.size.y < _MIN_FACE_DIMENSION:
		return _get_target_rect(_motion_state)
	var clamped_position: Vector2 = rect.position.max(safe_rect.position)
	var clamped_end: Vector2 = rect.end.min(safe_rect.end)
	var clamped_size: Vector2 = clamped_end - clamped_position
	if (
		clamped_size.x < _MIN_FACE_DIMENSION
		or clamped_size.y < _MIN_FACE_DIMENSION
	):
		return _get_target_rect(_motion_state)
	return Rect2(clamped_position, clamped_size)


func _get_safe_tilt_radians(rect: Rect2) -> float:
	if not is_instance_valid(_face) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 0.0
	var visual_rect: Rect2 = _get_local_visual_rect(rect.size)

	var lower: float = 0.0
	var upper: float = _MAX_TILT_RADIANS
	for _iteration: int in range(12):
		var candidate: float = (lower + upper) * 0.5
		if _rotated_visual_fits_envelope(
			rect,
			visual_rect,
			candidate * _tilt_direction
		):
			lower = candidate
		else:
			upper = candidate
	return lower


func _clamp_rect_to_visual_envelope(
	rect: Rect2,
	radians: float
) -> Rect2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return _get_target_rect(_motion_state)
	var visual_bounds: Rect2 = _get_rotated_visual_bounds(
		rect,
		_get_local_visual_rect(rect.size),
		radians
	)
	var safe_rect: Rect2 = Rect2(
		Vector2.ONE * _SAFE_EDGE_INSET,
		size - Vector2.ONE * _SAFE_EDGE_INSET * 2.0
	)
	if (
		visual_bounds.size.x > safe_rect.size.x
		or visual_bounds.size.y > safe_rect.size.y
	):
		return _get_target_rect(_motion_state)
	var correction: Vector2 = Vector2.ZERO
	if visual_bounds.position.x < safe_rect.position.x:
		correction.x += safe_rect.position.x - visual_bounds.position.x
	elif visual_bounds.end.x > safe_rect.end.x:
		correction.x -= visual_bounds.end.x - safe_rect.end.x
	if visual_bounds.position.y < safe_rect.position.y:
		correction.y += safe_rect.position.y - visual_bounds.position.y
	elif visual_bounds.end.y > safe_rect.end.y:
		correction.y -= visual_bounds.end.y - safe_rect.end.y
	rect.position += correction
	return rect


func _get_local_visual_rect(face_size: Vector2) -> Rect2:
	var visual_rect: Rect2 = Rect2(Vector2.ZERO, face_size)
	var style_value: StyleBox = _face.get_theme_stylebox(_STYLE_NAME)
	if style_value is StyleBoxFlat:
		var flat_style: StyleBoxFlat = style_value
		if flat_style.shadow_color.a > 0.0:
			var shadow_rect: Rect2 = visual_rect.grow(
				float(flat_style.shadow_size)
			)
			shadow_rect.position += flat_style.shadow_offset
			visual_rect = visual_rect.merge(shadow_rect)
	return visual_rect


func _get_rotated_visual_bounds(
	face_rect: Rect2,
	local_visual_rect: Rect2,
	radians: float
) -> Rect2:
	var pivot: Vector2 = face_rect.size * 0.5
	var corners: Array[Vector2] = [
		local_visual_rect.position,
		Vector2(local_visual_rect.end.x, local_visual_rect.position.y),
		local_visual_rect.end,
		Vector2(local_visual_rect.position.x, local_visual_rect.end.y),
	]
	var first_point: Vector2 = (
		face_rect.position
		+ pivot
		+ (corners[0] - pivot).rotated(radians)
	)
	var minimum: Vector2 = first_point
	var maximum: Vector2 = first_point
	for corner: Vector2 in corners.slice(1):
		var transformed: Vector2 = (
			face_rect.position
			+ pivot
			+ (corner - pivot).rotated(radians)
		)
		minimum = minimum.min(transformed)
		maximum = maximum.max(transformed)
	return Rect2(minimum, maximum - minimum)


func _rotated_visual_fits_envelope(
	face_rect: Rect2,
	local_visual_rect: Rect2,
	radians: float
) -> bool:
	var visual_bounds: Rect2 = _get_rotated_visual_bounds(
		face_rect,
		local_visual_rect,
		radians
	)
	var minimum: Vector2 = Vector2(
		_SAFE_EDGE_INSET,
		_SAFE_EDGE_INSET
	)
	var maximum: Vector2 = size - minimum
	return (
		visual_bounds.position.x >= minimum.x
		and visual_bounds.position.y >= minimum.y
		and visual_bounds.end.x <= maximum.x
		and visual_bounds.end.y <= maximum.y
	)


func _apply_face_rect(rect: Rect2) -> void:
	if not is_instance_valid(_face):
		return
	_face.position = rect.position
	_face.size = rect.size
	_face.pivot_offset = rect.size * 0.5


func _kill_motion_tween() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null


func _refresh_after_layout() -> void:
	if not _configured:
		return
	_apply_geometry_immediately(_motion_state)


# --- 信号处理函数 ---

func _on_presenter_resized() -> void:
	if not _configured:
		return
	_kill_motion_tween()
	_apply_geometry_immediately(_motion_state)


func _on_face_resized() -> void:
	if not is_instance_valid(_face):
		return
	_face.pivot_offset = _face.size * 0.5
