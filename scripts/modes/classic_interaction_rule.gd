# scripts/modes/classic_interaction_rule.gd

## ClassicInteractionRule: 经典的2048方块交互规则。
##
## 规则定义：
## 1. 只有类型为 PLAYER 的方块可以交互。
## 2. 只有当两个 PLAYER 方块的数值相同时，它们才能合并。
## 3. 合并后，一个方块的数值翻倍，另一个方块被销毁。
class_name ClassicInteractionRule
extends InteractionRule

## 处理两个方块之间的合并交互。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	# 经典模式下，只处理玩家方块之间的交互。
	if tile_a.type == Tile.TileType.PLAYER and tile_b.type == Tile.TileType.PLAYER:
		# 只有当数值相同时才合并。
		if tile_a.value == tile_b.value:
			# 将 tile_b 的数值翻倍，并销毁 tile_a。
			tile_b.setup(tile_a.value * 2, tile_a.type, p_rule, tile_a.color_schemes)
			tile_a.queue_free()
			# 返回结果，表明 tile_b 是合并后的方块，tile_a 是被消耗的方块。
			return {"merged_tile": tile_b, "consumed_tile": tile_a}
	
	# 如果不满足上述条件，则不发生任何交互。
	return {}

## 判断两个方块是否具备可交互性（用于游戏结束的判断）。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if tile_a == null or tile_b == null:
		return false
	
	# 同样，只有同为玩家方块且数值相等时，才认为它们可以交互。
	if tile_a.type == Tile.TileType.PLAYER and tile_b.type == Tile.TileType.PLAYER and tile_a.value == tile_b.value:
		return true
		
	return false

## 对于经典模式，等级是基于2的对数计算的。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	var level = int(log(value) / log(2)) - 1
	return max(0, level)
