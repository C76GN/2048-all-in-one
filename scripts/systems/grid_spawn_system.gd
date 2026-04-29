## GridSpawnSystem: 负责处理方块生成的系统。
##
## 该系统监听 `EventNames.SPAWN_TILE_REQUESTED` 事件，处理方块生成的逻辑（如网格空余判定、位置打乱），
## 将数据写入 `GridModel`，最后发送纯表现层的指令给视觉系统。
class_name GridSpawnSystem
extends GFSystem

# --- 私有变量 ---
var _grid_model: GridModel
var _seed_utility: GFSeedUtility
var _log: GFLogUtility

# --- Godot 生命周期方法 ---

func ready() -> void:
	_grid_model = get_model(GridModel) as GridModel
	_seed_utility = get_utility(GFSeedUtility) as GFSeedUtility
	_log = get_utility(GFLogUtility) as GFLogUtility
	register_simple_event(EventNames.SPAWN_TILE_REQUESTED, _on_spawn_tile_requested)

func dispose() -> void:
	unregister_simple_event(EventNames.SPAWN_TILE_REQUESTED, _on_spawn_tile_requested)

# --- 事件处理 ---

func _on_spawn_tile_requested(spawn_data: SpawnData) -> void:
	if not is_instance_valid(spawn_data):
		return

	if not is_instance_valid(_grid_model) or not is_instance_valid(_seed_utility):
		return

	if _log:
		_log.info("GridSpawnSystem", "spawn_tile called for value: %d at %s" % [spawn_data.value, spawn_data.position])

	var value: int = spawn_data.value
	var type: Tile.TileType = spawn_data.type
	var is_priority: bool = spawn_data.is_priority
	var spawn_pos: Vector2i

	if not _is_auto_position(spawn_data.position):
		spawn_pos = spawn_data.position
		if not _is_cell_in_bounds(spawn_pos):
			if _log:
				_log.warn("GridSpawnSystem", "忽略越界生成请求: %s" % spawn_pos)
			return
		if not _is_cell_empty(spawn_pos):
			if is_priority:
				_handle_priority_spawn(value, type)
			elif _log:
				_log.warn("GridSpawnSystem", "忽略被占用的生成位置: %s" % spawn_pos)
			return
	else:
		var empty_cells: Array[Vector2i] = _grid_model.get_empty_cells()
		if not empty_cells.is_empty():
			spawn_pos = empty_cells[_seed_utility.get_branched_rng("game_board_spawn").randi_range(0, empty_cells.size() - 1)]
		else:
			if is_priority:
				_handle_priority_spawn(value, type)
			return

	# 2. 写入数据模型
	var tile_data := GameTileData.new(value, type)
	_grid_model.place_tile(tile_data, spawn_pos)
	
	if _log:
		_log.info("GridSpawnSystem", "Spawned tile value=%d at %s, empty_cells_after=%d" % [value, spawn_pos, _grid_model.get_empty_cells().size()])
	
	# 3. 发送视觉指令
	var instruction: Array = [ {
		&"type": &"SPAWN",
		&"tile_data": tile_data,
		&"to_grid_pos": spawn_pos
	}]
	send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)


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
	return _grid_model.grid[position.x][position.y] == null


func _handle_priority_spawn(value: int, type: Tile.TileType) -> void:
	var player_data_list: Array[GameTileData] = []
	for x in _grid_model.grid_size:
		for y in _grid_model.grid_size:
			var data := _grid_model.grid[x][y] as GameTileData
			if data != null and data.type == Tile.TileType.PLAYER:
				player_data_list.append(data)

	if not player_data_list.is_empty():
		var data_to_transform: GameTileData = player_data_list[_seed_utility.get_branched_rng("game_board_priority_player").randi_range(0, player_data_list.size() - 1)]
		
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
		for x in _grid_model.grid_size:
			for y in _grid_model.grid_size:
				var data := _grid_model.grid[x][y] as GameTileData
				if data != null and data.type == Tile.TileType.MONSTER:
					monster_data_list.append(data)
					
		if not monster_data_list.is_empty():
			var data_to_empower: GameTileData = monster_data_list[_seed_utility.get_branched_rng("game_board_priority_monster").randi_range(0, monster_data_list.size() - 1)]
			
			data_to_empower.value *= 2
			
			var instruction: Array = [ {
				&"type": &"TRANSFORM",
				&"tile_data": data_to_empower,
				&"do_merge": true,
				&"do_transform": false,
			}]
			send_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, instruction)
