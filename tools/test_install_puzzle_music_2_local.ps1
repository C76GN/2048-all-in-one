[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "断言失败：$Message"
    }
}

$installerPath = Join-Path $PSScriptRoot "install_puzzle_music_2_local.ps1"
$parseTokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath,
    [ref]$parseTokens,
    [ref]$parseErrors
)
Assert-Condition ($parseErrors.Count -eq 0) "安装器必须通过 PowerShell 语法解析。"

$testRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) "puzzle-music-installer-$([guid]::NewGuid().ToString('N'))"
$sourceRoot = Join-Path $testRoot "source"
$userDataRoot = Join-Path $testRoot "user-data"
$fakeFfmpegPath = Join-Path $testRoot "fake-ffmpeg.cmd"
$trackNames = @(
    "Attempt.wav",
    "Blue.wav",
    "Fill.wav",
    "Known.wav",
    "Lesson.wav",
    "Onward.wav",
    "Overdone.wav",
    "Rotation.wav",
    "Slumber.wav",
    "Thorough.wav"
)

try {
    [System.IO.Directory]::CreateDirectory($sourceRoot) | Out-Null
    $sourceHashes = @{}
    for ($index = 0; $index -lt $trackNames.Count; $index++) {
        $sourcePath = Join-Path $sourceRoot $trackNames[$index]
        [System.IO.File]::WriteAllBytes(
            $sourcePath,
            [byte[]]@(82, 73, 70, 70, 1, 2, 3, 4, (10 + $index))
        )
        $sourceHashes[$trackNames[$index]] = (
            Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256
        ).Hash
    }

    $fakeFfmpeg = @"
@echo off
setlocal EnableExtensions
set "input="
set "output="
:next_argument
if "%~1"=="" goto convert
if /I "%~1"=="-i" goto capture_input
set "output=%~1"
shift
goto next_argument
:capture_input
shift
set "input=%~1"
shift
goto next_argument
:convert
if not defined input exit /b 91
if not defined output exit /b 92
copy /b /y "%input%" "%output%" >nul
exit /b %errorlevel%
"@
    [System.IO.File]::WriteAllText(
        $fakeFfmpegPath,
        $fakeFfmpeg,
        [System.Text.Encoding]::ASCII
    )

    & $installerPath `
        -SourceDirectory $sourceRoot `
        -UserDataRoot $userDataRoot `
        -FfmpegPath $fakeFfmpegPath `
        -OggQuality 5

    $packageRoot = Join-Path $userDataRoot "content_packages\puzzle_music_2"
    $manifestPath = Join-Path $packageRoot "gf_content_package.json"
    Assert-Condition (
        Test-Path -LiteralPath $manifestPath -PathType Leaf
    ) "安装器应生成内容包清单。"
    $manifest = Get-Content `
        -Raw `
        -Encoding UTF8 `
        -LiteralPath $manifestPath |
        ConvertFrom-Json
    Assert-Condition (
        @($manifest.resources).Count -eq $trackNames.Count
    ) "清单应登记全部十首曲目。"
    foreach ($resource in @($manifest.resources)) {
        Assert-Condition (
            $resource.type_hint -eq "AudioStreamOggVorbis"
        ) "新清单只能登记 AudioStreamOggVorbis。"
        Assert-Condition (
            ([string]$resource.path).EndsWith(
                ".ogg",
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) "新清单路径必须使用 .ogg。"
        $encodedPath = Join-Path $packageRoot (
            ([string]$resource.path).Replace("/", "\")
        )
        Assert-Condition (
            Test-Path -LiteralPath $encodedPath -PathType Leaf
        ) "清单中的 OGG 文件必须存在。"
        Assert-Condition (
            -not [string]::IsNullOrWhiteSpace(
                [string]$resource.metadata.encoded_sha256
            )
        ) "清单必须记录编码文件哈希。"
    }
    Assert-Condition (
        @(
            Get-ChildItem `
                -LiteralPath (Join-Path $packageRoot "audio") `
                -File `
                -Filter "*.wav"
        ).Count -eq 0
    ) "新安装不得复制源 WAV。"
    foreach ($trackName in $trackNames) {
        $sourcePath = Join-Path $sourceRoot $trackName
        Assert-Condition (
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq
            $sourceHashes[$trackName]
        ) "安装后源 WAV 必须保持不变：$trackName"
    }

    [System.IO.File]::WriteAllText(
        $fakeFfmpegPath,
        "@echo off`r`nexit /b 99`r`n",
        [System.Text.Encoding]::ASCII
    )
    & $installerPath `
        -SourceDirectory $sourceRoot `
        -UserDataRoot $userDataRoot `
        -FfmpegPath $fakeFfmpegPath `
        -OggQuality 5

    $firstOggPath = Join-Path $packageRoot "audio\Attempt.ogg"
    [System.IO.File]::AppendAllText(
        $firstOggPath,
        "tampered",
        [System.Text.Encoding]::ASCII
    )
    $conflictRejected = $false
    try {
        & $installerPath `
            -SourceDirectory $sourceRoot `
            -UserDataRoot $userDataRoot `
            -FfmpegPath $fakeFfmpegPath `
            -OggQuality 5
    }
    catch {
        $conflictRejected = $_.Exception.Message.Contains(
            "无法按当前源哈希和编码配置复用"
        )
    }
    Assert-Condition $conflictRejected "被篡改的编码文件必须在无 -Force 时拒绝覆盖。"

    Write-Host "Puzzle Music 2 本地安装器 PowerShell 验证通过。"
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    )
    if (
        $resolvedTestRoot.StartsWith(
            $resolvedTempRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $resolvedTestRoot)
    ) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
