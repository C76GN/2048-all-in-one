"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");

const loader = require("../../tools/wechat_minigame/chunked_file_loader.js");

const CHUNK_BYTES = 4 * 1024 * 1024;
const RESOURCE_PATH = "/engine/2048-all-in-one.bin";


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


function installFor(sourceByPath, calls, behavior = {}, options = {}) {
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
		makeFileSystem(sourceByPath, calls, behavior),
		resourceBytes,
		{
			chunkBytes: CHUNK_BYTES,
			chunkTimeoutMilliseconds: options.chunkTimeoutMilliseconds || 1000,
			logger: silentLogger(),
		},
	);
	return {fsUtils, delegatedPaths};
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
