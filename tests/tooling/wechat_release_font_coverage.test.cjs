"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const projectRoot = path.resolve(__dirname, "../..");
const coverageTool = path.join(
	projectRoot,
	"tools/wechat_minigame/release_font_coverage.py",
);
const generator = path.join(
	projectRoot,
	"tools/generate_wechat_release_font_subset.ps1",
);
const fontCoverageValidator = path.join(
	projectRoot,
	"tools/wechat_minigame/validate_font_coverage.py",
);
const manifestPath = path.join(
	projectRoot,
	"shared/assets/fonts/wechat_release_font_coverage.json",
);

function sha256File(filePath) {
	return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

test("release font coverage is current for translations and runtime literals", () => {
	const result = childProcess.spawnSync(
		"python",
		[coverageTool, "--project-root", projectRoot, "--check"],
		{encoding: "utf8", maxBuffer: 16 * 1024 * 1024},
	);
	assert.equal(result.status, 0, result.stderr || result.stdout || result.error);
	assert.match(result.stdout, /WeChat release font coverage: PASS/);
});

test("release font manifest binds the source, OFL, coverage, and subset", () => {
	const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
	assert.equal(manifest.schema_version, 1);
	assert.equal(manifest.policy_id, "wechat-release-shipped-literals-v1");
	assert.equal(manifest.license.spdx, "OFL-1.1");
	for (const section of ["source_font", "license", "subset_font"]) {
		const absolutePath = path.join(projectRoot, ...manifest[section].path.split("/"));
		assert.equal(sha256File(absolutePath), manifest[section].sha256);
	}
	const coveragePath = path.join(
		projectRoot,
		"shared/assets/fonts/wechat_release_font_coverage.txt",
	);
	assert.equal(sha256File(coveragePath), manifest.coverage.codepoints_sha256);
	assert.ok(manifest.coverage.codepoint_count > 128);
	assert.ok(manifest.subset_font.bytes > 0);
	assert.ok(
		manifest.subset_font.bytes < 2_000_000,
		"release font subset must preserve conservative total-package headroom",
	);
});

test("font generator pins deterministic FontTools inputs and options", () => {
	const source = fs.readFileSync(generator, "utf8");
	assert.match(source, /PinnedFontToolsVersion = "4\.59\.1"/);
	assert.match(source, /--unicodes-file=/);
	assert.match(source, /--no-recalc-timestamp/);
	assert.match(source, /--canonical-order/);
	assert.match(source, /--check/);
	assert.match(source, /validate_font_coverage\.py/);
	assert.match(source, /--font \$sourceFont/);
	assert.match(source, /--font \$stagedFont/);
	assert.ok(fs.existsSync(fontCoverageValidator));
});
