## 验证玩法与编辑画布把导航手势交给各自的 GFSpatialCanvas2D 输入策略。
extends GutTest


func test_overlapping_viewport_controllers_use_isolated_spatial_input_policies() -> void:
	var gameplay: BoardWorldViewportController = BoardWorldViewportController.new()
	var editor: BoardEditorViewportController = BoardEditorViewportController.new()
	var gameplay_canvas: GFSpatialCanvas2D = GFSpatialCanvas2D.new()
	var editor_canvas: GFSpatialCanvas2D = GFSpatialCanvas2D.new()
	gameplay_canvas.size = Vector2(400.0, 300.0)
	editor_canvas.size = Vector2(400.0, 300.0)
	assert_true(gameplay_canvas.set_input_policy(gameplay._create_spatial_input_policy()))
	assert_true(editor_canvas.set_input_policy(editor._create_spatial_input_policy()))

	var gameplay_policy: GFSpatialCanvasInputPolicy = gameplay_canvas.get_input_policy()
	var editor_policy: GFSpatialCanvasInputPolicy = editor_canvas.get_input_policy()
	for policy: GFSpatialCanvasInputPolicy in [gameplay_policy, editor_policy]:
		assert_true(policy.pan_mouse_button == MOUSE_BUTTON_MIDDLE)
		assert_true(policy.selection_mouse_button == MOUSE_BUTTON_NONE)
		assert_true(
			policy.touch_primary_behavior
			== GFSpatialCanvasInputPolicy.TouchPrimaryBehavior.NONE
		)
		assert_true(policy.touch_multi_pan_enabled and policy.touch_multi_zoom_enabled)
		assert_true(policy.consume_handled_events and policy.consume_wheel_events)

	var press: InputEventMouseButton = _make_mouse_button(
		MOUSE_BUTTON_MIDDLE,
		true,
		Vector2(100.0, 100.0)
	)
	assert_true(
		gameplay_canvas.handle_input_event(press)
		== GFSpatialCanvas2D.InputDisposition.CONSUMED
	)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(120.0, 100.0)
	assert_true(
		gameplay_canvas.handle_input_event(motion)
		== GFSpatialCanvas2D.InputDisposition.CONSUMED
	)
	assert_false(gameplay_canvas.get_world_center().is_zero_approx())
	assert_true(
		editor_canvas.get_world_center().is_zero_approx(),
		"玩法画布的中键捕获不得修改编辑画布状态。"
	)

	gameplay_canvas.free()
	var wheel: InputEventMouseButton = _make_mouse_button(
		MOUSE_BUTTON_WHEEL_UP,
		true,
		Vector2(200.0, 150.0)
	)
	assert_true(
		editor_canvas.handle_input_event(wheel)
		== GFSpatialCanvas2D.InputDisposition.CONSUMED
	)
	assert_gt(editor_canvas.get_zoom(), 1.0, "另一画布应在玩法画布释放后继续独立响应滚轮。")

	editor_canvas.free()
	gameplay.free()
	editor.free()


# --- 私有/辅助方法 ---

func _make_mouse_button(
	button_index: MouseButton,
	pressed: bool,
	position: Vector2
) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = position
	return event
