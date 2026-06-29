## 验证 GF 包锁、项目扩展启用和忽略规则保持一致。
extends GutTest


# --- 常量 ---

const _LOCKFILE_PATH: String = "res://.gf/packages.lock.json"
const _PROJECT_CONFIG_PATH: String = "res://project.godot"
const _GF_PLUGIN_CONFIG_PATH: String = "res://addons/gf/plugin.cfg"
const _GF_PACKAGE_CLI_PATH: String = "res://addons/gf/kernel/package/gf_package_cli.gd"
const _GF_PACKAGE_BACKEND_PATH: String = "res://addons/gf/kernel/package/gf_package_manager_backend.gd"
const _GF_EXTENSION_ROOT_PATH: String = "res://addons/gf/extensions"
const _GITIGNORE_PATH: String = "res://.gitignore"


# --- 测试用例 ---

func test_gf_plugin_version_is_recorded_as_semver() -> void:
	var plugin_config: ConfigFile = _load_config_file(_GF_PLUGIN_CONFIG_PATH)
	var plugin_version: String = _get_config_text(plugin_config, "plugin", "version")
	var issues: Array[String] = []

	if plugin_version.is_empty():
		_append_string(issues, "addons/gf/plugin.cfg 应记录 plugin/version。")
	elif not _is_semver(plugin_version):
		_append_string(issues, "addons/gf/plugin.cfg 的 plugin/version 应为 SemVer：%s。" % plugin_version)

	assert_true(issues.is_empty(), "GF 插件版本应可作为包管理和文档事实来源：\n%s" % _join_lines(issues))


func test_native_package_manager_entrypoints_exist() -> void:
	var issues: Array[String] = []

	if not ResourceLoader.exists(_GF_PACKAGE_CLI_PATH, "Script"):
		_append_string(issues, "GF 7 原生包管理 CLI 缺失：%s。" % _GF_PACKAGE_CLI_PATH)
	if not ResourceLoader.exists(_GF_PACKAGE_BACKEND_PATH, "Script"):
		_append_string(issues, "GF 7 原生包管理后端缺失：%s。" % _GF_PACKAGE_BACKEND_PATH)

	assert_true(issues.is_empty(), "GF 包管理入口应使用 Godot 原生实现：\n%s" % _join_lines(issues))


func test_lockfile_framework_version_matches_gf_plugin_version_when_present() -> void:
	if not FileAccess.file_exists(_LOCKFILE_PATH):
		assert_true(true, "当前为手动 vendored GF 源码状态，缺失 lockfile 时跳过 lockfile 版本校验。")
		return

	var lockfile: Dictionary = _read_json_dictionary(_LOCKFILE_PATH)
	var plugin_config: ConfigFile = _load_config_file(_GF_PLUGIN_CONFIG_PATH)
	var lockfile_version: String = _get_dictionary_text(lockfile, "framework_version")
	var plugin_version: String = _get_config_text(plugin_config, "plugin", "version")
	var issues: Array[String] = []

	if lockfile_version.is_empty():
		_append_string(issues, ".gf/packages.lock.json 存在时应记录 framework_version。")
	if plugin_version.is_empty():
		_append_string(issues, "addons/gf/plugin.cfg 应记录 plugin/version。")
	if not lockfile_version.is_empty() and not plugin_version.is_empty() and lockfile_version != plugin_version:
		_append_string(
			issues,
			"GF lockfile framework_version=%s 应与 plugin.cfg version=%s 一致。" % [
				lockfile_version,
				plugin_version,
			]
		)

	assert_true(issues.is_empty(), "存在 GF lockfile 时，框架版本来源应保持一致：\n%s" % _join_lines(issues))


func test_project_enabled_extensions_have_vendored_manifests() -> void:
	var lockfile: Dictionary = _read_json_dictionary(_LOCKFILE_PATH)
	var project_config: ConfigFile = _load_config_file(_PROJECT_CONFIG_PATH)
	var lockfile_extensions: PackedStringArray = _get_lockfile_enable_extensions(lockfile)
	var project_extensions: PackedStringArray = _get_config_packed_string_array(
		project_config,
		"gf",
		"extensions/enabled"
	)
	var plugin_config: ConfigFile = _load_config_file(_GF_PLUGIN_CONFIG_PATH)
	var plugin_version: String = _get_config_text(plugin_config, "plugin", "version")
	var issues: Array[String] = []

	for extension_id: String in project_extensions:
		var manifest_path: String = _get_extension_manifest_path(extension_id)
		if not FileAccess.file_exists(manifest_path):
			_append_string(issues, "project.godot 启用的 GF 扩展缺少 manifest：%s -> %s。" % [
				extension_id,
				manifest_path,
			])
			continue

		var manifest: Dictionary = _read_json_dictionary(manifest_path)
		var manifest_id: String = _get_dictionary_text(manifest, "id")
		var manifest_version: String = _get_dictionary_text(manifest, "version")
		if manifest_id != extension_id:
			_append_string(issues, "GF 扩展 manifest id=%s 应等于 project.godot 中的 %s。" % [
				manifest_id,
				extension_id,
			])
		if not plugin_version.is_empty() and manifest_version != plugin_version:
			_append_string(issues, "GF 扩展 %s version=%s 应与 plugin.cfg version=%s 一致。" % [
				extension_id,
				manifest_version,
				plugin_version,
			])

	assert_true(issues.is_empty(), "project.godot 启用的 GF 扩展应在 vendored GF 源码中可解析：\n%s" % _join_lines(issues))

	if not FileAccess.file_exists(_LOCKFILE_PATH):
		return

	lockfile_extensions.sort()
	project_extensions.sort()

	assert_true(
		_packed_string_arrays_equal(lockfile_extensions, project_extensions),
		"project.godot 启用的 GF 扩展应与 lockfile 中要求 enable_extension 的包一致。\nlockfile: %s\nproject: %s" % [
			_format_packed_string_array(lockfile_extensions),
			_format_packed_string_array(project_extensions),
		]
	)


func test_gf_package_cache_is_ignored_without_ignoring_lockfile() -> void:
	var gitignore_text: String = _read_text(_GITIGNORE_PATH)
	var issues: Array[String] = []

	if not _gitignore_has_entry(gitignore_text, ".gf/package_cache/"):
		_append_string(issues, ".gitignore 应忽略 .gf/package_cache/，避免提交 GF 下载缓存。")
	if _gitignore_has_entry(gitignore_text, ".gf/"):
		_append_string(issues, ".gitignore 不应忽略整个 .gf/，否则 packages.lock.json 容易被漏提交。")

	assert_true(issues.is_empty(), "GF 包管理相关忽略规则应只忽略缓存、不隐藏 lockfile：\n%s" % _join_lines(issues))


func test_generated_logs_user_data_and_exports_are_ignored() -> void:
	var gitignore_text: String = _read_text(_GITIGNORE_PATH)
	var issues: Array[String] = []
	var required_entries: Array[String] = [
		".godot/",
		"*.log",
		"logs/",
		"runtime_warning*.log",
		"user_data/",
		"ai_analysis/",
		"build/",
		"exports/",
		"*.pck",
	]

	for entry: String in required_entries:
		if not _gitignore_has_entry(gitignore_text, entry):
			_append_string(issues, ".gitignore 应忽略 %s，避免提交本地生成产物。" % entry)

	assert_true(issues.is_empty(), "Godot 缓存、日志和导出产物应保持忽略：\n%s" % _join_lines(issues))


# --- 私有/辅助方法 ---

func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _read_json_dictionary(path: String) -> Dictionary:
	var text: String = _read_text(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var parsed_dictionary: Dictionary = parsed
		return parsed_dictionary
	return {}


func _load_config_file(path: String) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var _load_error: Error = config.load(path)
	return config


func _get_lockfile_enable_extensions(lockfile: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var installed_value: Variant = lockfile.get("installed", {})
	if not installed_value is Dictionary:
		return result

	var installed: Dictionary = installed_value
	for package_id: Variant in installed.keys():
		var package_value: Variant = installed[package_id]
		if not package_value is Dictionary:
			continue
		var package_data: Dictionary = package_value
		var extension_id: String = _get_dictionary_text(package_data, "enable_extension")
		if extension_id.is_empty():
			continue
		_append_packed_string(result, extension_id)
	return result


func _get_config_text(config: ConfigFile, section: String, key: String) -> String:
	if not config.has_section_key(section, key):
		return ""
	var value: Variant = config.get_value(section, key, "")
	return GFVariantData.to_text(value, "")


func _get_config_packed_string_array(config: ConfigFile, section: String, key: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not config.has_section_key(section, key):
		return result

	var value: Variant = config.get_value(section, key, PackedStringArray())
	if value is PackedStringArray:
		var packed_value: PackedStringArray = value
		return packed_value
	if value is Array:
		var array_value: Array = value
		for item: Variant in array_value:
			_append_packed_string(result, GFVariantData.to_text(item, ""))
	return result


func _gitignore_has_entry(source: String, expected_entry: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line == expected_entry:
			return true
	return false


func _packed_string_arrays_equal(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if _get_packed_line(left, index) != _get_packed_line(right, index):
			return false
	return true


func _format_packed_string_array(source: PackedStringArray) -> String:
	return "[" + ", ".join(source) + "]"


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_dictionary_text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: Variant = fallback
	if source.has(key):
		value = source[key]
	return GFVariantData.to_text(value, fallback)


func _get_extension_manifest_path(extension_id: String) -> String:
	var directory_name: String = extension_id
	if directory_name.begins_with("gf."):
		directory_name = directory_name.substr(3)
	directory_name = directory_name.replace(".", "_")
	return _GF_EXTENSION_ROOT_PATH.path_join(directory_name).path_join("gf_extension.json")


func _is_semver(version: String) -> bool:
	var pieces: PackedStringArray = version.strip_edges().split(".", false)
	if pieces.size() != 3:
		return false

	for piece: String in pieces:
		if piece.is_empty():
			return false
		if not _is_digits(piece):
			return false
	return true


func _is_digits(value: String) -> bool:
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)
