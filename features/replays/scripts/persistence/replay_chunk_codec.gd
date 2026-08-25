## replays 的严格、版本化、有界分块流 codec。
##
## 每个编码 work unit 只产生一个不超过 128 KiB 的结构化 frame：header、
## scalar metadata、固定小批 topology cells、固定小批 final tiles，或单个 step。
## 静态 decode 只供测试和兼容调用；生产 Profile 加载由 ReplayChunkDecoder
## 逐帧推进。
class_name ReplayChunkCodec
extends RefCounted


# --- 常量 ---

const STREAM_SCHEMA_ID: StringName = ReplayChunkDecoder.STREAM_SCHEMA_ID
const STREAM_SCHEMA_VERSION: int = ReplayChunkDecoder.STREAM_SCHEMA_VERSION
const BUSINESS_SCHEMA_VERSION: int = ReplayChunkDecoder.BUSINESS_SCHEMA_VERSION
const CHUNK_BYTES: int = ReplayChunkDecoder.CHUNK_BYTES
const MAX_TOTAL_BYTES: int = ReplayChunkDecoder.MAX_TOTAL_BYTES
const MAX_FRAME_BYTES: int = ReplayChunkDecoder.MAX_FRAME_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = (
	ReplayChunkDecoder.MAX_FRAME_PAYLOAD_BYTES
)

const _PHASE_HEADER: int = 0
const _PHASE_METADATA: int = 1
const _PHASE_CELLS: int = 2
const _PHASE_TILES: int = 3
const _PHASE_STEPS: int = 4


# --- 私有变量 ---

var _source: ReplayChunkSourceSnapshot = null
var _phase: int = _PHASE_HEADER
var _next_replay_index: int = 0
var _current_cell_index: int = 0
var _current_tile_index: int = 0
var _current_step_index: int = 0
var _current_cell_count: int = -1
var _current_tile_count: int = -1
var _current_step_count: int = -1
var _encoded_step_count: int = 0
var _complete: bool = false
var _frame_writer: ChunkFrameStreamWriter = null
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 创建尚未执行序列化工作的编码器，并接管 source 生命周期。
## @param source: 待接管的不可变回放目录快照。
static func begin_encode(source: ReplayChunkSourceSnapshot) -> ReplayChunkCodec:
	if source == null:
		return null
	var codec: ReplayChunkCodec = ReplayChunkCodec.new()
	codec._source = source
	codec._frame_writer = ChunkFrameStreamWriter.new()
	return codec


## 在给定 frame 预算内推进；每个 unit 最多复制一个固定批或一个 step。
## @param frame_budget: 本次调用最多处理的有界 frame 数。
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
			_PHASE_CELLS:
				appended = _encode_cell_batch()
			_PHASE_TILES:
				appended = _encode_tile_batch()
			_PHASE_STEPS:
				appended = _encode_step()
			_:
				_fail(ERR_INVALID_DATA, "Replay encoder phase is invalid.")
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


func get_encoded_replay_count() -> int:
	return _next_replay_index


func get_encoded_step_count() -> int:
	return _encoded_step_count


## 一次性移出规范 chunks；重复调用返回空数组。
func take_chunks_taking_ownership() -> Array[PackedByteArray]:
	if not is_complete() or _frame_writer == null:
		return []
	return _frame_writer.take_chunks_taking_ownership()


## 测试/兼容用同步入口；生产 Profile 加载不得调用此方法。
## @param chunks: 待同步解码的规范 replay stream 分块。
static func decode_chunks(chunks: Array[PackedByteArray]) -> Variant:
	var prepared_state: ReplayCatalogPreparedState = (
		decode_prepared_state(chunks)
	)
	if prepared_state == null:
		return null
	return prepared_state.make_serialized_payload_for_tests()


## 同步产出 PreparedState；仅供测试和同步 provider 兼容入口。
## @param chunks: 待同步解码并物化的规范 replay stream 分块。
static func decode_prepared_state(
	chunks: Array[PackedByteArray]
) -> ReplayCatalogPreparedState:
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(chunks)
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
	var header: Dictionary = {
		&"record_type": ReplayChunkDecoder.RECORD_CATALOG,
		&"schema_id": STREAM_SCHEMA_ID,
		&"schema_version": STREAM_SCHEMA_VERSION,
		&"business_schema_version": BUSINESS_SCHEMA_VERSION,
		&"replay_count": _source.get_replay_count(),
	}
	if not _append_variant_frame(header, "Replay catalog header"):
		return false
	if _source.get_replay_count() == 0:
		_finish_encoding()
	else:
		_phase = _PHASE_METADATA
	return true


func _encode_metadata() -> bool:
	if _next_replay_index >= _source.get_replay_count():
		_fail(ERR_INVALID_DATA, "Replay metadata index is out of range.")
		return false
	var metadata_value: Variant = _source.duplicate_replay_metadata(
		_next_replay_index
	)
	_current_cell_count = _source.get_topology_cell_count(
		_next_replay_index
	)
	_current_tile_count = _source.get_final_tile_count(_next_replay_index)
	_current_step_count = _source.get_step_count(_next_replay_index)
	if (
		not metadata_value is Dictionary
		or _current_cell_count <= 0
		or _current_tile_count < 0
		or _current_step_count < 0
	):
		_fail(ERR_INVALID_DATA, "Replay scalar metadata is invalid.")
		return false
	var metadata: Dictionary = GFVariantData.as_dictionary(metadata_value)
	var frame: Dictionary = {
		&"record_type": ReplayChunkDecoder.RECORD_REPLAY_METADATA,
		&"replay_index": _next_replay_index,
		&"schema_version": metadata.get(&"schema_version"),
		&"replay_id": metadata.get(&"replay_id"),
		&"timestamp": metadata.get(&"timestamp"),
		&"mode_config_path": metadata.get(&"mode_config_path"),
		&"ruleset_id": metadata.get(&"ruleset_id"),
		&"ruleset_version": metadata.get(&"ruleset_version"),
		&"ruleset_fingerprint": metadata.get(&"ruleset_fingerprint"),
		&"initial_seed": metadata.get(&"initial_seed"),
		&"session_metadata": metadata.get(&"session_metadata"),
		&"final_score": metadata.get(&"final_score"),
		&"topology_schema_version": metadata.get(&"topology_schema_version"),
		&"topology_id": metadata.get(&"topology_id"),
		&"active_cell_count": metadata.get(&"active_cell_count"),
		&"snapshot_schema_version": metadata.get(&"snapshot_schema_version"),
		&"tile_count": metadata.get(&"tile_count"),
		&"step_count": metadata.get(&"step_count"),
	}
	if not _append_variant_frame(frame, "Replay scalar metadata"):
		return false
	_current_cell_index = 0
	_current_tile_index = 0
	_current_step_index = 0
	_phase = _PHASE_CELLS
	return true


func _encode_cell_batch() -> bool:
	var cells_value: Variant = _source.duplicate_topology_cell_batch(
		_next_replay_index,
		_current_cell_index
	)
	if not cells_value is Array:
		_fail(ERR_INVALID_DATA, "Replay topology cell batch is invalid.")
		return false
	var cells: Array = cells_value
	if cells.is_empty():
		_fail(ERR_INVALID_DATA, "Replay topology cell batch is empty.")
		return false
	var frame: Dictionary = {
		&"record_type": ReplayChunkDecoder.RECORD_TOPOLOGY_CELLS,
		&"replay_index": _next_replay_index,
		&"start_index": _current_cell_index,
		&"cells": cells,
	}
	if not _append_variant_frame(frame, "Replay topology cell batch"):
		return false
	_current_cell_index += cells.size()
	if _current_cell_index == _current_cell_count:
		if _current_tile_count > 0:
			_phase = _PHASE_TILES
		elif _current_step_count > 0:
			_phase = _PHASE_STEPS
		else:
			_finish_current_replay()
	elif _current_cell_index > _current_cell_count:
		_fail(ERR_INVALID_DATA, "Replay topology cell count changed during encode.")
		return false
	return true


func _encode_tile_batch() -> bool:
	var tiles_value: Variant = _source.duplicate_final_tile_batch(
		_next_replay_index,
		_current_tile_index
	)
	if not tiles_value is Array:
		_fail(ERR_INVALID_DATA, "Replay final tile batch is invalid.")
		return false
	var tiles: Array = tiles_value
	if tiles.is_empty():
		_fail(ERR_INVALID_DATA, "Replay final tile batch is empty.")
		return false
	var frame: Dictionary = {
		&"record_type": ReplayChunkDecoder.RECORD_FINAL_TILES,
		&"replay_index": _next_replay_index,
		&"start_index": _current_tile_index,
		&"tiles": tiles,
	}
	if not _append_variant_frame(frame, "Replay final tile batch"):
		return false
	_current_tile_index += tiles.size()
	if _current_tile_index == _current_tile_count:
		if _current_step_count > 0:
			_phase = _PHASE_STEPS
		else:
			_finish_current_replay()
	elif _current_tile_index > _current_tile_count:
		_fail(ERR_INVALID_DATA, "Replay final tile count changed during encode.")
		return false
	return true


func _encode_step() -> bool:
	var step_value: Variant = _source.duplicate_step(
		_next_replay_index,
		_current_step_index
	)
	if not step_value is Dictionary:
		_fail(ERR_INVALID_DATA, "Replay step snapshot is invalid.")
		return false
	var step: Dictionary = GFVariantData.as_dictionary(step_value)
	var frame: Dictionary = {
		&"record_type": ReplayChunkDecoder.RECORD_STEP,
		&"replay_index": _next_replay_index,
		&"step_index": _current_step_index,
		&"action": step.get(&"action"),
		&"checkpoint": step.get(&"checkpoint"),
	}
	if not _append_variant_frame(frame, "Replay step"):
		return false
	_current_step_index += 1
	_encoded_step_count += 1
	if _current_step_index == _current_step_count:
		_finish_current_replay()
	elif _current_step_index > _current_step_count:
		_fail(ERR_INVALID_DATA, "Replay step count changed during encode.")
		return false
	return true


func _finish_current_replay() -> void:
	if (
		_current_cell_index != _current_cell_count
		or _current_tile_index != _current_tile_count
		or _current_step_index != _current_step_count
	):
		_fail(ERR_INVALID_DATA, "Replay record counts are inconsistent.")
		return
	_next_replay_index += 1
	_current_cell_index = 0
	_current_tile_index = 0
	_current_step_index = 0
	_current_cell_count = -1
	_current_tile_count = -1
	_current_step_count = -1
	if _next_replay_index == _source.get_replay_count():
		_finish_encoding()
	else:
		_phase = _PHASE_METADATA


func _append_variant_frame(value: Variant, label: String) -> bool:
	if _frame_writer == null:
		_fail(ERR_UNCONFIGURED, "Replay frame writer is unavailable.")
		return false
	if _frame_writer.append_variant_frame(value, label):
		return true
	var writer_error_code: Error = _frame_writer.get_error_code()
	var writer_error: String = _frame_writer.get_error()
	_fail(writer_error_code, writer_error)
	return false


func _finish_encoding() -> void:
	if _frame_writer == null:
		_fail(ERR_UNCONFIGURED, "Replay frame writer is unavailable.")
		return
	if not _frame_writer.finish():
		var writer_error_code: Error = _frame_writer.get_error_code()
		var writer_error: String = _frame_writer.get_error()
		_fail(writer_error_code, writer_error)
		return
	_complete = true
	if _source != null:
		_source.release()
	_source = null


func _fail(error_code: Error, error: String) -> void:
	_error_code = error_code if error_code != OK else FAILED
	_error = error
	if _frame_writer != null:
		_frame_writer.release()
	if _source != null:
		_source.release()
	_source = null
