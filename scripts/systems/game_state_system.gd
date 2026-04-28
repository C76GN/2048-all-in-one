# scripts/systems/game_state_system.gd

## GameStateSystem: 负责采集与恢复一局游戏的完整逻辑状态。
class_name GameStateSystem
extends GFSystem


# --- 公共方法 ---

## 提取完整快照。
## @param grid_size_override: 外部指定的棋盘尺寸；小于等于 0 时使用 GridModel 当前尺寸。
## @return: 可用于撤销、书签比较和恢复的完整状态字典。
func get_full_game_state(grid_size_override: int = 0) -> Dictionary:
	var rule_sys := get_system(RuleSystem) as RuleSystem
	var status := get_model(GameStatusModel) as GameStatusModel
	var grid := get_model(GridModel) as GridModel
	var seed_util := get_utility(GFSeedUtility) as GFSeedUtility
	var grid_size: int = grid_size_override
	var extra_stats: Dictionary = {}

	if grid_size <= 0 and is_instance_valid(grid):
		grid_size = grid.grid_size

	if is_instance_valid(status):
		extra_stats = status.extra_stats.get_value().duplicate(true)

	var rules_states: Array = []
	if is_instance_valid(rule_sys):
		for rule in rule_sys.get_all_spawn_rules():
			var state: Variant = rule.get_state()
			if state is Dictionary or state is Array:
				rules_states.append(state.duplicate(true))
			else:
				rules_states.append(state)

	return {
		&"grid_size": grid_size,
		&"board_snapshot": grid.get_snapshot() if is_instance_valid(grid) else {},
		&"rng_state": seed_util.get_state() if is_instance_valid(seed_util) else 0,
		&"rng_full_state": seed_util.get_full_state() if is_instance_valid(seed_util) else {},
		&"score": status.score.get_value() if is_instance_valid(status) else 0,
		&"move_count": status.move_count.get_value() if is_instance_valid(status) else 0,
		&"highest_tile": status.highest_tile.get_value() if is_instance_valid(status) else 0,
		&"monsters_killed": status.monsters_killed.get_value() if is_instance_valid(status) else 0,
		&"status_message": status.status_message.get_value() if is_instance_valid(status) else "",
		&"extra_stats": extra_stats,
		&"rules_states": rules_states,
	}


## 根据快照恢复模型和系统的状态。
## @remark 该方法只恢复逻辑状态，表现层刷新由调用方决定。
func restore_state(state_to_restore: Dictionary) -> void:
	if state_to_restore.is_empty():
		return

	var rule_sys := get_system(RuleSystem) as RuleSystem
	var status := get_model(GameStatusModel) as GameStatusModel
	var grid := get_model(GridModel) as GridModel
	var seed_util := get_utility(GFSeedUtility) as GFSeedUtility

	if is_instance_valid(grid):
		var board_snapshot: Dictionary = state_to_restore.get(
			&"board_snapshot",
			state_to_restore.get(&"grid_snapshot", {})
		)
		if not board_snapshot.is_empty():
			grid.restore_from_snapshot(board_snapshot)

	if is_instance_valid(status):
		status.score.set_value(state_to_restore.get(&"score", 0))
		status.move_count.set_value(state_to_restore.get(&"move_count", 0))
		status.monsters_killed.set_value(state_to_restore.get(&"monsters_killed", 0))
		var highest_tile := 0
		if is_instance_valid(grid):
			highest_tile = grid.get_max_player_value()
		status.highest_tile.set_value(state_to_restore.get(&"highest_tile", highest_tile))
		status.status_message.set_value(state_to_restore.get(&"status_message", ""))
		var extra_stats: Dictionary = state_to_restore.get(&"extra_stats", {})
		status.extra_stats.set_value(extra_stats.duplicate(true))

	if is_instance_valid(seed_util):
		var rng_full_state: Dictionary = state_to_restore.get(&"rng_full_state", {})
		if not rng_full_state.is_empty():
			seed_util.set_full_state(rng_full_state)
		elif state_to_restore.has(&"rng_state"):
			seed_util.set_state(state_to_restore[&"rng_state"])

	if is_instance_valid(rule_sys) and state_to_restore.has(&"rules_states"):
		var rules_states: Array = state_to_restore[&"rules_states"]
		var all_rules: Array[SpawnRule] = rule_sys.get_all_spawn_rules()
		for i in range(min(all_rules.size(), rules_states.size())):
			all_rules[i].set_state(rules_states[i])
