# scripts/actions/board_undo_animation_action.gd

## BoardUndoAnimationAction: 封装棋盘撤回时的反向过渡动画。
##
## 根据前置滑动记录的反向映射表，将棋盘上的方块反向“退回”到原先的位置，
## 动画结束后调用全量重绘同步准确的视觉节点。
class_name BoardUndoAnimationAction
extends GFVisualAction


# --- 私有变量 ---

var _snapshot: Dictionary
var _reverse_target_map: Dictionary
var _game_board: Node


# --- Godot 生命周期方法 ---

func _init(snapshot: Dictionary, reverse_target_map: Dictionary, game_board: Node) -> void:
	_snapshot = snapshot
	_reverse_target_map = reverse_target_map
	_game_board = game_board


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board):
		return null
		
	# 1. 强制清理当前显示的所有 Tile
	if _game_board.has_method(&"clear_visual_tiles"):
		_game_board.clear_visual_tiles()
	
	# 2. 从快照提取方块数据
	var tiles_data: Array = _snapshot.get(&"tiles", [])
	if tiles_data.is_empty():
		return null
		
	var tween := _game_board.create_tween().set_parallel(true)
	var tween_duration: float = 0.15
	var at_least_one_move: bool = false
	
	# 3. 生成展示用的反向过渡 Tile
	for tile_info in tiles_data:
		var past_pos: Vector2i = tile_info[&"pos"]
		var value: int = tile_info[&"value"]
		var type: int = tile_info[&"type"]
		
		# 使用映射表查找它们在此次滑动后的“当前”源位置
		var key := "%d,%d" % [past_pos.x, past_pos.y]
		var start_grid_pos: Vector2i = _reverse_target_map.get(key, past_pos)
		
		var tile_node: Tile
		if is_instance_valid(_game_board.pool) and _game_board.get("TileScene") != null:
			tile_node = _game_board.pool.acquire(_game_board.TileScene, _game_board.board_container)
		else:
			continue
			
		tile_node.visible = true
		
		var colors = _game_board._get_tile_colors(value, type as Tile.TileType)
		var bg_color: Color = colors.bg
		var font_color: Color = colors.font
			
		tile_node.setup(value, bg_color, font_color)
		tile_node.position = _game_board._grid_to_pixel_center(start_grid_pos)
		
		# 添加反向平移动画
		if start_grid_pos != past_pos:
			at_least_one_move = true
			tween.tween_property(tile_node, "position", _game_board._grid_to_pixel_center(past_pos), tween_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 4. 动画结束后真正构建和同步 _visual_map
	if at_least_one_move:
		tween.finished.connect(func():
			if is_instance_valid(_game_board) and _game_board.has_method("restore_from_snapshot"):
				_game_board.restore_from_snapshot(_snapshot)
		)
		return tween.finished
	else:
		tween.kill()
		if is_instance_valid(_game_board) and _game_board.has_method("restore_from_snapshot"):
			_game_board.restore_from_snapshot(_snapshot)
	
	return null
