## 验证微信正式包资源闭包、字体替换与 fail-closed 依赖审计。
extends GutTest


# --- 常量 ---

const _POLICY_PATH: String = "res://tools/wechat_minigame/release_resource_policy.json"
const _PRESET_PATH: String = "res://export_presets.cfg"


# --- 测试用例 ---

func test_release_closure_and_preset_are_exact_and_complete() -> void:
	var report: Dictionary = WeChatMinigameReleaseResourceClosure.build_report(
		_POLICY_PATH,
		_PRESET_PATH,
		true
	)
	assert_true(
		_bool_value(report.get("ok", false)),
		"微信正式资源闭包必须通过：%s" % JSON.stringify(report.get("issues", []))
	)
	assert_false(_bool_value(report.get("dependency_partial", true), true))
	assert_false(_bool_value(report.get("dependency_truncated", true), true))
	assert_true(str(report.get("closure_sha256", "")).length() == 64)
	assert_true(
		_int_value(report.get("schema_version", 0)) == 1,
		"资源闭包 schema 版本必须保持为 1。"
	)
	assert_true(
		str(report.get("policy_id", ""))
		== "wechat-minigame-release-resource-closure-v1",
		"资源闭包 policy ID 必须匹配正式策略。"
	)
	assert_true(
		str(report.get("policy_path", "")) == _POLICY_PATH,
		"资源闭包必须绑定正式策略路径。"
	)
	assert_true(
		str(report.get("policy_sha256", ""))
		== FileAccess.get_sha256(_POLICY_PATH).to_lower(),
		"资源闭包必须绑定正式策略哈希。"
	)

	var counts: Dictionary = report.get("counts", {})
	assert_true(
		_int_value(counts.get("roots", -1), -1) == 106,
		"资源闭包根数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("structure_dynamic", -1), -1) == 44,
		"动态结构资源数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("content_resources", -1), -1) == 39,
		"内容资源数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("raw_dependency_closure", -1), -1) == 813,
		"原始依赖闭包数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("closure", -1), -1) == 812,
		"正式资源闭包数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("raw_include_patterns", -1), -1) == 18,
		"原始 include pattern 数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("raw_include_files", -1), -1) == 19,
		"原始 include file 数量必须保持稳定。"
	)
	assert_true(
		_int_value(counts.get("issues", -1), -1) == 0,
		"正式资源闭包不得包含问题。"
	)

	var roots: PackedStringArray = _to_strings(report.get("roots", []))
	var sorted_roots: PackedStringArray = roots.duplicate()
	sorted_roots.sort()
	assert_true(roots == sorted_roots, "显式资源根必须按 Unicode 码点稳定排序。")
	assert_true(_dedupe(roots).size() == roots.size(), "显式资源根不得重复。")
	assert_true(roots.has("res://app/scenes/boot.tscn"))
	assert_true(roots.has("res://app/scripts/boot_runtime.gd"))
	assert_true(roots.has("res://features/navigation/resources/scene_preload_map.tres"))
	assert_true(roots.has("res://features/themes/resources/themes/game/halftone_atlas_theme.tres"))
	assert_true(roots.has("res://features/themes/resources/themes/game/quiet_paper/quiet_paper_theme.tres"))
	assert_true(roots.has("res://features/asset_library/resources/shaders/transition/print_sheet_transition.gdshader"))
	assert_false(roots.has("res://features/platform_runtime/scenes/smoke_test/platform_smoke_test.tscn"))

	var closure: PackedStringArray = _to_strings(report.get("closure", []))
	assert_true(closure.has("res://shared/assets/fonts/ui_sans_regular.tres"))
	assert_true(closure.has("res://shared/assets/fonts/ui_sans_display.tres"))
	assert_true(closure.has("res://shared/assets/fonts/ui_sans_wechat_release.tres"))
	assert_true(closure.has("res://shared/assets/fonts/wechat_release_sans_subset.ttf"))
	assert_true(closure.has("res://shared/assets/fonts/ui_print_display.tres"))
	assert_true(closure.has("res://shared/assets/fonts/dm_serif_display_regular.ttf"))
	assert_false(closure.has("res://shared/assets/fonts/noto_sans_sc_variable.ttf"))
	for path: String in closure:
		assert_false(path.begins_with("res://tests/"), "测试资源不得进入正式闭包：%s" % path)
		assert_false(path.begins_with("res://tools/"), "项目工具不得进入正式闭包：%s" % path)
		assert_false(path.begins_with("res://addons/gf/tools/"), "GF 工具不得进入正式闭包：%s" % path)
		assert_false(path.begins_with("res://addons/gf/kernel/editor/"), "GF 编辑器代码不得进入正式闭包：%s" % path)
		assert_false(path.begins_with("res://features/diagnostics/"), "开发诊断不得进入正式闭包：%s" % path)

	var raw_includes: PackedStringArray = _to_strings(report.get("raw_includes", []))
	assert_true(raw_includes.has("res://addons/gf/extensions/save/gf_extension.json"))
	assert_true(raw_includes.has("res://features/themes/resources/gf_content_package.json"))
	assert_true(raw_includes.has("res://features/asset_library/resources/licenses/*"))
	assert_true(raw_includes.has("res://shared/assets/fonts/dm_serif_display_ofl.txt"))

	var preset: Dictionary = report.get("preset", {})
	assert_true(_bool_value(preset.get("ok", false)))
	assert_true(
		str(preset.get("section", "")) == "preset.3",
		"正式资源闭包必须绑定微信正式导出预设。"
	)
	var script_evidence: Dictionary = report.get("script_dependency_evidence", {})
	assert_true(_bool_value(script_evidence.get("ok", false)))
	assert_false(_bool_value(script_evidence.get("partial", true), true))
	assert_false(_bool_value(script_evidence.get("truncated", true), true))
	assert_true(_int_value(script_evidence.get("scripts_scanned", 0)) >= 600)
	assert_true(_int_value(script_evidence.get("paths_added", 0)) >= 500)
	var literal_evidence: Dictionary = report.get("runtime_literal_evidence", {})
	assert_true(_bool_value(literal_evidence.get("ok", false)))
	assert_true(
		_int_value(literal_evidence.get("allowed_directory_count", -1), -1) == 3,
		"运行时字面量允许目录数量必须保持稳定。"
	)
	assert_true(
		_int_value(literal_evidence.get("observed_literal_count", -1), -1) == 306,
		"运行时字面量观测数量必须保持稳定。"
	)
	assert_true(
		_int_value(literal_evidence.get("literal_count", -1), -1) == 306,
		"运行时资源字面量数量必须保持稳定。"
	)
	assert_true(
		_int_value(literal_evidence.get("explicit_rule_count", -1), -1) == 20,
		"运行时字面量显式规则数量必须保持稳定。"
	)
	var covered_counts: Dictionary = _dictionary_value(
		literal_evidence.get("covered_counts", {})
	)
	assert_true(
		_int_value(covered_counts.get("explicit_rule", -1), -1) == 34,
		"显式规则覆盖数量必须保持稳定。"
	)
	assert_true(_int_value(literal_evidence.get("literal_count", 0)) > 250)


func test_identity_evidence_is_minimal_complete_and_json_safe() -> void:
	var report: Dictionary = WeChatMinigameReleaseResourceClosure.build_report(
		_POLICY_PATH,
		_PRESET_PATH,
		true
	)
	var evidence: Dictionary = WeChatMinigameReleaseResourceClosure.make_identity_evidence(report)
	assert_true(evidence.size() == 11, "身份凭据必须保持最小且字段完整。")
	assert_true(
		_int_value(evidence.get("schema_version", 0)) == 1,
		"身份凭据 schema 版本必须保持为 1。"
	)
	assert_true(_bool_value(evidence.get("ok", false)))
	assert_true(
		str(evidence.get("policy_id", ""))
		== "wechat-minigame-release-resource-closure-v1",
		"身份凭据必须绑定正式资源闭包策略。"
	)
	assert_true(
		str(evidence.get("policy_path", ""))
		== "tools/wechat_minigame/release_resource_policy.json",
		"身份凭据必须使用项目相对策略路径。"
	)
	assert_true(
		str(evidence.get("policy_sha256", ""))
		== FileAccess.get_sha256(_POLICY_PATH).to_lower(),
		"身份凭据必须绑定正式策略哈希。"
	)
	assert_true(
		str(evidence.get("closure_sha256", ""))
		== str(report.get("closure_sha256", "")),
		"身份凭据必须绑定本次资源闭包哈希。"
	)
	assert_true(_int_value(evidence.get("full_dependency_scan_count", 0)) > 0)
	assert_false(_bool_value(evidence.get("dependency_partial", true), true))
	assert_false(_bool_value(evidence.get("dependency_truncated", true), true))
	assert_true(
		_dictionary_value(evidence.get("counts", {}))
		== _dictionary_value(report.get("counts", {})),
		"身份凭据必须保留完整闭包计数。"
	)
	assert_true(_array_value(evidence.get("issues", [])).is_empty())
	assert_true(JSON.parse_string(JSON.stringify(evidence)) is Dictionary)


func test_missing_dependency_report_fails_closed() -> void:
	var root_path: String = "res://app/scenes/boot.tscn"
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.evaluate_dependency_reports(
		PackedStringArray([root_path]),
		{}
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_bool_value(result.get("partial", false)))
	assert_true(_has_issue(result, "dependency_report_missing"))


func test_missing_dependency_path_fails_closed() -> void:
	var root_path: String = "res://app/scenes/boot.tscn"
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.evaluate_dependency_reports(
		PackedStringArray([root_path]),
		{
			root_path: {
				"ok": false,
				"paths": PackedStringArray([root_path]),
				"missing": [{"path": "res://missing/runtime_resource.tres"}],
				"limit_reached": false,
				"depth_limit_reached": false,
				"partial": false,
				"truncated": false,
			}
		}
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_bool_value(result.get("partial", false)))
	assert_true(_has_issue(result, "dependency_missing"))


func test_every_incomplete_dependency_signal_fails_closed() -> void:
	var root_path: String = "res://app/scenes/boot.tscn"
	for incomplete_field: String in PackedStringArray([
		"limit_reached",
		"depth_limit_reached",
		"partial",
		"truncated",
	]):
		var dependency_report: Dictionary = {
			"ok": true,
			"paths": PackedStringArray([root_path]),
			"missing": [],
			"limit_reached": false,
			"depth_limit_reached": false,
			"partial": false,
			"truncated": false,
		}
		dependency_report[incomplete_field] = true
		var result: Dictionary = WeChatMinigameReleaseResourceClosure.evaluate_dependency_reports(
			PackedStringArray([root_path]),
			{root_path: dependency_report}
		)
		assert_false(_bool_value(result.get("ok", true), true), incomplete_field)
		assert_true(_bool_value(result.get("partial", false)), incomplete_field)
		assert_true(_has_issue(result, "dependency_scan_incomplete"), incomplete_field)
		if incomplete_field in ["limit_reached", "depth_limit_reached", "truncated"]:
			assert_true(_bool_value(result.get("truncated", false)), incomplete_field)


func test_unhealthy_dependency_report_without_missing_paths_fails_closed() -> void:
	var root_path: String = "res://app/scenes/boot.tscn"
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.evaluate_dependency_reports(
		PackedStringArray([root_path]),
		{
			root_path: {
				"ok": false,
				"paths": PackedStringArray([root_path]),
				"missing": [],
				"limit_reached": false,
				"depth_limit_reached": false,
				"partial": false,
				"truncated": false,
				"summary": "unknown dependency state",
			}
		}
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_bool_value(result.get("partial", false)))
	assert_true(_has_issue(result, "dependency_report_unhealthy"))


func test_untracked_runtime_resource_literal_fails_closed() -> void:
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[{
			"script_path": "res://app/scripts/untracked_probe.gd",
			"path": "res://app/scenes/boot.tscn",
			"static_dependency": false,
			"context": "const UNTRACKED_PATH =",
		}],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray()
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_has_issue(result, "runtime_resource_literal_untracked"))


func test_allowed_directory_literal_is_exact_and_cannot_cover_descendants() -> void:
	var allowed_path: String = "res://features/themes/resources"
	var descendant_path: String = (
		"res://features/themes/resources/themes/game/halftone_atlas_theme.tres"
	)
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[
			{
				"script_path": "res://app/scripts/directory_probe.gd",
				"path": allowed_path,
				"static_dependency": false,
				"context": "const CONTENT_ROOT =",
			},
			{
				"script_path": "res://app/scripts/directory_probe.gd",
				"path": descendant_path,
				"static_dependency": false,
				"context": "const UNDECLARED_RESOURCE =",
			},
		],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray([allowed_path])
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_has_issue(result, "runtime_resource_literal_untracked"))
	assert_false(_has_issue(result, "allowed_directory_literal_unused"))


func test_dynamic_runtime_resource_literal_fails_closed() -> void:
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[{
			"script_path": "res://app/scripts/dynamic_probe.gd",
			"path": "res://features/themes/resources/%s.tres",
			"static_dependency": false,
			"context": "const DYNAMIC_PATH =",
		}],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray()
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_has_issue(result, "runtime_resource_literal_dynamic"))


func test_framework_and_space_literals_are_not_implicitly_allowed() -> void:
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[
			{
				"script_path": "res://addons/gf/kernel/core/gf.gd",
				"path": "res://addons/gf/runtime missing.tres",
				"static_dependency": false,
				"context": "ResourceLoader.load(candidate_path)",
			},
			{
				"script_path": "res://app/scripts/boot_runtime.gd",
				"path": "res://features/themes/resources/missing file.tres",
				"static_dependency": false,
				"context": "load(candidate_path)",
			},
		],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray()
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(
		_issue_count(result, "runtime_resource_literal_untracked") == 2,
		"两个未跟踪运行时资源字面量都必须被报告。"
	)


func test_runtime_literal_rule_is_exact_and_counted() -> void:
	var script_path: String = "res://tools/wechat_minigame_release_resource_closure.gd"
	var literal: String = "res://semantic token, not a resource"
	var rule: Dictionary = {
		"script_path": script_path,
		"literal": literal,
		"expected_count": 1,
		"kind": "test_semantic_token",
		"reason": "Unit-test proof of exact exception matching.",
	}
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[{
			"script_path": script_path,
			"path": literal,
			"static_dependency": false,
			"context": "test",
		}],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray(),
		[rule]
	)
	assert_true(_bool_value(result.get("ok", false)))
	rule["expected_count"] = 2
	var count_mismatch: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[{
			"script_path": script_path,
			"path": literal,
			"static_dependency": false,
			"context": "test",
		}],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray(),
		[rule]
	)
	assert_false(_bool_value(count_mismatch.get("ok", true), true))
	assert_true(_has_issue(count_mismatch, "runtime_literal_rule_count_mismatch"))


func test_broad_allowed_directory_literal_is_rejected() -> void:
	var result: Dictionary = WeChatMinigameReleaseResourceClosure.audit_runtime_resource_literals(
		[],
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
		PackedStringArray(["res://features"])
	)
	assert_false(_bool_value(result.get("ok", true), true))
	assert_true(_has_issue(result, "allowed_directory_literal_too_broad"))


func test_export_file_literal_is_sorted_and_stable() -> void:
	assert_true(
		WeChatMinigameReleaseResourceClosure.make_export_files_literal(PackedStringArray([
			"res://z.tres",
			"res://a.tres",
			"res://z.tres",
		])) == 'PackedStringArray("res://a.tres", "res://z.tres")',
		"导出文件字面量必须排序并去重。"
	)


func test_preset_exact_exclusion_cannot_remove_raw_manifest() -> void:
	var manifest_path: String = "res://addons/gf/extensions/save/gf_extension.json"
	var accepted: Dictionary = _check_raw_include_exclusion(manifest_path, "")
	assert_true(_bool_value(accepted.get("ok", false)))
	var rejected: Dictionary = _check_raw_include_exclusion(
		manifest_path,
		manifest_path.trim_prefix("res://")
	)
	assert_false(_bool_value(rejected.get("ok", true), true))
	assert_true(_has_issue(rejected, "preset_excludes_closure_path"))


func test_preset_wildcard_exclusion_cannot_remove_expanded_raw_license() -> void:
	var license_path: String = (
		"res://features/asset_library/resources/licenses/kenney_pattern_pack_2.txt"
	)
	var accepted: Dictionary = _check_raw_include_exclusion(license_path, "")
	assert_true(_bool_value(accepted.get("ok", false)))
	var rejected: Dictionary = _check_raw_include_exclusion(
		license_path,
		"features/asset_library/resources/licenses/*"
	)
	assert_false(_bool_value(rejected.get("ok", true), true))
	assert_true(_has_issue(rejected, "preset_excludes_closure_path"))


# --- 私有/辅助方法 ---

func _check_raw_include_exclusion(raw_path: String, exclude_filter: String) -> Dictionary:
	var fixture_path: String = "user://wechat_release_resource_closure_preset_fixture.cfg"
	var preset_name: String = "Raw Include Exclusion Fixture"
	var root_paths: PackedStringArray = PackedStringArray(["res://app/scenes/boot.tscn"])
	var include_pattern: String = (
		raw_path.get_base_dir().path_join("*")
		if raw_path.get_extension() == "txt"
		else raw_path
	)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("preset.0", "name", preset_name)
	config.set_value("preset.0", "custom_features", "wechat_minigame_release")
	config.set_value("preset.0", "export_filter", "resources")
	config.set_value("preset.0", "export_files", root_paths)
	config.set_value("preset.0", "include_filter", include_pattern.trim_prefix("res://"))
	config.set_value("preset.0", "exclude_filter", exclude_filter)
	var save_error: Error = config.save(fixture_path)
	assert_true(save_error == OK, "应能写入隔离的导出预设测试夹具。")
	if save_error != OK:
		return {"ok": false, "issues": []}
	var report: Dictionary = WeChatMinigameReleaseResourceClosure.check_export_preset(
		fixture_path,
		preset_name,
		PackedStringArray(["wechat_minigame_release"]),
		root_paths,
		PackedStringArray([include_pattern]),
		root_paths,
		PackedStringArray([raw_path])
	)
	var remove_error: Error = DirAccess.remove_absolute(fixture_path)
	assert_true(remove_error == OK, "应能移除导出预设测试夹具。")
	return report


func _has_issue(report: Dictionary, expected_code: String) -> bool:
	for issue_value: Variant in _array_value(report.get("issues", [])):
		var issue: Dictionary = _dictionary_value(issue_value)
		if str(issue.get("code", "")) == expected_code:
			return true
	return false


func _issue_count(report: Dictionary, expected_code: String) -> int:
	var result: int = 0
	for issue_value: Variant in _array_value(report.get("issues", [])):
		var issue: Dictionary = _dictionary_value(issue_value)
		if str(issue.get("code", "")) == expected_code:
			result += 1
	return result


func _array_value(value: Variant) -> Array:
	if value is Array:
		var array_value: Array = value
		return array_value
	return []


func _dictionary_value(value: Variant) -> Dictionary:
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return dictionary_value
	return {}


func _bool_value(value: Variant, default_value: bool = false) -> bool:
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


func _int_value(value: Variant, default_value: int = 0) -> int:
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


func _to_strings(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is PackedStringArray:
		var packed_value: PackedStringArray = value
		return packed_value.duplicate()
	if value is Array:
		for item: Variant in value:
			var _item_added: bool = result.append(str(item))
	return result


func _dedupe(values: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: String in values:
		if not result.has(value):
			var _value_added: bool = result.append(value)
	return result
