## GridMovementSystem: 按 BoardTopology 的连续 lane 处理移动与合并。
class_name GridMovementSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GridMovementSystem"


# --- 私有变量 ---

var _grid_model: GridModel
var _log: GFLogUtility
var _tile_composition_utility: TileCompositionUtility


# --- GF 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_utilities() -> Array[Script]:
	return [GFLogUtility, TileCompositionUtility]


func ready() -> void:
	_grid_model = _get_grid_model()
	_log = _get_log_utility()
	var utility_value: Variant = get_utility(TileCompositionUtility)
	if utility_value is TileCompositionUtility:
		_tile_composition_utility = utility_value


func dispose() -> void:
	_grid_model = null
	_log = null
	_tile_composition_utility = null


# --- 核心逻辑 ---

## 处理玩家的四向滑动输入。
## @param direction: LEFT、RIGHT、UP、DOWN 之一。
func handle_move(direction: Vector2i) -> MoveData:
	if not is_instance_valid(_grid_model):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GridModel 引用不可用。")
		return null

	var interaction_rule: InteractionRule = _grid_model.interaction_rule
	var movement_rule: MovementRule = _grid_model.movement_rule
	if not is_instance_valid(interaction_rule) or not is_instance_valid(movement_rule):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GridModel 缺少交互规则或移动规则。")
		return null
	var topology: BoardTopology = _grid_model.topology
	if not is_instance_valid(topology):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GridModel 缺少 BoardTopology。")
		return null

	interaction_rule.setup(_tile_composition_utility)
	movement_rule.setup(interaction_rule)

	var lanes: Array = topology.get_move_lanes(direction)
	if lanes.is_empty():
		return null

	var instructions: Array[Dictionary] = []
	var next_tiles_by_cell: Dictionary = {}
	var moved_lanes: Array = []
	var score_delta: int = 0
	var ratio_resolution_count: int = 0
	var merge_count: int = 0
	var max_merge_value: int = 0

	# 每个连续 lane 独立处理，拓扑空洞不会被跨越。
	for lane_value: Variant in lanes:
		if not lane_value is Array:
			continue
		var lane: Array = lane_value
		var line: Array[TileState] = []
		for coords_value: Variant in lane:
			if not coords_value is Vector2i:
				line.append(null)
				continue
			var coords: Vector2i = coords_value
			line.append(_grid_model.get_tile(coords))

		var result: Dictionary = movement_rule.process_line(line)
		var new_line: Array[TileState] = _get_tile_line(result, &"line")
		var merges: Array[Dictionary] = _get_dictionary_array(result, &"merges")
		var merged_tile_ids: Dictionary = {}

		if GFVariantData.get_option_bool(result, &"moved", false):
			moved_lanes.append(lane.duplicate())

		for merge_info: Dictionary in merges:
			var consumed: TileState = _get_tile_state(merge_info, &"consumed_tile")
			var merged: TileState = _get_tile_state(merge_info, &"merged_tile")
			if consumed == null or merged == null:
				continue
			merged_tile_ids[merged.get_instance_id()] = true

			var final_line_pos: int = new_line.find(merged)
			var orig_consumed_idx: int = line.find(consumed)
			var orig_merged_idx: int = line.find(merged)
			if (
				final_line_pos < 0
				or final_line_pos >= lane.size()
				or orig_consumed_idx < 0
				or orig_merged_idx < 0
			):
				continue

			var merge_score_delta: int = _get_int(merge_info, &"score", 0)
			var instruction: Dictionary = {
				&"type": &"MERGE",
				&"consumed_data": consumed,
				&"merged_data": merged,
				&"to_grid_pos": lane[final_line_pos],
				&"from_grid_pos_consumed": lane[orig_consumed_idx],
				&"from_grid_pos_merged": lane[orig_merged_idx],
				&"score_delta": merge_score_delta,
			}
			if merge_info.has(&"transform"):
				instruction[&"transform"] = true
			instructions.append(instruction)
			score_delta += merge_score_delta
			merge_count += 1
			max_merge_value = maxi(max_merge_value, merged.value)
			ratio_resolution_count += _get_int(merge_info, &"ratio_resolved", 0)

		var tiles_in_new_line_ids: Dictionary = {}
		for tile_data: TileState in new_line:
			if tile_data != null:
				tiles_in_new_line_ids[tile_data.get_instance_id()] = true

		for index: int in range(line.size()):
			var original_data: TileState = line[index]
			if original_data == null or not tiles_in_new_line_ids.has(original_data.get_instance_id()):
				continue
			if merged_tile_ids.has(original_data.get_instance_id()):
				continue
			var final_line_pos: int = new_line.find(original_data)
			if final_line_pos != -1 and final_line_pos != index:
				instructions.append({
					&"type": &"MOVE",
					&"tile_data": original_data,
					&"from_grid_pos": lane[index],
					&"to_grid_pos": lane[final_line_pos],
				})

		for index: int in range(mini(lane.size(), new_line.size())):
			var tile: TileState = new_line[index]
			if tile != null:
				next_tiles_by_cell[lane[index]] = tile

	if moved_lanes.is_empty():
		return null
	if not _grid_model.replace_tiles(next_tiles_by_cell):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "移动结果不符合当前棋盘拓扑，拒绝提交。")
		return null

	# 同一事务的表现元数据写入每条指令，动画队列只需读取首条即可编排整屏反馈。
	for instruction: Dictionary in instructions:
		instruction[&"move_direction"] = direction
		instruction[&"turn_merge_count"] = merge_count
		instruction[&"turn_max_merge_value"] = max_merge_value
		instruction[&"turn_score_delta"] = score_delta

	if score_delta != 0:
		send_simple_event(EventNames.SCORE_UPDATED, score_delta)
	if ratio_resolution_count > 0:
		send_simple_event(EventNames.RATIO_RESOLVED, ratio_resolution_count)

	var move_data: MoveData = MoveData.new()
	move_data.direction = direction
	move_data.moved_lanes = moved_lanes
	move_data.reverse_target_map = _build_reverse_target_map(instructions)

	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instructions)
	send_event(move_data)
	return move_data


# --- 辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _build_reverse_target_map(instructions: Array) -> Dictionary:
	var reverse_target_map: Dictionary = {}
	for raw_instruction: Variant in instructions:
		if not raw_instruction is Dictionary:
			continue
		var instruction: Dictionary = raw_instruction
		var instruction_type: StringName = _get_instruction_type(instruction)
		if instruction_type == &"MOVE":
			var from_pos: Vector2i = _get_vector2i(instruction, &"from_grid_pos", Vector2i.ZERO)
			reverse_target_map[_grid_pos_key(from_pos)] = _get_vector2i(
				instruction,
				&"to_grid_pos",
				from_pos
			)
		elif instruction_type == &"MERGE":
			var consumed_pos: Vector2i = _get_vector2i(
				instruction,
				&"from_grid_pos_consumed",
				Vector2i.ZERO
			)
			var merged_pos: Vector2i = _get_vector2i(
				instruction,
				&"from_grid_pos_merged",
				Vector2i.ZERO
			)
			var target_pos: Vector2i = _get_vector2i(
				instruction,
				&"to_grid_pos",
				Vector2i.ZERO
			)
			reverse_target_map[_grid_pos_key(consumed_pos)] = target_pos
			reverse_target_map[_grid_pos_key(merged_pos)] = target_pos
	return reverse_target_map


static func _grid_pos_key(grid_pos: Vector2i) -> String:
	return "%d,%d" % [grid_pos.x, grid_pos.y]


static func _get_instruction_type(data: Dictionary) -> StringName:
	var value: Variant = data.get(&"type", data.get("type", &""))
	if value is StringName:
		return value
	return StringName(str(value))


static func _get_vector2i(
	data: Dictionary,
	key: StringName,
	default_value: Vector2i
) -> Vector2i:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	return value if value is Vector2i else default_value


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


static func _get_tile_state(data: Dictionary, key: StringName) -> TileState:
	var value: Variant = data.get(key, data.get(String(key)))
	if value is TileState:
		var tile: TileState = value
		return tile
	return null


static func _get_tile_line(data: Dictionary, key: StringName) -> Array[TileState]:
	var result: Array[TileState] = []
	var value: Variant = data.get(key, data.get(String(key), []))
	if not value is Array:
		return result
	for item: Variant in value:
		if item == null or item is TileState:
			result.append(item)
	return result


static func _get_dictionary_array(data: Dictionary, key: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var value: Variant = data.get(key, data.get(String(key), []))
	if not value is Array:
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append(item)
	return result
