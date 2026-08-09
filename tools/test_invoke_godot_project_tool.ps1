param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

function ConvertTo-TestCommandLineArgument {
	param([string]$Argument)

	if ($Argument -notmatch '[\s"]') {
		return $Argument
	}
	return '"' + ($Argument -replace '"', '\"') + '"'
}

function Assert-TestCondition {
	param(
		[bool]$Condition,
		[string]$Message
	)

	if (-not $Condition) {
		throw $Message
	}
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$invokeScript = Join-Path $PSScriptRoot "invoke_godot_project_tool.ps1"
$fixtureScript = "res://tools/test_fixtures/project_tool_wait.gd"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
	"2048-project-tool-identity-test-{0}" -f ([guid]::NewGuid().ToString("N"))
)
$unrelatedLog = Join-Path $testRoot "unrelated-godot.log"
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

$invokeJob = $null
$unrelatedProcess = $null
$invokeRunRoot = $null
$completedSuccessfully = $false
try {
	$invokeJob = Start-Job -ScriptBlock {
		param(
			[string]$InvokeScript,
			[string]$FixtureScript,
			[string]$Godot,
			[string]$Root
		)
		& $InvokeScript `
			-ScriptPath $FixtureScript `
			-GodotExecutable $Godot `
			-ProjectRoot $Root `
			-TimeoutSeconds 3 `
			-PollIntervalMilliseconds 50 6>&1
	} -ArgumentList @(
		$invokeScript,
		$fixtureScript,
		$GodotExecutable,
		$resolvedProjectRoot
	)

	# 让包装器完成 baseline/启动阶段，再启动同项目、同脚本的
	# 无关 Godot。旧实现会因项目根匹配将它误认为派生进程并强杀。
	Start-Sleep -Milliseconds 1000
	$unrelatedArguments = @(
		"--headless",
		"--log-file", $unrelatedLog,
		"--path", $resolvedProjectRoot,
		"--script", $fixtureScript
	)
	$unrelatedArgumentLine = (
		$unrelatedArguments |
			ForEach-Object { ConvertTo-TestCommandLineArgument $_ }
	) -join " "
	$unrelatedProcess = Start-Process `
		-FilePath $GodotExecutable `
		-ArgumentList $unrelatedArgumentLine `
		-WorkingDirectory $resolvedProjectRoot `
		-WindowStyle Hidden `
		-PassThru
	Start-Sleep -Milliseconds 500
	$unrelatedProcess.Refresh()
	Assert-TestCondition `
		(-not $unrelatedProcess.HasExited) `
		"The unrelated Godot fixture exited before the timeout race was exercised."

	$finishedJob = Wait-Job -Job $invokeJob -Timeout 12
	Assert-TestCondition `
		($null -ne $finishedJob) `
		"invoke_godot_project_tool.ps1 did not finish its timeout path."
	$jobErrors = @()
	$jobOutput = @(
		Receive-Job -Job $invokeJob -ErrorVariable +jobErrors -ErrorAction SilentlyContinue
	)
	$combinedJobOutput = (@($jobOutput) + @($jobErrors) | Out-String)
	if ($combinedJobOutput -match 'Run root:\s*([^\r\n]+)') {
		$invokeRunRoot = $Matches[1].Trim()
	}
	Assert-TestCondition `
		($combinedJobOutput -match "timed out after 3 seconds") `
		"The fixture did not exercise the expected timeout path. Output: $combinedJobOutput"

	$unrelatedProcess.Refresh()
	Assert-TestCondition `
		(-not $unrelatedProcess.HasExited) `
		"Timeout cleanup killed an unrelated Godot process from the same project."

	$completedSuccessfully = $true
	Write-Host "PASS: timeout cleanup preserved the unrelated same-project Godot process."
}
finally {
	if ($null -ne $unrelatedProcess) {
		$unrelatedProcess.Refresh()
		if (-not $unrelatedProcess.HasExited) {
			Stop-Process -Id $unrelatedProcess.Id -Force -ErrorAction SilentlyContinue
		}
	}
	if ($null -ne $invokeJob) {
		if ($invokeJob.State -eq "Running") {
			Stop-Job -Job $invokeJob -ErrorAction SilentlyContinue
		}
		Remove-Job -Job $invokeJob -Force -ErrorAction SilentlyContinue
	}
	if (Test-Path -LiteralPath $testRoot) {
		Remove-Item -LiteralPath $testRoot -Recurse -Force
	}
	if (
		-not [string]::IsNullOrWhiteSpace($invokeRunRoot) `
		-and (Split-Path -Leaf $invokeRunRoot) -like '2048-project-tool-*' `
		-and (Split-Path -Parent $invokeRunRoot).TrimEnd('\') -eq ([IO.Path]::GetTempPath()).TrimEnd('\') `
		-and (Test-Path -LiteralPath $invokeRunRoot)
	) {
		Remove-Item -LiteralPath $invokeRunRoot -Recurse -Force
	}
}

if (-not $completedSuccessfully) {
	exit 1
}
