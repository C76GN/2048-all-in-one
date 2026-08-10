## 使用项目 profile 运行 GFProjectLayoutValidator，并写入机器可读报告。
extends SceneTree


# --- 常量 ---

const PROFILE_PATH: String = "res://gf_project_profile.json"
const REPORT_PATH: String = "res://build/project_layout_report.json"


# --- Godot 生命周期方法 ---

func _init() -> void:
	var validator: GFProjectLayoutValidator = GFProjectLayoutValidator.new()
	var report: Dictionary = validator.validate_profile_path(PROFILE_PATH, {
		"root_path": "res://",
		"include_hidden": false,
		"max_scanned_files": 50000,
		"max_scanned_directories": 20000,
		"max_scan_depth": 64,
	})
	var write_error: Error = _write_report(report)
	var is_clean: bool = (
		write_error == OK
		and
		GFVariantData.get_option_bool(report, "success")
		and GFVariantData.get_option_int(report, "warning_count") == 0
	)
	_print_summary(report, is_clean)
	quit(0 if is_clean else 1)


# --- 私有/辅助方法 ---

func _write_report(report: Dictionary) -> Error:
	var artifact_report: Dictionary = GFGeneratedArtifactReport.save_text(
		REPORT_PATH,
		JSON.stringify(report, "\t") + "\n",
		{
			"allowed_roots": PackedStringArray(["res://build"]),
			"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED,
			"generator_id": "ProjectLayoutValidation",
			"source_id": "gf_project_profile",
			"scan_filesystem": false,
			"label": "ProjectLayout",
		}
	)
	return GFGeneratedArtifactReport.get_error_code(artifact_report)


func _print_summary(report: Dictionary, succeeded: bool) -> void:
	var summary_prefix: String = "Project layout:" if succeeded else "Project layout failed:"
	print("%s profile=%s files=%d directories=%d errors=%d warnings=%d" % [
		summary_prefix,
		GFVariantData.get_option_string(report, "profile_id"),
		GFVariantData.get_option_int(report, "file_count"),
		GFVariantData.get_option_int(report, "directory_count"),
		GFVariantData.get_option_int(report, "error_count"),
		GFVariantData.get_option_int(report, "warning_count"),
	])
	for issue_value: Variant in GFVariantData.get_option_array(report, "issues"):
		var issue: Dictionary = GFVariantData.as_dictionary(issue_value)
		print("[%s] %s %s: %s" % [
			GFVariantData.get_option_string(issue, "severity"),
			GFVariantData.get_option_string(issue, "kind"),
			GFVariantData.get_option_string(issue, "path"),
			GFVariantData.get_option_string(issue, "message"),
		])
