## 验证玩法与编辑画布各自拥有独立的 GF 指针手势生命周期。
extends GutTest


func test_overlapping_viewport_controllers_do_not_share_gesture_state() -> void:
	var gameplay: BoardWorldViewportController = BoardWorldViewportController.new()
	var editor: BoardEditorViewportController = BoardEditorViewportController.new()
	gameplay._create_private_gesture_utility()
	editor._create_private_gesture_utility()

	assert_not_null(gameplay._gesture_utility)
	assert_not_null(editor._gesture_utility)
	assert_true(
		gameplay._gesture_utility != editor._gesture_utility,
		"重叠画布控制器必须拥有不同的 GFPointerGestureUtility 实例。"
	)
	assert_true(
		gameplay._gesture_utility.mouse_button_index == MOUSE_BUTTON_MIDDLE
		and editor._gesture_utility.mouse_button_index == MOUSE_BUTTON_MIDDLE
	)

	var gameplay_touch: InputEventScreenTouch = _make_touch(3, true, Vector2(24.0, 32.0))
	var editor_touch: InputEventScreenTouch = _make_touch(7, true, Vector2(64.0, 96.0))
	var _gameplay_handled: bool = (
		gameplay._gesture_utility.handle_input_event(gameplay_touch)
	)
	var _editor_handled: bool = (
		editor._gesture_utility.handle_input_event(editor_touch)
	)
	assert_true(gameplay._gesture_utility.get_active_pointer_count() == 1)
	assert_true(editor._gesture_utility.get_active_pointer_count() == 1)

	gameplay._dispose_private_gesture_utility()
	assert_null(gameplay._gesture_utility, "退出玩法画布应释放其私有手势实例。")
	assert_true(
		editor._gesture_utility.get_active_pointer_count() == 1,
		"释放玩法画布不得清空仍活动的编辑画布手势。"
	)
	assert_true(
		editor._gesture_utility.mouse_button_index == MOUSE_BUTTON_MIDDLE,
		"另一画布的配置不得被退出顺序恢复为过期值。"
	)

	editor._dispose_private_gesture_utility()
	assert_null(editor._gesture_utility)
	gameplay.free()
	editor.free()


# --- 私有/辅助方法 ---

func _make_touch(pointer_id: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = pointer_id
	event.pressed = pressed
	event.position = position
	return event
