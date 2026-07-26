## SyncAudioReviewVariants: 保守回填已验证同源音频编码变体的评审状态。
class_name SyncAudioReviewVariants
extends SceneTree


# --- 常量 ---

const REVIEW_RECORD_ROOT: String = "res://features/asset_library/resources/review/records"
const MAX_REVIEW_RECORD_COUNT: int = 20000
const _ASSET_REVIEW_RECORD_SCRIPT: Script = preload(
	"res://features/asset_library/scripts/data/asset_review_record.gd"
)
const _SYNC_POLICY_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_review_sync_policy.gd"
)


# --- 生命周期 ---

func _init() -> void:
	var report: Dictionary = _synchronize_review_groups()
	print("Audio review variant sync: %s" % JSON.stringify(report))
	quit(0 if GFVariantData.get_option_bool(report, "ok") else 1)


# --- 私有/辅助方法 ---

func _synchronize_review_groups() -> Dictionary:
	var report: Dictionary = _make_report()
	var scan_report: Dictionary = GFPathEnumerationTools.scan_files(
		REVIEW_RECORD_ROOT,
		{
			"recursive": true,
			"include_hidden": false,
			"extensions": PackedStringArray(["tres"]),
			"max_file_count": MAX_REVIEW_RECORD_COUNT,
			"sort": true,
		}
	)
	report["scan_report"] = _summarize_scan_report(scan_report)
	if (
		not GFVariantData.get_option_bool(scan_report, "ok")
		or GFVariantData.get_option_bool(scan_report, "truncated")
	):
		report["ok"] = false
		_append_issue(
			report,
			"review_record_scan_failed",
			"GF 候选记录路径枚举未完整完成，拒绝同步。"
		)
		return report

	var records_by_group: Dictionary = {}
	for record_path: String in GFVariantData.get_option_packed_string_array(
		scan_report,
		"paths"
	):
		var loaded: Resource = ResourceLoader.load(
			record_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		)
		if loaded == null or loaded.get_script() != _ASSET_REVIEW_RECORD_SCRIPT:
			continue
		var record: AssetReviewRecord = loaded
		if record.review_group_id == &"":
			continue
		var group_key: String = String(record.review_group_id)
		var group_records: Array[AssetReviewRecord] = _get_group_records(
			records_by_group,
			group_key
		)
		group_records.append(record)
		records_by_group[group_key] = group_records

	var group_ids: PackedStringArray = PackedStringArray(records_by_group.keys())
	group_ids.sort()
	report["group_count"] = group_ids.size()
	for group_id: String in group_ids:
		var group_records: Array[AssetReviewRecord] = _get_group_records(
			records_by_group,
			group_id
		)
		var plan: Dictionary = _SYNC_POLICY_SCRIPT.plan_from_consensus(group_records)
		var result: StringName = GFVariantData.to_string_name(plan.get("result"))
		match result:
			_SYNC_POLICY_SCRIPT.RESULT_READY:
				if not _apply_and_save_group(group_id, plan, report):
					report["ok"] = false
					return report
			_SYNC_POLICY_SCRIPT.RESULT_CONFLICT:
				report["conflict_group_count"] = (
					GFVariantData.get_option_int(report, "conflict_group_count") + 1
				)
				_append_string(report, "conflict_group_ids", group_id)
			_SYNC_POLICY_SCRIPT.RESULT_AMBIGUOUS:
				report["ambiguous_group_count"] = (
					GFVariantData.get_option_int(report, "ambiguous_group_count") + 1
				)
				_append_string(report, "ambiguous_group_ids", group_id)
			_SYNC_POLICY_SCRIPT.RESULT_NO_CHANGES:
				report["unchanged_group_count"] = (
					GFVariantData.get_option_int(report, "unchanged_group_count") + 1
				)
			_:
				report["invalid_group_count"] = (
					GFVariantData.get_option_int(report, "invalid_group_count") + 1
				)
				_append_string(report, "invalid_group_ids", group_id)

	if GFVariantData.get_option_int(report, "conflict_group_count") > 0:
		report["ok"] = false
		_append_issue(
			report,
			"review_group_conflict",
			"存在互相冲突的可试听人工结论；未覆盖这些评审组。"
		)
	if GFVariantData.get_option_int(report, "invalid_group_count") > 0:
		report["ok"] = false
		_append_issue(
			report,
			"invalid_review_group",
			"存在无法验证的评审组；未写入这些评审组。"
		)
	return report


func _apply_and_save_group(
	group_id: String,
	plan: Dictionary,
	report: Dictionary
) -> bool:
	var application: Dictionary = _SYNC_POLICY_SCRIPT.apply_plan(plan)
	if not GFVariantData.get_option_bool(application, "ok"):
		_append_issue(
			report,
			"sync_plan_apply_failed",
			"评审同步计划应用失败：%s。" % group_id
		)
		return false

	var saved_records: Array[AssetReviewRecord] = []
	for record_value: Variant in GFVariantData.get_option_array(
		application,
		"updated_records"
	):
		if not (record_value is AssetReviewRecord):
			_SYNC_POLICY_SCRIPT.revert_application(application)
			_rollback_saved_records(saved_records, report)
			_append_issue(
				report,
				"invalid_sync_target",
				"评审同步目标类型无效：%s。" % group_id
			)
			return false
		var record: AssetReviewRecord = record_value
		var save_result: Error = ResourceSaver.save(record, record.resource_path)
		if save_result != OK:
			_SYNC_POLICY_SCRIPT.revert_application(application)
			_rollback_saved_records(saved_records, report)
			_append_issue(
				report,
				"review_record_save_failed",
				"评审同步记录保存失败：%s（错误 %d）。"
				% [record.resource_path, save_result]
			)
			return false
		saved_records.append(record)

	report["updated_group_count"] = (
		GFVariantData.get_option_int(report, "updated_group_count") + 1
	)
	report["updated_record_count"] = (
		GFVariantData.get_option_int(report, "updated_record_count")
		+ GFVariantData.get_option_int(application, "updated_count")
	)
	_append_string(report, "updated_group_ids", group_id)
	return true


func _rollback_saved_records(
	saved_records: Array[AssetReviewRecord],
	report: Dictionary
) -> void:
	for record: AssetReviewRecord in saved_records:
		var rollback_result: Error = ResourceSaver.save(record, record.resource_path)
		if rollback_result == OK:
			continue
		_append_issue(
			report,
			"review_record_rollback_failed",
			"评审同步回滚失败：%s（错误 %d）。"
			% [record.resource_path, rollback_result]
		)


func _get_group_records(
	records_by_group: Dictionary,
	group_id: String
) -> Array[AssetReviewRecord]:
	var result: Array[AssetReviewRecord] = []
	var value: Variant = records_by_group.get(group_id)
	if value is Array:
		for record_value: Variant in value:
			if record_value is AssetReviewRecord:
				result.append(record_value)
	return result


func _summarize_scan_report(scan_report: Dictionary) -> Dictionary:
	var summary: Dictionary = scan_report.duplicate(true)
	var _erase_result: bool = summary.erase("paths")
	return summary


func _append_string(report: Dictionary, key: String, value: String) -> void:
	var values: PackedStringArray = GFVariantData.get_option_packed_string_array(
		report,
		key
	)
	if not values.has(value):
		var _append_result: bool = values.append(value)
	report[key] = values


func _append_issue(report: Dictionary, kind: String, message: String) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	issues.append({
		"kind": kind,
		"message": message,
	})
	report["issues"] = issues


func _make_report() -> Dictionary:
	return {
		"ok": true,
		"group_count": 0,
		"updated_group_count": 0,
		"updated_record_count": 0,
		"unchanged_group_count": 0,
		"ambiguous_group_count": 0,
		"conflict_group_count": 0,
		"invalid_group_count": 0,
		"updated_group_ids": PackedStringArray(),
		"ambiguous_group_ids": PackedStringArray(),
		"conflict_group_ids": PackedStringArray(),
		"invalid_group_ids": PackedStringArray(),
		"issues": [],
	}
