## GridSpawnSystem: 负责处理方块生成的系统。
##
## 该系统监听 `EventNames.SPAWN_TILE_REQUESTED` 事件，处理方块生成的逻辑（如网格空余判定、位置打乱），
## 将数据写入 `GridModel`，最后发送纯表现层的指令给视觉系统。
class_name GridSpawnSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "GridSpawnSystem"


# --- 私有变量 ---

var _grid_model: GridModel
var _seed_utility: GFSeedUtility
var _log: GFLogUtility
var _tile_composition_utility: TileCompositionUtility


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_utilities() -> Array[Script]:
	return [GFLogUtility, GFSeedUtility, TileCompositionUtility]


func ready() -> void:
	_grid_model = _get_grid_model()
	_seed_utility = _get_seed_utility()
	_log = _get_log_utility()
	_tile_composition_utility = _get_tile_composition_utility()
	register_simple_event(EventNames.SPAWN_TILE_REQUESTED, GFEventListener.from_method(self, &"_on_spawn_tile_requested", 1))


func dispose() -> void:
	_grid_model = null
	_seed_utility = null
	_log = null
	_tile_composition_utility = null


# --- 私有/辅助方法 ---

func _is_auto_position(position: Vector2i) -> bool:
	return position.x < 0 or position.y < 0


func _is_cell_active(position: Vector2i) -> bool:
	return is_instance_valid(_grid_model) and _grid_model.is_active_cell(position)


func _is_cell_empty(position: Vector2i) -> bool:
	return _grid_model.get_tile(position) == null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_tile_composition_utility() -> TileCompositionUtility:
	var utility_value: Variant = get_utility(TileCompositionUtility)
	if utility_value is TileCompositionUtility:
		var composition_utility: TileCompositionUtility = utility_value
		return composition_utility
	return null


func _handle_priority_spawn(value: int, definition_id: StringName) -> void:
	var interaction_rule: InteractionRule = _grid_model.interaction_rule
	if interaction_rule == null:
		return
	var next_definition: TileDefinition = interaction_rule.get_tile_definition(definition_id)
	if next_definition == null:
		next_definition = interaction_rule.get_default_tile_definition()
	if next_definition == null:
		return

	var recompose_candidates: Array[TileState] = []
	var same_definition_candidates: Array[TileState] = []
	for data: TileState in _grid_model.get_all_tiles():
		if data.definition_id == next_definition.definition_id:
			same_definition_candidates.append(data)
		else:
			recompose_candidates.append(data)

	if not recompose_candidates.is_empty():
		var recompose_random: GFDeterministicRandom = _seed_utility.get_branched_deterministic_random(
			"game_board_priority_recompose"
		)
		var candidate_index: int = recompose_random.next_int_range(0, recompose_candidates.size() - 1)
		var data_to_transform: TileState = recompose_candidates[candidate_index]
		var current_definition: TileDefinition = interaction_rule.get_tile_definition(
			data_to_transform.definition_id
		)
		if (
			current_definition == null
			or not _tile_composition_utility.recompose_tile(
				data_to_transform,
				current_definition,
				next_definition
			)
		):
			if is_instance_valid(_log):
				_log.error(_LOG_TAG, "优先生成无法重组为目标方块定义。")
			return

		data_to_transform.value = value
		var instruction: Array = [{
			&"type": &"TRANSFORM",
			&"tile_data": data_to_transform,
			&"do_transform": true,
		}]
		send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)
		return

	if same_definition_candidates.is_empty():
		return
	var empower_random: GFDeterministicRandom = _seed_utility.get_branched_deterministic_random(
		"game_board_priority_empower"
	)
	var empower_index: int = empower_random.next_int_range(0, same_definition_candidates.size() - 1)
	var data_to_empower: TileState = same_definition_candidates[empower_index]
	data_to_empower.value = maxi(value, data_to_empower.value * 2)
	var empower_instruction: Array = [{
		&"type": &"TRANSFORM",
		&"tile_data": data_to_empower,
		&"do_merge": true,
		&"do_transform": false,
	}]
	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, empower_instruction)


# --- 信号处理函数 ---

func _on_spawn_tile_requested(spawn_data: SpawnData) -> void:
	if not is_instance_valid(spawn_data):
		return

	if (
		not is_instance_valid(_grid_model)
		or not is_instance_valid(_seed_utility)
		or not is_instance_valid(_tile_composition_utility)
	):
		return
	if spawn_data.value <= 0:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "拒绝生成非正数方块。")
		return

	if is_instance_valid(_log):
		_log.debug(
			_LOG_TAG,
			"收到生成请求: value=%d, definition_id=%s, position=%s" % [
				spawn_data.value,
				spawn_data.definition_id,
				spawn_data.position,
			]
		)

	var value: int = spawn_data.value
	var definition_id: StringName = spawn_data.definition_id
	var is_priority: bool = spawn_data.is_priority
	var spawn_pos: Vector2i

	if not _is_auto_position(spawn_data.position):
		spawn_pos = spawn_data.position
		if not _is_cell_active(spawn_pos):
			if is_instance_valid(_log):
				_log.warn(_LOG_TAG, "忽略非活跃单元生成请求: %s" % spawn_pos)
			return
		if not _is_cell_empty(spawn_pos):
			if is_priority:
				_handle_priority_spawn(value, definition_id)
			elif is_instance_valid(_log):
				_log.warn(_LOG_TAG, "忽略被占用的生成位置: %s" % spawn_pos)
			return
	else:
		var empty_cells: Array[Vector2i] = _grid_model.get_empty_cells()
		if not empty_cells.is_empty():
			var spawn_random: GFDeterministicRandom = _seed_utility.get_branched_deterministic_random(
				"game_board_spawn"
			)
			spawn_pos = empty_cells[spawn_random.next_int_range(0, empty_cells.size() - 1)]
		else:
			if is_priority:
				_handle_priority_spawn(value, definition_id)
			return

	# 2. 写入数据模型
	var interaction_rule: InteractionRule = _grid_model.interaction_rule
	if interaction_rule == null:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "无法生成方块：当前棋盘缺少交互规则。")
		return
	var definition: TileDefinition = interaction_rule.get_tile_definition(definition_id)
	if definition == null:
		definition = interaction_rule.get_default_tile_definition()
	var tile_data: TileState = _tile_composition_utility.create_tile(definition, value)
	if tile_data == null:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "无法按当前模式的 TileDefinition 创建方块。")
		return
	if not _grid_model.place_tile(tile_data, spawn_pos):
		_tile_composition_utility.release_tile(tile_data)
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "方块无法放入目标活跃单元：%s。" % spawn_pos)
		return

	if is_instance_valid(_log):
		_log.debug(
			_LOG_TAG,
			"已生成方块: value=%d, definition_id=%s, position=%s, empty_cells=%d" % [
				value,
				definition.definition_id,
				spawn_pos,
				_grid_model.get_empty_cells().size(),
			]
		)

	# 3. 发送视觉指令
	var instruction: Array = [ {
		&"type": &"SPAWN",
		&"tile_data": tile_data,
		&"to_grid_pos": spawn_pos,
	}]
	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)
