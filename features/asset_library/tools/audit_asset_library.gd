## AuditAssetLibrary: 以命令行方式生成项目素材库审计报告。
class_name AuditAssetLibrary
extends SceneTree


# --- Godot 生命周期方法 ---

func _init() -> void:
	print("Running asset library audit...")
	var audit: AssetLibraryAudit = AssetLibraryAudit.new()
	var report: Dictionary = audit.write_audit_reports()
	var review_report: Dictionary = audit.write_review_catalog_reports()
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
