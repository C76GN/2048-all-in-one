## TestToolUtility: 管理开发环境下的独立对局实验台与调试操作。
##
## 该 Utility 订阅玩法发布的棋盘就绪事件，按需创建独立 Window，并通过 GF 输入、
## 控制台、信号和主题能力管理工作区。玩家场景不持有任何诊断 UI 节点。
class_name TestToolUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")
const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_ui_motion_utility.gd")
const _WORKSPACE_SCENE: PackedScene = preload("res://features/diagnostics/scenes/windows/gameplay_diagnostics_window.tscn")
const _INPUT_CONTEXT: GFInputContext = preload("res://features/diagnostics/resources/input/diagnostics_input_context.tres")
const _TOGGLE_WORKSPACE_ACTION: StringName = &"toggle_diagnostics_workspace"
const _CONSOLE_COMMAND: String = "toggle_test_tools"


# --- 公共变量 ---

## 收到普通对局棋盘上下文后是否自动打开独立工作区。
var open_on_gameplay_context: bool = false


# --- 私有变量 ---

var _test_window: GameplayDiagnosticsWindow
var _test_panel: TestPanel
var _game_board: GameBoardController
var _signal_utility: GFSignalUtility
var _input_mapping: GFInputMappingUtility
var _console_utility: GFConsoleUtility
var _theme_utility: GameThemeUtility
var _ui_motion_utility: GameUiMotionUtility
var _console_command_subscription: GFLifetimeSubscription
var _is_listening: bool = false


# --- GF 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [CurrentGameModel, GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [GameFlowSystem, GameStateSystem, RuleSystem]


func get_required_utilities() -> Array[Script]:
	return [
		_GAME_THEME_UTILITY_SCRIPT,
		_GAME_UI_MOTION_UTILITY_SCRIPT,
		GFCommandHistoryUtility,
		GFConsoleUtility,
		GFInputMappingUtility,
		GFSignalUtility,
		TileCompositionUtility,
	]


func init() -> void:
	tick_enabled = true
	ignore_pause = true
	ignore_time_scale = true


func ready() -> void:
	_signal_utility = _get_signal_utility()
	_input_mapping = _get_input_mapping_utility()
	_console_utility = _get_console_utility()
	_theme_utility = _get_theme_utility()
	_ui_motion_utility = _get_ui_motion_utility()

	if is_instance_valid(_input_mapping):
		_input_mapping.enable_context(_INPUT_CONTEXT, 1000)
	if is_instance_valid(_console_utility):
		_console_command_subscription = _console_utility.register_command(
			self,
			_CONSOLE_COMMAND,
			Callable(self, &"_cmd_toggle_workspace"),
			"Toggle the detached gameplay diagnostics workspace.",
			{"tier": GFConsoleUtility.CommandTier.INPUT}
		)
	if is_instance_valid(_signal_utility) and is_instance_valid(_theme_utility):
		var _theme_connection: GFSignalConnection = _signal_utility.connect_signal(
			_theme_utility.visual_theme_changed,
			_on_visual_theme_changed,
			self
		)
	_register_listeners()


## 轮询 GF 诊断输入上下文。
## @param _delta: 当前帧间隔；输入状态由 GFInputMappingUtility 维护。
func tick(_delta: float) -> void:
	if not is_instance_valid(_game_board) or not is_instance_valid(_input_mapping):
		return
	if _input_mapping.consume_action(_TOGGLE_WORKSPACE_ACTION):
		toggle_workspace()


## 释放测试工具持有的场景引用与 GF 注册。
func dispose() -> void:
	_is_listening = false
	if _console_command_subscription != null:
		var _command_cancelled: bool = _console_command_subscription.cancel()
		_console_command_subscription = null
	if is_instance_valid(_input_mapping):
		_input_mapping.disable_context(_INPUT_CONTEXT)
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	clear_context()
	_signal_utility = null
	_input_mapping = null
	_console_utility = null
	_theme_utility = null
	_ui_motion_utility = null


# --- 公共方法 ---

## 绑定当前玩法棋盘并创建独立诊断工作区。
## @param board: 当前对局的棋盘表现控制器。
func attach_gameplay_context(board: GameBoardController) -> void:
	if not is_instance_valid(board):
		clear_context()
		return
	if board == _game_board and is_instance_valid(_test_window):
		_sync_panel_from_grid()
		return

	clear_context()
	_game_board = board
	if not _can_open_detached_workspace():
		return
	if not _ensure_workspace():
		return
	_sync_panel_from_grid()
	if open_on_gameplay_context:
		set_workspace_visible(true)


## 清理当前场景相关的窗口、面板与棋盘引用。
func clear_context() -> void:
	_test_panel = null
	_game_board = null
	if is_instance_valid(_test_window):
		_test_window.hide_workspace()
		_test_window.queue_free()
	_test_window = null


## 显示或隐藏独立诊断工作区。
## @param is_visible: 为 true 时显示窗口，否则隐藏。
func set_workspace_visible(is_visible: bool) -> void:
	if is_visible:
		if not is_instance_valid(_test_window) and not _ensure_workspace():
			return
		_sync_panel_from_grid()
		_test_window.popup_workspace()
	elif is_instance_valid(_test_window):
		_test_window.hide_workspace()


## 切换独立诊断工作区可见性。
func toggle_workspace() -> void:
	set_workspace_visible(not is_workspace_visible())


## 查询独立诊断工作区是否可见。
func is_workspace_visible() -> bool:
	return is_instance_valid(_test_window) and _test_window.visible


# --- 私有/辅助方法 ---

func _register_listeners() -> void:
	if _is_listening:
		return

	register_event(GameplayBoardReadyData, GFEventListener.from_method(self, &"_on_gameplay_board_ready", 1))
	register_event(TestSpawnPayload, GFEventListener.from_method(self, &"_on_test_panel_spawn_requested_event", 1))
	register_simple_event(EventNames.BOARD_RESIZED, GFEventListener.from_method(self, &"_on_board_resized_event", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change_event", 1))
	register_simple_event(EventNames.TEST_VALUES_REQUESTED, GFEventListener.from_method(self, &"_on_test_panel_values_requested_event", 1))
	register_simple_event(EventNames.TEST_RESET_RESIZE_REQUESTED, GFEventListener.from_method(self, &"_on_reset_and_resize_requested_event", 1))
	register_simple_event(EventNames.TEST_LIVE_EXPAND_REQUESTED, GFEventListener.from_method(self, &"_on_live_expand_requested_event", 1))
	_is_listening = true


func _can_open_detached_workspace() -> bool:
	return (
		DisplayServer.get_name().to_lower() != "headless"
		and not OS.has_feature("web")
		and not OS.has_feature("mobile")
		and not OS.has_feature("android")
		and not OS.has_feature("ios")
	)


func _ensure_workspace() -> bool:
	if is_instance_valid(_test_window) and is_instance_valid(_test_panel):
		return true
	if not is_instance_valid(_game_board) or not _game_board.is_inside_tree():
		return false

	var instance: Node = _WORKSPACE_SCENE.instantiate()
	if not instance is GameplayDiagnosticsWindow:
		instance.free()
		push_error("[TestToolUtility] 独立诊断工作区场景根节点类型无效。")
		return false
	var diagnostics_window: GameplayDiagnosticsWindow = instance
	_test_window = diagnostics_window
	_game_board.get_tree().root.add_child(_test_window)
	_test_panel = _test_window.get_test_panel()
	if not is_instance_valid(_test_panel):
		_test_window.queue_free()
		_test_window = null
		push_error("[TestToolUtility] 独立诊断工作区缺少 TestPanel。")
		return false

	if is_instance_valid(_signal_utility):
		var _close_connection: GFSignalConnection = _signal_utility.connect_signal(
			_test_window.close_requested,
			_on_workspace_close_requested,
			self
		)
	_apply_workspace_theme()
	return true


func _sync_panel_from_grid() -> void:
	if not is_instance_valid(_test_panel):
		return
	var grid_model: GridModel = _get_grid_model()
	if not is_instance_valid(grid_model) or not is_instance_valid(grid_model.interaction_rule):
		return
	_test_panel.setup_panel(grid_model.interaction_rule.get_spawnable_options())
	_test_panel.update_coordinate_limits(grid_model.get_bounds_size())


func _apply_workspace_theme() -> void:
	if not is_instance_valid(_test_window):
		return
	if is_instance_valid(_theme_utility):
		var _theme_apply_count: int = _theme_utility.apply_current_theme_to_tree(_test_window)
	if is_instance_valid(_ui_motion_utility):
		var _bound_count: int = _ui_motion_utility.bind_interactive_controls(_test_window)


func _sync_highest_tile_from_grid() -> void:
	var game_flow_system: GameFlowSystem = _get_game_flow_system()
	if is_instance_valid(game_flow_system):
		game_flow_system.sync_highest_tile_from_grid()
		return

	var grid_model: GridModel = _get_grid_model()
	var status_model: GameStatusModel = _get_status_model()
	if is_instance_valid(grid_model) and is_instance_valid(status_model):
		status_model.highest_tile.set_value(grid_model.get_max_tile_value())


func _is_grid_pos_in_bounds(grid_model: GridModel, grid_pos: Vector2i) -> bool:
	return is_instance_valid(grid_model) and grid_model.is_active_cell(grid_pos)


func _get_game_flow_system() -> GameFlowSystem:
	var system_value: Object = get_system(GameFlowSystem)
	if system_value is GameFlowSystem:
		var game_flow_system: GameFlowSystem = system_value
		return game_flow_system
	return null


func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null


func _get_game_state_system() -> GameStateSystem:
	var system_value: Object = get_system(GameStateSystem)
	if system_value is GameStateSystem:
		var game_state_system: GameStateSystem = system_value
		return game_state_system
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_current_game_model() -> CurrentGameModel:
	var model_value: Object = get_model(CurrentGameModel)
	if model_value is CurrentGameModel:
		var current_game_model: CurrentGameModel = model_value
		return current_game_model
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
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


func _get_tile_composition_utility() -> TileCompositionUtility:
	var utility_value: Object = get_utility(TileCompositionUtility)
	if utility_value is TileCompositionUtility:
		var composition_utility: TileCompositionUtility = utility_value
		return composition_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_console_utility() -> GFConsoleUtility:
	var utility_value: Object = get_utility(GFConsoleUtility)
	if utility_value is GFConsoleUtility:
		var console_utility: GFConsoleUtility = utility_value
		return console_utility
	return null


func _cmd_toggle_workspace(_args: PackedStringArray) -> void:
	toggle_workspace()


# --- 信号处理函数 ---

func _on_gameplay_board_ready(payload: GameplayBoardReadyData) -> void:
	if is_instance_valid(payload):
		attach_gameplay_context(payload.board)


func _on_scene_will_change_event(_payload: Variant = null) -> void:
	clear_context()


func _on_board_resized_event(_new_size: int) -> void:
	_sync_panel_from_grid()


func _on_workspace_close_requested() -> void:
	set_workspace_visible(false)


func _on_visual_theme_changed(_theme: GameTheme) -> void:
	_apply_workspace_theme()


func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, option_id: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)

	var grid_model: GridModel = _get_grid_model()
	if not is_instance_valid(grid_model) or not _is_grid_pos_in_bounds(grid_model, grid_pos):
		return

	var interaction_rule: InteractionRule = grid_model.interaction_rule
	if not is_instance_valid(interaction_rule):
		return
	var _removed_old_tile: bool = grid_model.remove_tile(grid_pos)
	var composition_utility: TileCompositionUtility = _get_tile_composition_utility()
	if composition_utility == null:
		return
	var definition: TileDefinition = interaction_rule.get_spawn_definition(option_id)
	var tile_data: TileState = composition_utility.create_tile(definition, value)
	if tile_data == null:
		return
	if not grid_model.place_tile(tile_data, grid_pos):
		composition_utility.release_tile(tile_data)
		return

	send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, grid_model.get_snapshot())
	_sync_highest_tile_from_grid()


func _on_test_panel_values_requested(option_id: int) -> void:
	var grid_model: GridModel = _get_grid_model()
	var interaction_rule: InteractionRule = (
		grid_model.interaction_rule if is_instance_valid(grid_model) else null
	)
	if is_instance_valid(interaction_rule) and is_instance_valid(_test_panel):
		_test_panel.update_value_options(interaction_rule.get_spawnable_values(option_id))


func _on_test_panel_spawn_requested_event(payload: TestSpawnPayload) -> void:
	if is_instance_valid(payload):
		_on_test_panel_spawn_requested(payload.grid_pos, payload.value, payload.option_id)


func _on_test_panel_values_requested_event(option_id: int) -> void:
	_on_test_panel_values_requested(option_id)


func _on_reset_and_resize_requested_event(new_size: int) -> void:
	_on_reset_and_resize_requested(new_size)


func _on_live_expand_requested_event(new_size: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	var grid_model: GridModel = _get_grid_model()
	var current_size: Vector2i = (
		grid_model.get_bounds_size() if is_instance_valid(grid_model) else Vector2i.ZERO
	)
	if is_instance_valid(grid_model) and new_size > maxi(current_size.x, current_size.y):
		send_simple_event(EventNames.BOARD_LIVE_EXPAND_REQUESTED, new_size)


func _on_reset_and_resize_requested(new_size: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	if new_size <= 0:
		return

	var grid_model: GridModel = _get_grid_model()
	var current_game_model: CurrentGameModel = _get_current_game_model()
	var status_model: GameStatusModel = _get_status_model()
	var command_history: GFCommandHistoryUtility = _get_command_history_utility()
	var rule_system: RuleSystem = _get_rule_system()
	var game_board: GameBoardController = _game_board
	if (
		not is_instance_valid(grid_model)
		or not is_instance_valid(current_game_model)
		or not is_instance_valid(game_board)
	):
		return

	var mode_config_value: Variant = current_game_model.mode_config.get_value()
	if not mode_config_value is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_config_value
	if not is_instance_valid(mode_config):
		return

	var next_topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(new_size, new_size))
	if not grid_model.initialize(next_topology, grid_model.interaction_rule, grid_model.movement_rule):
		return
	if is_instance_valid(rule_system):
		var spawn_rules: Array[SpawnRule] = []
		for rule_resource: SpawnRule in mode_config.spawn_rules:
			var duplicated_rule: Resource = rule_resource.duplicate()
			if duplicated_rule is SpawnRule:
				var spawn_rule: SpawnRule = duplicated_rule
				spawn_rules.append(spawn_rule)
		rule_system.register_rules(spawn_rules)

	current_game_model.current_board_topology.set_value(next_topology.duplicate(true))
	if not is_instance_valid(_theme_utility):
		push_error("[TestToolUtility] 缺少 GameThemeUtility，无法重建测试棋盘视觉主题。")
		return

	var resolved_color_schemes: Dictionary = _theme_utility.resolve_color_schemes(
		mode_config.color_schemes
	)
	var resolved_board_theme: BoardTheme = _theme_utility.resolve_board_theme(
		mode_config.board_theme
	)
	game_board.setup(resolved_color_schemes, resolved_board_theme)

	if is_instance_valid(status_model):
		status_model.score.set_value(0)
		status_model.move_count.set_value(0)
		status_model.ratio_resolutions.set_value(0)
		status_model.highest_tile.set_value(0)
		status_model.extra_stats.set_value({})

	if is_instance_valid(command_history):
		command_history.clear()

	send_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION)
	_sync_highest_tile_from_grid()

	if is_instance_valid(command_history):
		var init_cmd: MoveCommand = MoveCommand.new(Vector2i.ZERO)
		init_cmd.mark_as_baseline()
		var game_state_system: GameStateSystem = _get_game_state_system()
		if is_instance_valid(game_state_system):
			var snapshot_set: bool = init_cmd.set_snapshot(
				game_state_system.get_full_game_state()
			)
			if snapshot_set:
				command_history.record(init_cmd)
			else:
				push_error("[TestToolUtility] 重建后的状态不符合 GFUndoableCommand 快照契约。")

	send_simple_event(EventNames.BOARD_RESIZED, new_size)
	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
