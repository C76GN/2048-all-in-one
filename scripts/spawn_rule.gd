# scripts/spawn_rule.gd

## SpawnRule: 方块生成规则的基类蓝图。
##
## 所有具体的生成逻辑（如定时生成、随机生成）都应继承此类。
class_name SpawnRule
extends Node

# --- 信号定义 ---

## 当此规则决定要生成一个新方块时发出。
@warning_ignore("unused_signal")
signal spawn_tile_requested(spawn_data: Dictionary)
