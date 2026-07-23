## 验证无障碍状态、反馈配方和 VFX 性能矩阵的运行时契约。
extends GutTest


# --- 常量 ---

const _PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)


# --- 测试用例 ---

func test_accessibility_state_is_persisted_through_gf_settings() -> void:
	var setup: Dictionary = await _make_accessibility_architecture()
	var accessibility: GameAccessibilityUtility = setup[&"accessibility"]
	watch_signals(accessibility)

	var defaults: GameAccessibilityState = accessibility.get_state()
	assert_false(defaults.reduced_motion, "默认不应强制减少动态效果。")
	assert_true(defaults.haptics_enabled, "默认应允许设备触觉。")
	assert_true(defaults.shader_effects_enabled, "默认应启用 Shader 表现。")
	assert_true(
		defaults.vfx_quality == GameAccessibilityState.VfxQuality.FULL,
		"默认应使用完整 VFX 档位。"
	)

	accessibility.set_reduced_motion(true)
	accessibility.set_haptics_enabled(false)
	accessibility.set_shader_effects_enabled(false)
	accessibility.set_vfx_quality(GameAccessibilityState.VfxQuality.REDUCED)
	var changed: GameAccessibilityState = accessibility.get_state()
	assert_true(changed.reduced_motion, "减少动态效果应立即进入运行时快照。")
	assert_false(changed.haptics_enabled, "触觉关闭应立即进入运行时快照。")
	assert_false(changed.shader_effects_enabled, "Shader 关闭应立即进入运行时快照。")
	assert_true(
		changed.vfx_quality == GameAccessibilityState.VfxQuality.REDUCED,
		"VFX 档位应由 GFSettingsUtility 统一持有。"
	)
	assert_signal_emit_count(accessibility, "state_changed", 4)
	var architecture_value: Variant = setup[&"architecture"]
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()
	else:
		assert_true(false, "测试 setup 必须提供 GFArchitecture。")


func test_vfx_performance_matrix_is_monotonic_and_reduced_motion_is_strict() -> void:
	var minimal_state: GameAccessibilityState = GameAccessibilityState.new()
	minimal_state.vfx_quality = GameAccessibilityState.VfxQuality.MINIMAL
	var reduced_state: GameAccessibilityState = GameAccessibilityState.new()
	reduced_state.vfx_quality = GameAccessibilityState.VfxQuality.REDUCED
	var full_state: GameAccessibilityState = GameAccessibilityState.new()
	full_state.vfx_quality = GameAccessibilityState.VfxQuality.FULL
	var minimal: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(minimal_state)
	var reduced: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(reduced_state)
	var full: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(full_state)

	assert_true(minimal.is_valid_budget() and reduced.is_valid_budget() and full.is_valid_budget())
	assert_true(
		minimal.max_tile_shards < reduced.max_tile_shards
		and reduced.max_tile_shards < full.max_tile_shards,
		"质量档位必须单调增加方块碎片预算。"
	)
	assert_true(
		minimal.celebration_particle_count < reduced.celebration_particle_count
		and reduced.celebration_particle_count < full.celebration_particle_count,
		"质量档位必须单调增加庆祝粒子预算。"
	)
	full_state.reduced_motion = true
	var motion_safe: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(full_state)
	assert_true(motion_safe.motion_scale == 0.0, "减少动态效果必须归零位移反馈。")
	assert_true(motion_safe.max_edge_fragments == 0, "减少动态效果不得绘制飞散边缘碎片。")
	assert_false(motion_safe.background_shader_enabled, "减少动态效果必须关闭背景冲击 Shader。")
	assert_false(motion_safe.celebration_shader_enabled, "减少动态效果必须改用静态庆祝反馈。")


func test_reduced_motion_disables_shake_haptics_and_background_impulse() -> void:
	var setup: Dictionary = await _make_accessibility_architecture(true)
	var architecture: GFArchitecture = setup[&"architecture"]
	var accessibility: GameAccessibilityUtility = setup[&"accessibility"]
	var feedback: GameBoardFeedbackUtility = setup[&"feedback"]
	var shake: GFShakeUtility = setup[&"shake"]
	var haptic: GFHapticUtility = setup[&"haptic"]
	assert_true(feedback.apply_profile(_PROFILE), "测试反馈 Profile 必须完整有效。")
	accessibility.set_reduced_motion(true)
	accessibility.set_haptics_enabled(false)

	var root: Node2D = Node2D.new()
	root.position = Vector2(120.0, 120.0)
	root.set_meta(&"feedback_base_position", root.position)
	add_child_autoqfree(root)
	var canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	root.add_child(canvas)
	var background: ColorRect = ColorRect.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(
		"res://features/asset_library/resources/shaders/background/halftone_paper_background.gdshader"
	)
	background.material = material
	add_child_autoqfree(background)
	await get_tree().process_frame

	var created: int = feedback.play_turn_feedback(
		root,
		canvas,
		background,
		Vector2i.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE,
		Rect2(Vector2.ZERO, Vector2(400.0, 400.0))
	)
	assert_true(created == 0, "减少动态效果下不得创建飞散棋盘碎片。")
	assert_true(root.position == Vector2(120.0, 120.0), "棋盘根节点不得产生位移冲击。")
	assert_true(shake.get_active_shake_count(&"board") == 0, "减少动态效果必须关闭震屏。")
	assert_true(haptic.get_active_haptic_count(&"board") == 0, "关闭触觉后不得提交设备振动。")
	assert_true(
		is_zero_approx(
			GFVariantData.to_float(material.get_shader_parameter(&"interaction_energy"), 0.0)
		),
		"减少动态效果必须清零背景交互能量。"
	)
	architecture.dispose()


# --- 私有/辅助方法 ---

func _make_accessibility_architecture(include_feedback: bool = false) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var signals: GFSignalUtility = GFSignalUtility.new()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFSignalUtility, signals)
	await architecture.register_utility(GameAccessibilityUtility, accessibility)
	var result: Dictionary = {
		&"architecture": architecture,
		&"accessibility": accessibility,
	}
	if include_feedback:
		var shake: GFShakeUtility = GFShakeUtility.new()
		var haptic: GFHapticUtility = GFHapticUtility.new()
		var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
		var feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
		await architecture.register_utility(GFShakeUtility, shake)
		await architecture.register_utility(GFHapticUtility, haptic)
		await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
		await architecture.register_utility(GameBoardFeedbackUtility, feedback)
		result[&"shake"] = shake
		result[&"haptic"] = haptic
		result[&"feedback"] = feedback
	await architecture.init()
	return result
