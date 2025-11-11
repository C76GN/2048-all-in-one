# scripts/rules/movement/classic_movement_rule.gd

## ClassicMovementRule: 实现了经典的“滑动到底”移动和合并逻辑。
##
## 这是2048标准玩法的移动规则。所有方块会沿着指定方向移动，
## 直到碰到棋盘边缘或其他方块。
class_name ClassicMovementRule
extends MovementRule


# --- 公共方法 ---

## 处理单行/列的移动与交互，采用经典滑动逻辑。
##
## @param line: 一个包含Tile节点或null的一维数组，代表棋盘的一行或一列。
## @return: 一个字典，包含 {"line": Array, "moved": bool, "merges": Array}。
func process_line(line: Array[Tile]) -> Dictionary:
	var slid_line: Array[Tile] = []
	for tile in line:
		if is_instance_valid(tile):
			slid_line.append(tile)

	var merged_line: Array[Tile] = []
	var merge_results: Array[Dictionary] = []
	var i: int = 0
	while i < slid_line.size():
		var current_tile: Tile = slid_line[i]
		if i + 1 < slid_line.size():
			var next_tile: Tile = slid_line[i + 1]

			var result: Dictionary = interaction_rule.process_interaction(current_tile, next_tile, interaction_rule)
			if not result.is_empty():
				var merged: Tile = result.get("merged_tile")
				if is_instance_valid(merged):
					merged_line.append(merged)

				merge_results.append(result)

				if result.has("score"):
					EventBus.score_updated.emit(result["score"])

				i += 2
				continue

		merged_line.append(current_tile)
		i += 1

	var result_line: Array[Tile] = []
	result_line.append_array(merged_line)
	# 用 null 填充剩余空间，使新行长度与原行一致。
	# 使用 line.size() 作为目标长度，因为它本身就是 grid_size，且能避免在 line[0] 为 null 时崩溃。
	while result_line.size() < line.size():
		result_line.append(null)

	var has_moved: bool = false
	if result_line.size() != line.size():
		has_moved = true
	else:
		for idx in range(result_line.size()):
			if (result_line[idx] == null and line[idx] != null) or \
			(result_line[idx] != null and line[idx] == null) or \
			(result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true
				break

	return {"line": result_line, "moved": has_moved, "merges": merge_results}
