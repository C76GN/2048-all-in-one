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
	var report_directory: String = REPORT_PATH.get_base_dir()
	var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(report_directory)
	)
	if mkdir_result != OK:
		push_error("[ProjectLayout] 无法创建报告目录：%s。" % report_directory)
		return mkdir_result
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[ProjectLayout] 无法写入报告：%s。" % REPORT_PATH)
		return FileAccess.get_open_error()
	var stored: bool = file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	return OK if stored else ERR_FILE_CANT_WRITE


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
