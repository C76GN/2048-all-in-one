## AssetSourceExclusionIndex: 保存已从评审库移除的源素材身份，防止全量导入复活。
##
## 该索引只由素材导入/清理工具持有，不进入玩家运行时真源；保存入口因此使用
## GFGeneratedArtifactReport 的原子生成物契约。
class_name AssetSourceExclusionIndex
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const MAX_INDEX_FILE_BYTES: int = 4 * 1024 * 1024
const MAX_INDEX_DEPTH: int = 8
const MAX_INDEX_ENTRIES: int = 500_000
const _GENERATED_OUTPUT_ROOTS: PackedStringArray = [
	"res://features/asset_library/resources",
	"user://",
]
const _BOUNDED_JSON_READER_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_bounded_json_object_reader.gd"
)


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
	var report: Dictionary = load_report_from_path(path)
	return _get_report_error_code(report, ERR_INVALID_DATA)


## 从 JSON 文件加载索引并返回结构化读取/校验报告；文件不存在时视为空索引。
## @param path: 排除索引 JSON 路径。
## @return: 包含 error_kind、读取预算证据和 loaded_count 的终态报告。
func load_report_from_path(path: String) -> Dictionary:
	_entries_by_key.clear()
	if not FileAccess.file_exists(path):
		return {
			"ok": true,
			"error_code": OK,
			"error_kind": &"",
			"message": "",
			"source_path": path,
			"exists": false,
			"loaded_count": 0,
		}
	var read_report: Dictionary = _BOUNDED_JSON_READER_SCRIPT.read_object_report(
		path,
		{
			"max_file_bytes": MAX_INDEX_FILE_BYTES,
			"max_depth": MAX_INDEX_DEPTH,
			"max_entries": MAX_INDEX_ENTRIES,
		}
	)
	if not GFVariantData.get_option_bool(read_report, "ok"):
		return _make_load_failure(
			read_report,
			_get_report_error_code(read_report, ERR_INVALID_DATA),
			GFVariantData.get_option_string_name(read_report, "error_kind", &"invalid_json"),
			GFVariantData.get_option_string(read_report, "message", "排除索引 JSON 无效。")
		)
	var document: Dictionary = GFVariantData.get_option_dictionary(
		read_report,
		"data"
	)
	if GFVariantData.get_option_int(document, "schema_version", -1) != SCHEMA_VERSION:
		return _make_load_failure(
			read_report,
			ERR_INVALID_DATA,
			&"unsupported_schema",
			"排除索引 schema_version 不受支持。"
		)
	var entries: Array = GFVariantData.get_option_array(document, "entries")
	for entry_index: int in entries.size():
		var entry_value: Variant = entries[entry_index]
		var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
		var add_result: Error = add_exclusion(
			GFVariantData.get_option_string(entry, "source_pack_id"),
			GFVariantData.get_option_string(entry, "relative_path"),
			GFVariantData.get_option_string(entry, "sha256")
		)
		if add_result != OK:
			_entries_by_key.clear()
			var failure: Dictionary = _make_load_failure(
				read_report,
				ERR_INVALID_DATA,
				&"invalid_entry",
				"排除索引包含无效身份项。"
			)
			failure["entry_index"] = entry_index
			return failure
	var result: Dictionary = _summarize_read_report(read_report)
	result["ok"] = true
	result["error_code"] = OK
	result["error_kind"] = &""
	result["message"] = ""
	result["exists"] = true
	result["loaded_count"] = _entries_by_key.size()
	return result


## 把索引以稳定、可审计的 JSON 文档写入指定路径。
## @param path: 排除索引 JSON 路径。
func save_to_path(path: String) -> Error:
	return GFGeneratedArtifactReport.get_error_code(save_report_to_path(path))


## 保存索引并返回 GF 标准生成产物报告；save_to_path 保留原 Error 契约。
## @param path: 排除索引 JSON 路径。
func save_report_to_path(path: String) -> Dictionary:
	var document: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"entries": get_entries(),
	}
	var text: String = GFVariantJsonCodec.stringify_json_compatible(
		document,
		"\t",
		true
	) + "\n"
	var save_options: Dictionary = {
		"allowed_roots": _GENERATED_OUTPUT_ROOTS,
		"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED,
		"generator_id": "asset_library.source_exclusion_index",
		"source_id": "asset_library.source_exclusions",
		"label": "AssetSourceExclusionIndex",
		"scan_filesystem": false,
	}
	var baseline: Dictionary = _read_text_baseline(path)
	if GFVariantData.get_option_bool(baseline, "ok"):
		save_options["expected_previous_sha256"] = GFVariantData.get_option_string(
			baseline,
			"sha256"
		)
	return GFGeneratedArtifactReport.save_text(
		path,
		text,
		save_options
	)


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


static func _summarize_read_report(read_report: Dictionary) -> Dictionary:
	var summary: Dictionary = read_report.duplicate(true)
	var _removed_data: bool = summary.erase("data")
	return summary


static func _make_load_failure(
	read_report: Dictionary,
	error_code: Error,
	error_kind: StringName,
	message: String
) -> Dictionary:
	var result: Dictionary = _summarize_read_report(read_report)
	result["ok"] = false
	result["error_code"] = error_code
	result["error_kind"] = error_kind
	result["message"] = message
	result["exists"] = true
	result["loaded_count"] = 0
	return result


static func _read_text_baseline(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "sha256": ""}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "sha256": ""}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	return {
		"ok": read_error == OK,
		"sha256": text.sha256_text() if read_error == OK else "",
	}


static func _get_report_error_code(report: Dictionary, fallback: Error) -> Error:
	@warning_ignore("int_as_enum_without_cast")
	var error_code: Error = GFVariantData.get_option_int(
		report,
		"error_code",
		fallback
	)
	return error_code
