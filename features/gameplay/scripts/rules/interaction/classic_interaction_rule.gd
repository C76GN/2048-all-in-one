## ClassicInteractionRule: 经典的2048方块交互规则。
##
## 规则定义：
## 1. 挂载经典合并 Recipe 的两个方块数值相同时可以交互。
## 2. 合并后，一个方块的数值翻倍，另一个方块被销毁。
class_name ClassicInteractionRule
extends InteractionRule


# --- 公共方法 ---

## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	var level: int = int(log(value) / log(2)) - 1
	return max(0, level)


## 获取经典规则可生成的方块数值。
##
## @param _option_id: 诊断面板的局部生成选项 ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_option_id: int) -> Array[int]:
	var values: Array[int] = []
	var current_power_of_two: int = 2
	while current_power_of_two <= 8192:
		values.append(current_power_of_two)
		current_power_of_two *= 2
	return values
