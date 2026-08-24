## 验证 ChunkProfileUtility 的可信身份、staging、物化与注销边界。
extends GutTest


# --- 常量 ---

const MAIN_PROFILE_ID: StringName = &"player_data.chunk_utility_test"
const MAIN_FILE_NAME: String = "profiles/chunk_utility_test.save"
const SECTION_ID: StringName = &"bookmarks"
const SECTION_SCHEMA_VERSION: int = 10
const PRODUCER_REVISION: int = 3
const MAIN_GENERATION: int = 1
const OTHER_SECTION_ID: StringName = &"custom_boards"
const MAXIMUM_TICK_FRAMES: int = 360


# --- 测试用例 ---

func test_create_save_lease_uses_trusted_identity_and_unique_ids() -> void:
	var setup: Dictionary = await _create_setup()
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var first: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	var second: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	assert_not_null(first)
	assert_not_null(second)
	if first != null and second != null:
		assert_false(first.get_lease_id() == second.get_lease_id())
		assert_true(utility.get_save_lease(first.get_lease_id()) == first)
		assert_true(first.get_main_profile_id() == MAIN_PROFILE_ID)
		assert_true(first.get_main_profile_file() == MAIN_FILE_NAME)
	assert_null(utility.create_save_lease(
		MAIN_PROFILE_ID,
		"../untrusted.save",
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	))
	_dispose_setup(setup)


func test_registration_failure_settles_lease_without_starting_profile_save() -> void:
	var rejecting: RejectingProfileUtility = RejectingProfileUtility.new()
	var setup: Dictionary = await _create_setup(rejecting)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var probe: LeaseSettlementProbe = LeaseSettlementProbe.new()
	probe.utility = utility
	var connect_error: int = utility.save_lease_settled.connect(
		probe.on_lease_settled
	)
	assert_true(connect_error == OK)
	var lease: ChunkSaveLease = _make_ready_lease(utility, [
		"first".to_utf8_buffer(),
	])
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	var architecture: GFArchitecture = _get_architecture(setup)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.get_status() == ChunkSaveLease.STATUS_FAILED
	))
	assert_true(rejecting.registration_calls == 1)
	assert_true(rejecting.save_calls == 0)
	assert_true(probe.settled_ids == [lease.get_lease_id()])
	assert_true(probe.observed_lease_in_signal)
	assert_true(
		probe.observed_status == ChunkSaveLease.STATUS_FAILED
	)
	assert_null(utility.get_save_lease(lease.get_lease_id()))
	var snapshot: Dictionary = utility.get_debug_snapshot()
	assert_true(_dictionary_int(snapshot, &"lease_count", -1) == 0)
	assert_true(_dictionary_int(snapshot, &"lease_scope_count", -1) == 0)
	assert_true(_dictionary_int(snapshot, &"settled_notification_count", -1) == 0)
	assert_true(_dictionary_int(snapshot, &"registered_profile_count", -1) == 0)
	_dispose_setup(setup)


func test_quiesce_stops_admission_and_settles_not_started_leases() -> void:
	var setup: Dictionary = await _create_setup()
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
	var completion: GFAsyncCompletion = utility.begin_quiesce(
		GFAsyncScope.new()
	)
	assert_true(completion.is_completed())
	assert_true(completion.is_successful())
	assert_true(lease.get_status() == ChunkSaveLease.STATUS_FAILED)
	assert_null(utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	))
	_dispose_setup(setup)


func test_fail_save_lease_releases_indexes_after_signal_window() -> void:
	var setup: Dictionary = await _create_setup()
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var probe: LeaseSettlementProbe = LeaseSettlementProbe.new()
	probe.utility = utility
	var connect_error: int = utility.save_lease_settled.connect(
		probe.on_lease_settled
	)
	assert_true(connect_error == OK)
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
	var settled: ChunkSaveLease = utility.fail_save_lease(
		lease.get_lease_id(),
		ERR_INVALID_DATA,
		"Sibling lease admission failed."
	)
	assert_true(settled == lease)
	assert_true(probe.observed_lease_in_signal)
	assert_true(probe.observed_status == ChunkSaveLease.STATUS_FAILED)
	assert_null(utility.get_save_lease(lease.get_lease_id()))
	var snapshot: Dictionary = utility.get_debug_snapshot()
	assert_true(_dictionary_int(snapshot, &"lease_count", -1) == 0)
	assert_true(_dictionary_int(snapshot, &"lease_scope_count", -1) == 0)
	assert_true(_dictionary_int(snapshot, &"settled_notification_count", -1) == 0)
	assert_null(utility.fail_save_lease(
		lease.get_lease_id(),
		ERR_INVALID_DATA,
		"Duplicate failure must be rejected."
	))
	_dispose_setup(setup)


func test_exact_commit_rebases_waiting_and_ready_siblings_before_next_stage() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var committing_lease: ChunkSaveLease = _make_ready_lease(utility, [
		"committed-a".to_utf8_buffer(),
	])
	assert_not_null(committing_lease)
	if committing_lease == null:
		_dispose_setup(setup)
		return
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return committing_lease.is_staged()
	))
	var owner_manifest: ChunkManifest = committing_lease.claim_manifest_for_provider()
	assert_true(
		owner_manifest != null
		and owner_manifest.get_bank() == ChunkManifest.BANK_A
	)
	if owner_manifest == null:
		_dispose_setup(setup)
		return

	var waiting_sibling: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	var ready_sibling: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 2
	)
	assert_not_null(waiting_sibling)
	assert_not_null(ready_sibling)
	if waiting_sibling == null or ready_sibling == null:
		_delete_chunk_files(setup, owner_manifest)
		_dispose_setup(setup)
		return
	assert_true(ready_sibling.offer_chunks_taking_ownership(
		["ready-froze-no-active-bank".to_utf8_buffer()],
		PRODUCER_REVISION + 2,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	))

	var main_operation: GFSaveProfileOperation = _make_main_operation(
		MAIN_PROFILE_ID,
		MAIN_GENERATION
	)
	assert_not_null(main_operation)
	if (
		main_operation == null
		or not committing_lease.bind_main_operation(main_operation)
	):
		_delete_chunk_files(setup, owner_manifest)
		_dispose_setup(setup)
		return
	var success: GFSaveProfileResult = _make_main_result(
		GFSaveProfileResult.STATUS_SAVED,
		MAIN_PROFILE_ID,
		MAIN_GENERATION,
		MAIN_GENERATION
	)
	var real_result: GFSaveProfileResult = _complete_main_operation(
		main_operation,
		success
	)
	assert_not_null(real_result)
	if real_result == null:
		_delete_chunk_files(setup, owner_manifest)
		_dispose_setup(setup)
		return
	assert_true(
		utility.settle_main_result(
			committing_lease.get_lease_id(),
			real_result
		) == committing_lease
	)
	assert_true(
		committing_lease.get_status() == ChunkSaveLease.STATUS_COMMITTED
	)
	assert_null(utility.get_save_lease(committing_lease.get_lease_id()))
	assert_true(
		waiting_sibling.matches_scope_basis_for_utility(
			ChunkManifest.BANK_A,
			1
		),
		"exact commit 必须在释放 scope owner 前推进 WAITING sibling basis。"
	)
	assert_true(
		ready_sibling.matches_scope_basis_for_utility(
			ChunkManifest.BANK_A,
			1
		),
		"exact commit 必须重写 READY sibling 冻结的旧 active bank。"
	)
	assert_true(
		_dictionary_int(
			utility.get_debug_snapshot(),
			&"scope_basis_count",
			-1
		) == 1
	)

	assert_true(await _tick_until(
		architecture,
		func() -> bool: return ready_sibling.is_staged()
	))
	var sibling_manifest: ChunkManifest = (
		ready_sibling.claim_manifest_for_provider()
	)
	assert_true(
		sibling_manifest != null
		and sibling_manifest.get_bank() == ChunkManifest.BANK_B,
		"后续 READY save 必须 stage 到新 active A 的另一 bank B。"
	)
	var _failed_ready: ChunkSaveLease = utility.fail_save_lease(
		ready_sibling.get_lease_id(),
		ERR_SKIP,
		"test cleanup"
	)
	var _failed_waiting: ChunkSaveLease = utility.fail_save_lease(
		waiting_sibling.get_lease_id(),
		ERR_SKIP,
		"test cleanup"
	)
	assert_true(
		_dictionary_int(
			utility.get_debug_snapshot(),
			&"scope_basis_count",
			-1
		) == 1,
		"exact commit basis 必须跨越无 live lease 窗口，防止 parked dirty 重用旧 bank。"
	)
	_delete_chunk_files(setup, owner_manifest)
	if sibling_manifest != null:
		_delete_chunk_files(setup, sibling_manifest)
	_dispose_setup(setup)


func test_exact_commit_basis_survives_empty_queue_for_later_parked_save() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var stale_provider_manifest: ChunkManifest = ChunkManifest.create(
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		["previous-visible-a".to_utf8_buffer()]
	)
	assert_not_null(stale_provider_manifest)
	if stale_provider_manifest == null:
		_dispose_setup(setup)
		return

	var committing_lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	assert_not_null(committing_lease)
	if committing_lease == null:
		_dispose_setup(setup)
		return
	assert_true(committing_lease.offer_chunks_taking_ownership(
		["late-committed-b".to_utf8_buffer()],
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		stale_provider_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return committing_lease.is_staged()
	))
	var committed_manifest: ChunkManifest = (
		committing_lease.claim_manifest_for_provider()
	)
	assert_true(
		committed_manifest != null
		and committed_manifest.get_bank() == ChunkManifest.BANK_B
	)
	if committed_manifest == null:
		_dispose_setup(setup)
		return
	var main_operation: GFSaveProfileOperation = _make_main_operation(
		MAIN_PROFILE_ID,
		MAIN_GENERATION
	)
	assert_not_null(main_operation)
	if (
		main_operation == null
		or not committing_lease.bind_main_operation(main_operation)
	):
		_delete_chunk_files(setup, committed_manifest)
		_dispose_setup(setup)
		return
	var real_result: GFSaveProfileResult = _complete_main_operation(
		main_operation,
		_make_main_result(
			GFSaveProfileResult.STATUS_SAVED,
			MAIN_PROFILE_ID,
			MAIN_GENERATION,
			MAIN_GENERATION
		)
	)
	assert_not_null(real_result)
	if real_result == null:
		_delete_chunk_files(setup, committed_manifest)
		_dispose_setup(setup)
		return
	assert_true(
		utility.settle_main_result(
			committing_lease.get_lease_id(),
			real_result
		) == committing_lease
	)
	assert_null(
		utility.get_save_lease(committing_lease.get_lease_id()),
		"settlement 后应先出现无 live lease 窗口。"
	)

	var fenced_lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	assert_null(
		fenced_lease,
		"exact commit 的 cleanup 尚未获得物理终态时不得复用 scope。"
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return not utility.is_save_scope_fenced(
				MAIN_PROFILE_ID,
				MAIN_FILE_NAME,
				SECTION_ID
			)
	))
	var later_lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION + 1
	)
	assert_not_null(later_lease)
	if later_lease == null:
		_delete_chunk_files(setup, committed_manifest)
		_dispose_setup(setup)
		return
	assert_true(
		later_lease.matches_scope_basis_for_utility(
			ChunkManifest.BANK_B,
			1
		),
		"parked save 之后新建 lease 必须继承无队列窗口前的 exact B basis。"
	)
	assert_true(later_lease.offer_chunks_taking_ownership(
		["parked-newer-a".to_utf8_buffer()],
		PRODUCER_REVISION + 1,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		stale_provider_manifest
	))
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return later_lease.is_staged()
	))
	var later_manifest: ChunkManifest = (
		later_lease.claim_manifest_for_provider()
	)
	assert_true(
		later_manifest != null
		and later_manifest.get_bank() == ChunkManifest.BANK_A,
		"Provider 仍暴露旧 A 时，stage-time basis 必须将新保存重定向到 A，不得覆盖已可见 B。"
	)
	var _failed_later: ChunkSaveLease = utility.fail_save_lease(
		later_lease.get_lease_id(),
		ERR_SKIP,
		"test cleanup"
	)
	_delete_chunk_files(setup, committed_manifest)
	if later_manifest != null:
		_delete_chunk_files(setup, later_manifest)
	_dispose_setup(setup)


func test_stage_then_materialize_preserves_order_and_unregisters_profiles() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var source_chunks: Array[PackedByteArray] = [
		"first-chunk".to_utf8_buffer(),
		"second-chunk".to_utf8_buffer(),
	]
	var lease: ChunkSaveLease = _make_ready_lease(utility, source_chunks)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	var manifest: ChunkManifest = lease.claim_manifest_for_provider()
	assert_not_null(manifest)
	if manifest == null:
		_dispose_setup(setup)
		return
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"registered_profile_count",
				-1
			) == 0
	))

	var materialization: MaterializationProbe = MaterializationProbe.new()
	materialization.start(
		utility,
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		manifest
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return materialization.completed
	))
	var result: Dictionary = materialization.result
	assert_true(_dictionary_bool(result, &"ok", false))
	var chunks_value: Variant = result.get(&"chunks")
	assert_true(chunks_value is Array)
	if chunks_value is Array:
		var chunks: Array = chunks_value
		assert_true(chunks.size() == 2)
		if chunks.size() == 2:
			assert_true(chunks[0] is PackedByteArray)
			assert_true(chunks[1] is PackedByteArray)
			if chunks[0] is PackedByteArray and chunks[1] is PackedByteArray:
				var first_chunk: PackedByteArray = chunks[0]
				var second_chunk: PackedByteArray = chunks[1]
				assert_true(
					first_chunk.get_string_from_utf8() == "first-chunk"
				)
				assert_true(
					second_chunk.get_string_from_utf8() == "second-chunk"
				)
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"registered_profile_count",
				-1
			) == 0
	))
	_assert_chunk_profiles_unregistered(setup, manifest)
	_delete_chunk_files(setup, manifest)
	_dispose_setup(setup)


func test_materialize_digest_mismatch_returns_no_partial_chunks() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var utility: ChunkProfileUtility = _get_chunk_utility(setup)
	var source_chunks: Array[PackedByteArray] = [
		"digest-source".to_utf8_buffer(),
		"must-not-leak".to_utf8_buffer(),
	]
	var lease: ChunkSaveLease = _make_ready_lease(utility, source_chunks)
	assert_not_null(lease)
	if lease == null:
		_dispose_setup(setup)
		return
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return lease.is_staged()
	))
	var manifest: ChunkManifest = lease.claim_manifest_for_provider()
	assert_not_null(manifest)
	if manifest == null:
		_dispose_setup(setup)
		return
	var tampered_payload: Dictionary = manifest.to_dict()
	var descriptors_value: Variant = tampered_payload.get(&"chunks")
	assert_true(descriptors_value is Array)
	if not descriptors_value is Array:
		_delete_chunk_files(setup, manifest)
		_dispose_setup(setup)
		return
	var descriptors: Array = descriptors_value
	var first_value: Variant = descriptors[0]
	assert_true(first_value is Dictionary)
	if not first_value is Dictionary:
		_delete_chunk_files(setup, manifest)
		_dispose_setup(setup)
		return
	var first_descriptor: Dictionary = first_value
	first_descriptor[&"sha256"] = "0".repeat(64)
	var tampered_manifest: ChunkManifest = ChunkManifest.from_dict(
		tampered_payload
	)
	assert_not_null(tampered_manifest)
	if tampered_manifest == null:
		_delete_chunk_files(setup, manifest)
		_dispose_setup(setup)
		return

	var materialization: MaterializationProbe = MaterializationProbe.new()
	materialization.start(
		utility,
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		tampered_manifest
	)
	assert_true(await _tick_until(
		architecture,
		func() -> bool: return materialization.completed
	))
	assert_false(_dictionary_bool(materialization.result, &"ok", true))
	assert_true(
		_dictionary_int(materialization.result, &"error_code", OK)
		== ERR_FILE_CORRUPT
	)
	var chunks_value: Variant = materialization.result.get(&"chunks")
	assert_true(chunks_value is Array)
	if chunks_value is Array:
		var failed_chunks: Array = chunks_value
		assert_true(failed_chunks.is_empty())
	assert_true(await _tick_until(
		architecture,
		func() -> bool:
			return _dictionary_int(
				utility.get_debug_snapshot(),
				&"registered_profile_count",
				-1
			) == 0
	))
	_assert_chunk_profiles_unregistered(setup, manifest)
	_delete_chunk_files(setup, manifest)
	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_setup(
	profile_override: GFSaveProfileUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	storage.save_dir_name = "gut_chunk_profile_utility_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.async_execution_mode = (
		GFStorageUtility.AsyncExecutionMode.COOPERATIVE
	)
	var profile_utility: GFSaveProfileUtility = (
		profile_override
		if profile_override != null
		else GFSaveProfileUtility.new()
	)
	var chunk_utility: ChunkProfileUtility = ChunkProfileUtility.new()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFSaveProfileUtility,
		profile_utility
	)
	await architecture.register_utility(ChunkProfileUtility, chunk_utility)
	var initialized: bool = await architecture.init()
	assert_true(initialized)
	return {
		&"architecture": architecture,
		&"storage": storage,
		&"profile_utility": profile_utility,
		&"chunk_utility": chunk_utility,
	}


func _make_ready_lease(
	utility: ChunkProfileUtility,
	chunks: Array[PackedByteArray]
) -> ChunkSaveLease:
	var lease: ChunkSaveLease = utility.create_save_lease(
		MAIN_PROFILE_ID,
		MAIN_FILE_NAME,
		SECTION_ID,
		SECTION_SCHEMA_VERSION,
		PRODUCER_REVISION
	)
	if lease == null:
		return null
	if not lease.offer_chunks_taking_ownership(
		chunks,
		PRODUCER_REVISION,
		SECTION_ID,
		SECTION_SCHEMA_VERSION
	):
		return null
	return lease


func _make_main_operation(
	profile_id: StringName,
	requested_generation: int
) -> GFSaveProfileOperation:
	var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
	if not operation.configure_save_ownership_for_framework(
		profile_id,
		requested_generation,
		0,
		{}
	):
		return null
	if not operation.start_for_framework():
		return null
	return operation


func _make_main_result(
	status: StringName,
	profile_id: StringName,
	requested_generation: int,
	persisted_generation: int
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
		false,
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


func _tick_until(
	architecture: GFArchitecture,
	condition: Callable
) -> bool:
	for _frame_index: int in range(MAXIMUM_TICK_FRAMES):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		var condition_result: Variant = condition.call()
		if condition_result is bool and condition_result:
			return true
	return false


func _dictionary_int(
	payload: Dictionary,
	key: StringName,
	default_value: int
) -> int:
	var value: Variant = payload.get(key, default_value)
	if value is int:
		return value
	return default_value


func _dictionary_bool(
	payload: Dictionary,
	key: StringName,
	default_value: bool
) -> bool:
	var value: Variant = payload.get(key, default_value)
	if value is bool:
		return value
	return default_value


func _assert_chunk_profiles_unregistered(
	setup: Dictionary,
	manifest: ChunkManifest
) -> void:
	var profile_utility: GFSaveProfileUtility = _get_profile_utility(setup)
	for chunk_index: int in range(manifest.get_chunk_count()):
		var identity: ChunkProfileIdentity = (
			ChunkProfileRuntimeFactory.make_identity(
				MAIN_PROFILE_ID,
				MAIN_FILE_NAME,
				manifest.get_section_id(),
				manifest.get_bank(),
				chunk_index
			)
		)
		assert_not_null(identity)
		if identity != null:
			assert_true(
				profile_utility.get_profile_state_snapshot(
					identity.get_profile_id()
				).is_empty()
			)


func _delete_chunk_files(setup: Dictionary, manifest: ChunkManifest) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	for chunk_index: int in range(manifest.get_chunk_count()):
		var identity: ChunkProfileIdentity = (
			ChunkProfileRuntimeFactory.make_identity(
				MAIN_PROFILE_ID,
				MAIN_FILE_NAME,
				manifest.get_section_id(),
				manifest.get_bank(),
				chunk_index
			)
		)
		if identity == null:
			continue
		var delete_error: Error = storage.delete_file(identity.get_file_name())
		assert_true(delete_error == OK or delete_error == ERR_FILE_NOT_FOUND)


func _dispose_setup(setup: Dictionary) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get(&"architecture")
	if value is GFArchitecture:
		return value
	return GFArchitecture.new()


func _get_storage(setup: Dictionary) -> GFStorageUtility:
	var value: Variant = setup.get(&"storage")
	if value is GFStorageUtility:
		return value
	return GFStorageUtility.new()


func _get_profile_utility(setup: Dictionary) -> GFSaveProfileUtility:
	var value: Variant = setup.get(&"profile_utility")
	if value is GFSaveProfileUtility:
		return value
	return GFSaveProfileUtility.new()


func _get_chunk_utility(setup: Dictionary) -> ChunkProfileUtility:
	var value: Variant = setup.get(&"chunk_utility")
	if value is ChunkProfileUtility:
		return value
	return ChunkProfileUtility.new()


# --- 内部类 ---

class MaterializationProbe extends RefCounted:
	var completed: bool = false
	var result: Dictionary = {}

	## @param utility: 执行异步 chunk 物化的项目 Utility。
	## @param main_profile_id: 用于派生 chunk 身份的可信主 Profile ID。
	## @param main_file_name: 用于派生 chunk 身份的可信主 Profile 文件名。
	## @param manifest: 描述待读取 bank 与 chunk 摘要的严格 Manifest。
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


class LeaseSettlementProbe extends RefCounted:
	var utility: ChunkProfileUtility = null
	var settled_ids: Array[StringName] = []
	var observed_lease_in_signal: bool = false
	var observed_status: StringName = &""

	## @param lease_id: Utility 在信号窗口内仍可查询的已结算 lease ID。
	func on_lease_settled(lease_id: StringName) -> void:
		settled_ids.append(lease_id)
		if utility == null:
			return
		var lease: ChunkSaveLease = utility.get_save_lease(lease_id)
		observed_lease_in_signal = lease != null
		if lease != null:
			observed_status = lease.get_status()


class RejectingProfileUtility extends GFSaveProfileUtility:
	var registration_calls: int = 0
	var save_calls: int = 0

	## @param _profile: 被测试替身拒绝注册的 Profile。
	## @param _migrations: 被测试替身忽略的可选迁移注册表。
	func register_profile(
		_profile: GFSaveProfile,
		_migrations: GFSaveMigrationRegistry = null
	) -> Dictionary:
		registration_calls += 1
		return {
			&"registered": false,
			&"issues": [],
		}

	## @param _profile_id: 替身不会执行保存的 Profile ID。
	## @param _request: 替身不会执行的可选 Profile 保存请求。
	func save_profile(
		_profile_id: StringName,
		_request: GFSaveProfileRequest = null
	) -> GFSaveProfileOperation:
		save_calls += 1
		return null
