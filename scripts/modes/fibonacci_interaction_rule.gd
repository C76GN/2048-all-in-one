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

# 使用黄金分割比来快速检查两个数是否是斐波那契数列中的连续项。
const PHI = 1.618034

## 处理两个方块之间的合并交互。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule, p_player_scheme: TileColorScheme, p_monster_scheme: TileColorScheme) -> Dictionary:
	if can_interact(tile_a, tile_b):
		# 将 tile_b 的数值更新为两者之和，并销毁 tile_a。
		tile_b.setup(tile_a.value + tile_b.value, tile_a.type, p_rule, p_player_scheme, p_monster_scheme)
		tile_a.queue_free()
		# 返回结果，表明 tile_b 是合并后的方块，tile_a 是被消耗的方块。
		return {"merged_tile": tile_b, "consumed_tile": tile_a}
	
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
