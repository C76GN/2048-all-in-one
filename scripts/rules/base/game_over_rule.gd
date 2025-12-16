# scripts/rules/base/game_over_rule.gd

## GameOverRule: 游戏结束规则的基类蓝图。
##
## 所有具体的胜负判断逻辑都应继承此类。它定义了所有游戏结束规则
## 必须遵循的公共接口，但本身不包含任何具体实现。
class_name GameOverRule
extends Resource


# --- 公共方法 ---

## 检查游戏是否已经结束的核心函数。
##
## @param grid_model: 对 GridModel 的引用，用于访问棋盘数据。
## @param interaction_rule: 当前游戏模式下的交互规则实例。
## @return: 如果游戏根据此规则判定为结束，则返回 true，否则返回 false。
func is_game_over(_grid_model: GridModel, _interaction_rule: InteractionRule) -> bool:
	return false
