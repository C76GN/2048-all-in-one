## 验证本地授权 BGM 内容包的发现、隔离洗牌、异步读取与静默降级。
extends GutTest


const _TRACK_A: StringName = &"asset.audio.music.puzzle_music_2.attempt"
const _TRACK_B: StringName = &"asset.audio.music.puzzle_music_2.blue"
const _LOAD_WORKER_SCRIPT: GDScript = preload(
	"res://features/themes/scripts/workers/puzzle_music_file_read_worker.gd"
)


func test_shuffle_is_stable_complete_and_avoids_cycle_boundary_repeat() -> void:
	var keys: PackedStringArray = PackedStringArray([
		String(_TRACK_A),
		String(_TRACK_B),
		"asset.audio.music.puzzle_music_2.fill",
	])
	var first: PackedStringArray = GameBackgroundMusicUtility.make_shuffle_order(
		keys,
		4242,
		3,
		_TRACK_A
	)
	var second: PackedStringArray = GameBackgroundMusicUtility.make_shuffle_order(
		keys,
		4242,
		3,
		_TRACK_A
	)

	assert_true(first == second, "相同 cosmetic nonce 与轮次应得到稳定洗牌。")
	assert_true(first.size() == keys.size(), "洗牌不得丢失曲目。")
	assert_ne(first[0], String(_TRACK_A), "新一轮首曲不得重复上一轮末曲。")
	for key: String in keys:
		assert_true(first.has(key), "洗牌结果应保留曲目：%s。" % key)


func test_local_track_boundary_rejects_project_external_and_traversal_paths() -> void:
	assert_true(
		GameBackgroundMusicUtility.is_allowed_local_track_path(
			"user://content_packages/puzzle_music_2/audio/Attempt.wav"
		),
		"受控 user:// 内容包 WAV 应可播放。"
	)
	assert_false(
		GameBackgroundMusicUtility.is_allowed_local_track_path(
			"res://features/asset_library/resources/audio/Attempt.wav"
		),
		"本地付费曲目不得伪装成仓库资源。"
	)
	assert_false(
		GameBackgroundMusicUtility.is_allowed_local_track_path(
			"user://content_packages/puzzle_music_2/../outside/Attempt.wav"
		),
		"路径穿越必须被拒绝。"
	)
	assert_false(
		GameBackgroundMusicUtility.is_allowed_local_track_path(
			"user://content_packages/puzzle_music_2/audio/Attempt.mp3"
		),
		"运行时只接受安装器声明的 WAV 格式。"
	)
	assert_false(
		GameBackgroundMusicUtility.is_allowed_local_track_path(
			"user://content_packages/another_pack/audio/Attempt.wav"
		),
		"同一 user:// 根下的其他内容包不得冒充已购音乐包。"
	)


func test_missing_local_package_degrades_silently() -> void:
	var setup: Dictionary = await _create_architecture([])
	var music: GameBackgroundMusicUtility = _get_music(setup)
	var audio: _FakeAudioUtility = _get_audio(setup)

	assert_true(music.get_available_track_keys().size() == 0, "空目录不应伪造曲目。")
	assert_false(music.start_if_available(), "缺少本地包时应静默保持无 BGM。")
	assert_true(audio.played_track_keys.size() == 0, "缺少本地包时不得触发播放。")

	_dispose_architecture(setup)


func test_stable_keys_load_in_background_and_advance_without_gameplay_rng() -> void:
	var setup: Dictionary = await _create_architecture([
		_make_entry(_TRACK_A),
		_make_entry(_TRACK_B),
	])
	var music: GameBackgroundMusicUtility = _get_music(setup)
	var audio: _FakeAudioUtility = _get_audio(setup)
	var background_work: _FakeBackgroundWorkUtility = _get_background_work(setup)
	var catalog: _FakeContentCatalogUtility = _get_catalog(setup)
	var wav_bytes: PackedByteArray = _make_test_wav_bytes()

	assert_true(music.get_available_track_keys().size() == 2, "应按稳定键发现两首曲目。")
	assert_true(music.start_if_available(), "有曲目时应提交后台读取。")
	assert_false(
		GFVariantData.get_option_bool(
			catalog.last_resolve_options,
			"check_exists",
			true
		),
		"user:// 原始 WAV 应让 GF 只解析稳定身份和路径，不能要求 ResourceLoader 导入产物。"
	)
	assert_true(background_work.has_pending_work(), "WAV IO 必须交给后台工作。")
	assert_true(
		GFVariantData.get_option_int(
			music.get_debug_snapshot(),
			"retained_load_worker_count"
		) == 1,
		"后台 Callable 的 RefCounted worker 必须由播放 Utility 强持有到任务终态。"
	)
	background_work.complete_pending(wav_bytes)

	assert_true(audio.played_track_keys.size() == 1, "后台完成后应委托 GFAudioUtility 播放。")
	assert_true(
		GFVariantData.get_option_int(
			music.get_debug_snapshot(),
			"retained_load_worker_count"
		) == 0,
		"后台任务应用完成后应释放 worker 强引用。"
	)
	assert_true(audio.last_stream is AudioStreamWAV, "主线程应把 WAV 字节构建为 AudioStreamWAV。")
	var first_key: String = audio.played_track_keys[0]
	assert_true(
		first_key == String(_TRACK_A) or first_key == String(_TRACK_B),
		"播放身份必须保持为内容包稳定资源键。"
	)

	audio.finish_current_track()
	assert_true(background_work.has_pending_work(), "自然结束后应异步请求下一首。")
	background_work.complete_pending(wav_bytes)
	assert_true(audio.played_track_keys.size() == 2, "自然结束后应推进播放列表。")
	assert_ne(
		audio.played_track_keys[1],
		first_key,
		"同一轮存在多首曲目时不得立即重复。"
	)

	_dispose_architecture(setup)


func test_oversized_track_is_quarantined_without_playback_or_retry_loop() -> void:
	var setup: Dictionary = await _create_architecture([
		_make_entry(_TRACK_A),
	])
	var music: GameBackgroundMusicUtility = _get_music(setup)
	var audio: _FakeAudioUtility = _get_audio(setup)
	var background_work: _FakeBackgroundWorkUtility = _get_background_work(setup)
	music.max_track_bytes = 64
	var oversized_bytes: PackedByteArray = PackedByteArray()
	var _resize_result: Error = oversized_bytes.resize(65) as Error

	assert_true(music.start_if_available(), "曲目应先进入受限后台读取。")
	background_work.complete_pending(oversized_bytes)

	assert_true(audio.played_track_keys.size() == 0, "超限曲目不得进入 GFAudioUtility。")
	assert_false(
		background_work.has_pending_work(),
		"同一目录 revision 内不得反复读取已确认超限的曲目。"
	)
	var snapshot: Dictionary = music.get_debug_snapshot()
	var unavailable: PackedStringArray = GFVariantData.get_option_packed_string_array(
		snapshot,
		"unavailable_track_keys"
	)
	assert_true(
		unavailable.has(String(_TRACK_A)),
		"超限曲目应在当前目录 revision 内被隔离。"
	)

	_dispose_architecture(setup)


func test_worker_checks_file_length_before_reading_oversized_wav() -> void:
	var test_root: String = (
		"user://content_packages/puzzle_music_2/gut_oversized_%d"
		% get_instance_id()
	)
	var absolute_root: String = ProjectSettings.globalize_path(test_root)
	var make_dir_error: Error = (
		DirAccess.make_dir_recursive_absolute(absolute_root) as Error
	)
	assert_true(make_dir_error == OK, "应创建隔离的 worker 测试目录。")
	var track_path: String = test_root.path_join("Oversized.wav")
	var absolute_track_path: String = ProjectSettings.globalize_path(track_path)
	var file: FileAccess = FileAccess.open(track_path, FileAccess.WRITE)
	assert_not_null(file, "应创建隔离的 worker 测试文件。")
	if file == null:
		return
	var bytes: PackedByteArray = PackedByteArray()
	var _resize_result: Error = bytes.resize(65) as Error
	var _stored: bool = file.store_buffer(bytes)
	file.close()

	var worker: RefCounted = _LOAD_WORKER_SCRIPT.new()
	var result: Dictionary = GFVariantData.as_dictionary(worker.call("run", {
		"path": track_path,
		"resource_key": _TRACK_A,
		"generation": 7,
		"max_bytes": 64,
	}))
	assert_false(
		GFVariantData.get_option_bool(result, "loaded", true),
		"worker 应在读取 payload 前拒绝超限文件。"
	)
	assert_true(
		GFVariantData.get_option_int(result, "byte_count") == 65,
		"拒绝结果应保留实际文件长度证据。"
	)

	var remove_file_error: Error = (
		DirAccess.remove_absolute(absolute_track_path) as Error
	)
	var remove_dir_error: Error = (
		DirAccess.remove_absolute(absolute_root) as Error
	)
	assert_true(remove_file_error == OK, "应清理隔离的 worker 测试文件。")
	assert_true(remove_dir_error == OK, "应清理隔离的 worker 测试目录。")


# --- 私有/辅助方法 ---

func _create_architecture(entries: Array[Dictionary]) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var catalog: _FakeContentCatalogUtility = _FakeContentCatalogUtility.new()
	catalog.entries = _copy_entries(entries)
	for entry: Dictionary in entries:
		var key: StringName = GFVariantData.get_option_string_name(entry, "key")
		var file_name: String = "%s.wav" % String(key).get_slice(".", 4).capitalize()
		catalog.paths[key] = (
			"user://content_packages/puzzle_music_2/audio/%s" % file_name
		)
	var audio: _FakeAudioUtility = _FakeAudioUtility.new()
	var background_work: _FakeBackgroundWorkUtility = _FakeBackgroundWorkUtility.new()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var clock: GameClockUtility = GameClockUtility.new()
	var music: GameBackgroundMusicUtility = GameBackgroundMusicUtility.new()
	music.auto_play_on_ready = false

	await architecture.register_utility(ProjectContentCatalogUtility, catalog)
	await architecture.register_utility(GFAudioUtility, audio)
	await architecture.register_utility(GFBackgroundWorkUtility, background_work)
	await architecture.register_utility(GFSignalUtility, signal_utility)
	await architecture.register_utility(GameClockUtility, clock)
	await architecture.register_utility(GameBackgroundMusicUtility, music)
	await architecture.init()
	return {
		"architecture": architecture,
		"catalog": catalog,
		"audio": audio,
		"background_work": background_work,
		"music": music,
	}


func _dispose_architecture(setup: Dictionary) -> void:
	var architecture_value: Variant = setup.get("architecture")
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()


func _make_entry(key: StringName) -> Dictionary:
	return {
		"key": key,
		"type_hint": GameBackgroundMusicUtility.RESOURCE_TYPE_HINT,
		"metadata": {
			"playlist": GameBackgroundMusicUtility.PLAYLIST_ID,
		},
	}


func _copy_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		result.append(entry.duplicate(true))
	return result


func _make_test_wav_bytes() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray([
		82, 73, 70, 70, 68, 3, 0, 0,
		87, 65, 86, 69, 102, 109, 116, 32,
		16, 0, 0, 0, 1, 0, 1, 0,
		64, 31, 0, 0, 64, 31, 0, 0,
		1, 0, 8, 0, 100, 97, 116, 97,
		32, 3, 0, 0,
	])
	var _resize_result: Error = bytes.resize(844) as Error
	for index: int in range(44, bytes.size()):
		bytes[index] = 128
	return bytes


func _get_music(setup: Dictionary) -> GameBackgroundMusicUtility:
	var value: Variant = setup.get("music")
	if value is GameBackgroundMusicUtility:
		var utility: GameBackgroundMusicUtility = value
		return utility
	assert_true(false, "测试 setup 缺少 GameBackgroundMusicUtility。")
	return GameBackgroundMusicUtility.new()


func _get_catalog(setup: Dictionary) -> _FakeContentCatalogUtility:
	var value: Variant = setup.get("catalog")
	if value is _FakeContentCatalogUtility:
		var utility: _FakeContentCatalogUtility = value
		return utility
	assert_true(false, "测试 setup 缺少 FakeContentCatalogUtility。")
	return _FakeContentCatalogUtility.new()


func _get_audio(setup: Dictionary) -> _FakeAudioUtility:
	var value: Variant = setup.get("audio")
	if value is _FakeAudioUtility:
		var utility: _FakeAudioUtility = value
		return utility
	assert_true(false, "测试 setup 缺少 FakeAudioUtility。")
	return _FakeAudioUtility.new()


func _get_background_work(setup: Dictionary) -> _FakeBackgroundWorkUtility:
	var value: Variant = setup.get("background_work")
	if value is _FakeBackgroundWorkUtility:
		var utility: _FakeBackgroundWorkUtility = value
		return utility
	assert_true(false, "测试 setup 缺少 FakeBackgroundWorkUtility。")
	return _FakeBackgroundWorkUtility.new()


# --- 内部类 ---

class _FakeContentCatalogUtility extends ProjectContentCatalogUtility:
	var entries: Array[Dictionary] = []
	var paths: Dictionary = {}
	var last_resolve_options: Dictionary = {}


	func get_required_utilities() -> Array[Script]:
		return []


	func ready() -> void:
		pass


	## @param _options: 测试替身忽略的查询选项。
	func query_resources(_options: Dictionary = {}) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for entry: Dictionary in entries:
			result.append(entry.duplicate(true))
		return result


	## @param resource_key: 要解析的稳定资源键。
	## @param _type_hint: 测试替身忽略的类型提示。
	## @param _options: 测试替身忽略的解析选项。
	func resolve_resource(
		resource_key: StringName,
		_type_hint: String = "",
		_options: Dictionary = {}
	) -> Dictionary:
		last_resolve_options = _options.duplicate(true)
		var path: String = GFVariantData.get_option_string(paths, resource_key)
		return {
			"ok": not path.is_empty(),
			"key": resource_key,
			"path": path,
			"metadata": {
				"content_package_id": GameBackgroundMusicUtility.PACKAGE_ID,
				"content_package_resource_key": resource_key,
			},
		}


class _FakeAudioUtility extends GFAudioUtility:
	var played_track_keys: PackedStringArray = PackedStringArray()
	var current_key: String = ""
	var playing: bool = false
	var last_stream: AudioStream = null


	func init() -> void:
		pass


	func dispose() -> void:
		played_track_keys.clear()
		current_key = ""
		playing = false
		last_stream = null


	## @param clip: 要记录的 BGM clip。
	## @param _crossfade_seconds: 测试替身忽略的淡变时长。
	func play_bgm_clip(
		clip: GFAudioClip,
		_crossfade_seconds: float = -1.0
	) -> void:
		if clip == null:
			return
		current_key = clip.path
		playing = true
		last_stream = clip.stream
		var _appended: bool = played_track_keys.append(current_key)


	## @param _fade_seconds: 测试替身忽略的停止淡变时长。
	func stop_bgm(_fade_seconds: float = 0.0) -> void:
		current_key = ""
		playing = false


	func is_bgm_playing() -> bool:
		return playing


	func get_current_bgm_key() -> String:
		return current_key


	func finish_current_track() -> void:
		var finished_key: String = current_key
		current_key = ""
		playing = false
		bgm_finished.emit(finished_key)


class _FakeBackgroundWorkUtility extends GFBackgroundWorkUtility:
	var _pending_task: GFBackgroundWorkTask = null


	func init() -> void:
		_pending_task = null


	func dispose() -> void:
		_pending_task = null


	## @param worker: 后台读取 Callable。
	## @param input_data: 传给 worker 的纯数据。
	## @param apply_callback: 主线程应用 Callable。
	## @param options: 任务 ID、优先级和 metadata。
	func submit_io_work(
		worker: Callable,
		input_data: Variant = null,
		apply_callback: Callable = Callable(),
		options: Dictionary = {}
	) -> GFBackgroundWorkTask:
		var task: GFBackgroundWorkTask = GFBackgroundWorkTask.new()
		task.kind = GFBackgroundWorkTask.Kind.IO
		task.work_id = GFVariantData.get_option_string_name(
			options,
			"id",
			&"fake-background-music-load"
		)
		task.status = GFBackgroundWorkTask.Status.QUEUED
		task.input_data = GFVariantData.duplicate_variant(input_data)
		task.set_internal_callbacks(worker, apply_callback)
		_pending_task = task
		return task


	## @param work_id: 要取消的测试任务 ID。
	func cancel_work(work_id: StringName) -> bool:
		if _pending_task == null or _pending_task.work_id != work_id:
			return false
		_pending_task.status = GFBackgroundWorkTask.Status.CANCELLED
		work_cancelled.emit(_pending_task)
		_pending_task = null
		return true


	func has_pending_work() -> bool:
		return _pending_task != null and not _pending_task.is_finished()


	## @param bytes: 模拟 worker 返回的 WAV 字节。
	func complete_pending(bytes: PackedByteArray) -> void:
		if _pending_task == null:
			return
		var task: GFBackgroundWorkTask = _pending_task
		var payload: Dictionary = GFVariantData.as_dictionary(task.input_data)
		task.status = GFBackgroundWorkTask.Status.APPLYING
		task.result = {
			"loaded": true,
			"path": GFVariantData.get_option_string(payload, "path"),
			"resource_key": GFVariantData.get_option_string_name(
				payload,
				"resource_key"
			),
			"generation": GFVariantData.get_option_int(payload, "generation"),
			"bytes": bytes.duplicate(),
		}
		var apply_callback: Callable = task.get_apply_callback()
		if apply_callback.is_valid():
			task.apply_result = apply_callback.call(task)
		task.status = GFBackgroundWorkTask.Status.COMPLETED
		work_completed.emit(task)
		_pending_task = null
