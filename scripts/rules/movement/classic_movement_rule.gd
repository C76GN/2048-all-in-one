# scripts/rules/movement/classic_movement_rule.gd

## ClassicMovementRule: 实现了经典的“滑动到底”移动和合并逻辑。
##
## 这是2048标准玩法的移动规则。
class_name ClassicMovementRule
extends MovementRule

# --- 公共方法 ---

## 处理单行/列的移动与交互，采用经典滑动逻辑。
func process_line(line: Array[Tile]) -> Dictionary:
	var slid_line: Array[Tile] = []
	for tile in line:
		if tile != null:
			slid_line.append(tile)

	var merged_line: Array[Tile] = []
	var merge_results: Array[Dictionary] = []
	var i = 0
	while i < slid_line.size():
		var current_tile = slid_line[i]
		if i + 1 < slid_line.size():
			var next_tile = slid_line[i + 1]

			var result = interaction_rule.process_interaction(current_tile, next_tile, interaction_rule)
			if not result.is_empty():
				var merged = result.get("merged_tile")
				if merged != null:
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
	# --- 修正点 ---
	# 将 line[0].get_parent().grid_size 替换为 line.size()
	# 因为 line 的长度本身就是 grid_size，且这样可以避免在 line[0] 为 null 时崩溃。
	while result_line.size() < line.size():
		result_line.append(null)

	var has_moved = false
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
