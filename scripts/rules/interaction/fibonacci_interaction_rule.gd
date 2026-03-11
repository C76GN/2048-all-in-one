# scripts/rules/interaction/fibonacci_interaction_rule.gd

## FibonacciInteractionRule: 斐波那契数列的2048方块交互规则。
##
## 规则定义：
## 1. 只有类型为 PLAYER 的方块可以交互。
## 2. 两个数值为 1 的方块可以合并成 2。
## 3. 两个数值在斐波那契数列中相邻的方块可以合并成它们的和。
##    (例如: 1+2=3, 2+3=5, 3+5=8, ...)
class_name FibonacciInteractionRule
extends InteractionRule


# --- 公共方法 ---

## 处理两个方块之间的合并交互。
##
## @param tile_a: 参与交互的第一个方块。
## @param tile_b: 参与交互的第二个方块（通常是移动的目标方块）。
## @param _p_rule: 对当前交互规则实例的引用。
## @return: 一个描述交互结果的字典。
func process_interaction(tile_a: GameTileData, tile_b: GameTileData, _p_rule: InteractionRule) -> Dictionary:
	if can_interact(tile_a, tile_b):
		var new_value: int = tile_a.value + tile_b.value
		tile_b.value = new_value
		return {&"merged_tile": tile_b, &"consumed_tile": tile_a, &"score": new_value}

	return {}


## 判断两个方块是否具备可交互性（用于游戏结束的判断）。
##
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果可以交互则返回 true。
func can_interact(tile_a: GameTileData, tile_b: GameTileData) -> bool:
	if tile_a == null or tile_b == null:
		return false

	if tile_a.type != Tile.TileType.PLAYER or tile_b.type != Tile.TileType.PLAYER:
		return false

	if SequenceMath.are_consecutive_fibonacci(tile_a.value, tile_b.value):
		return true

	return false


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	return SequenceMath.get_fibonacci_level(value)


## 将斐波那契模式相关的HUD显示数据写入传入的 stats 字典。
##
## @param context: 包含当前游戏统计信息的 Dictionary 对象。
## @param stats: 要写入显示数据的 Dictionary 对象。
func get_hud_stats(context: Dictionary, stats: Dictionary) -> void:
	var max_value: int = context.get(&"max_player_value", 0)
	var player_values_set: Dictionary = context.get(&"player_values_set", {})

	var max_display_value: int = 5 + max_value * 2
	var full_sequence := SequenceMath.generate_fibonacci()
	var display_sequence: Array[int] = []

	for num in full_sequence:
		display_sequence.append(num)
		if num > max_display_value:
			break

	var fib_data_for_ui: Array[Dictionary] = [ {&"text": tr("LABEL_SYNTH_SEQ"), &"color": Color.WHITE}]
	for num in display_sequence:
		var item: Dictionary = {&"text": str(num), &"color": Color.GRAY}
		if player_values_set.has(num):
			item[&"color"] = Color.WHITE
		fib_data_for_ui.append(item)

	stats[&"fibonacci_sequence_display"] = fib_data_for_ui


## 获取此规则下所有可生成的方块"类型"。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
func get_spawnable_types() -> Dictionary:
	return {Tile.TileType.PLAYER: tr("RULE_FIBONACCI")}


## 根据指定的类型ID，获取所有可生成的方块"数值"。
##
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	var sequence := SequenceMath.generate_fibonacci()
	if not sequence.has(1):
		sequence.push_front(1)

	var result: Array[int] = []
	for val in sequence:
		if val < 10000:
			result.append(val)

	var unique_result: Array[int] = []
	for item in result:
		if not unique_result.has(item):
			unique_result.append(item)
	unique_result.sort()
	return unique_result
