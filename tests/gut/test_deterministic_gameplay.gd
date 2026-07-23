## 验证玩法随机流和状态比较使用 GF 的跨运行时确定性契约。
extends GutTest


# --- 测试用例 ---

func test_rule_context_replays_gf_deterministic_random_branches() -> void:
	var first_seed_utility: GFSeedUtility = _make_seed_utility(2048)
	var second_seed_utility: GFSeedUtility = _make_seed_utility(2048)
	var first_context: RuleContext = _make_rule_context(first_seed_utility)
	var second_context: RuleContext = _make_rule_context(second_seed_utility)

	var first_samples: Array[int] = _collect_branch_samples(first_context, "classic_spawn_rule", 8)
	var second_samples: Array[int] = _collect_branch_samples(second_context, "classic_spawn_rule", 8)

	assert_true(first_samples == second_samples, "相同主种子和分支顺序必须产生相同 GF 固定随机序列。")


func test_fixed_seed_corpus_detects_rng_algorithm_drift() -> void:
	var seed_utility: GFSeedUtility = _make_seed_utility(2048)
	var context: RuleContext = _make_rule_context(seed_utility)
	var samples: Array[int] = _collect_branch_samples(context, "classic_spawn_rule", 8)

	assert_true(
		samples == [
			1611755550,
			423263690,
			2586111150,
			1329051314,
			213418805,
			1637229787,
			1046281542,
			3504252434,
		],
		"固定 seed corpus 必须在 GF 升级或平台切换后保持不变。"
	)


func test_seed_full_state_restores_deterministic_branch_counters() -> void:
	var source: GFSeedUtility = _make_seed_utility(4096)
	var _first_stream: GFDeterministicRandom = source.get_branched_deterministic_random("game_board_spawn")
	var _second_stream: GFDeterministicRandom = source.get_branched_deterministic_random("game_board_spawn")
	var saved_state: Dictionary = source.get_full_state()
	var expected_stream: GFDeterministicRandom = source.get_branched_deterministic_random("game_board_spawn")
	var expected_value: int = expected_stream.next_u32()

	var restored: GFSeedUtility = _make_seed_utility(1)
	restored.set_full_state(saved_state)
	var restored_stream: GFDeterministicRandom = restored.get_branched_deterministic_random("game_board_spawn")

	assert_true(
		restored_stream.next_u32() == expected_value,
		"GFSeedUtility 完整状态必须恢复 deterministic 分支计数。"
	)


func test_game_state_equality_uses_canonical_variant_encoding() -> void:
	var state_system: GameStateSystem = GameStateSystem.new()
	var left: Dictionary = {}
	left[&"position"] = Vector2i(2, 4)
	left["probability"] = 0.25
	left[&"values"] = [2, 4, 8]

	var right: Dictionary = {}
	right[&"values"] = [2, 4, 8]
	right["probability"] = 0.25
	right[&"position"] = Vector2i(2, 4)

	assert_true(state_system.are_states_equal(left, right), "Dictionary 插入顺序不应影响 canonical 状态比较。")
	right[&"position"] = Vector2i(4, 2)
	assert_false(state_system.are_states_equal(left, right), "规范编码仍必须区分不同状态值。")


func test_board_checksum_ignores_runtime_tile_ids_and_input_order() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var left: Dictionary = _make_board_snapshot([
		_make_tile_snapshot(Vector2i(1, 0), 4, 1000),
		_make_tile_snapshot(Vector2i(0, 0), 2, 1001),
	])
	var right: Dictionary = _make_board_snapshot([
		_make_tile_snapshot(Vector2i(0, 0), 2, 2000),
		_make_tile_snapshot(Vector2i(1, 0), 4, 2001),
	])

	assert_true(
		determinism.calculate_board_checksum(left) == determinism.calculate_board_checksum(right),
		"语义相同的棋盘不得因 tile UUID 或容器插入顺序产生 OOS。"
	)
	right[&"tiles"][1][&"value"] = 8
	assert_false(
		determinism.calculate_board_checksum(left) == determinism.calculate_board_checksum(right),
		"会改变玩法结果的方块值必须改变棋盘校验和。"
	)


# --- 私有/辅助方法 ---

func _make_seed_utility(seed_value: int) -> GFSeedUtility:
	var utility: GFSeedUtility = GFSeedUtility.new()
	utility.init()
	utility.set_global_seed(seed_value)
	return utility


func _make_rule_context(seed_utility: GFSeedUtility) -> RuleContext:
	var context: RuleContext = RuleContext.new()
	context.seed_utility = seed_utility
	return context


func _collect_branch_samples(context: RuleContext, branch_id: String, count: int) -> Array[int]:
	var samples: Array[int] = []
	for _index: int in range(count):
		var random_stream: GFDeterministicRandom = context.get_random_stream(branch_id)
		assert_true(random_stream != null, "规则上下文应返回 GFDeterministicRandom。")
		if random_stream != null:
			samples.append(random_stream.next_u32())
	return samples


func _make_board_snapshot(tiles: Array[Dictionary]) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": BoardTopology.create_rectangle(Vector2i(2, 1)).to_dict(),
		&"tiles": tiles,
	}


func _make_tile_snapshot(position: Vector2i, value: int, timestamp_msec: int) -> Dictionary:
	return {
		&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": GFUuid.generate_v7(timestamp_msec),
		&"definition_id": &"tile.classic.numeric",
		&"value": value,
		&"capability_recipe_ids": [&"tile.recipe.classic_merge"],
		&"capability_state": {},
		&"pos": position,
	}
