# Thin, zero-policy entry point. The historically named shared exporter owns the
# audited assembly transaction and selects the full-game profile through -Profile.
& (Join-Path $PSScriptRoot "export_wechat_minigame_smoke.ps1") -Profile Release @args
