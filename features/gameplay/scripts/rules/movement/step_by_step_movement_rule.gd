## StepByStepMovementRule: 实现了“步进式”的移动和合并逻辑。
##
## 在此规则下，每次移动指令只会让每个方块移动一格或进行一次合并。
class_name StepByStepMovementRule
extends MovementRule


# --- 公共方法 ---

## 处理单行/列的移动与交互，采用步进式逻辑。
##
## @param line: 一个包含TileState节点或null的一维数组，代表棋盘的一行或一列。
## @return: 单条 lane 的强类型结果。
func process_line(line: Array[TileState]) -> MovementLineResult:
	var new_line: Array[TileState] = line.duplicate(false)
	var merge_results: Array[TileInteractionResult] = []
	var moved_in_this_line: bool = false
	# 记录本轮已合并的方块，防止二次合并
	var merged_in_this_turn: Dictionary = {}

	# 从左到右（即从移动方向的起点开始）处理
	for i: int in range(1, new_line.size()):
		var current_tile: TileState = new_line[i]
		if current_tile == null:
			continue

		var target_tile: TileState = new_line[i - 1]

		# 如果目标位置为空，则移动
		if target_tile == null:
			new_line[i - 1] = current_tile
			new_line[i] = null
			moved_in_this_line = true
		# 如果目标位置有方块，则尝试合并
		else:
			# 确保两个方块都未参与本轮的合并
			if (
				not merged_in_this_turn.has(current_tile.get_instance_id())
				and not merged_in_this_turn.has(target_tile.get_instance_id())
			):
				var result: TileInteractionResult = interaction_rule.process_interaction(
					current_tile,
					target_tile,
					interaction_rule
				)
				if result != null and result.is_valid_result():
					var merged_tile: TileState = result.survivor
					var consumed_tile: TileState = result.consumed

					# 更新逻辑位置
					if merged_tile == target_tile:
						new_line[i] = null
					elif merged_tile == current_tile:
						new_line[i - 1] = current_tile
						new_line[i] = null

					merge_results.append(result)

					# 标记参与合并的方块
					if merged_tile != null:
						merged_in_this_turn[merged_tile.get_instance_id()] = true
					if consumed_tile != null:
						merged_in_this_turn[consumed_tile.get_instance_id()] = true

					moved_in_this_line = true

	return MovementLineResult.new(new_line, moved_in_this_line, merge_results)
