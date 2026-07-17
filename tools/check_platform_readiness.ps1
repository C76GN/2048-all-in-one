param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$ExportTemplateRoot = "",
	[string]$WeChatDevToolsPath = "",
	[switch]$AllowEnvironmentBlockers,
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

& "$PSScriptRoot\invoke_godot_project_tool.ps1" `
	-ScriptPath "res://features/platform_runtime/tools/platform_readiness_check.gd" `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $ProjectRoot `
	-ExpectedOutputPattern 'Platform readiness:' `
	-TimeoutSeconds $TimeoutSeconds

$projectReportPath = Join-Path $ProjectRoot "build\platform_readiness_report.json"
if (-not (Test-Path -LiteralPath $projectReportPath)) {
	throw "Platform readiness report was not created: $projectReportPath"
}

$godotCommand = Get-Command $GodotExecutable -ErrorAction Stop
$godotPath = $godotCommand.Source
$godotVersionOutput = (& $godotPath --version | Select-Object -First 1).Trim()
$versionMatch = [regex]::Match($godotVersionOutput, '^\d+\.\d+(?:\.\d+)?\.(?:stable|beta\d*|rc\d*|dev\d*)')
$templateVersion = if ($versionMatch.Success) { $versionMatch.Value } else { $godotVersionOutput }

$templateRoots = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($ExportTemplateRoot)) {
	$templateRoots.Add($ExportTemplateRoot)
}
$portableTemplateRoot = Join-Path (Split-Path -Parent $godotPath) "editor_data\export_templates"
$templateRoots.Add($portableTemplateRoot)
if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
	$templateRoots.Add((Join-Path $env:APPDATA "Godot\export_templates"))
}

$matchingTemplatePath = ""
foreach ($root in $templateRoots | Select-Object -Unique) {
	$candidate = Join-Path $root $templateVersion
	if (Test-Path -LiteralPath $candidate -PathType Container) {
		$matchingTemplatePath = $candidate
		break
	}
}

$wechatCandidates = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($WeChatDevToolsPath)) {
	$wechatCandidates.Add($WeChatDevToolsPath)
}
if (-not [string]::IsNullOrWhiteSpace($env:WECHAT_DEVTOOLS_PATH)) {
	$wechatCandidates.Add($env:WECHAT_DEVTOOLS_PATH)
}
$wechatCandidates.Add("C:\Program Files (x86)\Tencent\微信web开发者工具\cli.bat")
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
	$wechatCandidates.Add((Join-Path $env:LOCALAPPDATA "微信开发者工具\cli.bat"))
}

$resolvedWeChatPath = ""
foreach ($candidate in $wechatCandidates | Select-Object -Unique) {
	if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
		$resolvedWeChatPath = $candidate
		break
	}
}

$blockers = [System.Collections.Generic.List[string]]::new()
if ([string]::IsNullOrWhiteSpace($matchingTemplatePath)) {
	$blockers.Add("Missing export templates matching Godot $templateVersion.")
}
if ([string]::IsNullOrWhiteSpace($resolvedWeChatPath)) {
	$blockers.Add("WeChat DevTools CLI was not found.")
}

$environmentReport = [ordered]@{
	ok = ($blockers.Count -eq 0)
	generated_at = [DateTimeOffset]::Now.ToString("o")
	project_report = $projectReportPath
	godot = [ordered]@{
		executable = $godotPath
		version_output = $godotVersionOutput
		template_version = $templateVersion
		matching_template_path = $matchingTemplatePath
		template_roots = @($templateRoots | Select-Object -Unique)
	}
	wechat_devtools = [ordered]@{
		cli_path = $resolvedWeChatPath
	}
	blockers = @($blockers)
}

$environmentReportPath = Join-Path $ProjectRoot "build\platform_environment_report.json"
$environmentReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $environmentReportPath -Encoding UTF8
Write-Host "Platform environment: $($(if ($environmentReport.ok) { 'PASS' } else { 'BLOCKED' })) ($($blockers.Count) blockers)"

if (-not $environmentReport.ok -and -not $AllowEnvironmentBlockers) {
	throw "Platform environment has blockers. See $environmentReportPath"
}
