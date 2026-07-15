## 验证 SaveSystem 的最高分和轻量统计 SaveGraph 语义。
extends GutTest


# --- 常量 ---

const _MODE_ID: String = "classic_mode_config"
const _GRID_SIZE: int = 4


# --- 测试用例 ---

func test_set_high_score_updates_stats_without_recording_play() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var save_error: Error = save_system.set_high_score(_MODE_ID, _GRID_SIZE, 2048)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(save_error == OK, "最高分应写入 progress section。")
	assert_true(save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 2048, "统计图应提供最高分。")
	assert_true(_get_stat_int(stats, "best_score") == 2048, "最高分应以 stats.best_score 为唯一真源。")
	assert_true(_get_stat_int(stats, "plays") == 0, "只写入最高分不应增加完整对局次数。")
	assert_true(_get_stat_int(stats, "average_score") == 0, "只写入最高分不应生成平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 0, "只写入最高分不应生成平均步数。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 0, "只写入最高分不应生成目标达成次数。")

	_dispose_setup(setup)


func test_record_game_result_updates_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var first_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 512, 20, 128, 100)
	var second_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 256, 18, 256, 200)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(first_error == OK, "第一局统计应保存成功。")
	assert_true(second_error == OK, "第二局统计应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "每次完整对局都应增加 plays。")
	assert_true(_get_stat_int(stats, "best_score") == 512, "统计应保留最佳分数。")
	assert_true(_get_stat_int(stats, "best_steps") == 18, "统计应保留最少有效步数。")
	assert_true(_get_stat_int(stats, "max_tile") == 256, "统计应保留历史最大方块。")
	assert_true(_get_stat_int(stats, "total_score") == 768, "统计应累计总分。")
	assert_true(_get_stat_int(stats, "total_steps") == 38, "统计应累计总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 2, "统计应记录有效步数样本数。")
	assert_true(_get_stat_int(stats, "average_score") == 384, "统计应计算平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 19, "统计应计算平均步数。")
	assert_true(_get_stat_int(stats, "last_score") == 256, "统计应记录最近一局分数。")
	assert_true(_get_stat_int(stats, "last_played_at") == 200, "统计应记录最近一局时间戳。")

	_dispose_setup(setup)


func test_target_rate_is_bounded_by_play_count() -> void:
	var setup: Dictionary = await _create_save_architecture({
		"stats": {
			_MODE_ID: {
				"4x4": {
					"plays": 2,
					"target_value": 2048,
					"target_reached_count": 5,
				},
			},
		},
	})
	var stats: Dictionary = _get_save_system(setup).get_game_stats(_MODE_ID, _GRID_SIZE)

	assert_true(_get_stat_int(stats, "target_reached_count") == 2, "目标达成次数不应超过完整对局次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 100, "目标达成率应归一化到 0 到 100。")

	_dispose_setup(setup)


func test_zero_step_results_do_not_pollute_step_averages() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var zero_step_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 64, 0, 64, 100)
	var normal_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 128, 10, 128, 200)
	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)

	assert_true(zero_step_error == OK, "零步结果应保存成功。")
	assert_true(normal_error == OK, "正常结果应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "零步结果仍应计入完整对局次数。")
	assert_true(_get_stat_int(stats, "best_steps") == 10, "零步结果不应成为最佳步数。")
	assert_true(_get_stat_int(stats, "total_steps") == 10, "零步结果不应污染总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 1, "零步结果不应增加步数样本。")
	assert_true(_get_stat_int(stats, "average_score") == 96, "平均分仍应按所有完整对局计算。")
	assert_true(_get_stat_int(stats, "average_steps") == 10, "平均步数只应按有效步数样本计算。")

	_dispose_setup(setup)


func test_record_game_result_tracks_target_reach_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var missed_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 1024, 26, 1024, 100, 2048, false)
	var reached_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 2048, 35, 2048, 200, 2048, true)
	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)

	assert_true(missed_error == OK, "未达成局应保存成功。")
	assert_true(reached_error == OK, "达成局应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "目标统计应以完整对局次数为分母。")
	assert_true(_get_stat_int(stats, "target_value") == 2048, "统计应记录目标方块值。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 1, "统计应累计目标达成次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 50, "统计应计算目标达成率百分比。")
	assert_true(_get_stat_bool(stats, "last_target_reached"), "最近一局目标状态应记录为已达成。")

	_dispose_setup(setup)


func test_record_game_result_preserves_existing_higher_score() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var high_score_error: Error = save_system.set_high_score(_MODE_ID, _GRID_SIZE, 4096)
	var result_error: Error = save_system.record_game_result(_MODE_ID, _GRID_SIZE, 1024, 30, 512, 300)
	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)

	assert_true(high_score_error == OK, "已有最高分应保存成功。")
	assert_true(result_error == OK, "后续对局应保存成功。")
	assert_true(save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 4096, "较低分数不应覆盖已有最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "记录完整对局仍应增加 plays。")
	assert_true(_get_stat_int(stats, "average_score") == 1024, "平均分应基于实际得分。")
	assert_true(_get_stat_int(stats, "last_score") == 1024, "最近一局摘要应保留实际结束分数。")

	_dispose_setup(setup)


func test_stats_persist_through_gf_save_graph() -> void:
	var save_dir_name: String = "gut_save_system_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_save_architecture({}, save_dir_name)
	var save_error: Error = _get_save_system(setup).record_game_result(_MODE_ID, _GRID_SIZE, 1024, 24, 512, 400)
	assert_true(save_error == OK, "统计应写入 SaveGraph。")
	_dispose_setup(setup, false)

	var reloaded_setup: Dictionary = await _create_save_architecture({}, save_dir_name)
	var reloaded_save_system: SaveSystem = _get_save_system(reloaded_setup)
	var stats: Dictionary = reloaded_save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(reloaded_save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 1024, "重新加载后应保留最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "重新加载后应保留统计次数。")
	assert_true(_get_stat_int(stats, "average_steps") == 24, "重新加载后应保留平均步数。")
	assert_true(_get_stat_int(stats, "last_played_at") == 400, "重新加载后应保留最近时间戳。")

	_dispose_setup(reloaded_setup)


func test_progress_section_rejects_multiple_business_roots() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var invalid_error: Error = save_graph.replace_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		{
			"stats": {},
			"scores": {},
		}
	)

	assert_true(invalid_error == ERR_INVALID_DATA, "progress schema 应拒绝多真源载荷。")
	assert_true(save_graph.get_section_data(GameSaveGraphUtility.PROGRESS_SECTION_ID) == {"stats": {}}, "非法替换不得改变内存 section。")

	_dispose_setup(setup)


func test_persisted_progress_payload_has_strict_section_schema() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var save_error: Error = save_system.set_high_score(_MODE_ID, _GRID_SIZE, 2048)
	var payload: Dictionary = save_graph.preview_profile_payload()
	var scopes: Dictionary = GFVariantData.get_option_dictionary(payload, "scopes")
	var progress_scope: Dictionary = GFVariantData.get_option_dictionary(scopes, "progress")
	var sources: Dictionary = GFVariantData.get_option_dictionary(progress_scope, "sources")
	var source: Dictionary = GFVariantData.get_option_dictionary(sources, "state")
	var envelope: Dictionary = GFVariantData.get_option_dictionary(source, "data")
	var data: Dictionary = GFVariantData.get_option_dictionary(envelope, "data")

	assert_true(save_error == OK, "测试最高分应保存成功。")
	assert_true(GFVariantData.get_option_string(envelope, "section_id") == "progress", "Source 应声明稳定 section ID。")
	assert_true(GFVariantData.get_option_int(envelope, "schema_version") == GameStatsSaveData.SCHEMA_VERSION, "Source 应声明严格 schema 版本。")
	assert_true(data.has("stats"), "progress 数据必须包含 stats 根字段。")
	assert_false(data.has("scores"), "progress 数据不得保留第二套 scores 真源。")
	assert_true(data.size() == 1, "progress 业务根字段应保持单一。")

	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_save_architecture(
	initial_save_data: Dictionary = {},
	save_dir_name: String = ""
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var save_graph: GameSaveGraphUtility = _make_game_save_graph()
	var save_system: SaveSystem = SaveSystem.new()

	storage.save_dir_name = save_dir_name if not save_dir_name.is_empty() else "gut_save_system_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, GFSaveGraphUtility.new())
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_system(SaveSystem, save_system)
	await architecture.init()
	if not initial_save_data.is_empty():
		var seed_error: Error = save_graph.replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			initial_save_data
		)
		assert_true(seed_error == OK, "测试统计初始数据应写入 progress section。")

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"save_system": save_system,
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


func _dispose_setup(setup: Dictionary, delete_profile: bool = true) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	if delete_profile:
		var delete_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
		assert_true(delete_error == OK or delete_error == ERR_FILE_NOT_FOUND, "统计测试清理应返回可预期结果。")
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


func _get_stat_int(stats: Dictionary, key: String) -> int:
	return GFVariantData.get_option_int(stats, key)


func _get_stat_bool(stats: Dictionary, key: String) -> bool:
	return GFVariantData.get_option_bool(stats, key)
