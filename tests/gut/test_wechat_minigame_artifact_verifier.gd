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
const _STARTUP_COORDINATOR_SOURCE_PATH: String = (
	"res://tools/wechat_minigame/subpackage_startup_coordinator.js"
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
	"wechat-startup-coordinator.js",
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

	var total_half_limit: int = floori(
		float(ArtifactVerifier.TOTAL_PACKAGE_HARD_LIMIT_BYTES) / 2.0
	)
	var total_exact: Dictionary = ArtifactVerifier.evaluate_package_budget(
		0,
		total_half_limit,
		total_half_limit
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
		total_half_limit,
		total_half_limit + 1
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
			"startup_coordinator": {"sha256": "6".repeat(64)},
			"wxmemfs_patch": {"sha256": "7".repeat(64)},
			"release_resource_closure": {"sha256": "8".repeat(64)},
			"release_resource_policy": {"sha256": "9".repeat(64)},
		},
	}
	var actual_build_id: String = verifier.compute_report_build_id(export_report)
	assert_true(
		actual_build_id ==
			"c49fe442704031e85050b14d3f91232d79928e74354c6eb5756b98cb20535947",
		"PowerShell 与 GDScript 必须共享同一 build_id canonical framing。"
	)


func test_report_bound_fixture_recomputes_the_complete_candidate_identity() -> void:
	assert_true(_write_valid_report())
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_true(GFVariantData.get_option_bool(report, "ok"), str(_get_issues(report)))
	assert_true(_get_issues(report).is_empty())


func test_report_bound_fixture_rejects_render_resolution_evidence_drift() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	var render_resolution: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"render_resolution"
	)
	render_resolution["runtime_sha256"] = "0".repeat(64)
	export_report["render_resolution"] = render_resolution
	assert_true(_write_report(export_report))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_report_bound(_FIXTURE_ROOT, _REPORT_PATH)
	assert_false(GFVariantData.get_option_bool(report, "ok", true))
	assert_true(_has_issue(
		report,
		"report_render_resolution_mismatch:runtime_sha256"
	))


func test_report_bound_fixture_rejects_startup_coordinator_evidence_drift() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	var startup: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"startup"
	)
	startup["strategy"] = "serial"
	startup["engine_start_once"] = false
	startup["engine_start_timeout_ms"] = 1
	export_report["startup"] = startup
	export_report["build_id"] = ArtifactVerifier.new().compute_report_build_id(
		export_report
	)
	assert_true(_write_report(export_report))
	var report: Dictionary = ArtifactVerifier.new().verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_true(_has_issue(report, "report_startup_mismatch:strategy"))
	assert_true(_has_issue(report, "report_startup_mismatch:engine_start_once"))
	assert_true(_has_issue(report, "report_startup_mismatch:engine_start_timeout_ms"))


func test_report_bound_fixture_rejects_large_file_reader_concurrency_drift() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	var large_file_reader: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"large_file_reader"
	)
	large_file_reader["max_concurrent_resources"] = 3
	large_file_reader["inflight_deduplication"] = "disabled"
	export_report["large_file_reader"] = large_file_reader
	export_report["build_id"] = ArtifactVerifier.new().compute_report_build_id(
		export_report
	)
	assert_true(_write_report(export_report))
	var report: Dictionary = ArtifactVerifier.new().verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_true(_has_issue(
		report,
		"report_large_file_reader_mismatch:max_concurrent_resources"
	))
	assert_true(_has_issue(
		report,
		"report_large_file_reader_mismatch:inflight_deduplication"
	))


func test_report_bound_release_profile_requires_exact_font_policy() -> void:
	var export_report: Dictionary = _make_valid_export_report()
	assert_true(_write_project_config("", _RELEASE_PROJECT_NAME))
	_refresh_artifact_and_package_evidence(export_report)
	export_report["scope"] = ArtifactVerifier.PROFILE_SCOPE_RELEASE
	export_report["export_preset"] = "Web Compatibility WeChat Release"
	export_report["project_name"] = _RELEASE_PROJECT_NAME
	export_report["font_policy"] = _release_font_policy_fixture()
	export_report["resource_closure"] = _release_resource_closure_fixture(
		GFVariantData.get_option_dictionary(export_report, "tool_identity")
	)
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


func test_report_bound_release_profile_requires_bound_resource_closure() -> void:
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
	var missing_report: Dictionary = verifier.verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_true(_has_issue(
		missing_report,
		"report_release_resource_closure_missing"
	))

	var resource_closure: Dictionary = _release_resource_closure_fixture(
		GFVariantData.get_option_dictionary(export_report, "tool_identity")
	)
	resource_closure["policy_sha256"] = "0".repeat(64)
	resource_closure["dependency_partial"] = true
	export_report["resource_closure"] = resource_closure
	export_report["build_id"] = verifier.compute_report_build_id(export_report)
	assert_true(_write_report(export_report))
	var tampered_report: Dictionary = verifier.verify_report_bound(
		_FIXTURE_ROOT,
		_REPORT_PATH
	)
	assert_true(_has_issue(
		tampered_report,
		"report_release_resource_closure_mismatch:policy_sha256"
	))
	assert_true(_has_issue(
		tampered_report,
		"report_release_resource_closure_not_complete"
	))


func test_candidate_build_id_binds_release_resource_closure_digest_and_counts() -> void:
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var export_report: Dictionary = _make_valid_export_report()
	var resource_closure: Dictionary = _release_resource_closure_fixture(
		GFVariantData.get_option_dictionary(export_report, "tool_identity")
	)
	export_report["resource_closure"] = resource_closure
	var baseline: String = verifier.compute_report_build_id(export_report)
	resource_closure["closure_sha256"] = "8".repeat(64)
	export_report["resource_closure"] = resource_closure
	assert_ne(verifier.compute_report_build_id(export_report), baseline)
	resource_closure["closure_sha256"] = "7".repeat(64)
	var counts: Dictionary = GFVariantData.get_option_dictionary(
		resource_closure,
		"counts"
	)
	counts["closure"] = GFVariantData.get_option_int(counts, "closure") + 1
	resource_closure["counts"] = counts
	export_report["resource_closure"] = resource_closure
	assert_ne(verifier.compute_report_build_id(export_report), baseline)


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
		"{chunkBytes: 10485760, maxConcurrentResources: 3});\n" +
		"GODOTSDK.startGame('/engine/godot', '/game_data/2048-all-in-one.bin')\n"
	))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "chunk_loader_chunk_bytes_not_4194304"))
	assert_true(_has_issue(report, "chunk_loader_max_concurrent_resources_not_2"))
	assert_true(_has_issue(report, "chunk_loader_manifest_paths_not_exact"))


func test_subpackage_entries_and_parallel_coordinator_contract_are_enforced() -> void:
	assert_true(_write_text("game_data/game.js", "fixture"))
	assert_true(_write_text("engine/game.js", "fixture"))
	assert_true(_write_text(
		"godot-loader.js",
		"const loadPackage=()=>{};\nprobeGameData(()=>{});\n"
	))
	assert_true(_write_text("wechat-startup-coordinator.js", "modified"))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "game_data_entry_marker_missing"))
	assert_true(_has_issue(report, "engine_entry_marker_missing"))
	assert_true(_has_issue(report, "engine_starter_registration_invalid"))
	assert_true(_has_issue(report, "root_loader_startup_coordinator_missing"))
	assert_true(_has_issue(report, "root_loader_startup_option_missing:"))
	assert_true(_has_issue(report, "root_loader_serial_startup_present"))
	assert_true(_has_issue(report, "startup_coordinator_hash_mismatch:"))


func test_render_resolution_cap_and_css_size_contract_are_enforced() -> void:
	var invalid_loader: String = _valid_root_loader_text()
	invalid_loader = invalid_loader.replace("1280/s", "2560/s")
	invalid_loader = invalid_loader.replace(
		"this.offScreenCanvas.height=e*this.dpr",
		"this.offScreenCanvas.height=e"
	)
	invalid_loader = invalid_loader.replace(
		'this.onScreenCanvas.style.height=`${e}px`',
		'this.onScreenCanvas.style.height=""'
	)
	assert_true(_write_text("godot-loader.js", invalid_loader))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "root_loader_render_dpr_cap_missing"))
	assert_true(_has_issue(
		report,
		"root_loader_render_backing_store_contract_missing"
	))
	assert_true(_has_issue(report, "root_loader_render_css_size_contract_missing"))


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


func test_runtime_render_resolution_cap_and_css_size_contract_are_enforced() -> void:
	var invalid_runtime: String = _valid_wxmemfs_runtime_text()
	invalid_runtime = invalid_runtime.replace("1280/o", "2560/o")
	invalid_runtime = invalid_runtime.replace(
		"r.windowHeight&&(i=r.windowHeight)",
		"r.windowHeight"
	)
	invalid_runtime = invalid_runtime.replace(
		"canvas.style.height=csh",
		"canvas.style.height=''"
	)
	assert_true(_write_text("engine/godot.js", invalid_runtime))
	var verifier: ArtifactVerifier = ArtifactVerifier.new()
	var report: Dictionary = verifier.verify_artifact(_FIXTURE_ROOT)
	assert_true(_has_issue(report, "runtime_render_dpr_cap_missing"))
	assert_true(_has_issue(report, "runtime_render_window_metrics_missing"))
	assert_true(_has_issue(report, "runtime_render_css_size_contract_missing"))


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
		"render_resolution": {
			"policy_id": "wechat-bounded-backing-store-dpr-v1",
			"long_edge_target_pixels": 1280,
			"short_edge_target_pixels": 720,
			"minimum_dpr": 1,
			"device_dpr_ceiling": true,
			"css_size_preserved": true,
			"input_mapping_preserved": true,
			"resize_recomputed": true,
			"loader_patch": "2048-wechat-loader-dpr-cap-v1",
			"runtime_patch": "2048-wechat-runtime-dpr-cap-v1",
			"loader_sha256": FileAccess.get_sha256(
				ProjectSettings.globalize_path(_FIXTURE_ROOT + "/godot-loader.js")
			).to_lower(),
			"runtime_sha256": FileAccess.get_sha256(
				ProjectSettings.globalize_path(_FIXTURE_ROOT + "/engine/godot.js")
			).to_lower(),
		},
		"startup": {
			"schema_version": 1,
			"strategy": "parallel_subpackages_four_way_barrier",
			"coordinator_path": "wechat-startup-coordinator.js",
			"coordinator_sha256": FileAccess.get_sha256(
				ProjectSettings.globalize_path(
					_FIXTURE_ROOT + "/wechat-startup-coordinator.js"
				)
			).to_lower(),
			"trace_schema_version": 1,
			"trace_limit": 64,
			"package_timeout_ms": 300_000,
			"probe_timeout_ms": 10_000,
			"starter_timeout_ms": 10_000,
			"engine_start_timeout_ms": 300_000,
			"download_progress_weight": 0.95,
			"progress_trace_step_percentage": 5,
			"ui_progress_minimum_step": 0.005,
			"engine_package_bytes": GFVariantData.get_option_int(
				package,
				"engine_package_bytes"
			),
			"game_data_package_bytes": GFVariantData.get_option_int(
				package,
				"game_data_package_bytes"
			),
			"barrier": [
				"engine_entry",
				"engine_starter",
				"game_data_entry",
				"game_data_pck_probe",
			],
			"first_fatal_wins": true,
			"late_callbacks_inert": true,
			"engine_start_once": true,
		},
		"large_file_reader": {
			"strategy": "async_position_length_chunked_bounded_concurrency",
			"chunk_bytes": 4_194_304,
			"max_concurrent_resources": 2,
			"inflight_deduplication": "resource_path",
			"helper_path": "engine/wechat-chunked-file-loader.js",
			"helper_sha256": FileAccess.get_sha256(
				ProjectSettings.globalize_path(
					_FIXTURE_ROOT + "/engine/wechat-chunked-file-loader.js"
				)
			).to_lower(),
			"resources": [
				{
					"path": "/engine/godot.wasm.br",
					"bytes": 7,
					"sha256": FileAccess.get_sha256(
						ProjectSettings.globalize_path(
							_FIXTURE_ROOT + "/engine/godot.wasm.br"
						)
					).to_lower(),
				},
				{
					"path": "/game_data/2048-all-in-one.bin",
					"bytes": 7,
					"sha256": FileAccess.get_sha256(
						ProjectSettings.globalize_path(
							_FIXTURE_ROOT + "/game_data/2048-all-in-one.bin"
						)
					).to_lower(),
				},
			],
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
	if not _write_bytes(
		"wechat-startup-coordinator.js",
		FileAccess.get_file_as_bytes(_STARTUP_COORDINATOR_SOURCE_PATH)
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
	var measured: Dictionary = ArtifactVerifier.new().verify_artifact(_FIXTURE_ROOT)
	var measured_package: Dictionary = GFVariantData.get_option_dictionary(
		measured,
		"package"
	)
	if not _write_text(
		"game.js",
		_valid_root_game_text(
			GFVariantData.get_option_int(measured_package, "engine_package_bytes"),
			GFVariantData.get_option_int(measured_package, "game_data_package_bytes")
		)
	):
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
		"const exe = '/engine/godot';\n" +
		"const pack = '/game_data/2048-all-in-one.bin';\n" +
		"const chunkedResourceBytes = Object.freeze(" +
		JSON.stringify({
			"/engine/godot.wasm.br": wasm_bytes,
			"/game_data/2048-all-in-one.bin": pack_bytes,
		}) +
		");\n" +
		"GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(" +
		"GameGlobal.fsUtils, wx.getFileSystemManager(), chunkedResourceBytes, " +
		"{chunkBytes: 4194304, maxConcurrentResources: 2});\n" +
		"if (!GameGlobal.__godotEngineStarter) {\n" +
		"  GameGlobal.__godotEngineStarter = () => {\n" +
		"    if (!GameGlobal.__godotEngineStartPromise) {\n" +
		"      GameGlobal.__godotEngineStartPromise = Promise.resolve()\n" +
		"        .then(() => GODOTSDK.startGame(exe, pack));\n" +
		"    }\n" +
		"    return GameGlobal.__godotEngineStartPromise;\n" +
		"  };\n" +
		"}\n" +
		"GameGlobal.WeChatSubpackageStartupCoordinator.registerEngineStarter(" +
		"GameGlobal.__godotEngineStarter);\n"
	)


func _valid_root_game_text(engine_bytes: int, game_data_bytes: int) -> String:
	return (
		"import './wechat-startup-coordinator'\n" +
		"import './godot-loader'\n" +
		"GameGlobal.__godotStartupPackageBytes = Object.freeze({engine:" +
		str(engine_bytes) + ",game_data:" + str(game_data_bytes) + "});\n" +
		"GameGlobal.godotLoader = new GodotLoader(canvas, config);\n"
	)


func _valid_root_loader_text() -> String:
	return (
		"resizeCanvases(){/*2048-wechat-loader-dpr-cap-v1*/" +
		"const t=window.innerWidth,e=window.innerHeight," +
		"i=Number(window.devicePixelRatio)," +
		"r=Number.isFinite(i)&&i>0?Math.max(1,i):1," +
		"s=Math.max(t,e),o=Math.min(t,e);" +
		"this.dpr=Math.max(1,Math.min(r,s>0?1280/s:r,o>0?720/o:r))," +
		"this.onScreenCanvas.width=t*this.dpr," +
		"this.onScreenCanvas.height=e*this.dpr," +
		'this.onScreenCanvas.style.width=`${t}px`,' +
		'this.onScreenCanvas.style.height=`${e}px`,' +
		"this.offScreenCanvas.width=t*this.dpr," +
		"this.offScreenCanvas.height=e*this.dpr," +
		"this.gl.viewport(0,0,this.onScreenCanvas.width," +
		"this.onScreenCanvas.height),this.render()}\n" +
		"loadGameEngine(){const coordinator=" +
		"GameGlobal.WeChatSubpackageStartupCoordinator;" +
		"const startup=coordinator.start({loader:this," +
		"packageBytes:GameGlobal.__godotStartupPackageBytes," +
		"pckPath:\"/game_data/2048-all-in-one.bin\"," +
		"packageTimeoutMilliseconds:300000," +
		"probeTimeoutMilliseconds:10000," +
		"starterTimeoutMilliseconds:10000," +
		"engineStartTimeoutMilliseconds:300000});" +
		"startup.catch(()=>{});}\n"
	)


func _valid_wxmemfs_runtime_text() -> String:
	return (
		"rename:function(old_node,new_dir,new_name){" +
		'wx["getFileSystemManager"]()["renameSync"](oldWxPath,newWxPath);' +
		'try{}catch(e){throw new FS["ErrnoError"](29)}' +
		'delete old_node["parent"]["contents"][old_node["name"]];' +
		"/*2048-wechat-wxmemfs-rename-v1*/" +
		"},unlink:function(){};" +
		"var GodotDisplayScreen={hidpi:true," +
		"getPixelRatio:function(){/*2048-wechat-runtime-dpr-cap-v1*/" +
		"if(!GodotDisplayScreen.hidpi){return 1}" +
		"let t=window.devicePixelRatio||1,e=window.innerWidth," +
		"i=window.innerHeight;if(typeof wx!==\"undefined\"&&wx.getWindowInfo){" +
		"const r=wx.getWindowInfo();" +
		"r&&(r.pixelRatio&&(t=r.pixelRatio)," +
		"r.windowWidth&&(e=r.windowWidth)," +
		"r.windowHeight&&(i=r.windowHeight))}" +
		"const r=Number(t),s=Number.isFinite(r)&&r>0?Math.max(1,r):1," +
		"o=Math.max(e,i),h=Math.min(e,i);" +
		"return Math.max(1,Math.min(s,o>0?1280/o:s,h>0?720/h:s))}," +
		"updateSize:function(){const width=1,height=1,scale=1;" +
		"const csw=`${width/scale}px`;const csh=`${height/scale}px`;" +
		"if(canvas.style.width!==csw||canvas.style.height!==csh||" +
		"canvas.width!==width||canvas.height!==height){canvas.width=width;" +
		"canvas.height=height;canvas.style.width=csw;canvas.style.height=csh}}}"
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
	var startup: Dictionary = GFVariantData.get_option_dictionary(
		export_report,
		"startup"
	)
	if not startup.is_empty():
		startup["coordinator_sha256"] = FileAccess.get_sha256(
			ProjectSettings.globalize_path(
				_FIXTURE_ROOT + "/wechat-startup-coordinator.js"
			)
		).to_lower()
		startup["engine_package_bytes"] = GFVariantData.get_option_int(
			package,
			"engine_package_bytes"
		)
		startup["game_data_package_bytes"] = GFVariantData.get_option_int(
			package,
			"game_data_package_bytes"
		)
		export_report["startup"] = startup


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


func _release_resource_closure_fixture(tool_identity: Dictionary) -> Dictionary:
	var closure_tool: Dictionary = GFVariantData.get_option_dictionary(
		tool_identity,
		"release_resource_closure"
	)
	var closure_policy: Dictionary = GFVariantData.get_option_dictionary(
		tool_identity,
		"release_resource_policy"
	)
	return {
		"schema_version": 1,
		"ok": true,
		"policy_id": "wechat-minigame-release-resource-closure-v1",
		"policy_path": "tools/wechat_minigame/release_resource_policy.json",
		"policy_sha256": str(closure_policy.get("sha256", "")),
		"tool_path": "tools/wechat_minigame_release_resource_closure.gd",
		"tool_sha256": str(closure_tool.get("sha256", "")),
		"closure_sha256": "7".repeat(64),
		"full_dependency_scan_count": 601,
		"dependency_partial": false,
		"dependency_truncated": false,
		"counts": {
			"roots": 104,
			"structure_dynamic": 44,
			"content_resources": 37,
			"raw_dependency_closure": 794,
			"closure": 793,
			"raw_include_patterns": 17,
			"raw_include_files": 18,
			"issues": 0,
		},
		"issues": [],
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
