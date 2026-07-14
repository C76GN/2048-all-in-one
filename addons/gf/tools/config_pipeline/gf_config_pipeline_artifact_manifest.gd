## GFConfigPipelineArtifactManifest: 配置导表产物 manifest 辅助。
##
## 为 GFConfigPipelineProfile 生成输入摘要、输出摘要和 freshness 报告，支持 CI、
## 编辑器按钮或命令行在导表前判断是否可以跳过未变化的产物。
## 该工具只记录通用文件摘要和导表选项，不表达项目业务版本、热更新策略或远端发布流程。
## [br]
## @api public
## [br]
## @category tool_api
## [br]
## @since unreleased
class_name GFConfigPipelineArtifactManifest
extends RefCounted


# --- 常量 ---

## manifest JSON 格式标识。
## [br]
## @api public
## [br]
## @since unreleased
const FORMAT: String = "gf.config_pipeline.artifact_manifest"

## manifest 格式版本。
## [br]
## @api public
## [br]
## @since unreleased
const FORMAT_VERSION: int = 1

const _DEFAULT_JSON_INDENT: String = "\t"
const _MAX_JSON_SAFE_DEPTH: int = 32
const _GENERATED_ARTIFACT_REPORT_SCRIPT = preload("res://addons/gf/kernel/editor/gf_generated_artifact_report.gd")


# --- 公共方法 ---

## 根据 Profile 和本次选项生成 manifest 字典。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param profile_path: Profile 资源路径。
## [br]
## @param profile: 导表 Profile 资源。
## [br]
## @param options: 本次导表选项。
## [br]
## @schema options: Dictionary，可包含 output_path、access_output_path、access_class_name、access_provider_accessor、build_options、save_options、access_options 和 manifest_metadata。
## [br]
## @param run_result: 可选 Runner 或 Pipeline 结果；只会提取 JSON 兼容摘要。
## [br]
## @schema run_result: Dictionary，可包含 success、operation、profile_id、output_path、save_result、access_result、report 和 error。
## [br]
## @return: manifest 字典。
## [br]
## @schema return: Dictionary，包含 format、format_version、profile_path、profile_id、profile_digest、input_digest、output_digest、options_digest、source_entries、output_entries、metadata 和 run_summary。
func make_manifest(
	profile_path: String,
	profile: GFConfigPipelineProfile,
	options: Dictionary = {},
	run_result: Dictionary = {}
) -> Dictionary:
	if profile == null:
		return _make_empty_manifest(profile_path, options, run_result)

	var source_entries: Array[Dictionary] = _make_source_entries(profile)
	var output_entries: Array[Dictionary] = _make_output_entries(profile, options)
	var profile_summary: Dictionary = profile.describe()
	var tracked_options: Dictionary = _make_tracked_options(profile, options)
	var manifest: Dictionary = {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"profile_path": profile_path,
		"profile_id": String(profile.profile_id),
		"profile_digest": _sha256_variant(profile_summary),
		"input_digest": _sha256_variant(source_entries),
		"output_digest": _sha256_variant(output_entries),
		"options_digest": _sha256_variant(tracked_options),
		"source_entries": source_entries,
		"output_entries": output_entries,
		"metadata": GFVariantData.get_option_dictionary(options, "manifest_metadata").duplicate(true),
		"run_summary": _make_run_summary(run_result),
	}
	manifest["manifest_digest"] = _sha256_variant(_make_digest_projection(manifest))
	return manifest


## 读取 manifest JSON 文件。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param manifest_path: manifest JSON 路径。
## [br]
## @return: 读取报告。
## [br]
## @schema return: Dictionary，包含 success、path、manifest、error_code 和 error。
func load_manifest(manifest_path: String) -> Dictionary:
	if manifest_path.strip_edges().is_empty():
		return _make_load_result(false, manifest_path, {}, ERR_INVALID_PARAMETER, "manifest 路径为空。")
	if not FileAccess.file_exists(manifest_path):
		return _make_load_result(false, manifest_path, {}, ERR_FILE_NOT_FOUND, "manifest 文件不存在：%s。" % manifest_path)

	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		return _make_load_result(false, manifest_path, {}, open_error, "无法读取 manifest：%s。" % manifest_path)

	var text: String = file.get_as_text()
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return _make_load_result(
			false,
			manifest_path,
			{},
			parse_error,
			"manifest JSON 解析失败：%s:%d。" % [parser.get_error_message(), parser.get_error_line()]
		)

	var parsed_value: Variant = parser.data
	if not (parsed_value is Dictionary):
		return _make_load_result(false, manifest_path, {}, ERR_INVALID_DATA, "manifest 根节点必须是 Dictionary。")

	var manifest: Dictionary = parsed_value
	if GFVariantData.get_option_string(manifest, "format") != FORMAT:
		return _make_load_result(false, manifest_path, manifest, ERR_INVALID_DATA, "manifest format 不匹配。")
	if GFVariantData.get_option_int(manifest, "format_version") != FORMAT_VERSION:
		return _make_load_result(false, manifest_path, manifest, ERR_INVALID_DATA, "manifest format_version 不支持。")
	return _make_load_result(true, manifest_path, manifest, OK, "")


## 保存 manifest JSON 文件。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param manifest_path: manifest JSON 输出路径。
## [br]
## @param manifest: make_manifest() 返回的字典。
## [br]
## @schema manifest: Dictionary，包含 format、format_version、profile_digest、input_digest、options_digest 和 output_entries。
## [br]
## @param options: 保存选项。
## [br]
## @schema options: Dictionary，可包含 dry_run、overwrite_existing、indent、sort_keys、allow_parent_output_path、allow_gf_source_output 和 allow_absolute_output_path。
## [br]
## @return: 保存报告。
## [br]
## @schema return: Dictionary，包含 success、path、status、error_code、error、artifact_report、written、changed 和 dry_run。
func save_manifest(manifest_path: String, manifest: Dictionary, options: Dictionary = {}) -> Dictionary:
	if manifest_path.strip_edges().is_empty():
		return _make_save_result(false, manifest_path, ERR_INVALID_PARAMETER, "manifest 路径为空。", {})

	var path_error: String = _validate_manifest_path_policy(manifest_path, options)
	if not path_error.is_empty():
		var failure_report: Dictionary = _GENERATED_ARTIFACT_REPORT_SCRIPT.make_report(
			manifest_path,
			_GENERATED_ARTIFACT_REPORT_SCRIPT.STATUS_FAILED,
			ERR_INVALID_PARAMETER,
			path_error,
			{
				"dry_run": GFVariantData.get_option_bool(options, "dry_run", false),
				"generator_id": "gf.tool.config_pipeline",
				"source_id": GFVariantData.get_option_string(manifest, "profile_path"),
			}
		)
		return _make_save_result(false, manifest_path, ERR_INVALID_PARAMETER, path_error, failure_report)

	var indent: String = GFVariantData.get_option_string(options, "indent", _DEFAULT_JSON_INDENT)
	var sort_keys: bool = GFVariantData.get_option_bool(options, "sort_keys", true)
	var text: String = JSON.stringify(_to_json_safe(manifest, 0), indent, sort_keys)
	var artifact_options: Dictionary = options.duplicate(true)
	artifact_options["label"] = "GFConfigPipelineArtifactManifest"
	artifact_options["generator_id"] = "gf.tool.config_pipeline"
	artifact_options["source_id"] = GFVariantData.get_option_string(manifest, "profile_path")
	var artifact_report: Dictionary = _GENERATED_ARTIFACT_REPORT_SCRIPT.save_text(manifest_path, text, artifact_options)
	var save_error: Error = _GENERATED_ARTIFACT_REPORT_SCRIPT.get_error_code(artifact_report)
	return _make_save_result(
		save_error == OK,
		manifest_path,
		save_error,
		GFVariantData.get_option_string(artifact_report, "error"),
		artifact_report
	)


## 生成当前 Profile 相对已有 manifest 的 freshness 报告。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param manifest_path: 已保存 manifest 路径。
## [br]
## @param profile_path: Profile 资源路径。
## [br]
## @param profile: 导表 Profile 资源。
## [br]
## @param options: 本次导表选项。
## [br]
## @schema options: Dictionary，可包含 output_path、access_output_path、access_class_name、access_provider_accessor、build_options、save_options 和 access_options。
## [br]
## @return: freshness 报告。
## [br]
## @schema return: Dictionary，包含 fresh、success、manifest_path、current_manifest、stored_manifest、load_result、reasons、missing_outputs 和 changed_fields。
func make_freshness_report(
	manifest_path: String,
	profile_path: String,
	profile: GFConfigPipelineProfile,
	options: Dictionary = {}
) -> Dictionary:
	var current_manifest: Dictionary = make_manifest(profile_path, profile, options)
	var load_result: Dictionary = load_manifest(manifest_path)
	if not GFVariantData.get_option_bool(load_result, "success"):
		return _make_freshness_result(false, manifest_path, current_manifest, {}, load_result, ["manifest_unavailable"], [], [])

	var stored_manifest: Dictionary = GFVariantData.get_option_dictionary(load_result, "manifest")
	var changed_fields: PackedStringArray = _compare_manifest_fields(stored_manifest, current_manifest)
	var missing_outputs: PackedStringArray = _find_missing_outputs(stored_manifest)
	var reasons: PackedStringArray = PackedStringArray()
	for field: String in changed_fields:
		var _append_changed_reason: bool = reasons.append("changed_%s" % field)
	for output_path: String in missing_outputs:
		var _append_missing_reason: bool = reasons.append("missing_output:%s" % output_path)

	return _make_freshness_result(
		changed_fields.is_empty() and missing_outputs.is_empty(),
		manifest_path,
		current_manifest,
		stored_manifest,
		load_result,
		_packed_to_array(reasons),
		_packed_to_array(missing_outputs),
		_packed_to_array(changed_fields)
	)


## 根据输出路径推导默认 manifest 路径。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param output_path: 数据库输出路径。
## [br]
## @return: 默认 manifest 路径；output_path 为空时返回空字符串。
func get_default_manifest_path(output_path: String) -> String:
	if output_path.strip_edges().is_empty():
		return ""
	return "%s.manifest.json" % output_path


# --- 私有/辅助方法 ---

func _make_empty_manifest(profile_path: String, options: Dictionary, run_result: Dictionary) -> Dictionary:
	var manifest: Dictionary = {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"profile_path": profile_path,
		"profile_id": "",
		"profile_digest": "",
		"input_digest": "",
		"output_digest": "",
		"options_digest": _sha256_variant(_make_semantic_options(options)),
		"source_entries": [],
		"output_entries": [],
		"metadata": GFVariantData.get_option_dictionary(options, "manifest_metadata").duplicate(true),
		"run_summary": _make_run_summary(run_result),
	}
	manifest["manifest_digest"] = _sha256_variant(_make_digest_projection(manifest))
	return manifest


func _make_source_entries(profile: GFConfigPipelineProfile) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for source: GFConfigPipelineTableSource in profile.sources:
		if source == null:
			entries.append({
				"valid": false,
				"exists": false,
				"error": "source_null",
			})
			continue

		var file_report: Dictionary = _make_file_digest_report(source.source_path)
		entries.append({
			"valid": true,
			"table_name": String(source.get_table_key()),
			"source_path": source.source_path,
			"source_format": String(source.get_resolved_format()),
			"exists": GFVariantData.get_option_bool(file_report, "exists"),
			"size_bytes": GFVariantData.get_option_int(file_report, "size_bytes"),
			"sha256": GFVariantData.get_option_string(file_report, "sha256"),
			"error": GFVariantData.get_option_string(file_report, "error"),
		})
	return entries


func _make_output_entries(profile: GFConfigPipelineProfile, options: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var output_path: String = profile.resolve_output_path(options)
	if not output_path.is_empty():
		entries.append(_make_output_entry("database", output_path))

	var access_output_path: String = profile.resolve_access_output_path(options)
	if not access_output_path.is_empty():
		entries.append(_make_output_entry("access", access_output_path))
	return entries


func _make_output_entry(kind: String, output_path: String) -> Dictionary:
	var file_report: Dictionary = _make_file_digest_report(output_path)
	return {
		"kind": kind,
		"path": output_path,
		"exists": GFVariantData.get_option_bool(file_report, "exists"),
		"size_bytes": GFVariantData.get_option_int(file_report, "size_bytes"),
		"sha256": GFVariantData.get_option_string(file_report, "sha256"),
	}


func _make_tracked_options(profile: GFConfigPipelineProfile, options: Dictionary) -> Dictionary:
	var semantic_options: Dictionary = _make_semantic_options(options)
	return {
		"output_path": profile.resolve_output_path(semantic_options),
		"access_output_path": profile.resolve_access_output_path(semantic_options),
		"access_class_name": profile.resolve_access_class_name(semantic_options),
		"access_provider_accessor": profile.resolve_access_provider_accessor(semantic_options),
		"build_options": profile.make_build_options(semantic_options),
		"save_options": profile.make_save_options(semantic_options),
		"access_options": profile.make_access_options(semantic_options),
	}


func _make_semantic_options(options: Dictionary) -> Dictionary:
	var result: Dictionary = options.duplicate(true)
	var ignored_keys: PackedStringArray = PackedStringArray([
		"cache_mode",
		"changed_only",
		"dry_run",
		"json_report",
		"manifest_metadata",
		"manifest_options",
		"manifest_path",
		"pretty_output",
		"strict",
		"type_hint",
		"usage_requested",
		"write_manifest",
	])
	for key: String in ignored_keys:
		var _removed: bool = result.erase(key)
	return result


func _make_run_summary(run_result: Dictionary) -> Dictionary:
	if run_result.is_empty():
		return {}
	return {
		"success": GFVariantData.get_option_bool(run_result, "success"),
		"operation": String(GFVariantData.get_option_string_name(run_result, "operation")),
		"profile_id": String(GFVariantData.get_option_string_name(run_result, "profile_id")),
		"output_path": GFVariantData.get_option_string(run_result, "output_path"),
		"error": GFVariantData.get_option_string(run_result, "error"),
		"report": _make_report_summary(GFVariantData.get_option_dictionary(run_result, "report")),
		"save_result": _make_artifact_result_summary(GFVariantData.get_option_dictionary(run_result, "save_result")),
		"access_result": _make_artifact_result_summary(GFVariantData.get_option_dictionary(run_result, "access_result")),
	}


func _make_report_summary(report: Dictionary) -> Dictionary:
	if report.is_empty():
		return {}
	return {
		"ok": GFVariantData.get_option_bool(report, "ok"),
		"error_count": GFVariantData.get_option_int(report, "error_count"),
		"warning_count": GFVariantData.get_option_int(report, "warning_count"),
		"issue_count": GFVariantData.get_option_array(report, "issues").size(),
	}


func _make_artifact_result_summary(result: Dictionary) -> Dictionary:
	if result.is_empty():
		return {}
	var artifact_report: Dictionary = GFVariantData.get_option_dictionary(result, "artifact_report")
	return {
		"success": GFVariantData.get_option_bool(result, "success", true),
		"path": GFVariantData.get_option_string(result, "path"),
		"status": String(GFVariantData.get_option_string_name(result, "status")),
		"written": GFVariantData.get_option_bool(result, "written"),
		"changed": GFVariantData.get_option_bool(result, "changed"),
		"dry_run": GFVariantData.get_option_bool(result, "dry_run"),
		"artifact_status": String(GFVariantData.get_option_string_name(artifact_report, "status")),
	}


func _make_file_digest_report(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {
			"exists": false,
			"size_bytes": 0,
			"sha256": "",
			"error": "empty_path",
		}
	if not FileAccess.file_exists(path):
		return {
			"exists": false,
			"size_bytes": 0,
			"sha256": "",
			"error": "file_not_found",
		}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"exists": true,
			"size_bytes": 0,
			"sha256": "",
			"error": "file_open_failed",
		}

	var length: int = file.get_length()
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {
			"exists": true,
			"size_bytes": length,
			"sha256": "",
			"error": "file_read_failed",
		}
	return {
		"exists": true,
		"size_bytes": bytes.size(),
		"sha256": _sha256_bytes(bytes),
		"error": "",
	}


func _compare_manifest_fields(stored_manifest: Dictionary, current_manifest: Dictionary) -> PackedStringArray:
	var changed_fields: PackedStringArray = PackedStringArray()
	var fields: PackedStringArray = PackedStringArray([
		"profile_path",
		"profile_id",
		"profile_digest",
		"input_digest",
		"output_digest",
		"options_digest",
	])
	for field: String in fields:
		if GFVariantData.get_option_string(stored_manifest, field) != GFVariantData.get_option_string(current_manifest, field):
			var _append_field: bool = changed_fields.append(field)
	return changed_fields


func _find_missing_outputs(manifest: Dictionary) -> PackedStringArray:
	var missing_outputs: PackedStringArray = PackedStringArray()
	var output_entries: Array = GFVariantData.get_option_array(manifest, "output_entries")
	for entry_value: Variant in output_entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var path: String = GFVariantData.get_option_string(entry, "path")
		if path.is_empty():
			continue
		if not FileAccess.file_exists(path):
			var _append_missing: bool = missing_outputs.append(path)
	return missing_outputs


func _make_load_result(
	success: bool,
	manifest_path: String,
	manifest: Dictionary,
	error_code: Error,
	message: String
) -> Dictionary:
	return {
		"success": success,
		"path": manifest_path,
		"manifest": manifest.duplicate(true),
		"error_code": error_code,
		"error": message,
	}


func _make_save_result(
	success: bool,
	manifest_path: String,
	error_code: Error,
	message: String,
	artifact_report: Dictionary
) -> Dictionary:
	return {
		"success": success,
		"path": manifest_path,
		"error_code": error_code,
		"error": message,
		"artifact_report": artifact_report.duplicate(true),
		"status": GFVariantData.get_option_string_name(artifact_report, "status"),
		"written": GFVariantData.get_option_bool(artifact_report, "written"),
		"changed": GFVariantData.get_option_bool(artifact_report, "changed"),
		"dry_run": GFVariantData.get_option_bool(artifact_report, "dry_run"),
	}


func _make_freshness_result(
	fresh: bool,
	manifest_path: String,
	current_manifest: Dictionary,
	stored_manifest: Dictionary,
	load_result: Dictionary,
	reasons: Array,
	missing_outputs: Array,
	changed_fields: Array
) -> Dictionary:
	return {
		"success": fresh,
		"fresh": fresh,
		"manifest_path": manifest_path,
		"current_manifest": current_manifest.duplicate(true),
		"stored_manifest": stored_manifest.duplicate(true),
		"load_result": load_result.duplicate(true),
		"reasons": reasons.duplicate(true),
		"missing_outputs": missing_outputs.duplicate(true),
		"changed_fields": changed_fields.duplicate(true),
	}


func _make_digest_projection(manifest: Dictionary) -> Dictionary:
	return {
		"format": GFVariantData.get_option_string(manifest, "format"),
		"format_version": GFVariantData.get_option_int(manifest, "format_version"),
		"profile_path": GFVariantData.get_option_string(manifest, "profile_path"),
		"profile_id": GFVariantData.get_option_string(manifest, "profile_id"),
		"profile_digest": GFVariantData.get_option_string(manifest, "profile_digest"),
		"input_digest": GFVariantData.get_option_string(manifest, "input_digest"),
		"output_digest": GFVariantData.get_option_string(manifest, "output_digest"),
		"options_digest": GFVariantData.get_option_string(manifest, "options_digest"),
		"source_entries": GFVariantData.get_option_array(manifest, "source_entries"),
		"output_entries": GFVariantData.get_option_array(manifest, "output_entries"),
	}


func _sha256_variant(value: Variant) -> String:
	var text: String = JSON.stringify(_to_json_safe(value, 0), "", true)
	return _sha256_bytes(text.to_utf8_buffer())


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	var start_error: Error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error: Error = context.update(bytes)
	if update_error != OK:
		return ""
	return context.finish().hex_encode()


func _to_json_safe(value: Variant, depth: int) -> Variant:
	if depth > _MAX_JSON_SAFE_DEPTH:
		return {
			"__gf_json_error": "max_depth_exceeded",
			"max_depth": _MAX_JSON_SAFE_DEPTH,
		}
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL:
			var bool_value: bool = value
			return bool_value
		TYPE_INT:
			var int_value: int = value
			return int_value
		TYPE_FLOAT:
			var float_value: float = value
			if is_nan(float_value) or is_inf(float_value):
				return null
			return float_value
		TYPE_STRING:
			var string_value: String = value
			return string_value
		TYPE_STRING_NAME:
			var string_name_value: StringName = value
			return String(string_name_value)
		TYPE_NODE_PATH:
			var node_path_value: NodePath = value
			return String(node_path_value)
		TYPE_ARRAY:
			return _array_to_json_safe(value, depth + 1)
		TYPE_DICTIONARY:
			return _dictionary_to_json_safe(value, depth + 1)
		TYPE_PACKED_STRING_ARRAY:
			var string_array: PackedStringArray = value
			return _packed_string_array_to_array(string_array)
		TYPE_PACKED_BYTE_ARRAY:
			var byte_array: PackedByteArray = value
			return Array(byte_array)
		TYPE_PACKED_INT32_ARRAY:
			var int32_array: PackedInt32Array = value
			return Array(int32_array)
		TYPE_PACKED_INT64_ARRAY:
			var int64_array: PackedInt64Array = value
			return Array(int64_array)
		TYPE_PACKED_FLOAT32_ARRAY:
			var float32_array: PackedFloat32Array = value
			return _array_to_json_safe(Array(float32_array), depth + 1)
		TYPE_PACKED_FLOAT64_ARRAY:
			var float64_array: PackedFloat64Array = value
			return _array_to_json_safe(Array(float64_array), depth + 1)
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector2_array: PackedVector2Array = value
			return _array_to_json_safe(Array(vector2_array), depth + 1)
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector3_array: PackedVector3Array = value
			return _array_to_json_safe(Array(vector3_array), depth + 1)
		TYPE_PACKED_COLOR_ARRAY:
			var color_array: PackedColorArray = value
			return _array_to_json_safe(Array(color_array), depth + 1)
		TYPE_VECTOR2:
			var vector2_value: Vector2 = value
			return {
				"x": vector2_value.x,
				"y": vector2_value.y,
			}
		TYPE_VECTOR3:
			var vector3_value: Vector3 = value
			return {
				"x": vector3_value.x,
				"y": vector3_value.y,
				"z": vector3_value.z,
			}
		TYPE_COLOR:
			var color_value: Color = value
			return color_value.to_html(true)
		TYPE_OBJECT:
			if value is Resource:
				var resource: Resource = value
				return {
					"resource_path": resource.resource_path,
					"object_type": resource.get_class(),
				}
	return str(value)


func _array_to_json_safe(value: Variant, depth: int) -> Array:
	var source: Array = GFVariantData.as_array(value)
	var result: Array = []
	for item: Variant in source:
		result.append(_to_json_safe(item, depth + 1))
	return result


func _dictionary_to_json_safe(value: Variant, depth: int) -> Dictionary:
	var source: Dictionary = GFVariantData.as_dictionary(value)
	var result: Dictionary = {}
	for key: Variant in source.keys():
		result[_json_key_to_string(key)] = _to_json_safe(source[key], depth + 1)
	return result


func _json_key_to_string(key: Variant) -> String:
	match typeof(key):
		TYPE_STRING:
			var string_key: String = key
			return string_key
		TYPE_STRING_NAME:
			var string_name_key: StringName = key
			return "StringName:%s" % String(string_name_key)
		TYPE_INT:
			var int_key: int = key
			return "int:%d" % int_key
	return "type_%d:%s" % [typeof(key), str(key)]


func _validate_manifest_path_policy(manifest_path: String, options: Dictionary) -> String:
	var raw_path: String = manifest_path.replace("\\", "/").strip_edges()
	if raw_path.is_empty():
		return "manifest 路径为空。"
	if _has_unsupported_output_scheme(raw_path):
		return "manifest 路径使用了不支持的 URI scheme：%s。" % manifest_path
	if _path_has_parent_segment(raw_path) and not GFVariantData.get_option_bool(options, "allow_parent_output_path", false):
		return "manifest 路径不能包含父级越界片段：%s。" % manifest_path
	if _is_filesystem_absolute_path(raw_path) and not GFVariantData.get_option_bool(options, "allow_absolute_output_path", false):
		return "manifest 路径不能是绝对文件系统路径：%s。" % manifest_path
	var normalized_path: String = _normalize_output_path(raw_path)
	if _is_gf_source_output_path(normalized_path) and not GFVariantData.get_option_bool(options, "allow_gf_source_output", false):
		return "manifest 路径不能写入 GF 框架源码目录：%s。" % manifest_path
	return ""


func _normalize_output_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/").strip_edges()
	if normalized.contains("://"):
		var scheme: String = normalized.get_slice("://", 0).to_lower()
		var body: String = normalized.get_slice("://", 1).simplify_path()
		return "%s://%s" % [scheme, body]
	return normalized.simplify_path()


func _path_has_parent_segment(path: String) -> bool:
	var body: String = path
	if path.contains("://"):
		body = path.get_slice("://", 1)
	var parts: PackedStringArray = body.split("/", false)
	for part: String in parts:
		if part == "..":
			return true
	return false


func _is_filesystem_absolute_path(path: String) -> bool:
	var lower_path: String = path.to_lower()
	if lower_path.begins_with("res://") or lower_path.begins_with("user://"):
		return false
	if path.is_absolute_path():
		return true
	return path.length() >= 3 and path.substr(1, 2) == ":/"


func _has_unsupported_output_scheme(path: String) -> bool:
	var lower_path: String = path.to_lower()
	if not lower_path.contains("://"):
		return false
	return not (lower_path.begins_with("res://") or lower_path.begins_with("user://"))


func _is_gf_source_output_path(path: String) -> bool:
	var lower_path: String = path.to_lower()
	var gf_source_root: String = "res://addons".path_join("gf")
	return lower_path == gf_source_root or lower_path.begins_with(gf_source_root.path_join(""))


func _packed_string_array_to_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value: String in values:
		result.append(value)
	return result


func _packed_to_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value: String in values:
		result.append(value)
	return result
