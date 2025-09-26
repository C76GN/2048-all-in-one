# scripts/modes/fibonacci_interaction_rule.gd

## FibonacciInteractionRule: 斐波那契数列的2048方块交互规则。
##
## 规则定义：
## 1. 只有类型为 PLAYER 的方块可以交互。
## 2. 两个数值为 1 的方块可以合并成 2。
## 3. 两个数值在斐波那契数列中相邻的方块可以合并成它们的和。
##    (例如: 1+2=3, 2+3=5, 3+5=8, ...)
class_name FibonacciInteractionRule
extends InteractionRule

# 对GameBoard的引用，由GamePlay在运行时注入。
var game_board: Control

# 使用黄金分割比来快速检查两个数是否是斐波那契数列中的连续项。
const PHI = 1.618034

## 在游戏开始时被调用，用于设置此规则所需的依赖（如GameBoard）。
func setup(p_game_board: Control) -> void:
	self.game_board = p_game_board

## 处理两个方块之间的合并交互。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	if can_interact(tile_a, tile_b):
		var new_value = tile_a.value + tile_b.value
		# 将 tile_b 的数值更新为两者之和，并销毁 tile_a。
		tile_b.setup(new_value, tile_a.type, p_rule, tile_a.color_schemes)
		tile_a.queue_free()
		# 返回结果，表明 tile_b 是合并后的方块，tile_a 是被消耗的方块，并带上分数。
		return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}
	
	# 如果不满足条件，则不发生任何交互。
	return {}

## 判断两个方块是否具备可交互性（用于游戏结束的判断）。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if tile_a == null or tile_b == null:
		return false
		
	# 确保只处理玩家方块。
	if tile_a.type != Tile.TileType.PLAYER or tile_b.type != Tile.TileType.PLAYER:
		return false
	
	# 规则1: 两个 1 可以合并。
	if tile_a.value == 1 and tile_b.value == 1:
		return true
	
	# 规则2: 两个在斐波那契数列中相邻的数可以合并。
	if _are_consecutive_fibonacci(tile_a.value, tile_b.value):
		return true
		
	return false


## [内部辅助函数] 检查两个数是否是斐波那契数列中的连续项。
## 使用纯整数迭代法，避免浮点数精度问题，保证结果的绝对准确性。
func _are_consecutive_fibonacci(a: int, b: int) -> bool:
	# 确保 a < b
	if a > b:
		var temp = a
		a = b
		b = temp
	
	# 0 不是此模式下的有效值
	if a <= 0 or b <= 0:
		return false
	
	# 处理斐波那契数列的起始特殊情况
	if a == 1 and (b == 1 or b == 2):
		return true

	# 从 (1, 2) 开始迭代，检查 a, b 是否是序列中的连续项
	var prev = 1
	var curr = 2
	while curr <= b:
		if prev == a and curr == b:
			return true
		var next_fib = prev + curr
		prev = curr
		curr = next_fib
	
	return false

## 对于斐波那契模式，通过迭代查找其在序列中的索引。
func get_level_by_value(value: int) -> int:
	if value <= 1:
		return 0
	if value == 2:
		return 1

	var a = 1
	var b = 2
	var level = 1
	while b < value:
		var temp = a + b
		a = b
		b = temp
		level += 1
		if b == value:
			return level
			
	# 如果不是一个标准的斐波那契数，返回一个高级别的颜色
	return 15

## [公共辅助函数] 根据给定的最大值，生成一个从1开始的斐波那契数列。
## 例如，如果 max_value 是 8，它会返回 [1, 2, 3, 5, 8]。
## @param max_value: 生成序列的上限值。
## @return: 一个包含斐波那契数的整数数组。
func get_fibonacci_sequence_up_to(max_value: int) -> Array[int]:
	if max_value < 1:
		return []
		
	var sequence: Array[int] = [1]
	if max_value == 1:
		return sequence
		
	var a = 1
	var b = 2
	
	# 特殊处理数字2
	if b <= max_value:
		sequence.append(b)
	else:
		return sequence

	while true:
		var next_fib = a + b
		if next_fib <= max_value:
			sequence.append(next_fib)
			a = b
			b = next_fib
		else:
			break
			
	return sequence

## 获取用于在HUD上显示的动态数据。
func get_display_data(_context: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(game_board): return {}
	
	var max_value = game_board.get_max_player_value()
	var max_display_value = 5 + max_value * 2 
	
	var player_tiles_set = {}
	for v in game_board.get_all_player_tile_values():
		player_tiles_set[v] = true
		
	var sequence: Array[int] = [1, 2]
	# 动态生成序列直到达到上限
	while true:
		var next_fib = sequence[-1] + sequence[-2]
		if next_fib > max_display_value: break
		sequence.append(next_fib)
	
	# 构建斐波那契数列的数据数组
	var fib_data = [{"text": "合成序列:", "color": Color.WHITE}]
	for num in sequence:
		var item = {"text": str(num), "color": Color.GRAY}
		if player_tiles_set.has(num):
			item["color"] = Color.WHITE
		fib_data.append(item)
			
	return {"fibonacci_sequence": fib_data}

## 获取此规则下所有可生成的方块“类型”。
func get_spawnable_types() -> Dictionary:
	return {Tile.TileType.PLAYER: "斐波那契数"}

## 根据指定的类型ID，获取所有可生成的方块“数值”。
func get_spawnable_values(_type_id: int) -> Array[int]:
	var sequence: Array[int] = [1]
	if 1 > 10000: return sequence
	
	sequence.append(1)
	var a = 1
	var b = 2
	sequence.append(b)

	while b < 10000:
		var next_fib = a + b
		if next_fib > 10000: break
		sequence.append(next_fib)
		a = b
		b = next_fib
		
	var unique_sequence: Array[int] = []
	for item in sequence:
		if not unique_sequence.has(item):
			unique_sequence.append(item)
	unique_sequence.sort()
	return unique_sequence
