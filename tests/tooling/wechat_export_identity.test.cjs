"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const projectRoot = path.resolve(__dirname, "../..");
const exporterPath = path.join(projectRoot, "tools/export_wechat_minigame_smoke.ps1");
const toolPaths = [
	"tools/export_wechat_minigame_smoke.ps1",
	"tools/wechat_minigame_artifact_verifier.gd",
	"tools/wechat_minigame_artifact_check.gd",
	"addons/gf/kernel/core/gf_bounded_json_object_reader.gd",
	"addons/gf/kernel/core/gf_path_tools.gd",
	"tools/wechat_minigame/chunked_file_loader.js",
	"tools/wechat_minigame/wxmemfs_rename_patch.ps1",
];

function quotePowerShellLiteral(value) {
	return `'${String(value).replaceAll("'", "''")}'`;
}

function runPowerShell(fixtureRoot, body, expectSuccess = true) {
	const command = [
		"$ErrorActionPreference = 'Stop'",
		`. ${quotePowerShellLiteral(exporterPath)} -ProjectRoot ${quotePowerShellLiteral(fixtureRoot)} -FunctionsOnly`,
		body,
	].join("\n");
	const result = childProcess.spawnSync(
		"powershell.exe",
		["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
		{encoding: "utf8", maxBuffer: 16 * 1024 * 1024},
	);
	if (expectSuccess) {
		assert.equal(result.status, 0, result.stderr || result.stdout);
	} else {
		assert.notEqual(result.status, 0, "PowerShell command unexpectedly passed");
	}
	return result;
}

function runPwsh(fixtureRoot, body, expectSuccess = true) {
	const command = [
		"$ErrorActionPreference = 'Stop'",
		`. ${quotePowerShellLiteral(exporterPath)} -ProjectRoot ${quotePowerShellLiteral(fixtureRoot)} -FunctionsOnly`,
		body,
	].join("\n");
	const result = childProcess.spawnSync(
		"pwsh.exe",
		["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
		{encoding: "utf8", maxBuffer: 16 * 1024 * 1024},
	);
	if (expectSuccess) {
		assert.equal(result.status, 0, result.stderr || result.stdout || result.error);
	} else {
		assert.notEqual(result.status, 0, "PowerShell command unexpectedly passed");
	}
	return result;
}

function runExporter(fixtureRoot, extraArguments, expectSuccess = true) {
	const result = childProcess.spawnSync(
		"powershell.exe",
		[
			"-NoProfile",
			"-NonInteractive",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			exporterPath,
			"-ProjectRoot",
			fixtureRoot,
			...extraArguments,
		],
		{encoding: "utf8", maxBuffer: 16 * 1024 * 1024},
	);
	if (expectSuccess) {
		assert.equal(result.status, 0, result.stderr || result.stdout);
	} else {
		assert.notEqual(result.status, 0, "PowerShell exporter unexpectedly passed");
	}
	return result;
}

function writeFile(root, relativePath, contents) {
	const absolutePath = path.join(root, ...relativePath.split("/"));
	fs.mkdirSync(path.dirname(absolutePath), {recursive: true});
	fs.writeFileSync(absolutePath, contents, "utf8");
}

function sha256(contents) {
	return crypto.createHash("sha256").update(contents).digest("hex");
}

const originalSubpackageLoaderSource = 'class GodotLoader{loadGameEngine(){wx.loadSubpackage({complete:t=>{},name:"engine",success:()=>{this.progress=1,this.updateProgress(this.progress,this.config.textConfig.initText)}}).onProgressUpdate(({progress:t})=>{this.progress=t/100,this.updateProgress(this.progress,this.config.textConfig.downloadingText[0])})}cleanup(){}}';
let patchedSubpackageLoaderSource = "";

function getPatchedSubpackageLoaderSource() {
	if (patchedSubpackageLoaderSource !== "") {
		return patchedSubpackageLoaderSource;
	}
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-subpackage-loader-"));
	try {
		const sourceBase64 = Buffer.from(originalSubpackageLoaderSource, "utf8").toString("base64");
		const result = runPowerShell(fixtureRoot, [
			`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
			"$patched = ConvertTo-WeChatSubpackageLifecyclePatchedSource -Source $source",
			"[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patched))",
		].join("\n"));
		patchedSubpackageLoaderSource = Buffer.from(result.stdout.trim(), "base64").toString("utf8");
		return patchedSubpackageLoaderSource;
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
}

function createSubpackageLoaderHarness(options = {}) {
	const events = [];
	const progressUpdates = [];
	const callbacksByName = new Map();
	const progressCallbacksByName = new Map();
	const dataProbePaths = [];
	const timers = new Map();
	let nextTimerId = 1;
	let pendingProbe = null;
	const context = {
		GameGlobal: {},
		console: {
			log: (...args) => events.push(["log", ...args]),
			error: (...args) => events.push(["error", ...args]),
		},
		wx: {
			getFileSystemManager() {
				return {readFile(probeOptions) {
					dataProbePaths.push(probeOptions.filePath);
					if (options.probeMode === "throw") {
						throw new Error("probe sync failure");
					}
					if (options.probeMode === "pending") {
						pendingProbe = probeOptions;
						return;
					}
					if (options.probeMode === "fail") {
						probeOptions.fail({errMsg: "readFile:fail fixture"});
						return;
					}
					probeOptions.success({data: new Uint8Array([0x47]).buffer});
				}};
			},
			loadSubpackage(packageOptions) {
				if (options.syncThrowPackage === packageOptions.name) {
					throw new Error(`${packageOptions.name} sync failure`);
				}
				callbacksByName.set(packageOptions.name, packageOptions);
				if (options.invalidTaskPackage === packageOptions.name) {
					return {};
				}
				return {onProgressUpdate(callback) {
					if (options.progressThrowPackage === packageOptions.name) {
						throw new Error(`${packageOptions.name} progress failure`);
					}
					progressCallbacksByName.set(packageOptions.name, callback);
				}};
			},
		},
		setTimeout(callback, delay = 0) {
			const id = nextTimerId++;
			timers.set(id, {callback, delay});
			return id;
		},
		clearTimeout(id) {
			timers.delete(id);
		},
	};
	vm.runInNewContext(
		`${getPatchedSubpackageLoaderSource()};globalThis.LoaderForTest=GodotLoader;`,
		context,
	);
	const loader = Object.create(context.LoaderForTest.prototype);
	loader.progress = 0;
	loader.config = {textConfig: {
		downloadingText: ["下载中"],
		initText: "初始化",
		loadFailedText: "引擎分包加载失败",
	}};
	loader.updateProgress = (...args) => progressUpdates.push(args);
	return {
		callbacksByName,
		context,
		dataProbePaths,
		events,
		getPendingProbe: () => pendingProbe,
		loader,
		progressCallbacksByName,
		progressUpdates,
		runTimer(delay) {
			const timerEntry = [...timers.entries()].find(([, timer]) => timer.delay === delay);
			assert.ok(timerEntry, `missing ${delay} ms timer`);
			const [id, timer] = timerEntry;
			timers.delete(id);
			return timer.callback();
		},
		timerCount: (delay) => [...timers.values()].filter((timer) => timer.delay === delay).length,
	};
}

function assertSingleVisibleFailure(harness, pattern) {
	assert.equal(
		harness.progressUpdates.filter(([progress]) => progress === 0).length,
		1,
	);
	assert.equal(harness.timerCount(0), 1);
	assert.throws(() => harness.runTimer(0), pattern);
}

test("subpackage loader loads game data before engine and settles each stage once", () => {
	const harness = createSubpackageLoaderHarness();
	harness.loader.loadGameEngine();
	assert.deepEqual(harness.events[0], ["log", "[wechat-subpackage] start", "game_data"]);
	assert.equal(harness.callbacksByName.has("engine"), false);
	harness.progressCallbacksByName.get("game_data")({progress: 50});
	assert.deepEqual(harness.progressUpdates.at(-1), [0.25, "下载中"]);
	harness.context.GameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.callbacksByName.get("game_data").success({errMsg: "loadSubpackage:ok"});
	assert.deepEqual(harness.dataProbePaths, ["/game_data/2048-all-in-one.bin"]);
	assert.equal(harness.callbacksByName.has("engine"), true);
	harness.progressCallbacksByName.get("engine")({progress: 50});
	assert.deepEqual(harness.progressUpdates.at(-1), [0.75, "下载中"]);
	harness.context.GameGlobal.__godotEngineSubpackageEntryStarted = true;
	harness.callbacksByName.get("engine").success({errMsg: "loadSubpackage:ok"});
	assert.deepEqual(harness.progressUpdates.at(-1), [1, "初始化"]);
	harness.callbacksByName.get("engine").complete({errMsg: "loadSubpackage:ok"});
	harness.callbacksByName.get("engine").fail({errMsg: "late failure"});
	harness.callbacksByName.get("engine").success({errMsg: "late success"});
	assert.equal(harness.timerCount(0), 0);
	assert.equal(harness.progressUpdates.filter(([progress]) => progress === 0).length, 0);
});

test("subpackage loader reports a missing entry once and ignores late callbacks", () => {
	const harness = createSubpackageLoaderHarness();
	harness.loader.loadGameEngine();
	harness.callbacksByName.get("game_data").success({errMsg: "loadSubpackage:ok"});
	harness.context.GameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.callbacksByName.get("game_data").success({errMsg: "late success"});
	harness.callbacksByName.get("game_data").fail({errMsg: "late failure"});
	assert.equal(harness.callbacksByName.has("engine"), false);
	assert.ok(harness.events.some((event) => event[1] === "[wechat-subpackage] entry_missing"));
	assertSingleVisibleFailure(harness, /game_data\/game\.js did not execute/);
});

test("subpackage loader converts synchronous API and progress-task failures", () => {
	for (const options of [
		{syncThrowPackage: "game_data"},
		{invalidTaskPackage: "game_data"},
		{progressThrowPackage: "game_data"},
	]) {
		const harness = createSubpackageLoaderHarness(options);
		harness.loader.loadGameEngine();
		if (harness.callbacksByName.has("game_data")) {
			harness.context.GameGlobal.__godotGameDataSubpackageEntryStarted = true;
			harness.callbacksByName.get("game_data").success({errMsg: "late success"});
		}
		assert.equal(harness.callbacksByName.has("engine"), false);
		assertSingleVisibleFailure(harness, /(sync failure|progress task is unavailable|progress failure)/);
	}
});

test("subpackage deadline fails visibly and late success cannot continue", () => {
	const harness = createSubpackageLoaderHarness();
	harness.loader.loadGameEngine();
	harness.runTimer(300000);
	harness.context.GameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.callbacksByName.get("game_data").success({errMsg: "late success"});
	assert.equal(harness.callbacksByName.has("engine"), false);
	assert.ok(harness.events.some((event) => event[1] === "[wechat-subpackage] timeout"));
	assertSingleVisibleFailure(harness, /game_data subpackage load timed out/);
});

test("PCK probe deadline fails visibly and late read cannot start the engine", () => {
	const harness = createSubpackageLoaderHarness({probeMode: "pending"});
	harness.loader.loadGameEngine();
	harness.context.GameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.callbacksByName.get("game_data").success({errMsg: "loadSubpackage:ok"});
	harness.runTimer(10000);
	harness.getPendingProbe().success({data: new Uint8Array([0x47]).buffer});
	assert.equal(harness.callbacksByName.has("engine"), false);
	assertSingleVisibleFailure(harness, /game_data PCK probe timed out/);
});

function makeSourceFixture() {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-export-identity-"));
	for (const exactPath of [
		"default_bus_layout.tres",
		"export_presets.cfg",
		"icon.svg",
		"icon.svg.import",
		"project.godot",
	]) {
		writeFile(fixtureRoot, exactPath, `fixture:${exactPath}\n`);
	}
	writeFile(fixtureRoot, "app/main.gd", "alpha");
	writeFile(fixtureRoot, "features/feature.gd", "feature");
	writeFile(fixtureRoot, "shared/shared.gd", "shared");
	const vendorContents = "vendor-v1";
	writeFile(fixtureRoot, "addons/gf/core.gd", vendorContents);
	for (const toolPath of toolPaths) {
		writeFile(fixtureRoot, toolPath, `tool:${toolPath}\n`);
	}
	const vendorEntries = [
		["core.gd", vendorContents],
		...toolPaths
			.filter((toolPath) => toolPath.startsWith("addons/gf/"))
			.map((toolPath) => [
				toolPath.slice("addons/gf/".length),
				`tool:${toolPath}\n`,
			]),
	].sort(([left], [right]) => left.localeCompare(right, "en", {sensitivity: "variant"}));
	const vendorRecord = vendorEntries
		.map(([relativePath, contents]) => `${relativePath}\t${sha256(contents)}\n`)
		.join("");
	const lock = {
		schema_version: 2,
		framework_version: "11.0.0-dev.0",
		source_commit: "a".repeat(40),
		source_git_tree: "b".repeat(40),
		vendor_tree_sha256: sha256(vendorRecord),
		vendor_file_count: vendorEntries.length,
	};
	writeFile(fixtureRoot, ".gf/vendor.lock.json", `${JSON.stringify(lock)}\n`);
	return {fixtureRoot, lock};
}

function withSourceFixture(callback) {
	const fixture = makeSourceFixture();
	try {
		callback(fixture);
	} finally {
		fs.rmSync(fixture.fixtureRoot, {recursive: true, force: true});
	}
}

test("Godot preflight rejects 4.7.1 and accepts the exact 4.7.2 stable line", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-godot-version-"));
	try {
		const oldGodot = path.join(fixtureRoot, "godot-4.7.1.cmd");
		const requiredGodot = path.join(fixtureRoot, "godot-4.7.2.cmd");
		fs.writeFileSync(oldGodot, "@echo off\r\necho 4.7.1.stable.official.fake\r\n", "utf8");
		fs.writeFileSync(
			requiredGodot,
			"@echo off\r\necho 4.7.2.stable.official.fake\r\n",
			"utf8",
		);
		const rejected = runPowerShell(
			fixtureRoot,
			`Get-GodotIdentity -Executable ${quotePowerShellLiteral(oldGodot)}`,
			false,
		);
		assert.match(`${rejected.stderr}\n${rejected.stdout}`, /4\.7\.2\.stable is required/);
		const accepted = runPowerShell(
			fixtureRoot,
			`(Get-GodotIdentity -Executable ${quotePowerShellLiteral(requiredGodot)}).version`,
		);
		assert.equal(accepted.stdout.trim(), "4.7.2.stable.official.fake");
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test(
	"Godot preflight captures a Windows GUI-subsystem executable",
	{skip: process.platform !== "win32"},
	() => {
		const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-godot-gui-version-"));
		try {
			const guiGodot = path.join(fixtureRoot, "godot-gui-fixture.exe");
			const compileCommand = [
				"$ErrorActionPreference = 'Stop'",
				"$source = @'",
				"using System;",
				"using System.Threading;",
				"public static class Program",
				"{",
				"    [STAThread]",
				"    public static void Main(string[] args)",
				"    {",
				"        if (args.Length != 1 || args[0] != \"--version\") Environment.Exit(64);",
				"        Thread.Sleep(100);",
				"        Console.WriteLine(\"4.7.2.stable.steam.fixture\");",
				"    }",
				"}",
				"'@",
				`Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly ${quotePowerShellLiteral(guiGodot)} -OutputType WindowsApplication`,
			].join("\n");
			const compiled = childProcess.spawnSync(
				"powershell.exe",
				[
					"-NoProfile",
					"-NonInteractive",
					"-ExecutionPolicy",
					"Bypass",
					"-Command",
					compileCommand,
				],
				{encoding: "utf8", maxBuffer: 16 * 1024 * 1024},
			);
			assert.equal(compiled.status, 0, compiled.stderr || compiled.stdout || compiled.error);
			const accepted = runPwsh(
				fixtureRoot,
				`(Get-GodotIdentity -Executable ${quotePowerShellLiteral(guiGodot)}).version`,
			);
			assert.equal(accepted.stdout.trim(), "4.7.2.stable.steam.fixture");
		} finally {
			fs.rmSync(fixtureRoot, {recursive: true, force: true});
		}
	},
);

test("candidate build identity uses the documented canonical UTF-8 framing", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-build-id-"));
	try {
		const body = [
			"$godotIdentity = [ordered]@{ version = '4.7.2.stable.official.abcdef123' }",
			"$gfIdentity = [ordered]@{ framework_version = '11.0.0-dev.0'; source_commit = ('a' * 40); source_git_tree = ('b' * 40); vendor_tree_sha256 = ('c' * 64); vendor_file_count = 1967; lock_sha256 = ('d' * 64) }",
			"$toolIdentity = [ordered]@{ export_tool = [ordered]@{ sha256 = ('0' * 64) }; artifact_verifier = [ordered]@{ sha256 = ('1' * 64) }; artifact_check = [ordered]@{ sha256 = ('2' * 64) }; bounded_json_reader = [ordered]@{ sha256 = ('3' * 64) }; path_tools = [ordered]@{ sha256 = ('4' * 64) }; chunk_loader = [ordered]@{ sha256 = ('5' * 64) }; wxmemfs_patch = [ordered]@{ sha256 = ('6' * 64) } }",
			"Get-CandidateBuildId -GodotIdentity $godotIdentity -GfIdentity $gfIdentity -InputSnapshotSha256 ('e' * 64) -InputSnapshotFileCount 1234 -ArtifactManifestSha256 ('f' * 64) -ToolIdentity $toolIdentity",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		assert.equal(
			result.stdout.trim(),
			"274bffc55db1555d7607d5dd297d99613139b80b9e76a5882ea432caea2521e7",
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("package evidence uses host-invariant ordinal file order", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-package-order-"));
	try {
		const artifactRoot = path.join(fixtureRoot, "wxgame");
		const expectedPackageFiles = [
			"engine/game.js",
			"engine/godot-sdk.js",
			"engine/godot.js",
			"engine/godot.wasm.br",
			"engine/wechat-chunked-file-loader.js",
			"game.js",
			"game.json",
			"game_data/2048-all-in-one.bin",
			"game_data/game.js",
			"glx-config.js",
			"godot-loader.js",
			"images/background.png",
			"images/logo.png",
			"project.config.json",
			"weapp-adapter.js",
		];
		for (const relativePath of [
			...expectedPackageFiles,
			"project.private.config.json",
		]) {
			writeFile(artifactRoot, relativePath, relativePath);
		}
		const result = runPowerShell(
			fixtureRoot,
			[
				`$evidence = Get-PackageEvidence -StageRoot ${quotePowerShellLiteral(artifactRoot)}`,
				"ConvertTo-Json -Compress -Depth 4 -InputObject $evidence",
			].join("\n"),
		);
		const evidence = JSON.parse(result.stdout.trim());
		assert.deepEqual(evidence.files, expectedPackageFiles);
		assert.equal(evidence.file_count, expectedPackageFiles.length);
		assert.equal(
			evidence.total_package_bytes,
			expectedPackageFiles.reduce((total, relativePath) => (
				total + Buffer.byteLength(relativePath)
			), 0),
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("artifact manifest ignores only the volatile private sidecar", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-manifest-sidecar-"));
	try {
		const artifactRoot = path.join(fixtureRoot, "wxgame");
		writeFile(artifactRoot, "game.js", "immutable");
		const body = [
			`$artifactRoot = ${quotePowerShellLiteral(artifactRoot)}`,
			"$baseline = Get-ArtifactManifestEvidence -StageRoot $artifactRoot",
			"[IO.File]::WriteAllText((Join-Path $artifactRoot 'project.private.config.json'), '{\"setting\":{\"urlCheck\":false}}', [Text.UTF8Encoding]::new($false))",
			"$added = Get-ArtifactManifestEvidence -StageRoot $artifactRoot",
			"[IO.File]::WriteAllText((Join-Path $artifactRoot 'project.private.config.json'), '{\"setting\":{\"urlCheck\":true}}', [Text.UTF8Encoding]::new($false))",
			"$changed = Get-ArtifactManifestEvidence -StageRoot $artifactRoot",
			"[IO.File]::WriteAllText((Join-Path $artifactRoot 'unexpected.json'), '{}', [Text.UTF8Encoding]::new($false))",
			"$unexpected = Get-ArtifactManifestEvidence -StageRoot $artifactRoot",
			"[ordered]@{ baseline = $baseline; added = $added; changed = $changed; unexpected = $unexpected } | ConvertTo-Json -Compress -Depth 8",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		const manifests = JSON.parse(result.stdout.trim());
		assert.equal(manifests.added.manifest_sha256, manifests.baseline.manifest_sha256);
		assert.equal(manifests.changed.manifest_sha256, manifests.baseline.manifest_sha256);
		assert.deepEqual(
			manifests.changed.files.map((entry) => entry.path),
			["game.js"],
		);
		assert.notEqual(
			manifests.unexpected.manifest_sha256,
			manifests.baseline.manifest_sha256,
		);
		assert.deepEqual(
			manifests.unexpected.files.map((entry) => entry.path),
			["game.js", "unexpected.json"],
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("private config snapshot remains immutable after the source changes", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-private-snapshot-"));
	try {
		const outputRoot = path.join(fixtureRoot, "build/wechat_minigame_smoke/wxgame");
		const sourcePath = path.join(outputRoot, "project.private.config.json");
		const stageAPath = path.join(fixtureRoot, "build/stage-a/project.private.config.json");
		const stageBPath = path.join(fixtureRoot, "build/stage-b/project.private.config.json");
		fs.mkdirSync(path.dirname(stageAPath), {recursive: true});
		fs.mkdirSync(path.dirname(stageBPath), {recursive: true});
		writeFile(outputRoot, "project.config.json", `${JSON.stringify({
			appid: "wx0000000000000001",
			compileType: "minigame",
		})}\n`);
		writeFile(outputRoot, "project.private.config.json", `${JSON.stringify({
			appid: "wx0000000000000002",
			compileType: "minigame",
			setting: {urlCheck: false},
			condition: {minigame: {list: [{name: "before", pathName: "pages/a"}]}},
		})}\n`);
		const laterJson = `${JSON.stringify({
			appid: "wx0000000000000003",
			compileType: "gamePlugin",
			setting: {urlCheck: true},
			later_marker: true,
		})}\n`;
		const body = [
			`$sourcePath = ${quotePowerShellLiteral(sourcePath)}`,
			"$snapshot = Get-SanitizedPrivateConfigSnapshot -Path $sourcePath",
			`[IO.File]::WriteAllText($sourcePath, ${quotePowerShellLiteral(laterJson)}, [Text.UTF8Encoding]::new($false))`,
			"if ((Get-PreservedAppId -PrivateConfigSnapshot $snapshot) -cne 'wx0000000000000002') { throw 'snapshot identity drifted' }",
			`$null = Write-SanitizedPrivateConfigSnapshot -Snapshot $snapshot -DestinationPath ${quotePowerShellLiteral(stageAPath)}`,
			"Remove-Item -LiteralPath $sourcePath -Force",
			`$null = Write-SanitizedPrivateConfigSnapshot -Snapshot $snapshot -DestinationPath ${quotePowerShellLiteral(stageBPath)}`,
			`$stageA = [IO.File]::ReadAllText(${quotePowerShellLiteral(stageAPath)}, [Text.UTF8Encoding]::new($false))`,
			`$stageB = [IO.File]::ReadAllText(${quotePowerShellLiteral(stageBPath)}, [Text.UTF8Encoding]::new($false))`,
			"if ($stageA -cne $stageB) { throw 'snapshot materialization drifted' }",
			"$config = ConvertFrom-Json -InputObject $stageA",
			"if ($config.PSObject.Properties.Name -ccontains 'appid') { throw 'private appid was not sanitized' }",
			"if ($config.PSObject.Properties.Name -ccontains 'compileType') { throw 'private compileType was not sanitized' }",
			"if ($config.PSObject.Properties.Name -cnotcontains 'setting' -or $config.setting.PSObject.Properties.Name -cnotcontains 'urlCheck') { throw 'local preference was dropped' }",
			"if ([bool]$config.setting.urlCheck) { throw 'original local preference was not retained' }",
			"if ([string]$config.condition.minigame.list[0].name -cne 'before') { throw 'nested preference was not retained' }",
			"if ($config.PSObject.Properties.Name -ccontains 'later_marker') { throw 'source was read after snapshot' }",
			"Write-Output 'snapshot-pass'",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		assert.equal(result.stdout.trim(), "snapshot-pass");
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("missing private config remains absent when its snapshot is materialized", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-private-absent-"));
	try {
		const missingPath = path.join(fixtureRoot, "build/candidate/wxgame/project.private.config.json");
		const destinationPath = path.join(fixtureRoot, "build/stage/wxgame/project.private.config.json");
		const body = [
			`$snapshot = Get-SanitizedPrivateConfigSnapshot -Path ${quotePowerShellLiteral(missingPath)}`,
			"if ([bool]$snapshot.exists) { throw 'missing private config became present' }",
			`$null = Write-SanitizedPrivateConfigSnapshot -Snapshot $snapshot -DestinationPath ${quotePowerShellLiteral(destinationPath)}`,
			`if (Test-Path -LiteralPath ${quotePowerShellLiteral(destinationPath)}) { throw 'empty private config was generated' }`,
			"Write-Output 'absent-pass'",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		assert.equal(result.stdout.trim(), "absent-pass");
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("malformed private config cannot be frozen into an export snapshot", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-private-malformed-"));
	try {
		const sourcePath = path.join(fixtureRoot, "build/candidate/wxgame/project.private.config.json");
		writeFile(fixtureRoot, "build/candidate/wxgame/project.private.config.json", "{");
		const result = runPowerShell(
			fixtureRoot,
			`Get-SanitizedPrivateConfigSnapshot -Path ${quotePowerShellLiteral(sourcePath)}`,
			false,
		);
		assert.match(
			`${result.stderr}\n${result.stdout}`,
			/existing project\.private\.config\.json must contain a valid JSON object/,
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("dirty export input snapshot tracks included content and ignores non-export roots", () => {
	withSourceFixture(({fixtureRoot}) => {
		const readSnapshot = () => runPowerShell(
			fixtureRoot,
			"(Get-ExportInputSnapshot -Root $ProjectRoot).input_snapshot_sha256",
		).stdout.trim();
		const baseline = readSnapshot();
		writeFile(fixtureRoot, "app/main.gd", "bravo");
		const includedDrift = readSnapshot();
		assert.notEqual(includedDrift, baseline);
		writeFile(fixtureRoot, "build/generated.bin", "ignored-build");
		writeFile(fixtureRoot, ".godot/imported/cache", "ignored-import-cache");
		writeFile(fixtureRoot, ".git/objects/fake", "ignored-git");
		writeFile(fixtureRoot, "tests/fixture.gd", "ignored-test");
		writeFile(fixtureRoot, "docs/note.md", "ignored-doc");
		assert.equal(readSnapshot(), includedDrift);
	});
});

test("frozen identity rejects GF lock, vendor, export input, and tool drift", () => {
	const driftCases = [
		{
			name: "GF lock",
			mutation: ({lock}) => {
				const changedLock = {...lock, source_commit: "f".repeat(40)};
				return `[IO.File]::WriteAllText((Join-Path $ProjectRoot '.gf\\vendor.lock.json'), ${quotePowerShellLiteral(`${JSON.stringify(changedLock)}\n`)}, [Text.UTF8Encoding]::new($false))`;
			},
			pattern: /GF identity changed during WeChat export/,
		},
		{
			name: "GF vendor",
			mutation: () => "[IO.File]::WriteAllText((Join-Path $ProjectRoot 'addons\\gf\\core.gd'), 'vendor-v2', [Text.UTF8Encoding]::new($false))",
			pattern: /GF vendor tree hash mismatch/,
		},
		{
			name: "export input",
			mutation: () => "[IO.File]::WriteAllText((Join-Path $ProjectRoot 'app\\main.gd'), 'bravo', [Text.UTF8Encoding]::new($false))",
			pattern: /Export input content changed during WeChat export/,
		},
		{
			name: "tool",
			mutation: () => "[IO.File]::WriteAllText((Join-Path $ProjectRoot 'tools\\wechat_minigame_artifact_check.gd'), 'changed-tool', [Text.UTF8Encoding]::new($false))",
			pattern: /Tool identity changed during WeChat export/,
		},
	];
	for (const driftCase of driftCases) {
		withSourceFixture((fixture) => {
			const body = [
				"$expectedGf = Get-GfVendorIdentity -Root $ProjectRoot",
				"$expectedInput = Get-ExportInputSnapshot -Root $ProjectRoot",
				"$expectedTools = Get-ToolIdentity -Root $ProjectRoot",
				driftCase.mutation(fixture),
				"$rejected = $false",
				"try { Assert-FrozenExportIdentity -Root $ProjectRoot -ExpectedGfIdentity $expectedGf -ExpectedInputSnapshot $expectedInput -ExpectedToolIdentity $expectedTools } catch { $rejected = $true; Write-Output $_.Exception.Message }",
				"if (-not $rejected) { throw 'identity drift was not rejected' }",
			].join("\n");
			const result = runPowerShell(fixture.fixtureRoot, body);
			assert.match(result.stdout, driftCase.pattern, driftCase.name);
		});
	}
});

test("early staging failure removes every temporary candidate root", () => {
	withSourceFixture(({fixtureRoot}) => {
		const godotPath = path.join(fixtureRoot, "godot-4.7.2.cmd");
		fs.writeFileSync(
			godotPath,
			"@echo off\r\necho 4.7.2.stable.official.fake\r\n",
			"utf8",
		);
		const outputRelativePath = "build/candidate/wxgame";
		const finalRoot = path.join(fixtureRoot, "build/candidate");
		writeFile(
			finalRoot,
			"export-report.json",
			`${JSON.stringify({build_id: "old-build"})}\n`,
		);
		writeFile(finalRoot, "wxgame/marker.txt", "old-build");
		const result = runExporter(
			fixtureRoot,
			[
				"-GodotExecutable",
				godotPath,
				"-OutputPath",
				outputRelativePath,
				"-TestFailureInjection",
				"after_candidate_stage",
			],
			false,
		);
		assert.match(
			`${result.stderr}\n${result.stdout}`,
			/Injected WeChat candidate transaction failure after stage creation\./,
		);

		const buildRoot = path.join(fixtureRoot, "build");
		const buildEntries = fs.existsSync(buildRoot) ? fs.readdirSync(buildRoot) : [];
		assert.deepEqual(
			buildEntries.filter((entry) => (
				/^\.candidate\.(?:stage|verify|backup)-/.test(entry)
			)),
			[],
		);
		assert.equal(
			JSON.parse(fs.readFileSync(
				path.join(finalRoot, "export-report.json"),
				"utf8",
			)).build_id,
			"old-build",
		);
		assert.equal(
			fs.readFileSync(path.join(finalRoot, "wxgame/marker.txt"), "utf8"),
			"old-build",
		);
		assert.equal(fs.existsSync(path.join(buildRoot, "wechat_toolchain")), false);
	});
});

test("candidate publish fault restores the previous report and wxgame as one build", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-publish-transaction-"));
	try {
		for (const fault of ["after_candidate_backup", "after_candidate_publish"]) {
			const suffix = fault.replace("after_candidate_", "");
			const finalRoot = path.join(fixtureRoot, `build/candidate-${suffix}`);
			const stageRoot = path.join(fixtureRoot, `build/.candidate-${suffix}.stage-test`);
			const backupRoot = path.join(fixtureRoot, `build/.candidate-${suffix}.backup-test`);
			writeFile(finalRoot, "export-report.json", `${JSON.stringify({build_id: "old-build"})}\n`);
			writeFile(finalRoot, "wxgame/marker.txt", "old-build");
			writeFile(stageRoot, "export-report.json", `${JSON.stringify({build_id: "new-build"})}\n`);
			writeFile(stageRoot, "wxgame/marker.txt", "new-build");
			const body = [
				"$rejected = $false",
				`try { Publish-CandidateBundle -StageCandidateRoot ${quotePowerShellLiteral(stageRoot)} -FinalCandidateRoot ${quotePowerShellLiteral(finalRoot)} -BackupCandidateRoot ${quotePowerShellLiteral(backupRoot)} -FailureInjection '${fault}' } catch { $rejected = $true }`,
				"if (-not $rejected) { throw 'fault injection did not fail' }",
				`$report = Get-Content -Raw -Encoding UTF8 -LiteralPath ${quotePowerShellLiteral(path.join(finalRoot, "export-report.json"))} | ConvertFrom-Json`,
				"if ([string]$report.build_id -ne 'old-build') { throw 'old report build_id was not restored' }",
				`$marker = Get-Content -Raw -Encoding UTF8 -LiteralPath ${quotePowerShellLiteral(path.join(finalRoot, "wxgame/marker.txt"))}`,
				"if ($marker -ne 'old-build') { throw 'old wxgame was not restored' }",
				`if (Test-Path -LiteralPath ${quotePowerShellLiteral(backupRoot)}) { throw 'backup residue remains' }`,
				`if (Test-Path -LiteralPath ${quotePowerShellLiteral(stageRoot)}) { throw 'stage residue remains' }`,
			].join("\n");
			runPowerShell(fixtureRoot, body);
		}
		const unsafeFinalRoot = path.join(fixtureRoot, "build/candidate-unsafe");
		const unsafeStageRoot = path.join(fixtureRoot, "build/.candidate-unsafe.stage-test");
		const unsafeBackupRoot = path.join(fixtureRoot, "build/.candidate-unsafe.backup-test");
		writeFile(unsafeFinalRoot, "unrelated-user-file.txt", "must-survive");
		writeFile(unsafeStageRoot, "export-report.json", "{}\n");
		writeFile(unsafeStageRoot, "wxgame/marker.txt", "new-build");
		const unsafeBody = [
			"$rejected = $false",
			`try { Publish-CandidateBundle -StageCandidateRoot ${quotePowerShellLiteral(unsafeStageRoot)} -FinalCandidateRoot ${quotePowerShellLiteral(unsafeFinalRoot)} -BackupCandidateRoot ${quotePowerShellLiteral(unsafeBackupRoot)} } catch { $rejected = $true }`,
			"if (-not $rejected) { throw 'unsafe candidate replacement was not rejected' }",
			`if (-not (Test-Path -LiteralPath ${quotePowerShellLiteral(path.join(unsafeFinalRoot, "unrelated-user-file.txt"))})) { throw 'unrelated file was removed' }`,
			`if (Test-Path -LiteralPath ${quotePowerShellLiteral(unsafeBackupRoot)}) { throw 'unsafe candidate created a backup' }`,
		].join("\n");
		runPowerShell(fixtureRoot, unsafeBody);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});
