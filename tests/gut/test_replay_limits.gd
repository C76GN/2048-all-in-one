## 验证回放不可信载荷上限与最新优先的确定性目录淘汰。
extends GutTest


# --- 测试用例 ---

func test_replay_rejects_oversized_arrays_before_resource_construction() -> void:
	var replay_data: Dictionary = _make_replay(1_700_000_000_001, 4).to_dict()
	var oversized_actions: Array = []
	var _actions_resize_error: int = oversized_actions.resize(
		ReplayData.MAX_STEP_COUNT + 1
	)
	oversized_actions.fill(Vector2i.RIGHT)
	replay_data[&"actions"] = oversized_actions

	assert_null(
		ReplayData.from_dict(replay_data),
		"超过业务上限的 actions 必须在构造 ReplayData 前拒绝。"
	)

	replay_data = _make_replay(1_700_000_000_002, 4).to_dict()
	var oversized_checkpoints: Array = []
	var _checkpoints_resize_error: int = oversized_checkpoints.resize(
		ReplayData.MAX_STEP_COUNT + 1
	)
	oversized_checkpoints.fill(_make_checkpoint(1, 4).to_dict())
	replay_data[&"checkpoints"] = oversized_checkpoints
	assert_null(
		ReplayData.from_dict(replay_data),
		"超过业务上限的 checkpoints 必须在逐项反序列化前拒绝。"
	)


func test_replay_catalog_rejects_oversized_persisted_array_atomically() -> void:
	var provider: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var oversized_items: Array = []
	var _items_resize_error: int = oversized_items.resize(
		ReplayCatalogSaveData.MAX_REPLAY_COUNT + 1
	)
	oversized_items.fill({})

	assert_true(
		provider.replace_section_data({"items": oversized_items}) == ERR_INVALID_DATA,
		"超过目录上限的不可信 section 必须在逐项恢复前整体拒绝。"
	)
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			"items"
		).is_empty(),
		"拒绝超限 section 后必须保留原目录。"
	)


func test_saving_replays_deterministically_retains_newest_uuid_v7_items() -> void:
	var save_graph: ReplaySaveGraphStub = ReplaySaveGraphStub.new()
	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._save_graph = save_graph
	var replay_ids: PackedStringArray = PackedStringArray()

	for index: int in range(ReplayCatalogSaveData.MAX_REPLAY_COUNT + 3):
		var replay: ReplayData = _make_replay(
			1_700_000_000_000 + index,
			index + 4
		)
		var _replay_id_appended: bool = replay_ids.append(replay.replay_id)
		var operation: GameSaveSectionOperation = (
			replay_system.request_save_replay(replay)
		)
		var result: GameSaveSectionResult = (
			operation.get_result()
			if operation != null
			else null
		)
		assert_true(
			result != null and result.is_successful(),
			"目录到达上限后仍应保存新回放并淘汰最旧项。"
		)

	var retained: Array[ReplayData] = replay_system.load_replays()
	assert_true(
		retained.size() == ReplayCatalogSaveData.MAX_REPLAY_COUNT,
		"回放目录必须稳定保持业务数量上限。"
	)
	if retained.is_empty():
		return
	var newest_id_matches: bool = (
		retained[0].replay_id == replay_ids[replay_ids.size() - 1]
	)
	assert_true(
		newest_id_matches,
		"目录首项必须是 UUID v7 最新回放。"
	)
	var oldest_id_matches: bool = retained[retained.size() - 1].replay_id == replay_ids[3]
	assert_true(
		oldest_id_matches,
		"新增三项后必须确定性淘汰最旧三项。"
	)
	for replay_id: String in replay_ids.slice(0, 3):
		assert_false(
			_has_replay_id(retained, replay_id),
			"被淘汰的最旧回放不得残留在目录中。"
		)


# --- 私有/辅助方法 ---

func _make_replay(timestamp_msec: int, final_score: int) -> ReplayData:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(2, 2))
	var replay: ReplayData = ReplayData.new()
	replay.replay_id = GFUuid.generate_v7(timestamp_msec)
	replay.timestamp = floori(float(timestamp_msec) / 1000.0)
	replay.mode_config_path = (
		"res://features/gameplay/resources/modes/classic_mode_config.tres"
	)
	replay.ruleset_id = &"gameplay.classic"
	replay.ruleset_version = 1
	replay.ruleset_fingerprint = "a".repeat(64)
	replay.initial_seed = 2048
	replay.session_metadata = GameSessionMetadata.make_default_dict()
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	replay.checkpoints = [_make_checkpoint(1, final_score)]
	replay.final_board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	return replay


func _make_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "b".repeat(64)
	checkpoint.board_checksum = "c".repeat(64)
	checkpoint.rng_checksum = "d".repeat(64)
	checkpoint.score = score
	return checkpoint


func _has_replay_id(replays: Array[ReplayData], replay_id: String) -> bool:
	for replay: ReplayData in replays:
		if replay.replay_id == replay_id:
			return true
	return false


# --- 内部类 ---

class ReplaySaveGraphStub extends GameSaveGraphUtility:
	var provider: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var transaction_serial: int = 0

	## 从回放测试 Provider 读取指定 section。
	## @param section_id: 要读取的稳定 section 标识。
	func get_section_data(section_id: StringName) -> Dictionary:
		if section_id != GameSaveGraphUtility.REPLAYS_SECTION_ID:
			return {}
		return provider.get_section_data()

	## 以立即完成的 typed operation 替换测试回放 section。
	## @param section_id: 要替换的稳定 section 标识。
	## @param data: 当前版本的完整 section 业务数据。
	## @param _metadata: 本测试不消费的持久化诊断元数据。
	func request_replace_section_data(
		section_id: StringName,
		data: Dictionary,
		_metadata: Dictionary = {}
	) -> GameSaveSectionOperation:
		transaction_serial += 1
		var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
		var _operation_configured: bool = operation.configure_for_utility(
			transaction_serial,
			&"test.replay_limits",
			PackedStringArray([String(section_id)])
		)
		var error_code: Error = (
			provider.replace_section_data(data)
			if section_id == GameSaveGraphUtility.REPLAYS_SECTION_ID
			else ERR_INVALID_PARAMETER
		)
		var result: GameSaveSectionResult = GameSaveSectionResult.new()
		var _result_configured: bool = result.configure_for_utility(
			operation.get_transaction_id(),
			operation.get_profile_id(),
			operation.get_section_ids(),
			(
				GameSaveSectionResult.STATUS_PERSISTED
				if error_code == OK
				else GameSaveSectionResult.STATUS_INVALID_REQUEST
			),
			error_code,
			error_code == OK,
			false
		)
		var _completed: bool = operation.complete_for_utility(result)
		return operation
