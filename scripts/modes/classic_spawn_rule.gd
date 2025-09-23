# scripts/modes/classic_spawn_rule.gd

## ClassicSpawnRule: 实现了经典的2048生成规则。
##
## 规则包括：
## 1. 在游戏开始时，负责在棋盘上生成两个初始方块。
## 2. 在每次有效移动后，请求在随机空位生成一个新的玩家方块（90%为2，10%为4）。
class_name ClassicSpawnRule
extends SpawnRule

var game_board: Control # 对GameBoard节点的引用
var move_count: int = 0 # 经典模式也需要追踪移动次数

## 初始化此规则。
func setup(board: Control) -> void:
	self.game_board = board

## 负责棋盘的初始状态。
func initialize_board() -> void:
	_request_spawn()
	_request_spawn()

## 当玩家执行一次有效移动时被调用。
func on_move_made() -> void:
	move_count += 1
	_request_spawn()

## [内部函数] 请求生成一个新的方块。
func _request_spawn() -> void:
	# 经典规则：90%概率生成2，10%概率生成4。
	var value = 2 if randf() < 0.9 else 4
	
	var spawn_data = {
		"value": value, 
		"type": Tile.TileType.PLAYER, 
		"is_priority": false # 普通方块生成不是优先的，若棋盘已满则无法生成。
	}
	
	# 发出信号，请求 GameBoard 执行生成操作。
	spawn_tile_requested.emit(spawn_data)
