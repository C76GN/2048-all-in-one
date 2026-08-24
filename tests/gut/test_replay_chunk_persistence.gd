## 验证 replays 第二个 manifest-backed tracer 的逐步 codec 与 Provider 边界。
extends GutTest


# --- 常量 ---

const _BOARD_SIZE: Vector2i = Vector2i(4, 4)
const _MAIN_PROFILE_ID: StringName = &"accounts.primary.player_profile"
const _PROFILE_FILE_NAME: String = "profiles/primary.save"


# --- 测试用例 ---

func test_codec_charges_header_metadata_and_each_step_then_roundtrips() -> void:
	var replay: ReplayData = _make_replay(101, 3, 3072)
	var source: ReplayChunkSourceSnapshot = (
		ReplayChunkSourceSnapshot.take_ownership_of_immutable_items([replay])
	)
	assert_not_null(source)
	if source == null:
		return
	var codec: ReplayChunkCodec = ReplayChunkCodec.begin_encode(source)
	assert_not_null(codec)
	if codec == null:
		return

	assert_true(codec.advance(1) == 1)
	assert_true(codec.get_encoded_replay_count() == 0)
	assert_true(codec.get_encoded_step_count() == 0)
	assert_false(codec.is_complete(), "首个 unit 只能编码 catalog header。")
	assert_true(codec.advance(1) == 1)
	assert_true(codec.get_encoded_replay_count() == 0)
	assert_true(codec.get_encoded_step_count() == 0)
	assert_false(codec.is_complete(), "第二个 unit 只能编码单局 metadata。")
	assert_true(codec.advance(1) == 1)
	assert_true(codec.get_encoded_step_count() == 0)
	assert_false(codec.is_complete(), "第三个 unit 只能编码 topology cell batch。")
	for expected_step_count: int in range(1, 4):
		assert_true(codec.advance(1) == 1)
		assert_true(
			codec.get_encoded_step_count() == expected_step_count,
			"每个 unit 必须只推进一个 action/checkpoint step。"
		)
	assert_true(codec.is_complete())
	assert_true(codec.get_encoded_replay_count() == 1)

	var chunks: Array[PackedByteArray] = (
		codec.take_chunks_taking_ownership()
	)
	assert_false(chunks.is_empty())
	var decoded_value: Variant = ReplayChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if not decoded_value is Dictionary:
		return
	var item_values: Array = GFVariantData.get_option_array(
		GFVariantData.as_dictionary(decoded_value),
		&"items"
	)
	assert_true(item_values.size() == 1)
	if item_values.size() != 1 or not item_values[0] is Dictionary:
		return
	var restored: ReplayData = ReplayData.from_dict(
		GFVariantData.as_dictionary(item_values[0])
	)
	assert_not_null(restored)
	if restored != null:
		assert_true(restored.replay_id == replay.replay_id)
		assert_true(restored.actions == replay.actions)
		assert_true(restored.checkpoints.size() == 3)
		assert_true(restored.final_score == 3072)


func test_codec_large_replay_splits_canonical_chunks() -> void:
	var replay: ReplayData = _make_replay(102, 512, 8192)
	var chunks: Array[PackedByteArray] = _encode_replays([replay])
	assert_true(chunks.size() >= 2, "逐步回放流必须能跨越 128 KiB chunk。")
	if chunks.size() < 2:
		return
	assert_true(chunks[0].size() == ReplayChunkCodec.CHUNK_BYTES)
	for index: int in range(chunks.size() - 1):
		assert_true(chunks[index].size() == ReplayChunkCodec.CHUNK_BYTES)
	var decoded_value: Variant = ReplayChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if decoded_value is Dictionary:
		var items: Array = GFVariantData.get_option_array(
			GFVariantData.as_dictionary(decoded_value),
			&"items"
		)
		assert_true(items.size() == 1)
		if items.size() == 1 and items[0] is Dictionary:
			assert_not_null(ReplayData.from_dict(
				GFVariantData.as_dictionary(items[0])
			))


func test_codec_roundtrips_exact_8192_step_business_boundary() -> void:
	var replay: ReplayData = _make_replay(
		106,
		ReplayData.MAX_STEP_COUNT,
		65_536
	)
	var chunks: Array[PackedByteArray] = _encode_replays([replay])
	assert_false(chunks.is_empty())
	if chunks.is_empty():
		return
	var decoded_value: Variant = ReplayChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if not decoded_value is Dictionary:
		return
	var items: Array = GFVariantData.get_option_array(
		GFVariantData.as_dictionary(decoded_value),
		&"items"
	)
	assert_true(items.size() == 1)
	if items.size() == 1 and items[0] is Dictionary:
		var restored: ReplayData = ReplayData.from_dict(
			GFVariantData.as_dictionary(items[0])
		)
		assert_not_null(restored)
		if restored != null:
			assert_true(restored.actions.size() == ReplayData.MAX_STEP_COUNT)
			assert_true(restored.checkpoints.size() == ReplayData.MAX_STEP_COUNT)


func test_codec_accepts_empty_and_128_catalog_but_rejects_129_source() -> void:
	var empty_chunks: Array[PackedByteArray] = _encode_replays([])
	var empty_value: Variant = ReplayChunkCodec.decode_chunks(empty_chunks)
	assert_true(empty_value is Dictionary)
	if empty_value is Dictionary:
		assert_true(GFVariantData.get_option_array(
			GFVariantData.as_dictionary(empty_value),
			&"items"
		).is_empty())

	var maximum_replays: Array[ReplayData] = []
	for index: int in range(ReplayCatalogSaveData.MAX_REPLAY_COUNT):
		maximum_replays.append(_make_replay(10_000 + index, 0, 0))
	var maximum_chunks: Array[PackedByteArray] = _encode_replays(
		maximum_replays
	)
	assert_false(maximum_chunks.is_empty())
	var maximum_value: Variant = ReplayChunkCodec.decode_chunks(maximum_chunks)
	assert_true(maximum_value is Dictionary)
	if maximum_value is Dictionary:
		assert_true(GFVariantData.get_option_array(
			GFVariantData.as_dictionary(maximum_value),
			&"items"
		).size() == ReplayCatalogSaveData.MAX_REPLAY_COUNT)

	maximum_replays.append(_make_replay(20_000, 0, 0))
	assert_null(
		ReplayChunkSourceSnapshot.take_ownership_of_immutable_items(
			maximum_replays
		)
	)


func test_topology_metadata_stays_scalar_and_cells_decode_in_fixed_batches() -> void:
	var topology: BoardTopology = BoardTopology.create_rectangle(
		Vector2i(65, 33)
	)
	assert_true(
		topology.get_cell_count()
		> ReplayChunkSourceSnapshot.TOPOLOGY_CELL_BATCH_SIZE * 2
	)
	var replay: ReplayData = _make_replay(107, 0, 0)
	replay.initial_board_topology = topology.to_dict()
	replay.final_board_snapshot = _make_empty_board_snapshot(topology)
	var chunks: Array[PackedByteArray] = _encode_replays([replay])
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(chunks)
	assert_not_null(decoder)
	if decoder == null:
		return
	var unit_count: int = 0
	while not decoder.is_complete() and not decoder.is_failed():
		assert_true(decoder.advance(1) == 1)
		unit_count += 1
	assert_false(decoder.is_failed(), decoder.get_error())
	# header + metadata + ceil(2145 / 1024) topology batches
	assert_true(unit_count == 5)
	var prepared_state: ReplayCatalogPreparedState = (
		decoder.take_prepared_state_taking_ownership()
	)
	assert_not_null(prepared_state)
	if prepared_state == null:
		return
	var payload: Dictionary = prepared_state.make_serialized_payload_for_tests()
	var items: Array = GFVariantData.get_option_array(payload, &"items")
	assert_true(items.size() == 1)
	if items.size() == 1 and items[0] is Dictionary:
		var restored: ReplayData = ReplayData.from_dict(
			GFVariantData.as_dictionary(items[0])
		)
		assert_not_null(restored)
		if restored != null:
			assert_true(
				restored.get_initial_topology().get_cell_count()
				== topology.get_cell_count()
			)


func test_codec_rejects_truncation_tail_bad_counts_and_step_types() -> void:
	var valid_chunks: Array[PackedByteArray] = _encode_replays([
		_make_replay(103, 1, 1024),
	])
	assert_false(valid_chunks.is_empty())
	if valid_chunks.is_empty():
		return

	var truncated: Array[PackedByteArray] = _duplicate_chunks(valid_chunks)
	var truncated_last: PackedByteArray = truncated[-1]
	assert_true(truncated_last.resize(truncated_last.size() - 1) == OK)
	truncated[-1] = truncated_last
	assert_true(ReplayChunkCodec.decode_chunks(truncated) == null)

	var with_extra_byte: Array[PackedByteArray] = _duplicate_chunks(valid_chunks)
	var _appended_extra_byte: bool = with_extra_byte[-1].append(0x7f)
	assert_true(ReplayChunkCodec.decode_chunks(with_extra_byte) == null)

	var missing_replay: Array[PackedByteArray] = _make_test_stream(
		_make_stream_header(1),
		[]
	)
	assert_true(ReplayChunkCodec.decode_chunks(missing_replay) == null)

	var metadata: Dictionary = _make_replay_metadata(
		_make_replay(104, 1, 2048),
		1
	)
	var wrong_action: Array[PackedByteArray] = _make_test_stream(
		_make_stream_header(1),
		[
			metadata,
			_make_topology_cell_frame(_make_replay(104, 1, 2048)),
			{
				&"record_type": ReplayChunkDecoder.RECORD_STEP,
				&"replay_index": 0,
				&"step_index": 0,
				&"action": "right",
				&"checkpoint": _make_checkpoint(1, 2048).to_dict(),
			},
		]
	)
	assert_true(ReplayChunkCodec.decode_chunks(wrong_action) == null)

	var future_business_header: Dictionary = _make_stream_header(0)
	future_business_header[&"business_schema_version"] = (
		ReplayChunkCodec.BUSINESS_SCHEMA_VERSION + 1
	)
	assert_true(ReplayChunkCodec.decode_chunks(
		_make_test_stream(future_business_header, [])
	) == null)

	var noncanonical_stream: PackedByteArray = _join_chunks(valid_chunks)
	var noncanonical_chunks: Array[PackedByteArray] = [
		noncanonical_stream.slice(0, 1),
		noncanonical_stream.slice(1),
	]
	assert_true(ReplayChunkCodec.decode_chunks(noncanonical_chunks) == null)


func test_codec_rejects_step_count_above_business_budget() -> void:
	var replay: ReplayData = _make_replay(105, 0, 0)
	var metadata: Dictionary = _make_replay_metadata(
		replay,
		ReplayData.MAX_STEP_COUNT + 1
	)
	var chunks: Array[PackedByteArray] = _make_test_stream(
		_make_stream_header(1),
		[metadata]
	)
	assert_true(ReplayChunkCodec.decode_chunks(chunks) == null)


func test_decoder_rejects_noncanonical_scalar_metadata_early() -> void:
	var replay: ReplayData = _make_replay(106, 0, 0)
	var invalid_metadata_frames: Array[Dictionary] = []
	var negative_timestamp: Dictionary = _make_replay_metadata(replay, 0)
	negative_timestamp[&"timestamp"] = -1
	invalid_metadata_frames.append(negative_timestamp)
	var negative_score: Dictionary = _make_replay_metadata(replay, 0)
	negative_score[&"final_score"] = -1
	invalid_metadata_frames.append(negative_score)
	var uppercase_fingerprint: Dictionary = _make_replay_metadata(replay, 0)
	uppercase_fingerprint[&"ruleset_fingerprint"] = "A".repeat(64)
	invalid_metadata_frames.append(uppercase_fingerprint)
	var non_hex_fingerprint: Dictionary = _make_replay_metadata(replay, 0)
	non_hex_fingerprint[&"ruleset_fingerprint"] = "g".repeat(64)
	invalid_metadata_frames.append(non_hex_fingerprint)

	for metadata: Dictionary in invalid_metadata_frames:
		var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(
			_make_test_stream(_make_stream_header(1), [metadata])
		)
		assert_not_null(decoder)
		if decoder == null:
			continue
		assert_true(decoder.advance(1) == 1)
		assert_false(decoder.is_failed())
		assert_true(decoder.advance(1) == 1)
		assert_true(decoder.is_failed(), "非法标量必须在 metadata frame 被拒绝。")


func test_codec_rejects_noncanonical_frame_key_and_text_encoding() -> void:
	var string_key_header: Dictionary = {
		"record_type": ReplayChunkDecoder.RECORD_CATALOG,
		"schema_id": ReplayChunkCodec.STREAM_SCHEMA_ID,
		"schema_version": ReplayChunkCodec.STREAM_SCHEMA_VERSION,
		"business_schema_version": ReplayChunkCodec.BUSINESS_SCHEMA_VERSION,
		"replay_count": 0,
	}
	var string_record_type: Dictionary = _make_stream_header(0)
	string_record_type[&"record_type"] = String(
		ReplayChunkDecoder.RECORD_CATALOG
	)
	var string_schema_id: Dictionary = _make_stream_header(0)
	string_schema_id[&"schema_id"] = String(ReplayChunkCodec.STREAM_SCHEMA_ID)
	var reordered_header: Dictionary = {
		&"schema_id": ReplayChunkCodec.STREAM_SCHEMA_ID,
		&"record_type": ReplayChunkDecoder.RECORD_CATALOG,
		&"schema_version": ReplayChunkCodec.STREAM_SCHEMA_VERSION,
		&"business_schema_version": ReplayChunkCodec.BUSINESS_SCHEMA_VERSION,
		&"replay_count": 0,
	}
	var invalid_headers: Array[Dictionary] = [
		string_key_header,
		string_record_type,
		string_schema_id,
		reordered_header,
	]
	for header: Dictionary in invalid_headers:
		var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(
			_make_test_stream(header, [])
		)
		assert_not_null(decoder)
		if decoder == null:
			continue
		assert_true(decoder.advance(1) == 1)
		assert_true(
			decoder.is_failed(),
			"frame key、顺序及 StringName 类型必须保持规范编码。"
		)


func test_source_rejects_invalid_scalar_metadata_before_encoding() -> void:
	var invalid_replays: Array[ReplayData] = []
	var negative_timestamp: ReplayData = _make_replay(107, 0, 0)
	negative_timestamp.timestamp = -1
	invalid_replays.append(negative_timestamp)
	var negative_score: ReplayData = _make_replay(108, 0, 0)
	negative_score.final_score = -1
	invalid_replays.append(negative_score)
	var uppercase_fingerprint: ReplayData = _make_replay(109, 0, 0)
	uppercase_fingerprint.ruleset_fingerprint = "A".repeat(64)
	invalid_replays.append(uppercase_fingerprint)
	for replay: ReplayData in invalid_replays:
		assert_null(
			ReplayChunkSourceSnapshot.take_ownership_of_immutable_items([replay]),
			"非法 scalar metadata 不得进入 framed encoder。"
		)


func test_decoder_advance_one_rejects_malformed_checkpoint_at_its_frame() -> void:
	var replay: ReplayData = _make_replay(108, 1, 2048)
	var malformed_checkpoint: Dictionary = _make_checkpoint(1, 2048).to_dict()
	var _erased_checksum: bool = malformed_checkpoint.erase(&"rng_checksum")
	var chunks: Array[PackedByteArray] = _make_test_stream(
		_make_stream_header(1),
		[
			_make_replay_metadata(replay, 1),
			_make_topology_cell_frame(replay),
			{
				&"record_type": ReplayChunkDecoder.RECORD_STEP,
				&"replay_index": 0,
				&"step_index": 0,
				&"action": Vector2i.RIGHT,
				&"checkpoint": malformed_checkpoint,
			},
			{&"unreachable_tail": true},
		]
	)
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(chunks)
	assert_not_null(decoder)
	if decoder == null:
		return
	assert_true(decoder.advance(1) == 1)
	assert_false(decoder.is_failed())
	assert_true(decoder.advance(1) == 1)
	assert_false(decoder.is_failed())
	assert_true(decoder.advance(1) == 1)
	assert_false(decoder.is_failed())
	assert_true(decoder.advance(1) == 1)
	assert_true(decoder.is_failed(), "畸形 checkpoint 必须在其 frame 被早拒绝。")
	assert_true(decoder.get_decoded_replay_count() == 0)


func test_decoder_rejects_oversized_frame_length_before_payload_decode() -> void:
	var payload_length: int = ReplayChunkDecoder.MAX_FRAME_PAYLOAD_BYTES + 1
	var stream: PackedByteArray = PackedByteArray([
		(payload_length >> 24) & 0xff,
		(payload_length >> 16) & 0xff,
		(payload_length >> 8) & 0xff,
		payload_length & 0xff,
	])
	var oversized_payload: PackedByteArray = PackedByteArray()
	assert_true(oversized_payload.resize(payload_length) == OK)
	stream.append_array(oversized_payload)
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(
		_split_test_stream(stream)
	)
	assert_not_null(decoder)
	if decoder != null:
		assert_true(decoder.advance(1) == 0)
		assert_true(decoder.is_failed())


func test_decoder_never_deserializes_object_frames() -> void:
	var object_payload: PackedByteArray = var_to_bytes_with_objects(
		RefCounted.new()
	)
	assert_false(object_payload.is_empty())
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(
		_make_raw_frame_stream(object_payload)
	)
	assert_not_null(decoder)
	if decoder == null:
		return
	assert_true(decoder.advance(1) == 0)
	assert_true(decoder.is_failed())
	assert_engine_error("!p_allow_objects")


func test_codec_rejects_single_tile_frame_above_128_kib() -> void:
	var replay: ReplayData = _make_replay(109, 0, 0)
	var topology: BoardTopology = replay.get_initial_topology()
	replay.final_board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [{
			&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
			&"tile_id": GFUuid.generate_v7(109_000),
			&"definition_id": &"tile.classic",
			&"value": 2,
			&"capability_recipe_ids": [&"tile.recipe.classic_merge"],
			&"capability_state": {
				&"tile.recipe.classic_merge": {
					&"oversized": "x".repeat(
						ReplayChunkCodec.MAX_FRAME_PAYLOAD_BYTES
					),
				},
			},
			&"pos": Vector2i.ZERO,
		}],
	}
	var source: ReplayChunkSourceSnapshot = (
		ReplayChunkSourceSnapshot.take_ownership_of_immutable_items([replay])
	)
	assert_not_null(source)
	if source == null:
		return
	assert_true(
		typeof(source.duplicate_final_tile_batch(0, 0)) == TYPE_NIL,
		"超长 String 必须在 tile deep duplicate/var_to_bytes 前被预算扫描拒绝。"
	)
	var codec: ReplayChunkCodec = ReplayChunkCodec.begin_encode(source)
	assert_not_null(codec)
	if codec == null:
		return
	while not codec.is_complete() and not codec.is_failed():
		assert_true(codec.advance(1) == 1 or codec.is_failed())
	assert_true(codec.is_failed())
	assert_true(codec.get_error_code() == ERR_INVALID_DATA)
	assert_true(codec.get_error().contains("tile batch is invalid"))


func test_tile_budget_rejects_packed_container_object_cycle_and_nonfinite() -> void:
	assert_true(
		ReplayChunkSourceSnapshot.MAX_TILE_VARIANT_DEPTH
		== ChunkFrameVariantBudget.MAX_VARIANT_DEPTH
	)
	assert_true(
		ReplayChunkSourceSnapshot.MAX_TILE_PACKED_BYTES
		== ChunkFrameVariantBudget.MAX_PACKED_BYTES
	)
	assert_true(ChunkFrameVariantBudget.is_value_within_default_budget({
		&"bounded": 2048,
	}))
	var oversized_packed: PackedByteArray = PackedByteArray()
	assert_true(
		oversized_packed.resize(
			ReplayChunkSourceSnapshot.MAX_TILE_PACKED_BYTES + 1
		) == OK
	)
	assert_false(ReplayChunkSourceSnapshot.is_tile_variant_within_budget({
		&"payload": oversized_packed,
	}))
	assert_false(ChunkFrameVariantBudget.is_value_within_default_budget({
		&"payload": oversized_packed,
	}))

	var oversized_container: Array = []
	assert_true(
		oversized_container.resize(
			ReplayChunkSourceSnapshot.MAX_TILE_CONTAINER_ITEMS + 1
		) == OK
	)
	assert_false(ReplayChunkSourceSnapshot.is_tile_variant_within_budget({
		&"payload": oversized_container,
	}))
	assert_false(ReplayChunkSourceSnapshot.is_tile_variant_within_budget({
		&"payload": RefCounted.new(),
	}))

	var cyclic: Array = []
	cyclic.append(cyclic)
	assert_false(ReplayChunkSourceSnapshot.is_tile_variant_within_budget({
		&"payload": cyclic,
	}))
	assert_false(ReplayChunkSourceSnapshot.is_tile_variant_within_budget({
		&"payload": NAN,
	}))


func test_catalog_rejects_129_root_before_deep_duplicate() -> void:
	var oversized_items: Array = []
	assert_true(
		oversized_items.resize(ReplayCatalogSaveData.MAX_REPLAY_COUNT + 1)
		== OK
	)
	# Object 若进入 deep duplicate 会触发持久化边界错误；根计数必须先拒绝。
	oversized_items[0] = RefCounted.new()
	var business: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	assert_true(
		business.replace_section_data({&"items": oversized_items})
		== ERR_INVALID_DATA
	)


func test_materialization_lease_rejects_other_manifest_without_consuming() -> void:
	var business: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var old_replay: ReplayData = _make_replay(150, 0, 0)
	assert_true(business.replace_section_data({
		&"items": [old_replay.to_dict()],
	}) == OK)
	var provider: ReplayManifestSaveSectionProvider = (
		ReplayManifestSaveSectionProvider.new(business)
	)
	var chunks_a: Array[PackedByteArray] = _encode_replays([
		_make_replay(151, 1, 2048),
	])
	var chunks_b: Array[PackedByteArray] = _encode_replays([
		_make_replay(152, 2, 4096),
	])
	var manifest_a: ChunkManifest = ChunkManifest.create(
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		chunks_a
	)
	var manifest_b: ChunkManifest = ChunkManifest.create(
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		ChunkManifest.BANK_B,
		chunks_b
	)
	assert_not_null(manifest_a)
	assert_not_null(manifest_b)
	if manifest_a == null or manifest_b == null:
		return
	var lease_chunks: Array[PackedByteArray] = _duplicate_chunks(chunks_a)
	var lease: ChunkMaterializationLease = (
		provider.make_materialization_lease_taking_ownership(
			lease_chunks,
			manifest_a,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME
		)
	)
	assert_not_null(lease)
	if lease == null:
		return
	var context: Dictionary = _make_load_context(lease)
	var section_b: GFSaveSection = provider.make_section(manifest_b.to_dict())
	assert_true(provider.apply_section(section_b, context) == ERR_INVALID_DATA)
	assert_true(lease.is_available(), "Manifest 错配不得 claim A payload。")
	assert_false(lease.is_claimed())
	assert_true(provider.get_active_manifest() == null)
	assert_true(_first_replay_score(business) == 0)


func test_wrapper_requires_lease_claims_manifest_and_reuses_clean_state() -> void:
	var business: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var replay: ReplayData = _make_replay(201, 2, 4096)
	assert_true(
		business.replace_section_data({&"items": [replay.to_dict()]}) == OK
	)
	var provider: ReplayManifestSaveSectionProvider = (
		ReplayManifestSaveSectionProvider.new(business)
	)
	assert_null(
		provider.begin_save_snapshot({}),
		"首次且 dirty 时不得绕过 ChunkSaveLease inline 保存。"
	)

	var lease: ChunkSaveLease = _make_save_lease(
		provider.get_producer_revision()
	)
	assert_not_null(lease)
	if lease == null:
		return
	var operation: GFSaveSectionSnapshotOperation = provider.begin_save_snapshot({
		ManifestBackedSaveSectionProvider.SAVE_LEASES_CONTEXT_KEY: {
			&"replays": lease,
		},
	})
	assert_not_null(operation)
	if operation == null:
		return
	for _unit: int in range(32):
		if lease.is_ready_to_stage():
			break
		assert_true(operation.advance_for_framework(1) == 1)
	assert_true(lease.is_ready_to_stage())
	assert_true(operation.is_pending(), "offer 后必须等待 staging 终态。")

	var request: ChunkStageRequest = lease.take_stage_request_for_utility()
	assert_not_null(request)
	if request == null:
		return
	var candidate_manifest: ChunkManifest = request.build_manifest()
	assert_not_null(candidate_manifest)
	if candidate_manifest == null:
		return
	assert_true(lease.settle_stage_for_utility(ChunkStageResult.create(
		ChunkStageResult.STATUS_STAGED,
		OK,
		"",
		-1,
		candidate_manifest
	)))
	assert_true(operation.advance_for_framework(1) == 1)
	assert_true(operation.is_successful())

	var snapshot: GFSaveSectionSnapshot = operation.take_snapshot_for_framework()
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var manifest_value: Variant = record.get(&"payload")
	assert_true(manifest_value is Dictionary)
	if not manifest_value is Dictionary:
		return
	var claimed_manifest: ChunkManifest = ChunkManifest.from_dict(
		GFVariantData.as_dictionary(manifest_value)
	)
	assert_not_null(claimed_manifest)
	if claimed_manifest == null:
		return
	assert_true(
		claimed_manifest.get_section_schema_version()
		== ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION
	)
	assert_true(provider.commit_candidate_manifest(
		claimed_manifest,
		lease.get_producer_revision()
	))

	var reused: GFSaveSectionSnapshotOperation = provider.begin_save_snapshot({})
	assert_not_null(reused)
	if reused != null:
		assert_true(reused.is_successful())
	provider.mark_business_data_changed()
	assert_null(provider.begin_save_snapshot({}))


func test_wrapper_8192_root_rollback_is_small_and_restores_object_identity() -> void:
	var business: RecordingReplayCatalog = RecordingReplayCatalog.new()
	var old_replay: ReplayData = _make_replay(301, 8192, 8192)
	assert_true(
		business.replace_section_data({&"items": [old_replay.to_dict()]}) == OK
	)
	var dictionary_replace_count: int = business.dictionary_replace_call_count
	var old_identity: PackedInt64Array = business.get_replay_instance_ids()
	var provider: ReplayManifestSaveSectionProvider = (
		ReplayManifestSaveSectionProvider.new(business)
	)
	var new_replay: ReplayData = _make_replay(302, 2, 4096)
	var chunks: Array[PackedByteArray] = _encode_replays([new_replay])
	var manifest: ChunkManifest = ChunkManifest.create(
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		chunks
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var section: GFSaveSection = provider.make_section(manifest.to_dict())

	var corrupted_chunks: Array[PackedByteArray] = _duplicate_chunks(chunks)
	var corrupted_last: PackedByteArray = corrupted_chunks[-1]
	assert_true(corrupted_last.resize(corrupted_last.size() - 1) == OK)
	corrupted_chunks[-1] = corrupted_last
	assert_null(
		provider.make_materialization_lease_taking_ownership(
			corrupted_chunks,
			manifest,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME
		)
	)
	assert_true(corrupted_chunks.is_empty())

	var materialization: ChunkMaterializationLease = (
		provider.make_materialization_lease_taking_ownership(
			chunks,
			manifest,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME
		)
	)
	assert_not_null(materialization)
	if materialization == null:
		return
	assert_true(chunks.is_empty())
	var load_context: Dictionary = {
		ManifestBackedSaveSectionProvider.LOAD_LEASES_CONTEXT_KEY: {
			&"replays": materialization,
		},
		ManifestBackedSaveSectionProvider.LOAD_MAIN_PROFILE_ID_CONTEXT_KEY: (
			_MAIN_PROFILE_ID
		),
		ManifestBackedSaveSectionProvider.LOAD_CANONICAL_FILE_CONTEXT_KEY: (
			_PROFILE_FILE_NAME
		),
	}
	var previous: GFSaveSection = provider.capture_section(load_context)
	assert_not_null(previous)
	if previous == null:
		return
	assert_true(
		var_to_bytes(previous.get_payload()).size() < 256,
		"8192-step 旧根只能在 lease 中浅暂存，GF section 必须保持小 sentinel。"
	)
	assert_true(materialization.is_rollback_root_available())
	assert_true(provider.apply_section(section, load_context) == OK)
	assert_true(
		business.dictionary_replace_call_count == dictionary_replace_count,
		"PreparedState apply 不得同步重跑 Dictionary/ReplayData.from_dict 路径。"
	)
	assert_true(materialization.is_claimed())
	assert_true(_first_replay_score(business) == 4096)
	assert_false(business.get_replay_instance_ids() == old_identity)
	# 模拟后续 provider apply fault 后 GF 反向补偿当前 replay provider。
	assert_true(provider.rollback_section(previous, load_context) == OK)
	assert_true(
		business.dictionary_replace_call_count == dictionary_replace_count,
		"浅根 rollback 不得同步重跑 Dictionary 重建路径。"
	)
	assert_true(_first_replay_score(business) == 8192)
	assert_true(business.get_replay_instance_ids() == old_identity)
	assert_false(materialization.is_rollback_root_available())


func test_wrapper_async_materialization_advances_and_cancels_cleanly() -> void:
	var provider: ReplayManifestSaveSectionProvider = (
		ReplayManifestSaveSectionProvider.new(ReplayCatalogSaveData.new())
	)
	var chunks: Array[PackedByteArray] = _encode_replays([
		_make_replay(303, 40, 8192),
	])
	var manifest: ChunkManifest = ChunkManifest.create(
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		ChunkManifest.BANK_A,
		chunks
	)
	assert_not_null(manifest)
	if manifest == null:
		return
	var materialization: ChunkMaterializationLease = await (
		provider.make_materialization_lease_async_taking_ownership(
			chunks,
			manifest,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME
		)
	)
	assert_not_null(materialization)
	assert_true(chunks.is_empty())
	if materialization != null:
		var payload_value: Variant = materialization.claim_for_manifest(
			manifest,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME,
			&"replays",
			ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION
		)
		assert_true(payload_value is ReplayCatalogPreparedState)
		if payload_value is ReplayCatalogPreparedState:
			var state: ReplayCatalogPreparedState = payload_value
			assert_true(state.get_item_count() == 1)

	var cancelled_chunks: Array[PackedByteArray] = _encode_replays([
		_make_replay(304, 40, 4096),
	])
	var cancelled_manifest: ChunkManifest = ChunkManifest.create(
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		ChunkManifest.BANK_B,
		cancelled_chunks
	)
	assert_not_null(cancelled_manifest)
	if cancelled_manifest == null:
		return
	var continuation_gate: GFAsyncKeyedGate = GFAsyncKeyedGate.new()
	var lease_result: Dictionary = continuation_gate.try_request_lease(
		&"replay_materialization_test"
	)
	var continuation_value: Variant = lease_result.get(&"lease")
	assert_true(continuation_value is GFAsyncGateLease)
	if not continuation_value is GFAsyncGateLease:
		return
	var continuation_lease: GFAsyncGateLease = continuation_value
	call_deferred(
		&"_release_continuation_lease",
		continuation_lease
	)
	var cancelled: ChunkMaterializationLease = await (
		provider.make_materialization_lease_async_taking_ownership(
			cancelled_chunks,
			cancelled_manifest,
			_MAIN_PROFILE_ID,
			_PROFILE_FILE_NAME,
			continuation_lease
		)
	)
	assert_null(cancelled)
	assert_true(cancelled_chunks.is_empty())
	assert_false(continuation_lease.is_active())


func test_source_snapshot_survives_catalog_root_replacement() -> void:
	var business: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var frozen_replay: ReplayData = _make_replay(401, 1, 2048)
	assert_true(business.replace_section_data({
		&"items": [frozen_replay.to_dict()],
	}) == OK)
	var source: ReplayChunkSourceSnapshot = business.make_chunk_source_snapshot()
	assert_not_null(source)
	if source == null:
		return
	var replacement: ReplayData = _make_replay(402, 1, 4096)
	assert_true(business.replace_section_data({
		&"items": [replacement.to_dict()],
	}) == OK)
	var chunks: Array[PackedByteArray] = _encode_source(source)
	var decoded_value: Variant = ReplayChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if not decoded_value is Dictionary:
		return
	var items: Array = GFVariantData.get_option_array(
		GFVariantData.as_dictionary(decoded_value),
		&"items"
	)
	assert_true(items.size() == 1)
	if items.size() == 1 and items[0] is Dictionary:
		assert_true(
			GFVariantData.get_option_string(
				GFVariantData.as_dictionary(items[0]),
				&"replay_id"
			) == frozen_replay.replay_id,
			"冻结源不得跟随 Provider 后续整体根替换。"
		)


# --- 私有/辅助方法 ---

func _encode_replays(
	replays: Array[ReplayData]
) -> Array[PackedByteArray]:
	var source: ReplayChunkSourceSnapshot = (
		ReplayChunkSourceSnapshot.take_ownership_of_immutable_items(
			replays.duplicate()
		)
	)
	assert_not_null(source)
	return _encode_source(source) if source != null else []


func _encode_source(
	source: ReplayChunkSourceSnapshot
) -> Array[PackedByteArray]:
	var codec: ReplayChunkCodec = ReplayChunkCodec.begin_encode(source)
	assert_not_null(codec)
	if codec == null:
		return []
	var guard: int = 0
	while not codec.is_complete() and not codec.is_failed() and guard < 100_000:
		var consumed: int = codec.advance(32)
		assert_true(consumed > 0)
		guard += 1
	assert_true(codec.is_complete())
	assert_false(codec.is_failed(), codec.get_error())
	return codec.take_chunks_taking_ownership()


func _make_stream_header(replay_count: int) -> Dictionary:
	return {
		&"record_type": ReplayChunkDecoder.RECORD_CATALOG,
		&"schema_id": ReplayChunkCodec.STREAM_SCHEMA_ID,
		&"schema_version": ReplayChunkCodec.STREAM_SCHEMA_VERSION,
		&"business_schema_version": ReplayChunkCodec.BUSINESS_SCHEMA_VERSION,
		&"replay_count": replay_count,
	}


func _make_replay_metadata(replay: ReplayData, step_count: int) -> Dictionary:
	var topology: BoardTopology = replay.get_initial_topology()
	var tiles: Array = GFVariantData.get_option_array(
		replay.final_board_snapshot,
		&"tiles"
	)
	return {
		&"record_type": ReplayChunkDecoder.RECORD_REPLAY_METADATA,
		&"replay_index": 0,
		&"schema_version": ReplayData.SCHEMA_VERSION,
		&"replay_id": replay.replay_id,
		&"timestamp": replay.timestamp,
		&"mode_config_path": replay.mode_config_path,
		&"ruleset_id": replay.ruleset_id,
		&"ruleset_version": replay.ruleset_version,
		&"ruleset_fingerprint": replay.ruleset_fingerprint,
		&"initial_seed": replay.initial_seed,
		&"session_metadata": replay.session_metadata.duplicate(true),
		&"final_score": replay.final_score,
		&"topology_schema_version": BoardTopology.SERIALIZATION_SCHEMA_VERSION,
		&"topology_id": GFVariantData.get_option_string(
			replay.initial_board_topology,
			&"topology_id"
		),
		&"active_cell_count": topology.get_cell_count() if topology != null else 0,
		&"snapshot_schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"tile_count": tiles.size(),
		&"step_count": step_count,
	}


func _make_topology_cell_frame(replay: ReplayData) -> Dictionary:
	return {
		&"record_type": ReplayChunkDecoder.RECORD_TOPOLOGY_CELLS,
		&"replay_index": 0,
		&"start_index": 0,
		&"cells": GFVariantData.get_option_array(
			replay.initial_board_topology,
			&"active_cells"
		).duplicate(),
	}


func _make_test_stream(
	header: Dictionary,
	frames: Array
) -> Array[PackedByteArray]:
	var stream: PackedByteArray = PackedByteArray()
	_append_test_frame(stream, header)
	for frame: Variant in frames:
		_append_test_frame(stream, frame)
	return _split_test_stream(stream)


func _append_test_frame(stream: PackedByteArray, value: Variant) -> void:
	var payload: PackedByteArray = var_to_bytes(value)
	stream.append_array(PackedByteArray([
		(payload.size() >> 24) & 0xff,
		(payload.size() >> 16) & 0xff,
		(payload.size() >> 8) & 0xff,
		payload.size() & 0xff,
	]))
	stream.append_array(payload)


func _split_test_stream(stream: PackedByteArray) -> Array[PackedByteArray]:
	var chunks: Array[PackedByteArray] = []
	var offset: int = 0
	while offset < stream.size():
		var next_offset: int = mini(
			offset + ReplayChunkCodec.CHUNK_BYTES,
			stream.size()
		)
		chunks.append(stream.slice(offset, next_offset))
		offset = next_offset
	return chunks


func _make_raw_frame_stream(
	payload: PackedByteArray
) -> Array[PackedByteArray]:
	var stream: PackedByteArray = PackedByteArray([
		(payload.size() >> 24) & 0xff,
		(payload.size() >> 16) & 0xff,
		(payload.size() >> 8) & 0xff,
		payload.size() & 0xff,
	])
	stream.append_array(payload)
	return _split_test_stream(stream)


func _duplicate_chunks(
	chunks: Array[PackedByteArray]
) -> Array[PackedByteArray]:
	var duplicates: Array[PackedByteArray] = []
	for chunk: PackedByteArray in chunks:
		duplicates.append(chunk.duplicate())
	return duplicates


func _join_chunks(chunks: Array[PackedByteArray]) -> PackedByteArray:
	var stream: PackedByteArray = PackedByteArray()
	for chunk: PackedByteArray in chunks:
		stream.append_array(chunk)
	return stream


func _make_save_lease(producer_revision: int) -> ChunkSaveLease:
	return ChunkSaveLease.create(
		&"replay-test-lease",
		&"accounts.primary.player_profile",
		"profiles/primary.save",
		&"replays",
		ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		producer_revision,
		"accounts.primary.chunks.replays"
	)


func _make_load_context(lease: ChunkMaterializationLease) -> Dictionary:
	return {
		ManifestBackedSaveSectionProvider.LOAD_LEASES_CONTEXT_KEY: {
			&"replays": lease,
		},
		ManifestBackedSaveSectionProvider.LOAD_MAIN_PROFILE_ID_CONTEXT_KEY: (
			_MAIN_PROFILE_ID
		),
		ManifestBackedSaveSectionProvider.LOAD_CANONICAL_FILE_CONTEXT_KEY: (
			_PROFILE_FILE_NAME
		),
	}


func _first_replay_score(provider: ReplayCatalogSaveData) -> int:
	var items: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		&"items"
	)
	if items.is_empty() or not items[0] is Dictionary:
		return -1
	return GFVariantData.get_option_int(
		GFVariantData.as_dictionary(items[0]),
		&"final_score",
		-1
	)


func _release_continuation_lease(lease: GFAsyncGateLease) -> void:
	if lease != null:
		var _released: bool = lease.release(&"test_cancelled")


func _make_replay(
	timestamp: int,
	step_count: int,
	final_score: int
) -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	var topology: BoardTopology = BoardTopology.create_rectangle(_BOARD_SIZE)
	replay.replay_id = GFUuid.generate_v7(timestamp * 1000)
	replay.timestamp = timestamp
	replay.mode_config_path = (
		"res://features/gameplay/resources/modes/classic_mode_config.tres"
	)
	replay.ruleset_id = &"gameplay.classic"
	replay.ruleset_version = 1
	replay.ruleset_fingerprint = "a".repeat(64)
	replay.initial_seed = 2048
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = final_score
	for index: int in range(step_count):
		replay.actions.append(Vector2i.RIGHT)
		var step_score: int = (
			final_score
			if index == step_count - 1
			else mini(index, final_score)
		)
		replay.checkpoints.append(_make_checkpoint(index + 1, step_score))
	replay.final_board_snapshot = _make_empty_board_snapshot(topology)
	return replay


func _make_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "b".repeat(64)
	checkpoint.board_checksum = "c".repeat(64)
	checkpoint.rng_checksum = "d".repeat(64)
	checkpoint.score = score
	return checkpoint


func _make_empty_board_snapshot(topology: BoardTopology) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}


# --- 内部类 ---

class RecordingReplayCatalog extends ReplayCatalogSaveData:
	var dictionary_replace_call_count: int = 0

	func _replace_section_data(data: Dictionary) -> Error:
		dictionary_replace_call_count += 1
		return super._replace_section_data(data)
