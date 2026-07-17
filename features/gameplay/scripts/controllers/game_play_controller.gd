## GamePlayController: 通用的游戏逻辑控制器。
##
## 负责加载 GameModeConfig，设置 RuleSystem，并协调核心组件之间的通信。
## 它作为撤回(Undo)、快照(Snapshot)和游戏回放(Replay)功能的总协调者。
class_name GamePlayController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 常量 ---

const _LOG_TAG: String = "GamePlayController"
const _LEVEL_CLEANUP_ACTION_QUEUES: StringName = &"gameplay_action_queues"
const _ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const _ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const _ROUTE_TARGET_REACHED_MENU: StringName = &"target_reached_menu"
const _REPLAY_PROGRESS_FORMAT_FALLBACK: String = "回放进度: %d / %d"
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")
const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_ui_motion_utility.gd")


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
var _level_utility: GFLevelUtility
var _pause_utility: GamePauseUtility
var _signal_utility: GFSignalUtility
var _notification_utility: GFNotificationUtility
var _test_utility: TestToolUtility
var _log: GFLogUtility
var _theme_utility: GameThemeUtility
var _celebration_vfx_utility: GameCelebrationVfxUtility
var _console_command_subscription: GFLifetimeSubscription

## 标记是否已完成清理，避免 _exit_tree 重复执行。
var _is_cleaned_up: bool = false


# --- @onready 变量 (节点引用) ---

@onready var game_board: GameBoardController = %GameBoard
@onready var test_panel: Node = %TestPanel
@onready var _test_panel_controller: TestPanel = _get_test_panel_controller()
@onready var background_color_rect: ColorRect = %Background
@onready var _page_title: Label = %PageTitle
@onready var replay_controls_container: VBoxContainer = %ReplayControlsContainer
@onready var replay_progress_label: Label = %ReplayProgressLabel
@onready var replay_step_hint_label: Label = %ReplayStepHintLabel
@onready var replay_action_hint_label: Label = %ReplayActionHintLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = _get_game_status_model()
	_current_game_model = _get_current_game_model()
	_game_flow_system = _get_game_flow_system()
	_replay_system = _get_replay_system()
	_level_utility = _get_level_utility()
	_pause_utility = _get_pause_utility()
	_signal_utility = _get_signal_utility()
	_notification_utility = _get_notification_utility()
	_test_utility = _get_test_utility()
	_log = _get_log_utility()
	_theme_utility = _get_theme_utility()
	_celebration_vfx_utility = _get_celebration_vfx_utility()
	_apply_current_ui_theme()
	_register_level_runtime_cleanup()
	
	if _page_title:
		_page_title.visible = false
		
	if is_instance_valid(_game_status_model):
		_connect_managed_signal(_game_status_model.move_count.value_changed, _on_move_count_changed)
	if is_instance_valid(_theme_utility):
		_connect_managed_signal(_theme_utility.visual_theme_changed, _on_visual_theme_changed)
		
	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready_data_received", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))
	send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)
	_update_static_ui_text()
	
	var console: GFConsoleUtility = _get_console_utility()
	if Boot.are_dev_tools_enabled() and is_instance_valid(console):
		_console_command_subscription = console.register_command(
			self,
			"toggle_test_panel",
			Callable(self, &"_cmd_toggle_test_panel"),
			"Toggle developer test panel.",
			{"tier": GFConsoleUtility.CommandTier.INPUT}
		)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_static_ui_text()


func _exit_tree() -> void:
	_cleanup_listeners()
	super._exit_tree()


# --- 公共方法 ---

# --- 私有/辅助方法 ---

func _update_static_ui_text() -> void:
	if is_instance_valid(replay_controls_container):
		var label: Label = _get_replay_controls_label()
		if is_instance_valid(label):
			label.text = tr("LABEL_REPLAY_CONTROLS")
	if is_instance_valid(replay_step_hint_label):
		replay_step_hint_label.text = tr("REPLAY_KEYS_STEP_HINT")
	if is_instance_valid(replay_action_hint_label):
		replay_action_hint_label.text = tr("REPLAY_KEYS_ACTION_HINT")


func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	
	_unregister_level_runtime_cleanup()

	if _console_command_subscription != null:
		var _console_command_cancelled: bool = _console_command_subscription.cancel()
		_console_command_subscription = null
	
	_clear_action_queues()

	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_owner_events(self)

	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)

	if is_instance_valid(_test_utility):
		_test_utility.clear_context()

	_level_utility = null
	_pause_utility = null
	_celebration_vfx_utility = null
	_notification_utility = null
	
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已清理 GF 事件监听和原生信号连接。")


func _clear_action_queues() -> void:
	if not is_instance_valid(_action_queue):
		_action_queue = _get_action_queue_system()

	if is_instance_valid(_action_queue):
		_action_queue.clear_queue(true)
		_action_queue.clear_all_named_queues(true)


func _register_level_runtime_cleanup() -> void:
	if is_instance_valid(_level_utility):
		var _registered: bool = _level_utility.register_runtime_cleanup(_LEVEL_CLEANUP_ACTION_QUEUES, _clear_action_queues)


func _unregister_level_runtime_cleanup() -> void:
	if is_instance_valid(_level_utility):
		var _unregistered: bool = _level_utility.unregister_runtime_cleanup(_LEVEL_CLEANUP_ACTION_QUEUES)


func _connect_managed_signal(source_signal: Signal, callback: Callable) -> void:
	if not is_instance_valid(_signal_utility):
		push_error("[GamePlayController] 缺少 GFSignalUtility，无法连接跨生命周期信号。")
		return
	var _connection: GFSignalConnection = _signal_utility.connect_signal(source_signal, callback, self)


func _is_replay_mode() -> bool:
	if not is_instance_valid(_current_game_model):
		return false
	return GFVariantData.to_bool(_current_game_model.is_replay_mode.get_value(), false)


## 集中管理所有信号连接。
func _connect_signals() -> void:
	if is_instance_valid(_replay_system):
		_connect_managed_signal(_replay_system.playback_progress_changed, _on_replay_progress_changed)
		_connect_managed_signal(_replay_system.playback_status_changed, _on_replay_status_changed)

	register_simple_event(EventNames.GAME_STATE_CHANGED, GFEventListener.from_method(self, &"_on_game_state_changed", 1))
	register_simple_event(EventNames.BOARD_RESIZED, GFEventListener.from_method(self, &"_on_board_resized", 1))
	register_simple_event(EventNames.TOGGLE_PAUSE_UI, GFEventListener.from_method(self, &"_on_toggle_pause_ui", 1))
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, GFEventListener.from_method(self, &"_on_replay_continued_as_game", 1))
	register_simple_event(EventNames.TARGET_REACHED, GFEventListener.from_method(self, &"_on_target_reached", 1))


## 根据当前是普通模式还是回放模式，配置UI元素的可见性。
func _configure_ui_for_mode() -> void:
	if not is_instance_valid(_current_game_model):
		return

	var is_replay: bool = _is_replay_mode()
	replay_controls_container.visible = is_replay

	_set_test_panel_visible(not is_replay and Boot.are_dev_tools_enabled())

	_update_replay_ui()


## 聚合所有需要显示的数据，并更新到 Model。
func _update_replay_ui() -> void:
	if not is_instance_valid(_current_game_model):
		return

	if not is_instance_valid(_replay_system):
		return

	var current_step: int = _replay_system.get_current_step()
	var total_steps: int = _replay_system.get_total_steps()
	if is_instance_valid(replay_progress_label):
		replay_progress_label.text = GameTextFormatUtility.format_template(
			tr("LABEL_REPLAY_PROGRESS"),
			_REPLAY_PROGRESS_FORMAT_FALLBACK,
			[current_step, total_steps]
		)


func _cmd_toggle_test_panel(_args: PackedStringArray) -> void:
	if not Boot.are_dev_tools_enabled():
		return

	if is_instance_valid(test_panel) and not _is_replay_mode():
		_set_test_panel_visible(not _is_test_panel_visible())
		var console: GFConsoleUtility = _get_console_utility()
		if is_instance_valid(console) and _is_test_panel_visible():
			var _command_executed: bool = console.execute_command("clear")
			if is_instance_valid(_notification_utility):
				var _notification_id: int = _notification_utility.push_notification(
					"测试面板已切换。",
					"",
					GFNotificationUtility.Level.INFO,
					{
						"duration_seconds": 2.0,
						"key": "diagnostics.test_panel_toggled",
						"metadata": {"surface": "gameplay_hud"},
					}
				)


func _setup_test_tools_for_current_board() -> void:
	if (
		not Boot.are_dev_tools_enabled()
		or not is_instance_valid(_test_utility)
		or not is_instance_valid(_current_game_model)
		or not is_instance_valid(_test_panel_controller)
		or _is_replay_mode()
	):
		return

	var grid_model: GridModel = _get_grid_model()
	if is_instance_valid(grid_model):
		_test_utility.setup_test_tools(_test_panel_controller, game_board)
		var board_size: Vector2i = grid_model.get_bounds_size()
		_test_utility.initialize_panel(
			grid_model.interaction_rule,
			board_size
		)


func _apply_game_background_theme(theme: BoardTheme) -> void:
	if not is_instance_valid(background_color_rect):
		return

	if not is_instance_valid(_theme_utility):
		push_error("[GamePlayController] 缺少 GameThemeUtility，无法应用玩法背景主题。")
		return

	_theme_utility.apply_background_to_color_rect(background_color_rect, theme)


func _apply_mode_visual_theme(mode_config: GameModeConfig, refresh_snapshot: bool = false) -> void:
	if not is_instance_valid(mode_config) or not is_instance_valid(game_board):
		return
	if not is_instance_valid(_theme_utility):
		push_error("[GamePlayController] 缺少 GameThemeUtility，无法解析玩法视觉主题。")
		return

	var resolved_board_theme: BoardTheme = _theme_utility.resolve_board_theme(mode_config.board_theme)
	var resolved_color_schemes: Dictionary = _theme_utility.resolve_color_schemes(mode_config.color_schemes)

	_apply_game_background_theme(resolved_board_theme)
	game_board.setup(resolved_color_schemes, resolved_board_theme)

	if refresh_snapshot:
		var grid_model: GridModel = _get_grid_model()
		if is_instance_valid(grid_model):
			game_board.call_deferred(&"restore_from_snapshot", grid_model.get_snapshot())


func _apply_current_ui_theme() -> void:
	if is_instance_valid(_theme_utility):
		var _theme_apply_count: int = _theme_utility.apply_current_theme_to_tree(self)

	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(motion_utility):
		var _bound_count: int = motion_utility.bind_interactive_controls(self)


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_current_game_model() -> CurrentGameModel:
	var model_value: Object = get_model(CurrentGameModel)
	if model_value is CurrentGameModel:
		var current_model: CurrentGameModel = model_value
		return current_model
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_game_flow_system() -> GameFlowSystem:
	var system_value: Object = get_system(GameFlowSystem)
	if system_value is GameFlowSystem:
		var game_flow: GameFlowSystem = system_value
		return game_flow
	return null


func _get_replay_system() -> ReplaySystem:
	var system_value: Object = get_system(ReplaySystem)
	if system_value is ReplaySystem:
		var replay_system: ReplaySystem = system_value
		return replay_system
	return null


func _get_action_queue_system() -> GFActionQueueSystem:
	var system_value: Object = get_system(GFActionQueueSystem)
	if system_value is GFActionQueueSystem:
		var action_queue: GFActionQueueSystem = system_value
		return action_queue
	return null


func _get_game_state_system() -> GameStateSystem:
	var system_value: Object = get_system(GameStateSystem)
	if system_value is GameStateSystem:
		var game_state: GameStateSystem = system_value
		return game_state
	return null


func _get_level_utility() -> GFLevelUtility:
	var utility_value: Object = get_utility(GFLevelUtility)
	if utility_value is GFLevelUtility:
		var level_utility: GFLevelUtility = utility_value
		return level_utility
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


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_notification_utility() -> GFNotificationUtility:
	var utility_value: Object = get_utility(GFNotificationUtility)
	if utility_value is GFNotificationUtility:
		var notification_utility: GFNotificationUtility = utility_value
		return notification_utility
	return null


func _get_test_utility() -> TestToolUtility:
	var utility_value: Object = get_utility(TestToolUtility)
	if utility_value is TestToolUtility:
		var test_utility: TestToolUtility = utility_value
		return test_utility
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_console_utility() -> GFConsoleUtility:
	var utility_value: Object = get_utility(GFConsoleUtility)
	if utility_value is GFConsoleUtility:
		var console: GFConsoleUtility = utility_value
		return console
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(_GAME_UI_MOTION_UTILITY_SCRIPT)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_celebration_vfx_utility() -> GameCelebrationVfxUtility:
	if is_instance_valid(_celebration_vfx_utility):
		return _celebration_vfx_utility
	var utility_value: Object = get_utility(GameCelebrationVfxUtility)
	if utility_value is GameCelebrationVfxUtility:
		var celebration_vfx: GameCelebrationVfxUtility = utility_value
		_celebration_vfx_utility = celebration_vfx
		return celebration_vfx
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


func _get_ui_router_utility() -> GFUIRouterUtility:
	var utility_value: Object = get_utility(GFUIRouterUtility)
	if utility_value is GFUIRouterUtility:
		var ui_router: GFUIRouterUtility = utility_value
		return ui_router
	return null


func _get_replay_controls_label() -> Label:
	if not is_instance_valid(replay_controls_container):
		return null

	var node_value: Node = replay_controls_container.get_node_or_null("Label")
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


func _get_test_panel_controller() -> TestPanel:
	if test_panel is TestPanel:
		var panel: TestPanel = test_panel
		return panel

	var node_value: Node = get_node_or_null("%TestPanel")
	if node_value is TestPanel:
		var panel: TestPanel = node_value
		return panel
	return null


func _get_test_panel_canvas_item() -> CanvasItem:
	if test_panel is CanvasItem:
		var panel_canvas_item: CanvasItem = test_panel
		return panel_canvas_item
	return null


func _set_test_panel_visible(is_visible: bool) -> void:
	var panel_canvas_item: CanvasItem = _get_test_panel_canvas_item()
	if is_instance_valid(panel_canvas_item):
		panel_canvas_item.visible = is_visible


func _is_test_panel_visible() -> bool:
	var panel_canvas_item: CanvasItem = _get_test_panel_canvas_item()
	return is_instance_valid(panel_canvas_item) and panel_canvas_item.visible


# --- 信号处理函数 ---

func _on_scene_will_change(_payload: Variant = null) -> void:
	_cleanup_listeners()


func _on_game_ready_data_received(data: GameReadyData) -> void:
	if not is_instance_valid(_command_history):
		_command_history = _get_command_history_utility()
		
	if not is_instance_valid(_action_queue):
		_action_queue = _get_action_queue_system()
	
	_loaded_bookmark_data = data.loaded_bookmark_data
	
	if _is_replay_mode() and is_instance_valid(_replay_system):
		_replay_system.activate_replay_mode(data.replay_data_resource)
	elif is_instance_valid(_replay_system):
		_replay_system.deactivate_replay_mode()
	
	_configure_ui_for_mode()
	
	var mode_config_value: Variant = _current_game_model.mode_config.get_value()
	if not mode_config_value is GameModeConfig:
		push_warning("[GamePlayController] 当前模式配置无效，无法初始化棋盘。")
		return

	var mode_config: GameModeConfig = mode_config_value
	_apply_mode_visual_theme(mode_config, false)

	_connect_signals()

	if is_instance_valid(_loaded_bookmark_data):
		game_board.restore_from_snapshot(_loaded_bookmark_data.board_snapshot)
		if is_instance_valid(_game_flow_system):
			_game_flow_system.enter_playing_state()
			_game_flow_system.sync_bookmark_baseline_state()
	else:
		if is_instance_valid(_game_flow_system):
			if is_instance_valid(_log):
				_log.debug(_LOG_TAG, "触发初始棋盘规则。")
			_game_flow_system.trigger_initial_rules()

	var is_replay: bool = _is_replay_mode()
	if not is_replay:
		_setup_test_tools_for_current_board()
	
	if not is_instance_valid(_loaded_bookmark_data) and is_instance_valid(_command_history):
		var init_cmd: MoveCommand = MoveCommand.new(Vector2i.ZERO)
		init_cmd.mark_as_baseline()
		var game_state_system: GameStateSystem = _get_game_state_system()
		if is_instance_valid(game_state_system):
			var snapshot_set: bool = init_cmd.set_snapshot(game_state_system.get_full_game_state())
			if snapshot_set:
				_command_history.record(init_cmd)
			elif is_instance_valid(_log):
				_log.error(_LOG_TAG, "初始状态不符合 GFUndoableCommand 快照契约，未写入命令历史。")


func _on_board_resized(new_size: int) -> void:
	if is_instance_valid(_test_utility):
		_test_utility.update_limits(new_size)


func _on_move_count_changed(_old_value: int, _new_value: int) -> void:
	_update_replay_ui()


func _on_visual_theme_changed(_theme: GameTheme) -> void:
	var mode_config_value: Variant = _current_game_model.mode_config.get_value() if is_instance_valid(_current_game_model) else null
	if not mode_config_value is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_config_value
	_apply_current_ui_theme()
	_apply_mode_visual_theme(mode_config, true)


func _on_toggle_pause_ui(_payload: Variant = null) -> void:
	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility):
		push_error("[GamePlayController] 缺少 GamePauseUtility，无法切换暂停菜单。")
		return

	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[GamePlayController] 缺少 GFUIRouterUtility，无法切换暂停菜单。")
		return

	if pause_utility.is_paused():
		if ui_router.get_current_route_id(GFUIUtility.Layer.POPUP) != _ROUTE_PAUSE_MENU:
			push_error("[GamePlayController] 当前弹层不是暂停菜单，拒绝恢复游戏。")
			return
		if not ui_router.back(GFUIUtility.Layer.POPUP):
			push_error("[GamePlayController] GF UI 路由未能关闭暂停菜单。")
			return
		if not pause_utility.resume():
			push_error("[GamePlayController] 暂停菜单已关闭，但无法恢复对局时间。")
	else:
		var pause_panel: Node = ui_router.push_route(_ROUTE_PAUSE_MENU)
		if not is_instance_valid(pause_panel):
			push_error("[GamePlayController] GF UI 路由未能打开暂停菜单。")
			return
		if not pause_utility.pause():
			var _rolled_back: bool = ui_router.back(GFUIUtility.Layer.POPUP)
			push_error("[GamePlayController] 无法暂停对局时间，已回滚暂停菜单。")


func _on_replay_progress_changed(_current_step: int, _total_steps: int) -> void:
	_update_replay_ui()


func _on_replay_status_changed(_is_active: bool) -> void:
	_configure_ui_for_mode()


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_setup_test_tools_for_current_board()
	_configure_ui_for_mode()


func _on_target_reached(_payload: Variant = null) -> void:
	if _is_replay_mode():
		return

	var celebration_vfx: GameCelebrationVfxUtility = _get_celebration_vfx_utility()
	if is_instance_valid(celebration_vfx):
		var _played: bool = celebration_vfx.play_target_reached_celebration()

	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[GamePlayController] 缺少 GFUIRouterUtility，无法打开目标达成菜单。")
		return
	var target_panel: Node = ui_router.push_route(_ROUTE_TARGET_REACHED_MENU)
	if not is_instance_valid(target_panel):
		push_error("[GamePlayController] GF UI 路由未能打开目标达成菜单。")
		return
	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility) or not pause_utility.pause():
		var _rolled_back: bool = ui_router.back(GFUIUtility.Layer.POPUP)
		push_error("[GamePlayController] 无法暂停目标达成弹层后的对局时间，已回滚弹层。")


func _on_game_state_changed(new_state: StringName) -> void:
	if _is_replay_mode():
		return

	if new_state == EventNames.STATE_GAME_OVER:
		var ui_router: GFUIRouterUtility = _get_ui_router_utility()
		if not is_instance_valid(ui_router):
			push_error("[GamePlayController] 缺少 GFUIRouterUtility，无法打开游戏结束菜单。")
			return
		var game_over_panel: Node = ui_router.push_route(_ROUTE_GAME_OVER_MENU)
		if not is_instance_valid(game_over_panel):
			push_error("[GamePlayController] GF UI 路由未能打开游戏结束菜单。")
