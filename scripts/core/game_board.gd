# scripts/core/game_board.gd

## GameBoard: 负责游戏棋盘的视觉呈现和输入转发。
##
## 它持有 GridModel (逻辑核心)，并根据 Model 的信号更新 Tile 节点的位置和状态。
## 它是 Model 的 View。
class_name GameBoard
extends GFController


# --- 信号 ---

## 当需要播放一组动画时发出。
## @param instructions: 一个包含动画指令字典的数组。
signal play_animations_requested(instructions: Array)


# --- 常量 ---

## 预加载方块场景，用于在运行时动态实例化。
const TileScene: PackedScene = preload("res://scenes/components/tile.tscn")

## 每个单元格的像素尺寸。
const CELL_SIZE: int = 100

## 单元格之间的间距。
const SPACING: int = 15

## 棋盘背景的内边距。
const BOARD_PADDING: int = 15


# --- 导出变量 ---

## 用于生成棋盘背景格子的场景文件。
@export var grid_cell_scene: PackedScene = preload("res://scenes/components/board_grid_cell.tscn")


# --- 公共变量 ---

## 逻辑模型引用。
var model: GridModel

## 外部注入的配色方案字典。
var color_schemes: Dictionary

## 外部注入的棋盘与背景主题。
var board_theme: BoardTheme


# --- 私有变量 ---

## 逻辑数据到视觉节点的映射字典 { GameTileData: Tile }
var _visual_map: Dictionary = {}

## 防止在窗口大小改变时重复初始化棋盘。
var _is_initialized: bool = false

var _log: GFLogUtility

## 标记是否已完成清理。
var _is_cleaned_up: bool = false


# --- @onready 变量 (节点引用) ---

@onready var board_background: Panel = %BoardBackground
@onready var board_container: Node2D = %BoardContainer


# --- Godot 生命周期方法 ---

func _ready() -> void:
	model = get_model(GridModel) as GridModel
	_log = get_utility(GFLogUtility) as GFLogUtility
	
	var parent_control := get_parent() as Control
	if is_instance_valid(parent_control):
		parent_control.resized.connect(_on_resized)
	
	# --- 注册 GF 事件监听 ---
	Gf.listen_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_board_animation_requested)
	Gf.listen_simple(EventNames.BOARD_REFRESH_REQUESTED, _on_board_refresh_requested)
	Gf.listen_simple(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)


func _exit_tree() -> void:
	_cleanup_listeners()


# --- 公共方法 ---

## 设置并初始化棋盘。
## @param p_grid_size: 棋盘尺寸。
## @param p_interaction_rule: 交互规则实例。
## @param p_movement_rule: 移动规则实例。
## @param p_game_over_rule: 游戏结束规则。
## @param p_color_schemes: 配色方案字典。
## @param p_board_theme: 棋盘主题。
func setup(p_grid_size: int, p_interaction_rule: InteractionRule, p_movement_rule: MovementRule, _p_game_over_rule: GameOverRule, p_color_schemes: Dictionary, p_board_theme: BoardTheme) -> void:
	# 清理上一局遗留的方块节点和映射，防止幽灵方块
	var old_tile_count: int = 0
	var pool := get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
	for child in board_container.get_children():
		if child is Tile:
			old_tile_count += 1
			if pool:
				pool.release(child, TileScene)
				child.visible = false
			else:
				child.queue_free()
	
	if _log:
		_log.info("GameBoard", "setup() - Cleaned %d old tiles, _visual_map had %d entries" % [old_tile_count, _visual_map.size()])
	
	_visual_map.clear()
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme

	model.initialize(p_grid_size, p_interaction_rule, p_movement_rule)

	call_deferred(&"_update_board_layout")
	_draw_board_cells()
	_is_initialized = true


## 根据 spawn_data 生成方块（由 RuleManager 调用）。
## @param spawn_data: 包含生成信息的强类型数据对象。
func spawn_tile(spawn_data: SpawnData) -> void:
	if not is_instance_valid(spawn_data):
		return

	if _log:
		_log.info("GameBoard", "spawn_tile called for value: %d at %s" % [spawn_data.value, spawn_data.position])

	var value: int = spawn_data.value
	var type: Tile.TileType = spawn_data.type
	var is_priority: bool = spawn_data.is_priority
	var spawn_pos: Vector2i

	if spawn_data.position.x >= 0:
		spawn_pos = spawn_data.position
	else:
		var seed_util := get_utility(GFSeedUtility) as GFSeedUtility
		var empty_cells: Array[Vector2i] = model.get_empty_cells()
		if not empty_cells.is_empty():
			spawn_pos = empty_cells[seed_util.get_branched_rng("game_board_spawn").randi_range(0, empty_cells.size() - 1)]
		else:
			if is_priority:
				_handle_priority_spawn(value, type)
			return

	var new_tile: Tile = _create_visual_tile(value, type)
	var tile_data := GameTileData.new(value, type)
	_visual_map[tile_data] = new_tile
	model.place_tile(tile_data, spawn_pos)
	
	if _log:
		_log.info("GameBoard", "Spawned tile value=%d at %s, _visual_map.size=%d, empty_cells_after=%d" % [value, spawn_pos, _visual_map.size(), model.get_empty_cells().size()])
	
	new_tile.position = _grid_to_pixel_center(spawn_pos)
	new_tile.scale = Vector2.ZERO
	var instruction: Array = [ {&"type": &"SPAWN", &"tile": new_tile}]
	play_animations_requested.emit(instruction)


## 获取当前棋盘上数值最大的玩家方块的值。
## @return: 最大的玩家方块数值。
func get_max_player_value() -> int:
	if not model:
		return 0
	return model.get_max_player_value()


## 在指定网格位置生成一个特定方块，主要用于测试。
## @param grid_pos: 生成位置的网格坐标。
## @param value: 生成方块的数值。
## @param type: 生成方块的类型。
func spawn_specific_tile(grid_pos: Vector2i, value: int, type: Tile.TileType) -> void:
	if not model:
		return
	if not (grid_pos.x >= 0 and grid_pos.x < model.grid_size and grid_pos.y >= 0 and grid_pos.y < model.grid_size):
		if _log:
			_log.error("GameBoard", "Spawn position is out of bounds.")
		return

	if model.grid[grid_pos.x][grid_pos.y] != null:
		var old_data: GameTileData = model.grid[grid_pos.x][grid_pos.y]
		if _visual_map.has(old_data):
			var tile_node := _visual_map[old_data] as Tile
			var pool := get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
			if pool:
				pool.release(tile_node, TileScene)
				tile_node.visible = false
			else:
				tile_node.queue_free()
			_visual_map.erase(old_data)
		model.grid[grid_pos.x][grid_pos.y] = null

	var new_tile: Tile = _create_visual_tile(value, type)
	var tile_data := GameTileData.new(value, type)
	_visual_map[tile_data] = new_tile
	model.place_tile(tile_data, grid_pos)
	
	new_tile.position = _grid_to_pixel_center(grid_pos)
	new_tile.scale = Vector2.ZERO
	var instruction: Array = [ {&"type": &"SPAWN", &"tile": new_tile}]
	play_animations_requested.emit(instruction)


## 游戏中扩建棋盘。
## @param new_size: 新的棋盘尺寸。
func live_expand(new_size: int) -> void:
	if not model:
		return
	var old_size: int = model.grid_size
	model.expand_grid(new_size)
	_animate_expansion(old_size, new_size)
	Gf.send_simple_event(EventNames.BOARD_RESIZED, new_size)


## 遍历整个网格，返回所有空格子坐标的数组。
## @return: 一个包含所有空单元格 Vector2i 坐标的数组。
func get_empty_cells() -> Array[Vector2i]:
	if not model:
		return []
	return model.get_empty_cells()


## 遍历整个网格，返回所有玩家方块数值的数组。
## @return: 一个已排序的、包含所有玩家方块数值的数组。
func get_all_player_tile_values() -> Array[int]:
	if not model:
		return []
	return model.get_all_player_tile_values()


## 获取当前棋盘所有方块状态的可序列化快照。
## @return: 一个字典，包含grid_size和所有方块的数据。
func get_state_snapshot() -> Dictionary:
	if not model:
		return {"grid_size": 4, "tiles": []}
	return model.get_snapshot()


## 从快照恢复。
## @param snapshot: 包含棋盘状态的字典。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	var pool := get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
	for child in board_container.get_children():
		if child is Tile:
			if pool:
				pool.release(child, TileScene)
				child.visible = false
			else:
				child.queue_free()

	_visual_map.clear()

	if not model:
		return

	var grid_size: int = snapshot.get(&"grid_size", 4)
	var interaction_rule: InteractionRule = model.interaction_rule
	var movement_rule: MovementRule = model.movement_rule
	model.initialize(grid_size, interaction_rule, movement_rule)

	var tiles_data: Array = snapshot.get(&"tiles", [])
	for tile_data_snapshot in tiles_data:
		var pos: Vector2i = tile_data_snapshot[&"pos"]
		var value: int = tile_data_snapshot[&"value"]
		var type: Tile.TileType = tile_data_snapshot[&"type"]

		var new_tile: Tile = _create_visual_tile(value, type)
		var tile_data := GameTileData.new(value, type)
		_visual_map[tile_data] = new_tile
		
		new_tile.position = _grid_to_pixel_center(pos)
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0

		model.place_tile(tile_data, pos)


# --- 私有/辅助方法 ---

func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	Gf.unlisten_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_board_animation_requested)
	Gf.unlisten_simple(EventNames.BOARD_REFRESH_REQUESTED, _on_board_refresh_requested)
	Gf.unlisten_simple(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	if _log:
		_log.info("GameBoard", "_cleanup_listeners: cleaned up GF listeners")


func _create_visual_tile(value: int, type: Tile.TileType) -> Tile:
	var pool := get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
	var new_tile: Tile
	if pool:
		new_tile = pool.acquire(TileScene, board_container) as Tile
		new_tile.visible = true
	else:
		new_tile = TileScene.instantiate() as Tile
		board_container.add_child(new_tile)
	
	var colors := _get_tile_colors(value, type)
	new_tile.setup(value, colors.bg, colors.font)
	return new_tile


func _get_tile_colors(value: int, type: Tile.TileType) -> Dictionary:
	var bg_color := Color.WHITE
	var font_color := Color.BLACK
	
	if not model or not model.interaction_rule:
		return {"bg": bg_color, "font": font_color}
		
	var scheme_index: int = type
	if type == Tile.TileType.PLAYER:
		scheme_index = model.interaction_rule.get_color_scheme_index(value)
		
	var current_scheme: TileColorScheme = color_schemes.get(scheme_index)
	if is_instance_valid(current_scheme) and not current_scheme.styles.is_empty():
		var level: int = model.interaction_rule.get_level_by_value(value)
		if level >= current_scheme.styles.size():
			level = current_scheme.styles.size() - 1
		var current_style: TileLevelStyle = current_scheme.styles[level]
		if is_instance_valid(current_style):
			bg_color = current_style.background_color
			font_color = current_style.font_color
			
	return {"bg": bg_color, "font": font_color}


func _handle_priority_spawn(value: int, type: Tile.TileType) -> void:
	var player_data_list: Array[GameTileData] = []
	for x in model.grid_size:
		for y in model.grid_size:
			var data := model.grid[x][y] as GameTileData
			if data != null and data.type == Tile.TileType.PLAYER:
				player_data_list.append(data)

	if not player_data_list.is_empty():
		var seed_util := get_utility(GFSeedUtility) as GFSeedUtility
		var data_to_transform: GameTileData = player_data_list[seed_util.get_branched_rng("game_board_priority_player").randi_range(0, player_data_list.size() - 1)]
		data_to_transform.value = value
		data_to_transform.type = type
		
		var tile_node: Tile = _visual_map.get(data_to_transform)
		if is_instance_valid(tile_node):
			var colors := _get_tile_colors(value, type)
			tile_node.setup(value, colors.bg, colors.font)
			tile_node.animate_transform()
	else:
		var monster_data_list: Array[GameTileData] = []
		for x in model.grid_size:
			for y in model.grid_size:
				var data := model.grid[x][y] as GameTileData
				if data != null and data.type == Tile.TileType.MONSTER:
					monster_data_list.append(data)
					
		if not monster_data_list.is_empty():
			var seed_util := get_utility(GFSeedUtility) as GFSeedUtility
			var data_to_empower: GameTileData = monster_data_list[seed_util.get_branched_rng("game_board_priority_monster").randi_range(0, monster_data_list.size() - 1)]
			data_to_empower.value *= 2
			
			var tile_node: Tile = _visual_map.get(data_to_empower)
			if is_instance_valid(tile_node):
				var colors := _get_tile_colors(data_to_empower.value, data_to_empower.type)
				tile_node.setup(data_to_empower.value, colors.bg, colors.font)


## 更新棋盘的整体布局以适应其容器大小。
func _update_board_layout() -> void:
	if not model:
		return
	var layout_params: Dictionary = _calculate_layout_params(model.grid_size)
	if layout_params.is_empty():
		return

	if is_instance_valid(board_theme):
		var panel_style := board_background.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		panel_style.bg_color = board_theme.board_panel_color
		board_background.add_theme_stylebox_override("panel", panel_style)

	board_background.position = layout_params.offset
	board_background.size = layout_params.scaled_size
	board_container.position = layout_params.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * layout_params.scale_ratio
	board_container.scale = Vector2.ONE * layout_params.scale_ratio


## 绘制棋盘的静态背景单元格。
func _draw_board_cells() -> void:
	if not model:
		return

	# 清除旧的格子
	for child in board_container.get_children():
		# 注意：Tile 也是 Node2D 的子节点，所以这里需要区分
		# 由于 Tile 是 Node2D 类型 (继承自 scenes/components/tile.tscn)，
		# 而我们的格子场景是 Control (Panel)。
		if child is Control and not child is Tile:
			child.queue_free()

	# 确保有一个有效的格子场景
	if not is_instance_valid(grid_cell_scene):
		if _log: _log.error("GameBoard", "未配置 grid_cell_scene！")
		return

	for x in model.grid_size:
		for y in model.grid_size:
			var cell_instance: Control = grid_cell_scene.instantiate()
			board_container.add_child(cell_instance)

			# 设置格子的大小和位置
			cell_instance.size = Vector2.ONE * CELL_SIZE
			cell_instance.position = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))

			# 如果定义了 BoardTheme，尝试应用颜色
			# 注意：使用场景后，建议优先使用场景内的主题配置，
			# 这里保留颜色覆盖是为了兼容现有的 JSON 主题系统。
			if is_instance_valid(board_theme) and cell_instance is Panel:
				var stylebox: StyleBox = cell_instance.get_theme_stylebox("panel").duplicate()
				if stylebox is StyleBoxFlat:
					stylebox.bg_color = board_theme.empty_cell_color
					cell_instance.add_theme_stylebox_override("panel", stylebox)

			# 确保背景格子在最底层
			board_container.move_child(cell_instance, 0)


## 执行棋盘从旧尺寸到新尺寸的扩建动画。
func _animate_expansion(old_size: int, new_size: int) -> void:
	var final_layout: Dictionary = _calculate_layout_params(new_size)
	if final_layout.is_empty(): return
	var main_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	main_tween.tween_property(board_background, "position", final_layout.offset, 0.3)
	main_tween.tween_property(board_background, "size", final_layout.scaled_size, 0.3)
	var final_container_pos: Vector2 = final_layout.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * final_layout.scale_ratio
	main_tween.tween_property(board_container, "position", final_container_pos, 0.3)
	main_tween.tween_property(board_container, "scale", Vector2.ONE * final_layout.scale_ratio, 0.3)
	await main_tween.finished

	# 清理旧格子 (非 Tile 节点)
	for child in board_container.get_children():
		if child is Control and not child is Tile:
			child.queue_free()

	var new_cells_tween := create_tween().set_parallel(true)

	if not is_instance_valid(grid_cell_scene): return

	for x in new_size:
		for y in new_size:
			var cell_instance: Control = grid_cell_scene.instantiate()
			board_container.add_child(cell_instance)
			board_container.move_child(cell_instance, 0) # 保持在底部

			var final_size := Vector2.ONE * CELL_SIZE
			var final_pos := Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))

			if is_instance_valid(board_theme) and cell_instance is Panel:
				var stylebox: StyleBox = cell_instance.get_theme_stylebox("panel").duplicate()
				if stylebox is StyleBoxFlat:
					stylebox.bg_color = board_theme.empty_cell_color
					cell_instance.add_theme_stylebox_override("panel", stylebox)

			if x >= old_size or y >= old_size:
				var center_pos: Vector2 = final_pos + final_size / 2.0
				cell_instance.size = Vector2.ZERO
				cell_instance.position = center_pos
				new_cells_tween.tween_property(cell_instance, "size", final_size, 0.2).set_delay(0.05 * (x + y))
				new_cells_tween.tween_property(cell_instance, "position", final_pos, 0.2).set_delay(0.05 * (x + y))
			else:
				cell_instance.size = final_size
				cell_instance.position = final_pos

	await new_cells_tween.finished


## 将网格坐标转换为棋盘容器内的局部像素中心点坐标。
## @return: 对应于网格中心的像素坐标 (Vector2)。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos := Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))
	return top_left_pos + Vector2.ONE * (CELL_SIZE / 2.0)


## 根据棋盘尺寸和可用空间，计算缩放、尺寸和偏移等布局参数。
## @return: 一个包含布局参数的字典。
func _calculate_layout_params(p_size: int) -> Dictionary:
	var grid_area_side: float = float(p_size * CELL_SIZE + (p_size - 1) * SPACING)
	var logical_board_side: float = grid_area_side + BOARD_PADDING * 2
	var current_size: Vector2 = self.size
	if current_size.x == 0 or current_size.y == 0:
		return {}
	var scale_ratio: float = min(current_size.x / logical_board_side, current_size.y / logical_board_side)
	var scaled_size := Vector2.ONE * logical_board_side * scale_ratio
	var offset: Vector2 = (current_size - scaled_size) / 2.0
	return {
		"scale_ratio": scale_ratio,
		"scaled_size": scaled_size,
		"offset": offset,
	}


# --- 信号响应 ---

func _on_model_board_changed(instructions: Array) -> void:
	for instr in instructions:
		if instr.has(&"to_grid_pos"):
			instr[&"to_pos"] = _grid_to_pixel_center(instr[&"to_grid_pos"])

	play_animations_requested.emit(instructions)


func _on_model_tile_spawned(_tile: Node) -> void:
	pass


func _on_model_score_updated(amount: int) -> void:
	Gf.send_simple_event(EventNames.SCORE_UPDATED, amount)


# --- 信号处理函数 ---

## 接收到逻辑层的动画请求，将其包装为 Action 推入动画队列。
func _on_board_animation_requested(instructions: Array) -> void:
	var visual_instructions: Array = []
	if _log: _log.info("GameBoard", "_on_board_animation_requested: %d instructions, _visual_map.size=%d" % [instructions.size(), _visual_map.size()])
	
	for instr in instructions:
		var visual_instr: Dictionary = instr.duplicate()
		
		# 转换逻辑数据到视觉节点
		match instr[&"type"]:
			&"MOVE":
				var data: GameTileData = instr[&"tile_data"]
				var tile_node: Tile = _visual_map.get(data)
				visual_instr[&"tile"] = tile_node
				if not is_instance_valid(tile_node):
					if _log: _log.warn("GameBoard", "WARNING: MOVE instruction has no valid tile node! data=%s" % str(data))
			&"MERGE":
				var consumed_data: GameTileData = instr[&"consumed_data"]
				var merged_data: GameTileData = instr[&"merged_data"]
				
				var consumed_node: Tile = _visual_map.get(consumed_data)
				var merged_node: Tile = _visual_map.get(merged_data)
				
				if not is_instance_valid(consumed_node):
					if _log: _log.warn("GameBoard", "WARNING: MERGE consumed_node is invalid! consumed_data=%s" % str(consumed_data))
				if not is_instance_valid(merged_node):
					if _log: _log.warn("GameBoard", "WARNING: MERGE merged_node is invalid! merged_data=%s" % str(merged_data))
				
				visual_instr[&"consumed_tile"] = consumed_node
				visual_instr[&"merged_tile"] = merged_node
				
				# 延迟更新合并后的视觉状态
				if is_instance_valid(merged_node):
					var colors := _get_tile_colors(merged_data.value, merged_data.type)
					visual_instr[&"target_setup_data"] = {
						&"value": merged_data.value,
						&"bg": colors.bg,
						&"font": colors.font,
						&"do_transform": instr.has(&"transform")
					}
						
				# 从映射中移除被消耗的节点
				if consumed_data != null:
					_visual_map.erase(consumed_data)
			&"SPAWN":
				# SPAWN 指令通常在 GameBoard 内部生成，已经带了 tile 节点
				pass
		
		# 计算像素坐标
		if visual_instr.has(&"to_grid_pos"):
			visual_instr[&"to_pos"] = _grid_to_pixel_center(visual_instr[&"to_grid_pos"])
			
		visual_instructions.append(visual_instr)
			
	# 2. 实例化视觉动作
	var action := BoardAnimationAction.new(visual_instructions, self ) as GFVisualAction
	
	# 3. 推入 GFActionQueueSystem 执行
	var queue_sys := get_system(GFActionQueueSystem) as GFActionQueueSystem
	if queue_sys:
		queue_sys.enqueue(action)


## 接收到全量刷新请求（如撤回操作），直接重置棋盘视觉状态。
func _on_board_refresh_requested(grid_snapshot: Dictionary) -> void:
	restore_from_snapshot(grid_snapshot)


## 当场景即将改变时调用，确保释放旧场景前断开监听
func _on_scene_will_change(_payload: Variant = null) -> void:
	_cleanup_listeners()


## 当棋盘尺寸改变时，更新布局。
func _on_resized() -> void:
	_update_board_layout()
