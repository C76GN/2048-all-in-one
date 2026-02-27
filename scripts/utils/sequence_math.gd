# scripts/utils/sequence_math.gd

## SequenceMath: 数学序列工具类。
##
## 提供斐波那契（Fibonacci）和卢卡斯（Lucas）数列的生成、验证以及连续性检查等静态方法。
class_name SequenceMath
extends RefCounted


# --- 常量 ---

## 限制数列生成的大小，防止性能问题和数值溢出。
const MAX_SEQUENCE_VALUE: int = 65536


# --- 公共方法 ---

## 生成斐波那契数列。
## @return: 包含斐波那契数列的数组。
static func generate_fibonacci() -> Array[int]:
	var sequence: Array[int] = [1, 2]
	while sequence[-1] < MAX_SEQUENCE_VALUE:
		var next_val := sequence[-1] + sequence[-2]
		if next_val > MAX_SEQUENCE_VALUE:
			break
		sequence.append(next_val)
	return sequence


## 生成卢卡斯数列。
## @return: 包含卢卡斯数列的数组。
static func generate_lucas() -> Array[int]:
	var sequence: Array[int] = [2, 1] # L0, L1
	var l_n_minus_2 := 2
	var l_n_minus_1 := 1
	while l_n_minus_1 < MAX_SEQUENCE_VALUE:
		var next_luc := l_n_minus_1 + l_n_minus_2
		if next_luc > MAX_SEQUENCE_VALUE:
			break
		sequence.append(next_luc)
		l_n_minus_2 = l_n_minus_1
		l_n_minus_1 = next_luc
	return sequence


## 检查两个数是否是斐波那契数列中的连续项。
## @param a: 第一个整数。
## @param b: 第二个整数。
## @return: 如果是连续斐波那契数则返回 true。
static func are_consecutive_fibonacci(a: int, b: int) -> bool:
	# 确保 a < b
	if a > b:
		var temp := a
		a = b
		b = temp

	if a <= 0 or b <= 0:
		return false

	# 处理斐波那契数列的起始特殊情况 (1, 1, 2)
	if a == 1 and (b == 1 or b == 2):
		return true

	# 从 (1, 2) 开始迭代
	var prev := 1
	var curr := 2
	while curr <= b:
		if prev == a and curr == b:
			return true
		var next_val := prev + curr
		prev = curr
		curr = next_val

	return false


## 根据方块的数值，返回它在斐波那契序列中的索引。
## @param value: 方块的数值。
## @param sequence: (可选) 已生成的序列，若未提供则内部生成。
## @return: 对应的等级索引。
static func get_fibonacci_level(value: int, sequence: Array[int] = []) -> int:
	if sequence.is_empty():
		sequence = generate_fibonacci()
	
	var index := sequence.find(value)
	if index != -1:
		return index
	
	# 特殊处理 1 (F1=1, F2=1)
	if value == 1:
		return 0
		
	return 15


## 检查两个数是否是卢卡斯数列中的连续项。
static func are_consecutive_lucas(a: int, b: int, sequence: Array[int] = []) -> bool:
	if sequence.is_empty():
		sequence = generate_lucas()
	
	var idx1 := sequence.find(a)
	var idx2 := sequence.find(b)
	
	if idx1 != -1 and idx2 != -1:
		return abs(idx1 - idx2) == 1
	
	return false
