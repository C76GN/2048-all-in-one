## GameUiMotionUtility: 统一处理项目 UI 控件的轻量交互动效。
##
## 作为项目级 GFUtility，它负责按钮 hover、focus、press、面板入场和列表刷新表现，
## 不接管菜单业务、路由或输入语义。
class_name GameUiMotionUtility
extends GFUtility


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

const _REST_MODULATE: Color = Color.WHITE
const _HOVER_MODULATE: Color = Color(1.0, 0.96, 0.88, 1.0)
const _FOCUS_MODULATE: Color = Color(0.94, 1.0, 0.96, 1.0)
const _PRESS_MODULATE: Color = Color(0.9, 0.9, 0.9, 1.0)
const _HOVER_SCALE: float = 1.035
const _PRESS_SCALE: float = 0.965
const _HOVER_DURATION: float = 0.11
const _PRESS_DURATION: float = 0.055
const _PANEL_INTRO_OFFSET: Vector2 = Vector2(0.0, 18.0)
const _PANEL_INTRO_SCALE: float = 0.985
const _PANEL_INTRO_DURATION: float = 0.26
const _CHILD_REVEAL_OFFSET: Vector2 = Vector2(14.0, 0.0)
const _CHILD_REVEAL_DURATION: float = 0.18
const _CHILD_REVEAL_STAGGER: float = 0.035


# --- 公共方法 ---

## 递归绑定根节点下所有 BaseButton 控件。
## @param root: 要扫描的 UI 根节点。
## @return: 本次新绑定的按钮数量。
func bind_interactive_controls(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	var bound_count: int = 0
	if root is BaseButton and _bind_button(root as BaseButton):
		bound_count += 1

	for child in root.get_children():
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
	var animate_position := not container is Container
	var reveal_offset := offset if animate_position else Vector2.ZERO
	for child in container.get_children():
		if child is Control and (child as Control).visible:
			_play_control_reveal(
				child as Control,
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

	button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	button.focus_entered.connect(_on_button_focus_entered.bind(button))
	button.focus_exited.connect(_on_button_focus_exited.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))
	button.tree_exited.connect(_on_button_tree_exited.bind(button), CONNECT_ONE_SHOT)
	return true


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
	var start_modulate := base_modulate
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

	var tween := control.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if animate_position:
		tween.tween_property(control, "position", base_position, duration).set_delay(delay)
	tween.tween_property(control, "scale", base_scale, duration).set_delay(delay)
	tween.tween_property(control, "modulate", base_modulate, duration).set_delay(delay)
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

	var tween := button.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", base_scale * scale_multiplier, duration)
	tween.tween_property(button, "modulate", modulate, duration)
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


# --- 信号处理函数 ---

func _on_button_mouse_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_HOVERED_META, true)
	_animate_button(button, _HOVER_SCALE, _HOVER_MODULATE, _HOVER_DURATION)


func _on_button_mouse_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_HOVERED_META, false)
	_restore_button(button)


func _on_button_focus_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_FOCUSED_META, true)
	_animate_button(button, _HOVER_SCALE, _FOCUS_MODULATE, _HOVER_DURATION)


func _on_button_focus_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_FOCUSED_META, false)
	_restore_button(button)


func _on_button_down(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_animate_button(button, _PRESS_SCALE, _PRESS_MODULATE, _PRESS_DURATION)


func _on_button_up(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_restore_button(button)


func _on_button_tree_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_tween(button)
