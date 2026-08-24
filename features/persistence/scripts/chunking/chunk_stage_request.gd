## 冻结一次 inactive-bank 分块 staging 所需的项目意图与 chunk bytes。
##
## 请求不包含物理文件路径；active bank 来自已通过 GF Profile 读取并校验的
## Manifest，核心只选择另一 bank，且不拥有最终 Manifest 提交。
class_name ChunkStageRequest
extends RefCounted


# --- 常量 ---

const _MAX_PROFILE_PREFIX_LENGTH: int = 192


# --- 私有变量 ---

var _ready: bool = false
var _chunk_profile_prefix: String = ""
var _chunks: Array[PackedByteArray] = []
var _manifest: ChunkManifest = null


# --- 公共方法 ---

## 创建与调用方数组隔离的 typed staging request。
##
## @param chunk_profile_prefix: 派生 A/B chunk Profile ID 的稳定前缀。
## @param section_id: Feature section ID。
## @param section_schema_version: Feature section schema 版本。
## @param active_bank: 已激活 bank；首次 staging 传 BANK_NONE。
## @param chunks: 按规范顺序冻结的 chunk bytes。
## @return 参数合法时返回请求，否则返回 null。
static func create(
	chunk_profile_prefix: String,
	section_id: StringName,
	section_schema_version: int,
	active_bank: StringName,
	chunks: Array[PackedByteArray]
) -> ChunkStageRequest:
	var target_bank: StringName = ChunkManifest.select_inactive_bank(active_bank)
	if target_bank == ChunkManifest.BANK_NONE:
		return null
	if (
		chunk_profile_prefix.is_empty()
		or chunk_profile_prefix != chunk_profile_prefix.strip_edges()
		or chunk_profile_prefix.length() > _MAX_PROFILE_PREFIX_LENGTH
		or chunk_profile_prefix.contains("\n")
		or chunk_profile_prefix.contains("\r")
	):
		return null

	var request: ChunkStageRequest = ChunkStageRequest.new()
	request._chunk_profile_prefix = chunk_profile_prefix
	for payload: PackedByteArray in chunks:
		request._chunks.append(payload.duplicate())
	request._manifest = ChunkManifest.create(
		section_id,
		section_schema_version,
		target_bank,
		request._chunks
	)
	if request._manifest == null:
		return null
	request._ready = true
	return request


## 验证请求仍满足 Manifest schema 与预算。
##
## @return 可提交时返回 true。
func is_valid() -> bool:
	return (
		_ready
		and not _chunk_profile_prefix.is_empty()
		and _manifest != null
		and _manifest.is_valid()
		and _manifest.get_chunk_count() == _chunks.size()
	)


## 为 inactive bank 构造不可见的候选 Manifest。
##
## @return 请求合法时返回新 Manifest，否则返回 null。
func build_manifest() -> ChunkManifest:
	return _manifest.duplicate_manifest() if is_valid() else null


## 使用可信非持久化 prefix 派生指定 chunk 的逻辑 GF Profile ID。
##
## @param index: chunk 规范序号。
## @return 合法序号对应的 Profile ID；非法时为空。
func get_chunk_profile_id(index: int) -> StringName:
	if (
		not _ready
		or _manifest == null
		or index < 0
		or index >= _chunks.size()
	):
		return &""
	return StringName("%s.%s.%06d" % [
		_chunk_profile_prefix,
		String(_manifest.get_bank()),
		index,
	])


## 获取 chunk 数量。
func get_chunk_count() -> int:
	return _chunks.size()


## 获取指定 chunk 的隔离副本。
##
## @param index: chunk 规范序号。
## @return 合法序号返回 bytes 副本，否则返回空数组。
func duplicate_chunk(index: int) -> PackedByteArray:
	if index < 0 or index >= _chunks.size():
		return PackedByteArray()
	return _chunks[index].duplicate()
