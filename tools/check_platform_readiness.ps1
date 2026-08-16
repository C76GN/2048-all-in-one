param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$ExportTemplateRoot = "",
	[string]$WeChatDevToolsPath = "",
	[switch]$AllowEnvironmentBlockers,
	[ValidateRange(1, 30)]
	[int]$WeChatProbeTimeoutSeconds = 10,
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

function Stop-StartedProcessTree {
	param(
		[Parameter(Mandatory = $true)]
		[Diagnostics.Process]$Process,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	if ($Process.HasExited) {
		return
	}
	$startedProcessId = [int]$Process.Id
	$taskKillCommand = Get-Command "taskkill.exe" -CommandType Application -ErrorAction Stop
	$taskKillOutput = & $taskKillCommand.Source `
		/PID $startedProcessId `
		/T `
		/F 2>&1
	$taskKillExitCode = $LASTEXITCODE
	$null = $Process.WaitForExit(5000)
	if (-not $Process.HasExited) {
		throw "$Label process tree did not terminate after taskkill (PID $startedProcessId)."
	}
	if ($taskKillExitCode -ne 0) {
		Write-Warning (
			"$Label process tree ended while taskkill reported exit $taskKillExitCode`: " +
			([string]::Join([Environment]::NewLine, @($taskKillOutput)))
		)
	}
}

function Add-WeChatCliCandidate {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[System.Collections.Generic.List[object]]$Candidates,
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Source
	)

	if ([string]::IsNullOrWhiteSpace($Path)) {
		return
	}

	$expandedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
	if (Test-Path -LiteralPath $expandedPath -PathType Container) {
		$expandedPath = Join-Path $expandedPath "cli.bat"
	}
	elseif ((Split-Path -Leaf $expandedPath) -ine "cli.bat") {
		$expandedPath = Join-Path (Split-Path -Parent $expandedPath) "cli.bat"
	}

	$Candidates.Add([pscustomobject]@{
		path = $expandedPath
		source = $Source
	})
}

function Get-RegistryExecutablePath {
	param([string]$Value)

	if ([string]::IsNullOrWhiteSpace($Value)) {
		return ""
	}

	$match = [regex]::Match($Value, '^\s*"([^"]+\.exe)"')
	if ($match.Success) {
		return $match.Groups[1].Value
	}
	$match = [regex]::Match($Value, '^\s*([^,]+?\.exe)(?:\s|,|$)')
	if ($match.Success) {
		return $match.Groups[1].Value.Trim()
	}
	return ""
}

function Invoke-WeChatCliReadinessProbe {
	param(
		[string]$CliPath,
		[ValidateRange(1, 30)]
		[int]$ProbeTimeoutSeconds = 10
	)

	$probe = [ordered]@{
		status = "not_run"
		automation_ready = $false
		service_port_status = "unknown"
		session_authorized = $null
		account_login_status = "unknown"
		publishing_status = "not_verified"
		exit_code = $null
		reason = "WeChat DevTools CLI was not found, so automation was not probed."
	}
	if ([string]::IsNullOrWhiteSpace($CliPath)) {
		return $probe
	}

	$probe.status = "failed"
	$probe.reason = "The CLI path was found, but the automation probe did not complete."
	$probeTempPath = ""
	try {
		$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
		$probeTempPath = [IO.Path]::GetFullPath(
			(Join-Path $tempRoot ("2048-wechat-cli-probe-" + [Guid]::NewGuid().ToString("N")))
		)
		$probeTempPrefix = [IO.Path]::GetFullPath(
			(Join-Path $tempRoot "2048-wechat-cli-probe-")
		)
		if (-not $probeTempPath.StartsWith(
			$probeTempPrefix,
			[StringComparison]::OrdinalIgnoreCase
		)) {
			throw "Resolved WeChat CLI probe directory escaped the temporary root: $probeTempPath"
		}
		$null = New-Item -ItemType Directory -Path $probeTempPath
		$stdinPath = Join-Path $probeTempPath "stdin.txt"
		$stdoutPath = Join-Path $probeTempPath "stdout.txt"
		$stderrPath = Join-Path $probeTempPath "stderr.txt"
		[IO.File]::WriteAllText($stdinPath, "", [Text.UTF8Encoding]::new($false))

		# Start-Process handles .bat invocation correctly on Windows PowerShell 5.1.
		# Empty redirected stdin prevents the CLI from accepting a prompt that would
		# enable its service port or grant authorization during this read-only check.
		$probeProcess = Start-Process `
			-FilePath $CliPath `
			-ArgumentList "islogin" `
			-WorkingDirectory (Split-Path -Parent $CliPath) `
			-NoNewWindow `
			-RedirectStandardInput $stdinPath `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath `
			-PassThru
		$completedInTime = $probeProcess.WaitForExit($ProbeTimeoutSeconds * 1000)
		if (-not $completedInTime) {
			Stop-StartedProcessTree `
				-Process $probeProcess `
				-Label "WeChat CLI readiness probe"
			$probe.status = "timed_out"
			$probe.reason = "The CLI automation probe timed out after $ProbeTimeoutSeconds seconds."
			return $probe
		}

		$probeProcess.WaitForExit()
		$probe.exit_code = $probeProcess.ExitCode
		$probeOutput = (
			[IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::UTF8) +
			[Environment]::NewLine +
			[IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8)
		).Trim()

		$servicePortDisabledPattern = (
			'(?i)service\s+port\s+(?:is\s+)?(?:disabled|off|closed)|' +
			'\u670d\u52a1\u7aef\u53e3.{0,16}(?:\u5173\u95ed|\u672a\u5f00\u542f)'
		)
		$authorizationRequiredPattern = (
			'(?i)(?:client\s+)?(?:not\s+authorized|unauthorized)|' +
			'\u672a\u6388\u6743|\u9700\u8981\u6388\u6743|' +
			'\u6388\u6743.{0,12}(?:\u5931\u8d25|\u8d85\u65f6)'
		)
		$connectionFailurePattern = (
			'(?i)ECONNREFUSED|connection\s+(?:refused|failed)|' +
			'\u65e0\u6cd5\u8fde\u63a5|\u8fde\u63a5.{0,12}\u5931\u8d25'
		)

		if ($probeOutput -match $servicePortDisabledPattern) {
			$probe.status = "blocked"
			$probe.service_port_status = "disabled"
			$probe.session_authorized = $false
			$probe.reason = (
				"The CLI file exists, but the WeChat DevTools service port is disabled. " +
				"Enable it manually in DevTools Settings > Security Settings before using CLI automation."
			)
			return $probe
		}
		if ($probeOutput -match $authorizationRequiredPattern) {
			$probe.status = "blocked"
			$probe.session_authorized = $false
			$probe.reason = (
				"The CLI file exists, but this automation session is not authorized. " +
				"Authorize it manually in WeChat DevTools before retrying."
			)
			return $probe
		}
		if ($probeOutput -match $connectionFailurePattern) {
			$probe.status = "failed"
			$probe.reason = "The CLI file exists, but the DevTools automation endpoint was unreachable."
			return $probe
		}
		$loginMatch = [regex]::Match(
			$probeOutput,
			'(?im)(?:"?(?:is[_-]?login|isLogin|login|logged_in)"?|' +
			'\u662f\u5426\u767b\u5f55|\u767b\u5f55\u72b6\u6001)\s*[:=\uFF1A]\s*(true|false)|' +
			'^\s*(true|false)\s*$'
		)
		if ($null -ne $probeProcess.ExitCode -and $probeProcess.ExitCode -ne 0) {
			$probe.status = "failed"
			$probe.reason = "The CLI automation probe failed with exit code $($probeProcess.ExitCode)."
			return $probe
		}
		if (-not $loginMatch.Success) {
			$probe.status = "inconclusive"
			$probe.reason = (
				"The CLI command completed, but its islogin response could not be recognized. " +
				"Automation and publishing readiness were not inferred."
			)
			return $probe
		}

		# A successful islogin response proves only that the local CLI automation
		# channel answered. It does not prove account login or publish permission.
		$probe.status = "passed"
		$probe.automation_ready = $true
		$probe.service_port_status = "enabled"
		$probe.session_authorized = $true
		$loginValue = if (-not [string]::IsNullOrWhiteSpace($loginMatch.Groups[1].Value)) {
			$loginMatch.Groups[1].Value
		}
		else {
			$loginMatch.Groups[2].Value
		}
		$probe.account_login_status = if ($loginValue -ieq "true") {
			"logged_in"
		}
		else {
			"logged_out"
		}
		$probe.reason = (
			"The local CLI answered the non-mutating islogin probe. " +
			"Account login and publishing permission remain separately reported and are not inferred from the CLI path."
		)
	}
	catch {
		$probe.status = "failed"
		$probe.reason = "The CLI automation probe failed: $($_.Exception.Message)"
	}
	finally {
		if (-not [string]::IsNullOrWhiteSpace($probeTempPath) -and (Test-Path -LiteralPath $probeTempPath)) {
			$resolvedProbeCleanupPath = [IO.Path]::GetFullPath(
				(Resolve-Path -LiteralPath $probeTempPath).Path
			)
			$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
			$probeTempPrefix = [IO.Path]::GetFullPath(
				(Join-Path $tempRoot "2048-wechat-cli-probe-")
			)
			if (-not $resolvedProbeCleanupPath.StartsWith(
				$probeTempPrefix,
				[StringComparison]::OrdinalIgnoreCase
			)) {
				throw "Refusing to clean unexpected WeChat CLI probe path: $resolvedProbeCleanupPath"
			}
			Remove-Item -LiteralPath $resolvedProbeCleanupPath -Recurse -Force
		}
	}
	return $probe
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

$wechatCandidates = [System.Collections.Generic.List[object]]::new()
Add-WeChatCliCandidate -Candidates $wechatCandidates -Path $WeChatDevToolsPath -Source "parameter"
Add-WeChatCliCandidate -Candidates $wechatCandidates -Path $env:WECHAT_DEVTOOLS_PATH -Source "environment"
Add-WeChatCliCandidate `
	-Candidates $wechatCandidates `
	-Path "C:\Program Files (x86)\Tencent\微信web开发者工具\cli.bat" `
	-Source "default"
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
	Add-WeChatCliCandidate `
		-Candidates $wechatCandidates `
		-Path (Join-Path $env:LOCALAPPDATA "微信开发者工具\cli.bat") `
		-Source "default"
}

$pathCliCommand = Get-Command "cli.bat" -CommandType Application -ErrorAction SilentlyContinue |
	Select-Object -First 1
if ($null -ne $pathCliCommand) {
	Add-WeChatCliCandidate `
		-Candidates $wechatCandidates `
		-Path $pathCliCommand.Source `
		-Source "path"
}

$wechatRegistryRoots = @(
	"HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
	"HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
	"HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($registryRoot in $wechatRegistryRoots) {
	$registryEntries = Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue |
		Where-Object {
			$_.DisplayName -match '\u5fae\u4fe1\u5f00\u53d1\u8005\u5de5\u5177|WeChat.*DevTools'
		}
	foreach ($registryEntry in $registryEntries) {
		Add-WeChatCliCandidate `
			-Candidates $wechatCandidates `
			-Path $registryEntry.InstallLocation `
			-Source "registry_install_location"
		Add-WeChatCliCandidate `
			-Candidates $wechatCandidates `
			-Path (Get-RegistryExecutablePath -Value $registryEntry.DisplayIcon) `
			-Source "registry_display_icon"
		Add-WeChatCliCandidate `
			-Candidates $wechatCandidates `
			-Path (Get-RegistryExecutablePath -Value $registryEntry.UninstallString) `
			-Source "registry_uninstall_command"
	}
}

$wechatInstallDirectories = @(
	$(if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
		$wechatLegacyDirectoryName = (
			[regex]::Unescape('\u5fae\u4fe1') + "web" +
			[regex]::Unescape('\u5f00\u53d1\u8005\u5de5\u5177')
		)
		Join-Path ${env:ProgramFiles(x86)} (Join-Path "Tencent" $wechatLegacyDirectoryName)
	}),
	$(if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
		$wechatDirectoryName = [regex]::Unescape(
			'\u5fae\u4fe1\u5f00\u53d1\u8005\u5de5\u5177'
		)
		Join-Path $env:ProgramFiles (Join-Path "Tencent" $wechatDirectoryName)
	}),
	$(if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
		$wechatDirectoryName = [regex]::Unescape(
			'\u5fae\u4fe1\u5f00\u53d1\u8005\u5de5\u5177'
		)
		Join-Path $env:LOCALAPPDATA (Join-Path "Programs" $wechatDirectoryName)
	})
)
foreach ($installDirectory in $wechatInstallDirectories) {
	Add-WeChatCliCandidate `
		-Candidates $wechatCandidates `
		-Path $installDirectory `
		-Source "install_directory"
}

$resolvedWeChatPath = ""
$weChatDiscoverySource = ""
$seenWeChatCandidatePaths = [System.Collections.Generic.HashSet[string]]::new(
	[StringComparer]::OrdinalIgnoreCase
)
foreach ($candidate in $wechatCandidates) {
	if (
		-not [string]::IsNullOrWhiteSpace($candidate.path) -and
		$seenWeChatCandidatePaths.Add($candidate.path) -and
		(Test-Path -LiteralPath $candidate.path -PathType Leaf)
	) {
		$resolvedWeChatPath = (Resolve-Path -LiteralPath $candidate.path).Path
		$weChatDiscoverySource = $candidate.source
		break
	}
}
$weChatAutomation = Invoke-WeChatCliReadinessProbe `
	-CliPath $resolvedWeChatPath `
	-ProbeTimeoutSeconds $WeChatProbeTimeoutSeconds

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
			Stop-StartedProcessTree `
				-Process $exportProcess `
				-Label "temporary Godot Web export"
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
elseif (-not $weChatAutomation.automation_ready) {
	$blockers.Add(
		"WeChat DevTools CLI was found, but local automation is not ready: $($weChatAutomation.reason)"
	)
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
		cli_detected = -not [string]::IsNullOrWhiteSpace($resolvedWeChatPath)
		cli_path = $resolvedWeChatPath
		discovery_source = $weChatDiscoverySource
		automation = $weChatAutomation
	}
	web_export = $webExportEvidence
	blockers = @($blockers)
}

$environmentReportPath = Join-Path $ProjectRoot "build\platform_environment_report.json"
$environmentReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $environmentReportPath -Encoding UTF8
Write-Host "Platform environment: $($(if ($environmentReport.ok) { 'PASS' } else { 'BLOCKED' })) ($($blockers.Count) blockers)"
Write-Host "Web export smoke: $($webExportEvidence.status.ToUpperInvariant()) - $($webExportEvidence.reason)"
Write-Host "WeChat CLI detection: $($(if ([string]::IsNullOrWhiteSpace($resolvedWeChatPath)) { 'MISSING' } else { 'FOUND' }))$($(if ([string]::IsNullOrWhiteSpace($weChatDiscoverySource)) { '' } else { " via $weChatDiscoverySource" }))"
Write-Host "WeChat CLI automation: $($weChatAutomation.status.ToUpperInvariant()) - $($weChatAutomation.reason)"

if (-not $environmentReport.ok -and -not $AllowEnvironmentBlockers) {
	throw "Platform environment has blockers. See $environmentReportPath"
}
