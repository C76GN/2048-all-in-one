## AuditAssetLibrary: verification 模块拥有的跨项目素材引用审计入口。
class_name AuditAssetLibrary
extends SceneTree


const _PROJECT_USAGE_SCAN_ROOTS: PackedStringArray = [
	"res://app",
	VerificationResourcePath.FEATURES_ROOT,
	"res://shared",
]
const _REPORT_ROOT: String = "res://build/asset_library"
const _AUDIT_JSON_PATH: String = _REPORT_ROOT + "/asset_audit.json"
const _AUDIT_MARKDOWN_PATH: String = _REPORT_ROOT + "/asset_audit.md"
const _REVIEW_JSON_PATH: String = _REPORT_ROOT + "/review_catalog_audit.json"
const _REVIEW_MARKDOWN_PATH: String = _REPORT_ROOT + "/review_catalog_audit.md"


func _init() -> void:
	print("Running asset library audit...")
	var audit: AssetLibraryAudit = AssetLibraryAudit.new()
	var report: Dictionary = audit.write_audit_reports(
		_AUDIT_JSON_PATH,
		_AUDIT_MARKDOWN_PATH,
		{&"scan_roots": _PROJECT_USAGE_SCAN_ROOTS}
	)
	var review_report: Dictionary = audit.write_review_catalog_reports(
		_REVIEW_JSON_PATH,
		_REVIEW_MARKDOWN_PATH
	)
	audit.dispose()
	var ok: bool = (
		GFVariantData.get_option_bool(report, "ok", false)
		and GFVariantData.get_option_bool(review_report, "ok", false)
	)
	var summary_prefix: String = "Asset audit:" if ok else "Asset audit failed:"
	var summary: String = "%s %d resources, %d used, %d issues" % [
		summary_prefix,
		GFVariantData.get_option_int(report, "resource_count"),
		GFVariantData.get_option_int(report, "used_count"),
		GFVariantData.get_option_int(report, "issue_count"),
	]
	print(summary)
	print("Review catalog audit: %d records, %d slots, %d issues" % [
		GFVariantData.get_option_int(review_report, "review_record_count"),
		GFVariantData.get_option_int(review_report, "slot_count"),
		GFVariantData.get_option_int(review_report, "issue_count"),
	])
	quit(0 if ok else 1)
