## 验证所有发布预设都排除开发期内容，同时保留动态内容包及正式运行时资源。
extends GutTest


# --- 常量 ---

const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _RUNTIME_MANIFEST_PATHS: Array[String] = [
	"res://features/asset_library/resources/gf_content_package.json",
	"res://features/themes/resources/gf_content_package.json",
]
const _REQUIRED_INCLUDE_FILE_FILTERS: Array[String] = [
	"features/asset_library/resources/gf_content_package.json",
	"features/themes/resources/gf_content_package.json",
	"features/asset_library/resources/textures/icons/license_lucide.txt",
	"shared/assets/fonts/noto_sans_sc_ofl.txt",
]
const _REQUIRED_INCLUDE_ROOT_FILTERS: Array[String] = [
	"features/asset_library/resources/licenses",
]
const _REQUIRED_EXCLUDE_FILE_FILTERS: Array[String] = [
	"features/asset_library/resources/import_sources.json",
]
const _REQUIRED_EXCLUDE_ROOT_FILTERS: Array[String] = [
	"features/asset_library/resources/source_packs",
	"features/asset_library/resources/review",
	"features/asset_library/resources/reports",
	"features/asset_library/tools",
	"features/platform_runtime/tools",
	"tests",
	"addons/gut",
	"addons/gf/tools",
	"tools",
	"build",
]


# --- 测试用例 ---

func test_every_release_preset_uses_the_project_export_filters() -> void:
	var config: ConfigFile = _load_export_config()
	var preset_sections: PackedStringArray = _get_preset_sections(config)
	assert_false(preset_sections.is_empty(), "至少应存在一个发布预设。")

	for section: String in preset_sections:
		var preset_name: String = str(config.get_value(section, "name", section))
		assert_true(
			str(config.get_value(section, "export_filter", "")) == "all_resources",
			"%s 应从完整运行时资源集合开始过滤。" % preset_name
		)
		var include_filters: PackedStringArray = _parse_filter_list(
			str(config.get_value(section, "include_filter", ""))
		)
		var exclude_filters: PackedStringArray = _parse_filter_list(
			str(config.get_value(section, "exclude_filter", ""))
		)
		var required_include_filters: PackedStringArray = _build_required_filters(
			_REQUIRED_INCLUDE_FILE_FILTERS,
			_REQUIRED_INCLUDE_ROOT_FILTERS
		)
		var required_exclude_filters: PackedStringArray = _build_required_filters(
			_REQUIRED_EXCLUDE_FILE_FILTERS,
			_REQUIRED_EXCLUDE_ROOT_FILTERS
		)
		for required_filter: String in required_include_filters:
			assert_true(
				include_filters.has(required_filter),
				"%s 缺少发布包含规则：%s" % [preset_name, required_filter]
			)
		for required_filter: String in required_exclude_filters:
			assert_true(
				exclude_filters.has(required_filter),
				"%s 缺少发布排除规则：%s" % [preset_name, required_filter]
			)


func test_runtime_content_manifests_and_entries_survive_every_release_filter() -> void:
	var config: ConfigFile = _load_export_config()
	var runtime_paths: PackedStringArray = _collect_runtime_content_paths()
	assert_true(
		runtime_paths.size() > _RUNTIME_MANIFEST_PATHS.size(),
		"运行时内容路径应包含 manifest 及其正式资源。"
	)

	for section: String in _get_preset_sections(config):
		var preset_name: String = str(config.get_value(section, "name", section))
		var exclude_filters: PackedStringArray = _parse_filter_list(
			str(config.get_value(section, "exclude_filter", ""))
		)
		for runtime_path: String in runtime_paths:
			assert_false(
				_matches_any_filter(runtime_path.trim_prefix("res://"), exclude_filters),
				"%s 不得排除正式运行时资源：%s" % [preset_name, runtime_path]
			)


# --- 私有/辅助方法 ---

func _load_export_config() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	assert_true(config.load(_EXPORT_CONFIG_PATH) == OK, "应能读取导出预设。")
	return config


func _get_preset_sections(config: ConfigFile) -> PackedStringArray:
	var sections: PackedStringArray = PackedStringArray()
	for section: String in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			var _appended: bool = sections.append(section)
	sections.sort()
	return sections


func _parse_filter_list(serialized_filters: String) -> PackedStringArray:
	var filters: PackedStringArray = PackedStringArray()
	for filter_text: String in serialized_filters.split(",", false):
		var normalized_filter: String = filter_text.strip_edges().trim_prefix("res://")
		if normalized_filter.is_empty() or filters.has(normalized_filter):
			continue
		var _appended: bool = filters.append(normalized_filter)
	return filters


func _build_required_filters(
	file_filters: Array[String],
	root_filters: Array[String]
) -> PackedStringArray:
	var filters: PackedStringArray = PackedStringArray(file_filters)
	for root_filter: String in root_filters:
		var _appended: bool = filters.append("%s/%s" % [root_filter, "*"])
	return filters


func _collect_runtime_content_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for manifest_path: String in _RUNTIME_MANIFEST_PATHS:
		assert_true(FileAccess.file_exists(manifest_path), "运行时内容包 manifest 必须存在：%s" % manifest_path)
		if not FileAccess.file_exists(manifest_path):
			continue
		var _manifest_appended: bool = paths.append(manifest_path)
		var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
		assert_not_null(manifest_file, "应能读取运行时内容包 manifest：%s" % manifest_path)
		if manifest_file == null:
			continue
		var parsed_value: Variant = JSON.parse_string(manifest_file.get_as_text())
		assert_true(parsed_value is Dictionary, "运行时内容包 manifest 必须是 JSON 对象：%s" % manifest_path)
		if not parsed_value is Dictionary:
			continue
		var manifest: Dictionary = parsed_value
		var resource_values: Array = GFVariantData.get_option_array(manifest, "resources")
		for resource_value: Variant in resource_values:
			var entry: Dictionary = GFVariantData.as_dictionary(resource_value)
			var relative_path: String = GFVariantData.get_option_string(entry, "path")
			var runtime_path: String = manifest_path.get_base_dir().path_join(relative_path)
			assert_true(
				ResourceLoader.exists(runtime_path),
				"manifest 声明的正式运行时资源必须存在：%s" % runtime_path
			)
			if not paths.has(runtime_path):
				var _resource_appended: bool = paths.append(runtime_path)
	return paths


func _matches_any_filter(path: String, filters: PackedStringArray) -> bool:
	for filter_pattern: String in filters:
		if path.match(filter_pattern):
			return true
	return false
