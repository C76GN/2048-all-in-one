## 验证微信小游戏产物门禁会执行真实目录、JSON、白名单与预算检查。
extends GutTest


# --- 常量 ---

const ArtifactVerifier = preload(
	"res://tools/wechat_minigame_artifact_verifier.gd"
)
const _FIXTURE_ROOT: String = "res://build/test_wechat_minigame_artifact_verifier"
const _CHUNK_LOADER_SOURCE_PATH: String = (
	"res://tools/wechat_minigame/chunked_file_loader.js"
)
const _PROJECT_NAME: String = "2048 Chunked Toolchain Smoke"
const _REQUIRED_FILES: PackedStringArray = [
	"engine/2048-all-in-one.bin",
	"engine/game.js",
	"engine/wechat-chunked-file-loader.js",
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


# --- GUT 生命周期方法 ---

func before_each() -> void:
	_remove_fixture()
	assert_true(_create_valid_fixture())


func after_each() -> void:
	_remove_fixture()


# --- 测试用例 ---

func test_valid_fixture_passes_real_file_json_loader_and_budget_checks() -> void:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(GFVariantData.get_option_bool(report, "ok"))
	assert_true(_get_issues(report).is_empty())
	var package: Dictionary = GFVariantData.get_option_dictionary(report, "package")
	assert_true(GFVariantData.get_option_bool(package, "main_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(package, "total_hard_limit_ok"))


func test_unknown_file_and_stale_loader_are_rejected() -> void:
	assert_true(_write_text("unexpected.html", "<html></html>"))
	assert_true(_write_text("engine/game.js", "GODOTSDK.startGame('godot', 'empty-tips.bin')"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "unexpected_file:unexpected.html"))
	assert_true(_has_issue(report, "forbidden_browser_artifact:unexpected.html"))
	assert_true(_has_issue(report, "loader_pack_reference_missing:"))
	assert_true(_has_issue(report, "loader_uses_upstream_sample_pack"))


func test_upstream_sample_app_id_is_rejected() -> void:
	assert_true(_write_project_config("wxda5f10e2e9114855"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "project_app_id_is_upstream_sample:"))


func test_generic_template_project_identity_is_rejected() -> void:
	assert_true(_write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": "wxgame",
			"compileType": "minigame",
			"appid": "",
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "project_name_not_distinct"))


func test_main_package_over_hard_limit_is_rejected() -> void:
	var oversized_bytes: PackedByteArray = PackedByteArray()
	var _resize_error: Error = oversized_bytes.resize(
		ArtifactVerifier.MAIN_PACKAGE_HARD_LIMIT_BYTES + 1
	) as Error
	assert_true(_write_bytes("game.js", oversized_bytes))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "main_package_hard_limit_exceeded:"))


func test_empty_configuration_objects_are_rejected() -> void:
	assert_true(_write_text("project.config.json", "{}"))
	assert_true(_write_text("game.json", "{}"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "project_compile_type_not_minigame"))
	assert_true(_has_issue(report, "game_orientation_not_landscape"))
	assert_true(_has_issue(report, "game_engine_subpackage_not_exact"))


func test_private_configuration_cannot_override_identity_or_compile_type() -> void:
	assert_true(_write_text(
		"project.private.config.json",
		JSON.stringify({
			"appid": "wxda5f10e2e9114855",
			"compileType": "gamePlugin",
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "private_config_overrides_app_id"))
	assert_true(_has_issue(report, "private_config_overrides_compile_type"))


func test_pack_inspection_rejects_a_nonisolated_project_host() -> void:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT, true)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "pack_inspection_host_not_isolated"))


func test_missing_or_modified_chunk_loader_is_rejected() -> void:
	var helper_path: String = ProjectSettings.globalize_path(
		_FIXTURE_ROOT.path_join("engine/wechat-chunked-file-loader.js")
	)
	assert_true(DirAccess.remove_absolute(helper_path) == OK)
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var missing_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(
		missing_report,
		"required_file_missing:engine/wechat-chunked-file-loader.js"
	))

	assert_true(_write_text("engine/wechat-chunked-file-loader.js", "modified"))
	var modified_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(modified_report, "chunk_loader_hash_mismatch:"))


func test_chunk_loader_install_order_and_resource_sizes_are_enforced() -> void:
	assert_true(_write_text(
		"engine/game.js",
		"GODOTSDK.startGame('/engine/godot', '/engine/2048-all-in-one.bin')\n" +
		"GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(" +
		"GameGlobal.fsUtils, wx.getFileSystemManager(), {}, {chunkBytes: 4194304});\n"
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var order_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(order_report, "chunk_loader_import_missing"))
	assert_true(_has_issue(order_report, "chunk_loader_install_not_before_start"))
	assert_true(_has_issue(order_report, "chunk_loader_manifest_missing"))

	assert_true(_write_text(
		"engine/game.js",
		_valid_loader_text(8, 7)
	))
	var size_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(
		size_report,
		"chunk_loader_resource_size_mismatch:/engine/godot.wasm.br:8:7"
	))


func test_chunk_loader_rejects_wrong_chunk_size_and_manifest_paths() -> void:
	assert_true(_write_text(
		"engine/game.js",
		"import './wechat-chunked-file-loader'\n" +
		"const chunkedResourceBytes = Object.freeze(" +
		JSON.stringify({
			"/engine/godot.wasm.br": 7,
			"/engine/unexpected.bin": 7,
		}) +
		");\n" +
		"GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(" +
		"GameGlobal.fsUtils, wx.getFileSystemManager(), chunkedResourceBytes, " +
		"{chunkBytes: 10485760});\n" +
		"GODOTSDK.startGame('/engine/godot', '/engine/2048-all-in-one.bin')\n"
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "chunk_loader_chunk_bytes_not_4194304"))
	assert_true(_has_issue(report, "chunk_loader_manifest_paths_not_exact"))


func test_unpatched_or_fail_silent_wxmemfs_rename_is_rejected() -> void:
	assert_true(_write_text(
		"engine/godot.js",
		"rename:function(old_node,new_dir,new_name){" +
		'delete old_node["parent"]["contents"][old_node["name"]];' +
		'wx["getFileSystemManager"]()["renameSync"](oldWxPath,newWxPath)' +
		"},unlink:function(){}"
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "wxmemfs_rename_patch_marker_missing"))
	assert_true(_has_issue(
		report,
		"wxmemfs_physical_rename_not_before_memory_mutation"
	))
	assert_true(_has_issue(report, "wxmemfs_rename_failure_not_fail_closed"))


# --- 私有/辅助方法 ---

func _create_valid_fixture() -> bool:
	var absolute_root: String = ProjectSettings.globalize_path(_FIXTURE_ROOT)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return false
	for relative_path: String in _REQUIRED_FILES:
		if not _write_text(relative_path, "fixture"):
			return false
	if not _write_bytes(
		"engine/wechat-chunked-file-loader.js",
		FileAccess.get_file_as_bytes(_CHUNK_LOADER_SOURCE_PATH)
	):
		return false
	if not _write_text("engine/godot.js", _valid_wxmemfs_runtime_text()):
		return false
	if not _write_text(
		"engine/game.js",
		_valid_loader_text(7, 7)
	):
		return false
	if not _write_project_config(""):
		return false
	return _write_text(
		"game.json",
		JSON.stringify({
			"deviceOrientation": "landscape",
			"subpackages": [{"name": "engine", "root": "engine/"}],
		})
	)


func _valid_loader_text(wasm_bytes: int, pack_bytes: int) -> String:
	return (
		"import './wechat-chunked-file-loader'\n" +
		"const chunkedResourceBytes = Object.freeze(" +
		JSON.stringify({
			"/engine/godot.wasm.br": wasm_bytes,
			"/engine/2048-all-in-one.bin": pack_bytes,
		}) +
		");\n" +
		"GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(" +
		"GameGlobal.fsUtils, wx.getFileSystemManager(), chunkedResourceBytes, " +
		"{chunkBytes: 4194304});\n" +
		"GODOTSDK.startGame('/engine/godot', '/engine/2048-all-in-one.bin')\n"
	)


func _valid_wxmemfs_runtime_text() -> String:
	return (
		"rename:function(old_node,new_dir,new_name){" +
		'wx["getFileSystemManager"]()["renameSync"](oldWxPath,newWxPath);' +
		'try{}catch(e){throw new FS["ErrnoError"](29)}' +
		'delete old_node["parent"]["contents"][old_node["name"]];' +
		"/*2048-wechat-wxmemfs-rename-v1*/" +
		"},unlink:function(){}"
	)


func _write_project_config(app_id: String) -> bool:
	return _write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": _PROJECT_NAME,
			"compileType": "minigame",
			"appid": app_id,
		})
	)


func _write_text(relative_path: String, text: String) -> bool:
	return _write_bytes(relative_path, text.to_utf8_buffer())


func _write_bytes(relative_path: String, bytes: PackedByteArray) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(
		_FIXTURE_ROOT.path_join(relative_path)
	)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		return false
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored: bool = file.store_buffer(bytes)
	return stored and file.get_error() == OK


func _get_issues(report: Dictionary) -> PackedStringArray:
	var issues_value: Variant = report.get("issues", PackedStringArray())
	if issues_value is PackedStringArray:
		var issues: PackedStringArray = issues_value
		return issues
	return PackedStringArray()


func _has_issue(report: Dictionary, prefix: String) -> bool:
	for issue: String in _get_issues(report):
		if issue.begins_with(prefix):
			return true
	return false


func _remove_fixture() -> void:
	var absolute_root: String = ProjectSettings.globalize_path(_FIXTURE_ROOT)
	for relative_path: String in _REQUIRED_FILES:
		var absolute_path: String = absolute_root.path_join(relative_path)
		if FileAccess.file_exists(absolute_path):
			var _remove_file_error: Error = DirAccess.remove_absolute(absolute_path)
	var unexpected_path: String = absolute_root.path_join("unexpected.html")
	if FileAccess.file_exists(unexpected_path):
		var _remove_unexpected_error: Error = DirAccess.remove_absolute(unexpected_path)
	var private_config_path: String = absolute_root.path_join("project.private.config.json")
	if FileAccess.file_exists(private_config_path):
		var _remove_private_config_error: Error = DirAccess.remove_absolute(private_config_path)
	for relative_directory: String in PackedStringArray(["engine", "images"]):
		var absolute_directory: String = absolute_root.path_join(relative_directory)
		if DirAccess.dir_exists_absolute(absolute_directory):
			var _remove_child_error: Error = DirAccess.remove_absolute(absolute_directory)
	if DirAccess.dir_exists_absolute(absolute_root):
		var _remove_root_error: Error = DirAccess.remove_absolute(absolute_root)
