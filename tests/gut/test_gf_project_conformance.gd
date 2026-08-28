## 验证项目只通过受控入口使用 GF，并遵守 GF 模块生命周期契约。
extends GutTest


# --- 常量 ---

const PROJECT_SOURCE_ROOTS: Array[String] = [
	"res://app",
	VerificationResourcePath.FEATURES_ROOT,
	"res://shared",
]
const GLOBAL_GF_ACCESS_SCAN_ROOTS: Array[String] = [
	"res://app",
	VerificationResourcePath.FEATURES_ROOT,
	"res://shared",
	"res://tools",
]
const SOURCE_EXCLUDED_ROOTS: Array[String] = [
	"res://features/asset_library/resources/source_packs",
]
const GLOBAL_GF_ACCESS_ALLOWLIST: Array[String] = [
	"res://app/scripts/boot.gd",
	"res://app/scripts/boot_runtime.gd",
	"res://tools/gf_tool_architecture_access.gd",
]
const DIRECT_TIME_AND_RANDOM_ALLOWLIST: Array[String] = [
	"res://app/scripts/boot.gd",
	"res://app/scripts/boot_runtime.gd",
	"res://features/asset_library/tools/asset_review_browser.gd",
	"res://features/asset_library/tools/import_asset_sources.gd",
	"res://shared/scripts/utilities/game_clock_utility.gd",
]
const BOOT_RUNTIME_SCRIPT_PATH: String = "res://app/scripts/boot_runtime.gd"
const PLATFORM_CONTEXT_CONSUMER_PATHS: Array[String] = [
	"res://features/game_session/scripts/controllers/gameplay_responsive_layout_controller.gd",
	"res://features/board_editor/scripts/ui/board_editor_responsive_layout_controller.gd",
]
## 当前唯一宿主探测 owner；使用精确文件而不是排除整个 platform_runtime Feature。
const PLATFORM_PROBE_OWNER_PATHS: Array[String] = [
	"res://features/platform_runtime/scripts/adapters/local_platform_adapter.gd",
]
## settings UI 仅把这些类型/枚举值传给 GFDisplaySettingsUtility；它们不读取宿主事实。
const DISPLAY_SERVER_ENUM_ONLY_MEMBERS: Array[String] = [
	"WindowMode",
	"VSyncMode",
	"WINDOW_MODE_WINDOWED",
	"WINDOW_MODE_FULLSCREEN",
	"WINDOW_MODE_EXCLUSIVE_FULLSCREEN",
	"WINDOW_MODE_MAXIMIZED",
	"WINDOW_MODE_MINIMIZED",
	"VSYNC_DISABLED",
	"VSYNC_ENABLED",
	"VSYNC_ADAPTIVE",
	"VSYNC_MAILBOX",
]
## 非 Adapter 例外按精确文件和精确调用片段声明，避免同成员换参数或换用途后仍被放行。
## Composition Root 只读取既有构建 feature/headless 启动事实；开发诊断只读取启用条件。
const PLATFORM_PROBE_EXCEPTIONS: Dictionary = {
	"res://app/scripts/boot.gd": {
		"allowed_fragments": [
			"OS.has_feature(\"with_dev_tools\")",
			"DisplayServer.get_name() == \"headless\"",
		],
		"reason": "Composition Root 构建 feature 与 headless 启动选择。",
	},
	"res://app/scripts/boot_runtime.gd": {
		"allowed_fragments": [
			"OS.has_feature(_PLATFORM_SMOKE_FEATURE)",
			"OS.has_feature(_WECHAT_RELEASE_FEATURE)",
			"DisplayServer.get_name() == \"headless\"",
			"DisplayServer.get_name() != \"headless\"",
		],
		"reason": "Composition Root 场景选择与首帧启动编排。",
	},
	"res://app/scripts/game_architecture_installer.gd": {
		"allowed_fragments": [
			"OS.has_feature(_PLATFORM_SMOKE_FEATURE)",
			"OS.has_feature(_DEV_TOOLS_FEATURE)",
			"OS.has_feature(_VERBOSE_LOGGING_FEATURE)",
		],
		"reason": "Composition Root 构建 feature 组合。",
	},
	"res://features/diagnostics/scripts/installers/game_diagnostics_installer.gd": {
		"allowed_fragments": [
			"OS.has_feature(_VERBOSE_LOGGING_FEATURE)",
		],
		"reason": "仅开发诊断安装条件。",
	},
	"res://features/diagnostics/scripts/utilities/test_tool_utility.gd": {
		"allowed_fragments": [
			"DisplayServer.get_name().to_lower() != \"headless\"",
			"OS.has_feature(\"web\")",
			"OS.has_feature(\"mobile\")",
			"OS.has_feature(\"android\")",
			"OS.has_feature(\"ios\")",
		],
		"reason": "仅开发测试工具可用性诊断。",
	},
}
const PLATFORM_PROBE_REJECTION_FIXTURE_PATH: String = (
	"res://tests/gut/fixtures/direct_platform_probe_feature.gd.txt"
)
const PLATFORM_PROBE_REJECTION_VIRTUAL_PATH: String = (
	VerificationResourcePath.ROOT + "features/regression_fixture/scripts/direct_platform_probe.gd"
)
const PLATFORM_PROBE_EXCEPTION_MISUSE_FIXTURE_PATH: String = (
	"res://tests/gut/fixtures/platform_probe_exception_misuse.gd.txt"
)
const MAIN_MENU_SCRIPT_PATH: String = "res://features/navigation/scripts/menus/main_menu.gd"
const GF_API_INDEX_PATH: String = (
	"res://addons/gf/tools/ai_developer/knowledge/api_index.json"
)
const PROJECT_CONTRACT_PATH: String = "res://.gf/project_contract.json"
const GF_MODULE_BASE_PATHS: Array[String] = [
	"res://addons/gf/kernel/base/gf_model.gd",
	"res://addons/gf/kernel/base/gf_system.gd",
	"res://addons/gf/kernel/base/gf_utility.gd",
	"res://addons/gf/standard/utilities/settings/gf_settings_utility.gd",
	"res://addons/gf/standard/utilities/ui/gf_ui_router_utility.gd",
]
const EARLY_LIFECYCLE_METHODS: Array[String] = [
	"init",
	"async_init",
]
const CROSS_MODULE_LOOKUP_METHODS: Array[String] = [
	"get_architecture",
	"get_architecture_or_null",
	"get_model",
	"get_system",
	"get_utility",
]
const DECLARED_DEPENDENCY_CONTRACTS: Array[Dictionary] = [
	{
		"kind": "model",
		"lookup_method": "get_model",
		"hook_method": "get_required_models",
	},
	{
		"kind": "system",
		"lookup_method": "get_system",
		"hook_method": "get_required_systems",
	},
	{
		"kind": "utility",
		"lookup_method": "get_utility",
		"hook_method": "get_required_utilities",
	},
]
const ASSET_LIBRARY_TOOL_PATHS: Array[String] = [
	"res://features/asset_library/tools/asset_library_audit.gd",
	"res://features/asset_library/tools/import_asset_sources.gd",
	"res://tools/audit_asset_library.gd",
	"res://tools/purge_rejected_assets.gd",
	"res://tools/audit_asset_library.ps1",
	"res://tools/import_asset_sources.ps1",
	"res://tools/purge_rejected_assets.ps1",
]
const ASSET_LIBRARY_REPORT_ROOT: String = "build\\asset_library"
const OBSOLETE_ASSET_LIBRARY_REPORT_ROOTS: Array[String] = [
	"asset_library\\reports",
	"features\\asset_library\\resources\\reports",
]
const SHARED_TEXT_RESOURCE_EXTENSIONS: Array[String] = [
	"cfg",
	"csv",
	"gd",
	"gdshader",
	"import",
	"json",
	"res",
	"tres",
	"tscn",
]


# --- 私有变量 ---

var _platform_static_member_regex_cache: Dictionary = {}


# --- 测试用例 ---

func test_global_gf_access_is_limited_to_composition_root() -> void:
	var issues: Array[String] = []
	for path: String in _collect_script_paths(GLOBAL_GF_ACCESS_SCAN_ROOTS):
		if GLOBAL_GF_ACCESS_ALLOWLIST.has(path):
			continue
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var code: String = _get_code_line(_get_packed_line(lines, line_index))
			if _contains_global_gf_access(code):
				_append_string(issues, "%s:%d 不应直接访问全局 Gf/GFAutoload。" % [path, line_index + 1])

	assert_true(
		issues.is_empty(),
		"全局 GF 架构访问只允许出现在应用启动组合根和唯一 verification harness；其他节点和 Module 应使用 GF 注入或 Controller 上下文：\n%s"
		% _join_lines(issues)
	)


func test_direct_time_and_random_access_is_limited_to_adapters_and_tooling() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		if DIRECT_TIME_AND_RANDOM_ALLOWLIST.has(path):
			continue
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var code: String = _get_code_line(_get_packed_line(lines, line_index))
			if _contains_direct_time_or_random_access(code):
				_append_string(issues, "%s:%d 不应直接访问 Time 或原生随机源。" % [path, line_index + 1])

	assert_true(
		issues.is_empty(),
		"运行时系统时间应集中在 GameClockUtility，随机流应由 GFSeedUtility 管理；仅启动组合根和离线素材工具可直接访问底层 API：\n%s"
		% _join_lines(issues)
	)


func test_project_does_not_call_deprecated_gf_methods() -> void:
	var deprecated_methods: Array[Dictionary] = _collect_deprecated_gf_methods()
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if source.is_empty():
			_append_string(issues, "%s 无法读取或为空。" % path)
			continue
		for method_record: Dictionary in deprecated_methods:
			issues.append_array(_collect_deprecated_call_issues(path, source, method_record))

	assert_true(
		issues.is_empty(),
		"项目不得调用当前 GF 源码标记为 @deprecated 的 API；升级 GF 后本测试会自动读取新声明：\n%s"
		% _join_lines(issues)
	)


func test_runtime_sources_do_not_depend_on_gf_editor_api() -> void:
	var editor_api_classes: Array[String] = _collect_gf_editor_api_classes()
	var source_domains: Array[Dictionary] = _collect_project_source_domains()
	var issues: Array[String] = []
	if editor_api_classes.is_empty():
		_append_string(issues, "GF API index 未提供 editor_api 类目录。")
	if source_domains.is_empty():
		_append_string(issues, "项目契约未提供 source_domains。")

	for path: String in _collect_project_script_paths():
		if _resolve_source_domain(path, source_domains) in ["tool", "editor", "test"]:
			continue
		var source: String = _read_text(path)
		var executable_source: String = _mask_gdscript_comments_and_strings(source)
		for class_name_value: String in editor_api_classes:
			if not executable_source.contains(class_name_value):
				continue
			for line_number: int in _collect_symbol_lines(executable_source, class_name_value):
				_append_string(
					issues,
					"%s:%d runtime source 不应依赖 GF editor_api %s。" % [
						path,
						line_number,
						class_name_value,
					]
				)

	assert_true(
		issues.is_empty(),
		"GF editor API 只允许位于显式 tool source domain，不能进入玩家运行时依赖链：\n%s"
		% _join_lines(issues)
	)


func test_editor_api_guard_uses_deepest_contract_source_domain() -> void:
	var domains: Array[Dictionary] = [
		{"root": "res://features", "domain": "runtime"},
		{"root": "res://features/custom_authoring", "domain": "tool"},
	]
	assert_true(
		_resolve_source_domain("res://features/custom_authoring/editor.gd", domains) == "tool",
		"未命名为 tools 的契约 tool root 也必须按 deepest-root 获得工具域。"
	)
	assert_true(
		_resolve_source_domain("res://features/gameplay/tools/runtime.gd", domains) == "runtime",
		"路径名包含 tools 不得自动豁免 runtime source。"
	)


func test_editor_api_guard_only_scans_executable_references() -> void:
	var source: String = (
		"# GFEditorFixture comment\n"
		+ "var message: String = \"GFEditorFixture string\"\n"
		+ "var multiline: String = \"\"\"GFEditorFixture\ncontinued\"\"\"\n"
		+ "var utility: GFEditorFixture\n"
	)
	var lines: Array[int] = _collect_executable_symbol_lines(source, "GFEditorFixture")
	assert_true(lines == [5], "注释和字符串不得误报，实际可执行类型引用必须命中精确行。")


func test_gf_modules_only_resolve_cross_module_dependencies_in_ready() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if not _is_gf_module_source(source):
			continue
		var functions: Dictionary = _parse_top_level_functions(source)
		for lifecycle_method: String in EARLY_LIFECYCLE_METHODS:
			if not functions.has(lifecycle_method):
				continue
			var dependency_chain: Array[String] = _find_cross_module_dependency_chain(
				functions,
				lifecycle_method,
				{},
				[]
			)
			if dependency_chain.is_empty():
				continue
			var function_record: Dictionary = _get_dictionary(functions, lifecycle_method)
			_append_string(issues, "%s:%d %s() 通过 %s 提前获取跨模块依赖。" % [
				path,
				GFVariantData.get_option_int(function_record, "line", 1),
				lifecycle_method,
				" -> ".join(dependency_chain),
			])

	assert_true(
		issues.is_empty(),
		"GF init()/async_init() 只能初始化模块自身；跨模块 Model/System/Utility 必须在 ready() 获取：\n%s"
		% _join_lines(issues)
	)


func test_boot_enables_strict_architecture_dependency_contracts() -> void:
	var source: String = _read_text(BOOT_RUNTIME_SCRIPT_PATH)

	assert_true(source.contains("Gf.create_architecture()"), "Boot 应显式配置 GF 根架构。")
	assert_true(source.contains("architecture.strict_dependency_lookup = true"), "根架构必须禁用隐式父级依赖回退。")
	assert_false(
		source.contains("fail_on_missing_declared_dependencies"),
		"GF 11 已将声明依赖失败纳入生命周期计划，不得继续写入已移除开关。"
	)
	assert_true(source.contains("architecture_ready: bool = await Gf.init()"), "Boot 必须检查 GF 严格初始化结果。")
	assert_true(
		source.contains("themes_ready: bool = await _prepare_initial_themes()"),
		"Boot 必须等待 GF 主题资源会话完成后再进入首场景。"
	)


func test_responsive_layouts_consume_gf_platform_capabilities() -> void:
	var issues: Array[String] = []
	for path: String in PLATFORM_CONTEXT_CONSUMER_PATHS:
		var source: String = _read_text(path)
		var probes_host_directly: bool = (
			source.contains("OS.has_feature")
			or source.contains("DisplayServer.is_touchscreen_available")
		)
		if probes_host_directly:
			_append_string(issues, "%s 不得自行探测宿主平台或触摸设备。" % path)
		if not source.contains("get_utility(GamePlatformUtility"):
			_append_string(issues, "%s 必须从架构获取 GamePlatformUtility。" % path)
		if not source.contains("GamePlatformUtility.CAPABILITY_TOUCH"):
			_append_string(issues, "%s 必须通过 GF 平台能力选择触屏布局。" % path)

	assert_true(
		issues.is_empty(),
		"响应式布局只消费 GFPlatformRuntime 投影，宿主探测必须集中在平台 Adapter：\n%s"
		% _join_lines(issues)
	)


func test_production_code_does_not_probe_host_platform_outside_boundary() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		issues.append_array(_collect_direct_platform_probe_issues(path, _read_text(path)))

	assert_true(
		issues.is_empty(),
		"OS/DisplayServer 宿主探测必须由 LocalPlatformAdapter 投影；"
		+ "Composition Root 与开发诊断只保留精确声明的调用，DisplayServer 类型/枚举不算探测：\n"
		+ _join_lines(issues)
	)


func test_main_menu_preserves_projected_first_draw_wait() -> void:
	var source: String = _read_text(MAIN_MENU_SCRIPT_PATH)

	assert_true(
		source.contains("var platform_utility: GamePlatformUtility = _get_platform_utility()"),
		"MainMenu 应从所属架构获取 GamePlatformUtility。"
	)
	assert_true(
		source.contains("platform_utility.is_headless_runtime()"),
		"MainMenu 应消费平台上下文投影的 headless 事实。"
	)
	assert_true(
		source.contains("await get_tree().process_frame"),
		"headless 或平台上下文缺失时必须保留 process_frame 等待。"
	)
	assert_true(
		source.contains("await RenderingServer.frame_post_draw"),
		"图形运行时必须保留 frame_post_draw 等待。"
	)


func test_platform_probe_guard_rejects_feature_fixture() -> void:
	var fixture_source: String = _read_text(PLATFORM_PROBE_REJECTION_FIXTURE_PATH)
	var issues: Array[String] = _collect_direct_platform_probe_issues(
		PLATFORM_PROBE_REJECTION_VIRTUAL_PATH,
		fixture_source
	)

	assert_false(fixture_source.is_empty(), "平台探测拒绝 fixture 必须可读取。")
	assert_true(
		issues.size() == 2,
		"Feature 中的 OS 与 DisplayServer 探测都必须被拒绝。"
	)
	assert_true(_join_lines(issues).contains(PLATFORM_PROBE_REJECTION_VIRTUAL_PATH))


func test_platform_probe_guard_keeps_documented_exceptions_narrow() -> void:
	var composition_source: String = (
		"func select_build() -> bool:\n"
		+ "\treturn OS.has_feature(\"with_dev_tools\") "
		+ "and DisplayServer.get_name() == \"headless\"\n"
	)
	assert_true(
		_collect_direct_platform_probe_issues(
			"res://app/scripts/boot.gd",
			composition_source
		).is_empty(),
		"Composition Root 的已声明构建/headless 检查应保留。"
	)
	var misuse_fixture: String = _read_text(PLATFORM_PROBE_EXCEPTION_MISUSE_FIXTURE_PATH)
	assert_false(misuse_fixture.is_empty(), "平台例外误用 fixture 必须可读取。")
	assert_true(
		_collect_direct_platform_probe_issues(
			"res://app/scripts/boot.gd",
			misuse_fixture
		).size() == 3,
		"同一 Composition Root 文件中，错误 feature 参数、非 headless 比较与裸名称读取都必须被拒绝。"
	)
	assert_true(
		_collect_direct_platform_probe_issues(
			"res://features/diagnostics/scripts/utilities/test_tool_utility.gd",
			"func probe_size() -> Vector2i:\n\treturn DisplayServer.window_get_size()\n"
		).size() == 1,
		"开发诊断不应获得任意 DisplayServer 调用权限。"
	)
	var enum_only_source: String = (
		"func default_mode() -> DisplayServer.WindowMode:\n"
		+ "\treturn DisplayServer.WINDOW_MODE_WINDOWED\n"
	)
	assert_true(
		_collect_direct_platform_probe_issues(
			"res://features/settings/scripts/menus/enum_fixture.gd",
			enum_only_source
		).is_empty(),
		"DisplayServer 类型与枚举只表达 GFDisplaySettingsUtility 的参数，不是宿主探测。"
	)


func test_gf_modules_declare_static_cross_module_dependencies() -> void:
	var issues: Array[String] = []
	for path: String in _collect_project_script_paths():
		var source: String = _read_text(path)
		if not _is_gf_module_source(source):
			continue
		var functions: Dictionary = _parse_top_level_functions(source)
		var generic_declarations: String = _get_function_body(functions, "get_required_dependencies")
		for contract: Dictionary in DECLARED_DEPENDENCY_CONTRACTS:
			var kind: String = GFVariantData.get_option_string(contract, "kind")
			var lookup_method: String = GFVariantData.get_option_string(contract, "lookup_method")
			var hook_method: String = GFVariantData.get_option_string(contract, "hook_method")
			var declarations: String = "%s\n%s" % [
				generic_declarations,
				_get_function_body(functions, hook_method),
			]
			for dependency_symbol: String in _collect_static_dependency_symbols(source, lookup_method):
				var dependency_id: String = "%s:%s" % [kind, dependency_symbol]
				if _regex_matches(declarations, "\\b%s\\b" % dependency_symbol):
					continue
				_append_string(issues, "%s 未通过 %s() 声明 %s。" % [
					path,
					hook_method,
					dependency_id,
				])

	assert_true(
		issues.is_empty(),
		"项目 GF Module 的静态跨模块查找必须进入 GF 声明式依赖图；可选依赖必须使用本架构 local lookup：\n%s"
		% _join_lines(issues)
	)


func test_asset_library_tools_use_ignored_generated_report_root() -> void:
	var issues: Array[String] = []
	for path: String in ASSET_LIBRARY_TOOL_PATHS:
		var source: String = _read_text(path)
		if source.is_empty():
			_append_string(issues, "%s 无法读取或为空。" % path)
			continue
		var normalized_source: String = source.replace("/", "\\")
		if not normalized_source.contains(ASSET_LIBRARY_REPORT_ROOT):
			_append_string(issues, "%s 未使用忽略提交的素材报告目录。" % path)
		for obsolete_root: String in OBSOLETE_ASSET_LIBRARY_REPORT_ROOTS:
			if normalized_source.contains('"%s' % obsolete_root):
				_append_string(issues, "%s 仍引用已废弃的素材报告目录：%s。" % [
					path,
					obsolete_root,
				])

	assert_true(
		issues.is_empty(),
		"素材工具报告必须写入 build/asset_library 且不进入源码资源区：\n%s"
		% _join_lines(issues)
	)


func test_shared_does_not_depend_on_features() -> void:
	var feature_class_owners: Dictionary = _collect_feature_class_owners()
	var scan_report: Dictionary = GFPathEnumerationTools.scan_files("res://shared", {
		"recursive": true,
		"include_hidden": false,
		"extensions": PackedStringArray(SHARED_TEXT_RESOURCE_EXTENSIONS),
		"max_file_count": 5000,
		"sort": true,
	})
	var issues: Array[String] = []
	if not GFVariantData.get_option_bool(scan_report, "ok"):
		_append_string(issues, "GFPathEnumerationTools 无法完成 shared 依赖扫描。")
	if GFVariantData.get_option_bool(scan_report, "truncated"):
		_append_string(issues, "shared 依赖扫描达到安全上限，结果不完整。")

	for path: String in GFVariantData.get_option_packed_string_array(scan_report, "paths"):
		var source: String = _read_text(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var line: String = _get_packed_line(lines, line_index)
			var code: String = _get_code_line(line) if path.ends_with(".gd") else line
			if code.contains("res://features/"):
				_append_string(issues, "%s:%d shared 不得引用 Feature 资源路径。" % [
					path,
					line_index + 1,
				])
			if not path.ends_with(".gd"):
				continue
			for class_name_value: Variant in feature_class_owners.keys():
				var feature_class_name: String = GFVariantData.to_text(class_name_value)
				if not _regex_matches(code, "\\b%s\\b" % feature_class_name):
					continue
				_append_string(issues, "%s:%d shared 不得依赖 Feature 类型 %s（声明于 %s）。" % [
					path,
					line_index + 1,
					feature_class_name,
					GFVariantData.get_option_string(feature_class_owners, feature_class_name),
				])

	assert_true(
		issues.is_empty(),
		"Feature-Cohesive 依赖方向要求 shared 不得反向依赖 features：\n%s" % _join_lines(issues)
	)


# --- 私有/辅助方法 ---

func _collect_project_script_paths() -> Array[String]:
	return _collect_script_paths(PROJECT_SOURCE_ROOTS)


func _collect_script_paths(roots: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for root_path: String in roots:
		var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths(root_path, {
			"recursive": true,
			"include_addons": false,
			"include_hidden": false,
			"excluded_paths": SOURCE_EXCLUDED_ROOTS,
			"max_scan_depth": 64,
			"max_resource_paths": 5000,
		})
		for path: String in paths:
			if not _is_excluded_path(path):
				result.append(path)
	result.sort()
	return result


func _collect_feature_class_owners() -> Dictionary:
	var result: Dictionary = {}
	var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths(
		VerificationResourcePath.FEATURES_ROOT,
		{
		"recursive": true,
		"include_addons": false,
		"include_hidden": false,
		"excluded_paths": SOURCE_EXCLUDED_ROOTS,
		"max_scan_depth": 64,
		"max_resource_paths": 5000,
		}
	)
	for path: String in paths:
		if _is_excluded_path(path):
			continue
		var declared_class_name: String = _parse_class_name(_read_text(path))
		if not declared_class_name.is_empty():
			result[declared_class_name] = path
	return result


func _collect_direct_platform_probe_issues(path: String, source: String) -> Array[String]:
	var issues: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var code: String = _get_code_line(_get_packed_line(lines, line_index))
		if not code.contains("OS") and not code.contains("DisplayServer"):
			continue
		if PLATFORM_PROBE_OWNER_PATHS.has(path):
			continue
		var unapproved_code: String = _remove_allowed_platform_probe_fragments(path, code)
		var os_members: Array[String] = _collect_static_members(unapproved_code, "OS")
		var display_server_members: Array[String] = _collect_direct_display_server_members(
			unapproved_code
		)
		if os_members.is_empty() and display_server_members.is_empty():
			continue
		_append_string(issues, "%s:%d 直接探测了 OS/DisplayServer 宿主事实。" % [
			path,
			line_index + 1,
		])
	return issues


func _remove_allowed_platform_probe_fragments(path: String, code: String) -> String:
	if not PLATFORM_PROBE_EXCEPTIONS.has(path):
		return code
	var exception: Dictionary = _get_dictionary(PLATFORM_PROBE_EXCEPTIONS, path)
	var result: String = code
	for fragment: String in _get_string_array(exception, "allowed_fragments"):
		result = result.replace(fragment, "")
	return result


func _collect_static_members(
	code: String,
	owner_name: String
) -> Array[String]:
	var result: Array[String] = []
	var member_regex: RegEx = _get_platform_static_member_regex(owner_name)
	if member_regex == null:
		return result
	for match_value: RegExMatch in member_regex.search_all(code):
		var member_name: String = match_value.get_string(1)
		if not member_name.is_empty() and not result.has(member_name):
			result.append(member_name)
	return result


func _get_platform_static_member_regex(owner_name: String) -> RegEx:
	var cached_value: Variant = _platform_static_member_regex_cache.get(owner_name)
	if cached_value is RegEx:
		return cached_value
	var pattern: String = "\\b%s\\s*\\.\\s*([A-Za-z_][A-Za-z0-9_]*)" % owner_name
	var member_regex: RegEx = _compile_regex(pattern)
	if member_regex != null:
		_platform_static_member_regex_cache[owner_name] = member_regex
	return member_regex


func _collect_direct_display_server_members(code: String) -> Array[String]:
	var result: Array[String] = []
	for member_name: String in _collect_static_members(code, "DisplayServer"):
		if DISPLAY_SERVER_ENUM_ONLY_MEMBERS.has(member_name):
			continue
		result.append(member_name)
	return result


func _collect_deprecated_gf_methods() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var paths: PackedStringArray = GFScriptStructureTools.scan_script_paths("res://addons/gf", {
		"recursive": true,
		"include_addons": true,
		"include_hidden": false,
		"max_scan_depth": 64,
		"max_resource_paths": 10000,
	})
	for path: String in paths:
		var source: String = _read_text(path)
		if not source.contains("@deprecated"):
			continue
		var owner_class: String = _parse_class_name(source)
		if owner_class.is_empty():
			continue
		var pending_deprecation: String = ""
		var lines: PackedStringArray = source.split("\n")
		for line_index: int in range(lines.size()):
			var stripped: String = _get_packed_line(lines, line_index).strip_edges()
			if stripped.begins_with("## @deprecated"):
				pending_deprecation = stripped.trim_prefix("## ")
				continue
			if pending_deprecation.is_empty() or stripped.is_empty() or stripped.begins_with("##"):
				continue
			var method_name: String = _parse_function_name(stripped)
			if not method_name.is_empty():
				result.append({
					"owner_class": owner_class,
					"method_name": method_name,
					"framework_path": path,
					"framework_line": line_index + 1,
					"deprecation": pending_deprecation,
				})
			pending_deprecation = ""
	return result


func _collect_gf_editor_api_classes() -> Array[String]:
	var result: Array[String] = []
	var parsed: Variant = JSON.parse_string(_read_text(GF_API_INDEX_PATH))
	if not parsed is Dictionary:
		return result
	var api_index: Dictionary = parsed
	var classes: Dictionary = _get_dictionary(api_index, "classes")
	for class_name_value: Variant in classes.keys():
		var class_name_text: String = GFVariantData.to_text(class_name_value)
		var class_record: Dictionary = _get_dictionary(classes, class_name_value)
		if GFVariantData.get_option_string(class_record, "category") != "editor_api":
			continue
		if not class_name_text.is_empty():
			result.append(class_name_text)
	result.sort()
	return result


func _collect_project_source_domains() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(_read_text(PROJECT_CONTRACT_PATH))
	if not parsed is Dictionary:
		return result
	var contract: Dictionary = parsed
	var architecture: Dictionary = _get_dictionary(contract, "architecture")
	for record_value: Variant in GFVariantData.get_option_array(architecture, "source_domains"):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var root: String = GFVariantData.get_option_string(record, "root").trim_suffix("/")
		var domain: String = GFVariantData.get_option_string(record, "domain")
		if root.is_empty() or domain.is_empty():
			continue
		result.append({"root": root, "domain": domain})
	return result


func _resolve_source_domain(path: String, source_domains: Array[Dictionary]) -> String:
	var resolved_domain: String = "runtime"
	var resolved_root_length: int = -1
	for record: Dictionary in source_domains:
		var root: String = GFVariantData.get_option_string(record, "root").trim_suffix("/")
		if path != root and not path.begins_with(root + "/"):
			continue
		if root.length() <= resolved_root_length:
			continue
		resolved_root_length = root.length()
		resolved_domain = GFVariantData.get_option_string(record, "domain", "runtime")
	return resolved_domain


func _collect_executable_symbol_lines(source: String, symbol: String) -> Array[int]:
	var executable_source: String = _mask_gdscript_comments_and_strings(source)
	return _collect_symbol_lines(executable_source, symbol)


func _collect_symbol_lines(executable_source: String, symbol: String) -> Array[int]:
	var result: Array[int] = []
	var lines: PackedStringArray = executable_source.split("\n")
	for line_index: int in range(lines.size()):
		if _regex_matches(_get_packed_line(lines, line_index), "\\b%s\\b" % symbol):
			result.append(line_index + 1)
	return result


func _mask_gdscript_comments_and_strings(source: String) -> String:
	var result: Array[String] = []
	var index: int = 0
	var quote: String = ""
	var triple_quoted: bool = false
	var escaped: bool = false
	var in_comment: bool = false
	while index < source.length():
		var character: String = source[index]
		if in_comment:
			if character == "\n":
				in_comment = false
				result.append("\n")
			else:
				result.append(" ")
			index += 1
			continue
		if not quote.is_empty():
			if character == "\n":
				result.append("\n")
			else:
				result.append(" ")
			if triple_quoted and source.substr(index, 3) == quote.repeat(3):
				result.append("  ")
				index += 3
				quote = ""
				triple_quoted = false
				continue
			if not triple_quoted and not escaped and character == quote:
				quote = ""
			escaped = not escaped and character == "\\"
			if character != "\\":
				escaped = false
			index += 1
			continue
		if character == "#":
			in_comment = true
			result.append(" ")
			index += 1
			continue
		if character == "\"" or character == "'":
			quote = character
			triple_quoted = source.substr(index, 3) == character.repeat(3)
			result.append("   " if triple_quoted else " ")
			index += 3 if triple_quoted else 1
			continue
		result.append(character)
		index += 1
	return "".join(result)


func _collect_deprecated_call_issues(
	path: String,
	source: String,
	method_record: Dictionary
) -> Array[String]:
	var issues: Array[String] = []
	var owner_class: String = GFVariantData.get_option_string(method_record, "owner_class")
	var method_name: String = GFVariantData.get_option_string(method_record, "method_name")
	if owner_class.is_empty() or method_name.is_empty():
		return issues

	var typed_receivers: Array[String] = _collect_typed_identifiers(source, owner_class)
	var owner_returning_functions: Array[String] = _collect_owner_returning_functions(source, owner_class)
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var code: String = _get_code_line(_get_packed_line(lines, line_index))
		if code.is_empty():
			continue
		if not _line_calls_deprecated_method(
			code,
			owner_class,
			method_name,
			typed_receivers,
			owner_returning_functions
		):
			continue
		_append_string(issues, "%s:%d 调用了 %s.%s()；%s" % [
			path,
			line_index + 1,
			owner_class,
			method_name,
			GFVariantData.get_option_string(method_record, "deprecation"),
		])
	return issues


func _collect_typed_identifiers(source: String, owner_class: String) -> Array[String]:
	var result: Array[String] = []
	var type_regex: RegEx = _compile_regex(
		"\\b([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*%s\\b" % owner_class
	)
	if type_regex == null:
		return result
	for match_value: RegExMatch in type_regex.search_all(source):
		var identifier: String = match_value.get_string(1)
		if not identifier.is_empty() and not result.has(identifier):
			result.append(identifier)
	return result


func _collect_owner_returning_functions(source: String, owner_class: String) -> Array[String]:
	var result: Array[String] = []
	var return_regex: RegEx = _compile_regex(
		"(?m)^(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)[^\\n]*->\\s*%s\\b" % owner_class
	)
	if return_regex == null:
		return result
	for match_value: RegExMatch in return_regex.search_all(source):
		var function_name: String = match_value.get_string(1)
		if not function_name.is_empty() and not result.has(function_name):
			result.append(function_name)
	return result


func _line_calls_deprecated_method(
	code: String,
	owner_class: String,
	method_name: String,
	typed_receivers: Array[String],
	owner_returning_functions: Array[String]
) -> bool:
	for receiver: String in typed_receivers:
		if _regex_matches(code, "\\b%s\\s*\\.\\s*%s\\s*\\(" % [receiver, method_name]):
			return true

	for function_name: String in owner_returning_functions:
		if _regex_matches(
			code,
			"\\b%s\\s*\\([^)]*\\)\\s*\\.\\s*%s\\s*\\(" % [function_name, method_name]
		):
			return true

	if _regex_matches(code, "\\b%s\\s*\\.\\s*%s\\s*\\(" % [owner_class, method_name]):
		return true
	return _regex_matches(
		code,
		"\\bget_utility\\s*\\(\\s*%s\\s*\\)\\s*\\.\\s*%s\\s*\\(" % [owner_class, method_name]
	)


func _parse_top_level_functions(source: String) -> Dictionary:
	var result: Dictionary = {}
	var current_function: String = ""
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).trim_suffix("\r")
		var stripped: String = line.strip_edges()
		if line.begins_with("func "):
			current_function = _parse_function_name(stripped)
			if not current_function.is_empty():
				result[current_function] = {
					"line": line_index + 1,
					"body_lines": [],
				}
			continue

		if current_function.is_empty():
			continue
		if not stripped.is_empty() and not line.begins_with("\t") and not line.begins_with(" "):
			current_function = ""
			continue

		var record: Dictionary = _get_dictionary(result, current_function)
		var body_lines: Array[String] = _get_string_array(record, "body_lines")
		body_lines.append(line)
		record["body_lines"] = body_lines
		result[current_function] = record
	return result


func _find_cross_module_dependency_chain(
	functions: Dictionary,
	function_name: String,
	visited: Dictionary,
	chain_prefix: Array[String]
) -> Array[String]:
	if visited.has(function_name) or not functions.has(function_name):
		return []
	visited[function_name] = true

	var chain: Array[String] = chain_prefix.duplicate()
	chain.append(function_name)
	var function_record: Dictionary = _get_dictionary(functions, function_name)
	var body_lines: Array[String] = _get_string_array(function_record, "body_lines")
	var body: String = _join_lines(body_lines)
	if _contains_cross_module_lookup(body):
		return chain

	for called_function: String in _collect_defined_function_calls(body, functions):
		var nested_chain: Array[String] = _find_cross_module_dependency_chain(
			functions,
			called_function,
			visited,
			chain
		)
		if not nested_chain.is_empty():
			return nested_chain
	return []


func _collect_defined_function_calls(body: String, functions: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var call_regex: RegEx = _compile_regex("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	if call_regex == null:
		return result
	for match_value: RegExMatch in call_regex.search_all(body):
		var function_name: String = match_value.get_string(1)
		if functions.has(function_name) and not result.has(function_name):
			result.append(function_name)
	return result


func _contains_cross_module_lookup(body: String) -> bool:
	for method_name: String in CROSS_MODULE_LOOKUP_METHODS:
		if _regex_matches(body, "\\b%s\\s*\\(" % method_name):
			return true
	return false


func _get_function_body(functions: Dictionary, function_name: String) -> String:
	if not functions.has(function_name):
		return ""
	var function_record: Dictionary = _get_dictionary(functions, function_name)
	return _join_lines(_get_string_array(function_record, "body_lines"))


func _collect_static_dependency_symbols(source: String, lookup_method: String) -> Array[String]:
	var result: Array[String] = []
	var regex: RegEx = _compile_regex(
		"\\b%s\\s*\\(\\s*([A-Za-z_][A-Za-z0-9_]*)" % lookup_method
	)
	if regex == null:
		return result
	for match_value: RegExMatch in regex.search_all(source):
		var symbol: String = match_value.get_string(1)
		if not symbol.is_empty() and not result.has(symbol):
			result.append(symbol)
	result.sort()
	return result


func _contains_global_gf_access(code: String) -> bool:
	return (
		_regex_matches(code, "(?:^|[^A-Za-z0-9_])Gf\\s*\\.")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])GFAutoload\\s*\\.")
		or code.contains("\"Gf\"")
	)


func _contains_direct_time_or_random_access(code: String) -> bool:
	return (
		_regex_matches(code, "(?:^|[^A-Za-z0-9_])Time\\s*\\.")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])RandomNumberGenerator\\b")
		or _regex_matches(code, "(?:^|[^A-Za-z0-9_])(?:randf|randf_range|randfn|randi|randi_range|randomize|seed)\\s*\\(")
		or _regex_matches(code, "\\.(?:pick_random|shuffle)\\s*\\(")
	)


func _is_gf_module_source(source: String) -> bool:
	for base_path: String in GF_MODULE_BASE_PATHS:
		if source.contains("extends \"%s\"" % base_path):
			return true
	return _regex_matches(source, "(?m)^extends\\s+GF(?:Model|System|Utility)\\s*$")


func _parse_class_name(source: String) -> String:
	var class_regex: RegEx = _compile_regex(
		"(?m)^class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)[ \\t]*\\r?$"
	)
	if class_regex == null:
		return ""
	var match_value: RegExMatch = class_regex.search(source)
	return match_value.get_string(1) if match_value != null else ""


func _parse_function_name(stripped_line: String) -> String:
	var signature: String = stripped_line
	if signature.begins_with("static func "):
		signature = signature.trim_prefix("static ")
	if not signature.begins_with("func "):
		return ""
	var name_end: int = signature.find("(")
	if name_end < 0:
		return ""
	return signature.substr(5, name_end - 5).strip_edges()


func _get_code_line(line: String) -> String:
	var stripped: String = line.strip_edges()
	if stripped.is_empty() or stripped.begins_with("#"):
		return ""
	var comment_index: int = line.find("#")
	if comment_index >= 0:
		return line.left(comment_index)
	return line


func _is_excluded_path(path: String) -> bool:
	for excluded_root: String in SOURCE_EXCLUDED_ROOTS:
		if path == excluded_root or path.begins_with(excluded_root + "/"):
			return true
	return false


func _compile_regex(pattern: String) -> RegEx:
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile(pattern)
	if compile_error != OK:
		return null
	return regex


func _regex_matches(text: String, pattern: String) -> bool:
	var regex: RegEx = _compile_regex(pattern)
	return regex != null and regex.search(text) != null


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _get_dictionary(source: Dictionary, key: Variant) -> Dictionary:
	return GFVariantData.as_dictionary(GFVariantData.get_option_value(source, key))


func _get_string_array(source: Dictionary, key: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in GFVariantData.get_option_array(source, key):
		if value is String:
			result.append(value)
	return result


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var _append_result: bool = packed.append(line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)
