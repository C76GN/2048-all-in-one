## 微信小游戏冒烟产物的只读结构、预算、身份与字体边界验证器。
extends RefCounted


# --- 常量 ---

const MAIN_PACKAGE_HARD_LIMIT_BYTES: int = 4_000_000
const TOTAL_PACKAGE_HARD_LIMIT_BYTES: int = 30_000_000
const MAIN_PACKAGE_SOFT_LIMIT_BYTES: int = 3_600_000
const TOTAL_PACKAGE_SOFT_LIMIT_BYTES: int = 27_000_000
const PACK_RELATIVE_PATH: String = "engine/2048-all-in-one.bin"
const PROJECT_NAME: String = "2048 Chunked Toolchain Smoke"
const _PACK_LOADER_REFERENCE: String = "/engine/2048-all-in-one.bin"
const _CHUNK_LOADER_RELATIVE_PATH: String = "engine/wechat-chunked-file-loader.js"
const _CHUNK_LOADER_SHA256: String = (
	"ba1da7e564ea4a4cea46fd2c58ec02a55e3d3b466a2d01f54dbcef98ba22540f"
)
const _CHUNK_LOADER_IMPORT: String = "import './wechat-chunked-file-loader'"
const _CHUNK_LOADER_INSTALL: String = "installChunkedLocalFetch"
const _CHUNK_MANIFEST_PREFIX: String = (
	"const chunkedResourceBytes = Object.freeze("
)
const _CHUNK_BYTES_TOKEN: String = "chunkBytes: 4194304"
const _WXMEMFS_RENAME_PATCH_MARKER: String = "/*2048-wechat-wxmemfs-rename-v1*/"
const _WXMEMFS_RENAME_FUNCTION_TOKEN: String = (
	"rename:function(old_node,new_dir,new_name)"
)
const _WXMEMFS_PHYSICAL_RENAME_TOKEN: String = '["renameSync"](oldWxPath,newWxPath)'
const _WXMEMFS_MEMORY_MUTATION_TOKEN: String = (
	'delete old_node["parent"]["contents"][old_node["name"]]'
)
const _WXMEMFS_RENAME_FAILURE_TOKEN: String = 'throw new FS["ErrnoError"](29)'
const _CHUNK_RESOURCE_PATHS: PackedStringArray = [
	"/engine/godot.wasm.br",
	_PACK_LOADER_REFERENCE,
]
const _FULL_FONT_TOKEN: String = "noto_sans_sc_variable"
const _SMOKE_FONT_TOKEN: String = "wechat_smoke_sans_subset"
const _EXPORT_PLUGIN_CODE_TOKEN: String = "WeChatMiniGameSmokeExportPlugin"
const _SMOKE_FONT_SHA256: String = (
	"38bdd2457e67c2c1721f5734fee67059bc1b961563afb4f3e0f8b8c8b8049c22"
)
const _SMOKE_FONT_PATH: String = "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf"
const _FONT_VARIATION_PATHS: PackedStringArray = [
	"res://shared/assets/fonts/ui_sans_regular.tres",
	"res://shared/assets/fonts/ui_sans_display.tres",
]
const _REQUIRED_PATHS: PackedStringArray = [
	PACK_RELATIVE_PATH,
	"engine/game.js",
	_CHUNK_LOADER_RELATIVE_PATH,
	"engine/godot-sdk.js",
	"engine/godot.js",
	"engine/godot.wasm.br",
	"game.js",
	"game.json",
	"glx-config.js",
	"godot-loader.js",
	"images/background.png",
	"images/logo.png",
	"project.config.json",
	"weapp-adapter.js",
]
const _OPTIONAL_PATHS: PackedStringArray = [
	"project.private.config.json",
]
const _FORBIDDEN_SAMPLE_APP_IDS: PackedStringArray = [
	"wxda5f10e2e9114855",
	"wxf40904ea6120ad08",
]
const _REQUIRED_FONT_TEXT: String = "准备启动跨平台兼容性冒烟微信真机必须加入合法域名"


# --- 公共方法 ---

## 验证一个已组装的微信小游戏冒烟工程。
## @param artifact_root: 微信开发者工具工程的绝对或 res:// 根目录。
## @param inspect_pack: 是否同时扫描并加载项目 .bin 资源包。
## @return: 含 ok、issues、files 与 package 字段的只读报告。
func verify_artifact(artifact_root: String, inspect_pack: bool = false) -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()
	var normalized_root: String = _normalize_root(artifact_root)
	var files: PackedStringArray = PackedStringArray()
	if normalized_root.is_empty() or not DirAccess.dir_exists_absolute(normalized_root):
		_add_issue(issues, "artifact_root_missing:%s" % artifact_root)
		return _make_report(false, files, {}, issues)

	_collect_files(normalized_root, "", files, issues)
	files.sort()
	_validate_file_set(files, issues)
	var package: Dictionary = _measure_package(normalized_root, files, issues)
	_validate_loader(normalized_root, issues)
	_validate_project_config(normalized_root, issues)
	_validate_game_config(normalized_root, issues)
	_validate_private_config(normalized_root, issues)
	if inspect_pack:
		_inspect_pack(normalized_root, issues)
	return _make_report(issues.is_empty(), files, package, issues)


# --- 私有/辅助方法 ---

func _normalize_root(path: String) -> String:
	var normalized: String = path.strip_edges()
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		normalized = ProjectSettings.globalize_path(normalized)
	return normalized.replace("\\", "/").trim_suffix("/")


func _collect_files(
	root: String,
	relative_directory: String,
	files: PackedStringArray,
	issues: PackedStringArray
) -> void:
	var directory_path: String = (
		root if relative_directory.is_empty() else root.path_join(relative_directory)
	)
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		_add_issue(issues, "directory_unreadable:%s" % relative_directory)
		return
	var _list_begin_error: Error = directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		var relative_path: String = (
			entry_name
			if relative_directory.is_empty()
			else relative_directory.path_join(entry_name)
		).replace("\\", "/")
		if directory.is_link(entry_name):
			_add_issue(issues, "linked_artifact_entry:%s" % relative_path)
		elif directory.current_is_dir():
			_collect_files(root, relative_path, files, issues)
		else:
			var _file_added: bool = files.append(relative_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _validate_file_set(files: PackedStringArray, issues: PackedStringArray) -> void:
	for required_path: String in _REQUIRED_PATHS:
		if not files.has(required_path):
			_add_issue(issues, "required_file_missing:%s" % required_path)
	for path: String in files:
		if not _REQUIRED_PATHS.has(path) and not _OPTIONAL_PATHS.has(path):
			_add_issue(issues, "unexpected_file:%s" % path)
		var extension: String = path.get_extension().to_lower()
		if extension == "pck" or extension == "html" or extension == "wasm":
			_add_issue(issues, "forbidden_browser_artifact:%s" % path)


func _measure_package(
	root: String,
	files: PackedStringArray,
	issues: PackedStringArray
) -> Dictionary:
	var main_bytes: int = 0
	var engine_bytes: int = 0
	for relative_path: String in files:
		var file: FileAccess = FileAccess.open(root.path_join(relative_path), FileAccess.READ)
		if file == null:
			_add_issue(issues, "artifact_file_unreadable:%s" % relative_path)
			continue
		var file_bytes: int = file.get_length()
		if relative_path.begins_with("engine/"):
			engine_bytes += file_bytes
		else:
			main_bytes += file_bytes
	var total_bytes: int = main_bytes + engine_bytes
	if main_bytes > MAIN_PACKAGE_HARD_LIMIT_BYTES:
		_add_issue(issues, "main_package_hard_limit_exceeded:%d" % main_bytes)
	if total_bytes > TOTAL_PACKAGE_HARD_LIMIT_BYTES:
		_add_issue(issues, "total_package_hard_limit_exceeded:%d" % total_bytes)
	return {
		"main_package_bytes": main_bytes,
		"engine_package_bytes": engine_bytes,
		"total_package_bytes": total_bytes,
		"main_hard_limit_ok": main_bytes <= MAIN_PACKAGE_HARD_LIMIT_BYTES,
		"total_hard_limit_ok": total_bytes <= TOTAL_PACKAGE_HARD_LIMIT_BYTES,
		"main_soft_budget_ok": main_bytes <= MAIN_PACKAGE_SOFT_LIMIT_BYTES,
		"total_soft_budget_ok": total_bytes <= TOTAL_PACKAGE_SOFT_LIMIT_BYTES,
	}


func _validate_loader(root: String, issues: PackedStringArray) -> void:
	var loader_path: String = root.path_join("engine/game.js")
	var loader_text: String = FileAccess.get_file_as_string(loader_path)
	if not loader_text.contains(_PACK_LOADER_REFERENCE):
		_add_issue(issues, "loader_pack_reference_missing:%s" % _PACK_LOADER_REFERENCE)
	if loader_text.contains("empty-tips.bin") or loader_text.contains("demo-pck.bin"):
		_add_issue(issues, "loader_uses_upstream_sample_pack")
	_validate_chunk_loader(root, loader_text, issues)
	_validate_wxmemfs_runtime(root, issues)


func _validate_wxmemfs_runtime(root: String, issues: PackedStringArray) -> void:
	var runtime_path: String = root.path_join("engine/godot.js")
	var runtime_text: String = FileAccess.get_file_as_string(runtime_path)
	var function_index: int = runtime_text.find(_WXMEMFS_RENAME_FUNCTION_TOKEN)
	var physical_rename_index: int = runtime_text.find(
		_WXMEMFS_PHYSICAL_RENAME_TOKEN,
		maxi(function_index, 0)
	)
	var memory_mutation_index: int = runtime_text.find(
		_WXMEMFS_MEMORY_MUTATION_TOKEN,
		maxi(function_index, 0)
	)
	if not runtime_text.contains(_WXMEMFS_RENAME_PATCH_MARKER):
		_add_issue(issues, "wxmemfs_rename_patch_marker_missing")
	if function_index < 0 or physical_rename_index < 0 or memory_mutation_index < 0:
		_add_issue(issues, "wxmemfs_rename_contract_missing")
	elif physical_rename_index > memory_mutation_index:
		_add_issue(issues, "wxmemfs_physical_rename_not_before_memory_mutation")
	if not runtime_text.contains(_WXMEMFS_RENAME_FAILURE_TOKEN):
		_add_issue(issues, "wxmemfs_rename_failure_not_fail_closed")


func _validate_chunk_loader(
	root: String,
	loader_text: String,
	issues: PackedStringArray
) -> void:
	var helper_path: String = root.path_join(_CHUNK_LOADER_RELATIVE_PATH)
	if FileAccess.file_exists(helper_path):
		var actual_hash: String = FileAccess.get_sha256(helper_path).to_lower()
		if actual_hash != _CHUNK_LOADER_SHA256:
			_add_issue(issues, "chunk_loader_hash_mismatch:%s" % actual_hash)

	var import_index: int = loader_text.find(_CHUNK_LOADER_IMPORT)
	if import_index < 0:
		_add_issue(issues, "chunk_loader_import_missing")
	var install_index: int = loader_text.find(_CHUNK_LOADER_INSTALL)
	var start_index: int = loader_text.find("GODOTSDK.startGame(")
	if install_index < 0 or start_index < 0 or install_index > start_index:
		_add_issue(issues, "chunk_loader_install_not_before_start")
	if not loader_text.contains(_CHUNK_BYTES_TOKEN):
		_add_issue(issues, "chunk_loader_chunk_bytes_not_4194304")

	var manifest: Dictionary = _read_chunk_loader_manifest(loader_text, issues)
	if manifest.is_empty():
		return
	var manifest_paths: PackedStringArray = PackedStringArray()
	for path_value: Variant in manifest.keys():
		var _path_added: bool = manifest_paths.append(str(path_value))
	manifest_paths.sort()
	var expected_paths: PackedStringArray = _CHUNK_RESOURCE_PATHS.duplicate()
	expected_paths.sort()
	if manifest_paths != expected_paths:
		_add_issue(issues, "chunk_loader_manifest_paths_not_exact")
		return
	for resource_path: String in _CHUNK_RESOURCE_PATHS:
		var declared_value: Variant = manifest.get(resource_path)
		var declared_bytes: int = 0
		if declared_value is int:
			declared_bytes = declared_value
		elif declared_value is float:
			var declared_float: float = declared_value
			declared_bytes = int(declared_float)
			if float(declared_bytes) != declared_float:
				_add_issue(issues, "chunk_loader_resource_size_invalid:%s" % resource_path)
				continue
		else:
			_add_issue(issues, "chunk_loader_resource_size_invalid:%s" % resource_path)
			continue
		if declared_bytes <= 0:
			_add_issue(issues, "chunk_loader_resource_size_invalid:%s" % resource_path)
			continue
		var artifact_path: String = root.path_join(resource_path.trim_prefix("/"))
		var file: FileAccess = FileAccess.open(artifact_path, FileAccess.READ)
		if file == null:
			continue
		var actual_bytes: int = file.get_length()
		if declared_bytes != actual_bytes:
			_add_issue(issues, "chunk_loader_resource_size_mismatch:%s:%d:%d" % [
				resource_path,
				declared_bytes,
				actual_bytes,
			])


func _read_chunk_loader_manifest(
	loader_text: String,
	issues: PackedStringArray
) -> Dictionary:
	var prefix_index: int = loader_text.find(_CHUNK_MANIFEST_PREFIX)
	if prefix_index < 0:
		_add_issue(issues, "chunk_loader_manifest_missing")
		return {}
	var json_start: int = prefix_index + _CHUNK_MANIFEST_PREFIX.length()
	var json_end: int = loader_text.find(");", json_start)
	if json_end < 0:
		_add_issue(issues, "chunk_loader_manifest_missing")
		return {}
	var parsed_value: Variant = JSON.parse_string(loader_text.substr(
		json_start,
		json_end - json_start
	))
	if not parsed_value is Dictionary:
		_add_issue(issues, "chunk_loader_manifest_invalid_json")
		return {}
	var manifest: Dictionary = parsed_value
	if manifest.is_empty():
		_add_issue(issues, "chunk_loader_manifest_empty")
	return manifest


func _validate_project_config(root: String, issues: PackedStringArray) -> void:
	var config: Dictionary = _read_json_dictionary(
		root.path_join("project.config.json"),
		"project_config",
		issues
	)
	if str(config.get("compileType", "")) != "minigame":
		_add_issue(issues, "project_compile_type_not_minigame")
	if str(config.get("projectname", "")).strip_edges() != PROJECT_NAME:
		_add_issue(issues, "project_name_not_distinct")
	var app_id: String = str(config.get("appid", "")).strip_edges()
	if not _is_valid_app_id(app_id):
		_add_issue(issues, "project_app_id_invalid:%s" % app_id)
	elif _FORBIDDEN_SAMPLE_APP_IDS.has(app_id):
		_add_issue(issues, "project_app_id_is_upstream_sample:%s" % app_id)


func _validate_game_config(root: String, issues: PackedStringArray) -> void:
	var config: Dictionary = _read_json_dictionary(
		root.path_join("game.json"),
		"game_config",
		issues
	)
	if str(config.get("deviceOrientation", "")) != "landscape":
		_add_issue(issues, "game_orientation_not_landscape")
	var subpackages_value: Variant = config.get("subpackages", [])
	if not subpackages_value is Array:
		_add_issue(issues, "game_subpackages_not_array")
		return
	var subpackages: Array = subpackages_value
	if subpackages.size() != 1 or not subpackages[0] is Dictionary:
		_add_issue(issues, "game_engine_subpackage_not_exact")
		return
	var engine_package: Dictionary = subpackages[0]
	if (
		str(engine_package.get("name", "")) != "engine"
		or str(engine_package.get("root", "")) != "engine/"
	):
		_add_issue(issues, "game_engine_subpackage_not_exact")


func _validate_private_config(root: String, issues: PackedStringArray) -> void:
	var path: String = root.path_join("project.private.config.json")
	if not FileAccess.file_exists(path):
		return
	var config: Dictionary = _read_json_dictionary(path, "project_private_config", issues)
	if config.has("appid"):
		_add_issue(issues, "private_config_overrides_app_id")
	if config.has("compileType"):
		_add_issue(issues, "private_config_overrides_compile_type")


func _read_json_dictionary(
	path: String,
	label: String,
	issues: PackedStringArray
) -> Dictionary:
	var parsed_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed_value is Dictionary:
		var dictionary: Dictionary = parsed_value
		return dictionary
	_add_issue(issues, "%s_invalid_json" % label)
	return {}


func _is_valid_app_id(app_id: String) -> bool:
	if app_id.is_empty():
		return true
	if app_id.length() != 18 or not app_id.begins_with("wx"):
		return false
	for index: int in range(2, app_id.length()):
		var codepoint: int = app_id.unicode_at(index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 65 and codepoint <= 90)
			or (codepoint >= 97 and codepoint <= 122)
		):
			return false
	return true


func _inspect_pack(root: String, issues: PackedStringArray) -> void:
	if not _pack_host_is_isolated():
		_add_issue(issues, "pack_inspection_host_not_isolated")
		return
	var pack_path: String = root.path_join(PACK_RELATIVE_PATH)
	var pack_file: FileAccess = FileAccess.open(pack_path, FileAccess.READ)
	if pack_file == null:
		_add_issue(issues, "pack_unreadable:%s" % PACK_RELATIVE_PATH)
		return
	var pack_bytes: PackedByteArray = pack_file.get_buffer(pack_file.get_length())
	if _bytes_contain_text(pack_bytes, _FULL_FONT_TOKEN):
		_add_issue(issues, "pack_contains_full_font_token")
	if not _bytes_contain_text(pack_bytes, _SMOKE_FONT_TOKEN):
		_add_issue(issues, "pack_missing_smoke_font_token")
	if _bytes_contain_text(pack_bytes, _EXPORT_PLUGIN_CODE_TOKEN):
		_add_issue(issues, "pack_contains_editor_export_plugin")
	if not ProjectSettings.load_resource_pack(pack_path, true):
		_add_issue(issues, "pack_mount_failed")
		return
	if not ResourceLoader.exists(_SMOKE_FONT_PATH):
		_add_issue(issues, "pack_smoke_font_resource_missing")
	for variation_path: String in _FONT_VARIATION_PATHS:
		var resource: Resource = load(variation_path)
		if not resource is FontVariation:
			_add_issue(issues, "pack_font_variation_invalid:%s" % variation_path)
			continue
		var font_variation: FontVariation = resource
		if font_variation.base_font == null:
			_add_issue(issues, "pack_font_variation_base_missing:%s" % variation_path)
			continue
		var base_font: Font = font_variation.base_font
		if not base_font is FontFile:
			_add_issue(issues, "pack_font_base_not_font_file:%s" % variation_path)
			continue
		var font_file: FontFile = base_font
		if font_file.allow_system_fallback:
			_add_issue(issues, "pack_font_system_fallback_enabled:%s" % variation_path)
		if _sha256_bytes(font_file.data) != _SMOKE_FONT_SHA256:
			_add_issue(issues, "pack_font_hash_mismatch:%s" % variation_path)
		for index: int in range(_REQUIRED_FONT_TEXT.length()):
			var codepoint: int = _REQUIRED_FONT_TEXT.unicode_at(index)
			if not font_variation.has_char(codepoint):
				_add_issue(
					issues,
					"pack_font_glyph_missing:%s:U+%04X" % [variation_path, codepoint]
				)


func _pack_host_is_isolated() -> bool:
	if ResourceLoader.exists(_SMOKE_FONT_PATH):
		return false
	for variation_path: String in _FONT_VARIATION_PATHS:
		if ResourceLoader.exists(variation_path):
			return false
	return true


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _bytes_contain_text(bytes: PackedByteArray, text: String) -> bool:
	var needle: PackedByteArray = text.to_utf8_buffer()
	if needle.is_empty():
		return true
	if needle.size() > bytes.size():
		return false
	var search_offset: int = 0
	while search_offset <= bytes.size() - needle.size():
		var offset: int = bytes.find(needle[0], search_offset)
		if offset < 0 or offset + needle.size() > bytes.size():
			return false
		var matches: bool = true
		for needle_index: int in range(needle.size()):
			if bytes[offset + needle_index] != needle[needle_index]:
				matches = false
				break
		if matches:
			return true
		search_offset = offset + 1
	return false


func _make_report(
	ok: bool,
	files: PackedStringArray,
	package: Dictionary,
	issues: PackedStringArray
) -> Dictionary:
	return {
		"ok": ok,
		"files": files,
		"package": package,
		"issues": issues,
	}


func _add_issue(issues: PackedStringArray, issue: String) -> void:
	var _issue_added: bool = issues.append(issue)
