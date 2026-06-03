## 验证游戏初始化会把当前一局登记到 GFLevelUtility。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_CONFIG_PATH: String = "res://resources/modes/classic_mode_config.tres"


# --- 测试用例 ---

func test_game_initialization_records_current_session_in_level_utility() -> void:
	var architecture := GFArchitecture.new()
	var app_config := AppConfigModel.new()
	var level_utility := GFLevelUtility.new()
	var command_history := GFCommandHistoryUtility.new()

	architecture.register_model(AppConfigModel, app_config)
	architecture.register_model(GridModel, GridModel.new())
	architecture.register_model(GameStatusModel, GameStatusModel.new())
	architecture.register_model(CurrentGameModel, CurrentGameModel.new())
	architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	architecture.register_utility(GFCommandHistoryUtility, command_history)
	architecture.register_utility(GFLevelUtility, level_utility)
	architecture.register_system(RuleSystem, RuleSystem.new())
	architecture.register_system(GameFlowSystem, GameFlowSystem.new())
	architecture.register_system(GameInitSystem, GameInitSystem.new())
	await architecture.init()

	app_config.selected_mode_config_path.set_value(_CLASSIC_MODE_CONFIG_PATH)
	app_config.selected_grid_size.set_value(5)
	app_config.selected_seed.set_value(12345)

	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)

	assert_eq(level_utility.current_level_id, &"new_game:classic_mode_config:5:12345", "当前一局应登记为稳定的 gf level session。")
	assert_eq(level_utility.current_level_data.get("kind"), &"2048_session", "session 元数据应标记项目层语义类型。")
	assert_eq(level_utility.current_level_data.get("source"), &"new_game", "普通开局应记录来源。")
	assert_eq(level_utility.current_level_data.get("mode_config_path"), _CLASSIC_MODE_CONFIG_PATH, "session 元数据应记录模式配置路径。")
	assert_eq(level_utility.current_level_data.get("grid_size"), 5, "session 元数据应记录棋盘尺寸。")
	assert_eq(level_utility.current_level_data.get("initial_seed"), 12345, "session 元数据应记录初始种子。")
	assert_false(level_utility.current_level_data.get("is_replay_mode"), "普通开局不应标记为回放模式。")

	architecture.dispose()
