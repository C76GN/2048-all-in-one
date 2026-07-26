## DeterministicHintQuery: 在不可变棋盘快照上生成受预算约束的方向建议。
##
## 查询不读取 Architecture，不调用 GridModel、规则、历史或随机数。它只从快照中的
## 拓扑、占位和值提取通用结构信号，因此不会声称某一对方块一定能按当前模式合并。
class_name DeterministicHintQuery
extends RefCounted


# --- 常量 ---

const GameHintResultType = preload(
	"res://features/gameplay/scripts/data/game_hint_result.gd"
)
const DEFAULT_MAX_STEPS: int = 12000
const DEFAULT_MAX_ELAPSED_MSEC: int = 12

const _DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]
const _FACTOR_STRUCTURE: StringName = &"comparable_structure"
const _FACTOR_MOBILITY: StringName = &"compression_space"
const _FACTOR_STABILITY: StringName = &"front_stability"
const _FACTOR_FALLBACK: StringName = &"deterministic_fallback"
const _FACTOR_BUDGET_FALLBACK: StringName = &"budget_limited_fallback"


# --- 公共方法 ---

## 分析一份调用方拥有的棋盘快照。
##
## @param board_snapshot: GridModel.get_snapshot() 产生的只读快照；查询绝不修改它。
## @param snapshot_id: 调用方在捕获边界计算的稳定语义摘要。
## @param budget: 可注入 GFExecutionBudget；为空时使用保守默认预算。
func evaluate(
	board_snapshot: Dictionary,
	snapshot_id: String,
	budget: GFExecutionBudget = null
) -> GameHintResultType:
	var execution_budget: GFExecutionBudget = budget
	if execution_budget == null:
		execution_budget = GFExecutionBudget.new({
			&"max_steps": DEFAULT_MAX_STEPS,
			&"max_elapsed_msec": DEFAULT_MAX_ELAPSED_MSEC,
			&"metadata": {&"operation": &"deterministic_game_hint"},
		})

	var result: GameHintResultType = GameHintResultType.new()
	result.snapshot_id = snapshot_id
	if snapshot_id.is_empty():
		return _finish_invalid(result, execution_budget, "棋盘快照标识为空，未生成建议。")
	if not execution_budget.check():
		return _finish_budget_limited(result, execution_budget, [])

	var prepared: Dictionary = _prepare_snapshot(board_snapshot, execution_budget)
	if prepared.is_empty():
		if execution_budget.is_exceeded():
			return _finish_budget_limited(result, execution_budget, [])
		return _finish_invalid(result, execution_budget, "棋盘快照结构无效，未生成建议。")

	var candidates: Array[Dictionary] = []
	for direction: Vector2i in _DIRECTIONS:
		if not execution_budget.consume_steps():
			return _finish_budget_limited(result, execution_budget, candidates)
		var candidate: Dictionary = _score_direction(
			direction,
			prepared,
			execution_budget,
			result
		)
		if candidate.is_empty():
			if execution_budget.is_exceeded():
				return _finish_budget_limited(result, execution_budget, candidates)
			return _finish_invalid(result, execution_budget, "棋盘拓扑无法形成方向通道，未生成建议。")
		candidates.append(candidate)

	return _finish_completed(result, execution_budget, candidates)


# --- 私有/辅助方法 ---

func _prepare_snapshot(
	board_snapshot: Dictionary,
	budget: GFExecutionBudget
) -> Dictionary:
	if not (
		board_snapshot.size() == 3
		and board_snapshot.get(&"schema_version") is int
		and board_snapshot.get(&"topology") is Dictionary
		and board_snapshot.get(&"tiles") is Array
		and GFVariantData.get_option_int(board_snapshot, &"schema_version")
			== GridModel.SNAPSHOT_SCHEMA_VERSION
	):
		return {}

	var topology: Dictionary = GFVariantData.get_option_dictionary(
		board_snapshot,
		&"topology"
	)
	if not (
		topology.size() == 3
		and topology.get(&"schema_version") is int
		and topology.get(&"topology_id") is String
		and topology.get(&"active_cells") is Array
		and GFVariantData.get_option_int(topology, &"schema_version")
			== BoardTopology.SERIALIZATION_SCHEMA_VERSION
		and not GFVariantData.get_option_string(topology, &"topology_id").is_empty()
	):
		return {}

	var active_cells: Array = GFVariantData.get_option_array(topology, &"active_cells")
	if (
		active_cells.is_empty()
		or active_cells.size() > BoardTopology.MAX_CELL_COUNT
	):
		return {}

	var cell_lookup: Dictionary = {}
	var minimum: Vector2i = Vector2i(BoardTopology.MAX_CELL_COUNT, BoardTopology.MAX_CELL_COUNT)
	var previous: Vector2i = Vector2i(-1, -1)
	for index: int in range(active_cells.size()):
		if not budget.consume_steps():
			return {}
		var cell_value: Variant = active_cells[index]
		if not cell_value is Vector2i:
			return {}
		var cell: Vector2i = cell_value
		if cell.x < 0 or cell.y < 0 or cell_lookup.has(cell):
			return {}
		if index > 0 and not _is_row_major_before(previous, cell):
			return {}
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		previous = cell
		cell_lookup[cell] = true
	if minimum != Vector2i.ZERO:
		return {}

	var tiles: Array = GFVariantData.get_option_array(board_snapshot, &"tiles")
	if tiles.size() > active_cells.size():
		return {}
	var tiles_by_cell: Dictionary = {}
	var seen_tile_ids: Dictionary = {}
	var maximum_tile_value: int = 0
	for tile_value: Variant in tiles:
		if not budget.consume_steps():
			return {}
		if not tile_value is Dictionary:
			return {}
		var tile: Dictionary = tile_value
		if not _is_hint_tile_envelope_valid(tile, budget):
			return {}
		var position: Vector2i = tile[&"pos"]
		var tile_id: String = GFVariantData.get_option_string(tile, &"tile_id")
		if (
			not cell_lookup.has(position)
			or tiles_by_cell.has(position)
			or seen_tile_ids.has(tile_id)
		):
			return {}
		var tile_number: int = GFVariantData.get_option_int(tile, &"value")
		tiles_by_cell[position] = {
			&"value": tile_number,
			&"definition_id": GFVariantData.get_option_string_name(
				tile,
				&"definition_id"
			),
		}
		seen_tile_ids[tile_id] = true
		maximum_tile_value = maxi(maximum_tile_value, tile_number)

	return {
		&"active_cells": active_cells,
		&"cell_lookup": cell_lookup,
		&"tiles_by_cell": tiles_by_cell,
		&"maximum_tile_value": maximum_tile_value,
	}


func _is_hint_tile_envelope_valid(
	tile: Dictionary,
	budget: GFExecutionBudget
) -> bool:
	if not (
		tile.size() == 7
		and tile.get(&"schema_version") is int
		and tile.get(&"tile_id") is String
		and tile.get(&"definition_id") is StringName
		and tile.get(&"value") is int
		and tile.get(&"capability_recipe_ids") is Array
		and tile.get(&"capability_state") is Dictionary
		and tile.get(&"pos") is Vector2i
	):
		return false
	if not (
		GFVariantData.get_option_int(tile, &"schema_version")
			== TileState.SERIALIZATION_SCHEMA_VERSION
		and GFUuid.is_valid(GFVariantData.get_option_string(tile, &"tile_id"), 7)
		and GFVariantData.get_option_string_name(tile, &"definition_id") != &""
		and GFVariantData.get_option_int(tile, &"value") > 0
		and not GFVariantData.get_option_array(tile, &"capability_recipe_ids").is_empty()
	):
		return false

	var recipe_ids: Array = GFVariantData.get_option_array(
		tile,
		&"capability_recipe_ids"
	)
	var seen_recipe_ids: Dictionary = {}
	for recipe_value: Variant in recipe_ids:
		if not budget.consume_steps():
			return false
		if not recipe_value is StringName:
			return false
		var recipe_id: StringName = recipe_value
		if recipe_id == &"" or seen_recipe_ids.has(recipe_id):
			return false
		seen_recipe_ids[recipe_id] = true

	var capability_state: Dictionary = GFVariantData.get_option_dictionary(
		tile,
		&"capability_state"
	)
	for state_key: Variant in capability_state:
		if not budget.consume_steps():
			return false
		if not state_key is StringName or not seen_recipe_ids.has(state_key):
			return false
	return true


func _score_direction(
	direction: Vector2i,
	prepared: Dictionary,
	budget: GFExecutionBudget,
	result: GameHintResultType
) -> Dictionary:
	var active_cells: Array = GFVariantData.get_option_array(prepared, &"active_cells")
	var cell_lookup: Dictionary = GFVariantData.get_option_dictionary(
		prepared,
		&"cell_lookup"
	)
	var tiles_by_cell: Dictionary = GFVariantData.get_option_dictionary(
		prepared,
		&"tiles_by_cell"
	)
	var maximum_tile_value: int = GFVariantData.get_option_int(
		prepared,
		&"maximum_tile_value"
	)

	var starts: Array[Vector2i] = []
	for cell_value: Variant in active_cells:
		if not budget.consume_steps():
			return {}
		var cell: Vector2i = cell_value
		result.nodes_evaluated += 1
		if not cell_lookup.has(cell + direction):
			starts.append(cell)

	var exact_pairs: int = 0
	var divisible_pairs: int = 0
	var nearby_pairs: int = 0
	var moved_tiles: int = 0
	var displacement: int = 0
	var front_max_tiles: int = 0

	for start: Vector2i in starts:
		var occupied: Array[Dictionary] = []
		var current: Vector2i = start
		var lane_index: int = 0
		while cell_lookup.has(current):
			if not budget.consume_steps():
				return {}
			result.nodes_evaluated += 1
			if tiles_by_cell.has(current):
				var descriptor: Dictionary = GFVariantData.get_option_dictionary(
					tiles_by_cell,
					current
				)
				occupied.append({
					&"lane_index": lane_index,
					&"value": GFVariantData.get_option_int(descriptor, &"value"),
					&"definition_id": GFVariantData.get_option_string_name(
						descriptor,
						&"definition_id"
					),
				})
			current -= direction
			lane_index += 1

		for occupied_index: int in range(occupied.size()):
			if not budget.consume_steps():
				return {}
			result.nodes_evaluated += 1
			var tile: Dictionary = occupied[occupied_index]
			var original_index: int = GFVariantData.get_option_int(tile, &"lane_index")
			if original_index > occupied_index:
				moved_tiles += 1
				displacement += original_index - occupied_index
			if (
				occupied_index == 0
				and maximum_tile_value > 0
				and GFVariantData.get_option_int(tile, &"value") == maximum_tile_value
			):
				front_max_tiles += 1
			if occupied_index + 1 >= occupied.size():
				continue
			var pair_kind: StringName = _classify_pair(
				tile,
				occupied[occupied_index + 1]
			)
			match pair_kind:
				&"exact":
					exact_pairs += 1
				&"divisible":
					divisible_pairs += 1
				&"nearby":
					nearby_pairs += 1

	var structure_pair_count: int = exact_pairs + divisible_pairs + nearby_pairs
	var structure_score: int = exact_pairs * 120 + divisible_pairs * 90 + nearby_pairs * 35
	var mobility_score: int = moved_tiles * 18 + displacement * 7
	var stability_score: int = front_max_tiles * 12
	return {
		&"direction": direction,
		&"direction_id": _direction_id(direction),
		&"total_score": structure_score + mobility_score + stability_score,
		&"structure_score": structure_score,
		&"mobility_score": mobility_score,
		&"stability_score": stability_score,
		&"structure_pair_count": structure_pair_count,
		&"exact_pairs": exact_pairs,
		&"divisible_pairs": divisible_pairs,
		&"nearby_pairs": nearby_pairs,
		&"moved_tiles": moved_tiles,
		&"displacement": displacement,
		&"front_max_tiles": front_max_tiles,
	}


func _classify_pair(first: Dictionary, second: Dictionary) -> StringName:
	var first_value: int = GFVariantData.get_option_int(first, &"value")
	var second_value: int = GFVariantData.get_option_int(second, &"value")
	var first_definition: StringName = GFVariantData.get_option_string_name(
		first,
		&"definition_id"
	)
	var second_definition: StringName = GFVariantData.get_option_string_name(
		second,
		&"definition_id"
	)
	if first_definition == second_definition and first_value == second_value:
		return &"exact"

	var smaller: int = mini(first_value, second_value)
	var larger: int = maxi(first_value, second_value)
	if (
		first_definition != second_definition
		and smaller > 0
		and larger % smaller == 0
	):
		return &"divisible"
	if (
		first_definition == second_definition
		and larger > smaller
		and larger - smaller <= smaller
	):
		return &"nearby"
	return &""


func _finish_completed(
	result: GameHintResultType,
	budget: GFExecutionBudget,
	candidates: Array[Dictionary]
) -> GameHintResultType:
	_apply_direction_scores(result, candidates)
	var chosen: Dictionary = _choose_best(candidates)
	_apply_candidate(result, chosen)
	result.termination_reason = GameHintResultType.TERMINATION_COMPLETED
	result.elapsed_msec = budget.get_elapsed_msec()
	result.explanation = _make_explanation(chosen)
	return result


func _finish_budget_limited(
	result: GameHintResultType,
	budget: GFExecutionBudget,
	candidates: Array[Dictionary]
) -> GameHintResultType:
	_apply_direction_scores(result, candidates)
	var reason: StringName = budget.get_violation_reason()
	result.termination_reason = (
		reason if reason != &"" else GameHintResultType.TERMINATION_STEP_LIMIT
	)
	result.elapsed_msec = budget.get_elapsed_msec()
	if not candidates.is_empty():
		var chosen: Dictionary = _choose_best(candidates)
		_apply_candidate(result, chosen)
		result.explanation = (
			"分析在预算终止前完成 %d/4 个方向；当前最高结构评分来自%s。"
			% [candidates.size(), _direction_label(result.suggested_direction)]
		)
	else:
		result.suggested_direction = _DIRECTIONS[0]
		result.primary_factor = _FACTOR_BUDGET_FALLBACK
		result.factor_scores = {}
		result.explanation = (
			"分析在方向评分前达到预算边界，按固定顺序返回%s作为通用降级结果。"
			% _direction_label(result.suggested_direction)
		)
	return result


func _finish_invalid(
	result: GameHintResultType,
	budget: GFExecutionBudget,
	message: String
) -> GameHintResultType:
	result.termination_reason = GameHintResultType.TERMINATION_INVALID_SNAPSHOT
	result.elapsed_msec = budget.get_elapsed_msec()
	result.explanation = message
	return result


func _choose_best(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var chosen: Dictionary = candidates[0]
	for index: int in range(1, candidates.size()):
		var candidate: Dictionary = candidates[index]
		if (
			GFVariantData.get_option_int(candidate, &"total_score")
			> GFVariantData.get_option_int(chosen, &"total_score")
		):
			chosen = candidate
	return chosen


func _apply_candidate(result: GameHintResultType, candidate: Dictionary) -> void:
	if candidate.is_empty():
		result.suggested_direction = _DIRECTIONS[0]
		result.primary_factor = _FACTOR_FALLBACK
		return
	var direction_value: Variant = GFVariantData.get_option_value(
		candidate,
		&"direction",
		_DIRECTIONS[0]
	)
	if direction_value is Vector2i:
		result.suggested_direction = direction_value
	var structure_score: int = GFVariantData.get_option_int(candidate, &"structure_score")
	var mobility_score: int = GFVariantData.get_option_int(candidate, &"mobility_score")
	var stability_score: int = GFVariantData.get_option_int(candidate, &"stability_score")
	if structure_score <= 0 and mobility_score <= 0 and stability_score <= 0:
		result.primary_factor = _FACTOR_FALLBACK
	elif structure_score >= mobility_score and structure_score >= stability_score:
		result.primary_factor = _FACTOR_STRUCTURE
	elif mobility_score >= stability_score:
		result.primary_factor = _FACTOR_MOBILITY
	else:
		result.primary_factor = _FACTOR_STABILITY
	result.factor_scores = {
		&"structure": structure_score,
		&"mobility": mobility_score,
		&"stability": stability_score,
		&"total": GFVariantData.get_option_int(candidate, &"total_score"),
	}


func _apply_direction_scores(
	result: GameHintResultType,
	candidates: Array[Dictionary]
) -> void:
	result.direction_scores.clear()
	for candidate: Dictionary in candidates:
		result.direction_scores[
			GFVariantData.get_option_string_name(candidate, &"direction_id")
		] = GFVariantData.get_option_int(candidate, &"total_score")


func _make_explanation(candidate: Dictionary) -> String:
	var direction: Vector2i = _DIRECTIONS[0]
	var direction_value: Variant = GFVariantData.get_option_value(
		candidate,
		&"direction",
		_DIRECTIONS[0]
	)
	if direction_value is Vector2i:
		direction = direction_value
	var direction_label: String = _direction_label(direction)
	var structure_score: int = GFVariantData.get_option_int(candidate, &"structure_score")
	var mobility_score: int = GFVariantData.get_option_int(candidate, &"mobility_score")
	var stability_score: int = GFVariantData.get_option_int(candidate, &"stability_score")
	if structure_score <= 0 and mobility_score <= 0 and stability_score <= 0:
		return "四向结构差异不明显，按固定顺序给出%s；这是通用降级结果。" % direction_label
	if structure_score >= mobility_score and structure_score >= stability_score:
		return (
			"优先考虑%s：发现 %d 组可比较相邻结构；结构分 %d，位移空间分 %d。"
			% [
				direction_label,
				GFVariantData.get_option_int(candidate, &"structure_pair_count"),
				structure_score,
				mobility_score,
			]
		)
	if mobility_score >= stability_score:
		return (
			"优先考虑%s：可压缩 %d 个方块，累计腾挪 %d 格；可比较结构 %d 组。"
			% [
				direction_label,
				GFVariantData.get_option_int(candidate, &"moved_tiles"),
				GFVariantData.get_option_int(candidate, &"displacement"),
				GFVariantData.get_option_int(candidate, &"structure_pair_count"),
			]
		)
	return (
		"优先考虑%s：较高数值位于移动前沿的稳定性信号更强（%d 处）。"
		% [
			direction_label,
			GFVariantData.get_option_int(candidate, &"front_max_tiles"),
		]
	)


func _direction_id(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return &"up"
		Vector2i.LEFT:
			return &"left"
		Vector2i.RIGHT:
			return &"right"
		Vector2i.DOWN:
			return &"down"
		_:
			return &"unknown"


func _direction_label(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return "向上"
		Vector2i.LEFT:
			return "向左"
		Vector2i.RIGHT:
			return "向右"
		Vector2i.DOWN:
			return "向下"
		_:
			return "未知方向"


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)
