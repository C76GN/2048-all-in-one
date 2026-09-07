"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");

const loader = require("../../tools/wechat_minigame/chunked_file_loader.js");

const CHUNK_BYTES = 4 * 1024 * 1024;
const RESOURCE_PATH = "/engine/2048-all-in-one.bin";
const GAME_DATA_RESOURCE_PATH = "/game_data/2048-all-in-one.bin";


function makeBytes(size) {
	const bytes = Buffer.allocUnsafe(size);
	for (let index = 0; index < size; index += 1) {
		bytes[index] = index % 251;
	}
	return bytes;
}


function sha256(bytes) {
	return crypto.createHash("sha256").update(bytes).digest("hex");
}


function silentLogger() {
	return {
		info() {},
		error() {},
	};
}


function makeFileSystem(sourceByPath, calls, behavior = {}) {
	return {
		readFile(options) {
			calls.push({
				filePath: options.filePath,
				position: options.position,
				length: options.length,
				encoding: options.encoding,
			});
			const source = sourceByPath[options.filePath];
			const callIndex = calls.length - 1;
			if (behavior.throwOnCall === callIndex) {
				throw new Error("synchronous read failure");
			}
			if (behavior.failPath === options.filePath) {
				setImmediate(() => options.fail({errMsg: "fixture read failure"}));
				return;
			}
			const requestedEnd = options.position + options.length;
			const end = behavior.shortRead
				? Math.max(options.position, requestedEnd - 1)
				: requestedEnd;
			const chunk = source.subarray(options.position, end);
			const data = behavior.invalidData ? "not-an-array-buffer" : chunk.buffer.slice(
				chunk.byteOffset,
				chunk.byteOffset + chunk.byteLength,
			);
			const complete = () => options.success({data});
			if (behavior.delayMilliseconds) {
				setTimeout(complete, behavior.delayMilliseconds);
			} else {
				setImmediate(complete);
			}
		},
	};
}


function installWithFileSystem(sourceByPath, fileSystemManager, options = {}) {
	const delegatedPaths = [];
	const fsUtils = {
		localFetch(path) {
			delegatedPaths.push(path);
			return Promise.resolve(Buffer.from("delegated"));
		},
	};
	const resourceBytes = {};
	for (const [path, bytes] of Object.entries(sourceByPath)) {
		resourceBytes[path] = bytes.byteLength;
	}
	loader.installChunkedLocalFetch(
		fsUtils,
		fileSystemManager,
		resourceBytes,
		{
			chunkBytes: CHUNK_BYTES,
			chunkTimeoutMilliseconds: options.chunkTimeoutMilliseconds || 1000,
			maxConcurrentResources: options.maxConcurrentResources || 2,
			logger: silentLogger(),
		},
	);
	return {fsUtils, delegatedPaths};
}


function installFor(sourceByPath, calls, behavior = {}, options = {}) {
	return installWithFileSystem(
		sourceByPath,
		makeFileSystem(sourceByPath, calls, behavior),
		options,
	);
}


function waitForTurn() {
	return new Promise((resolve) => setImmediate(resolve));
}


function makeControlledFileSystem(sourceByPath, calls, pendingByPath) {
	return {
		readFile(options) {
			calls.push({
				filePath: options.filePath,
				position: options.position,
				length: options.length,
			});
			pendingByPath.set(options.filePath, options);
		},
	};
}


function completeControlledRead(sourceByPath, pendingByPath, filePath) {
	const options = pendingByPath.get(filePath);
	assert.ok(options, `missing controlled read for ${filePath}`);
	pendingByPath.delete(filePath);
	const source = sourceByPath[filePath];
	const chunk = source.subarray(options.position, options.position + options.length);
	options.success({
		data: chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength),
	});
}


test("reassembles deterministic bytes across chunk boundaries", async () => {
	for (const size of [1, CHUNK_BYTES - 1, CHUNK_BYTES, CHUNK_BYTES + 1, 3 * CHUNK_BYTES + 17]) {
		const source = makeBytes(size);
		const calls = [];
		const {fsUtils} = installFor({[RESOURCE_PATH]: source}, calls);
		const result = Buffer.from(await fsUtils.localFetch(RESOURCE_PATH));

		assert.equal(result.byteLength, source.byteLength);
		assert.equal(sha256(result), sha256(source));
		assert.deepEqual(
			calls.map(({position, length, encoding}) => ({position, length, encoding})),
			Array.from({length: Math.ceil(size / CHUNK_BYTES)}, (_, index) => ({
				position: index * CHUNK_BYTES,
				length: Math.min(CHUNK_BYTES, size - index * CHUNK_BYTES),
				encoding: undefined,
			})),
		);
	}
});


test("accepts only engine and game_data package resource roots", async () => {
	const source = makeBytes(64);
	const calls = [];
	const {fsUtils} = installFor({[GAME_DATA_RESOURCE_PATH]: source}, calls);
	assert.equal(
		sha256(Buffer.from(await fsUtils.localFetch(GAME_DATA_RESOURCE_PATH))),
		sha256(source),
	);
	assert.throws(
		() => installFor({"/other/data.bin": source}, []),
		/resource_path_outside_allowed_packages/,
	);
});


test("delegates paths outside the declared large-resource manifest", async () => {
	const calls = [];
	const source = makeBytes(32);
	const {fsUtils, delegatedPaths} = installFor({[RESOURCE_PATH]: source}, calls);
	const result = await fsUtils.localFetch("/engine/small-fixture.bin");

	assert.equal(Buffer.from(result).toString("utf8"), "delegated");
	assert.deepEqual(delegatedPaths, ["/engine/small-fixture.bin"]);
	assert.equal(calls.length, 0);
});


test("rejects short reads and invalid response types", async () => {
	const source = makeBytes(CHUNK_BYTES + 1);
	for (const behavior of [{shortRead: true}, {invalidData: true}]) {
		const calls = [];
		const {fsUtils} = installFor({[RESOURCE_PATH]: source}, calls, behavior);
		await assert.rejects(
			fsUtils.localFetch(RESOURCE_PATH),
			/\[wechat-chunked-fetch\].*(short_read|invalid_data_type)/,
		);
	}
});


test("normalizes a synchronous file-system exception into a tagged rejection", async () => {
	const source = makeBytes(32);
	const calls = [];
	const {fsUtils} = installFor(
		{[RESOURCE_PATH]: source},
		calls,
		{throwOnCall: 0},
	);

	await assert.rejects(
		fsUtils.localFetch(RESOURCE_PATH),
		/\[wechat-chunked-fetch\].*read_threw/,
	);
});


test("a failed resource does not poison the whole-file queue", async () => {
	const failedPath = "/engine/failed.bin";
	const recoveredPath = "/engine/recovered.bin";
	const sourceByPath = {
		[failedPath]: makeBytes(64),
		[recoveredPath]: makeBytes(CHUNK_BYTES + 5),
	};
	const calls = [];
	const {fsUtils} = installFor(sourceByPath, calls, {failPath: failedPath});
	const failed = fsUtils.localFetch(failedPath);
	const recovered = fsUtils.localFetch(recoveredPath);

	await assert.rejects(failed, /\[wechat-chunked-fetch\].*read_failed/);
	assert.equal(sha256(Buffer.from(await recovered)), sha256(sourceByPath[recoveredPath]));
	assert.equal(calls[0].filePath, failedPath);
	assert.equal(calls[1].filePath, recoveredPath);
});


test("starts two different resource paths concurrently", async () => {
	const firstPath = "/engine/first.bin";
	const secondPath = "/game_data/second.bin";
	const sourceByPath = {
		[firstPath]: makeBytes(64),
		[secondPath]: makeBytes(96),
	};
	const calls = [];
	const pendingByPath = new Map();
	const {fsUtils} = installWithFileSystem(
		sourceByPath,
		makeControlledFileSystem(sourceByPath, calls, pendingByPath),
	);

	const first = fsUtils.localFetch(firstPath);
	const second = fsUtils.localFetch(secondPath);
	await waitForTurn();
	assert.deepEqual(calls.map(({filePath}) => filePath), [firstPath, secondPath]);

	completeControlledRead(sourceByPath, pendingByPath, firstPath);
	completeControlledRead(sourceByPath, pendingByPath, secondPath);
	assert.equal(sha256(Buffer.from(await first)), sha256(sourceByPath[firstPath]));
	assert.equal(sha256(Buffer.from(await second)), sha256(sourceByPath[secondPath]));
});


test("deduplicates an in-flight read for the same resource path", async () => {
	const sourceByPath = {[RESOURCE_PATH]: makeBytes(128)};
	const calls = [];
	const pendingByPath = new Map();
	const {fsUtils} = installWithFileSystem(
		sourceByPath,
		makeControlledFileSystem(sourceByPath, calls, pendingByPath),
	);

	const first = fsUtils.localFetch(RESOURCE_PATH);
	const duplicate = fsUtils.localFetch(RESOURCE_PATH);
	assert.strictEqual(duplicate, first);
	await waitForTurn();
	assert.equal(calls.length, 1);

	completeControlledRead(sourceByPath, pendingByPath, RESOURCE_PATH);
	const [firstResult, duplicateResult] = await Promise.all([first, duplicate]);
	assert.strictEqual(duplicateResult, firstResult);
	assert.equal(sha256(Buffer.from(firstResult)), sha256(sourceByPath[RESOURCE_PATH]));

	const retry = fsUtils.localFetch(RESOURCE_PATH);
	assert.notStrictEqual(retry, first);
	await waitForTurn();
	assert.equal(calls.length, 2);
	completeControlledRead(sourceByPath, pendingByPath, RESOURCE_PATH);
	await retry;
});


test("never starts more than two resource paths concurrently", async () => {
	const firstPath = "/engine/first.bin";
	const secondPath = "/engine/second.bin";
	const thirdPath = "/game_data/third.bin";
	const sourceByPath = {
		[firstPath]: makeBytes(32),
		[secondPath]: makeBytes(48),
		[thirdPath]: makeBytes(64),
	};
	const calls = [];
	const pendingByPath = new Map();
	const {fsUtils} = installWithFileSystem(
		sourceByPath,
		makeControlledFileSystem(sourceByPath, calls, pendingByPath),
	);

	const first = fsUtils.localFetch(firstPath);
	const second = fsUtils.localFetch(secondPath);
	const third = fsUtils.localFetch(thirdPath);
	await waitForTurn();
	assert.equal(calls.length, 2);
	assert.deepEqual([...pendingByPath.keys()], [firstPath, secondPath]);

	completeControlledRead(sourceByPath, pendingByPath, firstPath);
	await waitForTurn();
	assert.equal(calls.length, 3);
	assert.deepEqual([...pendingByPath.keys()], [secondPath, thirdPath]);

	completeControlledRead(sourceByPath, pendingByPath, secondPath);
	completeControlledRead(sourceByPath, pendingByPath, thirdPath);
	await Promise.all([first, second, third]);
});


test("releases a concurrency slot after failure", async () => {
	const failedPath = "/engine/failed.bin";
	const blockedPath = "/engine/blocked.bin";
	const recoveredPath = "/game_data/recovered.bin";
	const sourceByPath = {
		[failedPath]: makeBytes(32),
		[blockedPath]: makeBytes(48),
		[recoveredPath]: makeBytes(64),
	};
	const calls = [];
	const pendingByPath = new Map();
	const {fsUtils} = installWithFileSystem(
		sourceByPath,
		makeControlledFileSystem(sourceByPath, calls, pendingByPath),
	);

	const failed = fsUtils.localFetch(failedPath);
	const blocked = fsUtils.localFetch(blockedPath);
	const recovered = fsUtils.localFetch(recoveredPath);
	await waitForTurn();
	assert.equal(calls.length, 2);
	pendingByPath.get(failedPath).fail({errMsg: "fixture read failure"});
	pendingByPath.delete(failedPath);
	await assert.rejects(failed, /\[wechat-chunked-fetch\].*read_failed/);
	await waitForTurn();
	assert.equal(calls.length, 3);
	assert.ok(pendingByPath.has(recoveredPath));

	completeControlledRead(sourceByPath, pendingByPath, blockedPath);
	completeControlledRead(sourceByPath, pendingByPath, recoveredPath);
	await Promise.all([blocked, recovered]);
});


test("times out one chunk and ignores its late success callback", async () => {
	const source = makeBytes(64);
	const calls = [];
	const {fsUtils} = installFor(
		{[RESOURCE_PATH]: source},
		calls,
		{delayMilliseconds: 40},
		{chunkTimeoutMilliseconds: 5},
	);

	await assert.rejects(
		fsUtils.localFetch(RESOURCE_PATH),
		/\[wechat-chunked-fetch\].*chunk_timeout/,
	);
	await new Promise((resolve) => setTimeout(resolve, 60));
	assert.equal(calls.length, 1);
});


test("cleans up a timed-out in-flight path before retry and ignores the stale callback", async () => {
	const sourceByPath = {[RESOURCE_PATH]: makeBytes(64)};
	const calls = [];
	let callCount = 0;
	const fileSystemManager = {
		readFile(options) {
			calls.push(options);
			callCount += 1;
			const chunk = sourceByPath[options.filePath].subarray(
				options.position,
				options.position + options.length,
			);
			const complete = () => options.success({
				data: chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength),
			});
			if (callCount === 1) {
				setTimeout(complete, 40);
			} else {
				setImmediate(complete);
			}
		},
	};
	const {fsUtils} = installWithFileSystem(
		sourceByPath,
		fileSystemManager,
		{chunkTimeoutMilliseconds: 5},
	);

	await assert.rejects(
		fsUtils.localFetch(RESOURCE_PATH),
		/\[wechat-chunked-fetch\].*chunk_timeout/,
	);
	const retried = Buffer.from(await fsUtils.localFetch(RESOURCE_PATH));
	assert.equal(sha256(retried), sha256(sourceByPath[RESOURCE_PATH]));
	await new Promise((resolve) => setTimeout(resolve, 60));
	assert.equal(calls.length, 2);
});


test("rejects duplicate installation instead of stacking wrappers", () => {
	const source = makeBytes(16);
	const calls = [];
	const installed = installFor({[RESOURCE_PATH]: source}, calls);

	assert.throws(
		() => loader.installChunkedLocalFetch(
			installed.fsUtils,
			makeFileSystem({[RESOURCE_PATH]: source}, calls),
			{[RESOURCE_PATH]: source.byteLength},
		),
		/\[wechat-chunked-fetch\].*already_installed/,
	);
});


test("rejects a configured resource concurrency above the fixed safety cap", () => {
	const source = makeBytes(16);
	assert.throws(
		() => installFor(
			{[RESOURCE_PATH]: source},
			[],
			{},
			{maxConcurrentResources: 3},
		),
		/\[wechat-chunked-fetch\].*max_concurrent_resources_exceeds_limit:3/,
	);
});
