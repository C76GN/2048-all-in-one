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
var _game_state_system: GameStateSystem
var _command_history: GFCommandHistoryUtility
var _level_utility: GFLevelUtility
var _mode_catalog: GameModeCatalogUtility
var _grid_model: GridModel
var _log: GFLogUtility
var _clock: GameClockUtility
var _determinism: GameDeterminismUtility


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [AppConfigModel, CurrentGameModel, GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [
		GameFlowSystem,
		GameStateSystem,
		ReplaySystem,
		RuleSystem,
		ProgressStatsSystem,
	]


func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GameDeterminismUtility,
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
	_determinism = _get_determinism_utility()
	_rule_system = _get_rule_system()
	_game_flow_system = _get_game_flow_system()
	_game_state_system = _get_game_state_system()
	_grid_model = _get_grid_model()

	register_simple_event(EventNames.REQUEST_GAME_INITIALIZATION, GFEventListener.from_method(self, &"_on_request_initialization", 1))


func dispose() -> void:
	_seed_utility = null
	_rule_system = null
	_game_flow_system = null
	_game_state_system = null
	_command_history = null
	_level_utility = null
	_mode_catalog = null
	_grid_model = null
	_log = null
	_clock = null
	_determinism = null


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


func _get_determinism_utility() -> GameDeterminismUtility:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		return utility_value
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


func _get_game_state_system() -> GameStateSystem:
	var system_value: Object = get_system(GameStateSystem)
	if system_value is GameStateSystem:
		return system_value
	return null


func _get_progress_stats_system() -> ProgressStatsSystem:
	var system_value: Object = get_system(ProgressStatsSystem)
	if system_value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = system_value
		return progress_stats_system
	return null


func _get_replay_system() -> ReplaySystem:
	var system_value: Object = get_system(ReplaySystem)
	if system_value is ReplaySystem:
		return system_value
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


func _restore_bookmark_command_history(bookmark_data: BookmarkData) -> bool:
	if not is_instance_valid(_command_history) or not is_instance_valid(bookmark_data):
		return false

	var history: Dictionary = bookmark_data.game_state_history
	_command_history.deserialize_full_history(
		history,
		Callable(MoveCommand, "deserialize")
	)
	return (
		_command_history.undo_count
		== GFVariantData.get_option_array(history, "undo").size()
		and _command_history.redo_count
		== GFVariantData.get_option_array(history, "redo").size()
	)


func _is_bookmark_command_history_valid(
	bookmark_data: BookmarkData,
	interaction_rule: InteractionRule,
	spawn_rules: Array[SpawnRule]
) -> bool:
	if (
		not is_instance_valid(bookmark_data)
		or not is_instance_valid(_game_state_system)
		or not is_instance_valid(_command_history)
	):
		return false
	var history: Dictionary = bookmark_data.game_state_history
	if not (
		history.size() == 2
		and GFVariantData.get_option_value(history, "undo") is Array
		and GFVariantData.get_option_value(history, "redo") is Array
	):
		return false
	for stack_key: String in ["undo", "redo"]:
		var stack: Array = GFVariantData.get_option_array(history, stack_key)
		if _command_history.max_history_size > 0 and stack.size() > _command_history.max_history_size:
			return false
		for command_value: Variant in stack:
			if not command_value is Dictionary:
				return false
			var command_data: Dictionary = command_value
			if not MoveCommand.is_serialized_data_valid(command_data):
				return false
			if not _game_state_system.can_restore_state(
				GFVariantData.get_option_dictionary(command_data, &"snapshot"),
				interaction_rule,
				spawn_rules
			):
				return false
	return true


func _is_bookmark_mode_contract_valid(
	bookmark_data: BookmarkData,
	mode_config: GameModeConfig
) -> bool:
	if not is_instance_valid(bookmark_data) or not is_instance_valid(mode_config):
		return false
	return (
		bookmark_data.target_tile_value == maxi(mode_config.target_tile_value, 0)
		and is_instance_valid(_determinism)
		and bookmark_data.matches_ruleset(mode_config, _determinism)
	)


func _start_level_session(
	level_source: StringName,
	mode_config: GameModeConfig,
	game_ready_data: GameReadyData
) -> bool:
	if not is_instance_valid(mode_config):
		return false
	if not is_instance_valid(_level_utility):
		push_error("[GameInitSystem] 缺少 GFLevelUtility，无法启动对局生命周期。")
		return false

	var level_id: StringName = _build_level_session_id(level_source, mode_config, game_ready_data)
	var level_data: Dictionary = _build_level_session_data(level_source, mode_config, game_ready_data)
	var level_session: Dictionary = _level_utility.start_level(level_id, level_data)
	return not level_session.is_empty()


func _restore_previous_level_session(
	previous_level_id: StringName,
	previous_level_data: Dictionary
) -> void:
	if not is_instance_valid(_level_utility):
		return
	_level_utility.clear_level_runtime()
	_level_utility.clear_current_level()
	if previous_level_id != &"":
		var _restored_level: Dictionary = _level_utility.start_level(
			previous_level_id,
			previous_level_data
		)


func _build_bookmark_game_state(bookmark_data: BookmarkData) -> Dictionary:
	if not is_instance_valid(bookmark_data):
		return {}
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(bookmark_data.board_snapshot, &"topology")
	)
	if topology == null:
		return {}
	return {
		&"schema_version": GameStateSystem.STATE_SCHEMA_VERSION,
		&"board_key": topology.get_stable_key(),
		&"board_snapshot": bookmark_data.board_snapshot.duplicate(true),
		&"rng_full_state": bookmark_data.rng_full_state.duplicate(true),
		&"score": bookmark_data.score,
		&"move_count": bookmark_data.move_count,
		&"highest_tile": bookmark_data.highest_tile,
		&"ratio_resolutions": bookmark_data.ratio_resolutions,
		&"target_tile_value": bookmark_data.target_tile_value,
		&"target_reached": bookmark_data.target_reached,
		&"extra_stats": bookmark_data.extra_stats.duplicate(true),
		&"rules_states": bookmark_data.rules_states.duplicate(true),
	}


func _duplicate_spawn_rules(source_rules: Array[SpawnRule]) -> Array[SpawnRule]:
	var result: Array[SpawnRule] = []
	for rule_resource: SpawnRule in source_rules:
		if not is_instance_valid(rule_resource):
			return []
		var duplicated_rule: Resource = rule_resource.duplicate()
		if not duplicated_rule is SpawnRule:
			return []
		result.append(duplicated_rule)
	return result


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
		"session_metadata": (
			game_ready_data.session_metadata.to_dict()
			if game_ready_data.session_metadata != null
			else {}
		),
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


func _resolve_session_metadata(
	level_source: StringName,
	replay_data: ReplayData,
	bookmark_data: BookmarkData,
	topology: BoardTopology,
	requested_seed_source: StringName,
	selected_board_is_custom: bool
) -> GameSessionMetadata:
	var metadata: GameSessionMetadata = null
	if level_source == _LEVEL_SOURCE_REPLAY and is_instance_valid(replay_data):
		metadata = replay_data.get_session_metadata()
	elif level_source == _LEVEL_SOURCE_BOOKMARK and is_instance_valid(bookmark_data):
		metadata = bookmark_data.get_session_metadata()
		if metadata != null:
			metadata = metadata.with_eligibility_reason(
				GameCompetitionEligibility.REASON_BOOKMARK
			)
	else:
		var reason_codes: Array[StringName] = []
		if requested_seed_source == GameSessionMetadata.SEED_SOURCE_MANUAL:
			reason_codes.append(GameCompetitionEligibility.REASON_MANUAL_SEED)
		elif requested_seed_source != GameSessionMetadata.SEED_SOURCE_RANDOM:
			return null
		var eligibility: GameCompetitionEligibility = GameCompetitionEligibility.create(
			reason_codes
		)
		metadata = GameSessionMetadata.create(
			requested_seed_source,
			eligibility
		)

	if metadata == null:
		return null
	if selected_board_is_custom or _is_custom_topology(topology):
		metadata = metadata.with_eligibility_reason(
			GameCompetitionEligibility.REASON_CUSTOM_BOARD
		)
	return metadata


func _does_session_metadata_match_contract(
	metadata: GameSessionMetadata
) -> bool:
	return metadata != null and metadata.is_valid()


func _make_random_seed() -> int:
	if not is_instance_valid(_seed_utility):
		return 0
	var timestamp: int = _get_unix_timestamp()
	var tick_msec: int = _clock.get_tick_msec() if is_instance_valid(_clock) else 0
	return GFSeedUtility.make_stable_seed([
		"game_init.random",
		timestamp,
		tick_msec,
		_seed_utility.next_uint32(),
	])


static func _is_custom_topology(topology: BoardTopology) -> bool:
	return (
		is_instance_valid(topology)
		and String(topology.topology_id).begins_with("board.custom.")
	)


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

	var game_ready_data: GameReadyData = GameReadyData.new()
	game_ready_data.is_replay_mode = is_instance_valid(replay_data)
	game_ready_data.loaded_bookmark_data = loaded_bookmark_data
	game_ready_data.replay_data_resource = replay_data

	var config_path: String = GFVariantData.to_text(app_config.selected_mode_config_path.get_value(), "")
	var init_seed: int = 0
	var requested_seed_source: StringName = GFVariantData.to_string_name(
		app_config.selected_seed_source.get_value(),
		GameSessionMetadata.SEED_SOURCE_RANDOM
	)

	if game_ready_data.is_replay_mode:
		config_path = replay_data.mode_config_path
		init_seed = replay_data.initial_seed
	elif is_instance_valid(loaded_bookmark_data):
		config_path = loaded_bookmark_data.mode_config_path
		init_seed = loaded_bookmark_data.initial_seed
	else:
		var config_seed: int = GFVariantData.to_int(app_config.selected_seed.get_value(), 0)
		if is_instance_valid(_log):
			_log.debug(
				_LOG_TAG,
				"新对局配置 seed: source=%s, value=%d"
				% [requested_seed_source, config_seed]
			)
		init_seed = config_seed

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
	if (
		is_instance_valid(replay_data)
		and (
			not is_instance_valid(_determinism)
			or not replay_data.matches_ruleset(mode_config, _determinism)
		)
	):
		var actual_fingerprint: String = (
			_determinism.calculate_ruleset_fingerprint(mode_config)
			if is_instance_valid(_determinism)
			else ""
		)
		var report: Dictionary = {
			&"kind": &"ruleset_mismatch",
			&"step_index": 0,
			&"expected_ruleset_id": replay_data.ruleset_id,
			&"actual_ruleset_id": mode_config.ruleset_id,
			&"expected_ruleset_version": replay_data.ruleset_version,
			&"actual_ruleset_version": mode_config.ruleset_version,
			&"expected_ruleset_fingerprint": replay_data.ruleset_fingerprint,
			&"actual_ruleset_fingerprint": actual_fingerprint,
		}
		var replay_system: ReplaySystem = _get_replay_system()
		if is_instance_valid(replay_system):
			var _oos_recorded: bool = replay_system.report_oos(report)
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "回放规则集与当前模式不一致，拒绝初始化。", report)
		return

	if (
		is_instance_valid(loaded_bookmark_data)
		and not _is_bookmark_mode_contract_valid(loaded_bookmark_data, mode_config)
	):
		var actual_bookmark_fingerprint: String = (
			_determinism.calculate_ruleset_fingerprint(mode_config)
			if is_instance_valid(_determinism)
			else ""
		)
		var bookmark_contract_error: String = (
			"书签规则集或目标契约与模式不一致，拒绝恢复: "
			+ "bookmark_ruleset=%s@%d, mode_ruleset=%s@%d, "
			+ "bookmark_fingerprint=%s, mode_fingerprint=%s, "
			+ "bookmark_target=%d, mode_target=%d, path=%s"
		) % [
			loaded_bookmark_data.ruleset_id,
			loaded_bookmark_data.ruleset_version,
			mode_config.ruleset_id,
			mode_config.ruleset_version,
			loaded_bookmark_data.ruleset_fingerprint,
			actual_bookmark_fingerprint,
			loaded_bookmark_data.target_tile_value,
			mode_config.target_tile_value,
			config_path,
		]
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, bookmark_contract_error)
		else:
			push_error("[GameInitSystem] %s" % bookmark_contract_error)
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

	var selected_board_is_custom: bool = (
		level_source == _LEVEL_SOURCE_NEW_GAME
		and GFVariantData.to_bool(
			app_config.selected_board_is_custom.get_value(),
			false
		)
	)
	var session_metadata: GameSessionMetadata = _resolve_session_metadata(
		level_source,
		replay_data,
		loaded_bookmark_data,
		board_topology,
		requested_seed_source,
		selected_board_is_custom
	)
	if session_metadata == null:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "无法构造严格对局元数据，拒绝初始化。")
		return
	if (
		level_source == _LEVEL_SOURCE_NEW_GAME
		and session_metadata.get_seed_source() == GameSessionMetadata.SEED_SOURCE_RANDOM
		and init_seed == 0
	):
		init_seed = _make_random_seed()
	if not _does_session_metadata_match_contract(session_metadata):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "对局元数据不满足当前严格契约。")
		return
	game_ready_data.initial_seed = init_seed
	game_ready_data.session_metadata = session_metadata

	game_ready_data.mode_config = mode_config
	game_ready_data.interaction_rule = _duplicate_interaction_rule(mode_config.interaction_rule)
	game_ready_data.movement_rule = _duplicate_movement_rule(mode_config.movement_rule)
	game_ready_data.game_over_rule = _duplicate_game_over_rule(mode_config.game_over_rule)
	game_ready_data.all_spawn_rules = _duplicate_spawn_rules(mode_config.spawn_rules)
	if (
		not is_instance_valid(game_ready_data.interaction_rule)
		or not is_instance_valid(game_ready_data.movement_rule)
		or not is_instance_valid(game_ready_data.game_over_rule)
		or game_ready_data.all_spawn_rules.size() != mode_config.spawn_rules.size()
		or not RuleSystem.are_rules_state_compatible(game_ready_data.all_spawn_rules)
	):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GameModeConfig 规则复制失败: %s" % config_path)
		return

	var game_status_model: GameStatusModel = _get_game_status_model()
	if (
		not is_instance_valid(_level_utility)
		or not is_instance_valid(_command_history)
		or not is_instance_valid(_grid_model)
		or not is_instance_valid(_seed_utility)
		or not is_instance_valid(_rule_system)
		or not is_instance_valid(_game_state_system)
		or game_ready_data.session_metadata == null
		or not is_instance_valid(game_status_model)
	):
		push_error("[GameInitSystem] 对局事务依赖不完整，拒绝初始化。")
		return

	var bookmark_game_state: Dictionary = {}
	if is_instance_valid(loaded_bookmark_data):
		bookmark_game_state = _build_bookmark_game_state(loaded_bookmark_data)
		if not _game_state_system.can_restore_state(
			bookmark_game_state,
			game_ready_data.interaction_rule,
			game_ready_data.all_spawn_rules
		):
			if is_instance_valid(_log):
				_log.error(_LOG_TAG, "书签完整状态预验证失败，拒绝初始化。")
			return
		if not _is_bookmark_command_history_valid(
			loaded_bookmark_data,
			game_ready_data.interaction_rule,
			game_ready_data.all_spawn_rules
		):
			if is_instance_valid(_log):
				_log.error(_LOG_TAG, "书签命令历史包含不可恢复快照，拒绝初始化。")
			return

	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system()
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	var high_score: int = 0
	if is_instance_valid(progress_stats_system):
		high_score = progress_stats_system.get_high_score(mode_id, board_topology.get_stable_key())

	game_ready_data.initial_high_score = high_score
	var previous_level_id: StringName = _level_utility.current_level_id
	var previous_level_data: Dictionary = _level_utility.current_level_data.duplicate(true)
	_level_utility.clear_level_runtime()
	if not _start_level_session(level_source, mode_config, game_ready_data):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GFLevelUtility 拒绝启动已预验证的对局。")
		return

	if not _grid_model.initialize(
		board_topology,
		game_ready_data.interaction_rule,
		game_ready_data.movement_rule
	):
		_restore_previous_level_session(previous_level_id, previous_level_data)
		return
	if not _rule_system.register_rules(game_ready_data.all_spawn_rules):
		_restore_previous_level_session(previous_level_id, previous_level_data)
		return

	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "设置全局随机种子: %d" % init_seed)
	_seed_utility.set_global_seed(init_seed)

	if is_instance_valid(loaded_bookmark_data):
		if not _game_state_system.restore_state(bookmark_game_state):
			_restore_previous_level_session(previous_level_id, previous_level_data)
			if is_instance_valid(_log):
				_log.error(_LOG_TAG, "书签状态提交失败，已恢复上一关卡登记。")
			return
		game_status_model.high_score.set_value(high_score)
		if not _restore_bookmark_command_history(loaded_bookmark_data):
			_restore_previous_level_session(previous_level_id, previous_level_data)
			if is_instance_valid(_log):
				_log.error(_LOG_TAG, "书签命令历史提交失败，已恢复上一关卡登记。")
			return
	else:
		_command_history.clear()
		game_status_model.reset_for_new_game(high_score)
		game_status_model.set_target_state(mode_config.target_tile_value, false)

	if is_instance_valid(_game_flow_system):
		_game_flow_system.setup(_rule_system, game_ready_data.game_over_rule)

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.mode_config.set_value(mode_config)
		current_game_model.current_board_topology.set_value(_duplicate_topology(board_topology))
		current_game_model.initial_seed.set_value(init_seed)
		current_game_model.initial_high_score.set_value(game_ready_data.initial_high_score)
		current_game_model.is_replay_mode.set_value(game_ready_data.is_replay_mode)
		current_game_model.session_metadata.set_value(game_ready_data.session_metadata)
		current_game_model.last_game_result.set_value(null)

	app_config.current_replay_data.set_value(null)
	app_config.selected_bookmark_data.set_value(null)
	send_event(game_ready_data)
