## ClassicSpawnRule: 实现了经典的2048生成规则。
##
## 规则包括：
## 1. 触发器(ON_INITIALIZE): 负责在棋盘上生成两个初始方块。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新的玩家方块。
class_name ClassicSpawnRule
extends SpawnRule


# --- 导出变量 ---

@export_group("规则配置")

## 生成数值为2的玩家方块的概率（其余为4）。
@export var probability_of_2: float = 0.9

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

	for i in range(spawn_count):
		var rng := context.get_rng("classic_spawn_rule")
		var value: int = 2 if rng.randf() < probability_of_2 else 4

		var spawn_data := SpawnData.new()
		spawn_data.value = value
		spawn_data.type = Tile.TileType.PLAYER
		spawn_data.is_priority = false

		context.request_spawn(spawn_data)

	return consumes_event_on_success
