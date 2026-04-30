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
func initialize(size: int, p_interaction_rule: InteractionRule, p_movement_rule: MovementRule) -> void:
	grid_size = size
	interaction_rule = p_interaction_rule
	movement_rule = p_movement_rule
	grid.clear()
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)


## 获取快照，用于撤回或保存
func get_snapshot() -> Dictionary:
	var tiles_list: Array[Dictionary] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var a_tile: GameTileData = grid[x][y]
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
func restore_from_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has(&"tiles") and not snapshot.has("tiles"):
		return

	grid_size = snapshot.get(&"grid_size", snapshot.get("grid_size", grid_size))
	if grid_size <= 0:
		return

	grid.clear()
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)
		
	var tiles_data: Array = snapshot.get(&"tiles", snapshot.get("tiles", []))
	for tile_info in tiles_data:
		var pos: Vector2i = tile_info.get(&"pos", tile_info.get("pos", Vector2i.ZERO))
		if not _is_cell_in_bounds(pos):
			continue

		var value: int = tile_info.get(&"value", tile_info.get("value", 0))
		var type: Tile.TileType = tile_info.get(&"type", tile_info.get("type", Tile.TileType.PLAYER))
		grid[pos.x][pos.y] = GameTileData.new(value, type)


## 将指定的方块数据结构放入网格
func place_tile(tile: GameTileData, grid_pos: Vector2i) -> void:
	if _is_cell_in_bounds(grid_pos):
		grid[grid_pos.x][grid_pos.y] = tile


## 扩展网格尺寸
func expand_grid(new_size: int) -> void:
	if new_size <= grid_size:
		return
	
	var new_grid: Array = []
	new_grid.resize(new_size)
	for x in range(new_size):
		new_grid[x] = []
		new_grid[x].resize(new_size)
		new_grid[x].fill(null)
		
	for x in range(grid_size):
		for y in range(grid_size):
			new_grid[x][y] = grid[x][y]
			
	grid_size = new_size
	grid = new_grid


## 获取所有空单元格的位置
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells


## 获取玩家拥有的最高方块值
func get_max_player_value() -> int:
	var max_val := 0
	for x in range(grid_size):
		for y in range(grid_size):
			var tile: GameTileData = grid[x][y]
			if tile != null and tile.type == Tile.TileType.PLAYER:
				if tile.value > max_val:
					max_val = tile.value
	return max_val


## 获取所有玩家方块值的去重列表供外部统计使用
func get_all_player_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile: GameTileData = grid[x][y]
			if tile != null and tile.type == Tile.TileType.PLAYER:
				values.append(tile.value)
	values.sort()
	return values


## GFModel 序列化协议：将模型状态导出为字典。
func to_dict() -> Dictionary:
	return get_snapshot()


## GFModel 序列化协议：从字典恢复模型状态。
func from_dict(data: Dictionary) -> void:
	restore_from_snapshot(data)


# --- 私有/辅助方法 ---

func _is_cell_in_bounds(grid_pos: Vector2i) -> bool:
	return (
		grid_pos.x >= 0
		and grid_pos.x < grid_size
		and grid_pos.y >= 0
		and grid_pos.y < grid_size
	)
