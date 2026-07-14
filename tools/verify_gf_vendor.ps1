param(
	[string]$ProjectRoot = ".",
	[string]$LockPath = ".gf/vendor.lock.json"
)

$ErrorActionPreference = "Stop"

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$vendorRoot = Join-Path $resolvedProjectRoot "addons/gf"
$resolvedLockPath = Join-Path $resolvedProjectRoot $LockPath

if (-not (Test-Path -LiteralPath $vendorRoot -PathType Container)) {
	throw "GF vendor root does not exist: $vendorRoot"
}
if (-not (Test-Path -LiteralPath $resolvedLockPath -PathType Leaf)) {
	throw "GF vendor lock does not exist: $resolvedLockPath"
}

$lock = Get-Content -LiteralPath $resolvedLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$records = [System.Collections.Generic.List[string]]::new()

foreach ($file in Get-ChildItem -LiteralPath $vendorRoot -Recurse -File) {
	$relativePath = $file.FullName.Substring($vendorRoot.Length + 1).Replace("\", "/")
	$fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
	$records.Add("$relativePath`t$fileHash")
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
if ([int]$lock.vendor_file_count -ne $sortedRecords.Length) {
	$issues.Add("file count mismatch: lock=$($lock.vendor_file_count), actual=$($sortedRecords.Length)")
}
if ([string]$lock.vendor_tree_sha256 -ne $treeHash) {
	$issues.Add("tree hash mismatch: lock=$($lock.vendor_tree_sha256), actual=$treeHash")
}
if ([string]$lock.framework_version -ne $pluginVersion) {
	$issues.Add("framework version mismatch: lock=$($lock.framework_version), plugin=$pluginVersion")
}
if ([string]::IsNullOrWhiteSpace([string]$lock.source_commit)) {
	$issues.Add("source_commit is missing")
}

if ($issues.Count -gt 0) {
	Write-Error ("GF vendor verification failed:`n- " + ($issues -join "`n- "))
	exit 1
}

Write-Output "GF vendor verified: version=$pluginVersion files=$($sortedRecords.Length) sha256=$treeHash commit=$($lock.source_commit)"
