"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
	ENGINE_START_TIMEOUT_MILLISECONDS,
	createStartupCoordinator,
} = require("../../tools/wechat_minigame/subpackage_startup_coordinator.js");


function deferred() {
	let resolve;
	let reject;
	const promise = new Promise((resolvePromise, rejectPromise) => {
		resolve = resolvePromise;
		reject = rejectPromise;
	});
	return {promise, resolve, reject};
}


function silentLogger() {
	return {
		info() {},
		warn() {},
		error() {},
	};
}


function createFakeTimers() {
	const timers = new Map();
	let nextTimerId = 1;
	return {
		setTimeoutFunction(callback, milliseconds) {
			const id = nextTimerId;
			nextTimerId += 1;
			timers.set(id, {callback, milliseconds});
			return id;
		},
		clearTimeoutFunction(id) {
			timers.delete(id);
		},
		runFirst(milliseconds) {
			const match = [...timers.entries()].find(([, timer]) => timer.milliseconds === milliseconds);
			assert.ok(match, `expected a ${milliseconds} ms timer`);
			timers.delete(match[0]);
			match[1].callback();
		},
		count() {
			return timers.size;
		},
	};
}


function createHarness(behavior = {}) {
	const packageRequests = new Map();
	const progressUpdates = [];
	const failures = [];
	const gameGlobal = {};
	const probeRequests = [];
	let nowMilliseconds = 100;
	const wxApi = {
		getFileSystemManager() {
			return {
				readFile(options) {
					if (behavior.probeThrows) {
						throw new Error("probe threw");
					}
					probeRequests.push(options);
				},
			};
		},
		getPerformance() {
			return {
				now() {
					nowMilliseconds += 1;
					return nowMilliseconds;
				},
			};
		},
		loadSubpackage(options) {
			if (options.name === behavior.syncThrowPackage) {
				throw new Error(`${options.name} sync throw`);
			}
			const progressCallbacks = [];
			packageRequests.set(options.name, {options, progressCallbacks});
			if (options.name === behavior.invalidTaskPackage) {
				return {};
			}
			return {
				onProgressUpdate(callback) {
					if (options.name === behavior.progressThrowPackage) {
						throw new Error(`${options.name} progress hook threw`);
					}
					progressCallbacks.push(callback);
				},
			};
		},
	};
	const timerDependencies = behavior.timers
		? {
			setTimeoutFunction: behavior.timers.setTimeoutFunction,
			clearTimeoutFunction: behavior.timers.clearTimeoutFunction,
		}
		: {};
	const coordinator = createStartupCoordinator({
		wxApi,
		gameGlobal,
		logger: silentLogger(),
		reportFailure(error) {
			failures.push(error);
		},
		...timerDependencies,
	});
	const loader = {
		progress: 0,
		updateProgress(progress, text) {
			progressUpdates.push({progress, text});
		},
	};
	return {
		coordinator,
		failures,
		gameGlobal,
		loader,
		packageRequests,
		probeRequests,
		progressUpdates,
	};
}


function markPackageEntry(harness, name) {
	const marker = name === "engine"
		? "__godotEngineSubpackageEntryStarted"
		: "__godotGameDataSubpackageEntryStarted";
	harness.gameGlobal[marker] = true;
	harness.packageRequests.get(name).options.success({errMsg: "loadSubpackage:ok"});
}


function startHarness(harness, overrides = {}) {
	return harness.coordinator.start({
		loader: harness.loader,
		packageBytes: {engine: 9, game_data: 11},
		pckPath: "/game_data/2048-all-in-one.bin",
		...overrides,
	});
}


test("requests both subpackages immediately and starts exactly once after the four-way barrier", async () => {
	const harness = createHarness();
	const engineStarted = deferred();
	let startCount = 0;
	const completion = startHarness(harness);

	assert.deepEqual([...harness.packageRequests.keys()], ["engine", "game_data"]);
	harness.coordinator.registerEngineStarter(() => {
		startCount += 1;
		return engineStarted.promise;
	});
	harness.gameGlobal.__godotEngineSubpackageEntryStarted = true;
	harness.packageRequests.get("engine").options.success();
	assert.equal(startCount, 0);

	harness.gameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.packageRequests.get("game_data").options.success();
	assert.equal(harness.probeRequests.length, 1);
	assert.equal(startCount, 0);
	harness.probeRequests[0].success({data: new ArrayBuffer(1)});
	await Promise.resolve();
	assert.equal(startCount, 1);

	harness.packageRequests.get("engine").options.success();
	harness.probeRequests[0].success({data: new ArrayBuffer(1)});
	await Promise.resolve();
	assert.equal(startCount, 1);

	engineStarted.resolve("started");
	const result = await completion;
	assert.equal(result.status, "started");
	assert.equal(harness.failures.length, 0);
});


test("supports every meaningful package, probe, and starter completion order", async () => {
	const orders = [
		["register", "engine", "game_data", "probe"],
		["game_data", "probe", "engine", "register"],
		["engine", "game_data", "probe", "register"],
		["game_data", "engine", "register", "probe"],
		["game_data", "engine", "probe", "register"],
		["engine", "register", "game_data", "probe"],
	];
	for (const order of orders) {
		const harness = createHarness();
		let startCount = 0;
		const completion = startHarness(harness);
		for (const action of order) {
			if (action === "register") {
				harness.coordinator.registerEngineStarter(() => {
					startCount += 1;
					return Promise.resolve();
				});
			} else if (action === "probe") {
				assert.equal(harness.probeRequests.length, 1, `probe prerequisite in ${order}`);
				harness.probeRequests[0].success({data: new ArrayBuffer(1)});
			} else {
				markPackageEntry(harness, action);
			}
		}
		assert.equal((await completion).status, "started", order.join(" -> "));
		assert.equal(startCount, 1, order.join(" -> "));
		assert.equal(harness.failures.length, 0, order.join(" -> "));
	}
});


test("uses byte-weighted monotonic download progress", async () => {
	const harness = createHarness();
	const completion = startHarness(harness);
	const engineProgress = harness.packageRequests.get("engine").progressCallbacks[0];
	const dataProgress = harness.packageRequests.get("game_data").progressCallbacks[0];
	engineProgress({progress: 50});
	dataProgress({progress: 25});
	engineProgress({progress: 30});
	dataProgress({progress: Number.NaN});

	const numericProgress = harness.progressUpdates.map((entry) => entry.progress);
	assert.equal(numericProgress.at(-1), 0.95 * (9 * 0.5 + 11 * 0.25) / 20);
	for (let index = 1; index < numericProgress.length; index += 1) {
		assert.ok(numericProgress[index] >= numericProgress[index - 1]);
	}

	const rejected = assert.rejects(completion, /engine_load_failed/);
	harness.packageRequests.get("engine").options.fail({errMsg: "stop fixture"});
	await rejected;
});


test("the first fatal error wins and every late callback becomes inert", async () => {
	const harness = createHarness();
	let startCount = 0;
	const completion = startHarness(harness);
	harness.coordinator.registerEngineStarter(() => {
		startCount += 1;
	});
	const rejected = assert.rejects(completion, /engine_load_failed: primary failure/);
	harness.packageRequests.get("engine").options.fail({errMsg: "primary failure"});

	harness.gameGlobal.__godotEngineSubpackageEntryStarted = true;
	harness.gameGlobal.__godotGameDataSubpackageEntryStarted = true;
	harness.packageRequests.get("engine").options.success({errMsg: "late success"});
	harness.packageRequests.get("game_data").options.fail({errMsg: "late failure"});
	harness.packageRequests.get("game_data").options.success({errMsg: "late success"});
	await rejected;
	assert.equal(harness.failures.length, 1);
	assert.match(harness.failures[0].message, /primary failure/);
	assert.equal(harness.probeRequests.length, 0);
	assert.equal(startCount, 0);
	assert.equal(harness.coordinator.getSnapshot().failureCode, "engine_load_failed");
});


test("normalizes synchronous package exceptions and progress-hook exceptions", async () => {
	for (const behavior of [
		{syncThrowPackage: "engine", expected: /engine_load_threw/},
		{invalidTaskPackage: "engine", expected: /engine_load_threw.*progress task is unavailable/},
		{progressThrowPackage: "engine", expected: /engine_load_threw.*progress hook threw/},
	]) {
		const harness = createHarness(behavior);
		await assert.rejects(startHarness(harness), behavior.expected);
		assert.equal(harness.failures.length, 1);
	}
});


test("package, PCK probe, and engine-starter deadlines fail closed", async () => {
	{
		const timers = createFakeTimers();
		const harness = createHarness({timers});
		const completion = startHarness(harness);
		const rejected = assert.rejects(completion, /engine_load_timeout/);
		timers.runFirst(300000);
		await rejected;
		assert.equal(harness.failures.length, 1);
	}
	{
		const timers = createFakeTimers();
		const harness = createHarness({timers});
		const completion = startHarness(harness);
		markPackageEntry(harness, "game_data");
		const rejected = assert.rejects(completion, /game_data_probe_timeout/);
		timers.runFirst(10000);
		await rejected;
		assert.equal(harness.failures.length, 1);
	}
	{
		const timers = createFakeTimers();
		const harness = createHarness({timers});
		const completion = startHarness(harness);
		markPackageEntry(harness, "engine");
		const rejected = assert.rejects(completion, /engine_starter_timeout/);
		timers.runFirst(10000);
		await rejected;
		assert.equal(harness.failures.length, 1);
	}
});


test("starter synchronous throws and promise rejections are terminal failures", async () => {
	for (const starter of [
		() => {
			throw new Error("sync starter failure");
		},
		() => Promise.reject(new Error("async starter failure")),
	]) {
		const harness = createHarness();
		const completion = startHarness(harness);
		harness.coordinator.registerEngineStarter(starter);
		markPackageEntry(harness, "engine");
		markPackageEntry(harness, "game_data");
		harness.probeRequests[0].success({data: new ArrayBuffer(1)});
		await assert.rejects(completion, /engine_start_(threw|rejected)/);
		assert.equal(harness.failures.length, 1);
	}
});


test("times out a never-settling engine start and ignores every late settlement", async () => {
	assert.equal(ENGINE_START_TIMEOUT_MILLISECONDS, 300000);
	for (const lateSettlement of ["resolve", "reject"]) {
		const timers = createFakeTimers();
		const harness = createHarness({timers});
		const engineStarted = deferred();
		const completion = startHarness(harness);
		harness.coordinator.registerEngineStarter(() => engineStarted.promise);
		markPackageEntry(harness, "engine");
		markPackageEntry(harness, "game_data");
		harness.probeRequests[0].success({data: new ArrayBuffer(1)});
		const rejected = assert.rejects(completion, /engine_start_timeout/);
		timers.runFirst(300000);
		await rejected;

		if (lateSettlement === "resolve") {
			engineStarted.resolve("late");
		} else {
			engineStarted.reject(new Error("late rejection"));
		}
		await Promise.resolve();
		assert.equal(harness.failures.length, 1);
		assert.equal(harness.coordinator.getSnapshot().failureCode, "engine_start_timeout");
		assert.equal(timers.count(), 0);
	}
});


test("honors an explicit engine-start completion deadline and arms it before invocation", async () => {
	const timers = createFakeTimers();
	const harness = createHarness({timers});
	const completion = startHarness(harness, {engineStartTimeoutMilliseconds: 12345});
	let timerCountAtInvocation = 0;
	harness.coordinator.registerEngineStarter(() => {
		timerCountAtInvocation = timers.count();
		return new Promise(() => {});
	});
	markPackageEntry(harness, "engine");
	markPackageEntry(harness, "game_data");
	harness.probeRequests[0].success({data: new ArrayBuffer(1)});
	assert.equal(timerCountAtInvocation, 1);
	const rejected = assert.rejects(completion, /engine_start_timeout/);
	timers.runFirst(12345);
	await rejected;
	assert.equal(timers.count(), 0);
});


test("rejects a different duplicate starter before either can run", async () => {
	const harness = createHarness();
	const completion = startHarness(harness);
	const firstStarter = () => Promise.resolve();
	assert.equal(harness.coordinator.registerEngineStarter(firstStarter), true);
	assert.equal(harness.coordinator.registerEngineStarter(firstStarter), true);
	const rejected = assert.rejects(completion, /engine_starter_duplicate/);
	assert.equal(harness.coordinator.registerEngineStarter(() => Promise.resolve()), false);
	await rejected;
	assert.equal(harness.failures.length, 1);
});


test("keeps a bounded structured timeline using the wx performance clock", async () => {
	const timers = createFakeTimers();
	const harness = createHarness({timers});
	const completion = startHarness(harness);
	const rejected = assert.rejects(completion, /engine_load_failed/);
	const engineProgress = harness.packageRequests.get("engine").progressCallbacks[0];
	const dataProgress = harness.packageRequests.get("game_data").progressCallbacks[0];
	for (let progress = 1; progress <= 100; progress += 1) {
		engineProgress({progress});
		dataProgress({progress});
	}
	const timeline = harness.gameGlobal.__godotStartupTimeline;
	assert.ok(timeline.length > 0 && timeline.length <= 64);
	assert.ok(Object.isFrozen(timeline));
	assert.ok(timeline.every((entry) => entry.schema_version === 1));
	assert.ok(timeline.every((entry) => Number.isFinite(entry.at_ms)));
	for (let index = 1; index < timeline.length; index += 1) {
		assert.ok(timeline[index].sequence > timeline[index - 1].sequence);
	}
	harness.packageRequests.get("engine").options.fail({errMsg: "end fixture"});
	await rejected;
});


test("throttles one thousand fine-grained callbacks per package without losing the 95 percent download terminal", async () => {
	const timers = createFakeTimers();
	const harness = createHarness({timers});
	const completion = startHarness(harness);
	const rejected = assert.rejects(completion, /engine_load_failed/);
	const engineProgress = harness.packageRequests.get("engine").progressCallbacks[0];
	const dataProgress = harness.packageRequests.get("game_data").progressCallbacks[0];
	for (let step = 1; step <= 1000; step += 1) {
		const progress = step / 10;
		engineProgress({progress});
		dataProgress({progress});
	}
	const progressEvents = harness.coordinator.getSnapshot().timeline.filter(
		(entry) => entry.event === "subpackage.progress",
	);
	assert.ok(progressEvents.length <= 42, `progress events: ${progressEvents.length}`);
	assert.ok(harness.progressUpdates.length <= 193, `UI updates: ${harness.progressUpdates.length}`);
	assert.equal(harness.progressUpdates.at(-1).progress, 0.95);
	for (let index = 1; index < harness.progressUpdates.length; index += 1) {
		assert.ok(
			harness.progressUpdates[index].progress >= harness.progressUpdates[index - 1].progress,
		);
	}
	harness.packageRequests.get("engine").options.fail({errMsg: "end fixture"});
	await rejected;
});
