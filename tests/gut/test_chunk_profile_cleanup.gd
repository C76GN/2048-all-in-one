## 验证 manifest-backed A/B chunk orphan/tail 回收与物理终态 fence。
extends GutTest


# --- 常量 ---

const MAIN_PROFILE_ID: StringName = &"player_data.chunk_cleanup_test"
const MAIN_FILE_NAME: String = "profiles/chunk_cleanup_test.save"
const SECTION_ID: StringName = &"bookmarks"
const SECTION_SCHEMA_VERSION: int = 10
const PRODUCER_REVISION: int = 7
const MAXIMUM_TICK_FRAMES: int = 720


# --- 测试用例 ---

func test_request_derives_only_fixed_old_bank_and_smaller_count_tail() -> void:
	var committed: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_B,
		[
			"new-zero".to_utf8_buffer(),
			"new-one".to_utf8_buffer(),
		]
	)
	assert_not_null(committed)
	if committed == null:
		return
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.after_exact_commit(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			ChunkManifest.BANK_A,
			committed
		)
	)
	assert_not_null(request)
	if request == null:
		return
	assert_true(request.is_valid())
	assert_true(request.get_identity_count() == 126)
	_assert_identity(request.get_identity(0), ChunkManifest.BANK_A, 0)
	_assert_identity(request.get_identity(63), ChunkManifest.BANK_A, 63)
	_assert_identity(request.get_identity(64), ChunkManifest.BANK_B, 2)
	_assert_identity(request.get_identity(125), ChunkManifest.BANK_B, 63)
	assert_null(request.get_identity(126))
	assert_null(ChunkProfileCleanupRequest.after_exact_commit(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		ChunkManifest.BANK_B,
		committed
	))


func test_exact_commit_reclaims_old_bank_and_tail_but_keeps_visible_chunks() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		[
			"old-zero".to_utf8_buffer(),
			"old-one".to_utf8_buffer(),
		]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 1) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_B, 1) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_B, 63) == OK)

	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["visible-new-zero".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	var committed_manifest: ChunkManifest = lease.claim_manifest_for_provider()
	assert_not_null(committed_manifest)
	if committed_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(committed_manifest.get_bank() == ChunkManifest.BANK_B)
	var cleanup_probe: CleanupSettlementProbe = CleanupSettlementProbe.new()
	cleanup_probe.utility = utility
	var connect_error: int = utility.cleanup_operation_settled.connect(
		cleanup_probe.on_cleanup_settled
	)
	assert_true(connect_error == OK)
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_SAVED,
		1,
		1
	))
	assert_true(utility.is_save_scope_fenced(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_false(utility.is_save_scope_fenced(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	))
	assert_false(cleanup_probe.last_result.is_empty())
	if not cleanup_probe.last_result.is_empty():
		assert_true(_dictionary_bool(
			cleanup_probe.last_result,
			&"ok",
			false
		))
		assert_true(_dictionary_int(
			cleanup_probe.last_result,
			&"total_count",
			0
		) == 127)
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 1))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_B, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 1))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 63))
	_dispose_setup(setup)


func test_exact_commit_defers_old_bank_cleanup_until_materialization_finishes() -> void:
	var delayed_profiles: DeferredChunkLoadProfileUtility = (
		DeferredChunkLoadProfileUtility.new()
	)
	var setup: Dictionary = await _create_setup(delayed_profiles)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var old_payload: PackedByteArray = "visible-old-a".to_utf8_buffer()
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		[old_payload]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	var materialization: MaterializationProbe = MaterializationProbe.new()
	materialization.start(
		utility,
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		active_manifest
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return (
				delayed_profiles.has_pending_load()
				and _dictionary_int(
					utility.get_debug_snapshot(),
					&"active_materialization_count",
					0
				) == 1
			)
	))

	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["visible-new-b".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_SAVED,
		1,
		1
	))
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"deferred_cleanup_count",
		-1
	) == 1)
	assert_true(
		_has_chunk(storage, ChunkManifest.BANK_A, 0),
		"旧 bank reader 未结束前 exact commit cleanup 不得删除 A。"
	)
	assert_null(
		utility.create_save_lease(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			SECTION_SCHEMA_VERSION,
			PRODUCER_REVISION + 1
		),
		"延迟 cleanup 已取得 scope fence 后不得复用 scope。"
	)
	assert_true(delayed_profiles.complete_pending_load(old_payload))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return materialization.completed
	))
	assert_true(_dictionary_bool(materialization.result, &"ok", false))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	_dispose_setup(setup)


func test_exact_commit_cleanup_survives_last_sibling_pre_stage_failure() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		["old-visible-a".to_utf8_buffer()]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)

	var first: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	var sibling: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	assert_not_null(first)
	assert_not_null(sibling)
	if first == null or sibling == null:
		_dispose_setup(setup)
		return
	assert_true(first.offer_chunks_taking_ownership(
		["new-visible-b".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return first.is_staged()
	))
	assert_not_null(first.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		first,
		GFSaveProfileResult.STATUS_SAVED,
		1,
		1
	))
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"pending_exact_cleanup_count",
		0
	) == 1)
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_not_null(utility.fail_save_lease(
		sibling.get_lease_id(),
		ERR_SKIP,
		"synthetic pre-stage sibling failure"
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return (
				_dictionary_int(
					utility.get_debug_snapshot(),
					&"cleanup_operation_count",
					-1
				) == 0
				and _dictionary_int(
					utility.get_debug_snapshot(),
					&"pending_exact_cleanup_count",
					-1
				) == 0
			)
	))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	assert_true(
		_has_chunk(storage, ChunkManifest.BANK_B, 0),
		"最后 sibling 在 staging 前失败时，deferred exact cleanup 不得删除可见 B。"
	)
	_dispose_setup(setup)


func test_newer_sibling_commit_replaces_deferred_exact_cleanup_basis() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		["old-visible-a".to_utf8_buffer()]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)

	var first: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	var sibling: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	assert_not_null(first)
	assert_not_null(sibling)
	if first == null or sibling == null:
		_dispose_setup(setup)
		return
	assert_true(first.offer_chunks_taking_ownership(
		["first-visible-b".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(sibling.offer_chunks_taking_ownership(
		["second-visible-a".to_utf8_buffer()],
		PRODUCER_REVISION + 1,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return first.is_staged()
	))
	assert_not_null(first.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		first,
		GFSaveProfileResult.STATUS_SAVED,
		1,
		1
	))
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"pending_exact_cleanup_count",
		0
	) == 1)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return sibling.is_staged()
	))
	var sibling_manifest: ChunkManifest = sibling.claim_manifest_for_provider()
	assert_not_null(sibling_manifest)
	if sibling_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(sibling_manifest.get_bank() == ChunkManifest.BANK_A)
	assert_true(_settle_main(
		utility,
		sibling,
		GFSaveProfileResult.STATUS_SAVED,
		2,
		2
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return (
				_dictionary_int(
					utility.get_debug_snapshot(),
					&"cleanup_operation_count",
					-1
				) == 0
				and _dictionary_int(
					utility.get_debug_snapshot(),
					&"pending_exact_cleanup_count",
					-1
				) == 0
			)
	))
	assert_true(
		_has_chunk(storage, ChunkManifest.BANK_A, 0),
		"新 sibling exact commit 后必须保留最新可见 A。"
	)
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 0))
	_dispose_setup(setup)


func test_known_main_failure_discards_candidate_bank_and_keeps_active_bank() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		["still-visible".to_utf8_buffer()]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		[
			"candidate-zero".to_utf8_buffer(),
			"candidate-one".to_utf8_buffer(),
		],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_STORAGE_FAILED,
		1,
		0
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 1))
	_dispose_setup(setup)


func test_superseded_main_result_does_not_guess_candidate_visibility() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var active_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		["visible-a".to_utf8_buffer()]
	)
	assert_not_null(active_manifest)
	if active_manifest == null:
		_dispose_setup(setup)
		return
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_B, 63) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["possibly-visible-b".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		active_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_SAVED,
		1,
		2
	))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_SUPERSEDED)
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"cleanup_operation_count",
		-1
	) == 0)
	assert_true(_has_chunk(storage, ChunkManifest.BANK_B, 0))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_B, 63))
	_dispose_setup(setup)


func test_stage_known_failure_discards_whole_candidate_bank() -> void:
	var failing_profiles: FailingChunkProfileUtility = (
		FailingChunkProfileUtility.new()
	)
	var setup: Dictionary = await _create_setup(failing_profiles)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["known-stage-failure".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return lease.get_status() == ChunkSaveLease.STATUS_FAILED
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	_dispose_setup(setup)


func test_stage_known_failure_waits_for_bound_main_physical_terminal() -> void:
	var failing_profiles: FailingChunkProfileUtility = (
		FailingChunkProfileUtility.new()
	)
	var setup: Dictionary = await _create_setup(failing_profiles)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	var main_operation: GFSaveProfileOperation = _make_main_operation(lease, 1)
	assert_not_null(main_operation)
	assert_true(main_operation != null and lease.bind_main_operation(main_operation))
	assert_true(lease.offer_chunks_taking_ownership(
		["known-stage-failure-with-main".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.get_status() == ChunkSaveLease.STATUS_FAILED
	))
	assert_true(
		utility.get_save_lease(lease.get_lease_id()) == lease,
		"已绑定 main 未物理终结时必须保留 lease cleanup identity。"
	)
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"cleanup_operation_count",
		-1
	) == 0)
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	assert_true(_settle_bound_main(
		utility,
		lease,
		main_operation,
		GFSaveProfileResult.STATUS_STORAGE_FAILED,
		1,
		0
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	_dispose_setup(setup)


func test_main_outcome_unknown_holds_fence_until_reconciliation_then_cleans() -> void:
	var setup: Dictionary = await _create_setup(
		ReconciledMainProfileUtility.new()
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["unknown-candidate".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		1,
		0
	))
	assert_true(lease.is_outcome_unknown())
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"cleanup_operation_count",
		-1
	) == 0, "main outcome_unknown 未对账前不得删除候选 bank。")
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return lease.get_status() == ChunkSaveLease.STATUS_FAILED
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	_dispose_setup(setup)


func test_explicit_family_cleanup_fences_and_waits_for_outcome_reconciliation() -> void:
	var setup: Dictionary = await _create_setup(
		ReconciledMainProfileUtility.new()
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["outcome-fenced-candidate".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		1,
		0
	))
	assert_true(lease.is_outcome_unknown())
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))

	var cleanup: ChunkProfileCleanupOperation = (
		utility.cleanup_derived_family_async(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID
		)
	)
	assert_true(cleanup.is_pending())
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"deferred_cleanup_count",
		-1
	) == 1)
	assert_null(utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	))
	var duplicate_cleanup: ChunkProfileCleanupOperation = (
		utility.cleanup_derived_family_async(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID
		)
	)
	assert_true(duplicate_cleanup.is_completed())
	assert_true(
		duplicate_cleanup.get_result().get_status()
		== ChunkProfileCleanupResult.STATUS_BUSY
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return cleanup.is_completed()
	))
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_true(cleanup.get_result().is_successful())
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(utility.is_save_scope_fenced(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	))
	_dispose_setup(setup)


func test_main_outcome_unknown_exact_generation_commits_and_cleans_tail() -> void:
	var reconciled_profiles: ReconciledMainProfileUtility = (
		ReconciledMainProfileUtility.new()
	)
	reconciled_profiles.snapshot_persisted_generation = 1
	var setup: Dictionary = await _create_setup(reconciled_profiles)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["exact-candidate".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		1,
		0
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.get_status() == ChunkSaveLease.STATUS_COMMITTED
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"cleanup_operation_count",
				-1
			) == 0
	))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	_dispose_setup(setup)


func test_main_outcome_unknown_newer_generation_is_superseded_without_cleanup() -> void:
	var reconciled_profiles: ReconciledMainProfileUtility = (
		ReconciledMainProfileUtility.new()
	)
	reconciled_profiles.snapshot_persisted_generation = 2
	var setup: Dictionary = await _create_setup(reconciled_profiles)
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 63) == OK)
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(lease.offer_chunks_taking_ownership(
		["superseded-candidate".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	assert_not_null(lease.claim_manifest_for_provider())
	assert_true(_settle_main(
		utility,
		lease,
		GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN,
		1,
		0
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.get_status() == ChunkSaveLease.STATUS_SUPERSEDED
	))
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"cleanup_operation_count",
		-1
	) == 0)
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 63))
	_dispose_setup(setup)


func test_cleanup_settlement_releases_scope_before_signal_waiter_resumes() -> void:
	var storage: ControllableDeleteStorage = ControllableDeleteStorage.new()
	var late_identity: ChunkProfileIdentity = _make_identity(
		ChunkManifest.BANK_A,
		0
	)
	assert_not_null(late_identity)
	if late_identity == null:
		return
	storage.late_success_file = late_identity.get_file_name()
	var setup: Dictionary = await _create_setup(null, storage)
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var cleanup: ChunkProfileCleanupOperation = (
		utility.cleanup_derived_family_async(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID
		)
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return (
				cleanup.is_pending()
				and _dictionary_int(
					cleanup.get_debug_snapshot(),
					&"caller_outcome_unknown_count",
					0
				) == 1
			)
	))
	var busy: ChunkProfileCleanupOperation = utility.cleanup_derived_family_async(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	)
	assert_true(
		busy.is_completed()
		and busy.get_result().get_status()
		== ChunkProfileCleanupResult.STATUS_BUSY
	)
	var waiter: CleanupFenceWaitProbe = CleanupFenceWaitProbe.new()
	waiter.start(utility)
	await get_tree().process_frame
	assert_false(waiter.completed)
	assert_true(storage.settle_late_success())
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return cleanup.is_completed() and waiter.completed
	))
	assert_false(utility.is_save_scope_fenced(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	))
	assert_true(
		utility.get_cleanup_operation(cleanup.get_operation_id()) == null,
		"settled signal 发布前必须先释放 operation map 与 scope owner。"
	)
	_dispose_setup(setup)


func test_cooperative_family_cleanup_does_not_expire_while_waiting_for_worker_acceptance() -> void:
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(null, null, clock)
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var cleanup: ChunkProfileCleanupOperation = (
		utility.cleanup_derived_family_async(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID
		)
	)
	# Runner 的 deferred begin 会一次冻结并提交整个 A/B family；暂不 tick
	# architecture，确保 cooperative Storage 尚未接纳队列中的任何 worker。
	await get_tree().process_frame
	assert_true(cleanup.is_pending())
	assert_true(_dictionary_int(
		cleanup.get_debug_snapshot(),
		&"physical_pending_count",
		0
	) == 128)
	assert_true(clock.advance_msec(5_001))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return cleanup.is_completed()
	))
	var result: ChunkProfileCleanupResult = cleanup.get_result()
	assert_not_null(result)
	if result != null:
		assert_true(
			result.is_successful(),
			"已接纳的 family cleanup 不能因 cooperative 队列等待而物理取消。"
		)
		assert_true(result.get_skipped_count() == 0)
	_dispose_setup(setup)


func test_delete_caller_outcome_unknown_waits_for_late_physical_terminal() -> void:
	var storage: ControllableDeleteStorage = ControllableDeleteStorage.new()
	var manifest: ChunkManifest = _make_sixty_three_chunk_manifest(
		ChunkManifest.BANK_A
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.after_exact_commit(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			ChunkManifest.BANK_NONE,
			manifest
		)
	)
	assert_not_null(request)
	if request == null:
		return
	assert_true(request.get_identity_count() == 1)
	var identity: ChunkProfileIdentity = request.get_identity(0)
	storage.late_success_file = identity.get_file_name()
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	assert_true(operation.configure_for_persistence(&"cleanup.late"))
	var runner: ChunkProfileCleanupRunner = ChunkProfileCleanupRunner.new(storage)
	assert_true(runner.start(request, operation))
	await get_tree().process_frame
	assert_true(operation.is_pending())
	assert_true(
		operation.get_phase()
		== ChunkProfileCleanupOperation.PHASE_WAITING_FOR_PHYSICAL
	)
	assert_true(_dictionary_int(
		operation.get_debug_snapshot(),
		&"caller_outcome_unknown_count",
		-1
	) == 1)
	assert_true(operation.request_cancel(&"test_cancel"))
	assert_true(operation.is_pending(), "cancel 不得伪造已接纳 delete 的物理终态。")
	assert_true(storage.settle_late_success())
	await get_tree().process_frame
	assert_true(operation.is_completed())
	var result: ChunkProfileCleanupResult = operation.get_result()
	assert_not_null(result)
	if result != null:
		assert_true(result.get_status() == ChunkProfileCleanupResult.STATUS_CANCELLED)
		assert_true(result.get_caller_outcome_unknown_count() == 1)
		assert_true(result.get_deleted_count() == 1)


func test_connect_failure_fallback_polls_once_per_process_frame() -> void:
	var storage: ConnectFailurePollingStorage = (
		ConnectFailurePollingStorage.new()
	)
	var manifest: ChunkManifest = _make_sixty_three_chunk_manifest(
		ChunkManifest.BANK_A
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.after_exact_commit(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			ChunkManifest.BANK_NONE,
			manifest
		)
	)
	assert_not_null(request)
	if request == null:
		return
	assert_true(request.get_identity_count() == 1)
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	assert_true(operation.configure_for_persistence(&"cleanup.connect_failure"))
	var runner: ConnectFailureCleanupRunner = (
		ConnectFailureCleanupRunner.new(storage)
	)
	assert_true(runner.start(request, operation))
	# 若 fallback 递归 call_deferred，本帧永远无法返回到测试。
	await get_tree().process_frame
	assert_true(runner.physical_connect_attempt_count == 1)
	assert_true(operation.is_pending())
	assert_true(_dictionary_int(
		operation.get_debug_snapshot(),
		&"physical_poll_count",
		0
	) == 1)
	assert_true(storage.settle_pending())
	assert_true(
		operation.is_pending(),
		"强制断开的 physical signal 只能由下一 process_frame poll 收敛。"
	)
	await get_tree().process_frame
	assert_true(operation.is_completed())
	assert_true(operation.get_result().is_successful())


func test_cleanup_runner_releases_signal_and_storage_after_normal_terminal() -> void:
	var storage: ControllableDeleteStorage = ControllableDeleteStorage.new()
	var manifest: ChunkManifest = _make_sixty_three_chunk_manifest(
		ChunkManifest.BANK_A
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.after_exact_commit(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			ChunkManifest.BANK_NONE,
			manifest
		)
	)
	assert_not_null(request)
	if request == null:
		return
	var operation: ChunkProfileCleanupOperation = ChunkProfileCleanupOperation.new()
	assert_true(operation.configure_for_persistence(&"cleanup.release"))
	var runner: ChunkProfileCleanupRunner = ChunkProfileCleanupRunner.new(storage)
	var runner_weak: WeakRef = weakref(runner)
	var storage_weak: WeakRef = weakref(storage)
	assert_true(runner.start(request, operation))
	for _frame_index: int in range(10):
		if operation.is_completed():
			break
		await get_tree().process_frame
	assert_true(operation.is_completed())
	assert_true(
		operation.cancellation_requested.get_connections().is_empty(),
		"normal terminal 必须显式断开 cancellation signal。"
	)
	# GFStorageUtility 自身 helpers 持有 owner callback；先按其公开生命周期释放，
	# 再验证 runner 没有额外保留 storage。
	storage.dispose()
	runner = null
	storage = null
	await get_tree().process_frame
	assert_true(_weak_ref_is_empty(runner_weak))
	assert_true(_weak_ref_is_empty(storage_weak))


func test_partial_failure_and_not_found_are_typed_and_idempotent() -> void:
	var storage: ControllableDeleteStorage = ControllableDeleteStorage.new()
	var manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_B,
		["candidate".to_utf8_buffer()]
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.discard_candidate(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID,
			manifest
		)
	)
	assert_not_null(request)
	if request == null:
		return
	var failed_identity: ChunkProfileIdentity = request.get_identity(7)
	storage.failure_file = failed_identity.get_file_name()
	var first: ChunkProfileCleanupOperation = await _run_cleanup(
		storage,
		request,
		&"cleanup.partial"
	)
	var first_result: ChunkProfileCleanupResult = first.get_result()
	assert_not_null(first_result)
	if first_result != null:
		assert_true(
			first_result.get_status()
			== ChunkProfileCleanupResult.STATUS_PARTIAL_FAILURE
		)
		assert_true(first_result.get_failed_count() == 1)
		assert_true(first_result.get_not_found_count() == 63)
		assert_true(first_result.get_first_failed_bank() == ChunkManifest.BANK_B)
		assert_true(first_result.get_first_failed_chunk_index() == 7)

	storage.failure_file = ""
	var second: ChunkProfileCleanupOperation = await _run_cleanup(
		storage,
		request,
		&"cleanup.idempotent"
	)
	var second_result: ChunkProfileCleanupResult = second.get_result()
	assert_not_null(second_result)
	if second_result != null:
		assert_true(second_result.is_successful())
		assert_true(second_result.get_not_found_count() == 64)
		assert_true(second_result.get_failed_count() == 0)


func test_explicit_family_cleanup_is_owner_driven_busy_safe_and_idempotent() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_A, 0) == OK)
	assert_true(_seed_chunk(storage, ChunkManifest.BANK_B, 63) == OK)
	var live_lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(live_lease)
	if live_lease == null:
		_dispose_setup(setup)
		return
	var first: ChunkProfileCleanupOperation = utility.cleanup_derived_family_async(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	)
	assert_true(first.is_pending())
	assert_true(_dictionary_int(
		utility.get_debug_snapshot(),
		&"deferred_cleanup_count",
		-1
	) == 1)
	assert_true(utility.is_save_scope_fenced(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_true(_has_chunk(storage, ChunkManifest.BANK_B, 63))
	assert_null(utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	))
	var busy: ChunkProfileCleanupOperation = utility.cleanup_derived_family_async(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	)
	assert_true(busy.is_completed())
	assert_true(
		busy.get_result().get_status() == ChunkProfileCleanupResult.STATUS_BUSY
	)
	for _frame_index: int in range(3):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
	assert_true(first.is_pending())
	assert_not_null(utility.fail_save_lease(
		live_lease.get_lease_id(),
		ERR_SKIP,
		"release explicit cleanup test lease"
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return first.is_completed()
	))
	assert_true(first.get_result().is_successful())
	assert_false(_has_chunk(storage, ChunkManifest.BANK_A, 0))
	assert_false(_has_chunk(storage, ChunkManifest.BANK_B, 63))

	var second: ChunkProfileCleanupOperation = utility.cleanup_derived_family_async(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return second.is_completed()
	))
	var second_result: ChunkProfileCleanupResult = second.get_result()
	assert_true(second_result.is_successful())
	assert_true(second_result.get_total_count() == 128)
	assert_true(second_result.get_not_found_count() == 128)
	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_setup(
	profile_override: GFSaveProfileUtility = null,
	storage_override: GFStorageUtility = null,
	clock_override: GFClock = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	storage.save_dir_name = "gut_chunk_cleanup_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.async_execution_mode = GFStorageUtility.AsyncExecutionMode.COOPERATIVE
	if clock_override != null:
		assert_true(storage.set_async_clock_for_framework(clock_override))
	var profile_utility: GFSaveProfileUtility = (
		profile_override
		if profile_override != null
		else GFSaveProfileUtility.new()
	)
	var chunk_utility: ChunkProfileUtility = ChunkProfileUtility.new()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveProfileUtility, profile_utility)
	await architecture.register_utility(ChunkProfileUtility, chunk_utility)
	assert_true(await architecture.init())
	return {
		&"architecture": architecture,
		&"storage": storage,
		&"chunk_utility": chunk_utility,
	}


func _settle_main(
	utility: ChunkProfileUtility,
	lease: ChunkSaveLease,
	status: StringName,
	requested_generation: int,
	persisted_generation: int
) -> bool:
	var operation: GFSaveProfileOperation = _make_main_operation(
		lease,
		requested_generation
	)
	if operation == null or not lease.bind_main_operation(operation):
		return false
	return _settle_bound_main(
		utility,
		lease,
		operation,
		status,
		requested_generation,
		persisted_generation
	)


func _make_main_operation(
	lease: ChunkSaveLease,
	requested_generation: int
) -> GFSaveProfileOperation:
	if lease == null:
		return null
	var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
	if not operation.configure_save_ownership_for_framework(
		lease.get_main_profile_id(),
		requested_generation,
		0,
		{}
	):
		return null
	if not operation.start_for_framework():
		return null
	return operation


func _settle_bound_main(
	utility: ChunkProfileUtility,
	lease: ChunkSaveLease,
	operation: GFSaveProfileOperation,
	status: StringName,
	requested_generation: int,
	persisted_generation: int
) -> bool:
	if utility == null or lease == null or operation == null:
		return false
	var successful: bool = status == GFSaveProfileResult.STATUS_SAVED
	var error_code: Error = OK if successful else ERR_CANT_CREATE
	if status == GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN:
		error_code = ERR_TIMEOUT
	var result: GFSaveProfileResult = GFSaveProfileResult.new()
	result.configure_for_framework(
		successful,
		status,
		GFSaveProfileOperation.OPERATION_SAVE,
		lease.get_main_profile_id(),
		requested_generation,
		persisted_generation,
		1,
		0,
		1,
		false,
		false,
		&"",
		&"",
		error_code,
		"" if successful else "synthetic main terminal"
	)
	if not operation.complete_for_framework(result):
		return false
	return utility.settle_main_result(
		lease.get_lease_id(),
		operation.get_result()
	) == lease


func _seed_chunk(
	storage: GFStorageUtility,
	bank: StringName,
	chunk_index: int
) -> Error:
	var identity: ChunkProfileIdentity = _make_identity(bank, chunk_index)
	if identity == null:
		return ERR_INVALID_PARAMETER
	return storage.save_data(identity.get_file_name(), {
		&"seed": "%s:%d" % [String(bank), chunk_index],
	})


func _has_chunk(
	storage: GFStorageUtility,
	bank: StringName,
	chunk_index: int
) -> bool:
	var identity: ChunkProfileIdentity = _make_identity(bank, chunk_index)
	return identity != null and storage.has_file(identity.get_file_name())


func _make_identity(
	bank: StringName,
	chunk_index: int
) -> ChunkProfileIdentity:
	return ChunkProfileIdentity.create(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		bank,
		chunk_index
	)


func _assert_identity(
	identity: ChunkProfileIdentity,
	bank: StringName,
	chunk_index: int
) -> void:
	assert_not_null(identity)
	if identity != null:
		assert_true(identity.get_bank() == bank)
		assert_true(identity.get_chunk_index() == chunk_index)


func _make_sixty_three_chunk_manifest(bank: StringName) -> ChunkManifest:
	var chunks: Array[PackedByteArray] = []
	for index: int in range(63):
		chunks.append(("chunk-%d" % index).to_utf8_buffer())
	return ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		bank,
		chunks
	)


func _run_cleanup(
	storage: GFStorageUtility,
	request: ChunkProfileCleanupRequest,
	operation_id: StringName
) -> ChunkProfileCleanupOperation:
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	assert_true(operation.configure_for_persistence(operation_id))
	var runner: ChunkProfileCleanupRunner = ChunkProfileCleanupRunner.new(storage)
	assert_true(runner.start(request, operation))
	for _frame_index: int in range(10):
		if operation.is_completed():
			break
		await get_tree().process_frame
	assert_true(operation.is_completed())
	return operation


func _tick_until(
	architecture: GFArchitecture,
	condition: Callable
) -> bool:
	for _frame_index: int in range(MAXIMUM_TICK_FRAMES):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		var value: Variant = condition.call()
		if value is bool and value:
			return true
	return false


func _dictionary_int(
	payload: Dictionary,
	key: StringName,
	fallback: int
) -> int:
	var value: Variant = payload.get(key, fallback)
	return value if value is int else fallback


func _dictionary_bool(
	payload: Dictionary,
	key: StringName,
	fallback: bool
) -> bool:
	var value: Variant = payload.get(key, fallback)
	return value if value is bool else fallback


func _weak_ref_is_empty(reference: WeakRef) -> bool:
	return reference == null or reference.get_ref() == null


func _dispose_setup(setup: Dictionary) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get(&"architecture")
	return value if value is GFArchitecture else GFArchitecture.new()


func _get_storage(setup: Dictionary) -> GFStorageUtility:
	var value: Variant = setup.get(&"storage")
	return value if value is GFStorageUtility else GFStorageUtility.new()


func _get_chunk_utility(setup: Dictionary) -> ChunkProfileUtility:
	var value: Variant = setup.get(&"chunk_utility")
	return value if value is ChunkProfileUtility else ChunkProfileUtility.new()


# --- 内部类 ---

class MaterializationProbe extends RefCounted:
	var completed: bool = false
	var result: Dictionary = {}

	## @param utility: 执行异步 chunk 物化的测试 Utility。
	## @param main_profile_id: 测试绑定的主 Profile ID。
	## @param main_file_name: 测试绑定的主 Profile 文件名。
	## @param manifest: 指向待物化 chunk 的测试 Manifest。
	func start(
		utility: ChunkProfileUtility,
		main_profile_id: StringName,
		main_file_name: String,
		manifest: ChunkManifest
	) -> void:
		var _deferred: Variant = call_deferred(
			&"_run",
			utility,
			main_profile_id,
			main_file_name,
			manifest
		)

	func _run(
		utility: ChunkProfileUtility,
		main_profile_id: StringName,
		main_file_name: String,
		manifest: ChunkManifest
	) -> void:
		result = await utility.materialize_chunks_async(
			main_profile_id,
			main_file_name,
			manifest
		)
		completed = true


class CleanupSettlementProbe extends RefCounted:
	var utility: ChunkProfileUtility = null
	var last_result: Dictionary = {}

	## @param _operation_id: 已终止清理操作的标识；探针仅使用通知时机。
	func on_cleanup_settled(_operation_id: StringName) -> void:
		if utility == null:
			return
		last_result = GFVariantData.get_option_dictionary(
			utility.get_debug_snapshot(),
			&"last_cleanup_result"
		)


class CleanupFenceWaitProbe extends RefCounted:
	var completed: bool = false


	## @param utility: 要等待其保存围栏解除的测试 Utility。
	func start(utility: ChunkProfileUtility) -> void:
		var _deferred: Variant = call_deferred(&"_run", utility)


	func _run(utility: ChunkProfileUtility) -> void:
		if utility == null:
			return
		while utility.is_save_scope_fenced(
			MAIN_PROFILE_ID,
			MAIN_FILE_NAME,
			SECTION_ID
		):
			var _operation_id: StringName = (
				await utility.cleanup_operation_settled
			)
		completed = true


class FailingChunkProfileUtility extends GFSaveProfileUtility:
	var save_calls: int = 0

	## @param profile_id: 要模拟保存失败的 Profile ID。
	## @param _request: 未被此失败桩使用的保存请求。
	func save_profile(
		profile_id: StringName,
		_request: GFSaveProfileRequest = null
	) -> GFSaveProfileOperation:
		save_calls += 1
		var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
		var _configured: bool = operation.configure_save_ownership_for_framework(
			profile_id,
			1,
			0,
			{}
		)
		var _started: bool = operation.start_for_framework()
		var result: GFSaveProfileResult = GFSaveProfileResult.new()
		result.configure_for_framework(
			false,
			GFSaveProfileResult.STATUS_STORAGE_FAILED,
			GFSaveProfileOperation.OPERATION_SAVE,
			profile_id,
			1,
			0,
			1,
			0,
			1,
			false,
			false,
			&"",
			&"",
			ERR_CANT_CREATE,
			"synthetic known stage failure"
		)
		var _completed: bool = operation.complete_for_framework(result)
		return operation


class DeferredChunkLoadProfileUtility extends GFSaveProfileUtility:
	var _pending_operation: GFSaveProfileOperation = null
	var _pending_sink: ChunkProfileLoadSink = null
	var _pending_profile_id: StringName = &""

	## @param profile_id: 要延迟完成加载的 Profile ID。
	## @param context: 包含测试 chunk load sink 的加载上下文。
	## @param metadata: 透传给测试操作的加载元数据。
	func load_profile(
		profile_id: StringName,
		context: Dictionary = {},
		metadata: Dictionary = {}
	) -> GFSaveProfileOperation:
		if _pending_operation != null:
			return null
		var sink_value: Variant = context.get(
			ChunkBlobSaveSectionProvider.LOAD_SINK_CONTEXT_KEY
		)
		if not sink_value is ChunkProfileLoadSink:
			return null
		var sink: ChunkProfileLoadSink = sink_value
		var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
		if not operation.configure_for_framework(
			GFSaveProfileOperation.OPERATION_LOAD,
			profile_id,
			0,
			0,
			context,
			metadata
		):
			return null
		if not operation.start_for_framework():
			return null
		_pending_operation = operation
		_pending_sink = sink
		_pending_profile_id = profile_id
		return operation

	func has_pending_load() -> bool:
		return _pending_operation != null

	## @param payload: 写入待决 load sink 的测试 chunk 字节。
	func complete_pending_load(payload: PackedByteArray) -> bool:
		if _pending_operation == null or _pending_sink == null:
			return false
		if _pending_sink.write_once(payload) != OK:
			return false
		var result: GFSaveProfileResult = GFSaveProfileResult.new()
		result.configure_for_framework(
			true,
			GFSaveProfileResult.STATUS_LOADED,
			GFSaveProfileOperation.OPERATION_LOAD,
			_pending_profile_id,
			0,
			0,
			1,
			0,
			1
		)
		var operation: GFSaveProfileOperation = _pending_operation
		_pending_operation = null
		_pending_sink = null
		_pending_profile_id = &""
		if not operation.complete_for_framework(result):
			return false
		return operation.emit_completed_for_framework()


class ReconciledMainProfileUtility extends GFSaveProfileUtility:
	var snapshot_persisted_generation: int = 0

	## @param profile_id: 要查询持久化 generation 的 Profile ID。
	func get_profile_state_snapshot(profile_id: StringName) -> Dictionary:
		if profile_id == MAIN_PROFILE_ID:
			return {
				&"profile_id": profile_id,
				&"state": GFSaveProfileUtility.STATE_IDLE,
				&"persisted_generation": snapshot_persisted_generation,
				&"save_queue_size": 0,
				&"load_queue_size": 0,
				&"flush_queue_size": 0,
				&"write_outcome_unknown": false,
				&"unknown_write_generations": PackedInt64Array(),
				&"detached_write_count": 0,
				&"detached_storage_request_ids": PackedInt64Array(),
			}
		return super.get_profile_state_snapshot(profile_id)


class ConnectFailureCleanupRunner extends ChunkProfileCleanupRunner:
	var physical_connect_attempt_count: int = 0


	func _init(storage: GFStorageUtility) -> void:
		super(storage)


	func _connect_delete_physical_completed(
		_delete_operation: GFStorageAsyncOperation,
		_handle_id: int
	) -> Error:
		physical_connect_attempt_count += 1
		return ERR_CANT_CONNECT


class ConnectFailurePollingStorage extends GFStorageUtility:
	var _pending_operation: GFStorageAsyncOperation = null
	var _pending_result: GFStorageAsyncResult = null
	var _next_request_id: int = 6_900_000


	## @param file_name: 要创建待轮询删除结果的测试文件名。
	## @param options: 可选的异步删除请求选项。
	func delete_file_request_async(
		file_name: String,
		options: GFStorageAsyncRequestOptions = null
	) -> GFStorageAsyncOperation:
		if _pending_operation != null:
			return null
		var request_id: int = _next_request_id
		_next_request_id += 1
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name
		)
		var effective_options: GFStorageAsyncRequestOptions = (
			options
			if options != null
			else GFStorageAsyncRequestOptions.create(self)
		)
		var _consumer_configured: bool = (
			operation.configure_consumer_for_framework(
				request_id,
				effective_options,
				GFClock.new(),
				Callable(self, &"_accept_cancel")
			)
		)
		var _accepted: bool = operation.mark_worker_accepted_for_framework()
		var delete_result: GFStorageDeleteResult = GFStorageDeleteResult.new()
		var _delete_configured: bool = delete_result.configure_for_framework(
			OK,
			GFStorageDeleteResult.FailureKind.NONE,
			1,
			1,
			0,
			GFStorageDeleteResult.FamilyMember.NONE
		)
		var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
		var _result_configured: bool = result.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name,
			true,
			OK,
			null,
			GFStorageAsyncResult.WriteFailureKind.NONE,
			{},
			delete_result
		)
		_pending_operation = operation
		_pending_result = result
		return operation


	func settle_pending() -> bool:
		if _pending_operation == null or _pending_result == null:
			return false
		var operation: GFStorageAsyncOperation = _pending_operation
		var result: GFStorageAsyncResult = _pending_result
		_pending_operation = null
		_pending_result = null
		return operation.complete_for_framework(result)


	func _accept_cancel(
		_operation: GFStorageAsyncOperation,
		_end_kind: int,
		_reason: StringName
	) -> bool:
		return true


class ControllableDeleteStorage extends GFStorageUtility:
	var late_success_file: String = ""
	var failure_file: String = ""
	var calls: PackedStringArray = PackedStringArray()
	var _late_operation: GFStorageAsyncOperation = null
	var _late_result: GFStorageAsyncResult = null
	var _next_request_id: int = 7_000_000

	## @param file_name: 要按脚本结果删除的测试文件名。
	## @param options: 可选的异步删除请求选项。
	func delete_file_request_async(
		file_name: String,
		options: GFStorageAsyncRequestOptions = null
	) -> GFStorageAsyncOperation:
		var _call_recorded: bool = calls.append(file_name)
		var request_id: int = _next_request_id
		_next_request_id += 1
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name
		)
		var effective_options: GFStorageAsyncRequestOptions = (
			options
			if options != null
			else GFStorageAsyncRequestOptions.create(self)
		)
		var _consumer_configured: bool = operation.configure_consumer_for_framework(
			request_id,
			effective_options,
			GFClock.new(),
			Callable(self, &"_accept_cancel")
		)
		var _accepted: bool = operation.mark_worker_accepted_for_framework()
		var error_code: Error = (
			ERR_CANT_CREATE
			if file_name == failure_file
			else (
				OK if file_name == late_success_file else ERR_FILE_NOT_FOUND
			)
		)
		var failure_kind: GFStorageDeleteResult.FailureKind = (
			GFStorageDeleteResult.FailureKind.IO_FAILED
			if error_code == ERR_CANT_CREATE
			else (
				GFStorageDeleteResult.FailureKind.NONE
				if error_code == OK
				else GFStorageDeleteResult.FailureKind.NOT_FOUND
			)
		)
		var delete_result: GFStorageDeleteResult = GFStorageDeleteResult.new()
		var existing_count: int = 1 if error_code in [OK, ERR_CANT_CREATE] else 0
		var _delete_configured: bool = delete_result.configure_for_framework(
			error_code,
			failure_kind,
			existing_count,
			1 if error_code == OK else 0,
			1 if error_code == ERR_CANT_CREATE else 0,
			(
				GFStorageDeleteResult.FamilyMember.FINAL
				if error_code == ERR_CANT_CREATE
				else GFStorageDeleteResult.FamilyMember.NONE
			)
		)
		var physical_result: GFStorageAsyncResult = GFStorageAsyncResult.new()
		var _physical_configured: bool = physical_result.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name,
			error_code == OK,
			error_code,
			null,
			GFStorageAsyncResult.WriteFailureKind.NONE,
			{},
			delete_result
		)
		if file_name == late_success_file:
			var _caller_unknown: bool = operation.complete_caller_for_framework(
				GFStorageAsyncCallerResult.Status.OUTCOME_UNKNOWN,
				GFStorageAsyncCallerResult.EndKind.DEADLINE_EXPIRED,
				&"deadline_expired"
			)
			_late_operation = operation
			_late_result = physical_result
		else:
			var _completed: bool = operation.complete_for_framework(physical_result)
		return operation

	func settle_late_success() -> bool:
		if _late_operation == null or _late_result == null:
			return false
		var operation: GFStorageAsyncOperation = _late_operation
		var result: GFStorageAsyncResult = _late_result
		_late_operation = null
		_late_result = null
		return operation.complete_for_framework(result)

	func _accept_cancel(
		_operation: GFStorageAsyncOperation,
		_end_kind: int,
		_reason: StringName
	) -> bool:
		return true
