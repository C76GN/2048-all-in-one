param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[string[]]$Include = @("scripts", "tests/gut", "tools"),
	[string[]]$ExcludePrefix = @("addons/gut"),
	[ValidateRange(1, 300)]
	[int]$StartupTimeoutSeconds = 120,
	[ValidateRange(1, 120)]
	[int]$RequestTimeoutSeconds = 60,
	[ValidateRange(1, 30)]
	[int]$PerFileTimeoutSeconds = 3,
	[ValidateRange(1, 60)]
	[int]$MaxFileTimeoutSeconds = 12,
	[ValidateRange(0, 8)]
	[int]$TimeoutRetries = 2,
	[string]$OutputJson = "build\gdscript_lsp_diagnostics.json",
	[switch]$AllowDiagnostics
)

$ErrorActionPreference = "Stop"

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$scriptPath = Join-Path $resolvedProjectRoot "tools\gdscript_lsp_diagnostics.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
	throw "Missing diagnostics script: $scriptPath"
}

$outputPath = Join-Path $resolvedProjectRoot $OutputJson
$outputDirectory = Split-Path -Parent $outputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
	New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$arguments = @(
	$scriptPath,
	"--project-root", $resolvedProjectRoot,
	"--godot", $GodotExecutable,
	"--spawn-lsp",
	"--port", "0",
	"--startup-timeout", ([string]$StartupTimeoutSeconds),
	"--request-timeout", ([string]$RequestTimeoutSeconds),
	"--per-file-timeout", ([string]$PerFileTimeoutSeconds),
	"--max-file-timeout", ([string]$MaxFileTimeoutSeconds),
	"--timeout-retries", ([string]$TimeoutRetries),
	"--format", "json",
	"--output-json", $outputPath
)

foreach ($path in $Include) {
	$arguments += @("--include", $path)
}

foreach ($prefix in $ExcludePrefix) {
	$arguments += @("--exclude-prefix", $prefix)
}

if ($AllowDiagnostics) {
	$arguments += "--allow-diagnostics"
}

python @arguments
$diagnosticsExitCode = $LASTEXITCODE
exit $diagnosticsExitCode
