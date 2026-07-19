## 验证玩法输入上下文与 gf 输入映射工具的按键消费时序。
extends GutTest


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://features/gameplay/resources/input/gameplay_input_context.tres")
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_REDO: StringName = &"redo"
const _SETTINGS_SCENE: PackedScene = preload(
	"res://features/settings/scenes/menus/settings_menu.tscn"
)


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


func test_keyboard_view_actions_are_part_of_gameplay_context() -> void:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	input_mapping.handle_input_event(_make_key_event(KEY_Q, KEY_Q))

	assert_true(
		input_mapping.consume_action(GameplayInputActions.VIEW_ZOOM_OUT),
		"键盘必须能够完成棋盘视图缩放。"
	)


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


func test_input_profile_persists_valid_rebind_and_rejects_conflict() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	settings.init()
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	var profile: GameInputProfileUtility = GameInputProfileUtility.new()
	profile._settings = settings
	profile._input_mapping = input_mapping
	profile._load_persisted_remap()

	var valid_report: Dictionary = profile.try_set_binding(
		&"gameplay",
		GameplayInputActions.MOVE_RIGHT,
		0,
		_make_key_event(KEY_X, KEY_X)
	)
	assert_true(GFVariantData.get_option_bool(valid_report, "ok"), "无冲突改键应提交。")
	var persisted: Dictionary = GFVariantData.to_dictionary(
		settings.get_value(GameInputProfileUtility.INPUT_REMAP_SETTING_KEY, {})
	)
	assert_false(
		GFVariantData.get_option_dictionary(persisted, "remapped_events").is_empty(),
		"GFInputRemapConfig 应通过 GFSettingsUtility 持久化。"
	)

	var conflict_report: Dictionary = profile.try_set_binding(
		&"gameplay",
		GameplayInputActions.MOVE_LEFT,
		0,
		_make_key_event(KEY_W, KEY_W)
	)
	assert_false(
		GFVariantData.get_option_bool(conflict_report, "ok"),
		"与默认向上操作冲突的 W 键不得静默覆盖。"
	)
	assert_gt(
		GFVariantData.get_option_int(conflict_report, "conflict_count"),
		0,
		"冲突结果应保留 GFInputConflictAnalyzer 的结构化报告。"
	)
	settings.dispose()


func test_input_timing_mode_defaults_to_realtime_and_is_persistent() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	settings.init()
	var profile: GameInputProfileUtility = GameInputProfileUtility.new()
	profile._settings = settings

	assert_true(
		profile.get_input_timing_mode()
		== GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET,
		"默认体验应立即响应新方向，不积压视觉动作。"
	)
	profile.set_input_timing_mode(
		GameInputProfileUtility.InputTimingMode.BLOCK_WHILE_ANIMATING
	)
	assert_true(
		GFVariantData.to_int(
			settings.get_value(GameInputProfileUtility.INPUT_TIMING_SETTING_KEY)
		) == GameInputProfileUtility.InputTimingMode.BLOCK_WHILE_ANIMATING
	)
	settings.dispose()


func test_board_animation_utility_applies_all_three_input_timing_policies() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	settings.init()
	var profile: GameInputProfileUtility = GameInputProfileUtility.new()
	profile._settings = settings
	var queue: GFActionQueueSystem = GFActionQueueSystem.new()
	queue.init()
	var animation_utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	animation_utility._input_profile = profile
	animation_utility._board_queue = queue

	profile.set_input_timing_mode(GameInputProfileUtility.InputTimingMode.BUFFERED)
	queue.is_processing = true
	assert_true(animation_utility.prepare_for_move(), "缓冲模式应接受新操作并排入视觉队列。")

	profile.set_input_timing_mode(
		GameInputProfileUtility.InputTimingMode.BLOCK_WHILE_ANIMATING
	)
	queue.is_processing = true
	assert_false(animation_utility.prepare_for_move(), "阻断模式应丢弃动画期间的新操作。")

	profile.set_input_timing_mode(GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET)
	queue.is_processing = true
	assert_true(animation_utility.prepare_for_move(), "实时模式应接受新操作。")
	assert_false(queue.is_processing, "实时模式应立即取消旧视觉动作，避免输入积压。")

	queue.dispose()
	settings.dispose()


func test_board_animation_utility_reacquires_queue_after_level_cleanup() -> void:
	var queue_root: GFActionQueueSystem = GFActionQueueSystem.new()
	queue_root.init()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var animation_utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	animation_utility._action_queue_system = queue_root
	assert_true(animation_utility.bind_board(board))
	var stale_queue: GFActionQueueSystem = animation_utility._board_queue

	queue_root.clear_all_named_queues(true)
	assert_true(
		animation_utility.enqueue(GFVisualAction.new()),
		"关卡清理后第一次棋盘动画必须自动取得新的 GF 命名队列。"
	)
	assert_not_same(animation_utility._board_queue, stale_queue)
	assert_true(
		GFVariantData.get_option_bool(
			animation_utility._board_queue.get_debug_snapshot(),
			"linked_node_alive"
		),
		"重建后的命名队列必须继续绑定棋盘生命周期。"
	)

	animation_utility.unbind_board(board)
	queue_root.dispose()


func test_settings_scene_exposes_timing_and_binding_controls() -> void:
	var scene_root: Node = _SETTINGS_SCENE.instantiate()
	assert_not_null(scene_root.get_node_or_null(
		"MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/CenterContentVBox/InputTimingContainer/InputTimingOptionButton"
	))
	assert_not_null(scene_root.get_node_or_null(
		"MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/CenterContentVBox/InputBindingsScroll/InputBindingsContainer"
	))
	assert_not_null(scene_root.get_node_or_null(
		"MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/CenterContentVBox/ResetBindingsButton"
	))
	assert_not_null(scene_root.get_node_or_null(
		"MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/CenterContentVBox/CompactBackButton"
	))
	scene_root.free()


func test_settings_layout_switches_to_single_column_on_narrow_viewports() -> void:
	assert_false(SettingsMenu.is_compact_layout(Vector2(1280.0, 720.0)))
	assert_true(SettingsMenu.is_compact_layout(Vector2(720.0, 1280.0)))
	assert_true(SettingsMenu.is_compact_layout(Vector2(390.0, 844.0)))


# --- 私有/辅助方法 ---

func _make_key_event(keycode: Key, physical_keycode: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	return event
