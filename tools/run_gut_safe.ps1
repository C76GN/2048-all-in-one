param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[string]$TestDir = "res://tests/gut",
	[string]$TestScripts = "",
	[string]$PostRunScript = "res://tests/gut/support/gf_test_shutdown_hook.gd",
	[string]$ExitLeakBaseline = ".gf/godot_exit_leak_baseline.json",
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
		"Parent node is busy adding/removing children",
		"Orphans"
	)
	return Find-OutputPatternLines $output $patterns
}

function Get-GodotExitLeakReport {
	param([string]$Text)

	$ridAllocations = @{}
	$ridPattern = [regex]"(?im)ERROR:\s+(\d+)\s+RID allocations of type '([^']+)' were leaked at exit\."
	foreach ($match in $ridPattern.Matches($Text)) {
		$count = [int]$match.Groups[1].Value
		$typeName = $match.Groups[2].Value
		if (-not $ridAllocations.ContainsKey($typeName) -or $count -gt $ridAllocations[$typeName]) {
			$ridAllocations[$typeName] = $count
		}
	}

	$objectDbInstances = 0
	$objectPattern = [regex]"(?im)(\d+)\s+ObjectDB instances were leaked at exit"
	foreach ($match in $objectPattern.Matches($Text)) {
		$objectDbInstances = [Math]::Max($objectDbInstances, [int]$match.Groups[1].Value)
	}

	$resourcesInUse = 0
	$resourcePattern = [regex]"(?im)(\d+)\s+resources still in use at exit"
	foreach ($match in $resourcePattern.Matches($Text)) {
		$resourcesInUse = [Math]::Max($resourcesInUse, [int]$match.Groups[1].Value)
	}

	$pagedAllocatorTypes = New-Object System.Collections.Generic.HashSet[string]
	$pagedPattern = [regex]"(?im)Pages in use exist at exit in PagedAllocator:\s+([^\r\n]+)"
	foreach ($match in $pagedPattern.Matches($Text)) {
		[void]$pagedAllocatorTypes.Add($match.Groups[1].Value.Trim())
	}

	$hasUncountedObjectLeak = $Text -match "(?im)ObjectDB instances were leaked at exit" -and $objectDbInstances -eq 0
	return [PSCustomObject]@{
		RidAllocations = $ridAllocations
		ObjectDbInstances = $objectDbInstances
		ResourcesInUse = $resourcesInUse
		PagedAllocatorTypes = @($pagedAllocatorTypes | Sort-Object)
		HasUncountedObjectLeak = $hasUncountedObjectLeak
		HasLeaks = $ridAllocations.Count -gt 0 -or $objectDbInstances -gt 0 -or $resourcesInUse -gt 0 -or $pagedAllocatorTypes.Count -gt 0 -or $hasUncountedObjectLeak
	}
}

function Get-GodotExitLeakBaselineIssues {
	param(
		[object]$Report,
		[string]$BaselinePath
	)

	$issues = New-Object System.Collections.Generic.List[string]
	if (-not $Report.HasLeaks) {
		return $issues
	}
	if ([string]::IsNullOrWhiteSpace($BaselinePath) -or -not (Test-Path -LiteralPath $BaselinePath)) {
		$issues.Add("Godot exit leaks were reported, but no baseline exists: $BaselinePath")
		return $issues
	}

	try {
		$baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath $BaselinePath | ConvertFrom-Json
	} catch {
		$issues.Add("Godot exit leak baseline is invalid JSON: $($_.Exception.Message)")
		return $issues
	}

	if ([int]$baseline.schema_version -ne 1) {
		$issues.Add("Unsupported Godot exit leak baseline schema_version: $($baseline.schema_version)")
	}
	$baselineDirectory = Split-Path -Parent $BaselinePath
	$vendorLockPath = Join-Path $baselineDirectory "vendor.lock.json"
	$baselineVendorTree = [string]$baseline.gf_vendor_tree_sha256
	$baselineSourceCommit = [string]$baseline.gf_source_commit
	if ([string]::IsNullOrWhiteSpace($baselineVendorTree) -or [string]::IsNullOrWhiteSpace($baselineSourceCommit)) {
		$issues.Add("Godot exit leak baseline must record the audited GF vendor tree and source commit.")
	} elseif (-not (Test-Path -LiteralPath $vendorLockPath)) {
		$issues.Add("GF vendor lock is missing beside the exit leak baseline: $vendorLockPath")
	} else {
		try {
			$vendorLock = Get-Content -Raw -Encoding UTF8 -LiteralPath $vendorLockPath | ConvertFrom-Json
			if ([string]$vendorLock.vendor_tree_sha256 -ne $baselineVendorTree) {
				$issues.Add("Godot exit leak baseline vendor tree does not match .gf/vendor.lock.json; audit and recalibrate the pinned GF snapshot.")
			}
			if ([string]$vendorLock.source_commit -ne $baselineSourceCommit) {
				$issues.Add("Godot exit leak baseline source commit does not match .gf/vendor.lock.json; audit and recalibrate the pinned GF snapshot.")
			}
		} catch {
			$issues.Add("GF vendor lock is invalid JSON: $($_.Exception.Message)")
		}
	}
	if ($Report.HasUncountedObjectLeak) {
		$issues.Add("Godot reported an uncounted ObjectDB leak that cannot be compared safely.")
	}

	$maxObjectDbInstances = [int]$baseline.max_objectdb_instances
	if ($Report.ObjectDbInstances -gt $maxObjectDbInstances) {
		$issues.Add("ObjectDB leak regression: $($Report.ObjectDbInstances) > baseline $maxObjectDbInstances")
	}

	$maxResourcesInUse = [int]$baseline.max_resources_in_use
	if ($Report.ResourcesInUse -gt $maxResourcesInUse) {
		$issues.Add("Resource leak regression: $($Report.ResourcesInUse) > baseline $maxResourcesInUse")
	}

	$allowedRidAllocations = @{}
	if ($null -ne $baseline.max_rid_allocations_by_type) {
		foreach ($property in $baseline.max_rid_allocations_by_type.PSObject.Properties) {
			$allowedRidAllocations[$property.Name] = [int]$property.Value
		}
	}
	foreach ($typeName in $Report.RidAllocations.Keys) {
		if (-not $allowedRidAllocations.ContainsKey($typeName)) {
			$issues.Add("New leaked RID type: $typeName ($($Report.RidAllocations[$typeName]))")
			continue
		}
		if ($Report.RidAllocations[$typeName] -gt $allowedRidAllocations[$typeName]) {
			$issues.Add("RID leak regression for ${typeName}: $($Report.RidAllocations[$typeName]) > baseline $($allowedRidAllocations[$typeName])")
		}
	}

	$allowedPagedAllocatorTypes = @($baseline.allowed_paged_allocator_types)
	foreach ($typeName in $Report.PagedAllocatorTypes) {
		if ($allowedPagedAllocatorTypes -notcontains $typeName) {
			$issues.Add("New PagedAllocator leak type: $typeName")
		}
	}
	return $issues
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
$resolvedExitLeakBaseline = ""
if (-not [string]::IsNullOrWhiteSpace($ExitLeakBaseline)) {
	$resolvedExitLeakBaseline = Join-Path $resolvedProjectRoot $ExitLeakBaseline
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
		"res://addons/gut/gut_cmdln.gd"
	)
	if ([string]::IsNullOrWhiteSpace($TestScripts)) {
		$arguments += "-gdir=$TestDir"
		$arguments += "-ginclude_subdirs"
	} else {
		$arguments += "-gtest=$TestScripts"
	}
	$arguments += "-gexit"
	if (-not [string]::IsNullOrWhiteSpace($PostRunScript)) {
		$arguments += "-gpost_run_script=$PostRunScript"
	}

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

	$combinedOutput = Get-CombinedOutputText @($stdoutFile, $stderrFile, $logFile)
	$exitLeakReport = Get-GodotExitLeakReport $combinedOutput
	$exitLeakIssues = Get-GodotExitLeakBaselineIssues $exitLeakReport $resolvedExitLeakBaseline
	if ($exitLeakIssues.Count -gt 0) {
		Write-Host "ERROR: Godot exit leak baseline regressed:"
		foreach ($issue in $exitLeakIssues) {
			Write-Host "  $issue"
		}
		if ($exitCode -eq 0) {
			$exitCode = 1
		}
	} elseif ($exitLeakReport.HasLeaks) {
		Write-Warning "Godot reported known GF/GUT shutdown debt within the reviewed baseline: ObjectDB=$($exitLeakReport.ObjectDbInstances), Resources=$($exitLeakReport.ResourcesInUse), RID types=$($exitLeakReport.RidAllocations.Count)."
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
