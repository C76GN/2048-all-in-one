## GetHudStatsQuery: 汇总 HUD 需要展示的动态统计数据。
##
## 该查询只读取 Model、System 和 Utility，不修改任何运行时状态。
class_name GetHudStatsQuery
extends GFQuery


# --- 公共方法 ---

## 执行 HUD 统计数据查询。
## @return: 动态统计数据字典。
func execute() -> Variant:
	var stats: Dictionary = {}
	var grid_model := get_model(GridModel) as GridModel
	var status_model := get_model(GameStatusModel) as GameStatusModel

	if is_instance_valid(grid_model) and is_instance_valid(status_model):
		_collect_interaction_stats(grid_model, status_model, stats)
		_collect_spawn_rule_stats(grid_model, stats)

		var external_extra: Dictionary = status_model.extra_stats.get_value()
		stats.merge(external_extra)

	var seed_utility := get_utility(GFSeedUtility) as GFSeedUtility
	if is_instance_valid(seed_utility):
		stats[&"seed_info"] = tr("SEED_INFO_LABEL") % seed_utility.get_global_seed()

	return stats


# --- 私有/辅助方法 ---

func _collect_interaction_stats(
	grid_model: GridModel,
	status_model: GameStatusModel,
	stats: Dictionary
) -> void:
	var interaction_rule := grid_model.interaction_rule
	if not is_instance_valid(interaction_rule):
		return

	var player_values_set: Dictionary = {}
	for value in grid_model.get_all_player_tile_values():
		player_values_set[value] = true

	var context: Dictionary = {
		&"max_player_value": status_model.highest_tile.get_value(),
		&"monsters_killed": status_model.monsters_killed.get_value(),
		&"player_values_set": player_values_set,
	}
	interaction_rule.get_hud_stats(context, stats)


func _collect_spawn_rule_stats(grid_model: GridModel, stats: Dictionary) -> void:
	var rule_system := get_system(RuleSystem) as RuleSystem
	if not is_instance_valid(rule_system):
		return

	var rule_context := RuleContext.new()
	rule_context.grid_model = grid_model

	for rule in rule_system.get_all_spawn_rules():
		rule.get_hud_stats(rule_context, stats)
