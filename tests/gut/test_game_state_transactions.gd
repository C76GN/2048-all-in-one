## 验证规则状态键控与完整游戏状态恢复的事务边界。
extends GutTest


const _CLASSIC_DEFINITION_PATH: String = \
	"res://features/gameplay/resources/tiles/definitions/classic_numeric_tile.tres"


func test_rule_states_restore_by_stable_id_after_rule_reorder() -> void:
	var probability_rule: ProbabilisticRatioSpawnRule = ProbabilisticRatioSpawnRule.new()
	probability_rule.rule_state_id = &"test.probability"
	probability_rule.base_probability = 0.1
	probability_rule.max_probability = 0.9
	probability_rule.setup()
	assert_true(
		probability_rule.set_state({&"current_probability": 0.4}),
		"测试前置概率状态应可设置。"
	)

	var stateless_rule: SpawnRule = SpawnRule.new()
	stateless_rule.rule_state_id = &"test.stateless"
	var original_order: Array[SpawnRule] = [probability_rule, stateless_rule]
	var captured: Dictionary = RuleSystem.capture_rule_states(original_order)

	assert_true(
		probability_rule.set_state({&"current_probability": 0.8}),
		"测试应先改变运行时概率。"
	)
	var reordered: Array[SpawnRule] = [stateless_rule, probability_rule]
	assert_true(
		RuleSystem.restore_rule_states(captured, reordered),
		"规则数组重排后仍应按稳定 rule_state_id 恢复。"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			GFVariantData.to_dictionary(probability_rule.get_state()),
			&"current_probability"
		),
		0.4,
		0.000001,
		"概率规则应恢复其自身 ID 对应的状态。"
	)


func test_rule_state_schema_mismatch_is_rejected_without_partial_mutation() -> void:
	var probability_rule: ProbabilisticRatioSpawnRule = ProbabilisticRatioSpawnRule.new()
	probability_rule.rule_state_id = &"test.probability"
	probability_rule.base_probability = 0.1
	probability_rule.max_probability = 0.9
	probability_rule.setup()
	assert_true(
		probability_rule.set_state({&"current_probability": 0.6}),
		"测试前置概率状态应可设置。"
	)
	var rules: Array[SpawnRule] = [probability_rule]
	var mismatched: Dictionary = RuleSystem.capture_rule_states(rules)
	var entry: Dictionary = mismatched["test.probability"]
	entry[&"schema_version"] = probability_rule.rule_state_schema_version + 1

	assert_false(
		RuleSystem.restore_rule_states(mismatched, rules),
		"状态 schema 与当前规则不一致时必须拒绝恢复。"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			GFVariantData.to_dictionary(probability_rule.get_state()),
			&"current_probability"
		),
		0.6,
		0.000001,
		"拒绝不匹配状态时不得改变当前规则状态。"
	)


func test_game_state_restore_rolls_back_every_component_when_rule_apply_fails() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var grid: GridModel = GridModel.new()
	var status: GameStatusModel = GameStatusModel.new()
	var rule_system: RuleSystem = RuleSystem.new()
	var state_system: GameStateSystem = GameStateSystem.new()

	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, composition)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_model(GridModel, grid)
	await architecture.register_model(GameStatusModel, status)
	await architecture.register_system(RuleSystem, rule_system)
	await architecture.register_system(GameStateSystem, state_system)
	await architecture.init()

	var definition_resource: Resource = load(_CLASSIC_DEFINITION_PATH)
	assert_true(definition_resource is TileDefinition, "测试必须能加载经典方块定义。")
	if not definition_resource is TileDefinition:
		architecture.dispose()
		return
	var definition: TileDefinition = definition_resource
	var interaction_rule: ClassicInteractionRule = ClassicInteractionRule.new()
	interaction_rule.tile_definitions = [definition]
	interaction_rule.default_definition_id = definition.definition_id
	assert_true(
		grid.initialize(
			BoardTopology.create_rectangle(Vector2i(2, 1)),
			interaction_rule,
			ClassicMovementRule.new()
		),
		"事务恢复测试棋盘应初始化成功。"
	)
	assert_true(
		grid.place_tile(composition.create_tile(definition, 2), Vector2i.ZERO),
		"事务恢复测试方块应放置成功。"
	)

	var rejecting_rule: RejectingSpawnRule = RejectingSpawnRule.new()
	rejecting_rule.rule_state_id = &"test.rejecting"
	var rejecting_rules: Array[SpawnRule] = [rejecting_rule]
	assert_true(
		rule_system.register_rules(rejecting_rules),
		"测试规则应以稳定状态 ID 注册。"
	)
	status.score.set_value(10)
	status.set_target_state(2048, false)
	var before: Dictionary = state_system.get_full_game_state()
	var target: Dictionary = before.duplicate(true)
	target[&"score"] = 99
	var target_rules: Dictionary = GFVariantData.get_option_dictionary(
		target,
		&"rules_states"
	)
	var target_entry: Dictionary = target_rules["test.rejecting"]
	target_entry[&"state"] = {&"value": 2}
	rejecting_rule.reject_next_apply = true

	assert_false(
		state_system.restore_state(target),
		"任一规则在提交阶段拒绝状态时，完整恢复必须报告失败。"
	)
	assert_true(
		state_system.are_states_equal(before, state_system.get_full_game_state()),
		"恢复失败后棋盘、统计、RNG 与规则状态必须整体回滚。"
	)

	architecture.dispose()


# --- 内部类 ---

class RejectingSpawnRule extends SpawnRule:
	var value: int = 1
	var reject_next_apply: bool = false

	func get_state() -> Variant:
		return {&"value": value}

	## 校验测试规则的单值状态。
	## @param state: 待校验的测试规则状态。
	func is_state_valid(state: Variant) -> bool:
		return (
			state is Dictionary
			and state.size() == 1
			and GFVariantData.get_option_value(state, &"value") is int
			and GFVariantData.get_option_int(state, &"value", 0) > 0
		)

	## 应用测试规则状态，并可按脚本拒绝下一次提交。
	## @param state: 待应用的测试规则状态。
	func set_state(state: Variant) -> bool:
		if not is_state_valid(state):
			return false
		if reject_next_apply:
			reject_next_apply = false
			return false
		value = GFVariantData.get_option_int(state, &"value", 1)
		return true
