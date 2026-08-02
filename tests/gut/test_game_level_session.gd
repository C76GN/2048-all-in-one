## 验证游戏初始化会把当前一局登记到 GFLevelUtility。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_CONFIG_PATH: String = "res://features/gameplay/resources/modes/classic_mode_config.tres"


# --- 测试用例 ---

func test_bookmark_target_contract_must_match_current_mode() -> void:
	var init_system: GameInitSystem = GameInitSystem.new()
	var bookmark: BookmarkData = BookmarkData.new()
	var mode_resource: Resource = load(_CLASSIC_MODE_CONFIG_PATH)
	assert_true(mode_resource is GameModeConfig, "测试必须能加载经典模式。")
	if not mode_resource is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_resource
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	init_system._determinism = determinism
	assert_true(bookmark.configure_ruleset(mode_config, determinism), "测试书签应冻结当前规则集。")
	bookmark.target_tile_value = 1024

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
	var current_game: CurrentGameModel = CurrentGameModel.new()
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var state_system: GameStateSystem = GameStateSystem.new()

	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, TileCompositionUtility.new())
	await architecture.register_model(AppConfigModel, app_config)
	await architecture.register_model(GridModel, GridModel.new())
	await architecture.register_model(GameStatusModel, GameStatusModel.new())
	await architecture.register_model(CurrentGameModel, current_game)
	await architecture.register_utility(GFResourceBroker, GFResourceBroker.new())
	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameModeCatalogUtility, mode_catalog)
	await architecture.register_utility(GameDeterminismUtility, determinism)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, command_history)
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFNotificationUtility, GFNotificationUtility.new())
	await architecture.register_utility(GFTimeUtility, GFTimeUtility.new())
	await architecture.register_utility(GamePauseUtility, GamePauseUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFLevelUtility, level_utility)
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.register_system(GameStateSystem, state_system)
	await architecture.register_system(GameFlowSystem, _SessionFlowSystem.new())
	await architecture.register_system(GameInitSystem, _SessionInitSystem.new())
	await architecture.init()

	var selected_topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(5, 5))
	app_config.selected_mode_config_path.set_value(_CLASSIC_MODE_CONFIG_PATH)
	app_config.selected_board_topology.set_value(selected_topology)
	app_config.selected_seed.set_value(12345)
	command_history.record(MoveCommand.new(Vector2i.LEFT))
	assert_true(command_history.undo_count == 1, "测试前置历史应模拟上一局残留命令。")

	var rejected_bookmark: BookmarkData = BookmarkData.new()
	rejected_bookmark.mode_config_path = _CLASSIC_MODE_CONFIG_PATH
	rejected_bookmark.target_tile_value = 2048
	rejected_bookmark.ruleset_id = &"gameplay.incompatible"
	rejected_bookmark.ruleset_version = 1
	rejected_bookmark.ruleset_fingerprint = "f".repeat(64)
	app_config.selected_bookmark_data.set_value(rejected_bookmark)
	var previous_level_data: Dictionary = {"kind": &"previous"}
	var _previous_level: Dictionary = level_utility.start_level(&"previous-session", previous_level_data)
	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)
	assert_push_error("书签规则集或目标契约与模式不一致")
	var rejected_selection: Variant = app_config.selected_bookmark_data.get_value()
	var rejected_bookmark_preserved: bool = is_same(rejected_selection, rejected_bookmark)
	assert_true(
		rejected_bookmark_preserved,
		"书签初始化预验证失败时必须保留用户选择。"
	)
	assert_true(
		level_utility.current_level_id == &"previous-session",
		"书签初始化预验证失败时不得启动新 level。"
	)
	assert_true(command_history.undo_count == 1, "书签初始化预验证失败时不得清空上一局历史。")

	app_config.selected_bookmark_data.set_value(null)
	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)
	assert_true(command_history.undo_count == 0, "新关卡事务必须清空上一局 GF 命令历史。")

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

	var current_state: Dictionary = state_system.get_full_game_state()
	var invalid_history_bookmark: BookmarkData = BookmarkData.new()
	invalid_history_bookmark.mode_config_path = _CLASSIC_MODE_CONFIG_PATH
	var current_mode_value: Variant = current_game.mode_config.get_value()
	assert_true(current_mode_value is GameModeConfig, "初始化后应暴露当前模式。")
	if current_mode_value is GameModeConfig:
		var current_mode: GameModeConfig = current_mode_value
		assert_true(
			invalid_history_bookmark.configure_ruleset(
				current_mode,
				determinism
			),
			"历史失败夹具应冻结当前规则集。"
		)
	invalid_history_bookmark.initial_seed = 12345
	invalid_history_bookmark.score = GFVariantData.get_option_int(current_state, &"score", 0)
	invalid_history_bookmark.move_count = GFVariantData.get_option_int(
		current_state,
		&"move_count",
		0
	)
	invalid_history_bookmark.ratio_resolutions = GFVariantData.get_option_int(
		current_state,
		&"ratio_resolutions",
		0
	)
	invalid_history_bookmark.highest_tile = GFVariantData.get_option_int(
		current_state,
		&"highest_tile",
		0
	)
	invalid_history_bookmark.target_tile_value = GFVariantData.get_option_int(
		current_state,
		&"target_tile_value",
		0
	)
	invalid_history_bookmark.target_reached = GFVariantData.get_option_bool(
		current_state,
		&"target_reached",
		false
	)
	invalid_history_bookmark.extra_stats = GFVariantData.get_option_dictionary(
		current_state,
		&"extra_stats"
	).duplicate(true)
	invalid_history_bookmark.rng_full_state = GFVariantData.get_option_dictionary(
		current_state,
		&"rng_full_state"
	).duplicate(true)
	invalid_history_bookmark.board_snapshot = GFVariantData.get_option_dictionary(
		current_state,
		&"board_snapshot"
	).duplicate(true)
	invalid_history_bookmark.rules_states = GFVariantData.get_option_dictionary(
		current_state,
		&"rules_states"
	).duplicate(true)
	invalid_history_bookmark.game_state_history = {
		"undo": [{
			&"schema_version": MoveCommand.SERIALIZATION_SCHEMA_VERSION,
			&"direction_x": 1,
			&"direction_y": 0,
			&"snapshot": {},
			&"reverse_map": {},
			&"is_baseline": false,
		}],
		"redo": [],
	}
	command_history.record(MoveCommand.new(Vector2i.LEFT))
	var committed_level_id: StringName = level_utility.current_level_id
	app_config.selected_bookmark_data.set_value(invalid_history_bookmark)
	architecture.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)
	assert_push_error("书签命令历史包含不可恢复快照")
	var invalid_history_selection: Variant = app_config.selected_bookmark_data.get_value()
	var invalid_history_bookmark_preserved: bool = is_same(
		invalid_history_selection,
		invalid_history_bookmark
	)
	assert_true(
		invalid_history_bookmark_preserved,
		"含无效 undo 快照的书签必须保留选择并允许修复或删除。"
	)
	assert_true(
		level_utility.current_level_id == committed_level_id,
		"无效历史必须在启动新 level 前被拒绝。"
	)
	assert_true(command_history.undo_count == 1, "无效历史不得清空当前 GF 命令栈。")

	architecture.dispose()


# --- 内部类 ---

## 关卡 session 测试只需要 GameInit 调用 setup，不运行完整对局状态机。
class _SessionFlowSystem extends GameFlowSystem:
	func get_required_models() -> Array[Script]:
		return []

	func get_required_systems() -> Array[Script]:
		return []

	func get_required_utilities() -> Array[Script]:
		return []

	func ready() -> void:
		pass


## 回放/统计属于本测试不覆盖的可选读路径；其余 GameInit DAG 保持真实。
class _SessionInitSystem extends GameInitSystem:
	func get_required_systems() -> Array[Script]:
		return [GameFlowSystem, GameStateSystem, RuleSystem]

	func _get_progress_stats_system() -> ProgressStatsSystem:
		return null
