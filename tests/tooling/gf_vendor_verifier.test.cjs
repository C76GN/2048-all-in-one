"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const projectRoot = path.resolve(__dirname, "../..");
const verifierPath = path.join(projectRoot, "tools/verify_gf_vendor.ps1");
const officialVersion = "11.0.0";
const officialCommit = "e88ea3470acdbc4af0e2d5a1d144af9104f5fc13";
const officialRunUrl = "https://github.com/C76GN/gf-framework/actions/runs/33381283504";

function quotePowerShellLiteral(value) {
	return `'${String(value).replaceAll("'", "''")}'`;
}

function sha256(bytes) {
	return crypto.createHash("sha256").update(bytes).digest("hex");
}

function runPowerShell(body) {
	const result = childProcess.spawnSync(
		"powershell.exe",
		["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", body],
		{encoding: "utf8", maxBuffer: 4 * 1024 * 1024},
	);
	assert.equal(result.status, 0, result.stderr || result.stdout || result.error);
	return result.stdout.trim();
}

function makeStableFixture(options = {}) {
	const archiveBytes = Buffer.from("GF Framework 11.0.0 archive fixture", "utf8");
	const downloadedArchiveBytes = options.tamperArchive
		? Buffer.from(archiveBytes.map((value, index) => (index === 0 ? value ^ 0xff : value)))
		: archiveBytes;
	const archiveDigest = sha256(archiveBytes);
	const manifest = {
		schema_version: 3,
		version: officialVersion,
		source_revision: options.manifestSourceRevision || officialCommit,
		framework_archive_build_count: 1,
		ai_developer_kit_build_count: 1,
		artifact_count: 2,
		artifacts: [
			{
				role: "framework",
				name: `gf-framework-${officialVersion}.zip`,
				path: `gf-framework-${officialVersion}.zip`,
				size_bytes: archiveBytes.length,
				sha256: archiveDigest,
			},
			{
				role: "ai_developer_kit",
				name: `gf-ai-developer-kit-${officialVersion}.zip`,
				path: `gf-ai-developer-kit-${officialVersion}.zip`,
				size_bytes: 7,
				sha256: "a".repeat(64),
			},
		],
	};
	const manifestBytes = Buffer.from(`${JSON.stringify(manifest)}\n`, "utf8");
	const downloadedManifestBytes = options.tamperManifest
		? Buffer.from(manifestBytes.map((value, index) => (index === 0 ? value ^ 0xff : value)))
		: manifestBytes;
	const manifestAssetUrl = "https://api.github.com/repos/C76GN/gf-framework/releases/assets/101";
	const archiveAssetUrl = "https://api.github.com/repos/C76GN/gf-framework/releases/assets/102";
	const tagObjectSha = "8".repeat(40);
	const jobs = [
		"Build GF release artifacts once",
		"GF release framework checks (static)",
		"GF release framework checks (gut)",
		"GF release framework checks (integration)",
		"GF release framework checks (lsp)",
		"Create GitHub Release",
	]
		.filter((name) => name !== options.omitJob)
		.map((name) => ({name, status: "completed", conclusion: "success"}));
	const release = {
		tag_name: officialVersion,
		draft: false,
		prerelease: false,
		html_url: `https://github.com/C76GN/gf-framework/releases/tag/${officialVersion}`,
		assets: [
			{
				name: `gf-release-artifacts-${officialVersion}.json`,
				state: "uploaded",
				size: manifestBytes.length,
				digest: `sha256:${sha256(manifestBytes)}`,
				url: manifestAssetUrl,
			},
			{
				name: `gf-framework-${officialVersion}.zip`,
				state: "uploaded",
				size: archiveBytes.length,
				digest: `sha256:${archiveDigest}`,
				url: archiveAssetUrl,
			},
		],
	};
	return {
		run: {
			repository: {full_name: "C76GN/gf-framework"},
			html_url: officialRunUrl,
			head_sha: officialCommit,
			status: "completed",
			conclusion: "success",
			event: "push",
			path: ".github/workflows/release.yml",
			name: "Release",
			head_branch: officialVersion,
		},
		jobs: {jobs},
		api: {
			[`https://api.github.com/repos/C76GN/gf-framework/git/ref/tags/${officialVersion}`]: {
				ref: `refs/tags/${officialVersion}`,
				object: {
					type: options.lightweightTag ? "commit" : "tag",
					sha: options.lightweightTag ? officialCommit : tagObjectSha,
				},
			},
			[`https://api.github.com/repos/C76GN/gf-framework/git/tags/${tagObjectSha}`]: {
				sha: tagObjectSha,
				tag: officialVersion,
				object: {type: "commit", sha: officialCommit},
			},
			[`https://api.github.com/repos/C76GN/gf-framework/releases/tags/${officialVersion}`]: release,
		},
		assets: {
			[manifestAssetUrl]: downloadedManifestBytes.toString("base64"),
			[archiveAssetUrl]: downloadedArchiveBytes.toString("base64"),
		},
	};
}

function runStableFixture(options = {}) {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "gf-vendor-stable-"));
	try {
		const fixturePath = path.join(fixtureRoot, "fixture.json");
		fs.writeFileSync(fixturePath, `${JSON.stringify(makeStableFixture(options))}\n`, "utf8");
		const body = [
			`. ${quotePowerShellLiteral(verifierPath)} -FunctionsOnly`,
			`$fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath ${quotePowerShellLiteral(fixturePath)} | ConvertFrom-Json`,
			"function Invoke-GitHubApi { param([string]$Uri) $property = $fixture.api.PSObject.Properties[$Uri]; if ($null -eq $property) { throw \"Unexpected API URI: $Uri\" }; return $property.Value }",
			"function Invoke-GitHubAssetBytes { param([string]$Uri) $property = $fixture.assets.PSObject.Properties[$Uri]; if ($null -eq $property) { throw \"Unexpected asset URI: $Uri\" }; return ,([Convert]::FromBase64String([string]$property.Value)) }",
			"$issues = [System.Collections.Generic.List[string]]::new()",
			`Test-StableReleaseProvenance -Run $fixture.run -JobsResponse $fixture.jobs -ExpectedUrl ${quotePowerShellLiteral(officialRunUrl)} -Version ${quotePowerShellLiteral(officialVersion)} -SourceCommit ${quotePowerShellLiteral(officialCommit)} -Issues $issues`,
			"[ordered]@{ issues = @($issues) } | ConvertTo-Json -Compress",
		].join("\n");
		return JSON.parse(runPowerShell(body));
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
}

test("stable verifier accepts the official 11.0.0 release evidence shape", () => {
	assert.deepEqual(runStableFixture().issues, []);
});

test("stable verifier rejects a lightweight release tag", () => {
	assert.match(runStableFixture({lightweightTag: true}).issues.join("\n"), /annotated tag/);
});

test("stable verifier rejects missing release jobs", () => {
	assert.match(
		runStableFixture({omitJob: "GF release framework checks (gut)"}).issues.join("\n"),
		/exactly one successful required job: GF release framework checks \(gut\)/,
	);
});

test("stable verifier binds manifest source_revision to source_commit", () => {
	assert.match(
		runStableFixture({manifestSourceRevision: "f".repeat(40)}).issues.join("\n"),
		/source_revision does not match source_commit/,
	);
});

test("stable verifier hashes the downloaded artifact manifest", () => {
	assert.match(
		runStableFixture({tamperManifest: true}).issues.join("\n"),
		/artifact manifest downloaded SHA-256 does not match/,
	);
});

test("stable verifier hashes the downloaded framework archive", () => {
	assert.match(
		runStableFixture({tamperArchive: true}).issues.join("\n"),
		/framework archive downloaded SHA-256 does not match/,
	);
});

test("development verifier keeps the canonical main full-CI contract", () => {
	const sourceCommit = "4".repeat(40);
	const fixture = {
		run: {
			repository: {full_name: "C76GN/gf-framework"},
			html_url: "https://github.com/C76GN/gf-framework/actions/runs/123",
			head_sha: sourceCommit,
			status: "completed",
			conclusion: "success",
			event: "push",
			path: ".github/workflows/ci.yml",
			name: `GF CI|mode=full|pr=0|head=${sourceCommit}|base=${sourceCommit}`,
			head_branch: "main",
		},
		jobs: {jobs: [
			{name: `GF full validation (${sourceCommit})`, status: "completed", conclusion: "success"},
			{name: "GF merge gate", status: "completed", conclusion: "success"},
		]},
	};
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "gf-vendor-development-"));
	try {
		const fixturePath = path.join(fixtureRoot, "fixture.json");
		fs.writeFileSync(fixturePath, `${JSON.stringify(fixture)}\n`, "utf8");
		const body = [
			`. ${quotePowerShellLiteral(verifierPath)} -FunctionsOnly`,
			`$fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath ${quotePowerShellLiteral(fixturePath)} | ConvertFrom-Json`,
			"$issues = [System.Collections.Generic.List[string]]::new()",
			`Test-DevelopmentActionsProvenance -Run $fixture.run -JobsResponse $fixture.jobs -ExpectedUrl $fixture.run.html_url -SourceCommit ${quotePowerShellLiteral(sourceCommit)} -Issues $issues`,
			"[ordered]@{ issues = @($issues) } | ConvertTo-Json -Compress",
		].join("\n");
		assert.deepEqual(JSON.parse(runPowerShell(body)).issues, []);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});
