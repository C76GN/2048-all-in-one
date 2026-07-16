## GameStateSystem: 负责采集与恢复一局游戏的完整逻辑状态。
class_name GameStateSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _CANONICAL_OPTIONS: Dictionary = {"allow_floats": true}


# --- 公共方法 ---

func get_required_models() -> Array[Script]:
	return [GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [RuleSystem]


func get_required_utilities() -> Array[Script]:
	return [GFSeedUtility]


## 提取完整快照。
## @param grid_size_override: 外部指定的棋盘尺寸；小于等于 0 时使用 GridModel 当前尺寸。
## @return: 可用于撤销、书签比较和恢复的完整状态字典。
func get_full_game_state(grid_size_override: int = 0) -> Dictionary:
	var rule_sys: RuleSystem = _get_rule_system()
	var status: GameStatusModel = _get_status_model()
	var grid: GridModel = _get_grid_model()
	var seed_util: GFSeedUtility = _get_seed_utility()
	var grid_size: int = grid_size_override
	var highest_tile: int = 0
	var score: int = 0
	var move_count: int = 0
	var ratio_resolutions: int = 0
	var target_tile_value: int = 0
	var target_reached: bool = false
	var extra_stats: Dictionary = {}

	if grid_size <= 0 and is_instance_valid(grid):
		grid_size = grid.grid_size
	if is_instance_valid(grid):
		highest_tile = grid.get_max_tile_value()

	if is_instance_valid(status):
		score = GFVariantData.to_int(status.score.get_value(), 0)
		move_count = GFVariantData.to_int(status.move_count.get_value(), 0)
		ratio_resolutions = GFVariantData.to_int(status.ratio_resolutions.get_value(), 0)
		target_tile_value = GFVariantData.to_int(status.target_tile_value.get_value(), 0)
		target_reached = GFVariantData.to_bool(status.target_reached.get_value(), false)
		var extra_stats_value: Variant = status.extra_stats.get_value()
		if extra_stats_value is Dictionary:
			var typed_extra_stats: Dictionary = extra_stats_value
			extra_stats = typed_extra_stats.duplicate(true)

	var rules_states: Array = []
	if is_instance_valid(rule_sys):
		for rule: SpawnRule in rule_sys.get_all_spawn_rules():
			var state: Variant = rule.get_state()
			if state is Dictionary:
				var state_dictionary: Dictionary = state
				rules_states.append(state_dictionary.duplicate(true))
			elif state is Array:
				var state_array: Array = state
				rules_states.append(state_array.duplicate(true))
			else:
				rules_states.append(state)

	return {
		&"grid_size": grid_size,
		&"board_snapshot": grid.get_snapshot() if is_instance_valid(grid) else {},
		&"rng_full_state": seed_util.get_full_state() if is_instance_valid(seed_util) else {},
		&"score": score,
		&"move_count": move_count,
		&"highest_tile": highest_tile,
		&"ratio_resolutions": ratio_resolutions,
		&"target_tile_value": target_tile_value,
		&"target_reached": target_reached,
		&"extra_stats": extra_stats,
		&"rules_states": rules_states,
	}


## 对比两个完整游戏状态是否等价。
## @param left: 左侧完整游戏状态。
## @param right: 右侧完整游戏状态。
func are_states_equal(left: Dictionary, right: Dictionary) -> bool:
	var left_bytes: PackedByteArray = GFDeterministicVariantSerializer.to_canonical_bytes(
		left,
		_CANONICAL_OPTIONS
	)
	if left_bytes.is_empty():
		return false
	var right_bytes: PackedByteArray = GFDeterministicVariantSerializer.to_canonical_bytes(
		right,
		_CANONICAL_OPTIONS
	)
	return not right_bytes.is_empty() and left_bytes == right_bytes


## 根据快照恢复模型和系统的状态。
## @param state_to_restore: get_full_game_state() 产生的完整游戏状态。
## @remark 该方法只恢复逻辑状态，表现层刷新由调用方决定。
func restore_state(state_to_restore: Dictionary) -> void:
	if state_to_restore.is_empty():
		return

	var rule_sys: RuleSystem = _get_rule_system()
	var status: GameStatusModel = _get_status_model()
	var grid: GridModel = _get_grid_model()
	var seed_util: GFSeedUtility = _get_seed_utility()

	if is_instance_valid(grid):
		var board_snapshot: Dictionary = GFVariantData.get_option_dictionary(
			state_to_restore,
			&"board_snapshot"
		)
		if not board_snapshot.is_empty():
			grid.restore_from_snapshot(board_snapshot)

	if is_instance_valid(status):
		status.score.set_value(GFVariantData.get_option_int(state_to_restore, &"score", 0))
		status.move_count.set_value(GFVariantData.get_option_int(state_to_restore, &"move_count", 0))
		status.ratio_resolutions.set_value(GFVariantData.get_option_int(state_to_restore, &"ratio_resolutions", 0))
		var highest_tile: int = GFVariantData.get_option_int(state_to_restore, &"highest_tile", 0)
		if is_instance_valid(grid):
			highest_tile = grid.get_max_tile_value()
		status.highest_tile.set_value(highest_tile)
		status.set_target_state(
			GFVariantData.get_option_int(state_to_restore, &"target_tile_value", 0),
			GFVariantData.get_option_bool(state_to_restore, &"target_reached", false)
		)
		var extra_stats: Dictionary = GFVariantData.get_option_dictionary(state_to_restore, &"extra_stats")
		status.extra_stats.set_value(extra_stats.duplicate(true))

	if is_instance_valid(seed_util):
		var rng_full_state: Dictionary = GFVariantData.get_option_dictionary(
			state_to_restore,
			&"rng_full_state"
		)
		if not rng_full_state.is_empty():
			seed_util.set_full_state(rng_full_state)

	if is_instance_valid(rule_sys):
		var rules_states: Array = GFVariantData.get_option_array(state_to_restore, &"rules_states")
		var all_rules: Array[SpawnRule] = rule_sys.get_all_spawn_rules()
		for i: int in range(min(all_rules.size(), rules_states.size())):
			all_rules[i].set_state(rules_states[i])


# --- 私有/辅助方法 ---

func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null


func _get_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null
