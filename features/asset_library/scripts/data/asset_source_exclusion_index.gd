## AssetSourceExclusionIndex: 保存已从评审库移除的源素材身份，防止全量导入复活。
class_name AssetSourceExclusionIndex
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1


# --- 私有变量 ---

var _entries_by_key: Dictionary = {}


# --- 公共方法 ---

## 加入一个只由源包、相对路径和内容哈希组成的排除项。
## @param source_pack_id: 导入配置中的稳定源包 ID。
## @param relative_path: 素材在源包内的相对路径。
## @param sha256: 源文件内容的 SHA-256。
func add_exclusion(
	source_pack_id: String,
	relative_path: String,
	sha256: String
) -> Error:
	var normalized_pack_id: String = source_pack_id.strip_edges()
	var normalized_relative_path: String = _normalize_relative_path(relative_path)
	var normalized_sha256: String = sha256.strip_edges().to_lower()
	if (
		normalized_pack_id.is_empty()
		or normalized_pack_id.contains("/")
		or normalized_pack_id.contains("\\")
		or normalized_pack_id.contains("|")
		or normalized_relative_path.is_empty()
		or normalized_relative_path.contains("|")
		or normalized_sha256.length() != 64
		or not normalized_sha256.is_valid_hex_number(false)
	):
		return ERR_INVALID_PARAMETER
	var key: String = _make_key(
		normalized_pack_id,
		normalized_relative_path,
		normalized_sha256
	)
	_entries_by_key[key] = {
		"source_pack_id": normalized_pack_id,
		"relative_path": normalized_relative_path,
		"sha256": normalized_sha256,
	}
	return OK


## 判断指定源素材的精确内容身份是否已经被排除。
## @param source_pack_id: 导入配置中的稳定源包 ID。
## @param relative_path: 素材在源包内的相对路径。
## @param sha256: 源文件内容的 SHA-256。
func is_excluded(source_pack_id: String, relative_path: String, sha256: String) -> bool:
	var normalized_relative_path: String = _normalize_relative_path(relative_path)
	if normalized_relative_path.is_empty():
		return false
	return _entries_by_key.has(_make_key(
		source_pack_id.strip_edges(),
		normalized_relative_path,
		sha256.strip_edges().to_lower()
	))


## 返回排除项数量。
func size() -> int:
	return _entries_by_key.size()


## 返回按稳定身份排序的排除项副本。
func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys: Array = _entries_by_key.keys()
	keys.sort()
	for key_value: Variant in keys:
		var entry: Dictionary = GFVariantData.get_option_dictionary(
			_entries_by_key,
			key_value
		)
		result.append(entry.duplicate(true))
	return result


## 从 JSON 文件加载索引；文件不存在时视为空索引。
## @param path: 排除索引 JSON 路径。
func load_from_path(path: String) -> Error:
	_entries_by_key.clear()
	if not FileAccess.file_exists(path):
		return OK
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = GFVariantJsonCodec.parse_json_text(text)
	if not (parsed is Dictionary):
		return ERR_PARSE_ERROR
	var document: Dictionary = parsed
	if GFVariantData.get_option_int(document, "schema_version", -1) != SCHEMA_VERSION:
		return ERR_INVALID_DATA
	for entry_value: Variant in GFVariantData.get_option_array(document, "entries"):
		var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
		var add_result: Error = add_exclusion(
			GFVariantData.get_option_string(entry, "source_pack_id"),
			GFVariantData.get_option_string(entry, "relative_path"),
			GFVariantData.get_option_string(entry, "sha256")
		)
		if add_result != OK:
			_entries_by_key.clear()
			return ERR_INVALID_DATA
	return OK


## 把索引以稳定、可审计的 JSON 文档写入指定路径。
## @param path: 排除索引 JSON 路径。
func save_to_path(path: String) -> Error:
	var absolute_directory: String = ProjectSettings.globalize_path(path.get_base_dir())
	var directory_result: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_result != OK:
		return directory_result
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var document: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"entries": get_entries(),
	}
	var text: String = GFVariantJsonCodec.stringify_json_compatible(
		document,
		"\t",
		true
	) + "\n"
	var stored: bool = file.store_string(text)
	file.close()
	return OK if stored else ERR_FILE_CANT_WRITE


# --- 私有/辅助方法 ---

static func _normalize_relative_path(path: String) -> String:
	var normalized: String = GFPathTools.normalize_path(path.strip_edges())
	if (
		normalized.is_empty()
		or normalized.is_absolute_path()
		or normalized == ".."
		or normalized.begins_with("../")
	):
		return ""
	return normalized.trim_prefix("./")


static func _make_key(
	source_pack_id: String,
	relative_path: String,
	sha256: String
) -> String:
	return "%s|%s|%s" % [source_pack_id, relative_path, sha256]
