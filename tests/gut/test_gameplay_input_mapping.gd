## 验证玩法输入上下文与 gf 输入映射工具的按键消费时序。
extends GutTest


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://features/gameplay/resources/input/gameplay_input_context.tres")
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_REDO: StringName = &"redo"


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


func test_redo_keyboard_mapping_is_registered() -> void:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	input_mapping.handle_input_event(_make_key_event(KEY_Y, KEY_Y))

	assert_true(input_mapping.consume_action(ACTION_REDO), "Y 键应映射为重做动作。")
	assert_false(input_mapping.consume_action(ACTION_REDO), "重做动作应只消费一次。")


func test_invalid_move_feedback_uses_gf_notification_queue() -> void:
	var input_system: PlayerInputSystem = PlayerInputSystem.new()
	var notifications: GFNotificationUtility = GFNotificationUtility.new()
	input_system._notifications = notifications

	input_system._show_invalid_move_feedback()
	var notification_record: Dictionary = notifications.get_active_notification()

	assert_true(
		GFVariantData.get_option_string(notification_record, "message").contains("无法移动")
		or GFVariantData.get_option_string(notification_record, "message").contains("No move"),
		"无效移动提示应使用本地化文案或安全 fallback。"
	)
	var duration: float = GFVariantData.get_option_float(notification_record, "duration_seconds")
	assert_true(duration > 0.0 and duration <= 2.0, "无效移动提示应短暂显示。")
	assert_true(
		GFVariantData.get_option_int(notification_record, "level") == GFNotificationUtility.Level.WARNING,
		"无效移动应进入 GF 警告级通知队列。"
	)


func test_player_input_discards_gameplay_actions_while_time_is_paused() -> void:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)
	var time_utility: GFTimeUtility = GFTimeUtility.new()
	time_utility.init()
	time_utility.is_paused = true
	var pause_utility: GamePauseUtility = GamePauseUtility.new()
	pause_utility._time_utility = time_utility
	var input_system: PlayerInputSystem = PlayerInputSystem.new()
	input_system.init()
	input_system._input_mapping = input_mapping
	input_system._pause_utility = pause_utility
	input_system._is_active = true
	input_system._is_playing = true

	input_mapping.handle_input_event(_make_key_event(KEY_D, KEY_D))
	input_system.tick(0.016)

	assert_true(input_system.ignore_pause, "输入 System 应在 GF 暂停期间继续接收恢复意图。")
	assert_true(input_system.ignore_time_scale, "输入 System 不应受玩法时间缩放影响。")
	assert_false(
		input_mapping.consume_action(ACTION_MOVE_RIGHT),
		"暂停期间积累的移动输入必须被丢弃，不得在恢复后补执行。"
	)
	input_system.dispose()


# --- 私有/辅助方法 ---

func _make_key_event(keycode: Key, physical_keycode: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	return event
