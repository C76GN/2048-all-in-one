## GameBackgroundMusicUtility: 项目背景音乐播放策略。
##
## 只消费 `user://content_packages` 下由 GF 内容包目录注册的稳定资源键。付费源文件
## 不进入仓库，缺少本地内容包时静默降级。压缩 OGG 或旧版 WAV 文件由
## GFBackgroundWorkUtility 在线程中读取，主线程只负责构建对应 AudioStream 并
## 委托 GFAudioUtility 播放。新安装包使用 OGG，避免在主线程展开大体积 PCM。
class_name GameBackgroundMusicUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal playlist_changed(track_keys: PackedStringArray)
signal track_started(track_key: StringName)


# --- 常量 ---

const PACKAGE_ID: StringName = &"c76.local_audio.puzzle_music_2"
const RESOURCE_KEY_PREFIX: String = "asset.audio.music.puzzle_music_2."
const PLAYLIST_ID: String = "puzzle_music_2"
const CONTENT_ROOT_PREFIX: String = "user://content_packages/puzzle_music_2/"
const RESOURCE_TYPE_HINT: String = "AudioStreamOggVorbis"
const LEGACY_RESOURCE_TYPE_HINT: String = "AudioStreamWAV"
const SUPPORTED_RESOURCE_TYPE_HINTS: Array[String] = [
	"AudioStreamOggVorbis",
	"AudioStreamWAV",
]
const MAX_TRACK_BYTES: int = 64 * 1024 * 1024
const _SHUFFLE_NAMESPACE: String = "game.background_music.cosmetic"
const _LOAD_WORKER_SCRIPT: GDScript = preload(
	"res://features/themes/scripts/workers/puzzle_music_file_read_worker.gd"
)


# --- 公共变量 ---

## 架构 ready 后，在没有其他 BGM 会话时自动播放本地曲目。
var auto_play_on_ready: bool = true

## 曲目切换时交给 GFAudioUtility 的淡变时长。
var crossfade_seconds: float = 0.65:
	set(value):
		crossfade_seconds = maxf(value, 0.0) if is_finite(value) else 0.65

## 单曲输入上限。可在测试或低内存平台缩小，但不可放宽超过 64 MiB。
var max_track_bytes: int = MAX_TRACK_BYTES:
	set(value):
		max_track_bytes = clampi(value, 1, MAX_TRACK_BYTES)


# --- 私有变量 ---

var _content_catalog: ProjectContentCatalogUtility = null
var _audio: GFAudioUtility = null
var _background_work: GFBackgroundWorkUtility = null
var _signals: GFSignalUtility = null
var _clock: GameClockUtility = null

var _track_keys: PackedStringArray = PackedStringArray()
var _track_type_hints: Dictionary = {}
var _play_queue: PackedStringArray = PackedStringArray()
var _queue_cursor: int = 0
var _shuffle_cycle: int = 0
var _session_nonce: int = 0
var _load_generation: int = 0
var _load_serial: int = 0
var _pending_load_task: GFBackgroundWorkTask = null
var _pending_track_key: StringName = &""
var _pending_track_path: String = ""
var _pending_track_type_hint: String = ""
var _current_track_key: StringName = &""
var _unavailable_track_keys: Dictionary = {}
var _disposing: bool = false


# --- GF 生命周期方法 ---

func init() -> void:
	_disposing = false
	_track_keys.clear()
	_track_type_hints.clear()
	_play_queue.clear()
	_queue_cursor = 0
	_shuffle_cycle = 0
	_session_nonce = 0
	_load_generation = 0
	_load_serial = 0
	_pending_load_task = null
	_pending_track_key = &""
	_pending_track_path = ""
	_pending_track_type_hint = ""
	_current_track_key = &""
	_unavailable_track_keys.clear()


func get_required_utilities() -> Array[Script]:
	return [
		ProjectContentCatalogUtility,
		GFAudioUtility,
		GFBackgroundWorkUtility,
		GFSignalUtility,
		GameClockUtility,
	]


func ready() -> void:
	_content_catalog = _resolve_content_catalog()
	_audio = _resolve_audio_utility()
	_background_work = _resolve_background_work_utility()
	_signals = _resolve_signal_utility()
	_clock = _resolve_clock_utility()
	_session_nonce = _clock.get_tick_msec() if is_instance_valid(_clock) else 0
	_connect_runtime_signals()
	var _available_count: int = refresh_playlist()
	if auto_play_on_ready:
		var _started: bool = start_if_available()


func dispose() -> void:
	_disposing = true
	_load_generation += 1
	_cancel_pending_load()
	if is_instance_valid(_signals):
		_signals.disconnect_owner(self)
	if (
		is_instance_valid(_audio)
		and _current_track_key != &""
		and _audio.get_current_bgm_key() == String(_current_track_key)
	):
		_audio.stop_bgm(minf(crossfade_seconds, 0.2))
	_track_keys.clear()
	_track_type_hints.clear()
	_play_queue.clear()
	_queue_cursor = 0
	_pending_track_key = &""
	_pending_track_path = ""
	_pending_track_type_hint = ""
	_current_track_key = &""
	_unavailable_track_keys.clear()


func release_dependencies() -> void:
	_content_catalog = null
	_audio = null
	_background_work = null
	_signals = null
	_clock = null
	super.release_dependencies()


# --- 公共方法 ---

## 从 GF 内容包目录重建可用曲目列表，不加载音频文件。
## @return 当前可用稳定资源键数量。
func refresh_playlist() -> int:
	var discovered_keys: PackedStringArray = _discover_track_keys()
	_load_generation += 1
	_cancel_pending_load()
	var previous_current: StringName = _current_track_key
	var playlist_changed_value: bool = discovered_keys != _track_keys
	_track_keys = discovered_keys
	_unavailable_track_keys.clear()
	_reset_play_queue()
	if previous_current != &"" and not _track_keys.has(String(previous_current)):
		if (
			is_instance_valid(_audio)
			and _audio.get_current_bgm_key() == String(previous_current)
		):
			_audio.stop_bgm(minf(crossfade_seconds, 0.2))
		_current_track_key = &""
	if playlist_changed_value:
		playlist_changed.emit(_track_keys.duplicate())
	return _track_keys.size()


## 在没有其他 BGM 会话时请求播放下一首可用曲目。
## @return 已经拥有当前会话，或成功提交读取请求时返回 true。
func start_if_available() -> bool:
	if (
		_disposing
		or _track_keys.is_empty()
		or not is_instance_valid(_audio)
		or not is_instance_valid(_background_work)
		or not is_instance_valid(_content_catalog)
	):
		return false
	if _pending_load_task != null and not _pending_load_task.is_finished():
		return true
	if _audio.is_bgm_playing():
		return (
			_current_track_key != &""
			and _audio.get_current_bgm_key() == String(_current_track_key)
		)
	return _request_next_track_load()


## 获取当前目录中的稳定曲目键副本。
func get_available_track_keys() -> PackedStringArray:
	return _track_keys.duplicate()


## 获取本 Utility 当前拥有的曲目键。
func get_current_track_key() -> StringName:
	return _current_track_key


func get_debug_snapshot() -> Dictionary:
	return {
		"package_id": String(PACKAGE_ID),
		"available_track_keys": _track_keys.duplicate(),
		"available_track_count": _track_keys.size(),
		"current_track_key": String(_current_track_key),
		"pending_track_key": String(_pending_track_key),
		"pending_track_type_hint": _pending_track_type_hint,
		"track_type_hints": _track_type_hints.duplicate(),
		"unavailable_track_keys": _get_unavailable_track_keys(),
		"load_pending": (
			_pending_load_task != null
			and not _pending_load_task.is_finished()
		),
		"shuffle_cycle": _shuffle_cycle,
		"auto_play_on_ready": auto_play_on_ready,
	}


## 为一轮播放创建稳定洗牌顺序。该方法只创建独立 cosmetic RNG，不读取或推进
## GFSeedUtility 的玩法状态。
## @param track_keys: 当前目录中可播放的稳定曲目键。
## @param session_nonce: 仅用于本次播放会话的 cosmetic nonce。
## @param cycle: 播放列表洗牌轮次。
## @param avoid_first: 新一轮首曲需要避开的上一轮末曲。
static func make_shuffle_order(
	track_keys: PackedStringArray,
	session_nonce: int,
	cycle: int,
	avoid_first: StringName = &""
) -> PackedStringArray:
	var result: PackedStringArray = track_keys.duplicate()
	result.sort()
	if result.size() <= 1:
		return result

	var seed_value: int = GFSeedUtility.make_stable_seed([
		_SHUFFLE_NAMESPACE,
		session_nonce,
		cycle,
		"|".join(result),
	])
	var rng: GFDeterministicRandom = GFDeterministicRandom.from_seed(seed_value)
	for index: int in range(result.size() - 1, 0, -1):
		var swap_index: int = rng.next_int_range(0, index)
		if swap_index == index:
			continue
		var swapped_value: String = result[index]
		result[index] = result[swap_index]
		result[swap_index] = swapped_value

	var avoided_text: String = String(avoid_first)
	if not avoided_text.is_empty() and result[0] == avoided_text:
		for index: int in range(1, result.size()):
			if result[index] == avoided_text:
				continue
			var replacement: String = result[index]
			result[index] = result[0]
			result[0] = replacement
			break
	return result


## 判断解析结果是否仍位于受控本地内容包目录，且为 OGG 或兼容的旧版 WAV。
## @param path: GF Resolver 返回的候选资源路径。
## @param type_hint: 非空时同时校验清单类型与文件扩展名一致。
static func is_allowed_local_track_path(path: String, type_hint: String = "") -> bool:
	var normalized: String = path.strip_edges().replace("\\", "/")
	if (
		not normalized.begins_with(CONTENT_ROOT_PREFIX)
		or normalized.contains("/../")
		or normalized.ends_with("/..")
	):
		return false
	var extension: String = normalized.get_extension().to_lower()
	match type_hint:
		RESOURCE_TYPE_HINT:
			return extension == "ogg"
		LEGACY_RESOURCE_TYPE_HINT:
			return extension == "wav"
		"":
			return extension in ["ogg", "wav"]
		_:
			return false


# --- 私有/辅助方法 ---

func _connect_runtime_signals() -> void:
	if (
		not is_instance_valid(_signals)
		or not is_instance_valid(_content_catalog)
		or not is_instance_valid(_audio)
	):
		return
	var _catalog_connection: GFSignalConnection = _signals.connect_signal(
		_content_catalog.catalog_refreshed,
		Callable(self, "_on_catalog_refreshed"),
		self
	)
	var _audio_connection: GFSignalConnection = _signals.connect_signal(
		_audio.bgm_finished,
		Callable(self, "_on_bgm_finished"),
		self
	)


func _discover_track_keys() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	_track_type_hints.clear()
	if not is_instance_valid(_content_catalog):
		return result
	var entries: Array[Dictionary] = _content_catalog.query_resources({
		"package_ids": PackedStringArray([String(PACKAGE_ID)]),
		"required_content_type": "music",
		"key_prefix": RESOURCE_KEY_PREFIX,
		"metadata": {
			"playlist": PLAYLIST_ID,
		},
	})
	for entry: Dictionary in entries:
		var resource_key: StringName = GFVariantData.get_option_string_name(entry, "key")
		var key_text: String = String(resource_key)
		var type_hint: String = GFVariantData.get_option_string(entry, "type_hint")
		if (
			resource_key == &""
			or not key_text.begins_with(RESOURCE_KEY_PREFIX)
			or not SUPPORTED_RESOURCE_TYPE_HINTS.has(type_hint)
		):
			continue
		if result.has(key_text):
			if (
				type_hint == RESOURCE_TYPE_HINT
				and GFVariantData.get_option_string(
					_track_type_hints,
					resource_key
				) == LEGACY_RESOURCE_TYPE_HINT
			):
				_track_type_hints[resource_key] = type_hint
			continue
		var _appended: bool = result.append(key_text)
		_track_type_hints[resource_key] = type_hint
	result.sort()
	return result


func _request_next_track_load() -> bool:
	if _track_keys.is_empty() or _disposing:
		return false
	var remaining_attempts: int = _track_keys.size()
	while remaining_attempts > 0:
		remaining_attempts -= 1
		var track_key: StringName = _take_next_track_key()
		if track_key == &"":
			return false
		if _unavailable_track_keys.has(track_key):
			continue
		var type_hint: String = GFVariantData.get_option_string(
			_track_type_hints,
			track_key
		)
		var track_path: String = _resolve_track_path(track_key, type_hint)
		if not is_allowed_local_track_path(track_path, type_hint):
			_unavailable_track_keys[track_key] = true
			continue
		if _submit_track_load(track_key, track_path, type_hint):
			return true
	return false


func _submit_track_load(
	track_key: StringName,
	track_path: String,
	type_hint: String
) -> bool:
	_load_generation += 1
	_load_serial += 1
	var generation: int = _load_generation
	var worker: RefCounted = _LOAD_WORKER_SCRIPT.new()
	var task: GFBackgroundWorkTask = _background_work.submit_io_work(
		Callable(worker, "run"),
		{
			"path": track_path,
			"resource_key": track_key,
			"generation": generation,
			"max_bytes": max_track_bytes,
			"type_hint": type_hint,
		},
		Callable(self, "_apply_loaded_track"),
		{
			"id": StringName("background-music-load:%d" % _load_serial),
			"priority": -10,
			"metadata": {
				"owner": "GameBackgroundMusicUtility",
				"resource_key": String(track_key),
			},
		}
	)
	if task == null or task.status == GFBackgroundWorkTask.Status.FAILED:
		return false
	_pending_load_task = task
	_pending_track_key = track_key
	_pending_track_path = track_path
	_pending_track_type_hint = type_hint
	return true


func _apply_loaded_track(task: GFBackgroundWorkTask) -> bool:
	if task == null:
		return true
	var result: Dictionary = GFVariantData.as_dictionary(task.result)
	task.result = null
	if task != _pending_load_task:
		return true

	_pending_load_task = null
	var expected_track_key: StringName = _pending_track_key
	var expected_track_path: String = _pending_track_path
	var expected_type_hint: String = _pending_track_type_hint
	_pending_track_key = &""
	_pending_track_path = ""
	_pending_track_type_hint = ""
	var result_generation: int = GFVariantData.get_option_int(result, "generation")
	var result_key: StringName = GFVariantData.get_option_string_name(
		result,
		"resource_key"
	)
	var result_path: String = GFVariantData.get_option_string(result, "path")
	var result_type_hint: String = GFVariantData.get_option_string(
		result,
		"type_hint"
	)
	if (
		_disposing
		or result_generation != _load_generation
		or result_key != expected_track_key
		or result_path != expected_track_path
		or result_type_hint != expected_type_hint
		or not is_allowed_local_track_path(result_path, result_type_hint)
		or not GFVariantData.get_option_bool(result, "loaded", false)
	):
		return _reject_track_and_continue(expected_track_key)

	var bytes_value: Variant = result.get("bytes", PackedByteArray())
	if not bytes_value is PackedByteArray:
		return _reject_track_and_continue(expected_track_key)
	var track_bytes: PackedByteArray = bytes_value
	if track_bytes.is_empty() or track_bytes.size() > max_track_bytes:
		return _reject_track_and_continue(expected_track_key)
	var stream: AudioStream = _make_audio_stream(track_bytes, result_type_hint)
	if stream == null:
		return _reject_track_and_continue(expected_track_key)

	var clip: GFAudioClip = GFAudioClip.new()
	clip.stream = stream
	# stream 非空时 GF 不会把 path 当作文件加载；这里用稳定键作为 BGM history_key，
	# 使自然结束回调、调试历史和本 Utility 的会话所有权保持一致。
	clip.path = String(expected_track_key)
	clip.bus_name = GFAudioUtility.BGM_BUS_NAME
	clip.metadata = {
		"resource_key": String(expected_track_key),
		"package_id": String(PACKAGE_ID),
		"playlist": PLAYLIST_ID,
		"type_hint": result_type_hint,
	}
	_audio.play_bgm_clip(clip, crossfade_seconds)
	if (
		not _audio.is_bgm_playing()
		or _audio.get_current_bgm_key() != String(expected_track_key)
	):
		return _reject_track_and_continue(expected_track_key)
	_current_track_key = expected_track_key
	track_started.emit(expected_track_key)
	return true


func _reject_track_and_continue(track_key: StringName) -> bool:
	if track_key != &"":
		_unavailable_track_keys[track_key] = true
	if _disposing:
		return true
	var _requested: bool = _request_next_track_load()
	# 后台工作 apply 回调的 false 代表框架任务失败；素材不可用已由本 Utility
	# 作为静默降级处理，因此始终完成当前 IO 任务。
	return true


func _resolve_track_path(track_key: StringName, type_hint: String) -> String:
	if not SUPPORTED_RESOURCE_TYPE_HINTS.has(type_hint):
		return ""
	var report: Dictionary = _content_catalog.resolve_resource(
		track_key,
		type_hint,
		{
			# user:// 中的本地 OGG/WAV 没有 Godot 导入产物，ResourceLoader.exists()
			# 必然为 false。这里只让 GF 解析稳定身份和受控路径；文件边界和
			# 清单类型由 is_allowed_local_track_path() 限定，实际存在性与大小
			# 由 IO worker 在打开文件时重新校验。
			"check_exists": false,
		}
	)
	if not GFVariantData.get_option_bool(report, "ok", false):
		return ""
	var metadata: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"metadata"
	)
	if (
		GFVariantData.get_option_string_name(metadata, "content_package_id")
		!= PACKAGE_ID
		or GFVariantData.get_option_string_name(
			metadata,
			"content_package_resource_key"
		) != track_key
	):
		return ""
	var path: String = GFVariantData.get_option_string(
		report,
		"path"
	).strip_edges()
	return path if is_allowed_local_track_path(path, type_hint) else ""


func _make_audio_stream(
	track_bytes: PackedByteArray,
	type_hint: String
) -> AudioStream:
	match type_hint:
		RESOURCE_TYPE_HINT:
			var ogg_stream: AudioStreamOggVorbis = (
				AudioStreamOggVorbis.load_from_buffer(track_bytes)
			)
			if ogg_stream != null:
				ogg_stream.loop = false
			return ogg_stream
		LEGACY_RESOURCE_TYPE_HINT:
			var wav_stream: AudioStreamWAV = AudioStreamWAV.load_from_buffer(
				track_bytes
			)
			if wav_stream != null:
				wav_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
			return wav_stream
		_:
			return null


func _take_next_track_key() -> StringName:
	if _track_keys.is_empty():
		return &""
	if _queue_cursor >= _play_queue.size():
		_play_queue = make_shuffle_order(
			_track_keys,
			_session_nonce,
			_shuffle_cycle,
			_current_track_key
		)
		_shuffle_cycle += 1
		_queue_cursor = 0
	if _play_queue.is_empty():
		return &""
	var result: StringName = StringName(_play_queue[_queue_cursor])
	_queue_cursor += 1
	return result


func _reset_play_queue() -> void:
	_play_queue.clear()
	_queue_cursor = 0
	_shuffle_cycle = 0


func _get_unavailable_track_keys() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for key_value: Variant in _unavailable_track_keys.keys():
		var key_text: String = GFVariantData.to_text(key_value)
		if not key_text.is_empty():
			var _appended: bool = result.append(key_text)
	result.sort()
	return result


func _cancel_pending_load() -> void:
	var task: GFBackgroundWorkTask = _pending_load_task
	_pending_load_task = null
	_pending_track_key = &""
	_pending_track_path = ""
	_pending_track_type_hint = ""
	if (
		task != null
		and not task.is_finished()
		and is_instance_valid(_background_work)
	):
		var _cancelled: bool = _background_work.cancel_work(task.work_id)


func _on_catalog_refreshed(_report: Dictionary) -> void:
	if _disposing:
		return
	var _available_count: int = refresh_playlist()
	if auto_play_on_ready:
		var _started: bool = start_if_available()


func _on_bgm_finished(history_key: String) -> void:
	if (
		_disposing
		or _current_track_key == &""
		or history_key != String(_current_track_key)
	):
		return
	_current_track_key = &""
	var _requested: bool = _request_next_track_load()


func _resolve_content_catalog() -> ProjectContentCatalogUtility:
	var utility_value: Object = get_utility(ProjectContentCatalogUtility)
	if utility_value is ProjectContentCatalogUtility:
		var utility: ProjectContentCatalogUtility = utility_value
		return utility
	return null


func _resolve_audio_utility() -> GFAudioUtility:
	var utility_value: Object = get_utility(GFAudioUtility)
	if utility_value is GFAudioUtility:
		var utility: GFAudioUtility = utility_value
		return utility
	return null


func _resolve_background_work_utility() -> GFBackgroundWorkUtility:
	var utility_value: Object = get_utility(GFBackgroundWorkUtility)
	if utility_value is GFBackgroundWorkUtility:
		var utility: GFBackgroundWorkUtility = utility_value
		return utility
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var utility: GFSignalUtility = utility_value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var utility: GameClockUtility = utility_value
		return utility
	return null
