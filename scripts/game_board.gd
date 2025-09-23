# scripts/game_board.gd

## GameBoard: 负责管理整个游戏棋盘的核心逻辑。
##
## 该脚本处理棋盘的初始化、方块的生成、移动和交互。它被设计为一个通用的“执行者”，
## 自身不包含任何具体的游戏规则（如如何合并、如何算输），而是通过外部注入的规则对象来执行逻辑。
## 通过信号与游戏主场景进行通信，实现了逻辑与表现的分离。
extends Control

# --- 信号定义 ---

## 当一次有效的移动成功执行后发出。
signal move_made
## 当游戏根据规则无法再进行下去时发出。
signal game_lost
## 当棋盘完成重置或扩建后发出，传递新的尺寸。
signal board_resized(new_grid_size)

# --- 常量与预加载资源 ---

# 预加载方块场景，用于在运行时动态实例化。
const TileScene = preload("res://scenes/tile.tscn")

# 每个单元格的像素尺寸。
const CELL_SIZE: int = 100
# 单元格之间的间距。
const SPACING: int = 15
# 棋盘背景的内边距。
const BOARD_PADDING: int = 15

# --- 核心数据 ---

# 棋盘的尺寸
var grid_size: int = 4
# 二维数组，用于存储棋盘上所有方块节点的引用。'null'代表空格。
var grid = []
# 防止在窗口大小改变时重复初始化棋盘。
var is_initialized: bool = false

# --- 规则引用 ---

# 外部注入的方块交互规则。
var interaction_rule: InteractionRule
# 外部注入的游戏结束判断规则。
var game_over_rule: GameOverRule

# --- 节点引用 ---

# 棋盘背景，用于整体缩放和定位。
@onready var board_background: Panel = $BoardBackground
# 棋盘容器，所有方块节点的父节点，方便统一管理和定位。
@onready var board_container: Node2D = $BoardContainer

# --- Godot 生命周期函数 ---

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 连接 resized 信号，当本控件尺寸变化时更新内部布局。
	resized.connect(_update_board_layout)
	# 推迟一帧调用，以确保父容器已经完成了初始布局，赋予了本控件正确的尺寸。
	_initialize_board()

# --- 公共接口 ---

## 设置当前棋盘使用的规则集。
## 这是外部（如GamePlay.gd）将具体玩法注入棋盘的入口。
func set_rules(p_interaction_rule: InteractionRule, p_game_over_rule: GameOverRule) -> void:
	self.interaction_rule = p_interaction_rule
	self.game_over_rule = p_game_over_rule

## 根据给定的方向向量处理一次完整的移动操作。
func handle_move(direction: Vector2i) -> void:
	var moved = false
	# 为了简化算法，将所有方向的移动都转换为向“左”移动的逻辑。
	var grid_copy_for_move = _get_rotated_grid(direction)
	var new_grid_after_move = []

	# 逐行处理旋转后的虚拟网格。
	for row_index in grid_size:
		var current_row = grid_copy_for_move[row_index]
		var result = _process_line(current_row)
		var processed_row = result[0]
		var has_moved_in_row = result[1]
		new_grid_after_move.append(processed_row)
		if has_moved_in_row:
			moved = true
	
	# 仅在发生了有效移动时，才更新棋盘状态。
	if moved:
		grid = _unrotate_grid(new_grid_after_move, direction)
		
		var move_tweens = _update_board_visuals()
		if not move_tweens.is_empty():
			for tween in move_tweens:
				await tween.finished
		
		move_made.emit()
		_check_game_over()

## 生成一个指定信息的方块。
## 这是一个通用的生成函数，取代了旧的 spawn_tile 和 spawn_monster。
func spawn_tile(spawn_data: Dictionary) -> Tween:
	var value = spawn_data.get("value", 2)
	var type = spawn_data.get("type", Tile.TileType.PLAYER)
	var is_priority = spawn_data.get("is_priority", false)
	
	var empty_cells = get_empty_cells()
	
	# 情况1：棋盘有空位，正常生成。
	if not empty_cells.is_empty():
		var spawn_pos: Vector2i = empty_cells.pick_random()
		return _spawn_at(spawn_pos, value, type)
	# 情况2：棋盘已满，但生成请求是优先的（如怪物），则执行转化逻辑。
	elif is_priority:
		var player_tiles = _get_all_player_tiles()
		# 子情况A：棋盘上仍有玩家方块，随机将一个转变为怪物。
		if not player_tiles.is_empty():
			var tile_to_transform = player_tiles.pick_random()
			tile_to_transform.setup(value, type)
			tile_to_transform.animate_transform()
		# 子情况B：棋盘上全是怪物方块，随机将一个数值翻倍以示“增强”。
		else:
			var monster_tiles = _get_all_monster_tiles()
			if not monster_tiles.is_empty():
				var tile_to_empower = monster_tiles.pick_random()
				tile_to_empower.setup(tile_to_empower.value * 2, type)
		return null
		
	return null

## 获取当前棋盘上数值最大的玩家方块的值。
func get_max_player_value() -> int:
	if not is_initialized: return 0
	var max_val = 0
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value > max_val:
				max_val = tile.value
	return max_val

## 在指定网格位置生成一个特定方块，主要用于测试。
func spawn_specific_tile(grid_pos: Vector2i, value: int, type: Tile.TileType) -> void:
	if not (grid_pos.x >= 0 and grid_pos.x < grid_size and grid_pos.y >= 0 and grid_pos.y < grid_size):
		push_error("Spawn position is out of bounds.")
		return
		
	if grid[grid_pos.x][grid_pos.y] != null:
		grid[grid_pos.x][grid_pos.y].queue_free()
		grid[grid_pos.x][grid_pos.y] = null
		
	_spawn_at(grid_pos, value, type)

## 重置整个棋盘并应用新的尺寸。
func reset_and_resize(new_size: int) -> void:
	for child in board_container.get_children():
		child.queue_free()
	
	grid.clear()
	is_initialized = false
	grid_size = new_size
	
	_initialize_board()
	board_resized.emit(grid_size)

## 在游戏进行中扩建棋盘（只能变大）。
func live_expand(new_size: int) -> void:
	if new_size <= grid_size:
		push_warning("Live expand only supports increasing the grid size.")
		return
	
	var old_size = grid_size
	grid_size = new_size
	for x in range(old_size):
		grid[x].resize(grid_size)
		grid[x].slice(old_size, grid_size - 1).fill(null)
	grid.resize(grid_size)
	for x in range(old_size, grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)
	
	_animate_expansion(old_size, new_size)
	board_resized.emit(grid_size)

## 遍历整个网格，返回所有空格子坐标的数组。
func get_empty_cells() -> Array:
	var empty_cells = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells

# --- 初始化与布局 ---

func _initialize_board() -> void:
	_initialize_grid()
	_update_board_layout()
	if not is_initialized:
		_draw_board_cells()
		is_initialized = true

## 当GameBoard控件尺寸改变时，重新计算并应用所有内部元素的变换。
func _update_board_layout() -> void:
	var layout_params = _calculate_layout_params(grid_size)
	if layout_params.is_empty(): return
	board_background.position = layout_params.offset
	board_background.size = layout_params.scaled_size
	board_container.position = layout_params.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * layout_params.scale_ratio
	board_container.scale = Vector2(layout_params.scale_ratio, layout_params.scale_ratio)

# --- 内部核心逻辑 ---

## 处理单行的移动与交互，现在委托给 interaction_rule。
func _process_line(line: Array) -> Array:
	var slid_line = []
	for tile in line:
		if tile != null: slid_line.append(tile)
	
	var merged_line = []
	var i = 0
	while i < slid_line.size():
		var current_tile = slid_line[i]
		if i + 1 < slid_line.size():
			var next_tile = slid_line[i + 1]
			
			# 将具体的交互逻辑委托给注入的规则对象。
			var result = interaction_rule.process_interaction(current_tile, next_tile)
			if not result.is_empty():
				var merged = result.get("merged_tile")
				if merged != null:
					merged_line.append(merged)
				i += 2
				continue
		
		merged_line.append(current_tile)
		i += 1
		
	var result_line = merged_line.duplicate()
	while result_line.size() < grid_size: result_line.append(null)
	
	var has_moved = false
	if result_line.size() != line.size(): has_moved = true
	else:
		for idx in range(result_line.size()):
			if (result_line[idx] == null and line[idx] != null) or \
			   (result_line[idx] != null and line[idx] == null) or \
			   (result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true; break
				
	return [result_line, has_moved]

## 检查游戏是否结束，现在委托给 game_over_rule。
func _check_game_over() -> void:
	# 将判断逻辑委托给注入的规则对象。
	if game_over_rule.is_game_over(self, interaction_rule):
		game_lost.emit()

# --- 视觉与动画 ---

## 根据 `grid` 数据更新所有方块的视觉位置，并为移动的方块创建动画。
func _update_board_visuals() -> Array:
	var active_tweens = []
	for x in grid_size:
		for y in grid_size:
			if grid[x][y] != null:
				var tile = grid[x][y]
				var new_pixel_pos = _grid_to_pixel_center(Vector2i(x, y))
				if tile.position != new_pixel_pos:
					var move_tween = tile.animate_move(new_pixel_pos)
					active_tweens.append(move_tween)
	return active_tweens

## 绘制棋盘的静态背景单元格。
func _draw_board_cells():
	for child in board_container.get_children():
		if child is Panel: child.queue_free()
			
	for x in grid_size:
		for y in grid_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = Color("3c3c3c")
			stylebox.set_corner_radius_all(8)
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell_bg.position = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))
			board_container.add_child(cell_bg)
			board_container.move_child(cell_bg, 0)

## 执行棋盘从旧尺寸到新尺寸的扩建动画。
func _animate_expansion(old_size: int, new_size: int) -> void:
	var final_layout = _calculate_layout_params(new_size)
	if final_layout.is_empty(): return

	var main_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	main_tween.tween_property(board_background, "position", final_layout.offset, 0.3)
	main_tween.tween_property(board_background, "size", final_layout.scaled_size, 0.3)
	var final_container_pos = final_layout.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * final_layout.scale_ratio
	main_tween.tween_property(board_container, "position", final_container_pos, 0.3)
	main_tween.tween_property(board_container, "scale", Vector2(final_layout.scale_ratio, final_layout.scale_ratio), 0.3)
	await main_tween.finished
	
	for child in board_container.get_children():
		if child is Panel: child.queue_free()

	var new_cells_tween = create_tween().set_parallel(true)
	for x in new_size:
		for y in new_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = Color("3c3c3c")
			stylebox.set_corner_radius_all(8)
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			
			var final_size = Vector2(CELL_SIZE, CELL_SIZE)
			var final_pos = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))

			board_container.add_child(cell_bg)
			board_container.move_child(cell_bg, 0)

			if x >= old_size or y >= old_size:
				var center_pos = final_pos + final_size / 2.0
				cell_bg.size = Vector2.ZERO
				cell_bg.position = center_pos
				new_cells_tween.tween_property(cell_bg, "size", final_size, 0.2).set_delay(0.05 * (x + y))
				new_cells_tween.tween_property(cell_bg, "position", final_pos, 0.2).set_delay(0.05 * (x + y))
			else:
				cell_bg.size = final_size
				cell_bg.position = final_pos
	await new_cells_tween.finished
	_update_board_visuals()

# --- 辅助函数 ---

## 在指定位置生成一个方块的内部实现。
func _spawn_at(grid_pos: Vector2i, value: int, type: Tile.TileType) -> Tween:
	var new_tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[grid_pos.x][grid_pos.y] = new_tile
	
	new_tile.setup(value, type)
	new_tile.position = _grid_to_pixel_center(grid_pos)
	return new_tile.animate_spawn()

## 初始化核心数据 `grid`，创建一个填满 null 的二维数组。
func _initialize_grid():
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)

## 遍历网格，返回所有玩家方块节点的数组。
func _get_all_player_tiles() -> Array:
	var player_tiles = []
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER:
				player_tiles.append(tile)
	return player_tiles

## 遍历网格，返回所有怪物方块节点的数组。
func _get_all_monster_tiles() -> Array:
	var monster_tiles = []
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.MONSTER:
				monster_tiles.append(tile)
	return monster_tiles

## 根据方向旋转网格，用以统一处理所有方向的移动逻辑。
func _get_rotated_grid(direction: Vector2i) -> Array:
	var rotated_grid = []
	rotated_grid.resize(grid_size)
	for i in grid_size:
		var line = []
		for j in grid_size:
			match direction:
				Vector2i.LEFT: line.append(grid[j][i])
				Vector2i.RIGHT: line.append(grid[grid_size - 1 - j][i])
				Vector2i.UP: line.append(grid[i][j])
				Vector2i.DOWN: line.append(grid[i][grid_size - 1 - j])
		rotated_grid[i] = line
	return rotated_grid

## 将旋转后的网格数据恢复到原始方向。
func _unrotate_grid(rotated_grid: Array, direction: Vector2i) -> Array:
	var new_grid = []
	new_grid.resize(grid_size)
	for i in grid_size: new_grid[i] = []; new_grid[i].resize(grid_size)
	
	for i in grid_size:
		for j in grid_size:
			match direction:
				Vector2i.LEFT: new_grid[j][i] = rotated_grid[i][j]
				Vector2i.RIGHT: new_grid[grid_size - 1 - j][i] = rotated_grid[i][j]
				Vector2i.UP: new_grid[i][j] = rotated_grid[i][j]
				Vector2i.DOWN: new_grid[i][grid_size - 1 - j] = rotated_grid[i][j]
	return new_grid

## 将网格坐标转换为棋盘容器内的局部像素中心点坐标。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos = Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))
	return top_left_pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

## 根据棋盘尺寸和可用空间，计算缩放、尺寸和偏移等布局参数。
func _calculate_layout_params(p_size: int) -> Dictionary:
	var grid_area_side = p_size * CELL_SIZE + (p_size - 1) * SPACING
	var logical_board_side = grid_area_side + BOARD_PADDING * 2
	
	var current_size = self.size
	if current_size.x == 0 or current_size.y == 0: return {}

	var scale_ratio = min(current_size.x / logical_board_side, current_size.y / logical_board_side)
	var scaled_size = Vector2(logical_board_side, logical_board_side) * scale_ratio
	var offset = (current_size - scaled_size) / 2.0

	return {"scale_ratio": scale_ratio, "scaled_size": scaled_size, "offset": offset}
