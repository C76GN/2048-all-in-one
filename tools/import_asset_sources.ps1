param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[ValidateRange(1, 7200)]
	[int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\invoke_godot_project_tool.ps1" `
	-ScriptPath "res://features/asset_library/tools/import_asset_sources.gd" `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $ProjectRoot `
	-ExpectedOutputPattern 'Asset source import:' `
	-TimeoutSeconds $TimeoutSeconds

$reportPath = Join-Path $ProjectRoot "features\asset_library\resources\reports\source_import_report.json"
if (-not (Test-Path -LiteralPath $reportPath)) {
	throw "Asset import report was not created: $reportPath"
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $report.ok) {
	throw "Asset import report is unhealthy: $reportPath"
}
