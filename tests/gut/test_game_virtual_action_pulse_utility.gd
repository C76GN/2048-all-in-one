## 验证项目虚拟动作脉冲的重入、取消与场景生命周期。
extends GutTest


func test_pulse_presses_then_releases_exactly_once() -> void:
	var source: RecordingVirtualInputSource = RecordingVirtualInputSource.new()
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(&"move_left", get_tree(), 0.0))
	assert_true(source.press_count == 1)
	assert_true(pulse_utility.get_pending_action_count() == 1)

	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(source.release_count == 1)
	assert_true(source.last_released_action == &"move_left")
	assert_true(pulse_utility.get_pending_action_count() == 0)


func test_repeated_pulse_only_allows_latest_token_to_release() -> void:
	var source: RecordingVirtualInputSource = RecordingVirtualInputSource.new()
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(&"move_right", get_tree(), 0.0))
	assert_true(pulse_utility.pulse(&"move_right", get_tree(), 0.0))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(source.press_count == 2)
	assert_true(source.release_count == 1, "较早 token 不得提前释放较新的脉冲。")
	assert_true(pulse_utility.get_pending_action_count() == 0)


func test_dispose_clears_source_and_late_timer_cannot_release_again() -> void:
	var source: RecordingVirtualInputSource = RecordingVirtualInputSource.new()
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_true(pulse_utility.pulse(&"pause", get_tree(), 0.0))
	pulse_utility.dispose()
	assert_true(source.clear_count == 1)
	assert_true(pulse_utility.get_pending_action_count() == 0)

	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(source.release_count == 0, "取消后的迟到计时器不得再次写入已释放来源。")
	assert_false(pulse_utility.pulse(&"pause", get_tree(), 0.0))


func test_failed_press_does_not_leave_pending_token() -> void:
	var source: RecordingVirtualInputSource = RecordingVirtualInputSource.new()
	source.accept_press = false
	var pulse_utility: GameVirtualActionPulseUtility = (
		GameVirtualActionPulseUtility.new().configure(source)
	)

	assert_false(pulse_utility.pulse(&"undo", get_tree(), 0.0))
	assert_true(pulse_utility.get_pending_action_count() == 0)
	assert_true(source.release_count == 0)


# --- 内部类 ---

class RecordingVirtualInputSource:
	extends GFVirtualInputSource

	var accept_press: bool = true
	var press_count: int = 0
	var release_count: int = 0
	var clear_count: int = 0
	var last_released_action: StringName = &""

	## 记录一次虚拟动作按下。
	## @param _action_id: 被按下的虚拟动作 ID。
	## @param _strength: 虚拟动作强度。
	func press(_action_id: StringName, _strength: float = 1.0) -> bool:
		press_count += 1
		return accept_press

	## 记录一次虚拟动作释放。
	## @param action_id: 被释放的虚拟动作 ID。
	func release(action_id: StringName) -> bool:
		release_count += 1
		last_released_action = action_id
		return true

	func clear_all() -> void:
		clear_count += 1
