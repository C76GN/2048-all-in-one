## 验证游戏初始化会把当前一局登记到 GFLevelUtility。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_CONFIG_PATH: String = "res://features/gameplay/resources/modes/classic_mode_config.tres"


# --- 测试用例 ---

func test_bookmark_target_contract_must_match_current_mode() -> void:
	var init_system: GameInitSystem = GameInitSystem.new()
	var bookmark: BookmarkData = BookmarkData.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	bookmark.target_tile_value = 1024
	mode_config.target_tile_value = 2048

	assert_false(
		init_system._is_bookmark_mode_contract_valid(bookmark, mode_config),
		"书签目标值与当前模式不一致时必须拒绝恢复。"
	)
	bookmark.target_tile_value = 2048
	assert_true(
		init_system._is_bookmark_mode_contract_valid(bookmark, mode_config),
		"目标契约一致的当前书签应允许恢复。"
	)


func test_game_initialization_records_current_session_in_level_utility() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var app_config: AppConfigModel = AppConfigModel.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var mode_catalog: GameModeCatalogUtility = GameModeCatalogUtility.new()
	var level_utility: GFLevelUtility = GFLevelUtility.new()
	var command_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()

	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, TileCompositionUtility.new())
	await architecture.register_model(AppConfigModel, app_config)
	await architecture.register_model(GridModel, GridModel.new())
	await architecture.register_model(GameStatusModel, GameStatusModel.new())
	await architecture.register_model(CurrentGameModel, CurrentGameModel.new())
	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameModeCatalogUtility, mode_catalog)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, command_history)
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_utility(GFTimeUtility, GFTimeUtility.new())
	await architecture.register_utility(GamePauseUtility, GamePauseUtility.new())
	await architecture.register_utility(GFLevelUtility, level_utility)
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.register_system(GameFlowSystem, GameFlowSystem.new())
	await architecture.register_system(GameInitSystem, GameInitSystem.new())
	await architecture.init()

	var selected_topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(5, 5))
	app_config.selected_mode_config_path.set_value(_CLASSIC_MODE_CONFIG_PATH)
	app_config.selected_board_topology.set_value(selected_topology)
	app_config.selected_seed.set_value(12345)

	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)

	var level_data: Dictionary = level_utility.current_level_data
	var expected_level_id: StringName = StringName(
		"new_game:classic_mode_config:%s:12345" % selected_topology.get_stable_key()
	)
	assert_true(GFVariantData.to_string_name(level_utility.current_level_id) == expected_level_id, "当前一局应登记为稳定的 gf level session。")
	assert_true(GFVariantData.to_string_name(level_data.get("kind")) == &"2048_session", "session 元数据应标记项目层语义类型。")
	assert_true(GFVariantData.to_string_name(level_data.get("source")) == &"new_game", "普通开局应记录来源。")
	assert_true(GFVariantData.to_text(level_data.get("mode_config_path")) == _CLASSIC_MODE_CONFIG_PATH, "session 元数据应记录模式配置路径。")
	var board_size_value: Variant = level_data.get("board_size")
	var board_size_matches: bool = false
	if board_size_value is Vector2i:
		var board_size: Vector2i = board_size_value
		board_size_matches = board_size == Vector2i(5, 5)
	assert_true(board_size_matches, "session 元数据应记录棋盘边界尺寸。")
	assert_true(GFVariantData.to_int(level_data.get("board_cell_count")) == 25, "session 元数据应记录活跃单元数量。")
	assert_true(GFVariantData.to_text(level_data.get("board_key")) == selected_topology.get_stable_key(), "session 元数据应记录稳定棋盘键。")
	assert_true(GFVariantData.to_int(level_data.get("initial_seed")) == 12345, "session 元数据应记录初始种子。")
	assert_false(GFVariantData.to_bool(level_data.get("is_replay_mode")), "普通开局不应标记为回放模式。")

	architecture.dispose()
