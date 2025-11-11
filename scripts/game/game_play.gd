# scripts/game/game_play.gd

## GamePlay: 通用的游戏逻辑控制器。
##
## 负责加载 GameModeConfig，设置 RuleManager，并协调核心组件之间的通信。
## 它使用状态机管理游戏生命周期，并作为撤回(Undo)、快照(Snapshot)和
## 游戏回放(Replay)功能的总协调者。
class_name GamePlay
extends Control


# --- 枚举 ---

## 定义了 GamePlay 的核心状态。
enum State {
	## 游戏已初始化，等待开始
	READY,
	## 游戏正在进行中
	PLAYING,
	## 游戏已结束
	GAME_OVER,
}


# --- 常量 ---

## 重启确认对话框的场景资源。
const RESTART_CONFIRM_DIALOG_SCENE: PackedScene = preload("res://scenes/ui/restart_confirm_dialog.tscn")

## 玩家输入源的脚本资源。
const PLAYER_INPUT_SOURCE_SCRIPT: Script = preload("res://scripts/core/player_input_source.gd")

## 回放输入源的脚本资源。
const REPLAY_INPUT_SOURCE_SCRIPT: Script = preload("res://scripts/core/replay_input_source.gd")


# --- 公共变量 ---

## 当前加载的游戏模式配置。
var mode_config: GameModeConfig

## 当前生效的交互规则。
var interaction_rule: InteractionRule

## 当前生效的规则管理器。
var rule_manager: RuleManager

## 当前模式下所有生成规则的实例数组。
var all_spawn_rules: Array[SpawnRule] = []

## 当前游戏的移动次数。
var move_count: int = 0

## 当前游戏消灭的怪物数量。
var monsters_killed: int = 0

## 当前游戏的分数。
var score: int = 0

## 当前棋盘的尺寸。
var current_grid_size: int = 4

## 进入游戏时的最高分记录。
var initial_high_score: int = 0


# --- 私有变量 ---

## 从书签加载时的数据。
var _loaded_bookmark_data: BookmarkData = null

## 上次保存书签时的完整游戏状态，用于防止重复保存。
var _last_saved_bookmark_state: Dictionary = {}

## 在HUD上显示的临时状态消息。
var _hud_status_message: String = ""

## 标记游戏状态是否已被测试工具修改。
var _is_game_state_tainted_by_test_tools: bool = false

## 本次游戏会话的初始种子。
var _initial_seed_of_session: int = 0

## 当前使用的输入源实例 (玩家或回放)。
var _input_source: BaseInputSource

## 标记当前是否为回放模式。
var _is_replay_mode: bool = false


# --- @onready 变量 (节点引用) ---

@onready var game_board: Control = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var hud: VBoxContainer = %HUD
@onready var background_color_rect: ColorRect = %ColorRect
@onready var board_animator: BoardAnimator = $BoardAnimator
@onready var state_machine: StateMachine = $StateMachine
@onready var undo_button: Button = %UndoButton
@onready var snapshot_button: Button = %SnapshotButton
@onready var ui_manager: UIManager = $UIManager
@onready var _hud_message_timer: Timer = %HUDMessageTimer
@onready var replay_controls_container: VBoxContainer = %ReplayControlsContainer
@onready var replay_prev_step_button: Button = %ReplayPrevStepButton
@onready var replay_next_step_button: Button = %ReplayNextStepButton
@onready var replay_back_button: Button = %ReplayBackButton
@onready var _history_manager: GameHistoryManager = $GameHistoryManager


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_initialize_game()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		_on_pause_toggled()
		get_viewport().set_input_as_handled()


# --- FSM 状态处理 ---

## [FSM] 状态机进入当前状态时被调用。
## @param new_state: 新状态。
## @param _message: 状态进入时的附加信息。
func _enter_state(new_state: State, _message: Dictionary = {}) -> void:
	match new_state:
		State.PLAYING:
			if is_instance_valid(_input_source):
				_input_source.start()
		State.GAME_OVER:
			if is_instance_valid(_input_source):
				_input_source.stop()

			for rule in all_spawn_rules:
				rule.teardown()

			if not _is_replay_mode:
				var mode_id: String = mode_config.resource_path.get_file().get_basename()
				SaveManager.set_high_score(mode_id, current_grid_size, score)

				var replay_data_to_save := ReplayData.new()
				replay_data_to_save.timestamp = int(Time.get_unix_time_from_system())
				replay_data_to_save.mode_config_path = mode_config.resource_path
				replay_data_to_save.initial_seed = _initial_seed_of_session
				replay_data_to_save.grid_size = current_grid_size
				replay_data_to_save.actions = _history_manager.get_action_sequence()

				if not _is_game_state_tainted_by_test_tools:
					if not replay_data_to_save.actions.is_empty():
						replay_data_to_save.final_score = score
						ReplayManager.save_replay(replay_data_to_save)
				else:
					print("警告: 游戏状态已被测试工具修改，回放将不会被保存。")

			if _is_replay_mode:
				replay_next_step_button.disabled = true
			else:
				ui_manager.show_ui(UIManager.UIType.GAME_OVER)


## [FSM] 状态机退出当前状态时被调用。
## @param _old_state: 退出的旧状态。
func _exit_state(_old_state: State) -> void:
	pass


## [FSM] 状态机在当前状态下每帧被调用。
## @param _delta: 帧间隔时间。
## @param current_state: 当前状态。
func _process_state(_delta: float, current_state: State) -> void:
	match current_state:
		State.PLAYING:
			_update_and_publish_hud_data()


# --- 私有/辅助方法 ---

## 负责整个游戏场景的初始化或重置。
## @param new_grid_size: 如果提供，则使用此尺寸开始新游戏，否则使用全局设置。
func _initialize_game(new_grid_size: int = -1) -> void:
	state_machine.set_state(State.READY)
	_is_game_state_tainted_by_test_tools = false

	var replay_data: ReplayData = GlobalGameManager.current_replay_data
	_loaded_bookmark_data = GlobalGameManager.selected_bookmark_data
	GlobalGameManager.current_replay_data = null
	GlobalGameManager.selected_bookmark_data = null

	_is_replay_mode = is_instance_valid(replay_data)
	_history_manager.clear()

	if is_instance_valid(_loaded_bookmark_data):
		if not _setup_game_from_bookmark(): return
	elif _is_replay_mode:
		if not _setup_replay_game(replay_data): return
	else:
		if not _setup_new_game(new_grid_size): return

	_finalize_initialization()


## 从一个有效的书签数据中设置游戏状态。
## @return: 如果设置成功返回 true，否则返回 false。
func _setup_game_from_bookmark() -> bool:
	mode_config = load(_loaded_bookmark_data.mode_config_path)
	current_grid_size = _loaded_bookmark_data.board_snapshot.get("grid_size")
	RNGManager.initialize_rng(_loaded_bookmark_data.initial_seed)
	RNGManager.set_state(_loaded_bookmark_data.rng_state)
	score = _loaded_bookmark_data.score
	move_count = _loaded_bookmark_data.move_count
	monsters_killed = _loaded_bookmark_data.monsters_killed

	if "game_state_history" in _loaded_bookmark_data and not _loaded_bookmark_data.game_state_history.is_empty():
		_history_manager.load_history(_loaded_bookmark_data.game_state_history.duplicate(true) as Array[Dictionary])

	_input_source = PLAYER_INPUT_SOURCE_SCRIPT.new()
	return true


## 根据全局设置或传入参数来配置一个新游戏。
## @param new_grid_size: 用于开始新游戏的棋盘尺寸。
## @return: 如果设置成功返回 true，否则返回 false。
func _setup_new_game(new_grid_size: int = -1) -> bool:
	if new_grid_size > -1:
		var new_seed: int = int(Time.get_unix_time_from_system())
		RNGManager.initialize_rng(new_seed)

	var config_path: String = GlobalGameManager.get_selected_mode_config_path()
	if new_grid_size > -1:
		current_grid_size = new_grid_size
	else:
		current_grid_size = GlobalGameManager.get_selected_grid_size()

	if not config_path.is_empty():
		mode_config = load(config_path)
		assert(is_instance_valid(mode_config), "GameModeConfig未能加载！")
	else:
		push_error("错误: 无法加载游戏模式配置。")
		get_tree().paused = false
		GlobalGameManager.return_to_main_menu()
		return false

	_input_source = PLAYER_INPUT_SOURCE_SCRIPT.new()
	return true


## 配置一个回放游戏。
## @param replay_data: 用于回放的游戏数据。
## @return: 如果设置成功返回 true，否则返回 false。
func _setup_replay_game(replay_data: ReplayData) -> bool:
	mode_config = load(replay_data.mode_config_path)
	current_grid_size = replay_data.grid_size
	RNGManager.initialize_rng(replay_data.initial_seed)

	var replay_input_source := REPLAY_INPUT_SOURCE_SCRIPT.new() as ReplayInputSource
	replay_input_source.initialize(replay_data)
	_input_source = replay_input_source
	return true


## 在设置好游戏模式和状态后，完成所有节点的实例化和连接。
func _finalize_initialization() -> void:
	_initial_seed_of_session = RNGManager.get_current_seed()
	add_child(_input_source)

	_configure_ui_for_mode()

	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	initial_high_score = SaveManager.get_high_score(mode_id, current_grid_size)

	game_board.grid_size = current_grid_size

	rule_manager = RuleManager.new()
	add_child(rule_manager)

	interaction_rule = mode_config.interaction_rule.duplicate() as InteractionRule
	interaction_rule.setup(game_board)
	var movement_rule: MovementRule = mode_config.movement_rule.duplicate() as MovementRule
	var game_over_rule: GameOverRule = mode_config.game_over_rule.duplicate() as GameOverRule

	if is_instance_valid(mode_config.board_theme):
		background_color_rect.color = mode_config.board_theme.game_background_color
		game_board.set_rules(interaction_rule, movement_rule, game_over_rule, mode_config.color_schemes, mode_config.board_theme)
	else:
		push_warning("当前游戏模式没有配置BoardTheme，将使用默认颜色。")
		game_board.set_rules(interaction_rule, movement_rule, game_over_rule, mode_config.color_schemes, null)

	all_spawn_rules.clear()
	for rule_resource in mode_config.spawn_rules:
		var rule_instance: SpawnRule = rule_resource.duplicate() as SpawnRule
		all_spawn_rules.append(rule_instance)

		var required_nodes: Dictionary = rule_instance.get_required_nodes()
		var created_nodes: Dictionary = {}
		if not required_nodes.is_empty():
			for node_key in required_nodes:
				if required_nodes[node_key] == "Timer":
					var new_timer := Timer.new()
					add_child(new_timer)
					created_nodes[node_key] = new_timer

		rule_instance.setup(game_board, created_nodes)

	rule_manager.register_rules(all_spawn_rules)
	game_board.initialize_board()
	_connect_signals()

	if is_instance_valid(_loaded_bookmark_data):
		game_board.restore_from_snapshot(_loaded_bookmark_data.board_snapshot)
		_last_saved_bookmark_state = _get_full_game_state()
	else:
		rule_manager.dispatch_event(RuleManager.Events.INITIALIZE_BOARD)

	_initialize_test_tools()
	_update_and_publish_hud_data()

	if not is_instance_valid(_loaded_bookmark_data):
		_save_current_state(null)

	state_machine.set_state(State.PLAYING)


## 集中管理所有信号连接。
func _connect_signals() -> void:
	if is_instance_valid(_input_source) and not _input_source.action_triggered.is_connected(_on_input_source_action_triggered):
		_input_source.action_triggered.connect(_on_input_source_action_triggered)

	if not ui_manager.resume_requested.is_connected(_on_resume_game):
		ui_manager.resume_requested.connect(_on_resume_game)
	if not ui_manager.restart_requested.is_connected(_on_restart_game):
		ui_manager.restart_requested.connect(_on_restart_game)
	if not ui_manager.main_menu_requested.is_connected(_on_return_to_main_menu):
		ui_manager.main_menu_requested.connect(_on_return_to_main_menu)

	if is_instance_valid(undo_button) and not undo_button.pressed.is_connected(_on_undo_button_pressed):
		undo_button.pressed.connect(_on_undo_button_pressed)
	if is_instance_valid(snapshot_button) and not snapshot_button.pressed.is_connected(_on_snapshot_button_pressed):
		snapshot_button.pressed.connect(_on_snapshot_button_pressed)

	if is_instance_valid(replay_prev_step_button) and not replay_prev_step_button.pressed.is_connected(_on_replay_prev_step_pressed):
		replay_prev_step_button.pressed.connect(_on_replay_prev_step_pressed)
	if is_instance_valid(replay_next_step_button) and not replay_next_step_button.pressed.is_connected(_on_replay_next_step_pressed):
		replay_next_step_button.pressed.connect(_on_replay_next_step_pressed)
	if is_instance_valid(replay_back_button) and not replay_back_button.pressed.is_connected(_on_replay_back_pressed):
		replay_back_button.pressed.connect(_on_replay_back_pressed)

	if not _hud_message_timer.timeout.is_connected(_on_hud_message_timer_timeout):
		_hud_message_timer.timeout.connect(_on_hud_message_timer_timeout)

	if is_instance_valid(rule_manager) and not rule_manager.spawn_tile_requested.is_connected(game_board.spawn_tile):
		rule_manager.spawn_tile_requested.connect(game_board.spawn_tile)

	if not EventBus.move_made.is_connected(_on_move_made):
		EventBus.move_made.connect(_on_move_made)
	if not EventBus.game_lost.is_connected(_on_game_lost):
		EventBus.game_lost.connect(_on_game_lost)
	if not EventBus.score_updated.is_connected(_on_score_updated):
		EventBus.score_updated.connect(_on_score_updated)
	if not EventBus.monster_killed.is_connected(_on_monster_killed):
		EventBus.monster_killed.connect(_on_monster_killed)
	if not EventBus.board_resized.is_connected(_on_board_resized):
		EventBus.board_resized.connect(_on_board_resized)

	if is_instance_valid(game_board) and is_instance_valid(board_animator):
		if not game_board.play_animations_requested.is_connected(board_animator.play_animation_sequence):
			game_board.play_animations_requested.connect(board_animator.play_animation_sequence)


## 根据当前是普通模式还是回放模式，配置UI元素的可见性。
func _configure_ui_for_mode() -> void:
	var is_interactive_mode: bool = not _is_replay_mode
	undo_button.visible = is_interactive_mode
	snapshot_button.visible = is_interactive_mode
	replay_controls_container.visible = _is_replay_mode

	test_panel.visible = false if _is_replay_mode else OS.has_feature("editor")

	_update_replay_buttons_state()


## 聚合所有需要显示的数据，并通过全局事件总线发布给HUD。
func _update_and_publish_hud_data() -> void:
	var display_data: Dictionary = {}

	if _is_replay_mode and _input_source is ReplayInputSource:
		var total_steps: int = _input_source.get_total_steps()
		var current_step_display: int = _history_manager.get_history_size() - 1
		display_data["step_info"] = "步骤: %d / %d" % [current_step_display, total_steps]

	display_data["score"] = "分数: %d" % score
	if not _is_replay_mode:
		if score > initial_high_score:
			display_data["high_score"] = "最高分: %d [color=yellow](新纪录!)[/color]" % score
		else:
			display_data["high_score"] = "最高分: %d" % initial_high_score

	display_data["highest_tile"] = "最大方块: %d" % game_board.get_max_player_value()
	display_data["move_count"] = "移动次数: %d" % move_count

	var player_values: Array = game_board.get_all_player_tile_values()
	var player_values_set: Dictionary = {}
	for v in player_values: player_values_set[v] = true

	var rule_context: Dictionary = {
		"monsters_killed": monsters_killed, "score": score, "move_count": move_count,
		"all_player_values": player_values, "max_player_value": game_board.get_max_player_value(),
		"player_values_set": player_values_set
	}

	if is_instance_valid(interaction_rule):
		var interaction_data: Dictionary = interaction_rule.get_hud_context_data(rule_context)
		display_data.merge(interaction_data)

	for rule in all_spawn_rules:
		var rule_data: Dictionary = rule.get_display_data()
		if not rule_data.is_empty():
			display_data.merge(rule_data)

	display_data["separator"] = "--------------------"
	if not mode_config.mode_description.is_empty():
		display_data["description"] = mode_config.mode_description

	if not _is_replay_mode:
		display_data["controls"] = "操作: W/A/S/D 或 方向键\n暂停: Esc"

	display_data["seed_info"] = "游戏种子: %d" % RNGManager.get_current_seed()

	if _is_game_state_tainted_by_test_tools:
		display_data["taint_warning"] = "[color=orange]警告: 调试工具已使用，回放将被禁用。[/color]"

	if not _hud_status_message.is_empty():
		display_data["status_message"] = _hud_status_message

	EventBus.hud_update_requested.emit(display_data)


## 初始化测试工具（仅在编辑器中运行时）。
func _initialize_test_tools() -> void:
	if not OS.has_feature("editor") or _is_replay_mode:
		test_panel.visible = false
		return

	test_panel.visible = true

	if not test_panel.spawn_requested.is_connected(_on_test_panel_spawn_requested):
		test_panel.spawn_requested.connect(_on_test_panel_spawn_requested)
	if not test_panel.values_requested_for_type.is_connected(_on_test_panel_values_requested):
		test_panel.values_requested_for_type.connect(_on_test_panel_values_requested)
	if not test_panel.reset_and_resize_requested.is_connected(_on_reset_and_resize_requested):
		test_panel.reset_and_resize_requested.connect(_on_reset_and_resize_requested)
	if not test_panel.live_expand_requested.is_connected(game_board.live_expand):
		test_panel.live_expand_requested.connect(func(new_size: int):
			_is_game_state_tainted_by_test_tools = true
			game_board.live_expand(new_size)
		)

	var spawnable_types: Dictionary = interaction_rule.get_spawnable_types()
	test_panel.setup_panel(spawnable_types)
	test_panel.update_coordinate_limits(current_grid_size)


## 保存当前游戏的完整状态，用于撤回。
## @param action: 导致此状态的玩家动作 (例如 Vector2i.UP)。
func _save_current_state(action: Variant) -> void:
	var state: Dictionary = _get_full_game_state()
	state["action"] = action
	_history_manager.save_state(state)


## 获取当前游戏的完整状态快照。
## @return: 一个包含游戏所有可序列化状态的字典。
func _get_full_game_state() -> Dictionary:
	var rules_states: Array = []
	for rule in all_spawn_rules:
		rules_states.append(rule.get_state())

	return {
		"board_snapshot": game_board.get_state_snapshot(),
		"rng_state": RNGManager.get_state(),
		"score": score,
		"move_count": move_count,
		"monsters_killed": monsters_killed,
		"rules_states": rules_states
	}


## 从一个状态字典中恢复完整的游戏状态。
## @param state_to_restore: 包含完整游戏状态的字典。
func _restore_state(state_to_restore: Dictionary) -> void:
	if state_machine.get_current_state() == State.GAME_OVER:
		state_machine.set_state(State.PLAYING)

	score = state_to_restore["score"]
	move_count = state_to_restore["move_count"]
	monsters_killed = state_to_restore["monsters_killed"]
	RNGManager.set_state(state_to_restore["rng_state"])
	game_board.restore_from_snapshot(state_to_restore["board_snapshot"])

	if state_to_restore.has("rules_states"):
		var rules_states: Array = state_to_restore["rules_states"]
		for i in range(min(all_spawn_rules.size(), rules_states.size())):
			all_spawn_rules[i].set_state(rules_states[i])

	_update_and_publish_hud_data()
	_update_replay_buttons_state()


## 在HUD上显示一条临时消息。
## @param message: 要显示的消息文本（支持BBCode）。
## @param duration: 消息显示的持续时间（秒）。
func _show_hud_message(message: String, duration: float) -> void:
	_hud_status_message = message
	_update_and_publish_hud_data()
	_hud_message_timer.start(duration)


## 显示重启确认对话框，让用户选择重启方式。
func _show_restart_confirmation() -> void:
	var dialog: RestartConfirmDialog = RESTART_CONFIRM_DIALOG_SCENE.instantiate()
	dialog.restart_from_bookmark.connect(_on_restart_from_bookmark_confirmed)
	dialog.restart_as_new_game.connect(_on_restart_as_new_game_confirmed)
	dialog.dismissed.connect(func():
		if get_tree().paused and state_machine.get_current_state() != State.GAME_OVER:
			ui_manager.show_ui(UIManager.UIType.PAUSE)
	)
	dialog.tree_exited.connect(dialog.queue_free)
	ui_manager.close_current_ui()
	ui_manager._canvas_layer.add_child(dialog)
	dialog.popup_centered()


## 根据当前的回放进度，更新回放控制按钮（上一步/下一步）的可用状态。
func _update_replay_buttons_state() -> void:
	if not _is_replay_mode or not _input_source is ReplayInputSource: return

	replay_prev_step_button.disabled = _history_manager.get_history_size() <= 1

	var is_at_end: bool = _history_manager.get_history_size() >= (_input_source.get_total_steps() + 1)
	replay_next_step_button.disabled = is_at_end

	if is_at_end and state_machine.get_current_state() != State.GAME_OVER:
		state_machine.set_state(State.GAME_OVER)


# --- 信号处理函数 ---

func _on_input_source_action_triggered(action: Variant) -> void:
	if state_machine.get_current_state() != State.PLAYING:
		return

	var move_was_valid: bool = game_board.handle_move(action)
	if move_was_valid:
		_save_current_state(action)
		_update_and_publish_hud_data()


func _on_move_made(move_data: Dictionary) -> void:
	move_count += 1
	rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED, move_data)
	_update_and_publish_hud_data()
	_update_replay_buttons_state()


func _on_game_lost() -> void:
	await get_tree().process_frame
	state_machine.set_state(State.GAME_OVER)


func _on_monster_killed() -> void:
	monsters_killed += 1
	rule_manager.dispatch_event(RuleManager.Events.MONSTER_KILLED)
	_update_and_publish_hud_data()


func _on_score_updated(amount: int) -> void:
	score += amount
	_update_and_publish_hud_data()


func _on_board_resized(new_size: int) -> void:
	if OS.has_feature("editor") and is_instance_valid(test_panel):
		test_panel.update_coordinate_limits(new_size)


func _on_pause_toggled() -> void:
	if state_machine.get_current_state() == State.GAME_OVER or _is_replay_mode:
		return

	if get_tree().paused:
		ui_manager.close_current_ui()
	else:
		ui_manager.show_ui(UIManager.UIType.PAUSE)


func _on_resume_game() -> void:
	state_machine.set_state(State.PLAYING)


func _on_restart_game(_from_bookmark: bool) -> void:
	if is_instance_valid(_loaded_bookmark_data):
		_show_restart_confirmation()
	else:
		get_tree().paused = false
		var current_scene_resource: PackedScene = load(get_tree().current_scene.scene_file_path)
		GlobalGameManager.select_mode_and_start(
			mode_config.resource_path,
			current_scene_resource,
			current_grid_size,
			_initial_seed_of_session
		)


func _on_return_to_main_menu() -> void:
	get_tree().paused = false
	GlobalGameManager.return_to_main_menu()


func _on_undo_button_pressed() -> void:
	if state_machine.get_current_state() != State.PLAYING or get_tree().paused or _is_replay_mode:
		return

	if _history_manager.can_undo():
		var previous_state: Dictionary = _history_manager.undo()
		_restore_state(previous_state)
	else:
		_show_hud_message("[color=yellow]无法撤回: 已在最初状态。[/color]", 3.0)


func _on_snapshot_button_pressed() -> void:
	if state_machine.get_current_state() != State.PLAYING or get_tree().paused:
		return

	if _is_game_state_tainted_by_test_tools:
		_show_hud_message("[color=orange]警告: 正在保存一个被调试工具修改过的状态！[/color]", 4.0)

	var current_state_for_comparison: Dictionary = _get_full_game_state()
	current_state_for_comparison["game_state_history"] = _history_manager.get_history()

	if JSON.stringify(current_state_for_comparison) == JSON.stringify(_last_saved_bookmark_state):
		_show_hud_message("[color=yellow]游戏状态未变，无需重复保存。[/color]", 3.0)
		return

	var new_bookmark := BookmarkData.new()
	new_bookmark.timestamp = int(Time.get_unix_time_from_system())
	new_bookmark.mode_config_path = mode_config.resource_path
	new_bookmark.initial_seed = RNGManager.get_current_seed()

	var latest_atomic_state: Dictionary = _history_manager.get_history().back()
	new_bookmark.score = latest_atomic_state["score"]
	new_bookmark.move_count = latest_atomic_state["move_count"]
	new_bookmark.monsters_killed = latest_atomic_state["monsters_killed"]
	new_bookmark.rng_state = latest_atomic_state["rng_state"]
	new_bookmark.board_snapshot = latest_atomic_state["board_snapshot"]
	new_bookmark.game_state_history = _history_manager.get_history().duplicate(true)

	BookmarkManager.save_bookmark(new_bookmark)
	_last_saved_bookmark_state = current_state_for_comparison
	_show_hud_message("[color=green]书签已保存！[/color]", 3.0)


func _on_hud_message_timer_timeout() -> void:
	_hud_status_message = ""
	_update_and_publish_hud_data()


func _on_restart_from_bookmark_confirmed() -> void:
	get_tree().paused = false
	GlobalGameManager.selected_bookmark_data = _loaded_bookmark_data
	get_tree().reload_current_scene()


func _on_restart_as_new_game_confirmed() -> void:
	get_tree().paused = false
	var new_seed: int = int(Time.get_unix_time_from_system())
	var current_scene_resource: PackedScene = load(get_tree().current_scene.scene_file_path)
	GlobalGameManager.select_mode_and_start(
		_loaded_bookmark_data.mode_config_path,
		current_scene_resource,
		_loaded_bookmark_data.board_snapshot.get("grid_size", 4),
		new_seed
	)


func _on_replay_prev_step_pressed() -> void:
	if not _is_replay_mode: return
	if _history_manager.get_history_size() > 1:
		var previous_state: Dictionary = _history_manager.undo()
		if previous_state != null:
			_restore_state(previous_state)
		_update_replay_buttons_state()


func _on_replay_next_step_pressed() -> void:
	if not _is_replay_mode: return
	if _input_source is ReplayInputSource:
		var next_step_index: int = _history_manager.get_history_size() - 1
		if next_step_index < _input_source.get_total_steps():
			_input_source.play_step(next_step_index)


func _on_replay_back_pressed() -> void:
	GlobalGameManager.return_to_main_menu()


func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	_is_game_state_tainted_by_test_tools = true
	var tile_type_enum: Tile.TileType = interaction_rule.get_tile_type_from_id(type_id)
	game_board.spawn_specific_tile(grid_pos, value, tile_type_enum)


func _on_test_panel_values_requested(type_id: int) -> void:
	var values: Array[int] = interaction_rule.get_spawnable_values(type_id)
	test_panel.update_value_options(values)


func _on_reset_and_resize_requested(new_size: int) -> void:
	_is_game_state_tainted_by_test_tools = true
	var current_scene_resource: PackedScene = load(get_tree().current_scene.scene_file_path)
	GlobalGameManager.select_mode_and_start(
		mode_config.resource_path,
		current_scene_resource,
		new_size,
		_initial_seed_of_session
	)
