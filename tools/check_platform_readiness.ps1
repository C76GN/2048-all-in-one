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

function ConvertTo-NativeCommandLineArgument {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Argument
	)

	if ($Argument.Contains('"') -or $Argument.Contains([char]0)) {
		throw "Native command arguments may not contain quotes or NUL characters."
	}
	if ($Argument -notmatch '\s') {
		return $Argument
	}

	# Windows CommandLineToArgvW requires trailing backslashes to be doubled
	# before the closing quote. Embedded quotes are rejected above.
	$trailingBackslashCount = [regex]::Match($Argument, '\\+$').Value.Length
	$quotedBody = $Argument
	if ($trailingBackslashCount -gt 0) {
		$argumentPrefix = $Argument.Substring(
			0,
			$Argument.Length - $trailingBackslashCount
		)
		$quotedBody = $argumentPrefix + ("\" * ($trailingBackslashCount * 2))
	}
	return '"' + $quotedBody + '"'
}

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

$webExportEvidence = [ordered]@{
	status = "skipped"
	reason = "Matching Godot export templates are unavailable."
	preset = "Web Compatibility Smoke"
	exit_code = $null
	output_created = $false
	artifact_count = 0
	destination_scope = "temporary"
	project_release_output_untouched = $true
	artifacts_removed = $true
}

if (-not [string]::IsNullOrWhiteSpace($matchingTemplatePath)) {
	$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
	$tempExportPath = Join-Path $tempRoot ("2048-web-export-smoke-" + [Guid]::NewGuid().ToString("N"))
	$tempExportPath = [IO.Path]::GetFullPath($tempExportPath)
	$tempPrefix = [IO.Path]::GetFullPath(
		(Join-Path $tempRoot "2048-web-export-smoke-")
	)
	if (-not $tempExportPath.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "Resolved Web smoke directory escaped the temporary root: $tempExportPath"
	}

	$null = New-Item -ItemType Directory -Path $tempExportPath
	$webOutputPath = Join-Path $tempExportPath "index.html"
	$webExportEvidence.status = "failed"
	$webExportEvidence.reason = "Temporary Web export did not complete."
	$webExportEvidence.artifacts_removed = $false

	try {
		$startInfo = [Diagnostics.ProcessStartInfo]::new()
		$startInfo.FileName = $godotPath
		$startInfo.UseShellExecute = $false
		$startInfo.CreateNoWindow = $true
		$startInfo.RedirectStandardOutput = $true
		$startInfo.RedirectStandardError = $true
		$exportArguments = @(
			"--headless",
			"--path",
			$ProjectRoot,
			"--export-release",
			$webExportEvidence.preset,
			$webOutputPath
		)
		$quotedExportArguments = @()
		foreach ($exportArgument in $exportArguments) {
			$quotedExportArguments += ConvertTo-NativeCommandLineArgument `
				-Argument ([string]$exportArgument)
		}
		$startInfo.Arguments = $quotedExportArguments -join " "

		$exportProcess = [Diagnostics.Process]::Start($startInfo)
		$stdoutTask = $exportProcess.StandardOutput.ReadToEndAsync()
		$stderrTask = $exportProcess.StandardError.ReadToEndAsync()
		$completedInTime = $exportProcess.WaitForExit($TimeoutSeconds * 1000)
		if (-not $completedInTime) {
			$exportProcess.Kill()
			$exportProcess.WaitForExit()
			$webExportEvidence.reason = "Temporary Web export timed out after $TimeoutSeconds seconds."
		}
		else {
			$exportProcess.WaitForExit()
			$webExportEvidence.exit_code = $exportProcess.ExitCode
			$webExportEvidence.output_created = Test-Path -LiteralPath $webOutputPath -PathType Leaf
			$webExportEvidence.artifact_count = @(
				Get-ChildItem -LiteralPath $tempExportPath -File
			).Count
			if ($exportProcess.ExitCode -eq 0 -and $webExportEvidence.output_created) {
				$webExportEvidence.status = "passed"
				$webExportEvidence.reason = "Godot completed an actual release Web export in a temporary directory."
			}
			else {
				$stderrText = $stderrTask.GetAwaiter().GetResult().Trim()
				$stdoutText = $stdoutTask.GetAwaiter().GetResult().Trim()
				$diagnosticText = if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
					$stderrText
				}
				else {
					$stdoutText
				}
				if ($diagnosticText.Length -gt 600) {
					$diagnosticText = $diagnosticText.Substring(
						$diagnosticText.Length - 600
					)
				}
				$webExportEvidence.reason = (
					"Temporary Web export failed (exit {0}): {1}" -f
					$exportProcess.ExitCode,
					$diagnosticText
				).Trim()
			}
		}
	}
	catch {
		$webExportEvidence.reason = "Temporary Web export failed: $($_.Exception.Message)"
	}
	finally {
		if (Test-Path -LiteralPath $tempExportPath) {
			$resolvedCleanupPath = [IO.Path]::GetFullPath(
				(Resolve-Path -LiteralPath $tempExportPath).Path
			)
			if (-not $resolvedCleanupPath.StartsWith(
				$tempPrefix,
				[StringComparison]::OrdinalIgnoreCase
			)) {
				throw "Refusing to clean unexpected Web smoke path: $resolvedCleanupPath"
			}
			Remove-Item -LiteralPath $resolvedCleanupPath -Recurse -Force
		}
		$webExportEvidence.artifacts_removed = -not (
			Test-Path -LiteralPath $tempExportPath
		)
	}
}

$blockers = [System.Collections.Generic.List[string]]::new()
if ([string]::IsNullOrWhiteSpace($matchingTemplatePath)) {
	$blockers.Add("Missing export templates matching Godot $templateVersion.")
}
elseif ($webExportEvidence.status -ne "passed") {
	$blockers.Add("Temporary Web export smoke failed.")
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
	web_export = $webExportEvidence
	blockers = @($blockers)
}

$environmentReportPath = Join-Path $ProjectRoot "build\platform_environment_report.json"
$environmentReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $environmentReportPath -Encoding UTF8
Write-Host "Platform environment: $($(if ($environmentReport.ok) { 'PASS' } else { 'BLOCKED' })) ($($blockers.Count) blockers)"
Write-Host "Web export smoke: $($webExportEvidence.status.ToUpperInvariant()) - $($webExportEvidence.reason)"

if (-not $environmentReport.ok -and -not $AllowEnvironmentBlockers) {
	throw "Platform environment has blockers. See $environmentReportPath"
}
