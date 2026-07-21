## PurgeRejectedAssets: 从项目评审库清除拒绝素材并登记源导入排除身份。
class_name PurgeRejectedAssets
extends SceneTree


# --- 常量 ---

const REVIEW_CATALOG_PROVIDER_SCRIPT = preload(
	"res://features/asset_library/scripts/catalog/game_asset_review_catalog_source_provider.gd"
)
const SOURCE_EXCLUSION_INDEX_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_source_exclusion_index.gd"
)
const SOURCE_PACK_ROOT: String = "res://features/asset_library/resources/source_packs"
const REVIEW_RECORD_ROOT: String = "res://features/asset_library/resources/review/records"
const SOURCE_EXCLUSION_PATH: String = "res://features/asset_library/resources/source_exclusions.json"
const REPORT_PATH: String = "res://build/rejected_asset_purge_report.json"
const REFERENCE_SCAN_ROOTS: PackedStringArray = [
	"res://app",
	"res://features",
	"res://shared",
	"res://project.godot",
]
const REFERENCE_SCAN_IGNORED_ROOTS: PackedStringArray = [
	SOURCE_PACK_ROOT,
	REVIEW_RECORD_ROOT,
	"res://features/asset_library/resources/reports",
]


# --- Godot 生命周期方法 ---

func _init() -> void:
	var report: Dictionary = run_purge()
	var ok: bool = GFVariantData.get_option_int(report, "error_count") == 0
	print("Rejected asset purge: %d matched, %d assets removed, %d records removed, %d issues" % [
		GFVariantData.get_option_int(report, "matched_count"),
		GFVariantData.get_option_int(report, "removed_asset_count"),
		GFVariantData.get_option_int(report, "removed_record_count"),
		GFVariantData.get_option_int(report, "issue_count"),
	])
	quit(0 if ok else 1)


# --- 公共方法 ---

## 清除所有 rejected 评审项，并返回机器可读报告。
func run_purge() -> Dictionary:
	var report: Dictionary = _make_report()
	var exclusion_index: AssetSourceExclusionIndex = SOURCE_EXCLUSION_INDEX_SCRIPT.new()
	var load_result: Error = exclusion_index.load_from_path(SOURCE_EXCLUSION_PATH)
	if load_result != OK:
		_add_issue(report, "source_exclusion_load_failed", SOURCE_EXCLUSION_PATH, load_result)
		_finalize_report(report)
		_write_report(report)
		return report

	var candidates: Array[Dictionary] = _collect_rejected_candidates(report)
	report["matched_count"] = candidates.size()
	_validate_candidates_are_unreferenced(candidates, report)
	if GFVariantData.get_option_int(report, "error_count") > 0:
		_finalize_report(report)
		_write_report(report)
		return report
	for candidate: Dictionary in candidates:
		var add_result: Error = exclusion_index.add_exclusion(
			GFVariantData.get_option_string(candidate, "source_pack_id"),
			GFVariantData.get_option_string(candidate, "relative_path"),
			GFVariantData.get_option_string(candidate, "sha256")
		)
		if add_result != OK:
			_add_issue(
				report,
				"source_exclusion_add_failed",
				GFVariantData.get_option_string(candidate, "record_path"),
				add_result
			)
	if GFVariantData.get_option_int(report, "error_count") > 0:
		_finalize_report(report)
		_write_report(report)
		return report

	var save_result: Error = exclusion_index.save_to_path(SOURCE_EXCLUSION_PATH)
	if save_result != OK:
		_add_issue(report, "source_exclusion_save_failed", SOURCE_EXCLUSION_PATH, save_result)
		_finalize_report(report)
		_write_report(report)
		return report
	report["exclusion_count"] = exclusion_index.size()

	for candidate: Dictionary in candidates:
		_remove_candidate(candidate, report)
	_finalize_report(report)
	_write_report(report)
	return report


# --- 私有/辅助方法 ---

func _collect_rejected_candidates(report: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var provider: GameAssetReviewCatalogSourceProvider = (
		REVIEW_CATALOG_PROVIDER_SCRIPT.new()
	)
	var _configured: GFAssetCatalogSourceProvider = provider.configure_review_records(
		REVIEW_RECORD_ROOT,
		&"asset_review_purge"
	)
	var catalog: GFAssetCatalog = provider.build_catalog()
	for asset_id: String in catalog.get_all_ids():
		var entry: GFAssetCatalogEntry = catalog.get_entry(StringName(asset_id))
		if entry == null:
			continue
		var record_path: String = GFVariantData.get_option_string(
			entry.metadata,
			"record_path"
		)
		var loaded: Resource = ResourceLoader.load(
			record_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		)
		if loaded == null:
			continue
		if GFVariantData.to_string_name(loaded.get("review_status")) != &"rejected":
			continue
		var candidate: Dictionary = _make_candidate(loaded, record_path)
		if not GFVariantData.get_option_bool(candidate, "valid"):
			_add_issue(report, "invalid_rejected_record", record_path, ERR_INVALID_DATA)
			continue
		result.append(candidate)
	return result


func _validate_candidates_are_unreferenced(
	candidates: Array[Dictionary],
	report: Dictionary
) -> void:
	if candidates.is_empty():
		return
	var targets: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		targets.append({
			"id": GFVariantData.get_option_string(candidate, "asset_id"),
			"root_path": GFVariantData.get_option_string(candidate, "library_path"),
		})
	var scan_report: Dictionary = GFProjectReferenceScanner.scan_references(targets, {
		"scan_roots": REFERENCE_SCAN_ROOTS,
		"additional_ignored_roots": REFERENCE_SCAN_IGNORED_ROOTS,
		"include_weak_references": false,
		"max_references_per_target": 50,
		"max_scanned_files": 30000,
		"max_total_bytes": 256 * 1024 * 1024,
		"warning_prefix": "[PurgeRejectedAssets]",
	})
	var scan_summary: Dictionary = scan_report.duplicate(true)
	var _erase_references_result: bool = scan_summary.erase("references")
	var _erase_weak_references_result: bool = scan_summary.erase("weak_references")
	report["reference_scan_report"] = scan_summary
	if GFVariantData.get_option_bool(scan_report, "partial_scan"):
		_add_issue(
			report,
			"partial_reference_scan",
			"",
			ERR_CANT_RESOLVE
		)
		return
	for reference_value: Variant in GFVariantData.get_option_array(
		scan_report,
		"references"
	):
		var reference: Dictionary = GFVariantData.as_dictionary(reference_value)
		_add_issue(
			report,
			"rejected_asset_still_referenced",
			GFVariantData.get_option_string(reference, "path"),
			ERR_ALREADY_IN_USE,
			{
				"target_id": GFVariantData.get_option_string(reference, "target_id"),
				"kind": GFVariantData.get_option_string(reference, "kind"),
			}
		)


func _make_candidate(record: Resource, record_path: String) -> Dictionary:
	var asset_id: String = GFVariantData.to_text(record.get("asset_id"))
	var source_pack_id: String = GFVariantData.to_text(record.get("source_pack_id"))
	var relative_path: String = GFPathTools.normalize_path(
		GFVariantData.to_text(record.get("relative_path"))
	)
	var sha256: String = GFVariantData.to_text(record.get("sha256")).to_lower()
	var library_path: String = GFPathTools.normalize_resource_path(
		GFVariantData.to_text(record.get("library_path"))
	)
	var normalized_record_path: String = GFPathTools.normalize_resource_path(record_path)
	var expected_library_path: String = GFPathTools.normalize_resource_path(
		SOURCE_PACK_ROOT.path_join(source_pack_id).path_join("files").path_join(relative_path)
	)
	var valid: bool = (
		not asset_id.is_empty()
		and not source_pack_id.is_empty()
		and not relative_path.is_empty()
		and not sha256.is_empty()
		and library_path == expected_library_path
		and GFPathTools.is_path_under_root(library_path, SOURCE_PACK_ROOT)
		and GFPathTools.is_path_under_root(normalized_record_path, REVIEW_RECORD_ROOT)
	)
	return {
		"valid": valid,
		"asset_id": asset_id,
		"source_pack_id": source_pack_id,
		"relative_path": relative_path,
		"sha256": sha256,
		"library_path": library_path,
		"import_path": library_path + ".import",
		"uid_path": library_path + ".uid",
		"record_path": normalized_record_path,
	}


func _remove_candidate(candidate: Dictionary, report: Dictionary) -> void:
	_remove_file(
		GFVariantData.get_option_string(candidate, "library_path"),
		"removed_asset_count",
		report
	)
	_remove_file(
		GFVariantData.get_option_string(candidate, "import_path"),
		"removed_import_count",
		report
	)
	_remove_file(
		GFVariantData.get_option_string(candidate, "uid_path"),
		"removed_import_count",
		report
	)
	_remove_file(
		GFVariantData.get_option_string(candidate, "record_path"),
		"removed_record_count",
		report
	)


func _remove_file(
	path: String,
	count_key: String,
	report: Dictionary
) -> void:
	if not FileAccess.file_exists(path):
		return
	var size_bytes: int = 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file != null:
		size_bytes = file.get_length()
		file.close()
	var remove_result: Error = DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
	if remove_result != OK:
		_add_issue(report, "file_remove_failed", path, remove_result)
		return
	report[count_key] = GFVariantData.get_option_int(report, count_key) + 1
	report["removed_byte_count"] = (
		GFVariantData.get_option_int(report, "removed_byte_count") + size_bytes
	)


func _make_report() -> Dictionary:
	return {
		"ok": true,
		"report_id": "rejected_asset_purge",
		"matched_count": 0,
		"exclusion_count": 0,
		"removed_asset_count": 0,
		"removed_import_count": 0,
		"removed_record_count": 0,
		"removed_byte_count": 0,
		"reference_scan_report": {},
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
	}


func _add_issue(
	report: Dictionary,
	kind: String,
	path: String,
	error: Error,
	metadata: Dictionary = {}
) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	var issue: Dictionary = metadata.duplicate(true)
	issue.merge({
		"kind": kind,
		"path": path,
		"error": error,
	})
	issues.append(issue)
	report["issues"] = issues
	report["error_count"] = GFVariantData.get_option_int(report, "error_count") + 1


func _finalize_report(report: Dictionary) -> void:
	report["issue_count"] = GFVariantData.get_option_array(report, "issues").size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count") == 0


func _write_report(report: Dictionary) -> void:
	var directory_result: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	)
	if directory_result != OK:
		return
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return
	var _stored: bool = file.store_string(
		GFVariantJsonCodec.stringify_json_compatible(report, "\t", true) + "\n"
	)
	file.close()
