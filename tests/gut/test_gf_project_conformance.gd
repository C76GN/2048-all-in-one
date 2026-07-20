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
	"res://app/scripts/boot_runtime.gd",
]
const DIRECT_TIME_AND_RANDOM_ALLOWLIST: Array[String] = [
	"res://app/scripts/boot.gd",
	"res://app/scripts/boot_runtime.gd",
	"res://features/asset_library/tools/asset_review_browser.gd",
	"res://features/asset_library/tools/import_asset_sources.gd",
	"res://shared/scripts/utilities/game_clock_utility.gd",
]
const BOOT_RUNTIME_SCRIPT_PATH: String = "res://app/scripts/boot_runtime.gd"
const PLATFORM_CONTEXT_CONSUMER_PATHS: Array[String] = [
	"res://features/gameplay/scripts/controllers/gameplay_responsive_layout_controller.gd",
	"res://features/board_editor/scripts/ui/board_editor_responsive_layout_controller.gd",
]
const GF_MODULE_BASE_PATHS: Array[String] = [
	"res://addons/gf/kernel/base/gf_model.gd",
	"res://addons/gf/kernel/base/gf_system.gd",
	"res://addons/gf/kernel/base/gf_utility.gd",
	"res://addons/gf/standard/utilities/settings/gf_settings_utility.gd",
	"res://addons/gf/standard/utilities/ui/gf_ui_router_utility.gd",
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
const DECLARED_DEPENDENCY_CONTRACTS: Array[Dictionary] = [
	{
		"kind": "model",
		"lookup_method": "get_model",
		"hook_method": "get_required_models",
	},
	{
		"kind": "system",
		"lookup_method": "get_system",
		"hook_method": "get_required_systems",
	},
	{
		"kind": "utility",
		"lookup_method": "get_utility",
		"hook_method": "get_required_utilities",
	},
]
const ASSET_LIBRARY_TOOL_PATHS: Array[String] = [
	"res://tools/audit_asset_library.ps1",
	"res://tools/import_asset_sources.ps1",
]
const ASSET_LIBRARY_REPORT_ROOT: String = "features\\asset_library\\resources\\reports"
const LEGACY_ASSET_LIBRARY_REPORT_ROOT: String = "asset_library\\reports"
const SHARED_TEXT_RESOURCE_EXTENSIONS: Array[String] = [
	"cfg",
	"csv",
	"gd",
	"gdshader",
	"import",
	"json",
	"res",
	"tres",
	"tscn",
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


func test_direct_time_and_random_access_is_limited_to_adapters_and_tooling() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		if DIRECT_TIME_AND_RANDOM_ALLOWLIST.has(path):
			continue
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var code: String = _get_code_line(_get_packed_line(lines, line_index))
			if _contains_direct_time_or_random_access(code):
				_append_string(issues, "%s:%d 不应直接访问 Time 或原生随机源。" % [path, line_index + 1])

	assert_true(
		issues.is_empty(),
		"运行时系统时间应集中在 GameClockUtility，随机流应由 GFSeedUtility 管理；仅启动组合根和离线素材工具可直接访问底层 API：\n%s"
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


func test_boot_enables_strict_architecture_dependency_contracts() -> void:
	var source: String = _read_text(BOOT_RUNTIME_SCRIPT_PATH)

	assert_true(source.contains("Gf.create_architecture()"), "Boot 应显式配置 GF 根架构。")
	assert_true(source.contains("architecture.strict_dependency_lookup = true"), "根架构必须禁用隐式父级依赖回退。")
	assert_true(
		source.contains("architecture.fail_on_missing_declared_dependencies = true"),
		"根架构必须在生命周期开始前拒绝缺失的声明式依赖。"
	)
	assert_true(source.contains("architecture_ready: bool = await Gf.init()"), "Boot 必须检查 GF 严格初始化结果。")


func test_responsive_layouts_consume_gf_platform_capabilities() -> void:
	var issues: Array[String] = []
	for path: String in PLATFORM_CONTEXT_CONSUMER_PATHS:
		var source: String = _read_text(path)
		var probes_host_directly: bool = (
			source.contains("OS.has_feature")
			or source.contains("DisplayServer.is_touchscreen_available")
		)
		if probes_host_directly:
			_append_string(issues, "%s 不得自行探测宿主平台或触摸设备。" % path)
		if not source.contains("get_utility(GamePlatformUtility"):
			_append_string(issues, "%s 必须从架构获取 GamePlatformUtility。" % path)
		if not source.contains("GamePlatformUtility.CAPABILITY_TOUCH"):
			_append_string(issues, "%s 必须通过 GF 平台能力选择触屏布局。" % path)

	assert_true(
		issues.is_empty(),
		"响应式布局只消费 GFPlatformRuntime 投影，宿主探测必须集中在平台 Adapter：\n%s"
		% _join_lines(issues)
	)


func test_gf_modules_declare_static_cross_module_dependencies() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if not _is_gf_module_source(source):
			continue
		var functions: Dictionary = _parse_top_level_functions(source)
		var generic_declarations: String = _get_function_body(functions, "get_required_dependencies")
		for contract: Dictionary in DECLARED_DEPENDENCY_CONTRACTS:
			var kind: String = GFVariantData.get_option_string(contract, "kind")
			var lookup_method: String = GFVariantData.get_option_string(contract, "lookup_method")
			var hook_method: String = GFVariantData.get_option_string(contract, "hook_method")
			var declarations: String = "%s\n%s" % [
				generic_declarations,
				_get_function_body(functions, hook_method),
			]
			for dependency_symbol: String in _collect_static_dependency_symbols(source, lookup_method):
				var dependency_id: String = "%s:%s" % [kind, dependency_symbol]
				if _regex_matches(declarations, "\\b%s\\b" % dependency_symbol):
					continue
				_append_string(issues, "%s 未通过 %s() 声明 %s。" % [
					path,
					hook_method,
					dependency_id,
				])

	assert_true(
		issues.is_empty(),
		"项目 GF Module 的静态跨模块查找必须进入 GF 声明式依赖图；可选依赖必须使用本架构 local lookup：\n%s"
		% _join_lines(issues)
	)


func test_asset_library_tools_use_feature_cohesive_report_root() -> void:
	var issues: Array[String] = []
	for path: String in ASSET_LIBRARY_TOOL_PATHS:
		var source: String = _read_text(path)
		if source.is_empty():
			_append_string(issues, "%s 无法读取或为空。" % path)
			continue
		if not source.contains(ASSET_LIBRARY_REPORT_ROOT):
			_append_string(issues, "%s 未使用 Feature-Cohesive 素材报告目录。" % path)
		if source.contains('"%s' % LEGACY_ASSET_LIBRARY_REPORT_ROOT):
			_append_string(issues, "%s 仍引用迁移前的根级素材报告目录。" % path)

	assert_true(
		issues.is_empty(),
		"素材工具报告必须归属 asset_library Feature：\n%s" % _join_lines(issues)
	)


func test_shared_does_not_depend_on_features() -> void:
	var feature_class_owners: Dictionary = _collect_feature_class_owners()
	var scan_report: Dictionary = GFPathEnumerationTools.scan_files("res://shared", {
		"recursive": true,
		"include_hidden": false,
		"extensions": PackedStringArray(SHARED_TEXT_RESOURCE_EXTENSIONS),
		"max_file_count": 5000,
		"sort": true,
	})
	var issues: Array[String] = []
	if not GFVariantData.get_option_bool(scan_report, "ok"):
		_append_string(issues, "GFPathEnumerationTools 无法完成 shared 依赖扫描。")
	if GFVariantData.get_option_bool(scan_report, "truncated"):
		_append_string(issues, "shared 依赖扫描达到安全上限，结果不完整。")

	for path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var line: String = _get_packed_line(lines, line_index)
			var code: String = _get_code_line(line) if path.ends_with(".gd") else line
			if code.contains("res://features/"):
				_append_string(issues, "%s:%d shared 不得引用 Feature 资源路径。" % [
					path,
					line_index + 1,
				])
			if not path.ends_with(".gd"):
				continue
			for class_name_value: Variant in feature_class_owners.keys():
				var feature_class_name: String = GFVariantData.to_text(class_name_value)
				if not _regex_matches(code, "\\b%s\\b" % feature_class_name):
					continue
				_append_string(issues, "%s:%d shared 不得依赖 Feature 类型 %s（声明于 %s）。" % [
					path,
					line_index + 1,
					feature_class_name,
					GFVariantData.get_option_string(feature_class_owners, feature_class_name),
				])

	assert_true(
		issues.is_empty(),
		"Feature-Cohesive 依赖方向要求 shared 不得反向依赖 features：\n%s" % _join_lines(issues)
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


func _collect_feature_class_owners() -> Dictionary:
	var result: Dictionary = {}
	var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths("res://features", {
		"recursive": true,
		"include_addons": false,
		"include_hidden": false,
		"excluded_paths": SOURCE_EXCLUDED_ROOTS,
		"max_scan_depth": 64,
		"max_resource_paths": 5000,
	})
	for path: String in paths:
		if _is_excluded_path(path):
			continue
		var declared_class_name: String = _parse_class_name(_read_text(path))
		if not declared_class_name.is_empty():
			result[declared_class_name] = path
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


func _get_function_body(functions: Dictionary, function_name: String) -> String:
	if not functions.has(function_name):
		return ""
	var function_record: Dictionary = _get_dictionary(functions, function_name)
	return _join_lines(_get_string_array(function_record, "body_lines"))


func _collect_static_dependency_symbols(source: String, lookup_method: String) -> Array[String]:
	var result: Array[String] = []
	var regex: RegEx = _compile_regex(
		"\\b%s\\s*\\(\\s*([A-Za-z_][A-Za-z0-9_]*)" % lookup_method
	)
	if regex == null:
		return result
	for match_value: RegExMatch in regex.search_all(source):
		var symbol: String = match_value.get_string(1)
		if not symbol.is_empty() and not result.has(symbol):
			result.append(symbol)
	result.sort()
	return result


func _contains_global_gf_access(code: String) -> bool:
	return (
		_regex_matches(code, "(?:^|[^A-Za-z0-9_])Gf\\s*\\.")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])GFAutoload\\s*\\.")
	)


func _contains_direct_time_or_random_access(code: String) -> bool:
	return (
		_regex_matches(code, "(?:^|[^A-Za-z0-9_])Time\\s*\\.")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])RandomNumberGenerator\\b")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])(?:randf|randf_range|randfn|randi|randi_range|randomize|seed)\\s*\\(")
		or _regex_matches(code, "\\.(?:pick_random|shuffle)\\s*\\(")
	)


func _is_gf_module_source(source: String) -> bool:
	for base_path: String in GF_MODULE_BASE_PATHS:
		if source.contains("extends \"%s\"" % base_path):
			return true
	return _regex_matches(source, "(?m)^extends\\s+GF(?:Model|System|Utility)\\s*$")


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
