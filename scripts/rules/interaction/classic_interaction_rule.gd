# scripts/rules/interaction/classic_interaction_rule.gd

## ClassicInteractionRule: 经典的2048方块交互规则。
##
## 规则定义：
## 1. 只有类型为 PLAYER 的方块可以交互。
## 2. 只有当两个 PLAYER 方块的数值相同时，它们才能合并。
## 3. 合并后，一个方块的数值翻倍，另一个方块被销毁。
class_name ClassicInteractionRule
extends InteractionRule


# --- 公共方法 ---

## 处理两个方块之间的合并交互。
##
## @param tile_a: 参与交互的第一个方块。
## @param tile_b: 参与交互的第二个方块（通常是移动的目标方块）。
## @param p_rule: 对当前交互规则实例的引用。
## @return: 一个描述交互结果的字典。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	# 经典模式下，只处理玩家方块之间的交互。
	if tile_a.type == Tile.TileType.PLAYER and tile_b.type == Tile.TileType.PLAYER:
		# 只有当数值相同时才合并。
		if tile_a.value == tile_b.value:
			var new_value: int = tile_a.value * 2
			# 将 tile_b 的数值翻倍
			tile_b.setup(new_value, tile_a.type, p_rule, tile_a.color_schemes)
			# 返回结果，动画系统将根据 "consumed_tile" 来处理 tile_a 的销毁。
			return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}

	# 如果不满足上述条件，则不发生任何交互。
	return {}


## 判断两个方块是否具备可交互性（用于游戏结束的判断）。
##
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果可以交互则返回 true。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if not is_instance_valid(tile_a) or not is_instance_valid(tile_b):
		return false

	# 只有同为玩家方块且数值相等时，才认为它们可以交互。
	if (tile_a.type == Tile.TileType.PLAYER
		and tile_b.type == Tile.TileType.PLAYER
		and tile_a.value == tile_b.value
	):
		return true

	return false


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	# 等级是基于2的对数计算的。
	var level: int = int(log(value) / log(2)) - 1
	return max(0, level)


## 获取此规则下所有可生成的方块“类型”。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
func get_spawnable_types() -> Dictionary:
	return {Tile.TileType.PLAYER: "玩家"}


## 根据指定的类型ID，获取所有可生成的方块“数值”。
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
