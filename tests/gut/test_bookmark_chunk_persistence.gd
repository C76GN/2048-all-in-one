## 验证 bookmarks 首个 manifest-backed tracer 的 codec 与 Provider 边界。
extends GutTest


# --- 常量 ---

const _MAIN_PROFILE_ID: StringName = &"accounts.primary.player_profile"
const _PROFILE_FILE_NAME: String = "profiles/primary.save"


# --- 测试用例 ---

func test_codec_v2_empty_catalog_roundtrip() -> void:
	var chunks: Array[PackedByteArray] = _encode_records([])
	assert_false(chunks.is_empty())
	var decoded_value: Variant = BookmarkChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if decoded_value is Dictionary:
		var decoded: Dictionary = decoded_value
		assert_true(GFVariantData.get_option_array(decoded, &"items").is_empty())


func test_codec_v2_roundtrip_splits_large_trace_into_bounded_frames() -> void:
	var bookmark: BookmarkData = _make_trace_bookmark(101, 2048, 768)
	var record: Dictionary = bookmark.to_dict()
	var chunks: Array[PackedByteArray] = _encode_records([record])
	assert_true(chunks.size() >= 2, "大记录必须跨越 128 KiB chunk。")
	if chunks.is_empty():
		return
	assert_true(chunks[0].size() == BookmarkChunkCodec.CHUNK_BYTES)

	var decoded_value: Variant = BookmarkChunkCodec.decode_chunks(chunks)
	assert_true(decoded_value is Dictionary)
	if not decoded_value is Dictionary:
		return
	var decoded: Dictionary = decoded_value
	assert_true(GFVariantData.get_option_array(decoded, &"items") == [record])

	var decoder: BookmarkChunkDecoder = BookmarkChunkDecoder.begin_decode(chunks)
	assert_not_null(decoder)
	if decoder == null:
		return
	var frame_count: int = 0
	while not decoder.is_complete() and not decoder.is_failed():
		assert_true(decoder.advance(1) == 1)
		frame_count += 1
	assert_true(decoder.is_complete())
	assert_true(frame_count > 768, "advance(1) 必须逐 frame 推进，不得整流同步解码。")
	var prepared: BookmarkCatalogPreparedState = (
		decoder.take_prepared_state_taking_ownership()
	)
	assert_not_null(prepared)
	if prepared != null:
		assert_true(prepared.get_item_count() == 1)


func test_codec_rejects_truncation_trailing_and_noncanonical_header() -> void:
	var valid_chunks: Array[PackedByteArray] = _encode_records([
		_make_bookmark(102, 1024).to_dict(),
	])
	assert_false(valid_chunks.is_empty())
	if valid_chunks.is_empty():
		return

	var truncated: Array[PackedByteArray] = _duplicate_chunks(valid_chunks)
	var truncated_last: PackedByteArray = truncated[-1]
	assert_true(truncated_last.resize(truncated_last.size() - 1) == OK)
	truncated[-1] = truncated_last
	assert_true(BookmarkChunkCodec.decode_chunks(truncated) == null)

	var with_extra_byte: Array[PackedByteArray] = _duplicate_chunks(valid_chunks)
	var _appended_extra_byte: bool = with_extra_byte[-1].append(0x7f)
	assert_true(BookmarkChunkCodec.decode_chunks(with_extra_byte) == null)

	var string_key_header: Dictionary = {
		"record_type": BookmarkChunkDecoder.RECORD_CATALOG,
		"schema_id": BookmarkChunkCodec.STREAM_SCHEMA_ID,
		"schema_version": BookmarkChunkCodec.STREAM_SCHEMA_VERSION,
		"business_schema_version": BookmarkChunkCodec.BUSINESS_SCHEMA_VERSION,
		"bookmark_count": 0,
	}
	assert_true(BookmarkChunkCodec.decode_chunks(
		_make_test_stream([string_key_header])
	) == null)

	var reordered_header: Dictionary = {}
	reordered_header[&"schema_id"] = BookmarkChunkCodec.STREAM_SCHEMA_ID
	reordered_header[&"record_type"] = BookmarkChunkDecoder.RECORD_CATALOG
	reordered_header[&"schema_version"] = BookmarkChunkCodec.STREAM_SCHEMA_VERSION
	reordered_header[&"business_schema_version"] = (
		BookmarkChunkCodec.BUSINESS_SCHEMA_VERSION
	)
	reordered_header[&"bookmark_count"] = 0
	assert_true(BookmarkChunkCodec.decode_chunks(
		_make_test_stream([reordered_header])
	) == null)


func test_codec_rejects_state_string_packed_container_and_object_before_encode() -> void:
	var oversized_bytes: PackedByteArray = PackedByteArray()
	assert_true(oversized_bytes.resize(65 * 1024) == OK)
	var oversized_container: Array[int] = []
	for value: int in range(2049):
		oversized_container.append(value)
	var rejected_values: Array = [
		"x".repeat(17 * 1024),
		oversized_bytes,
		oversized_container,
		RefCounted.new(),
	]
	for rejected_value: Variant in rejected_values:
		var record: Dictionary = _make_bookmark(103, 2048).to_dict()
		record["extra_stats"] = {&"unsafe": rejected_value}
		var source: BookmarkChunkSourceSnapshot = (
			BookmarkChunkSourceSnapshot.take_ownership_of_immutable_items([record])
		)
		assert_not_null(source)
		if source == null:
			continue
		var codec: BookmarkChunkCodec = BookmarkChunkCodec.begin_encode(source)
		assert_not_null(codec)
		if codec == null:
			continue
		while not codec.is_complete() and not codec.is_failed():
			var _consumed: int = codec.advance(1)
		assert_true(codec.is_failed())
		assert_true(codec.get_error_code() == ERR_OUT_OF_MEMORY)
		assert_true(codec.take_chunks_taking_ownership().is_empty())


func test_source_snapshot_helpers_reuse_frozen_aliases_and_copy_only_batches() -> void:
	var record: Dictionary = _make_bookmark(104, 2048).to_dict()
	var board_value: Variant = record.get(&"board_snapshot")
	assert_true(board_value is Dictionary)
	if not board_value is Dictionary:
		return
	var board: Dictionary = board_value
	var topology_value: Variant = board.get(&"topology")
	var cells_value: Variant = null
	if topology_value is Dictionary:
		var topology: Dictionary = topology_value
		cells_value = topology.get(&"active_cells")
	assert_true(topology_value is Dictionary and cells_value is Array)
	if not topology_value is Dictionary or not cells_value is Array:
		return
	var original_cells: Array = cells_value
	var original_tiles: Array = [{
		&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": GFUuid.generate_v7(104001),
		&"definition_id": &"tile.classic.numeric",
		&"value": 2,
		&"capability_recipe_ids": [&"tile.recipe.classic_merge"],
		&"capability_state": {},
		&"pos": Vector2i.ZERO,
	}]
	board[&"tiles"] = original_tiles
	record["highest_tile"] = 2

	var source: BookmarkChunkSourceSnapshot = (
		BookmarkChunkSourceSnapshot.take_ownership_of_immutable_items([record])
	)
	assert_not_null(source)
	if source == null:
		return
	var first_metadata_value: Variant = source.make_record_metadata(0)
	var second_metadata_value: Variant = source.make_record_metadata(0)
	assert_true(
		first_metadata_value is Dictionary
		and second_metadata_value is Dictionary
		and is_same(first_metadata_value, second_metadata_value),
		"metadata helper 必须复用接管时冻结的小根，不能重复扫描大 record。"
	)
	var record_views_value: Variant = source.get(&"_record_views")
	assert_true(record_views_value is Array)
	if not record_views_value is Array:
		return
	var record_views: Array = record_views_value
	assert_true(record_views.size() == 1 and record_views[0] is Dictionary)
	if record_views.size() != 1 or not record_views[0] is Dictionary:
		return
	var record_view: Dictionary = record_views[0]
	assert_true(
		is_same(record_view.get(&"cells"), original_cells)
		and is_same(record_view.get(&"tiles"), original_tiles),
		"cell/tile helper 必须持有冻结 alias，不能预先 deep-copy 整个 board。"
	)
	var cell_batch_value: Variant = source.make_topology_cell_batch(0, 0)
	var tile_batch_value: Variant = source.make_tile_batch(0, 0)
	assert_true(cell_batch_value is Array and tile_batch_value is Array)
	if not cell_batch_value is Array or not tile_batch_value is Array:
		return
	var cell_batch: Array = cell_batch_value
	var tile_batch: Array = tile_batch_value
	assert_true(
		cell_batch.size() <= BookmarkChunkSourceSnapshot.TOPOLOGY_CELL_BATCH_SIZE
		and tile_batch.size() == 1
		and is_same(tile_batch[0], original_tiles[0]),
		"helper 只能构造固定小批；单 tile 仍应引用已预算的冻结 envelope。"
	)


func test_wrapper_requires_first_save_lease_then_claims_and_reuses_manifest() -> void:
	var business: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var bookmark: BookmarkData = _make_bookmark(101, 2048)
	assert_true(
		business.replace_section_data({&"items": [bookmark.to_dict()]}) == OK
	)
	var provider: BookmarkManifestSaveSectionProvider = (
		BookmarkManifestSaveSectionProvider.new(business)
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
			&"bookmarks": lease,
		},
	})
	assert_not_null(operation)
	if operation == null:
		return
	assert_true(operation.advance_for_framework(1) == 1)
	assert_true(operation.is_pending(), "header unit 后仍须等待逐 frame 编码。")
	var guard: int = 0
	while operation.is_pending() and not lease.is_ready_to_stage() and guard < 10_000:
		assert_true(operation.advance_for_framework(1) == 1)
		guard += 1
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
	assert_true(claimed_manifest.get_section_schema_version() == 10)
	assert_true(provider.commit_candidate_manifest(
		claimed_manifest,
		lease.get_producer_revision()
	))

	var reused: GFSaveSectionSnapshotOperation = provider.begin_save_snapshot({})
	assert_not_null(reused)
	if reused == null:
		return
	assert_true(reused.is_successful(), "clean active Manifest 应无 lease 直接复用。")
	provider.mark_business_data_changed()
	assert_null(
		provider.begin_save_snapshot({}),
		"已有 Manifest 但业务 revision dirty 时仍不得 inline 保存。"
	)


func test_wrapper_load_decodes_strictly_and_rollback_restores_business_catalog() -> void:
	var business: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var old_bookmark: BookmarkData = _make_large_trace_bookmark(201, 1024)
	assert_true(
		business.replace_section_data({&"items": [old_bookmark.to_dict()]}) == OK
	)
	var old_root: Dictionary = business.make_shallow_rollback_state()
	var provider: BookmarkManifestSaveSectionProvider = (
		BookmarkManifestSaveSectionProvider.new(business)
	)
	var incoming_catalog: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var new_bookmark: BookmarkData = _make_bookmark(202, 4096)
	assert_true(incoming_catalog.replace_section_data({
		&"items": [new_bookmark.to_dict()],
	}) == OK)
	var chunks: Array[PackedByteArray] = _encode_source(
		incoming_catalog.make_chunk_source_snapshot()
	)
	var manifest: ChunkManifest = ChunkManifest.create(
		&"bookmarks",
		BookmarkManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
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
		),
		"损坏 stream 必须在 GF Provider apply callback 前被拒绝。"
	)
	assert_true(corrupted_chunks.is_empty())
	var materialization: ChunkMaterializationLease = (
		await provider.make_materialization_lease_async_taking_ownership(
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
			&"bookmarks": materialization,
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
		"大型 Bookmark 旧根只能暂存在 lease，GF rollback section 必须是小 sentinel。"
	)
	assert_true(materialization.is_rollback_root_available())
	assert_true(provider.apply_section(section, load_context) == OK)
	assert_true(materialization.is_claimed())
	assert_true(_first_bookmark_score(business) == 4096)
	var malformed_manifest_metadata: Dictionary = previous.get_metadata()
	malformed_manifest_metadata[&"chunk_committed_revision"] = 0
	malformed_manifest_metadata[&"chunk_active_manifest"] = {&"bad": true}
	var malformed_manifest_previous: GFSaveSection = provider.make_section(
		previous.get_payload(),
		malformed_manifest_metadata
	)
	assert_not_null(malformed_manifest_previous)
	if malformed_manifest_previous == null:
		return
	assert_true(
		provider.rollback_section(malformed_manifest_previous, load_context)
		== ERR_INVALID_DATA
	)
	assert_true(materialization.is_rollback_root_available())
	var malformed_metadata: Dictionary = previous.get_metadata()
	malformed_metadata[&"chunk_revision"] = "not-an-int"
	var malformed_previous: GFSaveSection = provider.make_section(
		previous.get_payload(),
		malformed_metadata
	)
	assert_not_null(malformed_previous)
	if malformed_previous == null:
		return
	assert_true(
		provider.rollback_section(malformed_previous, load_context)
		== ERR_INVALID_DATA
	)
	assert_true(
		materialization.is_rollback_root_available(),
		"畸形 metadata 不得先 claim/消费 shallow rollback root。"
	)
	assert_true(_first_bookmark_score(business) == 4096)
	assert_true(provider.rollback_section(previous, load_context) == OK)
	assert_true(_first_bookmark_score(business) == 1024)
	assert_false(materialization.is_rollback_root_available())
	var restored_root: Dictionary = business.make_shallow_rollback_state()
	# get_option_array() 会按契约深复制；这里必须读取根引用，才能验证
	# shallow rollback 恢复的是原 immutable envelope，而非等值重建。
	var old_items: Array = GFVariantData.as_array(old_root.get(&"items"))
	var restored_items: Array = GFVariantData.as_array(restored_root.get(&"items"))
	assert_true(
		old_items.size() == 1
		and restored_items.size() == 1
		and is_same(old_items[0], restored_items[0]),
		"rollback 必须恢复同一个 immutable Bookmark envelope。"
	)
	var old_decoded: Dictionary = GFVariantData.get_option_dictionary(
		old_root,
		&"decoded_items_by_id"
	)
	var restored_decoded: Dictionary = GFVariantData.get_option_dictionary(
		restored_root,
		&"decoded_items_by_id"
	)
	assert_true(
		old_decoded.has(old_bookmark.bookmark_id)
		and restored_decoded.has(old_bookmark.bookmark_id)
		and is_same(
			old_decoded.get(old_bookmark.bookmark_id),
			restored_decoded.get(old_bookmark.bookmark_id)
		),
		"rollback 必须恢复同一个已验证 BookmarkData cache 对象。"
	)


# --- 私有/辅助方法 ---

func _encode_records(
	records: Array[Dictionary]
) -> Array[PackedByteArray]:
	return _encode_source(
		BookmarkChunkSourceSnapshot.take_ownership_of_immutable_items(
			records.duplicate()
		)
	)


func _encode_source(
	source: BookmarkChunkSourceSnapshot
) -> Array[PackedByteArray]:
	assert_not_null(source)
	if source == null:
		return []
	var codec: BookmarkChunkCodec = BookmarkChunkCodec.begin_encode(source)
	assert_not_null(codec)
	if codec == null:
		return []
	var guard: int = 0
	while not codec.is_complete() and not codec.is_failed() and guard < 100_000:
		var consumed: int = codec.advance(1)
		if consumed != 1:
			assert_true(false, "每次 codec.advance(1) 必须推进一个有界 frame。")
			break
		guard += 1
	assert_false(codec.is_failed(), codec.get_error())
	assert_true(codec.is_complete())
	return codec.take_chunks_taking_ownership()


func _make_test_stream(
	frames: Array
) -> Array[PackedByteArray]:
	var stream: PackedByteArray = PackedByteArray()
	for frame_value: Variant in frames:
		_append_test_frame(stream, frame_value)
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
			offset + BookmarkChunkCodec.CHUNK_BYTES,
			stream.size()
		)
		chunks.append(stream.slice(offset, next_offset))
		offset = next_offset
	return chunks


func _duplicate_chunks(
	chunks: Array[PackedByteArray]
) -> Array[PackedByteArray]:
	var duplicates: Array[PackedByteArray] = []
	for chunk: PackedByteArray in chunks:
		duplicates.append(chunk.duplicate())
	return duplicates


func _make_save_lease(producer_revision: int) -> ChunkSaveLease:
	return ChunkSaveLease.create(
		&"bookmark-test-lease",
		&"accounts.primary.player_profile",
		"profiles/primary.save",
		&"bookmarks",
		BookmarkManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		producer_revision,
		"accounts.primary.chunks.bookmarks"
	)


func _first_bookmark_score(provider: BookmarkCatalogSaveData) -> int:
	var items: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		&"items"
	)
	if items.is_empty() or not items[0] is Dictionary:
		return -1
	return GFVariantData.get_option_int(
		GFVariantData.as_dictionary(items[0]),
		&"score",
		-1
	)


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.bookmark_id = GFUuid.generate_v7(timestamp * 1000)
	bookmark.mode_config_path = (
		"res://features/gameplay/resources/modes/classic_mode_config.tres"
	)
	var mode_value: Resource = load(bookmark.mode_config_path)
	assert_true(mode_value is GameModeConfig)
	if mode_value is GameModeConfig:
		var mode: GameModeConfig = mode_value
		bookmark.ruleset_id = mode.ruleset_id
		bookmark.ruleset_version = mode.ruleset_version
		bookmark.ruleset_fingerprint = (
			GameDeterminismUtility.new().calculate_ruleset_fingerprint(mode)
		)
		bookmark.rules_states = RuleSystem.capture_rule_states(mode.spawn_rules)
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	bookmark.initial_seed = 2048
	bookmark.rng_full_state = seed_utility.get_full_state()
	bookmark.score = score
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	bookmark.board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	bookmark.game_state_history = {&"undo": [], &"redo": []}
	return bookmark


func _make_large_trace_bookmark(timestamp: int, score: int) -> BookmarkData:
	return _make_trace_bookmark(
		timestamp,
		score,
		BookmarkData.PERSISTED_REPLAY_TRACE_LIMIT
	)


func _make_trace_bookmark(
	timestamp: int,
	score: int,
	step_count: int
) -> BookmarkData:
	var bookmark: BookmarkData = _make_bookmark(timestamp, score)
	bookmark.move_count = step_count
	for index: int in range(step_count):
		bookmark.replay_actions.append(Vector2i.RIGHT)
		var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
		checkpoint.step_index = index + 1
		checkpoint.state_checksum = "a".repeat(64)
		checkpoint.board_checksum = "b".repeat(64)
		checkpoint.rng_checksum = "c".repeat(64)
		checkpoint.score = (
			score
			if index == step_count - 1
			else mini(index, score)
		)
		bookmark.replay_checkpoints.append(checkpoint)
	return bookmark
