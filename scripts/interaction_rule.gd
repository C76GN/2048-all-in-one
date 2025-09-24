# scripts/interaction_rule.gd

## InteractionRule: 方块交互规则的基类蓝图。
##
## 所有具体的交互逻辑（如合并、战斗）都应继承此类。
## 它本身不包含任何逻辑，仅用于类型定义。
class_name InteractionRule
extends Resource

# --- 信号定义 ---

## 处理两个方块之间的交互。
## 具体的规则需要重写此方法。
func process_interaction(_tile_a: Tile, _tile_b: Tile, _p_rule: InteractionRule, _p_player_scheme: TileColorScheme, _p_monster_scheme: TileColorScheme) -> Dictionary:
	return {} # 默认不交互不交互

## 当一个怪物在交互中被消灭时发出。
@warning_ignore("unused_signal")
signal monster_killed

# 判断两个方块是否可以发生交互，但不实际执行。
# 具体的规则需要重写此方法。
func can_interact(_tile_a: Tile, _tile_b: Tile) -> bool:
	return false # 默认不能交互

## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
## 例如，在经典模式中，2->0, 4->1, 8->2。
## 子类需要重写此方法。
func get_level_by_value(_value: int) -> int:
	return 0
