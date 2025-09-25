# global/game_mode_config.gd

## GameModeConfig: 一个用于定义完整游戏模式的自定义资源。
##
## 它像一个配置单，将各种独立的规则组件（Interaction, Spawn等）组合在一起，
## 形成一个完整的玩法。
class_name GameModeConfig
extends Resource

@export var mode_name: String = "未命名模式"

@export_multiline var mode_description: String = ""

## 方块如何交互（合并、战斗等）的规则。
@export var interaction_rule: InteractionRule

## 一个字典，用于存储不同方块类型（Tile.TileType）对应的配色方案。
@export var color_schemes: Dictionary = {}

## 包含此模式所有“生成规则”资源的数组。
@export var spawn_rules: Array[SpawnRule]

## 游戏如何结束的规则。
@export var game_over_rule: GameOverRule

## 棋盘和背景的视觉主题。
@export var board_theme: BoardTheme
