# global/game_mode_config.gd

## GameModeConfig: 一个用于定义完整游戏模式的自定义资源。
##
## 它像一个配置单，将各种独立的规则组件（Interaction, Spawn等）组合在一起，
## 形成一个完整的玩法。
class_name GameModeConfig
extends Resource

@export var mode_name: String = "未命名模式"

## 方块如何交互（合并、战斗等）的规则。
@export var interaction_rule: InteractionRule

## 指向“如何生成新方块”规则的脚本文件列表。
@export var spawn_rule_scripts: Array[Script]

## 游戏如何结束的规则。
@export var game_over_rule: GameOverRule
