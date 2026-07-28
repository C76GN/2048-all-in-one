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


func test_single_serialization_checksum_matches_gf_storage_codec_boundaries() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var codec: GFStorageCodec = GFStorageCodec.new()
	var cases: Array[Dictionary] = [
		{
			&"label": "classic_integer_state",
			&"payload": {
				&"schema_version": 8,
				&"board": {
					&"topology": {
						&"kind": &"rectangle",
						&"size": Vector2i(4, 4),
					},
					&"tiles": [
						{
							&"position": Vector2i(0, 0),
							&"value": 2,
							&"definition_id": &"tile.classic.numeric",
						},
						{
							&"position": Vector2i(3, 2),
							&"value": 2048,
							&"definition_id": &"tile.classic.numeric",
						},
					],
				},
				&"rng": {
					&"root_seed": 2048,
					&"branch_counters": {&"game_board_spawn": 17},
				},
				&"score": 4096,
				&"target_reached": true,
			},
		},
		{
			&"label": "integral_float",
			&"payload": {
				&"zero": 0.0,
				&"negative_zero": -0.0,
				&"positive": 2048.0,
				&"negative": -16.0,
				&"nested": [1.0, {&"value": 64.0}],
			},
		},
		{
			&"label": "non_integral_float",
			&"payload": {
				&"probability": 0.9,
				&"fraction": 0.125,
				&"negative": -13.5,
				&"repeating": 1.0 / 3.0,
				&"nested": [0.1, {&"value": 2048.25}],
			},
		},
		{
			&"label": "variant_fallback",
			&"payload": {
				&"position": Vector2(1.25, -2.5),
				&"offset": Vector2(-0.0, 2048.0),
				&"color": Color(0.1, 0.25, 0.5, 0.75),
				&"nested": [
					{
						&"position": Vector2(3.5, 4.0),
						&"color": Color(1.0, 0.0, 0.5, 1.0),
					},
				],
			},
		},
	]

	for case_data: Dictionary in cases:
		var label: String = GFVariantData.get_option_string(
			case_data,
			&"label"
		)
		var payload: Dictionary = GFVariantData.get_option_dictionary(
			case_data,
			&"payload"
		)
		var expected: String = codec.calculate_checksum(
			payload,
			GFStorageCodec.Format.JSON
		)
		var actual: String = GFVariantData.to_text(
			determinism.call(&"_checksum", payload)
		)
		assert_true(
			actual == expected,
			"%s 必须与 GFStorageCodec.calculate_checksum(JSON) 逐字节兼容。"
			% label
		)
		assert_true(
			actual.length() == 64 and actual == actual.to_lower(),
			"%s 必须保持 GF 的小写 SHA-256 文本契约。" % label
		)


func test_ruleset_fingerprint_includes_deterministic_rule_parameters() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var first_mode: GameModeConfig = _make_ruleset_fixture(0.9)
	var same_mode: GameModeConfig = _make_ruleset_fixture(0.9)
	var changed_mode: GameModeConfig = _make_ruleset_fixture(0.5)

	var first_fingerprint: String = determinism.calculate_ruleset_fingerprint(first_mode)
	assert_true(first_fingerprint.length() == 64, "规则集指纹应使用稳定的 64 位十六进制摘要。")
	assert_true(
		first_fingerprint == determinism.calculate_ruleset_fingerprint(same_mode),
		"相同规则内容不得因 Resource 实例 ID 不同产生不同指纹。"
	)
	assert_false(
		first_fingerprint == determinism.calculate_ruleset_fingerprint(changed_mode),
		"会改变生成结果的概率参数即使漏升 ruleset_version，也必须改变指纹。"
	)
	same_mode.mode_name = "只改变展示名称"
	same_mode.mode_description = "展示文案不属于确定性结算规则。"
	assert_true(
		first_fingerprint == determinism.calculate_ruleset_fingerprint(same_mode),
		"展示文案变化不应使确定性回放失效。"
	)


func test_checkpoint_compatibility_and_session_paths_preserve_exact_hashes() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var mode_config: GameModeConfig = _make_ruleset_fixture(0.9)
	var full_state: Dictionary = _make_full_state()
	var ruleset_fingerprint: String = determinism.calculate_ruleset_fingerprint(
		mode_config
	)

	var compatibility_checkpoint: ReplayCheckpoint = determinism.create_checkpoint(
		1,
		full_state,
		mode_config
	)
	var session_checkpoint: ReplayCheckpoint = (
		determinism.create_checkpoint_for_session(
			1,
			full_state,
			ruleset_fingerprint
		)
	)

	assert_not_null(compatibility_checkpoint)
	assert_not_null(session_checkpoint)
	if compatibility_checkpoint == null or session_checkpoint == null:
		return
	assert_true(
		compatibility_checkpoint.to_dict() == session_checkpoint.to_dict(),
		"冻结规则集热路径必须逐字段保持现有回放 checkpoint 哈希与元数据。"
	)


func test_checkpoint_normalizes_board_and_fingerprints_ruleset_once() -> void:
	var determinism: CountingDeterminismUtility = CountingDeterminismUtility.new()
	var checkpoint: ReplayCheckpoint = determinism.create_checkpoint(
		1,
		_make_full_state(),
		_make_ruleset_fixture(0.9)
	)

	assert_not_null(checkpoint)
	assert_true(
		determinism.ruleset_fingerprint_calls == 1,
		"兼容入口每个 checkpoint 只应递归计算一次规则集指纹。"
	)
	assert_true(
		determinism.board_normalization_calls == 1,
		"同一棋盘快照不得为 board/state checksum 重复规范化。"
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


func _make_ruleset_fixture(probability_of_2: float) -> GameModeConfig:
	var mode: GameModeConfig = GameModeConfig.new()
	mode.ruleset_id = &"gameplay.fingerprint_fixture"
	mode.ruleset_version = 1
	mode.target_tile_value = 2048
	var spawn_rule: ClassicSpawnRule = ClassicSpawnRule.new()
	spawn_rule.probability_of_2 = probability_of_2
	mode.spawn_rules = [spawn_rule]
	return mode


func _make_board_snapshot(tiles: Array[Dictionary]) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": BoardTopology.create_rectangle(Vector2i(2, 1)).to_dict(),
		&"tiles": tiles,
	}


func _make_full_state() -> Dictionary:
	return {
		&"board_snapshot": _make_board_snapshot([
			_make_tile_snapshot(Vector2i(0, 0), 2, 3000),
			_make_tile_snapshot(Vector2i(1, 0), 4, 3001),
		]),
		&"rng_full_state": {
			&"root_seed": 2048,
			&"branch_counters": {&"game_board_spawn": 2},
		},
		&"score": 4,
		&"move_count": 1,
		&"highest_tile": 4,
		&"ratio_resolutions": 0,
		&"target_tile_value": 2048,
		&"target_reached": false,
		&"extra_stats": {},
		&"rules_states": {},
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


# --- 内部类 ---

class CountingDeterminismUtility extends GameDeterminismUtility:
	var ruleset_fingerprint_calls: int = 0
	var board_normalization_calls: int = 0


	## 记录规则集指纹计算次数并委托真实实现。
	## @param mode_config: 要生成规则集指纹的模式配置。
	func calculate_ruleset_fingerprint(mode_config: GameModeConfig) -> String:
		ruleset_fingerprint_calls += 1
		return super.calculate_ruleset_fingerprint(mode_config)


	## 记录棋盘快照规范化次数并委托真实实现。
	## @param board_snapshot: 要规范化的严格棋盘快照。
	func normalize_board_snapshot(board_snapshot: Dictionary) -> Dictionary:
		board_normalization_calls += 1
		return super.normalize_board_snapshot(board_snapshot)
