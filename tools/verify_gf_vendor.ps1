param(
	[string]$ProjectRoot = ".",
	[string]$LockPath = ".gf/vendor.lock.json",
	[string]$UpstreamRepositoryPath = "",
	[switch]$VerifyRemote,
	[switch]$FunctionsOnly
)

$ErrorActionPreference = "Stop"

$script:GfReleaseManifestMaximumBytes = 1MB
$script:GfReleaseArchiveMaximumBytes = 256MB

function Get-GitHubHeaders {
	param([Parameter(Mandatory = $true)][string]$Accept)

	$headers = @{
		"Accept" = $Accept
		"User-Agent" = "2048-all-in-one-gf-vendor-verifier"
		"X-GitHub-Api-Version" = "2022-11-28"
	}
	if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
		$headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)"
	}
	return $headers
}

function Invoke-GitHubApi {
	param([Parameter(Mandatory = $true)][string]$Uri)

	return Invoke-RestMethod `
		-Method Get `
		-Uri $Uri `
		-Headers (Get-GitHubHeaders -Accept "application/vnd.github+json")
}

function Invoke-GitHubAssetBytes {
	param([Parameter(Mandatory = $true)][string]$Uri)

	$tempPath = [IO.Path]::GetTempFileName()
	try {
		Invoke-WebRequest `
			-Method Get `
			-Uri $Uri `
			-Headers (Get-GitHubHeaders -Accept "application/octet-stream") `
			-UseBasicParsing `
			-OutFile $tempPath | Out-Null
		return ,([IO.File]::ReadAllBytes($tempPath))
	} finally {
		if ([IO.File]::Exists($tempPath)) {
			[IO.File]::Delete($tempPath)
		}
	}
}

function Get-Sha256Hex {
	param([Parameter(Mandatory = $true)][byte[]]$Bytes)

	$hasher = [Security.Cryptography.SHA256]::Create()
	try {
		return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace(
			"-",
			""
		).ToLowerInvariant()
	} finally {
		$hasher.Dispose()
	}
}

function Test-CommonActionsRun {
	param(
		[Parameter(Mandatory = $true)][object]$Run,
		[Parameter(Mandatory = $true)][string]$ExpectedUrl,
		[Parameter(Mandatory = $true)][string]$SourceCommit,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	if ([string]$Run.repository.full_name -ne "C76GN/gf-framework") {
		$Issues.Add("upstream Actions run repository does not match the official GF repository")
	}
	if ([string]$Run.html_url -ne $ExpectedUrl) {
		$Issues.Add("upstream Actions run URL does not match the official Actions response")
	}
	if ([string]$Run.head_sha -ne $SourceCommit) {
		$Issues.Add("upstream Actions run head_sha does not match source_commit")
	}
	if ([string]$Run.status -ne "completed" -or [string]$Run.conclusion -ne "success") {
		$Issues.Add("upstream Actions run must be completed successfully")
	}
	if ([string]$Run.event -ne "push") {
		$Issues.Add("upstream Actions run must be a push validation")
	}
}

function Test-RequiredSuccessfulJobs {
	param(
		[Parameter(Mandatory = $true)][object]$JobsResponse,
		[Parameter(Mandatory = $true)][string[]]$RequiredJobNames,
		[Parameter(Mandatory = $true)][string]$EvidenceLabel,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	foreach ($requiredJobName in $RequiredJobNames) {
		$matchingJobs = @($JobsResponse.jobs | Where-Object {
			[string]$_.name -eq $requiredJobName
		})
		if ($matchingJobs.Count -ne 1) {
			$Issues.Add(
				"$EvidenceLabel must contain exactly one successful required job: $requiredJobName"
			)
			continue
		}
		if (
			[string]$matchingJobs[0].status -ne "completed" -or
			[string]$matchingJobs[0].conclusion -ne "success"
		) {
			$Issues.Add("$EvidenceLabel required job must complete successfully: $requiredJobName")
		}
	}
}

function Test-DevelopmentActionsProvenance {
	param(
		[Parameter(Mandatory = $true)][object]$Run,
		[Parameter(Mandatory = $true)][object]$JobsResponse,
		[Parameter(Mandatory = $true)][string]$ExpectedUrl,
		[Parameter(Mandatory = $true)][string]$SourceCommit,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	Test-CommonActionsRun `
		-Run $Run `
		-ExpectedUrl $ExpectedUrl `
		-SourceCommit $SourceCommit `
		-Issues $Issues
	if ([string]$Run.path -ne ".github/workflows/ci.yml") {
		$Issues.Add("upstream CI run must use the canonical GF full-validation workflow")
	}
	if (-not ([string]$Run.name).StartsWith("GF CI|mode=full|", [StringComparison]::Ordinal)) {
		$Issues.Add("upstream CI run must declare GF mode=full")
	}
	if ([string]$Run.head_branch -ne "main") {
		$Issues.Add("development CI run must target official main")
	}
	Test-RequiredSuccessfulJobs `
		-JobsResponse $JobsResponse `
		-RequiredJobNames @(
			"GF full validation ($SourceCommit)",
			"GF merge gate"
		) `
		-EvidenceLabel "upstream CI run" `
		-Issues $Issues
}

function Resolve-OfficialAnnotatedTagCommit {
	param(
		[Parameter(Mandatory = $true)][string]$Version,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	$encodedVersion = [Uri]::EscapeDataString($Version)
	$tagRef = Invoke-GitHubApi -Uri (
		"https://api.github.com/repos/C76GN/gf-framework/git/ref/tags/$encodedVersion"
	)
	if ([string]$tagRef.ref -ne "refs/tags/$Version") {
		$Issues.Add("stable release tag response does not match source_ref")
		return ""
	}
	if ([string]$tagRef.object.type -ne "tag") {
		$Issues.Add("stable release tag must be an annotated tag")
		return ""
	}

	$currentObjectSha = ([string]$tagRef.object.sha).ToLowerInvariant()
	$currentObjectType = "tag"
	$visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
	$depth = 0
	while ($currentObjectType -eq "tag") {
		$depth += 1
		if ($depth -gt 8 -or -not $visited.Add($currentObjectSha)) {
			$Issues.Add("stable release annotated tag chain is cyclic or exceeds the peel limit")
			return ""
		}
		$tagObject = Invoke-GitHubApi -Uri (
			"https://api.github.com/repos/C76GN/gf-framework/git/tags/$currentObjectSha"
		)
		if ($depth -eq 1 -and [string]$tagObject.tag -ne $Version) {
			$Issues.Add("stable release annotated tag object does not match the framework version")
			return ""
		}
		if ([string]$tagObject.sha -ne $currentObjectSha) {
			$Issues.Add("stable release annotated tag object identity changed during peel")
			return ""
		}
		$currentObjectType = [string]$tagObject.object.type
		$currentObjectSha = ([string]$tagObject.object.sha).ToLowerInvariant()
	}
	if ($currentObjectType -ne "commit" -or $currentObjectSha -notmatch '^[0-9a-f]{40}$') {
		$Issues.Add("stable release annotated tag must peel to one Git commit")
		return ""
	}
	return $currentObjectSha
}

function Get-ReleaseAssetSha256 {
	param(
		[Parameter(Mandatory = $true)][object]$Asset,
		[Parameter(Mandatory = $true)][string]$AssetLabel,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	$digestMatch = [regex]::Match([string]$Asset.digest, '^sha256:([0-9a-f]{64})$')
	if (-not $digestMatch.Success) {
		$Issues.Add("$AssetLabel release asset must expose one lowercase SHA-256 digest")
		return ""
	}
	return $digestMatch.Groups[1].Value
}

function Test-StableReleaseProvenance {
	param(
		[Parameter(Mandatory = $true)][object]$Run,
		[Parameter(Mandatory = $true)][object]$JobsResponse,
		[Parameter(Mandatory = $true)][string]$ExpectedUrl,
		[Parameter(Mandatory = $true)][string]$Version,
		[Parameter(Mandatory = $true)][string]$SourceCommit,
		[Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
	)

	$initialIssueCount = $Issues.Count
	Test-CommonActionsRun `
		-Run $Run `
		-ExpectedUrl $ExpectedUrl `
		-SourceCommit $SourceCommit `
		-Issues $Issues
	if ([string]$Run.path -ne ".github/workflows/release.yml") {
		$Issues.Add("stable release run must use the canonical GF release workflow")
	}
	if ([string]$Run.name -ne "Release") {
		$Issues.Add("stable release run must identify the canonical Release workflow")
	}
	if ([string]$Run.head_branch -ne $Version) {
		$Issues.Add("stable release run must target the exact framework version tag")
	}
	Test-RequiredSuccessfulJobs `
		-JobsResponse $JobsResponse `
		-RequiredJobNames @(
			"Build GF release artifacts once",
			"GF release framework checks (static)",
			"GF release framework checks (gut)",
			"GF release framework checks (integration)",
			"GF release framework checks (lsp)",
			"Create GitHub Release"
		) `
		-EvidenceLabel "stable release run" `
		-Issues $Issues
	if ($Issues.Count -ne $initialIssueCount) {
		return
	}

	$tagCommit = Resolve-OfficialAnnotatedTagCommit -Version $Version -Issues $Issues
	if ($tagCommit -ne $SourceCommit) {
		$Issues.Add("stable release annotated tag does not peel to source_commit")
		return
	}

	$encodedVersion = [Uri]::EscapeDataString($Version)
	$release = Invoke-GitHubApi -Uri (
		"https://api.github.com/repos/C76GN/gf-framework/releases/tags/$encodedVersion"
	)
	if ([string]$release.tag_name -ne $Version) {
		$Issues.Add("stable GitHub Release tag_name does not match the framework version")
	}
	if ([bool]$release.draft -or [bool]$release.prerelease) {
		$Issues.Add("stable GitHub Release must be published, non-draft, and non-prerelease")
	}
	if ([string]$release.html_url -ne "https://github.com/C76GN/gf-framework/releases/tag/$Version") {
		$Issues.Add("stable GitHub Release URL does not match the official version URL")
	}

	$manifestName = "gf-release-artifacts-$Version.json"
	$archiveName = "gf-framework-$Version.zip"
	$releaseAssets = @($release.assets)
	$manifestAssets = @($releaseAssets | Where-Object { [string]$_.name -eq $manifestName })
	$archiveAssets = @($releaseAssets | Where-Object { [string]$_.name -eq $archiveName })
	if ($manifestAssets.Count -ne 1) {
		$Issues.Add("stable GitHub Release must contain exactly one artifact manifest: $manifestName")
	}
	if ($archiveAssets.Count -ne 1) {
		$Issues.Add("stable GitHub Release must contain exactly one framework archive: $archiveName")
	}
	if ($manifestAssets.Count -ne 1 -or $archiveAssets.Count -ne 1) {
		return
	}

	$manifestAsset = $manifestAssets[0]
	$archiveAsset = $archiveAssets[0]
	foreach ($assetEntry in @(
		@{ asset = $manifestAsset; label = "artifact manifest"; maximum = $script:GfReleaseManifestMaximumBytes },
		@{ asset = $archiveAsset; label = "framework archive"; maximum = $script:GfReleaseArchiveMaximumBytes }
	)) {
		$asset = $assetEntry.asset
		$label = [string]$assetEntry.label
		$size = [int64]$asset.size
		if ([string]$asset.state -ne "uploaded") {
			$Issues.Add("$label release asset must be in uploaded state")
		}
		if ($size -le 0 -or $size -gt [int64]$assetEntry.maximum) {
			$Issues.Add("$label release asset size is outside the verifier budget")
		}
		if ([string]$asset.url -notmatch '^https://api\.github\.com/repos/C76GN/gf-framework/releases/assets/[0-9]+$') {
			$Issues.Add("$label release asset URL must use the official GitHub asset API")
		}
	}
	$manifestExpectedSha256 = Get-ReleaseAssetSha256 `
		-Asset $manifestAsset `
		-AssetLabel "artifact manifest" `
		-Issues $Issues
	$archiveExpectedSha256 = Get-ReleaseAssetSha256 `
		-Asset $archiveAsset `
		-AssetLabel "framework archive" `
		-Issues $Issues
	if ($Issues.Count -ne $initialIssueCount) {
		return
	}

	[byte[]]$manifestBytes = Invoke-GitHubAssetBytes -Uri ([string]$manifestAsset.url)
	if ($manifestBytes.LongLength -ne [int64]$manifestAsset.size) {
		$Issues.Add("artifact manifest downloaded byte count does not match release metadata")
		return
	}
	if ((Get-Sha256Hex -Bytes $manifestBytes) -ne $manifestExpectedSha256) {
		$Issues.Add("artifact manifest downloaded SHA-256 does not match release metadata")
		return
	}
	try {
		$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
		$manifest = $strictUtf8.GetString($manifestBytes) | ConvertFrom-Json
	} catch {
		$Issues.Add("artifact manifest must be strict UTF-8 JSON: $($_.Exception.Message)")
		return
	}
	$manifestArtifacts = @($manifest.artifacts)
	if ([int]$manifest.schema_version -ne 3) {
		$Issues.Add("artifact manifest schema_version must be 3")
	}
	if ([string]$manifest.version -ne $Version) {
		$Issues.Add("artifact manifest version does not match the framework version")
	}
	if ([string]$manifest.source_revision -ne $SourceCommit) {
		$Issues.Add("artifact manifest source_revision does not match source_commit")
	}
	if ([int]$manifest.framework_archive_build_count -ne 1) {
		$Issues.Add("artifact manifest must record exactly one framework archive build")
	}
	if ([int]$manifest.artifact_count -ne $manifestArtifacts.Count) {
		$Issues.Add("artifact manifest artifact_count does not match its artifact array")
	}
	$frameworkArtifacts = @($manifestArtifacts | Where-Object { [string]$_.role -eq "framework" })
	if ($frameworkArtifacts.Count -ne 1) {
		$Issues.Add("artifact manifest must contain exactly one framework artifact")
		return
	}
	$frameworkArtifact = $frameworkArtifacts[0]
	if (
		[string]$frameworkArtifact.name -ne $archiveName -or
		[string]$frameworkArtifact.path -ne $archiveName
	) {
		$Issues.Add("artifact manifest framework artifact name and path must match the release archive")
	}
	if ([int64]$frameworkArtifact.size_bytes -ne [int64]$archiveAsset.size) {
		$Issues.Add("artifact manifest framework size does not match the release archive")
	}
	if ([string]$frameworkArtifact.sha256 -ne $archiveExpectedSha256) {
		$Issues.Add("artifact manifest framework SHA-256 does not match the release archive digest")
	}
	if ($Issues.Count -ne $initialIssueCount) {
		return
	}

	[byte[]]$archiveBytes = Invoke-GitHubAssetBytes -Uri ([string]$archiveAsset.url)
	if ($archiveBytes.LongLength -ne [int64]$archiveAsset.size) {
		$Issues.Add("framework archive downloaded byte count does not match release metadata")
		return
	}
	if ((Get-Sha256Hex -Bytes $archiveBytes) -ne $archiveExpectedSha256) {
		$Issues.Add("framework archive downloaded SHA-256 does not match release metadata and manifest")
	}
}

if ($FunctionsOnly) {
	return
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$vendorRoot = Join-Path $resolvedProjectRoot "addons/gf"
$resolvedLockPath = Join-Path $resolvedProjectRoot $LockPath

function Get-GitBlobSha1 {
	param([Parameter(Mandatory = $true)][string]$Path)

	$fileBytes = [IO.File]::ReadAllBytes($Path)
	$headerBytes = [Text.Encoding]::UTF8.GetBytes("blob $($fileBytes.LongLength)`0")
	$sha1 = [Security.Cryptography.SHA1]::Create()
	$null = $sha1.TransformBlock(
		$headerBytes,
		0,
		$headerBytes.Length,
		$headerBytes,
		0
	)
	$null = $sha1.TransformFinalBlock($fileBytes, 0, $fileBytes.Length)
	return ([BitConverter]::ToString($sha1.Hash)).Replace("-", "").ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $vendorRoot -PathType Container)) {
	throw "GF vendor root does not exist: $vendorRoot"
}
if (-not (Test-Path -LiteralPath $resolvedLockPath -PathType Leaf)) {
	throw "GF vendor lock does not exist: $resolvedLockPath"
}

$lock = Get-Content -LiteralPath $resolvedLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$records = [System.Collections.Generic.List[string]]::new()
$vendorFilesByRelativePath = [System.Collections.Generic.Dictionary[string,string]]::new(
	[StringComparer]::Ordinal
)

foreach ($file in Get-ChildItem -LiteralPath $vendorRoot -Recurse -File) {
	$relativePath = $file.FullName.Substring($vendorRoot.Length + 1).Replace("\", "/")
	if ($relativePath -match '(^|/)__pycache__/' -or $relativePath -match '\.py[cod]$') {
		continue
	}
	$fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
	$records.Add("$relativePath`t$fileHash")
	$vendorFilesByRelativePath.Add($relativePath, $file.FullName)
}

$sortedRecords = $records.ToArray()
[Array]::Sort($sortedRecords, [StringComparer]::Ordinal)
$payload = [Text.Encoding]::UTF8.GetBytes(($sortedRecords -join "`n") + "`n")
$sha256 = [Security.Cryptography.SHA256]::Create()
$treeHash = ([BitConverter]::ToString($sha256.ComputeHash($payload))).Replace("-", "").ToLowerInvariant()

$pluginConfigPath = Join-Path $vendorRoot "plugin.cfg"
$pluginConfig = Get-Content -LiteralPath $pluginConfigPath -Raw -Encoding UTF8
$versionMatch = [regex]::Match($pluginConfig, '(?m)^version="([^"]+)"$')
$pluginVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "" }

$issues = [System.Collections.Generic.List[string]]::new()
$sourceRepository = [string]$lock.source_repository
$sourceRef = [string]$lock.source_ref
$channel = [string]$lock.channel
$sourceCommit = [string]$lock.source_commit
$sourceGitTree = [string]$lock.source_git_tree
$upstreamCiRun = [string]$lock.upstream_ci_run

if ([int]$lock.schema_version -ne 2) {
	$issues.Add("unsupported lock schema_version: $($lock.schema_version)")
}
if ([int]$lock.vendor_file_count -ne $sortedRecords.Length) {
	$issues.Add("file count mismatch: lock=$($lock.vendor_file_count), actual=$($sortedRecords.Length)")
}
if ([string]$lock.vendor_tree_sha256 -ne $treeHash) {
	$issues.Add("tree hash mismatch: lock=$($lock.vendor_tree_sha256), actual=$treeHash")
}
if ([string]$lock.framework_version -ne $pluginVersion) {
	$issues.Add("framework version mismatch: lock=$($lock.framework_version), plugin=$pluginVersion")
}
if ($sourceRepository -ne "https://github.com/C76GN/gf-framework.git") {
	$issues.Add("source_repository must identify the official GF repository")
}
if ($channel -notin @("stable", "development")) {
	$issues.Add("channel must be stable or development")
}
if ($channel -eq "stable" -and $sourceRef -ne "refs/tags/$pluginVersion") {
	$issues.Add("stable channel source_ref must be the exact plugin version tag ref")
}
if ($channel -eq "stable" -and $pluginVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
	$issues.Add("stable channel framework_version must be a formal SemVer release")
}
if ($channel -eq "development" -and $sourceRef -ne "refs/heads/main") {
	$issues.Add("development channel source_ref must be refs/heads/main")
}
if ($sourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
	$issues.Add("source_commit must be a 40-character Git commit")
}
if ($sourceGitTree -notmatch '^[0-9a-fA-F]{40}$') {
	$issues.Add("source_git_tree must be a 40-character Git tree")
}
if ($upstreamCiRun -notmatch '^https://github\.com/C76GN/gf-framework/actions/runs/[0-9]+$') {
	$issues.Add("upstream_ci_run must identify an official GF Actions run")
}

if ($VerifyRemote -and $issues.Count -eq 0) {
	try {
		$runId = [regex]::Match($upstreamCiRun, '/runs/([0-9]+)$').Groups[1].Value
		$run = Invoke-GitHubApi -Uri "https://api.github.com/repos/C76GN/gf-framework/actions/runs/$runId"
		$jobsResponse = Invoke-GitHubApi -Uri "https://api.github.com/repos/C76GN/gf-framework/actions/runs/$runId/jobs`?per_page=100"
		if ($channel -eq "development") {
			Test-DevelopmentActionsProvenance `
				-Run $run `
				-JobsResponse $jobsResponse `
				-ExpectedUrl $upstreamCiRun `
				-SourceCommit $sourceCommit `
				-Issues $issues
		} else {
			Test-StableReleaseProvenance `
				-Run $run `
				-JobsResponse $jobsResponse `
				-ExpectedUrl $upstreamCiRun `
				-Version $pluginVersion `
				-SourceCommit $sourceCommit `
				-Issues $issues
		}

		$treeResponse = Invoke-GitHubApi -Uri "https://api.github.com/repos/C76GN/gf-framework/git/trees/$sourceCommit`?recursive=1"
		$vendorTreeEntry = @($treeResponse.tree | Where-Object { [string]$_.path -eq "addons/gf" })
		if ($vendorTreeEntry.Count -ne 1) {
			$issues.Add("official source_commit does not contain exactly one addons/gf tree")
		} elseif (
			[string]$vendorTreeEntry[0].type -ne "tree" -or
			[string]$vendorTreeEntry[0].sha -ne $sourceGitTree
		) {
			$issues.Add("source_git_tree does not match the official GitHub commit tree")
		}
		if ([bool]$treeResponse.truncated) {
			$issues.Add("official GitHub recursive tree response is truncated")
		} else {
			$remoteVendorBlobs = [System.Collections.Generic.Dictionary[string,string]]::new(
				[StringComparer]::Ordinal
			)
			foreach ($entry in $treeResponse.tree) {
				$entryPath = [string]$entry.path
				if (-not $entryPath.StartsWith("addons/gf/", [StringComparison]::Ordinal)) {
					continue
				}
				$relativePath = $entryPath.Substring("addons/gf/".Length)
				if ($relativePath -match '(^|/)__pycache__/' -or $relativePath -match '\.py[cod]$') {
					continue
				}
				if ([string]$entry.type -eq "blob") {
					$remoteVendorBlobs.Add($relativePath, ([string]$entry.sha).ToLowerInvariant())
				}
			}

			if ($remoteVendorBlobs.Count -ne $vendorFilesByRelativePath.Count) {
				$issues.Add(
					"official addons/gf blob count does not match local vendor: official=$($remoteVendorBlobs.Count), local=$($vendorFilesByRelativePath.Count)"
				)
			}
			$blobMismatchCount = 0
			$blobMismatchExamples = [System.Collections.Generic.List[string]]::new()
			foreach ($pair in $vendorFilesByRelativePath.GetEnumerator()) {
				$officialBlob = ""
				if (-not $remoteVendorBlobs.TryGetValue($pair.Key, [ref]$officialBlob)) {
					$blobMismatchCount += 1
					if ($blobMismatchExamples.Count -lt 10) {
						$blobMismatchExamples.Add("missing:$($pair.Key)")
					}
					continue
				}
				$localBlob = Get-GitBlobSha1 -Path $pair.Value
				if ($localBlob -ne $officialBlob) {
					$blobMismatchCount += 1
					if ($blobMismatchExamples.Count -lt 10) {
						$blobMismatchExamples.Add("content:$($pair.Key)")
					}
				}
			}
			if ($blobMismatchCount -gt 0) {
				$issues.Add(
					"local vendor does not exactly match official Git blobs: mismatches=$blobMismatchCount examples=$($blobMismatchExamples -join ',')"
				)
			}
		}
	} catch {
		$issues.Add("official GitHub provenance verification failed: $($_.Exception.Message)")
	}
}

if (-not [string]::IsNullOrWhiteSpace($UpstreamRepositoryPath)) {
	if (-not (Test-Path -LiteralPath $UpstreamRepositoryPath -PathType Container)) {
		$issues.Add("upstream repository path does not exist: $UpstreamRepositoryPath")
	} else {
		$resolvedUpstream = (Resolve-Path -LiteralPath $UpstreamRepositoryPath).Path
		$upstreamOrigin = (& git -C $resolvedUpstream remote get-url origin 2>$null)
		if ($LASTEXITCODE -ne 0 -or [string]$upstreamOrigin -ne $sourceRepository) {
			$issues.Add("supplied upstream repository origin does not match source_repository")
		}
		$upstreamStatus = @(& git -C $resolvedUpstream status --porcelain --untracked-files=all -- addons/gf 2>$null)
		if ($LASTEXITCODE -ne 0 -or $upstreamStatus.Count -gt 0) {
			$issues.Add("supplied upstream addons/gf checkout must be clean")
		}
		$resolvedCommit = (& git -C $resolvedUpstream rev-parse "${sourceCommit}^{commit}" 2>$null)
		if ($LASTEXITCODE -ne 0 -or [string]$resolvedCommit -ne $sourceCommit) {
			$issues.Add("source_commit is not present in the supplied upstream repository")
		} else {
			$upstreamHead = (& git -C $resolvedUpstream rev-parse HEAD 2>$null)
			if ($LASTEXITCODE -ne 0 -or [string]$upstreamHead -ne $sourceCommit) {
				$issues.Add("supplied upstream checkout HEAD must equal source_commit")
			}
			$resolvedTree = (& git -C $resolvedUpstream rev-parse "${sourceCommit}:addons/gf" 2>$null)
			if ($LASTEXITCODE -ne 0 -or [string]$resolvedTree -ne $sourceGitTree) {
				$issues.Add("source_git_tree does not match the supplied upstream repository")
			}
			if ($channel -eq "stable") {
				$resolvedRef = (& git -C $resolvedUpstream rev-parse "${sourceRef}^{commit}" 2>$null)
				if ($LASTEXITCODE -ne 0 -or [string]$resolvedRef -ne $sourceCommit) {
					$issues.Add("stable source_ref does not resolve to source_commit")
				}
			} elseif ($channel -eq "development") {
				& git -C $resolvedUpstream merge-base --is-ancestor $sourceCommit refs/remotes/origin/main 2>$null
				if ($LASTEXITCODE -ne 0) {
					$issues.Add("development source_commit is not an ancestor of official main")
				}
			}

			$upstreamVendorRoot = Join-Path $resolvedUpstream "addons/gf"
			$upstreamRecords = [System.Collections.Generic.List[string]]::new()
			foreach ($file in Get-ChildItem -LiteralPath $upstreamVendorRoot -Recurse -File) {
				$relativePath = $file.FullName.Substring($upstreamVendorRoot.Length + 1).Replace("\", "/")
				if ($relativePath -match '(^|/)__pycache__/' -or $relativePath -match '\.py[cod]$') {
					continue
				}
				$fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
				$upstreamRecords.Add("$relativePath`t$fileHash")
			}
			$upstreamSortedRecords = $upstreamRecords.ToArray()
			[Array]::Sort($upstreamSortedRecords, [StringComparer]::Ordinal)
			$upstreamPayload = [Text.Encoding]::UTF8.GetBytes(($upstreamSortedRecords -join "`n") + "`n")
			$upstreamSha256 = [Security.Cryptography.SHA256]::Create()
			$upstreamTreeHash = ([BitConverter]::ToString($upstreamSha256.ComputeHash($upstreamPayload))).Replace("-", "").ToLowerInvariant()
			if ($upstreamTreeHash -ne $treeHash) {
				$issues.Add("local vendor content does not match the supplied upstream checkout")
			}
		}
	}
}

if ($issues.Count -gt 0) {
	Write-Error ("GF vendor verification failed:`n- " + ($issues -join "`n- "))
	exit 1
}

Write-Output "GF vendor verified: version=$pluginVersion channel=$channel files=$($sortedRecords.Length) sha256=$treeHash commit=$sourceCommit tree=$sourceGitTree"
