param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[string]$TestDir = "res://tests/gut",
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 180,
	[ValidateRange(1, 1024)]
	[int]$MaxLogMB = 32,
	[ValidateRange(0, 1024)]
	[int]$MaxDefaultLogGrowthKB = 256,
	[ValidateRange(50, 5000)]
	[int]$PollIntervalMilliseconds = 100,
	[switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

function ConvertTo-CommandLineArgument {
	param([string]$Argument)

	if ($Argument -notmatch '[\s"]') {
		return $Argument
	}

	return '"' + ($Argument -replace '"', '\"') + '"'
}

function Get-FileLength {
	param([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path)) {
		return 0
	}

	if (-not (Test-Path -LiteralPath $Path)) {
		return 0
	}

	return (Get-Item -LiteralPath $Path).Length
}

function Get-FileGrowth {
	param(
		[string]$Path,
		[int64]$BaselineLength
	)

	$currentLength = Get-FileLength $Path
	if ($currentLength -le $BaselineLength) {
		return 0
	}

	return $currentLength - $BaselineLength
}

function Get-CombinedOutputText {
	param([string[]]$Paths)

	$output = ""
	foreach ($path in $Paths) {
		if (Test-Path -LiteralPath $path) {
			$output += "`n"
			$output += Get-Content -Raw -Encoding UTF8 -LiteralPath $path
		}
	}
	return $output
}

function Find-OutputPatternLines {
	param(
		[string]$Text,
		[string[]]$Patterns,
		[int]$Limit = 30
	)

	$matches = New-Object System.Collections.Generic.List[string]
	foreach ($line in ($Text -split "`r?`n")) {
		foreach ($pattern in $Patterns) {
			if ($line.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
				$matches.Add($line.Trim())
				break
			}
		}

		if ($matches.Count -ge $Limit) {
			break
		}
	}
	return $matches
}

function Get-GodotValidationIssues {
	param([string[]]$OutputPaths)

	$output = Get-CombinedOutputText $OutputPaths
	$patterns = @(
		"SCRIPT ERROR",
		"Parse Error:",
		"ERROR: Failed to load script",
		"GDScript::reload:",
		"UNSAFE_",
		"SHADOWED_",
		"RETURN_VALUE_DISCARDED",
		"MISSING_AWAIT",
		"requires the subtype",
		"is shadowing an already-declared",
		"The `"await`" keyword is unnecessary",
		"remove_child() can't be called",
		"Parent node is busy adding/removing children"
	)
	return Find-OutputPatternLines $output $patterns
}

function Stop-ProcessSafely {
	param([System.Diagnostics.Process]$Process)

	if ($null -eq $Process -or $Process.HasExited) {
		return
	}

	try {
		$Process.Kill()
		$Process.WaitForExit(5000)
	} catch {
		Write-Warning "Failed to stop Godot process cleanly: $($_.Exception.Message)"
	}
}

function Resolve-GodotExitCode {
	param(
		[System.Diagnostics.Process]$Process,
		[string]$StdoutPath,
		[string]$GodotLogPath
	)

	$Process.WaitForExit()
	$exitCode = $Process.ExitCode
	if ($null -ne $exitCode -and -not [string]::IsNullOrWhiteSpace([string]$exitCode)) {
		return [int]$exitCode
	}

	$output = ""
	foreach ($path in @($StdoutPath, $GodotLogPath)) {
		if (Test-Path -LiteralPath $path) {
			$output += Get-Content -Raw -Encoding UTF8 -LiteralPath $path
		}
	}

	if ($output -match "All tests passed") {
		Write-Warning "Godot process did not expose an exit code; inferred success from GUT output."
		return 0
	}

	Write-Warning "Godot process did not expose an exit code; inferred failure from missing GUT success marker."
	return 1
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
if (-not (Test-Path -LiteralPath $projectFile)) {
	throw "Project root does not contain project.godot: $resolvedProjectRoot"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$runRoot = Join-Path ([System.IO.Path]::GetTempPath()) "2048-all-in-one-gut-$timestamp-$runId"
$appData = Join-Path $runRoot "appdata"
$localAppData = Join-Path $runRoot "localappdata"
$userProfile = Join-Path $runRoot "userprofile"
$tempDir = Join-Path $runRoot "temp"
$logFile = Join-Path $runRoot "godot.log"
$stdoutFile = Join-Path $runRoot "stdout.log"
$stderrFile = Join-Path $runRoot "stderr.log"

New-Item -ItemType Directory -Force -Path $appData, $localAppData, $userProfile, $tempDir | Out-Null

$originalEnv = @{}
foreach ($name in @("APPDATA", "LOCALAPPDATA", "USERPROFILE", "TEMP", "TMP")) {
	$originalEnv[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$defaultGodotLog = ""
if (-not [string]::IsNullOrWhiteSpace($originalEnv["APPDATA"])) {
	$defaultGodotLog = Join-Path $originalEnv["APPDATA"] "Godot\app_userdata\2048-all-in-one\logs\godot.log"
}
$defaultLogLengthBefore = Get-FileLength $defaultGodotLog

try {
	$env:APPDATA = $appData
	$env:LOCALAPPDATA = $localAppData
	$env:USERPROFILE = $userProfile
	$env:TEMP = $tempDir
	$env:TMP = $tempDir

	$arguments = @(
		"--headless",
		"--log-file",
		$logFile,
		"--path",
		$resolvedProjectRoot,
		"-s",
		"res://addons/gut/gut_cmdln.gd",
		"-gdir=$TestDir",
		"-ginclude_subdirs",
		"-gexit"
	)

	$argumentLine = ($arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join " "
	Write-Host "Run root: $runRoot"
	Write-Host "Godot log: $logFile"
	Write-Host "Command: $GodotExecutable $argumentLine"

	$process = Start-Process `
		-FilePath $GodotExecutable `
		-ArgumentList $argumentLine `
		-WorkingDirectory $resolvedProjectRoot `
		-RedirectStandardOutput $stdoutFile `
		-RedirectStandardError $stderrFile `
		-NoNewWindow `
		-PassThru

	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while (-not $process.HasExited) {
		Start-Sleep -Milliseconds $PollIntervalMilliseconds

		if ((Get-Date) -gt $deadline) {
			Stop-ProcessSafely $process
			Write-Host "ERROR: Godot/GUT timed out after $TimeoutSeconds seconds. Logs kept at: $runRoot"
			exit 124
		}

		$logLengthMB = (Get-FileLength $logFile) / 1MB
		if ($logLengthMB -gt $MaxLogMB) {
			Stop-ProcessSafely $process
			Write-Host "ERROR: Godot log exceeded ${MaxLogMB}MB. Logs kept at: $runRoot"
			exit 125
		}

		$defaultLogGrowthKB = (Get-FileGrowth $defaultGodotLog $defaultLogLengthBefore) / 1KB
		if ($defaultLogGrowthKB -gt $MaxDefaultLogGrowthKB) {
			Stop-ProcessSafely $process
			Write-Host "ERROR: Default Godot user log grew by $([Math]::Round($defaultLogGrowthKB, 3))KB. Logs kept at: $runRoot"
			Write-Host "Default Godot log: $defaultGodotLog"
			exit 126
		}
	}

	$exitCode = Resolve-GodotExitCode $process $stdoutFile $logFile
	$defaultLogGrowthKB = (Get-FileGrowth $defaultGodotLog $defaultLogLengthBefore) / 1KB
	if ($defaultLogGrowthKB -gt $MaxDefaultLogGrowthKB) {
		Write-Host "ERROR: Default Godot user log grew by $([Math]::Round($defaultLogGrowthKB, 3))KB despite isolation."
		Write-Host "Default Godot log: $defaultGodotLog"
		$exitCode = 126
	} elseif ($defaultLogGrowthKB -gt 0) {
		Write-Warning "Default Godot user log changed by $([Math]::Round($defaultLogGrowthKB, 3))KB despite isolation: $defaultGodotLog"
	}

	$validationIssues = Get-GodotValidationIssues @($stdoutFile, $stderrFile, $logFile)
	if ($validationIssues.Count -gt 0) {
		Write-Host "ERROR: Godot reported script warnings/errors despite test completion:"
		foreach ($issue in $validationIssues) {
			Write-Host "  $issue"
		}
		if ($exitCode -eq 0) {
			$exitCode = 1
		}
	}

	Write-Host "Exit code: $exitCode"
	Write-Host "Stdout: $stdoutFile"
	Write-Host "Stderr: $stderrFile"
	Write-Host "Godot log size: $([Math]::Round((Get-FileLength $logFile) / 1MB, 3)) MB"

	if ($exitCode -eq 0 -and -not $KeepTemp) {
		Remove-Item -LiteralPath $runRoot -Recurse -Force
		Write-Host "Temporary run directory removed."
	} else {
		Write-Host "Temporary run directory kept: $runRoot"
	}

	exit $exitCode
}
finally {
	foreach ($name in $originalEnv.Keys) {
		[Environment]::SetEnvironmentVariable($name, $originalEnv[$name], "Process")
	}
}
