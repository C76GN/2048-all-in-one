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


# --- 公共方法 ---

## 处理玩家的四向滑动输入，返回唯一的强类型回合结果。
## @param direction: LEFT、RIGHT、UP、DOWN 之一。
func handle_move(direction: Vector2i) -> TurnResult:
	if not is_instance_valid(_grid_model):
		_log_error("GridModel 引用不可用。")
		return null

	var interaction_rule: InteractionRule = _grid_model.interaction_rule
	var movement_rule: MovementRule = _grid_model.movement_rule
	if not is_instance_valid(interaction_rule) or not is_instance_valid(movement_rule):
		_log_error("GridModel 缺少交互规则或移动规则。")
		return null
	var topology: BoardTopology = _grid_model.topology
	if not is_instance_valid(topology):
		_log_error("GridModel 缺少 BoardTopology。")
		return null

	interaction_rule.setup(_tile_composition_utility)
	movement_rule.setup(interaction_rule)

	var lanes: Array = topology.get_move_lanes(direction)
	if lanes.is_empty():
		return null

	var turn_result: TurnResult = TurnResult.new()
	turn_result.direction = direction
	var next_tiles_by_cell: Dictionary = {}

	# 每个连续 lane 独立处理，拓扑空洞不会被跨越。
	for lane_value: Variant in lanes:
		if not lane_value is Array:
			_log_error("棋盘拓扑返回了非数组 lane。")
			return null
		var lane: Array[Vector2i] = []
		for coords_value: Variant in lane_value:
			if not coords_value is Vector2i:
				_log_error("棋盘拓扑 lane 包含非 Vector2i 坐标。")
				return null
			var coords: Vector2i = coords_value
			lane.append(coords)
		var line: Array[TileState] = []
		for coords: Vector2i in lane:
			line.append(_grid_model.get_tile(coords))

		var line_result: MovementLineResult = movement_rule.process_line(line)
		if line_result == null or line_result.line.size() != lane.size():
			_log_error("移动规则返回了无效 lane 结果。")
			return null
		if line_result.moved:
			turn_result.moved_lanes.append(lane.duplicate())

		var merged_tile_ids: Dictionary = {}
		for interaction: TileInteractionResult in line_result.interactions:
			if interaction == null or not interaction.is_valid_result():
				continue
			var final_line_pos: int = line_result.line.find(interaction.survivor)
			var consumed_index: int = line.find(interaction.consumed)
			var survivor_index: int = line.find(interaction.survivor)
			if (
				final_line_pos < 0
				or consumed_index < 0
				or survivor_index < 0
			):
				_log_error("交互结果无法映射回原始 lane。")
				return null
			merged_tile_ids[interaction.survivor.get_instance_id()] = true
			var merge_result: TileMergeResult = TileMergeResult.new()
			merge_result.interaction = interaction
			merge_result.consumed_from_cell = lane[consumed_index]
			merge_result.survivor_from_cell = lane[survivor_index]
			merge_result.to_cell = lane[final_line_pos]
			turn_result.add_merge(merge_result)

		var tiles_in_new_line_ids: Dictionary = {}
		for tile_data: TileState in line_result.line:
			if tile_data != null:
				tiles_in_new_line_ids[tile_data.get_instance_id()] = true

		for index: int in range(line.size()):
			var original_data: TileState = line[index]
			if (
				original_data == null
				or not tiles_in_new_line_ids.has(original_data.get_instance_id())
				or merged_tile_ids.has(original_data.get_instance_id())
			):
				continue
			var final_line_pos: int = line_result.line.find(original_data)
			if final_line_pos >= 0 and final_line_pos != index:
				turn_result.movements.append(
					TileMovementResult.new(original_data, lane[index], lane[final_line_pos])
				)

		for index: int in range(line_result.line.size()):
			var tile: TileState = line_result.line[index]
			if tile != null:
				next_tiles_by_cell[lane[index]] = tile

	if not turn_result.is_effective() or turn_result.moved_lanes.is_empty():
		return null
	if not _grid_model.replace_tiles(next_tiles_by_cell):
		_log_error("移动结果不符合当前棋盘拓扑，拒绝提交。")
		return null

	if turn_result.score_delta != 0:
		send_simple_event(EventNames.SCORE_UPDATED, turn_result.score_delta)
	if turn_result.ratio_resolution_count > 0:
		send_simple_event(
			EventNames.RATIO_RESOLVED,
			turn_result.ratio_resolution_count
		)

	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, turn_result)
	send_event(turn_result)
	return turn_result


# --- 私有/辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		return model_value
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		return utility_value
	return null


func _log_error(message: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, message)
	else:
		push_error("[%s] %s" % [_LOG_TAG, message])
