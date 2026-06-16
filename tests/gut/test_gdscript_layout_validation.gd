## 验证项目 GDScript 文件的 section 布局约束。
extends GutTest


# --- 常量 ---

const SOURCE_ROOTS: Array[String] = [
	"res://scripts",
	"res://tests/gut",
]
const NAMING_SOURCE_ROOTS: Array[String] = [
	"res://scripts",
	"res://scenes",
	"res://resources",
	"res://tests/gut",
]
const CLASS_NAME_REQUIRED_ROOTS: Array[String] = [
	"res://scripts",
]
const PROJECT_NAMING_EXTENSIONS: Array[String] = [
	".gd",
	".tscn",
	".tres",
]
const CLASS_NAME_OVERRIDES: Dictionary = {
	"game_ui_controller": "GameUIController",
	"hud": "HUD",
}
const GF_LAYER_SUFFIX_RULES: Array[Dictionary] = [
	{ "root": "res://scripts/actions", "suffix": "Action" },
	{ "root": "res://scripts/commands", "suffix": "Command" },
	{ "root": "res://scripts/controllers", "suffix": "Controller" },
	{ "root": "res://scripts/models", "suffix": "Model" },
	{ "root": "res://scripts/queries", "suffix": "Query" },
	{ "root": "res://scripts/rules", "suffix": "Rule" },
	{ "root": "res://scripts/states", "suffix": "State" },
	{ "root": "res://scripts/systems", "suffix": "System" },
	{ "root": "res://scripts/utilities", "suffix": "Utility" },
]
const SECTION_PREFIX: String = "# --- "
const SECTION_SUFFIX: String = " ---"
const TRIPLE_QUOTE: String = "\"\"\""
const PRIVATE_SECTION_MARKERS: Array[String] = [
	"私有",
	"内部",
	"辅助",
	"private",
	"internal",
	"helper",
]
const LIFECYCLE_SECTION_MARKERS: Array[String] = [
	"生命周期",
	"回调",
	"callback",
	"callbacks",
	"lifecycle",
]
const SIGNAL_CALLBACK_SECTION_MARKERS: Array[String] = [
	"信号处理",
	"信号回调",
	"signal handler",
	"signal callback",
]
const VARIABLE_SECTION_MARKERS: Array[String] = [
	"变量",
	"variable",
]
const VIRTUAL_SECTION_MARKERS: Array[String] = [
	"虚方法",
	"可重写",
	"重写钩子",
	"hook",
	"hooks",
	"protected",
	"virtual",
]
const GODOT_CALLBACK_NAMES: Dictionary = {
	"_can_handle": true,
	"_draw": true,
	"_enter_tree": true,
	"_exit_tree": true,
	"_get": true,
	"_get_property_list": true,
	"_gui_input": true,
	"_init": true,
	"_input": true,
	"_notification": true,
	"_parse_begin": true,
	"_parse_category": true,
	"_parse_end": true,
	"_parse_group": true,
	"_parse_property": true,
	"_physics_process": true,
	"_process": true,
	"_property_can_revert": true,
	"_property_get_revert": true,
	"_ready": true,
	"_set": true,
	"_shortcut_input": true,
	"_to_string": true,
	"_unhandled_input": true,
	"_unhandled_key_input": true,
	"_update_property": true,
	"_validate_property": true,
}
const SECTION_ORDER_RULES: Array[Dictionary] = [
	{ "markers": ["信号处理", "信号回调", "signal handler", "signal callback"], "rank": 115 },
	{ "markers": ["信号"], "rank": 10 },
	{ "markers": ["枚举"], "rank": 20 },
	{ "markers": ["常量"], "rank": 30 },
	{ "markers": ["导出变量"], "rank": 40 },
	{ "markers": ["公共变量"], "rank": 50 },
	{ "markers": ["私有变量", "私有静态变量"], "rank": 60 },
	{ "markers": ["@onready"], "rank": 70 },
	{ "markers": ["生命周期", "回调", "lifecycle", "callback"], "rank": 80 },
	{ "markers": ["公共方法", "获取方法", "注册方法", "事件系统", "命令", "查询"], "rank": 90 },
	{ "markers": ["虚方法", "可重写", "hook", "virtual"], "rank": 100 },
	{ "markers": ["私有", "内部", "辅助", "private", "internal", "helper"], "rank": 110 },
	{ "markers": ["内部类", "subclass"], "rank": 120 },
]


# --- 测试用例 ---

func test_underscore_methods_use_matching_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_underscore_method_section_issues(path))

	assert_eq(issues, [], "下划线方法应放在匹配语义的 section 中：\n%s" % _join_lines(issues))


func test_top_level_private_variables_use_private_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_private_variable_section_issues(path))

	assert_eq(issues, [], "私有变量应放在私有变量 section 中：\n%s" % _join_lines(issues))


func test_public_methods_do_not_use_private_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_public_method_in_private_section_issues(path))

	assert_eq(issues, [], "普通公共方法不应放在私有/辅助 section 中：\n%s" % _join_lines(issues))


func test_private_helper_sections_do_not_return_to_public_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_regression_issues(path))

	assert_eq(issues, [], "私有/辅助方法 section 后不应再回到普通公共 section：\n%s" % _join_lines(issues))


func test_class_name_files_document_class_before_class_name() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_class_doc_order_issues(path))

	assert_eq(issues, [], "class_name 文件应先写文件级说明再声明 class_name：\n%s" % _join_lines(issues))


func test_top_level_inner_classes_use_inner_class_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_inner_class_section_issues(path))

	assert_eq(issues, [], "顶层内部类应放在内部类 section 中：\n%s" % _join_lines(issues))


func test_top_level_sections_follow_documented_order() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_order_issues(path))

	assert_eq(issues, [], "顶层 section 应遵循 CODING_STYLE.md 的布局顺序：\n%s" % _join_lines(issues))


func test_top_level_section_names_use_chinese_labels() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_language_issues(path))

	assert_eq(issues, [], "顶层 section 名称应使用中文语义标签：\n%s" % _join_lines(issues))


func test_project_paths_use_snake_case() -> void:
	var issues: Array[String] = []
	for source_root: String in NAMING_SOURCE_ROOTS:
		issues.append_array(_collect_path_naming_issues(source_root))

	assert_eq(issues, [], "项目脚本、场景、资源和测试路径应使用 snake_case：\n%s" % _join_lines(issues))


func test_project_scripts_declare_gf_style_class_names() -> void:
	var issues: Array[String] = []
	for source_root: String in CLASS_NAME_REQUIRED_ROOTS:
		for path: String in _collect_gdscript_files(source_root):
			issues.append_array(_collect_script_class_name_issues(path))

	assert_eq(issues, [], "项目脚本 class_name 应由文件名派生并保持 gf 示例命名风格：\n%s" % _join_lines(issues))


func test_gf_layer_script_names_express_architecture_layer() -> void:
	var issues: Array[String] = []
	for rule: Dictionary in GF_LAYER_SUFFIX_RULES:
		var root_path: String = GFVariantData.to_text(rule["root"])
		var expected_suffix: String = GFVariantData.to_text(rule["suffix"])
		for path: String in _collect_gdscript_files(root_path):
			issues.append_array(_collect_gf_layer_suffix_issues(path, expected_suffix))

	assert_eq(issues, [], "gf 架构层脚本类名应体现所属层级：\n%s" % _join_lines(issues))


# --- 私有/辅助方法 ---

func _collect_project_gdscript_files() -> Array[String]:
	var result: Array[String] = []
	for source_root: String in SOURCE_ROOTS:
		result.append_array(_collect_gdscript_files(source_root))
	result.sort()
	return result


func _collect_gdscript_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	_collect_gdscript_files_recursive(root_path, result)
	return result


func _collect_gdscript_files_recursive(root_path: String, result: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		return

	var list_error: Error = dir.list_dir_begin()
	if list_error != OK:
		return
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var child_path: String = root_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_gdscript_files_recursive(child_path, result)
		elif entry.ends_with(".gd"):
			_append_string(result, child_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_underscore_method_section_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	var current_section: String = ""
	var inside_multiline_string: bool = false
	for line_index: int in range(lines.size()):
		var raw_line: String = _trim_cr(lines[line_index])
		var triple_quote_count: int = _count_substring(raw_line, TRIPLE_QUOTE)
		if inside_multiline_string:
			if triple_quote_count % 2 == 1:
				inside_multiline_string = false
			continue
		if triple_quote_count % 2 == 1:
			inside_multiline_string = true
			continue

		var section_name: String = _parse_section_name(raw_line)
		if not section_name.is_empty():
			current_section = section_name
			continue

		var function_name: String = _parse_top_level_function_name(raw_line)
		if function_name.is_empty() or not function_name.begins_with("_"):
			continue
		if _underscore_method_section_is_valid(function_name, current_section):
			continue

		_append_string(issues, "%s:%d %s 位于不匹配的 section：%s" % [
			path,
			line_index + 1,
			function_name,
			_get_section_label(current_section),
		])
	return issues


func _collect_private_variable_section_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	_scan_top_level_source(path, func(line: String, line_number: int, section_name: String) -> void:
		if _line_starts_private_variable(line) and not _section_is_private_variable_section(section_name):
			_append_string(issues, "%s:%d 私有变量位于不匹配的 section：%s" % [
				path,
				line_number,
				_get_section_label(section_name),
			])
	)
	return issues


func _collect_public_method_in_private_section_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	_scan_top_level_source(path, func(line: String, line_number: int, section_name: String) -> void:
		var function_name: String = _parse_top_level_function_name(line)
		if function_name.is_empty() or function_name.begins_with("_"):
			return
		if _section_is_private_helper_section(section_name):
			_append_string(issues, "%s:%d %s 位于私有/辅助 section：%s" % [
				path,
				line_number,
				function_name,
				_get_section_label(section_name),
			])
	)
	return issues


func _collect_section_regression_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	var state: Dictionary = {
		"private_helper_section_seen": false,
	}
	_scan_top_level_source(path, func(line: String, line_number: int, _section_name: String) -> void:
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			return

		if GFVariantData.to_bool(state["private_helper_section_seen"]) and not _section_is_allowed_after_private_helper_section(parsed_section):
			_append_string(issues, "%s:%d section 不应出现在私有/辅助方法 section 之后：%s" % [
				path,
				line_number,
				_get_section_label(parsed_section),
			])
		if _section_is_private_helper_section(parsed_section):
			state["private_helper_section_seen"] = true
	)
	return issues


func _collect_class_doc_order_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var first_doc_line: int = -1
	var class_name_line: int = -1
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(lines[line_index]).strip_edges()
		if first_doc_line == -1 and line.begins_with("##"):
			first_doc_line = line_index + 1
		if line.begins_with("class_name "):
			class_name_line = line_index + 1
			break

	if class_name_line == -1:
		return []
	if first_doc_line != -1 and first_doc_line < class_name_line:
		return []
	return ["%s:%d class_name 出现在文件级说明之前" % [path, class_name_line]]


func _collect_inner_class_section_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	_scan_top_level_source(path, func(line: String, line_number: int, section_name: String) -> void:
		var inner_class_name: String = _parse_top_level_inner_class_name(line)
		if inner_class_name.is_empty():
			return
		if _section_is_inner_class_section(section_name):
			return
		_append_string(issues, "%s:%d %s 位于非内部类 section：%s" % [
			path,
			line_number,
			inner_class_name,
			_get_section_label(section_name),
		])
	)
	return issues


func _collect_section_order_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	var state: Dictionary = {
		"last_rank": -1,
		"last_section": "",
	}
	_scan_top_level_source(path, func(line: String, line_number: int, _section_name: String) -> void:
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			return

		var rank: int = _get_section_order_rank(parsed_section)
		if rank == -1:
			return

		var last_rank: int = GFVariantData.to_int(state["last_rank"], -1)
		if last_rank != -1 and rank < last_rank:
			_append_string(issues, "%s:%d section 顺序倒退：%s 出现在 %s 之后" % [
				path,
				line_number,
				_get_section_label(parsed_section),
				_get_section_label(GFVariantData.to_text(state["last_section"])),
			])
		state["last_rank"] = rank
		state["last_section"] = parsed_section
	)
	return issues


func _collect_section_language_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	_scan_top_level_source(path, func(line: String, line_number: int, _section_name: String) -> void:
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			return

		if not _contains_cjk_text(parsed_section):
			_append_string(issues, "%s:%d section 名称缺少中文语义：%s" % [
				path,
				line_number,
				_get_section_label(parsed_section),
			])
	)
	return issues


func _collect_path_naming_issues(root_path: String) -> Array[String]:
	var issues: Array[String] = []
	_collect_path_naming_issues_recursive(root_path, issues)
	return issues


func _collect_path_naming_issues_recursive(root_path: String, issues: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		_append_string(issues, "%s: 无法打开目录" % root_path)
		return

	var list_error: Error = dir.list_dir_begin()
	if list_error != OK:
		_append_string(issues, "%s: 无法读取目录，错误码 %d" % [root_path, list_error])
		return
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var child_path: String = root_path.path_join(entry)
		if dir.current_is_dir():
			if not _is_snake_case_name(entry):
				_append_string(issues, "%s 目录名应使用 snake_case" % child_path)
			_collect_path_naming_issues_recursive(child_path, issues)
		elif _should_validate_project_file_name(entry):
			var basename: String = entry.get_basename()
			if not _is_snake_case_name(basename):
				_append_string(issues, "%s 文件名应使用 snake_case" % child_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_script_class_name_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var declared_class_name: String = _parse_declared_class_name(file.get_as_text())
	file.close()
	if declared_class_name.is_empty():
		return ["%s 缺少 class_name" % path]

	var expected_class_name: String = _get_expected_class_name(path)
	if declared_class_name != expected_class_name:
		return ["%s class_name 应为 %s，实际为 %s" % [
			path,
			expected_class_name,
			declared_class_name,
		]]
	return []


func _collect_gf_layer_suffix_issues(path: String, expected_suffix: String) -> Array[String]:
	var declared_class_name: String = _read_declared_class_name(path)
	if declared_class_name.is_empty():
		return ["%s 缺少 class_name" % path]
	if declared_class_name.ends_with(expected_suffix):
		return []
	return ["%s class_name 应以 %s 结尾，实际为 %s" % [
		path,
		expected_suffix,
		declared_class_name,
	]]


func _read_declared_class_name(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var declared_class_name: String = _parse_declared_class_name(file.get_as_text())
	file.close()
	return declared_class_name


func _scan_top_level_source(path: String, callback: Callable) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		callback.call("无法打开文件", 0, "")
		return

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var current_section: String = ""
	var inside_multiline_string: bool = false
	for line_index: int in range(lines.size()):
		var raw_line: String = _trim_cr(lines[line_index])
		var triple_quote_count: int = _count_substring(raw_line, TRIPLE_QUOTE)
		if inside_multiline_string:
			if triple_quote_count % 2 == 1:
				inside_multiline_string = false
			continue
		if triple_quote_count % 2 == 1:
			inside_multiline_string = true
			continue

		var section_name: String = _parse_section_name(raw_line)
		if not section_name.is_empty():
			current_section = section_name
		callback.call(raw_line, line_index + 1, current_section)


func _parse_section_name(line: String) -> String:
	if line.begins_with("\t") or line.begins_with(" "):
		return ""

	var trimmed: String = line.strip_edges()
	if not trimmed.begins_with(SECTION_PREFIX):
		return ""
	if not trimmed.ends_with(SECTION_SUFFIX):
		return ""
	var start_index: int = SECTION_PREFIX.length()
	var content_length: int = trimmed.length() - SECTION_PREFIX.length() - SECTION_SUFFIX.length()
	if content_length <= 0:
		return ""
	return trimmed.substr(start_index, content_length).strip_edges()


func _parse_top_level_function_name(line: String) -> String:
	var signature: String = ""
	if line.begins_with("func "):
		signature = line.substr("func ".length())
	elif line.begins_with("static func "):
		signature = line.substr("static func ".length())
	else:
		return ""

	var open_index: int = signature.find("(")
	if open_index == -1:
		return ""
	return signature.substr(0, open_index).strip_edges()


func _parse_top_level_inner_class_name(line: String) -> String:
	if not line.begins_with("class "):
		return ""
	var signature: String = line.substr("class ".length()).strip_edges()
	if signature.is_empty():
		return ""

	var end_index: int = signature.find(" ")
	var colon_index: int = signature.find(":")
	if end_index == -1 or (colon_index != -1 and colon_index < end_index):
		end_index = colon_index
	if end_index == -1:
		return signature
	return signature.substr(0, end_index).strip_edges()


func _parse_declared_class_name(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	for raw_line: String in lines:
		var line: String = _trim_cr(raw_line).strip_edges()
		if not line.begins_with("class_name "):
			continue

		var declaration: String = line.substr("class_name ".length()).strip_edges()
		var space_index: int = declaration.find(" ")
		if space_index != -1:
			declaration = declaration.substr(0, space_index)
		return declaration
	return ""


func _line_starts_private_variable(line: String) -> bool:
	if line.begins_with("var _"):
		return true
	return line.begins_with("@export") and line.contains(" var _")


func _should_validate_project_file_name(file_name: String) -> bool:
	for extension: String in PROJECT_NAMING_EXTENSIONS:
		if file_name.ends_with(extension):
			return true
	return false


func _is_snake_case_name(value: String) -> bool:
	if value.is_empty() or value.begins_with("_") or value.ends_with("_"):
		return false
	if value.contains("__"):
		return false

	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code >= 97 and code <= 122:
			continue
		if code >= 48 and code <= 57:
			continue
		if code == 95:
			continue
		return false
	return true


func _get_expected_class_name(path: String) -> String:
	var basename: String = path.get_file().get_basename()
	if CLASS_NAME_OVERRIDES.has(basename):
		return GFVariantData.to_text(CLASS_NAME_OVERRIDES[basename])
	return basename.to_pascal_case()


func _underscore_method_section_is_valid(function_name: String, section_name: String) -> bool:
	if _section_has_marker(section_name, PRIVATE_SECTION_MARKERS):
		return true
	if GODOT_CALLBACK_NAMES.has(function_name):
		return _section_has_marker(section_name, LIFECYCLE_SECTION_MARKERS)
	if function_name.begins_with("_on_"):
		return (
			_section_has_marker(section_name, SIGNAL_CALLBACK_SECTION_MARKERS)
			or _section_has_marker(section_name, VIRTUAL_SECTION_MARKERS)
		)
	return _section_has_marker(section_name, VIRTUAL_SECTION_MARKERS)


func _section_is_private_variable_section(section_name: String) -> bool:
	return (
		_section_has_marker(section_name, PRIVATE_SECTION_MARKERS)
		and _section_has_marker(section_name, VARIABLE_SECTION_MARKERS)
	)


func _section_is_private_helper_section(section_name: String) -> bool:
	return (
		_section_has_marker(section_name, PRIVATE_SECTION_MARKERS)
		and not _section_has_marker(section_name, VARIABLE_SECTION_MARKERS)
	)


func _section_is_allowed_after_private_helper_section(section_name: String) -> bool:
	return (
		_section_is_private_helper_section(section_name)
		or _section_has_marker(section_name, SIGNAL_CALLBACK_SECTION_MARKERS)
		or _section_has_marker(section_name, VIRTUAL_SECTION_MARKERS)
		or _section_is_inner_class_section(section_name)
	)


func _section_is_inner_class_section(section_name: String) -> bool:
	var lower_section: String = section_name.to_lower()
	return (
		lower_section.contains("subclass")
		or section_name.contains("内部类")
		or (section_name.contains("内部") and section_name.contains("类"))
	)


func _get_section_order_rank(section_name: String) -> int:
	for rule: Dictionary in SECTION_ORDER_RULES:
		var markers: Array = GFVariantData.to_array(rule["markers"])
		for marker: String in markers:
			if section_name.to_lower().contains(marker.to_lower()):
				return GFVariantData.to_int(rule["rank"], -1)
	return -1


func _section_has_marker(section_name: String, markers: Array[String]) -> bool:
	var lower_section: String = section_name.to_lower()
	for marker: String in markers:
		if lower_section.contains(marker.to_lower()):
			return true
	return false


func _contains_cjk_text(text: String) -> bool:
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false


func _count_substring(text: String, needle: String) -> int:
	if needle.is_empty():
		return 0

	var count: int = 0
	var search_from: int = 0
	while search_from < text.length():
		var found_index: int = text.find(needle, search_from)
		if found_index == -1:
			break
		count += 1
		search_from = found_index + needle.length()
	return count


func _trim_cr(text: String) -> String:
	if text.ends_with("\r"):
		return text.substr(0, text.length() - 1)
	return text


func _get_section_label(section_name: String) -> String:
	if section_name.is_empty():
		return "<none>"
	return section_name


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)
