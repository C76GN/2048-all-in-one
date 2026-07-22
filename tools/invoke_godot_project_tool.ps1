param(
	[Parameter(Mandatory = $true)]
	[string]$ScriptPath,
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[string]$ExpectedOutputPattern = "",
	[switch]$Rendering,
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300,
	[ValidateRange(50, 5000)]
	[int]$PollIntervalMilliseconds = 100
)

$ErrorActionPreference = "Stop"

function ConvertTo-CommandLineArgument {
	param([string]$Argument)

	if ($Argument -notmatch '[\s"]') {
		return $Argument
	}
	return '"' + ($Argument -replace '"', '\"') + '"'
}

function Get-NewGodotToolProcesses {
	param(
		[System.Collections.Generic.HashSet[int]]$BaselineIds,
		[string]$ResolvedProjectRoot,
		[string]$RequestedScriptPath
	)

	$matches = @()
	foreach ($candidate in @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'godot*.exe' })) {
		$processId = [int]$candidate.ProcessId
		if ($BaselineIds.Contains($processId)) {
			continue
		}
		$commandLine = [string]$candidate.CommandLine
		if (
			$commandLine.IndexOf($RequestedScriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 `
			-or $commandLine.IndexOf($ResolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
		) {
			$matches += $candidate
		}
	}
	return $matches
}

function Get-CombinedOutput {
	param([string[]]$Paths)

	$result = ""
	foreach ($path in $Paths) {
		if (Test-Path -LiteralPath $path) {
			$result += "`n" + (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
		}
	}
	return $result
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$runRoot = Join-Path ([IO.Path]::GetTempPath()) (
	"2048-project-tool-{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
)
$appData = Join-Path $runRoot "appdata"
$localAppData = Join-Path $runRoot "localappdata"
$userProfile = Join-Path $runRoot "userprofile"
$tempDirectory = Join-Path $runRoot "temp"
$logFile = Join-Path $runRoot "godot.log"
$stdoutFile = Join-Path $runRoot "stdout.log"
$stderrFile = Join-Path $runRoot "stderr.log"
New-Item -ItemType Directory -Force -Path $appData, $localAppData, $userProfile, $tempDirectory | Out-Null

$baselineIds = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($process in @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'godot*.exe' })) {
	[void]$baselineIds.Add([int]$process.ProcessId)
}

$originalEnvironment = @{}
foreach ($name in @("APPDATA", "LOCALAPPDATA", "USERPROFILE", "TEMP", "TMP")) {
	$originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$completedSuccessfully = $false
try {
	$env:APPDATA = $appData
	$env:LOCALAPPDATA = $localAppData
	$env:USERPROFILE = $userProfile
	$env:TEMP = $tempDirectory
	$env:TMP = $tempDirectory

	$arguments = @()
	if (-not $Rendering) {
		$arguments += "--headless"
	}
	$arguments += @(
		"--log-file", $logFile,
		"--path", $resolvedProjectRoot,
		"--script", $ScriptPath
	)
	$argumentLine = ($arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join " "
	Write-Host "Godot project tool: $ScriptPath"
	Write-Host "Run root: $runRoot"

	$process = Start-Process `
		-FilePath $GodotExecutable `
		-ArgumentList $argumentLine `
		-WorkingDirectory $resolvedProjectRoot `
		-RedirectStandardOutput $stdoutFile `
		-RedirectStandardError $stderrFile `
		-WindowStyle Hidden `
		-PassThru

	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$lastObservedActivity = Get-Date
	do {
		Start-Sleep -Milliseconds $PollIntervalMilliseconds
		$process.Refresh()
		$derivedProcesses = @(Get-NewGodotToolProcesses $baselineIds $resolvedProjectRoot $ScriptPath)
		if (-not $process.HasExited -or $derivedProcesses.Count -gt 0) {
			$lastObservedActivity = Get-Date
		}
		if ((Get-Date) -gt $deadline) {
			foreach ($derivedProcess in $derivedProcesses) {
				Stop-Process -Id ([int]$derivedProcess.ProcessId) -Force -ErrorAction SilentlyContinue
			}
			if (-not $process.HasExited) {
				Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
			}
			throw "Godot project tool timed out after $TimeoutSeconds seconds. Logs kept at: $runRoot"
		}
	} while (
		-not $process.HasExited `
		-or $derivedProcesses.Count -gt 0 `
		-or ((Get-Date) - $lastObservedActivity).TotalMilliseconds -lt 1000
	)

	$combinedOutput = Get-CombinedOutput @($stdoutFile, $stderrFile, $logFile)
	if (-not [string]::IsNullOrWhiteSpace($combinedOutput)) {
		Write-Host $combinedOutput.Trim()
	}
	if (
		-not [string]::IsNullOrWhiteSpace($ExpectedOutputPattern) `
		-and $combinedOutput -notmatch $ExpectedOutputPattern
	) {
		throw "Godot project tool did not emit its completion marker '$ExpectedOutputPattern'. Logs kept at: $runRoot"
	}
	$diagnosticPattern = '(?im)SCRIPT ERROR|Parse Error:|ERROR: Failed to load script|GDScript::reload:|UNSAFE_|SHADOWED_|RETURN_VALUE_DISCARDED|MISSING_AWAIT|remove_child\(\) can''t be called|Parent node is busy adding/removing children'
	if ($combinedOutput -match $diagnosticPattern) {
		throw "Godot project tool reported script diagnostics. Logs kept at: $runRoot"
	}
	$processExitCode = $null
	if ($process.HasExited) {
		try {
			$processExitCode = $process.ExitCode
		} catch {
			$processExitCode = $null
		}
	}
	if ($null -ne $processExitCode -and [int]$processExitCode -ne 0) {
		throw "Godot project tool exited with code $processExitCode. Logs kept at: $runRoot"
	}
	$completedSuccessfully = $true
}
finally {
	foreach ($name in $originalEnvironment.Keys) {
		[Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
	}
	if ($completedSuccessfully -and (Test-Path -LiteralPath $runRoot)) {
		Remove-Item -LiteralPath $runRoot -Recurse -Force
	}
}
