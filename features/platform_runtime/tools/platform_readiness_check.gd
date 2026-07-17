## PlatformReadinessCheck: Web / 微信小游戏项目侧兼容性预检。
class_name PlatformReadinessCheck
extends SceneTree


# --- 常量 ---

const _WEB_PRESET_NAME: String = "Web Compatibility Smoke"
const _REPORT_PATH: String = "res://build/platform_readiness_report.json"
const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _GF_PLUGIN_CONFIG_PATH: String = "res://addons/gf/plugin.cfg"
const _ASSET_MANIFEST_PATH: String = "res://features/asset_library/resources/gf_content_package.json"
const _THEME_MANIFEST_PATH: String = "res://features/themes/resources/gf_content_package.json"
const _REPRESENTATIVE_SHADER_KEY: StringName = &"asset.shader.background.halftone_paper"
const _REPRESENTATIVE_AUDIO_KEY: StringName = &"asset.audio.ui.printworks.confirm_soft_01"
const _DYNAMIC_RESOURCE_REGISTRY_PATHS: Array[String] = [
	"res://features/gameplay/resources/registries/game_mode_registry.tres",
	"res://features/navigation/resources/registries/ui_route_registry.tres",
]

# --- Godot 生命周期方法 ---

func _init() -> void:
	var export_config: ConfigFile = ConfigFile.new()
	var export_error: Error = export_config.load(_EXPORT_CONFIG_PATH)
	var profile: GFCompatibilityProfile = _build_profile(export_config, export_error)
	var preflight: GFCompatibilityPreflight = GFCompatibilityPreflight.new().configure(
		"WeChat minigame project readiness",
		profile,
		{
			"preset": _WEB_PRESET_NAME,
			"scope": "project_contract",
		}
	)
	var _platform_check: Dictionary = preflight.require_platforms(
		PackedStringArray(["web", "wechat_minigame"]),
		GFCompatibilityPreflight.MATCH_ALL
	)
	var _feature_check: Dictionary = preflight.require_features(
		_get_required_features(),
		GFCompatibilityPreflight.MATCH_ALL
	)
	_require_artifacts(preflight)

	var platform_utility: GamePlatformUtility = GamePlatformUtility.new()
	platform_utility.init()
	var bridge_report: Dictionary = platform_utility.get_bridge_contract_report()
	var _merged_preflight: GFCompatibilityPreflight = preflight.merge_report(
		bridge_report,
		{
			"component": &"platform_runtime",
			"phase": &"bridge_contract",
			"check_id": &"platform_bridge_contract",
		}
	)
	var _resource_contract_merged: GFCompatibilityPreflight = preflight.merge_report(
		_build_dynamic_resource_contract_report(),
		{
			"component": &"resource_catalog",
			"phase": &"export_contract",
			"check_id": &"export_safe_dynamic_resources",
		}
	)
	platform_utility.dispose()

	var report: Dictionary = preflight.get_report({
		"fallback_action": "Fix the first project compatibility issue before exporting.",
		"no_action": "Project-side Web compatibility contract is ready for export validation.",
	})
	var write_error: Error = _write_report(report)
	var ok: bool = GFVariantData.get_option_bool(report, "ok") and write_error == OK
	print("Platform readiness: %s (%d checks, %d issues)" % [
		"PASS" if ok else "FAIL",
		GFVariantData.get_option_int(report, "check_count"),
		GFVariantData.get_option_int(report, "issue_count"),
	])
	quit(0 if ok else 1)


# --- 私有/辅助方法 ---

func _build_profile(export_config: ConfigFile, export_error: Error) -> GFCompatibilityProfile:
	var features: PackedStringArray = PackedStringArray([
		"platform.runtime_context",
		"platform.lifecycle",
	])
	if str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method.web",
		""
	)) == "gl_compatibility":
		var _renderer_added: bool = features.append("renderer.gl_compatibility.web")
	if (
		GFVariantData.to_int(ProjectSettings.get_setting("display/window/size/viewport_width"))
		== GFVariantData.to_int(ProjectSettings.get_setting("display/window/size/viewport_height"))
		and str(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items"
		and str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand"
	):
		var _viewport_added: bool = features.append("viewport.responsive_expand")

	var preset_section: String = ""
	if export_error == OK:
		preset_section = _find_preset_section(export_config, _WEB_PRESET_NAME)
	if not preset_section.is_empty():
		var options_section: String = "%s.options" % preset_section
		if not GFVariantData.to_bool(export_config.get_value(options_section, "variant/thread_support", true), true):
			var _thread_added: bool = features.append("web.single_threaded")
		if not GFVariantData.to_bool(export_config.get_value(options_section, "variant/extensions_support", true), true):
			var _extension_added: bool = features.append("web.extensions_disabled")
		if GFVariantData.to_bool(export_config.get_value(options_section, "vram_texture_compression/for_mobile", false)):
			var _texture_added: bool = features.append("texture.mobile")
		var custom_features: String = str(export_config.get_value(preset_section, "custom_features", ""))
		if custom_features.split(",", false).has("platform_smoke"):
			var _entry_added: bool = features.append("platform_smoke.entry")

	var profile: GFCompatibilityProfile = GFCompatibilityProfile.new().configure(
		&"wechat_minigame_smoke",
		str(Engine.get_version_info().get("string", "")),
		_read_gf_version(),
		PackedStringArray(["web", "wechat_minigame"]),
		features,
		{
			"export_config_error": export_error,
			"preset_section": preset_section,
		}
	)
	_add_profile_artifact(profile, &"boot_scene", "res://app/scenes/boot.tscn", &"scene")
	_add_profile_artifact(
		profile,
		&"platform_smoke_scene",
		"res://features/platform_runtime/scenes/smoke_test/platform_smoke_test.tscn",
		&"scene"
	)
	_add_profile_artifact(
		profile,
		&"representative_shader",
		_resolve_content_resource_path(_ASSET_MANIFEST_PATH, _REPRESENTATIVE_SHADER_KEY),
		&"shader"
	)
	_add_profile_artifact(
		profile,
		&"representative_audio",
		_resolve_content_resource_path(_ASSET_MANIFEST_PATH, _REPRESENTATIVE_AUDIO_KEY),
		&"audio"
	)
	return profile


func _find_preset_section(config: ConfigFile, preset_name: String) -> String:
	for section: String in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var preset_name_value: Variant = config.get_value(section, "name", "")
		if GFVariantData.to_text(preset_name_value) == preset_name:
			return section
	return ""


func _get_required_features() -> PackedStringArray:
	return PackedStringArray([
		"renderer.gl_compatibility.web",
		"web.single_threaded",
		"web.extensions_disabled",
		"texture.mobile",
		"platform_smoke.entry",
		"platform.runtime_context",
		"platform.lifecycle",
		"viewport.responsive_expand",
	])


func _read_gf_version() -> String:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(_GF_PLUGIN_CONFIG_PATH)
	if error != OK:
		return ""
	var version_value: Variant = config.get_value("plugin", "version", "")
	return GFVariantData.to_text(version_value)


func _resolve_content_resource_path(
	manifest_path: String,
	resource_key: StringName
) -> String:
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(
		manifest_path
	)
	if manifest == null:
		return ""
	for entry: Dictionary in manifest.get_normalized_resources():
		if GFVariantData.get_option_string_name(entry, "key") == resource_key:
			return GFVariantData.get_option_string(entry, "path")
	return ""


func _add_profile_artifact(
	profile: GFCompatibilityProfile,
	artifact_id: StringName,
	path: String,
	kind: StringName
) -> void:
	var _artifact: Dictionary = profile.add_artifact(artifact_id, path, {"kind": kind})


func _require_artifacts(preflight: GFCompatibilityPreflight) -> void:
	var _boot_check: Dictionary = preflight.require_artifact(&"boot_scene", {
		"require_path": true,
		"require_file_exists": true,
		"expected_kind": &"scene",
	})
	var _smoke_check: Dictionary = preflight.require_artifact(&"platform_smoke_scene", {
		"require_path": true,
		"require_file_exists": true,
		"expected_kind": &"scene",
	})
	var _shader_check: Dictionary = preflight.require_artifact(&"representative_shader", {
		"require_path": true,
		"require_file_exists": true,
		"expected_kind": &"shader",
	})
	var _audio_check: Dictionary = preflight.require_artifact(&"representative_audio", {
		"require_path": true,
		"require_file_exists": true,
		"expected_kind": &"audio",
	})


func _build_dynamic_resource_contract_report() -> Dictionary:
	var report: Dictionary = {
		"subject": "Export-safe dynamic resources",
		"issues": [],
	}
	for registry_path: String in _DYNAMIC_RESOURCE_REGISTRY_PATHS:
		var registry_resource: Resource = load(registry_path)
		if not registry_resource is GFResourceRegistry:
			var _registry_issue: Dictionary = GFValidationReportDictionary.append_issue(
				report,
				"error",
				&"invalid_dynamic_resource_registry",
				"Dynamic resource registry could not be loaded.",
				{"path": registry_path}
			)
			continue
		var registry: GFResourceRegistry = registry_resource
		for entry: GFResourceRegistryEntry in registry.entries:
			if entry == null or entry.type_hint == "Resource":
				continue
			var _entry_issue: Dictionary = GFValidationReportDictionary.append_issue(
				report,
				"error",
				&"export_unsafe_script_type_hint",
				"Dynamic scripted resources must use the built-in Resource type hint.",
				{
					"path": entry.path,
					"actual_value": entry.type_hint,
					"expected_value": "Resource",
				}
			)

	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(
		_THEME_MANIFEST_PATH
	)
	if manifest == null:
		var _manifest_issue: Dictionary = GFValidationReportDictionary.append_issue(
			report,
			"error",
			&"missing_theme_content_manifest",
			"Theme content package manifest could not be loaded.",
			{"path": _THEME_MANIFEST_PATH}
		)
	else:
		for entry: Dictionary in manifest.get_normalized_resources():
			var path: String = GFVariantData.get_option_string(entry, "path")
			var type_hint: String = GFVariantData.get_option_string(entry, "type_hint")
			if path.get_extension().to_lower() != "tres" or type_hint == "Resource":
				continue
			var _manifest_entry_issue: Dictionary = GFValidationReportDictionary.append_issue(
				report,
				"error",
				&"export_unsafe_content_type_hint",
				"Content-package scripted resources must use the built-in Resource type hint.",
				{
					"path": path,
					"actual_value": type_hint,
					"expected_value": "Resource",
				}
			)

	return GFValidationReportDictionary.finalize_report(
		report,
		"Export-safe dynamic resources",
		{
			"fallback_action": "Replace script class type hints with Resource and validate the loaded instance.",
			"no_action": "Dynamic scripted resource hints are export-safe.",
		}
	)


func _write_report(report: Dictionary) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(_REPORT_PATH)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if directory_error != OK:
		return directory_error
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var json_value: Variant = GFReportValueCodec.to_json_compatible(report)
	var _stored: bool = file.store_string(JSON.stringify(json_value, "\t") + "\n")
	return file.get_error()
