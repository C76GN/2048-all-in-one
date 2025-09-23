# scripts/modes/timed_monster_spawn_rule.gd

## TimedMonsterSpawnRule: "测试模式1"中使用的定时生成怪物规则。
##
## 管理一个倒计时器，时间到了就请求生成一个基于当前游戏状态的怪物。
## 同时处理移动后获得时间奖励的逻辑。
class_name TimedMonsterSpawnRule
extends SpawnRule

const INITIAL_SPAWN_INTERVAL: float = 10.0 # 怪物生成的基础时间间隔（秒）。
const MIN_TIME_BONUS: float = 0.5 # 每次移动获得的最小时间奖励。
const TIME_BONUS_DECAY_FACTOR: float = 5.0 # 时间奖励的衰减因子，移动次数越多，奖励越少。

var monster_spawn_timer: Timer # 用于定时生成怪物的计时器。
var move_count: int = 0 # 玩家的总移动次数，用于计算时间奖励。
var game_board: Control # 对GameBoard节点的引用，用于查询棋盘状态。

# --- 公共接口 ---

## 设置此规则所需的外部依赖并启动计时器。
## @param board: 从GamePlay传入的GameBoard节点实例。
func setup(board: Control) -> void:
	self.game_board = board
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = INITIAL_SPAWN_INTERVAL
	monster_spawn_timer.timeout.connect(_on_monster_timer_timeout)
	add_child(monster_spawn_timer)
	monster_spawn_timer.start()

## 当玩家执行一次有效移动时被调用。
##
## 此函数会根据移动次数计算并增加时间奖励。
func on_move_made() -> void:
	move_count += 1
	var time_to_add = MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / move_count
	monster_spawn_timer.start(monster_spawn_timer.time_left + time_to_add)

## 停止怪物生成计时器，通常在游戏结束时调用。
func stop_timer() -> void:
	if monster_spawn_timer:
		monster_spawn_timer.stop()

## 获取怪物生成计时器的剩余时间。
## @return: 剩余的秒数。
func get_time_left() -> float:
	if monster_spawn_timer:
		return monster_spawn_timer.time_left
	return 0.0

## 计算并获取下一次移动可以获得的时间奖励。
## @return: 预计的时间奖励秒数。
func get_next_move_bonus() -> float:
	var next_m_count = move_count + 1
	return MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / next_m_count

# --- 内部逻辑 ---

## 当怪物生成计时器到期时触发的回调函数。
func _on_monster_timer_timeout() -> void:
	var monster_value = _calculate_monster_value()
	var spawn_data = {
		"value": monster_value,
		"type": Tile.TileType.MONSTER,
		"is_priority": true # 怪物生成是优先的，即使棋盘满了也要强制生成。
	}
	spawn_tile_requested.emit(spawn_data)
	monster_spawn_timer.start(INITIAL_SPAWN_INTERVAL) # 重置计时器

## [内部函数] 根据动态生成的怪物池，计算本次要生成的怪物数值。
##
## @return: 最终通过加权随机选择出的怪物数值。
func _calculate_monster_value() -> int:
	var spawn_pool = get_monster_spawn_pool()
	var possible_values = spawn_pool["values"]
	var weights = spawn_pool["weights"]

	if possible_values.is_empty(): return 2

	var total_weight = 0
	for w in weights: total_weight += w
	if total_weight == 0: return 2

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var random_pick = rng.randi_range(1, total_weight)
	
	var cumulative_weight = 0
	for i in range(weights.size()):
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]
	
	return 2 # 作为后备

## 动态计算并获取当前的怪物生成池。
##
## 生成池的内容与玩家当前拥有的最大方块数值相关。
## 最大方块数值越高，可能生成的怪物数值也越高，且低级怪物的权重会降低。
## @return: 一个包含 "values" 和 "weights" 数组的字典。
func get_monster_spawn_pool() -> Dictionary:
	if not is_instance_valid(game_board): return {"values": [2], "weights": [1]}

	var max_player_value = game_board.get_max_player_value()
	if max_player_value <= 0:
		return {"values": [2], "weights": [1]}
		
	# 'k' 代表最大方块值是2的多少次方，它决定了怪物池的深度。
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	var weights = []
	var possible_values = []
	# 生成从 2^1 到 2^k 的所有可能怪物数值。
	# 权重被设置为 (k - i + 1)，这意味着数值越低的怪物权重越高，但随着k的增长，高级怪物的权重会相对提升。
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		weights.append(k - i + 1)
	
	return {"values": possible_values, "weights": weights}
