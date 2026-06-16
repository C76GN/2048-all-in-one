## GridModel: 负责游戏棋盘的逻辑状态管理。
##
## 维护方块的二维网格数据，提供快照、恢复、初始化以及基础的网格查询能力。
class_name GridModel
extends GFModel


# --- 公共变量 ---

## 棋盘尺寸
var grid_size: int = 4

## 存储所有方块的二维数组 (纯数据)
var grid: Array = []

## 交互规则的纯粹引用
var interaction_rule: InteractionRule

## 移动规则的纯粹引用
var movement_rule: MovementRule


# --- 公共方法 ---

## 初始化或重置数据
## @param size: 棋盘边长。
## @param p_interaction_rule: 当前模式使用的交互规则。
## @param p_movement_rule: 当前模式使用的移动规则。
func initialize(size: int, p_interaction_rule: InteractionRule, p_movement_rule: MovementRule) -> void:
	grid_size = size
	interaction_rule = p_interaction_rule
	movement_rule = p_movement_rule
	grid = _create_empty_grid(grid_size)


## 获取快照，用于撤回或保存
func get_snapshot() -> Dictionary:
	var tiles_list: Array[Dictionary] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var a_tile: GameTileData = row[y]
			if a_tile != null:
				tiles_list.append({
					&"pos": Vector2i(x, y),
					&"value": a_tile.value,
					&"type": a_tile.type,
				})
	return {
		&"grid_size": grid_size,
		&"tiles": tiles_list,
	}


## 从快照还原数据
## @param snapshot: get_snapshot() 产生的棋盘快照。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has(&"tiles") and not snapshot.has("tiles"):
		return

	grid_size = snapshot.get(&"grid_size", snapshot.get("grid_size", grid_size))
	if grid_size <= 0:
		return

	grid = _create_empty_grid(grid_size)
		
	var tiles_data: Array = snapshot.get(&"tiles", snapshot.get("tiles", []))
	for raw_tile_info: Variant in tiles_data:
		if not raw_tile_info is Dictionary:
			continue
		var tile_info: Dictionary = raw_tile_info
		var pos: Vector2i = tile_info.get(&"pos", tile_info.get("pos", Vector2i.ZERO))
		if not _is_cell_in_bounds(pos):
			continue

		var value: int = tile_info.get(&"value", tile_info.get("value", 0))
		var type: Tile.TileType = tile_info.get(&"type", tile_info.get("type", Tile.TileType.PLAYER))
		grid[pos.x][pos.y] = GameTileData.new(value, type)


## 将指定的方块数据结构放入网格
## @param tile: 要放置的方块数据。
## @param grid_pos: 目标网格坐标。
func place_tile(tile: GameTileData, grid_pos: Vector2i) -> void:
	if _is_cell_in_bounds(grid_pos):
		grid[grid_pos.x][grid_pos.y] = tile


## 扩展网格尺寸
## @param new_size: 扩展后的棋盘边长。
func expand_grid(new_size: int) -> void:
	if new_size <= grid_size:
		return
	
	var new_grid: Array = _create_empty_grid(new_size)
		
	for x: int in range(grid_size):
		var source_row: Array = grid[x]
		var target_row: Array = new_grid[x]
		for y: int in range(grid_size):
			target_row[y] = source_row[y]
			
	grid_size = new_size
	grid = new_grid


## 获取所有空单元格的位置
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			if row[y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells


## 获取玩家拥有的最高方块值
func get_max_player_value() -> int:
	var max_val: int = 0
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var tile: GameTileData = row[y]
			if tile != null and tile.type == Tile.TileType.PLAYER:
				if tile.value > max_val:
					max_val = tile.value
	return max_val


## 获取所有玩家方块值的去重列表供外部统计使用
func get_all_player_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var tile: GameTileData = row[y]
			if tile != null and tile.type == Tile.TileType.PLAYER:
				values.append(tile.value)
	values.sort()
	return values


## GFModel 序列化协议：将模型状态导出为字典。
func to_dict() -> Dictionary:
	return get_snapshot()


## GFModel 序列化协议：从字典恢复模型状态。
## @param data: 序列化后的棋盘状态。
func from_dict(data: Dictionary) -> void:
	restore_from_snapshot(data)


# --- 私有/辅助方法 ---

func _create_empty_grid(size: int) -> Array:
	var result: Array = []
	var _resize_result: Variant = result.resize(size)
	for x: int in range(size):
		var row: Array = []
		var _row_resize_result: Variant = row.resize(size)
		row.fill(null)
		result[x] = row
	return result


func _is_cell_in_bounds(grid_pos: Vector2i) -> bool:
	return (
		grid_pos.x >= 0
		and grid_pos.x < grid_size
		and grid_pos.y >= 0
		and grid_pos.y < grid_size
	)
