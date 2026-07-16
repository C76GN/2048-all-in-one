## GridMovementSystem: 负责处理网格移动、合并逻辑的核心系统。
##
## 该系统监听来自输入层或控制器的移动命令/事件，并执行滑动和合并算法。
## 执行结果将更新 `GridModel` 并可能触发 `board_changed` 等级事件。
class_name GridMovementSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GridMovementSystem"


# --- 私有变量 ---

var _grid_model: GridModel
var _log: GFLogUtility
var _tile_composition_utility: TileCompositionUtility


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_utilities() -> Array[Script]:
	return [GFLogUtility, TileCompositionUtility]


## 从架构获取必要的层级引用。
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

## 处理玩家的滑动输入。
## @param direction: 移动的方向向量 (Vector2i.UP, DOWN, LEFT, RIGHT)
## @return: 如果发生了有效移动，返回包含方向和受影响行/列的 MoveData；否则返回 null。
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
	interaction_rule.setup(_tile_composition_utility)
		
	var grid_size: int = _grid_model.grid_size
	var grid: Array = _grid_model.grid
	
	movement_rule.setup(interaction_rule)

	var instructions: Array[Dictionary] = []
	var new_grid: Array = []
	var _resize_result: Variant = new_grid.resize(grid_size)

	for i: int in range(grid_size):
		var row: Array = []
		var _row_resize_result: Variant = row.resize(grid_size)
		row.fill(null)
		new_grid[i] = row

	var moved_lines_indices: Array[int] = []
	var score_delta: int = 0
	var ratio_resolution_count: int = 0

	# 算法核心：按行/列处理
	for i: int in range(grid_size):
		var line: Array[TileState] = []

		# 提取当前行/列的 TileData 引用
		for j: int in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
			var source_column: Array = grid[coords.x]
			var tile_value: Variant = source_column[coords.y]
			if tile_value is TileState:
				line.append(tile_value)
			else:
				line.append(null)

		# 调用规则引擎计算合并结果
		var result: Dictionary = movement_rule.process_line(line)
		var new_line: Array[TileState] = result.line
		var merges: Array[Dictionary] = result.merges
		var merged_tile_ids: Dictionary = {}

		if result.moved:
			if not i in moved_lines_indices:
				moved_lines_indices.append(i)

		# 记录合并指令 (用于动画)
		for merge_info: Dictionary in merges:
			var consumed: TileState = merge_info.consumed_tile
			var merged: TileState = merge_info.merged_tile
			merged_tile_ids[merged.get_instance_id()] = true
			var final_line_pos: int = new_line.find(merged)
			var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction, grid_size)

			var orig_consumed_idx: int = line.find(consumed)
			var orig_merged_idx: int = line.find(merged)
			var from_coords_consumed: Vector2i = _get_coords_for_line(i, orig_consumed_idx, direction, grid_size)
			var from_coords_merged: Vector2i = _get_coords_for_line(i, orig_merged_idx, direction, grid_size)

			var instruction: Dictionary = {
				&"type": &"MERGE",
				&"consumed_data": consumed,
				&"merged_data": merged,
				&"to_grid_pos": final_coords,
				&"from_grid_pos_consumed": from_coords_consumed,
				&"from_grid_pos_merged": from_coords_merged,
			}
			
			if merge_info.has(&"transform"):
				instruction[&"transform"] = true

			instructions.append(instruction)

			if merge_info.has("score"):
				score_delta += _get_int(merge_info, &"score", 0)
			if merge_info.has("ratio_resolved"):
				ratio_resolution_count += _get_int(merge_info, &"ratio_resolved", 0)

		# 记录移动指令 (用于动画)
		var tiles_in_new_line_ids: Array = []
		for tile_data: TileState in new_line:
			if tile_data != null:
				tiles_in_new_line_ids.append(tile_data.get_instance_id())

		for j: int in range(grid_size):
			var original_data: TileState = line[j]
			if original_data == null or not original_data.get_instance_id() in tiles_in_new_line_ids:
				continue
			if merged_tile_ids.has(original_data.get_instance_id()):
				continue

			var final_line_pos: int = new_line.find(original_data)
			if final_line_pos != -1 and final_line_pos != j:
				var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction, grid_size)
				var from_coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
				instructions.append({
					&"type": &"MOVE",
					&"tile_data": original_data,
					&"from_grid_pos": from_coords,
					&"to_grid_pos": final_coords,
				})

		# 更新临时网格数据
		for j: int in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction, grid_size)
			var target_column: Array = new_grid[coords.x]
			target_column[coords.y] = new_line[j]

	# 如果有任何移动发生
	if not moved_lines_indices.is_empty():
		# 1. 更新 Model 数据
		_grid_model.grid = new_grid

		if score_delta != 0:
			send_simple_event(EventNames.SCORE_UPDATED, score_delta)
		if ratio_resolution_count > 0:
			send_simple_event(EventNames.RATIO_RESOLVED, ratio_resolution_count)

		var result_move_data: MoveData = MoveData.new()
		result_move_data.direction = direction
		result_move_data.moved_lines = moved_lines_indices
		result_move_data.reverse_target_map = _build_reverse_target_map(instructions)

		# 2. 发送动画请求事件 (简单事件)
		send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instructions)

		# 3. 发送移动完成事件 (类型事件，用于触发后续生成逻辑)
		send_event(result_move_data)

		return result_move_data

	return null


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

	for raw_instr: Variant in instructions:
		if not raw_instr is Dictionary:
			continue
		var instr: Dictionary = raw_instr
		var instruction_type: StringName = _get_instruction_type(instr)
		if instruction_type == &"MOVE":
			var from_pos: Vector2i = _get_vector2i(instr, &"from_grid_pos", Vector2i.ZERO)
			reverse_target_map[_grid_pos_key(from_pos)] = _get_vector2i(instr, &"to_grid_pos", from_pos)
		elif instruction_type == &"MERGE":
			var from_consumed: Vector2i = _get_vector2i(instr, &"from_grid_pos_consumed", Vector2i.ZERO)
			var from_merged: Vector2i = _get_vector2i(instr, &"from_grid_pos_merged", Vector2i.ZERO)
			var to_pos: Vector2i = _get_vector2i(instr, &"to_grid_pos", Vector2i.ZERO)
			reverse_target_map[_grid_pos_key(from_consumed)] = to_pos
			reverse_target_map[_grid_pos_key(from_merged)] = to_pos

	return reverse_target_map


func _grid_pos_key(grid_pos: Vector2i) -> String:
	return "%d,%d" % [grid_pos.x, grid_pos.y]


static func _get_instruction_type(data: Dictionary) -> StringName:
	var value: Variant = data.get(&"type", data.get("type", &""))
	if value is StringName:
		return value
	return StringName(str(value))


static func _get_vector2i(data: Dictionary, key: StringName, default_value: Vector2i) -> Vector2i:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is Vector2i:
		return value
	return default_value


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


func _get_coords_for_line(line_index: int, cell_index: int, direction: Vector2i, grid_size: int) -> Vector2i:
	match direction:
		Vector2i.LEFT: return Vector2i(cell_index, line_index)
		Vector2i.RIGHT: return Vector2i(grid_size - 1 - cell_index, line_index)
		Vector2i.UP: return Vector2i(line_index, cell_index)
		Vector2i.DOWN: return Vector2i(line_index, grid_size - 1 - cell_index)
	return Vector2i.ZERO
