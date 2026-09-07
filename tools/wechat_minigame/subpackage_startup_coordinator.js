"use strict";

(function installWeChatSubpackageStartupCoordinator(globalObject) {
	const PACKAGE_TIMEOUT_MILLISECONDS = 300000;
	const PROBE_TIMEOUT_MILLISECONDS = 10000;
	const STARTER_TIMEOUT_MILLISECONDS = 10000;
	const ENGINE_START_TIMEOUT_MILLISECONDS = 300000;
	const DOWNLOAD_PROGRESS_WEIGHT = 0.95;
	const PROGRESS_TRACE_STEP_PERCENTAGE = 5;
	const UI_PROGRESS_MIN_STEP = 0.005;
	const TRACE_LIMIT = 64;
	const TRACE_SCHEMA_VERSION = 1;
	const PACKAGE_NAMES = Object.freeze(["engine", "game_data"]);
	const PACKAGE_CONFIGURATION = Object.freeze({
		engine: Object.freeze({
			entryMarker: "__godotEngineSubpackageEntryStarted",
			entryPath: "engine/game.js",
		}),
		game_data: Object.freeze({
			entryMarker: "__godotGameDataSubpackageEntryStarted",
			entryPath: "game_data/game.js",
		}),
	});


	function asError(reason, fallbackMessage) {
		if (reason instanceof Error) {
			return reason;
		}
		if (reason && typeof reason.errMsg === "string") {
			return new Error(reason.errMsg);
		}
		return new Error(reason == null ? fallbackMessage : String(reason));
	}


	function finitePositiveNumber(value) {
		const number = Number(value);
		return Number.isFinite(number) && number > 0 ? number : 0;
	}


	function clampPercentage(value) {
		const number = Number(value);
		if (!Number.isFinite(number)) {
			return null;
		}
		return Math.max(0, Math.min(100, number));
	}


	function createClock(wxApi, explicitClock) {
		if (typeof explicitClock === "function") {
			return () => {
				try {
					const value = Number(explicitClock());
					if (Number.isFinite(value)) {
						return value;
					}
				} catch (_error) {
					// Date.now remains the final fallback.
				}
				return Date.now();
			};
		}
		try {
			if (wxApi && typeof wxApi.getPerformance === "function") {
				const performance = wxApi.getPerformance();
				if (performance && typeof performance.now === "function") {
					return () => {
						try {
							const value = Number(performance.now());
							if (Number.isFinite(value)) {
								return value;
							}
						} catch (_error) {
							// Date.now remains the final fallback.
						}
						return Date.now();
					};
				}
			}
		} catch (_error) {
			// Date.now remains a deterministic fallback when wx performance is unavailable.
		}
		return () => Date.now();
	}


	function createStartupCoordinator(dependencies = {}) {
		const wxApi = dependencies.wxApi || globalObject.wx;
		const gameGlobal = dependencies.gameGlobal || globalObject.GameGlobal || globalObject;
		const setTimeoutFunction = dependencies.setTimeoutFunction || globalObject.setTimeout;
		const clearTimeoutFunction = dependencies.clearTimeoutFunction || globalObject.clearTimeout;
		const logger = dependencies.logger || globalObject.console || {};
		const clockNow = createClock(wxApi, dependencies.clockNow);
		const externalFailureReporter = dependencies.reportFailure;
		let activeSession = null;
		let pendingStarter = null;
		let nextSessionId = 1;

		function safeLog(level, ...values) {
			try {
				if (logger && typeof logger[level] === "function") {
					logger[level](...values);
				}
			} catch (_error) {
				// Diagnostics must never change startup state.
			}
		}

		function isLive(session) {
			return activeSession === session && !session.terminal;
		}

		function publicTimeline(session) {
			return session.timeline.map((entry) => Object.assign({}, entry));
		}

		function exposeTimeline(session) {
			try {
				gameGlobal.__godotStartupTimeline = Object.freeze(publicTimeline(session));
			} catch (_error) {
				// A frozen/host GameGlobal must not block startup.
			}
		}

		function record(session, event, fields = {}) {
			const entry = {
				schema_version: TRACE_SCHEMA_VERSION,
				sequence: session.nextSequence,
				event,
				at_ms: Number(clockNow()),
			};
			session.nextSequence += 1;
			for (const [key, value] of Object.entries(fields)) {
				if (typeof value === "string") {
					entry[key] = value.slice(0, 256);
				} else if (typeof value === "number" && Number.isFinite(value)) {
					entry[key] = value;
				} else if (typeof value === "boolean") {
					entry[key] = value;
				}
			}
			session.timeline.push(Object.freeze(entry));
			if (session.timeline.length > TRACE_LIMIT) {
				session.timeline.splice(0, session.timeline.length - TRACE_LIMIT);
			}
			exposeTimeline(session);
			safeLog("info", "[wechat-startup]", JSON.stringify(entry));
		}

		function clearTimer(session, name) {
			if (!session.timers.has(name)) {
				return;
			}
			const timerId = session.timers.get(name);
			session.timers.delete(name);
			try {
				clearTimeoutFunction(timerId);
			} catch (_error) {
				// The session state already makes a late timer inert.
			}
		}

		function clearAllTimers(session) {
			for (const name of [...session.timers.keys()]) {
				clearTimer(session, name);
			}
		}

		function setDeadline(session, name, milliseconds, callback) {
			clearTimer(session, name);
			let timerId;
			try {
				timerId = setTimeoutFunction(() => {
					session.timers.delete(name);
					if (isLive(session)) {
						callback();
					}
				}, milliseconds);
			} catch (reason) {
				fail(session, "timer_registration_failed", asError(reason, "startup timer registration failed"));
				return;
			}
			session.timers.set(name, timerId);
		}

		function progressText(session, kind) {
			const config = session.loader && session.loader.config;
			const textConfig = config && config.textConfig;
			if (kind === "failed") {
				return textConfig && textConfig.loadFailedText
					? textConfig.loadFailedText
					: "引擎分包加载失败";
			}
			if (kind === "init") {
				return textConfig && textConfig.initText ? textConfig.initText : "引擎初始化中";
			}
			const downloading = textConfig && textConfig.downloadingText;
			return Array.isArray(downloading) && downloading.length > 0
				? downloading[0]
				: "资源下载中";
		}

		function writeProgress(session, progress, kind, force = false) {
			if (!isLive(session)) {
				return;
			}
			const monotonicProgress = Math.max(session.reportedProgress, Math.min(1, progress));
			const kindChanged = session.progressKind !== kind;
			if (
				!force &&
				!kindChanged &&
				monotonicProgress - session.reportedProgress + Number.EPSILON < UI_PROGRESS_MIN_STEP
			) {
				return;
			}
			session.reportedProgress = monotonicProgress;
			session.progressKind = kind;
			try {
				session.loader.progress = monotonicProgress;
				session.loader.updateProgress(monotonicProgress, progressText(session, kind));
			} catch (reason) {
				fail(session, "progress_update_failed", asError(reason, "startup progress update failed"));
			}
		}

		function updateDownloadProgress(session, packageName, percentage) {
			if (!isLive(session)) {
				return;
			}
			const normalized = clampPercentage(percentage);
			if (normalized == null || normalized <= session.packageProgress[packageName]) {
				return;
			}
			session.packageProgress[packageName] = normalized;
			const lastRecorded = session.packageRecordedProgress[packageName];
			if (
				lastRecorded == null ||
				normalized === 100 ||
				normalized - lastRecorded + Number.EPSILON >= PROGRESS_TRACE_STEP_PERCENTAGE
			) {
				session.packageRecordedProgress[packageName] = normalized;
				record(session, "subpackage.progress", {package: packageName, progress: normalized});
			}
			const weightedBytes = PACKAGE_NAMES.reduce(
				(total, name) => total + session.packageBytes[name] * session.packageProgress[name] / 100,
				0,
			);
			const progress = DOWNLOAD_PROGRESS_WEIGHT * weightedBytes / session.totalPackageBytes;
			const downloadComplete = PACKAGE_NAMES.every(
				(name) => session.packageProgress[name] === 100,
			);
			writeProgress(session, progress, "download", downloadComplete);
		}

		function defaultFailureReporter(session, error) {
			try {
				session.loader.progress = 0;
				session.loader.updateProgress(0, progressText(session, "failed"));
			} catch (_error) {
				// Preserve the first startup error.
			}
			try {
				setTimeoutFunction(() => {
					throw error;
				}, 0);
			} catch (_error) {
				safeLog("error", "[wechat-startup] visible failure", error);
			}
		}

		function fail(session, code, reason) {
			if (!isLive(session)) {
				return;
			}
			const sourceError = asError(reason, code);
			const error = new Error(`[wechat-startup] ${code}: ${sourceError.message}`);
			session.terminal = true;
			session.status = "failed";
			session.failureCode = code;
			clearAllTimers(session);
			record(session, "startup.fatal", {code, message: error.message});
			safeLog("error", "[wechat-startup] fatal", code, error);
			try {
				if (typeof externalFailureReporter === "function") {
					externalFailureReporter(error, publicTimeline(session));
				} else {
					defaultFailureReporter(session, error);
				}
			} catch (reportReason) {
				safeLog("error", "[wechat-startup] failure reporter threw", reportReason);
			}
			session.reject(error);
		}

		function maybeStartEngine(session) {
			if (!isLive(session) || session.engineStartInvoked) {
				return;
			}
			if (
				!session.packageReady.engine ||
				!session.engineStarter ||
				!session.packageReady.game_data ||
				!session.gameDataProbeReady
			) {
				return;
			}
			session.engineStartInvoked = true;
			clearTimer(session, "starter");
			record(session, "startup.barrier_ready", {
				engine_entry: true,
				engine_starter: true,
				game_data_entry: true,
				game_data_probe: true,
			});
			writeProgress(session, 0.98, "init");
			let starterResult;
			try {
				record(session, "engine.start_begin");
				setDeadline(session, "engine_start", session.engineStartTimeoutMilliseconds, () => {
					fail(session, "engine_start_timeout", new Error("engine start did not complete before its deadline"));
				});
				if (!isLive(session)) {
					return;
				}
				starterResult = session.engineStarter();
			} catch (reason) {
				fail(session, "engine_start_threw", asError(reason, "engine starter threw"));
				return;
			}
			Promise.resolve(starterResult).then(
				() => {
					if (!isLive(session)) {
						return;
					}
					clearTimer(session, "engine_start");
					session.terminal = true;
					session.status = "started";
					clearAllTimers(session);
					record(session, "engine.start_resolved");
					try {
						session.reportedProgress = 1;
						session.progressKind = "init";
						session.loader.progress = 1;
						session.loader.updateProgress(1, progressText(session, "init"));
					} catch (_error) {
						// The engine is already running; preserve that successful terminal state.
					}
					session.resolve({
						status: "started",
						timeline: publicTimeline(session),
					});
				},
				(reason) => {
					clearTimer(session, "engine_start");
					fail(session, "engine_start_rejected", asError(reason, "engine starter rejected"));
				},
			);
		}

		function beginGameDataProbe(session) {
			if (!isLive(session) || session.gameDataProbeStarted) {
				return;
			}
			session.gameDataProbeStarted = true;
			record(session, "game_data.probe_begin", {path: session.pckPath});
			setDeadline(session, "probe", session.probeTimeoutMilliseconds, () => {
				fail(session, "game_data_probe_timeout", new Error("game_data PCK probe timed out"));
			});
			try {
				const fileSystem = wxApi.getFileSystemManager();
				if (!fileSystem || typeof fileSystem.readFile !== "function") {
					throw new Error("wx file system readFile is unavailable");
				}
				fileSystem.readFile({
					filePath: session.pckPath,
					position: 0,
					length: 1,
					success(result) {
						if (!isLive(session) || session.gameDataProbeReady) {
							return;
						}
						const bytes = result && result.data && result.data.byteLength;
						if (bytes !== 1) {
							fail(session, "game_data_probe_empty", new Error("game_data PCK probe returned no byte"));
							return;
						}
						clearTimer(session, "probe");
						session.gameDataProbeReady = true;
						record(session, "game_data.probe_success", {bytes});
						maybeStartEngine(session);
					},
					fail: (result) => {
						if (!isLive(session) || session.gameDataProbeReady) {
							return;
						}
						fail(session, "game_data_probe_failed", asError(result, "game_data PCK probe failed"));
					},
				});
			} catch (reason) {
				fail(session, "game_data_probe_threw", asError(reason, "game_data PCK probe failed"));
			}
		}

		function packageSucceeded(session, packageName, result) {
			if (!isLive(session) || session.packageReady[packageName]) {
				return;
			}
			const configuration = PACKAGE_CONFIGURATION[packageName];
			clearTimer(session, `package:${packageName}`);
			updateDownloadProgress(session, packageName, 100);
			record(session, "subpackage.success", {
				package: packageName,
				detail: result && result.errMsg ? result.errMsg : "loadSubpackage:ok",
			});
			if (gameGlobal[configuration.entryMarker] !== true) {
				fail(
					session,
					`${packageName}_entry_missing`,
					new Error(`${configuration.entryPath} did not execute after the ${packageName} subpackage loaded`),
				);
				return;
			}
			session.packageReady[packageName] = true;
			record(session, "subpackage.entry_confirmed", {
				package: packageName,
				entry_path: configuration.entryPath,
			});
			if (packageName === "engine") {
				if (!session.engineStarter) {
					setDeadline(session, "starter", session.starterTimeoutMilliseconds, () => {
						fail(session, "engine_starter_timeout", new Error("engine starter was not registered"));
					});
				}
				maybeStartEngine(session);
				return;
			}
			beginGameDataProbe(session);
		}

		function requestPackage(session, packageName) {
			if (!isLive(session)) {
				return;
			}
			const configuration = PACKAGE_CONFIGURATION[packageName];
			gameGlobal[configuration.entryMarker] = false;
			record(session, "subpackage.request", {package: packageName});
			setDeadline(session, `package:${packageName}`, session.packageTimeoutMilliseconds, () => {
				fail(session, `${packageName}_load_timeout`, new Error(`${packageName} subpackage load timed out`));
			});
			if (!isLive(session)) {
				return;
			}
			try {
				const task = wxApi.loadSubpackage({
					name: packageName,
					success: (result) => packageSucceeded(session, packageName, result),
					fail: (result) => {
						if (isLive(session) && !session.packageReady[packageName]) {
							fail(session, `${packageName}_load_failed`, asError(result, `${packageName} subpackage load failed`));
						}
					},
					complete: (result) => {
						if (isLive(session)) {
							record(session, "subpackage.complete", {
								package: packageName,
								detail: result && result.errMsg ? result.errMsg : String(result),
							});
						}
					},
				});
				if (!task || typeof task.onProgressUpdate !== "function") {
					throw new Error(`${packageName} subpackage progress task is unavailable`);
				}
				task.onProgressUpdate((event) => {
					if (isLive(session) && !session.packageReady[packageName]) {
						updateDownloadProgress(session, packageName, event && event.progress);
					}
				});
			} catch (reason) {
				fail(session, `${packageName}_load_threw`, asError(reason, `${packageName} subpackage load failed`));
			}
		}

		function registerEngineStarter(starter) {
			if (typeof starter !== "function") {
				if (activeSession && isLive(activeSession)) {
					fail(activeSession, "engine_starter_invalid", new Error("engine starter must be a function"));
				}
				return false;
			}
			if (!activeSession) {
				if (!pendingStarter) {
					pendingStarter = starter;
				}
				return pendingStarter === starter;
			}
			const session = activeSession;
			if (!isLive(session)) {
				return session.engineStarter === starter;
			}
			if (session.engineStarter) {
				if (session.engineStarter !== starter) {
					fail(session, "engine_starter_duplicate", new Error("a different engine starter was already registered"));
					return false;
				}
				return true;
			}
			session.engineStarter = starter;
			clearTimer(session, "starter");
			record(session, "engine.starter_registered");
			maybeStartEngine(session);
			return true;
		}

		function start(options = {}) {
			if (activeSession) {
				return activeSession.promise;
			}
			let resolveSession;
			let rejectSession;
			const promise = new Promise((resolve, reject) => {
				resolveSession = resolve;
				rejectSession = reject;
			});
			const packageBytes = {
				engine: finitePositiveNumber(options.packageBytes && options.packageBytes.engine),
				game_data: finitePositiveNumber(options.packageBytes && options.packageBytes.game_data),
			};
			const session = {
				id: nextSessionId,
				promise,
				resolve: resolveSession,
				reject: rejectSession,
				terminal: false,
				status: "loading",
				failureCode: "",
				loader: options.loader,
				packageBytes,
				totalPackageBytes: packageBytes.engine + packageBytes.game_data,
				packageProgress: {engine: 0, game_data: 0},
				packageRecordedProgress: {engine: null, game_data: null},
				packageReady: {engine: false, game_data: false},
				gameDataProbeStarted: false,
				gameDataProbeReady: false,
				engineStarter: pendingStarter,
				engineStartInvoked: false,
				pckPath: typeof options.pckPath === "string" ? options.pckPath : "",
				packageTimeoutMilliseconds: finitePositiveNumber(options.packageTimeoutMilliseconds) || PACKAGE_TIMEOUT_MILLISECONDS,
				probeTimeoutMilliseconds: finitePositiveNumber(options.probeTimeoutMilliseconds) || PROBE_TIMEOUT_MILLISECONDS,
				starterTimeoutMilliseconds: finitePositiveNumber(options.starterTimeoutMilliseconds) || STARTER_TIMEOUT_MILLISECONDS,
				engineStartTimeoutMilliseconds: finitePositiveNumber(options.engineStartTimeoutMilliseconds) || ENGINE_START_TIMEOUT_MILLISECONDS,
				reportedProgress: 0,
				progressKind: "",
				timers: new Map(),
				timeline: [],
				nextSequence: 1,
			};
			nextSessionId += 1;
			pendingStarter = null;
			activeSession = session;
			record(session, "startup.begin", {
				session_id: session.id,
				engine_bytes: packageBytes.engine,
				game_data_bytes: packageBytes.game_data,
			});
			if (!session.loader || typeof session.loader.updateProgress !== "function") {
				fail(session, "loader_invalid", new Error("Godot loader progress boundary is unavailable"));
				return promise;
			}
			if (!wxApi || typeof wxApi.loadSubpackage !== "function") {
				fail(session, "wx_load_subpackage_unavailable", new Error("wx.loadSubpackage is unavailable"));
				return promise;
			}
			if (session.totalPackageBytes <= 0 || !packageBytes.engine || !packageBytes.game_data) {
				fail(session, "package_bytes_invalid", new Error("engine and game_data package byte weights are required"));
				return promise;
			}
			if (!session.pckPath.startsWith("/game_data/") || session.pckPath.includes("..")) {
				fail(session, "pck_path_invalid", new Error("PCK probe path must stay under /game_data/"));
				return promise;
			}
			writeProgress(session, 0, "download");
			for (const packageName of PACKAGE_NAMES) {
				requestPackage(session, packageName);
			}
			return promise;
		}

		function getSnapshot() {
			if (!activeSession) {
				return null;
			}
			return {
				status: activeSession.status,
				failureCode: activeSession.failureCode,
				engineStartInvoked: activeSession.engineStartInvoked,
				progress: activeSession.reportedProgress,
				timeline: publicTimeline(activeSession),
			};
		}

		return Object.freeze({
			start,
			registerEngineStarter,
			getSnapshot,
		});
	}


	const singleton = createStartupCoordinator();
	const publicApi = Object.freeze({
		PACKAGE_TIMEOUT_MILLISECONDS,
		PROBE_TIMEOUT_MILLISECONDS,
		STARTER_TIMEOUT_MILLISECONDS,
		ENGINE_START_TIMEOUT_MILLISECONDS,
		DOWNLOAD_PROGRESS_WEIGHT,
		PROGRESS_TRACE_STEP_PERCENTAGE,
		UI_PROGRESS_MIN_STEP,
		TRACE_LIMIT,
		TRACE_SCHEMA_VERSION,
		createStartupCoordinator,
		start: singleton.start,
		registerEngineStarter: singleton.registerEngineStarter,
		getSnapshot: singleton.getSnapshot,
	});
	if (globalObject.GameGlobal) {
		globalObject.GameGlobal.WeChatSubpackageStartupCoordinator = publicApi;
	} else {
		globalObject.WeChatSubpackageStartupCoordinator = publicApi;
	}
	if (typeof module !== "undefined" && module.exports) {
		module.exports = publicApi;
	}
})(typeof globalThis !== "undefined" ? globalThis : this);
