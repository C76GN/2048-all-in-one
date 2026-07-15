## TestToolUtility: 负责管理编辑器环境下的测试面板与调试逻辑。
##
## 封装了测试面板的初始化、信号连接以及 Tile 强制生成代理。
class_name TestToolUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")


# --- 私有变量 ---

var _test_panel: TestPanel
var _game_board: GameBoardController
var _is_listening: bool = false


## 释放测试工具持有的场景引用与事件监听。
func dispose() -> void:
	_is_listening = false

	clear_context()


# --- 公共方法 ---

## 设置测试工具。
## @param panel: 测试面板节点引用。
## @param board: 游戏棋盘节点引用。
func setup_test_tools(panel: TestPanel, board: GameBoardController) -> void:
	_test_panel = panel
	_game_board = board
	
	if not is_instance_valid(_test_panel) or not is_instance_valid(_game_board):
		clear_context()
		return

	_register_listeners()


## 清理当前场景相关的测试面板与棋盘引用。
func clear_context() -> void:
	_test_panel = null
	_game_board = null


## 初始化面板数据。
## @param interaction_rule: 当前的交互规则，用于获取可生成类型。
## @param grid_size: 当前棋盘尺寸。
func initialize_panel(interaction_rule: InteractionRule, grid_size: int) -> void:
	if not is_instance_valid(_test_panel) or not is_instance_valid(interaction_rule):
		return
		
	var spawnable_types: Dictionary = interaction_rule.get_spawnable_types()
	_test_panel.setup_panel(spawnable_types)
	_test_panel.update_coordinate_limits(grid_size)


## 更新坐标限制。
## @param new_size: 新的棋盘边长。
func update_limits(new_size: int) -> void:
	if is_instance_valid(_test_panel):
		_test_panel.update_coordinate_limits(new_size)


# --- 私有/辅助方法 ---

func _register_listeners() -> void:
	if _is_listening:
		return

	register_event(TestSpawnPayload, GFEventListener.from_method(self, &"_on_test_panel_spawn_requested_event", 1))
	register_simple_event(EventNames.TEST_VALUES_REQUESTED, GFEventListener.from_method(self, &"_on_test_panel_values_requested_event", 1))
	register_simple_event(EventNames.TEST_RESET_RESIZE_REQUESTED, GFEventListener.from_method(self, &"_on_reset_and_resize_requested_event", 1))
	register_simple_event(EventNames.TEST_LIVE_EXPAND_REQUESTED, GFEventListener.from_method(self, &"_on_live_expand_requested_event", 1))
	_is_listening = true


func _sync_highest_tile_from_grid() -> void:
	var game_flow_system: GameFlowSystem = _get_game_flow_system()
	if is_instance_valid(game_flow_system):
		game_flow_system.sync_highest_tile_from_grid()
		return

	var grid_model: GridModel = _get_grid_model()
	var status_model: GameStatusModel = _get_status_model()
	if is_instance_valid(grid_model) and is_instance_valid(status_model):
		status_model.highest_tile.set_value(grid_model.get_max_player_value())


func _is_grid_pos_in_bounds(grid_model: GridModel, grid_pos: Vector2i) -> bool:
	return (
		is_instance_valid(grid_model)
		and grid_pos.x >= 0
		and grid_pos.x < grid_model.grid_size
		and grid_pos.y >= 0
		and grid_pos.y < grid_model.grid_size
	)


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


# --- 信号处理函数 ---

func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	
	var grid_model: GridModel = _get_grid_model()
	
	if not is_instance_valid(grid_model):
		return
	if not _is_grid_pos_in_bounds(grid_model, grid_pos):
		return
		
	var interaction_rule: InteractionRule = grid_model.interaction_rule
	if is_instance_valid(interaction_rule):
		var tile_type_enum: Tile.TileType = interaction_rule.get_tile_type_from_id(type_id)
		
		# 清理旧数据
		var column: Array = grid_model.grid[grid_pos.x]
		var old_data_value: Variant = column[grid_pos.y]
		var old_data: GameTileData = null
		if old_data_value is GameTileData:
			old_data = old_data_value
		if old_data != null:
			# 发送移除动画指令
			var _remove_instruction: Array = [ {
				&"type": &"REMOVE", # 需要确保 GameBoardController 支持处理这个伪指令或刷新
				&"tile_data": old_data,
				&"to_grid_pos": grid_pos
			}]
			# 考虑到直接调用删除比较麻烦，这里让 GameBoardController 收到 BOARD_REFRESH_REQUESTED 时全量刷新即可。
			
		# 创建新数据并放置
		var tile_data: GameTileData = GameTileData.new(value, tile_type_enum)
		grid_model.place_tile(tile_data, grid_pos)
		
		# 通知视图层全量刷新 (比单点刷新更安全，且测试工具不需要关心视图层怎么画)
		send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, grid_model.get_snapshot())
		_sync_highest_tile_from_grid()


func _on_test_panel_values_requested(type_id: int) -> void:
	var grid_model: GridModel = _get_grid_model()
	var interaction_rule: InteractionRule = grid_model.interaction_rule if is_instance_valid(grid_model) else null
	
	if is_instance_valid(interaction_rule):
		var values: Array[int] = interaction_rule.get_spawnable_values(type_id)
		if is_instance_valid(_test_panel):
			_test_panel.update_value_options(values)


# --- 信号处理函数 ---

func _on_test_panel_spawn_requested_event(payload: TestSpawnPayload) -> void:
	if is_instance_valid(payload):
		_on_test_panel_spawn_requested(payload.grid_pos, payload.value, payload.type_id)


func _on_test_panel_values_requested_event(type_id: int) -> void:
	_on_test_panel_values_requested(type_id)


func _on_reset_and_resize_requested_event(new_size: int) -> void:
	_on_reset_and_resize_requested(new_size)


func _on_live_expand_requested_event(new_size: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	
	var grid_model: GridModel = _get_grid_model()
	
	if is_instance_valid(grid_model) and new_size > grid_model.grid_size:
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

	if not is_instance_valid(grid_model) or not is_instance_valid(current_game_model) or not is_instance_valid(game_board):
		return

	var mode_config_value: Variant = current_game_model.mode_config.get_value()
	if not mode_config_value is GameModeConfig:
		return
	var mode_config: GameModeConfig = mode_config_value
	if not is_instance_valid(mode_config):
		return

	grid_model.initialize(new_size, grid_model.interaction_rule, grid_model.movement_rule)
	if is_instance_valid(rule_system):
		var spawn_rules: Array[SpawnRule] = []
		for rule_resource: SpawnRule in mode_config.spawn_rules:
			var duplicated_rule: Resource = rule_resource.duplicate()
			if duplicated_rule is SpawnRule:
				var spawn_rule: SpawnRule = duplicated_rule
				spawn_rules.append(spawn_rule)
		rule_system.register_rules(spawn_rules)

	current_game_model.current_grid_size.set_value(new_size)
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if not is_instance_valid(theme_utility):
		push_error("[TestToolUtility] 缺少 GameThemeUtility，无法重建测试棋盘视觉主题。")
		return

	var resolved_color_schemes: Dictionary = theme_utility.resolve_color_schemes(mode_config.color_schemes)
	var resolved_board_theme: BoardTheme = theme_utility.resolve_board_theme(mode_config.board_theme)
	game_board.setup(resolved_color_schemes, resolved_board_theme)

	if is_instance_valid(status_model):
		status_model.score.set_value(0)
		status_model.move_count.set_value(0)
		status_model.monsters_killed.set_value(0)
		status_model.highest_tile.set_value(0)
		status_model.status_message.set_value("")
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
				game_state_system.get_full_game_state(new_size)
			)
			if snapshot_set:
				command_history.record(init_cmd)
			else:
				push_error("[TestToolUtility] 重建后的状态不符合 GFUndoableCommand 快照契约。")

	send_simple_event(EventNames.BOARD_RESIZED, new_size)
	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
