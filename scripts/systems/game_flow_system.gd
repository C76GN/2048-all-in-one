## GameFlowSystem: 负责管理游戏整体流程和规则触发的核心系统。
##
## 该系统监听来自其他系统或控制器的事件，并调用 RuleSystem 执行对应的规则，
## 例如判断游戏结束、触发方块生成等。
class_name GameFlowSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GameFlowSystem"
const _GAME_TEXT_FORMATTER: GDScript = preload("res://scripts/utilities/game_text_format_utility.gd")
const _TARGET_REACHED_MESSAGE_DURATION: float = 4.0
const _TARGET_REACHED_MESSAGE_FALLBACK: String = "[color=green]已达成目标 %d！可以继续挑战更高方块。[/color]"


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
var _current_grid_size: int = 4
var _initial_seed_of_session: int = 0
var _last_saved_bookmark_state: Dictionary = {}
var _player_actions: Array[Vector2i] = []

## 核心状态机。
var _fsm: GFStateMachine

var _log: GFLogUtility


# --- Godot 生命周期方法 ---

## 初始化内部状态机。
func init() -> void:
	_fsm = GFStateMachine.new(self)
	_fsm.add_state(EventNames.STATE_READY, GameReadyState.new())
	_fsm.add_state(EventNames.STATE_PLAYING, GamePlayingState.new())
	_fsm.add_state(EventNames.STATE_GAME_OVER, GameOverState.new())


## 处理初始化，绑定事件。
func ready() -> void:
	_grid_model = _get_grid_model()
	_game_status_model = _get_game_status_model()
	_log = _get_log_utility()

	register_event(MoveData, _on_move_made)
	register_simple_event(EventNames.TURN_FINISHED, _on_turn_finished)
	register_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)
	register_simple_event(EventNames.SCORE_UPDATED, _on_score_updated)
	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.UNDO_REQUESTED, _on_undo_requested)
	register_simple_event(EventNames.REDO_REQUESTED, _on_redo_requested)
	register_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED, _on_save_bookmark_requested)
	register_simple_event(EventNames.UI_PAUSE_REQUESTED, _on_ui_pause_requested)
	register_simple_event(EventNames.GAME_STATE_TAINTED, _on_game_state_tainted)
	register_simple_event(EventNames.BOARD_RESIZED, _on_board_resized)
	register_simple_event(EventNames.RESUME_GAME_REQUESTED, _on_resume_game_requested)
	register_simple_event(EventNames.RESTART_GAME_REQUESTED, _on_restart_game_requested)
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, _on_return_to_main_menu_from_game)
	register_simple_event(EventNames.REPLAY_CONTINUE_REQUESTED, _on_replay_continue_requested)


## 释放事件监听、状态机和运行时缓存。
func dispose() -> void:
	unregister_event(MoveData, _on_move_made)
	unregister_simple_event(EventNames.TURN_FINISHED, _on_turn_finished)
	unregister_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)
	unregister_simple_event(EventNames.SCORE_UPDATED, _on_score_updated)
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.UNDO_REQUESTED, _on_undo_requested)
	unregister_simple_event(EventNames.REDO_REQUESTED, _on_redo_requested)
	unregister_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED, _on_save_bookmark_requested)
	unregister_simple_event(EventNames.UI_PAUSE_REQUESTED, _on_ui_pause_requested)
	unregister_simple_event(EventNames.GAME_STATE_TAINTED, _on_game_state_tainted)
	unregister_simple_event(EventNames.BOARD_RESIZED, _on_board_resized)
	unregister_simple_event(EventNames.RESUME_GAME_REQUESTED, _on_resume_game_requested)
	unregister_simple_event(EventNames.RESTART_GAME_REQUESTED, _on_restart_game_requested)
	unregister_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, _on_return_to_main_menu_from_game)
	unregister_simple_event(EventNames.REPLAY_CONTINUE_REQUESTED, _on_replay_continue_requested)

	if _fsm != null:
		_fsm.dispose()
		_fsm = null

	_grid_model = null
	_game_status_model = null
	_rule_system = null
	_game_over_rule = null
	_log = null
	_player_actions.clear()
	_last_saved_bookmark_state = {}
	_mode_config = null
	_mode_config_path = ""
	_target_reached_notified = false
	_is_replay_mode = false
	_is_game_state_tainted = false
	_current_grid_size = 4
	_initial_seed_of_session = 0


## 更新游戏流程状态机。
## @param delta: 当前帧间隔。
func tick(delta: float) -> void:
	if _fsm != null:
		_fsm.update(delta)


# --- 公共方法 ---

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


## 检查游戏是否结束。
func check_game_over() -> void:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_over_rule):
		return
	if _grid_model.interaction_rule != null:
		if _game_over_rule.is_game_over(_grid_model, _grid_model.interaction_rule):
			send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, _grid_model.get_snapshot())
			send_simple_event(EventNames.GAME_LOST)
			if _is_replay_mode:
				return
			if _fsm == null:
				return
			_fsm.change_state(EventNames.STATE_GAME_OVER)
			_handle_game_over()


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

	tree.paused = false
	var mode_config_value: Variant = current_game_model.mode_config.get_value()
	if not mode_config_value is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_config_value
	var grid_size: int = GFVariantData.to_int(current_game_model.current_grid_size.get_value(), 4)
	var initial_seed: int = GFVariantData.to_int(current_game_model.initial_seed.get_value(), 0)
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "重新开始本局: initial_seed=%d, grid_size=%d" % [initial_seed, grid_size])

	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.selected_mode_config_path.set_value(mode_config.resource_path)
		app_config.selected_grid_size.set_value(grid_size)
		app_config.selected_seed.set_value(initial_seed)
		if is_instance_valid(_log):
			_log.debug(_LOG_TAG, "已写回 AppConfigModel.selected_seed=%d" % initial_seed)

	var seed_utility: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_utility):
		if is_instance_valid(_log):
			_log.debug(_LOG_TAG, "预设全局随机种子: %d" % initial_seed)
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


func _get_ui_utility() -> GFUIUtility:
	var utility_value: Object = get_utility(GFUIUtility)
	if utility_value is GFUIUtility:
		var ui_utility: GFUIUtility = utility_value
		return ui_utility
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


func _get_save_system() -> SaveSystem:
	var system_value: Object = get_system(SaveSystem)
	if system_value is SaveSystem:
		var save_system: SaveSystem = system_value
		return save_system
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

	_persist_current_game_result()

	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_status_model):
		return

	var replay_data: ReplayData = ReplayData.new()
	replay_data.timestamp = int(Time.get_unix_time_from_system())
	replay_data.mode_config_path = _mode_config_path
	replay_data.initial_seed = _initial_seed_of_session
	var current_grid_size: int = _get_current_grid_size()
	replay_data.grid_size = current_grid_size

	replay_data.actions = _player_actions.duplicate()
	replay_data.final_board_snapshot = _grid_model.get_snapshot()
	replay_data.final_score = GFVariantData.to_int(_game_status_model.score.get_value(), 0)

	if not _is_game_state_tainted and not replay_data.actions.is_empty():
		var replay_system: ReplaySystem = _get_replay_system()
		if is_instance_valid(replay_system):
			replay_system.save_replay(replay_data)


func _on_game_ready(data: GameReadyData) -> void:
	_is_replay_mode = data.is_replay_mode
	_is_game_state_tainted = false
	if is_instance_valid(data.mode_config):
		_mode_config = data.mode_config
		_mode_config_path = data.mode_config.resource_path
	else:
		_mode_config = null
	_current_grid_size = data.current_grid_size
	_initial_seed_of_session = data.initial_seed
	_player_actions.clear()
	_last_saved_bookmark_state = {}
	var initial_target_reached: bool = _is_target_reached(_get_initial_highest_tile(data))
	if is_instance_valid(data.loaded_bookmark_data):
		initial_target_reached = initial_target_reached or data.loaded_bookmark_data.target_reached
	_sync_target_state(initial_target_reached)
	_target_reached_notified = initial_target_reached
	if is_instance_valid(data.loaded_bookmark_data):
		_rebuild_player_actions_from_history()


func _get_current_grid_size() -> int:
	if is_instance_valid(_grid_model) and _grid_model.grid_size > 0:
		return _grid_model.grid_size

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		var grid_size: int = GFVariantData.to_int(current_game_model.current_grid_size.get_value(), 4)
		if grid_size > 0:
			return grid_size

	return _current_grid_size


func _get_full_game_state() -> Dictionary:
	var game_state_system: GameStateSystem = _get_game_state_system()
	if is_instance_valid(game_state_system):
		return game_state_system.get_full_game_state(_get_current_grid_size())
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

	var save_system: SaveSystem = _get_save_system()
	if not is_instance_valid(save_system):
		return

	var mode_id: String = _mode_config_path.get_file().get_basename()
	var current_grid_size: int = _get_current_grid_size()
	var best_score: int = GFVariantData.to_int(_game_status_model.high_score.get_value(), 0)
	save_system.set_high_score(mode_id, current_grid_size, best_score)


func _persist_current_game_result() -> void:
	if _is_replay_mode or _is_game_state_tainted:
		return
	if _mode_config_path.is_empty() or not is_instance_valid(_game_status_model):
		return

	var save_system: SaveSystem = _get_save_system()
	if not is_instance_valid(save_system):
		return

	sync_highest_tile_from_grid()
	var mode_id: String = _mode_config_path.get_file().get_basename()
	var current_grid_size: int = _get_current_grid_size()
	var final_score: int = GFVariantData.to_int(_game_status_model.score.get_value(), 0)
	var move_count: int = GFVariantData.to_int(_game_status_model.move_count.get_value(), 0)
	var highest_tile: int = GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)
	var target_value: int = _get_target_tile_value()
	var target_reached: bool = _has_reached_target_in_session(highest_tile)
	save_system.record_game_result(
		mode_id,
		current_grid_size,
		final_score,
		move_count,
		highest_tile,
		0,
		target_value,
		target_reached
	)


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


func _notify_target_reached_if_needed() -> void:
	var highest_tile: int = _get_current_highest_tile()
	if not _should_notify_target_reached(highest_tile):
		return

	_target_reached_notified = true
	_sync_target_state(true)
	send_event(HudMessagePayload.new(
		_GAME_TEXT_FORMATTER.format_template(
			tr("TARGET_REACHED_MESSAGE"),
			_TARGET_REACHED_MESSAGE_FALLBACK,
			[_get_target_tile_value()]
		),
		_TARGET_REACHED_MESSAGE_DURATION
	))
	send_simple_event(EventNames.TARGET_REACHED)


func _should_notify_target_reached(highest_tile: int) -> bool:
	return not _is_replay_mode and not _target_reached_notified and _is_target_reached(highest_tile)


func _get_current_highest_tile() -> int:
	if is_instance_valid(_game_status_model):
		return GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)
	if is_instance_valid(_grid_model):
		return _grid_model.get_max_player_value()
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


func _rebuild_player_actions_from_history() -> void:
	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(command_history):
		return

	for cmd_value: Variant in command_history.get_undo_history():
		if cmd_value is MoveCommand:
			var move_cmd: MoveCommand = cmd_value
			if move_cmd.is_baseline():
				continue
			var direction: Vector2i = move_cmd.get_direction()
			if direction != Vector2i.ZERO:
				_player_actions.append(direction)


func _on_game_state_tainted(_payload: Variant = null) -> void:
	_is_game_state_tainted = true


func _on_board_resized(new_size: int) -> void:
	if new_size <= 0:
		return

	_current_grid_size = new_size

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.current_grid_size.set_value(new_size)


func _on_undo_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING or _is_replay_mode:
		return

	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(command_history) or not _can_undo_player_move(command_history):
		send_event(HudMessagePayload.new(tr("UNDO_FAIL_MSG"), 3.0))
		return

	if await command_history.undo_last_async():
		if not _player_actions.is_empty():
			_player_actions.pop_back()
	else:
		send_event(HudMessagePayload.new(tr("UNDO_FAIL_MSG"), 3.0))


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
		send_event(HudMessagePayload.new(tr("REDO_FAIL_MSG"), 3.0))
		return

	if await command_history.redo_async():
		send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	else:
		send_event(HudMessagePayload.new(tr("REDO_FAIL_MSG"), 3.0))


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

	if _is_game_state_tainted:
		send_event(HudMessagePayload.new(tr("SNAPSHOT_TAINT_WARN"), 4.0))
		return

	var current_state_for_comparison: Dictionary = _get_bookmark_comparison_state()

	if _are_game_states_equal(current_state_for_comparison, _last_saved_bookmark_state):
		send_event(HudMessagePayload.new(tr("SNAPSHOT_NO_CHANGE"), 3.0))
		return

	var new_bookmark: BookmarkData = BookmarkData.new()
	new_bookmark.timestamp = int(Time.get_unix_time_from_system())
	new_bookmark.mode_config_path = _mode_config_path

	var seed_utility: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_utility):
		new_bookmark.initial_seed = seed_utility.get_global_seed()

	new_bookmark.score = GFVariantData.to_int(current_state_for_comparison.get(&"score", 0), 0)
	new_bookmark.move_count = GFVariantData.to_int(current_state_for_comparison.get(&"move_count", 0), 0)
	new_bookmark.monsters_killed = GFVariantData.to_int(current_state_for_comparison.get(&"monsters_killed", 0), 0)
	new_bookmark.highest_tile = GFVariantData.to_int(current_state_for_comparison.get(&"highest_tile", 0), 0)
	new_bookmark.target_tile_value = GFVariantData.to_int(current_state_for_comparison.get(&"target_tile_value", 0), 0)
	new_bookmark.target_reached = GFVariantData.to_bool(current_state_for_comparison.get(&"target_reached", false), false)
	new_bookmark.status_message = GFVariantData.to_text(current_state_for_comparison.get(&"status_message", ""), "")
	var extra_stats: Dictionary = GFVariantData.to_dictionary(current_state_for_comparison.get(&"extra_stats", {}))
	new_bookmark.extra_stats = extra_stats.duplicate(true)
	new_bookmark.rng_state = GFVariantData.to_int(current_state_for_comparison.get(&"rng_state", 0), 0)
	new_bookmark.rng_full_state = GFVariantData.to_dictionary(current_state_for_comparison.get(&"rng_full_state", {}))
	new_bookmark.board_snapshot = GFVariantData.to_dictionary(current_state_for_comparison.get(&"board_snapshot", {}))
	new_bookmark.rules_states = GFVariantData.to_array(current_state_for_comparison.get(&"rules_states", []))

	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	if is_instance_valid(command_history):
		new_bookmark.game_state_history = command_history.serialize_full_history()

	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	if is_instance_valid(bookmark_system):
		bookmark_system.save_bookmark(new_bookmark)
	_last_saved_bookmark_state = current_state_for_comparison.duplicate(true)
	send_event(HudMessagePayload.new(tr("SNAPSHOT_SAVED_SUCCESS"), 3.0))

func _on_ui_pause_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name == EventNames.STATE_GAME_OVER or _is_replay_mode:
		return
	send_simple_event(EventNames.TOGGLE_PAUSE_UI)


func _on_resume_game_requested(_payload: Variant = null) -> void:
	var ui_util: GFUIUtility = _get_ui_utility()
	if is_instance_valid(ui_util):
		ui_util.pop_panel()
	var tree: SceneTree = _get_scene_tree()
	if is_instance_valid(tree):
		tree.paused = false


func _on_restart_game_requested(_payload: Variant = null) -> void:
	var ui_util: GFUIUtility = _get_ui_utility()
	if is_instance_valid(ui_util):
		ui_util.clear_all()
	restart_game()


func _on_return_to_main_menu_from_game(_payload: Variant = null) -> void:
	var ui_util: GFUIUtility = _get_ui_utility()
	if is_instance_valid(ui_util):
		ui_util.clear_all()
	var tree: SceneTree = _get_scene_tree()
	if is_instance_valid(tree):
		tree.paused = false
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
	_is_replay_mode = false
	_is_game_state_tainted = false
	_last_saved_bookmark_state = {}

	var current_game_model: CurrentGameModel = _get_current_game_model()
	if is_instance_valid(current_game_model):
		current_game_model.is_replay_mode.set_value(false)

	sync_highest_tile_from_grid()
	_target_reached_notified = _has_reached_target_in_session(_get_current_highest_tile())
	_sync_target_state(_target_reached_notified)
	send_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, payload)
	send_event(HudMessagePayload.new(tr("REPLAY_CONTINUE_SUCCESS"), 3.0))


func _on_move_made(move_data: MoveData) -> void:
	if is_instance_valid(move_data):
		if not _is_replay_mode and move_data.direction != Vector2i.ZERO:
			_player_actions.append(move_data.direction)
		if is_instance_valid(_game_status_model):
			_game_status_model.increment_move_count()
		sync_highest_tile_from_grid()


func _on_monster_killed(payload: Variant = null) -> void:
	var kill_count: int = 1
	if payload is int:
		var payload_count: int = payload
		kill_count = max(payload_count, 0)

	if is_instance_valid(_game_status_model):
		_game_status_model.increment_monsters_killed(kill_count)


func _on_turn_finished(_payload: Variant = null) -> void:
	sync_highest_tile_from_grid()
	_notify_target_reached_if_needed()
	check_game_over()

func _on_score_updated(amount: int) -> void:
	if is_instance_valid(_game_status_model):
		_game_status_model.add_score(amount)
		_persist_current_high_score()
