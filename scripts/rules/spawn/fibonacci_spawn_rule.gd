# scripts/rules/spawn/fibonacci_spawn_rule.gd

## FibonacciSpawnRule: 为斐波那契模式生成方块。
##
## 规则：
## 1. 触发器(ON_INITIALIZE): 负责在棋盘上生成两个初始方块。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新的数值为1的玩家方块。
class_name FibonacciSpawnRule
extends SpawnRule


# --- 导出变量 ---

@export_group("规则配置")
## 如果为true，成功执行后将阻止其他低优先级规则运行。
@export var consumes_event_on_success: bool = true


# --- 公共方法 ---

## 执行生成逻辑。
## @param context: 包含 'grid_model' 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: Dictionary = {}) -> bool:
	var grid_model: GridModel = context.get("grid_model")
	if not grid_model: return false

	if grid_model.get_empty_cells().is_empty():
		return false

	var spawn_count: int = 1
	if trigger == TriggerType.ON_INITIALIZE:
		spawn_count = 2

	spawn_count = min(spawn_count, grid_model.get_empty_cells().size())

	for i in range(spawn_count):
		var spawn_data: Dictionary = {
			"value": 1,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}

		spawn_tile_requested.emit(spawn_data)

	# 根据配置决定是否消费事件。
	return consumes_event_on_success
