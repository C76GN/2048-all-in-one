# scripts/modes/battle_interaction_rule.gd

## BattleInteractionRule: "测试模式1"中使用的具体交互规则。
##
## 实现了玩家方块合并、怪物方块合并以及玩家与怪物之间的战斗逻辑。
class_name BattleInteractionRule
extends InteractionRule

## 处理两个方块之间的交互。
##
## @return: 返回一个字典，描述交互结果，例如 {"merged_tile": Tile, "consumed_tile": Tile}
func process_interaction(tile_a: Tile, tile_b: Tile) -> Dictionary:
	# 情况A: 两个方块类型相同
	if tile_a.type == tile_b.type:
		if tile_a.value == tile_b.value:
			tile_b.setup(tile_a.value * 2, tile_a.type)
			tile_a.queue_free()
			return {"merged_tile": tile_b, "consumed_tile": tile_a}
	
	# 情况B: 两个方块类型不同（战斗）
	else:
		var player_tile = tile_a if tile_a.type == Tile.TileType.PLAYER else tile_b
		var monster_tile = tile_a if tile_a.type == Tile.TileType.MONSTER else tile_b
		
		if player_tile.value > monster_tile.value:
			player_tile.setup(int(player_tile.value / monster_tile.value), player_tile.type)
			monster_tile.queue_free()
			monster_killed.emit()
			return {"merged_tile": player_tile, "consumed_tile": monster_tile}
		elif player_tile.value < monster_tile.value:
			monster_tile.setup(int(monster_tile.value / player_tile.value), monster_tile.type)
			player_tile.queue_free()
			return {"merged_tile": monster_tile, "consumed_tile": player_tile}
		else: # 同归于尽
			player_tile.queue_free()
			monster_tile.queue_free()
			monster_killed.emit()
			return {"merged_tile": null, "consumed_tile": [player_tile, monster_tile]}

	return {} # 没有发生交互

## 检查两个方块是否具备交互的可能性，但不实际执行交互。
##
## 这个函数是 GameOverRule 的主要查询接口，用于判断在棋盘满时是否还有可移动的步骤。
## 它只做“可能性”的判断，具体的交互结果由 process_interaction 处理。
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果两个方块可以发生交互，则返回 true；否则返回 false。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	# 安全检查：如果任何一个方块不存在，则不可能交互。
	if tile_a == null or tile_b == null:
		return false
	
	# 根据 BattleInteractionRule 的规则进行判断：
	# 1. 如果方块类型不同 (PLAYER vs MONSTER)，则总能发生战斗，所以可以交互。
	# 2. 如果方块类型相同，则只有当它们的数值相等时才能合并，此时可以交互。
	if tile_a.type != tile_b.type or tile_a.value == tile_b.value:
		return true
		
	# 如果不满足以上任何条件，则这两个方块无法交互。
	return false
