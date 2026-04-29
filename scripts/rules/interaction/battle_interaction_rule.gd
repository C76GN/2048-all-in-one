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
## @param _p_rule: 对当前交互规则实例的引用。
## @return: 一个描述交互结果的字典。
func process_interaction(tile_a: GameTileData, tile_b: GameTileData, _p_rule: InteractionRule) -> Dictionary:
	if tile_a.type == tile_b.type:
		if tile_a.value == tile_b.value:
			var new_value: int = tile_a.value * 2
			tile_b.value = new_value
			tile_b.type = tile_a.type

			if tile_a.type == Tile.TileType.PLAYER:
				return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}

			return {"merged_tile": tile_b, "consumed_tile": tile_a}

	else:
		var player_tile: GameTileData = tile_a if tile_a.type == Tile.TileType.PLAYER else tile_b
		var monster_tile: GameTileData = tile_a if tile_a.type == Tile.TileType.MONSTER else tile_b

		if player_tile.value > monster_tile.value:
			@warning_ignore("integer_division")
			var new_player_value: int = int(player_tile.value / monster_tile.value)
			player_tile.value = new_player_value
			# Note: animate_transform() and queue_free() are visual/Node operations.
			# We return the instruction, and GameBoard will perform the visual effects.
			return {
				"merged_tile": player_tile,
				"consumed_tile": monster_tile,
				"score": new_player_value,
				"monster_killed": 1,
				"transform": true,
			}

		elif player_tile.value < monster_tile.value:
			@warning_ignore("integer_division")
			var new_monster_value: int = int(monster_tile.value / player_tile.value)
			monster_tile.value = new_monster_value
			return {"merged_tile": monster_tile, "consumed_tile": player_tile, "score": - new_monster_value, "transform": true}

		else:
			var destination_was_player: bool = (tile_b.type == Tile.TileType.PLAYER)
			tile_b.value = 1
			
			if destination_was_player:
				var player_win_result := {
					"merged_tile": tile_b,
					"consumed_tile": tile_a,
					"score": 1,
					"transform": true,
				}
				if tile_a.type == Tile.TileType.MONSTER:
					player_win_result["monster_killed"] = 1
				return player_win_result

			var monster_win_result := {
				"merged_tile": tile_b,
				"consumed_tile": tile_a,
				"score": - 1,
				"transform": true,
			}
			if tile_a.type == Tile.TileType.MONSTER:
				monster_win_result["monster_killed"] = 1
			return monster_win_result

	return {}


## 检查两个方块是否具备交互的可能性，但不实际执行交互。
##
## 此函数是 GameOverRule 的主要查询接口，用于判断在棋盘满时是否还有可移动的步骤。
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果两个方块可以发生交互，则返回 true；否则返回 false。
func can_interact(tile_a: GameTileData, tile_b: GameTileData) -> bool:
	if tile_a == null or tile_b == null:
		return false

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
	var level: int = int(log(value) / log(2))
	return max(0, level)


## 获取此规则下所有可生成的方块"类型"。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
func get_spawnable_types() -> Dictionary:
	return {
		Tile.TileType.PLAYER: tr("RULE_PLAYER"),
		Tile.TileType.MONSTER: tr("RULE_MONSTER")
	}


## 根据指定的类型ID，获取所有可生成的方块"数值"。
##
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	var values: Array[int] = []
	var current_power_of_two: int = 2
	while current_power_of_two <= 8192:
		values.append(current_power_of_two)
		current_power_of_two *= 2
	return values


## 将战斗模式相关的HUD显示数据写入传入的 stats 对象。
##
## @param context: 包含当前游戏统计信息的 Dictionary 对象。
## @param stats: 要写入显示数据的 Dictionary 对象。
func get_hud_stats(context: Dictionary, stats: Dictionary) -> void:
	var monsters_killed: int = context.get(&"monsters_killed", 0)
	if monsters_killed >= 0:
		stats[&"monsters_killed_display"] = tr("BATTLE_KILLED_DISPLAY") % monsters_killed
