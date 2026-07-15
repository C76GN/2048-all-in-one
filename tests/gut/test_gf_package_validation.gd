## 验证 GF 包锁、项目扩展启用和忽略规则保持一致。
extends GutTest


# --- 常量 ---

const _LOCKFILE_PATH: String = "res://.gf/packages.lock.json"
const _VENDOR_LOCKFILE_PATH: String = "res://.gf/vendor.lock.json"
const _PROJECT_CONFIG_PATH: String = "res://project.godot"
const _GF_PLUGIN_CONFIG_PATH: String = "res://addons/gf/plugin.cfg"
const _GF_PACKAGE_CLI_PATH: String = "res://addons/gf/kernel/package/gf_package_cli.gd"
const _GF_PACKAGE_BACKEND_PATH: String = "res://addons/gf/kernel/package/gf_package_manager_backend.gd"
const _GF_EXTENSION_ROOT_PATH: String = "res://addons/gf/extensions"
const _GITIGNORE_PATH: String = "res://.gitignore"
const _GUT_RUNNER_PATH: String = "res://tools/run_gut_safe.ps1"
const _GUT_SHUTDOWN_HOOK_PATH: String = "res://tests/gut/support/gf_test_shutdown_hook.gd"
const _GODOT_EXIT_LEAK_BASELINE_PATH: String = "res://.gf/godot_exit_leak_baseline.json"


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


func test_vendored_gf_source_is_pinned() -> void:
	var issues: Array[String] = []
	if not FileAccess.file_exists(_VENDOR_LOCKFILE_PATH):
		_append_string(issues, "手动 vendored GF 必须提交 .gf/vendor.lock.json。")
		assert_true(false, _join_lines(issues))
		return

	var vendor_lock: Dictionary = _read_json_dictionary(_VENDOR_LOCKFILE_PATH)
	var plugin_config: ConfigFile = _load_config_file(_GF_PLUGIN_CONFIG_PATH)
	var plugin_version: String = _get_config_text(plugin_config, "plugin", "version")
	var locked_version: String = _get_dictionary_text(vendor_lock, "framework_version")
	var source_commit: String = _get_dictionary_text(vendor_lock, "source_commit")
	var tree_sha256: String = _get_dictionary_text(vendor_lock, "vendor_tree_sha256")

	if _get_dictionary_int(vendor_lock, "schema_version", 0) != 1:
		_append_string(issues, "GF vendor lock schema_version 必须为 1。")
	if _get_dictionary_text(vendor_lock, "source_kind") != "vendored_git_snapshot":
		_append_string(issues, "GF vendor lock source_kind 必须为 vendored_git_snapshot。")
	if locked_version != plugin_version:
		_append_string(issues, "GF vendor lock version=%s 应与 plugin.cfg version=%s 一致。" % [locked_version, plugin_version])
	if source_commit.length() != 40 or not _is_hex_text(source_commit):
		_append_string(issues, "GF vendor lock source_commit 必须是 40 位 Git commit。")
	if tree_sha256.length() != 64 or not _is_hex_text(tree_sha256):
		_append_string(issues, "GF vendor lock vendor_tree_sha256 必须是 64 位 SHA-256。")
	if _get_dictionary_int(vendor_lock, "vendor_file_count", 0) <= 0:
		_append_string(issues, "GF vendor lock vendor_file_count 必须大于 0。")

	assert_true(issues.is_empty(), "vendored GF 必须有可验证的精确来源：\n%s" % _join_lines(issues))


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


func test_extension_selection_is_explicit_and_export_strict() -> void:
	var project_config: ConfigFile = _load_config_file(_PROJECT_CONFIG_PATH)
	var issues: Array[String] = []

	if _get_config_text(project_config, "gf", "extensions/selection_mode") != "explicit":
		_append_string(issues, "GF 扩展选择模式必须为 explicit。")
	if not _get_config_bool(project_config, "gf", "extensions/auto_install_enabled_installers", false):
		_append_string(issues, "启用扩展必须自动安装其 installer。")
	if not _get_config_bool(project_config, "gf", "extensions/export_exclude_disabled", false):
		_append_string(issues, "导出时必须排除禁用扩展。")
	if not _get_config_bool(project_config, "gf", "extensions/export_fail_on_disabled_references", false):
		_append_string(issues, "导出发现禁用扩展引用时必须失败。")

	assert_true(issues.is_empty(), "GF 扩展选择和导出策略必须保持严格：\n%s" % _join_lines(issues))


func test_project_installers_use_auditable_resource_paths() -> void:
	var project_config: ConfigFile = _load_config_file(_PROJECT_CONFIG_PATH)
	var installer_paths: PackedStringArray = _get_config_packed_string_array(
		project_config,
		"gf",
		"project/installers"
	)
	var issues: Array[String] = []

	if installer_paths.is_empty():
		_append_string(issues, "GF 项目必须声明至少一个 Installer。")
	for installer_path: String in installer_paths:
		if not installer_path.begins_with("res://") or not installer_path.ends_with(".gd"):
			_append_string(issues, "GF Installer 必须使用 res:// GDScript 路径：%s。" % installer_path)
		elif not ResourceLoader.exists(installer_path, "Script"):
			_append_string(issues, "GF Installer 路径不可加载：%s。" % installer_path)

	assert_true(issues.is_empty(), "GF Installer 必须可追溯、可加载：\n%s" % _join_lines(issues))


func test_gut_runner_tracks_gf_shutdown_debt_without_regressions() -> void:
	var runner_text: String = _read_text(_GUT_RUNNER_PATH)
	var hook_text: String = _read_text(_GUT_SHUTDOWN_HOOK_PATH)
	var baseline: Dictionary = _read_json_dictionary(_GODOT_EXIT_LEAK_BASELINE_PATH)
	var vendor_lock: Dictionary = _read_json_dictionary(_VENDOR_LOCKFILE_PATH)
	var issues: Array[String] = []

	if not runner_text.contains("-gpost_run_script=$PostRunScript"):
		_append_string(issues, "GUT 安全运行器必须安装 post-run 清理 hook。")
	if not runner_text.contains(_GUT_SHUTDOWN_HOOK_PATH.trim_prefix("res://")):
		_append_string(issues, "GUT 安全运行器必须默认使用 GF 清理 hook。")
	if not hook_text.contains("GFExtensionSettings.clear_manifest_cache()"):
		_append_string(issues, "GUT post-run hook 必须释放 GF 扩展发现缓存。")
	if not runner_text.contains("Get-GodotExitLeakBaselineIssues"):
		_append_string(issues, "GUT 安全运行器必须对退出泄漏做版本化非回归检查。")
	if _get_dictionary_int(baseline, "schema_version", 0) != 1:
		_append_string(issues, "Godot 退出泄漏基线 schema_version 必须为 1。")
	if _get_dictionary_text(baseline, "godot_version") != "4.7":
		_append_string(issues, "Godot 退出泄漏基线必须绑定当前 4.7 运行时。")
	if _get_dictionary_text(baseline, "gf_version") != "7.0.0":
		_append_string(issues, "Godot 退出泄漏基线必须绑定当前 GF 7.0.0。")
	if _get_dictionary_text(baseline, "gut_version") != "9.7.1":
		_append_string(issues, "Godot 退出泄漏基线必须绑定当前 GUT 9.7.1。")
	if (
		_get_dictionary_text(baseline, "gf_source_commit")
		!= _get_dictionary_text(vendor_lock, "source_commit")
	):
		_append_string(issues, "Godot 退出泄漏基线必须绑定已审计的 GF source commit。")
	if (
		_get_dictionary_text(baseline, "gf_vendor_tree_sha256")
		!= _get_dictionary_text(vendor_lock, "vendor_tree_sha256")
	):
		_append_string(issues, "Godot 退出泄漏基线必须绑定已审计的 GF vendor tree。")
	var gf_global_script_class_count: int = _count_declared_script_classes("res://addons/gf")
	if (
		_get_dictionary_int(baseline, "gf_global_script_class_count", 0)
		!= gf_global_script_class_count
	):
		_append_string(issues, "Godot 退出泄漏基线记录的 GF 全局脚本类数量应为 %d。" % gf_global_script_class_count)
	if _get_dictionary_int(baseline, "max_objectdb_instances", 0) <= 0:
		_append_string(issues, "Godot 退出泄漏基线必须记录已审查的 ObjectDB 上限。")
	if _get_dictionary_int(baseline, "max_resources_in_use", 0) <= 0:
		_append_string(issues, "Godot 退出泄漏基线必须记录已审查的 Resource 上限。")

	assert_true(issues.is_empty(), "GUT 退出必须释放可控缓存，并禁止已知上游清理债务增长：\n%s" % _join_lines(issues))


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

func _count_declared_script_classes(root_path: String) -> int:
	var count: int = 0
	var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths(root_path, {
		"recursive": true,
		"include_addons": true,
		"include_hidden": false,
		"max_scan_depth": 64,
		"max_resource_paths": 10000,
	})
	for path: String in paths:
		var lines: PackedStringArray = _read_text(path).split("\n")
		for raw_line: String in lines:
			if raw_line.strip_edges().begins_with("class_name "):
				count += 1
				break
	return count


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


func _get_config_bool(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	if not config.has_section_key(section, key):
		return fallback
	return GFVariantData.to_bool(config.get_value(section, key, fallback), fallback)


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


func _get_dictionary_int(source: Dictionary, key: Variant, fallback: int = 0) -> int:
	return GFVariantData.to_int(source.get(key, fallback), fallback)


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


func _is_hex_text(value: String) -> bool:
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var is_digit: bool = code >= 48 and code <= 57
		var is_lower_hex: bool = code >= 97 and code <= 102
		var is_upper_hex: bool = code >= 65 and code <= 70
		if not is_digit and not is_lower_hex and not is_upper_hex:
			return false
	return not value.is_empty()


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)
