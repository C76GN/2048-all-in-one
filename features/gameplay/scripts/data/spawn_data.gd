## SpawnData: 用于描述一次方块生成请求的强类型数据对象。
##
## 替代原有的裸 Dictionary 在 SpawnRule、RuleSystem 和 GameBoardController 之间传递。
## 当 position.x 为 -1 时，表示未指定位置，由 GridSpawnSystem 随机选取空格。
class_name SpawnData
extends RefCounted


# --- 公共变量 ---

## 生成位置的网格坐标。(-1, -1) 表示由接收方随机选取空格。
var position: Vector2i = Vector2i(-1, -1)

## 生成方块的数值。
var value: int = 2

## 要生成的稳定方块定义 ID；为空时使用当前交互规则的默认定义。
var definition_id: StringName = &""

## 若为 true，棋盘满时将重组一个其他定义方块，或强化同定义方块。
var is_priority: bool = false
