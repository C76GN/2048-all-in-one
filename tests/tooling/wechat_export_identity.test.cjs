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
	"tools/wechat_minigame/subpackage_startup_coordinator.js",
	"tools/wechat_minigame/wxmemfs_rename_patch.ps1",
	"tools/wechat_minigame_release_resource_closure.gd",
	"tools/wechat_minigame/release_resource_policy.json",
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

// Exact method bodies from the reviewed minigame4.7.0.7.tpz loader.
const originalSubpackageLoaderSource = `class GodotLoader{loadGameEngine() {
            if (!wxApi || typeof wxApi.loadSubpackage !== "function") {
                return;
            }

            const task = wxApi.loadSubpackage({
                name: "engine",
                success: () => {
                    this.progress = 1;
                    this.updateProgress(this.progress, this.config.textConfig.initText);
                },
            });

            if (task && typeof task.onProgressUpdate === "function") {
                task.onProgressUpdate(({ progress }) => {
                    this.updateProgress(progress, this.config.textConfig.downloadingText[0]);
                });
            }
        }cleanup(){}}`;
let patchedSubpackageLoaderSource = "";
const originalResizeCanvasesSource = `class GodotLoader{resizeCanvases() {
            const viewport = this.getViewportSize();
            const width = viewport.width;
            const height = viewport.height;

            this.dpr = this.getDevicePixelRatio();
            this.onScreenCanvas.width = width * this.dpr;
            this.onScreenCanvas.height = height * this.dpr;
            this.onScreenCanvas.style.width = width + "px";
            this.onScreenCanvas.style.height = height + "px";
            this.offScreenCanvas.width = width * this.dpr;
            this.offScreenCanvas.height = height * this.dpr;

            if (this.gl) {
                this.gl.viewport(0, 0, this.onScreenCanvas.width, this.onScreenCanvas.height);
            }

            this.render();
        }}`;
let patchedResizeCanvasesSource = "";
const originalRuntimePixelRatioSource = 'const GodotDisplayScreen={hidpi:true,getPixelRatio:function(){if(!GodotDisplayScreen.hidpi){return 1}if(typeof wx!=="undefined"&&wx.getWindowInfo){const info=wx.getWindowInfo();if(info&&info.pixelRatio){return info.pixelRatio}}return window.devicePixelRatio||1}};';
let patchedRuntimePixelRatioSource = "";

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

test(
	"subpackage lifecycle patch is byte-identical across Windows PowerShell and PowerShell 7",
	{skip: process.platform !== "win32"},
	() => {
		const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-loader-shell-parity-"));
		try {
			const sourceBase64 = Buffer.from(originalSubpackageLoaderSource, "utf8").toString("base64");
			const body = [
				`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
				"$patched = ConvertTo-WeChatSubpackageLifecyclePatchedSource -Source $source",
				"[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patched))",
			].join("\n");
			const windowsPowerShell = runPowerShell(fixtureRoot, body).stdout.trim();
			const powerShell7 = runPwsh(fixtureRoot, body).stdout.trim();
			assert.equal(powerShell7, windowsPowerShell);
			assert.doesNotMatch(
				Buffer.from(windowsPowerShell, "base64").toString("utf8"),
				/\r/,
			);
		} finally {
			fs.rmSync(fixtureRoot, {recursive: true, force: true});
		}
	},
);

function getPatchedResizeCanvasesSource() {
	if (patchedResizeCanvasesSource !== "") {
		return patchedResizeCanvasesSource;
	}
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-render-resolution-"));
	try {
		const sourceBase64 = Buffer.from(originalResizeCanvasesSource, "utf8").toString("base64");
		const result = runPowerShell(fixtureRoot, [
			`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
			"$patched = ConvertTo-WeChatRenderResolutionPatchedSource -Source $source",
			"[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patched))",
		].join("\n"));
		patchedResizeCanvasesSource = Buffer.from(result.stdout.trim(), "base64").toString("utf8");
		return patchedResizeCanvasesSource;
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
}

function getPatchedRuntimePixelRatioSource() {
	if (patchedRuntimePixelRatioSource !== "") {
		return patchedRuntimePixelRatioSource;
	}
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-runtime-resolution-"));
	try {
		const sourceBase64 = Buffer.from(originalRuntimePixelRatioSource, "utf8").toString("base64");
		const result = runPowerShell(fixtureRoot, [
			`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
			"$patched = ConvertTo-WeChatRuntimeRenderResolutionPatchedSource -Source $source",
			"[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patched))",
		].join("\n"));
		patchedRuntimePixelRatioSource = Buffer.from(result.stdout.trim(), "base64").toString("utf8");
		return patchedRuntimePixelRatioSource;
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
}

function makeCanvasFixture() {
	let width = 0;
	let height = 0;
	const canvas = {style: {}};
	Object.defineProperties(canvas, {
		width: {
			get: () => width,
			set: (value) => {
				width = Math.trunc(Number(value));
			},
		},
		height: {
			get: () => height,
			set: (value) => {
				height = Math.trunc(Number(value));
			},
		},
	});
	return canvas;
}

function createRenderResolutionHarness() {
	const viewports = [];
	const context = {
		window: {
			innerWidth: 1,
			innerHeight: 1,
			devicePixelRatio: 1,
		},
	};
	vm.runInNewContext(
		`${getPatchedResizeCanvasesSource()};globalThis.LoaderForTest=GodotLoader;`,
		context,
	);
	const loader = Object.create(context.LoaderForTest.prototype);
	loader.dpr = 1;
	loader.getViewportSize = () => ({
		width: context.window.innerWidth,
		height: context.window.innerHeight,
	});
	loader.getDevicePixelRatio = () => context.window.devicePixelRatio;
	loader.onScreenCanvas = makeCanvasFixture();
	loader.offScreenCanvas = makeCanvasFixture();
	loader.gl = {viewport: (...args) => viewports.push(args)};
	let renderCount = 0;
	loader.render = () => {
		renderCount += 1;
	};
	return {
		context,
		loader,
		viewports,
		getRenderCount: () => renderCount,
		resize(width, height, devicePixelRatio) {
			context.window.innerWidth = width;
			context.window.innerHeight = height;
			context.window.devicePixelRatio = devicePixelRatio;
			loader.resizeCanvases();
		},
	};
}

function createRuntimeResolutionHarness() {
	let windowInfo = {windowWidth: 1, windowHeight: 1, pixelRatio: 1};
	const context = {
		window: {
			innerWidth: 1,
			innerHeight: 1,
			devicePixelRatio: 1,
		},
		wx: {
			getWindowInfo: () => windowInfo,
		},
	};
	vm.runInNewContext(
		`${getPatchedRuntimePixelRatioSource()};globalThis.ScreenForTest=GodotDisplayScreen;`,
		context,
	);
	return {
		context,
		screen: context.ScreenForTest,
		setWindowInfo(info) {
			windowInfo = info;
		},
	};
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

function createSubpackageDelegationHarness(withCoordinator = true) {
	const starts = [];
	const progressUpdates = [];
	const timers = [];
	const context = {
		GameGlobal: {
			__godotStartupPackageBytes: {engine: 9, game_data: 11},
		},
		setTimeout(callback, delay) {
			timers.push({callback, delay});
			return timers.length;
		},
	};
	if (withCoordinator) {
		context.GameGlobal.WeChatSubpackageStartupCoordinator = {
			start(options) {
				starts.push(options);
				return Promise.resolve({status: "started"});
			},
		};
	}
	vm.runInNewContext(
		`${getPatchedSubpackageLoaderSource()};globalThis.LoaderForTest=GodotLoader;`,
		context,
	);
	const loader = Object.create(context.LoaderForTest.prototype);
	loader.progress = 0;
	loader.config = {textConfig: {
		loadFailedText: "引擎分包加载失败",
	}};
	loader.updateProgress = (...args) => progressUpdates.push(args);
	return {context, loader, progressUpdates, starts, timers};
}

test("render resolution patch caps backing stores without changing CSS size", () => {
	const harness = createRenderResolutionHarness();

	harness.resize(844, 390, 3);
	assert.ok(Math.abs(harness.loader.dpr - 1280 / 844) < Number.EPSILON * 8);
	assert.equal(harness.loader.onScreenCanvas.width, 1280);
	assert.equal(harness.loader.onScreenCanvas.height, 591);
	assert.equal(harness.loader.offScreenCanvas.width, 1280);
	assert.equal(harness.loader.offScreenCanvas.height, 591);
	assert.deepEqual(harness.loader.onScreenCanvas.style, {
		width: "844px",
		height: "390px",
	});
	assert.deepEqual(harness.viewports.at(-1), [0, 0, 1280, 591]);

	harness.resize(390, 844, 3);
	assert.ok(Math.abs(harness.loader.dpr - 1280 / 844) < Number.EPSILON * 8);
	assert.equal(harness.loader.onScreenCanvas.width, 591);
	assert.equal(harness.loader.onScreenCanvas.height, 1280);
	assert.deepEqual(harness.loader.onScreenCanvas.style, {
		width: "390px",
		height: "844px",
	});

	harness.resize(640, 360, 1.25);
	assert.equal(harness.loader.dpr, 1.25);
	assert.equal(harness.loader.onScreenCanvas.width, 800);
	assert.equal(harness.loader.onScreenCanvas.height, 450);
	assert.equal(harness.getRenderCount(), 3);
});

test("runtime and loader use the same dynamic backing-store DPR cap", () => {
	const loaderHarness = createRenderResolutionHarness();
	const runtimeHarness = createRuntimeResolutionHarness();

	loaderHarness.resize(844, 390, 3);
	runtimeHarness.setWindowInfo({windowWidth: 844, windowHeight: 390, pixelRatio: 3});
	assert.equal(runtimeHarness.screen.getPixelRatio(), loaderHarness.loader.dpr);

	loaderHarness.resize(390, 844, 3);
	runtimeHarness.setWindowInfo({windowWidth: 390, windowHeight: 844, pixelRatio: 3});
	assert.equal(runtimeHarness.screen.getPixelRatio(), loaderHarness.loader.dpr);

	runtimeHarness.setWindowInfo({windowWidth: 640, windowHeight: 360, pixelRatio: 1.25});
	assert.equal(runtimeHarness.screen.getPixelRatio(), 1.25);
	runtimeHarness.screen.hidpi = false;
	assert.equal(runtimeHarness.screen.getPixelRatio(), 1);

	runtimeHarness.screen.hidpi = true;
	runtimeHarness.context.wx = undefined;
	runtimeHarness.context.window.innerWidth = 320;
	runtimeHarness.context.window.innerHeight = 180;
	runtimeHarness.context.window.devicePixelRatio = 3;
	assert.equal(runtimeHarness.screen.getPixelRatio(), 3);
});

test("loader preserves native viewport getters and the absent-GL resize path", () => {
	const harness = createRenderResolutionHarness();
	let nativeViewport = {width: 844, height: 390};
	let nativeRatio = 3;
	harness.loader.getViewportSize = () => nativeViewport;
	harness.loader.getDevicePixelRatio = () => nativeRatio;
	// The template's wx-derived values take precedence over a stale DOM window.
	harness.resize(1, 1, 1);
	assert.equal(harness.loader.onScreenCanvas.width, 1280);
	assert.equal(harness.loader.onScreenCanvas.style.width, "844px");
	nativeViewport = {width: 390, height: 844};
	nativeRatio = 1.25;
	harness.loader.gl = null;
	harness.resize(1, 1, 1);
	assert.equal(harness.loader.dpr, 1.25);
	assert.equal(harness.loader.onScreenCanvas.width, 487);
	assert.equal(harness.loader.onScreenCanvas.height, 1055);
	assert.equal(harness.loader.onScreenCanvas.style.height, "844px");
	assert.equal(harness.getRenderCount(), 2);
});

test("render resolution patch keeps DPR at least one and fails closed on template drift", () => {
	const harness = createRenderResolutionHarness();
	harness.resize(1920, 1080, 3);
	assert.equal(harness.loader.dpr, 1);
	assert.equal(harness.loader.onScreenCanvas.width, 1920);
	assert.equal(harness.loader.onScreenCanvas.height, 1080);

	harness.resize(320, 180, 0.75);
	assert.equal(harness.loader.dpr, 1);
	assert.equal(harness.loader.onScreenCanvas.width, 320);
	assert.equal(harness.loader.onScreenCanvas.height, 180);

	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-render-resolution-drift-"));
	try {
		const missingTarget = runPowerShell(
			fixtureRoot,
			"ConvertTo-WeChatRenderResolutionPatchedSource -Source 'class GodotLoader{}'",
			false,
		);
		assert.match(
			missingTarget.stderr || missingTarget.stdout,
			/no longer contains the expected resizeCanvases implementation/,
		);
		const sourceBase64 = Buffer.from(
			originalResizeCanvasesSource + originalResizeCanvasesSource,
			"utf8",
		).toString("base64");
		const duplicateTarget = runPowerShell(
			fixtureRoot,
			[
				`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
				"ConvertTo-WeChatRenderResolutionPatchedSource -Source $source",
			].join("\n"),
			false,
		);
		assert.match(
			duplicateTarget.stderr || duplicateTarget.stdout,
			/contains multiple resizeCanvases patch targets/,
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("runtime resolution patch fails closed on missing or duplicate targets", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-runtime-resolution-drift-"));
	try {
		const missingTarget = runPowerShell(
			fixtureRoot,
			"ConvertTo-WeChatRuntimeRenderResolutionPatchedSource -Source 'const fixture=1'",
			false,
		);
		assert.match(
			missingTarget.stderr || missingTarget.stdout,
			/no longer contains the expected getPixelRatio implementation/,
		);
		const sourceBase64 = Buffer.from(
			originalRuntimePixelRatioSource + originalRuntimePixelRatioSource,
			"utf8",
		).toString("base64");
		const duplicateTarget = runPowerShell(
			fixtureRoot,
			[
				`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
				"ConvertTo-WeChatRuntimeRenderResolutionPatchedSource -Source $source",
			].join("\n"),
			false,
		);
		assert.match(
			duplicateTarget.stderr || duplicateTarget.stdout,
			/contains multiple getPixelRatio patch targets/,
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("subpackage loader delegates one startup session to the coordinator", () => {
	const harness = createSubpackageDelegationHarness();
	harness.loader.loadGameEngine();
	assert.equal(harness.starts.length, 1);
	assert.equal(harness.starts[0].loader, harness.loader);
	assert.deepEqual(
		JSON.parse(JSON.stringify(harness.starts[0].packageBytes)),
		{engine: 9, game_data: 11},
	);
	assert.equal(harness.starts[0].pckPath, "/game_data/2048-all-in-one.bin");
	assert.equal(harness.starts[0].packageTimeoutMilliseconds, 300000);
	assert.equal(harness.starts[0].probeTimeoutMilliseconds, 10000);
	assert.equal(harness.starts[0].starterTimeoutMilliseconds, 10000);
	assert.equal(harness.starts[0].engineStartTimeoutMilliseconds, 300000);
	assert.equal(harness.timers.length, 0);
});

test("subpackage loader fails visibly when the coordinator import is absent", () => {
	const harness = createSubpackageDelegationHarness(false);
	harness.loader.loadGameEngine();
	assert.deepEqual(harness.progressUpdates, [[0, "引擎分包加载失败"]]);
	assert.equal(harness.timers.length, 1);
	assert.equal(harness.timers[0].delay, 0);
	assert.throws(
		() => harness.timers[0].callback(),
		/startup coordinator is unavailable/,
	);
});

test("root game entry imports the coordinator and freezes measured package weights", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-root-entry-"));
	try {
		const original = [
			"import './weapp-adapter'",
			"import './godot-loader'",
			"const config = {};",
			"GameGlobal.godotLoader = new GodotLoader(canvas, config);",
		].join("\n");
		const sourceBase64 = Buffer.from(original, "utf8").toString("base64");
		const result = runPowerShell(fixtureRoot, [
			`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${sourceBase64}'))`,
			"$patched = ConvertTo-WeChatStartupCoordinatorGameEntryPatchedSource -Source $source -EnginePackageBytes 9 -GameDataPackageBytes 11",
			"[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patched))",
		].join("\n"));
		const patched = Buffer.from(result.stdout.trim(), "base64").toString("utf8");
		assert.match(patched, /import '\.\/wechat-startup-coordinator'\nimport '\.\/godot-loader'/);
		assert.match(
			patched,
			/GameGlobal\.__godotStartupPackageBytes = Object\.freeze\(\{engine:9,game_data:11\}\);/,
		);
		assert.equal((patched.match(/new GodotLoader/g) || []).length, 1);

		for (const driftedSource of [
			"import './godot-loader'",
			`${original}\n${original}`,
		]) {
			const driftBase64 = Buffer.from(driftedSource, "utf8").toString("base64");
			const drift = runPowerShell(
				fixtureRoot,
				[
					`$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${driftBase64}'))`,
					"ConvertTo-WeChatStartupCoordinatorGameEntryPatchedSource -Source $source -EnginePackageBytes 9 -GameDataPackageBytes 11",
				].join("\n"),
				false,
			);
			assert.match(drift.stderr || drift.stdout, /(no longer contains|contains multiple)/);
		}
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
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

test("batch Godot preflight drains diagnostics and honors the final exit code", () => {
	const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wechat-godot-batch-exit-"));
	try {
		for (const exitCode of [0, 17]) {
			const wrapperPath = path.join(fixtureRoot, `godot-wrapper-${exitCode}.cmd`);
			fs.writeFileSync(wrapperPath, [
				"@echo off",
				"echo 4.7.2.stable.official.wrapper",
				"for /L %%i in (1,1,128) do echo wrapper-diagnostic-%%i",
				`exit /b ${exitCode}`,
				"",
			].join("\r\n"), "utf8");
			const result = runPowerShell(
				fixtureRoot,
				`(Get-GodotIdentity -Executable ${quotePowerShellLiteral(wrapperPath)}).version`,
				exitCode === 0,
			);
			if (exitCode === 0) {
				assert.equal(result.stdout.trim(), "4.7.2.stable.official.wrapper");
			} else {
				assert.match(`${result.stderr}\n${result.stdout}`, /Godot version preflight failed/);
			}
		}
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
			"$toolIdentity = [ordered]@{ export_tool = [ordered]@{ sha256 = ('0' * 64) }; artifact_verifier = [ordered]@{ sha256 = ('1' * 64) }; artifact_check = [ordered]@{ sha256 = ('2' * 64) }; bounded_json_reader = [ordered]@{ sha256 = ('3' * 64) }; path_tools = [ordered]@{ sha256 = ('4' * 64) }; chunk_loader = [ordered]@{ sha256 = ('5' * 64) }; startup_coordinator = [ordered]@{ sha256 = ('6' * 64) }; wxmemfs_patch = [ordered]@{ sha256 = ('7' * 64) }; release_resource_closure = [ordered]@{ sha256 = ('8' * 64) }; release_resource_policy = [ordered]@{ sha256 = ('9' * 64) } }",
			"Get-CandidateBuildId -GodotIdentity $godotIdentity -GfIdentity $gfIdentity -InputSnapshotSha256 ('e' * 64) -InputSnapshotFileCount 1234 -ArtifactManifestSha256 ('f' * 64) -ToolIdentity $toolIdentity",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		assert.equal(
			result.stdout.trim(),
			"633efda4f5f4118281674c5282f9ac4002ee9de62d8726dcf6f6d886f204d099",
		);
	} finally {
		fs.rmSync(fixtureRoot, {recursive: true, force: true});
	}
});

test("release resource closure evidence is exact and bound to frozen tools", () => {
	withSourceFixture(({fixtureRoot}) => {
		const evidence = {
			schema_version: 1,
			ok: true,
			policy_id: "wechat-minigame-release-resource-closure-v1",
			policy_path: "tools/wechat_minigame/release_resource_policy.json",
			policy_sha256: "",
			closure_sha256: "7".repeat(64),
			full_dependency_scan_count: 601,
			dependency_partial: false,
			dependency_truncated: false,
			counts: {
				roots: 106,
				structure_dynamic: 44,
				content_resources: 39,
				raw_dependency_closure: 813,
				closure: 812,
				raw_include_patterns: 18,
				raw_include_files: 19,
				issues: 0,
			},
			issues: [],
		};
		const body = [
			"$tools = Get-ToolIdentity -Root $ProjectRoot",
			`$evidence = ${quotePowerShellLiteral(JSON.stringify(evidence))} | ConvertFrom-Json`,
			"$evidence.policy_sha256 = $tools.release_resource_policy.sha256",
			"$normalized = Assert-ReleaseResourceClosureEvidence -Evidence $evidence -ToolIdentity $tools",
			"if ($normalized.tool_sha256 -cne $tools.release_resource_closure.sha256) { throw 'closure tool was not bound' }",
			"$evidence.policy_sha256 = ('0' * 64)",
			"$rejected = $false",
			"try { Assert-ReleaseResourceClosureEvidence -Evidence $evidence -ToolIdentity $tools } catch { $rejected = $true; Write-Output $_.Exception.Message }",
			"if (-not $rejected) { throw 'closure policy drift was not rejected' }",
		].join("\n");
		const result = runPowerShell(fixtureRoot, body);
		assert.match(result.stdout, /policy changed during its audit/);
	});
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
			"wechat-startup-coordinator.js",
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
		{
			name: "resource closure policy",
			mutation: () => "[IO.File]::WriteAllText((Join-Path $ProjectRoot 'tools\\wechat_minigame\\release_resource_policy.json'), '{}', [Text.UTF8Encoding]::new($false))",
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
