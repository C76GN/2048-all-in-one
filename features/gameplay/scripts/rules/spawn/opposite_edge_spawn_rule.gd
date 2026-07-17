## OppositeEdgeSpawnRule: 实现"对边生成"规则。
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

## 生成数值为2的方块概率（其余为4）。
@export var probability_of_2: float = 0.9

## 如果生成成功，是否"消费"事件，阻止后续低优先级的移动规则执行。
@export var consumes_event_on_success: bool = true


# --- 公共方法 ---

## 执行生成逻辑。
## @param context: 包含 grid_model 和 move_data 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: RuleContext) -> bool:
	if not is_instance_valid(context) or not is_instance_valid(context.grid_model):
		return false

	if not is_instance_valid(context.move_data):
		return false

	var direction: Vector2i = context.move_data.direction
	var moved_lanes: Array = context.move_data.moved_lanes

	if direction == Vector2i.ZERO or moved_lanes.is_empty():
		return false

	var valid_spawn_points: Array[Vector2i] = []
	for lane_value: Variant in moved_lanes:
		if not lane_value is Array:
			continue
		var lane: Array = lane_value
		if lane.is_empty() or not lane.back() is Vector2i:
			continue
		var trailing_cell: Vector2i = lane.back()
		if context.grid_model.get_tile(trailing_cell) == null:
			valid_spawn_points.append(trailing_cell)

	if not valid_spawn_points.is_empty():
		var random_stream: GFDeterministicRandom = context.get_random_stream("opposite_edge_spawn_rule")
		if random_stream == null:
			return false

		var random_index: int = random_stream.next_int_range(0, valid_spawn_points.size() - 1)
		var spawn_pos: Vector2i = valid_spawn_points[random_index]

		var value: int = 2 if random_stream.next_float_unit() < probability_of_2 else 4

		var spawn_data: SpawnData = SpawnData.new()
		spawn_data.position = spawn_pos
		spawn_data.value = value
		spawn_data.is_priority = false

		context.request_spawn(spawn_data)

		return consumes_event_on_success

	return false
