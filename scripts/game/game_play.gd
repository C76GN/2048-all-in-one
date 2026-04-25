# scripts/game/game_play.gd

## GamePlay: 通用的游戏逻辑控制器。
##
## 负责加载 GameModeConfig，设置 RuleSystem，并协调核心组件之间的通信。
## 它作为撤回(Undo)、快照(Snapshot)和游戏回放(Replay)功能的总协调者。
class_name GamePlay
extends GFController


# --- 常量 ---

## 暂停菜单场景路径。
const PAUSE_MENU_SCENE: String = "res://scenes/ui/pause_menu.tscn"

## 游戏结束菜单场景路径。
const GAME_OVER_MENU_SCENE: String = "res://scenes/ui/game_over_menu.tscn"


# --- 公共变量 ---

## 标记游戏状态是否已被测试工具修改。


# --- 私有变量 ---

## 当从书签加载时的数据。
var _loaded_bookmark_data: BookmarkData = null

var _game_status_model: GameStatusModel
var _current_game_model: CurrentGameModel

## 命令历史工具，用于支持游戏中的撤销（Undo）等功能
var _command_history: GFCommandHistoryUtility

var _action_queue: GFActionQueueSystem
var _game_flow_system: GameFlowSystem
var _replay_system: ReplaySystem
var _test_utility: TestToolUtility
var _log: GFLogUtility

## 标记是否已完成清理，避免 _exit_tree 重复执行。
var _is_cleaned_up: bool = false


# --- @onready 变量 (节点引用) ---

@onready var game_board: GameBoard = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var background_color_rect: ColorRect = %Background
@onready var _page_title: Label = %PageTitle
@onready var _hud_message_timer: Timer = %HUDMessageTimer
@onready var replay_controls_container: VBoxContainer = %ReplayControlsContainer
@onready var replay_prev_step_button: Button = %ReplayPrevStepButton
@onready var replay_next_step_button: Button = %ReplayNextStepButton
@onready var replay_back_button: Button = %ReplayBackButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = get_model(GameStatusModel) as GameStatusModel
	_current_game_model = get_model(CurrentGameModel) as CurrentGameModel
	_game_flow_system = get_system(GameFlowSystem) as GameFlowSystem
	_replay_system = get_system(ReplaySystem) as ReplaySystem
	_test_utility = get_utility(TestToolUtility) as TestToolUtility
	_log = get_utility(GFLogUtility) as GFLogUtility
	
	if _page_title:
		_page_title.visible = false
		
	if is_instance_valid(_game_status_model):
		if not _game_status_model.move_count.value_changed.is_connected(_on_move_count_changed):
			_game_status_model.move_count.value_changed.connect(_on_move_count_changed)
		
	Gf.listen(GameReadyData, _on_game_ready_data_received)
	Gf.listen_simple(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	Gf.send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)
	_update_static_ui_text()
	
	var console := get_utility(GFConsoleUtility) as GFConsoleUtility
	if Boot.are_dev_tools_enabled() and console:
		console.register_command("toggle_test_panel", _cmd_toggle_test_panel, "Toggle developer test panel.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_static_ui_text()


func _exit_tree() -> void:
	_cleanup_listeners()


# --- 公共方法 ---

# --- 私有/辅助方法 ---

func _update_static_ui_text() -> void:
	if is_instance_valid(replay_prev_step_button):
		replay_prev_step_button.text = tr("BTN_REPLAY_PREV")
	if is_instance_valid(replay_next_step_button):
		replay_next_step_button.text = tr("BTN_REPLAY_NEXT")
	if is_instance_valid(replay_back_button):
		replay_back_button.text = tr("BTN_REPLAY_BACK")

	if is_instance_valid(replay_controls_container):
		var label: Label = replay_controls_container.get_node_or_null("Label") as Label
		if is_instance_valid(label):
			label.text = tr("LABEL_REPLAY_CONTROLS")


func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	
	var console := get_utility(GFConsoleUtility) as GFConsoleUtility
	if console:
		console.unregister_command("toggle_test_panel")
	
	# 清理所有 GF 事件监听，防止旧场景实例在场景重载后仍接收事件
	Gf.unlisten(GameReadyData, _on_game_ready_data_received)
	Gf.unlisten_simple(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	Gf.unlisten_simple(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	Gf.unlisten_simple(EventNames.BOARD_RESIZED, _on_board_resized)
	Gf.unlisten_simple(EventNames.TOGGLE_PAUSE_UI, _on_toggle_pause_ui)
	Gf.unlisten(HudMessagePayload, _on_show_hud_message_event)

	if is_instance_valid(_game_status_model):
		if _game_status_model.move_count.value_changed.is_connected(_on_move_count_changed):
			_game_status_model.move_count.value_changed.disconnect(_on_move_count_changed)

	if is_instance_valid(_test_utility):
		_test_utility.clear_context()
	
	if _log:
		_log.info("GamePlay", "_cleanup_listeners: cleaned up all GF listeners and signal connections")


## 集中管理所有信号连接。
func _connect_signals() -> void:
	if is_instance_valid(replay_prev_step_button) and not replay_prev_step_button.pressed.is_connected(_replay_system.step_backward):
		replay_prev_step_button.pressed.connect(_replay_system.step_backward)
	if is_instance_valid(replay_next_step_button) and not replay_next_step_button.pressed.is_connected(_replay_system.step_forward):
		replay_next_step_button.pressed.connect(_replay_system.step_forward)
	if is_instance_valid(replay_back_button) and not replay_back_button.pressed.is_connected(_on_replay_back_pressed):
		replay_back_button.pressed.connect(_on_replay_back_pressed)

	Gf.listen_simple(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	Gf.listen_simple(EventNames.BOARD_RESIZED, _on_board_resized)
	Gf.listen_simple(EventNames.TOGGLE_PAUSE_UI, _on_toggle_pause_ui)
	Gf.listen(HudMessagePayload, _on_show_hud_message_event)

	if not _hud_message_timer.timeout.is_connected(_on_hud_message_timer_timeout):
		_hud_message_timer.timeout.connect(_on_hud_message_timer_timeout)


## 根据当前是普通模式还是回放模式，配置UI元素的可见性。
func _configure_ui_for_mode() -> void:
	var is_replay: bool = _current_game_model.is_replay_mode.get_value()
	replay_controls_container.visible = is_replay

	test_panel.visible = not is_replay and Boot.are_dev_tools_enabled()

	_update_replay_ui()


## 聚合所有需要显示的数据，并更新到 Model。
func _update_replay_ui() -> void:
	var is_replay: bool = _current_game_model.is_replay_mode.get_value()
	if not is_replay or not is_instance_valid(_replay_system):
		return
		
	replay_prev_step_button.disabled = (_replay_system.get_current_step() <= 0)
	replay_next_step_button.disabled = (_replay_system.get_current_step() >= _replay_system.get_total_steps())


## 在HUD上显示一条临时消息。
## @param message: 要显示的消息文本（支持BBCode）。
## @param duration: 消息显示的持续时间（秒）。
func _show_hud_message(message: String, duration: float) -> void:
	if is_instance_valid(_game_status_model):
		_game_status_model.status_message.set_value(message)
	_hud_message_timer.start(duration)


func _cmd_toggle_test_panel(_args: PackedStringArray) -> void:
	if not Boot.are_dev_tools_enabled():
		return

	if is_instance_valid(test_panel) and not _current_game_model.is_replay_mode.get_value():
		test_panel.visible = not test_panel.visible
		var console := get_utility(GFConsoleUtility) as GFConsoleUtility
		if console and test_panel.visible:
			console.execute_command("clear")
			Gf.send_event(HudMessagePayload.new("Test panel toggled.", 2.0))


# --- 信号处理函数 ---

func _on_scene_will_change(_payload: Variant = null) -> void:
	_cleanup_listeners()


func _on_game_ready_data_received(data: GameReadyData) -> void:
	if not _command_history:
		_command_history = get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
		
	if not _action_queue:
		_action_queue = get_system(GFActionQueueSystem) as GFActionQueueSystem
	
	if _action_queue:
		_action_queue.clear_queue()
			
	_loaded_bookmark_data = data.loaded_bookmark_data
	
	if _current_game_model.is_replay_mode.get_value():
		_replay_system.activate_replay_mode(data.replay_data_resource)
	
	_configure_ui_for_mode()
	
	var mode_config := _current_game_model.mode_config.get_value() as GameModeConfig
	var grid_size := _current_game_model.current_grid_size.get_value() as int
	
	if is_instance_valid(mode_config.board_theme):
		background_color_rect.color = mode_config.board_theme.game_background_color
		game_board.setup(grid_size, data.interaction_rule, data.movement_rule, data.game_over_rule, mode_config.color_schemes, mode_config.board_theme)
	else:
		game_board.setup(grid_size, data.interaction_rule, data.movement_rule, data.game_over_rule, mode_config.color_schemes, null)

	_connect_signals()

	if is_instance_valid(_loaded_bookmark_data):
		game_board.restore_from_snapshot(_loaded_bookmark_data.board_snapshot)
		if is_instance_valid(_game_flow_system):
			_game_flow_system.enter_playing_state()
			_game_flow_system.sync_bookmark_baseline_state()
	else:
		if is_instance_valid(_game_flow_system):
			if _log:
				_log.info("GamePlay", "Triggering initial rules...")
			_game_flow_system.trigger_initial_rules()

	var is_replay: bool = _current_game_model.is_replay_mode.get_value()
	if not is_replay and Boot.are_dev_tools_enabled() and is_instance_valid(_test_utility):
		var grid_model := get_model(GridModel) as GridModel
		if is_instance_valid(grid_model):
			_test_utility.setup_test_tools(test_panel, game_board)
			_test_utility.initialize_panel(grid_model.interaction_rule, _current_game_model.current_grid_size.get_value())
	
	if not is_instance_valid(_loaded_bookmark_data) and _command_history:
		var init_cmd := MoveCommand.new(Vector2i.ZERO)
		init_cmd.mark_as_baseline()
		var game_state_system := get_system(GameStateSystem) as GameStateSystem
		if is_instance_valid(game_state_system):
			init_cmd.set_snapshot(game_state_system.get_full_game_state(grid_size))
		_command_history.record(init_cmd)


func _on_board_resized(new_size: int) -> void:
	if is_instance_valid(_test_utility):
		_test_utility.update_limits(new_size)


func _on_move_count_changed(_old_value: int, _new_value: int) -> void:
	_update_replay_ui()


func _on_toggle_pause_ui(_payload: Variant = null) -> void:
	var tree := get_tree()
	if tree.paused:
		# 恢复游戏：弹出暂停菜单
		var ui_util := get_utility(GFUIUtility) as GFUIUtility
		if ui_util:
			ui_util.pop_panel()
		tree.paused = false
	else:
		# 暂停游戏：弹出暂停菜单
		tree.paused = true
		var ui_util := get_utility(GFUIUtility) as GFUIUtility
		if ui_util:
			ui_util.push_panel(PAUSE_MENU_SCENE)


func _on_show_hud_message_event(payload: HudMessagePayload) -> void:
	if is_instance_valid(payload):
		_show_hud_message(payload.message, payload.duration)


func _on_replay_back_pressed() -> void:
	Gf.send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)


func _on_hud_message_timer_timeout() -> void:
	if is_instance_valid(_game_status_model):
		_game_status_model.status_message.set_value("")





func _on_game_state_changed(new_state: StringName) -> void:
	if new_state == EventNames.STATE_GAME_OVER:
		# 使用 GFUIUtility 弹出游戏结束菜单
		var ui_util := get_utility(GFUIUtility) as GFUIUtility
		if ui_util:
			ui_util.push_panel(GAME_OVER_MENU_SCENE)
