## 验证 SaveSystem 的最高分和轻量统计存储语义。
extends GutTest


# --- 常量 ---

const _MODE_ID: String = "classic_mode_config"
const _GRID_SIZE: int = 4


# --- 测试用例 ---

func test_legacy_high_score_feeds_default_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.set_high_score(_MODE_ID, _GRID_SIZE, 2048)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 2048, "旧 scores 结构应继续提供最高分。")
	assert_true(_get_stat_int(stats, "best_score") == 2048, "旧最高分应成为默认统计的 best_score。")
	assert_true(_get_stat_int(stats, "plays") == 0, "只写入最高分不应增加完整对局次数。")
	assert_true(_get_stat_int(stats, "average_score") == 0, "只写入最高分不应生成平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 0, "只写入最高分不应生成平均步数。")
	assert_true(_get_stat_int(stats, "target_value") == 0, "只写入最高分不应生成目标值。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 0, "只写入最高分不应生成目标达成次数。")

	_dispose_setup(setup)


func test_record_game_result_updates_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 512, 20, 128, 100)
	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 256, 18, 256, 200)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(_get_stat_int(stats, "plays") == 2, "每次完整对局结果都应增加 plays。")
	assert_true(_get_stat_int(stats, "best_score") == 512, "统计应保留最佳分数。")
	assert_true(_get_stat_int(stats, "best_steps") == 18, "统计应保留最少有效步数。")
	assert_true(_get_stat_int(stats, "max_tile") == 256, "统计应保留历史最大方块。")
	assert_true(_get_stat_int(stats, "total_score") == 768, "统计应累计完整对局总分。")
	assert_true(_get_stat_int(stats, "total_steps") == 38, "统计应累计完整对局总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 2, "统计应记录有效步数样本数。")
	assert_true(_get_stat_int(stats, "average_score") == 384, "统计应计算平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 19, "统计应计算平均步数。")
	assert_true(_get_stat_int(stats, "last_score") == 256, "统计应记录最近一局分数。")
	assert_true(_get_stat_int(stats, "last_steps") == 18, "统计应记录最近一局步数。")
	assert_true(_get_stat_int(stats, "last_max_tile") == 256, "统计应记录最近一局最大方块。")
	assert_true(_get_stat_int(stats, "last_played_at") == 200, "统计应记录最近一局时间戳。")
	assert_true(save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 512, "完整对局结果也应同步最高分。")

	_dispose_setup(setup)


func test_sparse_legacy_stats_are_normalized() -> void:
	var setup: Dictionary = await _create_save_architecture(
		"",
		{
			"scores": {
				_MODE_ID: {
					"4x4": 2048,
				},
			},
			"stats": {
				_MODE_ID: {
					"4x4": {
						"plays": 3,
						"best_score": 1024,
						"last_score": 400,
						"last_steps": 20,
						"target_value": 2048,
						"target_reached_count": 2,
					},
				},
			},
		}
	)
	var save_system: SaveSystem = _get_save_system(setup)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(_get_stat_int(stats, "plays") == 3, "旧统计应保留完整对局次数。")
	assert_true(_get_stat_int(stats, "best_score") == 2048, "旧 scores 最高分应补齐到统计 best_score。")
	assert_true(_get_stat_int(stats, "total_score") == 1200, "缺失总分时应按最近分数和次数回填。")
	assert_true(_get_stat_int(stats, "total_steps") == 60, "缺失总步数时应按最近步数和样本数回填。")
	assert_true(_get_stat_int(stats, "step_samples") == 3, "缺失步数样本时应兼容旧统计次数。")
	assert_true(_get_stat_int(stats, "average_score") == 400, "旧统计应重新计算平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 20, "旧统计应重新计算平均步数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 67, "旧目标统计应重新计算达成率。")

	_dispose_setup(setup)


func test_legacy_target_rate_is_bounded_by_play_count() -> void:
	var setup: Dictionary = await _create_save_architecture(
		"",
		{
			"stats": {
				_MODE_ID: {
					"4x4": {
						"plays": 2,
						"target_value": 2048,
						"target_reached_count": 5,
					},
				},
			},
		}
	)
	var save_system: SaveSystem = _get_save_system(setup)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(_get_stat_int(stats, "target_reached_count") == 2, "旧统计的目标达成次数不应超过完整对局次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 100, "目标达成率应归一化到 0 到 100。")

	_dispose_setup(setup)


func test_zero_step_results_do_not_pollute_step_averages() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 64, 0, 64, 100)
	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 128, 10, 128, 200)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(_get_stat_int(stats, "plays") == 2, "零步结果仍应计入完整对局次数。")
	assert_true(_get_stat_int(stats, "best_steps") == 10, "零步结果不应成为最佳步数。")
	assert_true(_get_stat_int(stats, "total_steps") == 10, "零步结果不应污染总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 1, "零步结果不应增加步数样本。")
	assert_true(_get_stat_int(stats, "average_score") == 96, "平均分仍应按所有完整对局计算。")
	assert_true(_get_stat_int(stats, "average_steps") == 10, "平均步数只应按有效步数样本计算。")
	assert_true(_get_stat_int(stats, "last_steps") == 10, "最近一局应记录最新有效步数。")

	_dispose_setup(setup)


func test_record_game_result_tracks_target_reach_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 1024, 26, 1024, 100, 2048, false)
	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 2048, 35, 2048, 200, 2048, true)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(_get_stat_int(stats, "plays") == 2, "目标统计仍应以完整对局次数为分母。")
	assert_true(_get_stat_int(stats, "target_value") == 2048, "统计应记录当前模式配置的目标方块值。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 1, "统计应累计目标达成次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 50, "统计应计算目标达成率百分比。")
	assert_true(_get_stat_bool(stats, "last_target_reached"), "最近一局目标状态应记录为已达成。")

	_dispose_setup(setup)


func test_record_game_result_preserves_existing_higher_score() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.set_high_score(_MODE_ID, _GRID_SIZE, 4096)
	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 1024, 30, 512, 300)

	var stats: Dictionary = save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 4096, "较低的完整对局分数不应覆盖已有最高分。")
	assert_true(_get_stat_int(stats, "best_score") == 4096, "统计 best_score 应兼容并保留旧最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "记录完整对局仍应增加 plays。")
	assert_true(_get_stat_int(stats, "average_score") == 1024, "平均分应基于完整对局实际得分。")
	assert_true(_get_stat_int(stats, "average_steps") == 30, "平均步数应基于完整对局实际步数。")
	assert_true(_get_stat_int(stats, "last_score") == 1024, "最近一局摘要应保留实际结束分数。")

	_dispose_setup(setup)


func test_stats_persist_through_gf_storage() -> void:
	var save_dir_name: String = "gut_save_system_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_save_architecture(save_dir_name)
	var save_system: SaveSystem = _get_save_system(setup)

	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 1024, 24, 512, 400)
	_dispose_setup(setup, false)

	var reloaded_setup: Dictionary = await _create_save_architecture(save_dir_name)
	var reloaded_save_system: SaveSystem = _get_save_system(reloaded_setup)
	var stats: Dictionary = reloaded_save_system.get_game_stats(_MODE_ID, _GRID_SIZE)
	assert_true(reloaded_save_system.get_high_score(_MODE_ID, _GRID_SIZE) == 1024, "重新加载后应保留最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "重新加载后应保留统计次数。")
	assert_true(_get_stat_int(stats, "average_score") == 1024, "重新加载后应保留平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 24, "重新加载后应保留平均步数。")
	assert_true(_get_stat_int(stats, "last_played_at") == 400, "重新加载后应保留最近一局时间戳。")

	_dispose_setup(reloaded_setup)


func test_stats_persist_through_gf_save_slot_workflow_metadata() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_system: SaveSystem = _get_save_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var save_slot_workflow: GameSaveSlotWorkflowUtility = _get_save_slot_workflow(setup)

	save_system.record_game_result(_MODE_ID, _GRID_SIZE, 2048, 42, 2048, 500, 2048, true)

	assert_true(
		storage.has_slot(GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX),
		"最高分和统计应保存到 GF save slot。"
	)
	var card: GFSaveSlotCard = save_slot_workflow.build_stats_card(storage)
	assert_false(card.is_empty, "GFSaveSlotWorkflow 应能构建非空统计槽卡片。")
	assert_true(card.slot_index == GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX, "统计槽卡片应使用稳定槽位。")
	assert_true(GFVariantData.get_option_string(card.metadata, "schema_id") == "game_stats", "统计槽元数据应记录 schema_id。")
	assert_true(GFVariantData.get_option_int(card.metadata, "schema_version") == 1, "统计槽元数据应记录 schema_version。")
	var custom_metadata: Dictionary = GFVariantData.get_option_dictionary(card.metadata, "custom_metadata")
	assert_true(_get_stat_int(custom_metadata, "total_plays") == 1, "统计槽元数据应汇总总局数。")
	assert_true(_get_stat_int(custom_metadata, "best_score") == 2048, "统计槽元数据应汇总最高分。")

	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_save_architecture(save_dir_name: String = "", initial_save_data: Dictionary = {}) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var clock: GameClockUtility = GameClockUtility.new()
	var save_slot_workflow: GameSaveSlotWorkflowUtility = GameSaveSlotWorkflowUtility.new()
	var save_system: SaveSystem = SaveSystem.new()

	storage.save_dir_name = save_dir_name if not save_dir_name.is_empty() else "gut_save_system_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	if not initial_save_data.is_empty():
		var _seed_error: Error = storage.save_slot(
			GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX,
			initial_save_data,
			{}
		)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GameClockUtility, clock)
	await architecture.register_utility(GameSaveSlotWorkflowUtility, save_slot_workflow)
	await architecture.register_system(SaveSystem, save_system)
	await architecture.init()

	return {
		"architecture": architecture,
		"storage": storage,
		"save_slot_workflow": save_slot_workflow,
		"save_system": save_system,
	}


func _dispose_setup(setup: Dictionary, delete_file: bool = true) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	if delete_file and is_instance_valid(storage):
		storage.delete_slot(GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX)

	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_storage(setup: Dictionary) -> GFStorageUtility:
	var value: Variant = setup.get("storage")
	if value is GFStorageUtility:
		var storage: GFStorageUtility = value
		return storage
	assert_true(false, "测试 setup 缺少 GFStorageUtility。")
	return GFStorageUtility.new()


func _get_save_system(setup: Dictionary) -> SaveSystem:
	var value: Variant = setup.get("save_system")
	if value is SaveSystem:
		var save_system: SaveSystem = value
		return save_system
	assert_true(false, "测试 setup 缺少 SaveSystem。")
	return SaveSystem.new()


func _get_save_slot_workflow(setup: Dictionary) -> GameSaveSlotWorkflowUtility:
	var value: Variant = setup.get("save_slot_workflow")
	if value is GameSaveSlotWorkflowUtility:
		var save_slot_workflow: GameSaveSlotWorkflowUtility = value
		return save_slot_workflow
	assert_true(false, "测试 setup 缺少 GameSaveSlotWorkflowUtility。")
	return GameSaveSlotWorkflowUtility.new()


func _get_stat_int(stats: Dictionary, key: String) -> int:
	return GFVariantData.to_int(stats.get(key, 0), 0)


func _get_stat_bool(stats: Dictionary, key: String) -> bool:
	return GFVariantData.to_bool(stats.get(key, false), false)
