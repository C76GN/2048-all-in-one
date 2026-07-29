[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$SourceDirectory,

    [string]$UserDataRoot = "",

    [string]$FfmpegPath = "ffmpeg",

    [ValidateRange(-1, 10)]
    [int]$OggQuality = 5,

    [switch]$PlanOnly,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FfmpegExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        throw "FFmpeg 路径不能为空。"
    }
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($Candidate)
    }

    $commands = @(
        Get-Command -Name $Candidate -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandType -in @(
                    [System.Management.Automation.CommandTypes]::Application,
                    [System.Management.Automation.CommandTypes]::ExternalScript
                )
            }
    )
    if ($commands.Count -eq 0) {
        throw (
            "找不到 FFmpeg：$Candidate。请用 -FfmpegPath 指向 ffmpeg.exe，" +
            "例如 E:\_software\ffmpeg-8.1\bin\ffmpeg.exe。"
        )
    }
    return [System.IO.Path]::GetFullPath($commands[0].Source)
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function New-OggEncodingArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [int]$Quality
    )

    return @(
        "-hide_banner",
        "-loglevel", "error",
        "-nostdin",
        "-y",
        "-i", $InputPath,
        "-map", "0:a:0",
        "-map_metadata", "-1",
        "-vn",
        "-c:a", "libvorbis",
        "-q:a", $Quality.ToString(
            [System.Globalization.CultureInfo]::InvariantCulture
        ),
        $OutputPath
    )
}

function Format-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $quotedArguments = @(
        foreach ($argument in $Arguments) {
            "'" + $argument.Replace("'", "''") + "'"
        }
    )
    return (
        "& '" + $Executable.Replace("'", "''") + "' " +
        ($quotedArguments -join " ")
    )
}

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
$ffmpegExecutable = Resolve-FfmpegExecutable -Candidate $FfmpegPath
$encodingProfile = "ffmpeg-libvorbis-q$OggQuality"

$allSourceFiles = @(
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File
)
$sourceFiles = @()
foreach ($fileName in $tracks.Keys) {
    $matchingFiles = @(
        $allSourceFiles |
            Where-Object {
                $_.Name.Equals(
                    $fileName,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    if ($matchingFiles.Count -eq 0) {
        throw "源素材不完整，缺少：$fileName"
    }
    if ($matchingFiles.Count -gt 1) {
        throw "源素材中存在多个同名曲目，无法确定：$fileName"
    }
    $sourcePath = $matchingFiles[0].FullName
    $outputFileName = [System.IO.Path]::ChangeExtension($fileName, ".ogg")
    $sourceFiles += [pscustomobject]@{
        FileName = $fileName
        OutputFileName = $outputFileName
        Slug = $tracks[$fileName]
        ResourceKey = "asset.audio.music.puzzle_music_2.$($tracks[$fileName])"
        SourcePath = $sourcePath
        SourceByteCount = $matchingFiles[0].Length
        SourceSha256 = (
            Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        RelativePath = "audio/$outputFileName"
        DestinationPath = Join-Path $audioRoot $outputFileName
        EncodedSha256 = ""
        EncodedByteCount = 0
        ConversionRequired = $true
        TemporaryPath = ""
    }
}

$existingResourcesByKey = @{}
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $existingManifest = (
            Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
                ConvertFrom-Json
        )
        $existingResources = Get-ObjectPropertyValue `
            -InputObject $existingManifest `
            -Name "resources"
        foreach ($resource in @($existingResources)) {
            $resourceKey = [string](
                Get-ObjectPropertyValue -InputObject $resource -Name "key"
            )
            if (-not [string]::IsNullOrWhiteSpace($resourceKey)) {
                $existingResourcesByKey[$resourceKey] = $resource
            }
        }
    }
    catch {
        if (-not $Force) {
            throw (
                "现有内容包清单无法读取；为避免覆盖未知本地内容，" +
                "请检查 $manifestPath，确认后再追加 -Force。原错误：$($_.Exception.Message)"
            )
        }
    }
}

foreach ($sourceFile in $sourceFiles) {
    if (-not (Test-Path -LiteralPath $sourceFile.DestinationPath -PathType Leaf)) {
        continue
    }

    $reusable = $false
    $existingResource = $existingResourcesByKey[$sourceFile.ResourceKey]
    if ($null -ne $existingResource) {
        $existingMetadata = Get-ObjectPropertyValue `
            -InputObject $existingResource `
            -Name "metadata"
        $declaredEncodedHash = [string](
            Get-ObjectPropertyValue `
                -InputObject $existingMetadata `
                -Name "encoded_sha256"
        )
        $actualEncodedHash = (
            Get-FileHash `
                -LiteralPath $sourceFile.DestinationPath `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $reusable = (
            [string](
                Get-ObjectPropertyValue -InputObject $existingResource -Name "path"
            ) -eq $sourceFile.RelativePath -and
            [string](
                Get-ObjectPropertyValue `
                    -InputObject $existingResource `
                    -Name "type_hint"
            ) -eq "AudioStreamOggVorbis" -and
            [string](
                Get-ObjectPropertyValue `
                    -InputObject $existingMetadata `
                    -Name "source_sha256"
            ) -eq $sourceFile.SourceSha256 -and
            [string](
                Get-ObjectPropertyValue `
                    -InputObject $existingMetadata `
                    -Name "encoding_profile"
            ) -eq $encodingProfile -and
            -not [string]::IsNullOrWhiteSpace($declaredEncodedHash) -and
            $declaredEncodedHash -eq $actualEncodedHash
        )
        if ($reusable) {
            $sourceFile.EncodedSha256 = $actualEncodedHash
            $sourceFile.EncodedByteCount = (
                Get-Item -LiteralPath $sourceFile.DestinationPath
            ).Length
            $sourceFile.ConversionRequired = $false
        }
    }

    if (-not $reusable -and -not $Force) {
        throw (
            "目标已有无法按当前源哈希和编码配置复用的内容：" +
            "$($sourceFile.DestinationPath)。确认重新编码覆盖时请追加 -Force。"
        )
    }
}

if ($PlanOnly) {
    Write-Host "Puzzle Music 2 OGG 安装计划（未写入任何文件）："
    Write-Host "FFmpeg: $ffmpegExecutable"
    foreach ($sourceFile in $sourceFiles) {
        if (-not $sourceFile.ConversionRequired) {
            Write-Host "复用：$($sourceFile.DestinationPath)"
            continue
        }
        $plannedTemporaryPath = Join-Path (
            Split-Path -Parent $sourceFile.DestinationPath
        ) ".$($sourceFile.Slug).install.tmp.ogg"
        $plannedArguments = New-OggEncodingArguments `
            -InputPath $sourceFile.SourcePath `
            -OutputPath $plannedTemporaryPath `
            -Quality $OggQuality
        Write-Host (
            Format-NativeCommand `
                -Executable $ffmpegExecutable `
                -Arguments $plannedArguments
        )
    }
    Write-Host "计划登记 $($sourceFiles.Count) 个 AudioStreamOggVorbis 稳定资源键。"
    return
}

[System.IO.Directory]::CreateDirectory($audioRoot) | Out-Null
$temporaryPaths = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($sourceFile in $sourceFiles) {
        if (-not $sourceFile.ConversionRequired) {
            continue
        }
        $temporaryPath = Join-Path $audioRoot (
            ".$($sourceFile.Slug).$([guid]::NewGuid().ToString('N')).tmp.ogg"
        )
        $sourceFile.TemporaryPath = $temporaryPath
        $temporaryPaths.Add($temporaryPath)
        $ffmpegArguments = New-OggEncodingArguments `
            -InputPath $sourceFile.SourcePath `
            -OutputPath $temporaryPath `
            -Quality $OggQuality
        & $ffmpegExecutable @ffmpegArguments
        $ffmpegExitCode = $LASTEXITCODE
        if ($ffmpegExitCode -ne 0) {
            throw (
                "FFmpeg 转码失败（退出码 $ffmpegExitCode）：" +
                "$($sourceFile.FileName)"
            )
        }
        if (
            -not (Test-Path -LiteralPath $temporaryPath -PathType Leaf) -or
            (Get-Item -LiteralPath $temporaryPath).Length -le 0
        ) {
            throw "FFmpeg 未生成有效 OGG：$($sourceFile.FileName)"
        }
        $sourceFile.EncodedSha256 = (
            Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $sourceFile.EncodedByteCount = (
            Get-Item -LiteralPath $temporaryPath
        ).Length
    }

    foreach ($sourceFile in $sourceFiles) {
        $currentSourceHash = (
            Get-FileHash -LiteralPath $sourceFile.SourcePath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($currentSourceHash -ne $sourceFile.SourceSha256) {
            throw "源 WAV 在安装期间发生变化，已停止提交：$($sourceFile.SourcePath)"
        }
    }

    foreach ($sourceFile in $sourceFiles) {
        if (-not $sourceFile.ConversionRequired) {
            continue
        }
        Move-Item `
            -LiteralPath $sourceFile.TemporaryPath `
            -Destination $sourceFile.DestinationPath `
            -Force
    }
}
finally {
    foreach ($temporaryPath in $temporaryPaths) {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

$resources = @()
foreach ($sourceFile in $sourceFiles) {
    $resources += [ordered]@{
        key = $sourceFile.ResourceKey
        path = $sourceFile.RelativePath
        type_hint = "AudioStreamOggVorbis"
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
            source_format = "wav"
            installed_format = "ogg"
            audio_codec = "vorbis"
            encoding_profile = $encodingProfile
            encoder_quality = $OggQuality
            source_byte_count = $sourceFile.SourceByteCount
            encoded_byte_count = $sourceFile.EncodedByteCount
            source_sha256 = $sourceFile.SourceSha256
            encoded_sha256 = $sourceFile.EncodedSha256
        }
    }
}

$manifest = [ordered]@{
    schema_version = 1
    package_id = "c76.local_audio.puzzle_music_2"
    display_name = "Puzzle Music 2 (Local Licensed Install)"
    version = "1.1.0-local"
    content_types = @("asset_library", "audio", "music")
    safety_kind = "data_only"
    resources = $resources
    metadata = [ordered]@{
        author = "GravitySound"
        source_url = "https://www.gamedevmarket.net/asset/puzzle-music-2"
        license = "GameDev Market Pro Licence"
        install_scope = "local_user_data_only"
        redistribution = "standalone_source_files_prohibited"
        source_format = "wav"
        installed_format = "ogg"
        audio_codec = "vorbis"
        encoding_profile = $encodingProfile
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

The purchased source WAV directory is read-only to this installer.
This package registers locally encoded OGG streams; it never copies source WAV files into a new install.
An upgraded package may still contain unreferenced legacy WAV files because this installer does not delete user files.
Do not commit, publish, sell, or redistribute the source WAV or encoded OGG files as standalone assets.
"@
[System.IO.File]::WriteAllText(
    $noticePath,
    $notice.Trim() + [Environment]::NewLine,
    $utf8NoBom
)

Write-Host "Puzzle Music 2 已安装到 Godot 本地内容包目录："
Write-Host $packageRoot
Write-Host (
    "已登记 $($resources.Count) 个 AudioStreamOggVorbis 稳定资源键；" +
    "源 WAV 保持只读，清单未保存源目录路径。"
)
