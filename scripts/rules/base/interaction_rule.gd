# scripts/interaction_rule.gd

## InteractionRule: 方块交互规则的基类蓝图。
##
## 所有具体的交互逻辑（如合并、战斗）都应继承此类。
## 它本身不包含任何逻辑，仅用于类型定义。
class_name InteractionRule
extends Resource

# --- 信号定义 ---

## 在游戏开始时被调用，用于设置此规则所需的依赖（如GameBoard）。
## 子类可以重写此方法来存储对棋盘或其他节点的引用。
func setup(_game_board: Control) -> void:
	pass # 默认实现为空，需要引用的子类可以重写它。

## 处理两个方块之间的交互。
## 具体的规则需要重写此方法。
func process_interaction(_tile_a: Tile, _tile_b: Tile, _p_rule: InteractionRule) -> Dictionary:
	return {} # 默认不交互不交互

## 当一个怪物在交互中被消灭时发出。
@warning_ignore("unused_signal")
signal monster_killed

# 判断两个方块是否可以发生交互，但不实际执行。
# 具体的规则需要重写此方法。
func can_interact(_tile_a: Tile, _tile_b: Tile) -> bool:
	return false # 默认不能交互

## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
## 例如，在经典模式中，2->0, 4->1, 8->2。
## 子类需要重写此方法。
func get_level_by_value(_value: int) -> int:
	return 0

## 根据方块的数值，返回其应使用的配色方案索引。
## 默认返回0。子类可以重写此方法以支持多配色方案。
func get_color_scheme_index(_value: int) -> int:
	return 0

## 获取用于在HUD上显示的动态数据。
## 子类可以重写此方法，返回一个字典，供HUD展示。
func get_display_data(_context: Dictionary = {}) -> Dictionary:
	return {}

## 获取此规则下所有可生成的方块“类型”。
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
##          例如: {0: "Player", 1: "Monster"}
func get_spawnable_types() -> Dictionary:
	return {} # 默认返回空字典，子类必须重写。

## 根据指定的类型ID，获取所有可生成的方块“数值”。
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	return [] # 默认返回空数组，子类必须重写。

## 根据从UI（如TestPanel）接收的类型ID，返回对应的 Tile.TileType 枚举。
## 这将类型转换的逻辑封装在规则内部，避免了GamePlay中的类型检查。
## @param type_id: 来自UI的类型标识符。
## @return: Tile.TileType 枚举值。
func get_tile_type_from_id(type_id: int) -> Tile.TileType:
	# 默认实现：假设 type_id 直接对应枚举值 (0=PLAYER, 1=MONSTER)。
	# 对于需要特殊处理的规则（如卢卡斯-斐波那契），需要重写此方法。
	return type_id as Tile.TileType
