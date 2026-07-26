## AssetReviewSyncPolicy: 为同一声音的可试听编码变体规划保守的评审状态同步。
class_name AssetReviewSyncPolicy
extends RefCounted


# --- 常量 ---

const RESULT_READY: StringName = &"ready"
const RESULT_NO_CHANGES: StringName = &"no_changes"
const RESULT_CONFLICT: StringName = &"conflict"
const RESULT_AMBIGUOUS: StringName = &"ambiguous"
const RESULT_INVALID: StringName = &"invalid"


# --- 公共方法 ---

## 根据用户刚保存的来源记录规划同步，并允许上次同步 cohort 继续推进状态。
## @param source: 已写入新状态和新评审时间的当前记录。
## @param records: 同一显式 review_group_id 下的全部记录。
## @param previous_status: 当前记录保存前的状态。
## @param previous_reviewed_at: 当前记录保存前的评审时间。
## @return 包含 result、source_record、target_entries 和 reviewed_at 的计划。
static func plan_from_source(
	source: AssetReviewRecord,
	records: Array[AssetReviewRecord],
	previous_status: StringName,
	previous_reviewed_at: String
) -> Dictionary:
	if source == null or not source.can_drive_audio_variant_review():
		return _make_plan(RESULT_INVALID, source, [])
	var target_entries: Array[Dictionary] = []
	for candidate: AssetReviewRecord in records:
		if not _is_syncable_group_member(source, candidate) or candidate == source:
			continue
		if candidate.review_status == source.review_status:
			continue
		if candidate.review_status == AssetReviewRecord.STATUS_INBOX:
			target_entries.append(_make_target_entry(candidate))
			continue
		if (
			not previous_reviewed_at.is_empty()
			and candidate.review_status == previous_status
			and candidate.reviewed_at == previous_reviewed_at
		):
			target_entries.append(_make_target_entry(candidate))
			continue
		return _make_plan(RESULT_CONFLICT, source, [])
	if target_entries.is_empty():
		return _make_plan(RESULT_NO_CHANGES, source, [])
	return _make_plan(RESULT_READY, source, target_entries)


## 从一组现有记录的唯一可试听共识规划 inbox 回填。
## @param records: 同一显式 review_group_id 下的全部记录。
## @return 唯一共识可回填时为 ready；冲突或仅不可试听来源时返回保护状态。
static func plan_from_consensus(records: Array[AssetReviewRecord]) -> Dictionary:
	var group_id: StringName = &""
	var source_records: Array[AssetReviewRecord] = []
	var previewable_decisions: Array[AssetReviewRecord] = []
	var has_unpreviewable_decision: bool = false
	for record: AssetReviewRecord in records:
		if record == null or record.review_group_id == &"":
			continue
		if group_id == &"":
			group_id = record.review_group_id
		elif record.review_group_id != group_id:
			return _make_plan(RESULT_INVALID, null, [])
		if record.review_status == AssetReviewRecord.STATUS_INBOX:
			continue
		if not record.is_audio() or not record.preview_supported:
			has_unpreviewable_decision = true
			continue
		previewable_decisions.append(record)
		if not record.reviewed_at.is_empty():
			source_records.append(record)
	if previewable_decisions.is_empty():
		return _make_plan(
			RESULT_AMBIGUOUS if has_unpreviewable_decision else RESULT_NO_CHANGES,
			null,
			[]
		)

	var consensus_status: StringName = previewable_decisions[0].review_status
	for candidate: AssetReviewRecord in previewable_decisions:
		if candidate.review_status != consensus_status:
			return _make_plan(
				RESULT_CONFLICT,
				_choose_latest_source(source_records) if not source_records.is_empty() else null,
				[]
			)
	if source_records.is_empty():
		return _make_plan(RESULT_AMBIGUOUS, null, [])
	var source: AssetReviewRecord = _choose_latest_source(source_records)
	var target_entries: Array[Dictionary] = []
	for candidate: AssetReviewRecord in records:
		if not _is_syncable_group_member(source, candidate) or candidate == source:
			continue
		if candidate.review_status == AssetReviewRecord.STATUS_INBOX:
			target_entries.append(_make_target_entry(candidate))
	if target_entries.is_empty():
		return _make_plan(RESULT_NO_CHANGES, source, [])
	return _make_plan(RESULT_READY, source, target_entries)


## 原子地应用仍与计划快照一致的目标，并返回可回滚的变更列表。
## @param plan: 由本策略生成的 ready 计划。
## @return 包含 ok、updated_count、updated_records 和 changes 的应用报告。
static func apply_plan(plan: Dictionary) -> Dictionary:
	var report: Dictionary = {
		"ok": false,
		"updated_count": 0,
		"updated_records": [],
		"changes": [],
	}
	if GFVariantData.to_string_name(plan.get("result", &"")) != RESULT_READY:
		return report
	var source_value: Variant = plan.get("source_record")
	if not (source_value is AssetReviewRecord):
		return report
	var source: AssetReviewRecord = source_value
	if not source.can_drive_audio_variant_review():
		return report
	var target_entries: Array = GFVariantData.get_option_array(plan, "target_entries")
	for entry_value: Variant in target_entries:
		if not (entry_value is Dictionary):
			return report
		var entry: Dictionary = entry_value
		var target_value: Variant = entry.get("record")
		if not (target_value is AssetReviewRecord):
			return report
		var target: AssetReviewRecord = target_value
		if (
			target.review_status
				!= GFVariantData.to_string_name(entry.get("expected_status"))
			or target.reviewed_at
				!= GFVariantData.to_text(entry.get("expected_reviewed_at"))
		):
			return report

	var updated_records: Array[AssetReviewRecord] = []
	var changes: Array[Dictionary] = []
	for entry_value: Variant in target_entries:
		var entry: Dictionary = entry_value
		var target_value: Variant = entry.get("record")
		if not (target_value is AssetReviewRecord):
			return report
		var target: AssetReviewRecord = target_value
		changes.append({
			"record": target,
			"previous_status": target.review_status,
			"previous_reviewed_at": target.reviewed_at,
		})
		target.review_status = source.review_status
		target.reviewed_at = source.reviewed_at
		updated_records.append(target)
	report["ok"] = true
	report["updated_count"] = updated_records.size()
	report["updated_records"] = updated_records
	report["changes"] = changes
	return report


## 恢复 apply_plan 返回的内存变更。
## @param application: apply_plan 返回的应用报告。
static func revert_application(application: Dictionary) -> void:
	for change_value: Variant in GFVariantData.get_option_array(application, "changes"):
		if not (change_value is Dictionary):
			continue
		var change: Dictionary = change_value
		var record_value: Variant = change.get("record")
		if not (record_value is AssetReviewRecord):
			continue
		var record: AssetReviewRecord = record_value
		record.review_status = GFVariantData.to_string_name(
			change.get("previous_status"),
			AssetReviewRecord.STATUS_INBOX
		)
		record.reviewed_at = GFVariantData.to_text(
			change.get("previous_reviewed_at")
		)


# --- 私有/辅助方法 ---

static func _is_syncable_group_member(
	source: AssetReviewRecord,
	candidate: AssetReviewRecord
) -> bool:
	return (
		source != null
		and candidate != null
		and candidate.is_audio()
		and candidate.preview_supported
		and candidate.review_group_id == source.review_group_id
	)


static func _choose_latest_source(
	source_records: Array[AssetReviewRecord]
) -> AssetReviewRecord:
	var latest: AssetReviewRecord = source_records[0]
	for candidate: AssetReviewRecord in source_records:
		if candidate.reviewed_at > latest.reviewed_at:
			latest = candidate
	return latest


static func _make_target_entry(record: AssetReviewRecord) -> Dictionary:
	return {
		"record": record,
		"expected_status": record.review_status,
		"expected_reviewed_at": record.reviewed_at,
	}


static func _make_plan(
	result: StringName,
	source: AssetReviewRecord,
	target_entries: Array
) -> Dictionary:
	return {
		"result": result,
		"source_record": source,
		"target_entries": target_entries,
		"reviewed_at": source.reviewed_at if source != null else "",
	}
