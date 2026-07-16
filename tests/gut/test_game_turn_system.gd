## 验证项目移动流程由 gf.turn_based 的一次性 Action 编排。
extends GutTest


# --- 测试用例 ---

func test_valid_move_resolves_once_through_gf_turn_flow() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid_model: GridModel = GridModel.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	var turn_flow: GFTurnFlowSystem = GFTurnFlowSystem.new()
	var rule_system: RuleSystem = RuleSystem.new()
	var counting_rule: CountingMoveRule = CountingMoveRule.new()
	var resolved_actions: Array[GFTurnAction] = []
	var _resolved_connection: Error = turn_flow.action_resolved.connect(
		func(action: GFTurnAction) -> void: resolved_actions.append(action)
	) as Error

	await architecture.register_model(GridModel, grid_model)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_system(GameFlowSystem, GameFlowSystem.new())
	await architecture.register_system(RuleSystem, rule_system)
	await architecture.register_system(GFTurnFlowSystem, turn_flow)
	await architecture.register_system(GameTurnSystem, GameTurnSystem.new())
	await architecture.init()

	grid_model.initialize(4, ClassicInteractionRule.new(), ClassicMovementRule.new())
	rule_system.register_rules([counting_rule])
	architecture.send_event(GameReadyData.new())

	var move_data: MoveData = MoveData.new()
	move_data.direction = Vector2i.RIGHT
	architecture.send_event(move_data)
	await get_tree().process_frame

	assert_true(
		GFVariantData.to_int(status_model.move_count.get_value(), 0) == 1,
		"一次 MoveData 应且只应结算一个移动回合。"
	)
	assert_true(counting_rule.execution_count == 1, "ON_MOVE 规则应且只应由 GF 回合 Action 解析一次。")
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
	assert_true(
		direction_matches,
		"GFTurnContext 应保留最近一次移动方向。"
	)
	assert_true(turn_flow.context.current_actor == null, "行动解析完成后 GF 应释放当前 actor。")

	architecture.dispose()


# --- 内部类 ---

class CountingMoveRule extends SpawnRule:
	var execution_count: int = 0

	func _init() -> void:
		trigger = TriggerType.ON_MOVE

	func execute(_context: RuleContext) -> bool:
		execution_count += 1
		return false
