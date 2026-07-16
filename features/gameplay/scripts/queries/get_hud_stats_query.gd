## GetHudStatsQuery: 汇总 HUD 需要展示的动态统计数据。
##
## 该查询只读取 Model、System 和 Utility，不修改任何运行时状态。
class_name GetHudStatsQuery
extends "res://addons/gf/kernel/base/gf_query.gd"


# --- 常量 ---

const _SEED_INFO_FORMAT_FALLBACK: String = "游戏种子: %d"


# --- 公共方法 ---

## 执行 HUD 统计数据查询。
## @return: 动态统计数据字典。
func execute() -> Variant:
	var stats: Dictionary = {}
	var grid_model: GridModel = _get_grid_model()
	var status_model: GameStatusModel = _get_status_model()

	if is_instance_valid(grid_model) and is_instance_valid(status_model):
		_collect_interaction_stats(grid_model, status_model, stats)
		_collect_spawn_rule_stats(grid_model, stats)

		var external_extra: Dictionary = GFVariantData.to_dictionary(status_model.extra_stats.get_value(), {})
		stats.merge(external_extra)

	var seed_utility: GFSeedUtility = _get_seed_utility()
	if is_instance_valid(seed_utility):
		stats[&"seed_info"] = GameTextFormatUtility.format_template(
			tr("SEED_INFO_LABEL"),
			_SEED_INFO_FORMAT_FALLBACK,
			[seed_utility.get_global_seed()]
		)

	return stats


# --- 私有/辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null


func _collect_interaction_stats(
	grid_model: GridModel,
	status_model: GameStatusModel,
	stats: Dictionary
) -> void:
	var interaction_rule: InteractionRule = grid_model.interaction_rule
	if not is_instance_valid(interaction_rule):
		return

	var tile_values_set: Dictionary = {}
	for value: int in grid_model.get_all_tile_values():
		tile_values_set[value] = true

	var max_tile_value: int = GFVariantData.to_int(status_model.highest_tile.get_value(), 0)
	var ratio_resolutions: int = GFVariantData.to_int(status_model.ratio_resolutions.get_value(), 0)
	var context: Dictionary = {
		&"max_tile_value": max_tile_value,
		&"ratio_resolutions": ratio_resolutions,
		&"tile_values_set": tile_values_set,
	}
	interaction_rule.get_hud_stats(context, stats)


func _collect_spawn_rule_stats(grid_model: GridModel, stats: Dictionary) -> void:
	var rule_system: RuleSystem = _get_rule_system()
	if not is_instance_valid(rule_system):
		return

	var rule_context: RuleContext = RuleContext.new()
	rule_context.grid_model = grid_model

	for rule: SpawnRule in rule_system.get_all_spawn_rules():
		rule.get_hud_stats(rule_context, stats)
