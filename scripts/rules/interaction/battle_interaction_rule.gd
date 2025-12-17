# scripts/rules/interaction/battle_interaction_rule.gd

## BattleInteractionRule: "战斗模式"中使用的具体交互规则。
##
## 实现了玩家方块合并、怪物方块合并以及玩家与怪物之间的战斗逻辑。
class_name BattleInteractionRule
extends InteractionRule


# --- 公共方法 ---

## 处理两个方块之间的交互。
##
## @param tile_a: 参与交互的第一个方块。
## @param tile_b: 参与交互的第二个方块（通常是移动的目标方块）。
## @param p_rule: 对当前交互规则实例的引用。
## @return: 一个描述交互结果的字典。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	# 情况A: 两个方块类型相同，进行合并。
	if tile_a.type == tile_b.type:
		if tile_a.value == tile_b.value:
			var new_value: int = tile_a.value * 2
			tile_b.setup(new_value, tile_a.type, p_rule, tile_a.color_schemes)

			# 仅当玩家方块合并时，获得新方块数值的分数。
			if tile_a.type == Tile.TileType.PLAYER:
				return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}

			# 怪物方块合并不得分。
			return {"merged_tile": tile_b, "consumed_tile": tile_a}

	# 情况B: 两个方块类型不同，进行战斗。
	else:
		var player_tile: Tile = tile_a if tile_a.type == Tile.TileType.PLAYER else tile_b
		var monster_tile: Tile = tile_a if tile_a.type == Tile.TileType.MONSTER else tile_b

		# 玩家胜利
		if player_tile.value > monster_tile.value:
			@warning_ignore("integer_division")
			var new_player_value: int = int(player_tile.value / monster_tile.value)
			player_tile.setup(new_player_value, player_tile.type, p_rule, player_tile.color_schemes)
			player_tile.animate_transform()
			monster_tile.queue_free()
			EventBus.monster_killed.emit()
			return {"merged_tile": player_tile, "consumed_tile": monster_tile, "score": new_player_value}

		# 玩家失败
		elif player_tile.value < monster_tile.value:
			@warning_ignore("integer_division")
			var new_monster_value: int = int(monster_tile.value / player_tile.value)
			monster_tile.setup(new_monster_value, monster_tile.type, p_rule, monster_tile.color_schemes)
			monster_tile.animate_transform()
			player_tile.queue_free()
			return {"merged_tile": monster_tile, "consumed_tile": player_tile, "score": -new_monster_value}

		# 双方数值相同，同归于尽
		else:
			var destination_tile_was_player: bool = (tile_b.type == Tile.TileType.PLAYER)

			tile_b.setup(1, tile_b.type, p_rule, tile_b.color_schemes)
			tile_b.animate_transform()

			if tile_a.type == Tile.TileType.MONSTER:
				EventBus.monster_killed.emit()

			# 根据幸存方块的最终归属决定得分或扣分。
			if destination_tile_was_player:
				return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": 1}
			else:
				return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": -1}

	return {}


## 检查两个方块是否具备交互的可能性，但不实际执行交互。
##
## 此函数是 GameOverRule 的主要查询接口，用于判断在棋盘满时是否还有可移动的步骤。
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果两个方块可以发生交互，则返回 true；否则返回 false。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if not is_instance_valid(tile_a) or not is_instance_valid(tile_b):
		return false

	# 规则:
	# 1. 如果方块类型不同 (PLAYER vs MONSTER)，总能发生战斗。
	# 2. 如果方块类型相同，只有当它们的数值相等时才能合并。
	if tile_a.type != tile_b.type or tile_a.value == tile_b.value:
		return true

	return false


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	# 等级基于2的对数计算
	var level: int = int(log(value) / log(2))
	return max(0, level)


## 获取此规则下所有可生成的方块“类型”。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
func get_spawnable_types() -> Dictionary:
	return {
		Tile.TileType.PLAYER: tr("RULE_PLAYER"),
		Tile.TileType.MONSTER: tr("RULE_MONSTER")
	}


## 根据指定的类型ID，获取所有可生成的方块“数值”。
##
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	# 在这个模式中，玩家和怪物都遵循2的幂次方规则。
	var values: Array[int] = []
	var current_power_of_two: int = 2
	while current_power_of_two <= 8192:
		values.append(current_power_of_two)
		current_power_of_two *= 2
	return values


## 获取此规则相关的、用于HUD显示的原始上下文数据。
##
## @param context: 包含当前游戏状态的字典。
## @return: 一个包含战斗模式特定显示信息的字典。
func get_hud_context_data(context: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {}
	if context.has("monsters_killed"):
		data["monsters_killed_display"] = tr("BATTLE_KILLED_DISPLAY") % context["monsters_killed"]
	return data
