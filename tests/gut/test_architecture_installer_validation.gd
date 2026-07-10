## 验证项目 Installer 不重复装配 GF 扩展已拥有的 Module。
extends GutTest


# --- 常量 ---

const PROJECT_INSTALLER_PATH: String = "res://scripts/boot/game_architecture_installer.gd"
const EXTENSION_OWNED_MODULES: Array[Dictionary] = [
	{
		"symbol": "GFLevelUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFQuestUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFActionQueueSystem",
		"extension": "gf.action_queue",
		"owner": "addons/gf/extensions/action_queue/extension.gd",
	},
	{
		"symbol": "GFContentPackageUtility",
		"extension": "gf.content_package",
		"owner": "addons/gf/extensions/content_package/extension.gd",
	},
]


# --- 测试用例 ---

func test_project_installer_does_not_bind_extension_owned_modules() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var issues: Array[String] = []
	if source.is_empty():
		_append_string(issues, "%s 无法读取或为空。" % PROJECT_INSTALLER_PATH)

	for module: Dictionary in EXTENSION_OWNED_MODULES:
		var symbol: String = _get_dictionary_text(module, "symbol")
		var extension_id: String = _get_dictionary_text(module, "extension")
		var owner_path: String = _get_dictionary_text(module, "owner")
		if _source_binds_symbol(source, symbol):
			_append_string(issues, "%s 不应在项目 Installer 中手动绑定；它由 %s (%s) 自动装配。" % [
				symbol,
				owner_path,
				extension_id,
			])

	assert_true(
		issues.is_empty(),
		"项目 Installer 应只注册项目自身 Module，避免和 GF 扩展 Installer 重复注册：\n%s" % _join_lines(issues)
	)


# --- 私有/辅助方法 ---

func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _source_binds_symbol(source: String, symbol: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if line.begins_with("#"):
			continue
		if _line_binds_symbol(line, symbol):
			return true
	return false


func _line_binds_symbol(line: String, symbol: String) -> bool:
	var bind_patterns: Array[String] = [
		"bind_utility(%s" % symbol,
		"bind_system(%s" % symbol,
		"register_utility(%s" % symbol,
		"register_system(%s" % symbol,
		"register_utility_instance(%s.new()" % symbol,
		"register_system_instance(%s.new()" % symbol,
	]
	for pattern: String in bind_patterns:
		if line.contains(pattern):
			return true
	return false


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_dictionary_text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: Variant = fallback
	if source.has(key):
		value = source[key]
	return GFVariantData.to_text(value, fallback)


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var _append_result: bool = packed.append(line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)
