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
## @param p_rule: 对当前交互规则实例的引用。
## @return: 一个描述交互结果的字典。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	if can_interact(tile_a, tile_b):
		var new_value: int = tile_a.value + tile_b.value
		# 将 tile_b 的数值更新为两者之和
		tile_b.setup(new_value, tile_a.type, p_rule, tile_a.color_schemes)
		# 返回结果，表明 tile_b 是合并后的方块，tile_a 是被消耗的方块，并带上分数。
		return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}

	return {}


## 判断两个方块是否具备可交互性（用于游戏结束的判断）。
##
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果可以交互则返回 true。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if not is_instance_valid(tile_a) or not is_instance_valid(tile_b):
		return false

	if tile_a.type != Tile.TileType.PLAYER or tile_b.type != Tile.TileType.PLAYER:
		return false

	# 规则1: 两个 1 可以合并。
	if tile_a.value == 1 and tile_b.value == 1:
		return true

	# 规则2: 两个在斐波那契数列中相邻的数可以合并。
	if _are_consecutive_fibonacci(tile_a.value, tile_b.value):
		return true

	return false


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	if value <= 1:
		return 0
	if value == 2:
		return 1

	var a: int = 1
	var b: int = 2
	var level: int = 1
	while b < value:
		var temp: int = a + b
		a = b
		b = temp
		level += 1
		if b == value:
			return level

	# 如果不是一个标准的斐波那契数，返回一个高级别的颜色
	return 15


## 获取用于在HUD上显示的格式化好的上下文数据。
##
## @param context: 包含当前游戏状态的字典。
## @return: 一个包含HUD显示信息的字典。
func get_hud_context_data(context: Dictionary = {}) -> Dictionary:
	var max_value: int = context.get("max_player_value", 0)
	var player_values_set: Dictionary = context.get("player_values_set", {})

	# 动态生成序列直到达到上限
	var max_display_value: int = 5 + max_value * 2
	var sequence: Array[int] = [1, 2]
	while true:
		var next_fib: int = sequence[-1] + sequence[-2]
		if next_fib > max_display_value:
			break
		sequence.append(next_fib)

	# 在规则内部直接构建HUD所需的Array[Dictionary]结构
	var fib_data_for_ui: Array[Dictionary] = [{"text": "合成序列:", "color": Color.WHITE}]
	for num in sequence:
		var item: Dictionary = {"text": str(num), "color": Color.GRAY}
		if player_values_set.has(num):
			item["color"] = Color.WHITE
		fib_data_for_ui.append(item)

	# 返回一个键值对，键名清晰，值为FlowLabelList可以直接使用的数据
	return {
		"fibonacci_sequence_display": fib_data_for_ui
	}


## 获取此规则下所有可生成的方块“类型”。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
func get_spawnable_types() -> Dictionary:
	return {Tile.TileType.PLAYER: "斐波那契数"}


## 根据指定的类型ID，获取所有可生成的方块“数值”。
##
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	var sequence: Array[int] = [1]
	if 1 > 10000:
		return sequence

	sequence.append(1)
	var a: int = 1
	var b: int = 2
	sequence.append(b)

	while b < 10000:
		var next_fib: int = a + b
		if next_fib > 10000:
			break
		sequence.append(next_fib)
		a = b
		b = next_fib

	var unique_sequence: Array[int] = []
	for item in sequence:
		if not unique_sequence.has(item):
			unique_sequence.append(item)
	unique_sequence.sort()
	return unique_sequence


# --- 私有/辅助方法 ---

## [内部辅助函数] 检查两个数是否是斐波那契数列中的连续项。
##
## 使用纯整数迭代法，避免浮点数精度问题，保证结果的绝对准确性。
## @param a: 第一个整数。
## @param b: 第二个整数。
## @return: 如果是连续斐波那契数则返回 true。
func _are_consecutive_fibonacci(a: int, b: int) -> bool:
	# 确保 a < b
	if a > b:
		var temp: int = a
		a = b
		b = temp

	if a <= 0 or b <= 0:
		return false

	# 处理斐波那契数列的起始特殊情况
	if a == 1 and (b == 1 or b == 2):
		return true

	# 从 (1, 2) 开始迭代，检查 a, b 是否是序列中的连续项
	var prev: int = 1
	var curr: int = 2
	while curr <= b:
		if prev == a and curr == b:
			return true
		var next_fib: int = prev + curr
		prev = curr
		curr = next_fib

	return false
