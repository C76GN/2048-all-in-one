# scripts/modes/timed_monster_spawn_rule.gd

## TimedMonsterSpawnRule: 定时生成怪物的规则（资源版）。
##
## 管理一个倒计时，时间到了就请求生成怪物。
## 移动可以增加倒计时时间。
## Timer节点由GamePlay根据 get_required_nodes() 的请求创建并注入。
class_name TimedMonsterSpawnRule
extends SpawnRule

# --- 可配置属性 ---
@export var spawn_interval: float = 10.0
@export var min_time_bonus: float = 0.5
## 时间奖励衰减因子，此值越大，每次移动获得的奖励随移动次数增加而减少得越慢。
@export var time_bonus_decay_factor: float = 5.0

# --- 内部状态 ---
var monster_spawn_timer: Timer
var move_count_for_bonus: int = 0 # 用于计算时间奖励的独立移动计数

## 声明此规则需要一个名为 "timer" 的 Timer 节点才能工作。
func get_required_nodes() -> Dictionary:
	return {"timer": "Timer"}

## 接收依赖，并设置和启动计时器。
func setup(p_game_board: Control, required_nodes: Dictionary = {}) -> void:
	super.setup(p_game_board)
	
	if required_nodes.has("timer"):
		self.monster_spawn_timer = required_nodes["timer"]
		monster_spawn_timer.wait_time = spawn_interval
		# 确保只连接一次信号，防止重置时重复连接
		if not monster_spawn_timer.timeout.is_connected(_on_timer_timeout):
			monster_spawn_timer.timeout.connect(_on_timer_timeout)
		monster_spawn_timer.start()
	else:
		push_error("TimedMonsterSpawnRule 需要一个Timer，但没有提供！")

## RuleManager调用此函数来执行规则的核心逻辑。
## 当 trigger 设置为 ON_MOVE 时，每次移动都会调用此函数来增加时间。
func execute(_payload: Dictionary = {}) -> bool:
	# 根据移动增加时间奖励
	move_count_for_bonus += 1
	# 公式意图：提供一个基础奖励，加上一个随着游戏进行而递减的额外奖励。
	var time_to_add = min_time_bonus + time_bonus_decay_factor / move_count_for_bonus
	if is_instance_valid(monster_spawn_timer):
		monster_spawn_timer.start(monster_spawn_timer.time_left + time_to_add)
	
	# 此规则不“消费”移动事件，以便其他生成规则可以继续执行。
	return false

## 当计时器到期时，由信号回调调用。
func _on_timer_timeout():
	var monster_value = _calculate_monster_value()
	var spawn_data = {
		"value": monster_value,
		"type": Tile.TileType.MONSTER,
		"is_priority": true
	}
	spawn_tile_requested.emit(spawn_data)
	
	if is_instance_valid(monster_spawn_timer):
		monster_spawn_timer.start(spawn_interval)


## 在游戏结束时被调用，用于安全地停止计时器。
func teardown() -> void:
	if is_instance_valid(monster_spawn_timer):
		monster_spawn_timer.stop()

# --- UI查询接口 ---
func get_time_left() -> float:
	return monster_spawn_timer.time_left if is_instance_valid(monster_spawn_timer) else 0.0

func get_next_move_bonus() -> float:
	return min_time_bonus + time_bonus_decay_factor / (move_count_for_bonus + 1)

## 获取用于在HUD上显示的动态数据。
func get_display_data() -> Dictionary:
	var data = {}
	var time_left = get_time_left()
	if time_left > 0.0:
		data["timer_label"] = "怪物将在: %.1f s后出现" % time_left
	
	var next_bonus = get_next_move_bonus()
	if next_bonus > 0.0:
		data["bonus_label"] = "下次移动奖励: +%.2f s" % next_bonus
		
	var pool = get_monster_spawn_pool()
	var spawn_info_text = "怪物生成概率:\n"
	var total_weight = 0
	for w in pool["weights"]: total_weight += w
	if total_weight > 0:
		for i in range(pool["weights"].size()):
			var p = (float(pool["weights"][i]) / total_weight) * 100
			spawn_info_text += "  - %d: %.1f%%\n" % [pool["values"][i], p]
	data["spawn_info_label"] = spawn_info_text
	
	return data

# --- 内部逻辑 ---

## 动态计算并获取当前的怪物生成池。
func get_monster_spawn_pool() -> Dictionary:
	if not is_instance_valid(game_board): return {"values": [2], "weights": [1]}

	var max_player_value = game_board.get_max_player_value()
	if max_player_value <= 0:
		return {"values": [2], "weights": [1]}
		
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	var weights = []
	var possible_values = []
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		weights.append(k - i + 1)
	
	return {"values": possible_values, "weights": weights}

## [内部函数] 根据动态生成的怪物池，计算本次要生成的怪物数值。
func _calculate_monster_value() -> int:
	var spawn_pool = get_monster_spawn_pool()
	var possible_values = spawn_pool["values"]
	var weights = spawn_pool["weights"]

	if possible_values.is_empty(): return 2

	var total_weight = 0
	for w in weights: total_weight += w
	if total_weight == 0: return 2

	var rng = RNGManager.get_rng()
	var random_pick = rng.randi_range(1, total_weight)
	
	var cumulative_weight = 0
	for i in range(weights.size()):
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]
	
	return 2 # 作为后备
