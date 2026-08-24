## ProjectResourceReferenceValidator: 有界校验项目文本资源的外部资源引用。
##
## 仅扫描显式项目根中的 .tscn/.tres，不加载资源。每条 ext_resource 都校验
## res:// 路径存在；当引用和目标都声明稳定 UID 时，再要求二者完全一致。
class_name ProjectResourceReferenceValidator
extends RefCounted


# --- 常量 ---

const DEFAULT_SOURCE_ROOTS: Array[String] = [
	"res://app",
	# 运行时拼接 Feature 聚合根；它不是 architecture Module 自身，不能被 GF
	# ownership 扫描误识别为指向一个未声明的具体资源。
	"res:/" + "/features",
	"res://shared",
]
const DEFAULT_EXCLUDED_SOURCE_PATHS: Array[String] = [
	# 这两棵目录是作者评审/原始素材库存，所有发布 preset 都明确排除；运行时资源
	# 引用门禁不重复遍历它们的数千条评审记录。
	"res://features/asset_library/resources/review",
	"res://features/asset_library/resources/source_packs",
]
const _TEXT_RESOURCE_EXTENSIONS: Array[String] = ["tscn", "tres"]
const _MAX_SOURCE_FILES: int = 20_000
const _MAX_VISITED_ENTRIES_PER_ROOT: int = 30_000
const _MAX_SCAN_DEPTH: int = 64
const _MAX_SOURCE_FILE_BYTES: int = 8 * 1024 * 1024
const _MAX_LINES_PER_FILE: int = 100_000
const _MAX_REFERENCES_PER_FILE: int = 8_192
const _MAX_TOTAL_REFERENCES: int = 100_000
const _MAX_ISSUES: int = 256
const _MAX_UID_HEADER_BYTES: int = 4 * 1024
const _MAX_IMPORT_METADATA_BYTES: int = 64 * 1024


# --- 公共方法 ---

## 校验默认项目资源根，或校验 options.roots 指定的隔离根。
##
## options 仅用于测试/工具调用，可覆盖 roots；所有读取仍受固定预算约束。
static func validate_project_resources(options: Dictionary = {}) -> Dictionary:
	var roots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		options,
		"roots",
		PackedStringArray(DEFAULT_SOURCE_ROOTS)
	)
	var excluded_paths: PackedStringArray = GFVariantData.get_option_packed_string_array(
		options,
		"excluded_paths",
		PackedStringArray(DEFAULT_EXCLUDED_SOURCE_PATHS)
	)
	var issues: Array[Dictionary] = []
	var canonical_uid_cache: Dictionary = {}
	var scanned_file_count: int = 0
	var reference_count: int = 0
	var input_complete: bool = true

	for root_path: String in roots:
		if scanned_file_count >= _MAX_SOURCE_FILES or reference_count >= _MAX_TOTAL_REFERENCES:
			input_complete = false
			_append_issue(
				issues,
				_make_issue(
					&"resource_reference_scan_limit",
					root_path,
					0,
					"项目资源引用扫描达到全局预算。"
				)
			)
			break

		var scan_report: Dictionary = GFPathEnumerationTools.scan_files(root_path, {
			"recursive": true,
			"include_hidden": false,
			"extensions": _TEXT_RESOURCE_EXTENSIONS,
			"excluded_paths": excluded_paths,
			"max_scan_depth": _MAX_SCAN_DEPTH,
			"max_file_count": _MAX_SOURCE_FILES - scanned_file_count,
			"max_entry_count": _MAX_VISITED_ENTRIES_PER_ROOT,
			"sort": true,
		})
		if (
			not GFVariantData.get_option_bool(scan_report, "ok")
			or GFVariantData.get_option_bool(scan_report, "truncated")
		):
			input_complete = false
			_append_issue(
				issues,
				_make_issue(
					&"resource_reference_scan_incomplete",
					root_path,
					0,
					"项目资源根扫描未完整结束：kind=%s path=%s limit=%d。" % [
						GFVariantData.get_option_string(scan_report, "limit_kind"),
						GFVariantData.get_option_string(scan_report, "limit_path"),
						GFVariantData.get_option_int(scan_report, "limit_value"),
					]
				)
			)

		for source_path: String in GFVariantData.get_option_packed_string_array(
			scan_report,
			"paths"
		):
			if scanned_file_count >= _MAX_SOURCE_FILES or reference_count >= _MAX_TOTAL_REFERENCES:
				input_complete = false
				break
			var remaining_reference_budget: int = _MAX_TOTAL_REFERENCES - reference_count
			var file_report: Dictionary = validate_text_resource_file(
				source_path,
				remaining_reference_budget,
				canonical_uid_cache
			)
			scanned_file_count += 1
			reference_count += GFVariantData.get_option_int(file_report, "reference_count")
			if not GFVariantData.get_option_bool(file_report, "input_complete", true):
				input_complete = false
			for issue_value: Variant in GFVariantData.get_option_array(file_report, "issues"):
				_append_issue(issues, GFVariantData.as_dictionary(issue_value))
			if issues.size() >= _MAX_ISSUES:
				input_complete = false
				break
		if not input_complete and issues.size() >= _MAX_ISSUES:
			break

	var error_count: int = issues.size()
	return {
		"schema_version": 1,
		"kind": "project_resource_reference_validation",
		"success": input_complete and error_count == 0,
		"input_complete": input_complete,
		"scanned_file_count": scanned_file_count,
		"reference_count": reference_count,
		"error_count": error_count,
		"warning_count": 0,
		"issues": issues,
	}


## 有界校验单个 .tscn/.tres，供默认扫描与隔离回归测试复用。
static func validate_text_resource_file(
	source_path: String,
	reference_budget: int = _MAX_TOTAL_REFERENCES,
	canonical_uid_cache: Dictionary = {}
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var reference_count: int = 0
	var input_complete: bool = true
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		_append_issue(
			issues,
			_make_issue(
				&"resource_reference_source_unreadable",
				source_path,
				0,
				"无法读取项目文本资源。"
			)
		)
		return _make_file_report(false, 0, issues)

	if file.get_length() > _MAX_SOURCE_FILE_BYTES:
		file.close()
		_append_issue(
			issues,
			_make_issue(
				&"resource_reference_source_too_large",
				source_path,
				0,
				"项目文本资源超过 %d 字节读取预算。" % _MAX_SOURCE_FILE_BYTES
			)
		)
		return _make_file_report(false, 0, issues)

	var line_number: int = 0
	while not file.eof_reached():
		if line_number >= _MAX_LINES_PER_FILE:
			input_complete = false
			_append_issue(
				issues,
				_make_issue(
					&"resource_reference_line_limit",
					source_path,
					line_number,
					"项目文本资源达到行数预算。"
				)
			)
			break
		var line: String = file.get_line()
		line_number += 1
		var reference_record: Dictionary = _parse_ext_resource(line)
		if reference_record.is_empty():
			continue
		if (
			reference_count >= _MAX_REFERENCES_PER_FILE
			or reference_count >= reference_budget
		):
			input_complete = false
			_append_issue(
				issues,
				_make_issue(
					&"resource_reference_count_limit",
					source_path,
					line_number,
					"项目文本资源达到外部引用数量预算。"
				)
			)
			break
		reference_count += 1
		var issue: Dictionary = _validate_reference(
			source_path,
			line_number,
			reference_record,
			canonical_uid_cache
		)
		if not issue.is_empty():
			_append_issue(issues, issue)
			if issues.size() >= _MAX_ISSUES:
				input_complete = false
				break
	file.close()
	return _make_file_report(input_complete, reference_count, issues)


# --- 私有/辅助方法 ---

static func _parse_ext_resource(line: String) -> Dictionary:
	var stripped: String = line.strip_edges()
	if not stripped.begins_with("[ext_resource ") or not stripped.ends_with("]"):
		return {}
	var target_path: String = _extract_quoted_attribute(stripped, "path")
	if target_path.is_empty() or not target_path.begins_with("res://"):
		return {}
	return {
		"path": target_path,
		"uid": _extract_quoted_attribute(stripped, "uid"),
	}


static func _extract_quoted_attribute(line: String, attribute_name: String) -> String:
	var marker: String = attribute_name + "=\""
	var value_start: int = line.find(marker)
	if value_start < 0:
		return ""
	value_start += marker.length()
	var value_end: int = line.find("\"", value_start)
	if value_end < value_start:
		return ""
	return line.substr(value_start, value_end - value_start)


static func _validate_reference(
	source_path: String,
	line_number: int,
	reference_record: Dictionary,
	canonical_uid_cache: Dictionary
) -> Dictionary:
	var target_path: String = GFVariantData.get_option_string(reference_record, "path")
	if not FileAccess.file_exists(target_path):
		return _make_issue(
			&"ext_resource_path_missing",
			source_path,
			line_number,
			"ext_resource 目标不存在：%s。" % target_path,
			target_path
		)

	var declared_uid: String = GFVariantData.get_option_string(reference_record, "uid")
	if declared_uid.is_empty():
		return {}
	var canonical_uid: String = _read_canonical_uid_cached(
		target_path,
		canonical_uid_cache
	)
	# 并非每种合法资源都有源码侧 UID；没有可比真值时只保留路径校验。
	if canonical_uid.is_empty():
		return {}
	if declared_uid == canonical_uid:
		return {}
	return _make_issue(
		&"ext_resource_uid_mismatch",
		source_path,
		line_number,
		"ext_resource UID 与目标不一致：declared=%s canonical=%s target=%s。" % [
			declared_uid,
			canonical_uid,
			target_path,
		],
		target_path
	)


static func _read_canonical_uid(target_path: String) -> String:
	var sidecar_path: String = target_path + ".uid"
	if FileAccess.file_exists(sidecar_path):
		return _read_uid_sidecar(sidecar_path)

	var extension: String = target_path.get_extension().to_lower()
	if extension == "tscn" or extension == "tres":
		return _read_text_resource_header_uid(target_path)

	var import_path: String = target_path + ".import"
	if FileAccess.file_exists(import_path):
		return _read_import_uid(import_path)
	return ""


static func _read_canonical_uid_cached(target_path: String, cache: Dictionary) -> String:
	if cache.has(target_path):
		return GFVariantData.get_option_string(cache, target_path)
	var canonical_uid: String = _read_canonical_uid(target_path)
	cache[target_path] = canonical_uid
	return canonical_uid


static func _read_uid_sidecar(path: String) -> String:
	var text: String = _read_prefix(path, _MAX_UID_HEADER_BYTES).strip_edges()
	return text if text.begins_with("uid://") else ""


static func _read_text_resource_header_uid(path: String) -> String:
	var prefix: String = _read_prefix(path, _MAX_UID_HEADER_BYTES)
	if prefix.is_empty():
		return ""
	var first_line: String = prefix.get_slice("\n", 0).strip_edges()
	return _extract_quoted_attribute(first_line, "uid")


static func _read_import_uid(path: String) -> String:
	var prefix: String = _read_prefix(path, _MAX_IMPORT_METADATA_BYTES)
	if prefix.is_empty():
		return ""
	for line: String in prefix.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("uid=\""):
			return _extract_quoted_attribute(stripped, "uid")
	return ""


static func _read_prefix(path: String, max_bytes: int) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var byte_count: int = mini(file.get_length(), max_bytes)
	var bytes: PackedByteArray = file.get_buffer(byte_count)
	file.close()
	return bytes.get_string_from_utf8()


static func _make_file_report(
	input_complete: bool,
	reference_count: int,
	issues: Array[Dictionary]
) -> Dictionary:
	return {
		"success": input_complete and issues.is_empty(),
		"input_complete": input_complete,
		"reference_count": reference_count,
		"error_count": issues.size(),
		"issues": issues,
	}


static func _make_issue(
	kind: StringName,
	path: String,
	line_number: int,
	message: String,
	target_path: String = ""
) -> Dictionary:
	return {
		"severity": "error",
		"kind": String(kind),
		"path": path,
		"line": line_number,
		"target_path": target_path,
		"message": message,
	}


static func _append_issue(issues: Array[Dictionary], issue: Dictionary) -> void:
	if issue.is_empty() or issues.size() >= _MAX_ISSUES:
		return
	issues.append(issue)
