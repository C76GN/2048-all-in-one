## 微信小游戏冒烟与完整游戏候选产物的只读结构、预算、身份与字体边界验证器。
extends RefCounted


# --- 常量 ---

const MAIN_PACKAGE_HARD_LIMIT_BYTES: int = 4_000_000
const ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES: int = 20_000_000
const GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES: int = 20_000_000
const TOTAL_PACKAGE_HARD_LIMIT_BYTES: int = 20_000_000
const MAIN_PACKAGE_SOFT_LIMIT_BYTES: int = 3_600_000
const ENGINE_SUBPACKAGE_SOFT_LIMIT_BYTES: int = 18_000_000
const GAME_DATA_SUBPACKAGE_SOFT_LIMIT_BYTES: int = 18_000_000
const TOTAL_PACKAGE_SOFT_LIMIT_BYTES: int = 18_000_000
const EXPORT_REPORT_SCHEMA_VERSION: int = 5
const ARTIFACT_MANIFEST_SCHEMA_VERSION: int = 1
const BUILD_IDENTITY_SCHEMA_VERSION: int = 4
const INPUT_SNAPSHOT_SCHEMA_VERSION: int = 1
const REQUIRED_GODOT_VERSION_PREFIX: String = "4.7.2.stable"
const PACK_RELATIVE_PATH: String = "game_data/2048-all-in-one.bin"
const PROFILE_SCOPE_SMOKE: String = "toolchain_smoke"
const PROFILE_SCOPE_RELEASE: String = "full_game_release_candidate"
const PROJECT_NAME: String = "2048 Chunked Toolchain Smoke"
const RELEASE_PROJECT_NAME: String = "2048 Full Game Release Candidate"
const _EXPORT_PRESET: String = "Web Compatibility Smoke"
const _RELEASE_EXPORT_PRESET: String = "Web Compatibility WeChat Release"
const _TEMPLATE_RELEASE: String = "4.7"
const _TEMPLATE_ASSET: String = "minigame4.7.tpz"
const _TEMPLATE_EXPECTED_BYTES: int = 11_763_895
const _TEMPLATE_SHA256: String = (
	"ae5bdeb5ba1ce9712d4efc35d337cb5ecbef3ad5bfb0f7d06ae9cb662c1f2d71"
)
const _TOOL_IDENTITY_NAMES: PackedStringArray = [
	"export_tool",
	"artifact_verifier",
	"artifact_check",
	"bounded_json_reader",
	"path_tools",
	"chunk_loader",
	"startup_coordinator",
	"wxmemfs_patch",
	"release_resource_closure",
	"release_resource_policy",
]
const _TOOL_IDENTITY_PATHS: Dictionary = {
	"export_tool": "tools/export_wechat_minigame_smoke.ps1",
	"artifact_verifier": "tools/wechat_minigame_artifact_verifier.gd",
	"artifact_check": "tools/wechat_minigame_artifact_check.gd",
	"bounded_json_reader": "addons/gf/kernel/core/gf_bounded_json_object_reader.gd",
	"path_tools": "addons/gf/kernel/core/gf_path_tools.gd",
	"chunk_loader": "tools/wechat_minigame/chunked_file_loader.js",
	"startup_coordinator": "tools/wechat_minigame/subpackage_startup_coordinator.js",
	"wxmemfs_patch": "tools/wechat_minigame/wxmemfs_rename_patch.ps1",
	"release_resource_closure": "tools/wechat_minigame_release_resource_closure.gd",
	"release_resource_policy": "tools/wechat_minigame/release_resource_policy.json",
}
const _RELEASE_RESOURCE_CLOSURE_SCHEMA_VERSION: int = 1
const _RELEASE_RESOURCE_CLOSURE_POLICY_ID: String = (
	"wechat-minigame-release-resource-closure-v1"
)
const _RELEASE_RESOURCE_CLOSURE_COUNT_FIELDS: PackedStringArray = [
	"roots",
	"structure_dynamic",
	"content_resources",
	"raw_dependency_closure",
	"closure",
	"raw_include_patterns",
	"raw_include_files",
	"issues",
]
const _INPUT_INCLUDE_EXACT: PackedStringArray = [
	"default_bus_layout.tres",
	"export_presets.cfg",
	"icon.svg",
	"icon.svg.import",
	"project.godot",
]
const _INPUT_INCLUDE_ROOTS: PackedStringArray = [
	"addons",
	"app",
	"features",
	"shared",
]
const _INPUT_EXCLUDE_EXACT: PackedStringArray = [
	"features/asset_library/resources/import_sources.json",
	"features/asset_library/resources/import_sources.local.json",
	"shared/assets/fonts/noto_sans_sc_variable.ttf",
]
const _INPUT_EXCLUDE_PREFIXES: PackedStringArray = [
	"addons/gf/tools/",
	"addons/gut/",
	"features/asset_library/resources/review/",
	"features/asset_library/resources/source_packs/",
	"features/asset_library/tools/",
	"features/platform_runtime/tools/",
	"features/themes/tools/",
]
const _INPUT_EXCLUDE_GENERATED: PackedStringArray = [
	".git/",
	".godot/",
	"build/",
	"tests/",
	"tools/",
	"__pycache__/",
]
const _INPUT_EXCLUDE_CACHE_SUFFIXES: PackedStringArray = [".pyc", ".pyo"]
const _PACK_LOADER_REFERENCE: String = "/game_data/2048-all-in-one.bin"
const _CHUNK_LOADER_RELATIVE_PATH: String = "engine/wechat-chunked-file-loader.js"
const _CHUNK_LOADER_SHA256: String = (
	"2caab9872b5886cd823fcb9e9a037163d9c93bd77070ef12e56d6dccf51a0600"
)
const _CHUNK_LOADER_IMPORT: String = "import './wechat-chunked-file-loader'"
const _CHUNK_LOADER_INSTALL: String = "installChunkedLocalFetch"
const _CHUNK_MANIFEST_PREFIX: String = (
	"const chunkedResourceBytes = Object.freeze("
)
const _CHUNK_BYTES_TOKEN: String = "chunkBytes: 4194304"
const _CHUNK_MAX_CONCURRENT_RESOURCES_TOKEN: String = "maxConcurrentResources: 2"
const _WXMEMFS_RENAME_PATCH_MARKER: String = "/*2048-wechat-wxmemfs-rename-v1*/"
const _WXMEMFS_RENAME_FUNCTION_TOKEN: String = (
	"rename:function(old_node,new_dir,new_name)"
)
const _WXMEMFS_PHYSICAL_RENAME_TOKEN: String = '["renameSync"](oldWxPath,newWxPath)'
const _WXMEMFS_MEMORY_MUTATION_TOKEN: String = (
	'delete old_node["parent"]["contents"][old_node["name"]]'
)
const _WXMEMFS_RENAME_FAILURE_TOKEN: String = 'throw new FS["ErrnoError"](29)'
const _RUNTIME_RENDER_PATCH_MARKER: String = (
	"/*2048-wechat-runtime-dpr-cap-v1*/"
)
const _RUNTIME_RENDER_METRICS_TOKEN: String = (
	"let t=window.devicePixelRatio||1,e=window.innerWidth,i=window.innerHeight"
)
const _RUNTIME_RENDER_WINDOW_INFO_TOKEN: String = (
	"r.pixelRatio&&(t=r.pixelRatio),r.windowWidth&&(e=r.windowWidth)," +
	"r.windowHeight&&(i=r.windowHeight)"
)
const _RUNTIME_RENDER_DPR_CAP_TOKEN: String = (
	"return Math.max(1,Math.min(s,o>0?1280/o:s,h>0?720/h:s))"
)
const _RUNTIME_RENDER_CSS_SIZE_TOKEN: String = (
	"const csw=`${width/scale}px`;const csh=`${height/scale}px`;" +
	"if(canvas.style.width!==csw||canvas.style.height!==csh||" +
	"canvas.width!==width||canvas.height!==height){canvas.width=width;" +
	"canvas.height=height;canvas.style.width=csw;canvas.style.height=csh"
)
const _CHUNK_RESOURCE_PATHS: PackedStringArray = [
	"/engine/godot.wasm.br",
	_PACK_LOADER_REFERENCE,
]
const _GAME_DATA_ENTRY_MARKER: String = (
	"GameGlobal.__godotGameDataSubpackageEntryStarted = true;"
)
const _ENGINE_ENTRY_MARKER: String = (
	"GameGlobal.__godotEngineSubpackageEntryStarted = true;"
)
const _STARTUP_COORDINATOR_RELATIVE_PATH: String = "wechat-startup-coordinator.js"
const _STARTUP_COORDINATOR_SHA256: String = (
	"037d3f040e5ef4ecf89910b7435fddba62877123184dd21da246ce9b54969418"
)
const _STARTUP_COORDINATOR_IMPORT: String = "import './wechat-startup-coordinator'"
const _STARTUP_COORDINATOR_CALL: String = "const startup=coordinator.start({"
const _STARTUP_PACKAGE_BYTES_REFERENCE: String = (
	"packageBytes:GameGlobal.__godotStartupPackageBytes"
)
const _STARTUP_RUNTIME_OPTION_TOKENS: PackedStringArray = [
	"packageTimeoutMilliseconds:300000",
	"probeTimeoutMilliseconds:10000",
	"starterTimeoutMilliseconds:10000",
	"engineStartTimeoutMilliseconds:300000",
]
const _STARTUP_PACKAGE_BYTES_PREFIX: String = (
	"GameGlobal.__godotStartupPackageBytes = Object.freeze({engine:"
)
const _ENGINE_STARTER_REGISTRATION: String = "registerEngineStarter("
const _ENGINE_STARTER_CACHE_TOKEN: String = (
	"if (!GameGlobal.__godotEngineStartPromise) {"
)
const _ENGINE_START_DEFERRED_TOKEN: String = (
	".then(() => GODOTSDK.startGame(exe, pack))"
)
const _SERIAL_LOADER_TOKENS: PackedStringArray = [
	"const loadPackage=",
	"probeGameData(",
]
const _LOADER_RENDER_PATCH_MARKER: String = (
	"/*2048-wechat-loader-dpr-cap-v1*/"
)
const _RENDER_DPR_SOURCE_TOKEN: String = (
	"i=Number(window.devicePixelRatio)," +
	"r=Number.isFinite(i)&&i>0?Math.max(1,i):1," +
	"s=Math.max(t,e),o=Math.min(t,e)"
)
const _RENDER_DPR_CAP_TOKEN: String = (
	"this.dpr=Math.max(1,Math.min(r,s>0?1280/s:r,o>0?720/o:r))"
)
const _RENDER_BACKING_STORE_TOKENS: PackedStringArray = [
	"this.onScreenCanvas.width=t*this.dpr",
	"this.onScreenCanvas.height=e*this.dpr",
	"this.offScreenCanvas.width=t*this.dpr",
	"this.offScreenCanvas.height=e*this.dpr",
]
const _RENDER_CSS_SIZE_TOKENS: PackedStringArray = [
	'this.onScreenCanvas.style.width=`${t}px`',
	'this.onScreenCanvas.style.height=`${e}px`',
]
const _REQUIRED_PACK_INCLUDE_FILES: PackedStringArray = [
	"engine/godot.wasm.br",
	PACK_RELATIVE_PATH,
]
const _FULL_FONT_TOKEN: String = "noto_sans_sc_variable"
const _SMOKE_FONT_TOKEN: String = "wechat_smoke_sans_subset"
const _EXPORT_PLUGIN_CODE_TOKEN: String = "WeChatMiniGameProfileFontExportPlugin"
const _TEXT_SERVER_DATA_TOKEN: String = "icudt_godot.dat"
const _RELEASE_TRANSLATION_PATHS: PackedStringArray = [
	"res://shared/assets/translations.en.translation",
	"res://shared/assets/translations.zh.translation",
]
const _RELEASE_TRANSLATION_LOCALES: PackedStringArray = ["en", "zh"]
const _SMOKE_FONT_SHA256: String = (
	"38bdd2457e67c2c1721f5734fee67059bc1b961563afb4f3e0f8b8c8b8049c22"
)
const _SMOKE_FONT_PATH: String = "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf"
const _RELEASE_FONT_TOKEN: String = "wechat_release_sans_subset"
const _RELEASE_FONT_SHA256: String = (
	"b9bd519d1a5cee5647c976b21153726035adc848a563f0e8af2d612e56fd265f"
)
const _RELEASE_FONT_PATH: String = (
	"res://shared/assets/fonts/wechat_release_sans_subset.ttf"
)
const _RELEASE_COVERAGE_PATH: String = (
	"res://shared/assets/fonts/wechat_release_font_coverage.txt"
)
const _RELEASE_COVERAGE_MANIFEST_PATH: String = (
	"res://shared/assets/fonts/wechat_release_font_coverage.json"
)
const _RELEASE_COVERAGE_SHA256: String = (
	"aa0d06deafac5ccf7cccca1565d143b1b1478b1377170254161c44cab07ad157"
)
const _RELEASE_FONT_BYTES: int = 445_076
const _RELEASE_CODEPOINT_COUNT: int = 810
const _RELEASE_SOURCE_FONT_SHA256: String = (
	"763146584cf0710223441356b4395e279021b0806c196614377a7a0174ae074a"
)
const _RELEASE_SOURCE_FONT_PATH: String = (
	"shared/assets/fonts/noto_sans_sc_variable.ttf"
)
const _RELEASE_LICENSE_PATH: String = "shared/assets/fonts/noto_sans_sc_ofl.txt"
const _RELEASE_LICENSE_SHA256: String = (
	"6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
)
const _FONT_VARIATION_PATHS: PackedStringArray = [
	"res://shared/assets/fonts/ui_sans_regular.tres",
	"res://shared/assets/fonts/ui_sans_display.tres",
]
const _REQUIRED_PATHS: PackedStringArray = [
	PACK_RELATIVE_PATH,
	"game_data/game.js",
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
	_STARTUP_COORDINATOR_RELATIVE_PATH,
	"weapp-adapter.js",
]
const _VOLATILE_LOCAL_SIDECAR_PATH: String = "project.private.config.json"
const _OPTIONAL_PATHS: PackedStringArray = [
	_VOLATILE_LOCAL_SIDECAR_PATH,
]
const _FORBIDDEN_SAMPLE_APP_IDS: PackedStringArray = [
	"wxda5f10e2e9114855",
	"wxf40904ea6120ad08",
]
const _REQUIRED_FONT_TEXT: String = "准备启动跨平台兼容性冒烟微信真机必须加入合法域名"
const _CONFIG_JSON_MAX_BYTES: int = 64 * 1024
const _CONFIG_JSON_MAX_DEPTH: int = 16
const _REPORT_JSON_MAX_BYTES: int = 256 * 1024
const _REPORT_JSON_MAX_DEPTH: int = 24
const _FONT_MANIFEST_JSON_MAX_BYTES: int = 64 * 1024
const _FONT_MANIFEST_JSON_MAX_DEPTH: int = 16


# --- 公共方法 ---

## 验证一个已组装的微信小游戏冒烟或完整游戏候选工程。
## @param artifact_root: 微信开发者工具工程的绝对或 res:// 根目录。
## @param inspect_pack: 是否同时扫描并加载项目 .bin 资源包。
## @return: 含 ok、issues、files 与 package 字段的只读报告。
func verify_artifact(artifact_root: String, inspect_pack: bool = false) -> Dictionary:
	return _verify(artifact_root, "", inspect_pack)


## 验证产物及其同目录 export-report.json 的完整内容绑定。
## 默认 verify_artifact() 保持纯结构模式，便于在没有报告的夹具上复用。
func verify_report_bound(
	artifact_root: String,
	report_path: String,
	inspect_pack: bool = false
) -> Dictionary:
	return _verify(artifact_root, report_path, inspect_pack)


## 纯计算包体预算，供边界测试与目录测量共享同一判定。
static func evaluate_package_budget(
	main_bytes: int,
	engine_bytes: int,
	game_data_bytes: int
) -> Dictionary:
	var total_bytes: int = main_bytes + engine_bytes + game_data_bytes
	return {
		"main_package_bytes": main_bytes,
		"engine_package_bytes": engine_bytes,
		"game_data_package_bytes": game_data_bytes,
		"total_package_bytes": total_bytes,
		"main_hard_limit_ok": main_bytes <= MAIN_PACKAGE_HARD_LIMIT_BYTES,
		"engine_hard_limit_ok": engine_bytes <= ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES,
		"game_data_hard_limit_ok": (
			game_data_bytes <= GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES
		),
		"total_hard_limit_ok": total_bytes <= TOTAL_PACKAGE_HARD_LIMIT_BYTES,
		"main_soft_budget_ok": main_bytes <= MAIN_PACKAGE_SOFT_LIMIT_BYTES,
		"engine_soft_budget_ok": engine_bytes <= ENGINE_SUBPACKAGE_SOFT_LIMIT_BYTES,
		"game_data_soft_budget_ok": (
			game_data_bytes <= GAME_DATA_SUBPACKAGE_SOFT_LIMIT_BYTES
		),
		"total_soft_budget_ok": total_bytes <= TOTAL_PACKAGE_SOFT_LIMIT_BYTES,
	}


## 构造与 PowerShell 导出器相同 canonical framing 的可发布文件清单。
## DevTools 本机 sidecar 仍单独验证，但不参与 manifest 或 build identity。
func build_artifact_manifest(artifact_root: String) -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()
	var normalized_root: String = _normalize_root(artifact_root)
	var discovered_files: PackedStringArray = PackedStringArray()
	if normalized_root.is_empty() or not DirAccess.dir_exists_absolute(normalized_root):
		return _empty_artifact_manifest()
	_collect_files(normalized_root, "", discovered_files, issues)
	discovered_files.sort()
	var files: PackedStringArray = _artifact_files_from(discovered_files)
	return _build_artifact_manifest(normalized_root, files, issues)


## 构造报告 build_id；调用者仍须通过 verify_report_bound() 验证字段形状。
func compute_report_build_id(export_report: Dictionary) -> String:
	var godot: Dictionary = _dictionary_value(export_report.get("godot", {}))
	var gf: Dictionary = _dictionary_value(export_report.get("gf", {}))
	var template: Dictionary = _dictionary_value(export_report.get("template", {}))
	var tool_identity: Dictionary = _dictionary_value(
		export_report.get("tool_identity", {})
	)
	var font_policy: Dictionary = _dictionary_value(
		export_report.get("font_policy", {})
	)
	var resource_closure: Dictionary = _dictionary_value(
		export_report.get("resource_closure", {})
	)
	var resource_closure_counts: Dictionary = _dictionary_value(
		resource_closure.get("counts", {})
	)
	var records: PackedStringArray = PackedStringArray([
		"wechat-candidate-build-v%d" % BUILD_IDENTITY_SCHEMA_VERSION,
		"scope=%s" % str(export_report.get("scope", "")),
		"export_preset=%s" % str(export_report.get("export_preset", "")),
		"release_font_manifest_sha256=%s" % str(
			font_policy.get("coverage_manifest_sha256", "")
		),
		"release_font_subset_sha256=%s" % str(
			font_policy.get("subset_font_sha256", "")
		),
		"release_resource_closure_schema_version=%d" % _integer_value(
			resource_closure.get("schema_version"), 0
		),
		"release_resource_closure_policy_id=%s" % str(
			resource_closure.get("policy_id", "")
		),
		"release_resource_closure_policy_path=%s" % str(
			resource_closure.get("policy_path", "")
		),
		"release_resource_closure_policy_sha256=%s" % str(
			resource_closure.get("policy_sha256", "")
		),
		"release_resource_closure_tool_path=%s" % str(
			resource_closure.get("tool_path", "")
		),
		"release_resource_closure_tool_sha256=%s" % str(
			resource_closure.get("tool_sha256", "")
		),
		"release_resource_closure_digest_sha256=%s" % str(
			resource_closure.get("closure_sha256", "")
		),
		"release_resource_closure_full_dependency_scan_count=%d" % _integer_value(
			resource_closure.get("full_dependency_scan_count"), 0
		),
		"release_resource_closure_roots=%d" % _integer_value(
			resource_closure_counts.get("roots"), 0
		),
		"release_resource_closure_structure_dynamic=%d" % _integer_value(
			resource_closure_counts.get("structure_dynamic"), 0
		),
		"release_resource_closure_content_resources=%d" % _integer_value(
			resource_closure_counts.get("content_resources"), 0
		),
		"release_resource_closure_raw_dependency_closure=%d" % _integer_value(
			resource_closure_counts.get("raw_dependency_closure"), 0
		),
		"release_resource_closure_closure=%d" % _integer_value(
			resource_closure_counts.get("closure"), 0
		),
		"release_resource_closure_raw_include_patterns=%d" % _integer_value(
			resource_closure_counts.get("raw_include_patterns"), 0
		),
		"release_resource_closure_raw_include_files=%d" % _integer_value(
			resource_closure_counts.get("raw_include_files"), 0
		),
		"release_resource_closure_issues=%d" % _integer_value(
			resource_closure_counts.get("issues"), 0
		),
		"godot=%s" % str(godot.get("version", "")),
		"gf_framework_version=%s" % str(gf.get("framework_version", "")),
		"gf_source_commit=%s" % str(gf.get("source_commit", "")),
		"gf_source_git_tree=%s" % str(gf.get("source_git_tree", "")),
		"gf_vendor_tree_sha256=%s" % str(gf.get("vendor_tree_sha256", "")),
		"gf_vendor_file_count=%d" % _integer_value(gf.get("vendor_file_count")),
		"gf_lock_sha256=%s" % str(gf.get("lock_sha256", "")),
		"input_snapshot_sha256=%s" % str(
			export_report.get("input_snapshot_sha256", "")
		),
		"input_snapshot_file_count=%d" % _integer_value(
			_dictionary_value(export_report.get("input_snapshot", {})).get(
				"file_count",
				null
			)
		),
		"artifact_manifest_sha256=%s" % str(
			export_report.get("artifact_manifest_sha256", "")
		),
		"template_sha256=%s" % str(template.get("sha256", "")),
	])
	for tool_name: String in _TOOL_IDENTITY_NAMES:
		var tool: Dictionary = _dictionary_value(tool_identity.get(tool_name, {}))
		var _record_added: bool = records.append(
			"%s_sha256=%s" % [tool_name, str(tool.get("sha256", ""))]
		)
	return ("\n".join(records) + "\n").sha256_text()


## 读取当前验证宿主中固定组装、验证及其有界 JSON 依赖的实际内容身份。
func build_tool_identity() -> Dictionary:
	var identity: Dictionary = {}
	for tool_name: String in _TOOL_IDENTITY_NAMES:
		var relative_path: String = str(_TOOL_IDENTITY_PATHS.get(tool_name, ""))
		var full_path: String = ProjectSettings.globalize_path("res://" + relative_path)
		identity[tool_name] = {
			"path": relative_path,
			"sha256": (
				FileAccess.get_sha256(full_path).to_lower()
				if FileAccess.file_exists(full_path)
				else ""
			),
		}
	return identity


# --- 私有/辅助方法 ---

func _verify(
	artifact_root: String,
	report_path: String,
	inspect_pack: bool
) -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()
	var profile: Dictionary = _profile_from_report_path(report_path)
	var normalized_root: String = _normalize_root(artifact_root)
	var discovered_files: PackedStringArray = PackedStringArray()
	if normalized_root.is_empty() or not DirAccess.dir_exists_absolute(normalized_root):
		_add_issue(issues, "artifact_root_missing:%s" % artifact_root)
		return _make_report(false, discovered_files, {}, issues)

	_collect_files(normalized_root, "", discovered_files, issues)
	discovered_files.sort()
	_validate_file_set(discovered_files, issues)
	var files: PackedStringArray = _artifact_files_from(discovered_files)
	var package: Dictionary = _measure_package(normalized_root, files, issues)
	_validate_loader(normalized_root, issues)
	_validate_subpackage_entries(normalized_root, package, issues)
	_validate_project_config(normalized_root, profile, issues)
	_validate_game_config(normalized_root, issues)
	_validate_private_config(normalized_root, issues)
	if inspect_pack:
		_inspect_pack(normalized_root, profile, issues)
	if not report_path.is_empty():
		_validate_report_binding(
			normalized_root,
			_normalize_root(report_path),
			files,
			package,
			issues
		)
	return _make_report(issues.is_empty(), files, package, issues)


func _normalize_root(path: String) -> String:
	var normalized: String = path.strip_edges()
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		normalized = ProjectSettings.globalize_path(normalized)
	return normalized.replace("\\", "/").trim_suffix("/")


func _profile_from_report_path(report_path: String) -> Dictionary:
	if report_path.is_empty():
		return _profile_for_scope(PROFILE_SCOPE_SMOKE)
	var normalized_report_path: String = _normalize_root(report_path)
	var read_report: Dictionary = GFBoundedJsonObjectReader.read_object(
		normalized_report_path,
		_REPORT_JSON_MAX_BYTES,
		_REPORT_JSON_MAX_DEPTH
	)
	if not _boolean_value(read_report.get("ok")):
		return _profile_for_scope(PROFILE_SCOPE_SMOKE)
	var report: Dictionary = _dictionary_value(read_report.get("data"))
	var profile: Dictionary = _profile_for_scope(str(report.get("scope", "")))
	if str(profile.get("scope", "")) == PROFILE_SCOPE_RELEASE:
		var font_policy: Dictionary = _dictionary_value(report.get("font_policy", {}))
		profile["coverage_manifest_sha256"] = str(
			font_policy.get("coverage_manifest_sha256", "")
		)
	return profile


func _profile_for_scope(scope: String) -> Dictionary:
	if scope == PROFILE_SCOPE_RELEASE:
		return {
			"scope": PROFILE_SCOPE_RELEASE,
			"project_name": RELEASE_PROJECT_NAME,
			"export_preset": _RELEASE_EXPORT_PRESET,
			"font_path": _RELEASE_FONT_PATH,
			"font_token": _RELEASE_FONT_TOKEN,
			"font_sha256": _RELEASE_FONT_SHA256,
		}
	return {
		"scope": PROFILE_SCOPE_SMOKE,
		"project_name": PROJECT_NAME,
		"export_preset": _EXPORT_PRESET,
		"font_path": _SMOKE_FONT_PATH,
		"font_token": _SMOKE_FONT_TOKEN,
		"font_sha256": _SMOKE_FONT_SHA256,
	}


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


func _artifact_files_from(discovered_files: PackedStringArray) -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for path: String in discovered_files:
		if path == _VOLATILE_LOCAL_SIDECAR_PATH:
			continue
		var _file_added: bool = files.append(path)
	return files


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
	var game_data_bytes: int = 0
	for relative_path: String in files:
		var file: FileAccess = FileAccess.open(root.path_join(relative_path), FileAccess.READ)
		if file == null:
			_add_issue(issues, "artifact_file_unreadable:%s" % relative_path)
			continue
		var file_bytes: int = file.get_length()
		if relative_path.begins_with("engine/"):
			engine_bytes += file_bytes
		elif relative_path.begins_with("game_data/"):
			game_data_bytes += file_bytes
		else:
			main_bytes += file_bytes
	var package: Dictionary = evaluate_package_budget(
		main_bytes,
		engine_bytes,
		game_data_bytes
	)
	if not _boolean_value(package.get("main_hard_limit_ok")):
		_add_issue(issues, "main_package_hard_limit_exceeded:%d" % main_bytes)
	if not _boolean_value(package.get("engine_hard_limit_ok")):
		_add_issue(issues, "engine_subpackage_hard_limit_exceeded:%d" % engine_bytes)
	if not _boolean_value(package.get("game_data_hard_limit_ok")):
		_add_issue(
			issues,
			"game_data_subpackage_hard_limit_exceeded:%d" % game_data_bytes
		)
	if not _boolean_value(package.get("total_hard_limit_ok")):
		_add_issue(
			issues,
			"total_package_hard_limit_exceeded:%d" % _integer_value(
				package.get("total_package_bytes", 0)
			)
		)
	return package


func _validate_loader(root: String, issues: PackedStringArray) -> void:
	var loader_path: String = root.path_join("engine/game.js")
	var loader_text: String = FileAccess.get_file_as_string(loader_path)
	if not loader_text.contains(_PACK_LOADER_REFERENCE):
		_add_issue(issues, "loader_pack_reference_missing:%s" % _PACK_LOADER_REFERENCE)
	if loader_text.contains("empty-tips.bin") or loader_text.contains("demo-pck.bin"):
		_add_issue(issues, "loader_uses_upstream_sample_pack")
	_validate_chunk_loader(root, loader_text, issues)
	_validate_wxmemfs_runtime(root, issues)


func _validate_subpackage_entries(
	root: String,
	package: Dictionary,
	issues: PackedStringArray
) -> void:
	var data_entry: String = FileAccess.get_file_as_string(
		root.path_join("game_data/game.js")
	)
	if not data_entry.contains(_GAME_DATA_ENTRY_MARKER):
		_add_issue(issues, "game_data_entry_marker_missing")
	var engine_entry: String = FileAccess.get_file_as_string(
		root.path_join("engine/game.js")
	)
	if not engine_entry.contains(_ENGINE_ENTRY_MARKER):
		_add_issue(issues, "engine_entry_marker_missing")
	if (
		not engine_entry.contains(_ENGINE_STARTER_REGISTRATION)
		or not engine_entry.contains(_ENGINE_STARTER_CACHE_TOKEN)
		or not engine_entry.contains(_ENGINE_START_DEFERRED_TOKEN)
		or engine_entry.count("GODOTSDK.startGame(") != 1
	):
		_add_issue(issues, "engine_starter_registration_invalid")
	var root_loader: String = FileAccess.get_file_as_string(
		root.path_join("godot-loader.js")
	)
	_validate_render_resolution_policy(root_loader, issues)
	if (
		not root_loader.contains(_STARTUP_COORDINATOR_CALL)
		or not root_loader.contains(_STARTUP_PACKAGE_BYTES_REFERENCE)
	):
		_add_issue(issues, "root_loader_startup_coordinator_missing")
	for token: String in _STARTUP_RUNTIME_OPTION_TOKENS:
		if not root_loader.contains(token):
			_add_issue(issues, "root_loader_startup_option_missing:%s" % token)
	for token: String in _SERIAL_LOADER_TOKENS:
		if root_loader.contains(token):
			_add_issue(issues, "root_loader_serial_startup_present")
			break
	_validate_startup_coordinator(root, package, issues)


func _validate_startup_coordinator(
	root: String,
	package: Dictionary,
	issues: PackedStringArray
) -> void:
	var coordinator_path: String = root.path_join(_STARTUP_COORDINATOR_RELATIVE_PATH)
	if FileAccess.file_exists(coordinator_path):
		var actual_hash: String = FileAccess.get_sha256(coordinator_path).to_lower()
		if actual_hash != _STARTUP_COORDINATOR_SHA256:
			_add_issue(issues, "startup_coordinator_hash_mismatch:%s" % actual_hash)
	var coordinator_text: String = FileAccess.get_file_as_string(coordinator_path)
	for token: String in PackedStringArray([
		"const PACKAGE_TIMEOUT_MILLISECONDS = 300000;",
		"const PROBE_TIMEOUT_MILLISECONDS = 10000;",
		"const STARTER_TIMEOUT_MILLISECONDS = 10000;",
		"const ENGINE_START_TIMEOUT_MILLISECONDS = 300000;",
		"const DOWNLOAD_PROGRESS_WEIGHT = 0.95;",
		"const PROGRESS_TRACE_STEP_PERCENTAGE = 5;",
		"const UI_PROGRESS_MIN_STEP = 0.005;",
		"const TRACE_LIMIT = 64;",
		"startup.fatal",
		"startup.barrier_ready",
		"engine.start_resolved",
		"engine_start_timeout",
	]):
		if not coordinator_text.contains(token):
			_add_issue(issues, "startup_coordinator_contract_missing:%s" % token)
	var root_game: String = FileAccess.get_file_as_string(root.path_join("game.js"))
	if not root_game.contains(_STARTUP_COORDINATOR_IMPORT):
		_add_issue(issues, "startup_coordinator_import_missing")
	var expected_weights: String = (
		_STARTUP_PACKAGE_BYTES_PREFIX
		+ str(_integer_value(package.get("engine_package_bytes")))
		+ ",game_data:"
		+ str(_integer_value(package.get("game_data_package_bytes")))
		+ "});"
	)
	if not root_game.contains(expected_weights):
		_add_issue(issues, "startup_package_byte_weights_mismatch")


func _validate_render_resolution_policy(
	root_loader: String,
	issues: PackedStringArray
) -> void:
	if (
		not root_loader.contains(_LOADER_RENDER_PATCH_MARKER)
		or not root_loader.contains(_RENDER_DPR_SOURCE_TOKEN)
		or not root_loader.contains(_RENDER_DPR_CAP_TOKEN)
	):
		_add_issue(issues, "root_loader_render_dpr_cap_missing")
	for token: String in _RENDER_BACKING_STORE_TOKENS:
		if not root_loader.contains(token):
			_add_issue(issues, "root_loader_render_backing_store_contract_missing")
			break
	for token: String in _RENDER_CSS_SIZE_TOKENS:
		if not root_loader.contains(token):
			_add_issue(issues, "root_loader_render_css_size_contract_missing")
			break


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
	_validate_runtime_render_resolution_policy(runtime_text, issues)


func _validate_runtime_render_resolution_policy(
	runtime_text: String,
	issues: PackedStringArray
) -> void:
	if (
		not runtime_text.contains(_RUNTIME_RENDER_PATCH_MARKER)
		or not runtime_text.contains(_RUNTIME_RENDER_DPR_CAP_TOKEN)
	):
		_add_issue(issues, "runtime_render_dpr_cap_missing")
	if (
		not runtime_text.contains(_RUNTIME_RENDER_METRICS_TOKEN)
		or not runtime_text.contains(_RUNTIME_RENDER_WINDOW_INFO_TOKEN)
	):
		_add_issue(issues, "runtime_render_window_metrics_missing")
	if not runtime_text.contains(_RUNTIME_RENDER_CSS_SIZE_TOKEN):
		_add_issue(issues, "runtime_render_css_size_contract_missing")


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
	if not loader_text.contains(_CHUNK_MAX_CONCURRENT_RESOURCES_TOKEN):
		_add_issue(issues, "chunk_loader_max_concurrent_resources_not_2")

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


func _validate_project_config(
	root: String,
	profile: Dictionary,
	issues: PackedStringArray
) -> void:
	var config: Dictionary = _read_json_dictionary(
		root.path_join("project.config.json"),
		"project_config",
		issues
	)
	if str(config.get("compileType", "")) != "minigame":
		_add_issue(issues, "project_compile_type_not_minigame")
	if (
		str(config.get("projectname", "")).strip_edges()
		!= str(profile.get("project_name", ""))
	):
		_add_issue(issues, "project_name_not_distinct")
	var app_id: String = str(config.get("appid", "")).strip_edges()
	if not _is_valid_app_id(app_id):
		_add_issue(issues, "project_app_id_invalid:%s" % app_id)
	elif _FORBIDDEN_SAMPLE_APP_IDS.has(app_id):
		_add_issue(issues, "project_app_id_is_upstream_sample:%s" % app_id)
	_validate_pack_include(config, issues)


func _validate_pack_include(config: Dictionary, issues: PackedStringArray) -> void:
	var pack_options_value: Variant = config.get("packOptions", {})
	if not pack_options_value is Dictionary:
		_add_issue(issues, "project_pack_options_not_object")
		return
	var pack_options: Dictionary = pack_options_value
	var include_value: Variant = pack_options.get("include", [])
	if not include_value is Array:
		_add_issue(issues, "project_pack_include_not_array")
		return
	var included_files: PackedStringArray = PackedStringArray()
	for rule_value: Variant in include_value:
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = rule_value
		if str(rule.get("type", "")) == "file":
			included_files.append_array(PackedStringArray([
				str(rule.get("value", "")),
			]))
	for required_path: String in _REQUIRED_PACK_INCLUDE_FILES:
		if not included_files.has(required_path):
			_add_issue(issues, "project_pack_include_missing:%s" % required_path)


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
	if (
		subpackages.size() != 2
		or not subpackages[0] is Dictionary
		or not subpackages[1] is Dictionary
	):
		_add_issue(issues, "game_subpackages_not_exact")
		return
	var expected_subpackages: Array[Dictionary] = [
		{"name": "game_data", "root": "game_data/"},
		{"name": "engine", "root": "engine/"},
	]
	for index: int in range(expected_subpackages.size()):
		var actual: Dictionary = subpackages[index]
		var expected: Dictionary = expected_subpackages[index]
		if (
			str(actual.get("name", "")) != str(expected.get("name", ""))
			or str(actual.get("root", "")) != str(expected.get("root", ""))
		):
			_add_issue(issues, "game_subpackages_not_exact")
			return


func _validate_private_config(root: String, issues: PackedStringArray) -> void:
	var path: String = root.path_join(_VOLATILE_LOCAL_SIDECAR_PATH)
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
	issues: PackedStringArray,
	max_bytes: int = _CONFIG_JSON_MAX_BYTES,
	max_depth: int = _CONFIG_JSON_MAX_DEPTH
) -> Dictionary:
	var read_report: Dictionary = GFBoundedJsonObjectReader.read_object(
		path,
		max_bytes,
		max_depth
	)
	if _boolean_value(read_report.get("ok")):
		return _dictionary_value(read_report.get("data"))
	var error_kind: String = str(read_report.get("error_kind", "invalid"))
	_add_issue(issues, "%s_invalid_json:%s" % [label, error_kind])
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


func _validate_report_binding(
	artifact_root: String,
	report_path: String,
	files: PackedStringArray,
	package: Dictionary,
	issues: PackedStringArray
) -> void:
	if (
		artifact_root.get_file() != "wxgame"
		or report_path.get_file() != "export-report.json"
		or artifact_root.get_base_dir() != report_path.get_base_dir()
	):
		_add_issue(issues, "report_bundle_layout_invalid")
	if not FileAccess.file_exists(report_path):
		_add_issue(issues, "export_report_missing:%s" % report_path)
		return
	var report_read: Dictionary = GFBoundedJsonObjectReader.read_object(
		report_path,
		_REPORT_JSON_MAX_BYTES,
		_REPORT_JSON_MAX_DEPTH
	)
	if not _boolean_value(report_read.get("ok")):
		_add_issue(issues, "export_report_invalid_json:%s" % (
			str(report_read.get("error_kind", "invalid"))
		))
		return
	var export_report: Dictionary = _dictionary_value(report_read.get("data"))
	_validate_report_identity(export_report, issues)
	_validate_report_render_resolution(export_report, artifact_root, issues)
	_validate_report_startup(export_report, artifact_root, package, issues)
	_validate_report_large_file_reader(export_report, artifact_root, issues)
	_validate_report_artifact(export_report, artifact_root, files, issues)
	_validate_report_package(export_report, package, files, issues)
	var declared_build_id: String = str(export_report.get("build_id", ""))
	if not _is_lower_hex(declared_build_id, 64):
		_add_issue(issues, "report_build_id_invalid")
	elif declared_build_id != compute_report_build_id(export_report):
		_add_issue(issues, "report_build_id_mismatch")


func _validate_report_identity(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	if _integer_value(export_report.get("schema_version")) != EXPORT_REPORT_SCHEMA_VERSION:
		_add_issue(issues, "export_report_schema_not_5")
	var ok_value: Variant = export_report.get("ok")
	if not ok_value is bool:
		_add_issue(issues, "export_report_not_ok")
	else:
		var report_ok: bool = ok_value
		if not report_ok:
			_add_issue(issues, "export_report_not_ok")
	var scope: String = str(export_report.get("scope", ""))
	if not PackedStringArray([
		PROFILE_SCOPE_SMOKE,
		PROFILE_SCOPE_RELEASE,
	]).has(scope):
		_add_issue(issues, "export_report_scope_invalid")
	var profile: Dictionary = _profile_for_scope(scope)
	if (
		str(export_report.get("export_preset", ""))
		!= str(profile.get("export_preset", ""))
	):
		_add_issue(issues, "export_report_preset_invalid")
	if (
		str(export_report.get("project_name", ""))
		!= str(profile.get("project_name", ""))
	):
		_add_issue(issues, "export_report_project_name_invalid")
	if str(export_report.get("device_orientation", "")) != "landscape":
		_add_issue(issues, "export_report_orientation_invalid")
	if scope == PROFILE_SCOPE_RELEASE:
		_validate_release_font_policy(export_report, issues)
		_validate_release_resource_closure(export_report, issues)
		_validate_release_limitations(export_report, issues)

	var godot: Dictionary = _dictionary_value(export_report.get("godot", {}))
	if godot.is_empty():
		_add_issue(issues, "report_godot_identity_missing")
	else:
		var declared_version: String = str(godot.get("version", ""))
		var running_version_info: Dictionary = Engine.get_version_info()
		if not _running_godot_is_required_version(running_version_info):
			_add_issue(
				issues,
				"verification_godot_version_not_4_7_2:%s" % str(
					running_version_info.get("string", "")
				)
			)
		if not _matches_required_godot_version(declared_version):
			_add_issue(issues, "report_godot_version_not_4_7_2:%s" % declared_version)
		elif not _declared_godot_matches_running(declared_version, running_version_info):
			_add_issue(issues, "report_godot_version_mismatch:%s:%s" % [
				declared_version,
				str(running_version_info.get("string", "")),
			])
		if str(godot.get("required_version_prefix", "")) != REQUIRED_GODOT_VERSION_PREFIX:
			_add_issue(issues, "report_godot_requirement_invalid")

	var gf: Dictionary = _dictionary_value(export_report.get("gf", {}))
	if str(gf.get("framework_version", "")).is_empty():
		_add_issue(issues, "report_gf_framework_version_invalid")
	if not _is_lower_hex(str(gf.get("source_commit", "")), 40):
		_add_issue(issues, "report_gf_source_commit_invalid")
	if not _is_lower_hex(str(gf.get("source_git_tree", "")), 40):
		_add_issue(issues, "report_gf_source_git_tree_invalid")
	if not _is_lower_hex(str(gf.get("vendor_tree_sha256", "")), 64):
		_add_issue(issues, "report_gf_vendor_tree_invalid")
	if _integer_value(gf.get("vendor_file_count")) <= 0:
		_add_issue(issues, "report_gf_vendor_file_count_invalid")
	if not _is_lower_hex(str(gf.get("lock_sha256", "")), 64):
		_add_issue(issues, "report_gf_lock_hash_invalid")

	var input_hash: String = str(export_report.get("input_snapshot_sha256", ""))
	if not _is_lower_hex(input_hash, 64):
		_add_issue(issues, "report_input_snapshot_hash_invalid")
	var input_snapshot: Dictionary = _dictionary_value(
		export_report.get("input_snapshot", {})
	)
	if _integer_value(input_snapshot.get("schema_version")) != INPUT_SNAPSHOT_SCHEMA_VERSION:
		_add_issue(issues, "report_input_snapshot_schema_invalid")
	if str(input_snapshot.get("input_snapshot_sha256", "")) != input_hash:
		_add_issue(issues, "report_input_snapshot_hash_not_exact")
	if _integer_value(input_snapshot.get("file_count")) <= 0:
		_add_issue(issues, "report_input_snapshot_file_count_invalid")
	_validate_input_snapshot_rules(input_snapshot, issues)

	_validate_report_tool_identity(export_report, issues)
	_validate_report_template(export_report, issues)


func _validate_release_font_policy(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(export_report.get("font_policy", {}))
	var expected_strings: Dictionary = {
		"policy_id": "wechat-release-shipped-literals-v1",
		"coverage_manifest_path": _RELEASE_COVERAGE_MANIFEST_PATH.trim_prefix("res://"),
		"coverage_path": _RELEASE_COVERAGE_PATH.trim_prefix("res://"),
		"coverage_sha256": _RELEASE_COVERAGE_SHA256,
		"subset_font_path": _RELEASE_FONT_PATH.trim_prefix("res://"),
		"subset_font_sha256": _RELEASE_FONT_SHA256,
		"source_font_path": _RELEASE_SOURCE_FONT_PATH,
		"source_font_sha256": _RELEASE_SOURCE_FONT_SHA256,
		"license_path": _RELEASE_LICENSE_PATH,
		"license_spdx": "OFL-1.1",
		"license_sha256": _RELEASE_LICENSE_SHA256,
	}
	for field_value: Variant in expected_strings.keys():
		var field: String = str(field_value)
		if str(declared.get(field, "")) != str(expected_strings[field]):
			_add_issue(issues, "report_release_font_policy_mismatch:%s" % field)
	if not _is_lower_hex(str(declared.get("coverage_manifest_sha256", "")), 64):
		_add_issue(issues, "report_release_font_policy_mismatch:coverage_manifest_sha256")
	if _integer_value(declared.get("codepoint_count")) != _RELEASE_CODEPOINT_COUNT:
		_add_issue(issues, "report_release_font_policy_mismatch:codepoint_count")
	if _integer_value(declared.get("subset_font_bytes")) != _RELEASE_FONT_BYTES:
		_add_issue(issues, "report_release_font_policy_mismatch:subset_font_bytes")
	if declared.size() != expected_strings.size() + 3:
		_add_issue(issues, "report_release_font_policy_not_exact")


func _validate_release_resource_closure(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(
		export_report.get("resource_closure", {})
	)
	if declared.is_empty():
		_add_issue(issues, "report_release_resource_closure_missing")
		return
	var expected_field_count: int = 13
	if declared.size() != expected_field_count:
		_add_issue(issues, "report_release_resource_closure_not_exact")
	if (
		_integer_value(declared.get("schema_version"))
		!= _RELEASE_RESOURCE_CLOSURE_SCHEMA_VERSION
	):
		_add_issue(issues, "report_release_resource_closure_mismatch:schema_version")
	var ok_value: Variant = declared.get("ok")
	if not ok_value is bool or not _boolean_value(ok_value):
		_add_issue(issues, "report_release_resource_closure_not_complete")
	var partial_value: Variant = declared.get("dependency_partial")
	var truncated_value: Variant = declared.get("dependency_truncated")
	if (
		not partial_value is bool
		or _boolean_value(partial_value, true)
		or not truncated_value is bool
		or _boolean_value(truncated_value, true)
	):
		_add_issue(issues, "report_release_resource_closure_not_complete")
	var declared_issues: Variant = declared.get("issues")
	if not declared_issues is Array:
		_add_issue(issues, "report_release_resource_closure_issues_not_empty")
	else:
		var declared_issues_array: Array = declared_issues
		if not declared_issues_array.is_empty():
			_add_issue(issues, "report_release_resource_closure_issues_not_empty")

	var tool_identity: Dictionary = _dictionary_value(
		export_report.get("tool_identity", {})
	)
	var closure_tool: Dictionary = _dictionary_value(
		tool_identity.get("release_resource_closure", {})
	)
	var closure_policy: Dictionary = _dictionary_value(
		tool_identity.get("release_resource_policy", {})
	)
	var expected_strings: Dictionary = {
		"policy_id": _RELEASE_RESOURCE_CLOSURE_POLICY_ID,
		"policy_path": str(_TOOL_IDENTITY_PATHS.get("release_resource_policy", "")),
		"policy_sha256": str(closure_policy.get("sha256", "")),
		"tool_path": str(_TOOL_IDENTITY_PATHS.get("release_resource_closure", "")),
		"tool_sha256": str(closure_tool.get("sha256", "")),
	}
	for field_value: Variant in expected_strings.keys():
		var field: String = str(field_value)
		if str(declared.get(field, "")) != str(expected_strings[field]):
			_add_issue(issues, "report_release_resource_closure_mismatch:%s" % field)
	for hash_field: String in PackedStringArray([
		"policy_sha256",
		"tool_sha256",
		"closure_sha256",
	]):
		if not _is_lower_hex(str(declared.get(hash_field, "")), 64):
			_add_issue(issues, "report_release_resource_closure_mismatch:%s" % hash_field)
	if _integer_value(declared.get("full_dependency_scan_count")) <= 0:
		_add_issue(
			issues,
			"report_release_resource_closure_mismatch:full_dependency_scan_count"
		)

	var counts: Dictionary = _dictionary_value(declared.get("counts", {}))
	if counts.size() != _RELEASE_RESOURCE_CLOSURE_COUNT_FIELDS.size():
		_add_issue(issues, "report_release_resource_closure_counts_not_exact")
	for count_field: String in _RELEASE_RESOURCE_CLOSURE_COUNT_FIELDS:
		var count: int = _integer_value(counts.get(count_field))
		if count < 0:
			_add_issue(
				issues,
				"report_release_resource_closure_count_invalid:%s" % count_field
			)
	if (
		_integer_value(counts.get("roots")) <= 0
		or _integer_value(counts.get("closure")) <= 0
		or _integer_value(counts.get("issues")) != 0
	):
		_add_issue(issues, "report_release_resource_closure_not_complete")


func _validate_release_limitations(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	var limitations_value: Variant = export_report.get("limitations", [])
	if not limitations_value is Array:
		_add_issue(issues, "report_release_limitations_invalid")
		return
	var limitations: Array = limitations_value
	var limitation_texts: PackedStringArray = PackedStringArray()
	for value: Variant in limitations:
		var _limitation_added: bool = limitation_texts.append(str(value))
	var normalized: String = " ".join(limitation_texts).to_lower()
	if not normalized.contains("not enabled"):
		_add_issue(issues, "report_release_sdk_limitations_missing")
	for capability: String in PackedStringArray([
		"login",
		"share",
		"payment",
		"cloud save",
		"open-data",
	]):
		if not normalized.contains(capability):
			_add_issue(issues, "report_release_sdk_limitation_missing:%s" % capability)


func _validate_input_snapshot_rules(
	input_snapshot: Dictionary,
	issues: PackedStringArray
) -> void:
	var rules: Dictionary = _dictionary_value(input_snapshot.get("rules", {}))
	var expected_rules: Dictionary = {
		"include_exact": _INPUT_INCLUDE_EXACT,
		"include_roots": _INPUT_INCLUDE_ROOTS,
		"exclude_exact": _INPUT_EXCLUDE_EXACT,
		"exclude_prefixes": _INPUT_EXCLUDE_PREFIXES,
		"exclude_generated": _INPUT_EXCLUDE_GENERATED,
		"exclude_cache_suffixes": _INPUT_EXCLUDE_CACHE_SUFFIXES,
	}
	for rule_name_value: Variant in expected_rules.keys():
		var rule_name: String = str(rule_name_value)
		var expected: PackedStringArray = expected_rules[rule_name]
		if not _string_sequence_equals(rules.get(rule_name, []), expected):
			_add_issue(issues, "report_input_snapshot_rule_mismatch:%s" % rule_name)
	if rules.size() != expected_rules.size():
		_add_issue(issues, "report_input_snapshot_rules_not_exact")


func _validate_report_tool_identity(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	var declared_identity: Dictionary = _dictionary_value(
		export_report.get("tool_identity", {})
	)
	var actual_identity: Dictionary = build_tool_identity()
	if declared_identity.size() != _TOOL_IDENTITY_NAMES.size():
		_add_issue(issues, "report_tool_identity_not_exact")
	for tool_name: String in _TOOL_IDENTITY_NAMES:
		var declared: Dictionary = _dictionary_value(declared_identity.get(tool_name, {}))
		var actual: Dictionary = _dictionary_value(actual_identity.get(tool_name, {}))
		var expected_path: String = str(_TOOL_IDENTITY_PATHS.get(tool_name, ""))
		if str(declared.get("path", "")) != expected_path:
			_add_issue(issues, "report_tool_path_mismatch:%s" % tool_name)
		var declared_hash: String = str(declared.get("sha256", ""))
		if not _is_lower_hex(declared_hash, 64):
			_add_issue(issues, "report_tool_hash_invalid:%s" % tool_name)
		elif declared_hash != str(actual.get("sha256", "")):
			_add_issue(issues, "report_tool_hash_mismatch:%s" % tool_name)


func _validate_report_template(
	export_report: Dictionary,
	issues: PackedStringArray
) -> void:
	var template: Dictionary = _dictionary_value(export_report.get("template", {}))
	if (
		str(template.get("release", "")) != _TEMPLATE_RELEASE
		or str(template.get("asset", "")) != _TEMPLATE_ASSET
		or _integer_value(template.get("expected_bytes")) != _TEMPLATE_EXPECTED_BYTES
		or str(template.get("sha256", "")) != _TEMPLATE_SHA256
	):
		_add_issue(issues, "report_template_identity_invalid")


func _validate_report_render_resolution(
	export_report: Dictionary,
	artifact_root: String,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(
		export_report.get("render_resolution", {})
	)
	var expected_strings: Dictionary = {
		"policy_id": "wechat-bounded-backing-store-dpr-v1",
		"loader_patch": "2048-wechat-loader-dpr-cap-v1",
		"runtime_patch": "2048-wechat-runtime-dpr-cap-v1",
		"loader_sha256": FileAccess.get_sha256(
			artifact_root.path_join("godot-loader.js")
		).to_lower(),
		"runtime_sha256": FileAccess.get_sha256(
			artifact_root.path_join("engine/godot.js")
		).to_lower(),
	}
	for field_value: Variant in expected_strings.keys():
		var field: String = str(field_value)
		if str(declared.get(field, "")) != str(expected_strings[field]):
			_add_issue(issues, "report_render_resolution_mismatch:%s" % field)
	var expected_integers: Dictionary = {
		"long_edge_target_pixels": 1280,
		"short_edge_target_pixels": 720,
		"minimum_dpr": 1,
	}
	for field_value: Variant in expected_integers.keys():
		var field: String = str(field_value)
		if _integer_value(declared.get(field)) != _integer_value(
			expected_integers.get(field)
		):
			_add_issue(issues, "report_render_resolution_mismatch:%s" % field)
	for field: String in PackedStringArray([
		"device_dpr_ceiling",
		"css_size_preserved",
		"input_mapping_preserved",
		"resize_recomputed",
	]):
		var value: Variant = declared.get(field)
		if not value is bool or not value:
			_add_issue(issues, "report_render_resolution_mismatch:%s" % field)
	if declared.size() != 12:
		_add_issue(issues, "report_render_resolution_not_exact")


func _validate_report_startup(
	export_report: Dictionary,
	artifact_root: String,
	package: Dictionary,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(export_report.get("startup", {}))
	var coordinator_path: String = artifact_root.path_join(
		_STARTUP_COORDINATOR_RELATIVE_PATH
	)
	var expected_values: Dictionary = {
		"schema_version": 1,
		"strategy": "parallel_subpackages_four_way_barrier",
		"coordinator_path": _STARTUP_COORDINATOR_RELATIVE_PATH,
		"coordinator_sha256": FileAccess.get_sha256(coordinator_path).to_lower(),
		"trace_schema_version": 1,
		"trace_limit": 64,
		"package_timeout_ms": 300000,
		"probe_timeout_ms": 10000,
		"starter_timeout_ms": 10000,
		"engine_start_timeout_ms": 300000,
		"engine_package_bytes": _integer_value(package.get("engine_package_bytes")),
		"game_data_package_bytes": _integer_value(
			package.get("game_data_package_bytes")
		),
	}
	for field_value: Variant in expected_values.keys():
		var field: String = str(field_value)
		if declared.get(field) != expected_values[field]:
			_add_issue(issues, "report_startup_mismatch:%s" % field)
	var progress_weight: Variant = declared.get("download_progress_weight")
	if not progress_weight is float:
		_add_issue(issues, "report_startup_mismatch:download_progress_weight")
	else:
		var typed_progress_weight: float = progress_weight
		if not is_equal_approx(typed_progress_weight, 0.95):
			_add_issue(issues, "report_startup_mismatch:download_progress_weight")
	if _integer_value(declared.get("progress_trace_step_percentage")) != 5:
		_add_issue(issues, "report_startup_mismatch:progress_trace_step_percentage")
	var ui_progress_step: Variant = declared.get("ui_progress_minimum_step")
	if not ui_progress_step is float:
		_add_issue(issues, "report_startup_mismatch:ui_progress_minimum_step")
	else:
		var typed_ui_progress_step: float = ui_progress_step
		if not is_equal_approx(typed_ui_progress_step, 0.005):
			_add_issue(issues, "report_startup_mismatch:ui_progress_minimum_step")
	if not _string_sequence_equals(declared.get("barrier", []), PackedStringArray([
		"engine_entry",
		"engine_starter",
		"game_data_entry",
		"game_data_pck_probe",
	])):
		_add_issue(issues, "report_startup_mismatch:barrier")
	for field: String in PackedStringArray([
		"first_fatal_wins",
		"late_callbacks_inert",
		"engine_start_once",
	]):
		var value: Variant = declared.get(field)
		if not value is bool or not value:
			_add_issue(issues, "report_startup_mismatch:%s" % field)
	if declared.size() != 19:
		_add_issue(issues, "report_startup_not_exact")


func _validate_report_large_file_reader(
	export_report: Dictionary,
	artifact_root: String,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(
		export_report.get("large_file_reader", {})
	)
	var helper_path: String = artifact_root.path_join(_CHUNK_LOADER_RELATIVE_PATH)
	var helper_sha256: String = (
		FileAccess.get_sha256(helper_path).to_lower()
		if FileAccess.file_exists(helper_path)
		else ""
	)
	var expected_values: Dictionary = {
		"strategy": "async_position_length_chunked_bounded_concurrency",
		"chunk_bytes": 4_194_304,
		"max_concurrent_resources": 2,
		"inflight_deduplication": "resource_path",
		"helper_path": _CHUNK_LOADER_RELATIVE_PATH,
		"helper_sha256": helper_sha256,
	}
	for field_value: Variant in expected_values.keys():
		var field: String = str(field_value)
		if declared.get(field) != expected_values[field]:
			_add_issue(issues, "report_large_file_reader_mismatch:%s" % field)

	var expected_resource_paths: PackedStringArray = _CHUNK_RESOURCE_PATHS.duplicate()
	expected_resource_paths.sort()
	var declared_resource_paths: PackedStringArray = PackedStringArray()
	var resources_value: Variant = declared.get("resources", [])
	if not resources_value is Array:
		_add_issue(issues, "report_large_file_reader_resources_invalid")
	else:
		var resources: Array = resources_value
		for resource_value: Variant in resources:
			if not resource_value is Dictionary:
				_add_issue(issues, "report_large_file_reader_resources_invalid")
				continue
			var resource: Dictionary = resource_value
			var resource_path: String = str(resource.get("path", ""))
			if (
				resource_path.is_empty()
				or resource_path in declared_resource_paths
				or resource_path not in expected_resource_paths
			):
				_add_issue(
					issues,
					"report_large_file_reader_resource_path_invalid:%s" % resource_path
				)
				continue
			var _path_added: bool = declared_resource_paths.append(resource_path)
			var artifact_path: String = artifact_root.path_join(
				resource_path.trim_prefix("/")
			)
			var file: FileAccess = FileAccess.open(artifact_path, FileAccess.READ)
			if file == null:
				continue
			var actual_bytes: int = file.get_length()
			if _integer_value(resource.get("bytes")) != actual_bytes:
				_add_issue(
					issues,
					"report_large_file_reader_resource_bytes_mismatch:%s" % resource_path
				)
			var actual_sha256: String = FileAccess.get_sha256(artifact_path).to_lower()
			if str(resource.get("sha256", "")) != actual_sha256:
				_add_issue(
					issues,
					"report_large_file_reader_resource_hash_mismatch:%s" % resource_path
				)
	declared_resource_paths.sort()
	if declared_resource_paths != expected_resource_paths:
		_add_issue(issues, "report_large_file_reader_resource_paths_not_exact")
	if declared.size() != 7:
		_add_issue(issues, "report_large_file_reader_not_exact")


func _validate_report_artifact(
	export_report: Dictionary,
	artifact_root: String,
	files: PackedStringArray,
	issues: PackedStringArray
) -> void:
	var actual_manifest: Dictionary = _build_artifact_manifest(
		artifact_root,
		files,
		issues
	)
	var actual_hash: String = str(actual_manifest.get("manifest_sha256", ""))
	var top_hash: String = str(export_report.get("artifact_manifest_sha256", ""))
	if not _is_lower_hex(top_hash, 64):
		_add_issue(issues, "report_artifact_manifest_hash_invalid")
	elif top_hash != actual_hash:
		_add_issue(issues, "artifact_manifest_hash_mismatch")
	var declared_manifest: Dictionary = _dictionary_value(export_report.get("artifact", {}))
	if _integer_value(declared_manifest.get("schema_version")) != ARTIFACT_MANIFEST_SCHEMA_VERSION:
		_add_issue(issues, "artifact_manifest_schema_invalid")
	if str(declared_manifest.get("manifest_sha256", "")) != top_hash:
		_add_issue(issues, "artifact_manifest_hash_not_exact")

	var actual_entries: Array = actual_manifest.get("files", [])
	var declared_entries_value: Variant = declared_manifest.get("files", [])
	if not declared_entries_value is Array:
		_add_issue(issues, "artifact_manifest_files_not_array")
		return
	var declared_entries: Array = declared_entries_value
	if (
		_integer_value(declared_manifest.get("file_count")) != actual_entries.size()
		or declared_entries.size() != actual_entries.size()
	):
		_add_issue(issues, "artifact_manifest_entries_not_exact")
	var compared_count: int = mini(declared_entries.size(), actual_entries.size())
	for index: int in range(compared_count):
		if not declared_entries[index] is Dictionary:
			_add_issue(issues, "artifact_manifest_entry_invalid:%d" % index)
			continue
		var declared: Dictionary = declared_entries[index]
		var actual: Dictionary = actual_entries[index]
		var actual_path: String = str(actual.get("path", ""))
		if str(declared.get("path", "")) != actual_path:
			_add_issue(issues, "artifact_file_path_mismatch:%d" % index)
		if _integer_value(declared.get("bytes")) != _integer_value(
			actual.get("bytes", -1)
		):
			_add_issue(issues, "artifact_file_bytes_mismatch:%s" % actual_path)
		if str(declared.get("sha256", "")) != str(actual.get("sha256", "")):
			_add_issue(issues, "artifact_file_hash_mismatch:%s" % actual_path)


func _validate_report_package(
	export_report: Dictionary,
	actual_package: Dictionary,
	files: PackedStringArray,
	issues: PackedStringArray
) -> void:
	var declared: Dictionary = _dictionary_value(export_report.get("package", {}))
	for field: String in PackedStringArray([
		"main_package_bytes",
		"engine_package_bytes",
		"game_data_package_bytes",
		"total_package_bytes",
	]):
		if _integer_value(declared.get(field)) != _integer_value(
			actual_package.get(field, -1)
		):
			_add_issue(issues, "report_package_bytes_mismatch:%s" % field)
	var expected_limits: Dictionary = {
		"main_hard_limit_bytes": MAIN_PACKAGE_HARD_LIMIT_BYTES,
		"engine_hard_limit_bytes": ENGINE_SUBPACKAGE_HARD_LIMIT_BYTES,
		"game_data_hard_limit_bytes": GAME_DATA_SUBPACKAGE_HARD_LIMIT_BYTES,
		"total_hard_limit_bytes": TOTAL_PACKAGE_HARD_LIMIT_BYTES,
		"main_soft_limit_bytes": MAIN_PACKAGE_SOFT_LIMIT_BYTES,
		"engine_soft_limit_bytes": ENGINE_SUBPACKAGE_SOFT_LIMIT_BYTES,
		"game_data_soft_limit_bytes": GAME_DATA_SUBPACKAGE_SOFT_LIMIT_BYTES,
		"total_soft_limit_bytes": TOTAL_PACKAGE_SOFT_LIMIT_BYTES,
	}
	for limit_name_value: Variant in expected_limits.keys():
		var limit_name: String = str(limit_name_value)
		if _integer_value(declared.get(limit_name)) != _integer_value(
			expected_limits.get(limit_name)
		):
			_add_issue(issues, "report_package_limit_mismatch:%s" % limit_name)
	for field: String in PackedStringArray([
		"main_hard_limit_ok",
		"engine_hard_limit_ok",
		"game_data_hard_limit_ok",
		"total_hard_limit_ok",
		"main_soft_budget_ok",
		"engine_soft_budget_ok",
		"game_data_soft_budget_ok",
		"total_soft_budget_ok",
	]):
		var value: Variant = declared.get(field)
		if not value is bool:
			_add_issue(issues, "report_package_budget_mismatch:%s" % field)
			continue
		var declared_value: bool = value
		if declared_value != _boolean_value(actual_package.get(field)):
			_add_issue(issues, "report_package_budget_mismatch:%s" % field)
	if _integer_value(declared.get("file_count")) != files.size():
		_add_issue(issues, "report_package_file_count_mismatch")
	if not _string_sequence_equals(declared.get("files", []), files):
		_add_issue(issues, "report_package_files_not_exact")
	for empty_field: String in PackedStringArray([
		"missing_paths",
		"unexpected_paths",
		"forbidden_paths",
	]):
		var empty_value: Variant = declared.get(empty_field)
		if not empty_value is Array:
			_add_issue(issues, "report_package_issue_list_not_empty:%s" % empty_field)
			continue
		var empty_array: Array = empty_value
		if not empty_array.is_empty():
			_add_issue(issues, "report_package_issue_list_not_empty:%s" % empty_field)


func _build_artifact_manifest(
	root: String,
	files: PackedStringArray,
	issues: PackedStringArray
) -> Dictionary:
	var entries: Array = []
	var records: PackedStringArray = PackedStringArray([
		"wechat-artifact-manifest-v%d" % ARTIFACT_MANIFEST_SCHEMA_VERSION,
	])
	for relative_path: String in files:
		if not _is_canonical_manifest_path(relative_path):
			_add_issue(issues, "artifact_manifest_path_not_canonical:%s" % relative_path)
			continue
		var path: String = root.path_join(relative_path)
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			_add_issue(issues, "artifact_manifest_file_unreadable:%s" % relative_path)
			continue
		var byte_count: int = file.get_length()
		var sha256: String = FileAccess.get_sha256(path).to_lower()
		entries.append({
			"path": relative_path,
			"bytes": byte_count,
			"sha256": sha256,
		})
		var _record_added: bool = records.append(
			"%s\t%d\t%s" % [relative_path, byte_count, sha256]
		)
	return {
		"schema_version": ARTIFACT_MANIFEST_SCHEMA_VERSION,
		"manifest_sha256": ("\n".join(records) + "\n").sha256_text(),
		"file_count": entries.size(),
		"files": entries,
	}


func _empty_artifact_manifest() -> Dictionary:
	return {
		"schema_version": ARTIFACT_MANIFEST_SCHEMA_VERSION,
		"manifest_sha256": (
			"wechat-artifact-manifest-v%d\n" % ARTIFACT_MANIFEST_SCHEMA_VERSION
		).sha256_text(),
		"file_count": 0,
		"files": [],
	}


func _is_canonical_manifest_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.contains("\t")
		and not path.contains("\r")
		and not path.contains("\n")
		and not path.contains("../")
	)


func _matches_required_godot_version(version: String) -> bool:
	return (
		version == REQUIRED_GODOT_VERSION_PREFIX
		or version.begins_with(REQUIRED_GODOT_VERSION_PREFIX + ".")
	)


func _running_godot_is_required_version(version_info: Dictionary) -> bool:
	return (
		_integer_value(version_info.get("major")) == 4
		and _integer_value(version_info.get("minor")) == 7
		and _integer_value(version_info.get("patch")) == 2
		and str(version_info.get("status", "")) == "stable"
	)


func _declared_godot_matches_running(
	declared_version: String,
	version_info: Dictionary
) -> bool:
	if declared_version == REQUIRED_GODOT_VERSION_PREFIX:
		return true
	var suffix: String = declared_version.trim_prefix(
		REQUIRED_GODOT_VERSION_PREFIX + "."
	)
	var parts: PackedStringArray = suffix.split(".")
	if parts.is_empty() or parts[0].is_empty():
		return false
	var running_build: String = str(version_info.get("build", ""))
	if not running_build.is_empty() and parts[0] != running_build:
		return false
	if parts.size() >= 2:
		var declared_hash: String = parts[1]
		var running_hash: String = str(version_info.get("hash", ""))
		if declared_hash.is_empty() or not running_hash.begins_with(declared_hash):
			return false
	return parts.size() <= 2


func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 97 and codepoint <= 102)
		):
			return false
	return true


func _integer_value(value: Variant, default_value: int = -1) -> int:
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		var integer_value: int = int(float_value)
		if is_finite(float_value) and float(integer_value) == float_value:
			return integer_value
	return default_value


func _boolean_value(value: Variant, default_value: bool = false) -> bool:
	if value is bool:
		var boolean_value: bool = value
		return boolean_value
	return default_value


func _dictionary_value(value: Variant) -> Dictionary:
	if value is Dictionary:
		var dictionary: Dictionary = value
		return dictionary
	return {}


func _string_sequence_equals(value: Variant, expected: PackedStringArray) -> bool:
	if value is Array:
		var array_value: Array = value
		if array_value.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			if str(array_value[index]) != expected[index]:
				return false
		return true
	if value is PackedStringArray:
		var packed_value: PackedStringArray = value
		return packed_value == expected
	return false


func _inspect_pack(
	root: String,
	profile: Dictionary,
	issues: PackedStringArray
) -> void:
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
	var expected_font_token: String = str(profile.get("font_token", ""))
	if not _bytes_contain_text(pack_bytes, expected_font_token):
		_add_issue(issues, "pack_expected_font_token_missing:%s" % expected_font_token)
	var unexpected_font_token: String = (
		_SMOKE_FONT_TOKEN
		if expected_font_token == _RELEASE_FONT_TOKEN
		else _RELEASE_FONT_TOKEN
	)
	if _bytes_contain_text(pack_bytes, unexpected_font_token):
		_add_issue(issues, "pack_unexpected_font_token:%s" % unexpected_font_token)
	if _bytes_contain_text(pack_bytes, _EXPORT_PLUGIN_CODE_TOKEN):
		_add_issue(issues, "pack_contains_editor_export_plugin")
	if (
		str(profile.get("scope", "")) == PROFILE_SCOPE_RELEASE
		and _bytes_contain_text(pack_bytes, _TEXT_SERVER_DATA_TOKEN)
	):
		_add_issue(issues, "pack_contains_text_server_support_data")
	if not ProjectSettings.load_resource_pack(pack_path, true):
		_add_issue(issues, "pack_mount_failed")
		return
	if (
		str(profile.get("scope", "")) == PROFILE_SCOPE_RELEASE
		and FileAccess.file_exists("res://%s" % _TEXT_SERVER_DATA_TOKEN)
	):
		_add_issue(issues, "pack_contains_text_server_support_data")
	var expected_font_path: String = str(profile.get("font_path", ""))
	var expected_font_sha256: String = str(profile.get("font_sha256", ""))
	if not ResourceLoader.exists(expected_font_path):
		_add_issue(issues, "pack_expected_font_resource_missing:%s" % expected_font_path)
	if str(profile.get("scope", "")) == PROFILE_SCOPE_RELEASE:
		for index: int in range(_RELEASE_TRANSLATION_PATHS.size()):
			var translation_path: String = _RELEASE_TRANSLATION_PATHS[index]
			if not ResourceLoader.exists(translation_path):
				_add_issue(
					issues,
					"pack_translation_missing:%s" % translation_path
				)
				continue
			var translation_resource: Resource = load(translation_path)
			if not translation_resource is Translation:
				_add_issue(
					issues,
					"pack_translation_invalid:%s" % translation_path
				)
				continue
			var translation: Translation = translation_resource
			if translation.get_locale() != _RELEASE_TRANSLATION_LOCALES[index]:
				_add_issue(
					issues,
					"pack_translation_locale_mismatch:%s:%s" % [
						translation_path,
						translation.get_locale(),
					]
				)
	var required_codepoints: PackedInt32Array = _required_profile_codepoints(
		profile,
		issues
	)
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
		if _sha256_bytes(font_file.data) != expected_font_sha256:
			_add_issue(issues, "pack_font_hash_mismatch:%s" % variation_path)
		for codepoint: int in required_codepoints:
			if not font_variation.has_char(codepoint):
				_add_issue(
					issues,
					"pack_font_glyph_missing:%s:U+%04X" % [variation_path, codepoint]
				)


func _required_profile_codepoints(
	profile: Dictionary,
	issues: PackedStringArray
) -> PackedInt32Array:
	var codepoints: PackedInt32Array = PackedInt32Array()
	var scope: String = str(profile.get("scope", ""))
	if scope != PROFILE_SCOPE_RELEASE:
		for index: int in range(_REQUIRED_FONT_TEXT.length()):
			var _codepoint_added: bool = codepoints.append(
				_REQUIRED_FONT_TEXT.unicode_at(index)
			)
		return codepoints
	if not FileAccess.file_exists(_RELEASE_COVERAGE_PATH):
		_add_issue(issues, "pack_release_font_coverage_missing")
		return codepoints
	if FileAccess.get_sha256(_RELEASE_COVERAGE_PATH).to_lower() != _RELEASE_COVERAGE_SHA256:
		_add_issue(issues, "pack_release_font_coverage_hash_mismatch")
	if not FileAccess.file_exists(_RELEASE_COVERAGE_MANIFEST_PATH):
		_add_issue(issues, "pack_release_font_manifest_missing")
	else:
		var expected_manifest_hash: String = str(
			profile.get("coverage_manifest_sha256", "")
		)
		if (
			not _is_lower_hex(expected_manifest_hash, 64)
			or FileAccess.get_sha256(_RELEASE_COVERAGE_MANIFEST_PATH).to_lower()
			!= expected_manifest_hash
		):
			_add_issue(issues, "pack_release_font_manifest_hash_mismatch")
		_validate_packed_release_font_manifest(issues)

	var seen: Dictionary = {}
	var coverage_text: String = FileAccess.get_file_as_string(_RELEASE_COVERAGE_PATH)
	for token: String in coverage_text.strip_edges().split(",", false):
		var codepoint_text: String = token.strip_edges()
		if not codepoint_text.begins_with("U+"):
			_add_issue(issues, "pack_release_font_coverage_token_invalid:%s" % token)
			continue
		var codepoint: int = codepoint_text.trim_prefix("U+").hex_to_int()
		if codepoint <= 0 or codepoint > 0x10FFFF or seen.has(codepoint):
			_add_issue(issues, "pack_release_font_coverage_token_invalid:%s" % token)
			continue
		seen[codepoint] = true
		var _codepoint_added: bool = codepoints.append(codepoint)
	if codepoints.size() != _RELEASE_CODEPOINT_COUNT:
		_add_issue(issues, "pack_release_font_coverage_count_mismatch:%d" % codepoints.size())
	return codepoints


func _validate_packed_release_font_manifest(issues: PackedStringArray) -> void:
	var read_report: Dictionary = GFBoundedJsonObjectReader.read_object(
		_RELEASE_COVERAGE_MANIFEST_PATH,
		_FONT_MANIFEST_JSON_MAX_BYTES,
		_FONT_MANIFEST_JSON_MAX_DEPTH
	)
	if not _boolean_value(read_report.get("ok")):
		_add_issue(issues, "pack_release_font_manifest_invalid:%s" % (
			str(read_report.get("error_kind", "invalid"))
		))
		return
	var manifest: Dictionary = _dictionary_value(read_report.get("data"))
	var coverage: Dictionary = _dictionary_value(manifest.get("coverage", {}))
	var source_font: Dictionary = _dictionary_value(manifest.get("source_font", {}))
	var subset_font: Dictionary = _dictionary_value(manifest.get("subset_font", {}))
	var license: Dictionary = _dictionary_value(manifest.get("license", {}))
	if _integer_value(manifest.get("schema_version")) != 1:
		_add_issue(issues, "pack_release_font_manifest_schema_invalid")
	if str(manifest.get("policy_id", "")) != "wechat-release-shipped-literals-v1":
		_add_issue(issues, "pack_release_font_manifest_policy_invalid")
	if (
		_integer_value(coverage.get("codepoint_count")) != _RELEASE_CODEPOINT_COUNT
		or str(coverage.get("codepoints_sha256", "")) != _RELEASE_COVERAGE_SHA256
	):
		_add_issue(issues, "pack_release_font_manifest_coverage_invalid")
	if (
		str(source_font.get("path", "")) != _RELEASE_SOURCE_FONT_PATH
		or str(source_font.get("sha256", "")) != _RELEASE_SOURCE_FONT_SHA256
	):
		_add_issue(issues, "pack_release_font_manifest_source_invalid")
	if (
		str(subset_font.get("path", "")) != _RELEASE_FONT_PATH.trim_prefix("res://")
		or str(subset_font.get("sha256", "")) != _RELEASE_FONT_SHA256
		or _integer_value(subset_font.get("bytes")) != _RELEASE_FONT_BYTES
	):
		_add_issue(issues, "pack_release_font_manifest_subset_invalid")
	if (
		str(license.get("path", "")) != _RELEASE_LICENSE_PATH
		or str(license.get("spdx", "")) != "OFL-1.1"
		or str(license.get("sha256", "")) != _RELEASE_LICENSE_SHA256
	):
		_add_issue(issues, "pack_release_font_manifest_license_invalid")


func _pack_host_is_isolated() -> bool:
	if (
		ResourceLoader.exists(_SMOKE_FONT_PATH)
		or ResourceLoader.exists(_RELEASE_FONT_PATH)
	):
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
