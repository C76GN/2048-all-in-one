param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\invoke_godot_project_tool.ps1" `
	-ScriptPath "res://tools/validate_project_layout.gd" `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $ProjectRoot `
	-ExpectedOutputPattern 'Project layout:' `
	-TimeoutSeconds $TimeoutSeconds

$reportPath = Join-Path $ProjectRoot "build\project_layout_report.json"
if (-not (Test-Path -LiteralPath $reportPath)) {
	throw "Project layout report was not created: $reportPath"
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (
	[int]$report.schema_version -ne 1 `
	-or [string]$report.kind -ne "project_layout_analysis" `
	-or [string]$report.evaluation_status -ne "complete" `
	-or -not $report.input_complete `
	-or -not $report.evaluation_complete `
	-or -not $report.success `
	-or [int]$report.warning_count -ne 0
) {
	throw "Project layout report contains errors or warnings: $reportPath"
}
