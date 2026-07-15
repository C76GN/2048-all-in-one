## 验证回放继续游玩时的命令历史处理。
extends "res://tests/gut/support/gf_test_case.gd"


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

	assert_true(command_history.undo_count == 2, "从当前步继续时应保留已确认执行的历史。")
	assert_true(command_history.redo_count == 0, "从当前步继续时应丢弃回放中尚未确认的未来步骤。")
	assert_false(replay_system.is_replay_active(), "继续游玩后应退出回放模式。")


func test_game_flow_rejects_baseline_only_undo_history() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history([
		_make_move_command_data(Vector2i.ZERO, true),
	])

	assert_true(
		not flow_system._can_undo_player_move(command_history),
		"只剩 baseline 快照时应提示无法撤销。"
	)


func test_game_flow_rejects_zero_direction_move_for_undo() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history([
		_make_move_command_data(Vector2i.ZERO, false),
	])

	assert_true(
		not flow_system._can_undo_player_move(command_history),
		"零方向移动不应被视为可撤销的玩家移动。"
	)


func test_game_flow_accepts_last_player_move_for_undo() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history([
		_make_move_command_data(Vector2i.ZERO, true),
		_make_move_command_data(Vector2i.RIGHT, false),
	])

	assert_true(
		flow_system._can_undo_player_move(command_history),
		"最后一条玩家移动应允许撤销。"
	)


func test_game_flow_rejects_empty_redo_history() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history([
		_make_move_command_data(Vector2i.ZERO, true),
	])

	assert_true(
		not flow_system._can_redo_player_move(command_history),
		"没有 redo 历史时应提示无法重做。"
	)


func test_game_flow_rejects_baseline_only_redo_history() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history(
		[],
		[
			_make_move_command_data(Vector2i.ZERO, true),
		]
	)

	assert_true(
		not flow_system._can_redo_player_move(command_history),
		"baseline 快照不应被视为可重做的玩家移动。"
	)


func test_game_flow_rejects_zero_direction_move_for_redo() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history(
		[],
		[
			_make_move_command_data(Vector2i.ZERO, false),
		]
	)

	assert_true(
		not flow_system._can_redo_player_move(command_history),
		"零方向移动不应被视为可重做的玩家移动。"
	)


func test_game_flow_accepts_last_player_move_for_redo() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var command_history: GFCommandHistoryUtility = _make_history(
		[],
		[
			_make_move_command_data(Vector2i.RIGHT, false),
		]
	)

	assert_true(
		flow_system._can_redo_player_move(command_history),
		"最后一条玩家移动应允许重做。"
	)


# --- 私有/辅助方法 ---

func _make_flow_system() -> GameFlowSystem:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	track_gf_system(flow_system)
	return flow_system


func _make_history(undo_commands: Array, redo_commands: Array = []) -> GFCommandHistoryUtility:
	var command_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	command_history.init()
	command_history.deserialize_full_history(
		{
			"undo": undo_commands,
			"redo": redo_commands,
		},
		Callable(MoveCommand, "deserialize")
	)
	return command_history


func _make_move_command_data(direction: Vector2i, is_baseline: bool) -> Dictionary:
	return {
		&"schema_version": MoveCommand.SERIALIZATION_SCHEMA_VERSION,
		&"direction_x": direction.x,
		&"direction_y": direction.y,
		&"snapshot": {},
		&"reverse_map": {},
		&"is_baseline": is_baseline,
	}
