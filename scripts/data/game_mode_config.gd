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

## 在模式选择界面和游戏HUD中显示的玩法说明。
@export_multiline var mode_description: String = ""

@export_group("规则配置")
## 方块如何交互（合并、战斗等）的规则。
@export var interaction_rule: InteractionRule

## 方块如何移动（经典滑动、步进等）的规则。
@export var movement_rule: MovementRule

## 包含此模式所有"生成规则"资源的数组。
@export var spawn_rules: Array[SpawnRule]

## 游戏如何结束的规则。
@export var game_over_rule: GameOverRule

@export_group("视觉主题")
## 一个字典，用于存储不同方块类型（Tile.TileType）对应的配色方案。
@export var color_schemes: Dictionary = {}

## 棋盘和背景的视觉主题。
@export var board_theme: BoardTheme

@export_group("棋盘配置")
## 模式默认的棋盘大小。
@export var default_grid_size: int = 4

## 此模式支持的最小棋盘大小。
@export var min_grid_size: int = 3

## 此模式支持的最大棋盘大小。
@export var max_grid_size: int = 8


# --- 公共方法 ---

## 校验本配置是否完整有效，在游戏启动前调用。
##
## @return: 如果所有关键规则均已配置则返回 true，否则 push_error 并返回 false。
func validate() -> bool:
	var report := get_validation_report()
	if report.is_ok():
		return true

	for issue: GFValidationIssue in report.issues:
		if issue != null and issue.is_error():
			push_error("[GameModeConfig:%s] %s" % [mode_name, issue.message])
	return false


## 生成本配置的 gf 校验报告。
## @return: 包含所有配置问题的 GFValidationReport。
func get_validation_report() -> GFValidationReport:
	var report := GFValidationReport.new(
		"GameModeConfig:%s" % mode_name,
		{
			"mode_name": mode_name,
			"resource_path": resource_path,
		}
	) as GFValidationReport

	if not is_instance_valid(interaction_rule):
		report.add_error(&"missing_interaction_rule", "interaction_rule 未配置。", &"interaction_rule", resource_path)

	if not is_instance_valid(movement_rule):
		report.add_error(&"missing_movement_rule", "movement_rule 未配置。", &"movement_rule", resource_path)

	if spawn_rules.is_empty():
		report.add_error(&"empty_spawn_rules", "spawn_rules 为空，游戏将无法生成方块。", &"spawn_rules", resource_path)

	for i in range(spawn_rules.size()):
		if not is_instance_valid(spawn_rules[i]):
			report.add_error(
				&"missing_spawn_rule",
				"spawn_rules[%d] 未配置。" % i,
				"spawn_rules/%d" % i,
				resource_path
			)

	if not is_instance_valid(game_over_rule):
		report.add_error(&"missing_game_over_rule", "game_over_rule 未配置。", &"game_over_rule", resource_path)

	if not is_instance_valid(board_theme):
		report.add_error(&"missing_board_theme", "board_theme 未配置。", &"board_theme", resource_path)

	if min_grid_size <= 0:
		report.add_error(&"invalid_min_grid_size", "min_grid_size 必须大于 0。", &"min_grid_size", resource_path)

	if min_grid_size > max_grid_size:
		report.add_error(
			&"invalid_grid_size_range",
			"min_grid_size 不能大于 max_grid_size。",
			&"min_grid_size",
			resource_path
		)

	if default_grid_size < min_grid_size or default_grid_size > max_grid_size:
		report.add_error(
			&"invalid_default_grid_size",
			"default_grid_size 必须位于 [%d, %d] 范围内。" % [min_grid_size, max_grid_size],
			&"default_grid_size",
			resource_path
		)

	return report
