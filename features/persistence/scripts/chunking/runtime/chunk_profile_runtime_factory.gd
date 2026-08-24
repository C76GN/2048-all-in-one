## 由可信主 Profile 身份构造严格的小型 chunk GF Profile。
##
## Factory 不接受 Manifest 提供的 Profile 前缀或文件路径。
class_name ChunkProfileRuntimeFactory
extends RefCounted


# --- 常量 ---

const PROFILE_SCHEMA_ID: StringName = &"game.chunk_blob_profile"
const PROFILE_SCHEMA_VERSION: int = 1


# --- 公共方法 ---

## 派生 ChunkStageRequest 使用的可信、非持久化 Profile ID 前缀。
##
## @param main_profile_id: 主玩家 GF Profile ID。
## @param main_file_name: 主玩家 Profile 逻辑文件名。
## @param section_id: manifest-backed section ID。
## @return 合法身份对应 `chunk.<digest>.<section>`；非法时为空。
static func make_profile_prefix(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName
) -> String:
	var identity: ChunkProfileIdentity = make_identity(
		main_profile_id,
		main_file_name,
		section_id,
		ChunkProfileIdentity.BANK_A,
		0
	)
	if identity == null:
		return ""
	var suffix: String = ".%s.%06d" % [
		String(ChunkProfileIdentity.BANK_A),
		0,
	]
	var profile_id: String = String(identity.get_profile_id())
	return (
		profile_id.left(profile_id.length() - suffix.length())
		if profile_id.ends_with(suffix)
		else ""
	)

## 派生一个不可变 chunk Profile 身份。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param section_id: manifest-backed section 的稳定 ID。
## @param bank: 目标 A/B bank。
## @param chunk_index: bank 内零基 chunk 序号。
static func make_identity(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	bank: StringName,
	chunk_index: int
) -> ChunkProfileIdentity:
	return ChunkProfileIdentity.create(
		main_profile_id,
		main_file_name,
		section_id,
		bank,
		chunk_index
	)


## 构造只含 blob section、未知 section 拒绝且恢复 ACTION_FAIL 的 Profile。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param section_id: manifest-backed section 的稳定 ID。
## @param bank: 目标 A/B bank。
## @param chunk_index: bank 内零基 chunk 序号。
static func make_profile(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	bank: StringName,
	chunk_index: int
) -> GFSaveProfile:
	var identity: ChunkProfileIdentity = make_identity(
		main_profile_id,
		main_file_name,
		section_id,
		bank,
		chunk_index
	)
	if identity == null:
		return null

	var policy: GFSaveRecoveryPolicy = GFSaveRecoveryPolicy.new()
	policy.missing_file_action = GFSaveRecoveryPolicy.ACTION_FAIL
	policy.corrupt_file_action = GFSaveRecoveryPolicy.ACTION_FAIL
	policy.retry_delays_msec = PackedInt32Array()

	var provider: ChunkBlobSaveSectionProvider = (
		ChunkBlobSaveSectionProvider.new()
	)
	var providers: Array[GFSaveSectionProvider] = [provider]
	var profile: GFSaveProfile = GFSaveProfile.new()
	profile.profile_id = identity.get_profile_id()
	profile.schema_id = PROFILE_SCHEMA_ID
	profile.file_name = identity.get_file_name()
	profile.schema_version = PROFILE_SCHEMA_VERSION
	profile.providers = providers
	profile.recovery_policy = policy
	profile.save_enabled = true
	profile.load_enabled = true
	profile.unknown_section_policy = GFSaveProfile.UNKNOWN_SECTION_REJECT
	var validation: Dictionary = profile.validate_profile()
	var valid_value: Variant = validation.get("ok", false)
	if not valid_value is bool or not valid_value:
		return null
	return profile
