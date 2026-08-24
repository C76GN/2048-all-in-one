## 验证小型 chunk GF Profile runtime Adapter 的身份、所有权和 Provider 契约。
extends GutTest


# --- 测试用例 ---

func test_identity_is_deterministic_and_isolates_trusted_main_profiles() -> void:
	var first: ChunkProfileIdentity = ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	)
	var repeated: ChunkProfileIdentity = ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	)
	var other_profile: ChunkProfileIdentity = ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_b",
		"profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	)
	var other_file: ChunkProfileIdentity = ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_b.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	)
	assert_not_null(first)
	assert_not_null(repeated)
	assert_not_null(other_profile)
	assert_not_null(other_file)
	if first == null or repeated == null or other_profile == null or other_file == null:
		return
	assert_true(first.get_profile_id() == repeated.get_profile_id())
	assert_true(first.get_file_name() == repeated.get_file_name())
	assert_false(first.get_profile_id() == other_profile.get_profile_id())
	assert_false(first.get_file_name() == other_profile.get_file_name())
	assert_false(first.get_profile_id() == other_file.get_profile_id())
	assert_false(first.get_file_name() == other_file.get_file_name())
	assert_true(first.get_file_name().begins_with("chunk_profiles/"))
	assert_true(first.get_file_name().ends_with("/bookmarks/a/000000.save"))


func test_identity_rejects_untrusted_paths_banks_and_indices() -> void:
	assert_null(ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"../profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	))
	assert_null(ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"../bookmarks",
		ChunkProfileIdentity.BANK_A,
		0
	))
	assert_null(ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"bookmarks",
		&"active",
		0
	))
	assert_null(ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_B,
		-1
	))
	assert_null(ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"bookmarks",
		ChunkProfileIdentity.BANK_B,
		ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
	))


func test_factory_builds_one_strict_blob_profile() -> void:
	var identity: ChunkProfileIdentity = ChunkProfileRuntimeFactory.make_identity(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"progress",
		ChunkProfileIdentity.BANK_B,
		7
	)
	var profile: GFSaveProfile = ChunkProfileRuntimeFactory.make_profile(
		&"player_data.account_a",
		"profiles/account_a.save",
		&"progress",
		ChunkProfileIdentity.BANK_B,
		7
	)
	assert_not_null(identity)
	assert_not_null(profile)
	if identity == null or profile == null:
		return
	assert_true(profile.profile_id == identity.get_profile_id())
	assert_true(profile.file_name == identity.get_file_name())
	assert_true(profile.schema_id == ChunkProfileRuntimeFactory.PROFILE_SCHEMA_ID)
	assert_true(profile.providers.size() == 1)
	assert_true(
		profile.get_provider(ChunkBlobSaveSectionProvider.SECTION_ID)
		is ChunkBlobSaveSectionProvider
	)
	assert_true(
		profile.recovery_policy.missing_file_action
		== GFSaveRecoveryPolicy.ACTION_FAIL
	)
	assert_true(
		profile.recovery_policy.corrupt_file_action
		== GFSaveRecoveryPolicy.ACTION_FAIL
	)
	assert_true(
		profile.unknown_section_policy == GFSaveProfile.UNKNOWN_SECTION_REJECT
	)
	var validation: Dictionary = profile.validate_profile()
	var validation_ok_value: Variant = validation.get("ok")
	assert_true(validation_ok_value is bool)
	if validation_ok_value is bool:
		var validation_ok: bool = validation_ok_value
		assert_true(validation_ok)


func test_save_lease_and_load_sink_are_single_claim() -> void:
	var lease: ChunkProfileSaveLease = ChunkProfileSaveLease.take_ownership(
		"chunk-payload".to_utf8_buffer()
	)
	assert_not_null(lease)
	if lease == null:
		return
	assert_true(lease.is_available())
	var claimed_save: PackedByteArray = lease.claim()
	assert_true(claimed_save.get_string_from_utf8() == "chunk-payload")
	assert_true(lease.is_claimed())
	assert_true(lease.claim().is_empty())
	assert_null(ChunkProfileSaveLease.take_ownership(PackedByteArray()))
	var oversized: PackedByteArray = PackedByteArray()
	assert_true(
		oversized.resize(ChunkProfileSaveLease.MAX_PAYLOAD_BYTES + 1) == OK
	)
	assert_null(ChunkProfileSaveLease.take_ownership(oversized))

	var sink: ChunkProfileLoadSink = ChunkProfileLoadSink.new()
	assert_true(sink.write_once("loaded-payload".to_utf8_buffer()) == OK)
	assert_true(sink.is_written())
	assert_true(
		sink.write_once("duplicate".to_utf8_buffer()) == ERR_ALREADY_IN_USE
	)
	var claimed_load: PackedByteArray = sink.claim()
	assert_true(claimed_load.get_string_from_utf8() == "loaded-payload")
	assert_true(sink.is_claimed())
	assert_true(sink.claim().is_empty())


func test_provider_claims_save_lease_once_and_loads_into_sink_once() -> void:
	var provider: ChunkBlobSaveSectionProvider = (
		ChunkBlobSaveSectionProvider.new()
	)
	var save_lease: ChunkProfileSaveLease = (
		ChunkProfileSaveLease.take_ownership("save-bytes".to_utf8_buffer())
	)
	assert_not_null(save_lease)
	if save_lease == null:
		return
	var save_context: Dictionary = {
		ChunkBlobSaveSectionProvider.SAVE_LEASE_CONTEXT_KEY: save_lease,
	}
	var snapshot_operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot(save_context)
	)
	assert_not_null(snapshot_operation)
	if snapshot_operation == null:
		return
	assert_true(snapshot_operation.is_completed())
	assert_true(snapshot_operation.is_successful())
	assert_true(save_lease.is_claimed())
	assert_null(provider.begin_save_snapshot(save_context))
	assert_null(provider.begin_save_snapshot({}))

	var sink: ChunkProfileLoadSink = ChunkProfileLoadSink.new()
	var load_context: Dictionary = {
		ChunkBlobSaveSectionProvider.LOAD_SINK_CONTEXT_KEY: sink,
	}
	var rollback_snapshot: GFSaveSection = provider.capture_section(load_context)
	assert_not_null(rollback_snapshot)
	var section: GFSaveSection = provider.make_section(
		"load-bytes".to_utf8_buffer()
	)
	assert_true(provider.apply_section(section, load_context) == OK)
	assert_true(sink.is_written())
	var loaded: PackedByteArray = sink.claim()
	assert_true(loaded.get_string_from_utf8() == "load-bytes")
	assert_true(provider.apply_section(section, load_context) == ERR_ALREADY_IN_USE)


func test_provider_rollback_discards_unclaimed_load_candidate() -> void:
	var provider: ChunkBlobSaveSectionProvider = (
		ChunkBlobSaveSectionProvider.new()
	)
	var sink: ChunkProfileLoadSink = ChunkProfileLoadSink.new()
	var context: Dictionary = {
		ChunkBlobSaveSectionProvider.LOAD_SINK_CONTEXT_KEY: sink,
	}
	var previous: GFSaveSection = provider.capture_section(context)
	assert_not_null(previous)
	if previous == null:
		return
	var candidate: GFSaveSection = provider.make_section(
		"candidate".to_utf8_buffer()
	)
	assert_true(provider.apply_section(candidate, context) == OK)
	assert_true(provider.rollback_section(previous, context) == OK)
	assert_true(sink.is_rolled_back())
	assert_true(sink.claim().is_empty())
	assert_true(provider.apply_section(candidate, context) == ERR_ALREADY_IN_USE)


func test_gf_executor_only_delegates_to_injected_profile_utility() -> void:
	var utility: RecordingSaveProfileUtility = RecordingSaveProfileUtility.new()
	var executor: GfChunkProfileExecutor = GfChunkProfileExecutor.new(utility)
	var request: GFSaveProfileRequest = GFSaveProfileRequest.take_ownership(
		{},
		{},
		{}
	)
	var operation: GFSaveProfileOperation = executor.save_profile(
		&"chunk.profile",
		request
	)
	assert_null(operation)
	assert_true(utility.call_count == 1)
	assert_true(utility.last_profile_id == &"chunk.profile")
	assert_true(utility.last_request == request)


# --- 内部类 ---

class RecordingSaveProfileUtility extends GFSaveProfileUtility:
	var call_count: int = 0
	var last_profile_id: StringName = &""
	var last_request: GFSaveProfileRequest = null

	## @param profile_id: 记录的 chunk Profile 稳定 ID。
	## @param request: 记录的 GF Profile 保存请求。
	func save_profile(
		profile_id: StringName,
		request: GFSaveProfileRequest = null
	) -> GFSaveProfileOperation:
		call_count += 1
		last_profile_id = profile_id
		last_request = request
		return null
