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

	assert_true(issues.is_empty(), "下划线方法应放在匹配语义的 section 中：\n%s" % _join_lines(issues))


func test_top_level_private_variables_use_private_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_private_variable_section_issues(path))

	assert_true(issues.is_empty(), "私有变量应放在私有变量 section 中：\n%s" % _join_lines(issues))


func test_public_methods_do_not_use_private_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_public_method_in_private_section_issues(path))

	assert_true(issues.is_empty(), "普通公共方法不应放在私有/辅助 section 中：\n%s" % _join_lines(issues))


func test_private_helper_sections_do_not_return_to_public_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_regression_issues(path))

	assert_true(issues.is_empty(), "私有/辅助方法 section 后不应再回到普通公共 section：\n%s" % _join_lines(issues))


func test_class_name_files_document_class_before_class_name() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_class_doc_order_issues(path))

	assert_true(issues.is_empty(), "class_name 文件应先写文件级说明再声明 class_name：\n%s" % _join_lines(issues))


func test_top_level_inner_classes_use_inner_class_sections() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_inner_class_section_issues(path))

	assert_true(issues.is_empty(), "顶层内部类应放在内部类 section 中：\n%s" % _join_lines(issues))


func test_top_level_sections_follow_documented_order() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_order_issues(path))

	assert_true(issues.is_empty(), "顶层 section 应遵循 CODING_STYLE.md 的布局顺序：\n%s" % _join_lines(issues))


func test_top_level_section_names_use_chinese_labels() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_section_language_issues(path))

	assert_true(issues.is_empty(), "顶层 section 名称应使用中文语义标签：\n%s" % _join_lines(issues))


func test_project_paths_use_snake_case() -> void:
	var issues: Array[String] = []
	for source_root: String in NAMING_SOURCE_ROOTS:
		issues.append_array(_collect_path_naming_issues(source_root))

	assert_true(issues.is_empty(), "项目脚本、场景、资源和测试路径应使用 snake_case：\n%s" % _join_lines(issues))


func test_project_scripts_declare_gf_style_class_names() -> void:
	var issues: Array[String] = []
	for source_root: String in CLASS_NAME_REQUIRED_ROOTS:
		for path: String in _collect_gdscript_files(source_root):
			issues.append_array(_collect_script_class_name_issues(path))

	assert_true(issues.is_empty(), "项目脚本 class_name 应由文件名派生并保持 gf 示例命名风格：\n%s" % _join_lines(issues))


func test_gf_layer_script_names_express_architecture_layer() -> void:
	var issues: Array[String] = []
	for rule: Dictionary in GF_LAYER_SUFFIX_RULES:
		var root_path: String = _get_dictionary_text(rule, "root")
		var expected_suffix: String = _get_dictionary_text(rule, "suffix")
		for path: String in _collect_gdscript_files(root_path):
			issues.append_array(_collect_gf_layer_suffix_issues(path, expected_suffix))

	assert_true(issues.is_empty(), "gf 架构层脚本类名应体现所属层级：\n%s" % _join_lines(issues))


func test_issue_collections_use_is_empty_assertions() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_empty_array_assert_eq_issues(path))

	assert_true(
		issues.is_empty(),
		"问题列表空集合断言应使用 is_empty()，避免 GUT assert_eq 的 Variant 参数警告：\n%s" % _join_lines(issues)
	)


func test_gut_tests_use_type_safe_equality_assertions() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://tests/gut"):
		issues.append_array(_collect_gut_assert_eq_issues(path))

	assert_true(
		issues.is_empty(),
		"GUT 测试应使用 assert_true(actual == expected, ...)，避免 Godot 4.6 assert_eq 的 Variant 参数警告：\n%s" % _join_lines(issues)
	)


func test_known_return_value_calls_are_captured() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_discarded_return_value_call_issues(path))

	assert_true(
		issues.is_empty(),
		"已知会返回状态或 Tweener 的调用应保存、判断或返回其结果，避免 Godot 4.6 RETURN_VALUE_DISCARDED：\n%s" % _join_lines(issues)
	)


func test_known_coroutine_calls_are_awaited() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_missing_await_call_issues(path))

	assert_true(
		issues.is_empty(),
		"已知协程调用应显式 await，避免 Godot 4.6 MISSING_AWAIT：\n%s" % _join_lines(issues)
	)


func test_bindable_property_get_value_results_are_narrowed() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_get_value_narrowing_issues(path))

	assert_true(
		issues.is_empty(),
		"GFBindableProperty.get_value() 的 Variant 结果应立即收窄或先保存为 Variant，避免 Godot 4.6 类型警告：\n%s" % _join_lines(issues)
	)


func test_project_scripts_narrow_dictionary_get_object_results() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_dictionary_get_object_assignment_issues(path))

	assert_true(
		issues.is_empty(),
		"Dictionary.get() 返回 Variant；赋给自定义对象类型前应先保存为 Variant 并用 is 收窄：\n%s" % _join_lines(issues)
	)


func test_stylebox_flat_api_uses_flat_styleboxes() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_stylebox_flat_api_issues(path))

	assert_true(
		issues.is_empty(),
		"StyleBoxFlat 专属属性和方法应只在 StyleBoxFlat 变量上调用，避免 Godot 4.6 unsafe property/method warning：\n%s" % _join_lines(issues)
	)


func test_typed_onready_node_lookups_use_helper_narrowing() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_typed_onready_node_lookup_issues(path))

	assert_true(
		issues.is_empty(),
		"typed @onready 节点引用应通过 helper 收窄，避免 get_parent/get_node/instantiate 直接赋值触发 Godot 4.6 unsafe warning：\n%s" % _join_lines(issues)
	)


func test_runtime_node_lookup_results_are_narrowed() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_runtime_node_lookup_assignment_issues(path))

	assert_true(
		issues.is_empty(),
		"运行时节点查找/实例化结果应先保存为 Node/Variant，再用 is 收窄到具体类型：\n%s" % _join_lines(issues)
	)


func test_resource_load_results_are_narrowed() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_resource_result_assignment_issues(path))

	assert_true(
		issues.is_empty(),
		"资源加载/复制结果应先保存为 Resource/Variant/Object，再用 is 收窄到具体资源类型：\n%s" % _join_lines(issues)
	)


func test_stable_project_interfaces_use_typed_calls() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_stable_project_interface_dynamic_call_issues(path))

	assert_true(
		issues.is_empty(),
		"稳定的项目 Interface 应使用强类型调用，不应退回 has_method/call 字符串探测：\n%s" % _join_lines(issues)
	)


func test_project_scripts_avoid_dynamic_method_dispatch() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_dynamic_method_dispatch_issues(path))

	assert_true(
		issues.is_empty(),
		"项目脚本应避免 has_method/call/callv 动态派发，减少 Godot 4.6 unsafe method warning：\n%s" % _join_lines(issues)
	)


func test_typed_gdscript_preloads_do_not_call_static_methods() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_typed_gdscript_preload_static_call_issues(path))

	assert_true(
		issues.is_empty(),
		"GDScript preload 常量不应作为静态方法宿主调用；请用 class_name 直接调用，避免 Godot 4.7 UNSAFE_METHOD_ACCESS：\n%s" % _join_lines(issues)
	)


func test_project_scripts_avoid_explicit_as_casts() -> void:
	var issues: Array[String] = []
	for path: String in _collect_gdscript_files("res://scripts"):
		issues.append_array(_collect_explicit_as_cast_issues(path))

	assert_true(
		issues.is_empty(),
		"项目脚本应避免显式 as cast；请用强类型返回值、helper 收窄或 GFVariantData 转换：\n%s" % _join_lines(issues)
	)


func test_project_gdscript_variables_use_explicit_types() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_implicit_variable_type_issues(path))

	assert_true(
		issues.is_empty(),
		"项目 GDScript 变量应显式声明类型，避免 Godot 4.6 implicitly inferred static type 警告：\n%s" % _join_lines(issues)
	)


func test_project_gdscript_functions_declare_return_types() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_missing_return_type_issues(path))

	assert_true(
		issues.is_empty(),
		"项目 GDScript 函数应显式声明返回类型，避免 Godot 4.6 静态类型警告：\n%s" % _join_lines(issues)
	)


# --- 私有/辅助方法 ---

func _collect_project_gdscript_files() -> Array[String]:
	var result: Array[String] = []
	for source_root: String in SOURCE_ROOTS:
		result.append_array(_collect_gdscript_files(source_root))
	result.sort()
	return result


func _collect_gdscript_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var scan_report: Dictionary = _scan_project_files(root_path, PackedStringArray(["gd"]))
	assert_true(GFVariantData.get_option_bool(scan_report, "ok"), "GF GDScript 路径扫描应成功。")
	assert_false(
		GFVariantData.get_option_bool(scan_report, "truncated"),
		"GF GDScript 路径扫描不应达到安全上限。"
	)
	for path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
		_append_string(result, path)
	return result


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
		var raw_line: String = _trim_cr(_get_packed_line(lines, line_index))
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
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var section_name: String = _get_dictionary_text(record, "section_name")
		if _line_starts_private_variable(line) and not _section_is_private_variable_section(section_name):
			_append_string(issues, "%s:%d 私有变量位于不匹配的 section：%s" % [
				path,
				line_number,
				_get_section_label(section_name),
			])
	return issues


func _collect_public_method_in_private_section_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var section_name: String = _get_dictionary_text(record, "section_name")
		var function_name: String = _parse_top_level_function_name(line)
		if function_name.is_empty() or function_name.begins_with("_"):
			continue
		if _section_is_private_helper_section(section_name):
			_append_string(issues, "%s:%d %s 位于私有/辅助 section：%s" % [
				path,
				line_number,
				function_name,
				_get_section_label(section_name),
			])
	return issues


func _collect_section_regression_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	var state: Dictionary = {
		"private_helper_section_seen": false,
	}
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			continue

		if _get_dictionary_bool(state, "private_helper_section_seen") and not _section_is_allowed_after_private_helper_section(parsed_section):
			_append_string(issues, "%s:%d section 不应出现在私有/辅助方法 section 之后：%s" % [
				path,
				line_number,
				_get_section_label(parsed_section),
			])
		if _section_is_private_helper_section(parsed_section):
			state["private_helper_section_seen"] = true
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
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
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
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var section_name: String = _get_dictionary_text(record, "section_name")
		var inner_class_name: String = _parse_top_level_inner_class_name(line)
		if inner_class_name.is_empty():
			continue
		if _section_is_inner_class_section(section_name):
			continue
		_append_string(issues, "%s:%d %s 位于非内部类 section：%s" % [
			path,
			line_number,
			inner_class_name,
			_get_section_label(section_name),
		])
	return issues


func _collect_section_order_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	var state: Dictionary = {
		"last_rank": -1,
		"last_section": "",
	}
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			continue

		var rank: int = _get_section_order_rank(parsed_section)
		if rank == -1:
			continue

		var last_rank: int = _get_dictionary_int(state, "last_rank", -1)
		if last_rank != -1 and rank < last_rank:
			_append_string(issues, "%s:%d section 顺序倒退：%s 出现在 %s 之后" % [
				path,
				line_number,
				_get_section_label(parsed_section),
				_get_section_label(_get_dictionary_text(state, "last_section")),
			])
		state["last_rank"] = rank
		state["last_section"] = parsed_section
	return issues


func _collect_section_language_issues(path: String) -> Array[String]:
	var issues: Array[String] = []
	for record: Dictionary in _scan_top_level_source(path):
		var line: String = _get_dictionary_text(record, "line")
		var line_number: int = _get_dictionary_int(record, "line_number")
		var parsed_section: String = _parse_section_name(line)
		if parsed_section.is_empty():
			continue

		if not _contains_cjk_text(parsed_section):
			_append_string(issues, "%s:%d section 名称缺少中文语义：%s" % [
				path,
				line_number,
				_get_section_label(parsed_section),
			])
	return issues


func _collect_path_naming_issues(root_path: String) -> Array[String]:
	var issues: Array[String] = []
	var scan_report: Dictionary = _scan_project_files(root_path)
	if not GFVariantData.get_option_bool(scan_report, "ok"):
		_append_string(issues, "%s: GF 路径扫描失败" % root_path)
		return issues
	if GFVariantData.get_option_bool(scan_report, "truncated"):
		_append_string(issues, "%s: GF 路径扫描达到安全上限" % root_path)
		return issues

	var checked_directories: Dictionary = {}
	var root_prefix: String = root_path.trim_suffix("/") + "/"
	for child_path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
		var relative_path: String = child_path.trim_prefix(root_prefix)
		var segments: PackedStringArray = relative_path.split("/", false)
		for segment_index: int in range(maxi(segments.size() - 1, 0)):
			var directory_name: String = segments[segment_index]
			var directory_path: String = root_path.path_join("/".join(segments.slice(0, segment_index + 1)))
			if checked_directories.has(directory_path):
				continue
			checked_directories[directory_path] = true
			if not _is_snake_case_name(directory_name):
				_append_string(issues, "%s 目录名应使用 snake_case" % directory_path)
		if segments.is_empty():
			continue
		var file_name: String = segments[segments.size() - 1]
		if _should_validate_project_file_name(file_name) and not _is_snake_case_name(file_name.get_basename()):
			_append_string(issues, "%s 文件名应使用 snake_case" % child_path)
	return issues


func _scan_project_files(
	root_path: String,
	extensions: PackedStringArray = PackedStringArray()
) -> Dictionary:
	return GFPathEnumerationTools.scan_files(root_path, {
		"recursive": true,
		"include_hidden": false,
		"extensions": extensions,
		"max_file_count": 20000,
		"sort": true,
	})


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


func _collect_empty_array_assert_eq_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	var assert_eq_token: String = "assert_eq" + "("
	var empty_array_argument_token: String = ", " + "[]"
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains(assert_eq_token) and line.contains(empty_array_argument_token):
			_append_string(issues, "%s:%d 空问题列表应使用 assert_true(issues.is_empty(), ...)" % [
				path,
				line_index + 1,
			])
	return issues


func _collect_gut_assert_eq_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	var assert_eq_token: String = "assert_eq" + "("
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains(assert_eq_token):
			_append_string(issues, "%s:%d 使用 assert_true(actual == expected, ...) 替代 assert_eq。" % [
				path,
				line_index + 1,
			])
	return issues


func _collect_discarded_return_value_call_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		var matched_token: String = _get_discarded_return_value_token(line)
		if matched_token.is_empty():
			continue
		_append_string(issues, "%s:%d %s 的返回值应保存到 _ignored 变量、用于判断，或显式返回。" % [
			path,
			line_index + 1,
			matched_token,
		])
	return issues


func _get_discarded_return_value_token(line: String) -> String:
	if line.is_empty() or line.begins_with("#"):
		return ""

	for token: String in _get_return_value_capture_tokens():
		var token_index: int = line.find(token)
		if token_index == -1:
			continue
		if _return_value_call_is_used(line, token_index):
			continue
		return token
	return ""


func _return_value_call_is_used(line: String, token_index: int) -> bool:
	if _line_has_assignment_before_index(line, token_index):
		return true

	var leading_text: String = line.substr(0, token_index).strip_edges()
	return (
		leading_text.begins_with("assert_")
		or leading_text.begins_with("if ")
		or leading_text.begins_with("elif ")
		or leading_text.begins_with("while ")
		or leading_text.begins_with("return ")
		or leading_text.begins_with("await ")
	)


func _line_has_assignment_before_index(line: String, limit_index: int) -> bool:
	for index: int in range(min(limit_index, line.length())):
		var character: String = _get_character(line, index)
		if character != "=":
			continue
		var previous_character: String = _get_character(line, index - 1)
		var next_character: String = _get_character(line, index + 1)
		if previous_character in ["!", "<", ">", "="] or next_character == "=":
			continue
		return true
	return false


func _get_return_value_capture_tokens() -> Array[String]:
	return [
		"." + "connect(",
		"." + "connect_signal(",
		"." + "execute_command(",
		"." + "bind_interactive_controls(",
		"." + "play_children_reveal(",
		"." + "push_route(",
		"." + "register_runtime_cleanup(",
		"." + "set_parallel(",
		"." + "set_trans(",
		"." + "set_ease(",
		"." + "tween_property(",
		"." + "tween_callback(",
	]


func _collect_missing_await_call_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		var matched_token: String = _get_missing_await_token(line)
		if matched_token.is_empty():
			continue
		_append_string(issues, "%s:%d %s 应使用 await 调用。" % [
			path,
			line_index + 1,
			matched_token,
		])
	return issues


func _get_missing_await_token(line: String) -> String:
	if _line_should_skip_call_scan(line):
		return ""

	for token: String in _get_known_coroutine_call_tokens():
		var token_index: int = line.find(token)
		if token_index == -1:
			continue
		if _coroutine_call_is_awaited(line, token_index):
			continue
		return token
	return ""


func _coroutine_call_is_awaited(line: String, token_index: int) -> bool:
	var leading_text: String = line.substr(0, token_index)
	return leading_text.contains("await ")


func _line_should_skip_call_scan(line: String) -> bool:
	return (
		line.is_empty()
		or line.begins_with("#")
		or line.begins_with("func ")
		or line.begins_with("static func ")
	)


func _get_known_coroutine_call_tokens() -> Array[String]:
	return [
		"." + "process_frame",
		"architecture" + ".register_model(",
		"architecture" + ".register_system(",
		"architecture" + ".register_utility(",
		"architecture" + ".init(",
		"Gf" + ".init(",
		"." + "as_singleton(",
		"history" + "." + "execute_command(",
		"command_history" + "." + "execute_command(",
		"." + "undo_last_async(",
		"." + "redo_async(",
		"_" + "bind_models(",
		"_" + "bind_utilities(",
		"_" + "bind_systems(",
		"_" + "populate_list(",
		"_" + "update_list_and_focus(",
		"_" + "change_page(",
		"_" + "create_tile(",
		"_" + "create_collection_architecture(",
		"_" + "create_save_architecture(",
	]


func _collect_get_value_narrowing_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.begins_with("#") or not line.contains(".get_value("):
			continue
		if _get_value_usage_is_narrowed(lines, line_index):
			continue
		_append_string(issues, "%s:%d get_value() 结果应通过 GFVariantData、项目转换 helper，或 Variant 临时变量收口。" % [
			path,
			line_index + 1,
		])
	return issues


func _get_value_usage_is_narrowed(lines: PackedStringArray, line_index: int) -> bool:
	var statement_window: String = _get_statement_window(lines, line_index)
	if statement_window.contains("GFVariantData.to_"):
		return true
	if statement_window.contains("GFVariantData.get_option_"):
		return true
	if statement_window.contains("_variant_to_"):
		return true

	var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
	return line.begins_with("var ") and line.contains(": Variant =")


func _collect_typed_onready_node_lookup_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if not _typed_onready_line_needs_helper(line):
			continue
		_append_string(issues, "%s:%d typed @onready 节点查找应使用 helper 返回具体类型。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_runtime_node_lookup_assignment_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if not _runtime_node_lookup_line_needs_narrowing(line):
			continue
		_append_string(issues, "%s:%d 节点查找/实例化结果应先以 Node 或 Variant 接收。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_resource_result_assignment_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if not _resource_result_line_needs_narrowing(line):
			continue
		_append_string(issues, "%s:%d 资源结果应先以 Resource/Variant/Object 接收。" % [
			path,
			line_index + 1,
		])
	return issues


func _typed_onready_line_needs_helper(line: String) -> bool:
	if line.is_empty() or line.begins_with("#"):
		return false
	if not line.begins_with("@onready var "):
		return false
	if not line.contains(":") or not line.contains(" = "):
		return false
	for token: String in _get_onready_raw_node_lookup_tokens():
		if line.contains(token):
			return true
	return false


func _runtime_node_lookup_line_needs_narrowing(line: String) -> bool:
	if line.is_empty() or line.begins_with("#"):
		return false
	if line.begins_with("@onready var "):
		return false
	if not line.begins_with("var "):
		return false
	if not line.contains(":") or not line.contains(" = "):
		return false
	if not _line_contains_raw_node_lookup(line):
		return false

	var type_name: String = _extract_declared_variable_type_name(line)
	return _node_lookup_assignment_type_needs_narrowing(type_name)


func _line_contains_raw_node_lookup(line: String) -> bool:
	for token: String in _get_onready_raw_node_lookup_tokens():
		if line.contains(token):
			return true
	return false


func _node_lookup_assignment_type_needs_narrowing(type_name: String) -> bool:
	if type_name.is_empty():
		return false
	return not (type_name in [
		"Node",
		"Object",
		"Variant",
	])


func _resource_result_line_needs_narrowing(line: String) -> bool:
	if line.is_empty() or line.begins_with("#"):
		return false
	if not line.begins_with("var "):
		return false
	if not line.contains(":") or not line.contains(" = "):
		return false
	if not _line_contains_resource_result_expression(line):
		return false

	var type_name: String = _extract_declared_variable_type_name(line)
	return _resource_result_assignment_type_needs_narrowing(type_name)


func _line_contains_resource_result_expression(line: String) -> bool:
	for token: String in _get_resource_result_tokens():
		if line.contains(token):
			return true
	return false


func _get_resource_result_tokens() -> Array[String]:
	return [
		"ResourceLoader.load(",
		" load(",
		"= load(",
		".load_resource(",
		".get_cached(",
		".duplicate(",
	]


func _resource_result_assignment_type_needs_narrowing(type_name: String) -> bool:
	if type_name.is_empty():
		return false
	if type_name.begins_with("Array") or type_name.begins_with("Packed"):
		return false
	return not (type_name in [
		"Dictionary",
		"Object",
		"Resource",
		"Variant",
	])


func _get_onready_raw_node_lookup_tokens() -> Array[String]:
	return [
		"find_child(",
		"get_child(",
		"get_parent(",
		"get_node(",
		"get_node_or_null(",
		"instantiate(",
		"." + "find_child(",
		"." + "get_child(",
		"." + "get_parent(",
		"." + "get_node(",
		"." + "get_node_or_null(",
		"." + "instantiate(",
	]


func _collect_stable_project_interface_dynamic_call_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if not _uses_dynamic_stable_project_interface(line):
			continue
		_append_string(issues, "%s:%d 稳定项目方法应通过具体类型直接调用。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_dynamic_method_dispatch_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not _line_uses_dynamic_method_dispatch(line):
			continue
		_append_string(issues, "%s:%d 项目脚本应使用强类型方法调用。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_typed_gdscript_preload_static_call_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var preload_constant_names: Array[String] = []
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		var constant_name: String = _parse_typed_gdscript_preload_constant_name(line)
		if not constant_name.is_empty():
			_append_string(preload_constant_names, constant_name)
			continue

		for preload_constant_name: String in preload_constant_names:
			if _line_calls_preload_constant_static_method(line, preload_constant_name):
				_append_string(issues, "%s:%d %s 应改为 class_name 直接调用静态方法。" % [
					path,
					line_index + 1,
					preload_constant_name,
				])
	return issues


func _parse_typed_gdscript_preload_constant_name(line: String) -> String:
	if not line.begins_with("const "):
		return ""
	if not line.contains(": GDScript = preload("):
		return ""

	var colon_index: int = line.find(":")
	if colon_index == -1:
		return ""
	return line.substr("const ".length(), colon_index - "const ".length()).strip_edges()


func _line_calls_preload_constant_static_method(line: String, constant_name: String) -> bool:
	if line.is_empty() or line.begins_with("#"):
		return false
	if constant_name.is_empty():
		return false
	return line.contains(constant_name + ".") and not line.contains(constant_name + ".new(")


func _collect_explicit_as_cast_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not _line_uses_explicit_as_cast(line):
			continue
		_append_string(issues, "%s:%d 项目脚本应避免 unsafe cast。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_dictionary_get_object_assignment_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not _line_assigns_dictionary_get_to_object_type(line):
			continue
		_append_string(issues, "%s:%d Dictionary.get() 结果应先收窄再赋给对象类型。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_stylebox_flat_api_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	var class_stylebox_vars: Dictionary = {}
	var local_stylebox_vars: Dictionary = {}
	var inside_function: bool = false
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if _line_starts_function(line):
			inside_function = true
			local_stylebox_vars.clear()
			continue

		var variable_name: String = _extract_declared_variable_name(line)
		var type_name: String = _extract_declared_variable_type_name(line)
		if not variable_name.is_empty():
			if type_name == "StyleBox":
				if inside_function:
					local_stylebox_vars[variable_name] = true
				else:
					class_stylebox_vars[variable_name] = true
			elif type_name == "StyleBoxFlat":
				var _local_erase_result: bool = local_stylebox_vars.erase(variable_name)
				var _class_erase_result: bool = class_stylebox_vars.erase(variable_name)

		var matched_variable: String = _find_stylebox_parent_variable_using_flat_api(
			line,
			class_stylebox_vars,
			local_stylebox_vars
		)
		if matched_variable.is_empty():
			continue
		_append_string(issues, "%s:%d %s 声明为 StyleBox，调用 StyleBoxFlat API 前应先收窄。" % [
			path,
			line_index + 1,
			matched_variable,
		])
	return issues


func _collect_implicit_variable_type_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not _line_uses_implicit_variable_type(line):
			continue
		_append_string(issues, "%s:%d 变量声明应写出类型，不应依赖推断。" % [
			path,
			line_index + 1,
		])
	return issues


func _collect_missing_return_type_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	for line_index: int in range(lines.size()):
		var line: String = _trim_cr(_get_packed_line(lines, line_index)).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not _line_omits_return_type(line):
			continue
		_append_string(issues, "%s:%d 函数声明应写出返回类型。" % [
			path,
			line_index + 1,
		])
	return issues


func _uses_dynamic_stable_project_interface(line: String) -> bool:
	if line.is_empty() or line.begins_with("#"):
		return false
	if not _line_uses_dynamic_method_dispatch(line):
		return false

	for method_name: String in _get_stable_project_interface_method_names():
		if line.contains("\"%s\"" % method_name) or line.contains("&\"%s\"" % method_name):
			return true
	return false


func _line_uses_dynamic_method_dispatch(line: String) -> bool:
	return line.contains(".has_method(") or line.contains(".call(") or line.contains(".callv(")


func _line_uses_explicit_as_cast(line: String) -> bool:
	return (
		line.contains(" as ")
		or line.contains("\tas ")
		or line.contains(" as\t")
	)


func _line_uses_implicit_variable_type(line: String) -> bool:
	if not line.begins_with("var "):
		return false
	if line.contains(":="):
		return true
	return not line.contains(":")


func _line_omits_return_type(line: String) -> bool:
	if not line.begins_with("func ") and not line.begins_with("static func "):
		return false
	return line.contains("(") and line.ends_with(":") and not line.contains("->")


func _line_assigns_dictionary_get_to_object_type(line: String) -> bool:
	if not line.begins_with("var ") or not line.contains(".get("):
		return false

	var type_name: String = _extract_variable_type_name(line)
	if type_name.is_empty() or _dictionary_get_assignment_type_is_safe(type_name):
		return false

	return _expression_uses_direct_dictionary_get(_extract_assignment_expression(line))


func _find_stylebox_parent_variable_using_flat_api(
	line: String,
	class_stylebox_vars: Dictionary,
	local_stylebox_vars: Dictionary
) -> String:
	for variable_name: Variant in local_stylebox_vars.keys():
		var variable_text: String = GFVariantData.to_text(variable_name, "")
		if _line_uses_stylebox_flat_api_on_variable(line, variable_text):
			return variable_text
	for variable_name: Variant in class_stylebox_vars.keys():
		var variable_text: String = GFVariantData.to_text(variable_name, "")
		if _line_uses_stylebox_flat_api_on_variable(line, variable_text):
			return variable_text
	return ""


func _line_uses_stylebox_flat_api_on_variable(line: String, variable_name: String) -> bool:
	if variable_name.is_empty():
		return false

	for token: String in _get_stylebox_flat_api_tokens():
		if line.contains(variable_name + token):
			return true
	return false


func _get_stylebox_flat_api_tokens() -> Array[String]:
	return [
		".bg_color",
		".border_color",
		".shadow_color",
		".shadow_offset",
		".shadow_size",
		".set_border_width_all(",
		".set_corner_radius_all(",
	]


func _line_starts_function(line: String) -> bool:
	return line.begins_with("func ") or line.begins_with("static func ")


func _extract_declared_variable_name(line: String) -> String:
	if not line.begins_with("var "):
		return ""

	var colon_index: int = line.find(":")
	if colon_index == -1:
		return ""
	return line.substr(4, colon_index - 4).strip_edges()


func _extract_declared_variable_type_name(line: String) -> String:
	if not line.begins_with("var "):
		return ""

	var colon_index: int = line.find(":")
	if colon_index == -1:
		return ""
	var equals_index: int = line.find("=")
	var end_index: int = line.length() if equals_index == -1 else equals_index
	if end_index < colon_index:
		return ""
	return line.substr(colon_index + 1, end_index - colon_index - 1).strip_edges()


func _extract_variable_type_name(line: String) -> String:
	var colon_index: int = line.find(":")
	var equals_index: int = line.find("=")
	if colon_index == -1 or equals_index == -1 or equals_index < colon_index:
		return ""
	return line.substr(colon_index + 1, equals_index - colon_index - 1).strip_edges()


func _extract_assignment_expression(line: String) -> String:
	var equals_index: int = line.find("=")
	if equals_index == -1:
		return ""
	return line.substr(equals_index + 1).strip_edges()


func _expression_uses_direct_dictionary_get(expression: String) -> bool:
	var dictionary_get_index: int = expression.find(".get(")
	if dictionary_get_index == -1:
		return false

	var prefix: String = expression.substr(0, dictionary_get_index)
	return not prefix.contains("(")


func _dictionary_get_assignment_type_is_safe(type_name: String) -> bool:
	if type_name.begins_with("Array") or type_name.begins_with("Packed"):
		return true

	return type_name in [
		"bool",
		"float",
		"int",
		"String",
		"StringName",
		"NodePath",
		"Vector2",
		"Vector2i",
		"Vector3",
		"Vector3i",
		"Vector4",
		"Vector4i",
		"Rect2",
		"Rect2i",
		"Color",
		"Dictionary",
		"Variant",
	]


func _get_stable_project_interface_method_names() -> Array[String]:
	return [
		"bind_interactive_controls",
		"play_children_reveal",
		"play_panel_intro",
		"play_feedback",
		"release_visual_tile",
		"play_tile_feedback",
		"restore_from_snapshot",
		"restore_from_snapshot_with_reverse_animation",
		"get_cached_config",
		"get_registered_config_paths",
		"clear_runtime_cache",
		"get_architecture",
		"get_model",
		"get_system",
		"get_utility",
		"send_command",
		"send_query",
		"register_event_owned",
		"unregister_event",
		"send_event",
		"register_simple_event_owned",
		"unregister_simple_event",
		"send_simple_event",
		"unregister_owner_events",
	]


func _get_statement_window(lines: PackedStringArray, line_index: int) -> String:
	var result: String = ""
	var start_index: int = max(0, line_index - 2)
	var end_index: int = min(lines.size() - 1, line_index + 2)
	for index: int in range(start_index, end_index + 1):
		result += _trim_cr(_get_packed_line(lines, index)).strip_edges() + " "
	return result


func _read_declared_class_name(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var declared_class_name: String = _parse_declared_class_name(file.get_as_text())
	file.close()
	return declared_class_name


func _scan_top_level_source(path: String) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var missing_file_records: Array[Dictionary] = []
		missing_file_records.append({
			"line": "无法打开文件",
			"line_number": 0,
			"section_name": "",
		})
		return missing_file_records

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var records: Array[Dictionary] = []
	var current_section: String = ""
	var inside_multiline_string: bool = false
	for line_index: int in range(lines.size()):
		var raw_line: String = _trim_cr(_get_packed_line(lines, line_index))
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
		records.append({
			"line": raw_line,
			"line_number": line_index + 1,
			"section_name": current_section,
		})
	return records


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
		return _get_dictionary_text(CLASS_NAME_OVERRIDES, basename)
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
		var markers: Array[String] = _get_dictionary_string_array(rule, "markers")
		for marker: String in markers:
			if section_name.to_lower().contains(marker.to_lower()):
				return _get_dictionary_int(rule, "rank", -1)
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


func _get_character(text: String, index: int) -> String:
	if index < 0 or index >= text.length():
		return ""
	return text.substr(index, 1)


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_dictionary_value(source: Dictionary, key: Variant, fallback: Variant = null) -> Variant:
	if source.has(key):
		return source[key]
	return fallback


func _get_dictionary_text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	return GFVariantData.to_text(_get_dictionary_value(source, key, fallback), fallback)


func _get_dictionary_int(source: Dictionary, key: Variant, fallback: int = 0) -> int:
	return GFVariantData.to_int(_get_dictionary_value(source, key, fallback), fallback)


func _get_dictionary_bool(source: Dictionary, key: Variant, fallback: bool = false) -> bool:
	return GFVariantData.to_bool(_get_dictionary_value(source, key, fallback), fallback)


func _get_dictionary_string_array(source: Dictionary, key: Variant) -> Array[String]:
	var raw_values: Array = GFVariantData.to_array(_get_dictionary_value(source, key, []))
	var result: Array[String] = []
	for value: Variant in raw_values:
		_append_string(result, GFVariantData.to_text(value))
	return result


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
