## 验证微信小游戏产物门禁会执行真实目录、JSON、白名单与预算检查。
extends GutTest


# --- 常量 ---

const ArtifactVerifier = preload(
	"res://tools/wechat_minigame_artifact_verifier.gd"
)
const _FIXTURE_BUNDLE_ROOT: String = (
	"res://build/test_wechat_minigame_artifact_verifier"
)
const _FIXTURE_ROOT: String = _FIXTURE_BUNDLE_ROOT + "/wxgame"
const _REPORT_PATH: String = _FIXTURE_BUNDLE_ROOT + "/export-report.json"
const _CHUNK_LOADER_SOURCE_PATH: String = (
	"res://tools/wechat_minigame/chunked_file_loader.js"
)
const _PROJECT_NAME: String = "2048 Chunked Toolchain Smoke"
const _RELEASE_PROJECT_NAME: String = "2048 Full Game Release Candidate"
const _REQUIRED_FILES: PackedStringArray = [
	"engine/game.js",
	"engine/wechat-chunked-file-loader.js",
	"engine/godot-sdk.js",
	"engine/godot.js",
	"engine/godot.wasm.br",
	"game.js",
	"game.json",
	"game_data/2048-all-in-one.bin",
	"game_data/game.js",
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
	assert_true(GFVariantData.get_option_bool(package, "engine_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(package, "game_data_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(package, "total_hard_limit_ok"))


func test_package_budget_hard_limits_are_inclusive_at_exact_boundaries() -> void:
	var main_exact: Dictionary = ArtifactVerifier.evaluate_package_budget(
		ArtifactVerifier.MAIN_PACKAGE_HARD_LIMIT_BYTES,
		0,
		0
	)
	assert_true(GFVariantData.get_option_bool(main_exact, "main_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(main_exact, "total_hard_limit_ok"))

	var engine_exact: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		ArtifactVerifier.ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES,
		0
	)
	assert_true(GFVariantData.get_option_bool(engine_exact, "engine_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(engine_exact, "total_hard_limit_ok"))

	var game_data_exact: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		0,
		ArtifactVerifier.GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES
	)
	assert_true(GFVariantData.get_option_bool(
		game_data_exact,
		"game_data_hard_limit_ok"
	))
	assert_true(GFVariantData.get_option_bool(game_data_exact, "total_hard_limit_ok"))

	var total_exact: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES / 2,
		ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES / 2
	)
	assert_true(GFVariantData.get_option_bool(total_exact, "total_hard_limit_ok"))

	var main_over: Dictionary = ArtifactVerifier.evaluate_package_budget(
		ArtifactVerifier.MAIN_PACKAGE_HARD_LIMIT_BYTES + 1,
		0,
		0
	)
	assert_false(GFVariantData.get_option_bool(main_over, "main_hard_limit_ok", true))
	assert_true(GFVariantData.get_option_bool(main_over, "total_hard_limit_ok"))

	var engine_over: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		ArtifactVerifier.ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES + 1,
		0
	)
	assert_false(GFVariantData.get_option_bool(engine_over, "engine_hard_limit_ok", true))
	assert_false(GFVariantData.get_option_bool(engine_over, "total_hard_limit_ok", true))

	var game_data_over: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		0,
		ArtifactVerifier.GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES + 1
	)
	assert_false(GFVariantData.get_option_bool(
		game_data_over,
		"game_data_hard_limit_ok",
		true
	))
	assert_false(GFVariantData.get_option_bool(game_data_over, "total_hard_limit_ok", true))

	var total_over: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES / 2,
		ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES / 2 + 1
	)
	assert_true(GFVariantData.get_option_bool(total_over, "main_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(total_over, "engine_hard_limit_ok"))
	assert_true(GFVariantData.get_option_bool(total_over, "game_data_hard_limit_ok"))
	assert_false(GFVariantData.get_option_bool(total_over, "total_hard_limit_ok", true))


func test_candidate_build_id_uses_the_cross_tool_canonical_framing() -> void:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var export_report: Dictionary = {
		"scope": ArtifactVerifier.PROFILE_SCOPE_SMOKE,
		"export_preset": "Web Compatibility Smoke",
		"godot": {"version": "4.7.2.stable.official.abcdef123"},
		"gf": {
			"framework_version": "11.0.0-dev.0",
			"source_commit": "a".repeat(40),
			"source_git_tree": "b".repeat(40),
			"vendor_tree_sha256": "c".repeat(64),
			"vendor_file_count": 1967,
			"lock_sha256": "d".repeat(64),
		},
		"input_snapshot_sha256": "e".repeat(64),
		"input_snapshot": {"file_count": 1234},
		"artifact_manifest_sha256": "f".repeat(64),
		"template": {
			"sha256": (
				"ae5bdeb5ba1ce9712d4efc35d337cb5ecbef3ad5bfb0f7d06ae9cb662c1f2d71"
			),
		},
		"tool_identity": {
			"export_tool": {"sha256": "0".repeat(64)},
			"artifact_verifier": {"sha256": "1".repeat(64)},
			"artifact_check": {"sha256": "2".repeat(64)},
			"bounded_json_reader": {"sha256": "3".repeat(64)},
			"path_tools": {"sha256": "4".repeat(64)},
			"chunk_loader": {"sha256": "5".repeat(64)},
			"wxmemfs_patch": {"sha256": "6".repeat(64)},
		},
	}
	var actual_build_id: String = verifier.compute_report_build_id(export_report)
	assert_true(
		actual_build_id ==
			"274bffc55db1555d7607d5dd297d99613139b80b9e76a5882ea432caea2521e7",
		"PowerShell 与 GDScript 必须共享同一 build_id canonical framing。"
	)


func test_report_bound_fixture_recomputes_the_complete_candidate_identity() -> void:
	assert_true(_write_valid_report())
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_true(GFVariantData.get_option_bool(report, "ok"), str(_get_issues(report)))
	assert_true(_get_issues(report).is_empty())


func test_report_bound_release_profile_requires_exact_font_policy() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	assert_true(_write_project_config("", _RELEASE_PROJECT_NAME))
	_refresh_artifact_and_package_evidence(export_report)
	export_report["scope"] = ArtifactVerifier.PROFILE_SCOPE_RELEASE
	export_report["export_preset"] = "Web Compatibility WeChat Release"
	export_report["project_name"] = _RELEASE_PROJECT_NAME
	export_report["font_policy"] = _release_font_policy_fixture()
	export_report["limitations"] = [
		"This candidate contains the full game, but is not a signed production release.",
		"WeChat login, share, payment, cloud save and open-data capabilities are not enabled.",
	]
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	export_report["build_id"] = verifier.compute_report_build_id(export_report)
	assert_true(_write_report(export_report))
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_true(GFVariantData.get_option_bool(report, "ok"), str(_get_issues(report)))

	var font_policy: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"font_policy"
	)
	font_policy["subset_font_sha256"] = "0".repeat(64)
	export_report["font_policy"] = font_policy
	assert_true(_write_report(export_report))
	var tampered_report: Dictionary = verifier.verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_false(GFVariantData.get_option_bool(tampered_report, "ok", true))
	assert_true(_has_issue(
		tampered_report,
		"report_release_font_policy_mismatch:subset_font_sha256"
	))


func test_report_binding_ignores_benign_private_configuration_changes() -> void:
	assert_true(_write_valid_report())
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var baseline: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	var baseline_files: PackedStringArray = _get_files(baseline)
	var baseline_package: Dictionary = GFVariantData.get_option_dictionary(
		baseline,
		"package"
	)

	assert_true(_write_text(
		"project.private.config.json",
		JSON.stringify({"setting": {"urlCheck": false}})
	))
	var added: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_true(GFVariantData.get_option_bool(added, "ok"), str(_get_issues(added)))
	assert_true(_get_files(added) == baseline_files)
	assert_true(
		GFVariantData.get_option_dictionary(added, "package") == baseline_package
	)

	assert_true(_write_text(
		"project.private.config.json",
		JSON.stringify({"setting": {"urlCheck": true, "compileHotReLoad": true}})
	))
	var changed: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_true(GFVariantData.get_option_bool(changed, "ok"), str(_get_issues(changed)))
	assert_true(_get_files(changed) == baseline_files)
	assert_true(
		GFVariantData.get_option_dictionary(changed, "package") == baseline_package
	)


func test_report_binding_still_rejects_malicious_or_malformed_private_config() -> void:
	assert_true(_write_valid_report())
	assert_true(_write_text(
		"project.private.config.json",
		JSON.stringify({
			"appid": "local-identity-override",
			"compileType": "gamePlugin",
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var override_report: Dictionary = verifier.verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_false(GFVariantData.get_option_bool(override_report, "ok", true))
	assert_true(_has_issue(override_report, "private_config_overrides_app_id"))
	assert_true(_has_issue(override_report, "private_config_overrides_compile_type"))

	assert_true(_write_text("project.private.config.json", "{"))
	var malformed_report: Dictionary = verifier.verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_false(GFVariantData.get_option_bool(malformed_report, "ok", true))
	assert_true(_has_issue(malformed_report, "project_private_config_invalid_json"))


func test_report_binding_still_rejects_other_additional_files() -> void:
	assert_true(_write_valid_report())
	assert_true(_write_text("unexpected.json", "{}"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "unexpected_file:unexpected.json"))
	assert_true(_has_issue(report, "artifact_manifest_hash_mismatch"))
	assert_true(_has_issue(report, "report_package_files_not_exact"))


func test_report_bound_fixture_rejects_same_length_artifact_byte_drift() -> void:
	assert_true(_write_valid_report())
	assert_true(_write_text("images/logo.png", "mutated"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "artifact_manifest_hash_mismatch"))
	assert_true(_has_issue(report, "artifact_file_hash_mismatch:images/logo.png"))
	assert_false(_has_issue(report, "artifact_file_bytes_mismatch:images/logo.png"))


func test_report_bound_fixture_rejects_tool_identity_and_build_id_drift() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	var tool_identity: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"tool_identity"
	)
	var export_tool: Dictionary = GFVariantData.get_option_dictionary(
		tool_identity,
		"export_tool"
	)
	export_tool["sha256"] = "0".repeat(64)
	tool_identity["export_tool"] = export_tool
	export_report["tool_identity"] = tool_identity
	assert_true(_write_report(export_report))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "report_tool_hash_mismatch:export_tool"))
	assert_true(_has_issue(report, "report_build_id_mismatch"))


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


func test_each_subpackage_over_hard_limit_is_rejected() -> void:
	var oversized_bytes: PackedByteArray = PackedByteArray()
	assert_true(oversized_bytes.resize(
		ArtifactVerifier.ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES + 1
	) == OK)
	assert_true(_write_bytes("engine/godot.wasm.br", oversized_bytes))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var engine_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(engine_report, "engine_subpackage_hard_limit_exceeded:"))

	assert_true(_create_valid_fixture())
	assert_true(_write_bytes("game_data/2048-all-in-one.bin", oversized_bytes))
	var game_data_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(
		game_data_report,
		"game_data_subpackage_hard_limit_exceeded:"
	))


func test_empty_configuration_objects_are_rejected() -> void:
	assert_true(_write_text("project.config.json", "{}"))
	assert_true(_write_text("game.json", "{}"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "project_compile_type_not_minigame"))
	assert_true(_has_issue(report, "game_orientation_not_landscape"))
	assert_true(_has_issue(report, "game_subpackages_not_exact"))


func test_project_config_is_rejected_before_parsing_when_oversized() -> void:
	assert_true(_write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": _PROJECT_NAME,
			"compileType": "minigame",
			"appid": "",
			"padding": "x".repeat(70 * 1024),
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(
		report,
		"project_config_invalid_json:payload_too_large"
	))


func test_game_config_is_rejected_before_parsing_when_too_deep() -> void:
	var nested_json: String = "{}"
	for _depth: int in range(20):
		nested_json = '{"level":%s}' % nested_json
	assert_true(_write_text("game.json", nested_json))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "game_config_invalid_json:nesting_too_deep"))


func test_export_report_is_rejected_before_parsing_when_oversized() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	export_report["padding"] = "x".repeat(300 * 1024)
	assert_true(_write_report(export_report))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(
		report,
		"export_report_invalid_json:payload_too_large"
	))


func test_miniprogram_compile_type_is_rejected() -> void:
	assert_true(_write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": _PROJECT_NAME,
			"compileType": "miniprogram",
			"appid": "",
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(report, "project_compile_type_not_minigame"))


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
		"GODOTSDK.startGame('/engine/godot', '/game_data/2048-all-in-one.bin')\n" +
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
		"GODOTSDK.startGame('/engine/godot', '/game_data/2048-all-in-one.bin')\n"
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "chunk_loader_chunk_bytes_not_4194304"))
	assert_true(_has_issue(report, "chunk_loader_manifest_paths_not_exact"))


func test_subpackage_entry_markers_and_serial_load_order_are_enforced() -> void:
	assert_true(_write_text("game_data/game.js", "fixture"))
	assert_true(_write_text("engine/game.js", "fixture"))
	assert_true(_write_text(
		"godot-loader.js",
		'loadPackage("engine","__godotEngineSubpackageEntryStarted",' +
		'"engine/game.js",0.5,()=>{});\n' +
		'loadPackage("game_data","__godotGameDataSubpackageEntryStarted",' +
		'"game_data/game.js",0,()=>{});\n'
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "game_data_entry_marker_missing"))
	assert_true(_has_issue(report, "engine_entry_marker_missing"))
	assert_true(_has_issue(report, "root_loader_data_probe_missing"))
	assert_true(_has_issue(report, "root_loader_subpackage_order_invalid"))


func test_dynamic_binary_files_must_be_forced_into_upload_package() -> void:
	assert_true(_write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": _PROJECT_NAME,
			"compileType": "minigame",
			"appid": "",
			"packOptions": {"ignore": [], "include": []},
		})
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(
		report,
		"project_pack_include_missing:engine/godot.wasm.br"
	))
	assert_true(_has_issue(
		report,
		"project_pack_include_missing:game_data/2048-all-in-one.bin"
	))


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

func _write_valid_report() -> bool:
	return _write_report(_make_valid_export_report())


func _make_valid_export_report() -> Dictionary:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var structural_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(GFVariantData.get_option_bool(structural_report, "ok"))
	var package: Dictionary = GFVariantData.get_option_dictionary(
		structural_report,
		"package"
	)
	var files: PackedStringArray = _get_files(structural_report)
	package["main_hard_limit_bytes"] = ArtifactVerifier.MAIN_PACKAGE_HARD_LIMIT_BYTES
	package["engine_hard_limit_bytes"] = ArtifactVerifier.ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES
	package["game_data_hard_limit_bytes"] = ArtifactVerifier.GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES
	package["total_hard_limit_bytes"] = ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES
	package["main_soft_limit_bytes"] = ArtifactVerifier.MAIN_PACKAGE_SOFT_LIMIT_BYTES
	package["engine_soft_limit_bytes"] = ArtifactVerifier.ENGINE_SUBPACKAGE_SOFT_LIMIT_BYTES
	package["game_data_soft_limit_bytes"] = ArtifactVerifier.GAME_DATA_SUBPACKAGE_SOFT_LIMIT_BYTES
	package["total_soft_limit_bytes"] = ArtifactVerifier.TOTAL_PACKAGE_SOFT_LIMIT_BYTES
	package["file_count"] = files.size()
	package["files"] = files
	package["missing_paths"] = []
	package["unexpected_paths"] = []
	package["forbidden_paths"] = []
	var artifact_manifest: Dictionary = verifier.build_artifact_manifest(_FIXTURE_ROOT)
	var input_hash: String = "e".repeat(64)
	var export_report: Dictionary = {
		"schema_version": ArtifactVerifier.EXPORT_REPORT_SCHEMA_VERSION,
		"ok": true,
		"scope": "toolchain_smoke",
		"build_id": "",
		"export_preset": "Web Compatibility Smoke",
		"input_snapshot_sha256": input_hash,
		"artifact_manifest_sha256": str(
			artifact_manifest.get("manifest_sha256", "")
		),
		"godot": {
			"executable": "fixture",
			"version": _get_godot_report_version(),
			"required_version_prefix": ArtifactVerifier.REQUIRED_GODOT_VERSION_PREFIX,
		},
		"gf": {
			"framework_version": "11.0.0-dev.0",
			"source_commit": "a".repeat(40),
			"source_git_tree": "b".repeat(40),
			"vendor_tree_sha256": "c".repeat(64),
			"vendor_file_count": 1,
			"lock_sha256": "d".repeat(64),
		},
		"input_snapshot": {
			"schema_version": ArtifactVerifier.INPUT_SNAPSHOT_SCHEMA_VERSION,
			"input_snapshot_sha256": input_hash,
			"file_count": 1,
			"rules": {
				"include_exact": [
					"default_bus_layout.tres",
					"export_presets.cfg",
					"icon.svg",
					"icon.svg.import",
					"project.godot",
				],
				"include_roots": ["addons", "app", "features", "shared"],
				"exclude_exact": [
					"features/asset_library/resources/import_sources.json",
					"features/asset_library/resources/import_sources.local.json",
					"shared/assets/fonts/noto_sans_sc_variable.ttf",
				],
				"exclude_prefixes": [
					"addons/gf/tools/",
					"addons/gut/",
					"features/asset_library/resources/review/",
					"features/asset_library/resources/source_packs/",
					"features/asset_library/tools/",
					"features/platform_runtime/tools/",
					"features/themes/tools/",
				],
				"exclude_generated": [
					".git/",
					".godot/",
					"build/",
					"tests/",
					"tools/",
					"__pycache__/",
				],
				"exclude_cache_suffixes": [".pyc", ".pyo"],
			},
		},
		"tool_identity": verifier.build_tool_identity(),
		"template": {
			"release": "4.7",
			"asset": "minigame4.7.tpz",
			"expected_bytes": 11_763_895,
			"sha256": (
				"ae5bdeb5ba1ce9712d4efc35d337cb5ecbef3ad5bfb0f7d06ae9cb662c1f2d71"
			),
		},
		"artifact": artifact_manifest,
		"package": package,
		"project_name": _PROJECT_NAME,
		"device_orientation": "landscape",
	}
	export_report["build_id"] = verifier.compute_report_build_id(export_report)
	return export_report


func _get_godot_report_version() -> String:
	var version_info: Dictionary = Engine.get_version_info()
	var version: String = "%d.%d.%d.%s" % [
		GFVariantData.get_option_int(version_info, "major"),
		GFVariantData.get_option_int(version_info, "minor"),
		GFVariantData.get_option_int(version_info, "patch"),
		str(version_info.get("status", "")),
	]
	var build: String = str(version_info.get("build", ""))
	var version_hash: String = str(version_info.get("hash", ""))
	if not build.is_empty():
		version += "." + build
	if not version_hash.is_empty():
		version += "." + version_hash.left(9)
	return version


func _write_report(export_report: Dictionary) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(_REPORT_PATH)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		return false
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return false
	return file.store_string(JSON.stringify(export_report) + "\n")


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
	if not _write_text(
		"game_data/game.js",
		"GameGlobal.__godotGameDataSubpackageEntryStarted = true;\n"
	):
		return false
	if not _write_text("godot-loader.js", _valid_root_loader_text()):
		return false
	if not _write_project_config(""):
		return false
	return _write_text(
		"game.json",
		JSON.stringify({
			"deviceOrientation": "landscape",
		"subpackages": [
				{"name": "game_data", "root": "game_data/"},
				{"name": "engine", "root": "engine/"},
			],
		})
	)


func _valid_loader_text(wasm_bytes: int, pack_bytes: int) -> String:
	return (
		"GameGlobal.__godotEngineSubpackageEntryStarted = true;\n" +
		"import './wechat-chunked-file-loader'\n" +
		"const chunkedResourceBytes = Object.freeze(" +
		JSON.stringify({
			"/engine/godot.wasm.br": wasm_bytes,
			"/game_data/2048-all-in-one.bin": pack_bytes,
		}) +
		");\n" +
		"GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(" +
		"GameGlobal.fsUtils, wx.getFileSystemManager(), chunkedResourceBytes, " +
		"{chunkBytes: 4194304});\n" +
		"GODOTSDK.startGame('/engine/godot', '/game_data/2048-all-in-one.bin')\n"
	)


func _valid_root_loader_text() -> String:
	return (
		'loadPackage("game_data","__godotGameDataSubpackageEntryStarted",' +
		'"game_data/game.js",0,()=>{\n' +
		"probeGameData(()=>{\n" +
		'loadPackage("engine","__godotEngineSubpackageEntryStarted",' +
		'"engine/game.js",0.5,()=>{});\n' +
		"});\n" +
		"});\n"
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


func _write_project_config(
	app_id: String,
	project_name: String = _PROJECT_NAME
) -> bool:
	return _write_text(
		"project.config.json",
		JSON.stringify({
			"projectname": project_name,
			"compileType": "minigame",
			"appid": app_id,
			"packOptions": {
				"ignore": [],
				"include": [
					{"type": "file", "value": "engine/godot.wasm.br"},
					{
						"type": "file",
						"value": "game_data/2048-all-in-one.bin",
					},
				],
			},
		})
	)


func _refresh_artifact_and_package_evidence(export_report: Dictionary) -> void:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var structural_report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	var package: Dictionary = GFVariantData.get_option_dictionary(
		structural_report,
		"package"
	)
	var files: PackedStringArray = _get_files(structural_report)
	package["main_hard_limit_bytes"] = ArtifactVerifier.MAIN_PACKAGE_HARD_LIMIT_BYTES
	package["engine_hard_limit_bytes"] = ArtifactVerifier.ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES
	package["game_data_hard_limit_bytes"] = ArtifactVerifier.GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES
	package["total_hard_limit_bytes"] = ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES
	package["main_soft_limit_bytes"] = ArtifactVerifier.MAIN_PACKAGE_SOFT_LIMIT_BYTES
	package["engine_soft_limit_bytes"] = ArtifactVerifier.ENGINE_SUBPACKAGE_SOFT_LIMIT_BYTES
	package["game_data_soft_limit_bytes"] = ArtifactVerifier.GAME_DATA_SUBPACKAGE_SOFT_LIMIT_BYTES
	package["total_soft_limit_bytes"] = ArtifactVerifier.TOTAL_PACKAGE_SOFT_LIMIT_BYTES
	package["file_count"] = files.size()
	package["files"] = files
	package["missing_paths"] = []
	package["unexpected_paths"] = []
	package["forbidden_paths"] = []
	var artifact_manifest: Dictionary = verifier.build_artifact_manifest(_FIXTURE_ROOT)
	export_report["artifact"] = artifact_manifest
	export_report["artifact_manifest_sha256"] = str(
		artifact_manifest.get("manifest_sha256", "")
	)
	export_report["package"] = package


func _release_font_policy_fixture() -> Dictionary:
	var manifest_path: String = (
		"res://shared/assets/fonts/wechat_release_font_coverage.json"
	)
	var manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(manifest_path)
	)
	assert_true(manifest_value is Dictionary)
	if not manifest_value is Dictionary:
		return {}
	var manifest: Dictionary = manifest_value
	var coverage: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"coverage"
	)
	var subset_font: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"subset_font"
	)
	var source_font: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"source_font"
	)
	var license: Dictionary = GFVariantData.get_option_dictionary(manifest, "license")
	return {
		"policy_id": str(manifest.get("policy_id", "")),
		"coverage_manifest_path": manifest_path.trim_prefix("res://"),
		"coverage_manifest_sha256": FileAccess.get_sha256(manifest_path).to_lower(),
		"coverage_path": "shared/assets/fonts/wechat_release_font_coverage.txt",
		"coverage_sha256": str(coverage.get("codepoints_sha256", "")),
		"codepoint_count": GFVariantData.get_option_int(coverage, "codepoint_count"),
		"subset_font_path": str(subset_font.get("path", "")),
		"subset_font_sha256": str(subset_font.get("sha256", "")),
		"subset_font_bytes": GFVariantData.get_option_int(subset_font, "bytes"),
		"source_font_path": str(source_font.get("path", "")),
		"source_font_sha256": str(source_font.get("sha256", "")),
		"license_path": str(license.get("path", "")),
		"license_spdx": str(license.get("spdx", "")),
		"license_sha256": str(license.get("sha256", "")),
	}


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


func _get_files(report: Dictionary) -> PackedStringArray:
	var files_value: Variant = report.get("files", PackedStringArray())
	if files_value is PackedStringArray:
		var files: PackedStringArray = files_value
		return files
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
	var unexpected_json_path: String = absolute_root.path_join("unexpected.json")
	if FileAccess.file_exists(unexpected_json_path):
		var _remove_unexpected_json_error: Error = DirAccess.remove_absolute(
			unexpected_json_path
		)
	var private_config_path: String = absolute_root.path_join("project.private.config.json")
	if FileAccess.file_exists(private_config_path):
		var _remove_private_config_error: Error = DirAccess.remove_absolute(private_config_path)
	var report_path: String = ProjectSettings.globalize_path(_REPORT_PATH)
	if FileAccess.file_exists(report_path):
		var _remove_report_error: Error = DirAccess.remove_absolute(report_path)
	for relative_directory: String in PackedStringArray(["engine", "images"]):
		var absolute_directory: String = absolute_root.path_join(relative_directory)
		if DirAccess.dir_exists_absolute(absolute_directory):
			var _remove_child_error: Error = DirAccess.remove_absolute(absolute_directory)
	if DirAccess.dir_exists_absolute(absolute_root):
		var _remove_root_error: Error = DirAccess.remove_absolute(absolute_root)
	var absolute_bundle_root: String = ProjectSettings.globalize_path(_FIXTURE_BUNDLE_ROOT)
	if DirAccess.dir_exists_absolute(absolute_bundle_root):
		var _remove_bundle_error: Error = DirAccess.remove_absolute(absolute_bundle_root)
