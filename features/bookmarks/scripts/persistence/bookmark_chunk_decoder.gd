## Bookmark stream v2 的严格可推进解码器。
##
## 每个 advance work unit 至多读取一个不超过 128 KiB 的 outer frame；棋盘、
## 历史 bytes 与 replay trace 均分批恢复。完整 BookmarkData 与持久化 envelope
## 在流末一次构造为 PreparedState，GF apply callback 只交换有限根。
class_name BookmarkChunkDecoder
extends RefCounted


# --- 常量 ---

const STREAM_SCHEMA_ID: StringName = &"bookmark_record_stream"
const STREAM_SCHEMA_VERSION: int = 2
const BUSINESS_SCHEMA_VERSION: int = BookmarkCatalogSaveData.SCHEMA_VERSION
const CHUNK_BYTES: int = ChunkManifest.MAX_CHUNK_BYTES
const MAX_TOTAL_BYTES: int = ChunkManifest.MAX_TOTAL_BYTES
const MAX_FRAME_BYTES: int = ChunkManifest.MAX_CHUNK_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = MAX_FRAME_BYTES - 4

const TOPOLOGY_CELL_BATCH_SIZE: int = (
	BookmarkChunkSourceSnapshot.TOPOLOGY_CELL_BATCH_SIZE
)
const FINAL_TILE_BATCH_SIZE: int = (
	BookmarkChunkSourceSnapshot.FINAL_TILE_BATCH_SIZE
)
const HISTORY_BYTE_BATCH_SIZE: int = (
	BookmarkChunkSourceSnapshot.HISTORY_BYTE_BATCH_SIZE
)

const RECORD_CATALOG: StringName = &"catalog"
const RECORD_BOOKMARK_METADATA: StringName = &"bookmark_metadata"
const RECORD_STATE: StringName = &"state"
const RECORD_TOPOLOGY_CELLS: StringName = &"topology_cells"
const RECORD_TILES: StringName = &"tiles"
const RECORD_HISTORY_BYTES: StringName = &"history_bytes"
const RECORD_REPLAY_STEP: StringName = &"replay_step"

const _LENGTH_PREFIX_BYTES: int = 4
const _PHASE_HEADER: int = 0
const _PHASE_METADATA: int = 1
const _PHASE_STATES: int = 2
const _PHASE_CELLS: int = 3
const _PHASE_TILES: int = 4
const _PHASE_HISTORY: int = 5
const _PHASE_REPLAY: int = 6

const _HEADER_FIELDS: Array[StringName] = [
	&"record_type",
	&"schema_id",
	&"schema_version",
	&"business_schema_version",
	&"bookmark_count",
]
const _METADATA_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"schema_version",
	&"bookmark_id",
	&"timestamp",
	&"mode_config_path",
	&"ruleset_id",
	&"ruleset_version",
	&"ruleset_fingerprint",
	&"initial_seed",
	&"score",
	&"move_count",
	&"ratio_resolutions",
	&"highest_tile",
	&"target_tile_value",
	&"target_reached",
	&"board_schema_version",
	&"topology_schema_version",
	&"topology_id",
	&"active_cell_count",
	&"tile_count",
	&"history_byte_count",
	&"replay_step_count",
]
const _STATE_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"state_kind",
	&"value",
]
const _CELL_BATCH_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"start_index",
	&"cells",
]
const _TILE_BATCH_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"start_index",
	&"tiles",
]
const _HISTORY_BATCH_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"start_offset",
	&"bytes",
]
const _REPLAY_STEP_FIELDS: Array[StringName] = [
	&"record_type",
	&"bookmark_index",
	&"step_index",
	&"action",
	&"checkpoint",
]


# --- 私有变量 ---

var _reader: _ChunkReader = null
var _phase: int = _PHASE_HEADER
var _bookmark_count: int = -1
var _next_bookmark_index: int = 0
var _current_metadata: Dictionary = {}
var _current_states: Dictionary = {}
var _current_state_index: int = 0
var _current_cell_count: int = 0
var _current_tile_count: int = 0
var _current_history_byte_count: int = 0
var _current_step_count: int = 0
var _current_cell_index: int = 0
var _current_tile_index: int = 0
var _current_history_offset: int = 0
var _current_step_index: int = 0
var _current_cells: Array[Vector2i] = []
var _current_tiles: Array[Dictionary] = []
var _current_history_bytes: PackedByteArray = PackedByteArray()
var _current_actions: Array[Vector2i] = []
var _current_checkpoint_dicts: Array[Dictionary] = []
var _current_checkpoints: Array[ReplayCheckpoint] = []
var _cell_lookup: Dictionary = {}
var _has_previous_cell: bool = false
var _previous_cell: Vector2i = Vector2i.ZERO
var _minimum_cell: Vector2i = Vector2i.ZERO
var _items: Array[Dictionary] = []
var _decoded_items_by_id: Dictionary = {}
var _seen_bookmark_ids: Dictionary = {}
var _prepared_state: BookmarkCatalogPreparedState = null
var _complete: bool = false
var _prepared_state_claimed: bool = false
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 接管 chunks 的只读元素别名；调用方返回后必须放弃原数组及其元素。
## @param chunks: 已满足 Manifest 总量与单块边界的有序 chunk 根。
static func begin_decode(
	chunks: Array[PackedByteArray]
) -> BookmarkChunkDecoder:
	if not _validate_chunk_boundaries(chunks):
		return null
	var owned_root: Array[PackedByteArray] = chunks.duplicate()
	var decoder: BookmarkChunkDecoder = BookmarkChunkDecoder.new()
	decoder._reader = _ChunkReader.new(owned_root)
	return decoder


## 在 frame 预算内推进；每个 unit 只消费一个有界 outer frame。
## @param frame_budget: 本次调用允许消费的最大 outer frame 数。
func advance(frame_budget: int) -> int:
	if frame_budget <= 0 or _complete or is_failed() or _reader == null:
		return 0
	var consumed_units: int = 0
	while consumed_units < frame_budget and not _complete and not is_failed():
		var frame_result: Dictionary = _read_variant_frame(_reader)
		if not GFVariantData.get_option_bool(frame_result, &"ok", false):
			_fail(ERR_FILE_CORRUPT, "Bookmark stream frame is invalid.")
			break
		var frame_value: Variant = frame_result.get(&"value")
		if not frame_value is Dictionary:
			_fail(ERR_FILE_CORRUPT, "Bookmark frame must be a Dictionary.")
			break
		var frame: Dictionary = frame_value
		var accepted: bool = false
		match _phase:
			_PHASE_HEADER:
				accepted = _consume_header(frame)
			_PHASE_METADATA:
				accepted = _consume_metadata(frame)
			_PHASE_STATES:
				accepted = _consume_state(frame)
			_PHASE_CELLS:
				accepted = _consume_cell_batch(frame)
			_PHASE_TILES:
				accepted = _consume_tile_batch(frame)
			_PHASE_HISTORY:
				accepted = _consume_history_batch(frame)
			_PHASE_REPLAY:
				accepted = _consume_replay_step(frame)
			_:
				accepted = false
		consumed_units += 1
		if not accepted and not is_failed():
			_fail(
				ERR_FILE_CORRUPT,
				"Bookmark stream record violates its phase schema."
			)
	return consumed_units


func is_complete() -> bool:
	return _complete and not is_failed()


func is_failed() -> bool:
	return _error_code != OK


func get_error_code() -> Error:
	return _error_code


func get_error() -> String:
	return _error


func get_decoded_record_count() -> int:
	return (
		_prepared_state.get_item_count()
		if _prepared_state != null
		else _items.size()
	)


func take_prepared_state_taking_ownership() -> BookmarkCatalogPreparedState:
	if (
		not is_complete()
		or _prepared_state_claimed
		or _prepared_state == null
	):
		return null
	_prepared_state_claimed = true
	var owned_state: BookmarkCatalogPreparedState = _prepared_state
	_prepared_state = null
	return owned_state


# --- 私有/辅助方法 ---

func _consume_header(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _HEADER_FIELDS)
		or not _has_record_type(frame, RECORD_CATALOG)
	):
		return false
	var schema_id_value: Variant = frame.get(&"schema_id")
	var stream_version_value: Variant = frame.get(&"schema_version")
	var business_version_value: Variant = frame.get(&"business_schema_version")
	var count_value: Variant = frame.get(&"bookmark_count")
	if (
		not schema_id_value is StringName
		or not stream_version_value is int
		or not business_version_value is int
		or not count_value is int
	):
		return false
	var count: int = count_value
	if (
		schema_id_value != STREAM_SCHEMA_ID
		or stream_version_value != STREAM_SCHEMA_VERSION
		or business_version_value != BUSINESS_SCHEMA_VERSION
		or count < 0
		or count > BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
	):
		return false
	_bookmark_count = count
	if count == 0:
		return _complete_stream()
	_phase = _PHASE_METADATA
	return true


func _consume_metadata(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _METADATA_FIELDS)
		or not _has_record_type(frame, RECORD_BOOKMARK_METADATA)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
		or not _is_valid_scalar_metadata(frame)
	):
		return false
	var bookmark_id: String = GFVariantData.get_option_string(
		frame,
		&"bookmark_id"
	)
	if _seen_bookmark_ids.has(bookmark_id):
		return false
	_seen_bookmark_ids[bookmark_id] = true
	_current_metadata = frame.duplicate(false)
	var _removed_record_type: bool = _current_metadata.erase(&"record_type")
	var _removed_bookmark_index: bool = _current_metadata.erase(
		&"bookmark_index"
	)
	_current_cell_count = GFVariantData.get_option_int(
		frame,
		&"active_cell_count",
		-1
	)
	_current_tile_count = GFVariantData.get_option_int(frame, &"tile_count", -1)
	_current_history_byte_count = GFVariantData.get_option_int(
		frame,
		&"history_byte_count",
		-1
	)
	_current_step_count = GFVariantData.get_option_int(
		frame,
		&"replay_step_count",
		-1
	)
	_current_states = {}
	_current_state_index = 0
	_current_cell_index = 0
	_current_tile_index = 0
	_current_history_offset = 0
	_current_step_index = 0
	_current_cells = []
	_current_tiles = []
	_current_history_bytes = PackedByteArray()
	_current_actions = []
	_current_checkpoint_dicts = []
	_current_checkpoints = []
	_cell_lookup = {}
	_has_previous_cell = false
	_previous_cell = Vector2i.ZERO
	_minimum_cell = Vector2i.ZERO
	_phase = _PHASE_STATES
	return true


func _consume_state(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _STATE_FIELDS)
		or not _has_record_type(frame, RECORD_STATE)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
	):
		return false
	var kind_value: Variant = frame.get(&"state_kind")
	var state_value: Variant = frame.get(&"value")
	if not kind_value is StringName or not state_value is Dictionary:
		return false
	var expected_kind: StringName = (
		BookmarkChunkSourceSnapshot.STATE_KINDS[_current_state_index]
	)
	if kind_value != expected_kind:
		return false
	if (
		expected_kind == BookmarkChunkSourceSnapshot.STATE_SESSION_METADATA
		and GameSessionMetadata.from_dict(
			GFVariantData.as_dictionary(state_value)
		) == null
	):
		return false
	_current_states[expected_kind] = state_value
	_current_state_index += 1
	if _current_state_index == BookmarkChunkSourceSnapshot.STATE_KINDS.size():
		_phase = _PHASE_CELLS
	return true


func _consume_cell_batch(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _CELL_BATCH_FIELDS)
		or not _has_record_type(frame, RECORD_TOPOLOGY_CELLS)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
		or not _has_expected_index(frame, &"start_index", _current_cell_index)
	):
		return false
	var cells_value: Variant = frame.get(&"cells")
	if not cells_value is Array:
		return false
	var cells: Array = cells_value
	var expected_count: int = mini(
		TOPOLOGY_CELL_BATCH_SIZE,
		_current_cell_count - _current_cell_index
	)
	if expected_count <= 0 or cells.size() != expected_count:
		return false
	for cell_value: Variant in cells:
		if not cell_value is Vector2i:
			return false
		var cell: Vector2i = cell_value
		if cell.x < 0 or cell.y < 0 or _cell_lookup.has(cell):
			return false
		if _has_previous_cell and not _is_row_major_before(_previous_cell, cell):
			return false
		if not _has_previous_cell:
			_minimum_cell = cell
			_has_previous_cell = true
		else:
			_minimum_cell.x = mini(_minimum_cell.x, cell.x)
			_minimum_cell.y = mini(_minimum_cell.y, cell.y)
		_previous_cell = cell
		_cell_lookup[cell] = true
		_current_cells.append(cell)
	_current_cell_index += cells.size()
	if _current_cell_index == _current_cell_count:
		if _minimum_cell != Vector2i.ZERO:
			return false
		_phase = _PHASE_TILES if _current_tile_count > 0 else _PHASE_HISTORY
	return true


func _consume_tile_batch(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _TILE_BATCH_FIELDS)
		or not _has_record_type(frame, RECORD_TILES)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
		or not _has_expected_index(frame, &"start_index", _current_tile_index)
	):
		return false
	var tiles_value: Variant = frame.get(&"tiles")
	if not tiles_value is Array:
		return false
	var tiles: Array = tiles_value
	var expected_count: int = mini(
		FINAL_TILE_BATCH_SIZE,
		_current_tile_count - _current_tile_index
	)
	if expected_count <= 0 or tiles.size() != expected_count:
		return false
	for tile_value: Variant in tiles:
		if not tile_value is Dictionary:
			return false
		_current_tiles.append(GFVariantData.as_dictionary(tile_value))
	_current_tile_index += tiles.size()
	if _current_tile_index == _current_tile_count:
		_phase = _PHASE_HISTORY
	return true


func _consume_history_batch(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _HISTORY_BATCH_FIELDS)
		or not _has_record_type(frame, RECORD_HISTORY_BYTES)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
		or not _has_expected_index(
			frame,
			&"start_offset",
			_current_history_offset
		)
	):
		return false
	var bytes_value: Variant = frame.get(&"bytes")
	if not bytes_value is PackedByteArray:
		return false
	var bytes: PackedByteArray = bytes_value
	var expected_count: int = mini(
		HISTORY_BYTE_BATCH_SIZE,
		_current_history_byte_count - _current_history_offset
	)
	if expected_count <= 0 or bytes.size() != expected_count:
		return false
	_current_history_bytes.append_array(bytes)
	_current_history_offset += bytes.size()
	if _current_history_offset == _current_history_byte_count:
		if _current_step_count > 0:
			_phase = _PHASE_REPLAY
		else:
			return _finish_current_bookmark()
	return true


func _consume_replay_step(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _REPLAY_STEP_FIELDS)
		or not _has_record_type(frame, RECORD_REPLAY_STEP)
		or not _has_expected_index(
			frame,
			&"bookmark_index",
			_next_bookmark_index
		)
		or not _has_expected_index(frame, &"step_index", _current_step_index)
	):
		return false
	var action_value: Variant = frame.get(&"action")
	var checkpoint_value: Variant = frame.get(&"checkpoint")
	if not action_value is Vector2i or not checkpoint_value is Dictionary:
		return false
	var action: Vector2i = action_value
	if not _is_cardinal_direction(action):
		return false
	var checkpoint_payload: Dictionary = checkpoint_value
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.from_dict(
		checkpoint_payload
	)
	if checkpoint == null or checkpoint.step_index != _current_step_index + 1:
		return false
	_current_actions.append(action)
	_current_checkpoint_dicts.append(checkpoint_payload)
	_current_checkpoints.append(checkpoint)
	_current_step_index += 1
	if _current_step_index == _current_step_count:
		return _finish_current_bookmark()
	return true


func _finish_current_bookmark() -> bool:
	if (
		_current_state_index != BookmarkChunkSourceSnapshot.STATE_KINDS.size()
		or _current_cell_index != _current_cell_count
		or _current_tile_index != _current_tile_count
		or _current_history_offset != _current_history_byte_count
		or _current_step_index != _current_step_count
		or (
			_current_step_count > 0
			and _current_checkpoints.back().score
			!= GFVariantData.get_option_int(_current_metadata, &"score", -1)
		)
	):
		return false
	var topology: Dictionary = {
		&"schema_version": _current_metadata.get(&"topology_schema_version"),
		&"topology_id": _current_metadata.get(&"topology_id"),
		&"active_cells": _current_cells,
	}
	var board_snapshot: Dictionary = {
		&"schema_version": _current_metadata.get(&"board_schema_version"),
		&"topology": topology,
		&"tiles": _current_tiles,
	}
	if not GridModel.is_snapshot_envelope_valid(board_snapshot):
		return false
	var history_payload: PackedByteArray = _current_history_bytes
	var envelope: Dictionary = {
		"schema_version": BookmarkData.SCHEMA_VERSION,
		"bookmark_id": _current_metadata.get(&"bookmark_id"),
		"timestamp": _current_metadata.get(&"timestamp"),
		"mode_config_path": _current_metadata.get(&"mode_config_path"),
		"ruleset_id": _current_metadata.get(&"ruleset_id"),
		"ruleset_version": _current_metadata.get(&"ruleset_version"),
		"ruleset_fingerprint": _current_metadata.get(&"ruleset_fingerprint"),
		"initial_seed": _current_metadata.get(&"initial_seed"),
		"session_metadata": _current_states.get(
			BookmarkChunkSourceSnapshot.STATE_SESSION_METADATA
		),
		"score": _current_metadata.get(&"score"),
		"move_count": _current_metadata.get(&"move_count"),
		"ratio_resolutions": _current_metadata.get(&"ratio_resolutions"),
		"highest_tile": _current_metadata.get(&"highest_tile"),
		"target_tile_value": _current_metadata.get(&"target_tile_value"),
		"target_reached": _current_metadata.get(&"target_reached"),
		"extra_stats": _current_states.get(
			BookmarkChunkSourceSnapshot.STATE_EXTRA_STATS
		),
		"rng_full_state": _current_states.get(
			BookmarkChunkSourceSnapshot.STATE_RNG_FULL_STATE
		),
		"board_snapshot": board_snapshot,
		"rules_states": _current_states.get(
			BookmarkChunkSourceSnapshot.STATE_RULES_STATES
		),
		"game_state_history": {
			"codec": "gf_storage_binary_v1",
			"payload": history_payload,
		},
		"replay_actions": _current_actions,
		"replay_checkpoints": _current_checkpoint_dicts,
	}
	var decoded: BookmarkData = (
		BookmarkData.take_ownership_of_validated_chunk_parts(
			envelope,
			history_payload,
			_current_actions,
			_current_checkpoints
		)
	)
	if decoded == null:
		return false
	_items.append(envelope)
	_decoded_items_by_id[decoded.bookmark_id] = decoded
	_next_bookmark_index += 1
	_clear_current_bookmark()
	if _next_bookmark_index == _bookmark_count:
		return _complete_stream()
	_phase = _PHASE_METADATA
	return true


func _complete_stream() -> bool:
	if (
		_reader == null
		or _reader.get_remaining_bytes() != 0
		or _items.size() != _bookmark_count
	):
		return false
	var prepared_state: BookmarkCatalogPreparedState = (
		BookmarkCatalogPreparedState.take_ownership_of_validated_roots(
			_items,
			_decoded_items_by_id
		)
	)
	if prepared_state == null:
		return false
	_items = []
	_decoded_items_by_id = {}
	_prepared_state = prepared_state
	_complete = true
	_reader.release()
	_reader = null
	return true


func _clear_current_bookmark() -> void:
	_current_metadata = {}
	_current_states = {}
	_current_state_index = 0
	_current_cell_count = 0
	_current_tile_count = 0
	_current_history_byte_count = 0
	_current_step_count = 0
	_current_cell_index = 0
	_current_tile_index = 0
	_current_history_offset = 0
	_current_step_index = 0
	_current_cells = []
	_current_tiles = []
	_current_history_bytes = PackedByteArray()
	_current_actions = []
	_current_checkpoint_dicts = []
	_current_checkpoints = []
	_cell_lookup = {}
	_has_previous_cell = false
	_previous_cell = Vector2i.ZERO
	_minimum_cell = Vector2i.ZERO


func _fail(error_code: Error, error: String) -> void:
	_error_code = error_code if error_code != OK else ERR_FILE_CORRUPT
	_error = error
	_items.clear()
	_decoded_items_by_id.clear()
	_seen_bookmark_ids.clear()
	_prepared_state = null
	_clear_current_bookmark()
	if _reader != null:
		_reader.release()
	_reader = null


static func _is_valid_scalar_metadata(frame: Dictionary) -> bool:
	var fields_are_typed: bool = (
		frame.get(&"schema_version") is int
		and frame.get(&"bookmark_id") is String
		and frame.get(&"timestamp") is int
		and frame.get(&"mode_config_path") is String
		and frame.get(&"ruleset_id") is StringName
		and frame.get(&"ruleset_version") is int
		and frame.get(&"ruleset_fingerprint") is String
		and frame.get(&"initial_seed") is int
		and frame.get(&"score") is int
		and frame.get(&"move_count") is int
		and frame.get(&"ratio_resolutions") is int
		and frame.get(&"highest_tile") is int
		and frame.get(&"target_tile_value") is int
		and frame.get(&"target_reached") is bool
		and frame.get(&"board_schema_version") is int
		and frame.get(&"topology_schema_version") is int
		and frame.get(&"topology_id") is String
		and frame.get(&"active_cell_count") is int
		and frame.get(&"tile_count") is int
		and frame.get(&"history_byte_count") is int
		and frame.get(&"replay_step_count") is int
	)
	if not fields_are_typed:
		return false
	var bookmark_id: String = frame.get(&"bookmark_id")
	var timestamp: int = frame.get(&"timestamp")
	var mode_path: String = frame.get(&"mode_config_path")
	var ruleset_id: StringName = frame.get(&"ruleset_id")
	var fingerprint: String = frame.get(&"ruleset_fingerprint")
	var score: int = frame.get(&"score")
	var move_count: int = frame.get(&"move_count")
	var ratio_resolutions: int = frame.get(&"ratio_resolutions")
	var highest_tile: int = frame.get(&"highest_tile")
	var target_value: int = frame.get(&"target_tile_value")
	var target_reached: bool = frame.get(&"target_reached")
	var cell_count: int = frame.get(&"active_cell_count")
	var tile_count: int = frame.get(&"tile_count")
	var history_byte_count: int = frame.get(&"history_byte_count")
	var replay_step_count: int = frame.get(&"replay_step_count")
	return (
		frame.get(&"schema_version") == BookmarkData.SCHEMA_VERSION
		and GFUuid.is_valid(bookmark_id, 7)
		and timestamp >= 0
		and not mode_path.is_empty()
		and ruleset_id != &""
		and frame.get(&"ruleset_version") > 0
		and _is_sha256(fingerprint)
		and score >= 0
		and move_count >= 0
		and ratio_resolutions >= 0
		and highest_tile >= 0
		and target_value >= 0
		and (not target_reached if target_value == 0 else (
			target_reached or highest_tile < target_value
		))
		and frame.get(&"board_schema_version")
		== GridModel.SNAPSHOT_SCHEMA_VERSION
		and frame.get(&"topology_schema_version")
		== BoardTopology.SERIALIZATION_SCHEMA_VERSION
		and not GFVariantData.get_option_string(
			frame,
			&"topology_id"
		).is_empty()
		and cell_count > 0
		and cell_count <= BookmarkData.PERSISTED_BOARD_CELL_LIMIT
		and tile_count >= 0
		and tile_count <= cell_count
		and history_byte_count > 0
		and history_byte_count <= BookmarkData.MAX_HISTORY_PAYLOAD_BYTES
		and replay_step_count >= 0
		and replay_step_count <= BookmarkData.PERSISTED_REPLAY_TRACE_LIMIT
	)


static func _read_variant_frame(reader: _ChunkReader) -> Dictionary:
	var length_bytes: PackedByteArray = reader.read_exact(_LENGTH_PREFIX_BYTES)
	if length_bytes.size() != _LENGTH_PREFIX_BYTES:
		return {&"ok": false}
	var payload_length: int = _decode_u32(length_bytes)
	if (
		payload_length <= 0
		or payload_length > MAX_FRAME_PAYLOAD_BYTES
		or payload_length > reader.get_remaining_bytes()
	):
		return {&"ok": false}
	var payload: PackedByteArray = reader.read_exact(payload_length)
	if payload.size() != payload_length:
		return {&"ok": false}
	# bytes_to_var() 不允许对象；扫描后再 canonical re-encode，避免让恶意
	# 深层/巨容器 Variant 进入第二次递归序列化。
	var value: Variant = bytes_to_var(payload)
	if not BookmarkChunkSourceSnapshot.is_variant_within_frame_budget(value):
		return {&"ok": false}
	if var_to_bytes(value) != payload:
		return {&"ok": false}
	return {&"ok": true, &"value": value}


static func _validate_chunk_boundaries(
	chunks: Array[PackedByteArray]
) -> bool:
	if chunks.is_empty() or chunks.size() > ChunkManifest.MAX_CHUNK_COUNT:
		return false
	var total_bytes: int = 0
	for index: int in range(chunks.size()):
		var chunk: PackedByteArray = chunks[index]
		if chunk.is_empty() or chunk.size() > CHUNK_BYTES:
			return false
		if index < chunks.size() - 1 and chunk.size() != CHUNK_BYTES:
			return false
		total_bytes += chunk.size()
		if total_bytes > MAX_TOTAL_BYTES:
			return false
	return total_bytes > 0


static func _has_record_type(frame: Dictionary, expected: StringName) -> bool:
	var value: Variant = frame.get(&"record_type")
	return value is StringName and value == expected


static func _has_expected_index(
	frame: Dictionary,
	key: StringName,
	expected: int
) -> bool:
	var value: Variant = frame.get(key)
	return value is int and value == expected


static func _has_exact_fields(
	payload: Dictionary,
	fields: Array[StringName]
) -> bool:
	if payload.size() != fields.size():
		return false
	var keys: Array = payload.keys()
	for index: int in range(fields.size()):
		var key_value: Variant = keys[index]
		if not key_value is StringName or key_value != fields[index]:
			return false
	return true


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)


static func _is_cardinal_direction(direction: Vector2i) -> bool:
	return (
		direction == Vector2i.LEFT
		or direction == Vector2i.RIGHT
		or direction == Vector2i.UP
		or direction == Vector2i.DOWN
	)


static func _is_sha256(value: String) -> bool:
	return value.length() == 64 and value.to_lower().is_valid_hex_number()


static func _decode_u32(payload: PackedByteArray) -> int:
	return (
		(int(payload[0]) << 24)
		| (int(payload[1]) << 16)
		| (int(payload[2]) << 8)
		| int(payload[3])
	)


# --- 内部类 ---

class _ChunkReader extends RefCounted:
	var _chunks: Array[PackedByteArray] = []
	var _chunk_index: int = 0
	var _chunk_offset: int = 0
	var _remaining_bytes: int = 0

	func _init(chunks: Array[PackedByteArray]) -> void:
		_chunks = chunks
		for chunk: PackedByteArray in chunks:
			_remaining_bytes += chunk.size()

	func get_remaining_bytes() -> int:
		return _remaining_bytes

	## 使用 slice/append_array 跨 chunk 复制，禁止逐字节 8 MiB 循环。
	## @param byte_count: 要从当前读取位置精确取得的字节数。
	func read_exact(byte_count: int) -> PackedByteArray:
		if byte_count < 0 or byte_count > _remaining_bytes:
			return PackedByteArray()
		var result: PackedByteArray = PackedByteArray()
		var copied_bytes: int = 0
		while copied_bytes < byte_count:
			var chunk: PackedByteArray = _chunks[_chunk_index]
			var copy_count: int = mini(
				chunk.size() - _chunk_offset,
				byte_count - copied_bytes
			)
			result.append_array(
				chunk.slice(_chunk_offset, _chunk_offset + copy_count)
			)
			copied_bytes += copy_count
			_chunk_offset += copy_count
			_remaining_bytes -= copy_count
			if _chunk_offset == chunk.size():
				_chunk_index += 1
				_chunk_offset = 0
		return result

	func release() -> void:
		_chunks.clear()
		_chunk_index = 0
		_chunk_offset = 0
		_remaining_bytes = 0
