## 验证素材评审浏览器的连续评审导航和键盘工作流。
extends GutTest


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


# --- 私有/辅助方法 ---

func _make_key_event(keycode: Key, ctrl_pressed: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl_pressed
	return event
