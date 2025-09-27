# scripts/modes/battle_interaction_rule.gd

## BattleInteractionRule: "测试模式1"中使用的具体交互规则。
##
## 实现了玩家方块合并、怪物方块合并以及玩家与怪物之间的战斗逻辑。
class_name BattleInteractionRule
extends InteractionRule

## 处理两个方块之间的交互。
##
## @return: 返回一个字典，描述交互结果，例如 {"merged_tile": Tile, "consumed_tile": Tile}
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	# 情况A: 两个方块类型相同
	if tile_a.type == tile_b.type:
		if tile_a.value == tile_b.value:
			tile_b.setup(tile_a.value * 2, tile_a.type, p_rule, tile_a.color_schemes)
			tile_a.queue_free()
			return {"merged_tile": tile_b, "consumed_tile": tile_a}
	
	# 情况B: 两个方块类型不同（战斗）
	else:
		var player_tile = tile_a if tile_a.type == Tile.TileType.PLAYER else tile_b
		var monster_tile = tile_a if tile_a.type == Tile.TileType.MONSTER else tile_b
		
		if player_tile.value > monster_tile.value:
			player_tile.setup(int(player_tile.value / monster_tile.value), player_tile.type, p_rule, player_tile.color_schemes)
			player_tile.animate_transform()
			monster_tile.queue_free()
			EventBus.monster_killed.emit()
			return {"merged_tile": player_tile, "consumed_tile": monster_tile}
		elif player_tile.value < monster_tile.value:
			monster_tile.setup(int(monster_tile.value / player_tile.value), monster_tile.type, p_rule, monster_tile.color_schemes)
			monster_tile.animate_transform()
			player_tile.queue_free()
			return {"merged_tile": monster_tile, "consumed_tile": player_tile}
		else: 
			tile_b.setup(1, tile_b.type, p_rule, tile_b.color_schemes)
			tile_b.animate_transform()
			tile_a.queue_free()
			if tile_a.type == Tile.TileType.MONSTER:
				EventBus.monster_killed.emit()
			return {"merged_tile": tile_b, "consumed_tile": tile_a}

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

## 对于战斗模式，等级基于2的对数计算。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	var level = int(log(value) / log(2))
	return max(0, level)

## 获取此规则下所有可生成的方块“类型”。
func get_spawnable_types() -> Dictionary:
	return {
		Tile.TileType.PLAYER: "玩家",
		Tile.TileType.MONSTER: "怪物"
	}

## 根据指定的类型ID，获取所有可生成的方块“数值”。
func get_spawnable_values(_type_id: int) -> Array[int]:
	# 在这个模式中，玩家和怪物都遵循2的幂次方规则
	var values: Array[int] = []
	var current_power_of_two = 2
	while current_power_of_two <= 8192:
		values.append(current_power_of_two)
		current_power_of_two *= 2
	return values

## 获取用于在HUD上显示的原始上下文数据。
## @param context: 包含当前游戏状态的字典。
## @return: 一个包含战斗模式特定原始信息的字典。
func get_hud_context_data(context: Dictionary = {}) -> Dictionary:
	var data = {}
	if context.has("monsters_killed"):
		# 只返回原始数据，让上层去格式化
		data["monsters_killed"] = context["monsters_killed"]
	return data
