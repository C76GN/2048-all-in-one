## 验证项目素材评审库的源包导入、候选记录和用途槽位映射。
extends GutTest


# --- 常量 ---

const IMPORT_SOURCES_PATH: String = "res://features/asset_library/resources/import_sources.json"
const SLOT_MAP_PATH: String = "res://features/asset_library/resources/review/asset_slot_map.tres"
const COORDINATE_GRID_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/world_space_coordinate_grid_1e36eed0.tres"
const COORDINATE_GRID_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/world_space_coordinate_grid.gdshader"
const MASK_TRANSITION_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/luminance_mask_texture_transition_aa1d8745.tres"
const MASK_TRANSITION_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/luminance_mask_texture_transition.gdshader"
const SHINE_SWEEP_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/shine_sweep_overlay_2683bab7.tres"
const SHINE_SWEEP_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/shine_sweep_overlay.gdshader"
const SHINE_SWEEP_ASSET_ID: String = "asset.review.manual.shader.notes.shine.sweep.overlay.2683bab7"
const SURFACE_MASKED_SHINE_SWEEP_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/surface_masked_shine_sweep_c6f76108.tres"
const SURFACE_MASKED_SHINE_SWEEP_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/surface_masked_shine_sweep.gdshader"
const SURFACE_MASKED_SHINE_SWEEP_ASSET_ID: String = "asset.review.manual.shader.notes.surface.masked.shine.sweep.c6f76108"
const SPACE_BACKGROUND_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/space_cloud_starfield_background_93f9a76f.tres"
const SPACE_BACKGROUND_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/space_cloud_starfield_background.gdshader"
const SPACE_BACKGROUND_ASSET_ID: String = "asset.review.manual.shader.notes.space.cloud.starfield.background.93f9a76f"
const FLICKER_NOISE_BACKGROUND_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/flicker_noise_background_7c2f83c3.tres"
const FLICKER_NOISE_BACKGROUND_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/flicker_noise_background.gdshader"
const FLICKER_NOISE_BACKGROUND_ASSET_ID: String = "asset.review.manual.shader.notes.flicker.noise.background.7c2f83c3"
const GYROID_FBM_BACKGROUND_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/gyroid_fbm_background_eeb8815a.tres"
const GYROID_FBM_BACKGROUND_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/gyroid_fbm_background.gdshader"
const GYROID_FBM_BACKGROUND_ASSET_ID: String = "asset.review.manual.shader.notes.gyroid.fbm.background.eeb8815a"
const RAIN_SNOW_WEATHER_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/rain_snow_weather_overlay_513017af.tres"
const RAIN_SNOW_WEATHER_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/rain_snow_weather_overlay.gdshader"
const RAIN_SNOW_WEATHER_ASSET_ID: String = "asset.review.manual.shader.notes.rain.snow.weather.overlay.513017af"
const STEAMPUNKDEMON_RAIN_SNOW_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/steampunkdemon_rain_snow_overlay_638a6683.tres"
const STEAMPUNKDEMON_RAIN_SNOW_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/steampunkdemon_rain_snow_overlay.gdshader"
const STEAMPUNKDEMON_RAIN_SNOW_ASSET_ID: String = "asset.review.manual.shader.notes.steampunkdemon.rain.snow.overlay.638a6683"
const GLITCH_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/chromatic_aberration_glitch_c807ca4f.tres"
const GLITCH_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/chromatic_aberration_glitch.gdshader"
const GLITCH_ASSET_ID: String = "asset.review.manual.shader.notes.chromatic.aberration.glitch.c807ca4f"
const SCREEN_LENS_SHOCKWAVE_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/screen_lens_aberration_shockwave_5dfa21fd.tres"
const SCREEN_LENS_SHOCKWAVE_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/screen_lens_aberration_shockwave.gdshader"
const SCREEN_LENS_SHOCKWAVE_ASSET_ID: String = "asset.review.manual.shader.notes.screen.lens.aberration.shockwave.5dfa21fd"
const NEW_ITEM_RADIAL_SHINE_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/new_item_radial_shine_4ccdcf74.tres"
const NEW_ITEM_RADIAL_SHINE_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/new_item_radial_shine.gdshader"
const NEW_ITEM_RADIAL_SHINE_ASSET_ID: String = "asset.review.manual.shader.notes.new.item.radial.shine.4ccdcf74"
const HATCH_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/hand_drawn_hatch_tile_pattern_58c15683.tres"
const HATCH_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/hand_drawn_hatch_tile_pattern.gdshader"
const HATCH_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.hand.drawn.hatch.tile.pattern.58c15683"
const ANIMATED_CHECKER_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/animated_checker_tile_pattern_4b84449f.tres"
const ANIMATED_CHECKER_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/animated_checker_tile_pattern.gdshader"
const ANIMATED_CHECKER_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.animated.checker.tile.pattern.4b84449f"
const ANGLED_STRIPE_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/angled_stripe_tile_pattern_a1c96b85.tres"
const ANGLED_STRIPE_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/angled_stripe_tile_pattern.gdshader"
const ANGLED_STRIPE_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.angled.stripe.tile.pattern.a1c96b85"
const SINE_WAVE_STRIPE_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/sine_wave_stripe_pattern_a7a2d8b2.tres"
const SINE_WAVE_STRIPE_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/sine_wave_stripe_pattern.gdshader"
const SINE_WAVE_STRIPE_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.sine.wave.stripe.pattern.a7a2d8b2"
const NOISE_NODE_LINK_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/noise_node_link_tile_pattern_27ec9424.tres"
const NOISE_NODE_LINK_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/noise_node_link_tile_pattern.gdshader"
const NOISE_NODE_LINK_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.noise.node.link.tile.pattern.27ec9424"
const SQUARE_WAVE_PATTERN_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_shader_notes/square_wave_tile_pattern_aef95b1d.tres"
const SQUARE_WAVE_PATTERN_SHADER_PATH: String = "res://features/asset_library/resources/source_packs/manual_shader_notes/files/square_wave_tile_pattern.gdshader"
const SQUARE_WAVE_PATTERN_ASSET_ID: String = "asset.review.manual.shader.notes.square.wave.tile.pattern.aef95b1d"
const BURN_RECIPE_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_effect_notes/click_uv_radius_burn_card_recipe_293dea5f.tres"
const BURN_RECIPE_PATH: String = "res://features/asset_library/resources/source_packs/manual_effect_notes/files/click_uv_radius_burn_card_recipe.md"
const BURN_RECIPE_ASSET_ID: String = "asset.review.manual.effect.notes.click.uv.radius.burn.card.recipe.293dea5f"
const BUTTON_WOBBLE_RECIPE_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_effect_notes/interactive_button_follow_wobble_recipe_8a5fa6f0.tres"
const BUTTON_WOBBLE_RECIPE_PATH: String = "res://features/asset_library/resources/source_packs/manual_effect_notes/files/interactive_button_follow_wobble_recipe.md"
const BUTTON_WOBBLE_RECIPE_ASSET_ID: String = "asset.review.manual.effect.notes.interactive.button.follow.wobble.recipe.8a5fa6f0"
const POOLED_DROP_RECIPE_RECORD_PATH: String = "res://features/asset_library/resources/review/records/manual_effect_notes/pooled_shader_drop_controller_recipe_54f8901e.tres"
const POOLED_DROP_RECIPE_PATH: String = "res://features/asset_library/resources/source_packs/manual_effect_notes/files/pooled_shader_drop_controller_recipe.md"
const POOLED_DROP_RECIPE_ASSET_ID: String = "asset.review.manual.effect.notes.pooled.shader.drop.controller.recipe.54f8901e"


# --- 测试用例 ---

func test_import_sources_config_tracks_requested_source_packs() -> void:
	var config: Dictionary = _read_json(IMPORT_SOURCES_PATH)
	var source_packs: Array = GFVariantData.get_option_array(config, "source_packs")
	var source_pack_ids: PackedStringArray = _collect_source_pack_ids(source_packs)

	assert_true(source_packs.size() == 5, "素材导入配置应登记 5 个待评审源包。")
	assert_true(source_pack_ids.has("universal_ui_soundpack"), "应登记 Universal UI Soundpack。")
	assert_true(source_pack_ids.has("jdsherbert_ultimate_ui_sfx_free_mono"), "应登记 JDSherbert UI 音效包。")
	assert_true(source_pack_ids.has("downloaded_shader_pack"), "应登记下载的 shader 包。")
	assert_true(source_pack_ids.has("four_hundred_sounds_pack"), "应登记 400 Sounds Pack。")
	assert_true(source_pack_ids.has("ultimate_toon_source"), "应登记 Ultimate Toon Source。")


func test_review_catalog_reports_imported_records_without_polluting_runtime_package() -> void:
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	var runtime_report: Dictionary = asset_library.build_audit_report()
	var review_report: Dictionary = asset_library.build_review_catalog_report()
	var kind_counts: Dictionary = GFVariantData.get_option_dictionary(review_report, "kind_counts")
	var status_counts: Dictionary = GFVariantData.get_option_dictionary(review_report, "status_counts")

	assert_true(GFVariantData.get_option_int(runtime_report, "resource_count") == 11, "运行时素材包仍应只包含已批准资源。")
	assert_true(GFVariantData.get_option_int(runtime_report, "issue_count") == 0, "源素材包不应触发运行时未登记文件警告。")
	assert_true(GFVariantData.get_option_int(review_report, "review_record_count") >= 560, "评审目录应包含全量候选素材。")
	assert_true(GFVariantData.get_option_int(kind_counts, "audio") >= 560, "评审目录应包含音频候选。")
	assert_true(GFVariantData.get_option_int(kind_counts, "shader") >= 19, "评审目录应包含 shader 候选。")
	assert_true(GFVariantData.get_option_int(kind_counts, "vfx") >= 3, "评审目录应包含 VFX 候选。")
	assert_true(GFVariantData.get_option_int(status_counts, "inbox") >= 560, "新导入素材默认应处于 inbox 状态。")


func test_review_catalog_keeps_unknown_license_assets_review_only() -> void:
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	var report: Dictionary = asset_library.build_review_catalog_report()
	var source_pack_license_counts: Dictionary = GFVariantData.get_option_dictionary(report, "license_counts")
	var record_license_counts: Dictionary = GFVariantData.get_option_dictionary(report, "record_license_counts")

	assert_true(GFVariantData.get_option_int(source_pack_license_counts, "known") == 1, "当前只有 Universal UI Soundpack 授权已确认。")
	assert_true(GFVariantData.get_option_int(source_pack_license_counts, "unknown") == 6, "其余源包应保持授权待确认。")
	assert_true(GFVariantData.get_option_int(record_license_counts, "known") == 157, "已知授权候选记录数量应来自 UI Soundpack 音频和已确认 MIT shader。")
	assert_true(GFVariantData.get_option_int(record_license_counts, "unknown") >= 400, "未知授权素材应保留在评审区，不应自动批准。")
	assert_true(GFVariantData.get_option_int(report, "error_count") == 0, "未知授权源包只应产生 warning，不能阻断审计。")


func test_manual_coordinate_grid_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(COORDINATE_GRID_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动坐标网格 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == COORDINATE_GRID_SHADER_PATH, "评审记录应指向候选 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "坐标网格候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "坐标网格候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.debug.coordinate_grid"), "坐标网格候选应声明 debug grid 用途槽位。")


func test_manual_luminance_mask_transition_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(MASK_TRANSITION_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动亮度遮罩转场 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == MASK_TRANSITION_SHADER_PATH, "评审记录应指向候选转场 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "亮度遮罩转场候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "亮度遮罩转场候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.transition.scene_wipe"), "亮度遮罩转场候选应声明 scene_wipe 用途槽位。")


func test_manual_shine_sweep_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SHINE_SWEEP_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动扫光 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SHINE_SWEEP_SHADER_PATH, "评审记录应指向候选扫光 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "扫光候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "扫光候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.ui.shine_sweep"), "扫光候选应声明 UI 高亮用途槽位。")


func test_manual_surface_masked_shine_sweep_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SURFACE_MASKED_SHINE_SWEEP_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动表面遮罩扫光 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SURFACE_MASKED_SHINE_SWEEP_SHADER_PATH, "评审记录应指向候选表面遮罩扫光 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "表面遮罩扫光候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "表面遮罩扫光候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.ui.shine_sweep"), "表面遮罩扫光候选应声明 UI 高亮用途槽位。")


func test_manual_space_background_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SPACE_BACKGROUND_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动太空背景 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SPACE_BACKGROUND_SHADER_PATH, "评审记录应指向候选太空背景 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "太空背景候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "太空背景候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.background.space_clouds"), "太空背景候选应声明背景用途槽位。")


func test_manual_flicker_noise_background_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(FLICKER_NOISE_BACKGROUND_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动闪烁噪声背景 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == FLICKER_NOISE_BACKGROUND_SHADER_PATH, "评审记录应指向候选闪烁噪声背景 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "闪烁噪声背景候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "闪烁噪声背景候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.background.main"), "闪烁噪声背景候选应声明主背景用途槽位。")


func test_manual_gyroid_fbm_background_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(GYROID_FBM_BACKGROUND_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动 gyroid FBM 背景 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == GYROID_FBM_BACKGROUND_SHADER_PATH, "评审记录应指向候选 gyroid FBM 背景 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "gyroid FBM 背景候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "gyroid FBM 背景候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "确认 Shadertoy 授权前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.background.main"), "gyroid FBM 背景候选应声明主背景用途槽位。")


func test_manual_rain_snow_weather_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(RAIN_SNOW_WEATHER_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动雨雪天气 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == RAIN_SNOW_WEATHER_SHADER_PATH, "评审记录应指向候选雨雪天气 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "雨雪天气候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "雨雪天气候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.weather.rain_snow_overlay"), "雨雪天气候选应声明 weather overlay 用途槽位。")


func test_manual_steampunkdemon_rain_snow_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(STEAMPUNKDEMON_RAIN_SNOW_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "Brian Smith MIT 雨雪 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == STEAMPUNKDEMON_RAIN_SNOW_SHADER_PATH, "评审记录应指向候选 Brian Smith 雨雪 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "Brian Smith 雨雪候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "Brian Smith 雨雪候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"known", "已声明 MIT 的 Brian Smith 雨雪候选应标记为 known 授权。")
	assert_true(GFVariantData.to_text(record.get("license")) == "MIT", "Brian Smith 雨雪候选应记录 MIT 授权。")
	assert_true(suggested_slots.has("slot.shader.weather.rain_snow_overlay"), "Brian Smith 雨雪候选应声明 weather overlay 用途槽位。")


func test_manual_glitch_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(GLITCH_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动故障 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == GLITCH_SHADER_PATH, "评审记录应指向候选故障 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "故障候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "故障候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.vfx.glitch_aberration"), "故障候选应声明 VFX 用途槽位。")


func test_manual_screen_lens_shockwave_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SCREEN_LENS_SHOCKWAVE_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动屏幕镜头色散冲击波 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SCREEN_LENS_SHOCKWAVE_SHADER_PATH, "评审记录应指向候选屏幕镜头冲击波 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "屏幕镜头冲击波候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "屏幕镜头冲击波候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.vfx.glitch_aberration"), "屏幕镜头冲击波候选应声明 VFX 色散用途槽位。")


func test_manual_new_item_radial_shine_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(NEW_ITEM_RADIAL_SHINE_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动获得新物品径向闪光 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == NEW_ITEM_RADIAL_SHINE_SHADER_PATH, "评审记录应指向候选获得新物品闪光 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "获得新物品闪光候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "获得新物品闪光候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.vfx.new_item_radial_shine"), "获得新物品闪光候选应声明 new item reward 用途槽位。")


func test_manual_hatch_tile_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(HATCH_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手绘斜线方块图案 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == HATCH_PATTERN_SHADER_PATH, "评审记录应指向候选方块图案 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "方块图案候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "方块图案候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "方块图案候选应声明 tile pattern 用途槽位。")


func test_manual_animated_checker_tile_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(ANIMATED_CHECKER_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动动画棋盘方块图案 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == ANIMATED_CHECKER_PATTERN_SHADER_PATH, "评审记录应指向候选动画棋盘图案 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "动画棋盘图案候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "动画棋盘图案候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "动画棋盘图案候选应声明 tile pattern 用途槽位。")


func test_manual_angled_stripe_tile_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(ANGLED_STRIPE_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动斜向条纹方块图案 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == ANGLED_STRIPE_PATTERN_SHADER_PATH, "评审记录应指向候选斜向条纹方块图案 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "斜向条纹方块图案候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "斜向条纹方块图案候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "斜向条纹方块图案候选应声明 tile pattern 用途槽位。")


func test_manual_sine_wave_stripe_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SINE_WAVE_STRIPE_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动正弦波条纹 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SINE_WAVE_STRIPE_PATTERN_SHADER_PATH, "评审记录应指向候选正弦波条纹 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "正弦波条纹候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "正弦波条纹候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.pattern.sine_wave_stripes"), "正弦波条纹候选应声明通用 pattern 用途槽位。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "正弦波条纹候选应声明 tile pattern 用途槽位。")


func test_manual_noise_node_link_tile_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(NOISE_NODE_LINK_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动噪声节点连线方块图案 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == NOISE_NODE_LINK_PATTERN_SHADER_PATH, "评审记录应指向候选噪声节点连线方块图案 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "噪声节点连线方块图案候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "噪声节点连线方块图案候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "噪声节点连线方块图案候选应声明 tile pattern 用途槽位。")
	assert_true(suggested_slots.has("slot.shader.pattern.noise_node_links"), "噪声节点连线方块图案候选应声明通用 node-link 用途槽位。")


func test_manual_square_wave_tile_pattern_shader_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(SQUARE_WAVE_PATTERN_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动方格波纹方块图案 shader 应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == SQUARE_WAVE_PATTERN_SHADER_PATH, "评审记录应指向候选方格波纹方块图案 shader 源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"shader", "方格波纹方块图案候选应标记为 shader。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "方格波纹方块图案候选应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.shader.tile.hand_drawn_hatch_pattern"), "方格波纹方块图案候选应声明 tile pattern 用途槽位。")


func test_manual_burn_card_recipe_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(BURN_RECIPE_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动点击烧除卡片 VFX 配方应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == BURN_RECIPE_PATH, "评审记录应指向候选 VFX 配方源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"vfx", "烧除卡片配方应标记为 VFX。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "烧除卡片配方应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.vfx.ui.card_burn_dissolve"), "烧除卡片配方应声明 card burn dissolve 用途槽位。")


func test_manual_button_wobble_recipe_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(BUTTON_WOBBLE_RECIPE_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动按钮跟随晃动 VFX 配方应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == BUTTON_WOBBLE_RECIPE_PATH, "评审记录应指向候选按钮动效配方源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"vfx", "按钮跟随晃动配方应标记为 VFX。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "按钮跟随晃动配方应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.vfx.ui.interactive_button_follow_wobble"), "按钮跟随晃动配方应声明 interactive button 用途槽位。")


func test_manual_pooled_shader_drop_recipe_is_review_candidate_only() -> void:
	var record: Resource = ResourceLoader.load(POOLED_DROP_RECIPE_RECORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(record, "手动 pooled shader drop VFX 配方应有评审记录。")
	if record == null:
		return

	var suggested_slots: PackedStringArray = GFVariantData.get_option_packed_string_array(
		{ "value": record.get("suggested_slots") },
		"value"
	)

	assert_true(GFVariantData.to_text(record.get("library_path")) == POOLED_DROP_RECIPE_PATH, "评审记录应指向候选 pooled shader drop 配方源文件。")
	assert_true(GFVariantData.to_string_name(record.get("asset_kind")) == &"vfx", "pooled shader drop 配方应标记为 VFX。")
	assert_true(GFVariantData.to_string_name(record.get("review_status")) == &"candidate", "pooled shader drop 配方应保持 candidate 状态。")
	assert_true(GFVariantData.to_string_name(record.get("license_status")) == &"unknown", "未确认来源前授权状态应保持 unknown。")
	assert_true(suggested_slots.has("slot.vfx.shader.pooled_drop_controller"), "pooled shader drop 配方应声明 pooled drop controller 用途槽位。")


func test_slot_map_tracks_default_runtime_replacement_slots() -> void:
	var loaded: Resource = ResourceLoader.load(SLOT_MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var bindings: Array[Resource] = _get_slot_bindings(loaded)
	var slot_ids: PackedStringArray = _collect_slot_ids(bindings)

	assert_true(bindings.size() == 20, "默认槽位映射应覆盖 UI 音效、棋盘音效、shader 和 VFX。")
	assert_true(slot_ids.has("slot.audio.ui.select"), "应存在 UI 选择音效槽位。")
	assert_true(slot_ids.has("slot.audio.tile.merge"), "应存在方块合并音效槽位。")
	assert_true(slot_ids.has("slot.shader.background.main"), "应存在主背景 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.transition.scene_wipe"), "应存在场景切换 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.ui.startup_progress_bar"), "应存在启动进度条 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.ui.shine_sweep"), "应存在 UI 扫光 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.background.space_clouds"), "应存在太空背景 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.weather.rain_snow_overlay"), "应存在雨雪天气 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.vfx.glitch_aberration"), "应存在故障 VFX shader 槽位。")
	assert_true(slot_ids.has("slot.shader.vfx.new_item_radial_shine"), "应存在获得新物品径向闪光 shader 槽位。")
	assert_true(slot_ids.has("slot.shader.pattern.sine_wave_stripes"), "应存在正弦波条纹通用 pattern shader 槽位。")
	assert_true(slot_ids.has("slot.shader.tile.hand_drawn_hatch_pattern"), "应存在手绘斜线方块图案 shader 槽位。")
	assert_true(slot_ids.has("slot.vfx.ui.card_burn_dissolve"), "应存在卡片烧除 VFX 槽位。")
	assert_true(slot_ids.has("slot.vfx.ui.interactive_button_follow_wobble"), "应存在按钮跟随晃动 VFX 槽位。")
	assert_true(slot_ids.has("slot.vfx.shader.pooled_drop_controller"), "应存在 pooled shader drop VFX 槽位。")
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.transition.scene_wipe").has(
			"asset.review.manual.shader.notes.luminance.mask.texture.transition.aa1d8745"
		),
		"亮度遮罩转场候选应挂到场景切换槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.ui.shine_sweep").has(SHINE_SWEEP_ASSET_ID),
		"扫光候选应挂到 UI 高亮槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.ui.shine_sweep").has(SURFACE_MASKED_SHINE_SWEEP_ASSET_ID),
		"表面遮罩扫光候选应挂到 UI 高亮槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.background.space_clouds").has(SPACE_BACKGROUND_ASSET_ID),
		"太空背景候选应挂到太空背景槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.background.main").has(FLICKER_NOISE_BACKGROUND_ASSET_ID),
		"闪烁噪声背景候选应挂到主背景槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.background.main").has(GYROID_FBM_BACKGROUND_ASSET_ID),
		"gyroid FBM 背景候选应挂到主背景槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.weather.rain_snow_overlay").has(RAIN_SNOW_WEATHER_ASSET_ID),
		"雨雪天气候选应挂到天气槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.weather.rain_snow_overlay").has(STEAMPUNKDEMON_RAIN_SNOW_ASSET_ID),
		"Brian Smith MIT 雨雪候选应挂到天气槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.vfx.glitch_aberration").has(GLITCH_ASSET_ID),
		"故障候选应挂到 VFX 故障槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.vfx.glitch_aberration").has(SCREEN_LENS_SHOCKWAVE_ASSET_ID),
		"屏幕镜头冲击波候选应挂到 VFX 色散槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.vfx.new_item_radial_shine").has(NEW_ITEM_RADIAL_SHINE_ASSET_ID),
		"获得新物品闪光候选应挂到 reward VFX 槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.pattern.sine_wave_stripes").has(SINE_WAVE_STRIPE_PATTERN_ASSET_ID),
		"正弦波条纹候选应挂到通用 pattern 槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(HATCH_PATTERN_ASSET_ID),
		"方块图案候选应挂到手绘斜线方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(ANIMATED_CHECKER_PATTERN_ASSET_ID),
		"动画棋盘图案候选应挂到方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(ANGLED_STRIPE_PATTERN_ASSET_ID),
		"斜向条纹方块图案候选应挂到方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(SINE_WAVE_STRIPE_PATTERN_ASSET_ID),
		"正弦波条纹候选应挂到方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(NOISE_NODE_LINK_PATTERN_ASSET_ID),
		"噪声节点连线候选应挂到方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.shader.tile.hand_drawn_hatch_pattern").has(SQUARE_WAVE_PATTERN_ASSET_ID),
		"方格波纹候选应挂到方块图案槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.vfx.ui.card_burn_dissolve").has(BURN_RECIPE_ASSET_ID),
		"烧除卡片配方应挂到卡片烧除 VFX 槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.vfx.ui.interactive_button_follow_wobble").has(BUTTON_WOBBLE_RECIPE_ASSET_ID),
		"按钮跟随晃动配方应挂到按钮动效 VFX 槽位。"
	)
	assert_true(
		_find_slot_candidate_asset_ids(bindings, "slot.vfx.shader.pooled_drop_controller").has(POOLED_DROP_RECIPE_ASSET_ID),
		"pooled shader drop 配方应挂到 pooled drop VFX 槽位。"
	)
	assert_true(
		_find_slot_asset_key(bindings, "slot.audio.ui.select") == "asset.audio.ui.printworks.select_soft_01",
		"UI 选择槽位应绑定当前运行时默认素材。"
	)
	assert_true(
		_find_slot_asset_key(bindings, "slot.shader.ui.startup_progress_bar") == "asset.shader.ui.startup_progress_bar",
		"启动进度条槽位应绑定当前运行时默认 shader。"
	)


# --- 私有/辅助方法 ---

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var dictionary: Dictionary = parsed
		return dictionary
	return {}


func _collect_source_pack_ids(source_packs: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for source_pack_value: Variant in source_packs:
		var source_pack: Dictionary = GFVariantData.as_dictionary(source_pack_value)
		var source_pack_id: String = GFVariantData.get_option_string(source_pack, "source_pack_id")
		if not source_pack_id.is_empty():
			var _append_result: bool = result.append(source_pack_id)
	return result


func _get_slot_bindings(slot_map: Resource) -> Array[Resource]:
	var result: Array[Resource] = []
	if slot_map == null:
		return result
	var bindings_value: Variant = slot_map.get("bindings")
	if bindings_value is Array:
		var raw_bindings: Array = bindings_value
		for raw_binding: Variant in raw_bindings:
			if raw_binding is Resource:
				var binding: Resource = raw_binding
				result.append(binding)
	return result


func _collect_slot_ids(bindings: Array[Resource]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for binding: Resource in bindings:
		var slot_id_value: Variant = binding.get("slot_id")
		var slot_id: String = String(GFVariantData.to_string_name(slot_id_value))
		if not slot_id.is_empty():
			var _append_result: bool = result.append(slot_id)
	return result


func _find_slot_asset_key(bindings: Array[Resource], slot_id: String) -> String:
	for binding: Resource in bindings:
		var slot_id_value: Variant = binding.get("slot_id")
		if String(GFVariantData.to_string_name(slot_id_value)) != slot_id:
			continue
		var asset_key_value: Variant = binding.get("current_asset_key")
		return String(GFVariantData.to_string_name(asset_key_value))
	return ""


func _find_slot_candidate_asset_ids(bindings: Array[Resource], slot_id: String) -> PackedStringArray:
	for binding: Resource in bindings:
		var slot_id_value: Variant = binding.get("slot_id")
		if String(GFVariantData.to_string_name(slot_id_value)) != slot_id:
			continue
		return GFVariantData.get_option_packed_string_array(
			{ "value": binding.get("candidate_asset_ids") },
			"value"
		)
	return PackedStringArray()
