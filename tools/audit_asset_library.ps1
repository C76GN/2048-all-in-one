$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    godot --headless --path . --script res://tools/audit_asset_library.gd
} finally {
    Pop-Location
}
