param(
	[string]$PythonExecutable = "python",
	[string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$PinnedFontToolsVersion = "4.59.1"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$coverageTool = Join-Path $ProjectRoot "tools\wechat_minigame\release_font_coverage.py"
$fontCoverageValidator = Join-Path `
	$ProjectRoot `
	"tools\wechat_minigame\validate_font_coverage.py"
$sourceFont = Join-Path $ProjectRoot "shared\assets\fonts\noto_sans_sc_variable.ttf"
$coverageFile = Join-Path $ProjectRoot "shared\assets\fonts\wechat_release_font_coverage.txt"
$destinationFont = Join-Path $ProjectRoot "shared\assets\fonts\wechat_release_sans_subset.ttf"
$buildRoot = Join-Path $ProjectRoot "build\wechat_release_font_subset"
$stagedFont = Join-Path $buildRoot "wechat_release_sans_subset.ttf"

$fontToolsVersion = & $PythonExecutable -c "import fontTools; print(fontTools.__version__)"
if ($LASTEXITCODE -ne 0 -or $fontToolsVersion.Trim() -ne $PinnedFontToolsVersion) {
	throw (
		"FontTools $PinnedFontToolsVersion is required; install the exact version " +
		"into the selected Python environment before regenerating the release font."
	)
}

& $PythonExecutable $coverageTool --project-root $ProjectRoot --write
if ($LASTEXITCODE -ne 0) {
	throw "Failed to generate WeChat release font coverage evidence."
}
& $PythonExecutable `
	$fontCoverageValidator `
	--font $sourceFont `
	--coverage $coverageFile
if ($LASTEXITCODE -ne 0) {
	throw "The pinned source font cannot cover every shipped release glyph."
}

$null = New-Item -ItemType Directory -Force -Path $buildRoot
if (Test-Path -LiteralPath $stagedFont -PathType Leaf) {
	Remove-Item -LiteralPath $stagedFont -Force
}

$fontToolsArguments = @(
	"-m",
	"fontTools.subset",
	$sourceFont,
	"--output-file=$stagedFont",
	"--unicodes-file=$coverageFile",
	"--layout-features=*",
	"--glyph-names",
	"--symbol-cmap",
	"--legacy-cmap",
	"--notdef-glyph",
	"--notdef-outline",
	"--recommended-glyphs",
	"--name-IDs=*",
	"--name-legacy",
	"--name-languages=*",
	"--drop-tables+=DSIG",
	"--no-recalc-timestamp",
	"--canonical-order"
)
& $PythonExecutable @fontToolsArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedFont -PathType Leaf)) {
	throw "FontTools did not create the staged WeChat release font subset."
}
if ((Get-Item -LiteralPath $stagedFont).Length -le 0) {
	throw "The staged WeChat release font subset is empty."
}
& $PythonExecutable `
	$fontCoverageValidator `
	--font $stagedFont `
	--coverage $coverageFile
if ($LASTEXITCODE -ne 0) {
	throw "The staged WeChat release font subset is incomplete."
}

Move-Item -LiteralPath $stagedFont -Destination $destinationFont -Force
& $PythonExecutable $coverageTool --project-root $ProjectRoot --write
if ($LASTEXITCODE -ne 0) {
	throw "Failed to bind the generated release font to its coverage manifest."
}
& $PythonExecutable $coverageTool --project-root $ProjectRoot --check
if ($LASTEXITCODE -ne 0) {
	throw "Generated WeChat release font evidence did not verify."
}

Write-Host "WeChat release font subset: PASS"
Write-Host "Font: $destinationFont"
Write-Host "SHA-256: $((Get-FileHash -Algorithm SHA256 $destinationFont).Hash.ToLowerInvariant())"
Write-Host "Bytes: $((Get-Item -LiteralPath $destinationFont).Length)"
