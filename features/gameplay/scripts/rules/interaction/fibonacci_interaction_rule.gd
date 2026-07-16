## FibonacciInteractionRule: 斐波那契数列的2048方块交互规则。
##
## 规则定义：
## 1. 两个数值为 1 的方块可以合并成 2。
## 2. 两个数值在斐波那契数列中相邻的方块可以合并成它们的和。
##    (例如: 1+2=3, 2+3=5, 3+5=8, ...)
class_name FibonacciInteractionRule
extends InteractionRule


# --- 常量 ---

const _HUD_TEXT_COLOR: Color = Color(0.34901962, 0.2901961, 0.27058825, 1.0)
const _HUD_MUTED_COLOR: Color = Color(0.4, 0.35686275, 0.32156864, 1.0)


# --- 公共方法 ---

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
	var max_value: int = GFVariantData.to_int(context.get(&"max_tile_value", 0), 0)
	var tile_values_value: Variant = context.get(&"tile_values_set", {})
	var tile_values_set: Dictionary = tile_values_value if tile_values_value is Dictionary else {}

	var max_display_value: int = 5 + max_value * 2
	var full_sequence: Array[int] = SequenceMath.generate_fibonacci()
	var display_sequence: Array[int] = []

	for num: int in full_sequence:
		display_sequence.append(num)
		if num > max_display_value:
			break

	var fib_data_for_ui: Array[Dictionary] = [{&"text": tr("LABEL_SYNTH_SEQ"), &"color": _HUD_TEXT_COLOR}]
	for num: int in display_sequence:
		var item: Dictionary = {&"text": str(num), &"color": _HUD_MUTED_COLOR}
		if tile_values_set.has(num):
			item[&"color"] = _HUD_TEXT_COLOR
		fib_data_for_ui.append(item)

	stats[&"fibonacci_sequence_display"] = fib_data_for_ui


## 获取斐波那契规则可生成的方块数值。
##
## @param _option_id: 诊断面板的局部生成选项 ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_option_id: int) -> Array[int]:
	var sequence: Array[int] = SequenceMath.generate_fibonacci()
	if not sequence.has(1):
		sequence.push_front(1)

	var result: Array[int] = []
	for val: int in sequence:
		if val < 10000:
			result.append(val)

	var unique_result: Array[int] = []
	for item: int in result:
		if not unique_result.has(item):
			unique_result.append(item)
	unique_result.sort()
	return unique_result
