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
const _PRESSED_META: StringName = &"_game_ui_motion_pressed"
const _BASE_SCALE_META: StringName = &"_game_ui_motion_base_scale"
const _BASE_MODULATE_META: StringName = &"_game_ui_motion_base_modulate"
const _TWEEN_META: StringName = &"_game_ui_motion_tween"
const _BUTTON_BASE_SELF_MODULATE_META: StringName = &"_game_ui_motion_base_self_modulate"
const _BUTTON_TEXT_TWEEN_META: StringName = &"_game_ui_motion_text_tween"
const _TOGGLE_STATE_META: StringName = &"_game_ui_motion_toggle_state"
const _DISABLED_STATE_META: StringName = &"_game_ui_motion_disabled_state"
const _CONTROL_BASE_POSITION_META: StringName = &"_game_ui_motion_control_base_position"
const _CONTROL_BASE_SCALE_META: StringName = &"_game_ui_motion_control_base_scale"
const _CONTROL_BASE_MODULATE_META: StringName = &"_game_ui_motion_control_base_modulate"
const _CONTROL_BASE_ROTATION_META: StringName = &"_game_ui_motion_control_base_rotation"
const _CONTROL_TWEEN_META: StringName = &"_game_ui_motion_control_tween"
const _NUMERIC_TWEEN_META: StringName = &"_game_ui_motion_numeric_tween"
const _SCROLL_CONTAINER_BOUND_META: StringName = &"_game_ui_motion_scroll_container_bound"
const _SCROLL_BOUND_META: StringName = &"_game_ui_motion_scroll_bound"
const _SCROLL_HOVERED_META: StringName = &"_game_ui_motion_scroll_hovered"
const _SCROLL_TWEEN_META: StringName = &"_game_ui_motion_scroll_tween"
const _SCROLL_BASE_SCALE_META: StringName = &"_game_ui_motion_scroll_base_scale"
const _SCROLL_BASE_MODULATE_META: StringName = &"_game_ui_motion_scroll_base_modulate"
const _TAB_BOUND_META: StringName = &"_game_ui_motion_tab_bound"
const _TAB_INDEX_META: StringName = &"_game_ui_motion_tab_index"
## BaseButton 根控件始终保持布局几何稳定；可见变换由内部 Presenter 承担。
## 这避免 ScrollContainer 与密集按钮组裁切放大后的控件。
const _BUTTON_DEAL_OFFSET: Vector2 = Vector2(18.0, 0.0)
const _BUTTON_DEAL_STAGGER: float = 0.032
const _PANEL_INTRO_OFFSET: Vector2 = Vector2(0.0, 10.0)
const _PANEL_INTRO_SCALE: float = 0.992
const _PANEL_INTRO_DURATION: float = 0.18
const _CHILD_REVEAL_OFFSET: Vector2 = Vector2(8.0, 0.0)
const _CHILD_REVEAL_DURATION: float = 0.14
const _CHILD_REVEAL_STAGGER: float = 0.025
const _CHILD_REVEAL_SCALE: float = 0.985
const _CONTENT_SWITCH_OFFSET: Vector2 = Vector2(12.0, 0.0)
const _CONTENT_SWITCH_DURATION: float = 0.15
const _PIECE_ASSEMBLY_DURATION: float = 0.28
const _PIECE_ASSEMBLY_STAGGER: float = 0.055
const _PIECE_ASSEMBLY_SCALE: float = 0.72
const _PIECE_ASSEMBLY_ROTATION: float = 0.10
const _SCROLL_IDLE_ALPHA: float = 0.48
const _SCROLL_IDLE_THICKNESS_SCALE: float = 0.72
const _SCROLL_ACTIVE_DURATION: float = 0.11
const _SCROLL_IDLE_DELAY: float = 0.42
const _SCROLL_IDLE_DURATION: float = 0.20
const _NUMERIC_CHANGE_DURATION: float = 0.22
const _NUMERIC_DELTA_DURATION: float = 0.36
const _NUMERIC_GAIN_COLOR: Color = Color(0.82, 0.69, 0.34, 1.0)
const _NUMERIC_LOSS_COLOR: Color = Color(0.58, 0.27, 0.19, 1.0)
const _NUMERIC_DELTA_START_DISTANCE: float = 5.0
const _NUMERIC_DELTA_END_DISTANCE: float = 38.0


# --- 私有变量 ---

var _style: GameUiStyleUtility
var _accessibility: GameAccessibilityUtility
var _numeric_scatter_sequence: int = 0
var _tracked_buttons: Array[WeakRef] = []


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameUiStyleUtility, GameAccessibilityUtility]


func ready() -> void:
	_style = _get_style_utility()
	_accessibility = _get_accessibility_utility()
	if not is_instance_valid(_style):
		push_error("[GameUiMotionUtility] 缺少 GameUiStyleUtility。")
	if not is_instance_valid(_accessibility):
		push_error("[GameUiMotionUtility] 缺少 GameAccessibilityUtility。")


## 同步运行时改变的按钮禁用状态，清理陈旧交互表现。
## @param _delta: GF 每帧调度传入的时间增量；本同步只比较状态，不依赖时间。
func tick(_delta: float) -> void:
	for index: int in range(_tracked_buttons.size() - 1, -1, -1):
		var weak_reference: WeakRef = _tracked_buttons[index]
		var referenced_object: Variant = weak_reference.get_ref()
		if not referenced_object is BaseButton:
			_tracked_buttons.remove_at(index)
			continue
		var button: BaseButton = referenced_object
		var previous_disabled: bool = GFVariantData.to_bool(
			_get_button_meta(
				button,
				_DISABLED_STATE_META,
				button.disabled
			)
		)
		if previous_disabled == button.disabled:
			continue
		_sync_button_disabled_state(button)


func dispose() -> void:
	_tracked_buttons.clear()
	_style = null
	_accessibility = null


func release_dependencies() -> void:
	_style = null
	_accessibility = null
	super.release_dependencies()


# --- 公共方法 ---

## 递归绑定根节点下所有 BaseButton 控件。
## @param root: 要扫描的 UI 根节点。
## @return: 本次新绑定的按钮数量。
func bind_interactive_controls(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	if root is Control:
		var root_control: Control = root
		if is_instance_valid(_style):
			_style.style_control(root_control)
		_bind_supporting_control_motion(root_control)

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


## 分层播放弹层遮罩与任务表面的入场动画。
## @param backdrop: 全屏遮罩；可以为空。
## @param surface: 弹层任务表面。
## @return: 创建成功时返回统一 Tween，否则返回 null。
func play_modal_intro(backdrop: Control, surface: Control) -> Tween:
	if not is_instance_valid(surface):
		return null
	_store_control_base_state(surface, false)
	if is_instance_valid(backdrop):
		_store_control_base_state(backdrop, false)
		_kill_control_tween(backdrop)
	_kill_control_tween(surface)

	var surface_scale: Vector2 = _get_control_vector2_meta(
		surface,
		_CONTROL_BASE_SCALE_META,
		surface.scale
	)
	var surface_modulate: Color = _get_control_color_meta(
		surface,
		_CONTROL_BASE_MODULATE_META,
		surface.modulate
	)
	var backdrop_modulate: Color = Color.WHITE
	if is_instance_valid(backdrop):
		backdrop_modulate = _get_control_color_meta(
			backdrop,
			_CONTROL_BASE_MODULATE_META,
			backdrop.modulate
		)
	if _is_reduced_motion() or not surface.is_inside_tree():
		surface.scale = surface_scale
		surface.modulate = surface_modulate
		if is_instance_valid(backdrop):
			backdrop.modulate = backdrop_modulate
		return null

	surface.pivot_offset = surface.size * 0.5
	surface.scale = surface_scale * 0.972
	var surface_start_modulate: Color = surface_modulate
	surface_start_modulate.a = 0.0
	surface.modulate = surface_start_modulate
	if is_instance_valid(backdrop):
		var backdrop_start_modulate: Color = backdrop_modulate
		backdrop_start_modulate.a = 0.0
		backdrop.modulate = backdrop_start_modulate

	var tween: Tween = surface.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var scale_tweener: PropertyTweener = tween.tween_property(
		surface,
		"scale",
		surface_scale,
		0.20
	)
	var _scale_curve: Tweener = scale_tweener.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var surface_modulate_tweener: PropertyTweener = tween.tween_property(
		surface,
		"modulate",
		surface_modulate,
		0.16
	)
	var _surface_modulate_curve: Tweener = surface_modulate_tweener.set_trans(
		Tween.TRANS_CUBIC
	)
	var _surface_modulate_ease: Tweener = surface_modulate_tweener.set_ease(
		Tween.EASE_OUT
	)
	if is_instance_valid(backdrop):
		var backdrop_tweener: PropertyTweener = tween.tween_property(
			backdrop,
			"modulate",
			backdrop_modulate,
			0.16
		)
		var _backdrop_curve: Tweener = backdrop_tweener.set_trans(
			Tween.TRANS_CUBIC
		)
		var _backdrop_ease: Tweener = backdrop_tweener.set_ease(
			Tween.EASE_OUT
		)
		backdrop.set_meta(_CONTROL_TWEEN_META, tween)
	surface.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


## 分层播放弹层遮罩与任务表面的退出动画。
## @param backdrop: 全屏遮罩；可以为空。
## @param surface: 弹层任务表面。
## @return: 创建成功时返回统一 Tween；减少动态时返回 null。
func play_modal_outro(backdrop: Control, surface: Control) -> Tween:
	if not is_instance_valid(surface):
		return null
	_store_control_base_state(surface, false)
	if is_instance_valid(backdrop):
		_store_control_base_state(backdrop, false)
		_kill_control_tween(backdrop)
	_kill_control_tween(surface)
	if _is_reduced_motion() or not surface.is_inside_tree():
		return null

	var base_scale: Vector2 = _get_control_vector2_meta(
		surface,
		_CONTROL_BASE_SCALE_META,
		surface.scale
	)
	surface.pivot_offset = surface.size * 0.5
	var tween: Tween = surface.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var scale_tweener: PropertyTweener = tween.tween_property(
		surface,
		"scale",
		base_scale * 0.985,
		0.13
	)
	var _scale_curve: Tweener = scale_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN
	)
	var surface_fade: PropertyTweener = tween.tween_property(
		surface,
		"modulate:a",
		0.0,
		0.11
	)
	var _surface_fade_curve: Tweener = surface_fade.set_trans(
		Tween.TRANS_CUBIC
	)
	var _surface_fade_ease: Tweener = surface_fade.set_ease(
		Tween.EASE_IN
	)
	if is_instance_valid(backdrop):
		var backdrop_fade: PropertyTweener = tween.tween_property(
			backdrop,
			"modulate:a",
			0.0,
			0.13
		)
		var _backdrop_fade_curve: Tweener = backdrop_fade.set_trans(
			Tween.TRANS_CUBIC
		)
		var _backdrop_fade_ease: Tweener = backdrop_fade.set_ease(
			Tween.EASE_IN
		)
		backdrop.set_meta(_CONTROL_TWEEN_META, tween)
	surface.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


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
	if _is_reduced_motion():
		control.scale = base_scale
		control.modulate = base_modulate
		return null
	control.pivot_offset = control.size * 0.5
	control.scale = base_scale * maxf(scale_multiplier, 0.0)
	control.modulate = start_modulate

	if not control.is_inside_tree():
		control.scale = base_scale
		control.modulate = base_modulate
		return null

	var tween: Tween = control.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
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
	if _is_reduced_motion():
		value_label.text = str(new_value)
		_restore_control_base_state(value_label, false)
		if is_instance_valid(delta_label):
			_restore_control_base_state(delta_label, true)
			delta_label.visible = false
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
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
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
		var delta_direction: Vector2 = _next_numeric_delta_direction()
		_prepare_numeric_delta_label(
			delta_label,
			new_value - old_value,
			feedback_color,
			delta_direction
		)
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
			delta_base_position + delta_direction * _NUMERIC_DELTA_END_DISTANCE,
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
## @param initial_delay: 整组内容开始前的短延迟。
## @param maximum_stagger: 最后一个子项相对首项的最大等待时间。
## @return: 本次播放动效的子控件数量。
func play_children_reveal(
	container: Node,
	offset: Vector2 = _CHILD_REVEAL_OFFSET,
	stagger: float = _CHILD_REVEAL_STAGGER,
	initial_delay: float = 0.0,
	maximum_stagger: float = 0.16
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
				maxf(initial_delay, 0.0) + minf(
					float(animated_count) * maxf(stagger, 0.0),
					maxf(maximum_stagger, 0.0)
				),
				_CHILD_REVEAL_SCALE,
				animate_position
			)
			animated_count += 1

	return animated_count


## 让按钮纸片按逻辑顺序从左右两侧错峰进入。
## 外层 BaseButton 不移动，因此入场期间布局、焦点顺序与命中框仍然稳定。
## @param buttons: 按逻辑阅读顺序排列的按钮。
## @param offset: 单个纸片相对终点的水平起始距离。
## @param stagger: 相邻纸片的开始时间差。
## @param initial_delay: 第一张纸片开始前的等待时间。
## @return: 本次启动的纸片数量。
func play_button_deal_sequence(
	buttons: Array[BaseButton],
	offset: Vector2 = _BUTTON_DEAL_OFFSET,
	stagger: float = _BUTTON_DEAL_STAGGER,
	initial_delay: float = 0.0
) -> int:
	if not is_instance_valid(_style):
		return 0
	var animated_count: int = 0
	for button: BaseButton in buttons:
		if not is_instance_valid(button) or not button.visible:
			continue
		var direction: float = -1.0 if animated_count % 2 == 0 else 1.0
		_style.play_button_deal_in(
			button,
			Vector2(absf(offset.x) * direction, offset.y),
			_resolve_button_motion_state(button),
			maxf(initial_delay, 0.0)
				+ float(animated_count) * maxf(stagger, 0.0),
			_is_reduced_motion()
		)
		_play_button_text_reveal(
			button,
			maxf(initial_delay, 0.0)
				+ float(animated_count) * maxf(stagger, 0.0)
		)
		animated_count += 1
	return animated_count


## 立即完成给定按钮的纸片与文字入场。
## @param button: 需要直接落到当前终态的按钮。
func complete_button_motion(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_text_tween(button)
	button.self_modulate = _get_button_base_self_modulate(button)
	if is_instance_valid(_style):
		_style.complete_button_motion(button)


## 播放同一页面内的内容切换反馈。
## @param control: 刚切换为可见的内容根节点。
## @param direction: 正数从右侧进入，负数从左侧进入。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_content_switch(control: Control, direction: float = 1.0) -> Tween:
	if not is_instance_valid(control):
		return null
	var signed_direction: float = -1.0 if direction < 0.0 else 1.0
	return _play_control_reveal(
		control,
		_CONTENT_SWITCH_OFFSET * signed_direction,
		_CONTENT_SWITCH_DURATION,
		0.0,
		0.992,
		not control.get_parent() is Container
	)


## 让一组独立视觉部件以错峰缩放和旋转完成组装。
## @param pieces: 需要组装的控件数组；无效或隐藏控件会被忽略。
## @param stagger: 相邻部件的开始时间间隔。
## @return: 本次启动的部件动画数量。
func play_piece_assembly(
	pieces: Array[Control],
	stagger: float = _PIECE_ASSEMBLY_STAGGER
) -> int:
	var animated_count: int = 0
	for piece: Control in pieces:
		if not is_instance_valid(piece) or not piece.visible:
			continue
		var rotation_direction: float = -1.0 if animated_count % 2 == 0 else 1.0
		var _piece_tween: Tween = _play_piece_reveal(
			piece,
			float(animated_count) * stagger,
			rotation_direction
		)
		animated_count += 1
	return animated_count


## 重新触发指定滚动条的活动反馈。
## @param scroll_bar: 目标滚动条。
func show_scroll_activity(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	_bind_scroll_bar(scroll_bar)
	_animate_scroll_bar_activity(scroll_bar, true)


## 立即完成单个控件尚未结束的入场、切换或强调动效。
## @param control: 目标控件。
func complete_control_motion(control: Control) -> void:
	if not is_instance_valid(control):
		return
	_kill_control_tween(control)
	if control.has_meta(_CONTROL_BASE_POSITION_META):
		control.position = _get_control_vector2_meta(
			control,
			_CONTROL_BASE_POSITION_META,
			control.position
		)
	if control.has_meta(_CONTROL_BASE_SCALE_META):
		control.scale = _get_control_vector2_meta(
			control,
			_CONTROL_BASE_SCALE_META,
			control.scale
		)
	if control.has_meta(_CONTROL_BASE_MODULATE_META):
		control.modulate = _get_control_color_meta(
			control,
			_CONTROL_BASE_MODULATE_META,
			control.modulate
		)
	if control.has_meta(_CONTROL_BASE_ROTATION_META):
		control.rotation = GFVariantData.to_float(
			_get_control_meta(
				control,
				_CONTROL_BASE_ROTATION_META,
				control.rotation
			),
			control.rotation
		)


## 立即完成容器直接子控件尚未结束的入场动效。
## @param container: 目标容器。
func complete_children_motion(container: Node) -> void:
	if not is_instance_valid(container):
		return
	for child: Node in container.get_children():
		if child is Control:
			var child_control: Control = child
			complete_control_motion(child_control)


# --- 私有/辅助方法 ---

func _bind_supporting_control_motion(control: Control) -> void:
	if not is_instance_valid(control):
		return
	if control is ScrollContainer:
		var scroll_container: ScrollContainer = control
		_bind_scroll_container(scroll_container)
		_bind_scroll_bar(scroll_container.get_v_scroll_bar())
		_bind_scroll_bar(scroll_container.get_h_scroll_bar())
	elif control is ItemList:
		var item_list: ItemList = control
		_bind_scroll_bar(item_list.get_v_scroll_bar())
		_bind_scroll_bar(item_list.get_h_scroll_bar())
	elif control is ScrollBar:
		var scroll_bar: ScrollBar = control
		_bind_scroll_bar(scroll_bar)
	elif control is TabContainer:
		var tab_container: TabContainer = control
		_bind_tab_container(tab_container)


func _bind_button(button: BaseButton) -> bool:
	if not is_instance_valid(button):
		return false
	if GFVariantData.to_bool(_get_button_meta(button, _BOUND_META, false)):
		return false

	button.set_meta(_BOUND_META, true)
	button.set_meta(_HOVERED_META, false)
	button.set_meta(_FOCUSED_META, button.has_focus())
	button.set_meta(_PRESSED_META, false)
	button.set_meta(_BASE_SCALE_META, button.scale)
	button.set_meta(_BASE_MODULATE_META, button.modulate)
	button.set_meta(
		_BUTTON_BASE_SELF_MODULATE_META,
		button.self_modulate
	)
	button.set_meta(_TOGGLE_STATE_META, button.button_pressed)
	button.set_meta(_DISABLED_STATE_META, button.disabled)
	_tracked_buttons.append(weakref(button))
	button.call_deferred("set", "pivot_offset", button.size * 0.5)
	if is_instance_valid(_style):
		_style.prepare_button(button)
		_update_button_focus_ring_visibility(button)
		_refresh_button_motion_state(button, false)

	var _connect_result_157: int = button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
	var _connect_result_158: int = button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	var _connect_result_159: int = button.focus_entered.connect(_on_button_focus_entered.bind(button))
	var _connect_result_160: int = button.focus_exited.connect(_on_button_focus_exited.bind(button))
	var _connect_result_161: int = button.button_down.connect(_on_button_down.bind(button))
	var _connect_result_162: int = button.button_up.connect(_on_button_up.bind(button))
	var _connect_result_163: int = button.resized.connect(_on_button_resized.bind(button))
	var _connect_result_164: int = button.tree_exited.connect(_on_button_tree_exited.bind(button), CONNECT_ONE_SHOT)
	if button.toggle_mode:
		var _toggle_connection: int = button.toggled.connect(
			_on_button_toggled.bind(button)
		)
	return true


func _bind_scroll_bar(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	if GFVariantData.to_bool(
		_get_control_meta(scroll_bar, _SCROLL_BOUND_META, false)
	):
		return
	scroll_bar.set_meta(_SCROLL_BOUND_META, true)
	scroll_bar.set_meta(_SCROLL_HOVERED_META, false)
	scroll_bar.set_meta(_SCROLL_BASE_SCALE_META, scroll_bar.scale)
	scroll_bar.set_meta(_SCROLL_BASE_MODULATE_META, scroll_bar.modulate)
	_update_scroll_bar_pivot(scroll_bar)
	var _enter_connection: int = scroll_bar.mouse_entered.connect(
		_on_scroll_bar_mouse_entered.bind(scroll_bar)
	)
	var _exit_connection: int = scroll_bar.mouse_exited.connect(
		_on_scroll_bar_mouse_exited.bind(scroll_bar)
	)
	var _resize_connection: int = scroll_bar.resized.connect(
		_update_scroll_bar_pivot.bind(scroll_bar)
	)
	var _tree_exit_connection: int = scroll_bar.tree_exited.connect(
		_on_scroll_bar_tree_exited.bind(scroll_bar),
		CONNECT_ONE_SHOT
	)
	_set_scroll_bar_idle_state(scroll_bar)


func _bind_scroll_container(scroll_container: ScrollContainer) -> void:
	if not is_instance_valid(scroll_container):
		return
	if GFVariantData.to_bool(
		_get_control_meta(
			scroll_container,
			_SCROLL_CONTAINER_BOUND_META,
			false
		)
	):
		return
	scroll_container.set_meta(_SCROLL_CONTAINER_BOUND_META, true)
	var _start_connection: int = scroll_container.scroll_started.connect(
		_on_scroll_container_started.bind(scroll_container)
	)
	var _end_connection: int = scroll_container.scroll_ended.connect(
		_on_scroll_container_ended.bind(scroll_container)
	)


func _bind_tab_container(tab_container: TabContainer) -> void:
	if not is_instance_valid(tab_container):
		return
	if GFVariantData.to_bool(
		_get_control_meta(tab_container, _TAB_BOUND_META, false)
	):
		return
	tab_container.set_meta(_TAB_BOUND_META, true)
	tab_container.set_meta(_TAB_INDEX_META, tab_container.current_tab)
	var _tab_connection: int = tab_container.tab_changed.connect(
		_on_tab_container_changed.bind(tab_container)
	)


func _play_piece_reveal(
	control: Control,
	delay: float,
	rotation_direction: float
) -> Tween:
	if not is_instance_valid(control):
		return null
	_store_control_base_state(control, false)
	if not control.has_meta(_CONTROL_BASE_ROTATION_META):
		control.set_meta(_CONTROL_BASE_ROTATION_META, control.rotation)
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
	var base_rotation: float = GFVariantData.to_float(
		_get_control_meta(control, _CONTROL_BASE_ROTATION_META, control.rotation),
		control.rotation
	)
	if _is_reduced_motion() or not control.is_inside_tree():
		control.scale = base_scale
		control.modulate = base_modulate
		control.rotation = base_rotation
		return null

	control.pivot_offset = control.size * 0.5
	control.scale = base_scale * _PIECE_ASSEMBLY_SCALE
	control.rotation = base_rotation + _PIECE_ASSEMBLY_ROTATION * rotation_direction
	var start_modulate: Color = base_modulate
	start_modulate.a = 0.0
	control.modulate = start_modulate

	var tween: Tween = control.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var scale_tweener: PropertyTweener = tween.tween_property(
		control,
		"scale",
		base_scale,
		_PIECE_ASSEMBLY_DURATION
	)
	var _scale_curve: Tweener = scale_tweener.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var _scale_delay: Tweener = scale_tweener.set_delay(delay)
	var rotation_tweener: PropertyTweener = tween.tween_property(
		control,
		"rotation",
		base_rotation,
		_PIECE_ASSEMBLY_DURATION
	)
	var _rotation_curve: Tweener = rotation_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var _rotation_delay: Tweener = rotation_tweener.set_delay(delay)
	var modulate_tweener: PropertyTweener = tween.tween_property(
		control,
		"modulate",
		base_modulate,
		_PIECE_ASSEMBLY_DURATION * 0.72
	)
	var _modulate_curve: Tweener = modulate_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var _modulate_delay: Tweener = modulate_tweener.set_delay(delay)
	control.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


func _animate_scroll_bar_activity(
	scroll_bar: ScrollBar,
	return_to_idle: bool
) -> void:
	if not is_instance_valid(scroll_bar):
		return
	_kill_scroll_bar_tween(scroll_bar)
	var base_scale: Vector2 = _get_control_vector2_meta(
		scroll_bar,
		_SCROLL_BASE_SCALE_META,
		scroll_bar.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		scroll_bar,
		_SCROLL_BASE_MODULATE_META,
		scroll_bar.modulate
	)
	if _is_reduced_motion() or not scroll_bar.is_inside_tree():
		scroll_bar.scale = base_scale
		scroll_bar.modulate = base_modulate
		return

	var tween: Tween = scroll_bar.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var scale_tweener: PropertyTweener = tween.tween_property(
		scroll_bar,
		"scale",
		base_scale,
		_SCROLL_ACTIVE_DURATION
	)
	var _scale_curve: Tweener = scale_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var modulate_tweener: PropertyTweener = tween.parallel().tween_property(
		scroll_bar,
		"modulate",
		base_modulate,
		_SCROLL_ACTIVE_DURATION
	)
	var _modulate_curve: Tweener = modulate_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if return_to_idle:
		var _idle_delay: IntervalTweener = tween.tween_interval(_SCROLL_IDLE_DELAY)
		var idle_scale_tweener: PropertyTweener = tween.tween_property(
			scroll_bar,
			"scale",
			_get_scroll_bar_idle_scale(scroll_bar, base_scale),
			_SCROLL_IDLE_DURATION
		)
		var _idle_scale_curve: Tweener = idle_scale_tweener.set_trans(
			Tween.TRANS_CUBIC
		)
		var _idle_scale_ease: Tweener = idle_scale_tweener.set_ease(
			Tween.EASE_OUT
		)
		var idle_modulate: Color = base_modulate
		idle_modulate.a *= _SCROLL_IDLE_ALPHA
		var idle_modulate_tweener: PropertyTweener = tween.parallel().tween_property(
			scroll_bar,
			"modulate",
			idle_modulate,
			_SCROLL_IDLE_DURATION
		)
		var _idle_modulate_curve: Tweener = idle_modulate_tweener.set_trans(
			Tween.TRANS_CUBIC
		)
		var _idle_modulate_ease: Tweener = idle_modulate_tweener.set_ease(
			Tween.EASE_OUT
		)
	scroll_bar.set_meta(_SCROLL_TWEEN_META, tween)


func _animate_scroll_bar_idle(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	if GFVariantData.to_bool(
		_get_control_meta(scroll_bar, _SCROLL_HOVERED_META, false)
	):
		return
	_animate_scroll_bar_activity(scroll_bar, true)


func _set_scroll_bar_idle_state(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	var base_scale: Vector2 = _get_control_vector2_meta(
		scroll_bar,
		_SCROLL_BASE_SCALE_META,
		scroll_bar.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		scroll_bar,
		_SCROLL_BASE_MODULATE_META,
		scroll_bar.modulate
	)
	if _is_reduced_motion():
		scroll_bar.scale = base_scale
		scroll_bar.modulate = base_modulate
		return
	scroll_bar.scale = _get_scroll_bar_idle_scale(scroll_bar, base_scale)
	var idle_modulate: Color = base_modulate
	idle_modulate.a *= _SCROLL_IDLE_ALPHA
	scroll_bar.modulate = idle_modulate


func _get_scroll_bar_idle_scale(
	scroll_bar: ScrollBar,
	base_scale: Vector2
) -> Vector2:
	if scroll_bar is VScrollBar:
		return Vector2(
			base_scale.x * _SCROLL_IDLE_THICKNESS_SCALE,
			base_scale.y
		)
	return Vector2(
		base_scale.x,
		base_scale.y * _SCROLL_IDLE_THICKNESS_SCALE
	)


func _update_scroll_bar_pivot(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	scroll_bar.pivot_offset = scroll_bar.size * 0.5


func _kill_scroll_bar_tween(scroll_bar: ScrollBar) -> void:
	var tween: Tween = _get_tween_value(
		_get_control_meta(scroll_bar, _SCROLL_TWEEN_META, null)
	)
	if tween != null and tween.is_valid():
		tween.kill()
	scroll_bar.set_meta(_SCROLL_TWEEN_META, null)


func _update_button_focus_ring_visibility(button: BaseButton) -> void:
	if not is_instance_valid(_style):
		return
	if not is_instance_valid(button) or button.disabled:
		_style.set_button_focus_visible(button, false)
		return
	_style.set_button_focus_visible(
		button,
		GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false))
	)


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

	var fills_visible_viewport: bool = _control_fills_visible_viewport(control)
	var animate_transform_position: bool = (
		animate_position and not fills_visible_viewport
	)
	_store_control_base_state(control, animate_transform_position)
	_kill_control_tween(control)

	var base_position: Vector2 = control.position
	if animate_transform_position:
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
	if _is_reduced_motion():
		if animate_transform_position:
			control.position = base_position
		control.scale = base_scale
		control.modulate = base_modulate
		return null
	var start_modulate: Color = base_modulate
	start_modulate.a = 0.0
	var effective_start_scale: float = 1.0 if fills_visible_viewport else start_scale

	if animate_transform_position:
		control.position = base_position + offset
	control.pivot_offset = control.size * 0.5
	control.scale = base_scale * effective_start_scale
	control.modulate = start_modulate

	if not control.is_inside_tree():
		if animate_transform_position:
			control.position = base_position
		control.scale = base_scale
		control.modulate = base_modulate
		return null

	var tween: Tween = control.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	if animate_transform_position:
		var position_tweener: PropertyTweener = tween.tween_property(control, "position", base_position, duration)
		var _position_delay_result: Tweener = position_tweener.set_delay(delay)
	var scale_tweener: PropertyTweener = tween.tween_property(control, "scale", base_scale, duration)
	var _scale_delay_result: Tweener = scale_tweener.set_delay(delay)
	var modulate_tweener: PropertyTweener = tween.tween_property(control, "modulate", base_modulate, duration)
	var _modulate_delay_result: Tweener = modulate_tweener.set_delay(delay)
	control.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


func _control_fills_visible_viewport(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return false
	var viewport_rect: Rect2 = control.get_viewport().get_visible_rect()
	var control_rect: Rect2 = control.get_global_rect()
	return (
		control_rect.position.distance_to(viewport_rect.position) <= 1.0
		and control_rect.size.distance_to(viewport_rect.size) <= 1.0
	)


func _restore_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_refresh_button_motion_state(button)


func _is_button_active(button: BaseButton) -> bool:
	return (
		GFVariantData.to_bool(_get_button_meta(button, _HOVERED_META, false))
		or GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false))
	)


func _refresh_button_motion_state(
	button: BaseButton,
	animated: bool = true
) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_tween(button)
	_kill_button_text_tween(button)
	button.scale = _get_button_base_scale(button)
	button.modulate = _get_button_base_modulate(button)
	button.self_modulate = _get_button_base_self_modulate(button)
	if not is_instance_valid(_style):
		return
	_style.set_button_motion_state(
		button,
		_resolve_button_motion_state(button),
		animated,
		_is_reduced_motion()
	)


func _resolve_button_motion_state(
	button: BaseButton
) -> GameButtonMotionPresenter.MotionState:
	if not is_instance_valid(button) or button.disabled:
		return GameButtonMotionPresenter.MotionState.DISABLED
	if GFVariantData.to_bool(
		_get_button_meta(button, _PRESSED_META, false)
	):
		return GameButtonMotionPresenter.MotionState.PRESSED
	if GFVariantData.to_bool(
		_get_button_meta(button, _TOGGLE_STATE_META, false)
	):
		return GameButtonMotionPresenter.MotionState.SELECTED
	if _is_button_active(button):
		return GameButtonMotionPresenter.MotionState.ACTIVE
	return GameButtonMotionPresenter.MotionState.REST


func _get_button_base_scale(button: BaseButton) -> Vector2:
	var value: Variant = _get_button_meta(button, _BASE_SCALE_META, Vector2.ONE)
	if value is Vector2:
		return value
	return Vector2.ONE


func _get_button_base_modulate(button: BaseButton) -> Color:
	var value: Variant = _get_button_meta(
		button,
		_BASE_MODULATE_META,
		Color.WHITE
	)
	if value is Color:
		return value
	return Color.WHITE


func _get_button_base_self_modulate(button: BaseButton) -> Color:
	var value: Variant = _get_button_meta(
		button,
		_BUTTON_BASE_SELF_MODULATE_META,
		Color.WHITE
	)
	if value is Color:
		return value
	return Color.WHITE


func _play_button_text_reveal(button: BaseButton, delay: float) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_text_tween(button)
	var base_modulate: Color = _get_button_base_self_modulate(button)
	if _is_reduced_motion() or not button.is_inside_tree():
		button.self_modulate = base_modulate
		return
	var start_modulate: Color = base_modulate
	start_modulate.a = 0.0
	button.self_modulate = start_modulate
	var tween: Tween = button.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS
	)
	var modulate_tweener: PropertyTweener = tween.tween_property(
		button,
		"self_modulate",
		base_modulate,
		0.105
	)
	var _delay_result: Tweener = modulate_tweener.set_delay(maxf(delay, 0.0))
	var _curve_result: Tweener = modulate_tweener.set_trans(Tween.TRANS_QUAD)
	var _ease_result: Tweener = modulate_tweener.set_ease(Tween.EASE_OUT)
	button.set_meta(_BUTTON_TEXT_TWEEN_META, tween)


func _kill_button_text_tween(button: BaseButton) -> void:
	var tween: Tween = _get_tween_value(
		_get_button_meta(button, _BUTTON_TEXT_TWEEN_META, null)
	)
	if tween != null and tween.is_valid():
		tween.kill()
	button.set_meta(_BUTTON_TEXT_TWEEN_META, null)


func _kill_button_tween(button: BaseButton) -> void:
	var tween: Tween = _get_tween_value(_get_button_meta(button, _TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	button.set_meta(_TWEEN_META, null)


func _sync_button_disabled_state(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_DISABLED_STATE_META, button.disabled)
	button.set_meta(_PRESSED_META, false)
	if button.disabled:
		button.set_meta(_HOVERED_META, false)
		button.set_meta(_FOCUSED_META, false)
		if button.has_focus():
			button.release_focus()
	else:
		var is_hovered: bool = (
			button.is_inside_tree()
			and button.is_visible_in_tree()
			and button.get_global_rect().has_point(
				button.get_viewport().get_mouse_position()
			)
		)
		button.set_meta(_HOVERED_META, is_hovered)
		button.set_meta(_FOCUSED_META, button.has_focus())
		button.set_meta(_TOGGLE_STATE_META, button.button_pressed)
	_update_button_focus_ring_visibility(button)
	_refresh_button_motion_state(button, false)


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


func _prepare_numeric_delta_label(
	delta_label: Label,
	delta: int,
	color: Color,
	direction: Vector2
) -> void:
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
	delta_label.position = base_position + direction * _NUMERIC_DELTA_START_DISTANCE
	delta_label.pivot_offset = delta_label.size * 0.5
	delta_label.scale = base_scale * 0.78
	delta_label.modulate = color
	delta_label.visible = true


func _next_numeric_delta_direction() -> Vector2:
	# 增量标签的基础位置已与主数字错开；只向右上方的窄扇区离场，
	# 避免全圆散射在后半程重新穿过主数字或掉进棋盘区域。
	var lane: float = float(_numeric_scatter_sequence % 3) - 1.0
	var direction: Vector2 = Vector2(1.0, -0.32 + lane * 0.16).normalized()
	_numeric_scatter_sequence = (_numeric_scatter_sequence + 1) % 64
	return direction


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


func _get_accessibility_utility() -> GameAccessibilityUtility:
	var utility_value: Object = get_utility(GameAccessibilityUtility)
	if utility_value is GameAccessibilityUtility:
		var accessibility: GameAccessibilityUtility = utility_value
		return accessibility
	return null


func _is_reduced_motion() -> bool:
	if not is_instance_valid(_accessibility):
		_accessibility = _get_accessibility_utility()
	return (
		is_instance_valid(_accessibility)
		and _accessibility.get_state().reduced_motion
	)


func _play_fallback_toggle_settle(button: BaseButton) -> void:
	_kill_button_tween(button)
	var base_scale: Vector2 = _get_button_base_scale(button)
	button.modulate = _get_button_base_modulate(button)
	if _is_reduced_motion() or not button.is_inside_tree():
		button.scale = base_scale
		return
	var tween: Tween = button.create_tween()
	var _pause_mode_result: Tween = tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS
	)
	var compress_tweener: PropertyTweener = tween.tween_property(
		button,
		"scale",
		base_scale * Vector2(0.975, 0.94),
		0.052
	)
	var _compress_curve: Tweener = compress_tweener.set_trans(Tween.TRANS_QUAD)
	var _compress_ease: Tweener = compress_tweener.set_ease(Tween.EASE_OUT)
	var restore_tweener: PropertyTweener = tween.tween_property(
		button,
		"scale",
		base_scale,
		0.088
	)
	var _restore_curve: Tweener = restore_tweener.set_trans(Tween.TRANS_BACK)
	var _restore_ease: Tweener = restore_tweener.set_ease(Tween.EASE_OUT)
	button.set_meta(_TWEEN_META, tween)


# --- 信号处理函数 ---

func _on_button_mouse_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_HOVERED_META, true)
	if is_instance_valid(_style):
		var presenter: GameButtonMotionPresenter = (
			_style.get_button_motion_presenter(button)
		)
		if is_instance_valid(presenter):
			presenter.set_contact_position(button.get_local_mouse_position())
	_update_button_focus_ring_visibility(button)
	interactive_control_selected.emit(button)
	_refresh_button_motion_state(button)


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
	if not GFVariantData.to_bool(_get_button_meta(button, _HOVERED_META, false)):
		interactive_control_selected.emit(button)
	_refresh_button_motion_state(button)


func _on_button_focus_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_FOCUSED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_down(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_PRESSED_META, true)
	_update_button_focus_ring_visibility(button)
	interactive_control_confirmed.emit(button)
	_refresh_button_motion_state(button)


func _on_button_up(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_PRESSED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_toggled(pressed: bool, button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_TOGGLE_STATE_META, pressed)
	call_deferred(&"_on_button_toggle_settle", button)


func _on_button_toggle_settle(button: BaseButton = null) -> void:
	if not is_instance_valid(button):
		return
	var presenter: GameButtonMotionPresenter = null
	if is_instance_valid(_style):
		presenter = _style.get_button_motion_presenter(button)
	if is_instance_valid(presenter):
		_refresh_button_motion_state(button)
		return
	_play_fallback_toggle_settle(button)


func _on_button_resized(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.pivot_offset = button.size * 0.5
	if is_instance_valid(_style):
		_style.refresh_button_focus_ring(button)
	complete_button_motion(button)


func _on_button_tree_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_tween(button)
	_kill_button_text_tween(button)


func _on_scroll_container_started(scroll_container: ScrollContainer) -> void:
	if not is_instance_valid(scroll_container):
		return
	_animate_scroll_bar_activity(scroll_container.get_v_scroll_bar(), false)
	_animate_scroll_bar_activity(scroll_container.get_h_scroll_bar(), false)


func _on_scroll_container_ended(scroll_container: ScrollContainer) -> void:
	if not is_instance_valid(scroll_container):
		return
	_animate_scroll_bar_idle(scroll_container.get_v_scroll_bar())
	_animate_scroll_bar_idle(scroll_container.get_h_scroll_bar())


func _on_scroll_bar_mouse_entered(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	scroll_bar.set_meta(_SCROLL_HOVERED_META, true)
	_animate_scroll_bar_activity(scroll_bar, false)


func _on_scroll_bar_mouse_exited(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	scroll_bar.set_meta(_SCROLL_HOVERED_META, false)
	_animate_scroll_bar_idle(scroll_bar)


func _on_scroll_bar_tree_exited(scroll_bar: ScrollBar) -> void:
	if not is_instance_valid(scroll_bar):
		return
	_kill_scroll_bar_tween(scroll_bar)


func _on_tab_container_changed(tab_index: int, tab_container: TabContainer) -> void:
	if not is_instance_valid(tab_container):
		return
	var previous_index: int = GFVariantData.to_int(
		_get_control_meta(tab_container, _TAB_INDEX_META, tab_index),
		tab_index
	)
	tab_container.set_meta(_TAB_INDEX_META, tab_index)
	var content_node: Node = tab_container.get_current_tab_control()
	if not content_node is Control:
		return
	var content: Control = content_node
	var _content_tween: Tween = play_content_switch(
		content,
		float(tab_index - previous_index)
	)
