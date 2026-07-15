## 验证项目目录结构持续满足 GF profile，并将 warning 也作为门禁失败。
extends GutTest


# --- 常量 ---

const PROFILE_PATH: String = "res://gf_project_profile.json"


# --- 测试用例 ---

func test_project_layout_matches_gf_profile_without_warnings() -> void:
	var validator: GFProjectLayoutValidator = GFProjectLayoutValidator.new()
	var report: Dictionary = validator.validate_profile_path(PROFILE_PATH, {
		"root_path": "res://",
		"include_hidden": false,
		"max_scanned_files": 50000,
		"max_scanned_directories": 20000,
		"max_scan_depth": 64,
	})
	var issue_lines: PackedStringArray = _format_issue_lines(report)

	assert_true(
		GFVariantData.get_option_bool(report, "success"),
		"项目目录必须满足 GF profile：\n%s" % "\n".join(issue_lines)
	)
	assert_true(
		GFVariantData.get_option_int(report, "warning_count") == 0,
		"GF 项目布局 warning 也必须清零：\n%s" % "\n".join(issue_lines)
	)


# --- 私有/辅助方法 ---

func _format_issue_lines(report: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for issue_value: Variant in GFVariantData.get_option_array(report, "issues"):
		var issue: Dictionary = GFVariantData.as_dictionary(issue_value)
		var _appended: bool = result.append("[%s] %s %s: %s" % [
			GFVariantData.get_option_string(issue, "severity"),
			GFVariantData.get_option_string(issue, "kind"),
			GFVariantData.get_option_string(issue, "path"),
			GFVariantData.get_option_string(issue, "message"),
		])
	return result
