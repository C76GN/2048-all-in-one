## 验证回合业务结果只通过强类型契约聚合和传播。
extends GutTest


# --- 测试用例 ---

func test_turn_result_aggregates_merge_semantics_and_reverse_targets() -> void:
	var survivor: TileState = TileState.new()
	survivor.value = 8
	var consumed: TileState = TileState.new()
	consumed.value = 4
	var interaction: TileInteractionResult = TileInteractionResult.new()
	interaction.survivor = survivor
	interaction.consumed = consumed
	interaction.interaction_rule_id = &"classic_merge"
	interaction.feedback_cue_id = &"merge"
	interaction.score_delta = 8
	interaction.ratio_resolution_count = 1

	var merge: TileMergeResult = TileMergeResult.new()
	merge.interaction = interaction
	merge.survivor_from_cell = Vector2i(1, 0)
	merge.consumed_from_cell = Vector2i(2, 0)
	merge.to_cell = Vector2i.ZERO
	var result: TurnResult = TurnResult.new()
	result.direction = Vector2i.LEFT
	result.add_merge(merge)

	assert_true(result.is_effective(), "强类型合并应使回合结果生效。")
	assert_true(result.score_delta == 8, "TurnResult 应聚合规则提供的分数。")
	assert_true(result.ratio_resolution_count == 1, "TurnResult 应聚合规则语义计数。")
	assert_true(result.max_merge_value == 8, "TurnResult 应记录最高合并结果。")
	assert_true(result.merges.size() == 1, "TurnResult 应保留原始强类型合并结果。")
	var reverse_targets: Dictionary = result.get_reverse_target_map()
	assert_true(_get_cell(reverse_targets, "1,0") == Vector2i.ZERO, "幸存方块应映射回合并目标。")
	assert_true(_get_cell(reverse_targets, "2,0") == Vector2i.ZERO, "被消费方块应映射回合并目标。")


func test_turn_result_rejects_untyped_or_invalid_children() -> void:
	var result: TurnResult = TurnResult.new()
	result.direction = Vector2i.RIGHT
	result.add_merge(TileMergeResult.new())
	result.add_spawn(TileSpawnResult.new())
	result.add_transform(TileTransformResult.new())

	assert_false(result.is_effective(), "方向本身不能伪造有效回合。")
	assert_true(result.merges.is_empty(), "无效合并不得进入结果集合。")
	assert_true(result.spawns.is_empty(), "无效生成不得进入结果集合。")
	assert_true(result.transforms.is_empty(), "无效变换不得进入结果集合。")


# --- 私有/辅助方法 ---

func _get_cell(source: Dictionary, key: String) -> Vector2i:
	var value: Variant = source.get(key, Vector2i.ZERO)
	return value if value is Vector2i else Vector2i.ZERO
