## 描述一个已完整写入 A/B bank、但尚未提交可见性的严格分块候选。
##
## 持久化 schema 只保存 section/schema、bank，以及顺序化 chunk 的大小与摘要。
## Profile prefix、主 Profile 身份和物理路径均由可信外部 owner 派生。
class_name ChunkManifest
extends RefCounted


# --- 常量 ---

## 当前 Manifest schema ID。
const SCHEMA_ID: StringName = &"game_chunk_manifest"

## 当前 Manifest schema 版本。
const SCHEMA_VERSION: int = 1

## 首个固定 staging bank。
const BANK_A: StringName = &"a"

## 第二个固定 staging bank。
const BANK_B: StringName = &"b"

## 尚无已激活 bank。
const BANK_NONE: StringName = &""

## 单次 bundle 最多包含的 chunk 数。
const MAX_CHUNK_COUNT: int = 64

## 单个 Profile chunk 的初始硬预算。
const MAX_CHUNK_BYTES: int = 128 * 1024

## 单个 section bundle 的总字节预算。
const MAX_TOTAL_BYTES: int = 8 * 1024 * 1024

const _DIGEST_HEX_LENGTH: int = 64
const _MAX_ID_LENGTH: int = 128
const _MANIFEST_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"section_id",
	"section_schema_version",
	"bank",
	"chunks",
]
const _DESCRIPTOR_FIELDS: Array[String] = [
	"index",
	"byte_count",
	"sha256",
]


# --- 私有变量 ---

var _section_id: StringName = &""
var _section_schema_version: int = 0
var _bank: StringName = BANK_NONE
var _total_bytes: int = 0
var _chunks: Array[Dictionary] = []


# --- 公共方法 ---

## 从已冻结 chunk 构造当前 schema 的候选 Manifest。
##
## @param section_id: Feature section ID。
## @param section_schema_version: Feature section schema 版本。
## @param bank: 本次完整写入的 A 或 B bank。
## @param chunks: 按规范顺序冻结的 chunk bytes。
## @return 参数与预算合法时返回 Manifest，否则返回 null。
static func create(
	section_id: StringName,
	section_schema_version: int,
	bank: StringName,
	chunks: Array[PackedByteArray]
) -> ChunkManifest:
	if not _is_valid_identity(section_id, section_schema_version, bank):
		return null
	if chunks.is_empty() or chunks.size() > MAX_CHUNK_COUNT:
		return null

	var descriptors: Array[Dictionary] = []
	var total_bytes: int = 0
	for index: int in range(chunks.size()):
		var payload: PackedByteArray = chunks[index]
		var byte_count: int = payload.size()
		if byte_count <= 0 or byte_count > MAX_CHUNK_BYTES:
			return null
		total_bytes += byte_count
		if total_bytes > MAX_TOTAL_BYTES:
			return null
		descriptors.append({
			&"index": index,
			&"byte_count": byte_count,
			&"sha256": _sha256_text(payload),
		})

	var manifest: ChunkManifest = ChunkManifest.new()
	manifest._section_id = section_id
	manifest._section_schema_version = section_schema_version
	manifest._bank = bank
	manifest._total_bytes = total_bytes
	manifest._chunks = descriptors
	return manifest if manifest.is_valid() else null


## 从持久化 Dictionary 严格解码 Manifest。
##
## @param payload: 不可信持久化载荷。
## @return schema、字段、顺序和预算全部合法时返回 Manifest，否则返回 null。
static func from_dict(payload: Dictionary) -> ChunkManifest:
	if not _has_exact_fields(payload, _MANIFEST_FIELDS):
		return null
	var schema_id_value: Variant = payload.get(&"schema_id")
	var schema_version_value: Variant = payload.get(&"schema_version")
	var section_id_value: Variant = payload.get(&"section_id")
	var section_schema_value: Variant = payload.get(&"section_schema_version")
	var bank_value: Variant = payload.get(&"bank")
	var chunks_value: Variant = payload.get(&"chunks")
	var schema_id: String = _text_from_variant(schema_id_value)
	var schema_version: int = _int_from_variant(schema_version_value)
	var section_id_text: String = _text_from_variant(section_id_value)
	var section_schema: int = _int_from_variant(section_schema_value)
	var bank_text: String = _text_from_variant(bank_value)
	if not _is_text(schema_id_value) or schema_id != String(SCHEMA_ID):
		return null
	if not schema_version_value is int or schema_version != SCHEMA_VERSION:
		return null
	if (
		not _is_text(section_id_value)
		or not section_schema_value is int
		or not _is_text(bank_value)
		or not chunks_value is Array
	):
		return null

	var raw_chunks: Array = chunks_value
	if raw_chunks.is_empty() or raw_chunks.size() > MAX_CHUNK_COUNT:
		return null
	var descriptors: Array[Dictionary] = []
	var measured_total: int = 0
	for index: int in range(raw_chunks.size()):
		var descriptor_value: Variant = raw_chunks[index]
		if not descriptor_value is Dictionary:
			return null
		var descriptor: Dictionary = descriptor_value
		if not _has_exact_fields(descriptor, _DESCRIPTOR_FIELDS):
			return null
		var index_value: Variant = descriptor.get(&"index")
		var byte_count_value: Variant = descriptor.get(&"byte_count")
		var digest_value: Variant = descriptor.get(&"sha256")
		var descriptor_index: int = _int_from_variant(index_value, -1)
		var byte_count: int = _int_from_variant(byte_count_value)
		var digest: String = _text_from_variant(digest_value)
		if (
			not index_value is int
			or descriptor_index != index
			or not byte_count_value is int
			or byte_count <= 0
			or byte_count > MAX_CHUNK_BYTES
			or not _is_text(digest_value)
			or not _is_valid_digest(digest)
		):
			return null
		measured_total += byte_count
		if measured_total > MAX_TOTAL_BYTES:
			return null
		descriptors.append({
			&"index": index,
			&"byte_count": byte_count,
			&"sha256": digest,
		})

	var manifest: ChunkManifest = ChunkManifest.new()
	manifest._section_id = StringName(section_id_text)
	manifest._section_schema_version = section_schema
	manifest._bank = StringName(bank_text)
	manifest._total_bytes = measured_total
	manifest._chunks = descriptors
	return manifest if manifest.is_valid() else null


## 选择当前 active bank 之外的固定 staging bank。
##
## @param active_bank: 当前 Manifest 的 bank；首次 staging 传 BANK_NONE。
## @return inactive bank；输入非法时返回 BANK_NONE。
static func select_inactive_bank(active_bank: StringName) -> StringName:
	if active_bank == BANK_NONE or active_bank == BANK_B:
		return BANK_A
	if active_bank == BANK_A:
		return BANK_B
	return BANK_NONE


## 验证内存 Manifest 的全部 schema、顺序与预算约束。
##
## @return 合法时返回 true。
func is_valid() -> bool:
	if not _is_valid_identity(_section_id, _section_schema_version, _bank):
		return false
	if _chunks.is_empty() or _chunks.size() > MAX_CHUNK_COUNT:
		return false
	var measured_total: int = 0
	for index: int in range(_chunks.size()):
		var descriptor: Dictionary = _chunks[index]
		if not _has_exact_fields(descriptor, _DESCRIPTOR_FIELDS):
			return false
		var index_value: Variant = descriptor.get(&"index")
		var byte_count_value: Variant = descriptor.get(&"byte_count")
		var digest_value: Variant = descriptor.get(&"sha256")
		var descriptor_index: int = _int_from_variant(index_value, -1)
		var byte_count: int = _int_from_variant(byte_count_value)
		var digest: String = _text_from_variant(digest_value)
		if (
			not index_value is int
			or descriptor_index != index
			or not byte_count_value is int
			or byte_count <= 0
			or byte_count > MAX_CHUNK_BYTES
			or not _is_text(digest_value)
			or not _is_valid_digest(digest)
		):
			return false
		measured_total += byte_count
		if measured_total > MAX_TOTAL_BYTES:
			return false
	return measured_total == _total_bytes


## 验证指定 chunk 与 Manifest 中的顺序、大小和摘要一致。
##
## @param index: chunk 规范序号。
## @param payload: 从对应 GF Profile 读取的 bytes。
## @return 描述符与 payload 完全匹配时返回 true。
func verify_chunk(index: int, payload: PackedByteArray) -> bool:
	if index < 0 or index >= _chunks.size():
		return false
	var descriptor: Dictionary = _chunks[index]
	return (
		_int_from_variant(descriptor.get(&"index"), -1) == index
		and _int_from_variant(descriptor.get(&"byte_count"), -1)
		== payload.size()
		and _text_from_variant(descriptor.get(&"sha256"))
		== _sha256_text(payload)
	)


## 获取 Feature section ID。
func get_section_id() -> StringName:
	return _section_id


## 获取 section schema 版本。
func get_section_schema_version() -> int:
	return _section_schema_version


## 获取当前候选 bank。
func get_bank() -> StringName:
	return _bank


## 获取 chunk 数量。
func get_chunk_count() -> int:
	return _chunks.size()


## 获取总字节数；该预算证据由 descriptors 计算，不进入持久化 schema。
func get_total_bytes() -> int:
	return _total_bytes


## 编码为当前最小严格 schema Dictionary。
##
## @return 不包含 Profile prefix、主 Profile 身份或物理路径的持久化载荷。
func to_dict() -> Dictionary:
	var descriptors: Array[Dictionary] = []
	for descriptor: Dictionary in _chunks:
		descriptors.append(descriptor.duplicate(true))
	return {
		&"schema_id": SCHEMA_ID,
		&"schema_version": SCHEMA_VERSION,
		&"section_id": _section_id,
		&"section_schema_version": _section_schema_version,
		&"bank": _bank,
		&"chunks": descriptors,
	}


## 创建与当前 Manifest 隔离的副本。
##
## @return 当前对象有效时返回副本，否则返回 null。
func duplicate_manifest() -> ChunkManifest:
	return ChunkManifest.from_dict(to_dict())


# --- 私有/辅助方法 ---

static func _is_valid_identity(
	section_id: StringName,
	section_schema_version: int,
	bank: StringName
) -> bool:
	return (
		_is_bounded_text(String(section_id), _MAX_ID_LENGTH)
		and section_schema_version > 0
		and bank in [BANK_A, BANK_B]
	)


static func _is_bounded_text(value: String, maximum_length: int) -> bool:
	return (
		not value.is_empty()
		and value == value.strip_edges()
		and value.length() <= maximum_length
		and not value.contains("\n")
		and not value.contains("\r")
	)


static func _is_text(value: Variant) -> bool:
	return value is String or value is StringName


static func _text_from_variant(value: Variant) -> String:
	if value is String:
		var text: String = value
		return text
	if value is StringName:
		var name: StringName = value
		return String(name)
	return ""


static func _int_from_variant(value: Variant, fallback: int = 0) -> int:
	if value is int:
		var number: int = value
		return number
	return fallback


static func _has_exact_fields(
	payload: Dictionary,
	allowed_fields: Array[String]
) -> bool:
	if payload.size() != allowed_fields.size():
		return false
	for key_value: Variant in payload.keys():
		if not _is_text(key_value):
			return false
		if _text_from_variant(key_value) not in allowed_fields:
			return false
	return true


static func _is_valid_digest(digest: String) -> bool:
	if digest.length() != _DIGEST_HEX_LENGTH or digest != digest.to_lower():
		return false
	for index: int in range(digest.length()):
		var character: String = digest.substr(index, 1)
		if character not in "0123456789abcdef":
			return false
	return true


static func _sha256_text(payload: PackedByteArray) -> String:
	var hashing: HashingContext = HashingContext.new()
	var start_error: Error = hashing.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error: Error = hashing.update(payload)
	if update_error != OK:
		return ""
	return hashing.finish().hex_encode()
