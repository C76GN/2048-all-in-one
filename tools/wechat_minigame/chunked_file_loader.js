(function attachWeChatChunkedFileLoader() {
	"use strict";

	const TAG = "[wechat-chunked-fetch]";
	const DEFAULT_CHUNK_BYTES = 4 * 1024 * 1024;
	const DEFAULT_CHUNK_TIMEOUT_MILLISECONDS = 30 * 1000;
	const MAX_DECLARED_RESOURCE_BYTES = 30 * 1000 * 1000;
	const INSTALL_MARKER = "__wechatChunkedLocalFetchInstalled";


	function makeError(code, context = {}) {
		const fields = [`code=${code}`];
		for (const key of ["path", "chunk", "offset", "requested", "actual", "detail"]) {
			if (context[key] !== undefined) {
				fields.push(`${key}=${sanitizeDetail(context[key])}`);
			}
		}
		const error = new Error(`${TAG} ${fields.join(" ")}`);
		error.code = code;
		return error;
	}


	function sanitizeDetail(value) {
		return String(value).replace(/[\r\n]+/g, " ").slice(0, 256);
	}


	function requirePositiveSafeInteger(value, label) {
		if (!Number.isSafeInteger(value) || value <= 0) {
			throw makeError("invalid_configuration", {detail: `${label}:${value}`});
		}
		return value;
	}


	function normalizeManifest(resourceBytes) {
		if (resourceBytes === null || typeof resourceBytes !== "object" || Array.isArray(resourceBytes)) {
			throw makeError("invalid_configuration", {detail: "resource_manifest_not_object"});
		}
		const paths = Object.keys(resourceBytes).sort();
		if (paths.length === 0) {
			throw makeError("invalid_configuration", {detail: "resource_manifest_empty"});
		}
		const manifest = {};
		let totalBytes = 0;
		for (const path of paths) {
			const hasAllowedRoot = path.startsWith("/engine/") || path.startsWith("/game_data/");
			const hasUnsafeSegment = path.includes("\\") || path.includes("//")
				|| path.includes("/./") || path.includes("/../") || path.endsWith("/.")
				|| path.endsWith("/..");
			if (!hasAllowedRoot || hasUnsafeSegment) {
				throw makeError("invalid_configuration", {
					path,
					detail: "resource_path_outside_allowed_packages",
				});
			}
			const expectedBytes = requirePositiveSafeInteger(resourceBytes[path], `resource_bytes:${path}`);
			totalBytes += expectedBytes;
			if (!Number.isSafeInteger(totalBytes) || totalBytes > MAX_DECLARED_RESOURCE_BYTES) {
				throw makeError("invalid_configuration", {detail: `resource_total_bytes:${totalBytes}`});
			}
			manifest[path] = expectedBytes;
		}
		return Object.freeze(manifest);
	}


	function asUint8Array(data, context) {
		if (data instanceof ArrayBuffer) {
			return new Uint8Array(data);
		}
		if (ArrayBuffer.isView(data)) {
			return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
		}
		throw makeError("invalid_data_type", context);
	}


	function writeLog(logger, method, event, fields) {
		if (logger === null || typeof logger !== "object") {
			return;
		}
		const sink = typeof logger[method] === "function" ? logger[method] : logger.log;
		if (typeof sink !== "function") {
			return;
		}
		const details = Object.entries(fields)
			.map(([key, value]) => `${key}=${sanitizeDetail(value)}`)
			.join(" ");
		sink.call(logger, `${TAG} ${event}${details.length > 0 ? ` ${details}` : ""}`);
	}


	function readChunkInto(
		fileSystemManager,
		output,
		filePath,
		chunkIndex,
		position,
		length,
		timeoutMilliseconds,
	) {
		return new Promise((resolve, reject) => {
			let settled = false;
			const settle = (callback, value) => {
				if (settled) {
					return;
				}
				settled = true;
				clearTimeout(timeout);
				callback(value);
			};
			const timeout = setTimeout(() => {
				settle(reject, makeError("chunk_timeout", {
					path: filePath,
					chunk: chunkIndex,
					offset: position,
					requested: length,
				}));
			}, timeoutMilliseconds);
			try {
				fileSystemManager.readFile({
					filePath,
					position,
					length,
					success(result) {
						if (settled) {
							return;
						}
						try {
							const bytes = asUint8Array(result && result.data, {
								path: filePath,
								chunk: chunkIndex,
								offset: position,
								requested: length,
							});
							if (bytes.byteLength !== length) {
								throw makeError("short_read", {
									path: filePath,
									chunk: chunkIndex,
									offset: position,
									requested: length,
									actual: bytes.byteLength,
								});
							}
							output.set(bytes, position);
							settle(resolve, bytes.byteLength);
						} catch (error) {
							settle(reject, error);
						}
					},
					fail(result) {
						settle(reject, makeError("read_failed", {
							path: filePath,
							chunk: chunkIndex,
							offset: position,
							requested: length,
							detail: result && result.errMsg ? result.errMsg : "unknown",
						}));
					},
				});
			} catch (error) {
				settle(reject, makeError("read_threw", {
					path: filePath,
					chunk: chunkIndex,
					offset: position,
					requested: length,
					detail: error && error.message ? error.message : error,
				}));
			}
		});
	}


	function readResourceInChunks(
		fileSystemManager,
		filePath,
		expectedBytes,
		chunkBytes,
		timeoutMilliseconds,
		logger,
	) {
		const output = new Uint8Array(expectedBytes);
		const chunkCount = Math.ceil(expectedBytes / chunkBytes);
		let position = 0;
		let chunkIndex = 0;
		writeLog(logger, "info", "begin", {path: filePath, bytes: expectedBytes, chunks: chunkCount});

		function readNext() {
			if (position === expectedBytes) {
				writeLog(logger, "info", "complete", {path: filePath, bytes: position, chunks: chunkIndex});
				return Promise.resolve(output.buffer);
			}
			const length = Math.min(chunkBytes, expectedBytes - position);
			const currentPosition = position;
			const currentChunkIndex = chunkIndex;
			return readChunkInto(
				fileSystemManager,
				output,
				filePath,
				currentChunkIndex,
				currentPosition,
				length,
				timeoutMilliseconds,
			).then((actualBytes) => {
				position += actualBytes;
				chunkIndex += 1;
				writeLog(logger, "info", "chunk", {
					path: filePath,
					chunk: currentChunkIndex,
					offset: currentPosition,
					bytes: actualBytes,
				});
				return readNext();
			});
		}

		return readNext().catch((error) => {
			writeLog(logger, "error", "failed", {
				path: filePath,
				detail: error && error.message ? error.message : error,
			});
			throw error;
		});
	}


	function installChunkedLocalFetch(
		fsUtils,
		fileSystemManager,
		resourceBytes,
		options = {},
	) {
		if (fsUtils === null || typeof fsUtils !== "object" || typeof fsUtils.localFetch !== "function") {
			throw makeError("invalid_configuration", {detail: "fs_utils_missing_local_fetch"});
		}
		if (fileSystemManager === null || typeof fileSystemManager !== "object" || typeof fileSystemManager.readFile !== "function") {
			throw makeError("invalid_configuration", {detail: "file_system_missing_read_file"});
		}
		if (Object.prototype.hasOwnProperty.call(fsUtils, INSTALL_MARKER)) {
			throw makeError("already_installed");
		}

		const manifest = normalizeManifest(resourceBytes);
		const chunkBytes = requirePositiveSafeInteger(
			options.chunkBytes === undefined ? DEFAULT_CHUNK_BYTES : options.chunkBytes,
			"chunk_bytes",
		);
		const timeoutMilliseconds = requirePositiveSafeInteger(
			options.chunkTimeoutMilliseconds === undefined
				? DEFAULT_CHUNK_TIMEOUT_MILLISECONDS
				: options.chunkTimeoutMilliseconds,
			"chunk_timeout_milliseconds",
		);
		const logger = options.logger === undefined ? console : options.logger;
		const originalLocalFetch = fsUtils.localFetch;
		let queueTail = Promise.resolve();

		function chunkedLocalFetch(filePath) {
			if (!Object.prototype.hasOwnProperty.call(manifest, filePath)) {
				return originalLocalFetch.call(fsUtils, filePath);
			}
			const operation = queueTail.then(() => readResourceInChunks(
				fileSystemManager,
				filePath,
				manifest[filePath],
				chunkBytes,
				timeoutMilliseconds,
				logger,
			));
			queueTail = operation.then(() => undefined, () => undefined);
			return operation;
		}

		Object.defineProperty(fsUtils, INSTALL_MARKER, {
			configurable: false,
			enumerable: false,
			value: Object.freeze({chunkBytes, manifest, timeoutMilliseconds}),
			writable: false,
		});
		fsUtils.localFetch = chunkedLocalFetch;
		writeLog(logger, "info", "installed", {
			chunk_bytes: chunkBytes,
			resources: Object.keys(manifest).length,
		});
		return fsUtils.localFetch;
	}


	const api = Object.freeze({
		DEFAULT_CHUNK_BYTES,
		DEFAULT_CHUNK_TIMEOUT_MILLISECONDS,
		installChunkedLocalFetch,
	});
	if (typeof GameGlobal === "object" && GameGlobal !== null) {
		GameGlobal.WeChatChunkedFileLoader = api;
	}
	if (typeof module === "object" && module !== null && module.exports) {
		module.exports = api;
	}
}());
