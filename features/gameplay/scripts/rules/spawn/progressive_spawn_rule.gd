## ProgressiveSpawnRule: 渐进模式的方块生成规则。
##
## 规则行为:
## 1. 触发器(ON_INITIALIZE): 在棋盘上生成两个初始方块 (2或4)。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新方块。
## 3. 动态生成池:
##    - 游戏开始时，只生成 2 和 4。
##    - 当棋盘合成 2048 后，生成池扩展为 2, 4, 8。
##    - 当棋盘合成 4096 后，生成池扩展为 2, 4, 8, 16。
##    - 这个模式会随着最高方块值 (2^n) 解锁更多低阶方块的生成。
class_name ProgressiveSpawnRule
extends SpawnRule


# --- 导出变量 ---

@export_group("规则配置")

## 如果为true，成功执行后将阻止其他低优先级规则运行。
@export var consumes_event_on_success: bool = true


# --- 公共方法 ---

## 执行生成逻辑。
## @param context: 包含 grid_model 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: RuleContext) -> bool:
	if not is_instance_valid(context) or not is_instance_valid(context.grid_model):
		return false

	if context.grid_model.get_empty_cells().is_empty():
		return false

	var spawn_count: int = 1
	if trigger == TriggerType.ON_INITIALIZE:
		spawn_count = 2

	spawn_count = min(spawn_count, context.grid_model.get_empty_cells().size())

	for _i: int in range(spawn_count):
		var spawn_pool: Array[int] = _get_current_spawn_pool(context.grid_model)
		var random_stream: GFDeterministicRandom = context.get_random_stream("progressive_spawn_rule")
		if random_stream == null:
			return false
		var value: int = spawn_pool[random_stream.next_int_range(0, spawn_pool.size() - 1)]

		var spawn_data: SpawnData = SpawnData.new()
		spawn_data.value = value
		spawn_data.is_priority = false

		context.request_spawn(spawn_data)

	return consumes_event_on_success


# --- 私有/辅助方法 ---

## 根据当前棋盘上的最大方块值确定生成池。
## @param grid_model: 网格模型引用。
## @return: 一个包含当前所有可生成数值的数组。
func _get_current_spawn_pool(grid_model: GridModel) -> Array[int]:
	var max_value: int = grid_model.get_max_tile_value()
	var spawn_pool: Array[int] = [2, 4]

	if max_value < 2048:
		return spawn_pool

	var power: int = int(log(max_value) / log(2))

	for k: int in range(3, (power - 11) + 4):
		spawn_pool.append(int(pow(2, k)))

	return spawn_pool
