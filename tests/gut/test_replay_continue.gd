## 验证回放继续游玩时的命令历史处理。
extends GutTest


# --- 测试用例 ---

func test_continue_from_current_step_clears_redo_history() -> void:
	var command_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	command_history.init()
	command_history.deserialize_full_history(
		{
			"undo": [
				_make_move_command_data(Vector2i.ZERO, true),
				_make_move_command_data(Vector2i.RIGHT, false),
			],
			"redo": [
				_make_move_command_data(Vector2i.DOWN, false),
			],
		},
		Callable(MoveCommand, "deserialize")
	)

	var replay_data: ReplayData = ReplayData.new()
	replay_data.actions = [
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
	]

	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._command_history = command_history
	replay_system.activate_replay_mode(replay_data)

	replay_system.continue_from_current_step()

	assert_eq(command_history.undo_count, 2, "从当前步继续时应保留已确认执行的历史。")
	assert_eq(command_history.redo_count, 0, "从当前步继续时应丢弃回放中尚未确认的未来步骤。")
	assert_false(replay_system.is_replay_active(), "继续游玩后应退出回放模式。")


# --- 私有/辅助方法 ---

func _make_move_command_data(direction: Vector2i, is_baseline: bool) -> Dictionary:
	return {
		&"direction_x": direction.x,
		&"direction_y": direction.y,
		&"snapshot": {},
		&"reverse_map": {},
		&"is_baseline": is_baseline,
	}
