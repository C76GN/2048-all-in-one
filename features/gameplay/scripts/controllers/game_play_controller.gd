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
const _REPLAY_OOS_FORMAT_FALLBACK: String = "回放在第 %d 步失去同步"
const _REPLAY_JUMP_FORMAT_FALLBACK: String = "正在跳转: %d / %d"
const _REPLAY_MARKER_MERGE_FORMAT_FALLBACK: String = "第 %d 步 · 合并 ×%d · +%d"
const _REPLAY_MARKER_CHAIN_FORMAT_FALLBACK: String = "第 %d 步 · 连锁/变换"
const _REPLAY_MARKER_MILESTONE_FORMAT_FALLBACK: String = "第 %d 步 · 里程碑 %d"
const _REPLAY_MARKER_FAILURE_FORMAT_FALLBACK: String = "第 %d 步 · 对局失败"
const _REPLAY_MARKER_OOS_FORMAT_FALLBACK: String = "第 %d 步 · OOS"
const _REPLAY_CONTINUE_NOTE_FALLBACK: String = "从此继续会退出回放，并标记为不参与竞赛成绩。"
const _REPLAY_CONTINUE_OOS_NOTE_FALLBACK: String = "回放已 OOS，不能从当前状态继续。"
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
var _log: GFLogUtility
var _theme_utility: GameThemeUtility
var _celebration_vfx_utility: GameCelebrationVfxUtility
var _replay_markers: Array[ReplayMarker] = []
var _is_syncing_marker_picker: bool = false
var _pending_popup_route_ids: Dictionary = {}
var _game_initialization_requested: bool = false

## 标记是否已完成清理，避免 _exit_tree 重复执行。
var _is_cleaned_up: bool = false


# --- @onready 变量 (节点引用) ---

@onready var game_board: GameBoardController = %GameBoard
@onready var background_color_rect: ColorRect = %Background
@onready var _page_title: Label = %PageTitle
@onready var replay_controls_container: PanelContainer = %ReplayControlsContainer
@onready var replay_progress_label: Label = %ReplayProgressLabel
@onready var replay_prev_button: Button = %ReplayPrevButton
@onready var replay_next_button: Button = %ReplayNextButton
@onready var replay_marker_picker: OptionButton = %ReplayMarkerPicker
@onready var replay_prev_marker_button: Button = %ReplayPrevMarkerButton
@onready var replay_next_marker_button: Button = %ReplayNextMarkerButton
@onready var replay_continue_button: Button = %ReplayContinueButton
@onready var replay_exit_button: Button = %ReplayExitButton
@onready var replay_eligibility_label: Label = %ReplayEligibilityLabel
@onready var _responsive_layout_controller: GameplayResponsiveLayoutController = (
	%GameplayResponsiveLayoutController
)
@onready var _board_world_viewport_controller: BoardWorldViewportController = (
	%BoardWorldViewportController
)


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = _get_game_status_model()
	_current_game_model = _get_current_game_model()
	_game_flow_system = _get_game_flow_system()
	_replay_system = _get_replay_system()
	_level_utility = _get_level_utility()
	_pause_utility = _get_pause_utility()
	_signal_utility = _get_signal_utility()
	_log = _get_log_utility()
	_theme_utility = _get_theme_utility()
	_celebration_vfx_utility = _get_celebration_vfx_utility()
	_apply_current_ui_theme()
	_register_level_runtime_cleanup()
	_connect_replay_control_signals()
	
	if _page_title:
		_page_title.visible = false
		
	if is_instance_valid(_game_status_model):
		_connect_managed_signal(_game_status_model.move_count.value_changed, _on_move_count_changed)
	if is_instance_valid(_theme_utility):
		_connect_managed_signal(_theme_utility.visual_theme_changed, _on_visual_theme_changed)
		
	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready_data_received", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))
	_request_game_initialization_when_board_ready()
	_update_static_ui_text()


func _notification(what: int) -> void:
	super._notification(what)
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
	if is_instance_valid(replay_prev_button):
		replay_prev_button.text = tr("BTN_REPLAY_PREV")
	if is_instance_valid(replay_next_button):
		replay_next_button.text = tr("BTN_REPLAY_NEXT")
	if is_instance_valid(replay_prev_marker_button):
		replay_prev_marker_button.text = tr("BTN_REPLAY_PREV_MARKER")
	if is_instance_valid(replay_next_marker_button):
		replay_next_marker_button.text = tr("BTN_REPLAY_NEXT_MARKER")
	if is_instance_valid(replay_continue_button):
		replay_continue_button.text = tr("BTN_REPLAY_CONTINUE_FROM_HERE")
	if is_instance_valid(replay_exit_button):
		replay_exit_button.text = tr("BTN_REPLAY_EXIT")
	_refresh_replay_marker_picker()
	_update_replay_eligibility_note()


func _connect_replay_control_signals() -> void:
	var _prev_connection: int = replay_prev_button.pressed.connect(_on_replay_prev_pressed)
	var _next_connection: int = replay_next_button.pressed.connect(_on_replay_next_pressed)
	var _prev_marker_connection: int = replay_prev_marker_button.pressed.connect(
		_on_replay_prev_marker_pressed
	)
	var _next_marker_connection: int = replay_next_marker_button.pressed.connect(
		_on_replay_next_marker_pressed
	)
	var _marker_selected_connection: int = replay_marker_picker.item_selected.connect(
		_on_replay_marker_selected
	)
	var _continue_connection: int = replay_continue_button.pressed.connect(_on_replay_continue_pressed)
	var _exit_connection: int = replay_exit_button.pressed.connect(_on_replay_exit_pressed)


func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	
	_unregister_level_runtime_cleanup()

	_clear_action_queues()

	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_owner_events(self)

	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)

	_level_utility = null
	_pause_utility = null
	_celebration_vfx_utility = null
	
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


func _request_game_initialization_when_board_ready() -> void:
	if _game_initialization_requested:
		return
	if not is_instance_valid(_board_world_viewport_controller):
		push_error("[GamePlayController] 缺少 BoardWorldViewportController，无法初始化对局。")
		return
	if _board_world_viewport_controller.is_view_initialized():
		_request_game_initialization_once()
		return
	if not is_instance_valid(_signal_utility):
		push_error("[GamePlayController] 缺少 GFSignalUtility，无法等待棋盘世界稳定挂载。")
		return
	var _connection: GFSignalConnection = _signal_utility.connect_once(
		_board_world_viewport_controller.world_view_initialized,
		_request_game_initialization_once,
		self
	)


func _request_game_initialization_once() -> void:
	if _game_initialization_requested or _is_cleaned_up:
		return
	_game_initialization_requested = true
	send_simple_event(EventNames.REQUEST_GAME_INITIALIZATION)


func _is_replay_mode() -> bool:
	if not is_instance_valid(_current_game_model):
		return false
	return GFVariantData.to_bool(_current_game_model.is_replay_mode.get_value(), false)


## 集中管理所有信号连接。
func _connect_signals() -> void:
	if is_instance_valid(_replay_system):
		_connect_managed_signal(_replay_system.playback_progress_changed, _on_replay_progress_changed)
		_connect_managed_signal(_replay_system.playback_status_changed, _on_replay_status_changed)
		_connect_managed_signal(
			_replay_system.playback_desynchronized,
			_on_replay_desynchronized
		)
		_connect_managed_signal(
			_replay_system.playback_markers_changed,
			_on_replay_markers_changed
		)
		_connect_managed_signal(
			_replay_system.playback_jump_status_changed,
			_on_replay_jump_status_changed
		)

	register_simple_event(EventNames.GAME_STATE_CHANGED, GFEventListener.from_method(self, &"_on_game_state_changed", 1))
	register_simple_event(EventNames.TOGGLE_PAUSE_UI, GFEventListener.from_method(self, &"_on_toggle_pause_ui", 1))
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, GFEventListener.from_method(self, &"_on_replay_continued_as_game", 1))
	register_simple_event(EventNames.TARGET_REACHED, GFEventListener.from_method(self, &"_on_target_reached", 1))


## 根据当前是普通模式还是回放模式，配置UI元素的可见性。
func _configure_ui_for_mode() -> void:
	if not is_instance_valid(_current_game_model):
		return

	var is_replay: bool = _is_replay_mode()
	replay_controls_container.visible = is_replay
	if is_instance_valid(_responsive_layout_controller):
		_responsive_layout_controller.set_replay_mode_active(is_replay)

	if is_replay and is_instance_valid(_replay_system):
		_replay_markers = _replay_system.get_markers()
		_refresh_replay_marker_picker()
		call_deferred(&"_focus_replay_controls")
	_update_replay_ui()


## 聚合所有需要显示的数据，并更新到 Model。
func _update_replay_ui() -> void:
	if not is_instance_valid(_current_game_model):
		return

	if not is_instance_valid(_replay_system):
		return

	var current_step: int = _replay_system.get_current_step()
	var total_steps: int = _replay_system.get_total_steps()
	var is_desynchronized: bool = _replay_system.is_playback_desynchronized()
	var is_jumping: bool = _replay_system.is_jump_in_progress()
	if is_instance_valid(replay_progress_label):
		if is_desynchronized:
			var oos_report: Dictionary = _replay_system.get_oos_report()
			replay_progress_label.text = GameTextFormatUtility.format_template(
				tr("LABEL_REPLAY_OOS"),
				_REPLAY_OOS_FORMAT_FALLBACK,
				[GFVariantData.get_option_int(oos_report, &"step_index", current_step + 1)]
			)
		elif is_jumping:
			replay_progress_label.text = GameTextFormatUtility.format_template(
				tr("LABEL_REPLAY_JUMPING"),
				_REPLAY_JUMP_FORMAT_FALLBACK,
				[current_step, total_steps]
			)
		else:
			replay_progress_label.text = GameTextFormatUtility.format_template(
				tr("LABEL_REPLAY_PROGRESS"),
				_REPLAY_PROGRESS_FORMAT_FALLBACK,
				[current_step, total_steps]
			)
	if is_instance_valid(replay_prev_button):
		replay_prev_button.disabled = is_desynchronized or is_jumping or current_step <= 0
	if is_instance_valid(replay_next_button):
		replay_next_button.disabled = (
			is_desynchronized
			or is_jumping
			or current_step >= total_steps
		)
	if is_instance_valid(replay_prev_marker_button):
		replay_prev_marker_button.disabled = (
			is_desynchronized
			or is_jumping
			or _replay_system.find_previous_marker_index(current_step) < 0
		)
	if is_instance_valid(replay_next_marker_button):
		replay_next_marker_button.disabled = (
			is_desynchronized
			or is_jumping
			or _replay_system.find_next_marker_index(current_step) < 0
		)
	if is_instance_valid(replay_marker_picker):
		replay_marker_picker.disabled = (
			is_desynchronized
			or is_jumping
			or _replay_markers.is_empty()
		)
	if is_instance_valid(replay_continue_button):
		replay_continue_button.disabled = not _replay_system.can_continue_from_current_step()
	_sync_marker_picker_to_step(current_step)
	_update_replay_eligibility_note()


func _refresh_replay_marker_picker() -> void:
	if not is_instance_valid(replay_marker_picker):
		return
	_is_syncing_marker_picker = true
	replay_marker_picker.clear()
	for marker: ReplayMarker in _replay_markers:
		if not is_instance_valid(marker):
			continue
		replay_marker_picker.add_item(_format_replay_marker(marker))
		replay_marker_picker.set_item_metadata(
			replay_marker_picker.item_count - 1,
			marker.marker_id
		)
	if replay_marker_picker.item_count == 0:
		replay_marker_picker.add_item(tr("REPLAY_NO_MARKERS"))
		replay_marker_picker.set_item_disabled(0, true)
	replay_marker_picker.select(-1)
	_is_syncing_marker_picker = false


func _format_replay_marker(marker: ReplayMarker) -> String:
	match marker.kind:
		ReplayMarker.Kind.MERGE:
			return GameTextFormatUtility.format_template(
				tr("REPLAY_MARKER_MERGE_FORMAT"),
				_REPLAY_MARKER_MERGE_FORMAT_FALLBACK,
				[marker.step_index, marker.merge_count, marker.score_delta]
			)
		ReplayMarker.Kind.CHAIN_OR_TRANSFORM:
			return GameTextFormatUtility.format_template(
				tr("REPLAY_MARKER_CHAIN_FORMAT"),
				_REPLAY_MARKER_CHAIN_FORMAT_FALLBACK,
				[marker.step_index]
			)
		ReplayMarker.Kind.MILESTONE:
			return GameTextFormatUtility.format_template(
				tr("REPLAY_MARKER_MILESTONE_FORMAT"),
				_REPLAY_MARKER_MILESTONE_FORMAT_FALLBACK,
				[marker.step_index, marker.milestone_value]
			)
		ReplayMarker.Kind.FAILURE:
			return GameTextFormatUtility.format_template(
				tr("REPLAY_MARKER_FAILURE_FORMAT"),
				_REPLAY_MARKER_FAILURE_FORMAT_FALLBACK,
				[marker.step_index]
			)
		ReplayMarker.Kind.OOS:
			return GameTextFormatUtility.format_template(
				tr("REPLAY_MARKER_OOS_FORMAT"),
				_REPLAY_MARKER_OOS_FORMAT_FALLBACK,
				[marker.step_index]
			)
		_:
			return str(marker.step_index)


func _sync_marker_picker_to_step(current_step: int) -> void:
	if (
		not is_instance_valid(replay_marker_picker)
		or _is_syncing_marker_picker
		or replay_marker_picker.item_count == 0
	):
		return
	var selected_index: int = replay_marker_picker.selected
	if selected_index >= 0 and selected_index < _replay_markers.size():
		var selected_marker: ReplayMarker = _replay_markers[selected_index]
		if is_instance_valid(selected_marker) and selected_marker.step_index == current_step:
			return
	for index: int in range(_replay_markers.size()):
		var marker: ReplayMarker = _replay_markers[index]
		if is_instance_valid(marker) and marker.step_index == current_step:
			_is_syncing_marker_picker = true
			replay_marker_picker.select(index)
			_is_syncing_marker_picker = false
			return
	_is_syncing_marker_picker = true
	replay_marker_picker.select(-1)
	_is_syncing_marker_picker = false


func _update_replay_eligibility_note() -> void:
	if not is_instance_valid(replay_eligibility_label):
		return
	var is_oos: bool = (
		is_instance_valid(_replay_system)
		and _replay_system.is_playback_desynchronized()
	)
	var note: String = (
		_resolve_replay_text(
			"REPLAY_CONTINUE_OOS_NOTE",
			_REPLAY_CONTINUE_OOS_NOTE_FALLBACK
		)
		if is_oos
		else _resolve_replay_text(
			"REPLAY_CONTINUE_ELIGIBILITY_NOTE",
			_REPLAY_CONTINUE_NOTE_FALLBACK
		)
	)
	replay_eligibility_label.text = note
	if is_instance_valid(replay_continue_button):
		replay_continue_button.tooltip_text = note


func _focus_replay_controls() -> void:
	if not replay_controls_container.visible:
		return
	var viewport: Viewport = get_viewport()
	if is_instance_valid(viewport) and is_instance_valid(viewport.gui_get_focus_owner()):
		return
	if is_instance_valid(replay_next_button) and not replay_next_button.disabled:
		replay_next_button.grab_focus()
	elif is_instance_valid(replay_marker_picker) and not replay_marker_picker.disabled:
		replay_marker_picker.grab_focus()


func _resolve_replay_text(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key or translated.is_empty() else translated


func _publish_gameplay_board_ready() -> void:
	if _is_replay_mode() or not is_instance_valid(game_board):
		return
	send_event(GameplayBoardReadyData.new(game_board))


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
	var resolved_tile_visual_theme: TileVisualTheme = _theme_utility.resolve_tile_visual_theme()
	if not is_instance_valid(resolved_tile_visual_theme):
		push_error("[GamePlayController] 当前主题缺少 TileVisualTheme，无法建立方块身份视觉。")
		return

	_apply_game_background_theme(resolved_board_theme)
	game_board.setup(
		resolved_color_schemes,
		resolved_board_theme,
		resolved_tile_visual_theme,
		background_color_rect
	)

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


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
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


func _get_game_ui_router_utility() -> GameUiRouterUtility:
	var utility_value: Object = get_utility(GameUiRouterUtility)
	if utility_value is GameUiRouterUtility:
		var ui_router: GameUiRouterUtility = utility_value
		return ui_router
	var aliased_utility: GFUIRouterUtility = _get_ui_router_utility()
	if aliased_utility is GameUiRouterUtility:
		var game_ui_router: GameUiRouterUtility = aliased_utility
		return game_ui_router
	return null


func _open_gameplay_popup_async(route_id: StringName) -> GFUIRouteResult:
	if _pending_popup_route_ids.has(route_id):
		return null
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		return null
	_pending_popup_route_ids[route_id] = true
	var result: GFUIRouteResult = await ui_router.push_owned_route_async(self, route_id)
	var _request_cleared: bool = _pending_popup_route_ids.erase(route_id)
	return result


func _get_replay_controls_label() -> Label:
	if not is_instance_valid(replay_controls_container):
		return null

	var node_value: Node = replay_controls_container.get_node_or_null("Label")
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


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
		_publish_gameplay_board_ready()
	
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

	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
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
		var result: GFUIRouteResult = await _open_gameplay_popup_async(_ROUTE_PAUSE_MENU)
		if result == null:
			return
		if not result.is_successful():
			push_error(
				"[GamePlayController] GF UI 路由未能打开暂停菜单：status=%s, reason=%s。" % [
					result.get_status(),
					result.get_reason(),
				]
			)
			return
		if not pause_utility.pause():
			var _rolled_back: bool = ui_router.back(GFUIUtility.Layer.POPUP)
			push_error("[GamePlayController] 无法暂停对局时间，已回滚暂停菜单。")


func _on_replay_progress_changed(_current_step: int, _total_steps: int) -> void:
	_update_replay_ui()


func _on_replay_status_changed(_is_active: bool) -> void:
	_configure_ui_for_mode()


func _on_replay_markers_changed(markers: Array) -> void:
	_replay_markers.clear()
	for marker_value: Variant in markers:
		if marker_value is ReplayMarker:
			var marker: ReplayMarker = marker_value
			_replay_markers.append(marker)
	_refresh_replay_marker_picker()
	_update_replay_ui()


func _on_replay_jump_status_changed(_is_jumping: bool, _target_step: int) -> void:
	_update_replay_ui()


func _on_replay_desynchronized(report: Dictionary) -> void:
	_update_replay_ui()
	if is_instance_valid(_log):
		_log.warn(_LOG_TAG, "回放检测到 OOS，已冻结控制。", report)


func _on_replay_prev_pressed() -> void:
	if is_instance_valid(_replay_system):
		_replay_system.step_backward()


func _on_replay_next_pressed() -> void:
	if is_instance_valid(_replay_system):
		_replay_system.step_forward()


func _on_replay_prev_marker_pressed() -> void:
	if is_instance_valid(_replay_system):
		var _ignored_jump_started: bool = _replay_system.jump_to_previous_marker()


func _on_replay_next_marker_pressed() -> void:
	if is_instance_valid(_replay_system):
		var _ignored_jump_started: bool = _replay_system.jump_to_next_marker()


func _on_replay_marker_selected(marker_index: int) -> void:
	if _is_syncing_marker_picker or not is_instance_valid(_replay_system):
		return
	if marker_index < 0 or marker_index >= _replay_markers.size():
		return
	if not _replay_system.jump_to_marker(marker_index):
		_sync_marker_picker_to_step(_replay_system.get_current_step())


func _on_replay_continue_pressed() -> void:
	if is_instance_valid(_replay_system):
		_replay_system.continue_from_current_step()


func _on_replay_exit_pressed() -> void:
	send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_publish_gameplay_board_ready()
	_configure_ui_for_mode()


func _on_target_reached(_payload: Variant = null) -> void:
	if _is_replay_mode():
		return

	var celebration_vfx: GameCelebrationVfxUtility = _get_celebration_vfx_utility()
	if is_instance_valid(celebration_vfx):
		var _played: bool = celebration_vfx.play_target_reached_celebration()

	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[GamePlayController] 缺少 GFUIRouterUtility，无法打开目标达成菜单。")
		return
	var result: GFUIRouteResult = await _open_gameplay_popup_async(_ROUTE_TARGET_REACHED_MENU)
	if result == null:
		return
	if not result.is_successful():
		push_error("[GamePlayController] GF UI 路由未能打开目标达成菜单：status=%s, reason=%s。" % [
			result.get_status(),
			result.get_reason(),
		])
		return
	var pause_utility: GamePauseUtility = _get_pause_utility()
	if not is_instance_valid(pause_utility) or not pause_utility.pause():
		var _rolled_back: bool = ui_router.back(GFUIUtility.Layer.POPUP)
		push_error("[GamePlayController] 无法暂停目标达成弹层后的对局时间，已回滚弹层。")
		return
	if is_instance_valid(_game_flow_system):
		var _context_changed: bool = (
			_game_flow_system.set_target_reached_modal_active(true)
		)


func _on_game_state_changed(new_state: StringName) -> void:
	if _is_replay_mode():
		return

	if new_state == EventNames.STATE_GAME_OVER:
		var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
		if not is_instance_valid(ui_router):
			push_error("[GamePlayController] 缺少 GFUIRouterUtility，无法打开游戏结束菜单。")
			return
		var result: GFUIRouteResult = await _open_gameplay_popup_async(_ROUTE_GAME_OVER_MENU)
		if result == null:
			return
		if not result.is_successful():
			push_error(
				"[GamePlayController] GF UI 路由未能打开游戏结束菜单：status=%s, reason=%s。" % [
					result.get_status(),
					result.get_reason(),
				]
			)
