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
	if not is_instance_valid(interaction_rule):
		push_error("GameModeConfig[%s]: interaction_rule 未配置！" % mode_name)
		return false

	if not is_instance_valid(movement_rule):
		push_error("GameModeConfig[%s]: movement_rule 未配置！" % mode_name)
		return false

	if spawn_rules.is_empty():
		push_error("GameModeConfig[%s]: spawn_rules 为空，游戏将无法生成方块！" % mode_name)
		return false

	for i in range(spawn_rules.size()):
		if not is_instance_valid(spawn_rules[i]):
			push_error("GameModeConfig[%s]: spawn_rules[%d] 未配置！" % [mode_name, i])
			return false

	if not is_instance_valid(game_over_rule):
		push_error("GameModeConfig[%s]: game_over_rule 未配置！" % mode_name)
		return false

	if not is_instance_valid(board_theme):
		push_error("GameModeConfig[%s]: board_theme 未配置！" % mode_name)
		return false

	if min_grid_size <= 0:
		push_error("GameModeConfig[%s]: min_grid_size 必须大于 0！" % mode_name)
		return false

	if min_grid_size > max_grid_size:
		push_error("GameModeConfig[%s]: min_grid_size 不能大于 max_grid_size！" % mode_name)
		return false

	if default_grid_size < min_grid_size or default_grid_size > max_grid_size:
		push_error(
			"GameModeConfig[%s]: default_grid_size 必须位于 [%d, %d] 范围内！"
			% [mode_name, min_grid_size, max_grid_size]
		)
		return false

	return true
