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
