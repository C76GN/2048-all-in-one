## 验证微信小游戏冒烟导出器保持可复现模板、包体预算和隐私边界。
extends GutTest


# --- 常量 ---

const _TOOL_PATH: String = "res://tools/export_wechat_minigame_smoke.ps1"
const _RELEASE_TOOL_PATH: String = "res://tools/export_wechat_minigame_release.ps1"
const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _PROJECT_CONFIG_PATH: String = "res://project.godot"
const _SMOKE_FONT_PATH: String = "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf"
const _SMOKE_FONT_IMPORT_PATH: String = (
	"res://shared/assets/fonts/wechat_smoke_sans_subset.ttf.import"
)
const _SMOKE_FONT_RESOURCE_PATH: String = (
	"res://shared/assets/fonts/ui_sans_wechat_smoke.tres"
)
const _RELEASE_FONT_PATH: String = (
	"res://shared/assets/fonts/wechat_release_sans_subset.ttf"
)
const _RELEASE_FONT_IMPORT_PATH: String = (
	"res://shared/assets/fonts/wechat_release_sans_subset.ttf.import"
)
const _RELEASE_FONT_RESOURCE_PATH: String = (
	"res://shared/assets/fonts/ui_sans_wechat_release.tres"
)
const _RELEASE_COVERAGE_PATH: String = (
	"res://shared/assets/fonts/wechat_release_font_coverage.txt"
)
const _RELEASE_COVERAGE_MANIFEST_PATH: String = (
	"res://shared/assets/fonts/wechat_release_font_coverage.json"
)
const _FONT_LICENSE_PATH: String = "res://shared/assets/fonts/noto_sans_sc_ofl.txt"
const _EXPORT_PLUGIN_CONFIG_PATH: String = (
	"res://addons/wechat_minigame_smoke_export/plugin.cfg"
)
const _EXPORT_PLUGIN_PATH: String = (
	"res://addons/wechat_minigame_smoke_export/wechat_minigame_smoke_export_plugin.gd"
)
const _CHUNK_LOADER_SOURCE_PATH: String = (
	"res://tools/wechat_minigame/chunked_file_loader.js"
)
const _WXMEMFS_RENAME_PATCH_PATH: String = (
	"res://tools/wechat_minigame/wxmemfs_rename_patch.ps1"
)
const _SMOKE_FONT_SHA256: String = (
	"38bdd2457e67c2c1721f5734fee67059bc1b961563afb4f3e0f8b8c8b8049c22"
)
const _SOURCE_FONT_SHA256: String = (
	"763146584cf0710223441356b4395e279021b0806c196614377a7a0174ae074a"
)
const _FONT_LICENSE_SHA256: String = (
	"6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
)
const _WEB_PRESET_NAME: String = "Web Compatibility Smoke"
const _RELEASE_PRESET_NAME: String = "Web Compatibility WeChat Release"
const _VISIBLE_TEXT_SOURCE_PATHS: PackedStringArray = [
	"res://app/scripts/boot.gd",
	"res://app/scripts/boot_runtime.gd",
	"res://app/scenes/boot.tscn",
	"res://features/platform_runtime/scripts/controllers/platform_smoke_controller.gd",
]
const _REQUIRED_SMOKE_TEXTS: PackedStringArray = [
	"准备启动",
	"跨平台兼容性冒烟",
	"用于 Web / 微信小游戏适配前验证，不代表微信 SDK 已接入。",
	"运行平台 Compatibility 渲染器 能力契约",
	"等待后台 / 前台 / 窗口事件 生命周期",
	"拖动、滚轮缩放或双指缩放以验证输入 指针与触摸",
	"尚未执行持久化测试 写入并回读 清除冒烟数据",
	"微信真机必须加入合法域名 尚未发起请求 发起 GET 请求",
	"背景正在运行已审批的半色调 Shader；音频必须由用户操作触发。",
	"播放已审批 UI 音效 素材与音频",
	"未注册 平台上下文不可用 目标平台要求 手势结束",
	"写入失败：持久化往返；跨启动计数=通过失败 冒烟数据已清除",
	"仅允许 请求未能入队 请求中… 响应对象为空",
	"音频或素材库 已审批音频资源键解析失败",
]
const _RELEASE_RUNTIME_TEXT_EXTENSIONS: PackedStringArray = [
	"gd",
	"tscn",
	"tres",
	"cfg",
	"json",
]
const _RELEASE_AUDIT_EXCLUDED_ROOTS: PackedStringArray = [
	"tests",
	"tools",
	"build",
]


# --- 测试用例 ---

func test_export_tool_pins_the_verified_godot_4_7_template() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$TemplateRelease = "4.7"'))
	assert_true(source.contains('$TemplateExpectedBytes = 11763895'))
	assert_true(source.contains(
		"AE5BDEB5BA1CE9712D4EFC35D337CB5ECBEF3AD5BFB0F7D06AE9CB662C1F2D71"
	))
	assert_true(source.contains("godothub/godot-minigame/releases/download/4.7"))


func test_export_tool_rewrites_the_pack_and_rejects_browser_artifacts() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('"--export-pack"'))
	assert_true(source.contains('$PackFileName = "2048-all-in-one.bin"'))
	assert_true(source.contains("/game_data/$PackFileName"))
	assert_true(source.contains("Move-Item -LiteralPath $temporaryPackPath"))
	assert_true(source.contains("'(?i)\\.(?:pck|html|wasm)$'"))
	assert_true(source.contains("scope = $ReportScope"))


func test_export_tool_installs_the_canonical_chunked_large_file_reader() -> void:
	var source: String = _read_tool_source()
	assert_true(FileAccess.file_exists(_CHUNK_LOADER_SOURCE_PATH))
	assert_true(source.contains('$ChunkBytes = 4194304'))
	assert_true(source.contains('"tools\\wechat_minigame\\chunked_file_loader.js"'))
	assert_true(source.contains('"engine\\wechat-chunked-file-loader.js"'))
	assert_true(source.contains("chunkedResourceBytes"))
	assert_true(source.contains("installChunkedLocalFetch"))
	assert_true(source.contains('strategy = "async_position_length_chunked"'))
	var pack_index: int = source.find("Invoke-GodotPackExport -GodotPath")
	var loader_write_index: int = source.find(
		"Write-Utf8Text -Path $engineGamePath",
		pack_index + 1
	)
	assert_true(pack_index >= 0 and loader_write_index > pack_index)


func test_export_tool_patches_the_pinned_wxmemfs_rename_fail_closed() -> void:
	var source: String = _read_tool_source()
	assert_true(FileAccess.file_exists(_WXMEMFS_RENAME_PATCH_PATH))
	assert_true(source.contains(
		"CC396C67F410502C958185003EA72F5F67E5ACBCD040774D1AAF5B9622491B15"
	))
	assert_true(source.contains(
		"FD91EA35F0515360BE35AE6FD2425D102CBAF17F30F5B7CCB8688AF635CE3638"
	))
	assert_true(source.contains("ConvertTo-WeChatWxMemFsRenamePatchedSource"))
	assert_true(source.contains('strategy = "physical_rename_before_memfs_mutation"'))
	assert_true(source.contains('patch = "2048-wechat-wxmemfs-rename-v1"'))


func test_export_tool_patches_subpackage_lifecycle_and_confirms_engine_entry() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains(
		"181E61961CF6527F718E93E132D86DAF4310E091E3B004909076BDCE4D56C99C"
	))
	assert_true(source.contains("ConvertTo-WeChatSubpackageLifecyclePatchedSource"))
	for lifecycle_event: String in ["start", "progress", "success", "fail", "complete"]:
		assert_true(source.contains('"[wechat-subpackage] %s"' % lifecycle_event))
	assert_true(source.contains("this.config.textConfig.loadFailedText"))
	assert_true(source.contains("throw error"))
	assert_true(source.contains("__godotGameDataSubpackageEntryStarted = true"))
	assert_true(source.contains("__godotEngineSubpackageEntryStarted = true"))
	assert_true(source.contains('loadPackage("game_data"'))
	assert_true(source.contains('loadPackage("engine"'))
	assert_true(source.contains("[wechat-subpackage] entry_confirmed"))
	assert_true(source.contains("[wechat-subpackage] entry_started"))
	assert_true(source.contains("[wechat-subpackage] data_probe_success"))
	assert_true(source.contains('path="/game_data/2048-all-in-one.bin"'))
	assert_true(source.contains("const SUBPACKAGE_TIMEOUT_MS=300000"))
	assert_true(source.contains("const DATA_PROBE_TIMEOUT_MS=10000"))
	assert_true(source.contains("let fatal=false"))
	assert_true(source.contains("clearTimeout(timeoutId)"))
	assert_true(source.contains("[wechat-subpackage] timeout"))


func test_export_tool_enforces_conservative_wechat_package_budgets() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$ExportReportSchemaVersion = 3'))
	assert_true(source.contains('$MainPackageHardLimitBytes = 4000000'))
	assert_true(source.contains('$TotalPackageHardLimitBytes = 20000000'))
	assert_true(source.contains('$MainPackageSoftLimitBytes = 3600000'))
	assert_true(source.contains('$SubpackageHardLimitBytes = 20000000'))
	assert_true(source.contains('$SubpackageSoftLimitBytes = 18000000'))
	assert_true(source.contains('$TotalPackageSoftLimitBytes = 18000000'))
	assert_true(source.contains('value = "engine/godot.wasm.br"'))
	assert_true(source.contains('value = "game_data/$PackFileName"'))
	assert_true(source.contains("unexpected_paths"))
	assert_true(source.contains("forbidden_paths"))
	assert_true(source.contains("Invoke-GodotArtifactVerification"))
	assert_true(source.contains("res://tools/wechat_minigame_artifact_check.gd"))
	assert_true(source.contains('"--inspect-pack"'))
	assert_true(source.contains("Initialize-GodotArtifactVerificationProject"))
	assert_true(source.contains("-VerificationProjectRoot $verificationProjectRoot"))
	assert_true(source.contains('config/name="2048 WeChat Artifact Verification Host"'))
	assert_true(source.contains("global_script_class_cache.cfg"))
	assert_true(source.contains('"class": &"GFBoundedJsonObjectReader"'))
	assert_true(source.contains('"class": &"GFPathTools"'))
	assert_true(
		source.contains("$ReleaseFontCoverageManifestRelativePath")
		and source.contains("$ReleaseFontCoverageRelativePath"),
		"正式字体 coverage 证据应复制到隔离 verifier host，而不是塞进运行时 pack。"
	)


func test_export_tool_has_one_fixed_landscape_smoke_contract() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$DeviceOrientation = "landscape"'))
	assert_false(source.contains('ValidateSet("landscape", "portrait")'))


func test_export_tool_sets_a_distinct_devtools_project_identity() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$WeChatProjectName = if ($IsReleaseProfile)'))
	assert_true(source.contains('"2048 Chunked Toolchain Smoke"'))
	assert_true(source.contains('-NotePropertyName "projectname"'))
	assert_true(source.contains('-NotePropertyValue $WeChatProjectName'))
	assert_true(source.contains('$projectConfig.compileType = "minigame"'))
	assert_true(source.contains('project_name = $WeChatProjectName'))
	assert_true(source.contains('"2048 Full Game Release Candidate"'))


func test_release_entry_reuses_the_audited_export_transaction() -> void:
	var release_source: String = FileAccess.get_file_as_string(_RELEASE_TOOL_PATH)
	assert_false(release_source.is_empty())
	assert_true(release_source.contains("export_wechat_minigame_smoke.ps1"))
	assert_true(release_source.contains("-Profile Release @args"))
	assert_false(release_source.contains("Invoke-GodotPackExport"))
	var source: String = _read_tool_source()
	assert_true(source.contains('[ValidateSet("Smoke", "Release")]'))
	assert_true(source.contains('$ReportScope = if ($IsReleaseProfile)'))
	assert_true(source.contains("Get-ReleaseFontPolicyEvidence"))


func test_export_tool_publishes_transactionally_and_rejects_reparse_paths() -> void:
	var source: String = _read_tool_source()
	var backup_index: int = source.find(
		"Move-Item -LiteralPath $finalRoot -Destination $backupRoot"
	)
	var publish_index: int = source.find(
		"Move-Item -LiteralPath $stageRoot -Destination $finalRoot"
	)
	var retire_index: int = source.find("retired WeChat candidate bundle backup")
	assert_true(backup_index >= 0)
	assert_true(publish_index > backup_index)
	assert_true(retire_index > publish_index)
	assert_true(source.contains("$previousCandidateBackedUp = $true"))
	assert_true(source.contains("$newCandidatePublished = $true"))
	assert_true(source.contains("$publishCommitted = $true"))
	assert_true(source.contains("if (-not $publishCommitted)"))
	assert_true(source.contains("The new WeChat candidate is committed"))
	assert_true(source.contains("failed published WeChat candidate bundle"))
	assert_true(source.contains('"after_candidate_backup"'))
	assert_true(source.contains('"after_candidate_publish"'))
	assert_true(source.contains("[IO.FileAttributes]::ReparsePoint"))
	assert_true(source.contains("Assert-NoReparsePointTree"))
	assert_true(source.contains("function Assert-ExistingCandidateBundleShape"))
	assert_true(source.contains("cannot be replaced safely"))
	var report_index: int = source.find("-Path $stageReportPath")
	var verification_index: int = source.find(
		"-ReportPath $stageReportPath",
		report_index
	)
	var bundle_publish_index: int = source.find(
		"Publish-CandidateBundle `",
		verification_index
	)
	assert_true(report_index >= 0)
	assert_true(verification_index > report_index)
	assert_true(bundle_publish_index > verification_index)
	assert_true(source.contains('$stageRoot = Join-Path $stageCandidateRoot "wxgame"'))
	assert_true(source.contains(
		'$stageReportPath = Join-Path $stageCandidateRoot "export-report.json"'
	))


func test_export_tool_freezes_source_tool_and_complete_artifact_identity() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$RequiredGodotVersionPrefix = "4.7.2.stable"'))
	assert_true(source.contains("function Get-GodotIdentity"))
	assert_true(source.contains("function Get-GfVendorIdentity"))
	assert_true(source.contains("function Get-ExportInputSnapshot"))
	assert_true(source.contains("function Get-ToolIdentity"))
	assert_true(source.contains("function Assert-FrozenExportIdentity"))
	assert_true(source.contains("function Get-CandidateBuildId"))
	assert_true(source.contains('"wechat-artifact-manifest-v$ArtifactManifestSchemaVersion"'))
	assert_true(source.contains('schema_version = $ExportReportSchemaVersion'))
	assert_true(source.contains('artifact_manifest_sha256 = $artifactManifestSha256'))
	assert_true(source.contains('input_snapshot_sha256 = $inputSnapshotSha256'))
	assert_true(source.contains('build_id = $buildId'))
	assert_true(source.contains('gf = $gfIdentity'))
	assert_true(source.contains('tool_identity = $toolIdentity'))
	assert_true(source.contains('$ToolIdentityRelativePaths.Values'))
	assert_true(source.contains(
		'bounded_json_reader = "addons/gf/kernel/core/gf_bounded_json_object_reader.gd"'
	))
	assert_true(source.contains(
		'path_tools = "addons/gf/kernel/core/gf_path_tools.gd"'
	))
	assert_true(source.contains('"--report-path"'))
	var verifier_source: String = FileAccess.get_file_as_string(
		"res://tools/wechat_minigame_artifact_verifier.gd"
	)
	assert_true(verifier_source.contains("GFBoundedJsonObjectReader.read_object("))
	assert_false(verifier_source.contains("GFVariantData"))


func test_export_tool_never_inherits_the_upstream_sample_app_id() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$projectConfig.appid = $preservedAppId'))
	assert_true(source.contains('app_id_configured = -not [string]::IsNullOrWhiteSpace'))
	assert_true(source.contains('$ForbiddenSampleAppIds = @('))
	assert_true(source.contains("wxda5f10e2e9114855"))
	assert_true(source.contains("wxf40904ea6120ad08"))
	assert_true(source.contains('Assert-WeChatAppId `'))
	assert_true(source.contains('-Source "preserved project.config.json AppID"'))
	assert_true(source.contains('$privateConfig.PSObject.Properties.Remove("appid")'))
	assert_true(source.contains('$privateConfig.PSObject.Properties.Remove("compileType")'))


func test_wechat_smoke_font_is_pinned_and_only_overrides_the_smoke_feature() -> void:
	assert_true(FileAccess.file_exists(_SMOKE_FONT_PATH))
	assert_true(FileAccess.file_exists(_SMOKE_FONT_RESOURCE_PATH))
	var font_filesystem_path: String = ProjectSettings.globalize_path(_SMOKE_FONT_PATH)
	var actual_font_sha256: String = FileAccess.get_sha256(font_filesystem_path).to_lower()
	assert_true(
		actual_font_sha256 == _SMOKE_FONT_SHA256,
		"微信冒烟字体 hash 漂移：%s" % actual_font_sha256
	)
	var project_config: ConfigFile = ConfigFile.new()
	assert_true(project_config.load(_PROJECT_CONFIG_PATH) == OK)
	assert_true(
		str(project_config.get_value("gui", "theme/custom_font", ""))
			== "res://shared/assets/fonts/ui_sans_regular.tres"
	)
	assert_true(
		str(project_config.get_value(
			"gui",
			"theme/custom_font.wechat_minigame_smoke",
			""
		)) == _SMOKE_FONT_RESOURCE_PATH
	)
	assert_true(
		str(project_config.get_value(
			"gui",
			"theme/custom_font.wechat_minigame_release",
			""
		)) == _RELEASE_FONT_RESOURCE_PATH
	)


func test_wechat_smoke_font_disables_fallback_and_covers_runtime_literals() -> void:
	var import_config: ConfigFile = ConfigFile.new()
	assert_true(import_config.load(_SMOKE_FONT_IMPORT_PATH) == OK)
	assert_false(GFVariantData.to_bool(
		import_config.get_value("params", "allow_system_fallback", true),
		true
	))

	var resource: Resource = load(_SMOKE_FONT_PATH)
	assert_true(resource is Font)
	if not resource is Font:
		return
	var font: Font = resource
	var required_codepoints: Dictionary = {}
	for required_text: String in _REQUIRED_SMOKE_TEXTS:
		_add_non_ascii_codepoints(required_text, required_codepoints)
	for source_path: String in _VISIBLE_TEXT_SOURCE_PATHS:
		_add_source_literal_codepoints(source_path, required_codepoints)
	var sorted_codepoints: Array = required_codepoints.keys()
	sorted_codepoints.sort()
	for codepoint_value: Variant in sorted_codepoints:
		var codepoint: int = GFVariantData.to_int(codepoint_value)
		assert_true(font.has_char(codepoint), "微信冒烟字体缺少 U+%04X" % codepoint)


func test_web_smoke_remaps_the_full_font_and_includes_the_subset() -> void:
	var export_config: ConfigFile = ConfigFile.new()
	assert_true(export_config.load(_EXPORT_CONFIG_PATH) == OK)
	var preset_section: String = ""
	for section: String in export_config.get_sections():
		if str(export_config.get_value(section, "name", "")) == _WEB_PRESET_NAME:
			preset_section = section
			break
	assert_false(preset_section.is_empty())
	var include_filter: String = str(export_config.get_value(
		preset_section,
		"include_filter",
		""
	))
	var exclude_filter: String = str(export_config.get_value(
		preset_section,
		"exclude_filter",
		""
	))
	assert_true(include_filter.contains("shared/assets/fonts/wechat_smoke_sans_subset.ttf"))
	assert_true(include_filter.contains("shared/assets/fonts/ui_sans_wechat_smoke.tres"))
	assert_true(exclude_filter.contains("shared/assets/fonts/noto_sans_sc_variable.ttf"))
	assert_false(exclude_filter.contains("shared/assets/fonts/ui_sans_regular.tres"))
	assert_true(exclude_filter.contains("addons/wechat_minigame_smoke_export/*"))


func test_wechat_release_preset_exports_the_full_game_without_platform_smoke() -> void:
	var export_config: ConfigFile = ConfigFile.new()
	assert_true(export_config.load(_EXPORT_CONFIG_PATH) == OK)
	var preset_section: String = ""
	for section: String in export_config.get_sections():
		if str(export_config.get_value(section, "name", "")) == _RELEASE_PRESET_NAME:
			preset_section = section
			break
	assert_false(preset_section.is_empty())
	var custom_features: PackedStringArray = str(export_config.get_value(
		preset_section,
		"custom_features",
		""
	)).split(",", false)
	assert_true(custom_features.has("wechat_minigame_release"))
	assert_false(custom_features.has("platform_smoke"))
	var include_filter: String = str(export_config.get_value(
		preset_section,
		"include_filter",
		""
	))
	var exclude_filter: String = str(export_config.get_value(
		preset_section,
		"exclude_filter",
		""
	))
	assert_true(include_filter.contains("shared/assets/fonts/wechat_release_sans_subset.ttf"))
	assert_true(include_filter.contains("shared/assets/fonts/ui_sans_wechat_release.tres"))
	assert_true(include_filter.contains("shared/assets/translations.en.translation"))
	assert_true(include_filter.contains("shared/assets/translations.zh.translation"))
	assert_false(include_filter.contains("shared/assets/fonts/wechat_release_font_coverage.json"))
	assert_true(include_filter.contains("shared/assets/fonts/noto_sans_sc_ofl.txt"))
	assert_true(exclude_filter.contains("shared/assets/fonts/noto_sans_sc_variable.ttf"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_smoke_sans_subset.ttf"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_release_font_coverage.txt"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_release_font_coverage.json"))
	for excluded_path: String in PackedStringArray([
		"addons/gf/extensions/behavior_tree/*",
		"addons/gf/extensions/camera/*",
		"addons/gf/extensions/combat/*",
		"addons/gf/extensions/decision/*",
		"addons/gf/extensions/dialogue/*",
		"addons/gf/extensions/flow/*",
		"addons/gf/extensions/interaction/*",
		"addons/gf/extensions/layered_sprite/*",
		"addons/gf/extensions/network/*",
		"addons/gf/extensions/physics/*",
		"addons/gf/kernel/editor/*",
		"addons/gf/standard/editor/*",
		"addons/gf/standard/utilities/agent/*",
		"features/asset_library/resources/source_exclusions.json",
		"gf_project_profile.json",
		".gutconfig.json",
		"addons/gf/standard/foundation/math/gf_wave_function_collapse_2d.gd",
		"addons/gf/standard/foundation/math/gf_curve_2d_math.gd",
		"addons/gf/standard/foundation/math/gf_hex_grid_math.gd",
	]):
		assert_true(
			exclude_filter.split(",", false).has(excluded_path),
			"微信正式预设缺少体积排除规则：%s" % excluded_path
		)
	for retained_path: String in PackedStringArray([
		"addons/gf/standard/foundation/math/gf_grid_coordinate_math_2d.gd",
		"addons/gf/standard/foundation/math/gf_spatial_bounds_math.gd",
	]):
		assert_false(
			exclude_filter.split(",", false).has(retained_path),
			"微信正式预设误排除了运行时 GF 数学依赖：%s" % retained_path
		)
	var project_config: ConfigFile = ConfigFile.new()
	assert_true(project_config.load(_PROJECT_CONFIG_PATH) == OK)
	assert_true(GFVariantData.to_bool(project_config.get_value(
		"internationalization",
		"locale/include_text_server_data",
		false
	)))
	assert_false(GFVariantData.to_bool(project_config.get_value(
		"internationalization",
		"locale/include_text_server_data.wechat_minigame_release",
		true
	), true))
	var release_translations_value: Variant = project_config.get_value(
		"internationalization",
		"locale/translations.wechat_minigame_release",
		null
	)
	assert_true(release_translations_value is PackedStringArray)
	if release_translations_value is PackedStringArray:
		var release_translations: PackedStringArray = release_translations_value
		assert_true(release_translations.is_empty())


func test_wechat_release_exact_gf_script_exclusions_have_no_runtime_references() -> void:
	var export_config: ConfigFile = ConfigFile.new()
	assert_true(export_config.load(_EXPORT_CONFIG_PATH) == OK)
	var preset_section: String = ""
	for section: String in export_config.get_sections():
		if str(export_config.get_value(section, "name", "")) == _RELEASE_PRESET_NAME:
			preset_section = section
			break
	assert_false(preset_section.is_empty())
	if preset_section.is_empty():
		return

	var exclude_filters: PackedStringArray = _parse_export_filter_list(str(
		export_config.get_value(preset_section, "exclude_filter", "")
	))
	var exact_gf_script_paths: PackedStringArray = PackedStringArray()
	for filter_pattern: String in exclude_filters:
		if (
			filter_pattern.begins_with("addons/gf/")
			and filter_pattern.ends_with(".gd")
			and not filter_pattern.contains("*")
			and not filter_pattern.contains("?")
		):
			var _appended: bool = exact_gf_script_paths.append(filter_pattern)
	exact_gf_script_paths.sort()
	assert_false(
		exact_gf_script_paths.is_empty(),
		"微信正式预设必须声明需要审计的精确 GF 脚本排除项。"
	)
	if exact_gf_script_paths.is_empty():
		return

	var excluded_scripts: Array[Dictionary] = []
	for relative_path: String in exact_gf_script_paths:
		var resource_path: String = "res://%s" % relative_path
		assert_true(
			FileAccess.file_exists(resource_path),
			"微信正式预设排除的 GF 脚本不存在：%s" % resource_path
		)
		if not FileAccess.file_exists(resource_path):
			continue
		var script_source: String = FileAccess.get_file_as_string(resource_path)
		assert_false(script_source.is_empty(), "无法读取 GF 脚本：%s" % resource_path)
		if script_source.is_empty():
			continue
		var script_uid: String = ""
		var uid_path: String = "%s.uid" % resource_path
		if FileAccess.file_exists(uid_path):
			script_uid = FileAccess.get_file_as_string(uid_path).strip_edges()
			assert_true(
				script_uid.begins_with("uid://"),
				"GF 脚本 UID 文件内容无效：%s" % uid_path
			)
		excluded_scripts.append({
			"class_name": _read_script_class_name(script_source),
			"path": resource_path,
			"uid": script_uid,
		})

	var runtime_paths: PackedStringArray = _collect_release_runtime_text_paths(
		exclude_filters
	)
	assert_false(runtime_paths.is_empty(), "微信正式预设运行时文本资源审计集合不能为空。")
	var references: PackedStringArray = PackedStringArray()
	for source_path: String in runtime_paths:
		var source_text: String = FileAccess.get_file_as_string(source_path)
		var reference_text: String = source_text
		var identifier_text: String = source_text
		match source_path.get_extension().to_lower():
			"gd":
				reference_text = _sanitize_gdscript_source(source_text, false)
				identifier_text = _sanitize_gdscript_source(source_text, true)
			"tscn", "tres", "cfg":
				reference_text = _strip_text_resource_comments(source_text)
				identifier_text = reference_text
		for excluded_script: Dictionary in excluded_scripts:
			var target_path: String = str(excluded_script.get("path", ""))
			var target_class: String = str(excluded_script.get("class_name", ""))
			var target_uid: String = str(excluded_script.get("uid", ""))
			if (
				not target_class.is_empty()
				and _contains_ascii_identifier(identifier_text, target_class)
			):
				var _class_appended: bool = references.append(
					"%s -> %s [class_name: %s]" % [
						source_path,
						target_path,
						target_class,
					]
				)
			if reference_text.contains(target_path):
				var _path_appended: bool = references.append(
					"%s -> %s [resource path]" % [source_path, target_path]
				)
			if not target_uid.is_empty() and reference_text.contains(target_uid):
				var _uid_appended: bool = references.append(
					"%s -> %s [uid: %s]" % [
						source_path,
						target_path,
						target_uid,
					]
				)
	references.sort()
	assert_true(
		references.is_empty(),
		(
			"微信正式预设排除了仍被 release 运行时资源直接引用的 GF 脚本：\n%s"
			% "\n".join(references)
		)
	)


func test_wechat_release_translation_bootstrap_is_platform_owned_and_valid() -> void:
	var paths: PackedStringArray = (
		WechatReleaseTranslationBootstrapUtility.get_required_translation_paths()
	)
	assert_true(paths == PackedStringArray([
		"res://shared/assets/translations.en.translation",
		"res://shared/assets/translations.zh.translation",
	]))
	for path: String in paths:
		assert_true(ResourceLoader.exists(path))
		assert_true(ResourceLoader.load(path, "Translation") is Translation)
	assert_true(WechatReleaseTranslationBootstrapUtility.install_if_required(false) == OK)
	var boot_source: String = FileAccess.get_file_as_string(
		"res://app/scripts/boot_runtime.gd"
	)
	var bootstrap_index: int = boot_source.find(
		"WechatReleaseTranslationBootstrapUtility.install_if_required("
	)
	var architecture_index: int = boot_source.find("Gf.create_architecture()")
	var init_index: int = boot_source.find("Gf." + "init()")
	assert_true(
		bootstrap_index >= 0
		and architecture_index > bootstrap_index
		and init_index > architecture_index,
		"微信翻译必须由 Composition Root 在创建并初始化 GF 架构前完成注册。"
	)


func test_wechat_release_font_hash_license_and_declared_coverage_are_exact() -> void:
	for path: String in PackedStringArray([
		_RELEASE_FONT_PATH,
		_RELEASE_FONT_IMPORT_PATH,
		_RELEASE_FONT_RESOURCE_PATH,
		_RELEASE_COVERAGE_PATH,
		_RELEASE_COVERAGE_MANIFEST_PATH,
		_FONT_LICENSE_PATH,
	]):
		assert_true(FileAccess.file_exists(path), "正式微信字体证据缺失：%s" % path)
	var manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(_RELEASE_COVERAGE_MANIFEST_PATH)
	)
	assert_true(manifest_value is Dictionary)
	if not manifest_value is Dictionary:
		return
	var manifest: Dictionary = manifest_value
	assert_true(str(manifest.get("policy_id", "")) == "wechat-release-shipped-literals-v1")
	var source_font: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"source_font"
	)
	var license: Dictionary = GFVariantData.get_option_dictionary(manifest, "license")
	var subset_font: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"subset_font"
	)
	assert_true(str(source_font.get("sha256", "")) == _SOURCE_FONT_SHA256)
	assert_true(str(license.get("spdx", "")) == "OFL-1.1")
	assert_true(str(license.get("sha256", "")) == _FONT_LICENSE_SHA256)
	assert_true(
		FileAccess.get_sha256(_FONT_LICENSE_PATH).to_lower() == _FONT_LICENSE_SHA256
	)
	assert_true(
		FileAccess.get_sha256(_RELEASE_FONT_PATH).to_lower()
		== str(subset_font.get("sha256", ""))
	)
	assert_true(
		FileAccess.get_sha256(_RELEASE_COVERAGE_PATH).to_lower()
		== str(
			GFVariantData.get_option_dictionary(manifest, "coverage").get(
				"codepoints_sha256",
				""
			)
		)
	)

	var import_config: ConfigFile = ConfigFile.new()
	assert_true(import_config.load(_RELEASE_FONT_IMPORT_PATH) == OK)
	assert_false(GFVariantData.to_bool(
		import_config.get_value("params", "allow_system_fallback", true),
		true
	))
	var font_resource: Resource = load(_RELEASE_FONT_PATH)
	assert_true(font_resource is Font)
	if not font_resource is Font:
		return
	var font: Font = font_resource
	var declared_count: int = 0
	for token: String in FileAccess.get_file_as_string(
		_RELEASE_COVERAGE_PATH
	).strip_edges().split(",", false):
		var codepoint: int = token.trim_prefix("U+").hex_to_int()
		assert_true(codepoint > 0, "正式微信字体覆盖 token 无效：%s" % token)
		assert_true(font.has_char(codepoint), "正式微信字体缺少 %s" % token)
		declared_count += 1
	assert_true(
		declared_count
		== GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(manifest, "coverage"),
			"codepoint_count"
		)
	)


func test_export_plugin_replaces_fonts_for_smoke_and_release_profiles_only() -> void:
	assert_true(FileAccess.file_exists(_EXPORT_PLUGIN_CONFIG_PATH))
	var project_config: ConfigFile = ConfigFile.new()
	assert_true(project_config.load(_PROJECT_CONFIG_PATH) == OK)
	var enabled_plugins: PackedStringArray = project_config.get_value(
		"editor_plugins",
		"enabled",
		PackedStringArray()
	)
	assert_true(enabled_plugins.has(_EXPORT_PLUGIN_CONFIG_PATH))

	var source: String = FileAccess.get_file_as_string(_EXPORT_PLUGIN_PATH)
	var plugin_config: String = FileAccess.get_file_as_string(
		_EXPORT_PLUGIN_CONFIG_PATH
	)
	assert_true(plugin_config.contains("WeChat Mini Game Profile Font Export"))
	assert_true(plugin_config.contains("directory name is retained for compatibility"))
	assert_true(source.contains('const _SMOKE_FEATURE: String = "wechat_minigame_smoke"'))
	assert_true(source.contains('const _RELEASE_FEATURE: String = "wechat_minigame_release"'))
	assert_true(source.contains("WeChatMiniGameProfileFontExportPlugin"))
	assert_false(source.contains("WeChatMiniGameSmokeExportPlugin"))
	assert_true(source.contains("func _begin_customize_resources("))
	assert_true(source.contains("features.has(feature)"))
	assert_true(source.contains("_FONT_VARIATION_PATHS.has(path)"))
	assert_true(source.contains("resource.duplicate(true)"))
	assert_true(source.contains("customized_font.base_font = profile_font"))
	assert_true(source.contains("load(_active_font_path)"))
	assert_true(source.contains("_active_font_path,"))


# --- 私有/辅助方法 ---

func _read_tool_source() -> String:
	var file: FileAccess = FileAccess.open(_TOOL_PATH, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return ""
	return file.get_as_text()


func _add_source_literal_codepoints(path: String, codepoints: Dictionary) -> void:
	var source: String = FileAccess.get_file_as_string(path)
	assert_false(source.is_empty(), "可见文案来源必须可读取：%s" % path)
	var literal_expression: RegEx = RegEx.new()
	var compile_error: Error = literal_expression.compile("\"(?:\\\\.|[^\"\\\\])*\"")
	assert_true(compile_error == OK)
	for match_result: RegExMatch in literal_expression.search_all(source):
		_add_non_ascii_codepoints(match_result.get_string(), codepoints)


func _add_non_ascii_codepoints(text: String, codepoints: Dictionary) -> void:
	for index: int in range(text.length()):
		var codepoint: int = text.unicode_at(index)
		if codepoint >= 128:
			codepoints[codepoint] = true


func _parse_export_filter_list(serialized_filters: String) -> PackedStringArray:
	var filters: PackedStringArray = PackedStringArray()
	for filter_text: String in serialized_filters.split(",", false):
		var normalized_filter: String = (
			filter_text.strip_edges().trim_prefix("res://").replace("\\", "/")
		)
		if normalized_filter.is_empty() or filters.has(normalized_filter):
			continue
		var _appended: bool = filters.append(normalized_filter)
	filters.sort()
	return filters


func _collect_release_runtime_text_paths(
	exclude_filters: PackedStringArray
) -> PackedStringArray:
	var paths: PackedStringArray = _collect_release_runtime_text_paths_recursive(
		"res://",
		exclude_filters
	)
	paths.sort()
	return paths


func _collect_release_runtime_text_paths_recursive(
	root_path: String,
	exclude_filters: PackedStringArray
) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var directory_names: PackedStringArray = DirAccess.get_directories_at(root_path)
	directory_names.sort()
	for directory_name: String in directory_names:
		var directory_path: String = root_path.path_join(directory_name)
		var relative_directory_path: String = directory_path.trim_prefix("res://")
		if _should_skip_release_audit_path(relative_directory_path, true, exclude_filters):
			continue
		paths.append_array(_collect_release_runtime_text_paths_recursive(
			directory_path,
			exclude_filters
		))

	var file_names: PackedStringArray = DirAccess.get_files_at(root_path)
	file_names.sort()
	for file_name: String in file_names:
		var file_path: String = root_path.path_join(file_name)
		var relative_file_path: String = file_path.trim_prefix("res://")
		if _should_skip_release_audit_path(relative_file_path, false, exclude_filters):
			continue
		if not _RELEASE_RUNTIME_TEXT_EXTENSIONS.has(
			relative_file_path.get_extension().to_lower()
		):
			continue
		var _appended: bool = paths.append(file_path)
	return paths


func _should_skip_release_audit_path(
	relative_path: String,
	is_directory: bool,
	exclude_filters: PackedStringArray
) -> bool:
	var normalized_path: String = relative_path.replace("\\", "/").trim_prefix("/")
	var path_segments: PackedStringArray = normalized_path.split("/", false)
	if path_segments.is_empty():
		return false
	if _RELEASE_AUDIT_EXCLUDED_ROOTS.has(path_segments[0]):
		return true
	for segment: String in path_segments:
		if segment == "editor" or segment.begins_with("."):
			return true
	if _matches_any_export_filter(normalized_path, exclude_filters):
		return true
	return (
		is_directory
		and _matches_any_export_filter(
			"%s/__release_audit_probe__" % normalized_path,
			exclude_filters
		)
	)


func _matches_any_export_filter(
	relative_path: String,
	exclude_filters: PackedStringArray
) -> bool:
	for filter_pattern: String in exclude_filters:
		if relative_path.match(filter_pattern):
			return true
	return false


func _read_script_class_name(script_source: String) -> String:
	var executable_source: String = _sanitize_gdscript_source(script_source, true)
	for source_line: String in executable_source.split("\n", false):
		var normalized_line: String = source_line.strip_edges().replace("\t", " ")
		while normalized_line.contains("  "):
			normalized_line = normalized_line.replace("  ", " ")
		if not normalized_line.begins_with("class_name "):
			continue
		var declaration: PackedStringArray = normalized_line.split(" ", false)
		if declaration.size() >= 2:
			return declaration[1]
	return ""


func _sanitize_gdscript_source(source: String, strip_strings: bool) -> String:
	var result_lines: PackedStringArray = PackedStringArray()
	var active_quote: String = ""
	var active_is_triple: bool = false
	var strip_active_string: bool = false
	var is_escaped: bool = false
	for source_line: String in source.split("\n", true):
		var result_line: String = ""
		var index: int = 0
		while index < source_line.length():
			var character: String = source_line.substr(index, 1)
			if active_quote.is_empty():
				if character == "#":
					break
				if character == "\"" or character == "'":
					var triple_delimiter: String = character + character + character
					active_is_triple = source_line.substr(index, 3) == triple_delimiter
					active_quote = character
					strip_active_string = strip_strings
					var delimiter_length: int = 3 if active_is_triple else 1
					for delimiter_index: int in range(delimiter_length):
						result_line += " " if strip_active_string else character
					index += delimiter_length
					is_escaped = false
					continue
				result_line += character
				index += 1
				continue

			var closing_delimiter: String = active_quote
			if active_is_triple:
				closing_delimiter = active_quote + active_quote + active_quote
			var closes_string: bool = (
				not is_escaped
				and source_line.substr(index, closing_delimiter.length()) == closing_delimiter
			)
			if closes_string:
				for delimiter_index: int in range(closing_delimiter.length()):
					result_line += " " if strip_active_string else active_quote
				index += closing_delimiter.length()
				active_quote = ""
				active_is_triple = false
				strip_active_string = false
				is_escaped = false
				continue
			result_line += " " if strip_active_string else character
			if character == "\\":
				is_escaped = not is_escaped
			else:
				is_escaped = false
			index += 1
		var _appended: bool = result_lines.append(result_line)
		is_escaped = false
	return "\n".join(result_lines)


func _strip_text_resource_comments(source: String) -> String:
	var result_lines: PackedStringArray = PackedStringArray()
	for source_line: String in source.split("\n", true):
		var result_line: String = ""
		var active_quote: String = ""
		var is_escaped: bool = false
		for index: int in range(source_line.length()):
			var character: String = source_line.substr(index, 1)
			if active_quote.is_empty():
				if character == "#" or character == ";":
					break
				if character == "\"" or character == "'":
					active_quote = character
					is_escaped = false
				result_line += character
				continue
			result_line += character
			if character == active_quote and not is_escaped:
				active_quote = ""
				is_escaped = false
			elif character == "\\":
				is_escaped = not is_escaped
			else:
				is_escaped = false
		var _appended: bool = result_lines.append(result_line)
	return "\n".join(result_lines)


func _contains_ascii_identifier(source: String, identifier: String) -> bool:
	var search_from: int = 0
	while search_from < source.length():
		var match_index: int = source.find(identifier, search_from)
		if match_index < 0:
			return false
		var before_is_identifier: bool = (
			match_index > 0
			and _is_ascii_identifier_codepoint(source.unicode_at(match_index - 1))
		)
		var after_index: int = match_index + identifier.length()
		var after_is_identifier: bool = (
			after_index < source.length()
			and _is_ascii_identifier_codepoint(source.unicode_at(after_index))
		)
		if not before_is_identifier and not after_is_identifier:
			return true
		search_from = match_index + identifier.length()
	return false


func _is_ascii_identifier_codepoint(codepoint: int) -> bool:
	return (
		codepoint == 95
		or (codepoint >= 48 and codepoint <= 57)
		or (codepoint >= 65 and codepoint <= 90)
		or (codepoint >= 97 and codepoint <= 122)
	)
