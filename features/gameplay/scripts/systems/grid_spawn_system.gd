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


# --- Godot 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_utilities() -> Array[Script]:
	return [GFLogUtility, GFSeedUtility]


func ready() -> void:
	_grid_model = _get_grid_model()
	_seed_utility = _get_seed_utility()
	_log = _get_log_utility()
	register_simple_event(EventNames.SPAWN_TILE_REQUESTED, GFEventListener.from_method(self, &"_on_spawn_tile_requested", 1))


func dispose() -> void:
	_grid_model = null
	_seed_utility = null
	_log = null


# --- 私有/辅助方法 ---

func _is_auto_position(position: Vector2i) -> bool:
	return position.x < 0 or position.y < 0


func _is_cell_in_bounds(position: Vector2i) -> bool:
	return (
		position.x >= 0
		and position.y >= 0
		and position.x < _grid_model.grid_size
		and position.y < _grid_model.grid_size
	)


func _is_cell_empty(position: Vector2i) -> bool:
	var column: Array = _grid_model.grid[position.x]
	return column[position.y] == null


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


func _handle_priority_spawn(value: int, type: Tile.TileType) -> void:
	var player_data_list: Array[GameTileData] = []
	for x: int in range(_grid_model.grid_size):
		var column: Array = _grid_model.grid[x]
		for y: int in range(_grid_model.grid_size):
			var raw_data: Variant = column[y]
			var data: GameTileData = null
			if raw_data is GameTileData:
				data = raw_data
			if data != null and data.type == Tile.TileType.PLAYER:
				player_data_list.append(data)

	if not player_data_list.is_empty():
		var player_random: GFDeterministicRandom = _seed_utility.get_branched_deterministic_random(
			"game_board_priority_player"
		)
		var player_index: int = player_random.next_int_range(0, player_data_list.size() - 1)
		var data_to_transform: GameTileData = player_data_list[player_index]
		
		# 数据更新
		data_to_transform.value = value
		data_to_transform.type = type
		
		var instruction: Array = [ {
			&"type": &"TRANSFORM",
			&"tile_data": data_to_transform,
			&"do_transform": true,
		}]
		send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)
	else:
		var monster_data_list: Array[GameTileData] = []
		for x: int in range(_grid_model.grid_size):
			var column: Array = _grid_model.grid[x]
			for y: int in range(_grid_model.grid_size):
				var raw_data: Variant = column[y]
				var data: GameTileData = null
				if raw_data is GameTileData:
					data = raw_data
				if data != null and data.type == Tile.TileType.MONSTER:
					monster_data_list.append(data)
					
		if not monster_data_list.is_empty():
			var monster_random: GFDeterministicRandom = _seed_utility.get_branched_deterministic_random(
				"game_board_priority_monster"
			)
			var monster_index: int = monster_random.next_int_range(0, monster_data_list.size() - 1)
			var data_to_empower: GameTileData = monster_data_list[monster_index]
			
			data_to_empower.value *= 2
			
			var instruction: Array = [ {
				&"type": &"TRANSFORM",
				&"tile_data": data_to_empower,
				&"do_merge": true,
				&"do_transform": false,
			}]
			send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)


# --- 信号处理函数 ---

func _on_spawn_tile_requested(spawn_data: SpawnData) -> void:
	if not is_instance_valid(spawn_data):
		return

	if not is_instance_valid(_grid_model) or not is_instance_valid(_seed_utility):
		return

	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "收到生成请求: value=%d, type=%d, position=%s" % [spawn_data.value, spawn_data.type, spawn_data.position])

	var value: int = spawn_data.value
	var type: Tile.TileType = spawn_data.type
	var is_priority: bool = spawn_data.is_priority
	var spawn_pos: Vector2i

	if not _is_auto_position(spawn_data.position):
		spawn_pos = spawn_data.position
		if not _is_cell_in_bounds(spawn_pos):
			if is_instance_valid(_log):
				_log.warn(_LOG_TAG, "忽略越界生成请求: %s" % spawn_pos)
			return
		if not _is_cell_empty(spawn_pos):
			if is_priority:
				_handle_priority_spawn(value, type)
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
				_handle_priority_spawn(value, type)
			return

	# 2. 写入数据模型
	var tile_data: GameTileData = GameTileData.new(value, type)
	_grid_model.place_tile(tile_data, spawn_pos)

	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已生成方块: value=%d, type=%d, position=%s, empty_cells=%d" % [value, type, spawn_pos, _grid_model.get_empty_cells().size()])

	# 3. 发送视觉指令
	var instruction: Array = [ {
		&"type": &"SPAWN",
		&"tile_data": tile_data,
		&"to_grid_pos": spawn_pos,
	}]
	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)
