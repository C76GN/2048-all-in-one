@tool

## GFEditorContributionRegistry: GF 编辑器贡献清单读取器。
##
## 只读取 data-only JSON manifest 和模板文本，不加载贡献来源脚本。
## 根插件用它在标准库部分安装或残留时保持可恢复启动。
## [br]
## @api framework_internal
## [br]
## @category internal_helper
## [br]
## @since unreleased
## [br]
## @layer kernel/editor
class_name GFEditorContributionRegistry
extends RefCounted


# --- 常量 ---

## 支持的编辑器贡献清单 schema 版本。
## [br]
## @api framework_internal
## [br]
## @layer kernel/editor
const SCHEMA_VERSION: int = 1

const _GF_PATH_TOOLS = preload("res://addons/gf/kernel/core/gf_path_tools.gd")
const _GF_VARIANT_ACCESS_SCRIPT = preload("res://addons/gf/kernel/core/gf_variant_access.gd")
const _MANIFEST_ALLOWED_KEYS: Array[String] = [
	"schema_version",
	"package_id",
	"inspector_plugin_records",
	"export_plugin_records",
	"debugger_plugin_records",
	"dock_records",
	"template_records",
	"project_setting_records",
]
const _SCRIPT_RECORD_ALLOWED_KEYS: Array[String] = [
	"source_id",
	"path",
	"label",
]
const _DOCK_RECORD_ALLOWED_KEYS: Array[String] = [
	"source_id",
	"path",
	"label",
	"short_label",
	"order",
]
const _TEMPLATE_RECORD_ALLOWED_KEYS: Array[String] = [
	"source_id",
	"type",
	"label",
	"section",
	"base_class",
	"template_path",
]
const _PROJECT_SETTING_RECORD_ALLOWED_KEYS: Array[String] = [
	"source_id",
	"name",
	"default_value",
	"type",
	"type_name",
	"hint",
	"hint_string",
	"basic",
	"restart_if_changed",
	"internal",
	"update_initial_value",
	"usage",
]


# --- 框架内部方法 ---

## 创建空编辑器贡献记录集合。
## [br]
## @api framework_internal
## [br]
## @layer kernel/editor
## [br]
## @return 空记录集合。
## [br]
## @schema return: Dictionary，包含 inspector_plugin_records、export_plugin_records、debugger_plugin_records、dock_records、template_records 和 project_setting_records 数组。
static func empty_records() -> Dictionary:
	return {
		"inspector_plugin_records": [],
		"export_plugin_records": [],
		"debugger_plugin_records": [],
		"dock_records": [],
		"template_records": [],
		"project_setting_records": [],
	}


## 读取编辑器贡献清单并返回可直接交给插件 helper 的记录集合。
## [br]
## @api framework_internal
## [br]
## @layer kernel/editor
## [br]
## @param manifest_path: JSON manifest 路径。
## [br]
## @return 规范化后的记录集合。
## [br]
## @schema return: Dictionary，结构同 empty_records()；模板记录会把 template_path 解析为 template 文本。
static func load_manifest_records(manifest_path: String) -> Dictionary:
	var report: Dictionary = load_manifest_report(manifest_path)
	return _GF_VARIANT_ACCESS_SCRIPT.get_option_dictionary(report, "records", empty_records())


## 读取编辑器贡献清单并返回包含跳过记录的诊断报告。
## [br]
## @api framework_internal
## [br]
## @layer kernel/editor
## [br]
## @param manifest_path: JSON manifest 路径。
## [br]
## @return manifest 读取报告。
## [br]
## @schema return: Dictionary，包含 ok、source_path、records、issues、skipped_records、issue_count 和 skipped_record_count。
static func load_manifest_report(manifest_path: String) -> Dictionary:
	var normalized_path: String = _GF_PATH_TOOLS.normalize_resource_path(manifest_path)
	var records: Dictionary = empty_records()
	var issues: Array[Dictionary] = []
	var skipped_records: Array[Dictionary] = []
	if normalized_path.is_empty() or not FileAccess.file_exists(normalized_path):
		return _make_report(true, normalized_path, records, issues, skipped_records)

	var data: Dictionary = _read_json_object(normalized_path, issues)
	if not issues.is_empty():
		return _make_report(false, normalized_path, records, issues, skipped_records)

	var schema_version: int = _GF_VARIANT_ACCESS_SCRIPT.get_option_int(data, "schema_version", -1)
	if schema_version != SCHEMA_VERSION:
		issues.append(_make_issue(
			"unsupported_schema_version",
			normalized_path,
			"Editor contribution manifest schema_version is unsupported.",
			"schema_version",
			str(schema_version)
		))
		return _make_report(false, normalized_path, records, issues, skipped_records)

	if not _manifest_uses_allowed_keys(data, normalized_path, issues):
		return _make_report(false, normalized_path, records, issues, skipped_records)

	var package_id: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(data, "package_id").strip_edges()
	if package_id.is_empty():
		issues.append(_make_issue(
			"missing_package_id",
			normalized_path,
			"Editor contribution manifest package_id is required.",
			"package_id"
		))
		return _make_report(false, normalized_path, records, issues, skipped_records)

	records["inspector_plugin_records"] = _collect_script_records(
		data,
		"inspector_plugin_records",
		package_id,
		_SCRIPT_RECORD_ALLOWED_KEYS,
		issues,
		skipped_records
	)
	records["export_plugin_records"] = _collect_script_records(
		data,
		"export_plugin_records",
		package_id,
		_SCRIPT_RECORD_ALLOWED_KEYS,
		issues,
		skipped_records
	)
	records["debugger_plugin_records"] = _collect_script_records(
		data,
		"debugger_plugin_records",
		package_id,
		_SCRIPT_RECORD_ALLOWED_KEYS,
		issues,
		skipped_records
	)
	records["dock_records"] = _collect_script_records(
		data,
		"dock_records",
		package_id,
		_DOCK_RECORD_ALLOWED_KEYS,
		issues,
		skipped_records
	)
	records["template_records"] = _collect_template_records(
		data,
		"template_records",
		package_id,
		issues,
		skipped_records
	)
	records["project_setting_records"] = _collect_project_setting_records(
		data,
		"project_setting_records",
		package_id,
		issues
	)
	return _make_report(issues.is_empty(), normalized_path, records, issues, skipped_records)


# --- 私有/辅助方法 ---

static func _read_json_object(path: String, issues: Array[Dictionary]) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		issues.append(_make_issue(
			"open_failed",
			path,
			"Editor contribution manifest could not be opened.",
			"",
			error_string(FileAccess.get_open_error())
		))
		return {}

	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		issues.append(_make_issue(
			"read_failed",
			path,
			"Editor contribution manifest could not be read.",
			"",
			error_string(read_error)
		))
		return {}

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		issues.append(_make_issue(
			"parse_failed",
			path,
			"Editor contribution manifest is not valid JSON.",
			"",
			"line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		))
		return {}

	var parsed: Variant = parser.data
	if parsed is Dictionary:
		var data: Dictionary = parsed
		return data

	issues.append(_make_issue(
		"invalid_root_type",
		path,
		"Editor contribution manifest root must be an object."
	))
	return {}


static func _collect_script_records(
	data: Dictionary,
	record_key: String,
	package_id: String,
	allowed_keys: Array[String],
	issues: Array[Dictionary],
	skipped_records: Array[Dictionary]
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for raw_record: Dictionary in _get_record_dictionaries(data, record_key, issues):
		if not _record_uses_allowed_keys(raw_record, record_key, allowed_keys, issues):
			continue

		var source_id: String = _make_source_id(package_id, raw_record, record_key, issues)
		if source_id.is_empty():
			continue
		var script_path: String = _GF_PATH_TOOLS.normalize_resource_path(
			_GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "path")
		)
		if script_path.is_empty():
			issues.append(_make_issue("missing_path", record_key, "Contribution record path is required.", "path", "", source_id))
			continue
		var label: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "label").strip_edges()
		if label.is_empty():
			issues.append(_make_issue("missing_label", record_key, "Contribution record label is required.", "label", "", source_id))
			continue
		var short_label: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "short_label").strip_edges()
		if record_key == "dock_records" and short_label.is_empty():
			issues.append(_make_issue("missing_short_label", record_key, "Dock record short_label is required.", "short_label", "", source_id))
			continue
		if record_key == "dock_records" and not raw_record.has("order"):
			issues.append(_make_issue("missing_order", record_key, "Dock record order is required.", "order", "", source_id))
			continue
		if not ResourceLoader.exists(script_path, "Script"):
			skipped_records.append(_make_issue(
				"missing_script",
				record_key,
				"Contribution script is missing and the record was skipped.",
				"path",
				script_path,
				source_id
			))
			continue

		var record: Dictionary = _copy_allowed_record(raw_record, allowed_keys)
		record["package_id"] = package_id
		record["source_id"] = source_id
		record["path"] = script_path
		record["label"] = label
		if record_key == "dock_records":
			record["short_label"] = short_label
			record["order"] = _GF_VARIANT_ACCESS_SCRIPT.get_option_int(raw_record, "order", 0)
		records.append(record)
	return records


static func _collect_template_records(
	data: Dictionary,
	record_key: String,
	package_id: String,
	issues: Array[Dictionary],
	skipped_records: Array[Dictionary]
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for raw_record: Dictionary in _get_record_dictionaries(data, record_key, issues):
		if not _record_uses_allowed_keys(raw_record, record_key, _TEMPLATE_RECORD_ALLOWED_KEYS, issues):
			continue

		var source_id: String = _make_source_id(package_id, raw_record, record_key, issues)
		if source_id.is_empty():
			continue
		var template_type: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "type").strip_edges()
		var label: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "label").strip_edges()
		var base_class: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "base_class").strip_edges()
		if template_type.is_empty():
			issues.append(_make_issue("missing_template_type", record_key, "Template record type is required.", "type", "", source_id))
			continue
		if label.is_empty():
			issues.append(_make_issue("missing_label", record_key, "Template record label is required.", "label", "", source_id))
			continue
		if base_class.is_empty():
			issues.append(_make_issue("missing_base_class", record_key, "Template record base_class is required.", "base_class", "", source_id))
			continue
		var template_path: String = _GF_PATH_TOOLS.normalize_resource_path(
			_GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "template_path")
		)
		if template_path.is_empty():
			issues.append(_make_issue("missing_template_path", record_key, "Template record template_path is required.", "template_path", "", source_id))
			continue
		if not FileAccess.file_exists(template_path):
			skipped_records.append(_make_issue(
				"missing_template",
				record_key,
				"Template source file is missing and the record was skipped.",
				"template_path",
				template_path,
				source_id
			))
			continue

		var template_text: String = _read_template_text(template_path, record_key, issues, source_id)
		if template_text.is_empty():
			continue

		var record: Dictionary = _copy_allowed_record(raw_record, _TEMPLATE_RECORD_ALLOWED_KEYS)
		record["package_id"] = package_id
		record["source_id"] = source_id
		record["type"] = template_type
		record["label"] = label
		record["base_class"] = base_class
		record["template_path"] = template_path
		record["template"] = template_text
		records.append(record)
	return records


static func _collect_project_setting_records(
	data: Dictionary,
	record_key: String,
	package_id: String,
	issues: Array[Dictionary]
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for raw_record: Dictionary in _get_record_dictionaries(data, record_key, issues):
		if not _record_uses_allowed_keys(raw_record, record_key, _PROJECT_SETTING_RECORD_ALLOWED_KEYS, issues):
			continue

		var source_id: String = _make_source_id(package_id, raw_record, record_key, issues)
		if source_id.is_empty():
			continue
		var setting_name: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(raw_record, "name").strip_edges()
		if setting_name.is_empty():
			issues.append(_make_issue("missing_setting_name", record_key, "ProjectSettings record name is required.", "name", "", source_id))
			continue

		var default_value: Variant = _GF_VARIANT_ACCESS_SCRIPT.get_option_value(raw_record, "default_value")
		var issue_count_before: int = issues.size()
		var variant_type: int = _record_variant_type(raw_record, default_value, record_key, source_id, issues)
		if issues.size() != issue_count_before:
			continue
		var record: Dictionary = _copy_allowed_record(raw_record, _PROJECT_SETTING_RECORD_ALLOWED_KEYS)
		var _type_name_erased: bool = record.erase("type_name")
		record["package_id"] = package_id
		record["source_id"] = source_id
		record["name"] = setting_name
		record["type"] = variant_type
		records.append(record)
	return records


static func _get_record_dictionaries(
	data: Dictionary,
	record_key: String,
	issues: Array[Dictionary]
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var value: Variant = _GF_VARIANT_ACCESS_SCRIPT.get_option_value(data, record_key, [])
	if not (value is Array):
		issues.append(_make_issue("invalid_record_list", record_key, "Contribution record list must be an array.", record_key))
		return records

	var raw_records: Array = value
	for index: int in raw_records.size():
		var raw_record: Variant = raw_records[index]
		if raw_record is Dictionary:
			var record: Dictionary = raw_record
			records.append(record)
			continue
		issues.append(_make_issue(
			"invalid_record_type",
			record_key,
			"Contribution record must be an object.",
			record_key,
			str(index)
		))
	return records


static func _read_template_text(
	template_path: String,
	record_key: String,
	issues: Array[Dictionary],
	source_id: String
) -> String:
	var file: FileAccess = FileAccess.open(template_path, FileAccess.READ)
	if file == null:
		issues.append(_make_issue(
			"template_open_failed",
			record_key,
			"Template source file could not be opened.",
			"template_path",
			error_string(FileAccess.get_open_error()),
			source_id
		))
		return ""

	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		issues.append(_make_issue(
			"template_read_failed",
			record_key,
			"Template source file could not be read.",
			"template_path",
			error_string(read_error),
			source_id
		))
		return ""
	return text


static func _record_uses_allowed_keys(
	record: Dictionary,
	record_key: String,
	allowed_keys: Array[String],
	issues: Array[Dictionary]
) -> bool:
	for key_value: Variant in record.keys():
		var key: String = _GF_VARIANT_ACCESS_SCRIPT.to_text(key_value)
		if not allowed_keys.has(key):
			issues.append(_make_issue(
				"unknown_record_field",
				record_key,
				"Contribution record field is not part of the stable schema.",
				key
			))
			return false
	return true


static func _manifest_uses_allowed_keys(
	data: Dictionary,
	manifest_path: String,
	issues: Array[Dictionary]
) -> bool:
	for key_value: Variant in data.keys():
		var key: String = _GF_VARIANT_ACCESS_SCRIPT.to_text(key_value)
		if not _MANIFEST_ALLOWED_KEYS.has(key):
			issues.append(_make_issue(
				"unknown_manifest_field",
				manifest_path,
				"Editor contribution manifest field is not part of the stable schema.",
				key
			))
			return false
	return true


static func _copy_allowed_record(record: Dictionary, allowed_keys: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for key: String in allowed_keys:
		if record.has(key):
			result[key] = record[key]
	return result


static func _make_source_id(
	package_id: String,
	record: Dictionary,
	record_key: String,
	issues: Array[Dictionary]
) -> String:
	var source_id: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(record, "source_id").strip_edges()
	if source_id.is_empty():
		issues.append(_make_issue("missing_source_id", record_key, "Contribution record source_id is required.", "source_id"))
		return ""
	if source_id.contains(":"):
		return source_id
	return "%s:%s" % [package_id, source_id]


static func _record_variant_type(
	record: Dictionary,
	default_value: Variant,
	record_key: String,
	source_id: String,
	issues: Array[Dictionary]
) -> int:
	var type_name: String = _GF_VARIANT_ACCESS_SCRIPT.get_option_string(record, "type_name").strip_edges().to_lower()
	if type_name.is_empty():
		if not record.has("type"):
			issues.append(_make_issue("missing_setting_type", record_key, "ProjectSettings record type_name or type is required.", "type_name", "", source_id))
			return typeof(default_value)
		return _GF_VARIANT_ACCESS_SCRIPT.get_option_int(record, "type", typeof(default_value))

	match type_name:
		"nil":
			return TYPE_NIL
		"bool":
			return TYPE_BOOL
		"int":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"string":
			return TYPE_STRING
		"array":
			return TYPE_ARRAY
		"dictionary":
			return TYPE_DICTIONARY
		_:
			issues.append(_make_issue("unknown_type_name", record_key, "ProjectSettings record type_name is unknown.", "type_name", type_name, source_id))
			return typeof(default_value)


static func _make_report(
	ok: bool,
	source_path: String,
	records: Dictionary,
	issues: Array[Dictionary],
	skipped_records: Array[Dictionary]
) -> Dictionary:
	return {
		"ok": ok,
		"source_path": source_path,
		"records": records.duplicate(true),
		"issues": issues.duplicate(true),
		"skipped_records": skipped_records.duplicate(true),
		"issue_count": issues.size(),
		"skipped_record_count": skipped_records.size(),
	}


static func _make_issue(
	kind: String,
	path: String,
	message: String,
	field: String = "",
	actual_value: String = "",
	source_id: String = ""
) -> Dictionary:
	var issue: Dictionary = {
		"kind": kind,
		"path": path,
		"message": message,
	}
	if not field.is_empty():
		issue["field"] = field
	if not actual_value.is_empty():
		issue["actual_value"] = actual_value
	if not source_id.is_empty():
		issue["source_id"] = source_id
	return issue
