# scripts/game_board.gd

# 该脚本负责管理整个游戏棋盘的核心逻辑。
# 它处理包括棋盘的初始化、方块的生成、移动、合并、战斗以及胜负条件的判断。
# 通过信号与主场景(Main.gd)进行通信，实现了逻辑与表现的分离。
extends Control

# --- 信号定义 ---

# 当一次有效的移动（合并或战斗）成功执行后发出。
signal move_made
# 当玩家达到胜利条件时发出。
signal game_won
# 当游戏无法再进行下去时发出（棋盘已满且无任何可移动项）。
signal game_lost

# --- 常量与预加载资源 ---

# 预加载方块场景，用于动态实例化。
const TileScene = preload("res://scenes/tile.tscn")

# 棋盘的尺寸（4x4）。
const GRID_SIZE: int = 4
# 每个单元格的像素尺寸。
const CELL_SIZE: int = 100
# 单元格之间的间距。
const SPACING: int = 15

# --- 核心数据 ---

# 二维数组，用于存储棋盘上所有方块的引用。'null'代表空格。
var grid = []

# --- 节点引用 ---

# 棋盘容器，所有方块的父节点，方便统一管理和定位。
# 注意：这里的$BoardContainer路径是相对于当前脚本所在的GameBoard节点，所以无需修改。
@onready var board_container: Node2D = $BoardContainer


# Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 初始化网格数据结构。
	_initialize_grid()
	# 绘制棋盘的背景单元格。
	_draw_board()
	# 计算棋盘的总像素尺寸
	var board_side_length = GRID_SIZE * CELL_SIZE + (GRID_SIZE - 1) * SPACING
	# 设置当前Control节点的最小尺寸
	self.custom_minimum_size = Vector2(board_side_length, board_side_length)
	
	# 游戏开始时生成两个初始玩家方块。
	spawn_tile()
	spawn_tile()


# --- 公共接口 ---
# 这些函数由外部节点（如 Main.gd）调用，以控制游戏流程。

## 根据给定的方向向量处理玩家的移动输入。
## @param direction: 一个 Vector2i，如 Vector2i.UP，代表移动方向。
func handle_move(direction: Vector2i) -> void:
	var moved = false
	# 为了简化处理，将所有方向的移动都转换为向“左”移动的逻辑。
	var grid_copy_for_move = _get_rotated_grid(direction)
	var new_grid_after_move = []

	# 逐行处理旋转后的网格。
	for row_index in GRID_SIZE:
		var current_row = grid_copy_for_move[row_index]
		var result = _process_line(current_row)
		var processed_row = result[0]
		var has_moved_in_row = result[1]
		new_grid_after_move.append(processed_row)
		# 只要有一行发生了移动，就标记为有效移动。
		if has_moved_in_row:
			moved = true
	
	# 如果发生了有效移动，则更新棋盘状态。
	if moved:
		# 将处理后的网格旋转回原始方向。
		grid = _unrotate_grid(new_grid_after_move, direction)
		# 根据新的网格数据更新所有方块的视觉位置。
		_update_board_visuals()
		# 等待一个短暂的视觉延迟，然后生成新的方块。
		await get_tree().create_timer(0.1).timeout
		spawn_tile()
		# 发出信号，通知主场景移动已完成。
		move_made.emit()
		# 检查游戏是否结束。
		_check_game_over()
	else:
		# 即使没有移动，也需要检查游戏是否因为无法移动而结束。
		_check_game_over()

## 在一个随机的空位上生成一个新的玩家方块（数值为2）。
func spawn_tile() -> void:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return
	# 使用随机数生成器选择一个随机空位。
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var spawn_pos: Vector2i = empty_cells[rng.randi_range(0, empty_cells.size() - 1)]
	
	var new_tile = TileScene.instantiate()
	
	board_container.add_child(new_tile)
	grid[spawn_pos.x][spawn_pos.y] = new_tile
	new_tile.position = _grid_to_pixel(spawn_pos)
	new_tile.setup(2, new_tile.TileType.PLAYER)

## 在一个随机的空位上生成一个指定数值的怪物方块。
## @param monster_value: 要生成的怪物方块的数值。
func spawn_monster(monster_value: int) -> void:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return

	var spawn_pos: Vector2i = empty_cells.pick_random()
	var new_monster = TileScene.instantiate()
	
	board_container.add_child(new_monster)
	grid[spawn_pos.x][spawn_pos.y] = new_monster
	new_monster.position = _grid_to_pixel(spawn_pos)
	new_monster.setup(monster_value, new_monster.TileType.MONSTER)
	
## 获取当前棋盘上数值最大的玩家方块的值。
## 这是一个封装良好的公共接口，避免外部直接访问内部 grid 数据。
## @return: 返回最大的玩家方块数值，如果没有玩家方块则返回0。
func get_max_player_value() -> int:
	var max_val = 0
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var tile = grid[x][y]
			# 确保方块存在、是玩家类型，并且其值大于当前记录的最大值。
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value > max_val:
				max_val = tile.value
	return max_val


# --- 内部核心逻辑 ---
# 这些函数是棋盘功能的具体实现，由公共接口或其他内部函数调用。

## 初始化网格，创建一个填满 'null' 的二维数组。
func _initialize_grid():
	grid.resize(GRID_SIZE)
	for x in range(GRID_SIZE):
		grid[x] = []
		grid[x].resize(GRID_SIZE)
		grid[x].fill(null)

## 绘制棋盘的灰色背景单元格，作为视觉基础。
func _draw_board():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var cell_bg = ColorRect.new()
			cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell_bg.position = _grid_to_pixel(Vector2i(x, y))
			cell_bg.color = Color("8f8f8f")
			board_container.add_child(cell_bg)

## 遍历整个网格，返回所有空格子坐标的数组。
## @return: 一个包含所有空单元格 Vector2i 坐标的数组。
func _get_empty_cells() -> Array:
	var empty_cells = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells

## 根据移动方向，返回一个旋转后的虚拟网格。
## 这个技巧可以将所有方向的移动逻辑（上、下、右）统一为向左移动。
## @param direction: 移动方向向量。
## @return: 一个新的二维数组，代表旋转后的网格。
func _get_rotated_grid(direction: Vector2i) -> Array:
	var rotated_grid = []
	rotated_grid.resize(GRID_SIZE)
	for i in GRID_SIZE:
		var line = []
		for j in GRID_SIZE:
			match direction:
				Vector2i.LEFT: line.append(grid[j][i])
				Vector2i.RIGHT: line.append(grid[GRID_SIZE - 1 - j][i])
				Vector2i.UP: line.append(grid[i][j])
				Vector2i.DOWN: line.append(grid[i][GRID_SIZE - 1 - j])
		rotated_grid[i] = line
	return rotated_grid

## 将一个被旋转过的网格数据恢复到其原始的对应位置。
## @param rotated_grid: 经过 `_get_rotated_grid` 处理后的网格。
## @param direction: 原始的移动方向。
## @return: 恢复了正确方向的网格数据。
func _unrotate_grid(rotated_grid: Array, direction: Vector2i) -> Array:
	var new_grid = []
	new_grid.resize(GRID_SIZE)
	for i in GRID_SIZE: new_grid[i] = []; new_grid[i].resize(GRID_SIZE)
	for i in GRID_SIZE:
		for j in GRID_SIZE:
			match direction:
				Vector2i.LEFT: new_grid[j][i] = rotated_grid[i][j]
				Vector2i.RIGHT: new_grid[GRID_SIZE - 1 - j][i] = rotated_grid[i][j]
				Vector2i.UP: new_grid[i][j] = rotated_grid[i][j]
				Vector2i.DOWN: new_grid[i][GRID_SIZE - 1 - j] = rotated_grid[i][j]
	return new_grid

## 处理单行（或列）的移动、合并与战斗逻辑。这是整个游戏的核心算法。
## @param line: 一个包含方块或 'null' 的一维数组。
## @return: 一个包含两个元素的数组：[处理后的新行, 是否发生了移动]。
func _process_line(line: Array) -> Array:
	# 步骤1: 移除所有空格，将所有方块紧贴在一起。
	var slid_line = []
	for tile in line:
		if tile != null: slid_line.append(tile)
	
	# 步骤2: 遍历紧贴的方块，处理合并或战斗。
	var merged_line = []
	var i = 0
	while i < slid_line.size():
		var current_tile = slid_line[i]
		# 检查是否存在下一个方块用于比较。
		if i + 1 < slid_line.size():
			var next_tile = slid_line[i+1]
			
			# 情况A: 两个方块类型相同（玩家 vs 玩家 或 怪物 vs 怪物）。
			if current_tile.type == next_tile.type:
				# 数值相同则合并。
				if current_tile.value == next_tile.value:
					next_tile.setup(current_tile.value * 2, current_tile.type)
					merged_line.append(next_tile)
					current_tile.queue_free() # 销毁被合并的方块。
					i += 2; continue # 跳过两个已处理的方块。
			
			# 情况B: 两个方块类型不同（玩家 vs 怪物）。
			else:
				var player_tile = current_tile if current_tile.type == current_tile.TileType.PLAYER else next_tile
				var monster_tile = current_tile if current_tile.type == current_tile.TileType.MONSTER else next_tile
				
				# 玩家数值大，战斗胜利，数值相除。
				if player_tile.value > monster_tile.value:
					player_tile.setup(int(player_tile.value / monster_tile.value), player_tile.type)
					merged_line.append(player_tile)
					monster_tile.queue_free()
				# 怪物数值大，战斗失败，数值相除。
				elif player_tile.value < monster_tile.value:
					monster_tile.setup(int(monster_tile.value / player_tile.value), monster_tile.type)
					merged_line.append(monster_tile)
					player_tile.queue_free()
				# 数值相等，同归于尽。
				else:
					player_tile.queue_free()
					monster_tile.queue_free()
				i += 2; continue
				
		# 如果没有发生合并或战斗，则直接将当前方块加入结果。
		merged_line.append(current_tile)
		i += 1
		
	# 步骤3: 用 'null' 填充行末的空格，使其恢复标准长度。
	var result_line = merged_line.duplicate()
	while result_line.size() < GRID_SIZE: result_line.append(null)
	
	# 步骤4: 判断处理后的行与原始行是否不同，以确定是否发生了移动。
	var has_moved = false
	if result_line.size() != line.size(): has_moved = true
	else:
		for idx in range(result_line.size()): # <-- 修正循环
			if (result_line[idx] == null and line[idx] != null) or \
			   (result_line[idx] != null and line[idx] == null) or \
			   (result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true; break
				
	return [result_line, has_moved]

## 根据 `grid` 数组中的数据，更新场景中所有方块节点的实际位置。
func _update_board_visuals():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] != null:
				var tile = grid[x][y]
				tile.position = _grid_to_pixel(Vector2i(x, y))

## 将网格坐标（如 [0, 1]）转换为屏幕像素坐标。
## @param grid_pos: 网格坐标 Vector2i。
## @return: 对应的像素坐标 Vector2。
func _grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))

## 检查游戏是否结束（胜利或失败）。
func _check_game_over() -> void:
	# 检查胜利条件：是否存在一个数值达到4096的玩家方块。
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value >= 4096:
				game_won.emit()
				return
				
	# 如果棋盘已满，则检查失败条件。
	if _get_empty_cells().is_empty():
		# 遍历棋盘，检查是否存在任何可能的移动（相邻方块可合并或战斗）。
		for x in range(GRID_SIZE):
			for y in range(GRID_SIZE):
				var current_tile = grid[x][y]
				# 检查右侧相邻方块。
				if x + 1 < GRID_SIZE:
					var right_tile = grid[x+1][y]
					if right_tile != null and (current_tile.type != right_tile.type or current_tile.value == right_tile.value):
						return
				# 检查下方相邻方块。
				if y + 1 < GRID_SIZE:
					var down_tile = grid[x][y+1]
					if down_tile != null and (current_tile.type != down_tile.type or current_tile.value == down_tile.value):
						return
						
		# 如果遍历完所有方块都没有找到可移动的组合，则游戏失败。
		game_lost.emit()
