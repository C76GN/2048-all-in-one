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
	assert_true(source.contains("/engine/$PackFileName"))
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


func test_export_tool_enforces_conservative_wechat_package_budgets() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$MainPackageHardLimitBytes = 4000000'))
	assert_true(source.contains('$TotalPackageHardLimitBytes = 30000000'))
	assert_true(source.contains('$MainPackageSoftLimitBytes = 3600000'))
	assert_true(source.contains('$TotalPackageSoftLimitBytes = 27000000'))
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
	assert_false(include_filter.contains("shared/assets/fonts/wechat_release_font_coverage.json"))
	assert_true(include_filter.contains("shared/assets/fonts/noto_sans_sc_ofl.txt"))
	assert_true(exclude_filter.contains("shared/assets/fonts/noto_sans_sc_variable.ttf"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_smoke_sans_subset.ttf"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_release_font_coverage.txt"))
	assert_true(exclude_filter.contains("shared/assets/fonts/wechat_release_font_coverage.json"))


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
