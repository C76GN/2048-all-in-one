## GridMovementSystem: 负责处理网格移动、合并逻辑的核心系统。
##
## 该系统监听来自输入层或控制器的移动命令/事件，并执行滑动和合并算法。
## 执行结果将更新 `GridModel` 并可能触发 `board_changed` 等级事件。
class_name GridMovementSystem
extends GFSystem

# --- 缓存引用 ---
var _grid_model: GridModel
var _log: GFLogUtility


# --- Godot 生命周期方法 ---

## 从架构获取必要的层级引用。
func ready() -> void:
	_grid_model = get_model(GridModel) as GridModel
	_log = get_utility(GFLogUtility) as GFLogUtility


# --- 核心逻辑 ---

## 处理玩家的滑动输入。
## @param direction: 移动的方向向量 (Vector2i.UP, DOWN, LEFT, RIGHT)
## @return: 如果发生了有效移动，返回包含方向和受影响行/列的 MoveData；否则返回 null。
func handle_move(direction: Vector2i) -> MoveData:
	if not is_instance_valid(_grid_model):
		if is_instance_valid(_log):
			_log.error("GridMovementSystem", "GridModel reference is missing.")
		return null
		
	var interaction_rule = _grid_model.interaction_rule
	var movement_rule = _grid_model.movement_rule
	
	if not interaction_rule or not movement_rule:
		if is_instance_valid(_log):
			_log.error("GridMovementSystem", "GridModel is missing rules.")
		return null
		
	var grid_size = _grid_model.grid_size
	var grid = _grid_model.grid
	
	movement_rule.setup(interaction_rule)

	var instructions: Array[Dictionary] = []
	var new_grid: Array = []
	new_grid.resize(grid_size)

	for i in range(grid_size):
		new_grid[i] = []
		new_grid[i].resize(grid_size)
		new_grid[i].fill(null)

	var moved_lines_indices: Array[int] = []
	var score_delta: int = 0
	var monster_kill_count: int = 0

	# 算法核心：按行/列处理
	for i in range(grid_size):
		var line: Array[GameTileData] = []

		# 提取当前行/列的 TileData 引用
		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
			line.append(grid[coords.x][coords.y])

		# 调用规则引擎计算合并结果
		var result: Dictionary = movement_rule.process_line(line)
		var new_line: Array[GameTileData] = result.line
		var merges: Array[Dictionary] = result.merges
		var merged_tile_ids: Dictionary = {}

		if result.moved:
			if not i in moved_lines_indices:
				moved_lines_indices.append(i)

		# 记录合并指令 (用于动画)
		for merge_info in merges:
			var consumed: GameTileData = merge_info.consumed_tile
			var merged: GameTileData = merge_info.merged_tile
			merged_tile_ids[merged.get_instance_id()] = true
			var final_line_pos: int = new_line.find(merged)
			var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction, grid_size)

			var orig_consumed_idx: int = line.find(consumed)
			var orig_merged_idx: int = line.find(merged)
			var from_coords_consumed: Vector2i = _get_coords_for_line(i, orig_consumed_idx, direction, grid_size)
			var from_coords_merged: Vector2i = _get_coords_for_line(i, orig_merged_idx, direction, grid_size)

			var instruction: Dictionary = {
				&"type": &"MERGE",
				&"consumed_data": consumed,
				&"merged_data": merged,
				&"to_grid_pos": final_coords,
				&"from_grid_pos_consumed": from_coords_consumed,
				&"from_grid_pos_merged": from_coords_merged
			}
			
			if merge_info.has(&"transform"):
				instruction[&"transform"] = true

			instructions.append(instruction)

			if merge_info.has("score"):
				score_delta += int(merge_info.get("score", 0))
			if merge_info.has("monster_killed"):
				monster_kill_count += int(merge_info.get("monster_killed", 0))

		# 记录移动指令 (用于动画)
		var tiles_in_new_line_ids: Array = []
		for tile_data in new_line:
			if tile_data: tiles_in_new_line_ids.append(tile_data.get_instance_id())

		for j in range(grid_size):
			var original_data: GameTileData = line[j]
			if original_data == null or not original_data.get_instance_id() in tiles_in_new_line_ids:
				continue
			if merged_tile_ids.has(original_data.get_instance_id()):
				continue

			var final_line_pos: int = new_line.find(original_data)
			if final_line_pos != -1 and final_line_pos != j:
				var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction, grid_size)
				var from_coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
				instructions.append({
					&"type": &"MOVE",
					&"tile_data": original_data,
					&"from_grid_pos": from_coords,
					&"to_grid_pos": final_coords
				})

		# 更新临时网格数据
		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
			new_grid[coords.x][coords.y] = new_line[j]

	# 如果有任何移动发生
	if not moved_lines_indices.is_empty():
		# 1. 更新 Model 数据
		_grid_model.grid = new_grid

		if score_delta != 0:
			send_simple_event(EventNames.SCORE_UPDATED, score_delta)
		if monster_kill_count > 0:
			send_simple_event(EventNames.MONSTER_KILLED, monster_kill_count)
			
		# 2. 发送动画请求事件 (简单事件)
		send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instructions)

		# 3. 构造并发送移动完成事件 (类型事件，用于触发后续生成逻辑)
		var result_move_data := MoveData.new()
		result_move_data.direction = direction
		result_move_data.moved_lines = moved_lines_indices
		send_event(result_move_data)

		return result_move_data

	return null


# --- 辅助方法 ---

func _get_coords_for_line(line_index: int, cell_index: int, direction: Vector2i, grid_size: int) -> Vector2i:
	match direction:
		Vector2i.LEFT: return Vector2i(cell_index, line_index)
		Vector2i.RIGHT: return Vector2i(grid_size - 1 - cell_index, line_index)
		Vector2i.UP: return Vector2i(line_index, cell_index)
		Vector2i.DOWN: return Vector2i(line_index, grid_size - 1 - cell_index)
	return Vector2i.ZERO
