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


func test_resume_request_only_unpauses_tree() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var panel: Control = Control.new()
	ui_utility.push_panel_instance(panel)
	var tree: SceneTree = get_tree()
	tree.paused = true

	architecture.send_simple_event(EventNames.RESUME_GAME_REQUESTED)
	var paused_after_resume: bool = tree.paused
	var open_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	tree.paused = false
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_resume, "继续挑战应恢复 SceneTree 暂停状态。")
	assert_true(open_panel_count == 1, "GameFlowSystem 不应越权关闭由 UI 路由拥有的弹层。")


func test_restart_request_preserves_ui_stack_and_delegates_restart() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: TestGameFlowSystemSpy = TestGameFlowSystemSpy.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var popup_panel: Control = Control.new()
	var top_panel: Control = Control.new()
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
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var router: TestSceneRouterSystemSpy = TestSceneRouterSystemSpy.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var popup_panel: Control = Control.new()
	var top_panel: Control = Control.new()
	ui_utility.push_panel_instance(popup_panel, GFUIUtility.Layer.POPUP)
	ui_utility.push_panel_instance(top_panel, GFUIUtility.Layer.TOP)
	var tree: SceneTree = get_tree()
	tree.paused = true

	architecture.send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)
	var paused_after_return: bool = tree.paused
	var popup_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	var top_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.TOP).size()
	var route_count: int = router.return_to_main_menu_count
	tree.paused = false
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_return, "返回主界面应恢复 SceneTree 暂停状态。")
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


func test_valid_move_resolves_once_through_gf_turn_flow() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
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
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_system(GameFlowSystem, GameFlowSystem.new())
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
	grid_model.initialize(4, interaction_rule, ClassicMovementRule.new())
	architecture.send_event(GameReadyData.new())

	var move_data: MoveData = MoveData.new()
	move_data.direction = Vector2i.RIGHT
	architecture.send_event(move_data)
	await get_tree().process_frame

	assert_true(
		GFVariantData.to_int(status_model.move_count.get_value(), 0) == 1,
		"一次 MoveData 应且只应结算一个移动回合。"
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


func _dispose_architecture_and_flush(architecture: GFArchitecture) -> void:
	architecture.dispose()
	await get_tree().process_frame
	await get_tree().process_frame
