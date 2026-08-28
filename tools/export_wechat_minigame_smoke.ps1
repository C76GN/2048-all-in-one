param(
	[string]$GodotExecutable = "godot",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
	[string]$TemplateArchivePath = "",
	[string]$OutputPath = "",
	[string]$AppId = "",
	[ValidateSet("Smoke", "Release")]
	[string]$Profile = "Smoke",
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 600,
	[switch]$FunctionsOnly,
	[ValidateSet(
		"",
		"after_candidate_stage",
		"after_candidate_backup",
		"after_candidate_publish"
	)]
	[string]$TestFailureInjection = ""
)

$ErrorActionPreference = "Stop"

$TemplateRelease = "4.7"
$TemplateAssetName = "minigame4.7.tpz"
$TemplateDownloadUrl = (
	"https://github.com/godothub/godot-minigame/releases/download/4.7/minigame4.7.tpz"
)
$TemplateExpectedBytes = 11763895
$TemplateExpectedSha256 = "AE5BDEB5BA1CE9712D4EFC35D337CB5ECBEF3AD5BFB0F7D06AE9CB662C1F2D71"
$RequiredGodotVersionPrefix = "4.7.2.stable"
$ExportReportSchemaVersion = 3
$ArtifactManifestSchemaVersion = 1
$InputSnapshotSchemaVersion = 1
$BuildIdentitySchemaVersion = 2
$IsReleaseProfile = $Profile -eq "Release"
$ExportPreset = if ($IsReleaseProfile) {
	"Web Compatibility WeChat Release"
}
else {
	"Web Compatibility Smoke"
}
$ReportScope = if ($IsReleaseProfile) {
	"full_game_release_candidate"
}
else {
	"toolchain_smoke"
}
$PackFileName = "2048-all-in-one.bin"
$ChunkLoaderSourceRelativePath = "tools\wechat_minigame\chunked_file_loader.js"
$ChunkLoaderOutputRelativePath = "engine\wechat-chunked-file-loader.js"
$WxMemFsRenamePatchRelativePath = "tools\wechat_minigame\wxmemfs_rename_patch.ps1"
$TemplateGodotRuntimeSha256 = "CC396C67F410502C958185003EA72F5F67E5ACBCD040774D1AAF5B9622491B15"
$PatchedGodotRuntimeSha256 = "FD91EA35F0515360BE35AE6FD2425D102CBAF17F30F5B7CCB8688AF635CE3638"
$TemplateGodotLoaderSha256 = "181E61961CF6527F718E93E132D86DAF4310E091E3B004909076BDCE4D56C99C"
$ChunkBytes = 4194304
$WeChatProjectName = if ($IsReleaseProfile) {
	"2048 Full Game Release Candidate"
}
else {
	"2048 Chunked Toolchain Smoke"
}
$ProjectDescription = if ($IsReleaseProfile) {
	"2048-all-in-one - Godot 4.7 WeChat Mini Game full-game release candidate"
}
else {
	"2048-all-in-one - Godot 4.7 WeChat Mini Game smoke"
}
$MainPackageHardLimitBytes = 4000000
$TotalPackageHardLimitBytes = 20000000
$MainPackageSoftLimitBytes = 3600000
$SubpackageHardLimitBytes = 20000000
$SubpackageSoftLimitBytes = 18000000
$TotalPackageSoftLimitBytes = 18000000
$DeviceOrientation = "landscape"
$VolatileLocalSidecarRelativePath = "project.private.config.json"
$ForbiddenSampleAppIds = @(
	"wxda5f10e2e9114855",
	"wxf40904ea6120ad08"
)
$ExportInputExactPaths = @(
	"default_bus_layout.tres",
	"export_presets.cfg",
	"icon.svg",
	"icon.svg.import",
	"project.godot"
)
$ExportInputRoots = @(
	"addons",
	"app",
	"features",
	"shared"
)
$ExportInputExcludedPrefixes = @(
	"addons/gf/tools/",
	"addons/gut/",
	"features/asset_library/resources/review/",
	"features/asset_library/resources/source_packs/",
	"features/asset_library/tools/",
	"features/platform_runtime/tools/",
	"features/themes/tools/"
)
$ExportInputExcludedExactPaths = @(
	"features/asset_library/resources/import_sources.json",
	"features/asset_library/resources/import_sources.local.json",
	"shared/assets/fonts/noto_sans_sc_variable.ttf"
)
$ReleaseFontCoverageManifestRelativePath = (
	"shared\assets\fonts\wechat_release_font_coverage.json"
)
$ReleaseFontCoverageRelativePath = (
	"shared\assets\fonts\wechat_release_font_coverage.txt"
)
$ReleaseFontSubsetRelativePath = (
	"shared\assets\fonts\wechat_release_sans_subset.ttf"
)
$ReleaseFontSourceRelativePath = (
	"shared\assets\fonts\noto_sans_sc_variable.ttf"
)
$ReleaseFontLicenseRelativePath = "shared\assets\fonts\noto_sans_sc_ofl.txt"
$ToolIdentityRelativePaths = [ordered]@{
	export_tool = "tools/export_wechat_minigame_smoke.ps1"
	artifact_verifier = "tools/wechat_minigame_artifact_verifier.gd"
	artifact_check = "tools/wechat_minigame_artifact_check.gd"
	bounded_json_reader = "addons/gf/kernel/core/gf_bounded_json_object_reader.gd"
	path_tools = "addons/gf/kernel/core/gf_path_tools.gd"
	chunk_loader = "tools/wechat_minigame/chunked_file_loader.js"
	wxmemfs_patch = "tools/wechat_minigame/wxmemfs_rename_patch.ps1"
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectBuildRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "build"))
$outputRoot = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
	$defaultCandidate = if ($IsReleaseProfile) {
		"wechat_minigame_release_candidate\wxgame"
	}
	else {
		"wechat_minigame_smoke\wxgame"
	}
	Join-Path $projectBuildRoot $defaultCandidate
}
elseif ([IO.Path]::IsPathRooted($OutputPath)) {
	$OutputPath
}
else {
	Join-Path $ProjectRoot $OutputPath
}
$outputRoot = [IO.Path]::GetFullPath($outputRoot)
$outputCandidateRoot = [IO.Path]::GetFullPath((Split-Path -Parent $outputRoot))
$outputCandidateParent = [IO.Path]::GetFullPath((Split-Path -Parent $outputCandidateRoot))

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

function ConvertTo-WeChatSubpackageLifecyclePatchedSource {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Source
	)

	$original = (
		'loadGameEngine(){wx.loadSubpackage({complete:t=>{},name:"engine",' +
		'success:()=>{this.progress=1,this.updateProgress(this.progress,' +
		'this.config.textConfig.initText)}}).onProgressUpdate(({progress:t})=>{' +
		'this.progress=t/100,this.updateProgress(this.progress,' +
		'this.config.textConfig.downloadingText[0])})}'
	)
	$patched = @'
loadGameEngine(){
  const SUBPACKAGE_TIMEOUT_MS=300000;
  const DATA_PROBE_TIMEOUT_MS=10000;
  let fatal=false;
  const asError=(reason,fallback)=>reason instanceof Error
    ?reason
    :new Error(reason&&reason.errMsg?reason.errMsg:(reason==null?fallback:String(reason)));
  const failVisible=error=>{
    if(fatal){return;}
    fatal=true;
    this.progress=0;
    this.updateProgress(this.progress,this.config.textConfig.loadFailedText||"引擎分包加载失败");
    setTimeout(()=>{throw error;},0);
  };
  const probeGameData=onSuccess=>{
    const path="/game_data/2048-all-in-one.bin";
    let settled=false;
    let timeoutId=0;
    const finish=(error,result)=>{
      if(settled){return;}
      settled=true;
      clearTimeout(timeoutId);
      if(fatal){return;}
      if(error){
        console.error("[wechat-subpackage] data_probe_fail",error.message);
        failVisible(error);
        return;
      }
      const bytes=result&&result.data&&result.data.byteLength;
      if(bytes!==1){
        const probeError=new Error("game_data PCK probe returned no byte");
        console.error("[wechat-subpackage] data_probe_fail",probeError.message);
        failVisible(probeError);
        return;
      }
      console.log("[wechat-subpackage] data_probe_success",path,bytes);
      onSuccess();
    };
    console.log("[wechat-subpackage] data_probe_start",path);
    timeoutId=setTimeout(()=>finish(new Error("game_data PCK probe timed out")),DATA_PROBE_TIMEOUT_MS);
    try{
      const fileSystem=wx.getFileSystemManager();
      if(!fileSystem||typeof fileSystem.readFile!=="function"){
        throw new Error("wx file system readFile is unavailable");
      }
      fileSystem.readFile({
        filePath:path,
        position:0,
        length:1,
        success:result=>finish(null,result),
        fail:result=>{
          const detail=result&&result.errMsg?result.errMsg:String(result);
          finish(new Error("game_data PCK probe failed: "+detail));
        }
      });
    }catch(reason){
      finish(asError(reason,"game_data PCK probe failed"));
    }
  };
  const loadPackage=(name,marker,entryPath,progressBase,onSuccess)=>{
    let settled=false;
    let timeoutId=0;
    const clearDeadline=()=>clearTimeout(timeoutId);
    const fail=(event,error)=>{
      if(settled){return;}
      settled=true;
      clearDeadline();
      if(fatal){return;}
      console.error(event,name,error.message);
      failVisible(error);
    };
    const succeed=result=>{
      if(settled||fatal){return;}
      const detail=result&&result.errMsg?result.errMsg:"loadSubpackage:ok";
      console.log("[wechat-subpackage] success",name,detail);
      if(GameGlobal[marker]!==true){
        fail(
          "[wechat-subpackage] entry_missing",
          new Error(entryPath+" did not execute after the "+name+" subpackage loaded")
        );
        return;
      }
      settled=true;
      clearDeadline();
      console.log("[wechat-subpackage] entry_confirmed",name,entryPath);
      try{onSuccess();}catch(reason){failVisible(asError(reason,name+" continuation failed"));}
    };
    GameGlobal[marker]=false;
    console.log("[wechat-subpackage] start",name);
    timeoutId=setTimeout(()=>fail(
      "[wechat-subpackage] timeout",
      new Error(name+" subpackage load timed out")
    ),SUBPACKAGE_TIMEOUT_MS);
    try{
      const task=wx.loadSubpackage({
        name:name,
        success:result=>succeed(result),
        fail:result=>fail(
          "[wechat-subpackage] fail",
          asError(result,name+" subpackage load failed")
        ),
        complete:result=>{
          const detail=result&&result.errMsg?result.errMsg:String(result);
          console.log("[wechat-subpackage] complete",name,detail);
        }
      });
      if(!task||typeof task.onProgressUpdate!=="function"){
        throw new Error(name+" subpackage progress task is unavailable");
      }
      task.onProgressUpdate(({progress})=>{
        if(settled||fatal){return;}
        console.log("[wechat-subpackage] progress",name,progress);
        this.progress=progressBase+progress/200;
        this.updateProgress(this.progress,this.config.textConfig.downloadingText[0]);
      });
    }catch(reason){
      fail("[wechat-subpackage] fail",asError(reason,name+" subpackage load failed"));
    }
  };
  loadPackage("game_data","__godotGameDataSubpackageEntryStarted","game_data/game.js",0,()=>{
    probeGameData(()=>{
      loadPackage("engine","__godotEngineSubpackageEntryStarted","engine/game.js",0.5,()=>{
        this.progress=1;
        this.updateProgress(this.progress,this.config.textConfig.initText);
      });
    });
  });
}
'@
	$firstIndex = $Source.IndexOf($original, [StringComparison]::Ordinal)
	if ($firstIndex -lt 0) {
		throw "Pinned godot-loader.js no longer contains the expected loadGameEngine implementation."
	}
	if ($Source.IndexOf($original, $firstIndex + $original.Length, [StringComparison]::Ordinal) -ge 0) {
		throw "Pinned godot-loader.js contains multiple loadGameEngine patch targets."
	}
	return $Source.Replace($original, $patched)
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

function Get-SanitizedPrivateConfigSnapshot {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		return [pscustomobject][ordered]@{
			exists = $false
			app_id = ""
			sanitized_json = ""
		}
	}
	Assert-NoReparsePointPath -Path $Path -Label "existing WeChat private config"
	$privateConfig = Read-JsonObject `
		-Path $Path `
		-Label "existing project.private.config.json"
	$privateAppId = [string]$privateConfig.appid
	# Private configuration is allowed to retain local IDE preferences, but it may
	# not override the canonical project identity or compile target we just verified.
	$privateConfig.PSObject.Properties.Remove("appid")
	$privateConfig.PSObject.Properties.Remove("compileType")
	# Keep serialized bytes in memory so staging never re-reads a DevTools-owned live file.
	return [pscustomobject][ordered]@{
		exists = $true
		app_id = $privateAppId
		sanitized_json = (
			(ConvertTo-Json -InputObject $privateConfig -Depth 100) + "`n"
		)
	}
}

function Write-SanitizedPrivateConfigSnapshot {
	param(
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,
		[Parameter(Mandatory = $true)]
		[string]$DestinationPath
	)

	if (-not [bool]$Snapshot.exists) {
		return
	}
	Write-Utf8Text `
		-Path $DestinationPath `
		-Text ([string]$Snapshot.sanitized_json)
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

	$stream = [IO.File]::OpenRead($Path)
	$sha256 = [Security.Cryptography.SHA256]::Create()
	try {
		return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace(
			"-",
			""
		).ToUpperInvariant()
	}
	finally {
		$sha256.Dispose()
		$stream.Dispose()
	}
}

function Get-ReleaseFontPolicyEvidence {
	param([Parameter(Mandatory = $true)][string]$Root)

	$manifestPath = Join-Path $Root $ReleaseFontCoverageManifestRelativePath
	$coveragePath = Join-Path $Root $ReleaseFontCoverageRelativePath
	$subsetPath = Join-Path $Root $ReleaseFontSubsetRelativePath
	$sourcePath = Join-Path $Root $ReleaseFontSourceRelativePath
	$licensePath = Join-Path $Root $ReleaseFontLicenseRelativePath
	foreach ($requiredPath in @(
		$manifestPath,
		$coveragePath,
		$subsetPath,
		$sourcePath,
		$licensePath
	)) {
		if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
			throw "WeChat release font evidence is missing: $requiredPath"
		}
	}

	$manifest = Read-JsonObject -Path $manifestPath -Label "release font coverage manifest"
	if ([int]$manifest.schema_version -ne 1) {
		throw "WeChat release font coverage manifest schema must be 1."
	}
	if ([string]$manifest.policy_id -ne "wechat-release-shipped-literals-v1") {
		throw "WeChat release font coverage policy is not recognized."
	}
	$expectedSubsetPath = $ReleaseFontSubsetRelativePath.Replace("\", "/")
	$expectedSourcePath = $ReleaseFontSourceRelativePath.Replace("\", "/")
	$expectedLicensePath = $ReleaseFontLicenseRelativePath.Replace("\", "/")
	if ([string]$manifest.subset_font.path -ne $expectedSubsetPath) {
		throw "WeChat release font manifest points to an unexpected subset."
	}
	if ([string]$manifest.license.path -ne $expectedLicensePath) {
		throw "WeChat release font manifest points to an unexpected license."
	}
	if ([string]$manifest.source_font.path -ne $expectedSourcePath) {
		throw "WeChat release font manifest points to an unexpected source font."
	}

	$subsetSha256 = (Get-FileSha256 -Path $subsetPath).ToLowerInvariant()
	$sourceSha256 = (Get-FileSha256 -Path $sourcePath).ToLowerInvariant()
	$coverageSha256 = (Get-FileSha256 -Path $coveragePath).ToLowerInvariant()
	$licenseSha256 = (Get-FileSha256 -Path $licensePath).ToLowerInvariant()
	if ($subsetSha256 -ne ([string]$manifest.subset_font.sha256).ToLowerInvariant()) {
		throw "WeChat release font subset hash does not match its coverage manifest."
	}
	if ((Get-Item -LiteralPath $subsetPath).Length -ne [int64]$manifest.subset_font.bytes) {
		throw "WeChat release font subset byte count does not match its coverage manifest."
	}
	if ($sourceSha256 -ne ([string]$manifest.source_font.sha256).ToLowerInvariant()) {
		throw "WeChat release source font hash does not match its coverage manifest."
	}
	if ($coverageSha256 -ne ([string]$manifest.coverage.codepoints_sha256).ToLowerInvariant()) {
		throw "WeChat release font coverage hash does not match its manifest."
	}
	if ($licenseSha256 -ne ([string]$manifest.license.sha256).ToLowerInvariant()) {
		throw "WeChat release font license hash does not match its manifest."
	}
	if ([string]$manifest.license.spdx -ne "OFL-1.1") {
		throw "WeChat release font license must remain OFL-1.1."
	}

	return [ordered]@{
		policy_id = [string]$manifest.policy_id
		coverage_manifest_path = $ReleaseFontCoverageManifestRelativePath.Replace("\", "/")
		coverage_manifest_sha256 = (Get-FileSha256 -Path $manifestPath).ToLowerInvariant()
		coverage_path = $ReleaseFontCoverageRelativePath.Replace("\", "/")
		coverage_sha256 = $coverageSha256
		codepoint_count = [int]$manifest.coverage.codepoint_count
		subset_font_path = $expectedSubsetPath
		subset_font_sha256 = $subsetSha256
		subset_font_bytes = [int64]$manifest.subset_font.bytes
		source_font_path = $expectedSourcePath
		source_font_sha256 = $sourceSha256
		license_path = $expectedLicensePath
		license_spdx = [string]$manifest.license.spdx
		license_sha256 = $licenseSha256
	}
}

function Get-Utf8Sha256 {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Text
	)

	$bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
	$sha256 = [Security.Cryptography.SHA256]::Create()
	try {
		return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace(
			"-",
			""
		).ToLowerInvariant()
	}
	finally {
		$sha256.Dispose()
	}
}

function Assert-CanonicalManifestPath {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (
		[string]::IsNullOrWhiteSpace($Path) -or
		$Path.Contains("`t") -or
		$Path.Contains("`r") -or
		$Path.Contains("`n") -or
		$Path.StartsWith("/", [StringComparison]::Ordinal) -or
		$Path.Contains("../")
	) {
		throw "Manifest path is not canonically frameable: $Path"
	}
}

function Get-CanonicalRelativePath {
	param(
		[Parameter(Mandatory = $true)][string]$Root,
		[Parameter(Mandatory = $true)][string]$Path
	)

	$resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
	$resolvedPath = [IO.Path]::GetFullPath($Path)
	$rootPrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
	if (-not $resolvedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "Manifest file escaped its root: $resolvedPath"
	}
	return $resolvedPath.Substring($rootPrefix.Length).Replace("\", "/")
}

function Get-FileManifestEvidence {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Root,
		[Parameter(Mandatory = $true)]
		[IO.FileInfo[]]$Files,
		[Parameter(Mandatory = $true)]
		[string]$CanonicalHeader,
		[Parameter(Mandatory = $true)]
		[int]$SchemaVersion
	)

	$resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
	$filesByPath = [System.Collections.Generic.Dictionary[string,IO.FileInfo]]::new(
		[StringComparer]::Ordinal
	)
	foreach ($file in $Files) {
		$relativePath = Get-CanonicalRelativePath `
			-Root $resolvedRoot `
			-Path $file.FullName
		Assert-CanonicalManifestPath -Path $relativePath
		if ($filesByPath.ContainsKey($relativePath)) {
			throw "Manifest contains a duplicate path: $relativePath"
		}
		$filesByPath.Add($relativePath, $file)
	}
	$sortedPaths = @($filesByPath.Keys)
	[Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
	$entries = [System.Collections.Generic.List[object]]::new()
	$records = [System.Collections.Generic.List[string]]::new()
	$records.Add($CanonicalHeader)
	foreach ($relativePath in $sortedPaths) {
		$file = $filesByPath[$relativePath]
		$sha256 = (Get-FileSha256 -Path $file.FullName).ToLowerInvariant()
		$bytes = [int64]$file.Length
		$entries.Add([ordered]@{
			path = $relativePath
			bytes = $bytes
			sha256 = $sha256
		})
		$records.Add("$relativePath`t$bytes`t$sha256")
	}
	$canonicalText = ($records.ToArray() -join "`n") + "`n"
	return [ordered]@{
		schema_version = $SchemaVersion
		manifest_sha256 = Get-Utf8Sha256 -Text $canonicalText
		file_count = $entries.Count
		files = $entries.ToArray()
	}
}

function Get-ArtifactManifestEvidence {
	param([Parameter(Mandatory = $true)][string]$StageRoot)

	$artifactFiles = @(
		Get-ChildItem -LiteralPath $StageRoot -Recurse -File |
			Where-Object {
				$relativePath = Get-CanonicalRelativePath `
					-Root $StageRoot `
					-Path $_.FullName
				$relativePath -cne $VolatileLocalSidecarRelativePath
			}
	)
	return Get-FileManifestEvidence `
		-Root $StageRoot `
		-Files $artifactFiles `
		-CanonicalHeader "wechat-artifact-manifest-v$ArtifactManifestSchemaVersion" `
		-SchemaVersion $ArtifactManifestSchemaVersion
}

function Test-ExportInputExcluded {
	param([Parameter(Mandatory = $true)][string]$RelativePath)

	if ($ExportInputExcludedExactPaths -contains $RelativePath) {
		return $true
	}
	foreach ($prefix in $ExportInputExcludedPrefixes) {
		if ($RelativePath.StartsWith($prefix, [StringComparison]::Ordinal)) {
			return $true
		}
	}
	if (
		$RelativePath.Contains("/__pycache__/") -or
		$RelativePath.EndsWith(".pyc", [StringComparison]::OrdinalIgnoreCase) -or
		$RelativePath.EndsWith(".pyo", [StringComparison]::OrdinalIgnoreCase)
	) {
		return $true
	}
	return $false
}

function Get-ExportInputSnapshot {
	param([Parameter(Mandatory = $true)][string]$Root)

	$resolvedRoot = [IO.Path]::GetFullPath($Root)
	$filesByPath = [System.Collections.Generic.Dictionary[string,IO.FileInfo]]::new(
		[StringComparer]::Ordinal
	)
	foreach ($relativePath in $ExportInputExactPaths) {
		$fullPath = Join-Path $resolvedRoot $relativePath
		if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
			throw "Required export input is missing: $relativePath"
		}
		$filesByPath.Add($relativePath, (Get-Item -LiteralPath $fullPath))
	}
	foreach ($relativeRoot in $ExportInputRoots) {
		$fullRoot = Join-Path $resolvedRoot $relativeRoot
		if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) {
			throw "Required export input root is missing: $relativeRoot"
		}
		Assert-NoReparsePointTree -Path $fullRoot -Label "export input root $relativeRoot"
		foreach ($file in Get-ChildItem -LiteralPath $fullRoot -Recurse -File) {
			$relativePath = Get-CanonicalRelativePath `
				-Root $resolvedRoot `
				-Path $file.FullName
			if (Test-ExportInputExcluded -RelativePath $relativePath) {
				continue
			}
			if ($filesByPath.ContainsKey($relativePath)) {
				throw "Export input snapshot contains a duplicate path: $relativePath"
			}
			$filesByPath.Add($relativePath, $file)
		}
	}
	$manifest = Get-FileManifestEvidence `
		-Root $resolvedRoot `
		-Files @($filesByPath.Values) `
		-CanonicalHeader "wechat-export-input-snapshot-v$InputSnapshotSchemaVersion" `
		-SchemaVersion $InputSnapshotSchemaVersion
	return [ordered]@{
		schema_version = $InputSnapshotSchemaVersion
		input_snapshot_sha256 = $manifest.manifest_sha256
		file_count = $manifest.file_count
		rules = [ordered]@{
			include_exact = @($ExportInputExactPaths)
			include_roots = @($ExportInputRoots)
			exclude_exact = @($ExportInputExcludedExactPaths)
			exclude_prefixes = @($ExportInputExcludedPrefixes)
			exclude_generated = @(
				".git/",
				".godot/",
				"build/",
				"tests/",
				"tools/",
				"__pycache__/"
			)
			exclude_cache_suffixes = @(".pyc", ".pyo")
		}
	}
}

function Get-GfVendorIdentity {
	param([Parameter(Mandatory = $true)][string]$Root)

	$resolvedRoot = [IO.Path]::GetFullPath($Root)
	$lockPath = Join-Path $resolvedRoot ".gf\vendor.lock.json"
	$vendorRoot = Join-Path $resolvedRoot "addons\gf"
	if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
		throw "GF vendor lock is missing: $lockPath"
	}
	if (-not (Test-Path -LiteralPath $vendorRoot -PathType Container)) {
		throw "GF vendor root is missing: $vendorRoot"
	}
	Assert-NoReparsePointTree -Path $vendorRoot -Label "GF vendor root"
	$lock = Read-JsonObject -Path $lockPath -Label "GF vendor lock"
	$sourceCommit = [string]$lock.source_commit
	$sourceGitTree = [string]$lock.source_git_tree
	$lockedTreeHash = ([string]$lock.vendor_tree_sha256).ToLowerInvariant()
	if ([int]$lock.schema_version -ne 2) {
		throw "GF vendor lock schema_version must be 2."
	}
	if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
		throw "GF vendor source_commit must be a lowercase 40-character Git hash."
	}
	if ($sourceGitTree -notmatch '^[0-9a-f]{40}$') {
		throw "GF vendor source_git_tree must be a lowercase 40-character Git hash."
	}
	if ($lockedTreeHash -notmatch '^[0-9a-f]{64}$') {
		throw "GF vendor_tree_sha256 must be a 64-character SHA-256."
	}
	$records = [System.Collections.Generic.List[string]]::new()
	foreach ($file in Get-ChildItem -LiteralPath $vendorRoot -Recurse -File) {
		$relativePath = Get-CanonicalRelativePath `
			-Root $vendorRoot `
			-Path $file.FullName
		if (
			$relativePath -match '(^|/)__pycache__/' -or
			$relativePath -match '(?i)\.py[cod]$'
		) {
			continue
		}
		Assert-CanonicalManifestPath -Path $relativePath
		$records.Add(
			"$relativePath`t$((Get-FileSha256 -Path $file.FullName).ToLowerInvariant())"
		)
	}
	$sortedRecords = $records.ToArray()
	[Array]::Sort($sortedRecords, [StringComparer]::Ordinal)
	$actualTreeHash = Get-Utf8Sha256 -Text (($sortedRecords -join "`n") + "`n")
	if ([int]$lock.vendor_file_count -ne $sortedRecords.Length) {
		throw (
			"GF vendor file count mismatch: lock={0}, actual={1}." -f
			[int]$lock.vendor_file_count,
			$sortedRecords.Length
		)
	}
	if ($actualTreeHash -ne $lockedTreeHash) {
		throw "GF vendor tree hash mismatch: lock=$lockedTreeHash, actual=$actualTreeHash."
	}
	return [ordered]@{
		framework_version = [string]$lock.framework_version
		source_commit = $sourceCommit
		source_git_tree = $sourceGitTree
		vendor_tree_sha256 = $actualTreeHash
		vendor_file_count = $sortedRecords.Length
		lock_sha256 = (Get-FileSha256 -Path $lockPath).ToLowerInvariant()
	}
}

function Get-GodotIdentity {
	param([Parameter(Mandatory = $true)][string]$Executable)

	$command = Get-Command $Executable -ErrorAction Stop
	$godotPath = $command.Source
	$versionOutput = ""
	$versionExitCode = $null
	$extension = [IO.Path]::GetExtension($godotPath)
	if ($extension -in @(".cmd", ".bat")) {
		$versionOutput = (& $godotPath --version | Select-Object -First 1).Trim()
		$versionExitCode = $LASTEXITCODE
	}
	else {
		$startInfo = [Diagnostics.ProcessStartInfo]::new()
		$startInfo.FileName = $godotPath
		$startInfo.Arguments = "--version"
		$startInfo.UseShellExecute = $false
		$startInfo.CreateNoWindow = $true
		$startInfo.RedirectStandardOutput = $true
		$startInfo.RedirectStandardError = $true
		$process = [Diagnostics.Process]::new()
		$process.StartInfo = $startInfo
		try {
			if (-not $process.Start()) {
				throw "Godot version process did not start."
			}
			$stdoutTask = $process.StandardOutput.ReadToEndAsync()
			$stderrTask = $process.StandardError.ReadToEndAsync()
			if (-not $process.WaitForExit(10000)) {
				$process.Kill()
				$process.WaitForExit()
				throw "Godot version preflight timed out for $godotPath."
			}
			$process.WaitForExit()
			$versionExitCode = $process.ExitCode
			$stdout = $stdoutTask.GetAwaiter().GetResult()
			$null = $stderrTask.GetAwaiter().GetResult()
			$versionLines = @(
				$stdout -split '[\r\n]+' |
					Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
			)
			if ($versionLines.Count -gt 0) {
				$versionOutput = $versionLines[0].Trim()
			}
		}
		finally {
			$process.Dispose()
		}
	}
	if ($versionExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($versionOutput)) {
		throw "Godot version preflight failed for $godotPath."
	}
	$requiredPattern = '^' + [regex]::Escape($RequiredGodotVersionPrefix) + '(?:\.|$)'
	if ($versionOutput -cnotmatch $requiredPattern) {
		throw (
			"Godot $RequiredGodotVersionPrefix is required for this WeChat export profile; " +
			"got $versionOutput from $godotPath."
		)
	}
	return [ordered]@{
		executable = $godotPath
		version = $versionOutput
		required_version_prefix = $RequiredGodotVersionPrefix
	}
}

function Get-ToolIdentity {
	param([Parameter(Mandatory = $true)][string]$Root)

	$identity = [ordered]@{}
	foreach ($name in $ToolIdentityRelativePaths.Keys) {
		$relativePath = [string]$ToolIdentityRelativePaths[$name]
		$fullPath = Join-Path $Root $relativePath
		if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
			throw "Tool identity input is missing: $relativePath"
		}
		$identity[$name] = [ordered]@{
			path = $relativePath.Replace("\", "/")
			sha256 = (Get-FileSha256 -Path $fullPath).ToLowerInvariant()
		}
	}
	return $identity
}

function Get-CandidateBuildId {
	param(
		[Parameter(Mandatory = $true)][object]$GodotIdentity,
		[Parameter(Mandatory = $true)][object]$GfIdentity,
		[Parameter(Mandatory = $true)][string]$InputSnapshotSha256,
		[Parameter(Mandatory = $true)][int]$InputSnapshotFileCount,
		[Parameter(Mandatory = $true)][string]$ArtifactManifestSha256,
		[Parameter(Mandatory = $true)][object]$ToolIdentity,
		[string]$Scope = $ReportScope,
		[string]$Preset = $ExportPreset,
		[string]$ReleaseFontManifestSha256 = "",
		[string]$ReleaseFontSubsetSha256 = ""
	)

	$records = @(
		"wechat-candidate-build-v$BuildIdentitySchemaVersion",
		"scope=$Scope",
		"export_preset=$Preset",
		"release_font_manifest_sha256=$ReleaseFontManifestSha256",
		"release_font_subset_sha256=$ReleaseFontSubsetSha256",
		"godot=$($GodotIdentity.version)",
		"gf_framework_version=$($GfIdentity.framework_version)",
		"gf_source_commit=$($GfIdentity.source_commit)",
		"gf_source_git_tree=$($GfIdentity.source_git_tree)",
		"gf_vendor_tree_sha256=$($GfIdentity.vendor_tree_sha256)",
		"gf_vendor_file_count=$($GfIdentity.vendor_file_count)",
		"gf_lock_sha256=$($GfIdentity.lock_sha256)",
		"input_snapshot_sha256=$InputSnapshotSha256",
		"input_snapshot_file_count=$InputSnapshotFileCount",
		"artifact_manifest_sha256=$ArtifactManifestSha256",
		"template_sha256=$($TemplateExpectedSha256.ToLowerInvariant())",
		"export_tool_sha256=$($ToolIdentity.export_tool.sha256)",
		"artifact_verifier_sha256=$($ToolIdentity.artifact_verifier.sha256)",
		"artifact_check_sha256=$($ToolIdentity.artifact_check.sha256)",
		"bounded_json_reader_sha256=$($ToolIdentity.bounded_json_reader.sha256)",
		"path_tools_sha256=$($ToolIdentity.path_tools.sha256)",
		"chunk_loader_sha256=$($ToolIdentity.chunk_loader.sha256)",
		"wxmemfs_patch_sha256=$($ToolIdentity.wxmemfs_patch.sha256)"
	)
	return Get-Utf8Sha256 -Text (($records -join "`n") + "`n")
}

function Assert-FrozenExportIdentity {
	param(
		[Parameter(Mandatory = $true)][string]$Root,
		[Parameter(Mandatory = $true)][object]$ExpectedGfIdentity,
		[Parameter(Mandatory = $true)][object]$ExpectedInputSnapshot,
		[Parameter(Mandatory = $true)][object]$ExpectedToolIdentity
	)

	$actualGfIdentity = Get-GfVendorIdentity -Root $Root
	foreach ($field in @(
		"source_commit",
		"source_git_tree",
		"vendor_tree_sha256",
		"vendor_file_count",
		"lock_sha256"
	)) {
		if ([string]$actualGfIdentity[$field] -ne [string]$ExpectedGfIdentity[$field]) {
			throw "GF identity changed during WeChat export: $field."
		}
	}
	$actualInputSnapshot = Get-ExportInputSnapshot -Root $Root
	if (
		[string]$actualInputSnapshot.input_snapshot_sha256 -ne
		[string]$ExpectedInputSnapshot.input_snapshot_sha256
	) {
		throw "Export input content changed during WeChat export."
	}
	$actualToolIdentity = Get-ToolIdentity -Root $Root
	foreach ($name in $ToolIdentityRelativePaths.Keys) {
		if (
			[string]$actualToolIdentity[$name].sha256 -ne
			[string]$ExpectedToolIdentity[$name].sha256
		) {
			throw "Tool identity changed during WeChat export: $name."
		}
	}
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
		throw "Godot WeChat pack export timed out after $TimeoutSeconds seconds."
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
		[string]$ReportPath,
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
		"--report-path",
		$ReportPath,
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
	$globalScriptCachePath = Join-Path `
		$VerificationProjectRoot `
		".godot\global_script_class_cache.cfg"
	$null = New-Item `
		-ItemType Directory `
		-Force `
		-Path (Split-Path -Parent $globalScriptCachePath)
	Write-Utf8Text `
		-Path $globalScriptCachePath `
		-Text @"
list=[{
"base": &"RefCounted",
"class": &"GFBoundedJsonObjectReader",
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": "res://addons/gf/kernel/core/gf_bounded_json_object_reader.gd"
}, {
"base": &"RefCounted",
"class": &"GFPathTools",
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": "res://addons/gf/kernel/core/gf_path_tools.gd"
}]
"@
	foreach ($relativePath in $ToolIdentityRelativePaths.Values) {
		$destinationPath = Join-Path $VerificationProjectRoot $relativePath
		$null = New-Item `
			-ItemType Directory `
			-Force `
			-Path (Split-Path -Parent $destinationPath)
		Copy-Item `
			-LiteralPath (Join-Path $ProjectRoot $relativePath) `
			-Destination $destinationPath
	}
	# Coverage evidence belongs to the isolated verification host, not the
	# runtime pack. The verifier binds these copies to the frozen report hashes
	# while the mounted pack must contain only the subset font and runtime data.
	if ($IsReleaseProfile) {
		foreach ($relativePath in @(
			$ReleaseFontCoverageManifestRelativePath,
			$ReleaseFontCoverageRelativePath
		)) {
			$destinationPath = Join-Path $VerificationProjectRoot $relativePath
			$null = New-Item `
				-ItemType Directory `
				-Force `
				-Path (Split-Path -Parent $destinationPath)
			Copy-Item `
				-LiteralPath (Join-Path $ProjectRoot $relativePath) `
				-Destination $destinationPath
		}
	}
}

function Get-PreservedAppId {
	param(
		[Parameter(Mandatory = $true)]
		[object]$PrivateConfigSnapshot
	)

	if (-not [string]::IsNullOrWhiteSpace($AppId)) {
		return $AppId.Trim()
	}
	$existingConfigPath = Join-Path $outputRoot "project.config.json"
	$publicAppId = ""
	if (Test-Path -LiteralPath $existingConfigPath -PathType Leaf) {
		Assert-NoReparsePointPath -Path $existingConfigPath -Label "existing WeChat project config"
		$existingConfig = Read-JsonObject `
			-Path $existingConfigPath `
			-Label "existing project.config.json"
		$publicAppId = [string]$existingConfig.appid
	}
	$privateAppId = [string]$PrivateConfigSnapshot.app_id
	if (-not [string]::IsNullOrWhiteSpace($privateAppId)) {
		return $privateAppId.Trim()
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
		"engine/game.js",
		"engine/wechat-chunked-file-loader.js",
		"engine/godot-sdk.js",
		"engine/godot.js",
		"engine/godot.wasm.br",
		"game_data/$PackFileName",
		"game_data/game.js",
		"game.js",
		"game.json",
		"glx-config.js",
		"godot-loader.js",
		"images/background.png",
		"images/logo.png",
		"project.config.json",
		$VolatileLocalSidecarRelativePath,
		"weapp-adapter.js"
	)
	$files = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -File)
	$discoveredRelativePaths = @()
	$relativePaths = @()
	$unexpectedPaths = @()
	$mainPackageBytes = [int64]0
	$enginePackageBytes = [int64]0
	$gameDataPackageBytes = [int64]0
	foreach ($file in $files) {
		$relativePath = Get-RelativeOutputPath -Root $StageRoot -FullName $file.FullName
		$discoveredRelativePaths += $relativePath
		if ($allowedPaths -notcontains $relativePath) {
			$unexpectedPaths += $relativePath
		}
		# DevTools owns this local preference sidecar; validate it separately but do not
		# let it perturb publishable package evidence or candidate identity.
		if ($relativePath -ceq $VolatileLocalSidecarRelativePath) {
			continue
		}
		$relativePaths += $relativePath
		if ($relativePath.StartsWith("engine/", [StringComparison]::OrdinalIgnoreCase)) {
			$enginePackageBytes += $file.Length
		}
		elseif ($relativePath.StartsWith("game_data/", [StringComparison]::OrdinalIgnoreCase)) {
			$gameDataPackageBytes += $file.Length
		}
		else {
			$mainPackageBytes += $file.Length
		}
	}
	$requiredPaths = $allowedPaths | Where-Object {
		$_ -cne $VolatileLocalSidecarRelativePath
	}
	$missingPaths = @(
		$requiredPaths | Where-Object { $discoveredRelativePaths -notcontains $_ }
	)
	$forbiddenPaths = @(
		$discoveredRelativePaths | Where-Object {
			$_ -match '(?i)\.(?:pck|html|wasm)$'
		}
	)
	[string[]]$sortedRelativePaths = @($relativePaths)
	[Array]::Sort($sortedRelativePaths, [StringComparer]::Ordinal)
	$totalPackageBytes = $mainPackageBytes + $enginePackageBytes + $gameDataPackageBytes
	return [ordered]@{
		main_package_bytes = $mainPackageBytes
		engine_package_bytes = $enginePackageBytes
		game_data_package_bytes = $gameDataPackageBytes
		total_package_bytes = $totalPackageBytes
		main_hard_limit_bytes = $MainPackageHardLimitBytes
		engine_hard_limit_bytes = $SubpackageHardLimitBytes
		game_data_hard_limit_bytes = $SubpackageHardLimitBytes
		total_hard_limit_bytes = $TotalPackageHardLimitBytes
		main_soft_limit_bytes = $MainPackageSoftLimitBytes
		engine_soft_limit_bytes = $SubpackageSoftLimitBytes
		game_data_soft_limit_bytes = $SubpackageSoftLimitBytes
		total_soft_limit_bytes = $TotalPackageSoftLimitBytes
		main_hard_limit_ok = ($mainPackageBytes -le $MainPackageHardLimitBytes)
		engine_hard_limit_ok = ($enginePackageBytes -le $SubpackageHardLimitBytes)
		game_data_hard_limit_ok = ($gameDataPackageBytes -le $SubpackageHardLimitBytes)
		total_hard_limit_ok = ($totalPackageBytes -le $TotalPackageHardLimitBytes)
		main_soft_budget_ok = ($mainPackageBytes -le $MainPackageSoftLimitBytes)
		engine_soft_budget_ok = ($enginePackageBytes -le $SubpackageSoftLimitBytes)
		game_data_soft_budget_ok = ($gameDataPackageBytes -le $SubpackageSoftLimitBytes)
		total_soft_budget_ok = ($totalPackageBytes -le $TotalPackageSoftLimitBytes)
		file_count = $relativePaths.Count
		files = @($sortedRelativePaths)
		missing_paths = $missingPaths
		unexpected_paths = $unexpectedPaths
		forbidden_paths = $forbiddenPaths
	}
}

function Assert-ExistingCandidateBundleShape {
	param([Parameter(Mandatory = $true)][string]$Path)

	$candidateRoot = Assert-SafeBuildChildPath `
		-Path $Path `
		-Label "existing WeChat candidate bundle"
	if (-not (Test-Path -LiteralPath $candidateRoot)) {
		return
	}
	if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
		throw "Existing WeChat candidate root must be a directory: $candidateRoot"
	}
	Assert-NoReparsePointTree -Path $candidateRoot -Label "existing WeChat candidate bundle"
	foreach ($entry in Get-ChildItem -Force -LiteralPath $candidateRoot) {
		$allowed = (
			($entry.Name -ceq "wxgame" -and $entry.PSIsContainer) -or
			($entry.Name -ceq "export-report.json" -and -not $entry.PSIsContainer)
		)
		if (-not $allowed) {
			throw (
				"Existing WeChat candidate root contains an unrelated entry and " +
				"cannot be replaced safely: $($entry.FullName)"
			)
		}
	}
}

function Publish-CandidateBundle {
	param(
		[Parameter(Mandatory = $true)]
		[string]$StageCandidateRoot,
		[Parameter(Mandatory = $true)]
		[string]$FinalCandidateRoot,
		[Parameter(Mandatory = $true)]
		[string]$BackupCandidateRoot,
		[ValidateSet("", "after_candidate_backup", "after_candidate_publish")]
		[string]$FailureInjection = ""
	)

	$stageRoot = Assert-SafeBuildChildPath `
		-Path $StageCandidateRoot `
		-Label "staged WeChat candidate bundle"
	$finalRoot = Assert-SafeBuildChildPath `
		-Path $FinalCandidateRoot `
		-Label "published WeChat candidate bundle"
	$backupRoot = Assert-SafeBuildChildPath `
		-Path $BackupCandidateRoot `
		-Label "backed-up WeChat candidate bundle"
	if (-not (Test-Path -LiteralPath $stageRoot -PathType Container)) {
		throw "Staged WeChat candidate bundle does not exist: $stageRoot"
	}
	Assert-NoReparsePointTree -Path $stageRoot -Label "staged WeChat candidate bundle"
	if (Test-Path -LiteralPath $backupRoot) {
		throw "WeChat candidate backup path already exists: $backupRoot"
	}

	$previousCandidateBackedUp = $false
	$newCandidatePublished = $false
	$publishCommitted = $false
	try {
		if (Test-Path -LiteralPath $finalRoot) {
			Assert-ExistingCandidateBundleShape -Path $finalRoot
			Move-Item -LiteralPath $finalRoot -Destination $backupRoot
			$previousCandidateBackedUp = $true
		}
		if ($FailureInjection -eq "after_candidate_backup") {
			throw "Injected WeChat candidate transaction failure after backup."
		}
		Move-Item -LiteralPath $stageRoot -Destination $finalRoot
		$newCandidatePublished = $true
		if ($FailureInjection -eq "after_candidate_publish") {
			throw "Injected WeChat candidate transaction failure after publish."
		}
		$publishCommitted = $true
	}
	catch {
		$originalError = $_
		if (-not $publishCommitted) {
			if ($newCandidatePublished -and (Test-Path -LiteralPath $finalRoot)) {
				Remove-SafeBuildTree `
					-Path $finalRoot `
					-Label "failed published WeChat candidate bundle"
				$newCandidatePublished = $false
			}
			if ($previousCandidateBackedUp -and (Test-Path -LiteralPath $backupRoot)) {
				Move-Item -LiteralPath $backupRoot -Destination $finalRoot
				$previousCandidateBackedUp = $false
			}
			if (Test-Path -LiteralPath $stageRoot) {
				Remove-SafeBuildTree `
					-Path $stageRoot `
					-Label "failed staged WeChat candidate bundle"
			}
		}
		throw $originalError
	}

	if ($previousCandidateBackedUp -and (Test-Path -LiteralPath $backupRoot)) {
		try {
			Remove-SafeBuildTree `
				-Path $backupRoot `
				-Label "retired WeChat candidate bundle backup"
		}
		catch {
			Write-Warning (
				"The new WeChat candidate is committed, but its retired backup " +
				"could not be fully removed: " + $_.Exception.Message
			)
		}
	}
}

if ($FunctionsOnly) {
	return
}

$AppId = Assert-WeChatAppId -Value $AppId -Source "-AppId"
$releaseFontPolicy = if ($IsReleaseProfile) {
	Get-ReleaseFontPolicyEvidence -Root $ProjectRoot
}
else {
	$null
}
$outputRoot = Assert-SafeBuildChildPath -Path $outputRoot -Label "WeChat candidate output"
if ((Split-Path -Leaf $outputRoot) -ne "wxgame") {
	throw "WeChat OutputPath must end in a dedicated wxgame directory."
}
$outputCandidateRoot = Assert-SafeBuildChildPath `
	-Path $outputCandidateRoot `
	-Label "WeChat candidate bundle"
$buildPrefix = $projectBuildRoot.TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
if (
	-not $outputCandidateParent.Equals(
		$projectBuildRoot,
		[StringComparison]::OrdinalIgnoreCase
	) -and
	-not $outputCandidateParent.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)
) {
	throw "WeChat candidate parent must stay under the project build directory."
}
Assert-NoReparsePointPath -Path $outputCandidateParent -Label "WeChat candidate parent"
$null = New-Item -ItemType Directory -Force -Path $outputCandidateParent
Assert-ExistingCandidateBundleShape -Path $outputCandidateRoot

# Freeze every identity before any candidate staging or export work starts.
$privateConfigSnapshot = Get-SanitizedPrivateConfigSnapshot `
	-Path (Join-Path $outputRoot $VolatileLocalSidecarRelativePath)
$godotIdentity = Get-GodotIdentity -Executable $GodotExecutable
$godotPath = $godotIdentity.executable
$gfIdentity = Get-GfVendorIdentity -Root $ProjectRoot
$inputSnapshot = Get-ExportInputSnapshot -Root $ProjectRoot
$toolIdentity = Get-ToolIdentity -Root $ProjectRoot
$preservedAppId = Assert-WeChatAppId `
	-Value (Get-PreservedAppId -PrivateConfigSnapshot $privateConfigSnapshot) `
	-Source "preserved project.config.json AppID"
$candidateName = Split-Path -Leaf $outputCandidateRoot
$stageCandidateRoot = ""
$verificationProjectRoot = ""
$backupCandidateRoot = ""
try {
	$stageCandidateRoot = Assert-SafeBuildChildPath `
		-Path (Join-Path $outputCandidateParent (
			".$candidateName.stage-" + [Guid]::NewGuid().ToString("N")
		)) `
		-Label "WeChat candidate staging bundle"
	$stageRoot = Join-Path $stageCandidateRoot "wxgame"
	$null = New-Item -ItemType Directory -Path $stageCandidateRoot
	$null = New-Item -ItemType Directory -Path $stageRoot
	if ($TestFailureInjection -eq "after_candidate_stage") {
		throw "Injected WeChat candidate transaction failure after stage creation."
	}
	$stageReportPath = Join-Path $stageCandidateRoot "export-report.json"
	$reportPath = Join-Path $outputCandidateRoot "export-report.json"
	$backupCandidateRoot = Assert-SafeBuildChildPath `
		-Path (Join-Path $outputCandidateParent (
			".$candidateName.backup-" + [Guid]::NewGuid().ToString("N")
		)) `
		-Label "WeChat candidate backup bundle"
	$verificationProjectRoot = Assert-SafeBuildChildPath `
		-Path (Join-Path $outputCandidateParent (
			".$candidateName.verify-" + [Guid]::NewGuid().ToString("N")
		)) `
		-Label "isolated WeChat artifact verification project"

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

	$godotLoaderPath = Join-Path $stageRoot "godot-loader.js"
	$godotLoaderSha256 = Get-FileSha256 -Path $godotLoaderPath
	if ($godotLoaderSha256 -ne $TemplateGodotLoaderSha256) {
		throw (
			"Pinned godot-loader.js hash mismatch before lifecycle patch: expected " +
			"$TemplateGodotLoaderSha256, got $godotLoaderSha256"
		)
	}
	$godotLoaderSource = Get-Content -Raw -Encoding UTF8 -LiteralPath $godotLoaderPath
	$godotLoaderSource = ConvertTo-WeChatSubpackageLifecyclePatchedSource `
		-Source $godotLoaderSource
	Write-Utf8Text -Path $godotLoaderPath -Text $godotLoaderSource

	$gameConfig = [ordered]@{
		deviceOrientation = $DeviceOrientation
		iOSHighPerformance = $true
		"iOSHighPerformance+" = $true
		plugins = [ordered]@{}
		subpackages = @(
			[ordered]@{
				name = "game_data"
				root = "game_data/"
			},
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
	$projectConfig.description = $ProjectDescription
	$projectConfig | Add-Member `
		-NotePropertyName "projectname" `
		-NotePropertyValue $WeChatProjectName `
		-Force
	$projectConfig.compileType = "minigame"
	$projectConfig.appid = $preservedAppId
	$projectConfig.isGameTourist = $false
	$packIgnore = @()
	if (
		$null -ne $projectConfig.packOptions `
		-and $null -ne $projectConfig.packOptions.ignore
	) {
		$packIgnore = @($projectConfig.packOptions.ignore)
	}
	$projectConfig | Add-Member `
		-NotePropertyName "packOptions" `
		-NotePropertyValue ([ordered]@{
			ignore = $packIgnore
			include = @(
				[ordered]@{
					type = "file"
					value = "engine/godot.wasm.br"
				},
				[ordered]@{
					type = "file"
					value = "game_data/$PackFileName"
				}
			)
		}) `
		-Force
	Write-Utf8Text `
		-Path $projectConfigPath `
		-Text (($projectConfig | ConvertTo-Json -Depth 16) + "`n")
	Write-SanitizedPrivateConfigSnapshot `
		-Snapshot $privateConfigSnapshot `
		-DestinationPath (Join-Path $stageRoot $VolatileLocalSidecarRelativePath)

	$gameDataRoot = Join-Path $stageRoot "game_data"
	$null = New-Item -ItemType Directory -Force -Path $gameDataRoot
	$temporaryPackPath = Join-Path $gameDataRoot "2048-all-in-one.pck"
	Invoke-GodotPackExport -GodotPath $godotPath -PackPath $temporaryPackPath
	$finalPackPath = Join-Path $gameDataRoot $PackFileName
	Move-Item -LiteralPath $temporaryPackPath -Destination $finalPackPath
	Write-Utf8Text -Path (Join-Path $gameDataRoot "game.js") -Text @"
GameGlobal.__godotGameDataSubpackageEntryStarted = true;
console.log('[wechat-subpackage] entry_started', 'game_data', 'game_data/game.js');
"@

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
			path = "/game_data/$PackFileName"
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
GameGlobal.__godotEngineSubpackageEntryStarted = true;
console.log('[wechat-subpackage] entry_started', 'engine', 'engine/game.js');
const exe = '/engine/godot';
const pack = '/game_data/$PackFileName';
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
	if (-not $engineGameText.Contains("/game_data/$PackFileName")) {
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
	if (-not $packageEvidence.engine_hard_limit_ok) {
		throw "Generated WeChat engine package exceeds $SubpackageHardLimitBytes bytes."
	}
	if (-not $packageEvidence.game_data_hard_limit_ok) {
		throw "Generated WeChat game_data package exceeds $SubpackageHardLimitBytes bytes."
	}
	if (-not $packageEvidence.total_hard_limit_ok) {
		throw "Generated WeChat package exceeds $TotalPackageHardLimitBytes bytes."
	}
	$artifactManifest = Get-ArtifactManifestEvidence -StageRoot $stageRoot
	$artifactManifestSha256 = [string]$artifactManifest.manifest_sha256
	$inputSnapshotSha256 = [string]$inputSnapshot.input_snapshot_sha256
	$buildId = Get-CandidateBuildId `
		-GodotIdentity $godotIdentity `
		-GfIdentity $gfIdentity `
		-InputSnapshotSha256 $inputSnapshotSha256 `
		-InputSnapshotFileCount ([int]$inputSnapshot.file_count) `
		-ArtifactManifestSha256 $artifactManifestSha256 `
		-ToolIdentity $toolIdentity `
		-Scope $ReportScope `
		-Preset $ExportPreset `
		-ReleaseFontManifestSha256 $(
			if ($IsReleaseProfile) {
				[string]$releaseFontPolicy.coverage_manifest_sha256
			}
			else {
				""
			}
		) `
		-ReleaseFontSubsetSha256 $(
			if ($IsReleaseProfile) {
				[string]$releaseFontPolicy.subset_font_sha256
			}
			else {
				""
			}
		)
	$report = [ordered]@{
		schema_version = $ExportReportSchemaVersion
		ok = $true
		scope = $ReportScope
		build_id = $buildId
		generated_at = [DateTimeOffset]::Now.ToString("o")
		output_path = $outputRoot
		report_path = $reportPath
		export_preset = $ExportPreset
		input_snapshot_sha256 = $inputSnapshotSha256
		artifact_manifest_sha256 = $artifactManifestSha256
		godot = $godotIdentity
		gf = $gfIdentity
		input_snapshot = $inputSnapshot
		tool_identity = $toolIdentity
		template = [ordered]@{
			repository = "https://github.com/godothub/godot-minigame"
			release = $TemplateRelease
			asset = $TemplateAssetName
			download_url = $TemplateDownloadUrl
			expected_bytes = $TemplateExpectedBytes
			sha256 = $TemplateExpectedSha256.ToLowerInvariant()
			archive_path = $templateArchive
		}
		artifact = $artifactManifest
		app_id_configured = -not [string]::IsNullOrWhiteSpace($preservedAppId)
		project_name = $WeChatProjectName
		device_orientation = $DeviceOrientation
		user_file_system = $wxMemFsRenameEvidence
		large_file_reader = $largeFileReaderEvidence
		package = $packageEvidence
		limitations = if ($IsReleaseProfile) {
			@(
				"This candidate contains the full game, but is not a signed production release.",
				"WeChat login, share, payment, cloud save and open-data capabilities are not enabled.",
				"Preview, upload and device validation require the project's own Mini Game AppID."
			)
		}
		else {
			@(
				"This is a platform/toolchain smoke build, not a production release.",
				"WeChat login, share, payment, cloud save and open-data capabilities are not enabled.",
				"Preview, upload and device validation require the project's own Mini Game AppID."
			)
		}
	}
	if ($IsReleaseProfile) {
		$report.Add("font_policy", $releaseFontPolicy)
	}
	Write-Utf8Text `
		-Path $stageReportPath `
		-Text (($report | ConvertTo-Json -Depth 16) + "`n")
	$stageReportSha256 = Get-FileSha256 -Path $stageReportPath
	Initialize-GodotArtifactVerificationProject `
		-VerificationProjectRoot $verificationProjectRoot
	try {
		Invoke-GodotArtifactVerification `
			-GodotPath $godotPath `
			-ArtifactRoot $stageRoot `
			-ReportPath $stageReportPath `
			-VerificationProjectRoot $verificationProjectRoot
	}
	finally {
		if (Test-Path -LiteralPath $verificationProjectRoot) {
			Remove-SafeBuildTree `
				-Path $verificationProjectRoot `
				-Label "isolated WeChat artifact verification project"
		}
	}
	if ((Get-FileSha256 -Path $stageReportPath) -ne $stageReportSha256) {
		throw "Staged WeChat export report changed after report-bound verification."
	}
	$publicationManifest = Get-ArtifactManifestEvidence -StageRoot $stageRoot
	if (
		[string]$publicationManifest.manifest_sha256 -ne $artifactManifestSha256 -or
		[int]$publicationManifest.file_count -ne [int]$artifactManifest.file_count
	) {
		throw "Staged WeChat artifact changed after report-bound verification."
	}
	Assert-FrozenExportIdentity `
		-Root $ProjectRoot `
		-ExpectedGfIdentity $gfIdentity `
		-ExpectedInputSnapshot $inputSnapshot `
		-ExpectedToolIdentity $toolIdentity

	Publish-CandidateBundle `
		-StageCandidateRoot $stageCandidateRoot `
		-FinalCandidateRoot $outputCandidateRoot `
		-BackupCandidateRoot $backupCandidateRoot `
		-FailureInjection $TestFailureInjection

	Write-Host "WeChat Mini Game $Profile export: PASS"
	Write-Host "Output: $outputRoot"
	Write-Host "Build ID: $buildId"
	Write-Host (
		"Package bytes: main={0}, engine={1}, game_data={2}, total={3}" -f
		$packageEvidence.main_package_bytes,
		$packageEvidence.engine_package_bytes,
		$packageEvidence.game_data_package_bytes,
		$packageEvidence.total_package_bytes
	)
	Write-Host "Report: $reportPath"
}
catch {
	$originalError = $_
	if (
		-not [string]::IsNullOrWhiteSpace($stageCandidateRoot) -and
		(Test-Path -LiteralPath $stageCandidateRoot)
	) {
		Remove-SafeBuildTree `
			-Path $stageCandidateRoot `
			-Label "failed WeChat candidate staging bundle"
	}
	if (
		-not [string]::IsNullOrWhiteSpace($verificationProjectRoot) -and
		(Test-Path -LiteralPath $verificationProjectRoot)
	) {
		Remove-SafeBuildTree `
			-Path $verificationProjectRoot `
			-Label "failed isolated WeChat artifact verification project"
	}
	throw $originalError
}
