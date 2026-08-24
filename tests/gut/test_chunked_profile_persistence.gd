## 验证分块 Profile staging 核心的 A/B bank、取消与完整性契约。
extends GutTest


# --- 测试用例 ---

func test_success_stages_only_inactive_bank_and_returns_invisible_manifest() -> void:
	var fake: FakeChunkProfileExecutor = FakeChunkProfileExecutor.new()
	var persistence: ChunkedProfilePersistence = ChunkedProfilePersistence.new(fake)
	var chunks: Array[PackedByteArray] = _make_chunks(["alpha", "beta"])
	var request: ChunkStageRequest = _make_request(
		ChunkManifest.BANK_B,
		chunks
	)
	assert_not_null(request)
	if request == null:
		return

	var operation: ChunkStageOperation = persistence.stage(request)
	var result: ChunkStageResult = await _await_operation(operation)
	assert_not_null(result)
	if result == null:
		return
	assert_true(result.is_successful(), "完整写入后必须返回 staged 候选。")
	assert_true(
		result.get_status() == ChunkStageResult.STATUS_STAGED,
		"成功路径只能返回尚未可见的 staged typed 终态。"
	)
	var manifest: ChunkManifest = result.get_manifest()
	assert_not_null(manifest)
	if manifest == null:
		return
	assert_true(manifest.get_bank() == ChunkManifest.BANK_A)
	assert_true(manifest.verify_chunk(0, chunks[0]))
	assert_true(manifest.verify_chunk(1, chunks[1]))
	var expected_calls: Array[StringName] = [
		&"accounts.primary.chunks.bookmarks.a.000000",
		&"accounts.primary.chunks.bookmarks.a.000001",
	]
	assert_true(
		fake.calls == expected_calls,
		"staging executor 只能收到 inactive-bank chunk Profiles。"
	)
	assert_false(
		fake.calls.has(&"accounts.primary.player_profile"),
		"主玩家 Profile 与 Manifest 提交必须由外部 owner 完成。"
	)
	var persisted_manifest: Dictionary = manifest.to_dict()
	assert_true(persisted_manifest.size() == 6)
	assert_false(persisted_manifest.has(&"chunk_profile_prefix"))
	assert_false(persisted_manifest.has(&"commit_id"))
	assert_true(fake.all_requests_were_non_null)


func test_chunk_n_failure_never_flips_manifest() -> void:
	var fake: FakeChunkProfileExecutor = FakeChunkProfileExecutor.new()
	fake.fail_call_index = 1
	var persistence: ChunkedProfilePersistence = ChunkedProfilePersistence.new(fake)
	var request: ChunkStageRequest = _make_request(
		ChunkManifest.BANK_A,
		_make_chunks(["first", "second", "third"])
	)
	assert_not_null(request)
	if request == null:
		return

	var result: ChunkStageResult = await _await_operation(
		persistence.stage(request)
	)
	assert_not_null(result)
	if result == null:
		return
	assert_true(
		result.get_status() == ChunkStageResult.STATUS_CHUNK_PROFILE_FAILED
	)
	assert_true(result.get_failed_chunk_index() == 1)
	assert_true(fake.calls.size() == 2, "已知失败后不得继续写入其他 chunk。")
	assert_false(persistence.is_fenced(), "已知 chunk 失败不应伪装 outcome_unknown。")


func test_chunk_outcome_unknown_fences_target_bank_and_followup_stage() -> void:
	var fake: FakeChunkProfileExecutor = FakeChunkProfileExecutor.new()
	fake.outcome_unknown_profile_id = &"accounts.primary.chunks.bookmarks.b.000000"
	var persistence: ChunkedProfilePersistence = ChunkedProfilePersistence.new(fake)
	var first_request: ChunkStageRequest = _make_request(
		ChunkManifest.BANK_A,
		_make_chunks(["payload"])
	)
	assert_not_null(first_request)
	if first_request == null:
		return

	var first_result: ChunkStageResult = await _await_operation(
		persistence.stage(first_request)
	)
	assert_not_null(first_result)
	if first_result == null:
		return
	assert_true(
		first_result.get_status() == ChunkStageResult.STATUS_OUTCOME_UNKNOWN
	)
	assert_true(persistence.is_fenced())
	var calls_before_retry: int = fake.calls.size()
	var retry_request: ChunkStageRequest = _make_request(
		ChunkManifest.BANK_A,
		_make_chunks(["new-payload"])
	)
	assert_not_null(retry_request)
	if retry_request == null:
		return
	var retry_operation: ChunkStageOperation = persistence.stage(retry_request)
	assert_true(retry_operation.is_completed())
	var retry_result: ChunkStageResult = retry_operation.get_result()
	assert_not_null(retry_result)
	if retry_result == null:
		return
	assert_true(retry_result.get_status() == ChunkStageResult.STATUS_BUSY)
	assert_true(fake.calls.size() == calls_before_retry)
	var fence: Dictionary = persistence.get_fence_snapshot()
	var fence_section_value: Variant = fence.get(&"section_id")
	var fence_bank_value: Variant = fence.get(&"target_bank")
	var fence_index_value: Variant = fence.get(&"chunk_index")
	assert_true(fence_section_value is StringName)
	assert_true(fence_bank_value is StringName)
	assert_true(fence_index_value is int)
	if (
		not fence_section_value is StringName
		or not fence_bank_value is StringName
		or not fence_index_value is int
	):
		return
	var fence_section: StringName = fence_section_value
	var fence_bank: StringName = fence_bank_value
	var fence_index: int = fence_index_value
	assert_true(fence_section == &"bookmarks")
	assert_true(fence_bank == ChunkManifest.BANK_B)
	assert_true(fence_index == 0)


func test_cancel_waits_for_accepted_chunk_then_stops_further_staging() -> void:
	var fake: FakeChunkProfileExecutor = FakeChunkProfileExecutor.new()
	fake.defer_call_index = 0
	var persistence: ChunkedProfilePersistence = ChunkedProfilePersistence.new(fake)
	var request: ChunkStageRequest = _make_request(
		ChunkManifest.BANK_B,
		_make_chunks(["first", "second"])
	)
	assert_not_null(request)
	if request == null:
		return

	var operation: ChunkStageOperation = persistence.stage(request)
	await get_tree().process_frame
	assert_true(fake.calls.size() == 1)
	assert_true(operation.request_cancel(&"test_cancelled"))
	assert_false(operation.is_completed(), "已接纳的 GF 操作必须先结算。")
	assert_true(fake.complete_deferred_success())
	var result: ChunkStageResult = await _await_operation(operation)
	assert_not_null(result)
	if result == null:
		return
	assert_true(result.get_status() == ChunkStageResult.STATUS_CANCELLED)
	assert_true(result.get_error() == "test_cancelled")
	assert_true(fake.calls.size() == 1, "取消后不得写下一 chunk。")


func test_manifest_rejects_bad_digest_and_out_of_order_descriptors() -> void:
	var chunks: Array[PackedByteArray] = _make_chunks(["first", "second"])
	var manifest: ChunkManifest = ChunkManifest.create(
		&"bookmarks",
		3,
		ChunkManifest.BANK_A,
		chunks
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	assert_false(
		manifest.verify_chunk(0, "tampered".to_utf8_buffer()),
		"摘要不匹配的 chunk 必须在 materialize 前拒绝。"
	)

	var bad_digest_payload: Dictionary = manifest.to_dict()
	var bad_digest_chunks_value: Variant = bad_digest_payload.get(&"chunks")
	assert_true(bad_digest_chunks_value is Array)
	if not bad_digest_chunks_value is Array:
		return
	var bad_digest_chunks: Array = bad_digest_chunks_value
	var first_descriptor_value: Variant = bad_digest_chunks[0]
	assert_true(first_descriptor_value is Dictionary)
	if not first_descriptor_value is Dictionary:
		return
	var first_descriptor: Dictionary = first_descriptor_value
	first_descriptor[&"sha256"] = "not-a-sha256"
	assert_null(ChunkManifest.from_dict(bad_digest_payload))

	var out_of_order_payload: Dictionary = manifest.to_dict()
	var ordered_chunks_value: Variant = out_of_order_payload.get(&"chunks")
	assert_true(ordered_chunks_value is Array)
	if not ordered_chunks_value is Array:
		return
	var ordered_chunks: Array = ordered_chunks_value
	var first: Variant = ordered_chunks[0]
	ordered_chunks[0] = ordered_chunks[1]
	ordered_chunks[1] = first
	assert_null(ChunkManifest.from_dict(out_of_order_payload))


func test_manifest_rejects_unknown_schema_fields_and_chunk_budget_overflow() -> void:
	var valid_chunks: Array[PackedByteArray] = _make_chunks(["bounded"])
	var manifest: ChunkManifest = ChunkManifest.create(
		&"bookmarks",
		3,
		ChunkManifest.BANK_A,
		valid_chunks
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var unknown_field_payload: Dictionary = manifest.to_dict()
	unknown_field_payload[&"chunk_profile_prefix"] = "untrusted.persisted.prefix"
	assert_null(
		ChunkManifest.from_dict(unknown_field_payload),
		"严格 schema 必须拒绝额外字段。"
	)

	var oversized: PackedByteArray = PackedByteArray()
	assert_true(oversized.resize(ChunkManifest.MAX_CHUNK_BYTES + 1) == OK)
	var oversized_chunks: Array[PackedByteArray] = [oversized]
	assert_null(
		ChunkManifest.create(
			&"bookmarks",
			3,
			ChunkManifest.BANK_B,
			oversized_chunks
		),
		"单个 GF Profile callback 预算必须在写入前拒绝。"
	)


func test_materialization_lease_allows_exactly_one_claim() -> void:
	var chunks: Array[PackedByteArray] = _make_chunks(["materialized"])
	var manifest: ChunkManifest = ChunkManifest.create(
		&"bookmarks",
		3,
		ChunkManifest.BANK_A,
		chunks
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var main_profile_id: StringName = &"accounts.primary.player_profile"
	var canonical_file_name: String = "profiles/primary.save"
	var lease: ChunkMaterializationLease = (
		ChunkMaterializationLease.take_ownership(
			{&"value": 2048},
			manifest,
			main_profile_id,
			canonical_file_name
		)
	)
	assert_not_null(lease)
	if lease == null:
		return
	assert_true(lease.is_available())
	var mismatched_claim: Variant = lease.claim_for_manifest(
		manifest,
		main_profile_id,
		"profiles/other.save",
		&"bookmarks",
		3
	)
	assert_true(typeof(mismatched_claim) == TYPE_NIL)
	assert_true(lease.is_available(), "权限错配不得消费 lease。")
	var claimed_value: Variant = lease.claim_for_manifest(
		manifest,
		main_profile_id,
		canonical_file_name,
		&"bookmarks",
		3
	)
	assert_true(claimed_value is Dictionary)
	if not claimed_value is Dictionary:
		return
	var claimed: Dictionary = claimed_value
	var claimed_number_value: Variant = claimed.get(&"value")
	assert_true(claimed_number_value is int)
	if claimed_number_value is int:
		var claimed_number: int = claimed_number_value
		assert_true(claimed_number == 2048)
	assert_true(lease.is_claimed())
	assert_false(lease.is_available())
	var repeated_claim: Variant = lease.claim_for_manifest(
		manifest,
		main_profile_id,
		canonical_file_name,
		&"bookmarks",
		3
	)
	assert_true(
		typeof(repeated_claim) == TYPE_NIL,
		"重复 claim 不得重新暴露载荷。"
	)


# --- 私有/辅助方法 ---

func _make_request(
	active_bank: StringName,
	chunks: Array[PackedByteArray]
) -> ChunkStageRequest:
	return ChunkStageRequest.create(
		"accounts.primary.chunks.bookmarks",
		&"bookmarks",
		3,
		active_bank,
		chunks
	)


func _make_chunks(values: Array[String]) -> Array[PackedByteArray]:
	var chunks: Array[PackedByteArray] = []
	for value: String in values:
		chunks.append(value.to_utf8_buffer())
	return chunks


func _await_operation(
	operation: ChunkStageOperation,
	maximum_frames: int = 32
) -> ChunkStageResult:
	for _frame_index: int in range(maximum_frames):
		if operation.is_completed():
			return operation.get_result()
		await get_tree().process_frame
	assert_true(false, "分块 staging 未在确定性帧预算内完成。")
	return null


# --- 内部类 ---

class FakeChunkProfileExecutor extends ChunkProfileExecutor:
	var calls: Array[StringName] = []
	var all_requests_were_non_null: bool = true
	var fail_call_index: int = -1
	var defer_call_index: int = -1
	var outcome_unknown_profile_id: StringName = &""
	var _deferred_operation: GFSaveProfileOperation = null
	var _deferred_profile_id: StringName = &""

	## 记录逻辑 Profile 顺序并返回可控的 GF public operation。
	##
	## @param profile_id: 本次保存的逻辑 Profile ID。
	## @param request: 核心构造的一次性 GF Profile request。
	## @return 同步或受测试控制的 GF Profile operation。
	func save_profile(
		profile_id: StringName,
		request: GFSaveProfileRequest
	) -> GFSaveProfileOperation:
		all_requests_were_non_null = all_requests_were_non_null and request != null
		calls.append(profile_id)
		var call_index: int = calls.size() - 1
		var operation: GFSaveProfileOperation = _make_pending_operation(profile_id)
		if call_index == defer_call_index:
			_deferred_operation = operation
			_deferred_profile_id = profile_id
			return operation
		if profile_id == outcome_unknown_profile_id:
			_complete_operation(
				operation,
				profile_id,
				GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
			)
		elif call_index == fail_call_index:
			_complete_operation(
				operation,
				profile_id,
				GFSaveProfileResult.STATUS_STORAGE_FAILED
			)
		else:
			_complete_operation(
				operation,
				profile_id,
				GFSaveProfileResult.STATUS_SAVED
			)
		return operation

	func complete_deferred_success() -> bool:
		if _deferred_operation == null:
			return false
		var operation: GFSaveProfileOperation = _deferred_operation
		var profile_id: StringName = _deferred_profile_id
		_deferred_operation = null
		_deferred_profile_id = &""
		_complete_operation(
			operation,
			profile_id,
			GFSaveProfileResult.STATUS_SAVED
		)
		return true

	func _make_pending_operation(
		profile_id: StringName
	) -> GFSaveProfileOperation:
		var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
		var configured: bool = operation.configure_save_ownership_for_framework(
			profile_id,
			1,
			0,
			{}
		)
		if configured:
			var _started: bool = operation.start_for_framework()
		return operation

	func _complete_operation(
		operation: GFSaveProfileOperation,
		profile_id: StringName,
		status: StringName
	) -> void:
		var successful: bool = status == GFSaveProfileResult.STATUS_SAVED
		var error_code: Error = OK if successful else ERR_CANT_CREATE
		if status == GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN:
			error_code = ERR_TIMEOUT
		var result: GFSaveProfileResult = GFSaveProfileResult.new()
		result.configure_for_framework(
			successful,
			status,
			GFSaveProfileOperation.OPERATION_SAVE,
			profile_id,
			1,
			1 if successful else 0,
			1,
			0,
			1,
			false,
			false,
			&"",
			&"",
			error_code,
			"" if successful else "synthetic profile failure"
		)
		var completed: bool = operation.complete_for_framework(result)
		if completed:
			var _emitted: bool = operation.emit_completed_for_framework()
