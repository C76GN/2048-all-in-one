## 验证玩法输入上下文与 gf 输入映射工具的按键消费时序。
extends GutTest


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://resources/input/gameplay_input_context.tres")
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"


# --- 测试用例 ---

func test_keyboard_action_survives_until_next_system_poll() -> void:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	input_mapping.handle_input_event(_make_key_event(KEY_D, KEY_D))
	await get_tree().process_frame

	assert_true(input_mapping.consume_action(ACTION_MOVE_RIGHT), "键盘输入不应在系统轮询前被 process_frame 提前清除。")
	assert_false(input_mapping.consume_action(ACTION_MOVE_RIGHT), "consume_action 应只消费一次 just_started 状态。")


func test_transient_keyboard_action_clears_after_next_frame_utility_tick() -> void:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	input_mapping.handle_input_event(_make_key_event(KEY_LEFT))
	assert_true(input_mapping.was_action_just_started(ACTION_MOVE_LEFT))

	input_mapping.tick(0.016)
	assert_true(input_mapping.was_action_just_started(ACTION_MOVE_LEFT), "同帧 utility tick 不应提前清除输入缓冲。")

	await get_tree().process_frame
	input_mapping.tick(0.016)

	assert_false(input_mapping.was_action_just_started(ACTION_MOVE_LEFT))
	assert_true(input_mapping.is_action_active(ACTION_MOVE_LEFT))


# --- 私有/辅助方法 ---

func _make_key_event(keycode: Key, physical_keycode: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	return event
