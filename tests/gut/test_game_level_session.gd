## 验证游戏初始化会把当前一局登记到 GFLevelUtility。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_CONFIG_PATH: String = "res://features/gameplay/resources/modes/classic_mode_config.tres"


# --- 测试用例 ---

func test_game_initialization_records_current_session_in_level_utility() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var app_config: AppConfigModel = AppConfigModel.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var mode_cache: GameModeConfigCacheUtility = GameModeConfigCacheUtility.new()
	var level_utility: GFLevelUtility = GFLevelUtility.new()
	var command_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()

	await architecture.register_model(AppConfigModel, app_config)
	await architecture.register_model(GridModel, GridModel.new())
	await architecture.register_model(GameStatusModel, GameStatusModel.new())
	await architecture.register_model(CurrentGameModel, CurrentGameModel.new())
	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameModeConfigCacheUtility, mode_cache)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, command_history)
	await architecture.register_utility(GFLevelUtility, level_utility)
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.register_system(GameFlowSystem, GameFlowSystem.new())
	await architecture.register_system(GameInitSystem, GameInitSystem.new())
	await architecture.init()

	app_config.selected_mode_config_path.set_value(_CLASSIC_MODE_CONFIG_PATH)
	app_config.selected_grid_size.set_value(5)
	app_config.selected_seed.set_value(12345)

	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)

	var level_data: Dictionary = level_utility.current_level_data
	assert_true(GFVariantData.to_string_name(level_utility.current_level_id) == &"new_game:classic_mode_config:5:12345", "当前一局应登记为稳定的 gf level session。")
	assert_true(GFVariantData.to_string_name(level_data.get("kind")) == &"2048_session", "session 元数据应标记项目层语义类型。")
	assert_true(GFVariantData.to_string_name(level_data.get("source")) == &"new_game", "普通开局应记录来源。")
	assert_true(GFVariantData.to_text(level_data.get("mode_config_path")) == _CLASSIC_MODE_CONFIG_PATH, "session 元数据应记录模式配置路径。")
	assert_true(GFVariantData.to_int(level_data.get("grid_size")) == 5, "session 元数据应记录棋盘尺寸。")
	assert_true(GFVariantData.to_int(level_data.get("initial_seed")) == 12345, "session 元数据应记录初始种子。")
	assert_false(GFVariantData.to_bool(level_data.get("is_replay_mode")), "普通开局不应标记为回放模式。")

	architecture.dispose()
