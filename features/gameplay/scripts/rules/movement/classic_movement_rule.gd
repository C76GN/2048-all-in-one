## ClassicMovementRule: 实现了经典的“滑动到底”移动和合并逻辑。
##
## 这是2048标准玩法的移动规则。所有方块会沿着指定方向移动，
## 直到碰到棋盘边缘或其他方块。
class_name ClassicMovementRule
extends MovementRule


# --- 公共方法 ---

## 处理单行/列的移动与交互，采用经典滑动逻辑。
##
## @param line: 一个包含TileState节点或null的一维数组，代表棋盘的一行或一列。
## @return: 单条 lane 的强类型结果。
func process_line(line: Array[TileState]) -> MovementLineResult:
	var slid_line: Array[TileState] = []
	for tile: TileState in line:
		if tile != null:
			slid_line.append(tile)

	var merged_line: Array[TileState] = []
	var merge_results: Array[TileInteractionResult] = []
	var i: int = 0
	while i < slid_line.size():
		var current_tile: TileState = slid_line[i]
		if i + 1 < slid_line.size():
			var next_tile: TileState = slid_line[i + 1]

			var result: TileInteractionResult = interaction_rule.process_interaction(
				current_tile,
				next_tile,
				interaction_rule
			)
			if result != null and result.is_valid_result():
				merged_line.append(result.survivor)
				merge_results.append(result)

				i += 2
				continue

		merged_line.append(current_tile)
		i += 1

	var result_line: Array[TileState] = []
	result_line.append_array(merged_line)
	# 用 null 填充剩余空间，使新行长度与原行一致。
	# 使用 lane 自身长度作为目标，避免依赖外部棋盘尺寸或 line[0] 的内容。
	while result_line.size() < line.size():
		result_line.append(null)

	var has_moved: bool = false
	if result_line.size() != line.size():
		has_moved = true
	else:
		for idx: int in range(result_line.size()):
			if (
				(result_line[idx] == null and line[idx] != null)
				or (result_line[idx] != null and line[idx] == null)
				or (result_line[idx] != null and line[idx] != null and result_line[idx] != line[idx])
			):
				has_moved = true
				break

	return MovementLineResult.new(result_line, has_moved, merge_results)
