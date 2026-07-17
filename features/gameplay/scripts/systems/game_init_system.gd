## GameInitSystem: 负责当前对局的模式、规则和模型初始化装配。
class_name GameInitSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GameInitSystem"
const _LEVEL_KIND_GAME_SESSION: StringName = &"2048_session"
const _LEVEL_SOURCE_NEW_GAME: StringName = &"new_game"
const _LEVEL_SOURCE_BOOKMARK: StringName = &"bookmark"
const _LEVEL_SOURCE_REPLAY: StringName = &"replay"


# --- 私有变量 ---

var _seed_utility: GFSeedUtility
var _rule_system: RuleSystem
var _game_flow_system: GameFlowSystem
var _command_history: GFCommandHistoryUtility
var _level_utility: GFLevelUtility
var _mode_catalog: GameModeCatalogUtility
var _grid_model: GridModel
var _log: GFLogUtility
var _clock: GameClockUtility


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [AppConfigModel, CurrentGameModel, GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [GameFlowSystem, RuleSystem, SaveSystem]


func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GameModeCatalogUtility,
		GFCommandHistoryUtility,
		GFLevelUtility,
		GFLogUtility,
		GFSeedUtility,
	]


func ready() -> void:
	_seed_utility = _get_seed_utility()
	_command_history = _get_command_history_utility()
	_level_utility = _get_level_utility()
	_mode_catalog = _get_mode_catalog_utility()
	_log = _get_log_utility()
	_clock = _get_clock_utility()
	_rule_system = _get_rule_system()
	_game_flow_system = _get_game_flow_system()
	_grid_model = _get_grid_model()

	register_simple_event(EventNames.REQUEST_GAME_INITIALIZATION, GFEventListener.from_method(self, &"_on_request_initialization", 1))


func dispose() -> void:
	_seed_utility = null
	_rule_system = null
	_game_flow_system = null
	_command_history = null
	_level_utility = null
	_mode_catalog = null
	_grid_model = null
	_log = null
	_clock = null


# --- 私有/辅助方法 ---

func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


func _get_level_utility() -> GFLevelUtility:
	var utility_value: Object = get_utility(GFLevelUtility)
	if utility_value is GFLevelUtility:
		var level_utility: GFLevelUtility = utility_value
		return level_utility
	return null


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_unix_timestamp() -> int:
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	_clock = _get_clock_utility()
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	push_error("[GameInitSystem] 缺少 GameClockUtility，无法生成默认初始种子。")
	return 0


func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null


func _get_game_flow_system() -> GameFlowSystem:
	var system_value: Object = get_system(GameFlowSystem)
	if system_value is GameFlowSystem:
		var game_flow_system: GameFlowSystem = system_value
		return game_flow_system
	return null


func _get_save_system() -> SaveSystem:
	var system_value: Object = get_system(SaveSystem)
	if system_value is SaveSystem:
		var save_system: SaveSystem = system_value
		return save_system
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var game_status_model: GameStatusModel = model_value
		return game_status_model
	return null


func _get_current_game_model() -> CurrentGameModel:
	var model_value: Object = get_model(CurrentGameModel)
	if model_value is CurrentGameModel:
		var current_game_model: CurrentGameModel = model_value
		return current_game_model
	return null


func _get_replay_data(app_config: AppConfigModel) -> ReplayData:
	if not is_instance_valid(app_config):
		return null

	var replay_value: Variant = app_config.current_replay_data.get_value()
	if replay_value is ReplayData:
		var replay_data: ReplayData = replay_value
		return replay_data
	return null


func _get_bookmark_data(app_config: AppConfigModel) -> BookmarkData:
	if not is_instance_valid(app_config):
		return null

	var bookmark_value: Variant = app_config.selected_bookmark_data.get_value()
	if bookmark_value is BookmarkData:
		var bookmark_data: BookmarkData = bookmark_value
		return bookmark_data
	return null


func _duplicate_interaction_rule(rule_resource: InteractionRule) -> InteractionRule:
	if not is_instance_valid(rule_resource):
		return null

	var duplicated_resource: Resource = rule_resource.duplicate()
	if duplicated_resource is InteractionRule:
		var interaction_rule: InteractionRule = duplicated_resource
		return interaction_rule
	return null


func _duplicate_movement_rule(rule_resource: MovementRule) -> MovementRule:
	if not is_instance_valid(rule_resource):
		return null

	var duplicated_resource: Resource = rule_resource.duplicate()
	if duplicated_resource is MovementRule:
		var movement_rule: MovementRule = duplicated_resource
		return movement_rule
	return null


func _duplicate_game_over_rule(rule_resource: GameOverRule) -> GameOverRule:
	if not is_instance_valid(rule_resource):
		return null

	var duplicated_resource: Resource = rule_resource.duplicate()
	if duplicated_resource is GameOverRule:
		var game_over_rule: GameOverRule = duplicated_resource
		return game_over_rule
	return null


func _restore_bookmark_command_history(bookmark_data: BookmarkData) -> void:
	if not is_instance_valid(_command_history) or not is_instance_valid(bookmark_data):
		return

	if not bookmark_data.game_state_history.is_empty():
		_command_history.deserialize_full_history(
			bookmark_data.game_state_history,
			Callable(MoveCommand, "deserialize")
		)


func _is_bookmark_mode_contract_valid(
	bookmark_data: BookmarkData,
	mode_config: GameModeConfig
) -> bool:
	if not is_instance_valid(bookmark_data) or not is_instance_valid(mode_config):
		return false
	return bookmark_data.target_tile_value == maxi(mode_config.target_tile_value, 0)


func _start_level_session(
	level_source: StringName,
	mode_config: GameModeConfig,
	game_ready_data: GameReadyData
) -> void:
	if not is_instance_valid(mode_config):
		return
	if not is_instance_valid(_level_utility):
		push_error("[GameInitSystem] 缺少 GFLevelUtility，无法启动对局生命周期。")
		return

	var level_id: StringName = _build_level_session_id(level_source, mode_config, game_ready_data)
	var level_data: Dictionary = _build_level_session_data(level_source, mode_config, game_ready_data)
	var _level_session: Dictionary = _level_utility.start_level(level_id, level_data)


func _build_level_session_id(
	level_source: StringName,
	mode_config: GameModeConfig,
	game_ready_data: GameReadyData
) -> StringName:
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	var board_key: String = (
		game_ready_data.board_topology.get_stable_key()
		if is_instance_valid(game_ready_data.board_topology)
		else "invalid"
	)
	return StringName("%s:%s:%s:%d" % [
		String(level_source),
		mode_id,
		board_key,
		game_ready_data.initial_seed,
	])


func _build_level_session_data(
	level_source: StringName,
	mode_config: GameModeConfig,
	game_ready_data: GameReadyData
) -> Dictionary:
	var mode_path: String = mode_config.resource_path
	var topology: BoardTopology = game_ready_data.board_topology
	return {
		"kind": _LEVEL_KIND_GAME_SESSION,
		"source": level_source,
		"mode_id": mode_path.get_file().get_basename(),
		"mode_config_path": mode_path,
		"board_key": topology.get_stable_key() if is_instance_valid(topology) else "",
		"board_size": topology.get_bounds_size() if is_instance_valid(topology) else Vector2i.ZERO,
		"board_cell_count": topology.get_cell_count() if is_instance_valid(topology) else 0,
		"initial_seed": game_ready_data.initial_seed,
		"is_replay_mode": game_ready_data.is_replay_mode,
		"has_bookmark": is_instance_valid(game_ready_data.loaded_bookmark_data),
		"has_replay": is_instance_valid(game_ready_data.replay_data_resource),
	}


func _resolve_session_topology(
	app_config: AppConfigModel,
	replay_data: ReplayData,
	bookmark_data: BookmarkData,
	mode_config: GameModeConfig
) -> BoardTopology:
	var topology: BoardTopology = null
	if is_instance_valid(replay_data):
		topology = BoardTopology.from_dict(replay_data.initial_board_topology)
	elif is_instance_valid(bookmark_data):
		topology = BoardTopology.from_dict(
			GFVariantData.get_option_dictionary(bookmark_data.board_snapshot, &"topology")
		)
	else:
		var selected_value: Variant = app_config.selected_board_topology.get_value()
		if selected_value is BoardTopology:
			var selected_topology: BoardTopology = selected_value
			topology = _duplicate_topology(selected_topology)
		elif is_instance_valid(mode_config.board_topology_template):
			topology = mode_config.board_topology_template.create_topology()

	if topology == null or not is_instance_valid(mode_config.board_topology_template):
		return null
	if not mode_config.board_topology_template.accepts_topology(topology):
		return null
	return topology


static func _duplicate_topology(source: BoardTopology) -> BoardTopology:
	if not is_instance_valid(source):
		return null
	var duplicated: Resource = source.duplicate(true)
	if duplicated is BoardTopology:
		var topology: BoardTopology = duplicated
		return topology
	return null


# --- 信号处理函数 ---

func _on_request_initialization(_payload: Variant = null) -> void:
	var app_config: AppConfigModel = _get_app_config_model()
	if not is_instance_valid(app_config):
		return

	var replay_data: ReplayData = _get_replay_data(app_config)
	var loaded_bookmark_data: BookmarkData = _get_bookmark_data(app_config)
	var level_source: StringName = _LEVEL_SOURCE_NEW_GAME

	if is_instance_valid(replay_data):
		loaded_bookmark_data = null
		level_source = _LEVEL_SOURCE_REPLAY
	elif is_instance_valid(loaded_bookmark_data):
		replay_data = null
		level_source = _LEVEL_SOURCE_BOOKMARK

	app_config.current_replay_data.set_value(null)
	app_config.selected_bookmark_data.set_value(null)

	if not is_instance_valid(_level_utility):
		push_error("[GameInitSystem] 缺少 GFLevelUtility，无法清理上一局运行时状态。")
		return
	_level_utility.clear_level_runtime()

	var game_ready_data: GameReadyData = GameReadyData.new()
	game_ready_data.is_replay_mode = is_instance_valid(replay_data)
	game_ready_data.loaded_bookmark_data = loaded_bookmark_data
	game_ready_data.replay_data_resource = replay_data

	var config_path: String = GFVariantData.to_text(app_config.selected_mode_config_path.get_value(), "")
	var init_seed: int = 0

	if game_ready_data.is_replay_mode:
		config_path = replay_data.mode_config_path
		init_seed = replay_data.initial_seed
	elif is_instance_valid(loaded_bookmark_data):
		config_path = loaded_bookmark_data.mode_config_path
		init_seed = loaded_bookmark_data.initial_seed
	else:
		var config_seed: int = GFVariantData.to_int(app_config.selected_seed.get_value(), 0)
		if is_instance_valid(_log):
			_log.debug(_LOG_TAG, "普通模式配置种子: %d" % config_seed)
		if config_seed != 0:
			init_seed = config_seed
		else:
			init_seed = _get_unix_timestamp()
		if is_instance_valid(_log):
			_log.debug(_LOG_TAG, "本局初始种子: %d" % init_seed)

	game_ready_data.initial_seed = init_seed

	if not is_instance_valid(_mode_catalog):
		_mode_catalog = _get_mode_catalog_utility()
	if not is_instance_valid(_mode_catalog):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GameModeCatalogUtility 未注册，无法加载模式配置: %s" % config_path)
		return

	var mode_config: GameModeConfig = _mode_catalog.get_config(config_path)
	if not is_instance_valid(mode_config):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GameModeConfig 加载失败: %s" % config_path)
		return
	if not mode_config.validate():
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GameModeConfig 校验失败: %s" % config_path)
		return

	var board_topology: BoardTopology = _resolve_session_topology(
		app_config,
		replay_data,
		loaded_bookmark_data,
		mode_config
	)
	if board_topology == null:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "无法按当前模式契约解析棋盘拓扑: %s" % config_path)
		return
	game_ready_data.board_topology = board_topology
	if (
		is_instance_valid(loaded_bookmark_data)
		and not _is_bookmark_mode_contract_valid(loaded_bookmark_data, mode_config)
	):
		var target_contract_error: String = (
			"书签目标契约与模式不一致，拒绝恢复: bookmark=%d, mode=%d, path=%s"
			% [
				loaded_bookmark_data.target_tile_value,
				mode_config.target_tile_value,
				config_path,
			]
		)
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, target_contract_error)
		else:
			push_error("[GameInitSystem] %s" % target_contract_error)
		return

	game_ready_data.mode_config = mode_config
	_start_level_session(level_source, mode_config, game_ready_data)
	game_ready_data.interaction_rule = _duplicate_interaction_rule(mode_config.interaction_rule)
	game_ready_data.movement_rule = _duplicate_movement_rule(mode_config.movement_rule)
	game_ready_data.game_over_rule = _duplicate_game_over_rule(mode_config.game_over_rule)
	if (
		not is_instance_valid(game_ready_data.interaction_rule)
		or not is_instance_valid(game_ready_data.movement_rule)
		or not is_instance_valid(game_ready_data.game_over_rule)
	):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GameModeConfig 规则复制失败: %s" % config_path)
		return

	if is_instance_valid(_grid_model):
		if not _grid_model.initialize(
			board_topology,
			game_ready_data.interaction_rule,
			game_ready_data.movement_rule
		):
			return
		if is_instance_valid(loaded_bookmark_data):
			if not _grid_model.restore_from_snapshot(loaded_bookmark_data.board_snapshot):
				return

	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "设置全局随机种子: %d" % init_seed)
	if is_instance_valid(_seed_utility):
		_seed_utility.set_global_seed(init_seed)

	var save_system: SaveSystem = _get_save_system()
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	var high_score: int = 0
	if is_instance_valid(save_system):
		high_score = save_system.get_high_score(mode_id, board_topology.get_stable_key())

	var game_status_model: GameStatusModel = _get_game_status_model()
	if is_instance_valid(loaded_bookmark_data):
		if is_instance_valid(_seed_utility) and not loaded_bookmark_data.rng_full_state.is_empty():
			_seed_utility.set_full_state(loaded_bookmark_data.rng_full_state)
		if is_instance_valid(game_status_model):
			game_status_model.score.set_value(loaded_bookmark_data.score)
			game_status_model.move_count.set_value(loaded_bookmark_data.move_count)
			game_status_model.ratio_resolutions.set_value(loaded_bookmark_data.ratio_resolutions)
			game_status_model.highest_tile.set_value(loaded_bookmark_data.highest_tile)
			game_status_model.set_target_state(
				mode_config.target_tile_value,
				loaded_bookmark_data.target_reached
			)
			game_status_model.extra_stats.set_value(loaded_bookmark_data.extra_stats.duplicate(true))
			game_status_model.high_score.set_value(high_score)

		_restore_bookmark_command_history(loaded_bookmark_data)
	else:
		if is_instance_valid(game_status_model):
			game_status_model.reset_for_new_game(high_score)
			game_status_model.set_target_state(mode_config.target_tile_value, false)

	game_ready_data.initial_high_score = high_score

	if is_instance_valid(_game_flow_system):
		_game_flow_system.setup(_rule_system, game_ready_data.game_over_rule)

	for rule_resource: SpawnRule in mode_config.spawn_rules:
		var duplicated_rule: Resource = rule_resource.duplicate()
		if duplicated_rule is SpawnRule:
			var rule_instance: SpawnRule = duplicated_rule
			game_ready_data.all_spawn_rules.append(rule_instance)

	if is_instance_valid(_rule_system):
		_rule_system.register_rules(game_ready_data.all_spawn_rules)

	if is_instance_valid(loaded_bookmark_data) and not loaded_bookmark_data.rules_states.is_empty():
		var rules_states: Array = loaded_bookmark_data.rules_states
		for i: int in range(min(game_ready_data.all_spawn_rules.size(), rules_states.size())):
			game_ready_data.all_spawn_rules[i].set_state(rules_states[i])

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.mode_config.set_value(mode_config)
		current_game_model.current_board_topology.set_value(_duplicate_topology(board_topology))
		current_game_model.initial_seed.set_value(init_seed)
		current_game_model.initial_high_score.set_value(game_ready_data.initial_high_score)
		current_game_model.is_replay_mode.set_value(game_ready_data.is_replay_mode)

	send_event(game_ready_data)
