## manifest-backed Feature 共用的有界 framed-Variant stream writer。
##
## 本类只拥有长度前缀、Variant 结构预算、规范编码与 chunk 边界；不解释
## Bookmark、Replay 或其他 Feature 的 record schema、phase 与业务字段。
class_name ChunkFrameStreamWriter
extends RefCounted


# --- 常量 ---

const LENGTH_PREFIX_BYTES: int = 4
const CHUNK_BYTES: int = ChunkManifest.MAX_CHUNK_BYTES
const MAX_CHUNK_COUNT: int = ChunkManifest.MAX_CHUNK_COUNT
const MAX_TOTAL_BYTES: int = ChunkManifest.MAX_TOTAL_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = CHUNK_BYTES - LENGTH_PREFIX_BYTES


# --- 私有变量 ---

var _chunks: Array[PackedByteArray] = []
var _current_chunk: PackedByteArray = PackedByteArray()
var _total_bytes: int = 0
var _finished: bool = false
var _chunks_claimed: bool = false
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 在任何 var_to_bytes() 前应用项目统一 Variant frame 预算并追加一帧。
## @param value: 待按 Godot canonical Variant 编码写入的 Feature frame。
## @param label: 仅用于诊断的有限 Feature frame 名称。
func append_variant_frame(value: Variant, label: String) -> bool:
	if _finished or _chunks_claimed or is_failed():
		return false
	var normalized_label: String = label.strip_edges()
	if normalized_label.is_empty():
		normalized_label = "Chunk frame"
	if not ChunkFrameVariantBudget.is_value_within_default_budget(value):
		_fail(
			ERR_OUT_OF_MEMORY,
			"%s violates its structural budget." % normalized_label
		)
		return false
	var payload: PackedByteArray = var_to_bytes(value)
	if payload.is_empty():
		_fail(
			ERR_INVALID_DATA,
			"%s could not be encoded." % normalized_label
		)
		return false
	if payload.size() > MAX_FRAME_PAYLOAD_BYTES:
		_fail(
			ERR_OUT_OF_MEMORY,
			"%s exceeds the 128 KiB framed-record limit." % normalized_label
		)
		return false
	if (
		_total_bytes + LENGTH_PREFIX_BYTES + payload.size()
		> MAX_TOTAL_BYTES
	):
		_fail(ERR_OUT_OF_MEMORY, "Chunk frame stream exceeds 8 MiB.")
		return false
	_append_raw(_encode_u32(payload.size()))
	_append_raw(payload)
	return true


## 刷新最后一个部分 chunk，并冻结可一次性移出的规范 chunk 根。
func finish() -> bool:
	if _finished:
		return not is_failed()
	if _chunks_claimed or is_failed():
		return false
	if not _current_chunk.is_empty():
		_chunks.append(_current_chunk)
		_current_chunk = PackedByteArray()
	if (
		_chunks.is_empty()
		or _chunks.size() > MAX_CHUNK_COUNT
		or _total_bytes <= 0
		or _total_bytes > MAX_TOTAL_BYTES
	):
		_fail(ERR_INVALID_DATA, "Chunks violate manifest stream budgets.")
		return false
	_finished = true
	return true


func is_finished() -> bool:
	return _finished and not is_failed()


func is_failed() -> bool:
	return _error_code != OK


func get_error_code() -> Error:
	return _error_code


func get_error() -> String:
	return _error


func get_total_bytes() -> int:
	return _total_bytes


## 一次性移出规范 chunk 根；未完成或重复调用返回空数组。
func take_chunks_taking_ownership() -> Array[PackedByteArray]:
	if not is_finished() or _chunks_claimed:
		return []
	_chunks_claimed = true
	var owned_chunks: Array[PackedByteArray] = _chunks
	_chunks = []
	return owned_chunks


## 放弃尚未移出的字节；Feature encoder 失败或取消时调用。
func release() -> void:
	_chunks.clear()
	_current_chunk = PackedByteArray()
	_total_bytes = 0


# --- 私有/辅助方法 ---

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


func _fail(error_code: Error, error: String) -> void:
	_error_code = error_code if error_code != OK else FAILED
	_error = error
	_chunks.clear()
	_current_chunk = PackedByteArray()
	_total_bytes = 0


static func _encode_u32(value: int) -> PackedByteArray:
	return PackedByteArray([
		(value >> 24) & 0xff,
		(value >> 16) & 0xff,
		(value >> 8) & 0xff,
		value & 0xff,
	])
