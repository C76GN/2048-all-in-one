## 验证棋盘摘要、回合字幕与平台辅助边界共享同一规范语义。
extends GutTest


# --- 测试用例 ---

func test_sparse_board_summary_preserves_inactive_empty_and_tile_cells() -> void:
	var snapshot: Dictionary = _build_sparse_snapshot()
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var summary: GameAccessibilitySummary = utility.build_board_summary(snapshot)

	assert_not_null(summary, "严格稀疏棋盘必须生成无障碍摘要。")
	if not is_instance_valid(summary):
		return
	assert_true(summary.is_valid_summary(), "棋盘摘要必须满足共享严格契约。")
	assert_true(summary.kind == GameAccessibilitySummary.KIND_BOARD)
	assert_true(summary.board_text.contains("2"), "完整棋盘文本必须包含方块值。")
	assert_true(summary.board_text.contains("空"), "完整棋盘文本必须区分活跃空格。")
	assert_true(
		summary.board_text.contains("不可用"),
		"完整棋盘文本必须区分拓扑中的非活跃格。"
	)
	assert_true(
		GFVariantData.get_option_int(
			summary.canonical_payload,
			&"active_cell_count",
			0
		) == 3
	)
	assert_true(
		GFVariantData.get_option_int(
			summary.canonical_payload,
			&"occupied_tile_count",
			0
		) == 2
	)
	assert_true(
		summary.board_text.contains("目标"),
		"完整棋盘文本必须明确当前目标语义。"
	)


func test_session_context_exposes_goal_actions_and_end_reason() -> void:
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var summary: GameAccessibilitySummary = utility.build_board_summary(
		_build_sparse_snapshot(),
		{
			&"phase": &"game_over",
			&"target_value": 4,
			&"target_reached": true,
			&"end_reason": &"no_moves",
			&"available_actions": [&"restart", &"return"],
		}
	)
	assert_not_null(summary)
	if not is_instance_valid(summary):
		return
	var session: Dictionary = GFVariantData.get_option_dictionary(
		summary.canonical_payload,
		&"session"
	)
	assert_true(
		GFVariantData.get_option_string_name(session, &"phase")
		== &"game_over"
	)
	assert_true(GFVariantData.get_option_bool(session, &"target_reached"))
	assert_true(
		GFVariantData.get_option_array(
			session,
			&"available_actions"
		).size() == 2
	)
	assert_true(summary.board_text.contains("目标 4 已达成"))
	assert_true(summary.board_text.contains("重新开始"))
	assert_true(summary.board_text.contains("对局结束"))


func test_runtime_tile_ids_do_not_change_accessibility_board_identity() -> void:
	var first: Dictionary = _build_sparse_snapshot()
	var second: Dictionary = _build_sparse_snapshot()
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var first_summary: GameAccessibilitySummary = utility.build_board_summary(first)
	var second_summary: GameAccessibilitySummary = utility.build_board_summary(second)
	assert_not_null(first_summary)
	assert_not_null(second_summary)
	if not is_instance_valid(first_summary) or not is_instance_valid(second_summary):
		return
	assert_true(
		first_summary.board_checksum == second_summary.board_checksum,
		"辅助技术使用的棋盘身份必须排除运行时 UUID。"
	)
	assert_true(
		first_summary.canonical_payload == second_summary.canonical_payload,
		"同一语义棋盘必须生成逐字段相同的规范摘要。"
	)


func test_turn_subtitle_and_announcement_share_one_canonical_result() -> void:
	var snapshot: Dictionary = _build_sparse_snapshot()
	var turn_result: TurnResult = _build_turn_result()
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var summary: GameAccessibilitySummary = utility.build_turn_summary(
		turn_result,
		snapshot
	)

	assert_not_null(summary, "有效回合必须生成共享字幕结果。")
	if not is_instance_valid(summary):
		return
	assert_true(summary.kind == GameAccessibilitySummary.KIND_TURN)
	assert_true(summary.subtitle_text.contains("左"), "字幕必须包含移动方向。")
	assert_true(summary.subtitle_text.contains("合并 1 次"), "字幕必须包含合并次数。")
	assert_true(summary.subtitle_text.contains("+4"), "字幕必须包含得分变化。")
	assert_true(
		summary.announcement_text.begins_with(summary.subtitle_text),
		"辅助技术播报必须直接复用字幕文本，不得独立反推。"
	)
	var turn_payload: Dictionary = GFVariantData.get_option_dictionary(
		summary.canonical_payload,
		&"turn"
	)
	assert_true(GFVariantData.get_option_int(turn_payload, &"merge_count", 0) == 1)
	assert_true(GFVariantData.get_option_int(turn_payload, &"score_delta", 0) == 4)


func test_modal_turn_announcements_include_their_available_actions() -> void:
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var target_summary: GameAccessibilitySummary = utility.build_turn_summary(
		_build_turn_result(),
		_build_sparse_snapshot(),
		{
			&"phase": &"target_reached",
			&"target_value": 4,
			&"target_reached": true,
			&"available_actions": [&"continue", &"restart", &"return"],
		}
	)
	var game_over_summary: GameAccessibilitySummary = utility.build_turn_summary(
		_build_turn_result(),
		_build_sparse_snapshot(),
		{
			&"phase": &"game_over",
			&"target_value": 4,
			&"target_reached": true,
			&"end_reason": &"no_moves",
			&"available_actions": [&"restart", &"settings", &"return"],
		}
	)

	assert_not_null(target_summary)
	assert_not_null(game_over_summary)
	if not is_instance_valid(target_summary) or not is_instance_valid(
		game_over_summary
	):
		return
	assert_true(
		target_summary.announcement_text.contains("继续挑战"),
		"目标达成模态播报必须包含当前可执行的继续动作。"
	)
	assert_true(
		target_summary.announcement_text.contains("重新开始"),
		"目标达成模态播报必须包含重新开始动作。"
	)
	assert_true(
		game_over_summary.announcement_text.contains("设置"),
		"游戏结束播报必须包含结算弹窗实际提供的设置动作。"
	)
	assert_true(
		game_over_summary.announcement_text.contains("对局结束"),
		"游戏结束播报必须同时保留权威结束原因。"
	)


func test_publish_sequence_is_monotonic_and_callers_receive_copies() -> void:
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var first: GameAccessibilitySummary = utility.publish_board_summary(
		_build_sparse_snapshot()
	)
	var second: GameAccessibilitySummary = utility.publish_turn_summary(
		_build_turn_result(),
		_build_sparse_snapshot()
	)
	assert_not_null(first)
	assert_not_null(second)
	if not is_instance_valid(first) or not is_instance_valid(second):
		return
	assert_true(first.sequence == 1)
	assert_true(second.sequence == 2)

	var latest: GameAccessibilitySummary = utility.get_latest_summary()
	assert_not_same(latest, second, "调用方只能拿到摘要副本。")
	latest.canonical_payload.clear()
	var next_read: GameAccessibilitySummary = utility.get_latest_summary()
	assert_false(
		next_read.canonical_payload.is_empty(),
		"调用方修改副本不得污染字幕与平台适配共享状态。"
	)


func test_invalid_or_ineffective_inputs_publish_nothing() -> void:
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	assert_null(utility.publish_board_summary({}), "无效棋盘不得进入辅助技术边界。")
	assert_null(
		utility.publish_turn_summary(TurnResult.new(), _build_sparse_snapshot()),
		"无效移动不得生成误导字幕。"
	)
	assert_null(utility.get_latest_summary(), "失败构建不得覆盖最后有效摘要。")


func test_copy_board_text_uses_platform_boundary_and_reports_failure() -> void:
	var utility: GameAccessibilitySummaryUtility = (
		GameAccessibilitySummaryUtility.new()
	)
	var platform: TestGamePlatformUtilityStub = TestGamePlatformUtilityStub.new()
	utility._platform = platform
	var summary: GameAccessibilitySummary = utility.publish_board_summary(
		_build_sparse_snapshot()
	)
	assert_not_null(summary)
	assert_true(utility.copy_latest_board_text(), "复制必须由平台边界确认成功。")
	assert_true(
		platform.clipboard_text == summary.board_text,
		"平台收到的文本必须与 canonical 棋盘说明完全同源。"
	)

	platform.clipboard_write_succeeds = false
	assert_false(
		utility.copy_latest_board_text(),
		"平台拒绝写入时 UI 必须收到明确失败，不能误报已复制。"
	)


# --- 私有/辅助方法 ---

func _build_sparse_snapshot() -> Dictionary:
	var topology: BoardTopology = BoardTopology.create_custom(
		[
			Vector2i(0, 0),
			Vector2i(2, 0),
			Vector2i(0, 1),
		],
		&"board.test.accessibility"
	)
	var first_tile: TileState = _build_tile(2)
	var second_tile: TileState = _build_tile(4)
	var first_data: Dictionary = first_tile.to_dict()
	first_data[&"pos"] = Vector2i(0, 0)
	var second_data: Dictionary = second_tile.to_dict()
	second_data[&"pos"] = Vector2i(0, 1)
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [first_data, second_data],
	}


func _build_turn_result() -> TurnResult:
	var consumed: TileState = _build_tile(2)
	var survivor: TileState = _build_tile(4)
	var interaction: TileInteractionResult = TileInteractionResult.new()
	interaction.survivor = survivor
	interaction.consumed = consumed
	interaction.interaction_rule_id = &"rule.test.merge"
	interaction.score_delta = 4

	var merge: TileMergeResult = TileMergeResult.new()
	merge.interaction = interaction
	merge.consumed_from_cell = Vector2i(1, 0)
	merge.survivor_from_cell = Vector2i(0, 0)
	merge.to_cell = Vector2i(0, 0)

	var movement: TileMovementResult = TileMovementResult.new(
		_build_tile(8),
		Vector2i(2, 0),
		Vector2i(1, 0)
	)
	var result: TurnResult = TurnResult.new()
	result.direction = Vector2i.LEFT
	result.movements.append(movement)
	result.add_merge(merge)
	return result


func _build_tile(value: int) -> TileState:
	var tile: TileState = TileState.new(value, &"tile.test.accessibility")
	tile.capability_recipe_ids = [&"recipe.test.accessibility"]
	return tile
