class_name WeChatMinigameReleaseResourceClosure
extends SceneTree

## 微信小游戏正式包资源闭包审计器。
##
## 该工具只读取项目、GF 注册表、内容包与导出预设，不写入任何文件。
## 未声明的动态入口、缺失依赖、依赖扫描上限、字体重映射漂移或预设漂移
## 都会使报告失败，避免以不完整闭包继续发布。


# --- 常量 ---

const DEFAULT_POLICY_PATH: String = "res://tools/wechat_minigame/release_resource_policy.json"
const DEFAULT_PRESET_PATH: String = "res://export_presets.cfg"
const REPORT_SCHEMA_VERSION: int = 1
const IDENTITY_OUTPUT_PREFIX: String = "WECHAT_RELEASE_RESOURCE_CLOSURE="

const _BOUNDED_JSON_READER = preload("res://addons/gf/kernel/core/gf_bounded_json_object_reader.gd")
const _CONTENT_PACKAGE_CATALOG = preload("res://addons/gf/extensions/content_package/runtime/gf_content_package_catalog.gd")
const _CONTENT_PACKAGE_EXPORT_PLAN = preload("res://addons/gf/extensions/content_package/runtime/gf_content_package_export_plan.gd")
const _CONTENT_PACKAGE_MANIFEST = preload("res://addons/gf/extensions/content_package/resources/gf_content_package_manifest.gd")
const _EXTENSION_SETTINGS = preload("res://addons/gf/kernel/extension/gf_extension_settings.gd")
const _RESOURCE_REGISTRY_TOOLS = preload("res://addons/gf/standard/utilities/assets/gf_resource_registry_tools.gd")


# --- Godot 生命周期方法 ---

func _init() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var policy_path: String = _argument_value(arguments, "--policy", DEFAULT_POLICY_PATH)
	var preset_path: String = _argument_value(arguments, "--preset", DEFAULT_PRESET_PATH)
	var check_preset: bool = not arguments.has("--skip-preset-check")
	var report: Dictionary = build_report(policy_path, preset_path, check_preset)
	if arguments.has("--identity-only"):
		print(IDENTITY_OUTPUT_PREFIX + JSON.stringify(make_identity_evidence(report)))
	elif arguments.has("--print-export-files"):
		print(make_export_files_literal(_string_array(report.get("roots", PackedStringArray()))))
	elif arguments.has("--summary-only"):
		print(JSON.stringify({
			"ok": report.get("ok", false),
			"counts": report.get("counts", {}),
			"closure_sha256": report.get("closure_sha256", ""),
			"full_dependency_scan_count": report.get("full_dependency_scan_count", 0),
			"issues": report.get("issues", []),
		}, "", true))
	else:
		print(JSON.stringify(report, "", true))
	quit(0 if _bool_value(report.get("ok", false)) else 1)


# --- 公共方法 ---

## 构建稳定、JSON-safe 的微信正式包资源闭包报告。
static func build_report(
	policy_path: String = DEFAULT_POLICY_PATH,
	preset_path: String = DEFAULT_PRESET_PATH,
	check_preset: bool = true
) -> Dictionary:
	var report: Dictionary = _make_report(policy_path, preset_path, check_preset)
	var policy_read: Dictionary = _BOUNDED_JSON_READER.read_object(policy_path)
	if not _bool_value(policy_read.get("ok", false)):
		_append_issue(report, "policy_read_failed", "资源闭包策略无法完整读取。", {
			"error_kind": str(policy_read.get("error_kind", "")),
			"error": str(policy_read.get("error", "")),
		})
		return _finalize_report(report)

	var policy: Dictionary = _as_dictionary(policy_read.get("data", {}))
	report["policy_id"] = str(policy.get("policy_id", ""))
	report["policy_sha256"] = FileAccess.get_sha256(policy_path)
	_validate_policy(policy, report)
	if not _issues(report).is_empty():
		return _finalize_report(report)

	var features: PackedStringArray = _string_array(policy.get("expected_custom_features", []))
	_sort_unique(features)
	report["features"] = features

	var roots: PackedStringArray = PackedStringArray()
	var structural_dynamic_paths: PackedStringArray = PackedStringArray()
	var content_paths: PackedStringArray = PackedStringArray()
	var dynamic_path_evidence: Array[Dictionary] = []
	_append_paths(roots, _string_array(policy.get("fixed_roots", [])))
	_validate_project_settings(policy, roots, report)
	_collect_extension_installers(policy, roots, report)
	_collect_structure_roots(
		_as_dictionary(policy.get("structure_roots", {})),
		roots,
		structural_dynamic_paths,
		report
	)
	_collect_content_roots(
		_string_array(policy.get("content_manifests", [])),
		roots,
		content_paths,
		report
	)
	_validate_script_path_rules(
		_array(policy.get("script_path_rules", [])),
		features,
		roots,
		dynamic_path_evidence,
		report
	)
	_sort_unique(roots)
	_sort_unique(structural_dynamic_paths)
	_sort_unique(content_paths)

	report["roots"] = roots
	report["structure_dynamic_paths"] = structural_dynamic_paths
	report["content_resource_paths"] = content_paths
	report["dynamic_path_evidence"] = dynamic_path_evidence
	_validate_stable_counts(policy, roots, structural_dynamic_paths, content_paths, report)
	_validate_paths_exist(roots, "root_missing", report)

	var dependency_reports: Dictionary = {}
	var dependency_options: Dictionary = _make_dependency_options(policy)
	var dependency_scan_order: PackedStringArray = _make_dependency_scan_order(roots)
	var already_scanned_paths: PackedStringArray = PackedStringArray()
	var full_dependency_scan_count: int = 0
	for root_path: String in dependency_scan_order:
		if already_scanned_paths.has(root_path):
			dependency_reports[root_path] = {
				"ok": true,
				"paths": PackedStringArray([root_path]),
				"missing": [],
				"limit_reached": false,
				"depth_limit_reached": false,
				"partial": false,
				"truncated": false,
				"covered_by_previous_recursive_scan": true,
			}
			continue
		var dependency_report: Dictionary = _RESOURCE_REGISTRY_TOOLS.build_dependency_report(
			root_path,
			dependency_options
		)
		dependency_reports[root_path] = dependency_report
		full_dependency_scan_count += 1
		_append_paths(
			already_scanned_paths,
			_string_array(dependency_report.get("paths", PackedStringArray()))
		)
	var dependency_evaluation: Dictionary = evaluate_dependency_reports(
		roots,
		dependency_reports
	)
	_merge_issues(report, _array(dependency_evaluation.get("issues", [])))
	var script_dependency_result: Dictionary = expand_script_dependency_closure(
		_string_array(dependency_evaluation.get("paths", PackedStringArray())),
		_string_array(policy.get("script_class_index_roots", [])),
		dependency_options,
		_as_dictionary(policy.get("stable_strategy", {}))
	)
	_merge_issues(report, _array(script_dependency_result.get("issues", [])))
	var script_dependency_evidence: Dictionary = script_dependency_result.duplicate(true)
	var _paths_erased: bool = script_dependency_evidence.erase("paths")
	var _literal_records_erased: bool = script_dependency_evidence.erase("literal_records")
	var _script_issues_erased: bool = script_dependency_evidence.erase("issues")
	report["script_dependency_evidence"] = script_dependency_evidence
	report["dependency_report_count"] = dependency_reports.size()
	report["full_dependency_scan_count"] = (
		full_dependency_scan_count
		+ _int_value(script_dependency_result.get("resource_dependency_scan_count", 0))
	)
	report["dependency_partial"] = (
		_bool_value(dependency_evaluation.get("partial", true), true)
		or _bool_value(script_dependency_result.get("partial", true), true)
	)
	report["dependency_truncated"] = (
		_bool_value(dependency_evaluation.get("truncated", true), true)
		or _bool_value(script_dependency_result.get("truncated", true), true)
	)
	var raw_dependency_closure: PackedStringArray = _string_array(
		script_dependency_result.get("paths", PackedStringArray())
	)
	report["raw_dependency_closure"] = raw_dependency_closure

	var remap_result: Dictionary = apply_font_remap_policy(
		raw_dependency_closure,
		_array(policy.get("font_remaps", [])),
		features
	)
	_merge_issues(report, _array(remap_result.get("issues", [])))
	var closure: PackedStringArray = _string_array(remap_result.get("paths", PackedStringArray()))
	report["closure"] = closure
	report["font_remap_evidence"] = remap_result.get("evidence", [])

	var raw_include_result: Dictionary = _validate_raw_includes(
		_string_array(policy.get("raw_includes", []))
	)
	_merge_issues(report, _array(raw_include_result.get("issues", [])))
	report["raw_includes"] = raw_include_result.get("patterns", PackedStringArray())
	report["raw_include_expanded_paths"] = raw_include_result.get("expanded_paths", PackedStringArray())
	var runtime_literal_result: Dictionary = audit_runtime_resource_literals(
		_array(script_dependency_result.get("literal_records", [])),
		raw_dependency_closure,
		roots,
		_string_array(raw_include_result.get("expanded_paths", PackedStringArray())),
		dynamic_path_evidence,
		_string_array(policy.get("allowed_directory_literals", [])),
		_array(policy.get("runtime_literal_rules", []))
	)
	_merge_issues(report, _array(runtime_literal_result.get("issues", [])))
	var runtime_literal_evidence: Dictionary = runtime_literal_result.duplicate(true)
	var _runtime_issues_erased: bool = runtime_literal_evidence.erase("issues")
	report["runtime_literal_evidence"] = runtime_literal_evidence

	_validate_forbidden_paths(
		roots,
		closure,
		_string_array(raw_include_result.get("expanded_paths", PackedStringArray())),
		_array(policy.get("forbidden_paths", [])),
		report
	)

	if check_preset:
		var preset_report: Dictionary = check_export_preset(
		preset_path,
		str(policy.get("preset_name", "")),
			features,
			closure,
			_string_array(raw_include_result.get("patterns", PackedStringArray())),
			closure,
			_string_array(raw_include_result.get("expanded_paths", PackedStringArray()))
		)
		report["preset"] = preset_report
		_merge_issues(report, _array(preset_report.get("issues", [])))

	return _finalize_report(report)


## 提取可由正式导出报告与 build_id 绑定的最小、稳定闭包证据。
static func make_identity_evidence(report: Dictionary) -> Dictionary:
	return {
		"schema_version": _int_value(report.get("schema_version", 0)),
		"ok": _bool_value(report.get("ok", false)),
		"policy_id": str(report.get("policy_id", "")),
		"policy_path": str(report.get("policy_path", "")).trim_prefix("res://").replace("\\", "/"),
		"policy_sha256": str(report.get("policy_sha256", "")).to_lower(),
		"closure_sha256": str(report.get("closure_sha256", "")).to_lower(),
		"full_dependency_scan_count": _int_value(
			report.get("full_dependency_scan_count", 0)
		),
		"dependency_partial": _bool_value(report.get("dependency_partial", true), true),
		"dependency_truncated": _bool_value(
			report.get("dependency_truncated", true),
			true
		),
		"counts": _as_dictionary(report.get("counts", {})).duplicate(true),
		"issues": _array(report.get("issues", [])).duplicate(true),
	}


## 汇总 GF 依赖报告；供构建逻辑和 fail-closed 回归测试共同使用。
static func evaluate_dependency_reports(
	root_paths: PackedStringArray,
	dependency_reports: Dictionary
) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"partial": false,
		"truncated": false,
		"paths": PackedStringArray(),
		"issues": [],
	}
	var paths: PackedStringArray = PackedStringArray()
	var issues: Array[Dictionary] = []
	for root_path: String in root_paths:
		if not dependency_reports.has(root_path):
			issues.append(_issue(
				"dependency_report_missing",
				"依赖扫描报告缺失。",
				{"root_path": root_path}
			))
			result["partial"] = true
			continue
		var dependency_report: Dictionary = _as_dictionary(dependency_reports[root_path])
		_append_paths(paths, _string_array(dependency_report.get("paths", [])))
		var missing_paths: PackedStringArray = _dependency_missing_paths(dependency_report)
		if not missing_paths.is_empty():
			issues.append(_issue(
				"dependency_missing",
				"依赖闭包包含缺失路径。",
				{"root_path": root_path, "paths": missing_paths}
			))
			result["partial"] = true
		var limit_reached: bool = _bool_value(
			dependency_report.get("limit_reached", false)
		)
		var depth_limit_reached: bool = _bool_value(
			dependency_report.get("depth_limit_reached", false)
		)
		var explicitly_partial: bool = _bool_value(
			dependency_report.get("partial", false)
		)
		var explicitly_truncated: bool = _bool_value(
			dependency_report.get("truncated", false)
		)
		if limit_reached or depth_limit_reached or explicitly_partial or explicitly_truncated:
			issues.append(_issue(
				"dependency_scan_incomplete",
				"依赖扫描触及上限或返回不完整结果。",
				{
					"root_path": root_path,
					"limit_reached": limit_reached,
					"depth_limit_reached": depth_limit_reached,
					"partial": explicitly_partial,
					"truncated": explicitly_truncated,
				}
			))
			result["partial"] = true
			result["truncated"] = limit_reached or depth_limit_reached or explicitly_truncated
		if not _bool_value(dependency_report.get("ok", false)) and missing_paths.is_empty():
			issues.append(_issue(
				"dependency_report_unhealthy",
				"GF 依赖报告未通过。",
				{
					"root_path": root_path,
					"summary": str(dependency_report.get("summary", "")),
				}
			))
			result["partial"] = true
	_sort_unique(paths)
	result["paths"] = paths
	result["issues"] = issues
	result["ok"] = issues.is_empty()
	return result


## 在 Godot 资源依赖图之外补齐 GDScript preload/extends/global class 依赖。
##
## `ResourceLoader.get_dependencies()` 不保证枚举脚本的全局 class_name 解析依赖；
## 正式资源白名单必须显式补齐这些脚本，否则干净导出可能只在编辑器缓存存在时通过。
static func expand_script_dependency_closure(
	initial_paths: PackedStringArray,
	class_index_roots: PackedStringArray,
	dependency_options: Dictionary,
	strategy: Dictionary
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var paths: PackedStringArray = initial_paths.duplicate()
	_sort_unique(paths)
	var index_result: Dictionary = _build_script_class_index(
		class_index_roots,
		strategy
	)
	for issue_value: Variant in _array(index_result.get("issues", [])):
		issues.append(_as_dictionary(issue_value))
	var class_index: Dictionary = _as_dictionary(index_result.get("class_index", {}))
	var script_queue: PackedStringArray = PackedStringArray()
	var queued_scripts: Dictionary = {}
	for path: String in paths:
		if path.get_extension().to_lower() == "gd":
			_append_script_to_queue(path, script_queue, queued_scripts)

	var lexeme_regex: RegEx = RegEx.new()
	var identifier_regex: RegEx = RegEx.new()
	var static_load_regex: RegEx = RegEx.new()
	var extends_regex: RegEx = RegEx.new()
	if (
		lexeme_regex.compile(
			'"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|#[^\\r\\n]*'
		) != OK
		or identifier_regex.compile("[A-Za-z_][A-Za-z0-9_]*") != OK
		or static_load_regex.compile(
			"(?:ResourceLoader\\.(?:load|load_threaded_request)|(?:^|[^A-Za-z0-9_.])(?:preload|load))\\s*\\(\\s*$"
		) != OK
		or extends_regex.compile("(?:^|[\\r\\n])[\\t ]*extends[\\t ]*$") != OK
	):
		issues.append(_issue(
			"script_dependency_parser_failed",
			"GDScript 依赖扫描器初始化失败。"
		))
		return {
			"ok": false,
			"partial": true,
			"truncated": true,
			"paths": paths,
			"literal_records": [],
			"issues": issues,
		}

	var max_script_paths: int = _int_value(strategy.get("max_script_scan_paths", 0))
	var max_file_bytes: int = _int_value(strategy.get("max_script_file_bytes", 0))
	var max_total_bytes: int = _int_value(strategy.get("max_script_total_bytes", 0))
	var scanned_scripts: Dictionary = {}
	var scanned_total_bytes: int = 0
	var literal_records: Array[Dictionary] = []
	var class_dependency_edges: Dictionary = {}
	var static_dependency_edges: Dictionary = {}
	var resource_dependency_roots: Dictionary = {}
	var resource_dependency_scan_count: int = 0
	var queue_index: int = 0
	var truncated: bool = _bool_value(index_result.get("truncated", false))
	var partial: bool = _bool_value(index_result.get("partial", false))
	while queue_index < script_queue.size():
		if max_script_paths <= 0 or scanned_scripts.size() >= max_script_paths:
			issues.append(_issue(
				"script_dependency_path_limit",
				"GDScript 依赖扫描触及脚本数量上限。",
				{"limit": max_script_paths}
			))
			partial = true
			truncated = true
			break
		var script_path: String = script_queue[queue_index]
		queue_index += 1
		if scanned_scripts.has(script_path):
			continue
		scanned_scripts[script_path] = true
		var source_read: Dictionary = _read_bounded_script_source(
			script_path,
			max_file_bytes,
			max_total_bytes - scanned_total_bytes
		)
		if not _bool_value(source_read.get("ok", false)):
			issues.append(_issue(
				str(source_read.get("code", "script_dependency_read_failed")),
				"GDScript 依赖源无法完整读取。",
				{
					"path": script_path,
				"size": _int_value(source_read.get("size", -1), -1),
					"max_file_bytes": max_file_bytes,
					"remaining_total_bytes": max_total_bytes - scanned_total_bytes,
				}
			))
			partial = true
			truncated = true
			continue
		var source: String = str(source_read.get("source", ""))
		scanned_total_bytes += _int_value(source_read.get("size", 0))
		var analysis: Dictionary = _analyze_gdscript_source(
			source,
			lexeme_regex,
			identifier_regex,
			static_load_regex,
			extends_regex
		)
		for literal_value: Variant in _array(analysis.get("literal_records", [])):
			var literal_record: Dictionary = _as_dictionary(literal_value).duplicate(true)
			literal_record["script_path"] = script_path
			literal_records.append(literal_record)
		var identifiers: PackedStringArray = _string_array(
			analysis.get("identifiers", PackedStringArray())
		)
		for identifier: String in identifiers:
			if not class_index.has(identifier):
				continue
			var dependency_path: String = str(class_index[identifier])
			if dependency_path == script_path:
				continue
			class_dependency_edges["%s -> %s" % [script_path, dependency_path]] = true
			if not paths.has(dependency_path):
				var _dependency_path_added: bool = paths.append(dependency_path)
			_append_script_to_queue(dependency_path, script_queue, queued_scripts)

		for literal_value: Variant in _array(analysis.get("literal_records", [])):
			var literal_record: Dictionary = _as_dictionary(literal_value)
			if not _bool_value(literal_record.get("static_dependency", false)):
				continue
			var literal_path: String = _normalize_resource_pattern(
				str(literal_record.get("path", ""))
			)
			if literal_path.is_empty() or literal_path.contains("*") or literal_path.contains("?"):
				continue
			static_dependency_edges["%s -> %s" % [script_path, literal_path]] = true
			if paths.has(literal_path):
				if literal_path.get_extension().to_lower() == "gd":
					_append_script_to_queue(literal_path, script_queue, queued_scripts)
				continue
			if literal_path.get_extension().to_lower() == "gd":
				if not FileAccess.file_exists(literal_path):
					issues.append(_issue(
						"script_static_dependency_missing",
						"GDScript 静态脚本依赖不存在。",
						{"script_path": script_path, "path": literal_path}
					))
					partial = true
					continue
				var _literal_path_added: bool = paths.append(literal_path)
				_append_script_to_queue(literal_path, script_queue, queued_scripts)
				continue
			if resource_dependency_roots.has(literal_path):
				continue
			resource_dependency_roots[literal_path] = true
			var dependency_report: Dictionary = _RESOURCE_REGISTRY_TOOLS.build_dependency_report(
				literal_path,
				dependency_options
			)
			resource_dependency_scan_count += 1
			var dependency_result: Dictionary = evaluate_dependency_reports(
				PackedStringArray([literal_path]),
				{literal_path: dependency_report}
			)
			for issue_value: Variant in _array(dependency_result.get("issues", [])):
				issues.append(_as_dictionary(issue_value))
			partial = partial or _bool_value(dependency_result.get("partial", true), true)
			truncated = truncated or _bool_value(
				dependency_result.get("truncated", true),
				true
			)
			for dependency_path: String in _string_array(
				dependency_result.get("paths", PackedStringArray())
			):
				if not paths.has(dependency_path):
					var _transitive_path_added: bool = paths.append(dependency_path)
				if dependency_path.get_extension().to_lower() == "gd":
					_append_script_to_queue(dependency_path, script_queue, queued_scripts)

	_sort_unique(paths)
	var class_edges: PackedStringArray = _dictionary_keys_as_strings(class_dependency_edges)
	var static_edges: PackedStringArray = _dictionary_keys_as_strings(static_dependency_edges)
	return {
		"ok": issues.is_empty() and not partial and not truncated,
		"partial": partial,
		"truncated": truncated,
		"paths": paths,
		"literal_records": literal_records,
		"issues": issues,
		"class_index_path_count": _int_value(index_result.get("path_count", 0)),
		"class_index_class_count": class_index.size(),
		"scripts_scanned": scanned_scripts.size(),
		"script_source_bytes": scanned_total_bytes,
		"class_dependency_edge_count": class_edges.size(),
		"static_dependency_edge_count": static_edges.size(),
		"resource_dependency_scan_count": resource_dependency_scan_count,
		"paths_added": paths.size() - initial_paths.size(),
		"class_dependency_edges_sha256": "\n".join(class_edges).sha256_text(),
		"static_dependency_edges_sha256": "\n".join(static_edges).sha256_text(),
	}


## 审计运行时闭包脚本中的 res:// 文字；只接受依赖闭包、显式动态规则、
## raw include 或精确且足够窄的目录声明。
static func audit_runtime_resource_literals(
	literal_records: Array,
	dependency_paths: PackedStringArray,
	root_paths: PackedStringArray,
	raw_paths: PackedStringArray,
	dynamic_path_evidence: Array,
	allowed_directory_literals: PackedStringArray,
	runtime_literal_rule_values: Array = []
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var known_paths: Dictionary = {}
	for known_path: String in dependency_paths:
		known_paths[known_path] = "dependency"
	for known_path: String in root_paths:
		known_paths[known_path] = "root"
	for known_path: String in raw_paths:
		known_paths[known_path] = "raw_include"
	for evidence_value: Variant in dynamic_path_evidence:
		var evidence: Dictionary = _as_dictionary(evidence_value)
		for known_path: String in _string_array(evidence.get("paths", [])):
			known_paths[known_path] = "feature_rule"

	var allowed_directories: Dictionary = {}
	for raw_directory_path: String in allowed_directory_literals:
		var directory_path: String = _normalize_resource_pattern(raw_directory_path)
		var relative_segments: PackedStringArray = directory_path.trim_prefix("res://").split(
			"/",
			false
		)
		if (
			directory_path.is_empty()
			or directory_path.contains("*")
			or directory_path.contains("?")
			or directory_path.contains("%")
			or relative_segments.size() < 3
		):
			issues.append(_issue(
				"allowed_directory_literal_too_broad",
				"允许的运行时目录文字必须是 res:// 下至少三级的精确目录。",
				{"path": raw_directory_path}
			))
			continue
		if DirAccess.open(directory_path) == null:
			issues.append(_issue(
				"allowed_directory_literal_missing",
				"允许的运行时目录文字不存在或不可读。",
				{"path": directory_path}
			))
			continue
		allowed_directories[directory_path] = false

	var explicit_rules: Dictionary = {}
	for rule_value: Variant in runtime_literal_rule_values:
		var rule: Dictionary = _as_dictionary(rule_value)
		var rule_script_path: String = _normalize_resource_pattern(str(
			rule.get("script_path", "")
		))
		var rule_literal: String = str(rule.get("literal", ""))
		var expected_count: int = _int_value(rule.get("expected_count", 0))
		var rule_kind: String = str(rule.get("kind", "")).strip_edges()
		var rule_reason: String = str(rule.get("reason", "")).strip_edges()
		var rule_identity: String = _runtime_literal_rule_identity(
			rule_script_path,
			rule_literal
		)
		if (
			rule_script_path.is_empty()
			or not FileAccess.file_exists(rule_script_path)
			or not rule_literal.begins_with("res://")
			or rule_literal.contains("\n")
			or rule_literal.contains("\r")
			or expected_count <= 0
			or rule_kind.is_empty()
			or rule_reason.is_empty()
		):
			issues.append(_issue(
				"runtime_literal_rule_invalid",
				"运行时资源文字例外必须绑定存在的精确脚本、精确文字、正数次数、类型与原因。",
				{"rule": rule}
			))
			continue
		if explicit_rules.has(rule_identity):
			issues.append(_issue(
				"runtime_literal_rule_duplicate",
				"运行时资源文字例外重复声明。",
				{"script_path": rule_script_path, "literal": rule_literal}
			))
			continue
		explicit_rules[rule_identity] = {
			"script_path": rule_script_path,
			"literal": rule_literal,
			"expected_count": expected_count,
			"actual_count": 0,
			"kind": rule_kind,
			"reason": rule_reason,
		}

	var covered_counts: Dictionary = {
		"dependency": 0,
		"root": 0,
		"raw_include": 0,
		"feature_rule": 0,
		"allowed_directory": 0,
		"explicit_rule": 0,
	}
	var observed_count: int = 0
	var audited_count: int = 0
	for record_value: Variant in literal_records:
		var record: Dictionary = _as_dictionary(record_value)
		var raw_path: String = str(record.get("path", ""))
		if not raw_path.begins_with("res://"):
			continue
		observed_count += 1
		var script_path: String = str(record.get("script_path", ""))
		audited_count += 1
		var path: String = _normalize_resource_pattern(raw_path)
		if known_paths.has(path):
			var reason: String = str(known_paths[path])
			covered_counts[reason] = _int_value(covered_counts.get(reason, 0)) + 1
			continue
		if allowed_directories.has(path):
			allowed_directories[path] = true
			covered_counts["allowed_directory"] = _int_value(
				covered_counts.get("allowed_directory", 0)
			) + 1
			continue
		var rule_identity: String = _runtime_literal_rule_identity(script_path, raw_path)
		if explicit_rules.has(rule_identity):
			var matched_rule: Dictionary = _as_dictionary(explicit_rules[rule_identity])
			matched_rule["actual_count"] = _int_value(
				matched_rule.get("actual_count", 0)
			) + 1
			explicit_rules[rule_identity] = matched_rule
			covered_counts["explicit_rule"] = _int_value(
				covered_counts.get("explicit_rule", 0)
			) + 1
			continue
		if (
			path.is_empty()
			or path.contains("*")
			or path.contains("?")
			or path.contains("%")
			or path.contains("{")
			or path.contains("}")
		):
			issues.append(_issue(
				"runtime_resource_literal_dynamic",
				"运行时资源文字不是可证明的精确 res:// 路径。",
				{"script_path": script_path, "path": raw_path}
			))
			continue
		issues.append(_issue(
			"runtime_resource_literal_untracked",
			"运行时脚本包含未由闭包、feature 规则或精确目录声明覆盖的资源文字。",
			{
				"script_path": script_path,
				"path": path,
				"context": str(record.get("context", "")),
			}
		))

	for allowed_path_value: Variant in allowed_directories.keys():
		var allowed_path: String = str(allowed_path_value)
		if not _bool_value(allowed_directories[allowed_path]):
			issues.append(_issue(
				"allowed_directory_literal_unused",
				"允许的运行时目录文字没有被闭包脚本实际引用。",
				{"path": allowed_path}
			))
	var explicit_rule_evidence: Array[Dictionary] = []
	var rule_identities: PackedStringArray = _dictionary_keys_as_strings(explicit_rules)
	for rule_identity: String in rule_identities:
		var explicit_rule: Dictionary = _as_dictionary(explicit_rules[rule_identity])
		var expected_rule_count: int = _int_value(explicit_rule.get("expected_count", 0))
		var actual_rule_count: int = _int_value(explicit_rule.get("actual_count", 0))
		explicit_rule_evidence.append(explicit_rule.duplicate(true))
		if actual_rule_count != expected_rule_count:
			issues.append(_issue(
				"runtime_literal_rule_count_mismatch",
				"运行时资源文字例外的实际引用次数与声明不一致。",
				{
					"script_path": explicit_rule.get("script_path", ""),
					"literal": explicit_rule.get("literal", ""),
					"expected_count": expected_rule_count,
					"actual_count": actual_rule_count,
				}
			))
	return {
		"ok": issues.is_empty(),
		"observed_literal_count": observed_count,
		"literal_count": audited_count,
		"allowed_directory_count": allowed_directories.size(),
		"covered_counts": covered_counts,
		"explicit_rule_count": explicit_rules.size(),
		"explicit_rule_evidence": explicit_rule_evidence,
		"issues": issues,
	}


## 对源依赖闭包应用声明式字体 remap，并校验导出插件常量没有漂移。
static func apply_font_remap_policy(
	raw_paths: PackedStringArray,
	remap_values: Array,
	features: PackedStringArray
) -> Dictionary:
	var result_paths: PackedStringArray = raw_paths.duplicate()
	var evidence: Array[Dictionary] = []
	var issues: Array[Dictionary] = []
	for remap_value: Variant in remap_values:
		var remap_rule: Dictionary = _as_dictionary(remap_value)
		var feature: String = str(remap_rule.get("feature", ""))
		if feature.is_empty() or not features.has(feature):
			continue
		var plugin_path: String = str(remap_rule.get("export_plugin_path", ""))
		var source_variations: PackedStringArray = _string_array(
			remap_rule.get("source_variation_paths", [])
		)
		var removed_paths: PackedStringArray = _string_array(
			remap_rule.get("removed_dependency_paths", [])
		)
		var replacement_path: String = str(remap_rule.get("replacement_font_path", ""))
		var project_font_path: String = str(remap_rule.get("project_font_path", ""))
		var plugin_constants: Dictionary = _read_script_constants(plugin_path, issues)
		var declared_variations: PackedStringArray = _variant_to_strings(
			plugin_constants.get("_FONT_VARIATION_PATHS", [])
		)
		var profile_fonts: Dictionary = _as_dictionary(
			plugin_constants.get("_PROFILE_FONT_PATHS", {})
		)
		if not _sets_equal(source_variations, declared_variations):
			issues.append(_issue(
				"font_remap_variation_drift",
				"字体 remap 源路径与导出插件不一致。",
				{
					"expected": source_variations,
					"actual": declared_variations,
				}
			))
		if str(profile_fonts.get(feature, "")) != replacement_path:
			issues.append(_issue(
				"font_remap_profile_drift",
				"字体 remap 目标与导出插件不一致。",
				{
					"feature": feature,
					"expected": replacement_path,
					"actual": str(profile_fonts.get(feature, "")),
				}
			))
		for source_path: String in source_variations:
			if not result_paths.has(source_path):
				issues.append(_issue(
					"font_remap_source_missing",
					"字体 remap 源资源不在原始依赖闭包中。",
					{"path": source_path}
				))
		for removed_path: String in removed_paths:
			var _removed: bool = result_paths.erase(removed_path)
		if not replacement_path.is_empty() and not result_paths.has(replacement_path):
			var _replacement_added: bool = result_paths.append(replacement_path)
		if not project_font_path.is_empty() and not result_paths.has(project_font_path):
			var _project_font_added: bool = result_paths.append(project_font_path)
		evidence.append({
			"id": str(remap_rule.get("id", "")),
			"feature": feature,
			"source_variation_paths": source_variations,
			"replacement_font_path": replacement_path,
			"project_font_path": project_font_path,
			"removed_dependency_paths": removed_paths,
		})
	_sort_unique(result_paths)
	return {
		"ok": issues.is_empty(),
		"paths": result_paths,
		"evidence": evidence,
		"issues": issues,
	}


## 校验微信正式导出 preset 与稳定闭包策略完全一致。
static func check_export_preset(
	preset_path: String,
	preset_name: String,
	features: PackedStringArray,
	roots: PackedStringArray,
	raw_include_patterns: PackedStringArray,
	closure: PackedStringArray,
	raw_include_paths: PackedStringArray
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"preset_path": preset_path,
		"preset_name": preset_name,
		"section": "",
		"issues": [],
	}
	var issues: Array[Dictionary] = []
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(preset_path)
	if load_error != OK:
		issues.append(_issue(
			"preset_read_failed",
			"导出预设无法读取。",
			{"error": error_string(load_error)}
		))
		result["issues"] = issues
		return result
	var section: String = _find_preset_section(config, preset_name)
	result["section"] = section
	if section.is_empty():
		issues.append(_issue("preset_missing", "找不到微信正式导出预设。"))
		result["issues"] = issues
		return result
	var actual_features: PackedStringArray = _parse_csv(
		str(config.get_value(section, "custom_features", "")),
		false
	)
	if not _sets_equal(features, actual_features):
		issues.append(_issue(
			"preset_features_mismatch",
			"导出预设 custom feature 与策略不一致。",
			{"expected": features, "actual": actual_features}
		))
	if str(config.get_value(section, "export_filter", "")) != "resources":
		issues.append(_issue(
			"preset_export_filter_mismatch",
			"微信正式预设必须使用 resources 显式根集合。",
			{"actual": str(config.get_value(section, "export_filter", ""))}
		))
	var actual_roots: PackedStringArray = _variant_to_strings_preserve_order(
		config.get_value(section, "export_files", PackedStringArray())
	)
	if actual_roots != roots:
		issues.append(_issue(
			"preset_roots_mismatch",
			"导出预设 export_files 与排序后的完整闭包不一致。",
			{
				"missing": _set_difference(roots, actual_roots),
				"extra": _set_difference(actual_roots, roots),
				"order_or_duplicate_mismatch": _sets_equal(roots, actual_roots),
			}
		))
	var expected_includes: PackedStringArray = _resource_patterns_to_export_filters(
		raw_include_patterns
	)
	var actual_includes: PackedStringArray = _parse_csv(
		str(config.get_value(section, "include_filter", "")),
		true
	)
	if not _sets_equal(expected_includes, actual_includes):
		issues.append(_issue(
			"preset_include_filter_mismatch",
			"导出预设 include_filter 与 raw include 策略不一致。",
			{
				"missing": _set_difference(expected_includes, actual_includes),
				"extra": _set_difference(actual_includes, expected_includes),
			}
		))
	var exclude_filters: PackedStringArray = _parse_csv(
		str(config.get_value(section, "exclude_filter", "")),
		true
	)
	var required_paths: PackedStringArray = closure.duplicate()
	_append_paths(required_paths, raw_include_paths)
	_sort_unique(required_paths)
	for closure_path: String in required_paths:
		var relative_path: String = closure_path.trim_prefix("res://")
		for exclude_filter: String in exclude_filters:
			if relative_path.match(exclude_filter):
				issues.append(_issue(
					"preset_excludes_closure_path",
					"导出排除规则命中了有效闭包或 raw include 路径。",
					{"path": closure_path, "filter": exclude_filter}
				))
				break
	result["issues"] = issues
	result["ok"] = issues.is_empty()
	return result


## 由稳定根列表生成 export_presets.cfg 的 PackedStringArray 字面量。
static func make_export_files_literal(root_paths: PackedStringArray) -> String:
	var normalized: PackedStringArray = root_paths.duplicate()
	_sort_unique(normalized)
	var quoted_paths: PackedStringArray = PackedStringArray()
	for root_path: String in normalized:
		var _quoted_path_added: bool = quoted_paths.append(
			'"%s"' % root_path.replace('"', '\\"')
		)
	return "PackedStringArray(%s)" % ", ".join(quoted_paths)


# --- 私有/辅助方法 ---

static func _build_script_class_index(
	root_paths: PackedStringArray,
	strategy: Dictionary
) -> Dictionary:
	var state: Dictionary = {
		"paths": PackedStringArray(),
		"issues": [],
		"entry_count": 0,
		"partial": false,
		"truncated": false,
		"max_paths": _int_value(strategy.get("max_script_index_paths", 0)),
		"max_entries": _int_value(strategy.get("max_script_index_entries", 0)),
		"max_depth": _int_value(strategy.get("max_script_index_depth", 0)),
	}
	for root_path: String in root_paths:
		_collect_script_index_paths(root_path, 0, state)
		if _bool_value(state.get("truncated", false)):
			break
	var paths: PackedStringArray = _string_array(state.get("paths", PackedStringArray()))
	_sort_unique(paths)
	var class_index: Dictionary = {}
	var class_name_regex: RegEx = RegEx.new()
	if class_name_regex.compile(
		"(?m)^[\\t ]*class_name[\\t ]+([A-Za-z_][A-Za-z0-9_]*)"
	) != OK:
		_array(state.get("issues", [])).append(_issue(
			"script_class_parser_failed",
			"GDScript class_name 索引器初始化失败。"
		))
		state["partial"] = true
		state["truncated"] = true
	else:
		var max_file_bytes: int = _int_value(strategy.get("max_script_file_bytes", 0))
		var max_total_bytes: int = _int_value(strategy.get("max_script_total_bytes", 0))
		var total_bytes: int = 0
		for path: String in paths:
			var source_read: Dictionary = _read_bounded_script_source(
				path,
				max_file_bytes,
				max_total_bytes - total_bytes
			)
			if not _bool_value(source_read.get("ok", false)):
				_array(state.get("issues", [])).append(_issue(
					str(source_read.get("code", "script_class_index_read_failed")),
					"GDScript class_name 索引源无法完整读取。",
					{"path": path, "size": _int_value(source_read.get("size", -1), -1)}
				))
				state["partial"] = true
				state["truncated"] = true
				continue
			total_bytes += _int_value(source_read.get("size", 0))
			var source: String = str(source_read.get("source", ""))
			var class_match: RegExMatch = class_name_regex.search(source)
			if class_match == null:
				continue
			var class_name_text: String = class_match.get_string(1)
			if class_index.has(class_name_text) and str(class_index[class_name_text]) != path:
				_array(state.get("issues", [])).append(_issue(
					"script_class_name_duplicate",
					"GDScript class_name 在资源索引根中重复。",
					{
						"class_name": class_name_text,
						"first_path": str(class_index[class_name_text]),
						"second_path": path,
					}
				))
				state["partial"] = true
				continue
			class_index[class_name_text] = path
		state["source_bytes"] = total_bytes
	return {
		"ok": _array(state.get("issues", [])).is_empty(),
		"partial": _bool_value(state.get("partial", false)),
		"truncated": _bool_value(state.get("truncated", false)),
		"path_count": paths.size(),
		"entry_count": _int_value(state.get("entry_count", 0)),
		"source_bytes": _int_value(state.get("source_bytes", 0)),
		"class_index": class_index,
		"issues": _array(state.get("issues", [])),
	}


static func _collect_script_index_paths(
	directory_path: String,
	depth: int,
	state: Dictionary
) -> void:
	if _bool_value(state.get("truncated", false)):
		return
	var max_depth: int = _int_value(state.get("max_depth", 0))
	if max_depth <= 0 or depth > max_depth:
		_array(state.get("issues", [])).append(_issue(
			"script_class_index_depth_limit",
			"GDScript class_name 索引触及目录深度上限。",
			{"path": directory_path, "depth": depth, "limit": max_depth}
		))
		state["partial"] = true
		state["truncated"] = true
		return
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		_array(state.get("issues", [])).append(_issue(
			"script_class_index_directory_unreadable",
			"GDScript class_name 索引目录不存在或不可读。",
			{"path": directory_path}
		))
		state["partial"] = true
		return
	var directory_names: PackedStringArray = directory.get_directories()
	var file_names: PackedStringArray = directory.get_files()
	directory_names.sort()
	file_names.sort()
	for entry_name: String in directory_names:
		if not _consume_script_index_entry(directory_path.path_join(entry_name), state):
			return
		if directory.is_link(entry_name):
			_array(state.get("issues", [])).append(_issue(
				"script_class_index_link_rejected",
				"GDScript class_name 索引不跟随目录链接。",
				{"path": directory_path.path_join(entry_name)}
			))
			state["partial"] = true
			continue
		_collect_script_index_paths(directory_path.path_join(entry_name), depth + 1, state)
		if _bool_value(state.get("truncated", false)):
			return
	for file_name: String in file_names:
		var file_path: String = directory_path.path_join(file_name)
		if not _consume_script_index_entry(file_path, state):
			return
		if file_name.get_extension().to_lower() != "gd":
			continue
		var paths: PackedStringArray = _string_array(state.get("paths", PackedStringArray()))
		var max_paths: int = _int_value(state.get("max_paths", 0))
		if max_paths <= 0 or paths.size() >= max_paths:
			_array(state.get("issues", [])).append(_issue(
				"script_class_index_path_limit",
				"GDScript class_name 索引触及脚本数量上限。",
				{"path": file_path, "limit": max_paths}
			))
			state["partial"] = true
			state["truncated"] = true
			return
		var _script_path_added: bool = paths.append(file_path)
		state["paths"] = paths


static func _consume_script_index_entry(path: String, state: Dictionary) -> bool:
	var entry_count: int = _int_value(state.get("entry_count", 0)) + 1
	state["entry_count"] = entry_count
	var max_entries: int = _int_value(state.get("max_entries", 0))
	if max_entries > 0 and entry_count <= max_entries:
		return true
	_array(state.get("issues", [])).append(_issue(
		"script_class_index_entry_limit",
		"GDScript class_name 索引触及目录项上限。",
		{"path": path, "limit": max_entries}
	))
	state["partial"] = true
	state["truncated"] = true
	return false


static func _read_bounded_script_source(
	path: String,
	max_file_bytes: int,
	remaining_total_bytes: int
) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "script_source_unreadable", "size": -1}
	var size: int = file.get_length()
	if max_file_bytes <= 0 or size > max_file_bytes:
		file.close()
		return {"ok": false, "code": "script_source_file_limit", "size": size}
	if remaining_total_bytes < size:
		file.close()
		return {"ok": false, "code": "script_source_total_limit", "size": size}
	var source: String = file.get_as_text()
	file.close()
	return {"ok": true, "source": source, "size": size}


static func _analyze_gdscript_source(
	source: String,
	lexeme_regex: RegEx,
	identifier_regex: RegEx,
	static_load_regex: RegEx,
	extends_regex: RegEx
) -> Dictionary:
	var identifiers: Dictionary = {}
	var literal_records: Array[Dictionary] = []
	var code_tail: String = ""
	var previous_end: int = 0
	for match_result: RegExMatch in lexeme_regex.search_all(source):
		var code_segment: String = source.substr(
			previous_end,
			match_result.get_start() - previous_end
		)
		for identifier_match: RegExMatch in identifier_regex.search_all(code_segment):
			identifiers[identifier_match.get_string()] = true
		code_tail = _append_code_tail(code_tail, code_segment)
		var lexeme: String = match_result.get_string()
		if not lexeme.begins_with("#") and lexeme.length() >= 2:
			var literal: String = lexeme.substr(1, lexeme.length() - 2)
			if literal.begins_with("res://"):
				var static_dependency: bool = (
					static_load_regex.search(code_tail) != null
					or extends_regex.search(code_tail) != null
				)
				literal_records.append({
					"path": literal,
					"static_dependency": static_dependency,
					"context": code_tail.right(120).strip_edges(),
				})
			code_tail = _append_code_tail(code_tail, " ")
		else:
			code_tail = ""
		previous_end = match_result.get_end()
	var trailing_code: String = source.substr(previous_end)
	for identifier_match: RegExMatch in identifier_regex.search_all(trailing_code):
		identifiers[identifier_match.get_string()] = true
	return {
		"identifiers": _dictionary_keys_as_strings(identifiers),
		"literal_records": literal_records,
	}


static func _append_code_tail(existing: String, code_segment: String) -> String:
	var combined: String = existing + code_segment
	if combined.length() > 256:
		combined = combined.right(256)
	return combined


static func _append_script_to_queue(
	path: String,
	queue: PackedStringArray,
	queued_paths: Dictionary
) -> void:
	if queued_paths.has(path):
		return
	queued_paths[path] = true
	var _queued_path_added: bool = queue.append(path)


static func _dictionary_keys_as_strings(values: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values.keys():
		var _key_added: bool = result.append(str(value))
	result.sort()
	return result


static func _runtime_literal_rule_identity(script_path: String, literal: String) -> String:
	return "%s\u001f%s" % [script_path, literal]

static func _make_report(policy_path: String, preset_path: String, check_preset: bool) -> Dictionary:
	return {
		"schema_version": REPORT_SCHEMA_VERSION,
		"ok": false,
		"policy_id": "",
		"policy_path": policy_path,
		"policy_sha256": "",
		"preset_path": preset_path,
		"preset_check_enabled": check_preset,
		"features": PackedStringArray(),
		"roots": PackedStringArray(),
		"structure_dynamic_paths": PackedStringArray(),
		"content_resource_paths": PackedStringArray(),
		"dynamic_path_evidence": [],
		"raw_dependency_closure": PackedStringArray(),
		"closure": PackedStringArray(),
		"script_dependency_evidence": {},
		"runtime_literal_evidence": {},
		"raw_includes": PackedStringArray(),
		"raw_include_expanded_paths": PackedStringArray(),
		"font_remap_evidence": [],
		"dependency_partial": true,
		"dependency_truncated": true,
		"issues": [],
		"counts": {},
		"closure_sha256": "",
	}


static func _validate_policy(policy: Dictionary, report: Dictionary) -> void:
	if _int_value(policy.get("schema_version", 0)) != 1:
		_append_issue(report, "policy_schema_unsupported", "资源闭包策略 schema 不受支持。")
	for required_key: String in [
		"policy_id",
		"preset_name",
		"expected_custom_features",
		"enabled_extension_ids",
		"fixed_roots",
		"structure_roots",
		"content_manifests",
		"raw_includes",
		"font_remaps",
		"script_path_rules",
		"allowed_directory_literals",
		"runtime_literal_rules",
		"script_class_index_roots",
		"forbidden_paths",
		"dependency_extensions",
		"stable_strategy",
	]:
		if not policy.has(required_key):
			_append_issue(report, "policy_field_missing", "资源闭包策略缺少必需字段。", {
				"field": required_key,
			})
	if str(policy.get("policy_id", "")).strip_edges().is_empty():
		_append_issue(report, "policy_id_missing", "资源闭包策略必须声明 policy_id。")
	var strategy: Dictionary = _as_dictionary(policy.get("stable_strategy", {}))
	if str(strategy.get("unknown_runtime_literal_policy", "")) != "error":
		_append_issue(
			report,
			"unknown_runtime_literal_policy_not_strict",
			"正式包未知运行时资源文字策略必须为 error。"
		)


static func _validate_project_settings(
	policy: Dictionary,
	roots: PackedStringArray,
	report: Dictionary
) -> void:
	var expected_main_scene: String = str(ProjectSettings.get_setting(
		"application/run/main_scene",
		""
	))
	_require_root(expected_main_scene, "project_main_scene_not_rooted", roots, report)
	var project_installers: PackedStringArray = _variant_to_strings(ProjectSettings.get_setting(
		"gf/project/installers",
		PackedStringArray()
	))
	for installer_path: String in project_installers:
		_require_root(installer_path, "project_installer_not_rooted", roots, report)
	var release_font: String = str(ProjectSettings.get_setting(
		"gui/theme/custom_font.wechat_minigame_release",
		""
	))
	_require_root(release_font, "release_font_not_rooted", roots, report)
	var expected_extension_ids: PackedStringArray = _string_array(
		policy.get("enabled_extension_ids", [])
	)
	var actual_extension_ids: PackedStringArray = _variant_to_strings(
		_EXTENSION_SETTINGS.get_enabled_extension_ids()
	)
	if not _sets_equal(expected_extension_ids, actual_extension_ids):
		_append_issue(report, "enabled_extensions_mismatch", "启用的 GF 扩展与资源策略不一致。", {
			"expected": expected_extension_ids,
			"actual": actual_extension_ids,
		})


static func _collect_extension_installers(
	policy: Dictionary,
	roots: PackedStringArray,
	report: Dictionary
) -> void:
	var installer_paths: PackedStringArray = _variant_to_strings(
		_EXTENSION_SETTINGS.get_enabled_installer_paths()
	)
	var expected_count: int = _int_value(_as_dictionary(
		policy.get("stable_strategy", {})
	).get("expected_enabled_extension_count", -1), -1)
	if expected_count >= 0 and installer_paths.size() != expected_count:
		_append_issue(report, "extension_installer_count_mismatch", "GF 扩展 Installer 数量漂移。", {
			"expected": expected_count,
			"actual": installer_paths.size(),
		})
	for installer_path: String in installer_paths:
		_require_root(installer_path, "extension_installer_not_rooted", roots, report)


static func _collect_structure_roots(
	structure: Dictionary,
	roots: PackedStringArray,
	dynamic_paths: PackedStringArray,
	report: Dictionary
) -> void:
	for map_path: String in _string_array(structure.get("scene_preload_maps", [])):
		_append_unique(roots, map_path)
		var map_resource: Resource = ResourceLoader.load(map_path)
		if not map_resource is GFScenePreloadMap:
			_append_issue(report, "scene_preload_map_invalid", "场景预加载表无法加载。", {
				"path": map_path,
			})
			continue
		var preload_map: GFScenePreloadMap = map_resource
		_append_paths(dynamic_paths, preload_map.get_fixed_scene_paths())
		for entry: GFScenePreloadEntry in preload_map.entries:
			if entry == null:
				_append_issue(report, "scene_preload_entry_null", "场景预加载表包含空条目。", {
					"path": map_path,
				})
				continue
			_append_unique(dynamic_paths, entry.get_scene_path())
			_append_paths(dynamic_paths, entry.get_adjacent_scene_paths())

	for registry_value: Variant in _array(structure.get("resource_registries", [])):
		var registry_spec: Dictionary = _as_dictionary(registry_value)
		var registry_path: String = str(registry_spec.get("path", ""))
		var expansion: String = str(registry_spec.get("expansion", ""))
		_append_unique(roots, registry_path)
		var registry_resource: Resource = ResourceLoader.load(registry_path)
		if not registry_resource is GFResourceRegistry:
			_append_issue(report, "resource_registry_invalid", "GF 资源注册表无法加载。", {
				"path": registry_path,
			})
			continue
		var registry: GFResourceRegistry = registry_resource
		var registered_paths: PackedStringArray = registry.get_all_paths()
		_append_paths(dynamic_paths, registered_paths)
		if expansion == "ui_routes":
			for route_path: String in registered_paths:
				var route_resource: Resource = ResourceLoader.load(route_path)
				if not route_resource is GFUIRoute:
					_append_issue(report, "ui_route_invalid", "UI 路由资源无法加载。", {
						"path": route_path,
					})
					continue
				var route: GFUIRoute = route_resource
				_append_unique(dynamic_paths, route.scene_path)
		elif expansion != "resource_paths":
			_append_issue(report, "registry_expansion_unknown", "注册表展开策略不受支持。", {
				"path": registry_path,
				"expansion": expansion,
			})
	_append_paths(roots, dynamic_paths)


static func _collect_content_roots(
	manifest_paths: PackedStringArray,
	roots: PackedStringArray,
	content_paths: PackedStringArray,
	report: Dictionary
) -> void:
	var catalog: GFContentPackageCatalog = _CONTENT_PACKAGE_CATALOG.new()
	for manifest_path: String in manifest_paths:
		var manifest: GFContentPackageManifest = _CONTENT_PACKAGE_MANIFEST.load_from_path(
			manifest_path
		)
		if manifest == null:
			_append_issue(report, "content_manifest_invalid", "内容包 manifest 无法加载。", {
				"path": manifest_path,
			})
			continue
		if not catalog.add_manifest(manifest):
			_append_issue(report, "content_manifest_rejected", "内容包 manifest 被 catalog 拒绝。", {
				"path": manifest_path,
			})
	var graph_report: Dictionary = catalog.get_graph_report({"check_resource_exists": true})
	if not _bool_value(graph_report.get("ok", false)):
		_append_issue(report, "content_catalog_invalid", "GF 内容包目录校验失败。", {
			"summary": str(graph_report.get("summary", "")),
			"issues": graph_report.get("issues", []),
		})
	var plan: GFContentPackageExportPlan = _CONTENT_PACKAGE_EXPORT_PLAN.from_catalog(catalog, {
		"include_manifest": false,
		"include_resource_dependencies": false,
		"check_files": true,
	})
	var plan_report: Dictionary = plan.get_validation_report()
	if not _bool_value(plan_report.get("ok", false)):
		_append_issue(report, "content_export_plan_invalid", "GF 内容包导出计划校验失败。", {
			"summary": str(plan_report.get("summary", "")),
			"issues": plan_report.get("issues", []),
		})
	for entry: Dictionary in plan.entries:
		_append_unique(content_paths, str(entry.get("source_path", "")))
	_append_paths(roots, content_paths)


static func _validate_script_path_rules(
	rule_values: Array,
	features: PackedStringArray,
	roots: PackedStringArray,
	evidence: Array[Dictionary],
	report: Dictionary
) -> void:
	for rule_value: Variant in rule_values:
		var rule: Dictionary = _as_dictionary(rule_value)
		var script_path: String = str(rule.get("script_path", ""))
		var constant_name: String = str(rule.get("constant_name", ""))
		var include_features: PackedStringArray = _string_array(
			rule.get("include_features", [])
		)
		var expected_paths: PackedStringArray = _string_array(rule.get("expected_paths", []))
		var constants: Dictionary = _read_script_constants(script_path, _issues(report))
		if not constants.has(constant_name) and not constants.has(StringName(constant_name)):
			_append_issue(report, "dynamic_path_constant_missing", "动态资源路径常量不存在。", {
				"script_path": script_path,
				"constant_name": constant_name,
			})
			continue
		var actual_paths: PackedStringArray = _variant_to_strings(constants.get(
			constant_name,
			constants.get(StringName(constant_name), null)
		))
		if not _sets_equal(expected_paths, actual_paths):
			_append_issue(report, "dynamic_path_constant_drift", "动态资源路径常量与策略不一致。", {
				"script_path": script_path,
				"constant_name": constant_name,
				"expected": expected_paths,
				"actual": actual_paths,
			})
		var active: bool = include_features.is_empty() or _has_any(features, include_features)
		evidence.append({
			"script_path": script_path,
			"constant_name": constant_name,
			"paths": actual_paths,
			"include_features": include_features,
			"active": active,
		})
		if active:
			_append_paths(roots, actual_paths)


static func _validate_stable_counts(
	policy: Dictionary,
	roots: PackedStringArray,
	structural_dynamic_paths: PackedStringArray,
	content_paths: PackedStringArray,
	report: Dictionary
) -> void:
	var strategy: Dictionary = _as_dictionary(policy.get("stable_strategy", {}))
	_validate_count(
		"root_count_mismatch",
		"资源根数量漂移。",
		_int_value(strategy.get("expected_root_count", -1), -1),
		roots.size(),
		report
	)
	_validate_count(
		"structure_dynamic_count_mismatch",
		"结构化动态入口数量漂移。",
		_int_value(strategy.get("expected_structure_dynamic_count", -1), -1),
		structural_dynamic_paths.size(),
		report
	)
	_validate_count(
		"content_resource_count_mismatch",
		"内容包资源数量漂移。",
		_int_value(strategy.get("expected_content_resource_count", -1), -1),
		content_paths.size(),
		report
	)


static func _validate_count(
	code: String,
	message: String,
	expected: int,
	actual: int,
	report: Dictionary
) -> void:
	if expected >= 0 and actual != expected:
		_append_issue(report, code, message, {"expected": expected, "actual": actual})


static func _make_dependency_options(policy: Dictionary) -> Dictionary:
	var strategy: Dictionary = _as_dictionary(policy.get("stable_strategy", {}))
	return {
		"recursive": true,
		"include_root": true,
		"include_direct_dependencies": true,
		"extensions": _string_array(policy.get("dependency_extensions", [])),
		"excluded_paths": PackedStringArray(),
		"max_scan_depth": _int_value(strategy.get("max_dependency_depth", 64), 64),
		"max_dependency_paths": _int_value(
			strategy.get("max_dependency_paths", 20000),
			20000
		),
	}


static func _make_dependency_scan_order(roots: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for preferred_root: String in [
		"res://app/scenes/boot.tscn",
		"res://app/scripts/game_architecture_installer.gd",
	]:
		if roots.has(preferred_root):
			var _preferred_root_added: bool = result.append(preferred_root)
	for root_path: String in roots:
		_append_unique(result, root_path)
	return result


static func _validate_raw_includes(patterns: PackedStringArray) -> Dictionary:
	var normalized_patterns: PackedStringArray = PackedStringArray()
	var expanded_paths: PackedStringArray = PackedStringArray()
	var issues: Array[Dictionary] = []
	for raw_pattern: String in patterns:
		var pattern: String = _normalize_resource_pattern(raw_pattern)
		if pattern.is_empty():
			issues.append(_issue("raw_include_invalid", "raw include 路径无效。", {
				"path": raw_pattern,
			}))
			continue
		_append_unique(normalized_patterns, pattern)
		var matches: PackedStringArray = _expand_resource_pattern(pattern)
		if matches.is_empty():
			issues.append(_issue("raw_include_missing", "raw include 未匹配任何文件。", {
				"pattern": pattern,
			}))
		else:
			_append_paths(expanded_paths, matches)
	_sort_unique(normalized_patterns)
	_sort_unique(expanded_paths)
	return {
		"ok": issues.is_empty(),
		"patterns": normalized_patterns,
		"expanded_paths": expanded_paths,
		"issues": issues,
	}


static func _expand_resource_pattern(pattern: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not pattern.contains("*") and not pattern.contains("?"):
		if FileAccess.file_exists(pattern) or ResourceLoader.exists(pattern):
			var _literal_pattern_added: bool = result.append(pattern)
		return result
	var first_wildcard: int = pattern.length()
	for wildcard: String in ["*", "?"]:
		var index: int = pattern.find(wildcard)
		if index >= 0:
			first_wildcard = mini(first_wildcard, index)
	var slash_index: int = pattern.rfind("/", first_wildcard)
	if slash_index < "res://".length():
		return result
	var directory_path: String = pattern.substr(0, slash_index)
	var relative_pattern: String = pattern.substr(slash_index + 1)
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if file_name.match(relative_pattern):
			var _matched_path_added: bool = result.append(
				directory_path.path_join(file_name)
			)
	result.sort()
	return result


static func _validate_forbidden_paths(
	roots: PackedStringArray,
	closure: PackedStringArray,
	raw_paths: PackedStringArray,
	forbidden_values: Array,
	report: Dictionary
) -> void:
	var all_paths: PackedStringArray = roots.duplicate()
	_append_paths(all_paths, closure)
	_append_paths(all_paths, raw_paths)
	for path: String in all_paths:
		for forbidden_value: Variant in forbidden_values:
			var forbidden: Dictionary = _as_dictionary(forbidden_value)
			var kind: String = str(forbidden.get("kind", ""))
			var forbidden_path: String = str(forbidden.get("path", ""))
			var matched: bool = (
				path == forbidden_path
				if kind == "exact"
				else path == forbidden_path or path.begins_with(forbidden_path.path_join(""))
			)
			if matched:
				_append_issue(report, "forbidden_path_in_closure", "闭包包含禁止发布的路径。", {
					"path": path,
					"rule": forbidden,
				})
				break


static func _validate_paths_exist(paths: PackedStringArray, code: String, report: Dictionary) -> void:
	for path: String in paths:
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			_append_issue(report, code, "声明的资源路径不存在。", {"path": path})


static func _read_script_constants(script_path: String, issues: Array) -> Dictionary:
	var file: FileAccess = FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		issues.append(_issue("script_load_failed", "用于闭包审计的脚本无法读取。", {
			"path": script_path,
		}))
		return {}
	var source: String = file.get_as_text()
	file.close()
	var declaration_regex: RegEx = RegEx.new()
	var compile_error: Error = declaration_regex.compile(
		"(?m)^const[\\t ]+([A-Za-z_][A-Za-z0-9_]*)(?:[\\t ]*:[^=\\r\\n]+)?[\\t ]*=[\\t ]*"
	)
	if compile_error != OK:
		issues.append(_issue("script_constant_parser_failed", "动态路径常量解析器初始化失败。", {
			"path": script_path,
		}))
		return {}
	var matches: Array[RegExMatch] = declaration_regex.search_all(source)
	var result: Dictionary = {}
	for match_result: RegExMatch in matches:
		var constant_name: String = match_result.get_string(1)
		var expression_start: int = match_result.get_end()
		var expression: String = _read_constant_expression(source, expression_start)
		var parsed_value: Variant = _parse_constant_expression(expression, result)
		if parsed_value != null:
			result[constant_name] = parsed_value
	return result


static func _read_constant_expression(source: String, start_index: int) -> String:
	var depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	var index: int = start_index
	while index < source.length():
		var character: String = source.substr(index, 1)
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				in_string = false
		else:
			if character == '"':
				in_string = true
			elif character in ["[", "{", "("]:
				depth += 1
			elif character in ["]", "}", ")"]:
				depth = maxi(depth - 1, 0)
			elif (character == "\n" or character == "\r") and depth == 0:
				break
		index += 1
	return source.substr(start_index, index - start_index).strip_edges()


static func _parse_constant_expression(expression: String, known_constants: Dictionary) -> Variant:
	var string_regex: RegEx = RegEx.new()
	if string_regex.compile('"([^"\\r\\n]*)"') != OK:
		return null
	var string_matches: Array[RegExMatch] = string_regex.search_all(expression)
	if expression.begins_with("{"):
		var dictionary_result: Dictionary = {}
		var pair_regex: RegEx = RegEx.new()
		if pair_regex.compile('([A-Za-z_][A-Za-z0-9_]*|&?"[^"\\r\\n]+")\\s*:\\s*"([^"\\r\\n]*)"') != OK:
			return dictionary_result
		for pair_match: RegExMatch in pair_regex.search_all(expression):
			var raw_key: String = pair_match.get_string(1)
			var resolved_key: String = raw_key.trim_prefix("&").trim_prefix('"').trim_suffix('"')
			if known_constants.has(raw_key):
				resolved_key = str(known_constants[raw_key])
			dictionary_result[resolved_key] = pair_match.get_string(2)
		return dictionary_result
	if expression.begins_with("[") or expression.begins_with("PackedStringArray") or expression.begins_with("Array"):
		var array_result: PackedStringArray = PackedStringArray()
		for string_match: RegExMatch in string_matches:
			var _string_match_added: bool = array_result.append(
				string_match.get_string(1)
			)
		return array_result
	if string_matches.size() == 1:
		return string_matches[0].get_string(1)
	return null


static func _dependency_missing_paths(dependency_report: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for missing_value: Variant in _array(dependency_report.get("missing", [])):
		if missing_value is Dictionary:
			var missing: Dictionary = missing_value
			var path: String = str(missing.get("path", missing.get("dependency_path", "")))
			_append_unique(result, path)
		else:
			_append_unique(result, str(missing_value))
	_sort_unique(result)
	return result


static func _find_preset_section(config: ConfigFile, preset_name: String) -> String:
	for section: String in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			if str(config.get_value(section, "name", "")) == preset_name:
				return section
	return ""


static func _resource_patterns_to_export_filters(patterns: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for pattern: String in patterns:
		_append_unique(result, pattern.trim_prefix("res://"))
	_sort_unique(result)
	return result


static func _normalize_resource_pattern(path: String) -> String:
	var normalized: String = path.strip_edges().replace("\\", "/")
	if not normalized.begins_with("res://"):
		return ""
	if normalized.contains("..") or normalized.find("//", "res://".length()) >= 0:
		return ""
	return normalized


static func _parse_csv(value: String, trim_resource_prefix: bool) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for part: String in value.split(",", false):
		var normalized: String = part.strip_edges()
		if trim_resource_prefix:
			normalized = normalized.trim_prefix("res://")
		_append_unique(result, normalized)
	_sort_unique(result)
	return result


static func _argument_value(
	arguments: PackedStringArray,
	argument_name: String,
	default_value: String
) -> String:
	var index: int = arguments.find(argument_name)
	if index < 0 or index + 1 >= arguments.size():
		return default_value
	return arguments[index + 1]


static func _require_root(
	path: String,
	code: String,
	roots: PackedStringArray,
	report: Dictionary
) -> void:
	if path.is_empty():
		_append_issue(report, code, "项目设置声明的资源路径为空。")
	elif not roots.has(path):
		_append_issue(report, code, "项目设置声明的资源未进入固定根集合。", {"path": path})


static func _finalize_report(report: Dictionary) -> Dictionary:
	var roots: PackedStringArray = _string_array(report.get("roots", PackedStringArray()))
	var closure: PackedStringArray = _string_array(report.get("closure", PackedStringArray()))
	var raw_includes: PackedStringArray = _string_array(
		report.get("raw_includes", PackedStringArray())
	)
	var issues: Array = _array(report.get("issues", []))
	report["counts"] = {
		"roots": roots.size(),
		"structure_dynamic": _string_array(
			report.get("structure_dynamic_paths", PackedStringArray())
		).size(),
		"content_resources": _string_array(
			report.get("content_resource_paths", PackedStringArray())
		).size(),
		"raw_dependency_closure": _string_array(
			report.get("raw_dependency_closure", PackedStringArray())
		).size(),
		"closure": closure.size(),
		"raw_include_patterns": raw_includes.size(),
		"raw_include_files": _string_array(
			report.get("raw_include_expanded_paths", PackedStringArray())
		).size(),
		"issues": issues.size(),
	}
	var identity: Dictionary = {
		"schema_version": REPORT_SCHEMA_VERSION,
		"policy_id": str(report.get("policy_id", "")),
		"policy_sha256": str(report.get("policy_sha256", "")),
		"features": report.get("features", PackedStringArray()),
		"roots": roots,
		"closure": closure,
		"raw_includes": raw_includes,
		"font_remap_evidence": report.get("font_remap_evidence", []),
	}
	report["closure_sha256"] = JSON.stringify(identity, "", true).sha256_text()
	report["ok"] = (
		issues.is_empty()
		and not _bool_value(report.get("dependency_partial", true), true)
		and not _bool_value(report.get("dependency_truncated", true), true)
	)
	return report


static func _append_issue(
	report: Dictionary,
	code: String,
	message: String,
	details: Dictionary = {}
) -> void:
	_issues(report).append(_issue(code, message, details))


static func _issue(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"details": details.duplicate(true),
	}


static func _issues(report: Dictionary) -> Array:
	var value: Variant = report.get("issues", [])
	if value is Array:
		return value
	var result: Array = []
	report["issues"] = result
	return result


static func _merge_issues(report: Dictionary, values: Array) -> void:
	var target: Array = _issues(report)
	for value: Variant in values:
		target.append(_as_dictionary(value))


static func _array(value: Variant) -> Array:
	return value if value is Array else []


static func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _bool_value(value: Variant, default_value: bool = false) -> bool:
	if value is bool:
		var boolean_value: bool = value
		return boolean_value
	if value is int:
		var integer_value: int = value
		return integer_value != 0
	if value is float:
		var float_value: float = value
		return float_value != 0.0
	return default_value


static func _int_value(value: Variant, default_value: int = 0) -> int:
	if value is int:
		var integer_value: int = value
		return integer_value
	if value is bool:
		var boolean_value: bool = value
		return 1 if boolean_value else 0
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


static func _string_array(value: Variant) -> PackedStringArray:
	return _variant_to_strings(value)


static func _variant_to_strings(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is String or value is StringName:
		_append_unique(result, str(value))
	elif value is PackedStringArray:
		var packed_values: PackedStringArray = value
		_append_paths(result, packed_values)
	elif value is Array:
		for item: Variant in value:
			_append_unique(result, str(item))
	_sort_unique(result)
	return result


static func _variant_to_strings_preserve_order(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is String or value is StringName:
		var _string_added: bool = result.append(str(value))
	elif value is PackedStringArray:
		var packed_values: PackedStringArray = value
		result.append_array(packed_values)
	elif value is Array:
		for item: Variant in value:
			var _item_added: bool = result.append(str(item))
	return result


static func _append_paths(target: PackedStringArray, values: PackedStringArray) -> void:
	for value: String in values:
		_append_unique(target, value)


static func _append_unique(target: PackedStringArray, value: String) -> void:
	var normalized: String = value.strip_edges().replace("\\", "/")
	if not normalized.is_empty() and not target.has(normalized):
		var _normalized_added: bool = target.append(normalized)


static func _sort_unique(values: PackedStringArray) -> void:
	var unique: PackedStringArray = PackedStringArray()
	for value: String in values:
		_append_unique(unique, value)
	unique.sort()
	values.clear()
	values.append_array(unique)


static func _sets_equal(left: PackedStringArray, right: PackedStringArray) -> bool:
	return _set_difference(left, right).is_empty() and _set_difference(right, left).is_empty()


static func _set_difference(left: PackedStringArray, right: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: String in left:
		if not right.has(value):
			var _difference_added: bool = result.append(value)
	result.sort()
	return result


static func _has_any(left: PackedStringArray, right: PackedStringArray) -> bool:
	for value: String in right:
		if left.has(value):
			return true
	return false
