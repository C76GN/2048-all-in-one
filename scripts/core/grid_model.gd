# scripts/core/grid_model.gd

## GridModel: 负责管理棋盘数据和核心游戏逻辑的纯数据类。
##
## 它不包含任何 UI 或节点操作，仅维护 grid 数组和执行移动/合并算法。
## 通过信号通知 View 层进行更新。
class_name GridModel
extends RefCounted


# --- 信号 ---

## 当棋盘逻辑状态发生改变（如移动、合并）时发出，用于通知 View 更新动画。
## @param instructions: 动画指令数组。
signal board_changed(instructions: Array)

## 当有方块生成时发出。
## @param tile: 新生成的方块节点。
signal tile_spawned(tile: Node)

## 当分数发生变化时发出。
## @param amount: 增加的分数。
signal score_updated(amount: int)


# --- 公共变量 ---

## 棋盘尺寸。
var grid_size: int = 4

## 存储所有方块的二维数组。
var grid: Array = []


# --- 公共变量 ---

## 交互规则引用。
var interaction_rule: InteractionRule

## 移动规则引用。
var movement_rule: MovementRule


# --- 公共方法 ---

## 初始化模型。
## @param size: 棋盘尺寸。
## @param interaction_rule: 交互规则实例。
## @param movement_rule: 移动规则实例。
func initialize(size: int, p_interaction_rule: InteractionRule, p_movement_rule: MovementRule) -> void:
	grid_size = size
	interaction_rule = p_interaction_rule
	movement_rule = p_movement_rule

	if is_instance_valid(movement_rule):
		movement_rule.setup(interaction_rule)

	_initialize_grid()


## 处理移动逻辑。
## @param direction: 移动方向向量。
## @return: 如果发生了有效移动，返回 true。
func move(direction: Vector2i) -> bool:
	var moved: bool = false
	var instructions: Array[Dictionary] = []
	var new_grid: Array = []
	new_grid.resize(grid_size)

	for i in range(grid_size):
		new_grid[i] = []
		new_grid[i].resize(grid_size)
		new_grid[i].fill(null)

	var moved_lines_indices: Array[int] = []

	for i in range(grid_size):
		var line: Array[Tile] = []

		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction)
			line.append(grid[coords.x][coords.y])

		var result: Dictionary = movement_rule.process_line(line)
		var new_line: Array[Tile] = result.line
		var merges: Array[Dictionary] = result.merges

		if result.moved:
			moved = true
			if not i in moved_lines_indices:
				moved_lines_indices.append(i)

		for merge_info in merges:
			var consumed: Tile = merge_info.consumed_tile
			var merged: Tile = merge_info.merged_tile
			var final_line_pos: int = new_line.find(merged)
			var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction)

			instructions.append({
				"type": "MERGE",
				"consumed_tile": consumed,
				"merged_tile": merged,
				"to_grid_pos": final_coords
			})

			if merge_info.has("score"):
				score_updated.emit(merge_info["score"])

		var tiles_in_new_line: Dictionary = {}
		for tile in new_line:
			if tile: tiles_in_new_line[tile.get_instance_id()] = true

		for j in range(grid_size):
			var original_tile: Tile = line[j]
			if original_tile and not tiles_in_new_line.has(original_tile.get_instance_id()):
				continue

			var final_line_pos: int = new_line.find(original_tile)
			if original_tile and final_line_pos != -1 and final_line_pos != j:
				var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction)
				instructions.append({
					"type": "MOVE",
					"tile": original_tile,
					"to_grid_pos": final_coords
				})

		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction)
			new_grid[coords.x][coords.y] = new_line[j]

	if moved:
		grid = new_grid
		board_changed.emit(instructions)
		return true

	return false


## 获取所有空格子的坐标。
## @return: 空格子坐标数组。
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells


## 在指定位置放置一个方块（仅逻辑引用）。
## @param tile: 方块节点。
## @param grid_pos: 网格坐标。
func place_tile(tile: Node, grid_pos: Vector2i) -> void:
	if _is_valid_pos(grid_pos):
		grid[grid_pos.x][grid_pos.y] = tile
		tile_spawned.emit(tile)


## 获取最大玩家方块数值。
## @return: 最大玩家方块数值。
func get_max_player_value() -> int:
	var max_val: int = 0
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile and tile.get("type") == 0 and tile.get("value") > max_val:
				max_val = tile.value
	return max_val


## 获取所有玩家方块数值的数组。
## @return: 已排序的玩家方块数值数组。
func get_all_player_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile = grid[x][y]
			if tile and tile.get("type") == 0:
				values.append(tile.value)
	values.sort()
	return values


## 扩建棋盘。
## @param new_size: 新的棋盘尺寸。
func expand_grid(new_size: int) -> void:
	if new_size <= grid_size: return

	var old_size: int = grid_size
	grid_size = new_size

	for x in range(old_size):
		grid[x].resize(grid_size)
		grid[x].slice(old_size, grid_size - 1).fill(null)

	grid.resize(grid_size)

	for x in range(old_size, grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)


## 获取快照。
## @return: 包含棋盘状态的字典。
func get_snapshot() -> Dictionary:
	var tiles_data: Array[Dictionary] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile = grid[x][y]
			if tile != null:
				tiles_data.append({
					"pos": Vector2i(x, y),
					"value": tile.value,
					"type": tile.type
				})
	return {
		"grid_size": grid_size,
		"tiles": tiles_data,
	}


# --- 私有方法 ---

func _initialize_grid() -> void:
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)


func _get_coords_for_line(line_index: int, cell_index: int, direction: Vector2i) -> Vector2i:
	match direction:
		Vector2i.LEFT: return Vector2i(cell_index, line_index)
		Vector2i.RIGHT: return Vector2i(grid_size - 1 - cell_index, line_index)
		Vector2i.UP: return Vector2i(line_index, cell_index)
		Vector2i.DOWN: return Vector2i(line_index, grid_size - 1 - cell_index)
	return Vector2i.ZERO


func _is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size
