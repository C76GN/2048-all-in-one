# scripts/systems/game_flow_system.gd

## GameFlowSystem: 负责管理游戏整体流程和规则触发的核心系统。
##
## 该系统监听来自其他系统或控制器的事件，并调用 RuleSystem 执行对应的规则，
## 例如判断游戏结束、触发方块生成等。
class_name GameFlowSystem
extends GFSystem

# --- 缓存引用 ---
var _grid_model: GridModel
var _game_status_model: GameStatusModel
var _rule_system: RuleSystem
var _game_over_rule: GameOverRule

# --- 私有变量 ---
var _is_replay_mode: bool = false
var _is_game_state_tainted: bool = false
var _mode_config_path: String = ""
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
	_fsm.add_state(EventNames.STATE_READY, GFStateReady.new())
	_fsm.add_state(EventNames.STATE_PLAYING, GFStatePlaying.new())
	_fsm.add_state(EventNames.STATE_GAME_OVER, GFStateGameOver.new())


## 处理初始化，绑定事件。
func ready() -> void:
	_grid_model = get_model(GridModel) as GridModel
	_game_status_model = get_model(GameStatusModel) as GameStatusModel
	_log = get_utility(GFLogUtility) as GFLogUtility

	Gf.listen(MoveData, _on_move_made)
	Gf.listen_simple(EventNames.TURN_FINISHED, _on_turn_finished)
	Gf.listen_simple(EventNames.MONSTER_KILLED, _on_monster_killed)
	Gf.listen_simple(EventNames.SCORE_UPDATED, _on_score_updated)
	Gf.listen(GameReadyData, _on_game_ready)
	Gf.listen_simple(EventNames.UNDO_REQUESTED, _on_undo_requested)
	Gf.listen_simple(EventNames.SAVE_BOOKMARK_REQUESTED, _on_save_bookmark_requested)
	Gf.listen_simple(EventNames.UI_PAUSE_REQUESTED, _on_ui_pause_requested)
	Gf.listen_simple(EventNames.GAME_STATE_TAINTED, _on_game_state_tainted)
	
	# --- UI 菜单请求事件监听 ---
	Gf.listen_simple(EventNames.RESUME_GAME_REQUESTED, _on_resume_game_requested)
	Gf.listen_simple(EventNames.RESTART_GAME_REQUESTED, _on_restart_game_requested)
	Gf.listen_simple(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, _on_return_to_main_menu_from_game)


func dispose() -> void:
	Gf.unlisten(MoveData, _on_move_made)
	Gf.unlisten_simple(EventNames.TURN_FINISHED, _on_turn_finished)
	Gf.unlisten_simple(EventNames.MONSTER_KILLED, _on_monster_killed)
	Gf.unlisten_simple(EventNames.SCORE_UPDATED, _on_score_updated)
	Gf.unlisten(GameReadyData, _on_game_ready)
	Gf.unlisten_simple(EventNames.UNDO_REQUESTED, _on_undo_requested)
	Gf.unlisten_simple(EventNames.SAVE_BOOKMARK_REQUESTED, _on_save_bookmark_requested)
	Gf.unlisten_simple(EventNames.UI_PAUSE_REQUESTED, _on_ui_pause_requested)
	Gf.unlisten_simple(EventNames.GAME_STATE_TAINTED, _on_game_state_tainted)
	
	Gf.unlisten_simple(EventNames.RESUME_GAME_REQUESTED, _on_resume_game_requested)
	Gf.unlisten_simple(EventNames.RESTART_GAME_REQUESTED, _on_restart_game_requested)
	Gf.unlisten_simple(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, _on_return_to_main_menu_from_game)

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
	_mode_config_path = ""
	_is_replay_mode = false
	_is_game_state_tainted = false
	_current_grid_size = 4
	_initial_seed_of_session = 0


func tick(delta: float) -> void:
	if _fsm != null:
		_fsm.update(delta)


# --- 公共方法 ---

## 注入当前游戏的规则环境。
func setup(rule_system: RuleSystem, game_over_rule: GameOverRule) -> void:
	_rule_system = rule_system
	_game_over_rule = game_over_rule


## 将当前完整状态标记为已保存的书签基线。
func sync_bookmark_baseline_state() -> void:
	_last_saved_bookmark_state = _get_bookmark_comparison_state()


## 进入可操作的游戏状态，不触发棋盘初始化。
func enter_playing_state() -> void:
	if _fsm == null:
		return

	_fsm.start(EventNames.STATE_READY)
	_fsm.change_state(EventNames.STATE_PLAYING)


## 触发初始棋盘规则。
func trigger_initial_rules() -> void:
	enter_playing_state()
	Gf.send_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION)


## 检查游戏是否结束。
func check_game_over() -> void:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_game_over_rule):
		return
	if _grid_model.interaction_rule != null:
		if _game_over_rule.is_game_over(_grid_model, _grid_model.interaction_rule):
			Gf.send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, _grid_model.get_snapshot())
			Gf.send_simple_event(EventNames.GAME_LOST)
			_fsm.change_state(EventNames.STATE_GAME_OVER)
			_handle_game_over()

func _handle_game_over() -> void:
	if _is_replay_mode:
		return
		
	var save_system := get_system(SaveSystem) as SaveSystem
	if save_system:
		var mode_id: String = _mode_config_path.get_file().get_basename()
		save_system.set_high_score(mode_id, _current_grid_size, _game_status_model.score.get_value())
	
	var replay_data := ReplayData.new()
	replay_data.timestamp = int(Time.get_unix_time_from_system())
	replay_data.mode_config_path = _mode_config_path
	replay_data.initial_seed = _initial_seed_of_session
	replay_data.grid_size = _current_grid_size
	
	replay_data.actions = _player_actions.duplicate()
	replay_data.final_board_snapshot = _grid_model.get_snapshot()
	replay_data.final_score = _game_status_model.score.get_value()
	
	if not _is_game_state_tainted and not replay_data.actions.is_empty():
		var replay_system := get_system(ReplaySystem) as ReplaySystem
		if replay_system:
			replay_system.save_replay(replay_data)


func restart_game() -> void:
	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if not router:
		return

	var current_game_model := get_model(CurrentGameModel) as CurrentGameModel
	if not current_game_model:
		return

	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return

	tree.paused = false
	var mode_config := current_game_model.mode_config.get_value() as GameModeConfig
	if not is_instance_valid(mode_config):
		return
	var grid_size := current_game_model.current_grid_size.get_value() as int
	var initial_seed := current_game_model.initial_seed.get_value() as int
	if _log:
		_log.info("GameFlowSystem", "restart_game: initial_seed=%d, grid_size=%d" % [initial_seed, grid_size])

	var app_config := get_model(AppConfigModel) as AppConfigModel
	if app_config:
		app_config.selected_mode_config_path.set_value(mode_config.resource_path)
		app_config.selected_grid_size.set_value(grid_size)
		app_config.selected_seed.set_value(initial_seed)
		if _log:
			_log.info("GameFlowSystem", "Set app_config.selected_seed=%d" % initial_seed)

	var seed_utility := get_utility(GFSeedUtility) as GFSeedUtility
	if seed_utility:
		if _log:
			_log.info("GameFlowSystem", "Pre-setting global seed to %d" % initial_seed)
		seed_utility.set_global_seed(initial_seed)

	if is_instance_valid(tree.current_scene) and not tree.current_scene.scene_file_path.is_empty():
		router.goto_scene(tree.current_scene.scene_file_path)


# --- 私有事件处理 ---

func _on_game_ready(data: GameReadyData) -> void:
	_is_replay_mode = data.is_replay_mode
	_is_game_state_tainted = false
	if is_instance_valid(data.mode_config):
		_mode_config_path = data.mode_config.resource_path
	_current_grid_size = data.current_grid_size
	_initial_seed_of_session = data.initial_seed
	_player_actions.clear()
	_last_saved_bookmark_state = {}
	if is_instance_valid(data.loaded_bookmark_data):
		_rebuild_player_actions_from_history()

func _get_full_game_state() -> Dictionary:
	var utility := get_system(GameStateSystem) as GameStateSystem
	if utility:
		return utility.get_full_game_state(_current_grid_size)
	return {}


func _get_bookmark_comparison_state() -> Dictionary:
	var state := _get_full_game_state()
	var command_history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if command_history:
		state[&"game_state_history"] = command_history.serialize_history()
	return state


func _rebuild_player_actions_from_history() -> void:
	var command_history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if not command_history:
		return

	for cmd in command_history.get_undo_history():
		if cmd is MoveCommand:
			var move_cmd := cmd as MoveCommand
			if move_cmd.is_baseline():
				continue
			var direction: Vector2i = move_cmd.get_direction()
			if direction != Vector2i.ZERO:
				_player_actions.append(direction)


func _on_game_state_tainted(_payload: Variant = null) -> void:
	_is_game_state_tainted = true


func _on_undo_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING or _is_replay_mode:
		return
	var _command_history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if _command_history and _can_undo_player_move(_command_history):
		if _command_history.undo_last() and not _player_actions.is_empty():
			_player_actions.pop_back()
	else:
		Gf.send_event(HudMessagePayload.new(tr("UNDO_FAIL_MSG"), 3.0))


func _can_undo_player_move(command_history: GFCommandHistoryUtility) -> bool:
	var history := command_history.get_undo_history()
	if history.is_empty():
		return false

	var last_cmd: GFUndoableCommand = history.back() as GFUndoableCommand
	if last_cmd is MoveCommand:
		var move_cmd := last_cmd as MoveCommand
		return not move_cmd.is_baseline() and move_cmd.get_direction() != Vector2i.ZERO

	return true


func _on_save_bookmark_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name != EventNames.STATE_PLAYING:
		return
		
	if _is_game_state_tainted:
		Gf.send_event(HudMessagePayload.new(tr("SNAPSHOT_TAINT_WARN"), 4.0))

	var current_state_for_comparison: Dictionary = _get_bookmark_comparison_state()

	if JSON.stringify(current_state_for_comparison) == JSON.stringify(_last_saved_bookmark_state):
		Gf.send_event(HudMessagePayload.new(tr("SNAPSHOT_NO_CHANGE"), 3.0))
		return

	var new_bookmark := BookmarkData.new()
	new_bookmark.timestamp = int(Time.get_unix_time_from_system())
	new_bookmark.mode_config_path = _mode_config_path
	
	var seed_utility := get_utility(GFSeedUtility) as GFSeedUtility
	if is_instance_valid(seed_utility):
		new_bookmark.initial_seed = seed_utility.get_global_seed()

	new_bookmark.score = current_state_for_comparison.get(&"score", 0)
	new_bookmark.move_count = current_state_for_comparison.get(&"move_count", 0)
	new_bookmark.monsters_killed = current_state_for_comparison.get(&"monsters_killed", 0)
	new_bookmark.highest_tile = current_state_for_comparison.get(&"highest_tile", 0)
	new_bookmark.status_message = current_state_for_comparison.get(&"status_message", "")
	var extra_stats: Dictionary = current_state_for_comparison.get(&"extra_stats", {})
	new_bookmark.extra_stats = extra_stats.duplicate(true)
	new_bookmark.rng_state = current_state_for_comparison.get(&"rng_state", 0)
	new_bookmark.board_snapshot = current_state_for_comparison.get(&"board_snapshot", {})
	new_bookmark.rules_states = current_state_for_comparison.get(&"rules_states", [])
	
	var _command_history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if _command_history:
		new_bookmark.game_state_history = _command_history.serialize_history()

	var bookmark_system := get_system(BookmarkSystem) as BookmarkSystem
	if bookmark_system:
		bookmark_system.save_bookmark(new_bookmark)
	_last_saved_bookmark_state = current_state_for_comparison
	Gf.send_event(HudMessagePayload.new(tr("SNAPSHOT_SAVED_SUCCESS"), 3.0))
	
func _on_ui_pause_requested(_payload: Variant = null) -> void:
	if _fsm.current_state_name == EventNames.STATE_GAME_OVER or _is_replay_mode:
		return
	Gf.send_simple_event(EventNames.TOGGLE_PAUSE_UI)


func _on_resume_game_requested(_payload: Variant = null) -> void:
	var ui_util := get_utility(GFUIUtility) as GFUIUtility
	if ui_util:
		ui_util.pop_panel()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.paused = false


func _on_restart_game_requested(_payload: Variant = null) -> void:
	var ui_util := get_utility(GFUIUtility) as GFUIUtility
	if ui_util:
		ui_util.clear_all()
	restart_game()


func _on_return_to_main_menu_from_game(_payload: Variant = null) -> void:
	var ui_util := get_utility(GFUIUtility) as GFUIUtility
	if ui_util:
		ui_util.clear_all()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.paused = false
	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.return_to_main_menu()

func _on_move_made(move_data: MoveData) -> void:
	if is_instance_valid(move_data):
		if not _is_replay_mode and move_data.direction != Vector2i.ZERO:
			_player_actions.append(move_data.direction)
		_game_status_model.move_count.set_value(_game_status_model.move_count.get_value() + 1)
		
		# 更新最高方块值
		var max_val: int = _grid_model.get_max_player_value()
		_game_status_model.highest_tile.set_value(max_val)


func _on_monster_killed(_payload: Variant = null) -> void:
	_game_status_model.monsters_killed.set_value(_game_status_model.monsters_killed.get_value() + 1)


func _on_turn_finished(_payload: Variant = null) -> void:
	check_game_over()

func _on_score_updated(amount: int) -> void:
	var new_score: int = _game_status_model.score.get_value() + amount
	_game_status_model.score.set_value(new_score)
	
	# 实时更新局内显示最高分
	if new_score > _game_status_model.high_score.get_value():
		_game_status_model.high_score.set_value(new_score)
