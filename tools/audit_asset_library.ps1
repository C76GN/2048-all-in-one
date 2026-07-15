param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\invoke_godot_project_tool.ps1" `
	-ScriptPath "res://features/asset_library/tools/audit_asset_library.gd" `
	-GodotExecutable $GodotExecutable `
	-ProjectRoot $ProjectRoot `
	-ExpectedOutputPattern 'Asset audit:' `
	-TimeoutSeconds $TimeoutSeconds

foreach ($relativePath in @(
	"features\asset_library\resources\reports\asset_audit.json",
	"features\asset_library\resources\reports\review_catalog_audit.json"
)) {
	$reportPath = Join-Path $ProjectRoot $relativePath
	if (-not (Test-Path -LiteralPath $reportPath)) {
		throw "Asset audit report was not created: $reportPath"
	}
	$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
	if (-not $report.ok) {
		throw "Asset audit report is unhealthy: $reportPath"
	}
}
