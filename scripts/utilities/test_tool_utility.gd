# scripts/utilities/test_tool_utility.gd

## TestToolUtility: 负责管理编辑器环境下的测试面板与调试逻辑。
##
## 封装了测试面板的初始化、信号连接以及 Tile 强制生成代理。
class_name TestToolUtility
extends GFUtility


# --- 私有变量 ---

var _test_panel: Control
var _game_board: Control


# --- 公共方法 ---

## 设置测试工具。
## @param panel: 测试面板节点引用。
## @param board: 游戏棋盘节点引用。
func setup_test_tools(panel: Control, board: Control) -> void:
	_test_panel = panel
	_game_board = board
	
	if not _test_panel or not _game_board:
		return

	Gf.listen_simple(EventNames.TEST_SPAWN_REQUESTED, _on_test_panel_spawn_requested_event)
	Gf.listen_simple(EventNames.TEST_VALUES_REQUESTED, _on_test_panel_values_requested_event)
	Gf.listen_simple(EventNames.TEST_RESET_RESIZE_REQUESTED, _on_reset_and_resize_requested_event)
	Gf.listen_simple(EventNames.TEST_LIVE_EXPAND_REQUESTED, _on_live_expand_requested_event)


## 初始化面板数据。
## @param interaction_rule: 当前的交互规则，用于获取可生成类型。
## @param grid_size: 当前棋盘尺寸。
func initialize_panel(interaction_rule: InteractionRule, grid_size: int) -> void:
	if not _test_panel or not interaction_rule:
		return
		
	var spawnable_types: Dictionary = interaction_rule.get_spawnable_types()
	_test_panel.setup_panel(spawnable_types)
	_test_panel.update_coordinate_limits(grid_size)


## 更新坐标限制。
func update_limits(new_size: int) -> void:
	if _test_panel:
		_test_panel.update_coordinate_limits(new_size)


# --- 信号处理 ---

func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	Gf.send_simple_event(EventNames.GAME_STATE_TAINTED)
	var interaction_rule = _game_board.model.interaction_rule if _game_board and _game_board.model else null
	if interaction_rule:
		var tile_type_enum: Tile.TileType = interaction_rule.get_tile_type_from_id(type_id)
		
		if _game_board and _game_board.model:
			# Get old data and clean it up if it exists
			var old_data = _game_board.model.grid[grid_pos.x][grid_pos.y]
			if old_data != null:
				if _game_board._visual_map.has(old_data):
					var tile_node := _game_board._visual_map[old_data] as Tile
					var pool := Gf.get_architecture().get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
					if pool:
						pool.release(tile_node, _game_board.TileScene)
						tile_node.visible = false
					else:
						tile_node.queue_free()
					_game_board._visual_map.erase(old_data)
				_game_board.model.grid[grid_pos.x][grid_pos.y] = null
			
			var tile_data := GameTileData.new(value, tile_type_enum)
			_game_board.model.place_tile(tile_data, grid_pos)
			
			var instruction: Array = [ {
				&"type": &"SPAWN",
				&"tile_data": tile_data,
				&"to_grid_pos": grid_pos
			}]
			Gf.send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)


func _on_test_panel_values_requested(type_id: int) -> void:
	var interaction_rule = _game_board.model.interaction_rule if _game_board and _game_board.model else null
	if interaction_rule:
		var values: Array[int] = interaction_rule.get_spawnable_values(type_id)
		_test_panel.update_value_options(values)


# --- 事件处理代理 ---

func _on_test_panel_spawn_requested_event(payload: Array) -> void:
	_on_test_panel_spawn_requested(payload[0], payload[1], payload[2])


func _on_test_panel_values_requested_event(type_id: int) -> void:
	_on_test_panel_values_requested(type_id)


func _on_reset_and_resize_requested_event(new_size: int) -> void:
	_on_reset_and_resize_requested(new_size)


func _on_live_expand_requested_event(new_size: int) -> void:
	Gf.send_simple_event(EventNames.GAME_STATE_TAINTED)
	if _game_board and _game_board.model:
		_game_board.model.expand_grid(new_size)
		_game_board.live_expand(new_size)
		# live_expand internally sends BOARD_RESIZED now


func _on_reset_and_resize_requested(new_size: int) -> void:
	Gf.send_simple_event(EventNames.RESET_AND_RESIZE_WITH_PARAMS, [new_size])
