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
## @param board: 对 GameBoard 节点的引用，用于访问棋盘数据。
## @param interaction_rule: 当前游戏模式下的交互规则实例。
## @return: 如果游戏结束则返回 true，否则返回 false。
func is_game_over(board: Control, interaction_rule: InteractionRule) -> bool:
	# 规则1: 如果棋盘中还有空格，游戏不可能结束。
	if not board.get_empty_cells().is_empty():
		return false

	# 规则2: 遍历棋盘上的每一个方块，检查其下方和右侧的邻居。
	# 只要找到任何一对可以交互的相邻方块，就意味着游戏尚未结束。
	for x in range(board.grid_size):
		for y in range(board.grid_size):
			var current_tile: Tile = board.grid[x][y]
			# 此处理论上 current_tile 不会为 null，因为棋盘已满，但作为安全检查保留。
			if not is_instance_valid(current_tile):
				continue

			# 检查右侧相邻方块
			if x + 1 < board.grid_size:
				var right_tile: Tile = board.grid[x + 1][y]
				if interaction_rule.can_interact(current_tile, right_tile):
					return false # 发现可移动组合，游戏未结束

			# 检查下方相邻方块
			if y + 1 < board.grid_size:
				var down_tile: Tile = board.grid[x][y + 1]
				if interaction_rule.can_interact(current_tile, down_tile):
					return false # 发现可移动组合，游戏未结束

	# 如果遍历完所有相邻方块都没有找到任何可以交互的组合，则游戏确定失败。
	return true
