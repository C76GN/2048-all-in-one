$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    godot --headless --path . --script res://tools/import_asset_sources.gd
} finally {
    Pop-Location
}
