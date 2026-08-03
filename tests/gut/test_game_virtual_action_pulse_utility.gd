## 验证项目重触发策略委托 GF 虚拟脉冲、定时与 owner 生命周期。
extends GutTest


const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/gameplay/resources/input/gameplay_input_context.tres"
)


func test_pulse_uses_gf_typed_operation_and_releases_exactly_once() -> void:
	var timer: GFTimerUtility = _create_timer()
	var input_mapping: GFInputMappingUtility = _create_input_mapping()
	var source: GFVirtualInputSource = input_mapping.create_virtual_source(
		&"test_pulse",
		-1,
		timer
	)
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(GameplayInputActions.MOVE_LEFT, self, 0.25))
	var operation: GFVirtualInputPulseOperation = pulse_utility.get_active_operation(
		GameplayInputActions.MOVE_LEFT
	)
	assert_not_null(operation, "进行中的项目脉冲应暴露 GF 类型化句柄。")
	assert_true(operation.is_pending())
	assert_true(input_mapping.consume_action(GameplayInputActions.MOVE_LEFT))

	timer.tick(0.25)

	assert_true(operation.get_status() == GFVirtualInputPulseOperation.Status.COMPLETED)
	assert_true(operation.get_release_count() == 1, "GF lease 只能释放一次匹配贡献。")
	assert_false(input_mapping.is_action_active(GameplayInputActions.MOVE_LEFT))
	assert_true(pulse_utility.get_pending_action_count() == 0)
	pulse_utility.dispose()
	timer.dispose()


func test_repeated_pulse_retriggers_distinct_gf_action_edges() -> void:
	var timer: GFTimerUtility = _create_timer()
	var input_mapping: GFInputMappingUtility = _create_input_mapping()
	var source: GFVirtualInputSource = input_mapping.create_virtual_source(
		&"test_hud",
		-1,
		timer
	)
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(GameplayInputActions.UNDO, self, 0.5))
	var first_operation: GFVirtualInputPulseOperation = (
		pulse_utility.get_active_operation(GameplayInputActions.UNDO)
	)
	assert_true(input_mapping.consume_action(GameplayInputActions.UNDO))
	assert_true(
		pulse_utility.pulse(GameplayInputActions.UNDO, self, 0.5),
		"旧 GF pulse lease 仍活动时，第二次项目点击也应被接受。"
	)
	var second_operation: GFVirtualInputPulseOperation = (
		pulse_utility.get_active_operation(GameplayInputActions.UNDO)
	)

	assert_true(first_operation.get_status() == GFVirtualInputPulseOperation.Status.CANCELLED)
	assert_true(first_operation.get_terminal_reason() == &"manual_clear")
	assert_true(second_operation != first_operation)
	assert_true(
		input_mapping.consume_action(GameplayInputActions.UNDO),
		"项目 retrigger 必须先释放旧 lease，使第二次点击形成新的 just_started。"
	)

	timer.tick(0.5)
	assert_true(second_operation.get_status() == GFVirtualInputPulseOperation.Status.COMPLETED)
	assert_true(pulse_utility.get_pending_action_count() == 0)
	pulse_utility.dispose()
	timer.dispose()


func test_owner_exit_cancels_gf_pulse_and_clears_project_observer() -> void:
	var timer: GFTimerUtility = _create_timer()
	var input_mapping: GFInputMappingUtility = _create_input_mapping()
	var source: GFVirtualInputSource = input_mapping.create_virtual_source(
		&"test_owner",
		-1,
		timer
	)
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)
	var pulse_owner: Node = Node.new()
	add_child(pulse_owner)

	assert_true(pulse_utility.pulse(GameplayInputActions.PAUSE, pulse_owner, 1.0))
	var operation: GFVirtualInputPulseOperation = pulse_utility.get_active_operation(
		GameplayInputActions.PAUSE
	)
	pulse_owner.queue_free()
	await get_tree().process_frame

	assert_true(operation.get_status() == GFVirtualInputPulseOperation.Status.CANCELLED)
	assert_false(input_mapping.is_action_active(GameplayInputActions.PAUSE))
	assert_true(pulse_utility.get_pending_action_count() == 0)
	pulse_utility.dispose()
	timer.dispose()


func test_dispose_clears_gf_source_and_rejects_late_pulses() -> void:
	var timer: GFTimerUtility = _create_timer()
	var input_mapping: GFInputMappingUtility = _create_input_mapping()
	var source: GFVirtualInputSource = input_mapping.create_virtual_source(
		&"test_dispose",
		-1,
		timer
	)
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(GameplayInputActions.REDO, self, 1.0))
	var operation: GFVirtualInputPulseOperation = pulse_utility.get_active_operation(
		GameplayInputActions.REDO
	)
	pulse_utility.dispose()

	assert_true(operation.get_status() == GFVirtualInputPulseOperation.Status.CANCELLED)
	assert_false(input_mapping.is_action_active(GameplayInputActions.REDO))
	assert_true(pulse_utility.get_pending_action_count() == 0)
	assert_false(pulse_utility.pulse(GameplayInputActions.REDO, self, 0.1))
	timer.dispose()


func test_missing_gf_timer_returns_failed_project_pulse_without_pending_state() -> void:
	var input_mapping: GFInputMappingUtility = _create_input_mapping()
	var source: GFVirtualInputSource = input_mapping.create_virtual_source(&"test_missing_timer")
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_false(pulse_utility.pulse(GameplayInputActions.MOVE_UP, self, 0.1))
	assert_true(pulse_utility.get_pending_action_count() == 0)
	assert_false(input_mapping.is_action_active(GameplayInputActions.MOVE_UP))
	pulse_utility.dispose()


func test_realtime_timer_policy_ignores_pause_and_time_scale() -> void:
	var timer: GameRealtimeTimerUtility = GameRealtimeTimerUtility.new()

	assert_true(timer.ignore_pause, "输入脉冲计时器必须在暂停菜单期间继续推进。")
	assert_true(timer.ignore_time_scale, "输入脉冲计时器不得因玩法慢动作留下卡住贡献。")


func test_canonical_and_realtime_timers_coexist_as_distinct_gf_bindings() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var canonical_timer: GFTimerUtility = GFTimerUtility.new()
	var realtime_timer: GameRealtimeTimerUtility = GameRealtimeTimerUtility.new()

	await architecture.register_utility(GFTimerUtility, canonical_timer)
	await architecture.register_utility(GameRealtimeTimerUtility, realtime_timer)
	await architecture.init()

	assert_true(architecture.get_local_utility(GFTimerUtility) == canonical_timer)
	assert_true(
		architecture.get_local_utility(GameRealtimeTimerUtility) == realtime_timer
	)
	assert_false(canonical_timer.ignore_pause)
	assert_true(realtime_timer.ignore_pause)
	architecture.dispose()


# --- 私有/辅助方法 ---

func _create_timer() -> GFTimerUtility:
	var timer: GFTimerUtility = GFTimerUtility.new()
	timer.init()
	return timer


func _create_input_mapping() -> GFInputMappingUtility:
	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)
	return input_mapping
