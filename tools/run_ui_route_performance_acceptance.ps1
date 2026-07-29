param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = ".",
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$reportPath = Join-Path $resolvedProjectRoot (
	"build\ui_route_performance\route_timing_report.json"
)
$invokerPath = Join-Path $resolvedProjectRoot (
	"tools\invoke_godot_project_tool.ps1"
)

& powershell `
	-ExecutionPolicy Bypass `
	-File $invokerPath `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $resolvedProjectRoot `
	-ScriptPath "res://tools/run_ui_route_performance_acceptance.gd" `
	-Rendering `
	-ExpectedOutputPattern "[UiRoutePerformance] report=" `
	-TimeoutSeconds $TimeoutSeconds

if ($LASTEXITCODE -ne 0) {
	throw "UI route performance Godot run failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
	throw "UI route performance report was not generated: $reportPath"
}

$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
	ConvertFrom-Json
$summary = $report.summary
Write-Host (
	"UI route performance: passed={0}, ui={1}/{2} failed, scene={3}/{4} failed, preload={5}/{6} failed" -f
	[bool]$report.passed,
	[int]$summary.ui_route_failure_count,
	[int]$summary.ui_route_count,
	[int]$summary.scene_route_failure_count,
	[int]$summary.scene_route_count,
	[int]$summary.scene_preload_failure_count,
	[int]$summary.scene_preload_count
)
Write-Host "Report: $reportPath"

if (-not [bool]$report.passed) {
	throw "UI route performance acceptance failed. Review: $reportPath"
}
