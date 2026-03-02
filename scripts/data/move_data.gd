# scripts/data/move_data.gd

## MoveData: 用于描述一次玩家移动结果的强类型数据对象。
##
## 替代原有在 EventBus.move_made 信号和 SpawnRule.execute 上下文中传递的裸 Dictionary。
class_name MoveData
extends RefCounted


# --- 公共变量 ---

## 本次移动的方向向量。
var direction: Vector2i = Vector2i.ZERO

## 在本次移动中发生位移的行或列的索引列表。
var moved_lines: Array[int] = []
