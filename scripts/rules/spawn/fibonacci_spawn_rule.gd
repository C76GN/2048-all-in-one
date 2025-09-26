# scripts/modes/fibonacci_spawn_rule.gd

## FibonacciSpawnRule: 为斐波那契模式生成方块。
##
## 规则：
## 1. 触发器(ON_INITIALIZE): 负责在棋盘上生成两个初始方块。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新的数值为1的玩家方块。
class_name FibonacciSpawnRule
extends SpawnRule

## 如果为true，成功执行后将阻止其他低优先级规则运行。
@export var consumes_event_on_success: bool = true

## 执行生成逻辑。
func execute(_payload: Dictionary = {}) -> bool:
	# 检查棋盘是否已满，如果满了则无法生成。
	if game_board.get_empty_cells().is_empty():
		return false

	var spawn_count = 1
	# 特殊逻辑：如果是初始化事件，则生成两个方块。
	if trigger == TriggerType.ON_INITIALIZE:
		spawn_count = 2

	# 确保要生成的方块数量不超过棋盘上的空格数量。
	spawn_count = min(spawn_count, game_board.get_empty_cells().size())
	
	for i in range(spawn_count):
		var spawn_data = {
			"value": 1,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}
		
		spawn_tile_requested.emit(spawn_data)
	
	# 根据配置决定是否消费事件。
	return consumes_event_on_success
