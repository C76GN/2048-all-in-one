## 验证项目通用素材库的 GF 内容包注册、资源解析和审计报告。
extends GutTest


# --- 常量 ---

const _ASSET_LIBRARY_MANIFEST_PATH: String = "res://asset_library/gf_content_package.json"


# --- 测试用例 ---

func test_asset_library_manifest_is_valid_and_self_contained() -> void:
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(_ASSET_LIBRARY_MANIFEST_PATH)

	assert_true(manifest != null, "素材库 manifest 应能加载。")
	assert_true(manifest.package_id == GameAssetLibraryUtility.ASSET_LIBRARY_PACKAGE_ID, "素材库 package id 应稳定。")
	assert_true(manifest.safety_kind == &"trusted_developer", "素材库包含 shader，应使用 trusted_developer safety kind。")
	assert_true(manifest.is_valid({"check_resource_exists": true}), "素材库 manifest 应只登记存在且位于库内的资源。")
	assert_true(manifest.get_resource_keys().has("asset.audio.ui.printworks.select_soft_01"), "素材库应登记 UI 选择音效。")
	assert_true(manifest.get_resource_keys().has("asset.shader.ui.button_focus_dash"), "素材库应登记按钮焦点 shader。")
	assert_true(manifest.get_resource_keys().has("asset.shader.ui.startup_progress_bar"), "素材库应登记启动进度条 shader。")
	assert_true(manifest.get_resource_keys().has("asset.vfx.celebration.confetti_canvas"), "素材库应登记庆祝反馈 VFX shader。")


func test_asset_library_registers_assets_into_gf_resolver() -> void:
	var setup: Dictionary = await _create_asset_library_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resolver(setup)
	var asset_library: GameAssetLibraryUtility = _get_asset_library(setup)

	var audio: Resource = asset_library.load_asset(&"asset.audio.ui.printworks.select_soft_01", "AudioStreamOggVorbis")
	var shader: Resource = asset_library.load_asset(&"asset.shader.ui.button_focus_dash", "Shader")
	var startup_progress_shader: Resource = asset_library.load_asset(&"asset.shader.ui.startup_progress_bar", "Shader")
	var celebration_shader: Resource = asset_library.load_asset(&"asset.vfx.celebration.confetti_canvas", "Shader")
	var resolve_report: Dictionary = resolver.resolve(&"asset.shader.transition.halftone_wipe", "Shader")

	assert_true(audio is AudioStream, "素材库音频应能通过稳定 asset key 加载。")
	assert_true(shader is Shader, "素材库 shader 应能通过稳定 asset key 加载。")
	assert_true(startup_progress_shader is Shader, "启动进度条 shader 应能通过稳定 asset key 加载。")
	assert_true(celebration_shader is Shader, "素材库庆祝 VFX shader 应能通过稳定 asset key 加载。")
	assert_true(GFVariantData.get_option_bool(resolve_report, "ok", false), "素材库资源键应注册进 GFResourceResolverUtility。")
	assert_true(
		asset_library.resolve_asset_path(&"asset.audio.ui.printworks.select_soft_01", "AudioStreamOggVorbis")
			== "res://asset_library/audio/ui/printworks_select_soft_01.ogg",
		"素材库应提供稳定 ID 到资源路径的解析。"
	)

	await _dispose_architecture(architecture)


func test_asset_library_audit_reports_usage_and_metadata_health() -> void:
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	var report: Dictionary = asset_library.build_audit_report()
	var usage: Dictionary = GFVariantData.get_option_dictionary(report, "usage")
	var select_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.audio.ui.printworks.select_soft_01"
	)
	var button_shader_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.shader.ui.button_focus_dash"
	)
	var celebration_vfx_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.vfx.celebration.confetti_canvas"
	)
	var startup_progress_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.shader.ui.startup_progress_bar"
	)

	assert_true(GFVariantData.get_option_bool(report, "ok", false), "素材库审计不应有 error。")
	assert_true(GFVariantData.get_option_int(report, "resource_count") >= 11, "素材库审计应覆盖首批音频、shader 和 VFX。")
	assert_true(
		GFVariantData.get_option_packed_string_array(report, "unregistered_library_files").is_empty(),
		"素材库内不应存在未登记的运行时素材文件。"
	)
	assert_true(
		GFVariantData.get_option_array(report, "metadata_issues").is_empty(),
		"素材库登记项必须包含审计所需元数据。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(select_usage, "path_users").has("res://resources/audio/printworks_audio_bank.tres"),
		"审计报告应能说明 UI 选择音效被音频银行使用。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(button_shader_usage, "path_users").has("res://scripts/utilities/game_ui_motion_utility.gd"),
		"审计报告应能说明按钮焦点 shader 被 UI 动效 Utility 使用。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(celebration_vfx_usage, "key_users").has("res://scripts/utilities/game_celebration_vfx_utility.gd"),
		"审计报告应能说明庆祝 VFX shader 被庆祝 Utility 使用。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(startup_progress_usage, "path_users").has("res://scripts/boot/boot.gd"),
		"审计报告应能说明启动进度条 shader 被 Boot 使用。"
	)


# --- 私有/辅助方法 ---

func _create_asset_library_architecture() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var content_packages: GFContentPackageUtility = GFContentPackageUtility.new()
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()

	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFContentPackageUtility, content_packages)
	await architecture.register_utility(GameAssetLibraryUtility, asset_library)
	await architecture.init()
	await get_tree().process_frame

	return {
		"architecture": architecture,
		"resolver": resolver,
		"asset_library": asset_library,
	}


func _dispose_architecture(architecture: GFArchitecture) -> void:
	if architecture != null:
		architecture.dispose()
	await get_tree().process_frame


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_resolver(setup: Dictionary) -> GFResourceResolverUtility:
	var value: Variant = setup.get("resolver")
	if value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = value
		return resolver
	assert_true(false, "测试 setup 缺少 GFResourceResolverUtility。")
	return GFResourceResolverUtility.new()


func _get_asset_library(setup: Dictionary) -> GameAssetLibraryUtility:
	var value: Variant = setup.get("asset_library")
	if value is GameAssetLibraryUtility:
		var asset_library: GameAssetLibraryUtility = value
		return asset_library
	assert_true(false, "测试 setup 缺少 GameAssetLibraryUtility。")
	return GameAssetLibraryUtility.new()
