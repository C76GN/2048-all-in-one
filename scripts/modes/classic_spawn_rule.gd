# scripts/modes/classic_spawn_rule.gd

## ClassicSpawnRule: 实现了经典的2048生成规则。
##
## 每当一次有效的移动发生后，它会请求在棋盘上生成一个值为2的玩家方块。
## 这是一个非常简单、无状态的规则。
class_name ClassicSpawnRule
extends SpawnRule

## 当 GamePlay 场景捕获到 GameBoard 的 move_made 信号时调用此函数。
##
## 它的唯一职责是构建一个标准的生成请求数据包，然后发出 `spawn_tile_requested` 信号。
func on_move_made() -> void:
	# 定义要生成的方块信息：一个值为2的普通玩家方块。
	var spawn_data = {
		"value": 2, 
		"type": Tile.TileType.PLAYER, 
		"is_priority": false # 普通方块生成不是优先的，若棋盘已满则无法生成。
	}
	
	# 发出信号，请求 GameBoard 执行生成操作。
	spawn_tile_requested.emit(spawn_data)
