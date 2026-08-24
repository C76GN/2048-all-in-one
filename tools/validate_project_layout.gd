## 使用项目 profile 运行 GFProjectLayoutAnalyzer，并写入机器可读报告。
extends SceneTree


# --- 常量 ---

const PROFILE_PATH: String = "res://gf_project_profile.json"
const REPORT_PATH: String = "res://build/project_layout_report.json"


# --- Godot 生命周期方法 ---

func _init() -> void:
	var analyzer: GFProjectLayoutAnalyzer = GFProjectLayoutAnalyzer.new()
	var report: Dictionary = analyzer.analyze_profile_path(PROFILE_PATH, {
		"root_path": "res://",
	})
	var resource_reference_report: Dictionary = (
		ProjectResourceReferenceValidator.validate_project_resources()
	)
	_merge_resource_reference_report(report, resource_reference_report)
	var write_error: Error = _write_report(report)
	var is_clean: bool = (
		write_error == OK
		and
		GFVariantData.get_option_int(report, "schema_version") == 1
		and GFVariantData.get_option_string(report, "kind") == "project_layout_analysis"
		and GFVariantData.get_option_string(report, "evaluation_status") == "complete"
		and GFVariantData.get_option_bool(report, "input_complete")
		and GFVariantData.get_option_bool(report, "evaluation_complete")
		and GFVariantData.get_option_bool(report, "success")
		and GFVariantData.get_option_bool(resource_reference_report, "success")
		and GFVariantData.get_option_int(report, "warning_count") == 0
	)
	_print_summary(report, is_clean)
	quit(0 if is_clean else 1)


# --- 私有/辅助方法 ---

func _merge_resource_reference_report(
	report: Dictionary,
	resource_reference_report: Dictionary
) -> void:
	report["resource_reference_validation"] = resource_reference_report
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	issues.append_array(GFVariantData.get_option_array(resource_reference_report, "issues"))
	report["issues"] = issues
	var resource_error_count: int = GFVariantData.get_option_int(
		resource_reference_report,
		"error_count"
	)
	report["error_count"] = (
		GFVariantData.get_option_int(report, "error_count") + resource_error_count
	)
	report["success"] = (
		GFVariantData.get_option_bool(report, "success")
		and GFVariantData.get_option_bool(resource_reference_report, "success")
	)

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
	var resource_report: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"resource_reference_validation"
	)
	print("%s profile=%s files=%d directories=%d refs=%d errors=%d warnings=%d" % [
		summary_prefix,
		GFVariantData.get_option_string(report, "profile_id"),
		GFVariantData.get_option_int(report, "file_count"),
		GFVariantData.get_option_int(report, "directory_count"),
		GFVariantData.get_option_int(resource_report, "reference_count"),
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
