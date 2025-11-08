# scripts/rules/base/movement_rule.gd

## MovementRule: 方块移动规则的基类蓝图。
##
## 所有具体的移动逻辑（如经典滑动、步进式移动）都应继承此类。
## 它负责处理单行/列内的方块移动与合并计算。
class_name MovementRule
extends Resource

# --- 内部状态 ---

## 对当前交互规则的引用，由GameBoard在运行时注入。
var interaction_rule: InteractionRule


# --- 公共方法 ---

## 在游戏开始时被调用，用于设置此规则所需的依赖。
## @param p_interaction_rule: 当前游戏模式下的交互规则实例。
func setup(p_interaction_rule: InteractionRule) -> void:
	self.interaction_rule = p_interaction_rule


## 处理单行/列的移动与交互。
## @param line: 一个包含Tile节点或null的一维数组。
## @return: 一个字典，包含 {"line": Array, "moved": bool, "merges": Array}。
func process_line(line: Array[Tile]) -> Dictionary:
	# 子类必须重写此方法。
	return {"line": line, "moved": false, "merges": []}
