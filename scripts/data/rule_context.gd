# scripts/data/rule_context.gd

## RuleContext: 用于向规则传递游戏上下文的强类型数据对象。
##
## 替代原有在 RuleSystem.dispatch_event 和 SpawnRule.execute 中使用的裸
## Dictionary（原格式为 {"grid_model": ..., "move_data": ...}）。
## move_data 可以为 null，在 INITIALIZE_BOARD 和 MONSTER_KILLED 事件中不需要此数据。
class_name RuleContext
extends RefCounted


# --- 公共变量 ---

## 当前棋盘的逻辑数据模型。
var grid_model: GridModel

## 本次移动的数据。仅在 PLAYER_MOVED 事件中有效，其他事件中为 null。
var move_data: MoveData
