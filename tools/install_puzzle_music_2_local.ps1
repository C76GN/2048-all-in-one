[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$SourceDirectory,

    [string]$UserDataRoot = "",

    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$tracks = [ordered]@{
    "Attempt.wav"  = "attempt"
    "Blue.wav"     = "blue"
    "Fill.wav"     = "fill"
    "Known.wav"    = "known"
    "Lesson.wav"   = "lesson"
    "Onward.wav"   = "onward"
    "Overdone.wav" = "overdone"
    "Rotation.wav" = "rotation"
    "Slumber.wav"  = "slumber"
    "Thorough.wav" = "thorough"
}

if ([string]::IsNullOrWhiteSpace($UserDataRoot)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "无法推导 Godot user://：请显式传入 -UserDataRoot。"
    }
    $UserDataRoot = Join-Path $env:APPDATA "Godot\app_userdata\2048-all-in-one"
}

$sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
$userRoot = [System.IO.Path]::GetFullPath($UserDataRoot)
$packageRoot = Join-Path $userRoot "content_packages\puzzle_music_2"
$audioRoot = Join-Path $packageRoot "audio"
$manifestPath = Join-Path $packageRoot "gf_content_package.json"
$noticePath = Join-Path $packageRoot "SOURCE_AND_LICENSE.txt"

$sourceFiles = @()
foreach ($fileName in $tracks.Keys) {
    $matchingFiles = @(
        Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
            Where-Object { $_.Name -ieq $fileName }
    )
    if ($matchingFiles.Count -eq 0) {
        throw "源素材不完整，缺少：$fileName"
    }
    if ($matchingFiles.Count -gt 1) {
        throw "源素材中存在多个同名曲目，无法确定：$fileName"
    }
    $sourcePath = $matchingFiles[0].FullName
    $sourceFiles += [pscustomobject]@{
        FileName = $fileName
        Slug = $tracks[$fileName]
        SourcePath = $sourcePath
        Sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

foreach ($sourceFile in $sourceFiles) {
    $destinationPath = Join-Path $audioRoot $sourceFile.FileName
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        continue
    }
    $destinationHash = (
        Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($destinationHash -ne $sourceFile.Sha256 -and -not $Force) {
        throw "目标已有不同内容：$destinationPath。确认覆盖时请追加 -Force。"
    }
}

[System.IO.Directory]::CreateDirectory($audioRoot) | Out-Null
foreach ($sourceFile in $sourceFiles) {
    $destinationPath = Join-Path $audioRoot $sourceFile.FileName
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $destinationHash = (
            Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($destinationHash -eq $sourceFile.Sha256) {
            continue
        }
    }
    Copy-Item -LiteralPath $sourceFile.SourcePath -Destination $destinationPath -Force
}

$resources = @()
foreach ($sourceFile in $sourceFiles) {
    $resources += [ordered]@{
        key = "asset.audio.music.puzzle_music_2.$($sourceFile.Slug)"
        path = "audio/$($sourceFile.FileName)"
        type_hint = "AudioStreamWAV"
        priority = 100
        metadata = [ordered]@{
            tags = @("audio", "music", "bgm", "puzzle_music_2")
            asset_kind = "audio"
            category = "music"
            playlist = "puzzle_music_2"
            track_title = [System.IO.Path]::GetFileNameWithoutExtension(
                $sourceFile.FileName
            )
            origin = "third_party_local_purchase"
            author = "GravitySound"
            source = "Puzzle Music 2"
            source_url = "https://www.gamedevmarket.net/asset/puzzle-music-2"
            license = "GameDev Market Pro Licence"
            redistribution = "standalone_source_files_prohibited"
            source_sha256 = $sourceFile.Sha256
        }
    }
}

$manifest = [ordered]@{
    schema_version = 1
    package_id = "c76.local_audio.puzzle_music_2"
    display_name = "Puzzle Music 2 (Local Licensed Install)"
    version = "1.0.0-local"
    content_types = @("asset_library", "audio", "music")
    safety_kind = "data_only"
    resources = $resources
    metadata = [ordered]@{
        author = "GravitySound"
        source_url = "https://www.gamedevmarket.net/asset/puzzle-music-2"
        license = "GameDev Market Pro Licence"
        install_scope = "local_user_data_only"
        redistribution = "standalone_source_files_prohibited"
    }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$manifestJson = $manifest | ConvertTo-Json -Depth 12
$manifestTemporaryPath = "$manifestPath.tmp"
[System.IO.File]::WriteAllText(
    $manifestTemporaryPath,
    $manifestJson + [Environment]::NewLine,
    $utf8NoBom
)
Move-Item -LiteralPath $manifestTemporaryPath -Destination $manifestPath -Force

$notice = @"
Puzzle Music 2
Creator: GravitySound
Source: https://www.gamedevmarket.net/asset/puzzle-music-2
License: GameDev Market Pro Licence (local purchased copy)

This installer keeps the purchased WAV files in this user's Godot data directory.
Do not commit, publish, sell, or redistribute the source WAV files as standalone assets.
"@
[System.IO.File]::WriteAllText(
    $noticePath,
    $notice.Trim() + [Environment]::NewLine,
    $utf8NoBom
)

Write-Host "Puzzle Music 2 已安装到 Godot 本地内容包目录："
Write-Host $packageRoot
Write-Host "已登记 $($resources.Count) 个稳定资源键；未修改项目仓库，也未保存源目录路径。"
