## manifest-backed Feature 共用的有界 framed-Variant stream reader。
##
## 本类只验证 chunk/长度边界、跨 chunk 读取、Variant 结构预算和 canonical
## 编码；成功 frame 的业务 schema、顺序与 phase 必须由消费 Feature 校验。
class_name ChunkFrameStreamReader
extends RefCounted


# --- 常量 ---

const LENGTH_PREFIX_BYTES: int = ChunkFrameStreamWriter.LENGTH_PREFIX_BYTES
const CHUNK_BYTES: int = ChunkFrameStreamWriter.CHUNK_BYTES
const MAX_CHUNK_COUNT: int = ChunkFrameStreamWriter.MAX_CHUNK_COUNT
const MAX_TOTAL_BYTES: int = ChunkFrameStreamWriter.MAX_TOTAL_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = (
	ChunkFrameStreamWriter.MAX_FRAME_PAYLOAD_BYTES
)


# --- 私有变量 ---

var _chunks: Array[PackedByteArray] = []
var _chunk_index: int = 0
var _chunk_offset: int = 0
var _remaining_bytes: int = 0


# --- 公共方法 ---

## 验证规范 chunk 边界并接管只读元素别名。
##
## 返回后调用方必须放弃原数组根及其元素；Reader 自己持有独立数组根，避免
## 调用方之后 clear 原根时破坏读取状态。
## @param chunks: 已按 Manifest 顺序排列的完整 chunk 根。
static func begin_reading_taking_ownership(
	chunks: Array[PackedByteArray]
) -> ChunkFrameStreamReader:
	if not are_chunk_boundaries_valid(chunks):
		return null
	var reader: ChunkFrameStreamReader = ChunkFrameStreamReader.new()
	reader._chunks = chunks.duplicate()
	for chunk: PackedByteArray in reader._chunks:
		reader._remaining_bytes += chunk.size()
	return reader


## 读取并验证一个 frame；失败返回 {ok=false}，不会暴露部分 payload。
##
## bytes_to_var() 禁止对象。结构预算必须位于解码之后、canonical
## var_to_bytes() 之前，避免恶意深层/巨容器触发第二次递归序列化。
func read_variant_frame() -> Dictionary:
	var length_bytes: PackedByteArray = read_exact(LENGTH_PREFIX_BYTES)
	if length_bytes.size() != LENGTH_PREFIX_BYTES:
		return {&"ok": false}
	var payload_length: int = _decode_u32(length_bytes)
	if (
		payload_length <= 0
		or payload_length > MAX_FRAME_PAYLOAD_BYTES
		or payload_length > _remaining_bytes
	):
		return {&"ok": false}
	var payload: PackedByteArray = read_exact(payload_length)
	if payload.size() != payload_length:
		return {&"ok": false}
	var value: Variant = bytes_to_var(payload)
	if not ChunkFrameVariantBudget.is_value_within_default_budget(value):
		return {&"ok": false}
	if var_to_bytes(value) != payload:
		return {&"ok": false}
	return {&"ok": true, &"value": value}


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


## 验证外层 chunk 根的数量、单块大小、非末块满块及总字节预算。
## @param chunks: 待验证的有序二进制 chunk 数组。
static func are_chunk_boundaries_valid(
	chunks: Array[PackedByteArray]
) -> bool:
	if chunks.is_empty() or chunks.size() > MAX_CHUNK_COUNT:
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


# --- 私有/辅助方法 ---

static func _decode_u32(payload: PackedByteArray) -> int:
	return (
		(int(payload[0]) << 24)
		| (int(payload[1]) << 16)
		| (int(payload[2]) << 8)
		| int(payload[3])
	)
