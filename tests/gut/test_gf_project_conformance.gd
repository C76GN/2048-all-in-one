## 验证项目只通过受控入口使用 GF，并遵守 GF 模块生命周期契约。
extends GutTest


# --- 常量 ---

const PROJECT_SOURCE_ROOTS: Array[String] = [
	"res://app",
	"res://features",
	"res://shared",
]
const SOURCE_EXCLUDED_ROOTS: Array[String] = [
	"res://features/asset_library/resources/source_packs",
]
const GLOBAL_GF_ACCESS_ALLOWLIST: Array[String] = [
	"res://app/scripts/boot.gd",
]
const GF_MODULE_BASE_PATHS: Array[String] = [
	"res://addons/gf/kernel/base/gf_model.gd",
	"res://addons/gf/kernel/base/gf_system.gd",
	"res://addons/gf/kernel/base/gf_utility.gd",
]
const EARLY_LIFECYCLE_METHODS: Array[String] = [
	"init",
	"async_init",
]
const CROSS_MODULE_LOOKUP_METHODS: Array[String] = [
	"get_architecture",
	"get_architecture_or_null",
	"get_model",
	"get_system",
	"get_utility",
]


# --- 测试用例 ---

func test_global_gf_access_is_limited_to_composition_root() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		if GLOBAL_GF_ACCESS_ALLOWLIST.has(path):
			continue
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var code: String = _get_code_line(_get_packed_line(lines, line_index))
			if _contains_global_gf_access(code):
				_append_string(issues, "%s:%d 不应直接访问全局 Gf/GFAutoload。" % [path, line_index + 1])

	assert_true(
		issues.is_empty(),
		"全局 GF 架构访问只允许出现在应用启动组合根；其他节点和模块应使用 GF 注入或 Controller 上下文：\n%s"
		% _join_lines(issues)
	)


func test_project_does_not_call_deprecated_gf_methods() -> void:
	var deprecated_methods: Array[Dictionary] = _collect_deprecated_gf_methods()
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if source.is_empty():
			_append_string(issues, "%s 无法读取或为空。" % path)
			continue
		for method_record: Dictionary in deprecated_methods:
			issues.append_array(_collect_deprecated_call_issues(path, source, method_record))

	assert_true(
		issues.is_empty(),
		"项目不得调用当前 GF 源码标记为 @deprecated 的 API；升级 GF 后本测试会自动读取新声明：\n%s"
		% _join_lines(issues)
	)


func test_gf_modules_only_resolve_cross_module_dependencies_in_ready() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if not _is_gf_module_source(source):
			continue
		var functions: Dictionary = _parse_top_level_functions(source)
		for lifecycle_method: String in EARLY_LIFECYCLE_METHODS:
			if not functions.has(lifecycle_method):
				continue
			var dependency_chain: Array[String] = _find_cross_module_dependency_chain(
				functions,
				lifecycle_method,
				{},
				[]
			)
			if dependency_chain.is_empty():
				continue
			var function_record: Dictionary = _get_dictionary(functions, lifecycle_method)
			_append_string(issues, "%s:%d %s() 通过 %s 提前获取跨模块依赖。" % [
				path,
				GFVariantData.get_option_int(function_record, "line", 1),
				lifecycle_method,
				" -> ".join(dependency_chain),
			])

	assert_true(
		issues.is_empty(),
		"GF init()/async_init() 只能初始化模块自身；跨模块 Model/System/Utility 必须在 ready() 获取：\n%s"
		% _join_lines(issues)
	)


# --- 私有/辅助方法 ---

func _collect_project_script_paths() -> Array[String]:
	var result: Array[String] = []
	for root_path: String in PROJECT_SOURCE_ROOTS:
		var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths(root_path, {
			"recursive": true,
			"include_addons": false,
			"include_hidden": false,
			"excluded_paths": SOURCE_EXCLUDED_ROOTS,
			"max_scan_depth": 64,
			"max_resource_paths": 5000,
		})
		for path: String in paths:
			if not _is_excluded_path(path):
				result.append(path)
	result.sort()
	return result


func _collect_deprecated_gf_methods() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths("res://addons/gf", {
		"recursive": true,
		"include_addons": true,
		"include_hidden": false,
		"max_scan_depth": 64,
		"max_resource_paths": 10000,
	})
	for path: String in paths:
		var source: String = _read_text(path)
		if not source.contains("@deprecated"):
			continue
		var owner_class: String = _parse_class_name(source)
		if owner_class.is_empty():
			continue
		var pending_deprecation: String = ""
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var stripped: String = _get_packed_line(lines, line_index).strip_edges()
			if stripped.begins_with("## @deprecated"):
				pending_deprecation = stripped.trim_prefix("## ")
				continue
			if pending_deprecation.is_empty() or stripped.is_empty() or stripped.begins_with("##"):
				continue
			var method_name: String = _parse_function_name(stripped)
			if not method_name.is_empty():
				result.append({
					"owner_class": owner_class,
					"method_name": method_name,
					"framework_path": path,
					"framework_line": line_index + 1,
					"deprecation": pending_deprecation,
				})
			pending_deprecation = ""
	return result


func _collect_deprecated_call_issues(
	path: String,
	source: String,
	method_record: Dictionary
) -> Array[String]:
	var issues: Array[String] = []
	var owner_class: String = GFVariantData.get_option_string(method_record, "owner_class")
	var method_name: String = GFVariantData.get_option_string(method_record, "method_name")
	if owner_class.is_empty() or method_name.is_empty():
		return issues

	var typed_receivers: Array[String] = _collect_typed_identifiers(source, owner_class)
	var owner_returning_functions: Array[String] = _collect_owner_returning_functions(source, owner_class)
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var code: String = _get_code_line(_get_packed_line(lines, line_index))
		if code.is_empty():
			continue
		if not _line_calls_deprecated_method(
			code,
			owner_class,
			method_name,
			typed_receivers,
			owner_returning_functions
		):
			continue
		_append_string(issues, "%s:%d 调用了 %s.%s()；%s" % [
			path,
			line_index + 1,
			owner_class,
			method_name,
			GFVariantData.get_option_string(method_record, "deprecation"),
		])
	return issues


func _collect_typed_identifiers(source: String, owner_class: String) -> Array[String]:
	var result: Array[String] = []
	var type_regex: RegEx = _compile_regex(
		"\\b([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*%s\\b" % owner_class
	)
	if type_regex == null:
		return result
	for match_value: RegExMatch in type_regex.search_all(source):
		var identifier: String = match_value.get_string(1)
		if not identifier.is_empty() and not result.has(identifier):
			result.append(identifier)
	return result


func _collect_owner_returning_functions(source: String, owner_class: String) -> Array[String]:
	var result: Array[String] = []
	var return_regex: RegEx = _compile_regex(
		"(?m)^(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)[^\\n]*->\\s*%s\\b" % owner_class
	)
	if return_regex == null:
		return result
	for match_value: RegExMatch in return_regex.search_all(source):
		var function_name: String = match_value.get_string(1)
		if not function_name.is_empty() and not result.has(function_name):
			result.append(function_name)
	return result


func _line_calls_deprecated_method(
	code: String,
	owner_class: String,
	method_name: String,
	typed_receivers: Array[String],
	owner_returning_functions: Array[String]
) -> bool:
	for receiver: String in typed_receivers:
		if _regex_matches(code, "\\b%s\\s*\\.\\s*%s\\s*\\(" % [receiver, method_name]):
			return true

	for function_name: String in owner_returning_functions:
		if _regex_matches(
			code,
			"\\b%s\\s*\\([^)]*\\)\\s*\\.\\s*%s\\s*\\(" % [function_name, method_name]
		):
			return true

	if _regex_matches(code, "\\b%s\\s*\\.\\s*%s\\s*\\(" % [owner_class, method_name]):
		return true
	return _regex_matches(
		code,
		"\\bget_utility\\s*\\(\\s*%s\\s*\\)\\s*\\.\\s*%s\\s*\\(" % [owner_class, method_name]
	)


func _parse_top_level_functions(source: String) -> Dictionary:
	var result: Dictionary = {}
	var current_function: String = ""
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).trim_suffix("\r")
		var stripped: String = line.strip_edges()
		if line.begins_with("func "):
			current_function = _parse_function_name(stripped)
			if not current_function.is_empty():
				result[current_function] = {
					"line": line_index + 1,
					"body_lines": [],
				}
			continue

		if current_function.is_empty():
			continue
		if not stripped.is_empty() and not line.begins_with("\t") and not line.begins_with(" "):
			current_function = ""
			continue

		var record: Dictionary = _get_dictionary(result, current_function)
		var body_lines: Array[String] = _get_string_array(record, "body_lines")
		body_lines.append(line)
		record["body_lines"] = body_lines
		result[current_function] = record
	return result


func _find_cross_module_dependency_chain(
	functions: Dictionary,
	function_name: String,
	visited: Dictionary,
	chain_prefix: Array[String]
) -> Array[String]:
	if visited.has(function_name) or not functions.has(function_name):
		return []
	visited[function_name] = true

	var chain: Array[String] = chain_prefix.duplicate()
	chain.append(function_name)
	var function_record: Dictionary = _get_dictionary(functions, function_name)
	var body_lines: Array[String] = _get_string_array(function_record, "body_lines")
	var body: String = _join_lines(body_lines)
	if _contains_cross_module_lookup(body):
		return chain

	for called_function: String in _collect_defined_function_calls(body, functions):
		var nested_chain: Array[String] = _find_cross_module_dependency_chain(
			functions,
			called_function,
			visited,
			chain
		)
		if not nested_chain.is_empty():
			return nested_chain
	return []


func _collect_defined_function_calls(body: String, functions: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var call_regex: RegEx = _compile_regex("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	if call_regex == null:
		return result
	for match_value: RegExMatch in call_regex.search_all(body):
		var function_name: String = match_value.get_string(1)
		if functions.has(function_name) and not result.has(function_name):
			result.append(function_name)
	return result


func _contains_cross_module_lookup(body: String) -> bool:
	for method_name: String in CROSS_MODULE_LOOKUP_METHODS:
		if _regex_matches(body, "\\b%s\\s*\\(" % method_name):
			return true
	return false


func _contains_global_gf_access(code: String) -> bool:
	return (
		_regex_matches(code, "(?:^|[^A-Za-z0-9_])Gf\\s*\\.")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])GFAutoload\\s*\\.")
	)


func _is_gf_module_source(source: String) -> bool:
	for base_path: String in GF_MODULE_BASE_PATHS:
		if source.contains("extends \"%s\"" % base_path):
			return true
	return false


func _parse_class_name(source: String) -> String:
	var class_regex: RegEx = _compile_regex(
		"(?m)^class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)[ \\t]*\\r?$"
	)
	if class_regex == null:
		return ""
	var match_value: RegExMatch = class_regex.search(source)
	return match_value.get_string(1) if match_value != null else ""


func _parse_function_name(stripped_line: String) -> String:
	var signature: String = stripped_line
	if signature.begins_with("static func "):
		signature = signature.trim_prefix("static ")
	if not signature.begins_with("func "):
		return ""
	var name_end: int = signature.find("(")
	if name_end < 0:
		return ""
	return signature.substr(5, name_end - 5).strip_edges()


func _get_code_line(line: String) -> String:
	var stripped: String = line.strip_edges()
	if stripped.is_empty() or stripped.begins_with("#"):
		return ""
	var comment_index: int = line.find("#")
	if comment_index >= 0:
		return line.left(comment_index)
	return line


func _is_excluded_path(path: String) -> bool:
	for excluded_root: String in SOURCE_EXCLUDED_ROOTS:
		if path == excluded_root or path.begins_with(excluded_root + "/"):
			return true
	return false


func _compile_regex(pattern: String) -> RegEx:
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile(pattern)
	if compile_error != OK:
		return null
	return regex


func _regex_matches(text: String, pattern: String) -> bool:
	var regex: RegEx = _compile_regex(pattern)
	return regex != null and regex.search(text) != null


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _get_dictionary(source: Dictionary, key: Variant) -> Dictionary:
	return GFVariantData.as_dictionary(GFVariantData.get_option_value(source, key))


func _get_string_array(source: Dictionary, key: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in GFVariantData.get_option_array(source, key):
		if value is String:
			result.append(value)
	return result


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var _append_result: bool = packed.append(line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)
