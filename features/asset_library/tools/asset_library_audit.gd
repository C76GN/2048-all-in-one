## AssetLibraryAudit: 项目素材库的离线目录与审计模块。
##
## 复用 GFAssetCatalog、GFProjectReferenceScanner、GFPathEnumerationTools 与
## GFAssetAttributionTools，负责扫描候选素材、核验归因并生成审计报告。
class_name AssetLibraryAudit
extends RefCounted


# --- 常量 ---

const ASSET_LIBRARY_SOURCE_ROOT: String = GameAssetLibraryUtility.ASSET_LIBRARY_SOURCE_ROOT
const ASSET_LIBRARY_MANIFEST_PATH: String = GameAssetLibraryUtility.ASSET_LIBRARY_MANIFEST_PATH
const ASSET_LIBRARY_SOURCE_PACK_ROOT: String = "res://features/asset_library/resources/source_packs"
const ASSET_LIBRARY_REVIEW_ROOT: String = "res://features/asset_library/resources/review"
const ASSET_LIBRARY_REVIEW_RECORD_ROOT: String = "res://features/asset_library/resources/review/records"
const ASSET_LIBRARY_SOURCE_PACK_RESOURCE_ROOT: String = "res://features/asset_library/resources/review/source_packs"
const ASSET_LIBRARY_SLOT_MAP_PATH: String = "res://features/asset_library/resources/review/asset_slot_map.tres"
const DEFAULT_AUDIT_JSON_PATH: String = "res://features/asset_library/resources/reports/asset_audit.json"
const DEFAULT_AUDIT_MARKDOWN_PATH: String = "res://features/asset_library/resources/reports/asset_audit.md"
const DEFAULT_REVIEW_CATALOG_JSON_PATH: String = "res://features/asset_library/resources/reports/review_catalog_audit.json"
const DEFAULT_REVIEW_CATALOG_MARKDOWN_PATH: String = "res://features/asset_library/resources/reports/review_catalog_audit.md"
const _ASSET_REVIEW_RECORD_SCRIPT = preload("res://features/asset_library/scripts/data/asset_review_record.gd")
const _ASSET_SOURCE_PACK_SCRIPT = preload("res://features/asset_library/scripts/data/asset_source_pack.gd")
const _ASSET_SLOT_MAP_SCRIPT = preload("res://features/asset_library/scripts/data/asset_slot_map.gd")
const _ASSET_SLOT_BINDING_SCRIPT = preload("res://features/asset_library/scripts/data/asset_slot_binding.gd")
const _CONTENT_PACKAGE_CATALOG_SOURCE_SCRIPT = preload(
	"res://features/asset_library/scripts/catalog/game_content_package_catalog_source_provider.gd"
)
const _REVIEW_CATALOG_SOURCE_SCRIPT = preload(
	"res://features/asset_library/scripts/catalog/game_asset_review_catalog_source_provider.gd"
)

const _ASSET_FILE_EXTENSIONS: PackedStringArray = [
	"gdshader",
	"jpeg",
	"jpg",
	"mp3",
	"ogg",
	"png",
	"shader",
	"svg",
	"tres",
	"tscn",
	"wav",
	"webp",
]
const _RESOURCE_FILE_EXTENSIONS: PackedStringArray = [
	"tres",
]
const _ASSET_SCAN_EXCLUDED_PATHS: PackedStringArray = [
	ASSET_LIBRARY_REVIEW_ROOT,
	ASSET_LIBRARY_SOURCE_PACK_ROOT,
]
const _MAX_ASSET_LIBRARY_FILE_COUNT: int = 20000
const _DEFAULT_USAGE_SCAN_ROOTS: Array[String] = [
	"res://app",
	"res://features",
	"res://shared",
	"res://project.godot",
]


# --- 私有变量 ---

var _catalog_sources: GFAssetCatalogSourceRegistry = null
var _runtime_catalog_provider: GameContentPackageCatalogSourceProvider = null
var _review_catalog_provider: GameAssetReviewCatalogSourceProvider = null
var _runtime_catalog: GFAssetCatalog = null
var _review_catalog: GFAssetCatalog = null


# --- 生命周期方法 ---

func _init() -> void:
	_ensure_catalog_sources()


func dispose() -> void:
	if _catalog_sources != null:
		_catalog_sources.clear_sources()
	_catalog_sources = null
	_runtime_catalog_provider = null
	_review_catalog_provider = null
	_runtime_catalog = null
	_review_catalog = null


# --- 公共方法 ---


## 获取由内容包 manifest 构建的 GF 标准运行时素材目录。
## @return 运行时素材目录副本。
func get_runtime_catalog() -> GFAssetCatalog:
	if _runtime_catalog == null:
		_rebuild_runtime_catalog()
	if _runtime_catalog == null:
		return GFAssetCatalog.new()
	return GFAssetCatalog.from_dict(_runtime_catalog.to_dict())


## 获取由 AssetReviewRecord 构建的 GF 标准候选素材目录。
## @param rebuild: 为 true 时重新扫描评审记录。
## @return 候选素材目录副本。
func get_review_catalog(rebuild: bool = false) -> GFAssetCatalog:
	if rebuild or _review_catalog == null:
		_rebuild_review_catalog()
	if _review_catalog == null:
		return GFAssetCatalog.new()
	return GFAssetCatalog.from_dict(_review_catalog.to_dict())


## 使用 GFTextSearchScorer 搜索运行时素材。
## @param query: 搜索文本。
## @param options: GFAssetCatalog.search() 选项。
## @return 排序后的匹配报告。
func search_runtime_assets(query: String, options: Dictionary = {}) -> Array[Dictionary]:
	return get_runtime_catalog().search(query, options)


## 使用 GFTextSearchScorer 搜索候选素材。
## @param query: 搜索文本。
## @param options: GFAssetCatalog.search() 选项。
## @return 排序后的匹配报告。
func search_review_assets(query: String, options: Dictionary = {}) -> Array[Dictionary]:
	return get_review_catalog().search(query, options)


## 构建素材库审计报告，不写入文件。
## @param options: 审计选项；可传入 scan_roots 覆盖默认项目扫描目录。
func build_audit_report(options: Dictionary = {}) -> Dictionary:
	var report: Dictionary = _make_audit_report()
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(ASSET_LIBRARY_MANIFEST_PATH)
	if manifest == null:
		_add_audit_issue(report, "error", "missing_manifest", "素材库 manifest 无法加载。", {
			"path": ASSET_LIBRARY_MANIFEST_PATH,
		})
		_finalize_audit_report(report)
		return report

	var manifest_report: Dictionary = manifest.get_validation_report({"check_resource_exists": true})
	var export_plan: GFContentPackageExportPlan = GFContentPackageExportPlan.new()
	var _built_plan: GFContentPackageExportPlan = export_plan.build_from_manifest(manifest, {
		"include_manifest": true,
		"check_files": true,
	})
	var export_plan_report: Dictionary = export_plan.get_validation_report()
	var artifact_report: Dictionary = export_plan.get_artifact_report({"include_modified_time": true})
	var entries: Array[Dictionary] = manifest.get_normalized_resources()
	var usage_scan_roots: PackedStringArray = _get_usage_scan_roots(options)
	var usage_result: Dictionary = _collect_asset_usage(entries, usage_scan_roots)
	var usage: Dictionary = GFVariantData.get_option_dictionary(usage_result, "usage")
	var reference_scan_report: Dictionary = GFVariantData.get_option_dictionary(
		usage_result,
		"reference_scan_report"
	)
	var usage_summary: Dictionary = _summarize_usage(usage)
	var metadata_issues: Array[Dictionary] = _collect_metadata_issues(entries, manifest.metadata)
	var library_scan_report: Dictionary = _scan_asset_library_files()
	var unregistered_files: PackedStringArray = _collect_unregistered_asset_files(entries, library_scan_report)
	var unused_keys: PackedStringArray = _collect_unused_keys(entries, usage)
	var optional_unused_keys: PackedStringArray = _filter_unused_keys_by_policy(
		entries,
		unused_keys,
		true
	)
	var required_unused_keys: PackedStringArray = _filter_unused_keys_by_policy(
		entries,
		unused_keys,
		false
	)
	var attribution_report: Dictionary = _build_manifest_attribution_report(entries)

	report["package_id"] = String(manifest.package_id)
	report["version"] = manifest.version
	report["resource_count"] = entries.size()
	report["manifest_report"] = manifest_report
	report["export_plan_report"] = export_plan_report
	report["artifact_report"] = artifact_report
	report["runtime_catalog"] = get_runtime_catalog().get_debug_snapshot()
	report["library_scan_report"] = _summarize_path_scan_report(library_scan_report)
	report["reference_scan_report"] = reference_scan_report
	report["attribution_report"] = attribution_report
	report["attribution_notice"] = GFAssetAttributionTools.format_notice_text(
		attribution_report,
		{"title": "Asset library attributions"}
	)
	report["usage"] = usage
	report["unused_keys"] = unused_keys
	report["optional_unused_keys"] = optional_unused_keys
	report["required_unused_keys"] = required_unused_keys
	report["unregistered_library_files"] = unregistered_files
	report["metadata_issues"] = metadata_issues
	report["used_count"] = GFVariantData.get_option_int(usage_summary, "used_count")
	report["direct_path_reference_count"] = GFVariantData.get_option_int(usage_summary, "direct_path_reference_count")
	report["asset_key_reference_count"] = GFVariantData.get_option_int(usage_summary, "asset_key_reference_count")

	if not _is_report_ok(manifest_report):
		_add_audit_issue(report, "error", "invalid_manifest", "素材库 manifest 校验失败。", {})
	if not _is_report_ok(export_plan_report):
		_add_audit_issue(report, "error", "invalid_export_plan", "素材库导出计划校验失败。", {})
	if not _is_report_ok(artifact_report):
		_add_audit_issue(report, "error", "invalid_artifacts", "素材库 artifact 校验失败。", {})
	if (
		not GFVariantData.get_option_bool(library_scan_report, "ok")
		or GFVariantData.get_option_bool(library_scan_report, "truncated")
	):
		_add_audit_issue(
			report,
			"error",
			"partial_library_file_scan",
			"GF 素材库路径枚举未完整完成，未登记文件结果不可作为清理依据。",
			{"library_scan_report": _summarize_path_scan_report(library_scan_report)}
		)
	if GFVariantData.get_option_bool(reference_scan_report, "partial_scan"):
		_add_audit_issue(
			report,
			"error",
			"partial_reference_scan",
			"GF 项目引用扫描未完整完成，unused 结果不可作为删除依据。",
			{"reference_scan_report": reference_scan_report}
		)
	if not _is_report_ok(attribution_report):
		_add_audit_issue(
			report,
			"error",
			"invalid_asset_attribution",
			"GF 素材授权与署名覆盖校验失败。",
			{"attribution_report": attribution_report}
		)

	for metadata_issue: Dictionary in metadata_issues:
		_add_audit_issue(
			report,
			"error",
			GFVariantData.get_option_string(metadata_issue, "kind", "missing_metadata"),
			GFVariantData.get_option_string(metadata_issue, "message", "素材元数据不完整。"),
			metadata_issue
		)

	for path: String in unregistered_files:
		_add_audit_issue(report, "warning", "unregistered_library_file", "素材库中存在未登记文件：%s。" % path, {
			"path": path,
		})

	for key_text: String in required_unused_keys:
		_add_audit_issue(report, "warning", "unused_asset", "素材未被项目资源引用：%s。" % key_text, {
			"asset_key": key_text,
		})

	_finalize_audit_report(report)
	return report


## 生成并写入 JSON / Markdown 审计报告。
## @param json_path: JSON 报告输出路径。
## @param markdown_path: Markdown 报告输出路径。
func write_audit_reports(
	json_path: String = DEFAULT_AUDIT_JSON_PATH,
	markdown_path: String = DEFAULT_AUDIT_MARKDOWN_PATH
) -> Dictionary:
	var report: Dictionary = build_audit_report()
	var markdown_error: Error = _write_text_if_changed(markdown_path, _format_audit_markdown(report))
	if markdown_error != OK:
		_add_audit_issue(report, "error", "audit_markdown_write_failed", "素材库 Markdown 审计报告写入失败。", {
			"path": markdown_path,
			"error": markdown_error,
		})
		_finalize_audit_report(report)
	var json_error: Error = _write_text_if_changed(json_path, JSON.stringify(report, "\t"))
	if json_error != OK:
		_add_audit_issue(report, "error", "audit_json_write_failed", "素材库 JSON 审计报告写入失败。", {
			"path": json_path,
			"error": json_error,
		})
		_finalize_audit_report(report)
	return report


func build_review_catalog_report() -> Dictionary:
	var report: Dictionary = _make_review_catalog_report()
	var review_catalog: GFAssetCatalog = get_review_catalog(true)
	var source_pack_scan_report: Dictionary = _scan_source_pack_resources()
	var source_packs: Array[Resource] = _collect_source_pack_resources(source_pack_scan_report)
	var review_record_scan_report: Dictionary = _get_review_record_scan_report()
	var records: Array[Resource] = _collect_review_records()
	var slot_map: Resource = _load_asset_slot_map()
	var approved_attribution_report: Dictionary = _build_review_attribution_report(records)

	report["catalog"] = review_catalog.get_debug_snapshot()
	report["review_record_scan_report"] = _summarize_path_scan_report(review_record_scan_report)
	report["source_pack_scan_report"] = _summarize_path_scan_report(source_pack_scan_report)
	report["source_pack_count"] = source_packs.size()
	report["review_record_count"] = records.size()
	report["slot_count"] = _get_slot_bindings(slot_map).size()
	report["bound_slot_count"] = _get_bound_slot_count(slot_map)
	report["approved_attribution_report"] = approved_attribution_report
	report["approved_attribution_notice"] = GFAssetAttributionTools.format_notice_text(
		approved_attribution_report,
		{"title": "Approved asset attributions"}
	)
	if (
		not GFVariantData.get_option_bool(source_pack_scan_report, "ok")
		or GFVariantData.get_option_bool(source_pack_scan_report, "truncated")
	):
		_add_audit_issue(
			report,
			"error",
			"partial_source_pack_scan",
			"GF 源包资源路径枚举未完整完成，候选审计结果不可信。",
			{"source_pack_scan_report": _summarize_path_scan_report(source_pack_scan_report)}
		)
	if (
		not GFVariantData.get_option_bool(review_record_scan_report, "ok")
		or GFVariantData.get_option_bool(review_record_scan_report, "truncated")
	):
		_add_audit_issue(
			report,
			"error",
			"partial_review_record_scan",
			"GF 候选记录路径枚举未完整完成，候选目录结果不可信。",
			{"review_record_scan_report": _summarize_path_scan_report(review_record_scan_report)}
		)

	for source_pack: Resource in source_packs:
		_increment_count(report, "license_counts", _get_resource_string(source_pack, "license_status"))
		if not _source_pack_has_known_license(source_pack):
			_add_audit_issue(report, "warning", "source_pack_license_unknown", "素材包授权状态未确认：%s。" % _get_resource_string(source_pack, "display_name"), {
				"source_pack_id": _get_resource_string(source_pack, "source_pack_id"),
				"source_path": _get_resource_string(source_pack, "original_source_path"),
			})

	for record: Resource in records:
		_increment_count(report, "kind_counts", _get_resource_string(record, "asset_kind"))
		_increment_count(report, "status_counts", _get_resource_string(record, "review_status"))
		_increment_count(report, "record_license_counts", _get_resource_string(record, "license_status"))
		for slot_id: String in _get_resource_packed_string_array(record, "suggested_slots"):
			_increment_count(report, "slot_candidate_counts", slot_id)

	if not _is_report_ok(approved_attribution_report):
		_add_audit_issue(
			report,
			"error",
			"invalid_approved_asset_attribution",
			"已批准素材未通过 GF 授权与署名覆盖校验。",
			{"attribution_report": approved_attribution_report}
		)

	for binding: Resource in _get_slot_bindings(slot_map):
		if binding == null:
			continue
		var current_library_path: String = _get_resource_string(binding, "current_library_path")
		if current_library_path.is_empty():
			continue
		if not FileAccess.file_exists(current_library_path):
			_add_audit_issue(report, "error", "slot_binding_missing_file", "用途槽位绑定的文件不存在：%s。" % _get_resource_string(binding, "slot_id"), {
				"slot_id": _get_resource_string(binding, "slot_id"),
				"path": current_library_path,
			})

	_finalize_audit_report(report)
	return report


## 生成并写入评审素材目录 JSON / Markdown 审计报告。
## @param json_path: JSON 报告输出路径。
## @param markdown_path: Markdown 报告输出路径。
func write_review_catalog_reports(
	json_path: String = DEFAULT_REVIEW_CATALOG_JSON_PATH,
	markdown_path: String = DEFAULT_REVIEW_CATALOG_MARKDOWN_PATH
) -> Dictionary:
	var report: Dictionary = build_review_catalog_report()
	var markdown_error: Error = _write_text_if_changed(
		markdown_path,
		_format_review_catalog_markdown(report)
	)
	if markdown_error != OK:
		_add_audit_issue(report, "error", "review_markdown_write_failed", "评审目录 Markdown 报告写入失败。", {
			"path": markdown_path,
			"error": markdown_error,
		})
		_finalize_audit_report(report)
	var json_error: Error = _write_text_if_changed(json_path, JSON.stringify(report, "\t"))
	if json_error != OK:
		_add_audit_issue(report, "error", "review_json_write_failed", "评审目录 JSON 报告写入失败。", {
			"path": json_path,
			"error": json_error,
		})
		_finalize_audit_report(report)
	return report


# --- 私有/辅助方法 ---

func _ensure_catalog_sources() -> void:
	if _catalog_sources != null:
		return
	_catalog_sources = GFAssetCatalogSourceRegistry.new()

	_runtime_catalog_provider = _CONTENT_PACKAGE_CATALOG_SOURCE_SCRIPT.new()
	var runtime_content_catalog: GFContentPackageCatalog = GFContentPackageCatalog.new()
	var runtime_manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(
		ASSET_LIBRARY_MANIFEST_PATH
	)
	if runtime_manifest != null:
		var _manifest_added: bool = runtime_content_catalog.add_manifest(runtime_manifest)
	var _runtime_configured: GFAssetCatalogSourceProvider = (
		_runtime_catalog_provider.configure_catalog(
			runtime_content_catalog,
			&"content_package",
			"asset_library"
		)
	)
	var _runtime_registered: bool = _catalog_sources.register_source(
		_runtime_catalog_provider,
		{"priority": 100}
	)

	_review_catalog_provider = _REVIEW_CATALOG_SOURCE_SCRIPT.new()
	var _review_configured: GFAssetCatalogSourceProvider = (
		_review_catalog_provider.configure_review_records(
			ASSET_LIBRARY_REVIEW_RECORD_ROOT,
			&"asset_review"
		)
	)
	var _review_registered: bool = _catalog_sources.register_source(
		_review_catalog_provider,
		{"priority": 50}
	)


func _rebuild_runtime_catalog() -> void:
	_ensure_catalog_sources()
	_runtime_catalog = GFAssetCatalog.new()
	if _catalog_sources == null or _runtime_catalog_provider == null:
		return
	_runtime_catalog = _catalog_sources.build_catalog({
		"source_ids": PackedStringArray(["content_package"]),
	})


func _rebuild_review_catalog() -> void:
	_ensure_catalog_sources()
	_review_catalog = GFAssetCatalog.new()
	if _catalog_sources == null or _review_catalog_provider == null:
		return
	_review_catalog = _catalog_sources.build_catalog({
		"source_ids": PackedStringArray(["asset_review"]),
	})


func _collect_asset_usage(entries: Array[Dictionary], scan_roots: PackedStringArray) -> Dictionary:
	var usage: Dictionary = {}
	var targets: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var key_text: String = String(GFVariantData.get_option_string_name(entry, "key"))
		var path: String = GFVariantData.get_option_string(entry, "path")
		usage[key_text] = {
			"path": path,
			"type_hint": GFVariantData.get_option_string(entry, "type_hint"),
			"path_users": PackedStringArray(),
			"key_users": PackedStringArray(),
			"used": false,
		}
		if key_text.is_empty() or path.is_empty():
			continue
		targets.append({
			"id": key_text,
			"root_path": path,
			"class_names": [key_text],
		})

	var reference_scan_report: Dictionary = GFProjectReferenceScanner.scan_references(targets, {
		"scan_roots": scan_roots,
		"additional_ignored_roots": PackedStringArray([ASSET_LIBRARY_SOURCE_ROOT]),
		"include_weak_references": true,
		"max_references_per_target": 500,
		"max_weak_references_per_target": 500,
		"max_scanned_files": 30000,
		"max_total_bytes": 256 * 1024 * 1024,
		"warning_prefix": "[GameAssetLibraryUtility]",
	})
	_apply_usage_references(
		usage,
		GFVariantData.get_option_array(reference_scan_report, "references")
	)
	_apply_usage_references(
		usage,
		GFVariantData.get_option_array(reference_scan_report, "weak_references")
	)
	return {
		"usage": usage,
		"reference_scan_report": reference_scan_report,
	}


func _apply_usage_references(usage: Dictionary, references: Array) -> void:
	for reference_value: Variant in references:
		if not (reference_value is Dictionary):
			continue
		var reference_record: Dictionary = reference_value
		var asset_key: String = GFVariantData.get_option_string(reference_record, "target_id")
		if not usage.has(asset_key):
			continue
		var user_path: String = GFVariantData.get_option_string(reference_record, "path")
		var record: Dictionary = GFVariantData.get_option_dictionary(usage, asset_key)
		if GFVariantData.get_option_string(reference_record, "kind") == "class_name":
			_append_unique_string_to_record(record, "key_users", user_path)
		else:
			_append_unique_string_to_record(record, "path_users", user_path)
		record["used"] = true
		usage[asset_key] = record


func _summarize_usage(usage: Dictionary) -> Dictionary:
	var used_count: int = 0
	var direct_path_reference_count: int = 0
	var asset_key_reference_count: int = 0
	for key_value: Variant in usage.keys():
		var record: Dictionary = GFVariantData.get_option_dictionary(usage, key_value)
		if GFVariantData.get_option_bool(record, "used"):
			used_count += 1
		direct_path_reference_count += GFVariantData.get_option_packed_string_array(record, "path_users").size()
		asset_key_reference_count += GFVariantData.get_option_packed_string_array(record, "key_users").size()
	return {
		"used_count": used_count,
		"direct_path_reference_count": direct_path_reference_count,
		"asset_key_reference_count": asset_key_reference_count,
	}


func _collect_unused_keys(entries: Array[Dictionary], usage: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		var key_text: String = String(GFVariantData.get_option_string_name(entry, "key"))
		var record: Dictionary = GFVariantData.get_option_dictionary(usage, key_text)
		if GFVariantData.get_option_bool(record, "used"):
			continue
		var _append_result: bool = result.append(key_text)
	result.sort()
	return result


func _filter_unused_keys_by_policy(
	entries: Array[Dictionary],
	unused_keys: PackedStringArray,
	optional: bool
) -> PackedStringArray:
	var optional_by_key: Dictionary = {}
	for entry: Dictionary in entries:
		var key_text: String = String(GFVariantData.get_option_string_name(entry, "key"))
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
		optional_by_key[key_text] = (
			GFVariantData.get_option_string(metadata, "usage_policy", "required")
			== "optional"
		)

	var result: PackedStringArray = PackedStringArray()
	for key_text: String in unused_keys:
		if GFVariantData.get_option_bool(optional_by_key, key_text) != optional:
			continue
		var _append_result: bool = result.append(key_text)
	result.sort()
	return result


func _collect_metadata_issues(entries: Array[Dictionary], package_metadata: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var required_fields: PackedStringArray = GFVariantData.get_option_packed_string_array(
		package_metadata,
		"audit_required_metadata",
		PackedStringArray(["asset_kind", "category", "origin", "author", "source"])
	)
	var third_party_required_fields: PackedStringArray = GFVariantData.get_option_packed_string_array(
		package_metadata,
		"third_party_required_metadata",
		PackedStringArray(["author", "source", "source_url"])
	)
	for entry: Dictionary in entries:
		var key_text: String = String(GFVariantData.get_option_string_name(entry, "key"))
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
		for field: String in required_fields:
			if not _metadata_has_text(metadata, field):
				issues.append(_make_metadata_issue(key_text, field, "missing_metadata"))
		var usage_policy: String = GFVariantData.get_option_string(
			metadata,
			"usage_policy",
			"required"
		)
		if usage_policy not in ["required", "optional"]:
			issues.append(_make_metadata_issue(
				key_text,
				"usage_policy",
				"invalid_metadata"
			))
		if GFVariantData.get_option_string(metadata, "origin") != "third_party":
			continue
		for field: String in third_party_required_fields:
			if not _metadata_has_text(metadata, field):
				issues.append(_make_metadata_issue(key_text, field, "missing_third_party_metadata"))
	return issues


func _collect_unregistered_asset_files(
	entries: Array[Dictionary],
	library_scan_report: Dictionary
) -> PackedStringArray:
	var registered_paths: Dictionary = {}
	for entry: Dictionary in entries:
		registered_paths[GFVariantData.get_option_string(entry, "path")] = true

	var files: PackedStringArray = GFVariantData.get_option_packed_string_array(library_scan_report, "paths")
	var result: PackedStringArray = PackedStringArray()
	for path: String in files:
		if registered_paths.has(path):
			continue
		var _append_result: bool = result.append(path)
	result.sort()
	return result


func _scan_asset_library_files() -> Dictionary:
	return GFPathEnumerationTools.scan_files(ASSET_LIBRARY_SOURCE_ROOT, {
		"recursive": true,
		"include_hidden": false,
		"extensions": _ASSET_FILE_EXTENSIONS,
		"excluded_paths": _ASSET_SCAN_EXCLUDED_PATHS,
		"max_file_count": _MAX_ASSET_LIBRARY_FILE_COUNT,
		"sort": true,
	})


func _get_usage_scan_roots(options: Dictionary) -> PackedStringArray:
	var configured: PackedStringArray = GFVariantData.get_option_packed_string_array(
		options,
		"scan_roots",
		PackedStringArray()
	)
	if not configured.is_empty():
		return configured
	var result: PackedStringArray = PackedStringArray()
	for root_path: String in _DEFAULT_USAGE_SCAN_ROOTS:
		var _append_result: bool = result.append(root_path)
	return result


func _write_text(path: String, text: String) -> Error:
	var directory: String = path.get_base_dir()
	if directory.begins_with("res://") or directory.begins_with("user://"):
		var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(directory)
		)
		if mkdir_result != OK:
			return mkdir_result
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var store_result: bool = file.store_string(text)
	file.close()
	return OK if store_result else ERR_FILE_CANT_WRITE


func _write_text_if_changed(path: String, text: String) -> Error:
	if FileAccess.file_exists(path):
		var existing_file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if existing_file == null:
			return FileAccess.get_open_error()
		var existing_text: String = existing_file.get_as_text()
		existing_file.close()
		if existing_text == text:
			return OK
	return _write_text(path, text)


func _format_audit_markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	_append_markdown_line(lines, "# Asset Library Audit")
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "- Package: `%s`" % GFVariantData.get_option_string(report, "package_id"))
	_append_markdown_line(lines, "- Version: `%s`" % GFVariantData.get_option_string(report, "version"))
	_append_markdown_line(lines, "- Resource count: `%d`" % GFVariantData.get_option_int(report, "resource_count"))
	_append_markdown_line(lines, "- Used count: `%d`" % GFVariantData.get_option_int(report, "used_count"))
	_append_markdown_line(lines, "- Issue count: `%d`" % GFVariantData.get_option_int(report, "issue_count"))
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## Usage")
	var usage: Dictionary = GFVariantData.get_option_dictionary(report, "usage")
	var keys: Array = usage.keys()
	keys.sort()
	for key_value: Variant in keys:
		var key_text: String = GFVariantData.to_text(key_value)
		var record: Dictionary = GFVariantData.get_option_dictionary(usage, key_value)
		_append_markdown_line(lines, "")
		_append_markdown_line(lines, "### `%s`" % key_text)
		_append_markdown_line(lines, "- Path: `%s`" % GFVariantData.get_option_string(record, "path"))
		_append_markdown_line(lines, "- Used: `%s`" % ("yes" if GFVariantData.get_option_bool(record, "used") else "no"))
		_append_markdown_user_list(lines, "Path users", GFVariantData.get_option_packed_string_array(record, "path_users"))
		_append_markdown_user_list(lines, "Key users", GFVariantData.get_option_packed_string_array(record, "key_users"))
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## Issues")
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	if issues.is_empty():
		_append_markdown_line(lines, "- None")
	else:
		for issue_value: Variant in issues:
			var issue: Dictionary = GFVariantData.as_dictionary(issue_value)
			_append_markdown_line(lines, "- `%s` `%s`: %s" % [
				GFVariantData.get_option_string(issue, "severity"),
				GFVariantData.get_option_string(issue, "kind"),
				GFVariantData.get_option_string(issue, "message"),
			])
	return "\n".join(lines) + "\n"


func _format_review_catalog_markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	_append_markdown_line(lines, "# Asset Review Catalog Audit")
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "- Source packs: `%d`" % GFVariantData.get_option_int(report, "source_pack_count"))
	_append_markdown_line(lines, "- Review records: `%d`" % GFVariantData.get_option_int(report, "review_record_count"))
	_append_markdown_line(lines, "- Slot bindings: `%d / %d`" % [
		GFVariantData.get_option_int(report, "bound_slot_count"),
		GFVariantData.get_option_int(report, "slot_count"),
	])
	_append_markdown_line(lines, "- Issue count: `%d`" % GFVariantData.get_option_int(report, "issue_count"))
	_append_markdown_line(lines, "")
	_append_markdown_count_section(lines, "Kinds", GFVariantData.get_option_dictionary(report, "kind_counts"))
	_append_markdown_count_section(lines, "Statuses", GFVariantData.get_option_dictionary(report, "status_counts"))
	_append_markdown_count_section(lines, "Source Pack Licenses", GFVariantData.get_option_dictionary(report, "license_counts"))
	_append_markdown_count_section(lines, "Record Licenses", GFVariantData.get_option_dictionary(report, "record_license_counts"))
	_append_markdown_count_section(lines, "Suggested Slots", GFVariantData.get_option_dictionary(report, "slot_candidate_counts"))
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## Issues")
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	if issues.is_empty():
		_append_markdown_line(lines, "- None")
	else:
		for issue_value: Variant in issues:
			var issue: Dictionary = GFVariantData.as_dictionary(issue_value)
			_append_markdown_line(lines, "- `%s` `%s`: %s" % [
				GFVariantData.get_option_string(issue, "severity"),
				GFVariantData.get_option_string(issue, "kind"),
				GFVariantData.get_option_string(issue, "message"),
			])
	return "\n".join(lines) + "\n"


func _append_markdown_count_section(lines: PackedStringArray, title: String, counts: Dictionary) -> void:
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## %s" % title)
	if counts.is_empty():
		_append_markdown_line(lines, "- None")
		return
	var keys: Array = counts.keys()
	keys.sort()
	for key_value: Variant in keys:
		var key_text: String = GFVariantData.to_text(key_value)
		_append_markdown_line(lines, "- `%s`: `%d`" % [key_text, GFVariantData.get_option_int(counts, key_text)])


func _build_manifest_attribution_report(entries: Array[Dictionary]) -> Dictionary:
	var attribution_entries: Array = []
	var resource_paths: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		var path: String = GFVariantData.get_option_string(entry, "path")
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
		attribution_entries.append({
			"path": path,
			"license_id": GFVariantData.get_option_string(metadata, "license"),
			"title": GFVariantData.get_option_string(
				metadata,
				"display_name",
				String(GFVariantData.get_option_string_name(entry, "key"))
			),
			"creator": GFVariantData.get_option_string(metadata, "author"),
			"source_url": GFVariantData.get_option_string(metadata, "source_url"),
			"notice": GFVariantData.get_option_string(metadata, "notice"),
			"copyright": GFVariantData.get_option_string(metadata, "copyright"),
			"subject_path": String(GFVariantData.get_option_string_name(entry, "key")),
			"subject_kind": GFVariantData.get_option_string(metadata, "asset_kind"),
		})
		_append_unique_string(resource_paths, path)
	return GFAssetAttributionTools.build_attribution_report(
		attribution_entries,
		resource_paths,
		{
			"require_license_id": true,
			"inherit_from_parent": false,
		}
	)


func _build_review_attribution_report(records: Array[Resource]) -> Dictionary:
	var attribution_entries: Array = []
	var resource_paths: PackedStringArray = PackedStringArray()
	for record: Resource in records:
		if not _record_is_approved(record):
			continue
		var path: String = _get_resource_string(record, "library_path")
		var license_id: String = ""
		if _get_resource_string_name(record, "license_status") == &"known":
			license_id = _get_resource_string(record, "license")
		attribution_entries.append({
			"path": path,
			"license_id": license_id,
			"title": _get_resource_string(record, "display_name"),
			"creator": _get_resource_string(record, "author"),
			"source_url": _get_resource_string(record, "source_url"),
			"subject_path": _get_resource_string(record, "asset_id"),
			"subject_kind": _get_resource_string(record, "asset_kind"),
		})
		_append_unique_string(resource_paths, path)
	return GFAssetAttributionTools.build_attribution_report(
		attribution_entries,
		resource_paths,
		{
			"require_license_id": true,
			"inherit_from_parent": false,
		}
	)


func _collect_review_records() -> Array[Resource]:
	var records: Array[Resource] = []
	var catalog: GFAssetCatalog = get_review_catalog()
	for asset_id: String in catalog.get_all_ids():
		var entry: GFAssetCatalogEntry = catalog.get_entry(StringName(asset_id))
		if entry == null:
			continue
		var record_path: String = GFVariantData.get_option_string(entry.metadata, "record_path")
		var loaded: Resource = ResourceLoader.load(record_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if _resource_uses_script(loaded, _ASSET_REVIEW_RECORD_SCRIPT):
			_append_resource(records, loaded)
	return records


func _scan_source_pack_resources() -> Dictionary:
	return GFPathEnumerationTools.scan_files(ASSET_LIBRARY_SOURCE_PACK_RESOURCE_ROOT, {
		"recursive": true,
		"include_hidden": false,
		"extensions": _RESOURCE_FILE_EXTENSIONS,
		"max_file_count": _MAX_ASSET_LIBRARY_FILE_COUNT,
		"sort": true,
	})


func _collect_source_pack_resources(scan_report: Dictionary) -> Array[Resource]:
	var paths: PackedStringArray = GFVariantData.get_option_packed_string_array(scan_report, "paths")
	var source_packs: Array[Resource] = []
	for path: String in paths:
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if _resource_uses_script(loaded, _ASSET_SOURCE_PACK_SCRIPT):
			_append_resource(source_packs, loaded)
	return source_packs


func _get_review_record_scan_report() -> Dictionary:
	if _review_catalog_provider == null:
		return {}
	return _review_catalog_provider.get_scan_report()


func _summarize_path_scan_report(scan_report: Dictionary) -> Dictionary:
	var summary: Dictionary = scan_report.duplicate(true)
	var _erase_result: bool = summary.erase("paths")
	return summary


func _load_asset_slot_map() -> Resource:
	if not FileAccess.file_exists(ASSET_LIBRARY_SLOT_MAP_PATH):
		return _ASSET_SLOT_MAP_SCRIPT.new()
	var loaded: Resource = ResourceLoader.load(ASSET_LIBRARY_SLOT_MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if _resource_uses_script(loaded, _ASSET_SLOT_MAP_SCRIPT):
		return loaded
	return _ASSET_SLOT_MAP_SCRIPT.new()


func _source_pack_has_known_license(source_pack: Resource) -> bool:
	return (
		_get_resource_string_name(source_pack, "license_status") == &"known"
		and not _get_resource_string(source_pack, "license").strip_edges().is_empty()
	)


func _record_is_approved(record: Resource) -> bool:
	return _get_resource_string_name(record, "review_status") == &"approved"


func _get_slot_bindings(slot_map: Resource) -> Array[Resource]:
	var bindings: Array[Resource] = []
	if slot_map == null:
		return bindings
	var value: Variant = slot_map.get("bindings")
	if value is Array:
		var raw_bindings: Array = value
		for raw_binding: Variant in raw_bindings:
			if not (raw_binding is Resource):
				continue
			var binding: Resource = raw_binding
			if _resource_uses_script(binding, _ASSET_SLOT_BINDING_SCRIPT):
				_append_resource(bindings, binding)
	return bindings


func _get_bound_slot_count(slot_map: Resource) -> int:
	var count: int = 0
	for binding: Resource in _get_slot_bindings(slot_map):
		var asset_key: StringName = _get_resource_string_name(binding, "current_asset_key")
		var library_path: String = _get_resource_string(binding, "current_library_path")
		if asset_key != &"" or not library_path.is_empty():
			count += 1
	return count


func _resource_uses_script(resource: Resource, script: Script) -> bool:
	return resource != null and resource.get_script() == script


func _get_resource_string(resource: Resource, property_name: String, fallback: String = "") -> String:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	return GFVariantData.to_text(value, fallback)


func _get_resource_string_name(
	resource: Resource,
	property_name: String,
	fallback: StringName = &""
) -> StringName:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	return GFVariantData.to_string_name(value, fallback)


func _get_resource_packed_string_array(resource: Resource, property_name: String) -> PackedStringArray:
	if resource == null:
		return PackedStringArray()
	var value: Variant = resource.get(property_name)
	return GFVariantData.get_option_packed_string_array({ "value": value }, "value")


func _append_markdown_user_list(lines: PackedStringArray, label: String, users: PackedStringArray) -> void:
	if users.is_empty():
		_append_markdown_line(lines, "- %s: none" % label)
		return
	_append_markdown_line(lines, "- %s:" % label)
	for user: String in users:
		_append_markdown_line(lines, "  - `%s`" % user)


func _append_markdown_line(lines: PackedStringArray, line: String) -> void:
	var _append_result: bool = lines.append(line)


func _make_metadata_issue(asset_key: String, field: String, kind: String) -> Dictionary:
	var message: String = "素材 `%s` 缺少元数据字段 `%s`。" % [asset_key, field]
	if kind == "invalid_metadata":
		message = "素材 `%s` 的元数据字段 `%s` 取值无效。" % [asset_key, field]
	return {
		"kind": kind,
		"asset_key": asset_key,
		"field": field,
		"message": message,
	}


func _metadata_has_text(metadata: Dictionary, field: String) -> bool:
	return not GFVariantData.get_option_string(metadata, field).strip_edges().is_empty()


func _append_unique_string(target: PackedStringArray, value: String) -> void:
	if value.is_empty() or target.has(value):
		return
	var _append_result: bool = target.append(value)


func _append_resource(target: Array[Resource], value: Resource) -> void:
	target.append(value)


func _append_unique_string_to_record(record: Dictionary, key: String, value: String) -> void:
	var values: PackedStringArray = GFVariantData.get_option_packed_string_array(record, key, PackedStringArray())
	_append_unique_string(values, value)
	record[key] = values


func _make_report(report_id: String) -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"report_id": report_id,
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _make_audit_report() -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"report_id": "asset_library_audit",
		"library_root": ASSET_LIBRARY_SOURCE_ROOT,
		"manifest_path": ASSET_LIBRARY_MANIFEST_PATH,
		"package_id": "",
		"version": "",
		"resource_count": 0,
		"used_count": 0,
		"direct_path_reference_count": 0,
		"asset_key_reference_count": 0,
		"runtime_catalog": {},
		"library_scan_report": {},
		"reference_scan_report": {},
		"attribution_report": {},
		"attribution_notice": "",
		"usage": {},
		"unused_keys": PackedStringArray(),
		"optional_unused_keys": PackedStringArray(),
		"required_unused_keys": PackedStringArray(),
		"unregistered_library_files": PackedStringArray(),
		"metadata_issues": [],
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _make_review_catalog_report() -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"report_id": "asset_review_catalog_audit",
		"review_root": ASSET_LIBRARY_REVIEW_ROOT,
		"source_pack_root": ASSET_LIBRARY_SOURCE_PACK_ROOT,
		"source_pack_count": 0,
		"review_record_count": 0,
		"slot_count": 0,
		"bound_slot_count": 0,
		"catalog": {},
		"review_record_scan_report": {},
		"source_pack_scan_report": {},
		"approved_attribution_report": {},
		"approved_attribution_notice": "",
		"kind_counts": {},
		"status_counts": {},
		"license_counts": {},
		"record_license_counts": {},
		"slot_candidate_counts": {},
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _add_report_issue(report: Dictionary, severity: String, kind: String, message: String) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	issues.append({
		"severity": severity,
		"kind": kind,
		"message": message,
	})
	report["issues"] = issues
	if severity == "error":
		report["error_count"] = GFVariantData.get_option_int(report, "error_count", 0) + 1
	elif severity == "warning":
		report["warning_count"] = GFVariantData.get_option_int(report, "warning_count", 0) + 1


func _add_audit_issue(
	report: Dictionary,
	severity: String,
	kind: String,
	message: String,
	metadata: Dictionary
) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	var issue: Dictionary = metadata.duplicate(true)
	issue["severity"] = severity
	issue["kind"] = kind
	issue["message"] = message
	issues.append(issue)
	report["issues"] = issues
	if severity == "error":
		report["error_count"] = GFVariantData.get_option_int(report, "error_count", 0) + 1
	elif severity == "warning":
		report["warning_count"] = GFVariantData.get_option_int(report, "warning_count", 0) + 1


func _increment_count(report: Dictionary, key: String, value: String) -> void:
	var counts: Dictionary = GFVariantData.get_option_dictionary(report, key)
	counts[value] = GFVariantData.get_option_int(counts, value) + 1
	report[key] = counts


func _finalize_report(report: Dictionary) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	report["issue_count"] = issues.size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count", 0) == 0
	report["healthy"] = (
		GFVariantData.get_option_int(report, "error_count", 0) == 0
		and GFVariantData.get_option_int(report, "warning_count", 0) == 0
	)


func _finalize_audit_report(report: Dictionary) -> void:
	_finalize_report(report)


func _is_report_ok(report: Dictionary) -> bool:
	return GFVariantData.get_option_bool(report, "ok", false)
