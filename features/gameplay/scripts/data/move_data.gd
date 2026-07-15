## MoveData: 用于描述一次玩家移动结果的强类型数据对象。
##
## 用于在移动和生成上下文之间传递的强类型数据模型。
class_name MoveData
extends "res://addons/gf/kernel/base/gf_payload.gd"


# --- 公共变量 ---

## 本次移动的方向向量。
var direction: Vector2i = Vector2i.ZERO

## 在本次移动中发生位移的行或列的索引列表。
var moved_lines: Array[int] = []

## 本次移动产生的撤回反向位置映射。
##
## key 为移动前坐标字符串，value 为撤回前坐标。MoveCommand 用它播放撤回动画。
var reverse_target_map: Dictionary = {}
