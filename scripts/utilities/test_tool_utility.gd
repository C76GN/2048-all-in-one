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

	Gf.listen(TestSpawnPayload, _on_test_panel_spawn_requested_event)
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
	
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	
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
		Gf.send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, grid_model.get_snapshot())


func _on_test_panel_values_requested(type_id: int) -> void:
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var interaction_rule = grid_model.interaction_rule if grid_model else null
	
	if interaction_rule:
		var values: Array[int] = interaction_rule.get_spawnable_values(type_id)
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
	Gf.send_simple_event(EventNames.GAME_STATE_TAINTED)
	
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	
	if grid_model:
		grid_model.expand_grid(new_size)
		# 这里我们不再直接调用 _game_board.live_expand()
		# 而是发送一个事件让 GameBoard 自己去处理
		Gf.send_simple_event(&"test_live_expand_requested", new_size)


func _on_reset_and_resize_requested(new_size: int) -> void:
	Gf.send_simple_event(EventNames.RESET_AND_RESIZE_WITH_PARAMS, [new_size])
