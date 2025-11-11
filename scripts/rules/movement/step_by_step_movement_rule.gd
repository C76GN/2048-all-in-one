# scripts/rules/movement/step_by_step_movement_rule.gd

## StepByStepMovementRule: 实现了“步进式”的移动和合并逻辑。
##
## 在此规则下，每次移动指令只会让每个方块移动一格或进行一次合并。
class_name StepByStepMovementRule
extends MovementRule


# --- 公共方法 ---

## 处理单行/列的移动与交互，采用步进式逻辑。
##
## @param line: 一个包含Tile节点或null的一维数组，代表棋盘的一行或一列。
## @return: 一个字典，包含 {"line": Array, "moved": bool, "merges": Array}。
func process_line(line: Array[Tile]) -> Dictionary:
	var new_line: Array[Tile] = line.duplicate(false)
	var merge_results: Array[Dictionary] = []
	var moved_in_this_line: bool = false
	# 记录本轮已合并的方块，防止二次合并
	var merged_in_this_turn: Dictionary = {}

	# 从左到右（即从移动方向的起点开始）处理
	for i in range(1, new_line.size()):
		var current_tile: Tile = new_line[i]
		if not is_instance_valid(current_tile):
			continue

		var target_tile: Tile = new_line[i - 1]

		# 如果目标位置为空，则移动
		if not is_instance_valid(target_tile):
			new_line[i - 1] = current_tile
			new_line[i] = null
			moved_in_this_line = true
		# 如果目标位置有方块，则尝试合并
		else:
			# 确保两个方块都未参与本轮的合并
			if not merged_in_this_turn.has(current_tile.get_instance_id()) and \
			not merged_in_this_turn.has(target_tile.get_instance_id()):

				var result: Dictionary = interaction_rule.process_interaction(current_tile, target_tile, interaction_rule)
				if not result.is_empty():
					var merged_tile: Tile = result.get("merged_tile")
					var consumed_tile: Tile = result.get("consumed_tile")

					# 更新逻辑位置
					if merged_tile == target_tile:
						new_line[i] = null

					merge_results.append(result)

					# 标记参与合并的方块
					if is_instance_valid(merged_tile):
						merged_in_this_turn[merged_tile.get_instance_id()] = true
					if is_instance_valid(consumed_tile):
						merged_in_this_turn[consumed_tile.get_instance_id()] = true

					moved_in_this_line = true

					if result.has("score"):
						EventBus.score_updated.emit(result["score"])

	return {"line": new_line, "moved": moved_in_this_line, "merges": merge_results}
