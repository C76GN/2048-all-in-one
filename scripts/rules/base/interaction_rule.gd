# scripts/rules/base/interaction_rule.gd

## InteractionRule: 方块交互规则的基类蓝图。
##
## 所有具体的交互逻辑（如合并、战斗）都应继承此类。它定义了所有交互规则
## 必须遵循的公共接口，但本身不包含任何具体实现。
class_name InteractionRule
extends Resource


# --- 公共方法 ---

## 在游戏开始时被调用，用于设置此规则所需的依赖（如GameBoard）。
##
## 子类可以重写此方法来存储对棋盘或其他节点的引用。
## @param _game_board: 对当前GameBoard节点的引用。
func setup(_game_board: Control) -> void:
	pass


## 处理两个方块之间的交互。
##
## @param _tile_a: 参与交互的第一个方块。
## @param _tile_b: 参与交互的第二个方块（通常是移动的目标方块）。
## @param _p_rule: 对当前交互规则实例的引用，用于更新新方块的状态。
## @return: 一个描述交互结果的字典，可能包含 "merged_tile" 和 "consumed_tile"。
func process_interaction(_tile_a: Tile, _tile_b: Tile, _p_rule: InteractionRule) -> Dictionary:
	return {}


## 判断两个方块是否可以发生交互，但不实际执行。
##
## 此方法主要由游戏结束规则调用，以检查是否存在任何可能的移动。
## @param _tile_a: 第一个方块。
## @param _tile_b: 第二个方块。
## @return: 如果可以交互则返回 true。
func can_interact(_tile_a: Tile, _tile_b: Tile) -> bool:
	return false


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## 例如，在经典模式中，2->0, 4->1, 8->2。此方法主要用于确定方块的视觉样式。
## @param _value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(_value: int) -> int:
	return 0


## 根据方块的数值，返回其应使用的配色方案索引。
##
## 默认返回0。子类可以重写此方法以支持多配色方案。
## @param _value: 方块的数值。
## @return: 配色方案的索引。
func get_color_scheme_index(_value: int) -> int:
	return 0


## 获取此规则相关的、用于HUD显示的原始上下文数据。
##
## 子类可以重写此方法，返回一个字典，供上层逻辑（如GamePlay）格式化后展示。
## @param _context: 包含当前游戏状态的字典。
## @return: 一个包含HUD显示信息的字典。
func get_hud_context_data(_context: Dictionary = {}) -> Dictionary:
	return {}


## 获取此规则下所有可生成的方块“类型”。
##
## @return: 一个字典，键是类型ID(int)，值是类型的可读名称(String)。
##          例如: {0: "Player", 1: "Monster"}
func get_spawnable_types() -> Dictionary:
	return {}


## 根据指定的类型ID，获取所有可生成的方块“数值”。
##
## @param _type_id: 类型的ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_type_id: int) -> Array[int]:
	return []


## 根据从UI（如TestPanel）接收的类型ID，返回对应的 Tile.TileType 枚举。
##
## 这将类型转换的逻辑封装在规则内部，避免了GamePlay中的类型检查。
## @param type_id: 来自UI的类型标识符。
## @return: Tile.TileType 枚举值。
func get_tile_type_from_id(type_id: int) -> Tile.TileType:
	return type_id as Tile.TileType
