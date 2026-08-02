## 验证无障碍状态、反馈配方和 VFX 性能矩阵的运行时契约。
extends GutTest


# --- 常量 ---

const _PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)
const _TILE_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/components/tile.tscn"
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
	assert_true(defaults.turn_subtitles_enabled, "默认应显示规范回合字幕。")
	assert_true(
		defaults.vfx_quality == GameAccessibilityState.VfxQuality.FULL,
		"默认应使用完整 VFX 档位。"
	)

	accessibility.set_reduced_motion(true)
	accessibility.set_haptics_enabled(false)
	accessibility.set_shader_effects_enabled(false)
	accessibility.set_vfx_quality(GameAccessibilityState.VfxQuality.REDUCED)
	accessibility.set_turn_subtitles_enabled(false)
	var changed: GameAccessibilityState = accessibility.get_state()
	assert_true(changed.reduced_motion, "减少动态效果应立即进入运行时快照。")
	assert_false(changed.haptics_enabled, "触觉关闭应立即进入运行时快照。")
	assert_false(changed.shader_effects_enabled, "Shader 关闭应立即进入运行时快照。")
	assert_false(changed.turn_subtitles_enabled, "回合字幕偏好应立即进入运行时快照。")
	assert_true(
		changed.vfx_quality == GameAccessibilityState.VfxQuality.REDUCED,
		"VFX 档位应由 GFSettingsUtility 统一持有。"
	)
	assert_signal_emit_count(accessibility, "state_changed", 5)
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


func test_minimal_budget_shortens_and_softens_core_tile_motion() -> void:
	var motion_profile: GameTileMotionProfile = _PROFILE.tile_motion_profile
	assert_not_null(motion_profile, "棋盘反馈 Profile 必须拥有统一的 Tile 动画节拍。")
	assert_true(motion_profile.is_valid_profile(), "正式 Tile 动画节拍必须完整有效。")
	assert_true(
		is_equal_approx(motion_profile.move_duration, 0.14)
		and is_equal_approx(motion_profile.spawn_duration, 0.11)
		and is_equal_approx(motion_profile.merge_pulse_duration, 0.09),
		"完整档必须保持逐帧标定后的核心动画节拍。"
	)
	assert_true(
		motion_profile.spawn_start_scale > 1.0
		and motion_profile.spawn_start_rotation_degrees >= 10.0,
		"新方块应以略放大、带方向的纸片落定替代透明小点淡入。"
	)

	var minimal_state: GameAccessibilityState = GameAccessibilityState.new()
	minimal_state.vfx_quality = GameAccessibilityState.VfxQuality.MINIMAL
	var minimal_budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(minimal_state)
	assert_true(
		Tile.get_move_animation_duration(motion_profile, minimal_budget)
		< Tile.get_move_animation_duration(motion_profile),
		"MINIMAL 必须缩短方块移动时长。"
	)
	assert_true(
		Tile.get_merge_animation_duration(motion_profile, minimal_budget)
		< Tile.get_merge_animation_duration(motion_profile),
		"MINIMAL 必须缩短方块合并脉冲时长。"
	)

	var tile: Tile = await _create_tile()
	var spawn_tween: Tween = tile.animate_spawn(motion_profile, minimal_budget)
	assert_true(
		is_instance_valid(spawn_tween) and spawn_tween.is_valid(),
		"MINIMAL 仍应保留短促且可排队等待的核心动画。"
	)
	assert_true(
		tile.scale.x > 1.0 and tile.scale.x < motion_profile.spawn_start_scale,
		"MINIMAL 的生成缩放幅度必须比完整档更接近静止状态。"
	)
	tile.reset_animation_state()

	var merge_tween: Tween = tile.animate_merge(
		Callable(),
		0.0,
		motion_profile,
		minimal_budget
	)
	var _merge_step_active: bool = merge_tween.custom_step(
		motion_profile.get_merge_pulse_duration(minimal_budget)
	)
	assert_true(
		tile.scale.x > 1.0 and tile.scale.x < motion_profile.merge_peak_scale,
		"MINIMAL 的合并峰值必须保留辨识度但降低幅度。"
	)
	tile.reset_animation_state()


func test_reduced_motion_snaps_core_tile_animation_and_preserves_impacts() -> void:
	var motion_profile: GameTileMotionProfile = _PROFILE.tile_motion_profile
	var reduced_motion_state: GameAccessibilityState = GameAccessibilityState.new()
	reduced_motion_state.reduced_motion = true
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(
		reduced_motion_state
	)
	var tile: Tile = await _create_tile()

	assert_null(
		tile.animate_move(Vector2(96.0, 48.0), motion_profile, budget),
		"减少动态时移动不得创建 Tween。"
	)
	assert_true(
		tile.position.is_equal_approx(Vector2(96.0, 48.0)),
		"减少动态时移动必须同步落到准确目标。"
	)
	assert_null(
		tile.animate_spawn(motion_profile, budget),
		"减少动态时生成不得创建 Tween。"
	)
	assert_true(
		tile.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(tile.modulate.a, 1.0),
		"减少动态时生成必须直接显示最终状态。"
	)

	tile.rotation_degrees = 7.0
	assert_null(
		tile.animate_merge(
			tile.set_meta.bind(&"_test_merge_impact", true),
			0.5,
			motion_profile,
			budget
		),
		"减少动态时合并不得保留延迟 Tween。"
	)
	assert_true(
		GFVariantData.to_bool(tile.get_meta(&"_test_merge_impact", false)),
		"减少动态仍必须同步执行合并冲击回调。"
	)
	assert_true(
		is_zero_approx(tile.rotation_degrees),
		"减少动态时合并必须清除可能残留的纸片旋转。"
	)
	assert_null(
		tile.animate_transform(
			tile.set_meta.bind(&"_test_transform_impact", true),
			0.5,
			motion_profile,
			budget
		),
		"减少动态时变换不得保留延迟 Tween。"
	)
	assert_true(
		GFVariantData.to_bool(tile.get_meta(&"_test_transform_impact", false)),
		"减少动态仍必须同步执行变换冲击回调。"
	)

	assert_null(
		tile.animate_value_growth(
			2,
			4,
			Color.DARK_GRAY,
			Color.WHITE,
			Color.WHITE,
			Color.BLACK,
			motion_profile,
			budget
		),
		"减少动态时数值成长不得创建 Tween。"
	)
	assert_true(tile.value_label.text == "4", "减少动态时数值必须直接落到合并结果。")
	assert_null(
		tile.animate_despawn(motion_profile, budget),
		"减少动态时离场不得创建 Tween。"
	)
	assert_true(is_zero_approx(tile.modulate.a), "减少动态时离场必须同步隐藏。")


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


func test_board_backdrop_rotation_respects_budget_and_rectangular_geometry() -> void:
	var backdrop: BoardMotionBackdrop = BoardMotionBackdrop.new()
	add_child_autofree(backdrop)
	backdrop.set_board_size(Vector2(400.0, 400.0))
	backdrop.play_turn_impulse(
		Vector2.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE,
		0.6,
		0.25,
		Color.WHITE,
		0
	)
	backdrop._process(0.32)
	assert_almost_eq(
		absf(rad_to_deg(backdrop.rotation)),
		22.5,
		0.2,
		"MINIMAL 动态预算只能保留四分之一的棋格旋转。"
	)

	backdrop.reset_feedback()
	backdrop.set_board_size(Vector2(600.0, 400.0))
	backdrop.play_turn_impulse(
		Vector2.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE,
		0.5,
		1.0,
		Color.WHITE,
		0
	)
	backdrop._process(0.12)
	assert_lte(
		absf(rad_to_deg(backdrop.rotation)),
		6.1,
		"宽矩形棋盘只允许短促的小角度背景受力。"
	)
	backdrop._process(0.38)
	assert_almost_eq(
		backdrop.rotation,
		0.0,
		0.001,
		"宽矩形棋盘反馈结束后必须回正，不能永久交换长宽轴。"
	)

	backdrop.play_turn_impulse(
		Vector2.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE,
		0.5,
		0.0,
		Color.WHITE,
		0
	)
	assert_almost_eq(backdrop.rotation, 0.0, 0.001, "减少动态效果必须立即清除背景旋转。")


# --- 私有/辅助方法 ---

func _create_tile() -> Tile:
	var node: Node = _TILE_SCENE.instantiate()
	if not node is Tile:
		if is_instance_valid(node):
			node.queue_free()
		assert_true(false, "Tile 场景必须实例化为 Tile。")
		return null
	var tile: Tile = node
	add_child_autofree(tile)
	await get_tree().process_frame
	return tile


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
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
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
