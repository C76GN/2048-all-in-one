## 验证素材评审浏览器的连续评审导航和键盘工作流。
extends GutTest


# --- 常量 ---

const REVIEW_SYNC_POLICY_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_review_sync_policy.gd"
)


# --- 测试用例 ---

func test_continuation_keeps_current_asset_when_it_still_matches_filter() -> void:
	var asset_ids: PackedStringArray = PackedStringArray([
		"asset.first",
		"asset.current",
		"asset.last",
	])

	var selected_index: int = AssetReviewBrowser.choose_continuation_index(
		asset_ids,
		"asset.current",
		1
	)

	assert_true(selected_index == 1, "当前素材仍匹配筛选时应保持选中。")


func test_continuation_selects_same_slot_after_reviewed_asset_leaves_inbox() -> void:
	var remaining_asset_ids: PackedStringArray = PackedStringArray([
		"asset.first",
		"asset.next",
		"asset.last",
	])

	var selected_index: int = AssetReviewBrowser.choose_continuation_index(
		remaining_asset_ids,
		"asset.reviewed",
		1
	)

	assert_true(selected_index == 1, "已评审素材离开 inbox 后应选择原位置的下一项。")


func test_continuation_clamps_to_previous_item_at_end_of_list() -> void:
	var remaining_asset_ids: PackedStringArray = PackedStringArray([
		"asset.first",
		"asset.previous",
	])

	var selected_index: int = AssetReviewBrowser.choose_continuation_index(
		remaining_asset_ids,
		"asset.reviewed",
		2
	)

	assert_true(selected_index == 1, "评审列表末项后应回退到仍存在的上一项。")


func test_review_shortcuts_map_to_fast_actions() -> void:
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_1))
			== &"candidate",
		"数字键 1 应设为候选。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_2))
			== &"approved",
		"数字键 2 应批准素材。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_3))
			== &"rejected",
		"数字键 3 应拒绝素材。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_SPACE))
			== &"toggle_preview",
		"空格应切换音频预览。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_J))
			== &"next",
		"J 应选择下一项。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_K))
			== &"previous",
		"K 应选择上一项。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_S, true))
			== &"save",
		"Ctrl+S 应保存当前评审。"
	)


func test_review_shortcuts_do_not_interrupt_text_editing() -> void:
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_3), true)
			== &"",
		"文本输入时不得触发裸键评审操作。"
	)
	assert_true(
		AssetReviewBrowser.get_review_shortcut_command(_make_key_event(KEY_S, true), true)
			== &"save",
		"文本输入时仍应允许 Ctrl+S 保存。"
	)


func test_audio_variant_group_id_matches_declared_transcode_roots() -> void:
	var variant_roots: PackedStringArray = PackedStringArray(["MP3", "OGG", "WAV"])
	var mp3_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"MP3/Minimalist1.mp3",
		variant_roots
	)
	var ogg_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"OGG/Minimalist1.ogg",
		variant_roots
	)
	var wav_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"WAV/Minimalist1.wav",
		variant_roots
	)

	assert_false(mp3_group_id.is_empty(), "显式声明的音频格式目录应生成稳定评审组 ID。")
	assert_true(
		mp3_group_id == ogg_group_id,
		"同来源包、同相对路径的 MP3 与 OGG 应属于同一声音。"
	)
	assert_true(
		mp3_group_id == wav_group_id,
		"同一声音的 WAV 应与有损编码变体共享评审分组。"
	)


func test_audio_variant_group_id_preserves_pack_and_semantic_directories() -> void:
	var variant_roots: PackedStringArray = PackedStringArray(["MP3", "OGG", "WAV"])
	var menu_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"MP3/Menu/Click.mp3",
		variant_roots
	)
	var game_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"OGG/Game/Click.ogg",
		variant_roots
	)
	var other_pack_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"other_pack",
		"OGG/Menu/Click.ogg",
		variant_roots
	)
	var undeclared_group_id: StringName = AssetReviewRecord.make_audio_variant_group_id(
		&"ui_pack",
		"FLAC/Menu/Click.flac",
		variant_roots
	)

	assert_true(
		menu_group_id != game_group_id,
		"用途目录不同的同名音频不得误合并。"
	)
	assert_true(
		menu_group_id != other_pack_group_id,
		"不同来源包的同名音频不得互相同步。"
	)
	assert_true(
		undeclared_group_id.is_empty(),
		"没有在来源包中显式声明的目录不得靠文件名猜测分组。"
	)


func test_audio_variant_status_copy_keeps_rendition_specific_review_fields() -> void:
	var source_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"MP3/Confirm.mp3",
		"mp3"
	)
	source_record.review_status = AssetReviewRecord.STATUS_APPROVED
	source_record.rating = 4
	source_record.notes = "适合作为确认反馈。"
	source_record.reviewed_at = "2026-07-26 10:00:00"
	source_record.tags = PackedStringArray(["audio", "mp3", "confirm"])
	source_record.review_group_id = &"review.group.ui_pack.confirm"
	source_record.preview_supported = true
	var target_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"OGG/Confirm.ogg",
		"ogg"
	)
	target_record.rating = 2
	target_record.notes = "OGG 编码试听备注。"
	target_record.tags = PackedStringArray(["audio", "ogg", "confirm"])
	target_record.review_group_id = source_record.review_group_id
	target_record.preview_supported = true

	var copied: bool = target_record.copy_review_status_from(source_record)

	assert_true(copied, "同组、可试听且未评审的格式变体应接受状态同步。")
	assert_true(
		target_record.review_status == AssetReviewRecord.STATUS_APPROVED,
		"格式变体应同步评审状态。"
	)
	assert_true(target_record.rating == 2, "同步不得覆盖目标编码自己的评分。")
	assert_true(target_record.notes == "OGG 编码试听备注。", "同步不得覆盖目标编码自己的备注。")
	assert_true(
		target_record.reviewed_at == "2026-07-26 10:00:00",
		"格式变体应同步同一次人工评审时间。"
	)
	assert_true(
		target_record.tags == PackedStringArray(["audio", "ogg", "confirm"]),
		"同步不得覆盖目标格式自己的标签。"
	)
	assert_true(target_record.relative_path == "OGG/Confirm.ogg", "同步不得改写目标素材路径。")
	assert_true(target_record.extension == "ogg", "同步不得改写目标编码格式。")


func test_unpreviewable_audio_cannot_drive_cross_format_review() -> void:
	var m4a_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"M4A/Confirm.m4a",
		"m4a"
	)
	m4a_record.review_group_id = &"review.group.ui_pack.confirm"
	m4a_record.preview_supported = false
	var ogg_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"OGG/Confirm.ogg",
		"ogg"
	)
	ogg_record.review_group_id = m4a_record.review_group_id
	ogg_record.preview_supported = true
	ogg_record.review_status = AssetReviewRecord.STATUS_APPROVED
	ogg_record.reviewed_at = "2026-07-26 10:00:00"

	assert_false(
		m4a_record.can_drive_audio_variant_review(),
		"无法在评审器试听的格式不得把拒绝结论传播到可播放版本。"
	)
	assert_false(
		m4a_record.copy_review_status_from(ogg_record),
		"不可试听格式也不得接收内容状态同步。"
	)
	assert_true(
		ogg_record.can_drive_audio_variant_review(),
		"可试听且有显式组 ID 的音频可以驱动同声音格式同步。"
	)


func test_audio_variant_status_copy_does_not_overwrite_existing_review() -> void:
	var source_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"MP3/Confirm.mp3",
		"mp3"
	)
	source_record.review_group_id = &"review.group.ui_pack.confirm"
	source_record.preview_supported = true
	source_record.review_status = AssetReviewRecord.STATUS_APPROVED
	source_record.reviewed_at = "2026-07-26 10:00:00"
	var target_record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		"OGG/Confirm.ogg",
		"ogg"
	)
	target_record.review_group_id = source_record.review_group_id
	target_record.preview_supported = true
	target_record.review_status = AssetReviewRecord.STATUS_REJECTED
	target_record.reviewed_at = "2026-07-26 09:00:00"

	var copied: bool = target_record.copy_review_status_from(source_record)

	assert_false(copied, "已有人工结论的格式变体不得被自动覆盖。")
	assert_true(
		target_record.review_status == AssetReviewRecord.STATUS_REJECTED,
		"冲突目标必须保留原评审状态。"
	)
	assert_true(
		target_record.reviewed_at == "2026-07-26 09:00:00",
		"冲突目标必须保留原评审时间。"
	)


func test_sync_consensus_updates_only_previewable_inbox_and_is_idempotent() -> void:
	var source_record: AssetReviewRecord = _make_group_record(
		"MP3/Confirm.mp3",
		"mp3",
		AssetReviewRecord.STATUS_APPROVED,
		"2026-07-26 10:00:00",
		true
	)
	var inbox_record: AssetReviewRecord = _make_group_record(
		"OGG/Confirm.ogg",
		"ogg",
		AssetReviewRecord.STATUS_INBOX,
		"",
		true
	)
	inbox_record.rating = 2
	inbox_record.notes = "保留 OGG 试听备注。"
	var unpreviewable_record: AssetReviewRecord = _make_group_record(
		"M4A/Confirm.m4a",
		"m4a",
		AssetReviewRecord.STATUS_INBOX,
		"",
		false
	)
	var records: Array[AssetReviewRecord] = [
		source_record,
		inbox_record,
		unpreviewable_record,
	]

	var plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_consensus(records)
	var application: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.apply_plan(plan)

	assert_true(
		GFVariantData.to_string_name(plan.get("result"))
			== REVIEW_SYNC_POLICY_SCRIPT.RESULT_READY,
		"唯一可试听共识应生成可应用计划。"
	)
	assert_true(GFVariantData.get_option_bool(application, "ok"), "一致计划应成功应用。")
	assert_true(
		GFVariantData.get_option_int(application, "updated_count") == 1,
		"只应更新仍为 inbox 的可试听格式。"
	)
	assert_true(
		inbox_record.review_status == AssetReviewRecord.STATUS_APPROVED,
		"可试听 inbox 格式应继承唯一状态。"
	)
	assert_true(
		inbox_record.reviewed_at == source_record.reviewed_at,
		"同一批次格式应共享评审时间。"
	)
	assert_true(inbox_record.rating == 2, "同步不得覆盖目标格式评分。")
	assert_true(inbox_record.notes == "保留 OGG 试听备注。", "同步不得覆盖目标格式备注。")
	assert_true(
		unpreviewable_record.review_status == AssetReviewRecord.STATUS_INBOX,
		"不可试听格式不得作为内容同步目标。"
	)
	var second_plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_consensus(
		records
	)
	assert_true(
		GFVariantData.to_string_name(second_plan.get("result"))
			== REVIEW_SYNC_POLICY_SCRIPT.RESULT_NO_CHANGES,
		"同一共识第二次运行必须是零写入。"
	)


func test_sync_consensus_conflict_is_atomic_noop() -> void:
	var approved_record: AssetReviewRecord = _make_group_record(
		"MP3/Confirm.mp3",
		"mp3",
		AssetReviewRecord.STATUS_APPROVED,
		"2026-07-26 10:00:00",
		true
	)
	var rejected_record: AssetReviewRecord = _make_group_record(
		"OGG/Confirm.ogg",
		"ogg",
		AssetReviewRecord.STATUS_REJECTED,
		"2026-07-26 10:01:00",
		true
	)
	var inbox_record: AssetReviewRecord = _make_group_record(
		"WAV/Confirm.wav",
		"wav",
		AssetReviewRecord.STATUS_INBOX,
		"",
		true
	)

	var plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_consensus([
		approved_record,
		rejected_record,
		inbox_record,
	])
	var application: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.apply_plan(plan)

	assert_true(
		GFVariantData.to_string_name(plan.get("result"))
			== REVIEW_SYNC_POLICY_SCRIPT.RESULT_CONFLICT,
		"同组存在不同人工终态时必须报告冲突。"
	)
	assert_false(
		GFVariantData.get_option_bool(application, "ok"),
		"冲突计划不得产生部分应用。"
	)
	assert_true(
		inbox_record.review_status == AssetReviewRecord.STATUS_INBOX,
		"冲突组的 inbox 记录必须保持不变。"
	)


func test_undated_previewable_decision_still_blocks_conflicting_consensus() -> void:
	var undated_rejection: AssetReviewRecord = _make_group_record(
		"MP3/Confirm.mp3",
		"mp3",
		AssetReviewRecord.STATUS_REJECTED,
		"",
		true
	)
	var approved_record: AssetReviewRecord = _make_group_record(
		"OGG/Confirm.ogg",
		"ogg",
		AssetReviewRecord.STATUS_APPROVED,
		"2026-07-26 10:00:00",
		true
	)
	var inbox_record: AssetReviewRecord = _make_group_record(
		"WAV/Confirm.wav",
		"wav",
		AssetReviewRecord.STATUS_INBOX,
		"",
		true
	)

	var plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_consensus([
		undated_rejection,
		approved_record,
		inbox_record,
	])

	assert_true(
		GFVariantData.to_string_name(plan.get("result"))
			== REVIEW_SYNC_POLICY_SCRIPT.RESULT_CONFLICT,
		"缺失时间戳的可试听人工结论仍必须参与冲突保护。"
	)
	assert_true(
		inbox_record.review_status == AssetReviewRecord.STATUS_INBOX,
		"旧数据冲突不得向未评审格式扩散。"
	)


func test_unpreviewable_only_decision_is_ambiguous_consensus() -> void:
	var m4a_record: AssetReviewRecord = _make_group_record(
		"M4A/Cursor.m4a",
		"m4a",
		AssetReviewRecord.STATUS_REJECTED,
		"2026-07-26 10:00:00",
		false
	)
	var ogg_record: AssetReviewRecord = _make_group_record(
		"OGG/Cursor.ogg",
		"ogg",
		AssetReviewRecord.STATUS_INBOX,
		"",
		true
	)

	var plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_consensus([
		m4a_record,
		ogg_record,
	])

	assert_true(
		GFVariantData.to_string_name(plan.get("result"))
			== REVIEW_SYNC_POLICY_SCRIPT.RESULT_AMBIGUOUS,
		"只有不可试听格式被拒绝时必须跳过内容状态传播。"
	)
	assert_true(
		ogg_record.review_status == AssetReviewRecord.STATUS_INBOX,
		"可试听格式应等待独立内容评审。"
	)


func test_previous_candidate_sync_cohort_can_advance_to_approved() -> void:
	var source_record: AssetReviewRecord = _make_group_record(
		"MP3/Confirm.mp3",
		"mp3",
		AssetReviewRecord.STATUS_CANDIDATE,
		"2026-07-26 09:00:00",
		true
	)
	var sibling_record: AssetReviewRecord = _make_group_record(
		"OGG/Confirm.ogg",
		"ogg",
		AssetReviewRecord.STATUS_CANDIDATE,
		"2026-07-26 09:00:00",
		true
	)
	var previous_status: StringName = source_record.review_status
	var previous_reviewed_at: String = source_record.reviewed_at
	source_record.review_status = AssetReviewRecord.STATUS_APPROVED
	source_record.reviewed_at = "2026-07-26 10:00:00"

	var plan: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.plan_from_source(
		source_record,
		[source_record, sibling_record],
		previous_status,
		previous_reviewed_at
	)
	var application: Dictionary = REVIEW_SYNC_POLICY_SCRIPT.apply_plan(plan)

	assert_true(GFVariantData.get_option_bool(application, "ok"), "同一同步 cohort 应允许继续推进状态。")
	assert_true(
		sibling_record.review_status == AssetReviewRecord.STATUS_APPROVED,
		"上次同步为 candidate 的 sibling 应随来源推进为 approved。"
	)
	assert_true(
		sibling_record.reviewed_at == source_record.reviewed_at,
		"推进后的 cohort 应共享新的评审时间。"
	)


func test_asset_review_record_is_available_to_editor_tools() -> void:
	var record: AssetReviewRecord = AssetReviewRecord.new()
	var record_script_value: Variant = record.get_script()

	assert_true(record_script_value is Script, "素材评审记录应保留可检查的项目脚本。")
	if record_script_value is Script:
		var record_script: Script = record_script_value
		assert_true(record_script.is_tool(), "素材评审记录必须能在编辑器工具场景中执行方法。")


func test_record_metadata_formats_every_declared_field() -> void:
	var browser: AssetReviewBrowser = AssetReviewBrowser.new()
	autofree(browser)
	var record: AssetReviewRecord = AssetReviewRecord.new()
	record.library_path = "res://candidate.ogg"
	record.source_pack_id = &"audio_pack"
	record.license_status = &"known"
	record.license = "CC0"
	record.suggested_slots = PackedStringArray(["ui.confirm"])

	var metadata_text: String = browser._format_record_meta(record)

	assert_true(metadata_text.contains("res://candidate.ogg"), "元数据摘要应包含素材路径。")
	assert_true(metadata_text.contains("audio_pack"), "元数据摘要应包含来源包。")
	assert_true(metadata_text.contains("known / CC0"), "元数据摘要应包含授权结论。")
	assert_true(metadata_text.contains("ui.confirm"), "元数据摘要应包含建议用途。")
	assert_true(metadata_text.contains("格式组"), "元数据摘要应包含格式组说明。")


# --- 私有/辅助方法 ---

func _make_group_record(
	relative_path: String,
	extension: String,
	status: StringName,
	reviewed_at: String,
	preview_supported: bool
) -> AssetReviewRecord:
	var record: AssetReviewRecord = _make_audio_record(
		&"ui_pack",
		relative_path,
		extension
	)
	record.review_group_id = &"review.group.ui_pack.confirm"
	record.review_status = status
	record.reviewed_at = reviewed_at
	record.preview_supported = preview_supported
	return record


func _make_audio_record(
	source_pack_id: StringName,
	relative_path: String,
	extension: String
) -> AssetReviewRecord:
	var record: AssetReviewRecord = AssetReviewRecord.new()
	record.source_pack_id = source_pack_id
	record.asset_kind = AssetReviewRecord.KIND_AUDIO
	record.relative_path = relative_path
	record.extension = extension
	return record


func _make_key_event(keycode: Key, ctrl_pressed: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl_pressed
	return event
