## GFConfigPipelineCommand: 配置导表工具的 Godot 命令参数适配器。
##
## 解析 Godot `--` 之后的用户参数，调用 GFConfigPipelineRunner，并返回适合 CI、
## 编辑器按钮或项目脚本消费的结构化报告。该类只封装 Godot 原生命令入口，不调用
## 外部进程，不绑定项目目录、表语义或发布策略。
## [br]
## @api public
## [br]
## @category tool_api
## [br]
## @since unreleased
class_name GFConfigPipelineCommand
extends RefCounted


# --- 常量 ---

const _OPERATION_BUILD: StringName = &"build"
const _OPERATION_EXPORT: StringName = &"export"
const _OPERATION_LOAD: StringName = &"load"
const _DEFAULT_OPERATION: StringName = _OPERATION_EXPORT
const _MAX_JSON_DEPTH: int = 64


# --- 公共方法 ---

## 执行一次导表命令。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param arguments: Godot `--` 之后的用户参数。
## [br]
## @param base_options: 调用方直接注入的默认选项，命令行参数会覆盖同名字段。
## [br]
## @schema base_options: Dictionary，可包含 GFConfigPipelineRunner 选项，以及 output_path、access_output_path、access_class_name、access_provider_accessor、dry_run、changed_only、manifest_path 和 write_manifest。
## [br]
## @return: 命令报告。
## [br]
## @schema return: Dictionary，包含 success、exit_code、operation、profile_path、options、runner_result、json_report、pretty_output、usage_requested、strict、dry_run、changed_only、manifest_path 和 error。
func run(arguments: PackedStringArray = PackedStringArray(), base_options: Dictionary = {}) -> Dictionary:
	var parse_result: Dictionary = _parse_arguments(arguments, base_options)
	if not GFVariantData.get_option_bool(parse_result, "success"):
		return _make_command_result(
			false,
			GFVariantData.get_option_int(parse_result, "exit_code", 2),
			GFVariantData.get_option_string_name(parse_result, "operation", _DEFAULT_OPERATION),
			GFVariantData.get_option_string(parse_result, "profile_path"),
			GFVariantData.get_option_dictionary(parse_result, "options"),
			{},
			GFVariantData.get_option_bool(parse_result, "json_report"),
			GFVariantData.get_option_bool(parse_result, "pretty_output", true),
			GFVariantData.get_option_bool(parse_result, "usage_requested"),
			GFVariantData.get_option_bool(parse_result, "strict"),
			GFVariantData.get_option_string(parse_result, "error")
		)

	if GFVariantData.get_option_bool(parse_result, "usage_requested"):
		return _make_command_result(
			true,
			0,
			GFVariantData.get_option_string_name(parse_result, "operation", _DEFAULT_OPERATION),
			GFVariantData.get_option_string(parse_result, "profile_path"),
			GFVariantData.get_option_dictionary(parse_result, "options"),
			{},
			GFVariantData.get_option_bool(parse_result, "json_report"),
			GFVariantData.get_option_bool(parse_result, "pretty_output", true),
			true,
			GFVariantData.get_option_bool(parse_result, "strict"),
			""
		)

	var operation: StringName = GFVariantData.get_option_string_name(parse_result, "operation", _DEFAULT_OPERATION)
	var profile_path: String = GFVariantData.get_option_string(parse_result, "profile_path")
	var options: Dictionary = GFVariantData.get_option_dictionary(parse_result, "options").duplicate(true)
	var runner: GFConfigPipelineRunner = GFConfigPipelineRunner.new()
	var runner_result: Dictionary = _run_operation(runner, operation, profile_path, options)
	var command_success: bool = GFVariantData.get_option_bool(runner_result, "success")
	var command_error: String = GFVariantData.get_option_string(runner_result, "error")
	if command_success and GFVariantData.get_option_bool(parse_result, "strict") and _runner_result_has_warnings(runner_result):
		command_success = false
		command_error = "严格模式下导表报告存在 warning。"

	return _make_command_result(
		command_success,
		0 if command_success else 1,
		operation,
		profile_path,
		options,
		runner_result,
		GFVariantData.get_option_bool(parse_result, "json_report"),
		GFVariantData.get_option_bool(parse_result, "pretty_output", true),
		false,
		GFVariantData.get_option_bool(parse_result, "strict"),
		command_error
	)


## 把命令报告格式化为可打印文本。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param result: run() 返回的命令报告。
## [br]
## @schema result: Dictionary，包含 success、exit_code、operation、profile_path、runner_result、json_report、pretty_output、usage_requested 和 error。
## [br]
## @param pretty: JSON 输出是否使用缩进。
## [br]
## @return: 可打印文本；json_report 为 true 时返回 JSON 字符串。
func make_output_text(result: Dictionary, pretty: bool = true) -> String:
	if GFVariantData.get_option_bool(result, "usage_requested"):
		return get_usage()
	if GFVariantData.get_option_bool(result, "json_report"):
		var indent: String = "\t" if pretty else ""
		var safe_result: Variant = _to_json_safe(result, 0)
		return JSON.stringify(safe_result, indent, true)
	return _make_summary_text(result)


## 返回 Godot 命令行用法说明。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @return: 用法说明文本。
func get_usage() -> String:
	var lines: PackedStringArray = PackedStringArray()
	_append_line(lines, "GF Config Pipeline Command")
	_append_line(lines, "")
	_append_line(lines, "Usage:")
	_append_line(lines, "  godot --headless --path <project> -s res://addons/gf/tools/config_pipeline/gf_config_pipeline_cli.gd -- --profile res://path/to/profile.tres [options]")
	_append_line(lines, "")
	_append_line(lines, "Options:")
	_append_line(lines, "  --profile <path>             GFConfigPipelineProfile resource path.")
	_append_line(lines, "  --operation <export|build|load>")
	_append_line(lines, "  --output <path>              Override profile output_path.")
	_append_line(lines, "  --access-output <path>       Override profile access_output_path.")
	_append_line(lines, "  --class-name <name>          Override generated access class_name.")
	_append_line(lines, "  --provider-accessor <expr>   Override generated access provider expression.")
	_append_line(lines, "  --dry-run                    Preflight without writing generated artifacts.")
	_append_line(lines, "  --changed-only               Skip export when the artifact manifest is fresh.")
	_append_line(lines, "  --manifest <path>            Override artifact manifest path.")
	_append_line(lines, "  --write-manifest             Write a manifest after export even without --changed-only.")
	_append_line(lines, "  --strict                     Treat validation warnings as command failure.")
	_append_line(lines, "  --json                       Print JSON report.")
	_append_line(lines, "  --compact                    Print compact JSON when --json is enabled.")
	_append_line(lines, "  --help                       Print this help.")
	return "\n".join(lines)


# --- 私有/辅助方法 ---

func _parse_arguments(arguments: PackedStringArray, base_options: Dictionary) -> Dictionary:
	var profile_path: String = ""
	var operation: StringName = _DEFAULT_OPERATION
	var options: Dictionary = base_options.duplicate(true)
	var json_report: bool = false
	var pretty_output: bool = true
	var strict: bool = false
	var usage_requested: bool = false
	var index: int = 0

	while index < arguments.size():
		var raw_token: String = arguments[index]
		var split_token: Dictionary = _split_option_token(raw_token)
		var option_name: String = GFVariantData.get_option_string(split_token, "name")
		var inline_value: String = GFVariantData.get_option_string(split_token, "value")
		var has_inline_value: bool = GFVariantData.get_option_bool(split_token, "has_value")

		if option_name == "--help" or option_name == "-h":
			usage_requested = true
			index += 1
			continue
		if option_name == "--json":
			json_report = true
			index += 1
			continue
		if option_name == "--pretty":
			pretty_output = true
			index += 1
			continue
		if option_name == "--compact":
			pretty_output = false
			index += 1
			continue
		if option_name == "--strict":
			strict = true
			index += 1
			continue
		if option_name == "--dry-run":
			options["dry_run"] = true
			index += 1
			continue
		if option_name == "--changed-only":
			options["changed_only"] = true
			index += 1
			continue
		if option_name == "--write-manifest":
			options["write_manifest"] = true
			index += 1
			continue

		var value_result: Dictionary = {}
		if option_name == "--profile" or option_name == "-p":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			profile_path = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--operation" or option_name == "-o":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			operation = StringName(GFVariantData.get_option_string(value_result, "value").to_lower())
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--output":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			options["output_path"] = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--access-output":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			options["access_output_path"] = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--class-name":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			options["access_class_name"] = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--provider-accessor":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			options["access_provider_accessor"] = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue
		if option_name == "--manifest":
			value_result = _read_option_value(arguments, index, option_name, inline_value, has_inline_value)
			if not GFVariantData.get_option_bool(value_result, "success"):
				return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, GFVariantData.get_option_string(value_result, "error"))
			options["manifest_path"] = GFVariantData.get_option_string(value_result, "value")
			index = GFVariantData.get_option_int(value_result, "next_index")
			continue

		return _make_parse_failure(
			operation,
			profile_path,
			options,
			json_report,
			pretty_output,
			usage_requested,
			strict,
			"未知导表命令参数：%s。" % raw_token
		)

	if not usage_requested and profile_path.is_empty():
		return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, "缺少 --profile 参数。")
	if not _is_supported_operation(operation):
		return _make_parse_failure(operation, profile_path, options, json_report, pretty_output, usage_requested, strict, "不支持的导表操作：%s。" % String(operation))

	return {
		"success": true,
		"exit_code": 0,
		"operation": operation,
		"profile_path": profile_path,
		"options": options,
		"json_report": json_report,
		"pretty_output": pretty_output,
		"usage_requested": usage_requested,
		"strict": strict,
		"error": "",
	}


func _split_option_token(raw_token: String) -> Dictionary:
	var equal_index: int = raw_token.find("=")
	if equal_index < 0:
		return {
			"name": raw_token,
			"value": "",
			"has_value": false,
		}
	return {
		"name": raw_token.substr(0, equal_index),
		"value": raw_token.substr(equal_index + 1),
		"has_value": true,
	}


func _read_option_value(
	arguments: PackedStringArray,
	index: int,
	option_name: String,
	inline_value: String,
	has_inline_value: bool
) -> Dictionary:
	if has_inline_value:
		return {
			"success": true,
			"value": inline_value,
			"next_index": index + 1,
			"error": "",
		}
	if index + 1 >= arguments.size():
		return {
			"success": false,
			"value": "",
			"next_index": index + 1,
			"error": "%s 缺少参数值。" % option_name,
		}
	return {
		"success": true,
		"value": arguments[index + 1],
		"next_index": index + 2,
		"error": "",
	}


func _run_operation(
	runner: GFConfigPipelineRunner,
	operation: StringName,
	profile_path: String,
	options: Dictionary
) -> Dictionary:
	if operation == _OPERATION_LOAD:
		return runner.load_profile(profile_path, options)
	if operation == _OPERATION_BUILD:
		return runner.build_profile_path(profile_path, options)
	return runner.export_profile_path(profile_path, options)


func _is_supported_operation(operation: StringName) -> bool:
	return (
		operation == _OPERATION_EXPORT
		or operation == _OPERATION_BUILD
		or operation == _OPERATION_LOAD
	)


func _runner_result_has_warnings(result: Dictionary) -> bool:
	var report: Dictionary = GFVariantData.get_option_dictionary(result, "report")
	if GFVariantData.get_option_int(report, "warning_count") > 0:
		return true
	var warnings: Array = GFVariantData.get_option_array(report, "warnings")
	return not warnings.is_empty()


func _make_parse_failure(
	operation: StringName,
	profile_path: String,
	options: Dictionary,
	json_report: bool,
	pretty_output: bool,
	usage_requested: bool,
	strict: bool,
	message: String
) -> Dictionary:
	return {
		"success": false,
		"exit_code": 2,
		"operation": operation,
		"profile_path": profile_path,
		"options": options,
		"json_report": json_report,
		"pretty_output": pretty_output,
		"usage_requested": usage_requested,
		"strict": strict,
		"error": message,
	}


func _make_command_result(
	success: bool,
	exit_code: int,
	operation: StringName,
	profile_path: String,
	options: Dictionary,
	runner_result: Dictionary,
	json_report: bool,
	pretty_output: bool,
	usage_requested: bool,
	strict: bool,
	message: String
) -> Dictionary:
	return {
		"success": success,
		"exit_code": exit_code,
		"operation": operation,
		"profile_path": profile_path,
		"options": options.duplicate(true),
		"runner_result": runner_result.duplicate(true),
		"json_report": json_report,
		"pretty_output": pretty_output,
		"usage_requested": usage_requested,
		"strict": strict,
		"dry_run": GFVariantData.get_option_bool(options, "dry_run"),
		"changed_only": GFVariantData.get_option_bool(options, "changed_only"),
		"manifest_path": GFVariantData.get_option_string(options, "manifest_path"),
		"error": message,
	}


func _make_summary_text(result: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var operation: String = String(GFVariantData.get_option_string_name(result, "operation"))
	var status_text: String = "ok" if GFVariantData.get_option_bool(result, "success") else "failed"
	_append_line(lines, "GF Config Pipeline: %s" % status_text)
	_append_line(lines, "operation: %s" % operation)
	_append_line(lines, "profile: %s" % GFVariantData.get_option_string(result, "profile_path"))
	_append_line(lines, "exit_code: %d" % GFVariantData.get_option_int(result, "exit_code"))
	var runner_result: Dictionary = GFVariantData.get_option_dictionary(result, "runner_result")
	if GFVariantData.get_option_bool(runner_result, "skipped"):
		_append_line(lines, "skipped: true")
	var manifest_path: String = GFVariantData.get_option_string(runner_result, "manifest_path")
	if not manifest_path.is_empty():
		_append_line(lines, "manifest: %s" % manifest_path)
	var error: String = GFVariantData.get_option_string(result, "error")
	if not error.is_empty():
		_append_line(lines, "error: %s" % error)
	return "\n".join(lines)


func _append_line(lines: PackedStringArray, text: String) -> void:
	var _append_result: bool = lines.append(text)


func _to_json_safe(value: Variant, depth: int) -> Variant:
	if depth > _MAX_JSON_DEPTH:
		return "<max_depth>"

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
		TYPE_PACKED_INT32_ARRAY:
			var int32_array: PackedInt32Array = value
			return _packed_int32_array_to_array(int32_array)
		TYPE_PACKED_INT64_ARRAY:
			var int64_array: PackedInt64Array = value
			return _packed_int64_array_to_array(int64_array)
		TYPE_PACKED_FLOAT32_ARRAY:
			var float32_array: PackedFloat32Array = value
			return _packed_float32_array_to_array(float32_array)
		TYPE_PACKED_FLOAT64_ARRAY:
			var float64_array: PackedFloat64Array = value
			return _packed_float64_array_to_array(float64_array)
		TYPE_OBJECT:
			return _object_to_json_safe(value)

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
			return String(string_name_key)
		TYPE_INT:
			var int_key: int = key
			return str(int_key)
	return str(key)


func _packed_string_array_to_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value: String in values:
		result.append(value)
	return result


func _packed_int32_array_to_array(values: PackedInt32Array) -> Array:
	var result: Array = []
	for value: int in values:
		result.append(value)
	return result


func _packed_int64_array_to_array(values: PackedInt64Array) -> Array:
	var result: Array = []
	for value: int in values:
		result.append(value)
	return result


func _packed_float32_array_to_array(values: PackedFloat32Array) -> Array:
	var result: Array = []
	for value: float in values:
		if is_nan(value) or is_inf(value):
			result.append(null)
		else:
			result.append(value)
	return result


func _packed_float64_array_to_array(values: PackedFloat64Array) -> Array:
	var result: Array = []
	for value: float in values:
		if is_nan(value) or is_inf(value):
			result.append(null)
		else:
			result.append(value)
	return result


func _object_to_json_safe(value: Variant) -> Dictionary:
	if value is Resource:
		var resource: Resource = value
		return {
			"object_type": resource.get_class(),
			"resource_path": resource.resource_path,
		}
	if value is Object:
		var object_value: Object = value
		return {
			"object_type": object_value.get_class(),
		}
	return {
		"object_type": "Object",
	}
