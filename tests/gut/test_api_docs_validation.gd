## 验证项目公开 API 文档注释与函数签名保持同步。
extends GutTest


# --- 常量 ---

const SOURCE_ROOTS: Array[String] = [
	"res://app",
	"res://features",
	"res://shared",
	"res://tests/gut",
]
const SOURCE_EXCLUDED_ROOTS: Array[String] = [
	"res://features/asset_library/resources/source_packs",
]
const PROJECT_DOCUMENTATION_ROOTS: Array[String] = [
	"res://app",
	"res://docs",
	"res://features",
	"res://shared",
]
const PROJECT_DOCUMENTATION_FILES: Array[String] = [
	"res://README.md",
]
const ARCHITECTURE_DOC_PATH: String = "res://docs/architecture.md"
const REMOVED_GF_API_SYMBOLS: Array[String] = [
	"fail_on_missing_declared_dependencies",
]
const ARCHITECTURE_STARTUP_SECTION_HEADING: String = "## 启动与装配"
const GF11_ARCHITECTURE_STARTUP_DOC_PATTERNS: Array[Dictionary] = [
	{
		"pattern": "\\bBootRuntime\\b.{0,180}\\bstrict_dependency_lookup\\b",
		"contract": "BootRuntime 启用 strict_dependency_lookup",
	},
	{
		"pattern": "\\bGF 11\\b.{0,180}声明依赖.{0,80}强生命周期契约",
		"contract": "GF 11 声明依赖是强生命周期契约",
	},
	{
		"pattern": "Gf\\.init\\(\\).{0,180}false.{0,120}启动失败",
		"contract": "Gf" + ".init() 返回 false 时启动失败",
	},
]


# --- 测试用例 ---

func test_documented_params_match_function_signatures() -> void:
	var script_paths: Array[String] = _collect_project_gdscript_files()
	var issues: Array[String] = []
	for path: String in script_paths:
		issues.append_array(_collect_param_doc_issues(path))

	assert_true(
		issues.is_empty(),
		"API @param 注释应与函数签名双向一致：\n%s" % _join_lines(issues)
	)


func test_gf11_architecture_startup_documentation_has_no_api_drift() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_markdown_files():
		var source: String = _read_text(path)
		for removed_symbol: String in REMOVED_GF_API_SYMBOLS:
			if source.contains(removed_symbol):
				_append_string(issues, "%s 仍引用已移除的 GF API `%s`" % [path, removed_symbol])

	var architecture_doc: String = _read_text(ARCHITECTURE_DOC_PATH)
	var startup_section: String = _extract_markdown_section(
		architecture_doc,
		ARCHITECTURE_STARTUP_SECTION_HEADING
	)
	var normalized_startup_section: String = _normalize_whitespace(startup_section)
	if startup_section.is_empty():
		_append_string(
			issues,
			"%s 缺少 %s 章节" % [
				ARCHITECTURE_DOC_PATH,
				ARCHITECTURE_STARTUP_SECTION_HEADING,
			]
		)
	for contract_record: Dictionary in GF11_ARCHITECTURE_STARTUP_DOC_PATTERNS:
		var pattern: String = str(contract_record.get("pattern", ""))
		if not _regex_matches(normalized_startup_section, pattern):
			_append_string(
				issues,
				"%s 的 %s 章节缺少 GF 11 启动契约：%s" % [
					ARCHITECTURE_DOC_PATH,
					ARCHITECTURE_STARTUP_SECTION_HEADING,
					str(contract_record.get("contract", "")),
				]
			)

	assert_true(
		issues.is_empty(),
		"项目文档必须与 GF 11 架构依赖及启动失败契约一致：\n%s" % _join_lines(issues)
	)


func test_markdown_section_extraction_does_not_accept_misplaced_contract_text() -> void:
	var source: String = (
		"## 其他章节\n"
		+ "BootRuntime strict_dependency_lookup GF 11 声明依赖强生命周期契约 "
		+ "Gf" + ".init() false 启动失败\n\n"
		+ "## 启动与装配\n当前章节没有契约。\n\n"
		+ "## 后续章节\n尾声。\n"
	)
	var startup_section: String = _extract_markdown_section(
		source,
		ARCHITECTURE_STARTUP_SECTION_HEADING
	)

	assert_true(startup_section.strip_edges() == "当前章节没有契约。")
	for contract_record: Dictionary in GF11_ARCHITECTURE_STARTUP_DOC_PATTERNS:
		assert_false(
			_regex_matches(
				_normalize_whitespace(startup_section),
				str(contract_record.get("pattern", ""))
			),
			"其他章节中的契约文字不得让启动章节守卫误判为通过。"
		)


# --- 私有/辅助方法 ---

func _collect_project_gdscript_files() -> Array[String]:
	var result: Array[String] = []
	for source_root: String in SOURCE_ROOTS:
		result.append_array(_collect_gdscript_files(source_root))
	result.sort()
	return result


func _collect_project_markdown_files() -> Array[String]:
	var result: Array[String] = []
	result.append_array(PROJECT_DOCUMENTATION_FILES)
	for documentation_root: String in PROJECT_DOCUMENTATION_ROOTS:
		var scan_report: Dictionary = GFPathEnumerationTools.scan_files(documentation_root, {
			"recursive": true,
			"include_hidden": false,
			"extensions": PackedStringArray(["md"]),
			"max_file_count": 2000,
			"sort": true,
		})
		assert_true(GFVariantData.get_option_bool(scan_report, "ok"), "项目文档路径扫描应成功。")
		assert_false(
			GFVariantData.get_option_bool(scan_report, "truncated"),
			"项目文档路径扫描不应达到安全上限。"
		)
		for path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
			if _is_excluded_source_path(path):
				continue
			_append_string(result, path)
	result.sort()
	return result


func _collect_gdscript_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var scan_report: Dictionary = GFPathEnumerationTools.scan_files(root_path, {
		"recursive": true,
		"include_hidden": false,
		"extensions": PackedStringArray(["gd"]),
		"max_file_count": 20000,
		"sort": true,
	})
	assert_true(GFVariantData.get_option_bool(scan_report, "ok"), "GF API 文档路径扫描应成功。")
	assert_false(
		GFVariantData.get_option_bool(scan_report, "truncated"),
		"GF API 文档路径扫描不应达到安全上限。"
	)
	for path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
		if _is_excluded_source_path(path):
			continue
		_append_string(result, path)
	return result


func _is_excluded_source_path(path: String) -> bool:
	for excluded_root: String in SOURCE_EXCLUDED_ROOTS:
		if path == excluded_root or path.begins_with(excluded_root + "/"):
			return true
	return false


func _collect_param_doc_issues(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s: 无法打开文件" % path]

	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var issues: Array[String] = []
	var doc_lines: Array[String] = []
	var line_index: int = 0
	while line_index < lines.size():
		var line: String = _get_packed_line(lines, line_index)
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("##"):
			_append_string(doc_lines, trimmed)
			line_index += 1
			continue

		if _line_starts_function(trimmed):
			var signature_start_line: int = line_index + 1
			var signature: String = trimmed
			var signature_parenthesis_depth: int = _get_parenthesis_delta(trimmed)
			while signature_parenthesis_depth > 0 and line_index + 1 < lines.size():
				line_index += 1
				var signature_line: String = _get_packed_line(lines, line_index).strip_edges()
				signature += " " + signature_line
				signature_parenthesis_depth += _get_parenthesis_delta(signature_line)

			var function_name: String = _parse_function_name(signature)
			var actual_params: PackedStringArray = _parse_signature_params(signature)
			var documented_params: PackedStringArray = _parse_documented_params(doc_lines)
			if _should_validate_param_docs(function_name, actual_params, documented_params):
				issues.append_array(_collect_function_param_doc_issues(
					path,
					signature_start_line,
					function_name,
					actual_params,
					documented_params
				))

		if not trimmed.is_empty():
			doc_lines.clear()
		line_index += 1
	return issues


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_true(file != null, "%s 应可读取。" % path)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _extract_markdown_section(source: String, heading: String) -> String:
	var heading_start: int = source.find(heading)
	if heading_start < 0:
		return ""
	var content_start: int = source.find("\n", heading_start + heading.length())
	if content_start < 0:
		return ""
	content_start += 1
	var next_heading: int = source.find("\n## ", content_start)
	if next_heading < 0:
		return source.substr(content_start)
	return source.substr(content_start, next_heading - content_start)


func _normalize_whitespace(source: String) -> String:
	var whitespace_regex: RegEx = RegEx.new()
	if whitespace_regex.compile("\\s+") != OK:
		return source
	return whitespace_regex.sub(source, " ", true).strip_edges()


func _regex_matches(source: String, pattern: String) -> bool:
	if pattern.is_empty():
		return false
	var regex: RegEx = RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(source) != null


func _line_starts_function(trimmed: String) -> bool:
	return trimmed.begins_with("func ") or trimmed.begins_with("static func ")


func _get_parenthesis_delta(text: String) -> int:
	var delta: int = 0
	for i: int in range(text.length()):
		var character: String = _get_character(text, i)
		if character == "(":
			delta += 1
		elif character == ")":
			delta -= 1
	return delta


func _parse_signature_params(signature: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var open_index: int = signature.find("(")
	var close_index: int = signature.rfind(")")
	if open_index == -1 or close_index == -1 or close_index <= open_index:
		return result

	var args_text: String = signature.substr(open_index + 1, close_index - open_index - 1).strip_edges()
	if args_text.is_empty():
		return result

	for raw_part: String in _split_top_level_arguments(args_text):
		var part: String = raw_part.strip_edges()
		if part.is_empty():
			continue

		var default_index: int = _find_top_level_character(part, "=")
		var without_default: String = part
		if default_index != -1:
			without_default = part.substr(0, default_index).strip_edges()

		var type_index: int = _find_top_level_character(without_default, ":")
		var param_name: String = without_default
		if type_index != -1:
			param_name = without_default.substr(0, type_index).strip_edges()
		if not param_name.is_empty():
			_append_packed_string(result, param_name)
	return result


func _parse_documented_params(doc_lines: Array[String]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile("@param\\s+([A-Za-z_]\\w*)\\s*:")
	if compile_error != OK:
		return result
	for line: String in doc_lines:
		for match_result: RegExMatch in regex.search_all(line):
			_append_packed_string(result, match_result.get_string(1))
	return result


func _should_validate_param_docs(
	function_name: String,
	actual_params: PackedStringArray,
	documented_params: PackedStringArray
) -> bool:
	if not documented_params.is_empty():
		return true
	if actual_params.is_empty():
		return false
	return not function_name.begins_with("_")


func _collect_function_param_doc_issues(
	path: String,
	signature_start_line: int,
	function_name: String,
	actual_params: PackedStringArray,
	documented_params: PackedStringArray
) -> Array[String]:
	var issues: Array[String] = []
	var duplicate_params: PackedStringArray = _collect_duplicate_names(documented_params)
	for duplicate_param: String in duplicate_params:
		_append_string(issues, "%s:%d %s 重复记录 @param '%s'" % [
			path,
			signature_start_line,
			function_name,
			duplicate_param,
		])

	for actual_param: String in actual_params:
		if not documented_params.has(actual_param):
			_append_string(issues, "%s:%d %s 缺少 @param '%s'" % [
				path,
				signature_start_line,
				function_name,
				actual_param,
			])

	for documented_param: String in documented_params:
		if not actual_params.has(documented_param):
			_append_string(issues, "%s:%d %s 记录了未知 @param '%s'" % [
				path,
				signature_start_line,
				function_name,
				documented_param,
			])

	if issues.is_empty() and not _packed_string_arrays_equal(actual_params, documented_params):
		_append_string(issues, "%s:%d %s @param 顺序应为 [%s]，实际为 [%s]" % [
			path,
			signature_start_line,
			function_name,
			", ".join(actual_params),
			", ".join(documented_params),
		])

	return issues


func _split_top_level_arguments(args_text: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var start_index: int = 0
	for i: int in range(args_text.length()):
		if _get_character(args_text, i) == "," and _is_top_level_character(args_text, i):
			_append_packed_string(result, args_text.substr(start_index, i - start_index))
			start_index = i + 1
	_append_packed_string(result, args_text.substr(start_index))
	return result


func _find_top_level_character(text: String, target: String) -> int:
	for i: int in range(text.length()):
		if _get_character(text, i) == target and _is_top_level_character(text, i):
			return i
	return -1


func _is_top_level_character(text: String, target_index: int) -> bool:
	var parenthesis_depth: int = 0
	var bracket_depth: int = 0
	var brace_depth: int = 0
	var in_string: bool = false
	var string_delimiter: String = ""
	var escaped: bool = false

	for i: int in range(target_index):
		var character: String = _get_character(text, i)
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == string_delimiter:
				in_string = false
			continue

		if character == "\"" or character == "'":
			in_string = true
			string_delimiter = character
		elif character == "(":
			parenthesis_depth += 1
		elif character == ")":
			parenthesis_depth -= 1
		elif character == "[":
			bracket_depth += 1
		elif character == "]":
			bracket_depth -= 1
		elif character == "{":
			brace_depth += 1
		elif character == "}":
			brace_depth -= 1

	return (
		not in_string
		and parenthesis_depth == 0
		and bracket_depth == 0
		and brace_depth == 0
	)


func _collect_duplicate_names(names: PackedStringArray) -> PackedStringArray:
	var duplicates: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for param_name: String in names:
		if seen.has(param_name):
			if not duplicates.has(param_name):
				_append_packed_string(duplicates, param_name)
		else:
			seen[param_name] = true
	return duplicates


func _packed_string_arrays_equal(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	for i: int in range(left.size()):
		if _get_packed_line(left, i) != _get_packed_line(right, i):
			return false
	return true


func _parse_function_name(signature: String) -> String:
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile("(?:static\\s+)?func\\s+(\\w+)")
	if compile_error != OK:
		return "<未知>"
	var result: RegExMatch = regex.search(signature)
	if result == null:
		return "<未知>"
	return result.get_string(1)


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_character(text: String, index: int) -> String:
	if index < 0 or index >= text.length():
		return ""
	return text.substr(index, 1)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)
