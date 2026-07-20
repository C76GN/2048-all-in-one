## 验证成就资源目录、GF Quest 投影和严格本地进度。
extends GutTest


const ACHIEVEMENT_LIST_SCENE: PackedScene = preload(
	"res://features/achievements/scenes/ui/achievement_list_dialog.tscn"
)
const _BOARD_KEY: String = "board.rectangle.4x4@achievement-test"
const _EXPECTED_ACHIEVEMENT_COUNT: int = 7


func test_achievement_catalog_registers_strict_resource_definitions() -> void:
	var setup: Dictionary = await _create_setup(
		"gut_achievement_catalog_%d" % Time.get_ticks_usec()
	)
	var catalog: AchievementCatalogUtility = _get_catalog(setup)
	var report: GFValidationReport = catalog.get_validation_report()

	assert_true(report != null and report.is_ok(), "成就定义目录应通过严格校验。")
	assert_true(
		catalog.get_definition_ids().size() == _EXPECTED_ACHIEVEMENT_COUNT,
		"示例项目应注册完整的首批成就资源。"
	)
	assert_true(
		catalog.get_registered_definition_paths().size() == _EXPECTED_ACHIEVEMENT_COUNT,
		"成就资源路径应由 GF Resource Registry 提供。"
	)
	var definition: AchievementDefinition = catalog.get_definition(
		&"achievement.first_game"
	)
	assert_true(definition != null, "目录应按稳定 ID 查询成就定义。")
	if definition != null:
		assert_true(
			definition.get_criteria_fingerprint().length() == 24,
			"成就达成条件应提供稳定内容指纹。"
		)
	_dispose_setup(setup)


func test_achievement_save_data_rejects_duplicate_or_unknown_fields() -> void:
	var provider: AchievementSaveData = AchievementSaveData.new()
	var record: AchievementProgressRecord = AchievementProgressRecord.create(
		&"achievement.test",
		"criteria-fingerprint",
		1,
		100,
		100
	)
	assert_true(record != null, "有效进度记录应可创建。")
	if record == null:
		return
	assert_true(
		provider.replace_section_data({"records": [record.to_dict()]}) == OK,
		"严格成就 section 应接受当前 schema。"
	)
	assert_true(
		provider.replace_section_data({
			"records": [record.to_dict(), record.to_dict()],
		}) == ERR_INVALID_DATA,
		"同一 achievement_id 不得重复持久化。"
	)
	assert_true(
		provider.replace_section_data({"records": [], "legacy": {}}) == ERR_INVALID_DATA,
		"成就 section 不得保留未知旧字段兼容分支。"
	)


func test_persisted_game_result_advances_gf_quest_once() -> void:
	var setup: Dictionary = await _create_setup(
		"gut_achievement_progress_%d" % Time.get_ticks_usec()
	)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var achievement_system: AchievementSystem = _get_achievement_system(setup)
	var quest: GFQuestUtility = _get_quest(setup)

	var save_error: Error = progress_stats_system.record_game_result(
		"classic",
		_BOARD_KEY,
		4096,
		40,
		2048,
		100,
		2048,
		true
	)
	assert_true(save_error == OK, "对局结果应先成功提交统计 section。")
	assert_true(
		achievement_system.is_unlocked(&"achievement.first_game"),
		"首次有效对局应解锁首局成就。"
	)
	assert_true(
		achievement_system.is_unlocked(&"achievement.first_target"),
		"首次达成模式目标应解锁目标成就。"
	)
	assert_true(
		achievement_system.is_unlocked(&"achievement.reach_2048"),
		"达到 2048 应解锁对应成就。"
	)
	var ten_games: Dictionary = achievement_system.get_entry(&"achievement.ten_games")
	assert_true(
		GFVariantData.get_option_int(ten_games, &"current_value") == 1,
		"累计十局成就应推进到 1。"
	)
	var quest_report: Dictionary = quest.get_quest_report(&"achievement.ten_games")
	assert_true(
		GFVariantData.get_option_int(quest_report, "current_count") == 1,
		"项目进度应投影到 GFQuestUtility。"
	)

	var reconciliation_error: Error = achievement_system.reconcile_progress()
	assert_true(reconciliation_error == OK, "重复协调应成功。")
	assert_true(
		GFVariantData.get_option_int(
			achievement_system.get_entry(&"achievement.ten_games"),
			&"current_value"
		) == 1,
		"高水位协调必须幂等，不得重复累计同一对局。"
	)
	_dispose_setup(setup)


func test_achievement_system_backfills_from_canonical_sections() -> void:
	var save_dir_name: String = "gut_achievement_backfill_%d" % Time.get_ticks_usec()
	var seed_setup: Dictionary = await _create_setup(save_dir_name, false)
	var seed_error: Error = _get_progress_stats_system(seed_setup).record_game_result(
		"classic",
		_BOARD_KEY,
		12000,
		55,
		4096,
		200,
		2048,
		true
	)
	assert_true(seed_error == OK, "回填测试应先写入规范统计真源。")
	_dispose_setup(seed_setup, false)

	var reloaded: Dictionary = await _create_setup(save_dir_name, true)
	var achievements: AchievementSystem = _get_achievement_system(reloaded)
	assert_true(
		achievements.is_unlocked(&"achievement.first_game"),
		"新安装的成就系统应从历史统计回填首局成就。"
	)
	assert_true(
		achievements.is_unlocked(&"achievement.score_10000"),
		"新成就应能从历史最高分高水位回填。"
	)
	assert_true(
		achievements.is_unlocked(&"achievement.reach_2048"),
		"方块高水位不应依赖一次性 UI 通知。"
	)
	_dispose_setup(reloaded)


func test_achievement_dialog_renders_and_adapts_layout() -> void:
	var setup: Dictionary = await _create_setup(
		"gut_achievement_ui_%d" % Time.get_ticks_usec()
	)
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = _get_architecture(setup)
	add_child_autoqfree(context)
	var panel_node: Node = ACHIEVEMENT_LIST_SCENE.instantiate()
	assert_true(
		panel_node is AchievementListDialog,
		"成就场景根节点应使用强类型控制器。"
	)
	if not panel_node is AchievementListDialog:
		_dispose_setup(setup)
		return
	var panel: AchievementListDialog = panel_node
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(1200.0, 800.0)
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var list: VBoxContainer = panel.get_node(
		"OuterMargin/Surface/InnerMargin/RootVBox/AchievementScroll/AchievementList"
	) as VBoxContainer
	var header: BoxContainer = panel.get_node(
		"OuterMargin/Surface/InnerMargin/RootVBox/Header"
	) as BoxContainer
	var filters: BoxContainer = panel.get_node(
		"OuterMargin/Surface/InnerMargin/RootVBox/Filters"
	) as BoxContainer
	assert_true(
		list.get_child_count() == _EXPECTED_ACHIEVEMENT_COUNT,
		"成就列表应呈现目录中的全部定义。"
	)
	assert_false(header.vertical, "宽屏成就标题栏应横向排列。")

	panel.size = Vector2(390.0, 844.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(header.vertical, "窄屏成就标题栏应纵向排列。")
	assert_true(filters.vertical, "窄屏成就筛选控件应纵向排列。")

	context.remove_child(panel)
	panel.queue_free()
	await get_tree().process_frame
	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_setup(
	save_dir_name: String,
	include_achievement_system: bool = true
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var save_graph: GameSaveGraphUtility = _make_save_graph()
	var catalog: AchievementCatalogUtility = AchievementCatalogUtility.new()
	var quest: GFQuestUtility = GFQuestUtility.new()
	var progress_stats_system: ProgressStatsSystem = ProgressStatsSystem.new()
	var achievement_system: AchievementSystem = null

	storage.save_dir_name = save_dir_name
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, GFSaveGraphUtility.new())
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFViewportUtility, GFViewportUtility.new())
	await architecture.register_utility(GFAssetUtility, GFAssetUtility.new())
	await architecture.register_utility(
		GFResourceResolverUtility,
		GFResourceResolverUtility.new()
	)
	await architecture.register_utility(
		ProjectResourceCatalogUtility,
		ProjectResourceCatalogUtility.new()
	)
	await architecture.register_utility(AchievementCatalogUtility, catalog)
	await architecture.register_utility(GFQuestUtility, quest)
	await architecture.register_system(ProgressStatsSystem, progress_stats_system)
	if include_achievement_system:
		achievement_system = AchievementSystem.new()
		await architecture.register_system(AchievementSystem, achievement_system)
	await architecture.init()
	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"catalog": catalog,
		"quest": quest,
		"progress_stats_system": progress_stats_system,
		"achievement_system": achievement_system,
	}


func _make_save_graph() -> GameSaveGraphUtility:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GFSaveScope.Phase.EARLY
	))
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		TileDiscoverySaveData.new(),
		GFSaveScope.Phase.NORMAL
	))
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID,
		AchievementSaveData.new(),
		GFSaveScope.Phase.LATE
	))
	return save_graph


func _dispose_setup(setup: Dictionary, delete_profile: bool = true) -> void:
	var save_graph_value: Variant = setup.get("save_graph")
	if save_graph_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = save_graph_value
		assert_true(
			save_graph.flush_pending_save() == OK,
			"成就测试结束前应收敛排队玩家数据。"
		)
	var storage_value: Variant = setup.get("storage")
	if delete_profile and storage_value is GFStorageUtility:
		var storage: GFStorageUtility = storage_value
		var delete_error: Error = storage.delete_file(
			GameSaveGraphUtility.PROFILE_FILE_NAME
		)
		assert_true(
			delete_error == OK or delete_error == ERR_FILE_NOT_FOUND,
			"成就测试玩家数据应可清理。"
		)
	_get_architecture(setup).dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_catalog(setup: Dictionary) -> AchievementCatalogUtility:
	var value: Variant = setup.get("catalog")
	if value is AchievementCatalogUtility:
		var catalog: AchievementCatalogUtility = value
		return catalog
	assert_true(false, "测试 setup 缺少 AchievementCatalogUtility。")
	return AchievementCatalogUtility.new()


func _get_progress_stats_system(setup: Dictionary) -> ProgressStatsSystem:
	var value: Variant = setup.get("progress_stats_system")
	if value is ProgressStatsSystem:
		var system: ProgressStatsSystem = value
		return system
	assert_true(false, "测试 setup 缺少 ProgressStatsSystem。")
	return ProgressStatsSystem.new()


func _get_achievement_system(setup: Dictionary) -> AchievementSystem:
	var value: Variant = setup.get("achievement_system")
	if value is AchievementSystem:
		var system: AchievementSystem = value
		return system
	assert_true(false, "测试 setup 缺少 AchievementSystem。")
	return AchievementSystem.new()


func _get_quest(setup: Dictionary) -> GFQuestUtility:
	var value: Variant = setup.get("quest")
	if value is GFQuestUtility:
		var quest: GFQuestUtility = value
		return quest
	assert_true(false, "测试 setup 缺少 GFQuestUtility。")
	return GFQuestUtility.new()
