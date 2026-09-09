param(
	[Parameter(Mandatory = $true)]
	[string]$ScriptPath,
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[string]$ExpectedOutputPattern = "",
	[switch]$Rendering,
	[ValidateSet("", "forward_plus", "mobile", "gl_compatibility")]
	[string]$RenderingMethod = "",
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

function Get-GodotToolRunProcesses {
	param(
		[int]$LauncherProcessId,
		[string]$RunLogFile,
		[string]$RequestedScriptPath
	)

	$allProcesses = @(Get-CimInstance Win32_Process)
	$descendantIds = New-Object 'System.Collections.Generic.HashSet[int]'
	[void]$descendantIds.Add($LauncherProcessId)
	$changed = $true
	while ($changed) {
		$changed = $false
		foreach ($candidate in $allProcesses) {
			$processId = [int]$candidate.ProcessId
			$parentProcessId = [int]$candidate.ParentProcessId
			if (
				-not $descendantIds.Contains($processId) `
				-and $descendantIds.Contains($parentProcessId)
			) {
				[void]$descendantIds.Add($processId)
				$changed = $true
			}
		}
	}

	$matches = @()
	foreach ($candidate in @($allProcesses | Where-Object { $_.Name -like 'godot*.exe' })) {
		$processId = [int]$candidate.ProcessId
		if ($processId -eq $LauncherProcessId) {
			continue
		}
		$commandLine = [string]$candidate.CommandLine
		$hasRunIdentity = (
			$commandLine.IndexOf(
				$RunLogFile,
				[System.StringComparison]::OrdinalIgnoreCase
			) -ge 0 `
			-and $commandLine.IndexOf(
				$RequestedScriptPath,
				[System.StringComparison]::OrdinalIgnoreCase
			) -ge 0
		)
		if ($descendantIds.Contains($processId) -or $hasRunIdentity) {
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
$originalTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$runRoot = Join-Path $originalTempRoot (
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
	if (-not [string]::IsNullOrWhiteSpace($RenderingMethod)) {
		$arguments += @("--rendering-method", $RenderingMethod)
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
	# Retain the native process handle before it exits. On Windows, a detached
	# Process object can otherwise lose its exit code after the polling loop.
	$processHandle = $process.Handle

	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$lastObservedActivity = Get-Date
	do {
		Start-Sleep -Milliseconds $PollIntervalMilliseconds
		$process.Refresh()
		$derivedProcesses = @()
		if ($process.HasExited) {
			# A launcher may hand off to a child, but an active primary process
			# already keeps this run alive. Avoid polling every Windows process
			# through WMI during the actual game or performance measurement.
			$derivedProcesses = @(
				Get-GodotToolRunProcesses $process.Id $logFile $ScriptPath
			)
		}
		if (-not $process.HasExited -or $derivedProcesses.Count -gt 0) {
			$lastObservedActivity = Get-Date
		}
		if ((Get-Date) -gt $deadline) {
			$derivedProcesses = @(
				Get-GodotToolRunProcesses $process.Id $logFile $ScriptPath
			)
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
	$process.WaitForExit()
	$processExitCode = $process.ExitCode
	Write-Host "Godot project tool exit code: $processExitCode"
	if ($null -eq $processExitCode) {
		throw "Godot project tool exit code is unavailable. Logs kept at: $runRoot"
	}
	if (
		-not [string]::IsNullOrWhiteSpace($ExpectedOutputPattern) `
		-and $combinedOutput.IndexOf(
			$ExpectedOutputPattern,
			[System.StringComparison]::Ordinal
		) -lt 0
	) {
		throw "Godot project tool did not emit its completion marker '$ExpectedOutputPattern'. Logs kept at: $runRoot"
	}
	$diagnosticPattern = '(?im)SCRIPT ERROR|Parse Error:|ERROR: Failed to load script|GDScript::reload:|UNSAFE_|SHADOWED_|RETURN_VALUE_DISCARDED|MISSING_AWAIT|remove_child\(\) can''t be called|Parent node is busy (?:adding/removing|setting up) children'
	if ($combinedOutput -match $diagnosticPattern) {
		throw "Godot project tool reported script diagnostics. Logs kept at: $runRoot"
	}
	if ([int]$processExitCode -ne 0) {
		throw "Godot project tool exited with code $processExitCode. Logs kept at: $runRoot"
	}
	$completedSuccessfully = $true
}
finally {
	foreach ($name in $originalEnvironment.Keys) {
		[Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
	}
	if ($completedSuccessfully -and (Test-Path -LiteralPath $runRoot)) {
		$resolvedRunRoot = [IO.Path]::GetFullPath($runRoot).TrimEnd('\')
		if (
			-not [string]::Equals(
				[IO.Path]::GetDirectoryName($resolvedRunRoot),
				$originalTempRoot,
				[System.StringComparison]::OrdinalIgnoreCase
			) -or [IO.Path]::GetFileName($resolvedRunRoot) -notmatch '^2048-project-tool-\d{8}-\d{6}-[a-f0-9]{8}$'
		) {
			throw "Refusing cleanup outside the exact generated tool directory: $resolvedRunRoot"
		}
		# Godot shader-cache paths can exceed MAX_PATH. Native .NET deletion with
		# an extended path avoids PowerShell 5's truncated recursive enumeration.
		$extendedRunRoot = if ($resolvedRunRoot.StartsWith('\\')) {
			'\\?\UNC\' + $resolvedRunRoot.Substring(2)
		} else {
			'\\?\' + $resolvedRunRoot
		}
		[IO.Directory]::Delete($extendedRunRoot, $true)
	}
}
