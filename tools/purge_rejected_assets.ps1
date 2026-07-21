param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[ValidateRange(1, 1800)]
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$reportPath = Join-Path $ProjectRoot "build\rejected_asset_purge_report.json"
if (Test-Path -LiteralPath $reportPath) {
	Remove-Item -LiteralPath $reportPath -Force
}
& "$PSScriptRoot\invoke_godot_project_tool.ps1" `
	-ScriptPath "res://features/asset_library/tools/purge_rejected_assets.gd" `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $ProjectRoot `
	-ExpectedOutputPattern 'Rejected asset purge:' `
	-TimeoutSeconds $TimeoutSeconds

if (-not (Test-Path -LiteralPath $reportPath)) {
	throw "Rejected asset purge report was not created: $reportPath"
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $report.ok) {
	throw "Rejected asset purge report is unhealthy: $reportPath"
}
