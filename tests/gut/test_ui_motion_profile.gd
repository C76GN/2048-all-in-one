## 验证主题级 UI Motion Profile、可中断重定向与静态终态。
extends GutTest


# --- 常量 ---

const _HALFTONE_MOTION_PROFILE: GameUiMotionProfile = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_motion_profile.tres"
)


# --- 测试用例 ---

func test_default_profile_exposes_existing_and_forward_semantic_presets() -> void:
	assert_true(
		_HALFTONE_MOTION_PROFILE.get_validation_report().is_ok(),
		"默认 UI Motion Profile 应通过 GFValidationReport。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_BUTTON_ACTIVE
		),
		0.0,
		"按钮 active 语义应提供完整阶段时长。"
	)
	assert_true(
		_HALFTONE_MOTION_PROFILE.get_offset(
			GameUiMotionProfile.PRESET_TOAST_ENTER
		) == Vector2(0.0, 8.0),
		"Toast 入场应通过语义查询暴露外围位移。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_TOAST_EXIT
		),
		0.0,
		"Toast 退出应提供短促时长。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_delay(
			GameUiMotionProfile.PRESET_LOADING_DELAY
		),
		0.0,
		"Loading 应声明避免瞬时闪烁的延迟。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_PROGRESS_CHANGE
		),
		0.0,
		"Progress 变化应有独立语义时长。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_ERROR_LOCAL
		),
		0.0,
		"局部 Error 应有独立语义时长。"
	)
	assert_gt(
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_REWARD_RESULT_REVEAL
		),
		_HALFTONE_MOTION_PROFILE.get_duration(
			GameUiMotionProfile.PRESET_CONTENT_SWITCH
		),
		"结果揭示应比普通内容切换更有重量。"
	)


func test_utility_uses_applied_profile_for_panel_reveal() -> void:
	var panel: Control = Control.new()
	panel.position = Vector2(20.0, 30.0)
	panel.size = Vector2(200.0, 80.0)
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var profile: GameUiMotionProfile = GameUiMotionProfile.new()
	profile.panel_enter_offset = Vector2(0.0, 24.0)
	profile.panel_enter_start_scale = 0.91
	profile.panel_enter_duration = 0.31
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	assert_true(motion.apply_profile(profile), "有效 Profile 应能注入 Utility。")

	var tween: Tween = motion.play_panel_intro(panel)
	assert_not_null(tween, "自定义面板入场应创建 Tween。")
	assert_true(
		panel.position.is_equal_approx(Vector2(20.0, 54.0)),
		"面板入场应使用 Profile 的语义偏移。"
	)
	assert_true(
		panel.scale.is_equal_approx(Vector2.ONE * 0.91),
		"面板入场应使用 Profile 的起始缩放。"
	)
	motion.complete_control_motion(panel)


func test_control_reveal_rejects_null_and_freed_targets_without_side_effects() -> void:
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	assert_null(
		motion.play_control_reveal(null),
		"公开 reveal API 对 null 目标必须安全失败。"
	)
	var released_control: Control = Control.new()
	released_control.free()
	assert_null(
		motion.play_control_reveal(released_control),
		"公开 reveal API 对已释放目标必须安全失败。"
	)
	assert_null(
		motion.play_control_reveal(42),
		"公开 reveal API 对非 Object Variant 必须安全失败。"
	)
	assert_null(
		motion.play_control_reveal("not-a-control"),
		"公开 reveal API 对非控件 Variant 必须安全失败。"
	)


func test_content_switch_retargets_from_current_visual_state() -> void:
	var content: Control = Control.new()
	content.position = Vector2(80.0, 40.0)
	content.size = Vector2(240.0, 120.0)
	add_child_autoqfree(content)
	await get_tree().process_frame

	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var first_tween: Tween = motion.play_content_switch(content, 1.0)
	assert_not_null(first_tween, "首次内容切换应创建 Tween。")
	var _first_step_active: bool = first_tween.custom_step(0.05)
	var interrupted_position: Vector2 = content.position
	var interrupted_scale: Vector2 = content.scale
	var interrupted_modulate: Color = content.modulate

	var second_tween: Tween = motion.play_content_switch(content, -1.0)
	assert_false(first_tween.is_valid(), "新切换应取消旧 Tween。")
	assert_not_null(second_tween, "重定向后的切换应创建新 Tween。")
	assert_true(
		content.position.is_equal_approx(interrupted_position),
		"重定向不得跳回固定入场位置。"
	)
	assert_true(
		content.scale.is_equal_approx(interrupted_scale),
		"重定向不得重置为固定起始缩放。"
	)
	assert_true(
		content.modulate.is_equal_approx(interrupted_modulate),
		"重定向不得闪回全透明状态。"
	)
	motion.complete_control_motion(content)


func test_numeric_change_retargets_displayed_value_and_can_complete_now() -> void:
	var root: Control = Control.new()
	var value_label: Label = Label.new()
	var delta_label: Label = Label.new()
	value_label.size = Vector2(120.0, 40.0)
	root.add_child(value_label)
	value_label.add_child(delta_label)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var first_tween: Tween = motion.play_numeric_change(
		value_label,
		0,
		100,
		delta_label
	)
	assert_not_null(first_tween, "首次数值变化应创建 Tween。")
	var _first_step_active: bool = first_tween.custom_step(0.08)
	var displayed_value: int = value_label.text.to_int()
	assert_gt(displayed_value, 0, "首次计数应已产生可见中间值。")

	var second_tween: Tween = motion.play_numeric_change(
		value_label,
		100,
		200,
		delta_label
	)
	assert_false(first_tween.is_valid(), "新数值目标应取消旧 Tween。")
	assert_not_null(second_tween, "新数值目标应从当前画面继续。")
	assert_true(
		value_label.text.to_int() == displayed_value,
		"重定向应从当前显示值继续，不能跳回调用方旧值。"
	)
	assert_true(
		delta_label.text == "+%d" % (200 - displayed_value),
		"增量飘字应对应当前画面到新目标的剩余变化。"
	)

	motion.complete_numeric_motion(value_label)
	assert_false(second_tween.is_valid(), "complete_now 应取消仍在执行的 Tween。")
	assert_true(value_label.text == "200", "complete_now 应提交最后一次目标值。")
	assert_false(delta_label.visible, "complete_now 应清理增量飘字。")


func test_modal_reverse_retargets_without_transparency_flash() -> void:
	var root: Control = Control.new()
	var backdrop: ColorRect = ColorRect.new()
	var surface: PanelContainer = PanelContainer.new()
	backdrop.size = Vector2(640.0, 360.0)
	surface.size = Vector2(360.0, 220.0)
	root.add_child(backdrop)
	root.add_child(surface)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var intro_tween: Tween = motion.play_modal_intro(backdrop, surface)
	assert_not_null(intro_tween, "Modal 入场应创建 Tween。")
	var _intro_step_active: bool = intro_tween.custom_step(0.07)
	var outro_tween: Tween = motion.play_modal_outro(backdrop, surface)
	assert_false(intro_tween.is_valid(), "退出应取消仍在执行的入场。")
	var _outro_step_active: bool = outro_tween.custom_step(0.04)
	var interrupted_surface_alpha: float = surface.modulate.a
	var interrupted_backdrop_alpha: float = backdrop.modulate.a

	var resumed_intro: Tween = motion.play_modal_intro(backdrop, surface)
	assert_false(outro_tween.is_valid(), "重新打开应取消退出 Tween。")
	assert_not_null(resumed_intro, "重新打开应从当前画面重定向。")
	assert_true(
		is_equal_approx(surface.modulate.a, interrupted_surface_alpha),
		"重新打开不得把任务表面闪回全透明。"
	)
	assert_true(
		is_equal_approx(backdrop.modulate.a, interrupted_backdrop_alpha),
		"重新打开不得把遮罩闪回全透明。"
	)


func test_reward_result_reveal_uses_profile_and_keeps_cta_immediately_available() -> void:
	var surface: VBoxContainer = VBoxContainer.new()
	var title: Label = Label.new()
	var summary: Label = Label.new()
	var cta: Button = Button.new()
	cta.custom_minimum_size = Vector2(160.0, 44.0)
	surface.add_child(title)
	surface.add_child(summary)
	surface.add_child(cta)
	add_child_autoqfree(surface)
	await get_tree().process_frame

	var profile: GameUiMotionProfile = GameUiMotionProfile.new()
	profile.reward_result_start_scale = 0.90
	profile.reward_result_reveal_duration = 0.44
	profile.reward_result_reveal_stagger = 0.06
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	assert_true(motion.apply_profile(profile))

	var result_controls: Array[Control] = [title, summary]
	assert_true(
		motion.play_reward_result_controls(result_controls) == 2,
		"结果编排应只处理调用方声明的已提交表现控件。"
	)
	assert_true(
		title.scale.is_equal_approx(Vector2.ONE * 0.90),
		"结果控件应使用主题 reward start scale。"
	)
	assert_almost_eq(
		title.modulate.a,
		1.0,
		0.001,
		"结果业务真值必须从第 0 帧可读，动效只建立强调层级。"
	)
	assert_true(
		cta.scale.is_equal_approx(Vector2.ONE)
		and cta.modulate.is_equal_approx(Color.WHITE),
		"未纳入表现编排的 CTA 必须从第 0 帧可见且保持稳定命中根。"
	)
	motion.complete_children_motion(surface)


func test_local_error_feedback_preserves_layout_and_static_error_terminal() -> void:
	var status_label: Label = Label.new()
	status_label.size = Vector2(220.0, 44.0)
	status_label.modulate = Color(1.0, 0.62, 0.55, 1.0)
	add_child_autoqfree(status_label)
	await get_tree().process_frame

	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var terminal_modulate: Color = status_label.modulate
	var tween: Tween = motion.play_local_error(status_label)
	assert_not_null(tween)
	assert_true(
		status_label.scale.is_equal_approx(Vector2.ONE),
		"局部错误反馈不得改变标签布局或缩放。"
	)
	if tween != null:
		var _active: bool = tween.custom_step(
			motion.get_profile().local_error_duration
		)
	assert_true(
		status_label.modulate.is_equal_approx(terminal_modulate),
		"局部错误反馈必须回到调用方已提交的静态错误颜色。"
	)


func test_reduced_motion_interrupts_container_reveal_at_static_final_state() -> void:
	var host: VBoxContainer = VBoxContainer.new()
	var content: Control = Control.new()
	host.add_child(content)
	add_child_autoqfree(host)
	await get_tree().process_frame

	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	var accessibility_state: GameAccessibilityState = GameAccessibilityState.new()
	accessibility.set("_state", accessibility_state)
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	motion.set("_accessibility", accessibility)
	var first_tween: Tween = motion.play_content_switch(content)
	assert_not_null(first_tween, "普通模式下内容切换应创建 Tween。")
	var _first_step_active: bool = first_tween.custom_step(0.04)

	accessibility_state.reduced_motion = true
	accessibility.set("_state", accessibility_state)
	var reduced_tween: Tween = motion.play_content_switch(content)
	assert_null(reduced_tween, "减少动态时不得创建不可见 Tween。")
	assert_false(first_tween.is_valid(), "切换减少动态后应取消旧 Tween。")
	assert_true(content.scale.is_equal_approx(Vector2.ONE), "内容应直接落到基础缩放。")
	assert_true(
		content.modulate.is_equal_approx(Color.WHITE),
		"Container 内容应直接落到完全可见终态。"
	)
