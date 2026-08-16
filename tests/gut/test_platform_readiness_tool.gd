## 验证平台就绪脚本执行真实、临时且有明确证据的 Web 导出 smoke。
extends GutTest


# --- 常量 ---

const _READINESS_TOOL_PATH: String = "res://tools/check_platform_readiness.ps1"


# --- 测试用例 ---

func test_web_export_smoke_is_actual_temporary_and_evidence_backed() -> void:
	var source: String = FileAccess.get_file_as_string(_READINESS_TOOL_PATH)

	assert_false(source.is_empty(), "平台就绪 PowerShell 工具必须可读取。")
	assert_true(
		source.contains('"--export-release"')
		and source.contains('"Web Compatibility Smoke"'),
		"模板可用时必须调用 Godot 的真实 Web release export。"
	)
	assert_true(
		source.contains("[IO.Path]::GetTempPath()")
		and source.contains("2048-web-export-smoke-"),
		"Web smoke 产物必须隔离到系统临时目录。"
	)
	assert_true(
		source.contains('status = "skipped"')
		and source.contains('$webExportEvidence.status = "failed"')
		and source.contains('$webExportEvidence.status = "passed"'),
		"报告必须显式区分 pass、skip 与 fail。"
	)
	assert_true(
		source.contains("project_release_output_untouched = $true")
		and source.contains("Remove-Item -LiteralPath $resolvedCleanupPath"),
		"临时导出不得复用或遗留项目发布输出。"
	)
	assert_true(
		source.contains("$startInfo.Arguments")
		and not source.contains("$startInfo.ArgumentList")
		and not source.contains(".Kill($true)"),
		"进程参数必须兼容 Windows PowerShell 5.1 的 .NET Framework API。"
	)


func test_missing_templates_skip_export_instead_of_claiming_success() -> void:
	var source: String = FileAccess.get_file_as_string(_READINESS_TOOL_PATH)
	var template_guard_index: int = source.find(
		'if (-not [string]::IsNullOrWhiteSpace($matchingTemplatePath))'
	)
	var export_index: int = source.find('"--export-release"')

	assert_true(
		template_guard_index >= 0 and export_index > template_guard_index,
		"真实导出调用必须位于 export template 可用性守卫之后。"
	)
	assert_true(
		source.contains(
			'reason = "Matching Godot export templates are unavailable."'
		),
		"缺少模板时必须给出可审计的 skip 原因。"
	)


func test_wechat_cli_detection_uses_ordered_fallbacks_and_records_source() -> void:
	var source: String = FileAccess.get_file_as_string(_READINESS_TOOL_PATH)
	var parameter_index: int = source.find('-Source "parameter"')
	var environment_index: int = source.find('-Source "environment"')
	var default_index: int = source.find('-Source "default"')
	var path_index: int = source.find('Get-Command "cli.bat"')
	var registry_index: int = source.find("$wechatRegistryRoots")
	var install_directory_index: int = source.find("$wechatInstallDirectories")

	assert_true(
		parameter_index >= 0
		and environment_index > parameter_index
		and default_index > environment_index
		and path_index > default_index
		and registry_index > path_index
		and install_directory_index > registry_index,
		"微信 CLI 探测顺序必须是显式参数、环境变量、默认路径、PATH、注册表、安装目录。"
	)
	assert_true(
		source.contains("$env:WECHAT_DEVTOOLS_PATH")
		and source.contains("registry_display_icon")
		and source.contains("discovery_source = $weChatDiscoverySource"),
		"报告必须记录 CLI 的发现来源，并支持非 C 盘注册表安装。"
	)


func test_wechat_cli_presence_is_not_reported_as_automation_or_publish_readiness() -> void:
	var source: String = FileAccess.get_file_as_string(_READINESS_TOOL_PATH)

	assert_true(
		source.contains("cli_detected = -not [string]::IsNullOrWhiteSpace")
		and source.contains("automation_ready = $false")
		and source.contains('publishing_status = "not_verified"'),
		"CLI 文件、自动化通道和发布能力必须作为独立证据报告。"
	)
	assert_true(
		source.contains('-ArgumentList "islogin"')
		and source.contains("-RedirectStandardInput $stdinPath")
		and source.contains("2048-wechat-cli-probe-")
		and source.contains("Stop-StartedProcessTree")
		and source.contains('Get-Command "taskkill.exe"')
		and source.contains("/PID $startedProcessId")
		and source.contains("/T")
		and source.contains("/F")
		and source.contains('service_port_status = "disabled"')
		and source.contains("session_authorized = $false"),
		"自动化探测必须只读，并明确识别服务端口关闭或会话未授权。"
	)
	assert_true(
		source.contains("elseif (-not $weChatAutomation.automation_ready)")
		and source.contains("local automation is not ready")
		and source.contains('status = "inconclusive"')
		and source.contains("Automation and publishing readiness were not inferred."),
		"仅找到 CLI 文件时，平台就绪结果仍必须保持阻塞。"
	)
