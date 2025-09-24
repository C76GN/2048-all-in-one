# scripts/modes/probabilistic_spawn_rule.gd

## ProbabilisticSpawnRule: 实现了按概率生成方块的规则。
##
## 规则行为：
## 1. 监听移动事件（ON_MOVE_PROBABILITY）。
## 2. 每次触发时，根据当前概率决定是否生成方块。
## 3. 如果生成成功，则重置概率。
## 4. 如果生成失败，则增加下一次的成功概率，直到达到上限。
## 所有参数（基础概率、增量、要生成的方块等）都可以在编辑器中配置。
class_name ProbabilisticSpawnRule
extends SpawnRule

# --- 可配置属性 ---

@export_group("生成方块配置")
## 成功生成时，要生成的方块的数值。
@export var spawn_value: int = 2
## 成功生成时，要生成的方块的类型。
@export var spawn_type: Tile.TileType = Tile.TileType.PLAYER

@export_group("概率配置")
## 基础概率（0.0 到 1.0 之间）。
@export_range(0.0, 1.0) var base_probability: float = 0.25
## 每次生成失败后，概率增加的量。
@export_range(0.0, 1.0) var increase_on_failure: float = 0.1
## 概率可以达到的最大值。
@export_range(0.0, 1.0) var max_probability: float = 0.9

@export_group("行为配置")
## 如果生成成功，是否“消费”事件，阻止后续低优先级的移动规则执行。
@export var consumes_event_on_success: bool = false

# --- 内部状态 ---

# 当前的动态概率值。
var _current_probability: float = 0.0


## 初始化此规则，设置初始概率。
func setup(p_game_board: Control, _required_nodes: Dictionary = {}) -> void:
	super.setup(p_game_board)
	_current_probability = base_probability


## RuleManager调用此函数来执行概率生成逻辑。
func execute(_payload: Dictionary = {}) -> bool:
	# 如果棋盘已满，则无法生成，直接返回false。
	if game_board.get_empty_cells().is_empty():
		return false
		
	var rng_value = randf()
	
	# 检查随机数是否小于当前概率
	if rng_value < _current_probability:
		# --- 成功 ---
		var spawn_data = {
			"value": spawn_value,
			"type": spawn_type,
			"is_priority": false
		}
		spawn_tile_requested.emit(spawn_data)
		
		# 重置概率
		_current_probability = base_probability
		print("概率生成成功！下次概率重置为: ", _current_probability)
		
		return consumes_event_on_success
	else:
		# --- 失败 ---
		# 增加下一次的概率
		_current_probability = min(_current_probability + increase_on_failure, max_probability)
		print("概率生成失败。下次概率提升至: ", _current_probability)
		
		# 因为没有成功生成，所以事件没有被消费。
		return false
