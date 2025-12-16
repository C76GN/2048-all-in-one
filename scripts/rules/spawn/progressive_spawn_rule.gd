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
		var spawn_pool: Array[int] = _get_current_spawn_pool(grid_model)
		var value: int = spawn_pool[RNGManager.get_rng().randi_range(0, spawn_pool.size() - 1)]

		var spawn_data: Dictionary = {
			"value": value,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}

		spawn_tile_requested.emit(spawn_data)

	return consumes_event_on_success


# --- 私有/辅助方法 ---

## 根据当前棋盘上的最大方块值确定生成池。
## @param grid_model: 网格模型引用。
## @return: 一个包含当前所有可生成数值的数组。
func _get_current_spawn_pool(grid_model: GridModel) -> Array[int]:
	var max_value: int = grid_model.get_max_player_value()
	# 基础生成池
	var spawn_pool: Array[int] = [2, 4]

	if max_value < 2048:
		return spawn_pool

	# 计算最大值是2的多少次方，例如 2048 -> 11, 4096 -> 12
	var power: int = int(log(max_value) / log(2))

	# 从 2^11 (2048) 开始，每增加一次幂，就在生成池中增加一个新方块。
	# k 从 3 开始，因为池中已有 2^1 和 2^2。
	# power - 11 是解锁等级，0级(2048)解锁8, 1级(4096)解锁16。
	# 所以解锁的方块幂次是 k = 3 到 (power - 11) + 3。
	for k in range(3, (power - 11) + 4):
		spawn_pool.append(int(pow(2, k)))

	return spawn_pool
