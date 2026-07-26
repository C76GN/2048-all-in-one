## 验证语义音效不会因层级回退而退化为“格式不同、听感相同”的同一反馈。
extends GutTest


# --- 常量 ---

const _THEME_MANIFEST_PATH: String = (
	"res://features/themes/resources/gf_content_package.json"
)


# --- 测试用例 ---

func test_all_runtime_semantic_events_resolve_to_direct_distinct_clips() -> void:
	var audio_themes: Array[GameAudioTheme] = _load_catalog_audio_themes()
	assert_false(audio_themes.is_empty(), "内容包必须声明至少一个音效主题。")
	for audio_theme: GameAudioTheme in audio_themes:
		assert_true(
			is_instance_valid(audio_theme.audio_bank),
			"音效主题 %s 必须提供音频银行。" % audio_theme.theme_id
		)
		if not is_instance_valid(audio_theme.audio_bank):
			continue

		var event_ids: Array[StringName] = _get_runtime_event_ids(audio_theme)
		var resolved_paths: Dictionary = {}
		for event_id: StringName in event_ids:
			var resolution: Dictionary = audio_theme.audio_bank.resolve_clip(event_id)
			assert_true(
				GFVariantData.get_option_bool(resolution, &"ok"),
				"主题 %s 的语义事件 %s 必须解析到音效。" % [
					audio_theme.theme_id,
					event_id,
				]
			)
			assert_false(
				GFVariantData.get_option_bool(resolution, &"fallback_used"),
				"主题 %s 的语义事件 %s 必须使用直接映射，不能退回父事件。" % [
					audio_theme.theme_id,
					event_id,
				]
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
				"主题 %s 的事件 %s 与 %s 不能复用同一音频文件。" % [
					audio_theme.theme_id,
					event_id,
					GFVariantData.get_option_string_name(resolved_paths, clip.path),
				]
			)
			resolved_paths[clip.path] = event_id

		assert_true(
			resolved_paths.size() == event_ids.size(),
			"主题 %s 的 11 个运行时语义事件必须对应 11 份独立音频文件。"
			% audio_theme.theme_id
		)
		assert_true(
			audio_theme.get_validation_report().is_ok(),
			"主题 %s 必须由 GameAudioTheme validation 自身执行 direct + unique 契约。"
			% audio_theme.theme_id
		)


func test_new_semantic_clips_keep_review_provenance() -> void:
	for audio_theme: GameAudioTheme in _load_catalog_audio_themes():
		for event_id: StringName in [
			audio_theme.ui_cancel_event,
			audio_theme.tile_move_blocked_event,
			audio_theme.tile_merge_chain_event,
			audio_theme.tile_transform_event,
			audio_theme.target_reached_event,
		]:
			var clip: GFAudioClip = audio_theme.audio_bank.get_clip(event_id)
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


# --- 私有/辅助方法 ---

func _load_catalog_audio_themes() -> Array[GameAudioTheme]:
	var result: Array[GameAudioTheme] = []
	var file: FileAccess = FileAccess.open(_THEME_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed_value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed_value is Dictionary:
		return result
	var manifest: Dictionary = parsed_value
	var manifest_directory: String = _THEME_MANIFEST_PATH.get_base_dir()
	for entry_value: Variant in GFVariantData.get_option_array(manifest, &"resources"):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, &"metadata")
		if GFVariantData.get_option_string(metadata, &"catalog_role") != "sound_theme":
			continue
		var relative_path: String = GFVariantData.get_option_string(entry, &"path")
		var resource_value: Resource = load(manifest_directory.path_join(relative_path))
		if resource_value is GameAudioTheme:
			var audio_theme: GameAudioTheme = resource_value
			result.append(audio_theme)
	return result


func _get_runtime_event_ids(audio_theme: GameAudioTheme) -> Array[StringName]:
	return [
		audio_theme.ui_select_event,
		audio_theme.ui_confirm_event,
		audio_theme.ui_cancel_event,
		audio_theme.tile_spawn_event,
		audio_theme.tile_move_event,
		audio_theme.tile_move_blocked_event,
		audio_theme.tile_merge_event,
		audio_theme.tile_merge_chain_event,
		audio_theme.tile_transform_event,
		audio_theme.target_reached_event,
		audio_theme.game_over_event,
	]
