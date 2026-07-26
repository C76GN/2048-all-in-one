## 验证语义音效不会因层级回退而退化为“格式不同、听感相同”的同一反馈。
extends GutTest


# --- 常量 ---

const _AUDIO_THEME: GameAudioTheme = preload(
	"res://features/themes/resources/themes/game/printworks_audio_theme.tres"
)


# --- 测试用例 ---

func test_all_runtime_semantic_events_resolve_to_direct_distinct_clips() -> void:
	assert_true(is_instance_valid(_AUDIO_THEME.audio_bank), "音效主题必须提供音频银行。")
	if not is_instance_valid(_AUDIO_THEME.audio_bank):
		return

	var event_ids: Array[StringName] = [
		_AUDIO_THEME.ui_select_event,
		_AUDIO_THEME.ui_confirm_event,
		_AUDIO_THEME.ui_cancel_event,
		_AUDIO_THEME.tile_spawn_event,
		_AUDIO_THEME.tile_move_event,
		_AUDIO_THEME.tile_move_blocked_event,
		_AUDIO_THEME.tile_merge_event,
		_AUDIO_THEME.tile_merge_chain_event,
		_AUDIO_THEME.tile_transform_event,
		_AUDIO_THEME.target_reached_event,
		_AUDIO_THEME.game_over_event,
	]
	var resolved_paths: Dictionary = {}
	for event_id: StringName in event_ids:
		var resolution: Dictionary = _AUDIO_THEME.audio_bank.resolve_clip(event_id)
		assert_true(
			GFVariantData.get_option_bool(resolution, &"ok"),
			"语义事件 %s 必须解析到音效。" % event_id
		)
		assert_false(
			GFVariantData.get_option_bool(resolution, &"fallback_used"),
			"语义事件 %s 必须使用直接映射，不能退回父事件。" % event_id
		)
		var clip_value: Variant = GFVariantData.get_option_value(resolution, &"clip")
		assert_true(clip_value is GFAudioClip, "语义事件必须解析为 GFAudioClip。")
		if not clip_value is GFAudioClip:
			continue
		var clip: GFAudioClip = clip_value
		assert_false(clip.path.is_empty(), "语义音效路径不能为空。")
		assert_true(FileAccess.file_exists(clip.path), "语义音效文件必须存在：%s。" % clip.path)
		assert_true(clip.bus_name == "SFX", "语义音效必须进入独立 SFX 总线。")
		assert_false(
			resolved_paths.has(clip.path),
			"事件 %s 与 %s 不能复用同一音频文件。" % [
				event_id,
				GFVariantData.get_option_string_name(resolved_paths, clip.path),
			]
		)
		resolved_paths[clip.path] = event_id

	assert_true(
		resolved_paths.size() == event_ids.size(),
		"11 个运行时语义事件必须对应 11 份独立音频文件。"
	)


func test_new_semantic_clips_keep_review_provenance() -> void:
	for event_id: StringName in [
		_AUDIO_THEME.ui_cancel_event,
		_AUDIO_THEME.tile_move_blocked_event,
		_AUDIO_THEME.tile_merge_chain_event,
		_AUDIO_THEME.tile_transform_event,
		_AUDIO_THEME.target_reached_event,
	]:
		var clip: GFAudioClip = _AUDIO_THEME.audio_bank.get_clip(event_id)
		assert_true(is_instance_valid(clip), "新增语义音效必须直接存在于 bank。")
		if not is_instance_valid(clip):
			continue
		assert_false(
			GFVariantData.get_option_string_name(
				clip.metadata,
				&"review_asset_id"
			) == &"",
			"新增语义音效必须保留已审批素材记录 ID。"
		)
