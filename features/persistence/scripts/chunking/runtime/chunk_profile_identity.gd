## 表达由可信主 Profile 身份派生的小型 chunk GF Profile 逻辑身份。
##
## 派生值只暴露只读 getter；持久化 Manifest 无权提供路径或 Profile 前缀。
class_name ChunkProfileIdentity
extends RefCounted


# --- 常量 ---

const BANK_A: StringName = &"a"
const BANK_B: StringName = &"b"
const MAX_CHUNK_INDEX: int = 63

const _IDENTITY_DOMAIN: String = "game.chunk-profile/v1"
const _MAX_MAIN_PROFILE_ID_LENGTH: int = 192
const _MAX_SECTION_ID_LENGTH: int = 64
const _MAX_LOGICAL_PATH_LENGTH: int = 255
const _MAX_LOGICAL_SEGMENT_LENGTH: int = 64
const _MAX_LOGICAL_SEGMENTS: int = 16
const _PROFILE_ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789._-"
const _SECTION_ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_-"
const _PATH_SEGMENT_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789._-"
const _ALNUM_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789"
const _RESERVED_FILE_STEMS: Array[String] = [
	"con", "prn", "aux", "nul",
	"com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
	"lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
]


# --- 私有变量 ---

var _profile_id: StringName = &""
var _file_name: String = ""
var _main_identity_digest: String = ""
var _section_id: StringName = &""
var _bank: StringName = &""
var _chunk_index: int = -1


# --- 公共方法 ---

## 从 Composition Root/SaveGraph 已验证的主 Profile 身份派生 chunk 身份。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param section_id: manifest-backed section 的稳定 ID。
## @param bank: 目标 A/B bank。
## @param chunk_index: bank 内零基 chunk 序号。
static func create(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	bank: StringName,
	chunk_index: int
) -> ChunkProfileIdentity:
	var main_profile_text: String = String(main_profile_id)
	var section_text: String = String(section_id)
	if not _is_valid_identity_token(
		main_profile_text,
		_MAX_MAIN_PROFILE_ID_LENGTH,
		_PROFILE_ID_CHARS
	):
		return null
	if not _is_valid_logical_file_name(main_file_name):
		return null
	if not _is_valid_identity_token(
		section_text,
		_MAX_SECTION_ID_LENGTH,
		_SECTION_ID_CHARS
	):
		return null
	if bank not in [BANK_A, BANK_B]:
		return null
	if chunk_index < 0 or chunk_index > MAX_CHUNK_INDEX:
		return null

	var digest: String = _make_main_identity_digest(
		main_profile_text,
		main_file_name
	)
	if digest.is_empty():
		return null
	var profile_id_text: String = "chunk.%s.%s.%s.%06d" % [
		digest,
		section_text,
		String(bank),
		chunk_index,
	]
	var file_name: String = "chunk_profiles/%s/%s/%s/%06d.save" % [
		digest,
		section_text,
		String(bank),
		chunk_index,
	]
	if not _is_valid_logical_file_name(file_name):
		return null

	var identity: ChunkProfileIdentity = ChunkProfileIdentity.new()
	identity._profile_id = StringName(profile_id_text)
	identity._file_name = file_name
	identity._main_identity_digest = digest
	identity._section_id = section_id
	identity._bank = bank
	identity._chunk_index = chunk_index
	return identity


## 获取派生的 GF runtime Profile ID。
func get_profile_id() -> StringName:
	return _profile_id


## 获取派生的 GFStorage logical file name。
func get_file_name() -> String:
	return _file_name


## 获取主 Profile 身份对的稳定摘要。
func get_main_identity_digest() -> String:
	return _main_identity_digest


## 获取业务 section ID。
func get_section_id() -> StringName:
	return _section_id


## 获取目标 A/B bank。
func get_bank() -> StringName:
	return _bank


## 获取规范 chunk 序号。
func get_chunk_index() -> int:
	return _chunk_index


# --- 私有/辅助方法 ---

static func _is_valid_identity_token(
	value: String,
	maximum_length: int,
	allowed_characters: String
) -> bool:
	if (
		value.is_empty()
		or value.length() > maximum_length
		or value != value.strip_edges()
		or value != value.to_lower()
		or not _is_ascii_alnum(value.substr(0, 1))
		or not _is_ascii_alnum(value.substr(value.length() - 1, 1))
	):
		return false
	for index: int in range(value.length()):
		if not allowed_characters.contains(value.substr(index, 1)):
			return false
	return true


static func _is_valid_logical_file_name(value: String) -> bool:
	if (
		value.is_empty()
		or value.length() > _MAX_LOGICAL_PATH_LENGTH
		or value != value.strip_edges()
		or value != value.to_lower()
	):
		return false
	var segments: PackedStringArray = value.split("/", true)
	if segments.is_empty() or segments.size() > _MAX_LOGICAL_SEGMENTS:
		return false
	for segment: String in segments:
		if not _is_valid_logical_segment(segment):
			return false
	return true


static func _is_valid_logical_segment(value: String) -> bool:
	if (
		value.is_empty()
		or value.length() > _MAX_LOGICAL_SEGMENT_LENGTH
		or not _is_ascii_alnum(value.substr(0, 1))
		or not _is_ascii_alnum(value.substr(value.length() - 1, 1))
	):
		return false
	for index: int in range(value.length()):
		if not _PATH_SEGMENT_CHARS.contains(value.substr(index, 1)):
			return false
	return value.get_slice(".", 0) not in _RESERVED_FILE_STEMS


static func _is_ascii_alnum(value: String) -> bool:
	return value.length() == 1 and _ALNUM_CHARS.contains(value)


static func _make_main_identity_digest(
	main_profile_id: String,
	main_file_name: String
) -> String:
	var payload: PackedByteArray = _IDENTITY_DOMAIN.to_utf8_buffer()
	var _domain_separator_appended: bool = payload.append(0)
	payload.append_array(main_profile_id.to_utf8_buffer())
	var _profile_separator_appended: bool = payload.append(0)
	payload.append_array(main_file_name.to_utf8_buffer())
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(payload) != OK:
		return ""
	return hashing.finish().hex_encode()
