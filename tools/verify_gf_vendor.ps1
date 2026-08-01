param(
	[string]$ProjectRoot = ".",
	[string]$LockPath = ".gf/vendor.lock.json",
	[string]$UpstreamRepositoryPath = "",
	[switch]$VerifyRemote
)

$ErrorActionPreference = "Stop"

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

function Invoke-GitHubApi {
	param([Parameter(Mandatory = $true)][string]$Uri)

	$headers = @{
		"Accept" = "application/vnd.github+json"
		"User-Agent" = "2048-all-in-one-gf-vendor-verifier"
		"X-GitHub-Api-Version" = "2022-11-28"
	}
	if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
		$headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)"
	}
	return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}

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
		if ([string]$run.repository.full_name -ne "C76GN/gf-framework") {
			$issues.Add("upstream CI run repository does not match the official GF repository")
		}
		if ([string]$run.html_url -ne $upstreamCiRun) {
			$issues.Add("upstream CI run URL does not match the official Actions response")
		}
		if ([string]$run.head_sha -ne $sourceCommit) {
			$issues.Add("upstream CI run head_sha does not match source_commit")
		}
		if ([string]$run.status -ne "completed" -or [string]$run.conclusion -ne "success") {
			$issues.Add("upstream CI run must be completed successfully")
		}
		if ([string]$run.path -ne ".github/workflows/ci.yml") {
			$issues.Add("upstream CI run must use the canonical GF full-validation workflow")
		}
		if (-not ([string]$run.name).StartsWith("GF CI|mode=full|", [StringComparison]::Ordinal)) {
			$issues.Add("upstream CI run must declare GF mode=full")
		}
		if ([string]$run.event -ne "push") {
			$issues.Add("upstream CI run must be the canonical push validation")
		}
		if ($channel -eq "development" -and [string]$run.head_branch -ne "main") {
			$issues.Add("development CI run must target official main")
		}
		if ($channel -eq "stable" -and [string]$run.head_branch -ne $pluginVersion) {
			$issues.Add("stable CI run must target the exact framework version tag")
		}
		$jobsResponse = Invoke-GitHubApi -Uri "https://api.github.com/repos/C76GN/gf-framework/actions/runs/$runId/jobs`?per_page=100"
		$requiredJobNames = @(
			"GF full validation ($sourceCommit)",
			"GF merge gate"
		)
		foreach ($requiredJobName in $requiredJobNames) {
			$matchingJobs = @($jobsResponse.jobs | Where-Object { [string]$_.name -eq $requiredJobName })
			if ($matchingJobs.Count -ne 1) {
				$issues.Add("upstream CI run must contain exactly one successful required job: $requiredJobName")
				continue
			}
			if (
				[string]$matchingJobs[0].status -ne "completed" -or
				[string]$matchingJobs[0].conclusion -ne "success"
			) {
				$issues.Add("upstream CI required job must complete successfully: $requiredJobName")
			}
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
