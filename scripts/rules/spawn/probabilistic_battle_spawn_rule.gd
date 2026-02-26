# scripts/rules/spawn/probabilistic_battle_spawn_rule.gd

## ProbabilisticBattleSpawnRule: 实现了玩家或怪物二选一的概率生成规则。
##
## 规则行为:
## 1. 监听移动事件 (ON_MOVE)。
## 2. 每次移动后，有较低概率生成一个怪物方块。如果生成失败，则生成一个常规的玩家方块。
## 3. 怪物生成概率是动态的：如果失败，则增加下一次的成功概率，直到达到上限；如果成功，则重置为基础概率。
## 4. 生成的怪物数值会根据当前棋盘上玩家方块的最大值动态调整，变得更具挑战性。
class_name ProbabilisticBattleSpawnRule
extends SpawnRule


# --- 导出变量 ---

@export_group("概率配置")
## 生成怪物的基础概率（0.0 到 1.0 之间）。
@export_range(0.0, 1.0) var base_probability: float = 0.05

## 每次生成怪物失败后，概率增加的量。
@export_range(0.0, 1.0) var increase_on_failure: float = 0.02

## 怪物生成概率可以达到的最大值。
@export_range(0.0, 1.0) var max_probability: float = 0.5


@export_group("玩家方块配置")
## 生成数值为2的玩家方块的概率（其余为4）。
@export_range(0.0, 1.0) var probability_of_2: float = 0.9


# --- 私有变量 ---

## 当前的动态怪物生成概率值。
var _current_probability: float = 0.0


# --- 公共方法 ---

## 初始化此规则，设置初始概率。
## @param _required_nodes: 一个字典，包含规则声明需要的已创建节点。
func setup(_required_nodes: Dictionary = {}) -> void:
	_current_probability = base_probability


## RuleManager调用此函数来执行概率生成逻辑。
## @param context: 包含 'grid_model' 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: Dictionary = {}) -> bool:
	var grid_model: GridModel = context.get("grid_model")
	if not grid_model: return false

	if grid_model.get_empty_cells().is_empty():
		return false

	var rng := RNGManager.get_rng()

	# 决定生成怪物还是玩家
	if rng.randf() < _current_probability:
		# 成功: 生成怪物
		var monster_value: int = _calculate_monster_value(grid_model)
		var spawn_data := {
			"value": monster_value,
			"type": Tile.TileType.MONSTER,
			"is_priority": true
		}
		spawn_tile_requested.emit(spawn_data)

		# 重置概率
		_current_probability = base_probability

	else:
		# 失败: 生成玩家
		_current_probability = min(_current_probability + increase_on_failure, max_probability)

		var value: int = 2 if rng.randf() < probability_of_2 else 4
		var spawn_data := {
			"value": value,
			"type": Tile.TileType.PLAYER,
			"is_priority": false
		}
		spawn_tile_requested.emit(spawn_data)

	# 此规则总是会生成一个方块（除非棋盘已满），所以它应该消费事件，
	# 阻止其他“移动后生成”规则执行。
	return true


## 获取用于在HUD上显示的动态数据。
## @param context: 可选的上下文字典，包含 'grid_model'。
## @return: 一个包含显示信息的字典。
func get_display_data(context: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {}
	data["monster_chance_label"] = tr("BATTLE_MONSTER_CHANCE") % (_current_probability * 100)

	var grid_model: GridModel = context.get("grid_model")
	var pool: Dictionary = get_monster_spawn_pool(grid_model)
	var spawn_info_text: String = tr("BATTLE_SPAWN_INFO")
	var total_weight: int = 0
	for w in pool["weights"]: total_weight += w
	if total_weight > 0:
		for i in range(pool["weights"].size()):
			var p: float = (float(pool["weights"][i]) / total_weight) * 100
			spawn_info_text += tr("FORMAT_BATTLE_PROBABILITY") % [pool["values"][i], p]
	data["spawn_info_label"] = spawn_info_text

	return data


## 获取规则当前的内部状态，用于保存。
## @return: 一个包含规则状态的可序列化变量 (如字典或基础类型)。
func get_state() -> Variant:
	return {"current_probability": _current_probability}


## 从一个状态值恢复规则的内部状态。
## @param state: 从历史记录中加载的状态值。
func set_state(state: Variant) -> void:
	if state is Dictionary and state.has("current_probability"):
		_current_probability = state["current_probability"]


## 动态计算并获取当前的怪物生成池。
## @param grid_model: 网格模型引用。
## @return: 一个包含 "values" 和 "weights" 数组的字典。
func get_monster_spawn_pool(grid_model: GridModel = null) -> Dictionary:
	if not grid_model:
		return {"values": [2], "weights": [1]}

	var max_player_value: int = grid_model.get_max_player_value()
	if max_player_value <= 0:
		return {"values": [2], "weights": [1]}

	var k: int = int(log(max_player_value) / log(2))
	if k < 1: k = 1

	var weights: Array[int] = []
	var possible_values: Array[int] = []
	for i in range(1, k + 1):
		possible_values.append(int(pow(2, i)))
		weights.append(k - i + 1)

	return {"values": possible_values, "weights": weights}


# --- 私有/辅助方法 ---

## 根据动态生成的怪物池，计算本次要生成的怪物数值。
## @param grid_model: 网格模型引用。
## @return: 计算出的怪物数值。
func _calculate_monster_value(grid_model: GridModel) -> int:
	var spawn_pool: Dictionary = get_monster_spawn_pool(grid_model)
	var possible_values: Array[int] = spawn_pool["values"]
	var weights: Array[int] = spawn_pool["weights"]

	if possible_values.is_empty(): return 2

	var total_weight: int = 0
	for w in weights: total_weight += w
	if total_weight == 0: return 2

	var rng := RNGManager.get_rng()
	var random_pick: int = rng.randi_range(1, total_weight)

	var cumulative_weight: int = 0
	for i in range(weights.size()):
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]

	# 作为后备
	return 2
