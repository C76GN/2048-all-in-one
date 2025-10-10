# scripts/rules/spawn/progressive_spawn_rule.gd

## ProgressiveSpawnRule: 渐进模式的方块生成规则。
##
## 规则行为:
## 1. 触发器(ON_INITIALIZE): 在棋盘上生成两个初始方块 (2或4)。
## 2. 触发器(ON_MOVE): 在每次有效移动后，生成一个新方块。
## 3. 动态生成池:
##    - 游戏开始时，只生成 2 和 4。
##    - 当玩家合成 2048 后，生成池扩展为 2, 4, 8。
##    - 当玩家合成 4096 后，生成池扩展为 2, 4, 8, 16。
##    - 这个模式会随着玩家合成的最高方块值 (2^n) 而解锁更多低阶方块的生成。
class_name ProgressiveSpawnRule
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
		var spawn_pool = _get_current_spawn_pool()
		var value = spawn_pool[RNGManager.get_rng().randi_range(0, spawn_pool.size() - 1)]
		
		var spawn_data = {
			"value": value,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}
		
		spawn_tile_requested.emit(spawn_data)
	
	# 成功请求了生成，根据配置决定是否消费事件。
	return consumes_event_on_success

## [内部函数] 根据当前棋盘上的最大方块值确定生成池。
func _get_current_spawn_pool() -> Array[int]:
	var max_value = game_board.get_max_player_value()
	var spawn_pool: Array[int] = [2, 4] # 基础生成池
	
	if max_value < 2048:
		return spawn_pool

	# 计算最大值是2的多少次方，例如 2048 -> 11, 4096 -> 12
	var power = int(log(max_value) / log(2))
	
	# 从 2^11 (2048) 开始，每增加一次幂，就在生成池中增加一个新方块。
	# k 从 3 开始，因为池中已有 2^1 和 2^2。
	# power - 11 是解锁等级，0级(2048)解锁8, 1级(4096)解锁16。
	# 所以解锁的方块幂次是 k = 3 到 (power - 11) + 3。
	for k in range(3, (power - 11) + 4):
		spawn_pool.append(int(pow(2, k)))
		
	return spawn_pool
