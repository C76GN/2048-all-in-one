## 验证 GameFlowSystem 的目标达成提示门控逻辑。
extends "res://tests/gut/support/gf_test_case.gd"


# --- 测试用例 ---

func test_target_reached_notification_is_gated_once_per_session() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config

	assert_true(
		not flow_system._should_notify_target_reached(1024),
		"未达到目标值时不应提示目标达成。"
	)
	assert_true(
		flow_system._should_notify_target_reached(2048),
		"首次达到目标值时应提示目标达成。"
	)

	flow_system._target_reached_notified = true
	assert_true(
		not flow_system._should_notify_target_reached(4096),
		"目标达成提示在同一会话中只应出现一次。"
	)


func test_target_reached_notification_is_disabled_without_mode_target() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	flow_system._mode_config = mode_config

	assert_true(
		not flow_system._should_notify_target_reached(4096),
		"没有配置目标值的模式不应触发目标达成提示。"
	)


func test_target_reached_notification_is_disabled_during_replay() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config
	flow_system._is_replay_mode = true

	assert_true(
		not flow_system._should_notify_target_reached(2048),
		"回放模式不应触发目标达成提示或弹层。"
	)


func test_target_state_sync_writes_status_model() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	flow_system._sync_target_state(false)

	assert_true(
		GFVariantData.to_int(status_model.target_tile_value.get_value(), 0) == 2048,
		"目标同步应写入当前模式的目标方块值。"
	)
	assert_true(
		not GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"未达成时运行时模型应保持 target_reached=false。"
	)

	flow_system._sync_target_state(true)

	assert_true(
		GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"目标达成后运行时模型应记录 target_reached=true。"
	)


func test_session_target_reached_uses_runtime_status_model() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	mode_config.target_tile_value = 2048
	status_model.set_target_state(2048, true)
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	assert_true(
		flow_system._has_reached_target_in_session(1024),
		"本局曾达成目标后，即使当前最高方块低于目标，结算仍应记为已达成。"
	)


func test_session_target_reached_requires_mode_target() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.set_target_state(2048, true)
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	assert_true(
		not flow_system._has_reached_target_in_session(4096),
		"未配置目标值的模式不应从运行时状态误判为目标达成。"
	)


func test_game_over_persistence_saga_survives_new_session_on_same_profile() -> void:
	var flow_system: TestPersistenceSagaFlowSystem = (
		TestPersistenceSagaFlowSystem.new()
	)
	var progress_spy: TestPendingProgressStatsSystem = (
		TestPendingProgressStatsSystem.new()
	)
	var replay_spy: TestImmediateReplaySystem = TestImmediateReplaySystem.new()
	track_gf_system(flow_system)
	track_gf_system(progress_spy)
	track_gf_system(replay_spy)
	flow_system.progress_spy = progress_spy
	flow_system.replay_spy = replay_spy
	flow_system._persistence_epoch = 7
	flow_system._persistence_owner_active = true
	flow_system.active_profile_file_name = "profiles/account-a.save"
	var recorded_result: GameResultRecordedData = GameResultRecordedData.new()
	var replay_data: ReplayData = ReplayData.new()

	@warning_ignore("return_value_discarded")
	flow_system._persist_game_over_artifacts.call_deferred(
		recorded_result,
		replay_data,
		12_345,
		flow_system._persistence_epoch,
		flow_system.active_profile_file_name
	)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		progress_spy.request_count == 1
		and progress_spy.last_duration_msec == 12_345
		and replay_spy.request_count == 0,
		"game-over saga 必须冻结 duration，并在 progress 终结前不提交 replay。"
	)

	flow_system._persistence_epoch += 1
	progress_spy.complete_pending_success()
	for _frame: int in range(4):
		await get_tree().process_frame
	assert_true(
		progress_spy.request_count == 1 and replay_spy.request_count == 1,
		"同一 Profile 开始新会话后，旧局冻结的 result 与 replay 仍必须串行完成。"
	)


func test_game_over_persistence_rejects_profile_changed_before_deferred_run() -> void:
	var flow_system: TestPersistenceSagaFlowSystem = (
		TestPersistenceSagaFlowSystem.new()
	)
	var progress_spy: TestPendingProgressStatsSystem = (
		TestPendingProgressStatsSystem.new()
	)
	var replay_spy: TestImmediateReplaySystem = TestImmediateReplaySystem.new()
	track_gf_system(flow_system)
	track_gf_system(progress_spy)
	track_gf_system(replay_spy)
	flow_system.progress_spy = progress_spy
	flow_system.replay_spy = replay_spy
	flow_system._persistence_epoch = 11
	flow_system._persistence_owner_active = true
	flow_system.active_profile_file_name = "profiles/account-a.save"
	var owner_profile_file_name: String = flow_system.active_profile_file_name

	@warning_ignore("return_value_discarded")
	flow_system._persist_game_over_artifacts.call_deferred(
		GameResultRecordedData.new(),
		ReplayData.new(),
		777,
		flow_system._persistence_epoch,
		owner_profile_file_name
	)
	flow_system.active_profile_file_name = "profiles/account-b.save"
	for _frame: int in range(3):
		await get_tree().process_frame

	assert_true(
		progress_spy.request_count == 0 and replay_spy.request_count == 0,
		"deferred saga 执行前账号已切换时，不得把旧账号终局产物写入新 Profile。"
	)


func test_game_over_persistence_stops_replay_after_profile_changes_mid_saga() -> void:
	var flow_system: TestPersistenceSagaFlowSystem = (
		TestPersistenceSagaFlowSystem.new()
	)
	var progress_spy: TestPendingProgressStatsSystem = (
		TestPendingProgressStatsSystem.new()
	)
	var replay_spy: TestImmediateReplaySystem = TestImmediateReplaySystem.new()
	track_gf_system(flow_system)
	track_gf_system(progress_spy)
	track_gf_system(replay_spy)
	flow_system.progress_spy = progress_spy
	flow_system.replay_spy = replay_spy
	flow_system._persistence_epoch = 17
	flow_system._persistence_owner_active = true
	flow_system.active_profile_file_name = "profiles/account-a.save"

	@warning_ignore("return_value_discarded")
	flow_system._persist_game_over_artifacts.call_deferred(
		GameResultRecordedData.new(),
		ReplayData.new(),
		888,
		flow_system._persistence_epoch,
		flow_system.active_profile_file_name
	)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		progress_spy.request_count == 1 and replay_spy.request_count == 0,
		"账号切换前，旧 Profile 的 progress 写入应已开始且 replay 尚未提交。"
	)

	flow_system.active_profile_file_name = "profiles/account-b.save"
	progress_spy.complete_pending_success()
	for _frame: int in range(4):
		await get_tree().process_frame
	assert_true(
		progress_spy.request_count == 1 and replay_spy.request_count == 0,
		"progress 终态到达前账号已切换时，不得向新 Profile 提交旧账号 replay。"
	)


func test_accessibility_context_matches_target_and_game_over_buttons() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	flow_system.init()
	flow_system._fsm.current_state_name = EventNames.STATE_PLAYING
	assert_true(
		flow_system.set_target_reached_modal_active(true),
		"玩法阶段应允许进入目标达成交互语义。"
	)

	var target_context: Dictionary = flow_system.get_accessibility_context()
	assert_true(
		GFVariantData.get_option_string_name(target_context, &"phase")
		== &"target_reached"
	)
	assert_true(
		GFVariantData.get_option_array(target_context, &"available_actions")
		== [&"continue", &"restart", &"return"],
		"目标达成语义必须逐项匹配弹窗按钮。"
	)

	flow_system._fsm.current_state_name = EventNames.STATE_GAME_OVER
	var game_over_context: Dictionary = flow_system.get_accessibility_context()
	assert_true(
		GFVariantData.get_option_string_name(game_over_context, &"phase")
		== &"game_over"
	)
	assert_true(
		GFVariantData.get_option_array(game_over_context, &"available_actions")
		== [&"restart", &"settings", &"return"],
		"游戏结束语义必须逐项匹配结算弹窗按钮。"
	)


func test_accessibility_phase_transitions_republish_canonical_actions() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var flow_system: TestAccessibilityPublishingFlowSystem = (
		TestAccessibilityPublishingFlowSystem.new()
	)
	var grid_model: GridModel = GridModel.new()
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i.ONE)
	assert_true(
		grid_model.initialize(topology, InteractionRule.new(), null),
		"无障碍阶段发布测试应建立有效棋盘。"
	)
	var tile: TileState = TileState.new(2, &"tile.test.accessibility_phase")
	tile.capability_recipe_ids = [&"recipe.test.accessibility_phase"]
	assert_true(grid_model.place_tile(tile, Vector2i.ZERO))

	var summary_utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var published: Array[GameAccessibilitySummary] = []
	var _summary_connected: Error = summary_utility.summary_published.connect(
		func(summary: GameAccessibilitySummary) -> void:
			published.append(summary)
	) as Error
	await _register_board_summary_dependencies(architecture)
	await architecture.register_model(GridModel, grid_model)
	await architecture.register_utility(
		GameAccessibilitySummaryUtility,
		summary_utility
	)
	await _register_pause_utilities(architecture)
	await architecture.register_utility(
		GFNotificationUtility,
		GFNotificationUtility.new()
	)
	flow_system.configure_dependencies(
		grid_model,
		null,
		null,
		null,
		null,
		null,
		summary_utility
	)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()
	flow_system._fsm.change_state(EventNames.STATE_PLAYING)
	flow_system._game_over_rule = StandardGameOverRule.new()

	assert_true(flow_system.set_target_reached_modal_active(true))
	assert_true(flow_system.set_target_reached_modal_active(false))
	assert_true(flow_system.check_game_over())

	assert_true(
		published.size() == 3,
		"目标弹层开、关与终局转换都必须各自立即发布一次权威摘要。"
	)
	if published.size() != 3:
		await _dispose_architecture_and_flush(architecture)
		return
	_assert_published_session(
		published[0],
		&"target_reached",
		[&"continue", &"restart", &"return"]
	)
	_assert_published_session(
		published[1],
		&"playing",
		[&"move", &"pause", &"hint", &"save_bookmark"]
	)
	_assert_published_session(
		published[2],
		&"game_over",
		[&"restart", &"settings", &"return"]
	)
	await _dispose_architecture_and_flush(architecture)


func test_target_move_turn_publishes_only_final_semantic_summary() -> void:
	var flow_system: TestTargetAccessibilityFlowSystem = (
		TestTargetAccessibilityFlowSystem.new()
	)
	track_gf_system(flow_system)
	flow_system.init()
	flow_system._fsm.current_state_name = EventNames.STATE_PLAYING
	var grid_model: GridModel = GridModel.new()
	assert_true(
		grid_model.initialize(
			BoardTopology.create_rectangle(Vector2i.ONE),
			InteractionRule.new(),
			null
		)
	)
	var tile: TileState = TileState.new(2048, &"tile.test.target_summary")
	tile.capability_recipe_ids = [&"recipe.test.target_summary"]
	assert_true(grid_model.place_tile(tile, Vector2i.ZERO))
	var status_model: GameStatusModel = GameStatusModel.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	mode_config.target_tile_value = 2048
	var summary_utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var published: Array[GameAccessibilitySummary] = []
	var _summary_connected: Error = summary_utility.summary_published.connect(
		func(summary: GameAccessibilitySummary) -> void:
			published.append(summary)
	) as Error
	flow_system._grid_model = grid_model
	flow_system._game_status_model = status_model
	flow_system._mode_config = mode_config
	flow_system._accessibility_summary = summary_utility

	var turn_result: TurnResult = TurnResult.new()
	turn_result.direction = Vector2i.RIGHT
	turn_result.movements.append(
		TileMovementResult.new(
			tile,
			Vector2i.ZERO,
			Vector2i.ZERO
		)
	)
	var action: GameMoveTurnAction = GameMoveTurnAction.new(
		grid_model,
		turn_result
	)
	action._rule_system = RuleSystem.new()
	action._game_flow_system = flow_system
	action._accessibility_summary_utility = summary_utility
	action._resolve(GFTurnContext.new())

	assert_true(
		published.size() == 1,
		"目标达成回合应只发布一次包含回合结果与最终操作语义的摘要。"
	)
	if published.size() != 1:
		return
	assert_true(
		published[0].kind == GameAccessibilitySummary.KIND_TURN,
		"目标达成回合的唯一摘要应保留移动、合并与得分语义。"
	)
	_assert_published_session(
		published[0],
		&"target_reached",
		[&"continue", &"restart", &"return"]
	)


func test_terminal_move_turn_publishes_only_final_semantic_summary() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid_model: GridModel = GridModel.new()
	assert_true(
		grid_model.initialize(
			BoardTopology.create_rectangle(Vector2i.ONE),
			InteractionRule.new(),
			null
		)
	)
	var tile: TileState = TileState.new(2, &"tile.test.terminal_summary")
	tile.capability_recipe_ids = [&"recipe.test.terminal_summary"]
	assert_true(grid_model.place_tile(tile, Vector2i.ZERO))
	var status_model: GameStatusModel = GameStatusModel.new()
	var summary_utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var published: Array[GameAccessibilitySummary] = []
	var _summary_connected: Error = summary_utility.summary_published.connect(
		func(summary: GameAccessibilitySummary) -> void:
			published.append(summary)
	) as Error
	var flow_system: TestAccessibilityPublishingFlowSystem = (
		TestAccessibilityPublishingFlowSystem.new()
	)
	var rule_system: RuleSystem = RuleSystem.new()
	await _register_board_summary_dependencies(architecture)
	await architecture.register_model(GridModel, grid_model)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(
		GameAccessibilitySummaryUtility,
		summary_utility
	)
	await _register_pause_utilities(architecture)
	await architecture.register_utility(
		GFNotificationUtility,
		GFNotificationUtility.new()
	)
	flow_system.configure_dependencies(
		grid_model,
		status_model,
		null,
		null,
		null,
		null,
		summary_utility
	)
	await architecture.register_system(RuleSystem, rule_system)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()
	flow_system._fsm.change_state(EventNames.STATE_PLAYING)
	flow_system._game_over_rule = StandardGameOverRule.new()

	var turn_result: TurnResult = TurnResult.new()
	turn_result.direction = Vector2i.RIGHT
	turn_result.movements.append(
		TileMovementResult.new(
			tile,
			Vector2i.ZERO,
			Vector2i.ZERO
		)
	)
	var action: GameMoveTurnAction = GameMoveTurnAction.new(
		grid_model,
		turn_result
	)
	action._inject_dependencies(architecture)
	action._resolve(GFTurnContext.new())

	assert_true(
		published.size() == 1,
		"终局回合应只发布一次包含回合结果与最终操作语义的摘要。"
	)
	if published.size() == 1:
		assert_true(
			published[0].kind == GameAccessibilitySummary.KIND_TURN,
			"终局回合的唯一摘要应保留移动、合并与得分语义。"
		)
		_assert_published_session(
			published[0],
			&"game_over",
			[&"restart", &"settings", &"return"]
		)
	await _dispose_architecture_and_flush(architecture)


func test_departing_gameplay_does_not_publish_stale_playing_summary() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid_model: GridModel = GridModel.new()
	assert_true(
		grid_model.initialize(
			BoardTopology.create_rectangle(Vector2i.ONE),
			InteractionRule.new(),
			null
		)
	)
	var tile: TileState = TileState.new(2, &"tile.test.departing_summary")
	tile.capability_recipe_ids = [&"recipe.test.departing_summary"]
	assert_true(grid_model.place_tile(tile, Vector2i.ZERO))
	var summary_utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var published: Array[GameAccessibilitySummary] = []
	var _summary_connected: Error = summary_utility.summary_published.connect(
		func(summary: GameAccessibilitySummary) -> void:
			published.append(summary)
	) as Error
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	var router: TestSceneRouterSystemSpy = TestSceneRouterSystemSpy.new()
	await _register_board_summary_dependencies(architecture)
	await architecture.register_model(GridModel, grid_model)
	await architecture.register_utility(
		GameAccessibilitySummaryUtility,
		summary_utility
	)
	await _register_pause_utilities(architecture)
	await architecture.register_utility(
		GFNotificationUtility,
		GFNotificationUtility.new()
	)
	flow_system.configure_dependencies(
		grid_model,
		null,
		null,
		null,
		_get_pause_utility(architecture),
		null,
		summary_utility,
		router
	)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()
	flow_system._fsm.change_state(EventNames.STATE_PLAYING)

	assert_true(flow_system.set_target_reached_modal_active(true))
	published.clear()
	architecture.send_simple_event(EventNames.RESTART_GAME_REQUESTED)
	assert_true(
		published.is_empty(),
		"重新开始离开当前对局时不得先播报旧棋盘的 playing 摘要。"
	)

	assert_true(flow_system.set_target_reached_modal_active(true))
	published.clear()
	architecture.send_simple_event(
		EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED
	)
	assert_true(
		published.is_empty(),
		"返回主菜单离开当前对局时不得先播报旧棋盘的 playing 摘要。"
	)
	await _dispose_architecture_and_flush(architecture)


func test_terminal_target_turn_records_goal_without_opening_target_modal() -> void:
	var flow_system: TestTerminalTargetFlowSystem = (
		TestTerminalTargetFlowSystem.new()
	)
	track_gf_system(flow_system)
	flow_system.init()
	flow_system._fsm.current_state_name = EventNames.STATE_PLAYING
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	mode_config.target_tile_value = 2048
	status_model.highest_tile.set_value(2048)
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	flow_system.settle_move_turn()

	assert_true(
		GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"终局回合仍必须保存本局已达成目标。"
	)
	assert_true(flow_system.game_over_check_count == 1)
	assert_true(
		flow_system.target_feedback_count == 0,
		"同回合已终局时不得再发 TARGET_REACHED 打开第二个弹窗。"
	)
	assert_false(
		flow_system._target_reached_modal_active,
		"终局语义中不得残留目标达成模态阶段。"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			flow_system.get_accessibility_context(),
			&"phase"
		) == &"game_over",
		"同回合达成目标并终局时，最终权威语义必须只有 game_over。"
	)


func test_resume_request_synchronizes_gf_time_without_closing_ui_stack() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await _register_pause_utilities(architecture)
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	flow_system.configure_dependencies(
		null,
		null,
		null,
		null,
		_get_pause_utility(architecture)
	)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var panel: Control = _make_test_control()
	ui_utility.push_panel_instance(panel)
	var pause_utility: GamePauseUtility = _get_pause_utility(architecture)
	assert_true(pause_utility.pause(), "测试前应通过统一 Adapter 暂停对局。")

	architecture.send_simple_event(EventNames.RESUME_GAME_REQUESTED)
	var paused_after_resume: bool = pause_utility.is_paused()
	var synchronized_after_resume: bool = pause_utility.is_synchronized()
	var open_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_resume, "继续挑战应恢复 GF 逻辑时间。")
	assert_true(synchronized_after_resume, "继续挑战后 GF 时间与 SceneTree 必须同步。")
	assert_true(open_panel_count == 1, "GameFlowSystem 不应越权关闭由 UI 路由拥有的弹层。")


func test_restart_request_preserves_ui_stack_and_delegates_restart() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await _register_pause_utilities(architecture)
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var popup_panel: Control = _make_test_control()
	var top_panel: Control = _make_test_control()
	ui_utility.push_panel_instance(popup_panel, GFUIUtility.Layer.POPUP)
	ui_utility.push_panel_instance(top_panel, GFUIUtility.Layer.TOP)

	architecture.send_simple_event(EventNames.RESTART_GAME_REQUESTED)
	var popup_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	var top_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.TOP).size()
	var restart_count: int = flow_system.restart_count
	await _dispose_architecture_and_flush(architecture)

	assert_true(popup_panel_count == 1, "GameFlowSystem 不应清空 UI 路由拥有的弹层栈。")
	assert_true(top_panel_count == 1, "GameFlowSystem 不应清空无关的顶层提示栈。")
	assert_true(restart_count == 1, "重新开始请求应委托 GameFlowSystem.restart_game()。")


func test_return_to_main_menu_request_preserves_ui_stack_unpauses_and_routes() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await _register_pause_utilities(architecture)
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	var router: TestSceneRouterSystemSpy = TestSceneRouterSystemSpy.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	flow_system.configure_dependencies(
		null,
		null,
		null,
		null,
		_get_pause_utility(architecture),
		null,
		null,
		router
	)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var popup_panel: Control = _make_test_control()
	var top_panel: Control = _make_test_control()
	ui_utility.push_panel_instance(popup_panel, GFUIUtility.Layer.POPUP)
	ui_utility.push_panel_instance(top_panel, GFUIUtility.Layer.TOP)
	var pause_utility: GamePauseUtility = _get_pause_utility(architecture)
	assert_true(pause_utility.pause(), "测试前应通过统一 Adapter 暂停对局。")

	architecture.send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)
	var paused_after_return: bool = pause_utility.is_paused()
	var synchronized_after_return: bool = pause_utility.is_synchronized()
	var popup_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	var top_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.TOP).size()
	var route_count: int = router.return_to_main_menu_count
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_return, "返回主界面应恢复 GF 逻辑时间。")
	assert_true(synchronized_after_return, "返回主界面后 GF 时间与 SceneTree 必须同步。")
	assert_true(popup_panel_count == 1, "GameFlowSystem 不应直接清空 UI 路由拥有的弹层栈。")
	assert_true(top_panel_count == 1, "GameFlowSystem 不应直接清空无关的顶层提示栈。")
	assert_true(route_count == 1, "返回主界面应调用 SceneRouterSystem.return_to_main_menu()。")


func test_game_ready_uses_explicit_bookmark_target_state() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	var ready_data: GameReadyData = GameReadyData.new()
	var bookmark: BookmarkData = BookmarkData.new()
	mode_config.target_tile_value = 2048
	bookmark.highest_tile = 4096
	bookmark.target_reached = false
	ready_data.mode_config = mode_config
	ready_data.loaded_bookmark_data = bookmark
	flow_system._game_status_model = status_model

	flow_system._on_game_ready(ready_data)

	assert_false(
		GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"当前书签 schema 的 target_reached 应是唯一事实，不得从最高方块重新推断。"
	)
	assert_false(
		flow_system._target_reached_notified,
		"显式未达成状态不得被旧兼容逻辑改写。"
	)


func test_game_ready_restores_bookmark_replay_trace_prefix() -> void:
	var flow_system: GameFlowSystem = _make_flow_system()
	var ready_data: GameReadyData = GameReadyData.new()
	var bookmark: BookmarkData = BookmarkData.new()
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = 1
	checkpoint.state_checksum = "a".repeat(64)
	checkpoint.board_checksum = "b".repeat(64)
	checkpoint.rng_checksum = "c".repeat(64)
	bookmark.replay_actions = [Vector2i.LEFT]
	bookmark.replay_checkpoints = [checkpoint]
	ready_data.loaded_bookmark_data = bookmark

	flow_system._on_game_ready(ready_data)

	assert_true(flow_system._player_actions == [Vector2i.LEFT], "书签操作前缀必须直接恢复。")
	assert_true(flow_system._turn_checkpoints.size() == 1, "书签 checkpoint 前缀必须直接恢复。")
	assert_true(
		flow_system._turn_checkpoints[0].state_checksum == checkpoint.state_checksum,
		"恢复后的 checkpoint 必须保留确定性摘要。"
	)


func test_valid_move_resolves_once_through_gf_turn_flow() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await _register_pause_utilities(architecture)
	var grid_model: GridModel = GridModel.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	var turn_flow: GFTurnFlowSystem = GFTurnFlowSystem.new()
	var resolved_actions: Array[GFTurnAction] = []
	var _resolved_connection: Error = turn_flow.action_resolved.connect(
		func(action: GFTurnAction) -> void: resolved_actions.append(action)
	) as Error

	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, TileCompositionUtility.new())
	await architecture.register_model(GridModel, grid_model)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	var notifications: GFNotificationUtility = GFNotificationUtility.new()
	var clock: GameClockUtility = GameClockUtility.new()
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	await architecture.register_utility(GFNotificationUtility, notifications)
	await architecture.register_utility(GameClockUtility, clock)
	flow_system.configure_dependencies(
		grid_model,
		status_model,
		clock,
		notifications,
		_get_pause_utility(architecture)
	)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.register_system(GFTurnFlowSystem, turn_flow)
	await architecture.register_system(GameTurnSystem, GameTurnSystem.new())
	await architecture.init()

	var definition_resource: Resource = load(
		"res://features/gameplay/resources/tiles/definitions/classic_numeric_tile.tres"
	)
	assert_true(definition_resource is TileDefinition, "应加载经典方块定义。")
	var interaction_rule: ClassicInteractionRule = ClassicInteractionRule.new()
	if definition_resource is TileDefinition:
		var definition: TileDefinition = definition_resource
		interaction_rule.tile_definitions = [definition]
		interaction_rule.default_definition_id = definition.definition_id
	assert_true(
		grid_model.initialize(
			BoardTopology.create_rectangle(Vector2i(4, 4)),
			interaction_rule,
			ClassicMovementRule.new()
		),
		"回合测试棋盘应初始化成功。"
	)
	architecture.send_event(GameReadyData.new())

	var turn_result: TurnResult = TurnResult.new()
	turn_result.direction = Vector2i.RIGHT
	turn_result.movements.append(
		TileMovementResult.new(TileState.new(), Vector2i.ZERO, Vector2i.RIGHT)
	)
	architecture.send_event(turn_result)
	await get_tree().process_frame

	assert_true(
		GFVariantData.to_int(status_model.move_count.get_value(), 0) == 1,
		"一次 TurnResult 应且只应结算一个移动回合。"
	)
	assert_true(resolved_actions.size() == 1, "GF 应发出一次 action_resolved 生命周期信号。")
	if resolved_actions.size() == 1:
		assert_true(resolved_actions[0] is GameMoveTurnAction, "已解析行动应保持项目强类型。")
		assert_true(resolved_actions[0].is_sealed(), "已离开 GF 队列的行动必须永久封存。")
	assert_true(turn_flow.get_action_count() == 0, "已解析回合 Action 不得残留在 GF 队列。")
	assert_true(
		GFVariantData.get_option_int(turn_flow.context.metadata, &"resolved_turn_count", 0) == 1,
		"GFTurnContext 应记录已解析回合数量。"
	)
	var last_direction: Variant = GFVariantData.get_option_value(
		turn_flow.context.metadata,
		&"last_move_direction",
		Vector2i.ZERO
	)
	var direction_matches: bool = false
	if last_direction is Vector2i:
		var typed_direction: Vector2i = last_direction
		direction_matches = typed_direction == Vector2i.RIGHT
	assert_true(direction_matches, "GFTurnContext 应保留最近一次移动方向。")
	assert_true(turn_flow.context.current_actor == null, "行动解析完成后 GF 应释放当前 actor。")

	await _dispose_architecture_and_flush(architecture)


# --- 私有/辅助方法 ---

func _make_flow_system() -> GameFlowSystem:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	track_gf_system(flow_system)
	return flow_system


func _make_test_control() -> Control:
	var control: Control = Control.new()
	track_test_node(control)
	return control


func _register_pause_utilities(architecture: GFArchitecture) -> void:
	await architecture.register_utility(GFTimeUtility, GFTimeUtility.new())
	await architecture.register_utility(GamePauseUtility, GamePauseUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())


## 注册 GridModel 与 GameAccessibilitySummaryUtility 声明的真实最小依赖链。
func _register_board_summary_dependencies(
	architecture: GFArchitecture
) -> void:
	await architecture.register_utility(
		GFCapabilityUtility,
		GFCapabilityUtility.new()
	)
	await architecture.register_utility(
		TileCompositionUtility,
		TileCompositionUtility.new()
	)
	await architecture.register_utility(
		GameDeterminismUtility,
		GameDeterminismUtility.new()
	)
	await architecture.register_utility(
		GamePlatformUtility,
		TestGamePlatformUtilityStub.new()
	)


func _get_pause_utility(architecture: GFArchitecture) -> GamePauseUtility:
	var utility_value: Object = architecture.get_utility(GamePauseUtility)
	if utility_value is GamePauseUtility:
		var pause_utility: GamePauseUtility = utility_value
		return pause_utility
	return null


func _dispose_architecture_and_flush(architecture: GFArchitecture) -> void:
	architecture.dispose()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_published_session(
	summary: GameAccessibilitySummary,
	expected_phase: StringName,
	expected_actions: Array
) -> void:
	assert_not_null(summary)
	if not is_instance_valid(summary):
		return
	var session: Dictionary = GFVariantData.get_option_dictionary(
		summary.canonical_payload,
		&"session"
	)
	assert_true(
		GFVariantData.get_option_string_name(session, &"phase")
		== expected_phase,
		"发布摘要的 phase 必须匹配当前交互阶段。"
	)
	assert_true(
		GFVariantData.get_option_array(session, &"available_actions")
		== expected_actions,
		"发布摘要的 actions 必须逐项匹配当前可操作控件。"
	)


# --- 内部类 ---

class TestPendingProgressStatsSystem:
	extends ProgressStatsSystem

	var request_count: int = 0
	var last_duration_msec: int = -1
	var pending_operation: GameSaveSectionOperation = null

	## @param _result: saga 传入的冻结规范结果。
	## @param duration_msec: saga 传入的冻结对局时长。
	func request_record_game_result(
		_result: GameResultRecordedData,
		duration_msec: int = 0
	) -> GameSaveSectionOperation:
		request_count += 1
		last_duration_msec = duration_msec
		pending_operation = GameSaveSectionOperation.new()
		var _configured: bool = pending_operation.configure_for_utility(
			request_count,
			&"test.profile",
			PackedStringArray(["progress"])
		)
		return pending_operation

	func complete_pending_success() -> void:
		if pending_operation == null or not pending_operation.is_pending():
			return
		var result: GameSaveSectionResult = GameSaveSectionResult.new()
		var _configured: bool = result.configure_for_utility(
			pending_operation.get_transaction_id(),
			pending_operation.get_profile_id(),
			pending_operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
		var _completed: bool = pending_operation.complete_for_utility(result)


class TestImmediateReplaySystem:
	extends ReplaySystem

	var request_count: int = 0

	## @param _replay_data: saga 传入的冻结回放。
	func request_save_replay(
		_replay_data: ReplayData
	) -> GameSaveSectionOperation:
		request_count += 1
		var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
		var _operation_configured: bool = operation.configure_for_utility(
			request_count + 100,
			&"test.profile",
			PackedStringArray(["replays"])
		)
		var result: GameSaveSectionResult = GameSaveSectionResult.new()
		var _result_configured: bool = result.configure_for_utility(
			operation.get_transaction_id(),
			operation.get_profile_id(),
			operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
		var _completed: bool = operation.complete_for_utility(result)
		return operation


class TestPersistenceSagaFlowSystem:
	extends GameFlowSystem

	var progress_spy: TestPendingProgressStatsSystem = null
	var replay_spy: TestImmediateReplaySystem = null
	var active_profile_file_name: String = ""

	func _get_progress_stats_system() -> ProgressStatsSystem:
		return progress_spy

	func _get_replay_system() -> ReplaySystem:
		return replay_spy


	func _get_active_persistence_profile_file_name() -> String:
		return active_profile_file_name


	func _get_save_graph_utility() -> GameSaveGraphUtility:
		return null


class TestAccessibilityPublishingFlowSystem:
	extends TestGameFlowSystemSpy

	func _handle_game_over() -> void:
		pass


class TestTargetAccessibilityFlowSystem:
	extends GameFlowSystem

	func _emit_target_reached_feedback() -> void:
		var _changed: bool = set_target_reached_modal_active(true)


class TestTerminalTargetFlowSystem:
	extends GameFlowSystem

	var game_over_check_count: int = 0
	var target_feedback_count: int = 0

	func check_game_over() -> bool:
		game_over_check_count += 1
		_target_reached_modal_active = false
		if _fsm != null:
			_fsm.current_state_name = EventNames.STATE_GAME_OVER
		return true

	func _emit_target_reached_feedback() -> void:
		target_feedback_count += 1
