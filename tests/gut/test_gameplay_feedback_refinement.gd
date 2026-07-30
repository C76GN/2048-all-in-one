## 验证普通棋盘移动降噪和 HUD Feedback Rail 的项目表现语义。
extends GutTest


# --- 常量 ---

const _PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)
const _HUD_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/hud.tscn"
)


# --- 测试用例 ---

func test_move_feedback_is_short_subtle_and_does_not_use_emphasis_channels() -> void:
	var setup: Dictionary = await _make_feedback_architecture()
	var architecture: GFArchitecture = setup[&"architecture"]
	var feedback: GameBoardFeedbackUtility = setup[&"feedback"]
	var shake: GFShakeUtility = setup[&"shake"]
	assert_true(feedback.apply_profile(_PROFILE))

	var move_recipe: GameFeedbackRecipe = _PROFILE.move_recipe
	assert_between(move_recipe.root_impulse, 3.0, 6.0)
	assert_lte(move_recipe.root_rotation_degrees, 0.3)
	assert_between(
		move_recipe.impact_duration + move_recipe.settle_duration,
		0.12,
		0.18
	)

	var root: Node2D = Node2D.new()
	root.position = Vector2(120.0, 80.0)
	root.set_meta(&"feedback_base_position", root.position)
	add_child_autoqfree(root)
	var canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	root.add_child(canvas)
	var backdrop: BoardMotionBackdrop = BoardMotionBackdrop.new()
	backdrop.set_board_size(Vector2(400.0, 400.0))
	root.add_child(backdrop)
	await get_tree().process_frame

	var fragment_count: int = feedback.play_turn_feedback(
		root,
		canvas,
		null,
		Vector2i.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.MOVE,
		Rect2(Vector2.ZERO, Vector2(400.0, 400.0)),
		Color.WHITE,
		backdrop
	)
	assert_true(fragment_count == 0, "普通移动不得生成装饰碎片。")
	assert_true(
		shake.get_active_shake_count(&"board") == 0,
		"普通移动不得提交 Shake。"
	)
	assert_true(canvas._turn_duration == 0.0, "普通移动不得播放棋盘边缘冲击。")
	assert_true(backdrop._duration == 0.0, "普通移动不得启动后层纸片冲击。")

	var tween_value: Variant = feedback._root_tweens.get(root.get_instance_id())
	assert_true(tween_value is Tween, "普通移动仍应保留短促的棋盘根节点确认。")
	if tween_value is Tween:
		var tween: Tween = tween_value
		var _impact_active: bool = tween.custom_step(0.05)
		var travel_distance: float = root.position.distance_to(Vector2(120.0, 80.0))
		assert_between(travel_distance, 3.0, 6.0)
		assert_lte(absf(root.rotation_degrees), 0.3)
		var _settle_active: bool = tween.custom_step(0.20)
		assert_true(root.position.is_equal_approx(Vector2(120.0, 80.0)))
		assert_almost_eq(root.rotation_degrees, 0.0, 0.001)

	architecture.dispose()


func test_merge_feedback_keeps_the_emphasis_channels() -> void:
	var setup: Dictionary = await _make_feedback_architecture()
	var architecture: GFArchitecture = setup[&"architecture"]
	var feedback: GameBoardFeedbackUtility = setup[&"feedback"]
	var shake: GFShakeUtility = setup[&"shake"]
	assert_true(feedback.apply_profile(_PROFILE))

	var root: Node2D = Node2D.new()
	root.position = Vector2(120.0, 80.0)
	root.set_meta(&"feedback_base_position", root.position)
	add_child_autoqfree(root)
	var canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	root.add_child(canvas)
	var backdrop: BoardMotionBackdrop = BoardMotionBackdrop.new()
	backdrop.set_board_size(Vector2(400.0, 400.0))
	root.add_child(backdrop)
	await get_tree().process_frame

	var fragment_count: int = feedback.play_turn_feedback(
		root,
		canvas,
		null,
		Vector2i.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.MERGE,
		Rect2(Vector2.ZERO, Vector2(400.0, 400.0)),
		Color.WHITE,
		backdrop
	)
	assert_gt(fragment_count, 0)
	assert_gt(shake.get_active_shake_count(&"board"), 0, "合并应保留 GF Shake 强调。")
	assert_gt(canvas._turn_duration, 0.0, "合并应保留棋盘边缘冲击。")
	assert_gt(backdrop._duration, 0.0, "合并应保留后层纸片反馈。")

	architecture.dispose()


func test_feedback_rail_uses_priority_and_interruptible_motion() -> void:
	var surface: Dictionary = await _make_feedback_surface()
	var hud: Hud = surface[&"hud"]
	var panel: PanelContainer = surface[&"panel"]
	var label: RichTextLabel = surface[&"label"]
	var rest_position: Vector2 = panel.position
	var record: Dictionary = {
		&"id": 42,
		&"message": "这个方向无法移动。",
		&"level": GFNotificationUtility.Level.WARNING,
		&"priority": GFNotificationUtility.Priority.HIGH,
		&"metadata": {},
	}

	hud._on_notification_started(record)

	assert_true(panel.visible)
	assert_true(label.text == "这个方向无法移动。")
	var motion_profile: GameUiMotionProfile = hud._get_notification_motion_profile()
	assert_true(
		panel.position.is_equal_approx(
			rest_position
			+ motion_profile.toast_enter_offset
				* Hud._NOTIFICATION_OFFSET_SCALE_HIGH
		)
	)
	assert_almost_eq(
		panel.modulate.a,
		1.0,
		0.001,
		"通知正文与承载底板必须从进入首帧起保持可读。"
	)
	var level_style_value: StyleBox = panel.get_theme_stylebox("panel")
	assert_true(level_style_value is StyleBoxFlat)
	if level_style_value is StyleBoxFlat:
		var level_style: StyleBoxFlat = level_style_value
		assert_true(
			level_style.border_width_left == 3,
			"高优先级通知应提高边缘辨识度。"
		)

	var enter_tween: Tween = hud._notification_motion_tween
	assert_not_null(enter_tween)
	if enter_tween != null:
		var _enter_active: bool = enter_tween.custom_step(
			motion_profile.toast_enter_duration
		)
	assert_true(panel.position.is_equal_approx(rest_position))
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)

	hud._on_notification_finished(record, "timeout")
	var exit_tween: Tween = hud._notification_motion_tween
	assert_not_null(exit_tween)
	if exit_tween != null:
		var _exit_active: bool = exit_tween.custom_step(
			motion_profile.toast_exit_duration
		)
	assert_false(panel.visible)
	assert_true(label.text.is_empty())
	hud.free()


func test_feedback_rail_motion_surface_is_inside_a_stable_container_slot() -> void:
	var hud_node: Node = _HUD_SCENE.instantiate()
	var panel_node: Node = hud_node.get_node(
		"SafeArea/FeedbackRail/NotificationSlot/NotificationPanel"
	)
	assert_true(hud_node is Hud)
	assert_true(panel_node is PanelContainer)
	if panel_node is PanelContainer and hud_node is Hud:
		var panel: PanelContainer = panel_node
		var slot: Node = panel.get_parent()
		assert_true(slot is Control and not slot is Container)
		assert_true(slot.get_parent() is VBoxContainer)
		if slot is Control:
			var typed_slot: Control = slot
			var hud: Hud = hud_node
			hud._notification_panel = panel
			hud._notification_slot = typed_slot
			hud._reset_notification_surface_layout()
		assert_true(
			panel.position.is_zero_approx()
			and panel.size.y <= 68.0
			and is_zero_approx(panel.anchor_right)
			and is_zero_approx(panel.anchor_bottom),
			"通知表面必须使用固定尺寸的 top-left 视觉根，避免填满反馈轨。"
		)
	hud_node.free()


func test_feedback_rail_reduced_motion_uses_static_terminal_states() -> void:
	var surface: Dictionary = await _make_feedback_surface()
	var hud: Hud = surface[&"hud"]
	var panel: PanelContainer = surface[&"panel"]
	var accessibility: GameAccessibilityUtility = surface[&"accessibility"]
	accessibility._state.reduced_motion = true
	var rest_position: Vector2 = panel.position
	var record: Dictionary = {
		&"id": 7,
		&"message": "存档已保存。",
		&"level": GFNotificationUtility.Level.SUCCESS,
		&"priority": GFNotificationUtility.Priority.NORMAL,
		&"metadata": {},
	}

	hud._on_notification_started(record)

	assert_true(panel.visible)
	assert_null(hud._notification_motion_tween)
	assert_true(panel.position.is_equal_approx(rest_position))
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)

	hud._on_notification_finished(record, "timeout")

	assert_false(panel.visible)
	assert_null(hud._notification_motion_tween)
	hud.free()


func test_feedback_rail_retargets_without_stale_exit_hiding_new_message() -> void:
	var surface: Dictionary = await _make_feedback_surface()
	var hud: Hud = surface[&"hud"]
	var panel: PanelContainer = surface[&"panel"]
	var label: RichTextLabel = surface[&"label"]
	var first_record: Dictionary = {
		&"id": 11,
		&"message": "正在保存。",
		&"level": GFNotificationUtility.Level.INFO,
		&"priority": GFNotificationUtility.Priority.LOW,
		&"metadata": {},
	}
	var second_record: Dictionary = {
		&"id": 12,
		&"message": "保存失败。",
		&"level": GFNotificationUtility.Level.ERROR,
		&"priority": GFNotificationUtility.Priority.CRITICAL,
		&"metadata": {},
	}

	hud._on_notification_started(first_record)
	var first_tween: Tween = hud._notification_motion_tween
	hud._on_notification_started(second_record)

	assert_false(first_tween.is_valid(), "新通知必须取消旧入场，不能并行争用同一表面。")
	assert_true(hud._active_notification_id == 12)
	assert_true(label.text == "保存失败。")
	assert_true(panel.visible)

	hud._on_notification_finished(first_record, "replaced")

	assert_true(hud._active_notification_id == 12)
	assert_true(panel.visible, "迟到的旧通知终态不得隐藏当前通知。")
	hud._on_notification_finished(second_record, "timeout")
	var exit_tween: Tween = hud._notification_motion_tween
	assert_not_null(exit_tween)
	if exit_tween != null:
		var _exit_active: bool = exit_tween.custom_step(
			hud._get_notification_motion_profile().toast_exit_duration
		)
	assert_false(panel.visible)
	hud.free()


func test_notification_producers_assign_semantic_priorities() -> void:
	var input_system: PlayerInputSystem = PlayerInputSystem.new()
	input_system._notifications = GFNotificationUtility.new()
	input_system._show_invalid_move_feedback()
	assert_true(
		GFVariantData.get_option_int(
			input_system._notifications.get_active_notification(),
			&"priority"
		) == GFNotificationUtility.Priority.LOW,
		"重复且低风险的无效移动提示应保持低优先级。"
	)

	var flow_system: GameFlowSystem = GameFlowSystem.new()
	flow_system._notifications = GFNotificationUtility.new()
	flow_system._push_gameplay_notification(
		"保存失败。",
		3.0,
		GFNotificationUtility.Level.ERROR,
		"gameplay.test_save_failed"
	)
	assert_true(
		GFVariantData.get_option_int(
			flow_system._notifications.get_active_notification(),
			&"priority"
		) == GFNotificationUtility.Priority.CRITICAL,
		"需要玩家处理的错误应进入最高通知优先级。"
	)


func test_real_gf_duplicate_record_stays_single_without_fake_aggregate_metadata() -> void:
	var notifications: GFNotificationUtility = GFNotificationUtility.new()
	var first_id: int = notifications.push_notification(
		"这个方向无法移动。",
		"",
		GFNotificationUtility.Level.WARNING,
		{&"key": "gameplay.invalid_move"}
	)
	var duplicate_id: int = notifications.push_notification(
		"这个方向无法移动。",
		"",
		GFNotificationUtility.Level.WARNING,
		{&"key": "gameplay.invalid_move"}
	)
	var record: Dictionary = notifications.get_active_notification()
	assert_true(first_id == duplicate_id, "GF 去重应返回同一个活动通知 ID。")
	assert_true(notifications.get_queue().is_empty(), "重复通知不得额外进入队列。")
	assert_false(
		GFVariantData.get_option_dictionary(record, &"metadata").has(
			&"aggregate_count"
		),
		"项目不得伪造 GF 10 生产路径不会提供的聚合计数。"
	)

	var surface: Dictionary = await _make_feedback_surface()
	var hud: Hud = surface[&"hud"]
	var label: RichTextLabel = surface[&"label"]
	hud._on_notification_started(record)
	assert_true(label.text == "这个方向无法移动。")
	hud.free()
	notifications.dispose()


# --- 私有/辅助方法 ---

func _make_feedback_architecture() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	var shake: GFShakeUtility = GFShakeUtility.new()
	var haptic: GFHapticUtility = GFHapticUtility.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	await architecture.register_utility(GFStorageUtility, GFStorageUtility.new())
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GameAccessibilityUtility, accessibility)
	await architecture.register_utility(GFShakeUtility, shake)
	await architecture.register_utility(GFHapticUtility, haptic)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameBoardFeedbackUtility, feedback)
	await architecture.init()
	return {
		&"architecture": architecture,
		&"feedback": feedback,
		&"shake": shake,
	}


func _make_feedback_surface() -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.94, 0.90, 1.0)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child_autoqfree(panel)
	var label: RichTextLabel = RichTextLabel.new()
	panel.add_child(label)
	await get_tree().process_frame
	var hud: Hud = Hud.new()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	motion._accessibility = accessibility
	hud._notification_panel = panel
	hud._notification_label = label
	hud._accessibility_utility = accessibility
	hud._ui_motion_utility = motion
	return {
		&"hud": hud,
		&"panel": panel,
		&"label": label,
		&"accessibility": accessibility,
	}
