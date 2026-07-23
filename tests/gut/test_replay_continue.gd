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


func test_replay_progress_is_published_after_a_step_settles() -> void:
	var command_history: GFCommandHistoryUtility = _make_history([
		_make_move_command_data(Vector2i.ZERO, true),
		_make_move_command_data(Vector2i.RIGHT, false),
	])
	var replay_data: ReplayData = ReplayData.new()
	replay_data.actions = [Vector2i.RIGHT, Vector2i.DOWN]
	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._command_history = command_history
	replay_system.activate_replay_mode(replay_data)

	var progress: Dictionary = {
		&"current": -1,
		&"total": -1,
	}
	var _progress_connection: int = replay_system.playback_progress_changed.connect(
		func(current_step: int, total_steps: int) -> void:
			progress[&"current"] = current_step
			progress[&"total"] = total_steps
	)
	replay_system.notify_playback_step_settled()

	assert_true(
		GFVariantData.get_option_int(progress, &"current", -1) == 1
		and GFVariantData.get_option_int(progress, &"total", -1) == 2,
		"回放命令落定后应发布基于 GF 命令历史的准确进度。"
	)


func test_first_replay_oos_is_retained_and_blocks_progression() -> void:
	var replay_system: ReplaySystem = ReplaySystem.new()
	var replay_data: ReplayData = ReplayData.new()
	replay_data.actions = [Vector2i.RIGHT]
	replay_system.activate_replay_mode(replay_data)
	watch_signals(replay_system)

	assert_true(
		replay_system.report_oos({&"step_index": 1, &"actual": "first"}),
		"首个回放差异必须进入 OOS 状态。"
	)
	assert_false(
		replay_system.report_oos({&"step_index": 2, &"actual": "later"}),
		"后续差异不得覆盖首个根因。"
	)
	assert_true(replay_system.is_playback_desynchronized(), "OOS 状态必须可查询。")
	assert_true(
		GFVariantData.get_option_int(replay_system.get_oos_report(), &"step_index") == 1,
		"诊断报告必须保留首个偏离回合。"
	)
	assert_false(
		replay_system.can_continue_from_current_step(),
		"已 OOS 的回放不得恢复为普通对局。"
	)
	assert_signal_emit_count(replay_system, "playback_desynchronized", 1)


func test_ineffective_replay_action_records_expected_checkpoint_context() -> void:
	var replay_system: ReplaySystem = ReplaySystem.new()
	var replay_data: ReplayData = ReplayData.new()
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = 1
	checkpoint.state_checksum = "a".repeat(64)
	checkpoint.board_checksum = "b".repeat(64)
	checkpoint.rng_checksum = "c".repeat(64)
	checkpoint.score = 32
	replay_data.actions = [Vector2i.RIGHT]
	replay_data.checkpoints = [checkpoint]
	replay_system.activate_replay_mode(replay_data)

	assert_true(
		replay_system.report_ineffective_action(Vector2i.RIGHT),
		"预期有效却未产生 TurnResult 的动作必须立即记录 OOS。"
	)
	var report: Dictionary = replay_system.get_oos_report()
	assert_true(
		GFVariantData.get_option_string_name(report, &"kind") == &"ineffective_action",
		"OOS 报告必须区分无效动作与 checksum 差异。"
	)
	assert_true(
		GFVariantData.get_option_int(report, &"step_index") == 1,
		"无效动作 OOS 必须记录首次偏离回合。"
	)
	assert_true(
		GFVariantData.get_option_string(report, &"expected_state_checksum")
		== checkpoint.state_checksum,
		"无效动作报告必须携带预期 checkpoint 上下文。"
	)


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
