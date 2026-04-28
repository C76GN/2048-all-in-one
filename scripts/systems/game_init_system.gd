# scripts/systems/game_init_system.gd

## GameInitSystem: 负责提取原 GamePlay.gd 中的装配逻辑。
class_name GameInitSystem
extends GFSystem


# --- 常量 ---

const GAME_MODE_CONFIG_CACHE = preload("res://scripts/utilities/game_mode_config_cache.gd")


# --- 私有变量 ---

var _seed_utility: GFSeedUtility
var _rule_system: RuleSystem
var _game_flow_system: GameFlowSystem
var _command_history: GFCommandHistoryUtility
var _log: GFLogUtility


# --- Godot 生命周期方法 ---

func ready() -> void:
	_seed_utility = get_utility(GFSeedUtility) as GFSeedUtility
	_command_history = get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	_log = get_utility(GFLogUtility) as GFLogUtility
	_rule_system = get_system(RuleSystem) as RuleSystem
	_game_flow_system = get_system(GameFlowSystem) as GameFlowSystem

	register_simple_event(EventNames.REQUEST_GAME_INITIALIZATION, _on_request_initialization)


func dispose() -> void:
	unregister_simple_event(EventNames.REQUEST_GAME_INITIALIZATION, _on_request_initialization)


# --- 私有/辅助方法 ---

func _restore_bookmark_command_history(bookmark_data: BookmarkData) -> void:
	if not is_instance_valid(_command_history) or not is_instance_valid(bookmark_data):
		return

	var history_data: Variant = bookmark_data.game_state_history
	if history_data is Dictionary and not history_data.is_empty():
		_command_history.deserialize_full_history(history_data, Callable(MoveCommand, "deserialize"))
	elif history_data is Array and not history_data.is_empty():
		_command_history.deserialize_history(history_data, Callable(MoveCommand, "deserialize"))


# --- 信号处理函数 ---

func _on_request_initialization(_payload: Variant = null) -> void:
	var app_config := get_model(AppConfigModel) as AppConfigModel
	if not app_config:
		return

	var replay_data: ReplayData = app_config.current_replay_data.get_value()
	var loaded_bookmark_data: BookmarkData = app_config.selected_bookmark_data.get_value()

	app_config.current_replay_data.set_value(null)
	app_config.selected_bookmark_data.set_value(null)

	if _command_history:
		_command_history.clear()

	var game_ready_data := GameReadyData.new()
	game_ready_data.is_replay_mode = is_instance_valid(replay_data)
	game_ready_data.loaded_bookmark_data = loaded_bookmark_data
	game_ready_data.replay_data_resource = replay_data

	var config_path: String = app_config.selected_mode_config_path.get_value()
	var grid_size := 4
	var init_seed := 0

	if game_ready_data.is_replay_mode:
		config_path = replay_data.mode_config_path
		grid_size = replay_data.grid_size
		init_seed = replay_data.initial_seed
	elif is_instance_valid(loaded_bookmark_data):
		config_path = loaded_bookmark_data.mode_config_path
		grid_size = loaded_bookmark_data.board_snapshot.get(
			&"grid_size",
			loaded_bookmark_data.board_snapshot.get("grid_size", 4)
		)
		init_seed = loaded_bookmark_data.initial_seed
	else:
		grid_size = app_config.selected_grid_size.get_value()
		var config_seed: int = app_config.selected_seed.get_value()
		if _log:
			_log.info("GameInitSystem", "Normal mode: config_seed=%d" % config_seed)
		if config_seed != 0:
			init_seed = config_seed
		else:
			init_seed = int(Time.get_unix_time_from_system())
		if _log:
			_log.info("GameInitSystem", "Final init_seed=%d" % init_seed)

	game_ready_data.current_grid_size = grid_size
	game_ready_data.initial_seed = init_seed

	var mode_config: GameModeConfig = GAME_MODE_CONFIG_CACHE.get_config(config_path)
	if not is_instance_valid(mode_config):
		if _log:
			_log.error("GameInitSystem", "GameModeConfig load failed: %s" % config_path)
		return
	if not mode_config.validate():
		if _log:
			_log.error("GameInitSystem", "GameModeConfig validation failed: %s" % config_path)
		return

	game_ready_data.mode_config = mode_config
	game_ready_data.interaction_rule = mode_config.interaction_rule.duplicate() as InteractionRule
	game_ready_data.movement_rule = mode_config.movement_rule.duplicate() as MovementRule
	game_ready_data.game_over_rule = mode_config.game_over_rule.duplicate() as GameOverRule

	if _log:
		_log.info("GameInitSystem", "Calling set_global_seed(%d)" % init_seed)
	if is_instance_valid(_seed_utility):
		_seed_utility.set_global_seed(init_seed)

	var save_system := get_system(SaveSystem) as SaveSystem
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	var high_score: int = save_system.get_high_score(mode_id, grid_size) if save_system else 0

	var game_status_model := get_model(GameStatusModel) as GameStatusModel
	if is_instance_valid(loaded_bookmark_data):
		if is_instance_valid(_seed_utility):
			if not loaded_bookmark_data.rng_full_state.is_empty():
				_seed_utility.set_full_state(loaded_bookmark_data.rng_full_state)
			else:
				_seed_utility.set_state(loaded_bookmark_data.rng_state)
		if game_status_model:
			game_status_model.score.set_value(loaded_bookmark_data.score)
			game_status_model.move_count.set_value(loaded_bookmark_data.move_count)
			game_status_model.monsters_killed.set_value(loaded_bookmark_data.monsters_killed)
			game_status_model.highest_tile.set_value(loaded_bookmark_data.highest_tile)
			game_status_model.status_message.set_value(loaded_bookmark_data.status_message)
			game_status_model.extra_stats.set_value(loaded_bookmark_data.extra_stats.duplicate(true))
			game_status_model.high_score.set_value(high_score)

		_restore_bookmark_command_history(loaded_bookmark_data)
	else:
		if game_status_model:
			game_status_model.score.set_value(0)
			game_status_model.move_count.set_value(0)
			game_status_model.monsters_killed.set_value(0)
			game_status_model.highest_tile.set_value(0)
			game_status_model.status_message.set_value("")
			game_status_model.extra_stats.set_value({})
			game_status_model.high_score.set_value(high_score)

	game_ready_data.initial_high_score = high_score

	if _game_flow_system:
		_game_flow_system.setup(_rule_system, game_ready_data.game_over_rule)

	for rule_resource in mode_config.spawn_rules:
		var rule_instance: SpawnRule = rule_resource.duplicate() as SpawnRule
		game_ready_data.all_spawn_rules.append(rule_instance)

	_rule_system.register_rules(game_ready_data.all_spawn_rules)

	if is_instance_valid(loaded_bookmark_data) and not loaded_bookmark_data.rules_states.is_empty():
		var rules_states: Array = loaded_bookmark_data.rules_states
		for i in range(min(game_ready_data.all_spawn_rules.size(), rules_states.size())):
			game_ready_data.all_spawn_rules[i].set_state(rules_states[i])

	var current_game_model := get_model(CurrentGameModel) as CurrentGameModel
	if current_game_model:
		current_game_model.mode_config.set_value(mode_config)
		current_game_model.current_grid_size.set_value(grid_size)
		current_game_model.initial_seed.set_value(init_seed)
		current_game_model.initial_high_score.set_value(game_ready_data.initial_high_score)
		current_game_model.is_replay_mode.set_value(game_ready_data.is_replay_mode)

	send_event(game_ready_data)
