param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$TemplateArchivePath = "",
	[string]$OutputPath = "",
	[string]$AppId = "",
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

$TemplateRelease = "4.7"
$TemplateAssetName = "minigame4.7.tpz"
$TemplateDownloadUrl = (
	"https://github.com/godothub/godot-minigame/releases/download/4.7/minigame4.7.tpz"
)
$TemplateExpectedBytes = 11763895
$TemplateExpectedSha256 = "AE5BDEB5BA1CE9712D4EFC35D337CB5ECBEF3AD5BFB0F7D06AE9CB662C1F2D71"
$ExportPreset = "Web Compatibility Smoke"
$PackFileName = "2048-all-in-one.bin"
$ChunkLoaderSourceRelativePath = "tools\wechat_minigame\chunked_file_loader.js"
$ChunkLoaderOutputRelativePath = "engine\wechat-chunked-file-loader.js"
$WxMemFsRenamePatchRelativePath = "tools\wechat_minigame\wxmemfs_rename_patch.ps1"
$TemplateGodotRuntimeSha256 = "CC396C67F410502C958185003EA72F5F67E5ACBCD040774D1AAF5B9622491B15"
$PatchedGodotRuntimeSha256 = "FD91EA35F0515360BE35AE6FD2425D102CBAF17F30F5B7CCB8688AF635CE3638"
$ChunkBytes = 4194304
$WeChatProjectName = "2048 Chunked Toolchain Smoke"
$MainPackageHardLimitBytes = 4000000
$TotalPackageHardLimitBytes = 30000000
$MainPackageSoftLimitBytes = 3600000
$TotalPackageSoftLimitBytes = 27000000
$DeviceOrientation = "landscape"
$ForbiddenSampleAppIds = @(
	"wxda5f10e2e9114855",
	"wxf40904ea6120ad08"
)

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectBuildRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "build"))
$outputRoot = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
	Join-Path $projectBuildRoot "wechat_minigame_smoke\wxgame"
}
elseif ([IO.Path]::IsPathRooted($OutputPath)) {
	$OutputPath
}
else {
	Join-Path $ProjectRoot $OutputPath
}
$outputRoot = [IO.Path]::GetFullPath($outputRoot)

function Assert-NoReparsePointPath {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	$fullPath = [IO.Path]::GetFullPath($Path)
	$projectRootPath = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd("\", "/")
	$projectPrefix = $projectRootPath + [IO.Path]::DirectorySeparatorChar
	if (
		-not $fullPath.Equals($projectRootPath, [StringComparison]::OrdinalIgnoreCase) -and
		-not $fullPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)
	) {
		throw "$Label escaped the project root while checking reparse points: $fullPath"
	}

	$currentPath = $projectRootPath
	if (Test-Path -LiteralPath $currentPath) {
		$currentItem = Get-Item -Force -LiteralPath $currentPath
		if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
			throw "$Label may not traverse a reparse point: $currentPath"
		}
	}
	$relativePath = $fullPath.Substring($projectRootPath.Length).TrimStart("\", "/")
	foreach ($segment in $relativePath.Split(@("\", "/"), [StringSplitOptions]::RemoveEmptyEntries)) {
		$currentPath = Join-Path $currentPath $segment
		if (-not (Test-Path -LiteralPath $currentPath)) {
			continue
		}
		$currentItem = Get-Item -Force -LiteralPath $currentPath
		if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
			throw "$Label may not traverse a reparse point: $currentPath"
		}
	}
}

function Assert-NoReparsePointTree {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	Assert-NoReparsePointPath -Path $Path -Label $Label
	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		return
	}
	$pendingDirectories = [System.Collections.Generic.Stack[IO.DirectoryInfo]]::new()
	$pendingDirectories.Push([IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path)))
	while ($pendingDirectories.Count -gt 0) {
		$currentDirectory = $pendingDirectories.Pop()
		foreach ($entry in $currentDirectory.EnumerateFileSystemInfos()) {
			if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
				throw "$Label may not contain a reparse point: $($entry.FullName)"
			}
			if ($entry -is [IO.DirectoryInfo]) {
				$pendingDirectories.Push($entry)
			}
		}
	}
}

function Assert-SafeBuildChildPath {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	$fullPath = [IO.Path]::GetFullPath($Path)
	$buildPrefix = $projectBuildRoot.TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
	if (-not $fullPath.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "$Label must stay under the project build directory: $fullPath"
	}
	if ($fullPath.Equals($projectBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
		throw "$Label may not be the project build root."
	}
	Assert-NoReparsePointPath -Path $fullPath -Label $Label
	return $fullPath
}

function Remove-SafeBuildTree {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	$fullPath = Assert-SafeBuildChildPath -Path $Path -Label $Label
	if (-not (Test-Path -LiteralPath $fullPath)) {
		return
	}
	$resolvedPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $fullPath).Path)
	$null = Assert-SafeBuildChildPath -Path $resolvedPath -Label $Label
	Assert-NoReparsePointTree -Path $resolvedPath -Label $Label
	Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Assert-WeChatAppId {
	param(
		[AllowEmptyString()]
		[string]$Value,
		[Parameter(Mandatory = $true)]
		[string]$Source
	)

	$normalizedValue = $Value.Trim()
	if ([string]::IsNullOrWhiteSpace($normalizedValue)) {
		return ""
	}
	if ($normalizedValue -notmatch '^wx[0-9A-Za-z]{16}$') {
		throw "$Source must be empty or a WeChat Mini Game AppID beginning with wx."
	}
	if ($ForbiddenSampleAppIds -contains $normalizedValue) {
		throw "$Source contains an upstream sample AppID and must be replaced with the project's own Mini Game AppID."
	}
	return $normalizedValue
}

function Read-JsonObject {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$Label
	)

	try {
		$value = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path |
			ConvertFrom-Json
	}
	catch {
		throw "$Label must contain a valid JSON object: $($_.Exception.Message)"
	}
	if ($null -eq $value -or $value -isnot [pscustomobject]) {
		throw "$Label must contain a JSON object."
	}
	return $value
}

function Write-SanitizedPrivateConfig {
	param(
		[Parameter(Mandatory = $true)]
		[string]$SourcePath,
		[Parameter(Mandatory = $true)]
		[string]$DestinationPath
	)

	$privateConfig = Read-JsonObject `
		-Path $SourcePath `
		-Label "existing project.private.config.json"
	# Private configuration is allowed to retain local IDE preferences, but it may
	# not override the canonical project identity or compile target we just verified.
	$privateConfig.PSObject.Properties.Remove("appid")
	$privateConfig.PSObject.Properties.Remove("compileType")
	Write-Utf8Text `
		-Path $DestinationPath `
		-Text (($privateConfig | ConvertTo-Json -Depth 16) + "`n")
}

function ConvertTo-NativeCommandLineArgument {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Argument
	)

	if ($Argument.Contains('"') -or $Argument.Contains([char]0)) {
		throw "Native command arguments may not contain quotes or NUL characters."
	}
	if ($Argument -notmatch '\s') {
		return $Argument
	}
	$trailingBackslashCount = [regex]::Match($Argument, '\\+$').Value.Length
	$quotedBody = $Argument
	if ($trailingBackslashCount -gt 0) {
		$argumentPrefix = $Argument.Substring(
			0,
			$Argument.Length - $trailingBackslashCount
		)
		$quotedBody = $argumentPrefix + ("\" * ($trailingBackslashCount * 2))
	}
	return '"' + $quotedBody + '"'
}

function Write-Utf8Text {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Text
	)

	$utf8NoBom = [Text.UTF8Encoding]::new($false)
	[IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-FileSha256 {
	param([Parameter(Mandatory = $true)][string]$Path)

	return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Assert-TemplateArchive {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "WeChat template archive was not found: $Path"
	}
	$archive = Get-Item -LiteralPath $Path
	if ($archive.Length -ne $TemplateExpectedBytes) {
		throw (
			"WeChat template size mismatch: expected {0}, got {1}." -f
			$TemplateExpectedBytes,
			$archive.Length
		)
	}
	$actualHash = Get-FileSha256 -Path $archive.FullName
	if ($actualHash -ne $TemplateExpectedSha256) {
		throw "WeChat template SHA-256 mismatch: $actualHash"
	}
	return $archive.FullName
}

function Resolve-TemplateArchive {
	if (-not [string]::IsNullOrWhiteSpace($TemplateArchivePath)) {
		$providedArchivePath = if ([IO.Path]::IsPathRooted($TemplateArchivePath)) {
			$TemplateArchivePath
		}
		else {
			Join-Path $ProjectRoot $TemplateArchivePath
		}
		return Assert-TemplateArchive -Path ([IO.Path]::GetFullPath($providedArchivePath))
	}

	$cacheRoot = Assert-SafeBuildChildPath `
		-Path (Join-Path $projectBuildRoot "wechat_toolchain\$TemplateRelease") `
		-Label "WeChat template cache"
	$null = New-Item -ItemType Directory -Force -Path $cacheRoot
	$cachedArchive = Join-Path $cacheRoot $TemplateAssetName
	if (Test-Path -LiteralPath $cachedArchive -PathType Leaf) {
		return Assert-TemplateArchive -Path $cachedArchive
	}

	$partialArchive = Assert-SafeBuildChildPath `
		-Path ($cachedArchive + ".partial") `
		-Label "WeChat template partial download"
	if (Test-Path -LiteralPath $partialArchive) {
		Remove-Item -LiteralPath $partialArchive -Force
	}
	Write-Host "Downloading pinned WeChat template $TemplateRelease..."
	try {
		Invoke-WebRequest `
			-Uri $TemplateDownloadUrl `
			-OutFile $partialArchive `
			-TimeoutSec 300 `
			-UseBasicParsing
		$null = Assert-TemplateArchive -Path $partialArchive
		Move-Item -LiteralPath $partialArchive -Destination $cachedArchive
	}
	catch {
		if (Test-Path -LiteralPath $partialArchive) {
			Remove-Item -LiteralPath $partialArchive -Force
		}
		throw (
			"Unable to download the pinned WeChat template. Pass -TemplateArchivePath " +
			"with a verified minigame4.7.tpz. $($_.Exception.Message)"
		)
	}
	return Assert-TemplateArchive -Path $cachedArchive
}

function Invoke-GodotPackExport {
	param(
		[Parameter(Mandatory = $true)]
		[string]$GodotPath,
		[Parameter(Mandatory = $true)]
		[string]$PackPath
	)

	$startInfo = [Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $GodotPath
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$arguments = @(
		"--headless",
		"--quiet",
		"--path",
		$ProjectRoot,
		"--export-pack",
		$ExportPreset,
		$PackPath
	)
	$quotedArguments = @()
	foreach ($argument in $arguments) {
		$quotedArguments += ConvertTo-NativeCommandLineArgument -Argument ([string]$argument)
	}
	$startInfo.Arguments = $quotedArguments -join " "

	$exportProcess = [Diagnostics.Process]::Start($startInfo)
	$stdoutTask = $exportProcess.StandardOutput.ReadToEndAsync()
	$stderrTask = $exportProcess.StandardError.ReadToEndAsync()
	$completedInTime = $exportProcess.WaitForExit($TimeoutSeconds * 1000)
	if (-not $completedInTime) {
		$exportProcess.Kill()
		$exportProcess.WaitForExit()
		throw "Godot WeChat smoke pack export timed out after $TimeoutSeconds seconds."
	}
	$exportProcess.WaitForExit()
	$stdoutText = $stdoutTask.GetAwaiter().GetResult().Trim()
	$stderrText = $stderrTask.GetAwaiter().GetResult().Trim()
	if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $PackPath -PathType Leaf)) {
		$diagnosticText = if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
			$stderrText
		}
		else {
			$stdoutText
		}
		if ($diagnosticText.Length -gt 2000) {
			$diagnosticText = $diagnosticText.Substring($diagnosticText.Length - 2000)
		}
		throw (
			"Godot pack export failed (exit {0}): {1}" -f
			$exportProcess.ExitCode,
			$diagnosticText
		).Trim()
	}
}

function Invoke-GodotArtifactVerification {
	param(
		[Parameter(Mandatory = $true)]
		[string]$GodotPath,
		[Parameter(Mandatory = $true)]
		[string]$ArtifactRoot,
		[Parameter(Mandatory = $true)]
		[string]$VerificationProjectRoot
	)

	$startInfo = [Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $GodotPath
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$arguments = @(
		"--headless",
		"--path",
		$VerificationProjectRoot,
		"--script",
		"res://tools/wechat_minigame_artifact_check.gd",
		"--",
		"--artifact-root",
		$ArtifactRoot,
		"--inspect-pack"
	)
	$quotedArguments = @()
	foreach ($argument in $arguments) {
		$quotedArguments += ConvertTo-NativeCommandLineArgument -Argument ([string]$argument)
	}
	$startInfo.Arguments = $quotedArguments -join " "

	$verificationProcess = [Diagnostics.Process]::Start($startInfo)
	$stdoutTask = $verificationProcess.StandardOutput.ReadToEndAsync()
	$stderrTask = $verificationProcess.StandardError.ReadToEndAsync()
	$completedInTime = $verificationProcess.WaitForExit($TimeoutSeconds * 1000)
	if (-not $completedInTime) {
		$verificationProcess.Kill()
		$verificationProcess.WaitForExit()
		throw "WeChat artifact verification timed out after $TimeoutSeconds seconds."
	}
	$verificationProcess.WaitForExit()
	$stdoutText = $stdoutTask.GetAwaiter().GetResult().Trim()
	$stderrText = $stderrTask.GetAwaiter().GetResult().Trim()
	if ($verificationProcess.ExitCode -ne 0) {
		$diagnosticText = if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
			$stderrText
		}
		else {
			$stdoutText
		}
		if ($diagnosticText.Length -gt 4000) {
			$diagnosticText = $diagnosticText.Substring($diagnosticText.Length - 4000)
		}
		throw (
			"WeChat artifact verification failed (exit {0}): {1}" -f
			$verificationProcess.ExitCode,
			$diagnosticText
		).Trim()
	}
}

function Initialize-GodotArtifactVerificationProject {
	param([Parameter(Mandatory = $true)][string]$VerificationProjectRoot)

	$verificationToolsRoot = Join-Path $VerificationProjectRoot "tools"
	$null = New-Item -ItemType Directory -Path $verificationToolsRoot
	Write-Utf8Text `
		-Path (Join-Path $VerificationProjectRoot "project.godot") `
		-Text @"
config_version=5

[application]

config/name="2048 WeChat Artifact Verification Host"

[rendering]

renderer/rendering_method="gl_compatibility"
"@
	foreach ($scriptName in @(
		"wechat_minigame_artifact_check.gd",
		"wechat_minigame_artifact_verifier.gd"
	)) {
		Copy-Item `
			-LiteralPath (Join-Path $ProjectRoot "tools\$scriptName") `
			-Destination (Join-Path $verificationToolsRoot $scriptName)
	}
}

function Get-PreservedAppId {
	if (-not [string]::IsNullOrWhiteSpace($AppId)) {
		return $AppId.Trim()
	}
	$existingConfigPath = Join-Path $outputRoot "project.config.json"
	$existingPrivateConfigPath = Join-Path $outputRoot "project.private.config.json"
	$publicAppId = ""
	if (Test-Path -LiteralPath $existingConfigPath -PathType Leaf) {
		Assert-NoReparsePointPath -Path $existingConfigPath -Label "existing WeChat project config"
		$existingConfig = Read-JsonObject `
			-Path $existingConfigPath `
			-Label "existing project.config.json"
		$publicAppId = [string]$existingConfig.appid
	}
	if (Test-Path -LiteralPath $existingPrivateConfigPath -PathType Leaf) {
		Assert-NoReparsePointPath `
			-Path $existingPrivateConfigPath `
			-Label "existing WeChat private config"
		$existingPrivateConfig = Read-JsonObject `
			-Path $existingPrivateConfigPath `
			-Label "existing project.private.config.json"
		$privateAppId = [string]$existingPrivateConfig.appid
		if (-not [string]::IsNullOrWhiteSpace($privateAppId)) {
			return $privateAppId
		}
	}
	return $publicAppId
}

function Get-RelativeOutputPath {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Root,
		[Parameter(Mandatory = $true)]
		[string]$FullName
	)

	$rootPrefix = $Root.TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
	if (-not $FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "Output file escaped the staging root: $FullName"
	}
	return $FullName.Substring($rootPrefix.Length).Replace("\", "/")
}

function Get-PackageEvidence {
	param([Parameter(Mandatory = $true)][string]$StageRoot)

	$allowedPaths = @(
		"engine/$PackFileName",
		"engine/game.js",
		"engine/wechat-chunked-file-loader.js",
		"engine/godot-sdk.js",
		"engine/godot.js",
		"engine/godot.wasm.br",
		"game.js",
		"game.json",
		"glx-config.js",
		"godot-loader.js",
		"images/background.png",
		"images/logo.png",
		"project.config.json",
		"project.private.config.json",
		"weapp-adapter.js"
	)
	$files = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -File)
	$relativePaths = @()
	$unexpectedPaths = @()
	$mainPackageBytes = [int64]0
	$enginePackageBytes = [int64]0
	foreach ($file in $files) {
		$relativePath = Get-RelativeOutputPath -Root $StageRoot -FullName $file.FullName
		$relativePaths += $relativePath
		if ($allowedPaths -notcontains $relativePath) {
			$unexpectedPaths += $relativePath
		}
		if ($relativePath.StartsWith("engine/", [StringComparison]::OrdinalIgnoreCase)) {
			$enginePackageBytes += $file.Length
		}
		else {
			$mainPackageBytes += $file.Length
		}
	}
	$requiredPaths = $allowedPaths | Where-Object { $_ -ne "project.private.config.json" }
	$missingPaths = @($requiredPaths | Where-Object { $relativePaths -notcontains $_ })
	$forbiddenPaths = @(
		$relativePaths | Where-Object {
			$_ -match '(?i)\.(?:pck|html|wasm)$'
		}
	)
	$totalPackageBytes = $mainPackageBytes + $enginePackageBytes
	return [ordered]@{
		main_package_bytes = $mainPackageBytes
		engine_package_bytes = $enginePackageBytes
		total_package_bytes = $totalPackageBytes
		main_hard_limit_bytes = $MainPackageHardLimitBytes
		total_hard_limit_bytes = $TotalPackageHardLimitBytes
		main_soft_limit_bytes = $MainPackageSoftLimitBytes
		total_soft_limit_bytes = $TotalPackageSoftLimitBytes
		main_hard_limit_ok = ($mainPackageBytes -le $MainPackageHardLimitBytes)
		total_hard_limit_ok = ($totalPackageBytes -le $TotalPackageHardLimitBytes)
		main_soft_budget_ok = ($mainPackageBytes -le $MainPackageSoftLimitBytes)
		total_soft_budget_ok = ($totalPackageBytes -le $TotalPackageSoftLimitBytes)
		file_count = $files.Count
		files = @($relativePaths | Sort-Object)
		missing_paths = $missingPaths
		unexpected_paths = $unexpectedPaths
		forbidden_paths = $forbiddenPaths
	}
}

$AppId = Assert-WeChatAppId -Value $AppId -Source "-AppId"
$outputRoot = Assert-SafeBuildChildPath -Path $outputRoot -Label "WeChat smoke output"
$outputParent = Assert-SafeBuildChildPath `
	-Path (Split-Path -Parent $outputRoot) `
	-Label "WeChat smoke output parent"
$null = New-Item -ItemType Directory -Force -Path $outputParent
$preservedAppId = Assert-WeChatAppId `
	-Value (Get-PreservedAppId) `
	-Source "preserved project.config.json AppID"
$stageRoot = Assert-SafeBuildChildPath `
	-Path (Join-Path $outputParent (".stage-" + [Guid]::NewGuid().ToString("N"))) `
	-Label "WeChat smoke staging directory"
$null = New-Item -ItemType Directory -Path $stageRoot
$existingPrivateConfigPath = Join-Path $outputRoot "project.private.config.json"
$preservedPrivateConfigPath = ""
if (Test-Path -LiteralPath $existingPrivateConfigPath -PathType Leaf) {
	Assert-NoReparsePointPath `
		-Path $existingPrivateConfigPath `
		-Label "existing WeChat private config"
	$preservedPrivateConfigPath = $existingPrivateConfigPath
}
$backupRoot = Assert-SafeBuildChildPath `
	-Path (Join-Path $outputParent (".backup-" + [Guid]::NewGuid().ToString("N"))) `
	-Label "WeChat smoke output backup"
$previousOutputBackedUp = $false
$newOutputPublished = $false
$publishCommitted = $false
$verificationProjectRoot = Assert-SafeBuildChildPath `
	-Path (Join-Path $outputParent (".verify-" + [Guid]::NewGuid().ToString("N"))) `
	-Label "isolated WeChat artifact verification project"

try {
	$templateArchive = Resolve-TemplateArchive
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	[IO.Compression.ZipFile]::ExtractToDirectory($templateArchive, $stageRoot)
	$godotRuntimePath = Join-Path $stageRoot "engine\godot.js"
	$godotRuntimeInputHash = Get-FileSha256 -Path $godotRuntimePath
	if ($godotRuntimeInputHash -ne $TemplateGodotRuntimeSha256) {
		throw (
			"Pinned WeChat godot.js SHA-256 mismatch: expected {0}, got {1}." -f
			$TemplateGodotRuntimeSha256,
			$godotRuntimeInputHash
		)
	}
	$wxMemFsRenamePatchPath = Join-Path $ProjectRoot $WxMemFsRenamePatchRelativePath
	if (-not (Test-Path -LiteralPath $wxMemFsRenamePatchPath -PathType Leaf)) {
		throw "WXMEMFS rename patch was not found: $wxMemFsRenamePatchPath"
	}
	. $wxMemFsRenamePatchPath
	$godotRuntimeSource = [IO.File]::ReadAllText(
		$godotRuntimePath,
		[Text.UTF8Encoding]::new($false)
	)
	$patchedGodotRuntimeSource = ConvertTo-WeChatWxMemFsRenamePatchedSource `
		-Source $godotRuntimeSource
	Write-Utf8Text -Path $godotRuntimePath -Text $patchedGodotRuntimeSource
	$godotRuntimeOutputHash = Get-FileSha256 -Path $godotRuntimePath
	if ($godotRuntimeOutputHash -ne $PatchedGodotRuntimeSha256) {
		throw (
			"Patched WeChat godot.js SHA-256 mismatch: expected {0}, got {1}." -f
			$PatchedGodotRuntimeSha256,
			$godotRuntimeOutputHash
		)
	}
	$wxMemFsRenameEvidence = [ordered]@{
		strategy = "physical_rename_before_memfs_mutation"
		patch = "2048-wechat-wxmemfs-rename-v1"
		template_runtime_sha256 = $godotRuntimeInputHash
		patched_runtime_sha256 = $godotRuntimeOutputHash
	}

	foreach ($sampleTree in @("subpackages", "subpacks")) {
		$sampleTreePath = Join-Path $stageRoot $sampleTree
		if (Test-Path -LiteralPath $sampleTreePath) {
			Remove-SafeBuildTree -Path $sampleTreePath -Label "template sample tree"
		}
	}
	foreach ($sampleFile in @(
		".eslintrc.js",
		".godot-subpack-managed.json",
		"engine\empty-tips.bin",
		"images\background.jpg",
		"images\background.jpg.import",
		"images\logo.png.import",
		"project.private.config.json"
	)) {
		$sampleFilePath = Join-Path $stageRoot $sampleFile
		if (Test-Path -LiteralPath $sampleFilePath) {
			Remove-Item -LiteralPath $sampleFilePath -Force
		}
	}
	foreach ($templateMarkdown in @(Get-ChildItem -LiteralPath $stageRoot -File -Filter "*.md")) {
		Remove-Item -LiteralPath $templateMarkdown.FullName -Force
	}

	Copy-Item `
		-LiteralPath (Join-Path $ProjectRoot "features\asset_library\resources\textures\branding\printworks_boot_splash.png") `
		-Destination (Join-Path $stageRoot "images\background.png") `
		-Force
	Copy-Item `
		-LiteralPath (Join-Path $ProjectRoot "features\asset_library\resources\textures\branding\printworks_boot_mark.png") `
		-Destination (Join-Path $stageRoot "images\logo.png") `
		-Force

	$gameEntryPath = Join-Path $stageRoot "game.js"
	$gameEntryText = Get-Content -Raw -Encoding UTF8 -LiteralPath $gameEntryPath
	$gameEntryText = $gameEntryText.Replace("images/background.jpg", "images/background.png")
	Write-Utf8Text -Path $gameEntryPath -Text $gameEntryText

	$gameConfig = [ordered]@{
		deviceOrientation = $DeviceOrientation
		iOSHighPerformance = $true
		"iOSHighPerformance+" = $true
		plugins = [ordered]@{}
		subpackages = @(
			[ordered]@{
				name = "engine"
				root = "engine/"
			}
		)
	}
	Write-Utf8Text `
		-Path (Join-Path $stageRoot "game.json") `
		-Text (($gameConfig | ConvertTo-Json -Depth 8) + "`n")

	$projectConfigPath = Join-Path $stageRoot "project.config.json"
	$projectConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $projectConfigPath |
		ConvertFrom-Json
	$projectConfig.description = "2048-all-in-one - Godot 4.7 WeChat Mini Game smoke"
	$projectConfig | Add-Member `
		-NotePropertyName "projectname" `
		-NotePropertyValue $WeChatProjectName `
		-Force
	$projectConfig.compileType = "minigame"
	$projectConfig.appid = $preservedAppId
	$projectConfig.isGameTourist = $false
	Write-Utf8Text `
		-Path $projectConfigPath `
		-Text (($projectConfig | ConvertTo-Json -Depth 16) + "`n")
	if (-not [string]::IsNullOrWhiteSpace($preservedPrivateConfigPath)) {
		Write-SanitizedPrivateConfig `
			-SourcePath $preservedPrivateConfigPath `
			-DestinationPath (Join-Path $stageRoot "project.private.config.json")
	}

	$godotCommand = Get-Command $GodotExecutable -ErrorAction Stop
	$godotPath = $godotCommand.Source
	$temporaryPackPath = Join-Path $stageRoot "engine\2048-all-in-one.pck"
	Invoke-GodotPackExport -GodotPath $godotPath -PackPath $temporaryPackPath
	$finalPackPath = Join-Path $stageRoot "engine\$PackFileName"
	Move-Item -LiteralPath $temporaryPackPath -Destination $finalPackPath

	$chunkLoaderSourcePath = Join-Path $ProjectRoot $ChunkLoaderSourceRelativePath
	if (-not (Test-Path -LiteralPath $chunkLoaderSourcePath -PathType Leaf)) {
		throw "Canonical WeChat chunk loader was not found: $chunkLoaderSourcePath"
	}
	$chunkLoaderOutputPath = Join-Path $stageRoot $ChunkLoaderOutputRelativePath
	Copy-Item `
		-LiteralPath $chunkLoaderSourcePath `
		-Destination $chunkLoaderOutputPath `
		-Force

	$largeResourceFiles = @(
		[ordered]@{
			path = "/engine/godot.wasm.br"
			file = (Join-Path $stageRoot "engine\godot.wasm.br")
		},
		[ordered]@{
			path = "/engine/$PackFileName"
			file = $finalPackPath
		}
	)
	$chunkedResourceBytes = [ordered]@{}
	$largeFileReaderResources = @()
	foreach ($resource in $largeResourceFiles) {
		$resourceItem = Get-Item -LiteralPath $resource.file
		if ($resourceItem.Length -le 0) {
			throw "Chunked WeChat resource must not be empty: $($resource.path)"
		}
		$chunkedResourceBytes[$resource.path] = [int64]$resourceItem.Length
		$largeFileReaderResources += [ordered]@{
			path = $resource.path
			bytes = [int64]$resourceItem.Length
			sha256 = Get-FileSha256 -Path $resource.file
		}
	}
	$chunkedResourceBytesJson = $chunkedResourceBytes | ConvertTo-Json -Compress
	$engineGamePath = Join-Path $stageRoot "engine\game.js"
	Write-Utf8Text -Path $engineGamePath -Text @"
import './godot-sdk'
import './godot'
import './wechat-chunked-file-loader'
const exe = '/engine/godot';
const pack = '/engine/$PackFileName';
const chunkedResourceBytes = Object.freeze($chunkedResourceBytesJson);
GameGlobal.WeChatChunkedFileLoader.installChunkedLocalFetch(
  GameGlobal.fsUtils,
  wx.getFileSystemManager(),
  chunkedResourceBytes,
  {chunkBytes: $ChunkBytes}
);
console.log('[wechat-loader] start_game');
GODOTSDK.startGame(exe, pack)
  .then(() => console.log('[wechat-loader] start_game_resolved'))
  .catch((error) => {
    const detail = error && error.message ? error.message : String(error);
    console.error('[wechat-loader] start_game_failed', detail);
    throw error;
  });
"@
	$largeFileReaderEvidence = [ordered]@{
		strategy = "async_position_length_chunked"
		chunk_bytes = $ChunkBytes
		helper_path = "engine/wechat-chunked-file-loader.js"
		helper_sha256 = Get-FileSha256 -Path $chunkLoaderOutputPath
		resources = $largeFileReaderResources
	}

	$packageEvidence = Get-PackageEvidence -StageRoot $stageRoot
	$engineGameText = Get-Content -Raw -Encoding UTF8 -LiteralPath $engineGamePath
	if (-not $engineGameText.Contains("/engine/$PackFileName")) {
		throw "Generated engine loader does not reference the exported .bin pack."
	}
	if (
		$packageEvidence.missing_paths.Count -gt 0 -or
		$packageEvidence.unexpected_paths.Count -gt 0 -or
		$packageEvidence.forbidden_paths.Count -gt 0
	) {
		throw (
			"Generated WeChat output failed the exact file whitelist. " +
			"missing=[{0}] unexpected=[{1}] forbidden=[{2}]" -f
			([string]::Join(", ", $packageEvidence.missing_paths)),
			([string]::Join(", ", $packageEvidence.unexpected_paths)),
			([string]::Join(", ", $packageEvidence.forbidden_paths))
		)
	}
	if (-not $packageEvidence.main_hard_limit_ok) {
		throw "Generated WeChat main package exceeds $MainPackageHardLimitBytes bytes."
	}
	if (-not $packageEvidence.total_hard_limit_ok) {
		throw "Generated WeChat package exceeds $TotalPackageHardLimitBytes bytes."
	}
	Initialize-GodotArtifactVerificationProject `
		-VerificationProjectRoot $verificationProjectRoot
	try {
		Invoke-GodotArtifactVerification `
			-GodotPath $godotPath `
			-ArtifactRoot $stageRoot `
			-VerificationProjectRoot $verificationProjectRoot
	}
	finally {
		if (Test-Path -LiteralPath $verificationProjectRoot) {
			Remove-SafeBuildTree `
				-Path $verificationProjectRoot `
				-Label "isolated WeChat artifact verification project"
		}
	}

	if (Test-Path -LiteralPath $outputRoot) {
		Assert-NoReparsePointTree -Path $outputRoot -Label "previous WeChat smoke output"
		Move-Item -LiteralPath $outputRoot -Destination $backupRoot
		$previousOutputBackedUp = $true
	}
	Move-Item -LiteralPath $stageRoot -Destination $outputRoot
	$newOutputPublished = $true

	$godotVersionOutput = (& $godotPath --version | Select-Object -First 1).Trim()
	$report = [ordered]@{
		ok = $true
		scope = "toolchain_smoke"
		generated_at = [DateTimeOffset]::Now.ToString("o")
		output_path = $outputRoot
		export_preset = $ExportPreset
		godot = [ordered]@{
			executable = $godotPath
			version = $godotVersionOutput
		}
		template = [ordered]@{
			repository = "https://github.com/godothub/godot-minigame"
			release = $TemplateRelease
			asset = $TemplateAssetName
			download_url = $TemplateDownloadUrl
			expected_bytes = $TemplateExpectedBytes
			sha256 = $TemplateExpectedSha256
			archive_path = $templateArchive
		}
		app_id_configured = -not [string]::IsNullOrWhiteSpace($preservedAppId)
		project_name = $WeChatProjectName
		device_orientation = $DeviceOrientation
		user_file_system = $wxMemFsRenameEvidence
		large_file_reader = $largeFileReaderEvidence
		package = $packageEvidence
		limitations = @(
			"This is a platform/toolchain smoke build, not a production release.",
			"WeChat login, share, payment, cloud save and open-data capabilities are not enabled.",
			"Preview, upload and device validation require the project's own Mini Game AppID."
		)
	}
	$reportPath = Join-Path $outputParent "export-report.json"
	Write-Utf8Text -Path $reportPath -Text (($report | ConvertTo-Json -Depth 12) + "`n")
	$publishCommitted = $true
	if ($previousOutputBackedUp -and (Test-Path -LiteralPath $backupRoot)) {
		$previousOutputBackedUp = $false
		try {
			Remove-SafeBuildTree -Path $backupRoot -Label "retired WeChat smoke output backup"
		}
		catch {
			Write-Warning (
				"The new WeChat output is committed, but its retired backup could not be fully removed: " +
				$_.Exception.Message
			)
		}
	}

	Write-Host "WeChat Mini Game smoke export: PASS"
	Write-Host "Output: $outputRoot"
	Write-Host (
		"Package bytes: main={0}, engine={1}, total={2}" -f
		$packageEvidence.main_package_bytes,
		$packageEvidence.engine_package_bytes,
		$packageEvidence.total_package_bytes
	)
	Write-Host "Report: $reportPath"
}
catch {
	$originalError = $_
	if (-not $publishCommitted) {
		if ($newOutputPublished -and (Test-Path -LiteralPath $outputRoot)) {
			Remove-SafeBuildTree -Path $outputRoot -Label "failed published WeChat smoke output"
			$newOutputPublished = $false
		}
		if ($previousOutputBackedUp -and (Test-Path -LiteralPath $backupRoot)) {
			Move-Item -LiteralPath $backupRoot -Destination $outputRoot
			$previousOutputBackedUp = $false
		}
	}
	if (Test-Path -LiteralPath $stageRoot) {
		Remove-SafeBuildTree -Path $stageRoot -Label "failed WeChat smoke staging directory"
	}
	if (Test-Path -LiteralPath $verificationProjectRoot) {
		Remove-SafeBuildTree `
			-Path $verificationProjectRoot `
			-Label "failed isolated WeChat artifact verification project"
	}
	throw $originalError
}
