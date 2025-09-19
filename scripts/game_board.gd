# scripts/game_board.gd

# 该脚本负责管理整个游戏棋盘的核心逻辑。
# 它处理包括棋盘的初始化、方块的生成、移动、合并、战斗以及胜负条件的判断。
# 通过信号与游戏场景进行通信，实现了逻辑与表现的分离。
extends Control

# --- 信号定义 ---

# 当一次有效的移动（合并或战斗）成功执行后发出。
signal move_made
# 当游戏无法再进行下去时发出（棋盘已满且无任何可移动项）。
signal game_lost
# 当一个怪物被消灭时发出（无论是战斗胜利还是同归于尽）。
signal monster_killed

# --- 常量与预加载资源 ---

# 预加载方块场景，用于动态实例化。
const TileScene = preload("res://scenes/tile.tscn")

# 棋盘的尺寸（4x4）。
const GRID_SIZE: int = 4
# 每个单元格的像素尺寸。
const CELL_SIZE: int = 100
# 单元格之间的间距。
const SPACING: int = 15
# 棋盘背景的内边距
const BOARD_PADDING: int = 15

# --- 核心数据 ---

# 二维数组，用于存储棋盘上所有方块的引用。'null'代表空格。
var grid = []

# --- 节点引用 ---

# 棋盘容器，所有方块的父节点，方便统一管理和定位。
@onready var board_container: Node2D = $BoardContainer

# Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 初始化网格数据结构。
	_initialize_grid()
	
	# 计算棋盘内容区域（所有格子+间距）的总像素尺寸
	var grid_area_side_length = GRID_SIZE * CELL_SIZE + (GRID_SIZE - 1) * SPACING
	# 计算包含内边距的棋盘背景总尺寸
	var board_background_side_length = grid_area_side_length + BOARD_PADDING * 2
	# 设置当前Control节点的最小尺寸，以容纳背景和内边距
	self.custom_minimum_size = Vector2(board_background_side_length, board_background_side_length)
	# 将方块和格子背景的容器向内偏移，留出边距
	board_container.position = Vector2(BOARD_PADDING, BOARD_PADDING)
	# 绘制棋盘的背景单元格
	_draw_board()
	
	# 游戏开始时生成两个初始玩家方块。
	spawn_tile()
	spawn_tile()

# --- 公共接口 ---
# 这些函数由外部节点（如游戏模式主脚本）调用，以控制游戏流程。

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
		# 立即更新数据模型
		grid = _unrotate_grid(new_grid_after_move, direction)
		# 立即启动所有视觉动画，并获取这些动画的引用
		var move_tweens = _update_board_visuals()
		# 如果有动画正在播放，就等待它们全部完成
		if not move_tweens.is_empty():
			for tween in move_tweens:
				await tween.finished
		# 生成新方块，并获取它的生成动画
		var spawn_tween = spawn_tile()
		# 如果确实生成了新方块（和它的动画），就等待它完成
		if spawn_tween != null:
			await spawn_tween.finished
			
		# 在所有动画都结束后，再执行后续逻辑
		move_made.emit()
		_check_game_over()

## 在一个随机的空位上生成一个新的玩家方块（数值为2）。
func spawn_tile() -> Tween:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty():
		return null
	# 使用随机数生成器选择一个随机空位。
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var spawn_pos: Vector2i = empty_cells[rng.randi_range(0, empty_cells.size() - 1)]
	var new_tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[spawn_pos.x][spawn_pos.y] = new_tile
	# 先初始化，但不设置位置，动画会处理
	new_tile.setup(2, new_tile.TileType.PLAYER)
	new_tile.position = _grid_to_pixel_center(spawn_pos)
	# 调用生成动画，并将其返回
	return new_tile.animate_spawn()

## 在一个随机的空位上生成一个指定数值的怪物方块。
## 如果棋盘已满，则执行特殊逻辑。
## @param monster_value: 要生成的怪物方块的数值。
func spawn_monster(monster_value: int) -> void:
	var empty_cells = _get_empty_cells()
	
	# 情况1：棋盘有空位
	if not empty_cells.is_empty():
		var spawn_pos: Vector2i = empty_cells.pick_random()
		var new_monster = TileScene.instantiate()
		
		board_container.add_child(new_monster)
		grid[spawn_pos.x][spawn_pos.y] = new_monster
		
		new_monster.setup(monster_value, new_monster.TileType.MONSTER)
		new_monster.position = _grid_to_pixel_center(spawn_pos)
		new_monster.animate_spawn()
		
	# 情况2：棋盘已满
	else:
		var player_tiles = _get_all_player_tiles()
		
		# 子情况A：棋盘上有玩家方块，随机将一个转变为怪物
		if not player_tiles.is_empty():
			var tile_to_transform = player_tiles.pick_random()
			# 使用 setup 函数改变其类型和数值
			tile_to_transform.setup(monster_value, tile_to_transform.TileType.MONSTER)
			# 播放转变动画
			tile_to_transform.animate_transform()
			
		# 子情况B：棋盘上全是怪物方块，随机将一个数值翻倍
		else:
			var monster_tiles = _get_all_monster_tiles()
			if not monster_tiles.is_empty():
				var tile_to_empower = monster_tiles.pick_random()
				# setup 函数在数值变大时会自动调用合并动画。
				tile_to_empower.setup(tile_to_empower.value * 2, tile_to_empower.TileType.MONSTER)
	
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

## 测试功能：在指定位置生成一个方块。
## @param grid_pos: 要生成方块的网格坐标 (Vector2i)。
## @param value: 方块的数值。
## @param type: 方块的类型 (Tile.TileType.PLAYER 或 Tile.TileType.MONSTER)。
func spawn_specific_tile(grid_pos: Vector2i, value: int, type: Tile.TileType) -> void:
	# 检查坐标是否在棋盘范围内
	if not (grid_pos.x >= 0 and grid_pos.x < GRID_SIZE and grid_pos.y >= 0 and grid_pos.y < GRID_SIZE):
		print("Error: Spawn position is out of bounds.")
		return
		
	# 如果该位置已有方块，先将其移除
	if grid[grid_pos.x][grid_pos.y] != null:
		grid[grid_pos.x][grid_pos.y].queue_free()
		grid[grid_pos.x][grid_pos.y] = null
		
	var new_tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[grid_pos.x][grid_pos.y] = new_tile
	
	new_tile.setup(value, type)
	new_tile.position = _grid_to_pixel_center(grid_pos)
	new_tile.animate_spawn()

# --- 内部核心逻辑 ---
# 这些函数是棋盘功能的具体实现，由公共接口或其他内部函数调用。

## 遍历网格，返回所有玩家方块节点的数组。
func _get_all_player_tiles() -> Array:
	var player_tiles = []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER:
				player_tiles.append(tile)
	return player_tiles

## 遍历网格，返回所有怪物方块节点的数组。
func _get_all_monster_tiles() -> Array:
	var monster_tiles = []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.MONSTER:
				monster_tiles.append(tile)
	return monster_tiles

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
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = Color("3c3c3c")
			stylebox.corner_radius_top_left = 8
			stylebox.corner_radius_top_right = 8
			stylebox.corner_radius_bottom_right = 8
			stylebox.corner_radius_bottom_left = 8
			cell_bg.add_theme_stylebox_override("panel", stylebox)

			cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
			# 使用返回左上角坐标的函数
			cell_bg.position = _grid_to_pixel_top_left(Vector2i(x, y))
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
			var next_tile = slid_line[i + 1]
			
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
					monster_killed.emit()
				# 怪物数值大，战斗失败，数值相除。
				elif player_tile.value < monster_tile.value:
					monster_tile.setup(int(monster_tile.value / player_tile.value), monster_tile.type)
					merged_line.append(monster_tile)
					player_tile.queue_free()
				# 数值相等，同归于尽。
				else:
					player_tile.queue_free()
					monster_tile.queue_free()
					monster_killed.emit()
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
		for idx in range(result_line.size()):
			if (result_line[idx] == null and line[idx] != null) or \
			   (result_line[idx] != null and line[idx] == null) or \
			   (result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true; break
				
	return [result_line, has_moved]

## 根据 `grid` 数组中的数据，更新场景中所有方块节点的实际位置。
func _update_board_visuals() -> Array:
	var active_tweens = []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] != null:
				var tile = grid[x][y]
				var new_pixel_pos = _grid_to_pixel_center(Vector2i(x, y))
				# 如果方块不在目标位置，就为它创建一个移动动画
				if tile.position != new_pixel_pos:
					var move_tween = tile.animate_move(new_pixel_pos)
					active_tweens.append(move_tween)
	return active_tweens

## 将网格坐标转换为屏幕像素坐标（返回格子左上角）。
func _grid_to_pixel_top_left(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))

## 将网格坐标转换为屏幕像素坐标（返回格子中心点）。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos = _grid_to_pixel_top_left(grid_pos)
	var center_pos = top_left_pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	return center_pos

## 检查游戏是否结束
func _check_game_over() -> void:
	# 如果棋盘已满，检查失败条件。
	if _get_empty_cells().is_empty():
		# 遍历棋盘，检查是否存在任何可能的移动（相邻方块可合并或战斗）。
		for x in range(GRID_SIZE):
			for y in range(GRID_SIZE):
				var current_tile = grid[x][y]
				# 检查右侧相邻方块。
				if x + 1 < GRID_SIZE:
					var right_tile = grid[x + 1][y]
					if right_tile != null and (current_tile.type != right_tile.type or current_tile.value == right_tile.value):
						return
				# 检查下方相邻方块。
				if y + 1 < GRID_SIZE:
					var down_tile = grid[x][y + 1]
					if down_tile != null and (current_tile.type != down_tile.type or current_tile.value == down_tile.value):
						return
		# 如果遍历完所有方块都没有找到可移动的组合，则游戏失败。
		game_lost.emit()
