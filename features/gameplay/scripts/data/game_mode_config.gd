## GameModeConfig: 一个用于定义完整游戏模式的自定义资源。
##
## 它像一个配置单，将各种独立的规则组件（Interaction, Spawn等）组合在一起，
## 形成一个完整的玩法。
class_name GameModeConfig
extends Resource


# --- 导出变量 ---

@export_group("基本信息")
## 在UI上显示的模式名称。
@export var mode_name: String = "未命名模式"

## 只描述玩法语义的稳定规则集 ID，不随显示名称或主题变化。
@export var ruleset_id: StringName = &""

## 任意会改变确定性结算结果的规则修改都必须递增该版本。
@export_range(1, 2147483647, 1) var ruleset_version: int = 1

## 在模式选择界面和游戏HUD中显示的玩法说明。
@export_multiline var mode_description: String = ""

@export_group("规则配置")
## 方块如何交互（相加、求商、变换等）的规则。
@export var interaction_rule: InteractionRule

## 方块如何移动（经典滑动、步进等）的规则。
@export var movement_rule: MovementRule

## 包含此模式所有"生成规则"资源的数组。
@export var spawn_rules: Array[SpawnRule]

## 游戏如何结束的规则。
@export var game_over_rule: GameOverRule

@export_group("视觉主题")
## 一个字典，用于存储 TileDefinition.color_scheme_index 对应的配色方案。
@export var color_schemes: Dictionary = {}

## 棋盘和背景的视觉主题。
@export var board_theme: BoardTheme

@export_group("棋盘配置")
## 本模式允许创建的棋盘空间模板。
@export var board_topology_template: BoardTopologyTemplate

@export_group("目标配置")
## 本模式用于统计目标达成的最高方块值；为 0 表示暂不定义目标。
@export var target_tile_value: int = 0


# --- 公共方法 ---

## 校验本配置是否完整有效，在游戏启动前调用。
##
## @return: 如果所有关键规则均已配置则返回 true，否则 push_error 并返回 false。
func validate() -> bool:
	var report: GFValidationReport = get_validation_report()
	if report.is_ok():
		return true

	for issue: GFValidationIssue in report.issues:
		if issue != null and issue.is_error():
			push_error("[GameModeConfig:%s] %s" % [mode_name, issue.message])
	return false


## 生成本配置的 gf 校验报告。
## @return: 包含所有配置问题的 GFValidationReport。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameModeConfig:%s" % mode_name,
		{
			"mode_name": mode_name,
			"resource_path": resource_path,
		}
	)
	if ruleset_id == &"":
		_add_config_error(report, &"missing_ruleset_id", "ruleset_id 不能为空。", &"ruleset_id")
	if ruleset_version <= 0:
		_add_config_error(
			report,
			&"invalid_ruleset_version",
			"ruleset_version 必须大于 0。",
			&"ruleset_version"
		)

	if not is_instance_valid(interaction_rule):
		_add_config_error(report, &"missing_interaction_rule", "interaction_rule 未配置。", &"interaction_rule")
	elif not interaction_rule.get_tile_definition_validation_report().is_ok():
		_add_config_error(
			report,
			&"invalid_tile_definitions",
			"interaction_rule 的 TileDefinition 或 GF Capability Recipe 校验失败。",
			&"interaction_rule"
		)

	if not is_instance_valid(movement_rule):
		_add_config_error(report, &"missing_movement_rule", "movement_rule 未配置。", &"movement_rule")

	if spawn_rules.is_empty():
		_add_config_error(report, &"empty_spawn_rules", "spawn_rules 为空，游戏将无法生成方块。", &"spawn_rules")

	for i: int in range(spawn_rules.size()):
		if not is_instance_valid(spawn_rules[i]):
			_add_config_error(
				report,
				&"missing_spawn_rule",
				"spawn_rules[%d] 未配置。" % i,
				"spawn_rules/%d" % i
			)
			continue
		var spawn_rule: SpawnRule = spawn_rules[i]
		var _merged_spawn_report: RefCounted = report.merge(
			spawn_rule.get_validation_report(),
			false
		)
		if is_instance_valid(interaction_rule):
			for definition_id: StringName in spawn_rule.get_referenced_definition_ids():
				if interaction_rule.get_tile_definition(definition_id) == null:
					_add_config_error(
						report,
						&"unknown_spawn_definition_id",
						"spawn_rules[%d] 引用了当前模式未声明的 definition_id：%s。" % [
							i,
							definition_id,
						],
						"spawn_rules/%d" % i
					)

	if not is_instance_valid(game_over_rule):
		_add_config_error(report, &"missing_game_over_rule", "game_over_rule 未配置。", &"game_over_rule")

	if not is_instance_valid(board_theme):
		_add_config_error(report, &"missing_board_theme", "board_theme 未配置。", &"board_theme")

	if not is_instance_valid(board_topology_template):
		_add_config_error(
			report,
			&"missing_board_topology_template",
			"board_topology_template 未配置。",
			&"board_topology_template"
		)
	else:
		var _merged_topology_report: RefCounted = report.merge(
			board_topology_template.get_validation_report(),
			false
		)

	if target_tile_value < 0:
		_add_config_error(report, &"invalid_target_tile_value", "target_tile_value 不能小于 0。", &"target_tile_value")

	return report


## 当前模式是否定义了可统计的目标。
func has_target() -> bool:
	return target_tile_value > 0


## 根据当前最高方块值判断是否达成目标。
## @param max_tile_value: 本局达到的最高方块值。
func is_target_reached(max_tile_value: int) -> bool:
	return has_target() and max_tile_value >= target_tile_value


# --- 私有/辅助方法 ---

func _add_config_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
