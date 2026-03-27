# scripts/systems/game_state_system.gd

class_name GameStateSystem
extends GFSystem

## 提取完整快照。
func get_full_game_state(grid_size: int) -> Dictionary:
	var arch := Gf.get_architecture()
	var rule_sys := arch.get_system(RuleSystem) as RuleSystem
	var status := arch.get_model(GameStatusModel) as GameStatusModel
	var grid := arch.get_model(GridModel) as GridModel
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility
	
	var rules_states: Array = []
	if rule_sys:
		for rule in rule_sys.get_all_spawn_rules():
			rules_states.append(rule.get_state())

	return {
		&"grid_size": grid_size,
		&"board_snapshot": grid.get_snapshot() if grid else {},
		&"rng_state": seed_util.get_state() if seed_util else 0,
		&"score": status.score.get_value() if status else 0,
		&"move_count": status.move_count.get_value() if status else 0,
		&"monsters_killed": status.monsters_killed.get_value() if status else 0,
		&"rules_states": rules_states
	}


## 根据快照恢复模型和系统的状态。
## @remark 注意，这不会自动更新UI和动画。
func restore_state(state_to_restore: Dictionary) -> void:
	var arch := Gf.get_architecture()
	var rule_sys := arch.get_system(RuleSystem) as RuleSystem
	var status := arch.get_model(GameStatusModel) as GameStatusModel
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility
	
	if status:
		status.score.set_value(state_to_restore.get(&"score", 0))
		status.move_count.set_value(state_to_restore.get(&"move_count", 0))
		status.monsters_killed.set_value(state_to_restore.get(&"monsters_killed", 0))
		
	if seed_util:
		seed_util.set_state(state_to_restore.get(&"rng_state", 0))
		
	if rule_sys and state_to_restore.has(&"rules_states"):
		var rules_states: Array = state_to_restore[&"rules_states"]
		var all_rules: Array[SpawnRule] = rule_sys.get_all_spawn_rules()
		for i in range(min(all_rules.size(), rules_states.size())):
			all_rules[i].set_state(rules_states[i])
