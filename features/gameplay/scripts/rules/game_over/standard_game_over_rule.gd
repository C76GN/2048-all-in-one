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

	if not is_instance_valid(grid_model.topology):
		return true

	for cell: Vector2i in grid_model.topology.get_active_cells():
		var current_tile: TileState = grid_model.get_tile(cell)
		if current_tile == null:
			continue

		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor_cell: Vector2i = cell + direction
			if not grid_model.is_active_cell(neighbor_cell):
				continue
			var neighbor_tile: TileState = grid_model.get_tile(neighbor_cell)
			if neighbor_tile != null and interaction_rule.can_interact(current_tile, neighbor_tile):
				return false

	return true
