# scripts/utilities/test_tool_utility.gd

## TestToolUtility: 负责管理编辑器环境下的测试面板与调试逻辑。
##
## 封装了测试面板的初始化、信号连接以及 Tile 强制生成代理。
class_name TestToolUtility
extends GFUtility


# --- 私有变量 ---

var _test_panel: Control
var _game_board: GameBoard
var _is_listening: bool = false


# --- Godot 生命周期方法 ---

func dispose() -> void:
	if _is_listening:
		unregister_event(TestSpawnPayload, _on_test_panel_spawn_requested_event)
		unregister_simple_event(EventNames.TEST_VALUES_REQUESTED, _on_test_panel_values_requested_event)
		unregister_simple_event(EventNames.TEST_RESET_RESIZE_REQUESTED, _on_reset_and_resize_requested_event)
		unregister_simple_event(EventNames.TEST_LIVE_EXPAND_REQUESTED, _on_live_expand_requested_event)
		_is_listening = false

	clear_context()


# --- 公共方法 ---

## 设置测试工具。
## @param panel: 测试面板节点引用。
## @param board: 游戏棋盘节点引用。
func setup_test_tools(panel: Control, board: GameBoard) -> void:
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
func update_limits(new_size: int) -> void:
	if is_instance_valid(_test_panel):
		_test_panel.update_coordinate_limits(new_size)


# --- 私有/辅助方法 ---

func _register_listeners() -> void:
	if _is_listening:
		return

	register_event(TestSpawnPayload, _on_test_panel_spawn_requested_event)
	register_simple_event(EventNames.TEST_VALUES_REQUESTED, _on_test_panel_values_requested_event)
	register_simple_event(EventNames.TEST_RESET_RESIZE_REQUESTED, _on_reset_and_resize_requested_event)
	register_simple_event(EventNames.TEST_LIVE_EXPAND_REQUESTED, _on_live_expand_requested_event)
	_is_listening = true


# --- 信号处理 ---

func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	
	var grid_model := get_model(GridModel) as GridModel
	
	if not grid_model:
		return
		
	var interaction_rule = grid_model.interaction_rule
	if interaction_rule:
		var tile_type_enum: Tile.TileType = interaction_rule.get_tile_type_from_id(type_id)
		
		# 清理旧数据
		var old_data = grid_model.grid[grid_pos.x][grid_pos.y]
		if old_data != null:
			# 发送移除动画指令
			var _remove_instruction: Array = [ {
				&"type": &"REMOVE", # 需要确保 GameBoard 支持处理这个伪指令或刷新
				&"tile_data": old_data,
				&"to_grid_pos": grid_pos
			}]
			# 考虑到直接调用删除比较麻烦，这里我们让 GameBoard 收到 BOARD_REFRESH_REQUESTED 时全量刷新即可。
			
		# 创建新数据并放置
		var tile_data := GameTileData.new(value, tile_type_enum)
		grid_model.place_tile(tile_data, grid_pos)
		
		# 通知视图层全量刷新 (比单点刷新更安全，且测试工具不需要关心视图层怎么画)
		send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, grid_model.get_snapshot())


func _on_test_panel_values_requested(type_id: int) -> void:
	var grid_model := get_model(GridModel) as GridModel
	var interaction_rule = grid_model.interaction_rule if grid_model else null
	
	if interaction_rule:
		var values: Array[int] = interaction_rule.get_spawnable_values(type_id)
		if is_instance_valid(_test_panel):
			_test_panel.update_value_options(values)


# --- 事件处理代理 ---

func _on_test_panel_spawn_requested_event(payload: TestSpawnPayload) -> void:
	if is_instance_valid(payload):
		_on_test_panel_spawn_requested(payload.grid_pos, payload.value, payload.type_id)


func _on_test_panel_values_requested_event(type_id: int) -> void:
	_on_test_panel_values_requested(type_id)


func _on_reset_and_resize_requested_event(new_size: int) -> void:
	_on_reset_and_resize_requested(new_size)


func _on_live_expand_requested_event(new_size: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)
	
	var grid_model := get_model(GridModel) as GridModel
	
	if grid_model and new_size > grid_model.grid_size:
		send_simple_event(EventNames.BOARD_LIVE_EXPAND_REQUESTED, new_size)


func _on_reset_and_resize_requested(new_size: int) -> void:
	send_simple_event(EventNames.GAME_STATE_TAINTED)

	var grid_model := get_model(GridModel) as GridModel
	var current_game_model := get_model(CurrentGameModel) as CurrentGameModel
	var status_model := get_model(GameStatusModel) as GameStatusModel
	var command_history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	var game_board: GameBoard = _game_board

	if not grid_model or not current_game_model or not is_instance_valid(game_board):
		return

	var mode_config := current_game_model.mode_config.get_value() as GameModeConfig
	if not is_instance_valid(mode_config):
		return

	current_game_model.current_grid_size.set_value(new_size)
	game_board.setup(new_size, grid_model.interaction_rule, grid_model.movement_rule, null, mode_config.color_schemes, mode_config.board_theme)

	if is_instance_valid(status_model):
		status_model.score.set_value(0)
		status_model.move_count.set_value(0)
		status_model.monsters_killed.set_value(0)
		status_model.highest_tile.set_value(0)
		status_model.status_message.set_value("")
		status_model.extra_stats.set_value({})

	if command_history:
		command_history.clear()

	send_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION)

	if command_history:
		var init_cmd := MoveCommand.new(Vector2i.ZERO)
		init_cmd.mark_as_baseline()
		var game_state_system := get_system(GameStateSystem) as GameStateSystem
		if is_instance_valid(game_state_system):
			init_cmd.set_snapshot(game_state_system.get_full_game_state(new_size))
		command_history.record(init_cmd)

	send_simple_event(EventNames.BOARD_RESIZED, new_size)
	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
