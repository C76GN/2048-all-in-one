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


func test_replay_catalog_save_snapshot_yields_between_bounded_slices() -> void:
	var provider: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var replay: ReplayData = _make_replay(1_700_000_000_003, 16)
	assert_true(
		provider.replace_section_data({&"items": [replay.to_dict()]}) == OK,
		"测试回放应进入目录 Provider。"
	)
	var operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "bounded_test"})
	)

	assert_not_null(operation, "Replay Provider 应创建协作式 Snapshot Operation。")
	assert_true(
		operation != null and operation.is_pending(),
		"回放目录不得在 begin 调用栈同步构建完整 Snapshot。"
	)
	if operation == null:
		return

	var first_slice_units: int = operation.advance_for_framework(1)
	assert_true(first_slice_units == 1, "单次推进必须遵守一个 work unit 预算。")
	assert_true(
		operation.is_pending(),
		"含回放步骤的目录必须在多个有界 slice 中构建。"
	)
	for _slice: int in range(32):
		if operation.is_completed():
			break
		var _consumed_units: int = operation.advance_for_framework(1)

	assert_true(operation.is_successful(), "有界 Replay Snapshot 应进入成功终态。")
	var snapshot: GFSaveSectionSnapshot = operation.take_snapshot_for_framework()
	assert_not_null(snapshot, "成功操作应交付一次性 Snapshot。")
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var payload_value: Variant = record.get("payload")
	assert_true(payload_value is Dictionary, "Replay Snapshot payload 应为严格字典。")
	if payload_value is Dictionary:
		var payload: Dictionary = payload_value
		assert_true(
			payload == provider.get_section_data(),
			"分片快照必须与当前 Replay section 数据一致。"
		)


func test_replay_system_reuses_provider_runtime_cache_without_exposing_mutable_data() -> void:
	var save_graph: ReplaySaveGraphStub = ReplaySaveGraphStub.new()
	var stored_replay: ReplayData = _make_replay(1_700_000_000_010, 64)
	assert_true(
		save_graph.provider.replace_section_data({
			&"items": [stored_replay.to_dict()],
		}) == OK
	)
	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._save_graph = save_graph

	var first_read: Array[ReplayData] = replay_system.load_replays()
	assert_true(first_read.size() == 1)
	if first_read.is_empty():
		return
	first_read[0].final_score = -1
	first_read[0].actions[0] = Vector2i.LEFT
	var first_eligibility_value: Variant = first_read[0].session_metadata.get(
		&"eligibility"
	)
	if first_eligibility_value is Dictionary:
		var first_eligibility: Dictionary = first_eligibility_value
		first_eligibility[&"eligible"] = false
	var first_topology_value: Variant = first_read[0].final_board_snapshot.get(
		&"topology"
	)
	if first_topology_value is Dictionary:
		var first_topology: Dictionary = first_topology_value
		var first_active_cells_value: Variant = first_topology.get(&"active_cells")
		if first_active_cells_value is Array:
			var first_active_cells: Array = first_active_cells_value
			first_active_cells[0] = Vector2i(99, 99)
	first_read[0].checkpoints[0].score = -1
	var second_read: Array[ReplayData] = replay_system.load_replays()
	assert_true(
		second_read.size() == 1 and second_read[0].final_score == 64,
		"命中 runtime cache 时仍必须向调用方交付隔离 ReplayData。"
	)
	if not second_read.is_empty():
		assert_true(second_read[0].actions[0] == Vector2i.RIGHT)
		var second_eligibility: Dictionary = GFVariantData.get_option_dictionary(
			second_read[0].session_metadata,
			&"eligibility"
		)
		assert_true(GFVariantData.get_option_bool(second_eligibility, &"eligible"))
		var second_topology: Dictionary = GFVariantData.get_option_dictionary(
			second_read[0].final_board_snapshot,
			&"topology"
		)
		var second_active_cells: Array = GFVariantData.get_option_array(
			second_topology,
			&"active_cells"
		)
		assert_false(second_active_cells.has(Vector2i(99, 99)))
		assert_true(second_read[0].checkpoints[0].score == 64)
	var cache_snapshot: Dictionary = replay_system.get_cache_debug_snapshot()
	assert_true(GFVariantData.get_option_int(cache_snapshot, &"misses") == 1)
	assert_true(GFVariantData.get_option_int(cache_snapshot, &"hits") == 1)

	var next_replay: ReplayData = _make_replay(1_700_000_000_011, 128)
	var operation: GameSaveSectionOperation = replay_system.request_save_replay(
		next_replay
	)
	assert_true(
		operation != null
		and operation.get_result() != null
		and operation.get_result().is_successful()
	)
	assert_false(
		GFVariantData.get_option_bool(
			replay_system.get_cache_debug_snapshot(),
			&"valid"
		),
		"同步应用回放候选后必须立即失效旧 Profile cache。"
	)
	var refreshed: Array[ReplayData] = replay_system.load_replays()
	assert_true(refreshed.size() == 2)


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

	## 从回放测试 Provider 读取指定 section 的隔离运行时缓存快照。
	## @param section_id: 要读取运行时缓存的稳定 section 标识。
	func get_section_runtime_cache_snapshot(section_id: StringName) -> Dictionary:
		if section_id != GameSaveGraphUtility.REPLAYS_SECTION_ID:
			return {}
		return provider.get_runtime_section_cache_snapshot()

	func is_profile_loaded() -> bool:
		return true

	func get_active_profile_id() -> StringName:
		return &"test.replay_limits"

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
