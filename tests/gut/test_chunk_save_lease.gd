## 验证分块 save lease 的所有权边界、identity 与可见性终态。
extends GutTest


# --- 常量 ---

const LEASE_ID: StringName = &"save-lease-41"
const MAIN_PROFILE_ID: StringName = &"accounts.primary.player"
const MAIN_PROFILE_FILE: String = "profiles/primary.save"
const SECTION_ID: StringName = &"bookmarks"
const SECTION_SCHEMA_VERSION: int = 3
const PRODUCER_REVISION: int = 41
const CHUNK_PROFILE_PREFIX: String = "accounts.primary.chunks.bookmarks"
const MAIN_GENERATION: int = 7


# --- 测试用例 ---

func test_create_and_offer_are_constant_time_ownership_boundaries() -> void:
	var lease: ChunkSaveLease = _make_lease()
	assert_not_null(lease)
	if lease == null:
		return
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_WAITING_FOR_PROVIDER)

	var oversized_payload: PackedByteArray = PackedByteArray()
	assert_true(
		oversized_payload.resize(ChunkManifest.MAX_CHUNK_BYTES + 1) == OK
	)
	var chunks: Array[PackedByteArray] = [oversized_payload]
	assert_true(
		lease.offer_chunks_taking_ownership(
			chunks,
			PRODUCER_REVISION,
			SECTION_ID,
			SECTION_SCHEMA_VERSION
		),
		"offer 只移交数组根，不应在 Provider callback 遍历 payload。"
	)
	assert_true(lease.is_ready_to_stage())
	assert_null(
		lease.take_stage_request_for_utility(),
		"严格 payload 预算应在 callback 外构造 request 时执行。"
	)
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)

	var source: String = FileAccess.get_file_as_string(
		"res://features/persistence/scripts/chunking/chunk_save_lease.gd"
	)
	var create_source: String = _extract_function_source(
		source,
		"static func create("
	)
	var offer_source: String = _extract_function_source(
		source,
		"func offer_chunks_taking_ownership("
	)
	assert_false(create_source.is_empty())
	assert_false(create_source.contains(".duplicate("))
	assert_false(create_source.contains("for "))
	assert_false(create_source.contains("while "))
	assert_false(offer_source.is_empty())
	assert_false(offer_source.contains(".duplicate("))
	assert_false(offer_source.contains("for "))
	assert_false(offer_source.contains("while "))
	assert_false(offer_source.contains(".is_valid()"))


func test_waiting_and_ready_rebase_require_exact_scope_epoch_before_stage() -> void:
	var stale_active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		_make_chunks(["visible-a"])
	)
	assert_not_null(stale_active_manifest)
	if stale_active_manifest == null:
		return

	var waiting: ChunkSaveLease = _make_lease()
	assert_not_null(waiting)
	if waiting == null:
		return
	assert_true(
		waiting.rebase_scope_basis_for_utility(ChunkManifest.BANK_B, 7)
	)
	assert_true(waiting.offer_chunks_taking_ownership(
		_make_chunks(["waiting-after-b"]),
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		stale_active_manifest
	))
	assert_true(
		waiting.matches_scope_basis_for_utility(ChunkManifest.BANK_B, 7)
	)
	assert_null(
		waiting.take_stage_request_for_utility(ChunkManifest.BANK_B, 6),
		"旧 epoch 不得 claim 已接纳 payload。"
	)
	assert_true(waiting.is_ready_to_stage())
	var waiting_request: ChunkStageRequest = (
		waiting.take_stage_request_for_utility(ChunkManifest.BANK_B, 7)
	)
	assert_not_null(waiting_request)
	var waiting_manifest: ChunkManifest = (
		waiting_request.build_manifest()
		if waiting_request != null
		else null
	)
	assert_true(
		waiting_manifest != null
		and waiting_manifest.get_bank() == ChunkManifest.BANK_A,
		"WAITING lease 必须忽略早先冻结的 A，并在最新 active B 之外 stage A。"
	)

	var ready_lease: ChunkSaveLease = _make_lease()
	assert_not_null(ready_lease)
	if ready_lease == null:
		return
	assert_true(ready_lease.offer_chunks_taking_ownership(
		_make_chunks(["ready-before-commit"]),
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		stale_active_manifest
	))
	assert_true(
		ready_lease.rebase_scope_basis_for_utility(ChunkManifest.BANK_B, 11)
	)
	assert_false(
		ready_lease.rebase_scope_basis_for_utility(ChunkManifest.BANK_A, 11),
		"同 epoch 不得接受冲突 bank。"
	)
	assert_null(
		ready_lease.take_stage_request_for_utility(ChunkManifest.BANK_A, 11),
		"bank CAS 不匹配时不得 claim payload。"
	)
	assert_true(ready_lease.is_ready_to_stage())
	var ready_request: ChunkStageRequest = ready_lease.take_stage_request_for_utility(
		ChunkManifest.BANK_B,
		11
	)
	assert_not_null(ready_request)
	var ready_manifest: ChunkManifest = (
		ready_request.build_manifest() if ready_request != null else null
	)
	assert_true(
		ready_manifest != null
		and ready_manifest.get_bank() == ChunkManifest.BANK_A,
		"READY lease 重基线不得复制/丢弃 payload，且必须改写 target bank。"
	)


func test_manifest_claim_does_not_commit_before_real_main_result() -> void:
	var lease: ChunkSaveLease = _make_lease()
	assert_not_null(lease)
	if lease == null:
		return
	var main_operation: GFSaveProfileOperation = _make_main_operation()
	assert_true(lease.bind_main_operation(main_operation))
	var claimed_manifest: ChunkManifest = _stage_and_claim(lease)
	assert_not_null(claimed_manifest)
	if claimed_manifest == null:
		return
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_MANIFEST_CLAIMED)
	assert_null(
		lease.claim_manifest_for_provider(),
		"Provider 对候选 Manifest 只能 claim 一次。"
	)
	assert_null(lease.get_committed_manifest())

	var synthetic_success: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		MAIN_GENERATION
	)
	assert_false(
		lease.settle_main_result_for_utility(synthetic_success),
		"未完成的绑定 GF operation 不能被外来结果伪造为成功。"
	)
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_MANIFEST_CLAIMED)

	var real_success: GFSaveProfileResult = _complete_main_operation(
		main_operation,
		synthetic_success
	)
	assert_not_null(real_success)
	if real_success == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_success))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_COMMITTED)
	var committed_manifest: ChunkManifest = lease.get_committed_manifest()
	assert_not_null(committed_manifest)
	if committed_manifest != null:
		assert_true(committed_manifest.to_dict() == claimed_manifest.to_dict())


func test_coalesced_main_save_supersedes_candidate_manifest() -> void:
	var fixture: Dictionary = _make_staged_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	var operation_value: Variant = fixture.get(&"operation")
	assert_true(lease_value is ChunkSaveLease)
	assert_true(operation_value is GFSaveProfileOperation)
	if not lease_value is ChunkSaveLease or not operation_value is GFSaveProfileOperation:
		return
	var lease: ChunkSaveLease = lease_value
	var operation: GFSaveProfileOperation = operation_value
	var coalesced: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		MAIN_GENERATION + 1,
		true
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		operation,
		coalesced
	)
	assert_not_null(real_result)
	if real_result == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_result))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_SUPERSEDED)
	assert_null(lease.get_committed_manifest())


func test_known_main_failure_never_commits_candidate_manifest() -> void:
	var fixture: Dictionary = _make_staged_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	var operation_value: Variant = fixture.get(&"operation")
	assert_true(lease_value is ChunkSaveLease)
	assert_true(operation_value is GFSaveProfileOperation)
	if not lease_value is ChunkSaveLease or not operation_value is GFSaveProfileOperation:
		return
	var lease: ChunkSaveLease = lease_value
	var operation: GFSaveProfileOperation = operation_value
	var failure: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_STORAGE_FAILED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		0
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		operation,
		failure
	)
	assert_not_null(real_result)
	if real_result == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_result))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_true(lease.get_error_code() == ERR_CANT_CREATE)
	assert_null(lease.get_committed_manifest())


func test_main_outcome_unknown_keeps_visibility_fenced() -> void:
	var fixture: Dictionary = _make_staged_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	var operation_value: Variant = fixture.get(&"operation")
	assert_true(lease_value is ChunkSaveLease)
	assert_true(operation_value is GFSaveProfileOperation)
	if not lease_value is ChunkSaveLease or not operation_value is GFSaveProfileOperation:
		return
	var lease: ChunkSaveLease = lease_value
	var operation: GFSaveProfileOperation = operation_value
	var unknown: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		0
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		operation,
		unknown
	)
	assert_not_null(real_result)
	if real_result == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_result))
	assert_true(lease.is_outcome_unknown())
	assert_true(lease.get_error_code() == ERR_TIMEOUT)
	assert_null(lease.get_committed_manifest())


func test_main_outcome_unknown_can_reconcile_to_late_commit() -> void:
	var fixture: Dictionary = _make_main_outcome_unknown_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	assert_true(lease_value is ChunkSaveLease)
	if not lease_value is ChunkSaveLease:
		return
	var lease: ChunkSaveLease = lease_value
	var evidence: Dictionary = _make_settled_main_snapshot(MAIN_GENERATION)
	assert_true(
		lease.reconcile_main_outcome_for_utility(
			true,
			MAIN_GENERATION,
			evidence
		)
	)
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_COMMITTED)
	assert_not_null(lease.get_committed_manifest())
	assert_false(
		lease.reconcile_main_outcome_for_utility(
			true,
			MAIN_GENERATION,
			evidence
		),
		"late reconciliation 只能收敛一次。"
	)


func test_main_outcome_unknown_newer_generation_is_superseded() -> void:
	var fixture: Dictionary = _make_main_outcome_unknown_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	assert_true(lease_value is ChunkSaveLease)
	if not lease_value is ChunkSaveLease:
		return
	var lease: ChunkSaveLease = lease_value
	var newer_generation: int = MAIN_GENERATION + 1
	var evidence: Dictionary = _make_settled_main_snapshot(newer_generation)
	assert_true(lease.reconcile_main_outcome_for_utility(
		true,
		newer_generation,
		evidence
	))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_SUPERSEDED)
	assert_null(
		lease.get_committed_manifest(),
		"newer generation 不能伪装为本 lease 的 exact Manifest commit。"
	)


func test_main_outcome_unknown_can_fail_only_after_fences_clear() -> void:
	var fixture: Dictionary = _make_main_outcome_unknown_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	assert_true(lease_value is ChunkSaveLease)
	if not lease_value is ChunkSaveLease:
		return
	var lease: ChunkSaveLease = lease_value
	var pending_evidence: Dictionary = _make_settled_main_snapshot(
		MAIN_GENERATION - 1
	)
	pending_evidence["write_outcome_unknown"] = true
	pending_evidence["unknown_write_generations"] = PackedInt64Array([
		MAIN_GENERATION,
	])
	pending_evidence["detached_write_count"] = 1
	pending_evidence["detached_storage_request_ids"] = PackedInt64Array([91])
	assert_false(
		lease.reconcile_main_outcome_for_utility(
			false,
			MAIN_GENERATION - 1,
			pending_evidence
		),
		"GF public snapshot 仍有 unknown/detached 时不得解除 fence。"
	)
	assert_true(lease.is_outcome_unknown())

	var settled_evidence: Dictionary = _make_settled_main_snapshot(
		MAIN_GENERATION - 1
	)
	assert_true(
		lease.reconcile_main_outcome_for_utility(
			false,
			MAIN_GENERATION - 1,
			settled_evidence
		)
	)
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_null(lease.get_committed_manifest())


func test_stage_outcome_unknown_is_not_downgraded_by_main_failure() -> void:
	var lease: ChunkSaveLease = _make_lease()
	assert_not_null(lease)
	if lease == null:
		return
	var main_operation: GFSaveProfileOperation = _make_main_operation()
	assert_true(lease.bind_main_operation(main_operation))
	assert_true(_offer_valid_chunks(lease))
	var request: ChunkStageRequest = lease.take_stage_request_for_utility()
	assert_not_null(request)
	if request == null:
		return
	var stage_operation: ChunkStageOperation = ChunkStageOperation.new()
	assert_true(lease.bind_stage_operation_for_utility(stage_operation))
	var stage_unknown: ChunkStageResult = ChunkStageResult.create(
		ChunkStageResult.STATUS_OUTCOME_UNKNOWN,
		ERR_TIMEOUT,
		"chunk write outcome is unknown",
		0
	)
	assert_true(stage_operation.complete_for_persistence(stage_unknown))
	assert_true(lease.settle_stage_for_utility(stage_unknown))
	assert_true(lease.is_outcome_unknown())
	var stage_error: String = lease.get_error()

	var main_failure: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_STORAGE_FAILED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		0
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		main_operation,
		main_failure
	)
	assert_not_null(real_result)
	if real_result == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_result))
	assert_true(lease.is_outcome_unknown())
	assert_true(lease.get_error() == stage_error)
	var stored_main_result: GFSaveProfileResult = lease.get_main_result()
	assert_not_null(stored_main_result)
	if stored_main_result != null:
		assert_true(
			stored_main_result.get_status()
			== GFSaveProfileResult.STATUS_STORAGE_FAILED
		)


func test_stage_outcome_unknown_reconciles_only_after_exact_fences_clear() -> void:
	var lease: ChunkSaveLease = _make_lease()
	assert_not_null(lease)
	if lease == null:
		return
	var main_operation: GFSaveProfileOperation = _make_main_operation()
	assert_true(lease.bind_main_operation(main_operation))
	assert_true(_offer_valid_chunks(lease))
	var request: ChunkStageRequest = lease.take_stage_request_for_utility()
	assert_not_null(request)
	if request == null:
		return
	var failed_profile_id: StringName = request.get_chunk_profile_id(0)
	var chunk_unknown: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		failed_profile_id,
		1,
		0
	)
	var stage_operation: ChunkStageOperation = ChunkStageOperation.new()
	assert_true(lease.bind_stage_operation_for_utility(stage_operation))
	var stage_unknown: ChunkStageResult = ChunkStageResult.create(
		ChunkStageResult.STATUS_OUTCOME_UNKNOWN,
		ERR_TIMEOUT,
		"chunk write outcome is unknown",
		0,
		null,
		chunk_unknown
	)
	assert_true(stage_operation.complete_for_persistence(stage_unknown))
	assert_true(lease.settle_stage_for_utility(stage_unknown))
	assert_true(lease.is_stage_outcome_unknown())

	var wrong_profile_evidence: Dictionary = _make_settled_stage_snapshot(
		&"accounts.primary.chunks.bookmarks.B.000001"
	)
	assert_false(
		lease.reconcile_stage_outcome_for_utility(wrong_profile_evidence),
		"只能使用 exact failed chunk Profile 的 public snapshot。"
	)
	var pending_evidence: Dictionary = _make_settled_stage_snapshot(
		failed_profile_id
	)
	pending_evidence["write_outcome_unknown"] = true
	pending_evidence["unknown_write_generations"] = PackedInt64Array([1])
	pending_evidence["detached_write_count"] = 1
	pending_evidence["detached_storage_request_ids"] = PackedInt64Array([91])
	assert_false(
		lease.reconcile_stage_outcome_for_utility(pending_evidence),
		"unknown/detached fence 未清空时不得把 stage 降级为已知失败。"
	)
	assert_true(lease.is_stage_outcome_unknown())

	var settled_evidence: Dictionary = _make_settled_stage_snapshot(
		failed_profile_id
	)
	assert_true(
		lease.reconcile_stage_outcome_for_utility(settled_evidence)
	)
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_false(lease.is_stage_outcome_unknown())
	assert_null(lease.get_committed_manifest())

	var main_success: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		MAIN_GENERATION
	)
	var real_main_success: GFSaveProfileResult = _complete_main_operation(
		main_operation,
		main_success
	)
	assert_not_null(real_main_success)
	if real_main_success == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_main_success))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_null(
		lease.get_committed_manifest(),
		"stage fence 对账后，即使主 Profile 后续保存成功也不得提交 Manifest。"
	)


func test_profile_generation_revision_and_section_identity_are_rejected() -> void:
	var lease: ChunkSaveLease = _make_lease()
	assert_not_null(lease)
	if lease == null:
		return
	var chunks: Array[PackedByteArray] = _make_chunks(["identity"])
	assert_false(
		lease.offer_chunks_taking_ownership(
			chunks,
			PRODUCER_REVISION + 1,
			SECTION_ID,
			SECTION_SCHEMA_VERSION
		),
		"Provider revision 不能跨 lease 混用。"
	)
	assert_false(
		lease.offer_chunks_taking_ownership(
			chunks,
			PRODUCER_REVISION,
			&"custom_boards",
			SECTION_SCHEMA_VERSION
		),
		"section ID 不能跨 lease 混用。"
	)
	assert_false(
		lease.offer_chunks_taking_ownership(
			chunks,
			PRODUCER_REVISION,
			SECTION_ID,
			SECTION_SCHEMA_VERSION + 1
		),
		"section schema 不能跨 lease 混用。"
	)
	var foreign_manifest: ChunkManifest = ChunkManifest.create(
		&"custom_boards",
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		chunks
	)
	assert_not_null(foreign_manifest)
	assert_false(
		lease.offer_chunks_taking_ownership(
			chunks,
			PRODUCER_REVISION,
			SECTION_ID,
			SECTION_SCHEMA_VERSION,
			foreign_manifest
		)
	)

	var wrong_profile_operation: GFSaveProfileOperation = _make_main_operation(
		&"accounts.other.player",
		MAIN_GENERATION
	)
	assert_false(lease.bind_main_operation(wrong_profile_operation))
	var correct_operation: GFSaveProfileOperation = _make_main_operation()
	assert_true(lease.bind_main_operation(correct_operation))
	assert_true(_offer_valid_chunks(lease))
	assert_not_null(_stage_and_claim_after_offer(lease))
	var wrong_generation: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION + 1,
		MAIN_GENERATION + 1
	)
	var actual_wrong_generation: GFSaveProfileResult = _complete_main_operation(
		correct_operation,
		wrong_generation
	)
	assert_not_null(actual_wrong_generation)
	if actual_wrong_generation == null:
		return
	assert_false(lease.settle_main_result_for_utility(actual_wrong_generation))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_MANIFEST_CLAIMED)
	assert_null(lease.get_main_result())


func test_success_with_stale_persisted_generation_does_not_commit() -> void:
	var fixture: Dictionary = _make_staged_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	var operation_value: Variant = fixture.get(&"operation")
	assert_true(lease_value is ChunkSaveLease)
	assert_true(operation_value is GFSaveProfileOperation)
	if not lease_value is ChunkSaveLease or not operation_value is GFSaveProfileOperation:
		return
	var lease: ChunkSaveLease = lease_value
	var operation: GFSaveProfileOperation = operation_value
	var stale_success: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		MAIN_GENERATION - 1
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		operation,
		stale_success
	)
	assert_not_null(real_result)
	if real_result == null:
		return
	assert_true(lease.settle_main_result_for_utility(real_result))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_null(lease.get_committed_manifest())


# --- 私有/辅助方法 ---

func _make_lease() -> ChunkSaveLease:
	return ChunkSaveLease.create(
		LEASE_ID,
		MAIN_PROFILE_ID,
		MAIN_PROFILE_FILE,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION,
		CHUNK_PROFILE_PREFIX
	)


func _make_staged_fixture() -> Dictionary:
	var lease: ChunkSaveLease = _make_lease()
	if lease == null:
		return {}
	var operation: GFSaveProfileOperation = _make_main_operation()
	if not lease.bind_main_operation(operation):
		return {}
	if _stage_and_claim(lease) == null:
		return {}
	return {
		&"lease": lease,
		&"operation": operation,
	}


func _make_main_outcome_unknown_fixture() -> Dictionary:
	var fixture: Dictionary = _make_staged_fixture()
	var lease_value: Variant = fixture.get(&"lease")
	var operation_value: Variant = fixture.get(&"operation")
	if not lease_value is ChunkSaveLease or not operation_value is GFSaveProfileOperation:
		return {}
	var lease: ChunkSaveLease = lease_value
	var operation: GFSaveProfileOperation = operation_value
	var unknown: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		0
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		operation,
		unknown
	)
	if real_result == null or not lease.settle_main_result_for_utility(real_result):
		return {}
	return fixture


func _offer_valid_chunks(lease: ChunkSaveLease) -> bool:
	return lease.offer_chunks_taking_ownership(
		_make_chunks(["alpha", "beta"]),
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	)


func _stage_and_claim(lease: ChunkSaveLease) -> ChunkManifest:
	if not _offer_valid_chunks(lease):
		return null
	return _stage_and_claim_after_offer(lease)


func _stage_and_claim_after_offer(lease: ChunkSaveLease) -> ChunkManifest:
	var request: ChunkStageRequest = lease.take_stage_request_for_utility()
	if request == null:
		return null
	var operation: ChunkStageOperation = ChunkStageOperation.new()
	if not lease.bind_stage_operation_for_utility(operation):
		return null
	var manifest: ChunkManifest = request.build_manifest()
	if manifest == null:
		return null
	var result: ChunkStageResult = ChunkStageResult.create(
		ChunkStageResult.STATUS_STAGED,
		OK,
		"",
		-1,
		manifest
	)
	if not operation.complete_for_persistence(result):
		return null
	if not lease.settle_stage_for_utility(result):
		return null
	return lease.claim_manifest_for_provider()


func _make_main_operation(
	profile_id: StringName = MAIN_PROFILE_ID,
	requested_generation: int = MAIN_GENERATION
) -> GFSaveProfileOperation:
	var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
	var configured: bool = operation.configure_save_ownership_for_framework(
		profile_id,
		requested_generation,
		0,
		{}
	)
	if configured:
		var _started: bool = operation.start_for_framework()
	return operation


func _make_main_result(
	status: StringName,
	profile_id: StringName,
	requested_generation: int,
	persisted_generation: int,
	coalesced: bool = false
) -> GFSaveProfileResult:
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
		requested_generation,
		persisted_generation,
		1,
		0,
		1,
		coalesced,
		false,
		&"",
		&"",
		error_code,
		"" if successful else "synthetic main profile failure"
	)
	return result


func _complete_main_operation(
	operation: GFSaveProfileOperation,
	result: GFSaveProfileResult
) -> GFSaveProfileResult:
	if operation == null or result == null:
		return null
	if not operation.complete_for_framework(result):
		return null
	return operation.get_result()


func _make_chunks(values: Array[String]) -> Array[PackedByteArray]:
	var chunks: Array[PackedByteArray] = []
	for value: String in values:
		chunks.append(value.to_utf8_buffer())
	return chunks


func _make_settled_main_snapshot(persisted_generation: int) -> Dictionary:
	return {
		"profile_id": MAIN_PROFILE_ID,
		"persisted_generation": persisted_generation,
		"write_outcome_unknown": false,
		"unknown_write_generations": PackedInt64Array(),
		"detached_write_count": 0,
		"detached_storage_request_ids": PackedInt64Array(),
	}


func _make_settled_stage_snapshot(profile_id: StringName) -> Dictionary:
	return {
		"profile_id": profile_id,
		"state": GFSaveProfileUtility.STATE_IDLE,
		"write_outcome_unknown": false,
		"unknown_write_generations": PackedInt64Array(),
		"detached_write_count": 0,
		"detached_storage_request_ids": PackedInt64Array(),
	}


func _extract_function_source(source: String, signature: String) -> String:
	var start_index: int = source.find(signature)
	if start_index < 0:
		return ""
	var end_index: int = source.find("\n\n##", start_index)
	if end_index < 0:
		end_index = source.length()
	return source.substr(start_index, end_index - start_index)
