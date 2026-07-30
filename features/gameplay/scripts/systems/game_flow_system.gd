## GameFlowSystem: 负责管理游戏整体流程和规则触发的核心系统。
##
## 该系统监听来自其他系统或控制器的事件，并调用 RuleSystem 执行对应的规则，
## 例如判断游戏结束、触发方块生成等。
class_name GameFlowSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GameFlowSystem"
const _TARGET_REACHED_MESSAGE_DURATION: float = 4.0
const _TARGET_REACHED_MESSAGE_FALLBACK: String = "已达成目标 %d！可以继续挑战更高方块。"
const _NOTIFICATION_SURFACE: String = "gameplay_hud"
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")


# --- 私有变量 ---

var _grid_model: GridModel
var _game_status_model: GameStatusModel
var _rule_system: RuleSystem
var _game_over_rule: GameOverRule
var _is_replay_mode: bool = false
var _is_game_state_tainted: bool = false
var _mode_config: GameModeConfig
var _mode_config_path: String = ""
var _target_reached_notified: bool = false
var _current_board_topology: BoardTopology = null
var _initial_seed_of_session: int = 0
var _last_saved_bookmark_state: Dictionary = {}
var _player_actions: Array[Vector2i] = []
var _turn_checkpoints: Array[ReplayCheckpoint] = []
var _session_metadata: GameSessionMetadata = null
var _session_duration_msec: int = 0
var _session_ruleset_fingerprint: String = ""
var _target_reached_modal_active: bool = false
var _is_settling_move_turn: bool = false
var _persistence_epoch: int = 0
var _persistence_owner_active: bool = false
var _bookmark_save_in_progress: bool = false
var _section_reconciliation_waiters: Array[_SectionReconciliationWaiter] = []

## 核心状态机。
var _fsm: GFStateMachine

var _clock: GameClockUtility
var _notifications: GFNotificationUtility
var _pause_utility: GamePauseUtility
var _determinism: GameDeterminismUtility
var _accessibility_summary: GameAccessibilitySummaryUtility
var _save_graph: GameSaveGraphUtility
var _signal_utility: GFSignalUtility


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [AppConfigModel, CurrentGameModel, GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [BookmarkSystem, GameStateSystem, ReplaySystem, ProgressStatsSystem, SceneRouterSystem]


func get_required_utilities() -> Array[Script]:
	return [
		_GAME_THEME_UTILITY_SCRIPT,
		GameAccessibilitySummaryUtility,
		GameClockUtility,
		GameDeterminismUtility,
		GamePauseUtility,
		GameSaveGraphUtility,
		GFCommandHistoryUtility,
		GFLogUtility,
		GFNotificationUtility,
		GFSeedUtility,
		GFSignalUtility,
	]


## 初始化内部状态机。
func init() -> void:
	_fsm = GFStateMachine.new(self)
	_fsm.add_state(EventNames.STATE_READY, GameReadyState.new())
	_fsm.add_state(EventNames.STATE_PLAYING, GamePlayingState.new())
	_fsm.add_state(EventNames.STATE_GAME_OVER, GameOverState.new())


## 处理初始化，绑定事件。
func ready() -> void:
	_persistence_epoch += 1
	_persistence_owner_active = true
	_bookmark_save_in_progress = false
	_grid_model = _get_grid_model()
	_game_status_model = _get_game_status_model()
	_clock = _get_clock_utility()
	_notifications = _get_notification_utility()
	_pause_utility = _get_pause_utility()
	_determinism = _get_determinism_utility()
	_accessibility_summary = _get_accessibility_summary_utility()
	_save_graph = _get_save_graph_utility()
	_signal_utility = _get_signal_utility()
	if not is_instance_valid(_notifications):
		push_error("[GameFlowSystem] 缺少 GFNotificationUtility，玩法反馈不可用。")
	if not is_instance_valid(_pause_utility):
		push_error("[GameFlowSystem] 缺少 GamePauseUtility，对局暂停状态不可用。")

	register_simple_event(EventNames.RATIO_RESOLVED, GFEventListener.from_method(self, &"_on_ratio_resolved", 1))
	register_simple_event(EventNames.SCORE_UPDATED, GFEventListener.from_method(self, &"_on_score_updated", 1))
	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready", 1))
	register_simple_event(EventNames.UNDO_REQUESTED, GFEventListener.from_method(self, &"_on_undo_requested", 1))
	register_simple_event(EventNames.REDO_REQUESTED, GFEventListener.from_method(self, &"_on_redo_requested", 1))
	register_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED, GFEventListener.from_method(self, &"_on_save_bookmark_requested", 1))
	register_simple_event(EventNames.UI_PAUSE_REQUESTED, GFEventListener.from_method(self, &"_on_ui_pause_requested", 1))
	register_simple_event(EventNames.GAME_STATE_TAINTED, GFEventListener.from_method(self, &"_on_game_state_tainted", 1))
	register_simple_event(EventNames.BOARD_RESIZED, GFEventListener.from_method(self, &"_on_board_resized", 1))
	register_simple_event(EventNames.RESUME_GAME_REQUESTED, GFEventListener.from_method(self, &"_on_resume_game_requested", 1))
	register_simple_event(EventNames.RESTART_GAME_REQUESTED, GFEventListener.from_method(self, &"_on_restart_game_requested", 1))
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, GFEventListener.from_method(self, &"_on_return_to_main_menu_from_game", 1))
	register_simple_event(EventNames.REPLAY_CONTINUE_REQUESTED, GFEventListener.from_method(self, &"_on_replay_continue_requested", 1))


## 释放状态机和运行时缓存。GF 在绑定释放时按 owner 统一清理事件。
func dispose() -> void:
	_persistence_epoch += 1
	_persistence_owner_active = false
	_bookmark_save_in_progress = false
	for waiter: _SectionReconciliationWaiter in (
		_section_reconciliation_waiters.duplicate()
	):
		waiter.cancel()
	_section_reconciliation_waiters.clear()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	if _fsm != null:
		_fsm.dispose()
		_fsm = null

	_grid_model = null
	_game_status_model = null
	_rule_system = null
	_game_over_rule = null
	_clock = null
	_notifications = null
	_pause_utility = null
	_determinism = null
	_accessibility_summary = null
	_save_graph = null
	_signal_utility = null
	_player_actions.clear()
	_turn_checkpoints.clear()
	_last_saved_bookmark_state = {}
	_mode_config = null
	_mode_config_path = ""
	_target_reached_notified = false
	_is_replay_mode = false
	_is_game_state_tainted = false
	_current_board_topology = null
	_initial_seed_of_session = 0
	_session_metadata = null
	_session_duration_msec = 0
	_session_ruleset_fingerprint = ""
	_target_reached_modal_active = false
	_is_settling_move_turn = false


## 更新游戏流程状态机。
## @param delta: 当前帧间隔。
func tick(delta: float) -> void:
	if _fsm != null:
		_fsm.update(delta)
		if (
			not _is_replay_mode
			and _fsm.current_state_name == EventNames.STATE_PLAYING
			and delta > 0.0
		):
			_session_duration_msec += maxi(roundi(delta * 1000.0), 0)


# --- 公共方法 ---

## 返回棋盘无障碍摘要消费的当前流程、目标与可操作项。
func get_accessibility_context() -> Dictionary:
	var phase: StringName = (
		_fsm.current_state_name
		if _fsm != null and _fsm.current_state_name != &""
		else &"ready"
	)
	var normalized_phase: StringName = &"ready"
	if phase == EventNames.STATE_PLAYING:
		normalized_phase = &"playing"
	elif phase == EventNames.STATE_GAME_OVER:
		normalized_phase = &"game_over"
	if normalized_phase == &"playing" and _target_reached_modal_active:
		normalized_phase = &"target_reached"
	var available_actions: Array[StringName] = []
	if normalized_phase == &"playing":
		if _is_replay_mode:
			available_actions.append(&"replay_controls")
			available_actions.append(&"pause")
			available_actions.append(&"return")
		else:
			available_actions.append(&"move")
			available_actions.append(&"pause")
			available_actions.append(&"hint")
			available_actions.append(&"save_bookmark")
			var command_history: GFCommandHistoryUtility = (
				_get_command_history_utility()
			)
			if (
				is_instance_valid(command_history)
				and _can_undo_player_move(command_history)
			):
				available_actions.append(&"undo")
			if (
				is_instance_valid(command_history)
				and _can_redo_player_move(command_history)
			):
				available_actions.append(&"redo")
	elif normalized_phase == &"target_reached":
		available_actions.append(&"continue")
		available_actions.append(&"restart")
		available_actions.append(&"return")
	elif normalized_phase == &"game_over":
		available_actions.append(&"restart")
		available_actions.append(&"settings")
		available_actions.append(&"return")
	return {
		&"phase": normalized_phase,
		&"target_value": (
			GFVariantData.to_int(
				_game_status_model.target_tile_value.get_value(),
				0
			)
			if is_instance_valid(_game_status_model)
			else 0
		),
		&"target_reached": (
			GFVariantData.to_bool(
				_game_status_model.target_reached.get_value(),
				false
			)
			if is_instance_valid(_game_status_model)
			else false
		),
		&"end_reason": (
			&"no_moves" if normalized_phase == &"game_over" else &""
		),
		&"available_actions": available_actions,
	}


## 同步目标达成弹层是否正在阻断玩法输入。
##
## UI 路由仍拥有弹层开关；流程系统只保存生成无障碍语义所需的交互阶段。
## @param active: 弹层已打开且成功暂停对局时为 true，关闭时为 false。
## @return: 交互阶段实际发生变化时返回 true。
func set_target_reached_modal_active(active: bool) -> bool:
	if active and (
		_fsm == null
		or _fsm.current_state_name != EventNames.STATE_PLAYING
	):
		return false
	if _target_reached_modal_active == active:
		return false
	_target_reached_modal_active = active
	if not _is_settling_move_turn:
		var _summary: GameAccessibilitySummary = (
			_publish_accessibility_board_summary()
		)
	return true


## 注入当前游戏的规则环境。
## @param rule_system: 负责执行生成规则的系统。
## @param game_over_rule: 当前模式使用的游戏结束判定规则。
func setup(rule_system: RuleSystem, game_over_rule: GameOverRule) -> void:
	_rule_system = rule_system
	_game_over_rule = game_over_rule


## 将当前完整状态标记为已保存的书签基线。
func sync_bookmark_baseline_state() -> void:
	_last_saved_bookmark_state = _get_bookmark_comparison_state()


## 从棋盘状态同步状态模型中的最高方块值。
func sync_highest_tile_from_grid() -> void:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_status_model):
		return

	_game_status_model.sync_highest_tile_from_grid(_grid_model)


## 进入可操作的游戏状态，不触发棋盘初始化。
func enter_playing_state() -> void:
	if _fsm == null:
		return

	_fsm.start(EventNames.STATE_READY)
	_fsm.change_state(EventNames.STATE_PLAYING)


## 触发初始棋盘规则。
func trigger_initial_rules() -> void:
	enter_playing_state()
	send_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION)
	sync_highest_tile_from_grid()


## 应用一次有效移动产生的局内统计变化。
## @param turn_result: 当前 GF 回合行动携带的强类型结果。
func apply_move_turn(turn_result: TurnResult) -> void:
	if not is_instance_valid(turn_result):
		return
	if not _is_replay_mode and turn_result.direction != Vector2i.ZERO:
		_player_actions.append(turn_result.direction)
	if is_instance_valid(_game_status_model):
		_game_status_model.increment_move_count()
	sync_highest_tile_from_grid()


## 在生成规则完成后固化确定性检查点；回放模式下立即比较首个 OOS。
## @param turn_result: 当前已完成规则链的强类型回合结果。
## @return: 成功固化的检查点；依赖或规则集指纹无效时返回 null。
func finalize_turn_result(turn_result: TurnResult) -> ReplayCheckpoint:
	if (
		not is_instance_valid(turn_result)
		or not is_instance_valid(_determinism)
		or not is_instance_valid(_mode_config)
	):
		return null
	var replay_system: ReplaySystem = _get_replay_system()
	var step_index: int = _player_actions.size()
	if _is_replay_mode and is_instance_valid(replay_system):
		step_index = replay_system.get_current_step() + 1
	var ruleset_fingerprint: String = _get_session_ruleset_fingerprint()
	if ruleset_fingerprint.is_empty():
		push_error("[GameFlowSystem] 当前对局缺少冻结规则集指纹。")
		return null
	var checkpoint: ReplayCheckpoint = _determinism.create_checkpoint_for_session(
		step_index,
		_get_full_game_state(),
		ruleset_fingerprint,
		turn_result
	)
	if checkpoint == null:
		push_error("[GameFlowSystem] 无法生成第 %d 步确定性检查点。" % step_index)
		return null
	if not _is_replay_mode:
		_turn_checkpoints.append(checkpoint)
		return checkpoint
	if not is_instance_valid(replay_system):
		return checkpoint
	var replay: ReplayData = replay_system.get_current_replay()
	if replay == null or step_index <= 0 or step_index > replay.checkpoints.size():
		var _missing_checkpoint_oos_recorded: bool = replay_system.report_oos({
			&"kind": &"missing_checkpoint",
			&"step_index": step_index,
			&"direction": turn_result.direction,
		})
		return checkpoint
	var expected: ReplayCheckpoint = replay.checkpoints[step_index - 1]
	if expected.state_checksum == checkpoint.state_checksum:
		return checkpoint
	var _checksum_oos_recorded: bool = replay_system.report_oos({
		&"kind": &"state_checksum_mismatch",
		&"step_index": step_index,
		&"direction": turn_result.direction,
		&"expected_state_checksum": expected.state_checksum,
		&"actual_state_checksum": checkpoint.state_checksum,
		&"expected_board_checksum": expected.board_checksum,
		&"actual_board_checksum": checkpoint.board_checksum,
		&"expected_rng_checksum": expected.rng_checksum,
		&"actual_rng_checksum": checkpoint.rng_checksum,
		&"expected_score": expected.score,
		&"actual_score": checkpoint.score,
	})
	return checkpoint


## 完成当前 GF 移动回合的目标与失败结算。
func settle_move_turn() -> void:
	_is_settling_move_turn = true
	sync_highest_tile_from_grid()
	var reached_target_now: bool = _mark_target_reached_if_needed()
	if check_game_over():
		_is_settling_move_turn = false
		return
	if reached_target_now:
		_emit_target_reached_feedback()
	_is_settling_move_turn = false


## 检查游戏是否结束。
## @return: 当前棋盘已满足终局规则时返回 true。
func check_game_over() -> bool:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_over_rule):
		return false
	if _grid_model.interaction_rule != null:
		if _game_over_rule.is_game_over(_grid_model, _grid_model.interaction_rule):
			send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, _grid_model.get_snapshot())
			send_simple_event(EventNames.GAME_LOST)
			if _is_replay_mode:
				return true
			if _fsm == null:
				return true
			_target_reached_modal_active = false
			_fsm.change_state(EventNames.STATE_GAME_OVER)
			if not _is_settling_move_turn:
				var _summary: GameAccessibilitySummary = (
					_publish_accessibility_board_summary()
				)
			_handle_game_over()
			return true
	return false


## 使用当前模式、尺寸和初始种子重新开始本局。
func restart_game() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if not is_instance_valid(router):
		return

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if not is_instance_valid(current_game_model):
		return

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree):
		return

	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility) or not pause_utility.resume():
		push_error("[GameFlowSystem] 无法恢复对局时间，拒绝重新开始。")
		return
	var mode_config_value: Variant = current_game_model.mode_config.get_value()
	if not mode_config_value is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_config_value
	var topology_value: Variant = current_game_model.current_board_topology.get_value()
	if not topology_value is BoardTopology:
		return
	var board_topology: BoardTopology = topology_value
	var initial_seed: int = GFVariantData.to_int(current_game_model.initial_seed.get_value(), 0)
	var log_utility: GFLogUtility = _get_log_utility()
	if is_instance_valid(log_utility):
		log_utility.debug(
			_LOG_TAG,
			"重新开始本局: initial_seed=%d, board=%s" % [initial_seed, board_topology.get_stable_key()]
		)

	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.selected_mode_config_path.set_value(mode_config.resource_path)
		app_config.selected_board_topology.set_value(board_topology.duplicate(true))
		app_config.selected_seed.set_value(initial_seed)
		var current_metadata: GameSessionMetadata = _get_current_session_metadata()
		app_config.selected_seed_source.set_value(
			GameSessionMetadata.SEED_SOURCE_MANUAL
		)
		app_config.selected_board_is_custom.set_value(
			current_metadata != null
			and current_metadata.get_eligibility().has_reason(
				GameCompetitionEligibility.REASON_CUSTOM_BOARD
			)
		)
		if is_instance_valid(log_utility):
			log_utility.debug(_LOG_TAG, "已写回 AppConfigModel.selected_seed=%d" % initial_seed)

	var seed_utility: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_utility):
		if is_instance_valid(log_utility):
			log_utility.debug(_LOG_TAG, "预设全局随机种子: %d" % initial_seed)
		seed_utility.set_global_seed(initial_seed)

	if is_instance_valid(tree.current_scene) and not tree.current_scene.scene_file_path.is_empty():
		router.goto_scene(tree.current_scene.scene_file_path)


# --- 私有/辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
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


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_accessibility_summary_utility() -> GameAccessibilitySummaryUtility:
	var utility_value: Object = get_utility(GameAccessibilitySummaryUtility)
	if utility_value is GameAccessibilitySummaryUtility:
		var summary_utility: GameAccessibilitySummaryUtility = utility_value
		return summary_utility
	return null


func _publish_accessibility_board_summary() -> GameAccessibilitySummary:
	if (
		not is_instance_valid(_accessibility_summary)
		or not is_instance_valid(_grid_model)
	):
		return null
	return _accessibility_summary.publish_board_summary(
		_grid_model.get_snapshot(),
		get_accessibility_context()
	)


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

	push_error("[GameFlowSystem] 缺少 GameClockUtility，无法创建时间戳。")
	return 0


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


func _get_notification_utility() -> GFNotificationUtility:
	var utility_value: Object = get_utility(GFNotificationUtility)
	if utility_value is GFNotificationUtility:
		var notification_utility: GFNotificationUtility = utility_value
		return notification_utility
	return null


func _get_pause_utility() -> GamePauseUtility:
	if is_instance_valid(_pause_utility):
		return _pause_utility
	var utility_value: Object = get_utility(GamePauseUtility)
	if utility_value is GamePauseUtility:
		var pause_utility: GamePauseUtility = utility_value
		_pause_utility = pause_utility
		return pause_utility
	return null


func _get_determinism_utility() -> GameDeterminismUtility:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		return utility_value
	return null


func _get_save_graph_utility() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		_save_graph = utility_value
		return _save_graph
	return null


func _get_signal_utility() -> GFSignalUtility:
	if is_instance_valid(_signal_utility):
		return _signal_utility
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		_signal_utility = utility_value
		return _signal_utility
	return null


func _push_gameplay_notification(
	message: String,
	duration_seconds: float,
	level: GFNotificationUtility.Level,
	key: String,
	priority: int = -1
) -> void:
	if not is_instance_valid(_notifications):
		push_error("[GameFlowSystem] GFNotificationUtility 未注册，无法显示玩法反馈。")
		return
	var resolved_priority: int = (
		priority
		if priority >= GFNotificationUtility.Priority.LOW
		else _get_notification_priority_for_level(level)
	)
	var _notification_id: int = _notifications.push_notification(
		message,
		"",
		level,
		{
			"duration_seconds": duration_seconds,
			"key": key,
			"priority": resolved_priority,
			"metadata": {"surface": _NOTIFICATION_SURFACE},
		}
	)


func _get_notification_priority_for_level(
	level: GFNotificationUtility.Level
) -> GFNotificationUtility.Priority:
	match level:
		GFNotificationUtility.Level.ERROR:
			return GFNotificationUtility.Priority.CRITICAL
		GFNotificationUtility.Level.WARNING:
			return GFNotificationUtility.Priority.NORMAL
		GFNotificationUtility.Level.SUCCESS:
			return GFNotificationUtility.Priority.NORMAL
		_:
			return GFNotificationUtility.Priority.LOW


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _get_replay_system() -> ReplaySystem:
	var system_value: Object = get_system(ReplaySystem)
	if system_value is ReplaySystem:
		var replay_system: ReplaySystem = system_value
		return replay_system
	return null


func _get_game_state_system() -> GameStateSystem:
	var system_value: Object = get_system(GameStateSystem)
	if system_value is GameStateSystem:
		var game_state_system: GameStateSystem = system_value
		return game_state_system
	return null


func _get_progress_stats_system() -> ProgressStatsSystem:
	var system_value: Object = get_system(ProgressStatsSystem)
	if system_value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = system_value
		return progress_stats_system
	return null


func _get_bookmark_system() -> BookmarkSystem:
	var system_value: Object = get_system(BookmarkSystem)
	if system_value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = system_value
		return bookmark_system
	return null


func _get_scene_tree() -> SceneTree:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		return tree
	return null


# --- 私有事件处理 ---

func _handle_game_over() -> void:
	if _is_replay_mode:
		return

	_play_game_over_sound()
	var recorded_result: GameResultRecordedData = _build_current_game_result()
	var persistence_profile_file_name: String = (
		_get_active_persistence_profile_file_name()
	)

	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_status_model):
		if recorded_result != null:
			@warning_ignore("return_value_discarded")
			_persist_game_over_artifacts.call_deferred(
				recorded_result,
				null,
				_session_duration_msec,
				_persistence_epoch,
				persistence_profile_file_name
			)
		return

	var replay_data: ReplayData = ReplayData.new()
	replay_data.timestamp = _get_unix_timestamp()
	replay_data.mode_config_path = _mode_config_path
	if not replay_data.configure_ruleset(_mode_config, _determinism):
		return
	replay_data.initial_seed = _initial_seed_of_session
	if _session_metadata == null:
		return
	replay_data.session_metadata = _session_metadata.to_dict()
	var current_topology: BoardTopology = _get_current_topology()
	if current_topology == null:
		return
	replay_data.initial_board_topology = current_topology.to_dict()

	replay_data.actions = _player_actions.duplicate()
	replay_data.checkpoints = _turn_checkpoints.duplicate()
	replay_data.final_board_snapshot = _grid_model.get_snapshot()
	replay_data.final_score = GFVariantData.to_int(_game_status_model.score.get_value(), 0)

	var replay_to_save: ReplayData = (
		replay_data
		if not _is_game_state_tainted and not replay_data.actions.is_empty()
		else null
	)
	if recorded_result != null or replay_to_save != null:
		@warning_ignore("return_value_discarded")
		_persist_game_over_artifacts.call_deferred(
			recorded_result,
			replay_to_save,
			_session_duration_msec,
			_persistence_epoch,
			persistence_profile_file_name
		)


func _on_game_ready(data: GameReadyData) -> void:
	_persistence_epoch += 1
	_bookmark_save_in_progress = false
	_is_replay_mode = data.is_replay_mode
	_is_game_state_tainted = false
	_session_metadata = (
		GameSessionMetadata.from_dict(data.session_metadata.to_dict())
		if data.session_metadata != null
		else null
	)
	if is_instance_valid(data.mode_config):
		_mode_config = data.mode_config
		_mode_config_path = data.mode_config.resource_path
	else:
		_mode_config = null
	_session_ruleset_fingerprint = ""
	var _frozen_ruleset_fingerprint: String = _get_session_ruleset_fingerprint()
	_current_board_topology = _duplicate_topology(data.board_topology)
	_initial_seed_of_session = data.initial_seed
	_session_duration_msec = 0
	_player_actions.clear()
	_turn_checkpoints.clear()
	_last_saved_bookmark_state = {}
	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.session_metadata.set_value(_session_metadata)
		current_game_model.last_game_result.set_value(null)
	var initial_target_reached: bool = false
	if is_instance_valid(data.loaded_bookmark_data):
		initial_target_reached = data.loaded_bookmark_data.target_reached
	else:
		initial_target_reached = _is_target_reached(_get_initial_highest_tile(data))
	_sync_target_state(initial_target_reached)
	_target_reached_notified = initial_target_reached
	_target_reached_modal_active = false
	if is_instance_valid(data.loaded_bookmark_data):
		_restore_replay_trace_from_bookmark(data.loaded_bookmark_data)


func _get_current_topology() -> BoardTopology:
	if is_instance_valid(_grid_model) and is_instance_valid(_grid_model.topology):
		return _grid_model.topology
	return _current_board_topology


func _get_current_board_key() -> String:
	var topology: BoardTopology = _get_current_topology()
	return topology.get_stable_key() if is_instance_valid(topology) else ""


func _get_current_session_metadata() -> GameSessionMetadata:
	if _session_metadata != null:
		return _session_metadata
	var current_game_model: CurrentGameModel = _get_current_game_model()
	if not is_instance_valid(current_game_model):
		return null
	var metadata_value: Variant = current_game_model.session_metadata.get_value()
	if metadata_value is GameSessionMetadata:
		_session_metadata = metadata_value
	return _session_metadata


func _get_session_ruleset_fingerprint() -> String:
	if (
		_session_ruleset_fingerprint.is_empty()
		and is_instance_valid(_determinism)
		and is_instance_valid(_mode_config)
	):
		_session_ruleset_fingerprint = _determinism.calculate_ruleset_fingerprint(
			_mode_config
		)
	return _session_ruleset_fingerprint


func _add_eligibility_reason(reason_code: StringName) -> bool:
	var current_metadata: GameSessionMetadata = _get_current_session_metadata()
	if current_metadata == null:
		return false
	var next_metadata: GameSessionMetadata = current_metadata.with_eligibility_reason(
		reason_code
	)
	if next_metadata == null:
		return false
	_session_metadata = next_metadata
	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.session_metadata.set_value(next_metadata)
	return true


static func _duplicate_topology(source: BoardTopology) -> BoardTopology:
	if not is_instance_valid(source):
		return null
	var duplicated: Resource = source.duplicate(true)
	if duplicated is BoardTopology:
		var topology: BoardTopology = duplicated
		return topology
	return null


func _get_full_game_state() -> Dictionary:
	var game_state_system: GameStateSystem = _get_game_state_system()
	if is_instance_valid(game_state_system):
		return game_state_system.get_full_game_state()
	return {}


func _get_bookmark_comparison_state() -> Dictionary:
	sync_highest_tile_from_grid()

	var state: Dictionary = _get_full_game_state()
	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if is_instance_valid(command_history):
		state[&"game_state_history"] = command_history.serialize_full_history()
	return state


func _persist_current_high_score() -> void:
	if _is_replay_mode or _is_game_state_tainted:
		return
	if _mode_config_path.is_empty() or not is_instance_valid(_game_status_model):
		return

	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system()
	if not is_instance_valid(progress_stats_system):
		return

	var mode_id: String = _mode_config_path.get_file().get_basename()
	var best_score: int = GFVariantData.to_int(_game_status_model.high_score.get_value(), 0)
	var save_error: Error = progress_stats_system.set_high_score(mode_id, _get_current_board_key(), best_score)
	_log_persistence_error("save high score", save_error)


func _build_current_game_result() -> GameResultRecordedData:
	if _is_replay_mode:
		return null
	if (
		_mode_config_path.is_empty()
		or not is_instance_valid(_game_status_model)
		or not is_instance_valid(_mode_config)
		or not is_instance_valid(_determinism)
		or _session_metadata == null
	):
		return null

	sync_highest_tile_from_grid()
	var mode_id: String = _mode_config_path.get_file().get_basename()
	var final_score: int = GFVariantData.to_int(_game_status_model.score.get_value(), 0)
	var move_count: int = GFVariantData.to_int(_game_status_model.move_count.get_value(), 0)
	var highest_tile: int = GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)
	var target_value: int = _get_target_tile_value()
	var target_reached: bool = _has_reached_target_in_session(highest_tile)
	var ruleset_fingerprint: String = _get_session_ruleset_fingerprint()
	if ruleset_fingerprint.is_empty():
		_log_persistence_error("resolve frozen ruleset fingerprint", ERR_INVALID_DATA)
		return null
	var final_state_hash: String = _determinism.calculate_state_checksum_for_session(
		_get_full_game_state(),
		ruleset_fingerprint
	)
	var result: GameResultRecordedData = GameResultRecordedData.create(
		StringName(mode_id),
		_get_current_board_key(),
		_mode_config.ruleset_id,
		_mode_config.ruleset_version,
		ruleset_fingerprint,
		_initial_seed_of_session,
		final_state_hash,
		_session_metadata.get_eligibility(),
		final_score,
		move_count,
		highest_tile,
		_get_unix_timestamp(),
		target_value,
		target_reached
	)
	if result == null:
		_log_persistence_error("build game result", ERR_INVALID_DATA)
		return null
	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.last_game_result.set_value(result)
	return result


func _persist_game_over_artifacts(
	recorded_result: GameResultRecordedData,
	replay_data: ReplayData,
	duration_msec: int,
	owner_epoch: int,
	owner_profile_file_name: String
) -> void:
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system()
	var replay_system: ReplaySystem = _get_replay_system()

	await _wait_for_section_serial_lane()
	if not _is_game_over_persistence_profile_current(
		owner_profile_file_name
	):
		return
	if recorded_result != null and is_instance_valid(progress_stats_system):
		var progress_operation: GameSaveSectionOperation = (
			progress_stats_system.request_record_game_result(
				recorded_result,
				duration_msec
			)
		)
		var progress_outcome: Dictionary = (
			await _await_section_operation_settlement(progress_operation)
		)
		if (
			not GFVariantData.get_option_bool(
				progress_outcome,
				&"candidate_persisted",
				false
			)
			and owner_epoch == _persistence_epoch
			and _is_game_over_persistence_profile_current(
				owner_profile_file_name
			)
		):
			_log_persistence_error(
				"save game result",
				_get_section_outcome_error(progress_outcome)
			)

	if not _is_game_over_persistence_profile_current(
		owner_profile_file_name
	):
		return
	await _wait_for_section_serial_lane()
	if not _is_game_over_persistence_profile_current(
		owner_profile_file_name
	):
		return
	if replay_data != null and is_instance_valid(replay_system):
		var replay_operation: GameSaveSectionOperation = (
			replay_system.request_save_replay(replay_data)
		)
		var replay_outcome: Dictionary = (
			await _await_section_operation_settlement(replay_operation)
		)
		if (
			not GFVariantData.get_option_bool(
				replay_outcome,
				&"candidate_persisted",
				false
			)
			and owner_epoch == _persistence_epoch
			and _is_game_over_persistence_profile_current(
				owner_profile_file_name
			)
		):
			_log_persistence_error(
				"save replay",
				_get_section_outcome_error(replay_outcome)
			)


func _get_active_persistence_profile_file_name() -> String:
	var save_graph: GameSaveGraphUtility = _get_save_graph_utility()
	if save_graph == null:
		return ""
	return save_graph.get_profile_file_name()


func _is_game_over_persistence_profile_current(
	owner_profile_file_name: String
) -> bool:
	if (
		not _persistence_owner_active
		or owner_profile_file_name.is_empty()
	):
		return false
	return (
		_get_active_persistence_profile_file_name()
		== owner_profile_file_name
	)


func _wait_for_section_serial_lane() -> void:
	var save_graph: GameSaveGraphUtility = _get_save_graph_utility()
	if save_graph == null:
		return
	var pending_operation: GameSaveSectionOperation = (
		save_graph.get_pending_section_operation()
	)
	if pending_operation != null:
		var _pending_outcome: Dictionary = (
			await _await_section_operation_settlement(pending_operation)
		)
	if save_graph.is_section_reconciliation_pending():
		var transaction_id: int = (
			save_graph.get_pending_section_reconciliation_transaction_id()
		)
		if transaction_id > 0:
			var _evidence: Dictionary = await _await_section_reconciliation(
				transaction_id
			)


func _await_section_operation_settlement(
	operation: GameSaveSectionOperation
) -> Dictionary:
	if operation == null:
		return {
			&"candidate_persisted": false,
			&"error_code": int(ERR_UNCONFIGURED),
		}
	var result: GameSaveSectionResult = operation.get_result()
	if result == null:
		result = await operation.completed
	if result == null:
		return {
			&"candidate_persisted": false,
			&"error_code": int(FAILED),
		}
	if result.is_successful():
		return {
			&"transaction_id": result.get_transaction_id(),
			&"status": String(result.get_status()),
			&"candidate_persisted": true,
			&"memory_rolled_back": result.was_memory_rolled_back(),
			&"error_code": int(OK),
		}
	if result.get_status() != GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN:
		return {
			&"transaction_id": result.get_transaction_id(),
			&"status": String(result.get_status()),
			&"candidate_persisted": false,
			&"memory_rolled_back": result.was_memory_rolled_back(),
			&"error_code": int(result.get_error_code()),
		}
	var evidence: Dictionary = await _await_section_reconciliation(
		result.get_transaction_id()
	)
	if evidence.is_empty():
		return {
			&"transaction_id": result.get_transaction_id(),
			&"status": String(result.get_status()),
			&"candidate_persisted": false,
			&"memory_rolled_back": false,
			&"error_code": int(result.get_error_code()),
		}
	evidence[&"error_code"] = (
		int(OK)
		if GFVariantData.get_option_bool(
			evidence,
			&"candidate_persisted",
			false
		)
		else int(result.get_error_code())
	)
	return evidence


func _await_section_reconciliation(transaction_id: int) -> Dictionary:
	var save_graph: GameSaveGraphUtility = _get_save_graph_utility()
	if save_graph == null or transaction_id <= 0:
		return {}
	var latest_evidence: Dictionary = (
		save_graph.get_last_section_reconciliation_evidence()
	)
	if (
		GFVariantData.get_option_int(
			latest_evidence,
			&"transaction_id",
			0
		) == transaction_id
	):
		return latest_evidence
	var signal_utility: GFSignalUtility = _get_signal_utility()
	if not is_instance_valid(signal_utility):
		return {}
	var waiter: _SectionReconciliationWaiter = _SectionReconciliationWaiter.new()
	if not waiter.begin(save_graph, signal_utility, self, transaction_id):
		return {}
	_section_reconciliation_waiters.append(waiter)
	var evidence: Dictionary = await waiter.settled
	_section_reconciliation_waiters.erase(waiter)
	if (
		GFVariantData.get_option_bool(evidence, &"cancelled", false)
		or GFVariantData.get_option_int(
			evidence,
			&"transaction_id",
			0
		) != transaction_id
	):
		return {}
	return evidence


static func _get_section_outcome_error(outcome: Dictionary) -> Error:
	@warning_ignore("int_as_enum_without_cast")
	var error_code: Error = GFVariantData.get_option_int(
		outcome,
		&"error_code",
		FAILED
	)
	return error_code


func _play_game_over_sound() -> void:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		theme_utility.play_game_over_sound()


func _log_persistence_error(operation: String, error: Error) -> void:
	if error == OK:
		return
	var log_utility: GFLogUtility = _get_log_utility()
	if is_instance_valid(log_utility):
		log_utility.error(_LOG_TAG, "%s failed with error %d." % [operation, error])


func _get_target_tile_value() -> int:
	if is_instance_valid(_mode_config):
		return max(_mode_config.target_tile_value, 0)
	return 0


func _is_target_reached(highest_tile: int) -> bool:
	if not is_instance_valid(_mode_config):
		return false
	return _mode_config.is_target_reached(highest_tile)


func _has_reached_target_in_session(highest_tile: int) -> bool:
	if _get_target_tile_value() <= 0:
		return false
	if is_instance_valid(_game_status_model):
		var model_reached: bool = GFVariantData.to_bool(_game_status_model.target_reached.get_value(), false)
		if model_reached:
			return true
	return _is_target_reached(highest_tile)


func _get_initial_highest_tile(data: GameReadyData) -> int:
	if is_instance_valid(data.loaded_bookmark_data):
		return max(data.loaded_bookmark_data.highest_tile, 0)
	if is_instance_valid(_game_status_model):
		return GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)
	return 0


func _mark_target_reached_if_needed() -> bool:
	var highest_tile: int = _get_current_highest_tile()
	if not _should_notify_target_reached(highest_tile):
		return false

	_target_reached_notified = true
	_sync_target_state(true)
	return true


func _emit_target_reached_feedback() -> void:
	_push_gameplay_notification(
		GameTextFormatUtility.format_template(
			tr("TARGET_REACHED_MESSAGE"),
			_TARGET_REACHED_MESSAGE_FALLBACK,
			[_get_target_tile_value()]
		),
		_TARGET_REACHED_MESSAGE_DURATION,
		GFNotificationUtility.Level.SUCCESS,
		"gameplay.target_reached",
		GFNotificationUtility.Priority.HIGH
	)
	send_simple_event(EventNames.TARGET_REACHED)


func _should_notify_target_reached(highest_tile: int) -> bool:
	return not _is_replay_mode and not _target_reached_notified and _is_target_reached(highest_tile)


func _get_current_highest_tile() -> int:
	if is_instance_valid(_game_status_model):
		return GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)
	if is_instance_valid(_grid_model):
		return _grid_model.get_max_tile_value()
	return 0


func _sync_target_state(reached: bool) -> void:
	if not is_instance_valid(_game_status_model):
		return
	_game_status_model.set_target_state(_get_target_tile_value(), reached)


func _are_game_states_equal(left: Dictionary, right: Dictionary) -> bool:
	var game_state_system: GameStateSystem = _get_game_state_system()
	if not is_instance_valid(game_state_system):
		return left == right

	return game_state_system.are_states_equal(left, right)


func _restore_replay_trace_from_bookmark(bookmark: BookmarkData) -> void:
	if not is_instance_valid(bookmark):
		return
	_player_actions = bookmark.replay_actions.duplicate()
	_turn_checkpoints = bookmark.replay_checkpoints.duplicate()


func _on_game_state_tainted(_payload: Variant = null) -> void:
	_is_game_state_tainted = true
	var _reason_added: bool = _add_eligibility_reason(
		GameCompetitionEligibility.REASON_DEBUG
	)


func _on_board_resized(_new_size: int) -> void:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_grid_model.topology):
		return

	_current_board_topology = _duplicate_topology(_grid_model.topology)

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.current_board_topology.set_value(_duplicate_topology(_grid_model.topology))


func _on_undo_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING or _is_replay_mode:
		return

	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(command_history) or not _can_undo_player_move(command_history):
		_push_gameplay_notification(
			tr("UNDO_FAIL_MSG"),
			3.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.undo_unavailable"
		)
		return

	if await command_history.undo_last_async():
		var _reason_added: bool = _add_eligibility_reason(
			GameCompetitionEligibility.REASON_UNDO_REDO
		)
		if not _player_actions.is_empty():
			_player_actions.pop_back()
		if not _turn_checkpoints.is_empty():
			_turn_checkpoints.pop_back()
	else:
		_push_gameplay_notification(
			tr("UNDO_FAIL_MSG"),
			3.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.undo_unavailable"
		)


func _can_undo_player_move(command_history: GFCommandHistoryUtility) -> bool:
	var history: Array = command_history.get_undo_history()
	if history.is_empty():
		return false

	var last_cmd_value: Variant = history.back()
	if last_cmd_value is MoveCommand:
		var move_cmd: MoveCommand = last_cmd_value
		return not move_cmd.is_baseline() and move_cmd.get_direction() != Vector2i.ZERO

	return last_cmd_value is GFUndoableCommand


func _on_redo_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING or _is_replay_mode:
		return

	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(command_history) or not _can_redo_player_move(command_history):
		_push_gameplay_notification(
			tr("REDO_FAIL_MSG"),
			3.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.redo_unavailable"
		)
		return

	if await command_history.redo_async():
		var _reason_added: bool = _add_eligibility_reason(
			GameCompetitionEligibility.REASON_UNDO_REDO
		)
		send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	else:
		_push_gameplay_notification(
			tr("REDO_FAIL_MSG"),
			3.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.redo_unavailable"
		)


func _can_redo_player_move(command_history: GFCommandHistoryUtility) -> bool:
	var history: Array = command_history.get_redo_history()
	if history.is_empty():
		return false

	var last_cmd_value: Variant = history.back()
	if last_cmd_value is MoveCommand:
		var move_cmd: MoveCommand = last_cmd_value
		return not move_cmd.is_baseline() and move_cmd.get_direction() != Vector2i.ZERO

	return last_cmd_value is GFUndoableCommand


func _on_save_bookmark_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING:
		return
	if _bookmark_save_in_progress:
		_push_gameplay_notification(
			tr("SNAPSHOT_SAVE_PENDING"),
			3.0,
			GFNotificationUtility.Level.INFO,
			"gameplay.bookmark_save_pending"
		)
		return

	if _is_game_state_tainted:
		_push_gameplay_notification(
			tr("SNAPSHOT_TAINT_WARN"),
			4.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.bookmark_tainted",
			GFNotificationUtility.Priority.HIGH
		)
		return

	var current_state_for_comparison: Dictionary = _get_bookmark_comparison_state()

	if _are_game_states_equal(current_state_for_comparison, _last_saved_bookmark_state):
		_push_gameplay_notification(
			tr("SNAPSHOT_NO_CHANGE"),
			3.0,
			GFNotificationUtility.Level.INFO,
			"gameplay.bookmark_unchanged"
		)
		return

	var new_bookmark: BookmarkData = BookmarkData.new()
	new_bookmark.timestamp = _get_unix_timestamp()
	new_bookmark.mode_config_path = _mode_config_path
	if not new_bookmark.configure_ruleset(_mode_config, _get_determinism_utility()):
		_log_persistence_error("freeze bookmark ruleset", ERR_INVALID_DATA)
		return

	var seed_utility: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_utility):
		new_bookmark.initial_seed = seed_utility.get_global_seed()
	if _session_metadata == null:
		_log_persistence_error("freeze bookmark session metadata", ERR_INVALID_DATA)
		return
	new_bookmark.session_metadata = _session_metadata.to_dict()

	new_bookmark.score = GFVariantData.to_int(current_state_for_comparison.get(&"score", 0), 0)
	new_bookmark.move_count = GFVariantData.to_int(current_state_for_comparison.get(&"move_count", 0), 0)
	new_bookmark.ratio_resolutions = GFVariantData.to_int(current_state_for_comparison.get(&"ratio_resolutions", 0), 0)
	new_bookmark.highest_tile = GFVariantData.to_int(current_state_for_comparison.get(&"highest_tile", 0), 0)
	new_bookmark.target_tile_value = GFVariantData.to_int(current_state_for_comparison.get(&"target_tile_value", 0), 0)
	new_bookmark.target_reached = GFVariantData.to_bool(current_state_for_comparison.get(&"target_reached", false), false)
	var extra_stats: Dictionary = GFVariantData.to_dictionary(current_state_for_comparison.get(&"extra_stats", {}))
	new_bookmark.extra_stats = extra_stats.duplicate(true)
	new_bookmark.rng_full_state = GFVariantData.to_dictionary(current_state_for_comparison.get(&"rng_full_state", {}))
	new_bookmark.board_snapshot = GFVariantData.to_dictionary(current_state_for_comparison.get(&"board_snapshot", {}))
	new_bookmark.rules_states = GFVariantData.to_dictionary(
		current_state_for_comparison.get(&"rules_states", {})
	)

	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if is_instance_valid(command_history):
		new_bookmark.game_state_history = command_history.serialize_full_history()
	new_bookmark.replay_actions = _player_actions.duplicate()
	new_bookmark.replay_checkpoints = _turn_checkpoints.duplicate()

	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	if not is_instance_valid(bookmark_system):
		return
	_bookmark_save_in_progress = true
	var operation: GameSaveSectionOperation = (
		bookmark_system.request_save_bookmark(new_bookmark)
	)
	@warning_ignore("return_value_discarded")
	_complete_bookmark_save.call_deferred(
		operation,
		current_state_for_comparison.duplicate(true),
		_persistence_epoch
	)


func _complete_bookmark_save(
	operation: GameSaveSectionOperation,
	saved_state: Dictionary,
	owner_epoch: int
) -> void:
	if owner_epoch != _persistence_epoch:
		return
	var initial_result: GameSaveSectionResult = (
		operation.get_result()
		if operation != null
		else null
	)
	if initial_result == null and operation != null:
		initial_result = await operation.completed
	if owner_epoch != _persistence_epoch:
		return
	if (
		initial_result != null
		and initial_result.get_status()
		== GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN
	):
		_push_gameplay_notification(
			tr("SNAPSHOT_SAVE_PENDING"),
			4.0,
			GFNotificationUtility.Level.WARNING,
			"gameplay.bookmark_save_pending",
			GFNotificationUtility.Priority.HIGH
		)
	var outcome: Dictionary = await _await_section_operation_settlement(
		operation
	)
	if owner_epoch != _persistence_epoch:
		return
	_bookmark_save_in_progress = false
	if not GFVariantData.get_option_bool(
		outcome,
		&"candidate_persisted",
		false
	):
		var error_code: Error = _get_section_outcome_error(outcome)
		_log_persistence_error("save bookmark", error_code)
		_push_gameplay_notification(
			tr("SNAPSHOT_SAVE_FAILED"),
			3.0,
			GFNotificationUtility.Level.ERROR,
			"gameplay.bookmark_save_failed"
		)
		return
	_last_saved_bookmark_state = saved_state.duplicate(true)
	_push_gameplay_notification(
		tr("SNAPSHOT_SAVED_SUCCESS"),
		3.0,
		GFNotificationUtility.Level.SUCCESS,
		"gameplay.bookmark_saved"
	)


func _on_ui_pause_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name == EventNames.STATE_GAME_OVER or _is_replay_mode:
		return
	send_simple_event(EventNames.TOGGLE_PAUSE_UI)


func _on_resume_game_requested(_payload: Variant = null) -> void:
	var _context_changed: bool = set_target_reached_modal_active(false)
	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility) or not pause_utility.resume():
		push_error("[GameFlowSystem] 无法恢复对局时间。")


func _on_restart_game_requested(_payload: Variant = null) -> void:
	_target_reached_modal_active = false
	restart_game()


func _on_return_to_main_menu_from_game(_payload: Variant = null) -> void:
	_target_reached_modal_active = false
	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility) or not pause_utility.resume():
		push_error("[GameFlowSystem] 无法恢复对局时间，拒绝返回主界面。")
		return
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()


func _on_replay_continue_requested(payload: Variant = null) -> void:
	if not _is_replay_mode:
		return

	var continued_actions: Array[Vector2i] = []
	if payload != null and payload is Object and payload is ReplayContinueData:
		var continue_data: ReplayContinueData = payload
		for action: Vector2i in continue_data.actions:
			continued_actions.append(action)

	_player_actions = continued_actions
	_turn_checkpoints.clear()
	if payload is ReplayContinueData:
		var continued_replay: ReplayData = payload.replay_data
		if is_instance_valid(continued_replay):
			for index: int in range(mini(continued_actions.size(), continued_replay.checkpoints.size())):
				_turn_checkpoints.append(continued_replay.checkpoints[index])
	_is_replay_mode = false
	_is_game_state_tainted = false
	_last_saved_bookmark_state = {}
	var _reason_added: bool = _add_eligibility_reason(
		GameCompetitionEligibility.REASON_REPLAY_CONTINUATION
	)

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.is_replay_mode.set_value(false)

	sync_highest_tile_from_grid()
	_target_reached_notified = _has_reached_target_in_session(_get_current_highest_tile())
	_sync_target_state(_target_reached_notified)
	send_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, payload)
	_push_gameplay_notification(
		tr("REPLAY_CONTINUE_SUCCESS"),
		3.0,
		GFNotificationUtility.Level.SUCCESS,
		"gameplay.replay_continued"
	)


func _on_ratio_resolved(payload: Variant = null) -> void:
	var resolution_count: int = 1
	if payload is int:
		var payload_count: int = payload
		resolution_count = max(payload_count, 0)

	if is_instance_valid(_game_status_model):
		_game_status_model.increment_ratio_resolutions(resolution_count)


func _on_score_updated(amount: int) -> void:
	if is_instance_valid(_game_status_model):
		_game_status_model.add_score(amount)
		_persist_current_high_score()


# --- 内部类 ---

class _SectionReconciliationWaiter:
	extends RefCounted

	signal settled(evidence: Dictionary)

	var _save_graph: GameSaveGraphUtility = null
	var _transaction_id: int = 0
	var _connection: GFSignalConnection = null
	var _terminal: bool = false

	## 绑定一个指定 section transaction 的 reconciliation 终态。
	## @param save_graph: 发布 reconciliation 证据的项目持久化 Utility。
	## @param signal_utility: 拥有安全 Signal 连接的 GF Utility。
	## @param owner: 持有当前等待生命周期的 GameFlowSystem。
	## @param transaction_id: 只接收此 section transaction 的证据。
	func begin(
		save_graph: GameSaveGraphUtility,
		signal_utility: GFSignalUtility,
		owner: Object,
		transaction_id: int
	) -> bool:
		if (
			_terminal
			or _connection != null
			or save_graph == null
			or signal_utility == null
			or owner == null
			or transaction_id <= 0
		):
			return false
		_save_graph = save_graph
		_transaction_id = transaction_id
		_connection = signal_utility.connect_signal(
			_save_graph.section_reconciliation_settled,
			_on_settled,
			owner
		)
		if _connection != null and _connection.is_active():
			return true
		_disconnect()
		return false

	func cancel() -> void:
		if _terminal:
			return
		_terminal = true
		var transaction_id: int = _transaction_id
		_disconnect()
		settled.emit({
			&"transaction_id": transaction_id,
			&"cancelled": true,
			&"candidate_persisted": false,
		})

	func _on_settled(evidence: Dictionary) -> void:
		if (
			_terminal
			or GFVariantData.get_option_int(
				evidence,
				&"transaction_id",
				0
			) != _transaction_id
		):
			return
		_terminal = true
		var evidence_snapshot: Dictionary = evidence.duplicate(true)
		_disconnect()
		settled.emit(evidence_snapshot)

	func _disconnect() -> void:
		if _connection != null:
			_connection.disconnect_signal()
		_connection = null
		_save_graph = null
