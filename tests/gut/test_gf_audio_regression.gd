## 验证官方 GF 音频生命周期在 SceneTree 先释放播放器时仍可安全收敛。
extends GutTest


func test_dispose_tolerates_bgm_players_released_by_scene_tree() -> void:
	var audio: GFAudioUtility = GFAudioUtility.new()
	audio.init()
	await get_tree().process_frame
	await get_tree().process_frame

	var bgm_player_value: Variant = audio.get("_bgm_player")
	var fade_player_value: Variant = audio.get("_bgm_fade_player")
	assert_true(bgm_player_value is AudioStreamPlayer, "GF 应创建主 BGM 播放器。")
	assert_true(fade_player_value is AudioStreamPlayer, "GF 应创建淡变 BGM 播放器。")
	if bgm_player_value is AudioStreamPlayer:
		var bgm_player: AudioStreamPlayer = bgm_player_value
		bgm_player.free()
	if fade_player_value is AudioStreamPlayer:
		var fade_player: AudioStreamPlayer = fade_player_value
		fade_player.free()

	audio.dispose()

	assert_push_error_count(0, "SceneTree 先释放播放器后，音频 Utility dispose 不应产生错误。")
