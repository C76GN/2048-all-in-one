## 冻结一次严格派生的 chunk logical family 回收集合。
##
## 请求只能由可信主 Profile 身份、section ID、固定 A/B bank 和 0..63 序号
## 派生；不会扫描、枚举或解析 GFStorage 私有目录。
class_name ChunkProfileCleanupRequest
extends RefCounted


# --- 常量 ---

const KIND_EXACT_COMMIT: StringName = &"exact_commit"
const KIND_DISCARD_CANDIDATE: StringName = &"discard_candidate"
const KIND_ENTIRE_FAMILY: StringName = &"entire_family"


# --- 私有变量 ---

var _kind: StringName = &""
var _main_profile_id: StringName = &""
var _main_file_name: String = ""
var _section_id: StringName = &""
var _identities: Array[ChunkProfileIdentity] = []


# --- 公共方法 ---

## 为一次 exact 主 Manifest commit 构造回收请求。
##
## 旧 active bank 已整体失去可见性；新 active bank 只保留 Manifest count
## 范围，尾块可安全回收。首次提交时 previous_active_bank 传 BANK_NONE。
## @param main_profile_id: 已提交主 Manifest 的可信主 Profile ID。
## @param main_file_name: 已提交主 Profile 的可信 logical 文件名。
## @param section_id: 已提交 Manifest 所属的稳定 Feature section ID。
## @param previous_active_bank: 提交前的 active bank；首次提交为 BANK_NONE。
## @param committed_manifest: 已精确提交并获得可见性的当前 Manifest。
static func after_exact_commit(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	previous_active_bank: StringName,
	committed_manifest: ChunkManifest
) -> ChunkProfileCleanupRequest:
	if (
		committed_manifest == null
		or not committed_manifest.is_valid()
		or committed_manifest.get_section_id() != section_id
		or previous_active_bank not in [
			ChunkManifest.BANK_NONE,
			ChunkManifest.BANK_A,
			ChunkManifest.BANK_B,
		]
		or previous_active_bank == committed_manifest.get_bank()
	):
		return null
	var request: ChunkProfileCleanupRequest = _create_base(
		KIND_EXACT_COMMIT,
		main_profile_id,
		main_file_name,
		section_id
	)
	if request == null:
		return null
	if previous_active_bank != ChunkManifest.BANK_NONE:
		if not request._append_bank_range(
			previous_active_bank,
			0,
			ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
		):
			return null
	if not request._append_bank_range(
		committed_manifest.get_bank(),
		committed_manifest.get_chunk_count(),
		ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
	):
		return null
	return request


## 为已知未提交的候选 bank 构造整 bank 回收请求。
## @param main_profile_id: 候选载荷所属的可信主 Profile ID。
## @param main_file_name: 候选载荷所属主 Profile 的可信 logical 文件名。
## @param section_id: 候选 Manifest 所属的稳定 Feature section ID。
## @param candidate_manifest: 已知未提交的候选 Manifest。
static func discard_candidate(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	candidate_manifest: ChunkManifest
) -> ChunkProfileCleanupRequest:
	if (
		candidate_manifest == null
		or not candidate_manifest.is_valid()
		or candidate_manifest.get_section_id() != section_id
	):
		return null
	var request: ChunkProfileCleanupRequest = _create_base(
		KIND_DISCARD_CANDIDATE,
		main_profile_id,
		main_file_name,
		section_id
	)
	if request == null or not request._append_bank_range(
		candidate_manifest.get_bank(),
		0,
		ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
	):
		return null
	return request


## 为显式主 Profile 删除/reset 构造整套 A/B 派生 family 回收请求。
##
## 本入口本身不删除主 Profile，也不会由 Utility 未经 owner 调用而自动触发。
## @param main_profile_id: 待删除或 reset 的可信主 Profile ID。
## @param main_file_name: 待删除或 reset 主 Profile 的可信 logical 文件名。
## @param section_id: 需要回收派生 family 的稳定 Feature section ID。
static func entire_family(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName
) -> ChunkProfileCleanupRequest:
	var request: ChunkProfileCleanupRequest = _create_base(
		KIND_ENTIRE_FAMILY,
		main_profile_id,
		main_file_name,
		section_id
	)
	if request == null:
		return null
	for bank: StringName in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]:
		if not request._append_bank_range(
			bank,
			0,
			ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
		):
			return null
	return request


## 获取回收原因分类。
func get_kind() -> StringName:
	return _kind


## 获取可信主 Profile ID。
func get_main_profile_id() -> StringName:
	return _main_profile_id


## 获取可信主 Profile logical 文件名。
func get_main_file_name() -> String:
	return _main_file_name


## 获取稳定 section ID。
func get_section_id() -> StringName:
	return _section_id


## 获取有界 logical family 数量。
func get_identity_count() -> int:
	return _identities.size()


## 获取指定派生身份；越界返回 null。
## @param index: identities 集合中的零基索引。
func get_identity(index: int) -> ChunkProfileIdentity:
	if index < 0 or index >= _identities.size():
		return null
	return _identities[index]


## 查询请求是否满足严格派生与固定预算。
func is_valid() -> bool:
	return (
		_kind in [KIND_EXACT_COMMIT, KIND_DISCARD_CANDIDATE, KIND_ENTIRE_FAMILY]
		and not _main_profile_id.is_empty()
		and not _main_file_name.is_empty()
		and not _section_id.is_empty()
		and _identities.size() <= 2 * (ChunkProfileIdentity.MAX_CHUNK_INDEX + 1)
	)


# --- 私有/辅助方法 ---

static func _create_base(
	kind: StringName,
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName
) -> ChunkProfileCleanupRequest:
	# index 0 的成功派生同时验证全部可信身份字段。
	if ChunkProfileIdentity.create(
		main_profile_id,
		main_file_name,
		section_id,
		ChunkProfileIdentity.BANK_A,
		0
	) == null:
		return null
	var request: ChunkProfileCleanupRequest = ChunkProfileCleanupRequest.new()
	request._kind = kind
	request._main_profile_id = main_profile_id
	request._main_file_name = main_file_name
	request._section_id = section_id
	return request


func _append_bank_range(bank: StringName, begin: int, end: int) -> bool:
	if (
		bank not in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]
		or begin < 0
		or end < begin
		or end > ChunkProfileIdentity.MAX_CHUNK_INDEX + 1
	):
		return false
	for chunk_index: int in range(begin, end):
		var identity: ChunkProfileIdentity = ChunkProfileIdentity.create(
			_main_profile_id,
			_main_file_name,
			_section_id,
			bank,
			chunk_index
		)
		if identity == null:
			return false
		_identities.append(identity)
	return true
