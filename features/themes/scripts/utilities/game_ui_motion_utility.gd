## GameUiMotionUtility: 统一处理项目 UI 控件的轻量交互动效。
##
## 作为项目级 GFUtility，它负责按钮 hover、focus、press、面板入场和列表刷新表现。
## 静态色板和 StyleBox 由 GameUiStyleUtility 统一管理。
class_name GameUiMotionUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal interactive_control_selected(control: Control)
signal interactive_control_confirmed(control: Control)


# --- 常量 ---

const _BOUND_META: StringName = &"_game_ui_motion_bound"
const _HOVERED_META: StringName = &"_game_ui_motion_hovered"
const _FOCUSED_META: StringName = &"_game_ui_motion_focused"
const _BASE_SCALE_META: StringName = &"_game_ui_motion_base_scale"
const _TWEEN_META: StringName = &"_game_ui_motion_tween"
const _CONTROL_BASE_POSITION_META: StringName = &"_game_ui_motion_control_base_position"
const _CONTROL_BASE_SCALE_META: StringName = &"_game_ui_motion_control_base_scale"
const _CONTROL_BASE_MODULATE_META: StringName = &"_game_ui_motion_control_base_modulate"
const _CONTROL_TWEEN_META: StringName = &"_game_ui_motion_control_tween"
const _NUMERIC_TWEEN_META: StringName = &"_game_ui_motion_numeric_tween"
const _REST_MODULATE: Color = Color.WHITE
const _HOVER_MODULATE: Color = Color(0.98, 1.0, 0.99, 1.0)
const _FOCUS_MODULATE: Color = Color(1.0, 0.98, 1.0, 1.0)
const _PRESS_MODULATE: Color = Color(0.96, 0.94, 0.84, 1.0)
const _HOVER_SCALE: float = 1.012
const _PRESS_SCALE: float = 0.980
const _HOVER_DURATION: float = 0.11
const _PRESS_DURATION: float = 0.055
const _PANEL_INTRO_OFFSET: Vector2 = Vector2(0.0, 10.0)
const _PANEL_INTRO_SCALE: float = 0.992
const _PANEL_INTRO_DURATION: float = 0.18
const _CHILD_REVEAL_OFFSET: Vector2 = Vector2(8.0, 0.0)
const _CHILD_REVEAL_DURATION: float = 0.14
const _CHILD_REVEAL_STAGGER: float = 0.025
const _NUMERIC_CHANGE_DURATION: float = 0.22
const _NUMERIC_DELTA_DURATION: float = 0.36
const _NUMERIC_GAIN_COLOR: Color = Color(0.82, 0.69, 0.34, 1.0)
const _NUMERIC_LOSS_COLOR: Color = Color(0.58, 0.27, 0.19, 1.0)
const _NUMERIC_DELTA_START_OFFSET: Vector2 = Vector2(-3.0, 3.0)
const _NUMERIC_DELTA_END_OFFSET: Vector2 = Vector2(10.0, -26.0)


# --- 私有变量 ---

var _style: GameUiStyleUtility


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameUiStyleUtility]


func ready() -> void:
	_style = _get_style_utility()
	if not is_instance_valid(_style):
		push_error("[GameUiMotionUtility] 缺少 GameUiStyleUtility。")


func dispose() -> void:
	_style = null


func release_dependencies() -> void:
	_style = null
	super.release_dependencies()


# --- 公共方法 ---

## 递归绑定根节点下所有 BaseButton 控件。
## @param root: 要扫描的 UI 根节点。
## @return: 本次新绑定的按钮数量。
func bind_interactive_controls(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	if root is Control and is_instance_valid(_style):
		var root_control: Control = root
		_style.style_control(root_control)

	var bound_count: int = 0
	if root is BaseButton:
		var root_button: BaseButton = root
		if _bind_button(root_button):
			bound_count += 1

	for child: Node in root.get_children():
		bound_count += bind_interactive_controls(child)

	return bound_count


## 绑定单个按钮控件。
## @param button: 要绑定交互动效的按钮。
## @return: 本次完成新绑定时返回 true。
func bind_button(button: BaseButton) -> bool:
	return _bind_button(button)


## 播放单个面板的入场动画。
## @param panel: 要播放入场动效的面板控件。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_panel_intro(panel: Control) -> Tween:
	return play_control_reveal(
		panel,
		_PANEL_INTRO_OFFSET,
		_PANEL_INTRO_DURATION,
		0.0,
		_PANEL_INTRO_SCALE
	)


## 播放单个控件的出现动画。
## @param control: 要播放出现动效的控件。
## @param offset: 动画起点相对于原始位置的偏移。
## @param duration: 动画持续时间。
## @param delay: 动画开始前的延迟时间。
## @param start_scale: 动画起点相对于原始缩放的倍率。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_control_reveal(
	control: Control,
	offset: Vector2 = _CHILD_REVEAL_OFFSET,
	duration: float = _CHILD_REVEAL_DURATION,
	delay: float = 0.0,
	start_scale: float = 1.0
) -> Tween:
	return _play_control_reveal(control, offset, duration, delay, start_scale, true)


## 播放单个控件的短促强调反馈，并恢复控件首次记录的基础状态。
## @param control: 要强调的控件。
## @param scale_multiplier: 动画起点相对于基础缩放的倍率。
## @param start_modulate: 动画起点的调制颜色。
## @param duration: 恢复基础状态所需时间。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_control_pulse(
	control: Control,
	scale_multiplier: float = 1.035,
	start_modulate: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0),
	duration: float = 0.22
) -> Tween:
	if not is_instance_valid(control):
		return null

	_store_control_base_state(control, false)
	_kill_control_tween(control)

	var base_scale: Vector2 = _get_control_vector2_meta(
		control,
		_CONTROL_BASE_SCALE_META,
		control.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		control,
		_CONTROL_BASE_MODULATE_META,
		control.modulate
	)
	control.pivot_offset = control.size * 0.5
	control.scale = base_scale * maxf(scale_multiplier, 0.0)
	control.modulate = start_modulate

	if not control.is_inside_tree():
		control.scale = base_scale
		control.modulate = base_modulate
		return null

	var tween: Tween = control.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var safe_duration: float = maxf(duration, 0.001)
	var _scale_tweener: PropertyTweener = tween.tween_property(
		control,
		"scale",
		base_scale,
		safe_duration
	)
	var _modulate_tweener: PropertyTweener = tween.tween_property(
		control,
		"modulate",
		base_modulate,
		safe_duration
	)
	control.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


## 播放整数值变化反馈：主标签短促计数，增量标签向上离场。
## @param value_label: 展示最终数值的标签。
## @param old_value: 变化前数值。
## @param new_value: 变化后数值。
## @param delta_label: 可选的增量飘字标签。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_numeric_change(
	value_label: Label,
	old_value: int,
	new_value: int,
	delta_label: Label = null
) -> Tween:
	if not is_instance_valid(value_label):
		return null

	_store_control_base_state(value_label, false)
	_kill_control_tween(value_label)
	_kill_numeric_tween(value_label)
	_restore_control_base_state(value_label, false)
	value_label.text = str(old_value)

	if is_instance_valid(delta_label):
		_store_control_base_state(delta_label, true)
		_restore_control_base_state(delta_label, true)
		delta_label.visible = false

	if old_value == new_value or not value_label.is_inside_tree():
		value_label.text = str(new_value)
		return null

	var feedback_color: Color = _get_numeric_feedback_color(new_value > old_value)
	var base_scale: Vector2 = _get_control_vector2_meta(
		value_label,
		_CONTROL_BASE_SCALE_META,
		value_label.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		value_label,
		_CONTROL_BASE_MODULATE_META,
		value_label.modulate
	)
	value_label.pivot_offset = value_label.size * 0.5
	value_label.scale = base_scale * 1.08
	value_label.modulate = base_modulate.lerp(feedback_color, 0.22)

	var tween: Tween = value_label.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _number_tweener: MethodTweener = tween.tween_method(
		_set_numeric_label_progress.bind(value_label, old_value, new_value),
		0.0,
		1.0,
		_NUMERIC_CHANGE_DURATION
	)
	var _scale_tweener: PropertyTweener = tween.tween_property(
		value_label,
		"scale",
		base_scale,
		_NUMERIC_CHANGE_DURATION
	)
	var _modulate_tweener: PropertyTweener = tween.tween_property(
		value_label,
		"modulate",
		base_modulate,
		_NUMERIC_CHANGE_DURATION
	)

	if is_instance_valid(delta_label):
		_prepare_numeric_delta_label(delta_label, new_value - old_value, feedback_color)
		var delta_base_position: Vector2 = _get_control_vector2_meta(
			delta_label,
			_CONTROL_BASE_POSITION_META,
			delta_label.position
		)
		var delta_base_scale: Vector2 = _get_control_vector2_meta(
			delta_label,
			_CONTROL_BASE_SCALE_META,
			delta_label.scale
		)
		var _delta_position_tweener: PropertyTweener = tween.tween_property(
			delta_label,
			"position",
			delta_base_position + _NUMERIC_DELTA_END_OFFSET,
			_NUMERIC_DELTA_DURATION
		)
		var _delta_scale_tweener: PropertyTweener = tween.tween_property(
			delta_label,
			"scale",
			delta_base_scale,
			_NUMERIC_CHANGE_DURATION
		)
		var delta_fade_tweener: PropertyTweener = tween.tween_property(
			delta_label,
			"modulate:a",
			0.0,
			_NUMERIC_DELTA_DURATION * 0.72
		)
		var _delta_fade_delay: Tweener = delta_fade_tweener.set_delay(
			_NUMERIC_DELTA_DURATION * 0.28
		)

	value_label.set_meta(_NUMERIC_TWEEN_META, tween)
	var _finished_connection: int = tween.finished.connect(
		_finish_numeric_change.bind(value_label, delta_label, new_value, tween),
		CONNECT_ONE_SHOT
	)
	return tween


## 错峰播放容器直接子控件的出现动画。
## @param container: 要扫描直接子节点的容器。
## @param offset: 每个子控件动画起点相对于原始位置的偏移。
## @param stagger: 相邻子控件之间的延迟时间。
## @return: 本次播放动效的子控件数量。
func play_children_reveal(
	container: Node,
	offset: Vector2 = _CHILD_REVEAL_OFFSET,
	stagger: float = _CHILD_REVEAL_STAGGER
) -> int:
	if not is_instance_valid(container):
		return 0

	var animated_count: int = 0
	var animate_position: bool = not container is Container
	var reveal_offset: Vector2 = offset if animate_position else Vector2.ZERO
	for child: Node in container.get_children():
		if child is Control:
			var child_control: Control = child
			if not child_control.visible:
				continue
			var _reveal_tween: Tween = _play_control_reveal(
				child_control,
				reveal_offset,
				_CHILD_REVEAL_DURATION,
				float(animated_count) * stagger,
				1.0,
				animate_position
			)
			animated_count += 1

	return animated_count


# --- 私有/辅助方法 ---

func _bind_button(button: BaseButton) -> bool:
	if not is_instance_valid(button):
		return false
	if GFVariantData.to_bool(_get_button_meta(button, _BOUND_META, false)):
		return false

	button.set_meta(_BOUND_META, true)
	button.set_meta(_HOVERED_META, false)
	button.set_meta(_FOCUSED_META, false)
	button.set_meta(_BASE_SCALE_META, button.scale)
	button.call_deferred("set", "pivot_offset", button.size * 0.5)
	if is_instance_valid(_style):
		_style.prepare_button(button)

	var _connect_result_157: int = button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
	var _connect_result_158: int = button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	var _connect_result_159: int = button.focus_entered.connect(_on_button_focus_entered.bind(button))
	var _connect_result_160: int = button.focus_exited.connect(_on_button_focus_exited.bind(button))
	var _connect_result_161: int = button.button_down.connect(_on_button_down.bind(button))
	var _connect_result_162: int = button.button_up.connect(_on_button_up.bind(button))
	var _connect_result_163: int = button.resized.connect(_on_button_resized.bind(button))
	var _connect_result_164: int = button.tree_exited.connect(_on_button_tree_exited.bind(button), CONNECT_ONE_SHOT)
	return true


func _update_button_focus_ring_visibility(button: BaseButton) -> void:
	if not is_instance_valid(_style):
		return
	if not is_instance_valid(button) or button.disabled:
		_style.set_button_focus_visible(button, false)
		return
	_style.set_button_focus_visible(button, _is_button_active(button))


func _play_control_reveal(
	control: Control,
	offset: Vector2,
	duration: float,
	delay: float,
	start_scale: float,
	animate_position: bool
) -> Tween:
	if not is_instance_valid(control):
		return null

	_store_control_base_state(control, animate_position)
	_kill_control_tween(control)

	var base_position: Vector2 = control.position
	if animate_position:
		base_position = _get_control_vector2_meta(
			control,
			_CONTROL_BASE_POSITION_META,
			control.position
		)
	var base_scale: Vector2 = _get_control_vector2_meta(
		control,
		_CONTROL_BASE_SCALE_META,
		control.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		control,
		_CONTROL_BASE_MODULATE_META,
		control.modulate
	)
	var start_modulate: Color = base_modulate
	start_modulate.a = 0.0

	if animate_position:
		control.position = base_position + offset
	control.scale = base_scale * start_scale
	control.modulate = start_modulate

	if not control.is_inside_tree():
		if animate_position:
			control.position = base_position
		control.scale = base_scale
		control.modulate = base_modulate
		return null

	var tween: Tween = control.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	if animate_position:
		var position_tweener: PropertyTweener = tween.tween_property(control, "position", base_position, duration)
		var _position_delay_result: Tweener = position_tweener.set_delay(delay)
	var scale_tweener: PropertyTweener = tween.tween_property(control, "scale", base_scale, duration)
	var _scale_delay_result: Tweener = scale_tweener.set_delay(delay)
	var modulate_tweener: PropertyTweener = tween.tween_property(control, "modulate", base_modulate, duration)
	var _modulate_delay_result: Tweener = modulate_tweener.set_delay(delay)
	control.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


func _animate_button(
	button: BaseButton,
	scale_multiplier: float,
	modulate: Color,
	duration: float
) -> void:
	if not is_instance_valid(button):
		return

	_kill_button_tween(button)

	var base_scale: Vector2 = _get_button_base_scale(button)
	if not button.is_inside_tree():
		button.scale = base_scale * scale_multiplier
		button.modulate = modulate
		return

	var tween: Tween = button.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _scale_tweener: PropertyTweener = tween.tween_property(button, "scale", base_scale * scale_multiplier, duration)
	var _modulate_tweener: PropertyTweener = tween.tween_property(button, "modulate", modulate, duration)
	button.set_meta(_TWEEN_META, tween)


func _restore_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if _is_button_active(button):
		_animate_button(button, _HOVER_SCALE, _get_active_modulate(button), _HOVER_DURATION)
	else:
		_animate_button(button, 1.0, _REST_MODULATE, _HOVER_DURATION)


func _is_button_active(button: BaseButton) -> bool:
	return (
		GFVariantData.to_bool(_get_button_meta(button, _HOVERED_META, false))
		or GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false))
	)


func _get_active_modulate(button: BaseButton) -> Color:
	if GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false)):
		return _FOCUS_MODULATE
	return _HOVER_MODULATE


func _get_button_base_scale(button: BaseButton) -> Vector2:
	var value: Variant = _get_button_meta(button, _BASE_SCALE_META, Vector2.ONE)
	if value is Vector2:
		return value
	return Vector2.ONE


func _kill_button_tween(button: BaseButton) -> void:
	var tween: Tween = _get_tween_value(_get_button_meta(button, _TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	button.set_meta(_TWEEN_META, null)


func _get_button_meta(button: BaseButton, key: StringName, default_value: Variant) -> Variant:
	if is_instance_valid(button) and button.has_meta(key):
		return button.get_meta(key)
	return default_value


func _get_tween_value(value: Variant) -> Tween:
	if value is Tween:
		var tween: Tween = value
		return tween
	return null


func _store_control_base_state(control: Control, store_position: bool) -> void:
	if store_position and not control.has_meta(_CONTROL_BASE_POSITION_META):
		control.set_meta(_CONTROL_BASE_POSITION_META, control.position)
	if not control.has_meta(_CONTROL_BASE_SCALE_META):
		control.set_meta(_CONTROL_BASE_SCALE_META, control.scale)
	if not control.has_meta(_CONTROL_BASE_MODULATE_META):
		control.set_meta(_CONTROL_BASE_MODULATE_META, control.modulate)


func _restore_control_base_state(control: Control, restore_position: bool) -> void:
	if not is_instance_valid(control):
		return
	if restore_position:
		control.position = _get_control_vector2_meta(
			control,
			_CONTROL_BASE_POSITION_META,
			control.position
		)
	control.scale = _get_control_vector2_meta(
		control,
		_CONTROL_BASE_SCALE_META,
		control.scale
	)
	control.modulate = _get_control_color_meta(
		control,
		_CONTROL_BASE_MODULATE_META,
		control.modulate
	)


func _kill_numeric_tween(value_label: Label) -> void:
	var tween: Tween = _get_tween_value(_get_control_meta(value_label, _NUMERIC_TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	value_label.set_meta(_NUMERIC_TWEEN_META, null)


func _prepare_numeric_delta_label(delta_label: Label, delta: int, color: Color) -> void:
	var base_position: Vector2 = _get_control_vector2_meta(
		delta_label,
		_CONTROL_BASE_POSITION_META,
		delta_label.position
	)
	var base_scale: Vector2 = _get_control_vector2_meta(
		delta_label,
		_CONTROL_BASE_SCALE_META,
		delta_label.scale
	)
	delta_label.text = ("+%d" % delta) if delta > 0 else str(delta)
	delta_label.position = base_position + _NUMERIC_DELTA_START_OFFSET
	delta_label.pivot_offset = delta_label.size * 0.5
	delta_label.scale = base_scale * 0.78
	delta_label.modulate = color
	delta_label.visible = true


func _get_numeric_feedback_color(is_increase: bool) -> Color:
	if is_instance_valid(_style):
		return _style.get_value_change_color(is_increase)
	return _NUMERIC_GAIN_COLOR if is_increase else _NUMERIC_LOSS_COLOR


func _set_numeric_label_progress(
	progress: float,
	value_label: Label,
	old_value: int,
	new_value: int
) -> void:
	if not is_instance_valid(value_label):
		return
	value_label.text = str(roundi(lerpf(float(old_value), float(new_value), progress)))


func _finish_numeric_change(
	value_label: Label,
	delta_label: Label,
	new_value: int,
	tween: Tween
) -> void:
	if not is_instance_valid(value_label):
		return
	var active_tween: Tween = _get_tween_value(
		_get_control_meta(value_label, _NUMERIC_TWEEN_META, null)
	)
	if active_tween != tween:
		return
	value_label.text = str(new_value)
	_restore_control_base_state(value_label, false)
	value_label.set_meta(_NUMERIC_TWEEN_META, null)
	if is_instance_valid(delta_label):
		_restore_control_base_state(delta_label, true)
		delta_label.visible = false


func _kill_control_tween(control: Control) -> void:
	var tween: Tween = _get_tween_value(_get_control_meta(control, _CONTROL_TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	control.set_meta(_CONTROL_TWEEN_META, null)


func _get_control_meta(control: Control, key: StringName, default_value: Variant) -> Variant:
	if is_instance_valid(control) and control.has_meta(key):
		return control.get_meta(key)
	return default_value


func _get_control_vector2_meta(control: Control, key: StringName, default_value: Vector2) -> Vector2:
	var value: Variant = _get_control_meta(control, key, default_value)
	if value is Vector2:
		return value
	return default_value


func _get_control_color_meta(control: Control, key: StringName, default_value: Color) -> Color:
	var value: Variant = _get_control_meta(control, key, default_value)
	if value is Color:
		return value
	return default_value


func _get_style_utility() -> GameUiStyleUtility:
	var utility_value: Object = get_utility(GameUiStyleUtility)
	if utility_value is GameUiStyleUtility:
		var style_utility: GameUiStyleUtility = utility_value
		return style_utility
	return null


# --- 信号处理函数 ---

func _on_button_mouse_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_HOVERED_META, true)
	_update_button_focus_ring_visibility(button)
	interactive_control_selected.emit(button)
	_animate_button(button, _HOVER_SCALE, _HOVER_MODULATE, _HOVER_DURATION)


func _on_button_mouse_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_HOVERED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_focus_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_FOCUSED_META, true)
	_update_button_focus_ring_visibility(button)
	interactive_control_selected.emit(button)
	_animate_button(button, _HOVER_SCALE, _FOCUS_MODULATE, _HOVER_DURATION)


func _on_button_focus_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_FOCUSED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_down(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	if is_instance_valid(_style):
		_style.set_button_focus_visible(button, true)
	interactive_control_confirmed.emit(button)
	_animate_button(button, _PRESS_SCALE, _PRESS_MODULATE, _PRESS_DURATION)


func _on_button_up(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_resized(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if is_instance_valid(_style):
		_style.refresh_button_focus_ring(button)


func _on_button_tree_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_tween(button)
