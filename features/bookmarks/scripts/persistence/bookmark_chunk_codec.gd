## bookmarks 的严格、版本化、有界分块流 codec。
##
## stream v2 每个 work unit 只序列化一个不超过 128 KiB 的结构化 frame；
## 大棋盘、2 MiB 历史和 8192-step replay 均不会形成单个同步记录。
class_name BookmarkChunkCodec
extends RefCounted


# --- 常量 ---

const STREAM_SCHEMA_ID: StringName = BookmarkChunkDecoder.STREAM_SCHEMA_ID
const STREAM_SCHEMA_VERSION: int = BookmarkChunkDecoder.STREAM_SCHEMA_VERSION
const BUSINESS_SCHEMA_VERSION: int = BookmarkChunkDecoder.BUSINESS_SCHEMA_VERSION
const CHUNK_BYTES: int = BookmarkChunkDecoder.CHUNK_BYTES
const MAX_TOTAL_BYTES: int = BookmarkChunkDecoder.MAX_TOTAL_BYTES
const MAX_FRAME_BYTES: int = BookmarkChunkDecoder.MAX_FRAME_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = (
	BookmarkChunkDecoder.MAX_FRAME_PAYLOAD_BYTES
)

const _LENGTH_PREFIX_BYTES: int = 4
const _PHASE_HEADER: int = 0
const _PHASE_METADATA: int = 1
const _PHASE_STATES: int = 2
const _PHASE_CELLS: int = 3
const _PHASE_TILES: int = 4
const _PHASE_HISTORY: int = 5
const _PHASE_REPLAY: int = 6


# --- 私有变量 ---

var _source: BookmarkChunkSourceSnapshot = null
var _phase: int = _PHASE_HEADER
var _next_record_index: int = 0
var _current_state_index: int = 0
var _current_cell_index: int = 0
var _current_tile_index: int = 0
var _current_history_offset: int = 0
var _current_step_index: int = 0
var _current_cell_count: int = -1
var _current_tile_count: int = -1
var _current_history_byte_count: int = -1
var _current_step_count: int = -1
var _complete: bool = false
var _chunks_claimed: bool = false
var _chunks: Array[PackedByteArray] = []
var _current_chunk: PackedByteArray = PackedByteArray()
var _total_bytes: int = 0
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 创建接管有限书签目录快照的增量编码器。
## @param source: 已冻结并通过根边界校验的书签源快照。
static func begin_encode(
	source: BookmarkChunkSourceSnapshot
) -> BookmarkChunkCodec:
	if source == null:
		return null
	var codec: BookmarkChunkCodec = BookmarkChunkCodec.new()
	codec._source = source
	return codec


## 在 frame 预算内推进；每个 unit 最多复制一个固定批或单个 replay step。
## @param frame_budget: 本次调用允许推进的最大 outer frame 数。
func advance(frame_budget: int) -> int:
	if frame_budget <= 0 or _complete or is_failed() or _source == null:
		return 0
	var consumed_units: int = 0
	while consumed_units < frame_budget and not _complete and not is_failed():
		var appended: bool = false
		match _phase:
			_PHASE_HEADER:
				appended = _encode_header()
			_PHASE_METADATA:
				appended = _encode_metadata()
			_PHASE_STATES:
				appended = _encode_state()
			_PHASE_CELLS:
				appended = _encode_cell_batch()
			_PHASE_TILES:
				appended = _encode_tile_batch()
			_PHASE_HISTORY:
				appended = _encode_history_batch()
			_PHASE_REPLAY:
				appended = _encode_replay_step()
			_:
				_fail(ERR_INVALID_DATA, "Bookmark encoder phase is invalid.")
		if not appended:
			break
		consumed_units += 1
	return consumed_units


func is_complete() -> bool:
	return _complete and not is_failed()


func is_failed() -> bool:
	return _error_code != OK


func get_error_code() -> Error:
	return _error_code


func get_error() -> String:
	return _error


func get_encoded_record_count() -> int:
	return _next_record_index


func take_chunks_taking_ownership() -> Array[PackedByteArray]:
	if not is_complete() or _chunks_claimed:
		return []
	_chunks_claimed = true
	var owned_chunks: Array[PackedByteArray] = _chunks
	_chunks = []
	return owned_chunks


## 测试/兼容用同步入口；生产 Profile 加载不得调用。
## @param chunks: 按规范顺序组成完整 stream v2 的 chunk 字节。
static func decode_chunks(chunks: Array[PackedByteArray]) -> Variant:
	var prepared_state: BookmarkCatalogPreparedState = (
		decode_prepared_state(chunks)
	)
	if prepared_state == null:
		return null
	return prepared_state.make_serialized_payload_for_tests()


## 同步产出 PreparedState；仅供测试和同步 provider 兼容入口。
## @param chunks: 按规范顺序组成完整 stream v2 的 chunk 字节。
static func decode_prepared_state(
	chunks: Array[PackedByteArray]
) -> BookmarkCatalogPreparedState:
	var decoder: BookmarkChunkDecoder = BookmarkChunkDecoder.begin_decode(chunks)
	if decoder == null:
		return null
	while not decoder.is_complete() and not decoder.is_failed():
		if decoder.advance(256) <= 0:
			return null
	if decoder.is_failed():
		return null
	return decoder.take_prepared_state_taking_ownership()


# --- 私有/辅助方法 ---

func _encode_header() -> bool:
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_CATALOG,
		&"schema_id": STREAM_SCHEMA_ID,
		&"schema_version": STREAM_SCHEMA_VERSION,
		&"business_schema_version": BUSINESS_SCHEMA_VERSION,
		&"bookmark_count": _source.get_record_count(),
	}
	if not _append_variant_frame(frame, "Bookmark catalog header"):
		return false
	if _source.get_record_count() == 0:
		_finish_encoding()
	else:
		_phase = _PHASE_METADATA
	return true


func _encode_metadata() -> bool:
	var metadata_value: Variant = _source.make_record_metadata(
		_next_record_index
	)
	if not metadata_value is Dictionary:
		_fail(ERR_INVALID_DATA, "Bookmark scalar metadata is invalid.")
		return false
	var metadata: Dictionary = metadata_value
	# SourceSnapshot 已在接管时冻结同一份小 metadata；count 直接从该 alias
	# 读取，避免一次 record 为四个 count 重建/扫描四次大根。
	_current_cell_count = GFVariantData.get_option_int(
		metadata,
		&"active_cell_count",
		-1
	)
	_current_tile_count = GFVariantData.get_option_int(
		metadata,
		&"tile_count",
		-1
	)
	_current_history_byte_count = GFVariantData.get_option_int(
		metadata,
		&"history_byte_count",
		-1
	)
	_current_step_count = GFVariantData.get_option_int(
		metadata,
		&"replay_step_count",
		-1
	)
	if (
		_current_cell_count <= 0
		or _current_tile_count < 0
		or _current_history_byte_count <= 0
		or _current_step_count < 0
	):
		_fail(ERR_INVALID_DATA, "Bookmark metadata counts are invalid.")
		return false
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_BOOKMARK_METADATA,
		&"bookmark_index": _next_record_index,
		&"schema_version": metadata.get(&"schema_version"),
		&"bookmark_id": metadata.get(&"bookmark_id"),
		&"timestamp": metadata.get(&"timestamp"),
		&"mode_config_path": metadata.get(&"mode_config_path"),
		&"ruleset_id": metadata.get(&"ruleset_id"),
		&"ruleset_version": metadata.get(&"ruleset_version"),
		&"ruleset_fingerprint": metadata.get(&"ruleset_fingerprint"),
		&"initial_seed": metadata.get(&"initial_seed"),
		&"score": metadata.get(&"score"),
		&"move_count": metadata.get(&"move_count"),
		&"ratio_resolutions": metadata.get(&"ratio_resolutions"),
		&"highest_tile": metadata.get(&"highest_tile"),
		&"target_tile_value": metadata.get(&"target_tile_value"),
		&"target_reached": metadata.get(&"target_reached"),
		&"board_schema_version": metadata.get(&"board_schema_version"),
		&"topology_schema_version": metadata.get(&"topology_schema_version"),
		&"topology_id": metadata.get(&"topology_id"),
		&"active_cell_count": metadata.get(&"active_cell_count"),
		&"tile_count": metadata.get(&"tile_count"),
		&"history_byte_count": metadata.get(&"history_byte_count"),
		&"replay_step_count": metadata.get(&"replay_step_count"),
	}
	if not _append_variant_frame(frame, "Bookmark scalar metadata"):
		return false
	_current_state_index = 0
	_current_cell_index = 0
	_current_tile_index = 0
	_current_history_offset = 0
	_current_step_index = 0
	_phase = _PHASE_STATES
	return true


func _encode_state() -> bool:
	var state_kind: StringName = _source.get_state_kind(_current_state_index)
	var state_value: Variant = _source.get_state_value(
		_next_record_index,
		_current_state_index
	)
	if state_kind == &"" or not state_value is Dictionary:
		_fail(ERR_INVALID_DATA, "Bookmark state root is invalid.")
		return false
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_STATE,
		&"bookmark_index": _next_record_index,
		&"state_kind": state_kind,
		&"value": state_value,
	}
	if not _append_variant_frame(frame, "Bookmark state root"):
		return false
	_current_state_index += 1
	if _current_state_index == BookmarkChunkSourceSnapshot.STATE_KINDS.size():
		_phase = _PHASE_CELLS
	return true


func _encode_cell_batch() -> bool:
	var cells_value: Variant = _source.make_topology_cell_batch(
		_next_record_index,
		_current_cell_index
	)
	if not cells_value is Array:
		_fail(ERR_INVALID_DATA, "Bookmark topology cell batch is invalid.")
		return false
	var cells: Array = cells_value
	if cells.is_empty():
		_fail(ERR_INVALID_DATA, "Bookmark topology cell batch is empty.")
		return false
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_TOPOLOGY_CELLS,
		&"bookmark_index": _next_record_index,
		&"start_index": _current_cell_index,
		&"cells": cells,
	}
	if not _append_variant_frame(frame, "Bookmark topology cell batch"):
		return false
	_current_cell_index += cells.size()
	if _current_cell_index == _current_cell_count:
		_phase = _PHASE_TILES if _current_tile_count > 0 else _PHASE_HISTORY
	elif _current_cell_index > _current_cell_count:
		_fail(ERR_INVALID_DATA, "Bookmark topology count changed during encode.")
		return false
	return true


func _encode_tile_batch() -> bool:
	var tiles_value: Variant = _source.make_tile_batch(
		_next_record_index,
		_current_tile_index
	)
	if not tiles_value is Array:
		_fail(ERR_INVALID_DATA, "Bookmark tile batch is invalid.")
		return false
	var tiles: Array = tiles_value
	if tiles.is_empty():
		_fail(ERR_INVALID_DATA, "Bookmark tile batch is empty.")
		return false
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_TILES,
		&"bookmark_index": _next_record_index,
		&"start_index": _current_tile_index,
		&"tiles": tiles,
	}
	if not _append_variant_frame(frame, "Bookmark tile batch"):
		return false
	_current_tile_index += tiles.size()
	if _current_tile_index == _current_tile_count:
		_phase = _PHASE_HISTORY
	elif _current_tile_index > _current_tile_count:
		_fail(ERR_INVALID_DATA, "Bookmark tile count changed during encode.")
		return false
	return true


func _encode_history_batch() -> bool:
	var bytes_value: Variant = _source.make_history_byte_batch(
		_next_record_index,
		_current_history_offset
	)
	if not bytes_value is PackedByteArray:
		_fail(ERR_INVALID_DATA, "Bookmark history byte batch is invalid.")
		return false
	var bytes: PackedByteArray = bytes_value
	if bytes.is_empty():
		_fail(ERR_INVALID_DATA, "Bookmark history byte batch is empty.")
		return false
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_HISTORY_BYTES,
		&"bookmark_index": _next_record_index,
		&"start_offset": _current_history_offset,
		&"bytes": bytes,
	}
	if not _append_variant_frame(frame, "Bookmark history byte batch"):
		return false
	_current_history_offset += bytes.size()
	if _current_history_offset == _current_history_byte_count:
		if _current_step_count > 0:
			_phase = _PHASE_REPLAY
		else:
			_finish_current_record()
	elif _current_history_offset > _current_history_byte_count:
		_fail(ERR_INVALID_DATA, "Bookmark history size changed during encode.")
		return false
	return true


func _encode_replay_step() -> bool:
	var step_value: Variant = _source.make_replay_step(
		_next_record_index,
		_current_step_index
	)
	if not step_value is Dictionary:
		_fail(ERR_INVALID_DATA, "Bookmark replay step is invalid.")
		return false
	var step: Dictionary = step_value
	var frame: Dictionary = {
		&"record_type": BookmarkChunkDecoder.RECORD_REPLAY_STEP,
		&"bookmark_index": _next_record_index,
		&"step_index": _current_step_index,
		&"action": step.get(&"action"),
		&"checkpoint": step.get(&"checkpoint"),
	}
	if not _append_variant_frame(frame, "Bookmark replay step"):
		return false
	_current_step_index += 1
	if _current_step_index == _current_step_count:
		_finish_current_record()
	elif _current_step_index > _current_step_count:
		_fail(ERR_INVALID_DATA, "Bookmark replay count changed during encode.")
		return false
	return true


func _finish_current_record() -> void:
	if (
		_current_state_index != BookmarkChunkSourceSnapshot.STATE_KINDS.size()
		or _current_cell_index != _current_cell_count
		or _current_tile_index != _current_tile_count
		or _current_history_offset != _current_history_byte_count
		or _current_step_index != _current_step_count
	):
		_fail(ERR_INVALID_DATA, "Bookmark record counts are inconsistent.")
		return
	_next_record_index += 1
	_current_state_index = 0
	_current_cell_index = 0
	_current_tile_index = 0
	_current_history_offset = 0
	_current_step_index = 0
	_current_cell_count = -1
	_current_tile_count = -1
	_current_history_byte_count = -1
	_current_step_count = -1
	if _next_record_index == _source.get_record_count():
		_finish_encoding()
	else:
		_phase = _PHASE_METADATA


func _append_variant_frame(value: Variant, label: String) -> bool:
	if not BookmarkChunkSourceSnapshot.is_variant_within_frame_budget(value):
		_fail(ERR_OUT_OF_MEMORY, "%s violates its structural budget." % label)
		return false
	var payload: PackedByteArray = var_to_bytes(value)
	if payload.is_empty():
		_fail(ERR_INVALID_DATA, "%s could not be encoded." % label)
		return false
	if payload.size() > MAX_FRAME_PAYLOAD_BYTES:
		_fail(
			ERR_OUT_OF_MEMORY,
			"%s exceeds the 128 KiB framed-record limit." % label
		)
		return false
	if _total_bytes + _LENGTH_PREFIX_BYTES + payload.size() > MAX_TOTAL_BYTES:
		_fail(ERR_OUT_OF_MEMORY, "Bookmark chunk stream exceeds 8 MiB.")
		return false
	_append_raw(_encode_u32(payload.size()))
	_append_raw(payload)
	return true


func _append_raw(payload: PackedByteArray) -> void:
	var source_offset: int = 0
	while source_offset < payload.size():
		var available_bytes: int = CHUNK_BYTES - _current_chunk.size()
		var copy_count: int = mini(
			available_bytes,
			payload.size() - source_offset
		)
		_current_chunk.append_array(
			payload.slice(source_offset, source_offset + copy_count)
		)
		_total_bytes += copy_count
		source_offset += copy_count
		if _current_chunk.size() == CHUNK_BYTES:
			_chunks.append(_current_chunk)
			_current_chunk = PackedByteArray()


func _finish_encoding() -> void:
	if not _current_chunk.is_empty():
		_chunks.append(_current_chunk)
		_current_chunk = PackedByteArray()
	if (
		_chunks.is_empty()
		or _chunks.size() > ChunkManifest.MAX_CHUNK_COUNT
		or _total_bytes <= 0
		or _total_bytes > MAX_TOTAL_BYTES
	):
		_fail(ERR_INVALID_DATA, "Bookmark chunks violate manifest budgets.")
		return
	_complete = true
	if _source != null:
		_source.release()
	_source = null


func _fail(error_code: Error, error: String) -> void:
	_error_code = error_code if error_code != OK else FAILED
	_error = error
	_chunks.clear()
	_current_chunk = PackedByteArray()
	if _source != null:
		_source.release()
	_source = null


static func _encode_u32(value: int) -> PackedByteArray:
	return PackedByteArray([
		(value >> 24) & 0xff,
		(value >> 16) & 0xff,
		(value >> 8) & 0xff,
		value & 0xff,
	])
