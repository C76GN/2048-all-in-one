# scripts/modes/fibonacci_spawn_rule.gd

## FibonacciSpawnRule: 为斐波那契模式生成方块。
##
## 规则：
## 1. 触发器(ON_INITIALIZE): 负责在棋盘上生成一个初始方块。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新的数值为1的玩家方块。
class_name FibonacciSpawnRule
extends SpawnRule

## 执行生成逻辑。
func execute(_payload: Dictionary = {}) -> bool:
	# 检查棋盘是否已满，如果满了则无法生成。
	if game_board.get_empty_cells().is_empty():
		return false

	var spawn_data = {
		"value": 1,
		"type": Tile.TileType.PLAYER,
		"is_priority": false
	}
	
	spawn_tile_requested.emit(spawn_data)
	
	# 成功请求了生成，消费掉移动事件。
	return true
