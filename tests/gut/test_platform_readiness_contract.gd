## 验证 Web / 微信小游戏准备配置不会被后续改动悄然破坏。
extends GutTest


# --- 常量 ---

const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _WEB_PRESET_NAME: String = "Web Compatibility Smoke"
const _BOOT_SCRIPT_PATH: String = "res://app/scripts/boot.gd"
const _SMOKE_SCENE_PATH: String = "res://features/platform_runtime/scenes/smoke_test/platform_smoke_test.tscn"
const _MODE_REGISTRY_PATH: String = "res://features/gameplay/resources/registries/game_mode_registry.tres"
const _UI_ROUTE_REGISTRY_PATH: String = "res://features/navigation/resources/registries/ui_route_registry.tres"


# --- 测试用例 ---

func test_web_renderer_override_uses_compatibility() -> void:
	assert_true(
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method.web", ""))
			== "gl_compatibility",
		"Web 渲染器必须使用 Compatibility。"
	)


func test_window_contract_supports_landscape_and_portrait_without_letterboxing() -> void:
	assert_true(
		GFVariantData.to_int(ProjectSettings.get_setting("display/window/size/viewport_width"))
			== 720,
		"响应式基准视口宽度应为 720。"
	)
	assert_true(
		GFVariantData.to_int(ProjectSettings.get_setting("display/window/size/viewport_height"))
			== 720,
		"响应式基准视口高度应为 720。"
	)
	assert_true(
		str(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items",
		"UI 应使用 canvas_items 拉伸模式。"
	)
	assert_true(
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand",
		"横竖屏应使用 expand，避免固定比例黑边。"
	)


func test_web_smoke_preset_is_single_threaded_and_mobile_texture_ready() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_true(config.load(_EXPORT_CONFIG_PATH) == OK, "应能读取导出预设。")
	var section: String = _find_preset_section(config)
	assert_false(section.is_empty(), "应存在 Web Compatibility Smoke 导出预设。")
	var options_section: String = "%s.options" % section
	assert_false(GFVariantData.to_bool(config.get_value(options_section, "variant/thread_support", true), true))
	assert_false(GFVariantData.to_bool(config.get_value(options_section, "variant/extensions_support", true), true))
	assert_true(GFVariantData.to_bool(config.get_value(options_section, "vram_texture_compression/for_mobile", false)))
	assert_true(str(config.get_value(section, "custom_features", "")).contains("platform_smoke"))


func test_boot_routes_platform_smoke_exports_to_dedicated_scene() -> void:
	var file: FileAccess = FileAccess.open(_BOOT_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var source: String = file.get_as_text()
	assert_true(source.contains("OS.has_feature(_PLATFORM_SMOKE_FEATURE)"))
	assert_true(source.contains("PLATFORM_SMOKE_SCENE_PATH"))
	assert_true(ResourceLoader.exists(_SMOKE_SCENE_PATH, "PackedScene"))


func test_dynamic_script_resource_registries_use_export_safe_type_hints() -> void:
	for registry_path: String in PackedStringArray([
		_MODE_REGISTRY_PATH,
		_UI_ROUTE_REGISTRY_PATH,
	]):
		var resource: Resource = load(registry_path)
		assert_true(resource is GFResourceRegistry, "应能加载资源注册表：%s" % registry_path)
		if not resource is GFResourceRegistry:
			continue
		var registry: GFResourceRegistry = resource
		for entry: GFResourceRegistryEntry in registry.entries:
			assert_true(
				entry.type_hint == "Resource",
				"导出时动态加载的脚本资源不得把 class_name 当作 ResourceLoader type_hint。"
			)


# --- 私有/辅助方法 ---

func _find_preset_section(config: ConfigFile) -> String:
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		if str(config.get_value(section, "name", "")) == _WEB_PRESET_NAME:
			return section
	return ""
