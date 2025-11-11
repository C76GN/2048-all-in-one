# scripts/global/game_mode_config.gd

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

## 包含此模式所有“生成规则”资源的数组。
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
