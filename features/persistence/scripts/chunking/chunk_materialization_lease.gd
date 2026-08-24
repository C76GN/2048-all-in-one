## 为 GF Profile Provider 暂存单所有者分块载荷。
##
## Lease 通过 Object 身份穿过 Profile context；载荷只能 claim 一次，避免大型
## Dictionary 或 PackedByteArray 被普通业务入口重复复制或长期暴露。
class_name ChunkMaterializationLease
extends RefCounted


# --- 私有变量 ---

var _value: Variant = null
var _available: bool = false
var _claimed: bool = false
var _manifest_payload: Dictionary = {}
var _main_profile_id: StringName = &""
var _canonical_file_name: String = ""
var _section_id: StringName = &""
var _section_schema_version: int = 0
var _rollback_root: Variant = null
var _rollback_available: bool = false
var _rollback_claimed: bool = false


# --- 公共方法 ---

## 接管载荷；调用方在返回后必须放弃源值及其嵌套集合 alias。
##
## @param value: 交给未来 Profile Provider 的不透明载荷。
## @param manifest: 与载荷对应且已通过严格校验的 Chunk Manifest。
## @param main_profile_id: 绑定载荷权限的可信主 Profile ID。
## @param canonical_file_name: 绑定载荷权限的规范主 Profile 文件名。
## @return 持有载荷的新 Lease。
static func take_ownership(
	value: Variant,
	manifest: ChunkManifest,
	main_profile_id: StringName,
	canonical_file_name: String
) -> ChunkMaterializationLease:
	if (
		typeof(value) == TYPE_NIL
		or manifest == null
		or not manifest.is_valid()
		or main_profile_id == &""
		or not _is_bounded_authority_text(canonical_file_name)
	):
		return null
	var manifest_copy: ChunkManifest = manifest.duplicate_manifest()
	if manifest_copy == null:
		return null
	var lease: ChunkMaterializationLease = ChunkMaterializationLease.new()
	lease._value = value
	lease._available = true
	lease._manifest_payload = manifest_copy.to_dict()
	lease._main_profile_id = main_profile_id
	lease._canonical_file_name = canonical_file_name
	lease._section_id = manifest_copy.get_section_id()
	lease._section_schema_version = (
		manifest_copy.get_section_schema_version()
	)
	return lease


## 查询载荷是否仍可被唯一消费者接管。
##
## @return 尚未 claim 时返回 true。
func is_available() -> bool:
	return _available and not _claimed


## 查询载荷是否已经被接管。
##
## @return 首次 claim 后返回 true。
func is_claimed() -> bool:
	return _claimed


## 查询绑定的 Profile/section 权限是否与当前事务完全一致。
## @param main_profile_id: 当前事务使用的可信主 Profile ID。
## @param canonical_file_name: 当前事务使用的规范主 Profile 文件名。
## @param section_id: 当前事务使用的 Feature section ID。
## @param section_schema_version: 当前事务要求的 section schema 版本。
func matches_authority(
	main_profile_id: StringName,
	canonical_file_name: String,
	section_id: StringName,
	section_schema_version: int
) -> bool:
	return (
		main_profile_id != &""
		and main_profile_id == _main_profile_id
		and canonical_file_name == _canonical_file_name
		and section_id == _section_id
		and section_schema_version == _section_schema_version
	)


## 一次性移出与实际 Manifest/权限完全匹配的载荷。
##
## 错配与重复调用都返回 null；错配不会消费载荷。
## @param manifest: 当前事务已经验证的实际 Chunk Manifest。
## @param main_profile_id: 当前事务使用的可信主 Profile ID。
## @param canonical_file_name: 当前事务使用的规范主 Profile 文件名。
## @param section_id: 当前事务使用的 Feature section ID。
## @param section_schema_version: 当前事务要求的 section schema 版本。
func claim_for_manifest(
	manifest: ChunkManifest,
	main_profile_id: StringName,
	canonical_file_name: String,
	section_id: StringName,
	section_schema_version: int
) -> Variant:
	if (
		not is_available()
		or not matches_authority(
			main_profile_id,
			canonical_file_name,
			section_id,
			section_schema_version
		)
		or not _matches_manifest(manifest)
	):
		return null
	var claimed_value: Variant = _value
	_value = null
	_available = false
	_claimed = true
	return claimed_value


## 在同一 load context 中暂存应用前的浅层业务根。
##
## root 只存在于内存 lease 中，不进入 GF 持久化 Variant；只能暂存一次。
## @param root: 移交给 Lease 唯一持有的浅层回滚业务根。
## @param main_profile_id: 当前 load context 的可信主 Profile ID。
## @param canonical_file_name: 当前 load context 的规范主 Profile 文件名。
## @param section_id: 当前 load context 的 Feature section ID。
## @param section_schema_version: 当前 load context 的 section schema 版本。
func stage_rollback_root_taking_ownership(
	root: Variant,
	main_profile_id: StringName,
	canonical_file_name: String,
	section_id: StringName,
	section_schema_version: int
) -> bool:
	if (
		typeof(root) == TYPE_NIL
		or _rollback_available
		or _rollback_claimed
		or not matches_authority(
			main_profile_id,
			canonical_file_name,
			section_id,
			section_schema_version
		)
	):
		return false
	_rollback_root = root
	_rollback_available = true
	return true


## 查询浅层回滚根是否仍由 lease 持有。
func is_rollback_root_available() -> bool:
	return _rollback_available and not _rollback_claimed


## 一次性移出同一权限域中的浅层回滚根。
## @param main_profile_id: 当前回滚事务使用的可信主 Profile ID。
## @param canonical_file_name: 当前回滚事务使用的规范主 Profile 文件名。
## @param section_id: 当前回滚事务使用的 Feature section ID。
## @param section_schema_version: 当前回滚事务要求的 section schema 版本。
func claim_rollback_root_for_authority(
	main_profile_id: StringName,
	canonical_file_name: String,
	section_id: StringName,
	section_schema_version: int
) -> Variant:
	if (
		not is_rollback_root_available()
		or not matches_authority(
			main_profile_id,
			canonical_file_name,
			section_id,
			section_schema_version
		)
	):
		return null
	var claimed_root: Variant = _rollback_root
	_rollback_root = null
	_rollback_available = false
	_rollback_claimed = true
	return claimed_root


# --- 私有/辅助方法 ---

func _matches_manifest(manifest: ChunkManifest) -> bool:
	return (
		manifest != null
		and manifest.is_valid()
		and manifest.get_section_id() == _section_id
		and manifest.get_section_schema_version() == _section_schema_version
		and manifest.to_dict() == _manifest_payload
	)


static func _is_bounded_authority_text(value: String) -> bool:
	return (
		not value.is_empty()
		and value == value.strip_edges()
		and value.length() <= 512
		and not value.contains("\n")
		and not value.contains("\r")
	)
