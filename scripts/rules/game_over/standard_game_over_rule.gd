# scripts/rules/game_over/standard_game_over_rule.gd

## StandardGameOverRule: 标准的2048游戏失败判断规则。
##
## 当棋盘已满，且没有任何相邻的方块可以进行交互时，游戏失败。
class_name StandardGameOverRule
extends GameOverRule


# --- 公共方法 ---

## 检查游戏是否已经结束。
##
## 游戏结束的条件是：棋盘已满，且没有任何相邻的方块可以进行交互。
## 此函数通过委托给传入的 `interaction_rule` 来判断方块间的可交互性。
## @param grid_model: 对 GridModel 的引用，用于访问棋盘数据。
## @param interaction_rule: 当前游戏模式下的交互规则实例。
## @return: 如果游戏结束则返回 true，否则返回 false。
func is_game_over(grid_model: GridModel, interaction_rule: InteractionRule) -> bool:
	if not grid_model.get_empty_cells().is_empty():
		return false

	for x in range(grid_model.grid_size):
		for y in range(grid_model.grid_size):
			var current_tile: Tile = grid_model.grid[x][y]
			if not is_instance_valid(current_tile):
				continue

			if x + 1 < grid_model.grid_size:
				var right_tile: Tile = grid_model.grid[x + 1][y]
				if interaction_rule.can_interact(current_tile, right_tile):
					return false

			if y + 1 < grid_model.grid_size:
				var down_tile: Tile = grid_model.grid[x][y + 1]
				if interaction_rule.can_interact(current_tile, down_tile):
					return false

	return true
