## 验证微信小游戏冒烟导出器保持可复现模板、包体预算和隐私边界。
extends GutTest


# --- 常量 ---

const _TOOL_PATH: String = "res://tools/export_wechat_minigame_smoke.ps1"
const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _PROJECT_CONFIG_PATH: String = "res://project.godot"
const _SMOKE_FONT_PATH: String = "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf"
const _SMOKE_FONT_IMPORT_PATH: String = (
	"res://shared/assets/fonts/wechat_smoke_sans_subset.ttf.import"
)
const _SMOKE_FONT_RESOURCE_PATH: String = (
	"res://shared/assets/fonts/ui_sans_wechat_smoke.tres"
)
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
const _WEB_PRESET_NAME: String = "Web Compatibility Smoke"
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
	assert_true(source.contains('scope = "toolchain_smoke"'))


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


func test_export_tool_has_one_fixed_landscape_smoke_contract() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains('$DeviceOrientation = "landscape"'))
	assert_false(source.contains('ValidateSet("landscape", "portrait")'))


func test_export_tool_sets_a_distinct_devtools_project_identity() -> void:
	var source: String = _read_tool_source()
	assert_true(source.contains(
		'$WeChatProjectName = "2048 Chunked Toolchain Smoke"'
	))
	assert_true(source.contains('-NotePropertyName "projectname"'))
	assert_true(source.contains('-NotePropertyValue $WeChatProjectName'))
	assert_true(source.contains('project_name = $WeChatProjectName'))


func test_export_tool_publishes_transactionally_and_rejects_reparse_paths() -> void:
	var source: String = _read_tool_source()
	var backup_index: int = source.find(
		"Move-Item -LiteralPath $outputRoot -Destination $backupRoot"
	)
	var publish_index: int = source.find(
		"Move-Item -LiteralPath $stageRoot -Destination $outputRoot"
	)
	var retire_index: int = source.find(
		"Remove-SafeBuildTree -Path $backupRoot"
	)
	assert_true(backup_index >= 0)
	assert_true(publish_index > backup_index)
	assert_true(retire_index > publish_index)
	assert_true(source.contains("$previousOutputBackedUp = $true"))
	assert_true(source.contains("$newOutputPublished = $true"))
	assert_true(source.contains("$publishCommitted = $true"))
	assert_true(source.contains("if (-not $publishCommitted)"))
	assert_true(source.contains("The new WeChat output is committed"))
	assert_true(source.contains("failed published WeChat smoke output"))
	assert_true(source.contains("[IO.FileAttributes]::ReparsePoint"))
	assert_true(source.contains("Assert-NoReparsePointTree"))


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


func test_export_plugin_replaces_the_font_only_for_the_wechat_smoke_feature() -> void:
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
	assert_true(source.contains('const _SMOKE_FEATURE: String = "wechat_minigame_smoke"'))
	assert_true(source.contains("func _begin_customize_resources("))
	assert_true(source.contains("features.has(_SMOKE_FEATURE)"))
	assert_true(source.contains("_FONT_VARIATION_PATHS.has(path)"))
	assert_true(source.contains("resource.duplicate(true)"))
	assert_true(source.contains("customized_font.base_font = smoke_font"))
	assert_true(source.contains("load(_SMOKE_FONT_PATH)"))


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
