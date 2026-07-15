## 验证统一玩家数据 SaveGraph 的结构、持久化和事务语义。
extends GutTest


# --- 测试用例 ---

func test_profile_graph_has_three_feature_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var snapshot: Dictionary = save_graph.get_debug_snapshot()
	var health: Dictionary = GFVariantData.get_option_dictionary(snapshot, "graph_health")

	assert_true(save_graph.is_profile_loaded(), "首次运行应完成空档加载决策。")
	assert_true(GFVariantData.get_option_bool(health, "ok"), "玩家数据图结构应通过 GF 健康检查。")
	assert_true(GFVariantData.get_option_int(health, "scope_count") == 4, "根图应包含根 Scope 和三个 Feature 子 Scope。")
	assert_true(GFVariantData.get_option_int(health, "source_count") == 3, "每个 Feature 子 Scope 应有一个严格数据 Source。")
	assert_true(
		GFVariantData.get_option_packed_string_array(snapshot, "section_ids")
		== PackedStringArray(["bookmarks", "progress", "replays"]),
		"诊断应暴露稳定 section 标识。"
	)

	_dispose_setup(setup)


func test_stats_bookmarks_and_replays_persist_in_one_graph_file() -> void:
	var save_dir_name: String = "gut_save_graph_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var save_system: SaveSystem = _get_save_system(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var replay_system: ReplaySystem = _get_replay_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)

	var stats_error: Error = save_system.record_game_result("classic", 4, 2048, 32, 2048, 500, 2048, true)
	var bookmark: BookmarkData = _make_bookmark(600, 512)
	var replay: ReplayData = _make_replay(700, 2048)
	var bookmark_error: Error = bookmark_system.save_bookmark(bookmark)
	var replay_error: Error = replay_system.save_replay(replay)
	assert_true(stats_error == OK, "统计 section 应保存成功。")
	assert_true(bookmark_error == OK, "书签 section 应保存成功。")
	assert_true(replay_error == OK, "回放 section 应保存成功。")
	assert_true(GFUuid.is_valid(bookmark.bookmark_id, 7), "书签应获得稳定 UUID v7。")
	assert_true(GFUuid.is_valid(replay.replay_id, 7), "回放应获得稳定 UUID v7。")
	assert_true(
		storage.list_files("", "save")
		== PackedStringArray([GameSaveGraphUtility.PROFILE_FILE_NAME]),
		"三类玩家数据应只落到一个原子 SaveGraph 文件。"
	)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_save_system: SaveSystem = _get_save_system(reloaded)
	var reloaded_bookmarks: BookmarkSystem = _get_bookmark_system(reloaded)
	var reloaded_replays: ReplaySystem = _get_replay_system(reloaded)
	assert_true(
		reloaded_graph.is_profile_loaded(),
		"重载事务应成功：%s" % _describe_load_failure(reloaded_graph)
	)
	assert_true(reloaded_save_system.get_high_score("classic", 4) == 2048, "重载后应保留统计。")
	var bookmarks: Array[BookmarkData] = reloaded_bookmarks.load_bookmarks()
	var replays: Array[ReplayData] = reloaded_replays.load_replays()
	assert_true(bookmarks.size() == 1, "重载后应保留书签目录。")
	assert_true(replays.size() == 1, "重载后应保留回放目录。")
	if bookmarks.size() == 1 and replays.size() == 1:
		assert_true(bookmarks[0].bookmark_id == bookmark.bookmark_id, "书签稳定 ID 应跨重载保留。")
		assert_true(replays[0].replay_id == replay.replay_id, "回放稳定 ID 应跨重载保留。")
		assert_true(bookmarks[0].score == 512, "书签业务数据应完整恢复。")
		assert_true(replays[0].final_score == 2048, "回放业务数据应完整恢复。")

		var delete_bookmark_error: Error = reloaded_bookmarks.delete_bookmark(bookmarks[0].bookmark_id)
		var delete_replay_error: Error = reloaded_replays.delete_replay(replays[0].replay_id)
		assert_true(delete_bookmark_error == OK, "应按稳定 ID 删除书签。")
		assert_true(delete_replay_error == OK, "应按稳定 ID 删除回放。")
		assert_true(reloaded_bookmarks.load_bookmarks().is_empty(), "书签删除应更新统一图。")
		assert_true(reloaded_replays.load_replays().is_empty(), "回放删除应更新统一图。")

	_dispose_setup(reloaded)


func test_late_section_failure_rolls_back_earlier_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var save_system: SaveSystem = _get_save_system(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)

	var score_error: Error = save_system.set_high_score("classic", 4, 128)
	var bookmark_error: Error = bookmark_system.save_bookmark(_make_bookmark(800, 64))
	assert_true(score_error == OK, "回滚测试前统计应保存成功。")
	assert_true(bookmark_error == OK, "回滚测试前书签应保存成功。")
	var payload: Dictionary = save_graph.preview_profile_payload()
	var progress_source: Dictionary = _get_section_source(payload, GameSaveGraphUtility.PROGRESS_SECTION_ID)
	progress_source["data"] = {
		"section_id": "progress",
		"schema_version": GameStatsSaveData.SCHEMA_VERSION,
		"data": {
			"stats": {
				"classic": {
					"4x4": {
						"best_score": 4096,
					},
				},
			},
		},
	}
	var bookmarks_source: Dictionary = _get_section_source(payload, GameSaveGraphUtility.BOOKMARKS_SECTION_ID)
	bookmarks_source["data"] = {
		"section_id": "bookmarks",
		"schema_version": BookmarkCatalogSaveData.SCHEMA_VERSION,
		"data": {
			"items": [],
		},
	}
	var replays_source: Dictionary = _get_section_source(payload, GameSaveGraphUtility.REPLAYS_SECTION_ID)
	replays_source["data"] = {
		"section_id": "replays",
		"schema_version": ReplayCatalogSaveData.SCHEMA_VERSION,
		"data": "invalid_late_section",
	}
	var raw_save_error: Error = storage.save_data(GameSaveGraphUtility.PROFILE_FILE_NAME, payload)
	assert_true(raw_save_error == OK, "应能写入故障注入载荷。")

	var load_error: Error = save_graph.load_profile()
	assert_true(load_error == ERR_INVALID_DATA, "后期 section 业务校验失败时整张图加载应失败。")
	assert_true(save_system.get_high_score("classic", 4) == 128, "progress 的先行应用必须回滚。")
	assert_true(bookmark_system.load_bookmarks().size() == 1, "bookmarks 的先行应用必须回滚。")
	var load_snapshot: Dictionary = GFVariantData.get_option_dictionary(save_graph.get_debug_snapshot(), "last_load")
	assert_false(GFVariantData.get_option_bool(load_snapshot, "ok"), "诊断应记录失败事务。")

	_dispose_setup(setup)


func test_profile_schema_mismatch_is_rejected_without_fallback() -> void:
	var save_dir_name: String = "gut_save_graph_schema_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_persistence_architecture(save_dir_name)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var payload: Dictionary = save_graph.preview_profile_payload()
	var metadata: Dictionary = GFVariantData.as_dictionary(GFVariantData.get_option_value(payload, "metadata"))
	metadata["schema_version"] = GameSaveGraphUtility.PROFILE_SCHEMA_VERSION + 1
	var seed_error: Error = storage.save_data(GameSaveGraphUtility.PROFILE_FILE_NAME, payload)
	assert_true(seed_error == OK, "应能写入 schema 故障载荷。")
	_dispose_setup(setup, false)

	var reloaded: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	assert_false(reloaded_graph.is_profile_loaded(), "不匹配 schema 不应进入运行时模型。")
	assert_true(_get_save_system(reloaded).get_high_score("classic", 4) == 0, "不得保留旧 schema 双读回退。")
	assert_true(_get_bookmark_system(reloaded).load_bookmarks().is_empty(), "拒绝载荷时书签默认值应保持为空。")

	_dispose_setup(reloaded)


func test_save_dependency_failure_rolls_back_replaced_section() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var save_system: SaveSystem = _get_save_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var initial_error: Error = save_system.set_high_score("classic", 4, 128)
	assert_true(initial_error == OK, "故障注入前的统计应保存成功。")

	var cleanup_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
	assert_true(cleanup_error == OK, "故障注入前应清理测试玩家数据文件。")
	architecture.unregister_utility(GFStorageUtility)
	var failed_error: Error = save_system.set_high_score("classic", 4, 4096)
	assert_true(failed_error == ERR_UNCONFIGURED, "SaveGraph 缺少存储依赖时应返回明确错误。")
	assert_true(save_system.get_high_score("classic", 4) == 128, "写入失败必须恢复 progress section 内存快照。")

	_dispose_setup(setup, false)


# --- 私有/辅助方法 ---

func _create_persistence_architecture(
	save_dir_name: String = "",
	include_systems: bool = false
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var framework_save_graph: GFSaveGraphUtility = GFSaveGraphUtility.new()
	var save_graph: GameSaveGraphUtility = _make_game_save_graph()
	var save_system: SaveSystem = null
	var bookmark_system: BookmarkSystem = null
	var replay_system: ReplaySystem = null

	storage.save_dir_name = save_dir_name if not save_dir_name.is_empty() else "gut_save_graph_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, framework_save_graph)
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, GFCommandHistoryUtility.new())
	if include_systems:
		save_system = SaveSystem.new()
		bookmark_system = BookmarkSystem.new()
		replay_system = ReplaySystem.new()
		await architecture.register_system(SaveSystem, save_system)
		await architecture.register_system(BookmarkSystem, bookmark_system)
		await architecture.register_system(ReplaySystem, replay_system)
	await architecture.init()

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"save_system": save_system,
		"bookmark_system": bookmark_system,
		"replay_system": replay_system,
	}


func _make_game_save_graph() -> GameSaveGraphUtility:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var progress_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GFSaveScope.Phase.EARLY
	)
	var bookmarks_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		BookmarkCatalogSaveData.new(),
		GFSaveScope.Phase.NORMAL
	)
	var replays_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		ReplayCatalogSaveData.new(),
		GFSaveScope.Phase.LATE
	)
	assert_true(progress_registered and bookmarks_registered and replays_registered, "测试 SaveGraph section 应完整注册。")
	return save_graph


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	bookmark.score = score
	return bookmark


func _make_replay(timestamp: int, final_score: int) -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	replay.timestamp = timestamp
	replay.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	replay.grid_size = 4
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	return replay


func _get_section_source(payload: Dictionary, section_id: StringName) -> Dictionary:
	var scopes: Dictionary = GFVariantData.as_dictionary(GFVariantData.get_option_value(payload, "scopes"))
	var section_payload: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(scopes, String(section_id))
	)
	var sources: Dictionary = GFVariantData.as_dictionary(GFVariantData.get_option_value(section_payload, "sources"))
	return GFVariantData.as_dictionary(GFVariantData.get_option_value(sources, "state"))


func _describe_load_failure(save_graph: GameSaveGraphUtility) -> String:
	var snapshot: Dictionary = save_graph.get_debug_snapshot()
	var load_result: Dictionary = GFVariantData.get_option_dictionary(snapshot, "last_load")
	return JSON.stringify({
		"error_code": GFVariantData.get_option_int(load_result, "error_code", FAILED),
		"error": GFVariantData.get_option_string(load_result, "error"),
		"errors": GFVariantData.get_option_array(load_result, "errors"),
	})


func _dispose_setup(setup: Dictionary, delete_profile: bool = true) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	if delete_profile:
		var delete_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
		assert_true(delete_error == OK or delete_error == ERR_FILE_NOT_FOUND, "测试玩家数据清理应返回可预期结果。")
	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = GFVariantData.get_option_value(setup, "architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_storage(setup: Dictionary) -> GFStorageUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "storage")
	if value is GFStorageUtility:
		var storage: GFStorageUtility = value
		return storage
	assert_true(false, "测试 setup 缺少 GFStorageUtility。")
	return GFStorageUtility.new()


func _get_save_graph(setup: Dictionary) -> GameSaveGraphUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "save_graph")
	if value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = value
		return save_graph
	assert_true(false, "测试 setup 缺少 GameSaveGraphUtility。")
	return GameSaveGraphUtility.new()


func _get_save_system(setup: Dictionary) -> SaveSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "save_system")
	if value is SaveSystem:
		var save_system: SaveSystem = value
		return save_system
	assert_true(false, "测试 setup 缺少 SaveSystem。")
	return SaveSystem.new()


func _get_bookmark_system(setup: Dictionary) -> BookmarkSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "bookmark_system")
	if value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = value
		return bookmark_system
	assert_true(false, "测试 setup 缺少 BookmarkSystem。")
	return BookmarkSystem.new()


func _get_replay_system(setup: Dictionary) -> ReplaySystem:
	var value: Variant = GFVariantData.get_option_value(setup, "replay_system")
	if value is ReplaySystem:
		var replay_system: ReplaySystem = value
		return replay_system
	assert_true(false, "测试 setup 缺少 ReplaySystem。")
	return ReplaySystem.new()
