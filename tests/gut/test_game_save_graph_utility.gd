## 验证统一玩家数据 SaveGraph 的结构、持久化和事务语义。
extends GutTest


# --- 常量 ---

const _BOARD_KEY: String = "board.rectangle.4x4@test"
const _BOARD_SIZE: Vector2i = Vector2i(4, 4)
const _TEST_PLATFORM_STUB_SCRIPT: Script = preload(
	"res://tests/gut/fixtures/test_game_platform_utility_stub.gd"
)


# --- 测试用例 ---

func test_profile_graph_has_seven_feature_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var snapshot: Dictionary = save_graph.get_debug_snapshot()
	var health: Dictionary = GFVariantData.get_option_dictionary(snapshot, "graph_health")
	var document_inspection: Dictionary = GFSaveDocument.inspect_dict(
		save_graph.preview_profile_payload()
	)

	assert_true(save_graph.is_profile_loaded(), "首次运行应完成空档加载决策。")
	assert_true(GFVariantData.get_option_bool(health, "ok"), "玩家数据图结构应通过 GF 健康检查。")
	assert_true(GFVariantData.get_option_int(health, "scope_count") == 8, "根图应包含根 Scope 和七个 Feature 子 Scope。")
	assert_true(GFVariantData.get_option_int(health, "source_count") == 7, "每个 Feature 子 Scope 应有一个严格数据 Source。")
	assert_true(
		GFVariantData.get_option_bool(document_inspection, "ok"),
		"Profile 预览必须是规范 GFSaveDocument，禁止保存裸 SaveGraph 字典。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(snapshot, "section_ids")
		== PackedStringArray(["achievements", "bookmarks", "custom_boards", "discoveries", "limited_levels", "progress", "replays"]),
		"诊断应暴露稳定 section 标识。"
	)

	_dispose_setup(setup)


func test_high_frequency_sections_coalesce_into_one_async_profile_write() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var completion_counter: Dictionary = {"value": 0}
	var _completion_connection: int = save_graph.profile_save_completed.connect(
		func(_error: Error) -> void:
			completion_counter["value"] = GFVariantData.get_option_int(
				completion_counter,
				"value"
			) + 1
	)

	var progress_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)
	var discovery_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		{"tile_compositions": [], "board_topologies": []}
	)
	var queued_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(progress_error == OK and discovery_error == OK, "合法高频 section 应先原子更新内存图。")
	assert_true(GFVariantData.get_option_bool(queued_snapshot, "save_pending"), "同帧更新后应只留下一个待写 Profile。")
	assert_false(GFVariantData.get_option_bool(queued_snapshot, "save_in_flight"), "静默窗口内不应立即占用输入帧写盘。")

	save_graph.tick(1.0)
	storage.wait_for_async_tasks()
	var completed_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(
		GFVariantData.get_option_int(completion_counter, "value") == 1,
		"多个高频 section 必须合并成一次 GFStorageUtility 异步事务。"
	)
	assert_false(GFVariantData.get_option_bool(completed_snapshot, "save_pending"), "异步写入完成后不应残留待写状态。")
	assert_false(GFVariantData.get_option_bool(completed_snapshot, "save_in_flight"), "异步写入完成后不应残留在途状态。")

	_dispose_setup(setup)


func test_synchronous_async_completion_does_not_leave_save_in_flight() -> void:
	var storage: _ScriptedStorage = _ScriptedStorage.new()
	storage.async_completion_errors = [OK]
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)

	var queue_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)
	save_graph.tick(1.0)
	var snapshot: Dictionary = save_graph.get_debug_snapshot()

	assert_true(queue_error == OK, "同步完成回归夹具应成功排队。")
	assert_true(storage.async_save_call_count == 1, "静默窗口后应只启动一次异步保存。")
	assert_false(
		GFVariantData.get_option_bool(snapshot, "save_pending"),
		"save_data_async 内同步完成后不应残留待写状态。"
	)
	assert_false(
		GFVariantData.get_option_bool(snapshot, "save_in_flight"),
		"同步完成回调不得被调用后的 in-flight 赋值覆盖。"
	)

	_dispose_setup(setup)


func test_synchronous_thread_start_failure_retries_without_stuck_in_flight() -> void:
	var storage: _ScriptedStorage = _ScriptedStorage.new()
	# 等价于 Web 单线程下 GFStorageUtility 在线程启动失败时同步发出完成信号，
	# 但公共 save_data_async() 仍返回 OK 的路径。
	storage.async_completion_errors = [ERR_CANT_CREATE, OK]
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)

	var queue_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)
	save_graph.tick(1.0)
	var failed_snapshot: Dictionary = save_graph.get_debug_snapshot()

	assert_true(queue_error == OK, "线程失败回归夹具应成功排队。")
	assert_true(storage.async_save_call_count == 1, "第一次异步启动应到达存储边界。")
	assert_true(
		GFVariantData.get_option_bool(failed_snapshot, "save_pending"),
		"线程启动失败必须保留最新 Profile 待重试。"
	)
	assert_false(
		GFVariantData.get_option_bool(failed_snapshot, "save_in_flight"),
		"同步失败回调后不得永久残留 in-flight。"
	)

	save_graph.tick(3.0)
	var retried_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(storage.async_save_call_count == 2, "退避窗口结束后应重新尝试保存。")
	assert_false(
		GFVariantData.get_option_bool(retried_snapshot, "save_pending"),
		"后续成功回调应收敛待写状态。"
	)
	assert_false(
		GFVariantData.get_option_bool(retried_snapshot, "save_in_flight"),
		"同步重试成功后不应残留在途状态。"
	)

	_dispose_setup(setup)


func test_background_flush_deduplicates_events_and_retries_after_foreground() -> void:
	var storage: _ScriptedStorage = _ScriptedStorage.new()
	storage.sync_save_errors = [ERR_CANT_OPEN, OK]
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var platform: GamePlatformUtility = _get_platform_stub(setup)
	var queue_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)

	platform.call(
		&"publish_lifecycle_event",
		GFPlatformLifecycleEvent.TYPE_BACKGROUND,
		1
	)
	var failed_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(queue_error == OK, "后台冲刷夹具应成功排队。")
	assert_true(storage.sync_save_call_count == 1, "首次后台事件应立即同步冲刷。")
	assert_true(
		GFVariantData.get_option_bool(failed_snapshot, "save_pending"),
		"后台同步冲刷失败必须保留待写状态。"
	)

	platform.call(
		&"publish_lifecycle_event",
		GFPlatformLifecycleEvent.TYPE_BACKGROUND,
		2
	)
	assert_true(
		storage.sync_save_call_count == 1,
		"同一前台周期的 pause/focus-out 重复后台事件不得重复冲刷。"
	)

	platform.call(
		&"publish_lifecycle_event",
		GFPlatformLifecycleEvent.TYPE_FOREGROUND,
		3
	)
	platform.call(
		&"publish_lifecycle_event",
		GFPlatformLifecycleEvent.TYPE_BACKGROUND,
		4
	)
	var recovered_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(storage.sync_save_call_count == 2, "重新进入后台时应重试先前失败的待写 Profile。")
	assert_false(
		GFVariantData.get_option_bool(recovered_snapshot, "save_pending"),
		"后台重试成功后应清除待写状态。"
	)

	_dispose_setup(setup)


func test_architecture_dispose_flushes_pending_profile_before_exit() -> void:
	var storage: _ScriptedStorage = _ScriptedStorage.new()
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var architecture: GFArchitecture = _get_architecture(setup)
	var queue_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)

	architecture.dispose()

	assert_true(queue_error == OK, "退出冲刷夹具应成功排队。")
	assert_true(
		storage.sync_save_call_count == 1,
		"架构退出必须在存储释放前同步冲刷 Profile；实际调用：%d。"
		% storage.sync_save_call_count
	)
	var cleanup_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
	assert_true(
		cleanup_error == OK or cleanup_error == ERR_FILE_NOT_FOUND,
		"退出冲刷测试数据应可清理。"
	)
	setup.clear()


func test_stats_bookmarks_and_replays_persist_in_one_graph_file() -> void:
	var save_dir_name: String = "gut_save_graph_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var custom_board_system: CustomBoardSystem = _get_custom_board_system(setup)
	var replay_system: ReplaySystem = _get_replay_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)

	var stats_error: Error = progress_stats_system.record_game_result(
		_make_game_result(2048, 32, 2048, 500, 2048, true)
	)
	var bookmark: BookmarkData = _make_bookmark(600, 512)
	var custom_board: CustomBoardData = _make_custom_board()
	var replay: ReplayData = _make_replay(700, 2048)
	var bookmark_error: Error = bookmark_system.save_bookmark(bookmark)
	var custom_board_error: Error = custom_board_system.save_custom_board(custom_board)
	var replay_error: Error = replay_system.save_replay(replay)
	assert_true(stats_error == OK, "统计 section 应保存成功。")
	assert_true(bookmark_error == OK, "书签 section 应保存成功。")
	assert_true(custom_board_error == OK, "玩家棋盘 section 应保存成功。")
	assert_true(replay_error == OK, "回放 section 应保存成功。")
	assert_true(GFUuid.is_valid(bookmark.bookmark_id, 7), "书签应获得稳定 UUID v7。")
	assert_true(GFUuid.is_valid(custom_board.custom_board_id, 7), "玩家棋盘应获得稳定 UUID v7。")
	assert_true(GFUuid.is_valid(replay.replay_id, 7), "回放应获得稳定 UUID v7。")
	assert_true(
		storage.list_files("", "save")
		== PackedStringArray([GameSaveGraphUtility.PROFILE_FILE_NAME]),
		"六类玩家数据应只落到一个原子 SaveGraph 文件。"
	)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(reloaded)
	var reloaded_bookmarks: BookmarkSystem = _get_bookmark_system(reloaded)
	var reloaded_custom_boards: CustomBoardSystem = _get_custom_board_system(reloaded)
	var reloaded_replays: ReplaySystem = _get_replay_system(reloaded)
	assert_true(
		reloaded_graph.is_profile_loaded(),
		"重载事务应成功：%s" % _describe_load_failure(reloaded_graph)
	)
	assert_true(reloaded_progress_stats_system.get_high_score("classic", _BOARD_KEY) == 2048, "重载后应保留统计。")
	var bookmarks: Array[BookmarkData] = reloaded_bookmarks.load_bookmarks()
	var custom_boards: Array[CustomBoardData] = reloaded_custom_boards.load_custom_boards()
	var replays: Array[ReplayData] = reloaded_replays.load_replays()
	assert_true(bookmarks.size() == 1, "重载后应保留书签目录。")
	assert_true(custom_boards.size() == 1, "重载后应保留玩家棋盘目录。")
	assert_true(replays.size() == 1, "重载后应保留回放目录。")
	if bookmarks.size() == 1 and custom_boards.size() == 1 and replays.size() == 1:
		assert_true(bookmarks[0].bookmark_id == bookmark.bookmark_id, "书签稳定 ID 应跨重载保留。")
		assert_true(custom_boards[0].custom_board_id == custom_board.custom_board_id, "玩家棋盘稳定 ID 应跨重载保留。")
		assert_true(replays[0].replay_id == replay.replay_id, "回放稳定 ID 应跨重载保留。")
		assert_true(bookmarks[0].score == 512, "书签业务数据应完整恢复。")
		assert_true(custom_boards[0].display_name == "Cross Five", "玩家棋盘业务数据应完整恢复。")
		assert_true(replays[0].final_score == 2048, "回放业务数据应完整恢复。")

		var delete_bookmark_error: Error = reloaded_bookmarks.delete_bookmark(bookmarks[0].bookmark_id)
		var delete_custom_board_error: Error = reloaded_custom_boards.delete_custom_board(custom_boards[0].custom_board_id)
		var delete_replay_error: Error = reloaded_replays.delete_replay(replays[0].replay_id)
		assert_true(delete_bookmark_error == OK, "应按稳定 ID 删除书签。")
		assert_true(delete_custom_board_error == OK, "应按稳定 ID 删除玩家棋盘。")
		assert_true(delete_replay_error == OK, "应按稳定 ID 删除回放。")
		assert_true(reloaded_bookmarks.load_bookmarks().is_empty(), "书签删除应更新统一图。")
		assert_true(reloaded_custom_boards.load_custom_boards().is_empty(), "玩家棋盘删除应更新统一图。")
		assert_true(reloaded_replays.load_replays().is_empty(), "回放删除应更新统一图。")

	_dispose_setup(reloaded)


func test_late_section_failure_rolls_back_earlier_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)

	var score_error: Error = progress_stats_system.set_high_score("classic", _BOARD_KEY, 128)
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
					_BOARD_KEY: {
						"best_score": 4096,
					},
				},
			},
			"results": [],
			"leaderboards": {},
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
	assert_true(progress_stats_system.get_high_score("classic", _BOARD_KEY) == 128, "progress 的先行应用必须回滚。")
	assert_true(bookmark_system.load_bookmarks().size() == 1, "bookmarks 的先行应用必须回滚。")
	var load_snapshot: Dictionary = GFVariantData.get_option_dictionary(save_graph.get_debug_snapshot(), "last_load")
	assert_false(GFVariantData.get_option_bool(load_snapshot, "ok"), "诊断应记录失败事务。")

	_dispose_setup(setup)


func test_obsolete_profile_is_backed_up_and_reset_without_compatibility() -> void:
	var save_dir_name: String = "gut_save_graph_recovery_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var score_error: Error = progress_stats_system.set_high_score("classic", _BOARD_KEY, 512)
	assert_true(score_error == OK, "迁移夹具应先写入当前统计。")
	assert_true(
		save_graph.flush_pending_save() == OK,
		"构造旧版本夹具前应先收敛当前异步写入。"
	)

	var legacy_payload: Dictionary = save_graph.preview_profile_payload()
	var metadata: Dictionary = GFVariantData.get_option_dictionary(
		legacy_payload,
		"metadata"
	)
	metadata["schema_version"] = 1
	legacy_payload["metadata"] = metadata
	var legacy_graph_payload: Dictionary = _get_save_graph_payload(legacy_payload)
	var scopes: Dictionary = GFVariantData.get_option_dictionary(
		legacy_graph_payload,
		"scopes"
	)
	var removed_custom_boards: bool = scopes.erase(
		String(GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID)
	)
	var removed_discoveries: bool = scopes.erase(
		String(GameSaveGraphUtility.DISCOVERIES_SECTION_ID)
	)
	var removed_achievements: bool = scopes.erase(String(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID
	))
	legacy_graph_payload["scopes"] = scopes
	assert_true(
		removed_custom_boards and removed_discoveries and removed_achievements,
		"player_data@1 夹具应只保留当时存在的三个 section。"
	)
	var seed_error: Error = storage.save_data(
		GameSaveGraphUtility.PROFILE_FILE_NAME,
		legacy_payload
	)
	assert_true(seed_error == OK, "应能写入合法的旧 Profile。")
	_dispose_setup(setup, false)

	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true
	)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_storage: GFStorageUtility = _get_storage(reloaded)
	assert_true(
		reloaded_graph.is_profile_loaded(),
		"旧 Profile 备份后应建立当前严格 Profile：%s"
		% _describe_load_failure(reloaded_graph)
	)
	assert_true(
		_get_progress_stats_system(reloaded).get_high_score("classic", _BOARD_KEY) == 0,
		"运行时不得通过旧业务字段双读恢复统计。"
	)
	var load_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		reloaded_graph.get_debug_snapshot(),
		"last_load"
	)
	assert_true(
		GFVariantData.get_option_bool(
			load_snapshot,
			"recovered_obsolete_profile",
			false
		),
		"加载诊断应明确记录旧 Profile 恢复流程。"
	)
	var recovery_file: String = GFVariantData.get_option_string(
		load_snapshot,
		"recovery_file"
	)
	assert_true(
		recovery_file == "recovery/player_data.schema-1.save",
		"恢复文件应使用稳定且可审计的版本化路径。"
	)
	var recovery_result: GFStorageReadResult = reloaded_storage.load_data(
		recovery_file
	)
	var recovery_payload: Dictionary = recovery_result.payload
	var recovery_metadata: Dictionary = GFVariantData.get_option_dictionary(
		recovery_payload,
		"metadata"
	)
	assert_true(
		recovery_result.ok
		and GFVariantData.get_option_int(recovery_metadata, "schema_version", 0) == 1,
		"恢复备份必须完整保留原 Profile，而不是直接删除。"
	)
	var persisted_result: GFStorageReadResult = reloaded_storage.load_data(
		GameSaveGraphUtility.PROFILE_FILE_NAME
	)
	var persisted_payload: Dictionary = persisted_result.payload
	var persisted_metadata: Dictionary = GFVariantData.get_option_dictionary(
		persisted_payload,
		"metadata"
	)
	var persisted_graph_payload: Dictionary = _get_save_graph_payload(persisted_payload)
	var persisted_scopes: Dictionary = GFVariantData.get_option_dictionary(
		persisted_graph_payload,
		"scopes"
	)
	assert_true(
		GFVariantData.get_option_int(persisted_metadata, "schema_version", 0)
		== GameSaveGraphUtility.PROFILE_SCHEMA_VERSION,
		"重建成功后活动 Profile 应立即使用当前版本。"
	)
	assert_true(
		persisted_scopes.has(String(GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID)),
		"重建后的 Profile 应包含新的严格成就 section。"
	)
	var recovery_cleanup_error: Error = reloaded_storage.delete_file(recovery_file)
	assert_true(recovery_cleanup_error == OK, "测试恢复备份应可清理。")

	_dispose_setup(reloaded)


func test_unreadable_storage_profile_is_reset_to_current_format() -> void:
	var save_dir_name: String = "gut_save_graph_unreadable_%d" % Time.get_ticks_usec()
	var legacy_bytes: PackedByteArray = _make_legacy_storage_bytes({
		"legacy_profile": true,
	})
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		legacy_bytes
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	assert_push_error(
		"Storage document envelope missing or malformed",
		"GFStorage 应明确拒绝旧物理文档。"
	)
	var load_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)

	assert_true(
		save_graph.is_profile_loaded(),
		"无法按当前 codec 解码的 Profile 应按项目 reset_allowed 策略重建。"
	)
	assert_true(
		GFVariantData.get_option_bool(
			load_snapshot,
			"recovered_unreadable_profile",
			false
		),
		"加载诊断应明确记录物理存储格式重建。"
	)
	assert_true(
		progress_stats_system.set_high_score("classic", _BOARD_KEY, 1024) == OK,
		"重建后业务 section 必须可以立即排队写入。"
	)
	assert_true(save_graph.flush_pending_save() == OK, "重建后的 Profile 应可完成同步冲刷。")
	var persisted_result: GFStorageReadResult = storage.load_data(
		GameSaveGraphUtility.PROFILE_FILE_NAME
	)
	assert_true(persisted_result.ok, "活动 Profile 必须已改写为当前 GFStorage 文档格式。")

	_dispose_setup(setup)


func test_future_profile_schema_mismatch_is_rejected_without_fallback() -> void:
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
	assert_true(_get_progress_stats_system(reloaded).get_high_score("classic", _BOARD_KEY) == 0, "不得保留旧 schema 双读回退。")
	assert_true(_get_bookmark_system(reloaded).load_bookmarks().is_empty(), "拒绝载荷时书签默认值应保持为空。")

	_dispose_setup(reloaded)


func test_bookmark_schema_rejects_removed_transient_status_field() -> void:
	var bookmark: BookmarkData = _make_bookmark(900, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(900000)
	var current_payload: Dictionary = bookmark.to_dict()

	assert_false(current_payload.has("status_message"), "瞬时 HUD 通知不得进入书签持久化 schema。")
	assert_true(BookmarkData.from_dict(current_payload) != null, "当前严格书签 schema 应可反序列化。")

	var removed_schema_payload: Dictionary = current_payload.duplicate(true)
	removed_schema_payload["status_message"] = "legacy transient message"
	assert_true(
		BookmarkData.from_dict(removed_schema_payload) == null,
		"已移除字段不得通过兼容分支继续进入当前书签模型。"
	)


func test_bookmark_schema_rejects_inconsistent_target_state() -> void:
	var bookmark: BookmarkData = _make_bookmark(901, 512)
	bookmark.bookmark_id = GFUuid.generate_v7(901000)
	bookmark.highest_tile = 4096
	bookmark.target_tile_value = 2048
	bookmark.target_reached = false

	assert_true(
		BookmarkData.from_dict(bookmark.to_dict()) == null,
		"最高方块已达到目标时，当前 schema 不得接受 target_reached=false。"
	)


func test_bookmark_schema_preserves_historical_target_achievement() -> void:
	var bookmark: BookmarkData = _make_bookmark(902, 1024)
	bookmark.bookmark_id = GFUuid.generate_v7(902000)
	bookmark.highest_tile = 1024
	bookmark.target_tile_value = 2048
	bookmark.target_reached = true
	bookmark.board_snapshot[&"tiles"] = [
		_make_classic_tile_snapshot(Vector2i.ZERO, 1024, 902001),
	]

	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "曾达成目标后当前最高方块降低的书签仍应有效。")
	if restored != null:
		assert_true(restored.target_reached, "显式目标达成状态必须原样恢复。")


func test_bookmark_schema_preserves_strict_replay_trace_prefix() -> void:
	var bookmark: BookmarkData = _make_bookmark(903, 64)
	bookmark.bookmark_id = GFUuid.generate_v7(903000)
	bookmark.replay_actions = [Vector2i.RIGHT, Vector2i.DOWN]
	bookmark.replay_checkpoints = [
		_make_replay_checkpoint(1, 16),
		_make_replay_checkpoint(2, 64),
	]

	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "书签必须接受与操作一一对应的严格回放前缀。")
	if restored != null:
		assert_true(restored.replay_actions == bookmark.replay_actions, "操作前缀必须原样恢复。")
		assert_true(restored.replay_checkpoints.size() == 2, "每个操作必须恢复一个 checkpoint。")
		var last_checkpoint: ReplayCheckpoint = restored.replay_checkpoints.back()
		assert_true(last_checkpoint.score == 64, "末尾 checkpoint 必须对应书签分数。")

	var incomplete_payload: Dictionary = bookmark.to_dict()
	var incomplete_checkpoints: Array = GFVariantData.get_option_array(
		incomplete_payload,
		"replay_checkpoints"
	)
	incomplete_checkpoints.pop_back()
	incomplete_payload["replay_checkpoints"] = incomplete_checkpoints
	assert_true(
		BookmarkData.from_dict(incomplete_payload) == null,
		"actions/checkpoints 数量不一致的书签必须被当前严格 schema 拒绝。"
	)


func test_bookmark_schema_requires_strict_ruleset_identity() -> void:
	var bookmark: BookmarkData = _make_bookmark(904, 128)
	bookmark.bookmark_id = GFUuid.generate_v7(904000)
	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "完整规则集身份应通过书签 schema。")
	if restored != null:
		assert_true(restored.ruleset_id == bookmark.ruleset_id, "ruleset_id 必须原样恢复。")
		assert_true(
			restored.ruleset_fingerprint == bookmark.ruleset_fingerprint,
			"规则集内容指纹必须原样恢复。"
		)

	var invalid_fingerprint_payload: Dictionary = bookmark.to_dict()
	invalid_fingerprint_payload["ruleset_fingerprint"] = "not-a-current-fingerprint"
	assert_true(
		BookmarkData.from_dict(invalid_fingerprint_payload) == null,
		"书签必须拒绝缺失严格 64 位十六进制内容指纹的规则集身份。"
	)


func test_bookmark_and_replay_preserve_daily_session_metadata() -> void:
	var bookmark: BookmarkData = _make_bookmark(905, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(905000)
	var bookmark_topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(bookmark.board_snapshot, &"topology")
	)
	assert_not_null(bookmark_topology)
	bookmark.session_metadata = _make_daily_session_metadata(
		bookmark.ruleset_id,
		bookmark.ruleset_version,
		bookmark.ruleset_fingerprint,
		bookmark_topology,
		bookmark.initial_seed,
		"2026-07-25"
	).to_dict()

	var restored_bookmark: BookmarkData = BookmarkData.from_dict(
		bookmark.to_dict()
	)
	assert_not_null(restored_bookmark, "书签必须往返保存 Daily Challenge 身份。")
	if restored_bookmark != null:
		var bookmark_metadata: GameSessionMetadata = (
			restored_bookmark.get_session_metadata()
		)
		assert_not_null(bookmark_metadata)
		assert_true(
			bookmark_metadata.get_seed_source()
			== GameSessionMetadata.SEED_SOURCE_DAILY
		)
		assert_true(
			bookmark_metadata.get_challenge().get_seed()
			== bookmark.initial_seed
		)

	var replay: ReplayData = _make_replay(906, 512)
	replay.replay_id = GFUuid.generate_v7(906000)
	var replay_topology: BoardTopology = replay.get_initial_topology()
	assert_not_null(replay_topology)
	replay.session_metadata = _make_daily_session_metadata(
		replay.ruleset_id,
		replay.ruleset_version,
		replay.ruleset_fingerprint,
		replay_topology,
		replay.initial_seed,
		"2026-07-26"
	).to_dict()

	var restored_replay: ReplayData = ReplayData.from_dict(replay.to_dict())
	assert_not_null(restored_replay, "回放必须往返保存 Daily Challenge 身份。")
	if restored_replay != null:
		var replay_metadata: GameSessionMetadata = restored_replay.get_session_metadata()
		assert_not_null(replay_metadata)
		assert_true(
			replay_metadata.get_seed_source()
			== GameSessionMetadata.SEED_SOURCE_DAILY
		)
		assert_true(
			replay_metadata.get_challenge().get_challenge_hash()
			== _make_daily_session_metadata(
				replay.ruleset_id,
				replay.ruleset_version,
				replay.ruleset_fingerprint,
				replay_topology,
				replay.initial_seed,
				"2026-07-26"
			).get_challenge().get_challenge_hash()
		)


func test_replay_schema_rejects_final_snapshot_with_different_topology() -> void:
	var replay: ReplayData = _make_replay(903, 2048)
	replay.replay_id = GFUuid.generate_v7(903000)
	replay.final_board_snapshot = _make_empty_board_snapshot(
		BoardTopology.create_rectangle(Vector2i(3, 3))
	)

	assert_true(
		ReplayData.from_dict(replay.to_dict()) == null,
		"方向操作序列无法表达拓扑变化，回放最终快照必须保持初始拓扑。"
	)


func test_replay_schema_rejects_non_cardinal_action() -> void:
	var replay: ReplayData = _make_replay(904, 2048)
	replay.replay_id = GFUuid.generate_v7(904000)
	replay.actions = [Vector2i.ZERO]

	assert_true(
		ReplayData.from_dict(replay.to_dict()) == null,
		"严格回放不得接受零向量或斜向动作。"
	)


func test_save_dependency_failure_rolls_back_replaced_section() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var initial_error: Error = progress_stats_system.set_high_score("classic", _BOARD_KEY, 128)
	assert_true(initial_error == OK, "故障注入前的统计应保存成功。")
	assert_true(save_graph.flush_pending_save() == OK, "故障注入前应冲刷排队统计。")

	var cleanup_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
	assert_true(cleanup_error == OK, "故障注入前应清理测试玩家数据文件。")
	architecture.unregister_utility(GFStorageUtility)
	var failed_error: Error = progress_stats_system.set_high_score("classic", _BOARD_KEY, 4096)
	assert_true(failed_error == ERR_UNCONFIGURED, "SaveGraph 缺少存储依赖时应返回明确错误。")
	assert_true(progress_stats_system.get_high_score("classic", _BOARD_KEY) == 128, "写入失败必须恢复 progress section 内存快照。")

	_dispose_setup(setup, false)


# --- 私有/辅助方法 ---

func _create_persistence_architecture(
	save_dir_name: String = "",
	include_systems: bool = false,
	raw_profile_bytes: PackedByteArray = PackedByteArray(),
	storage_override: GFStorageUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	var framework_save_graph: GFSaveGraphUtility = GFSaveGraphUtility.new()
	var save_graph: GameSaveGraphUtility = _make_game_save_graph()
	var platform: GamePlatformUtility = _TEST_PLATFORM_STUB_SCRIPT.new()
	var progress_stats_system: ProgressStatsSystem = null
	var bookmark_system: BookmarkSystem = null
	var custom_board_system: CustomBoardSystem = null
	var replay_system: ReplaySystem = null

	storage.save_dir_name = save_dir_name if not save_dir_name.is_empty() else "gut_save_graph_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	if not raw_profile_bytes.is_empty():
		var fixture_error: Error = _write_raw_storage_file(
			storage,
			GameSaveGraphUtility.PROFILE_FILE_NAME,
			raw_profile_bytes
		)
		assert_true(fixture_error == OK, "无法写入不可读 Profile 回归夹具。")

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, framework_save_graph)
	await architecture.register_utility(GamePlatformUtility, platform)
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, GFCommandHistoryUtility.new())
	if include_systems:
		progress_stats_system = ProgressStatsSystem.new()
		bookmark_system = BookmarkSystem.new()
		custom_board_system = CustomBoardSystem.new()
		replay_system = ReplaySystem.new()
		await architecture.register_system(ProgressStatsSystem, progress_stats_system)
		await architecture.register_system(BookmarkSystem, bookmark_system)
		await architecture.register_system(CustomBoardSystem, custom_board_system)
		await architecture.register_system(ReplaySystem, replay_system)
	await architecture.init()

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"platform": platform,
		"progress_stats_system": progress_stats_system,
		"bookmark_system": bookmark_system,
		"custom_board_system": custom_board_system,
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
	var custom_boards_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID,
		CustomBoardCatalogSaveData.new(),
		GFSaveScope.Phase.NORMAL
	)
	var discoveries_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		TileDiscoverySaveData.new(),
		GFSaveScope.Phase.NORMAL
	)
	var achievements_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID,
		AchievementSaveData.new(),
		GFSaveScope.Phase.LATE
	)
	var replays_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		ReplayCatalogSaveData.new(),
		GFSaveScope.Phase.LATE
	)
	var limited_levels_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.LIMITED_LEVELS_SECTION_ID,
		LimitedMoveLevelProgressSaveData.new(),
		GFSaveScope.Phase.LATE
	)
	assert_true(
		progress_registered
		and bookmarks_registered
		and custom_boards_registered
		and discoveries_registered
		and achievements_registered
		and replays_registered
		and limited_levels_registered,
		"测试 SaveGraph section 应完整注册。"
	)
	return save_graph


func _write_raw_storage_file(
	storage: GFStorageUtility,
	file_name: String,
	bytes: PackedByteArray
) -> Error:
	var directory_error: Error = storage.ensure_directory()
	if directory_error != OK:
		return directory_error
	var path: String = storage.get_storage_directory_path().path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var _store_result: Variant = file.store_buffer(bytes)
	file.close()
	return OK


func _make_legacy_storage_bytes(data: Dictionary, obfuscation_key: int = 42) -> PackedByteArray:
	var bytes: PackedByteArray = var_to_bytes(data)
	var key_byte: int = obfuscation_key & 0xff
	for index: int in range(bytes.size()):
		bytes[index] = bytes[index] ^ key_byte
	return Marshalls.raw_to_base64(bytes).to_utf8_buffer()


func _make_empty_progress_data() -> Dictionary:
	return {
		"stats": {},
		"results": [],
		"leaderboards": {},
	}


func _make_game_result(
	score: int,
	steps: int,
	max_tile: int,
	played_at: int,
	target_value: int = 0,
	target_reached: bool = false
) -> GameResultRecordedData:
	var result: GameResultRecordedData = GameResultRecordedData.create(
		&"classic",
		_BOARD_KEY,
		&"gameplay.classic",
		1,
		"a".repeat(64),
		2048,
		("%d|%d|%d|%d" % [score, steps, max_tile, played_at]).sha256_text(),
		null,
		GameCompetitionEligibility.create(),
		score,
		steps,
		max_tile,
		played_at,
		target_value,
		target_reached
	)
	assert_not_null(result, "SaveGraph 结果 fixture 必须满足严格契约。")
	return result


func _make_daily_session_metadata(
	ruleset_id: StringName,
	ruleset_version: int,
	ruleset_fingerprint: String,
	topology: BoardTopology,
	seed_value: int,
	utc_date: String
) -> GameSessionMetadata:
	var challenge: GameChallengeMetadata = GameChallengeMetadata.create_daily(
		GameChallengeUtility.DAILY_CHALLENGE_SCHEMA_VERSION,
		utc_date,
		ruleset_id,
		ruleset_version,
		ruleset_fingerprint,
		topology.get_stable_key(),
		seed_value,
		(
			"%s|%s|%d|%s|%s|%d"
			% [
				utc_date,
				ruleset_id,
				ruleset_version,
				ruleset_fingerprint,
				topology.get_stable_key(),
				seed_value,
			]
		).sha256_text()
	)
	assert_not_null(challenge, "Daily session fixture 必须满足挑战契约。")
	var metadata: GameSessionMetadata = GameSessionMetadata.create(
		GameSessionMetadata.SEED_SOURCE_DAILY,
		challenge,
		GameCompetitionEligibility.create([
			GameCompetitionEligibility.REASON_DAILY,
		])
	)
	assert_not_null(metadata, "Daily session fixture 必须满足会话契约。")
	return metadata


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	var mode_resource: Resource = load(bookmark.mode_config_path)
	if mode_resource is GameModeConfig:
		var mode_config: GameModeConfig = mode_resource
		bookmark.ruleset_id = mode_config.ruleset_id
		bookmark.ruleset_version = mode_config.ruleset_version
		bookmark.ruleset_fingerprint = GameDeterminismUtility.new().calculate_ruleset_fingerprint(
			mode_config
		)
		bookmark.rules_states = RuleSystem.capture_rule_states(mode_config.spawn_rules)
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	bookmark.initial_seed = 2048
	bookmark.rng_full_state = seed_utility.get_full_state()
	bookmark.score = score
	bookmark.board_snapshot = _make_empty_board_snapshot()
	bookmark.game_state_history = {
		"undo": [],
		"redo": [],
	}
	return bookmark


func _make_replay(timestamp: int, final_score: int) -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	var topology: BoardTopology = BoardTopology.create_rectangle(_BOARD_SIZE)
	replay.timestamp = timestamp
	replay.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	replay.ruleset_id = &"gameplay.classic"
	replay.ruleset_version = 1
	replay.ruleset_fingerprint = "a".repeat(64)
	replay.initial_seed = 2048
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	replay.checkpoints = [_make_replay_checkpoint(1, final_score)]
	replay.final_board_snapshot = _make_empty_board_snapshot(topology)
	return replay


func _make_replay_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "b".repeat(64)
	checkpoint.board_checksum = "c".repeat(64)
	checkpoint.rng_checksum = "d".repeat(64)
	checkpoint.score = score
	return checkpoint


func _make_custom_board() -> CustomBoardData:
	var custom_board: CustomBoardData = CustomBoardData.new()
	custom_board.display_name = "Cross Five"
	custom_board.topology = BoardTopology.create_cross(2)
	return custom_board


func _make_empty_board_snapshot(topology: BoardTopology = null) -> Dictionary:
	var resolved_topology: BoardTopology = topology
	if resolved_topology == null:
		resolved_topology = BoardTopology.create_rectangle(_BOARD_SIZE)
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": resolved_topology.to_dict(),
		&"tiles": [],
	}


func _make_classic_tile_snapshot(
	position: Vector2i,
	value: int,
	timestamp_msec: int
) -> Dictionary:
	return {
		&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": GFUuid.generate_v7(timestamp_msec),
		&"definition_id": &"tile.classic.numeric",
		&"value": value,
		&"capability_recipe_ids": [&"tile.recipe.classic_merge"],
		&"capability_state": {},
		&"pos": position,
	}


func _get_section_source(payload: Dictionary, section_id: StringName) -> Dictionary:
	var graph_payload: Dictionary = _get_save_graph_payload(payload)
	var scopes: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(graph_payload, "scopes")
	)
	var section_payload: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(scopes, String(section_id))
	)
	var sources: Dictionary = GFVariantData.as_dictionary(GFVariantData.get_option_value(section_payload, "sources"))
	return GFVariantData.as_dictionary(GFVariantData.get_option_value(sources, "state"))


func _get_save_graph_payload(document_payload: Dictionary) -> Dictionary:
	var sections: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(document_payload, "sections")
	)
	var section: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(
			sections,
			String(GFSaveGraphUtility.DOCUMENT_SECTION_ID)
		)
	)
	return GFVariantData.as_dictionary(GFVariantData.get_option_value(section, "payload"))


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
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var flush_error: Error = save_graph.flush_pending_save()
	assert_true(flush_error == OK, "测试结束前应冲刷排队玩家数据。")
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


func _get_platform_stub(setup: Dictionary) -> GamePlatformUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "platform")
	if value is GamePlatformUtility:
		var platform: GamePlatformUtility = value
		return platform
	assert_true(false, "测试 setup 缺少 TestGamePlatformUtilityStub。")
	return _TEST_PLATFORM_STUB_SCRIPT.new()


func _get_progress_stats_system(setup: Dictionary) -> ProgressStatsSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "progress_stats_system")
	if value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = value
		return progress_stats_system
	assert_true(false, "测试 setup 缺少 ProgressStatsSystem。")
	return ProgressStatsSystem.new()


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


func _get_custom_board_system(setup: Dictionary) -> CustomBoardSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "custom_board_system")
	if value is CustomBoardSystem:
		var custom_board_system: CustomBoardSystem = value
		return custom_board_system
	assert_true(false, "测试 setup 缺少 CustomBoardSystem。")
	return CustomBoardSystem.new()


# --- 内部类 ---

class _ScriptedStorage extends GFStorageUtility:
	var async_completion_errors: Array[int] = []
	var async_start_errors: Array[int] = []
	var sync_save_errors: Array[int] = []
	var async_save_call_count: int = 0
	var sync_save_call_count: int = 0


	func save_data_async(file_name: String, _data: Dictionary) -> Error:
		async_save_call_count += 1
		var completion_error: Error = (
			async_completion_errors.pop_front() as Error
			if not async_completion_errors.is_empty()
			else OK
		)
		save_completed.emit(file_name, completion_error)
		return (
			async_start_errors.pop_front() as Error
			if not async_start_errors.is_empty()
			else OK
		)


	func save_data(file_name: String, data: Dictionary) -> Error:
		sync_save_call_count += 1
		if not sync_save_errors.is_empty():
			var scripted_error: Error = sync_save_errors.pop_front() as Error
			if scripted_error != OK:
				return scripted_error
		return super.save_data(file_name, data)
