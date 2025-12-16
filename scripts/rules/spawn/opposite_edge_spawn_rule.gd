# scripts/rules/spawn/opposite_edge_spawn_rule.gd

## OppositeEdgeSpawnRule: 实现“对边生成”规则。
##
## 规则行为:
## 1. 触发器(ON_MOVE): 在每次有效移动后触发。
## 2. 对边生成: 新方块生成在玩家滑动的反方向边缘。
## 3. 移动前置: 只在那些实际发生位移的行或列的边缘生成。
## 4. 随机选择: 从所有有效生成点中随机选择一个。
class_name OppositeEdgeSpawnRule
extends SpawnRule


# --- 导出变量 ---

@export_group("规则配置")
## 生成数值为2的玩家方块的概率（其余为4）。
@export var probability_of_2: float = 0.9
## 如果生成成功，是否“消费”事件，阻止后续低优先级的移动规则执行。
@export var consumes_event_on_success: bool = true


# --- 公共方法 ---

## 执行生成逻辑。
## @param context: 包含 'grid_model' 和 'move_data' 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: Dictionary = {}) -> bool:
	var grid_model: GridModel = context.get("grid_model")
	if not grid_model: return false

	var move_data: Dictionary = context.get("move_data", {})
	var direction: Vector2i = move_data.get("direction", Vector2i.ZERO)
	var moved_lines: Array = move_data.get("moved_lines", [])

	if direction == Vector2i.ZERO or moved_lines.is_empty():
		return false

	var valid_spawn_points: Array[Vector2i] = []
	var grid_size: int = grid_model.grid_size

	match direction:
		Vector2i.UP:
			var target_y: int = grid_size - 1
			for x in moved_lines:
				if grid_model.grid[x][target_y] == null:
					valid_spawn_points.append(Vector2i(x, target_y))

		Vector2i.DOWN:
			var target_y: int = 0
			for x in moved_lines:
				if grid_model.grid[x][target_y] == null:
					valid_spawn_points.append(Vector2i(x, target_y))

		Vector2i.LEFT:
			var target_x: int = grid_size - 1
			for y in moved_lines:
				if grid_model.grid[target_x][y] == null:
					valid_spawn_points.append(Vector2i(target_x, y))

		Vector2i.RIGHT:
			var target_x: int = 0
			for y in moved_lines:
				if grid_model.grid[target_x][y] == null:
					valid_spawn_points.append(Vector2i(target_x, y))

	# 如果找到了有效的生成点
	if not valid_spawn_points.is_empty():
		# 使用全局RNG来选择位置，以遵循游戏种子
		var random_index: int = RNGManager.get_rng().randi_range(0, valid_spawn_points.size() - 1)
		var spawn_pos: Vector2i = valid_spawn_points[random_index]

		# 经典规则：按概率生成2或4
		var value: int = 2 if RNGManager.get_rng().randf() < probability_of_2 else 4

		var spawn_data: Dictionary = {
			"position": spawn_pos, # 指定生成位置
			"value": value,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}

		spawn_tile_requested.emit(spawn_data)

		# 成功请求了生成，根据配置决定是否消费事件。
		return consumes_event_on_success

	# 没有找到有效的生成点，不消费事件
	return false
