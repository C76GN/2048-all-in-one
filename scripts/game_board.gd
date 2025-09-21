# scripts/game_board.gd

## GameBoard: 负责管理整个游戏棋盘的核心逻辑。
##
## 该脚本处理棋盘的初始化、方块的生成、移动、合并、战斗以及胜负条件的判断。
## 通过信号与游戏主场景进行通信，实现了逻辑与表现的分离。
extends Control

# --- 信号定义 ---

## 当一次有效的移动（合并或战斗）成功执行后发出。
signal move_made
## 当游戏无法再进行下去时（棋盘已满且无任何可移动项）发出。
signal game_lost
## 当一个怪物被消灭时（无论是战斗胜利还是同归于尽）发出。
signal monster_killed
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
	call_deferred("_initialize_board")

# --- 公共接口 ---

## 根据给定的方向向量处理一次完整的移动操作。
##
## @param direction: 一个 Vector2i，如 Vector2i.UP，代表移动方向。
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
		# 只要有一行发生了移动，就标记为一次有效移动。
		if has_moved_in_row:
			moved = true
	
	# 仅在发生了有效移动时，才更新棋盘状态并生成新方块。
	if moved:
		# 步骤1: 将处理后的数据反向旋转，更新核心数据模型。
		grid = _unrotate_grid(new_grid_after_move, direction)
		
		# 步骤2: 根据新数据模型更新所有方块的视觉位置，并等待动画完成。
		var move_tweens = _update_board_visuals()
		if not move_tweens.is_empty():
			# 使用 await 等待所有移动动画播放完毕。
			for tween in move_tweens:
				await tween.finished
		
		# 步骤3: 在移动动画结束后，生成一个新的玩家方块，并等待其生成动画完成。
		var spawn_tween = spawn_tile()
		if spawn_tween != null:
			await spawn_tween.finished
			
		# 步骤4: 在所有动画都结束后，发出移动成功信号，并检查游戏是否结束。
		move_made.emit()
		_check_game_over()

## 在一个随机的空位上生成一个新的玩家方块（默认数值为2）。
##
## @return: 返回控制生成动画的 Tween 对象，若棋盘已满则返回 null。
func spawn_tile() -> Tween:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty():
		return null
	
	# 从所有空格中随机选择一个位置。
	var spawn_pos: Vector2i = empty_cells.pick_random()
	
	# 实例化、添加并设置新方块。
	var new_tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[spawn_pos.x][spawn_pos.y] = new_tile
	
	# 初始化方块的数值和类型，并设置其初始位置。
	new_tile.setup(2, new_tile.TileType.PLAYER)
	new_tile.position = _grid_to_pixel_center(spawn_pos)
	
	# 启动并返回生成动画。
	return new_tile.animate_spawn()

## 生成一个指定数值的怪物方块。
## 如果棋盘有空位，则在随机空位生成；如果棋盘已满，则执行特殊转化逻辑。
## @param monster_value: 要生成的怪物方块的数值。
func spawn_monster(monster_value: int) -> void:
	var empty_cells = _get_empty_cells()
	
	# 情况1：棋盘有空位，正常生成。
	if not empty_cells.is_empty():
		var spawn_pos: Vector2i = empty_cells.pick_random()
		var new_monster = TileScene.instantiate()
		
		board_container.add_child(new_monster)
		grid[spawn_pos.x][spawn_pos.y] = new_monster
		
		new_monster.setup(monster_value, new_monster.TileType.MONSTER)
		new_monster.position = _grid_to_pixel_center(spawn_pos)
		new_monster.animate_spawn()
		
	# 情况2：棋盘已满，执行转化逻辑。
	else:
		var player_tiles = _get_all_player_tiles()
		# 子情况A：棋盘上仍有玩家方块，随机将一个转变为怪物。
		if not player_tiles.is_empty():
			var tile_to_transform = player_tiles.pick_random()
			tile_to_transform.setup(monster_value, tile_to_transform.TileType.MONSTER)
			tile_to_transform.animate_transform()
		# 子情况B：棋盘上全是怪物方块，随机将一个数值翻倍以示“增强”。
		else:
			var monster_tiles = _get_all_monster_tiles()
			if not monster_tiles.is_empty():
				var tile_to_empower = monster_tiles.pick_random()
				tile_to_empower.setup(tile_to_empower.value * 2, tile_to_empower.TileType.MONSTER)

## 获取当前棋盘上数值最大的玩家方块的值。
##
## @return: 返回最大的玩家方块数值；如果没有玩家方块，则返回0。
func get_max_player_value() -> int:
	# 安全检查：如果棋盘尚未完全初始化，则直接返回0，避免访问无效数据。
	if not is_initialized:
		return 0

	var max_val = 0
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			# 确保方块存在、是玩家类型，并且其值大于当前记录的最大值。
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value > max_val:
				max_val = tile.value
	return max_val

## [测试用] 在指定位置生成一个特定方块。
##
## @param grid_pos: 要生成方块的网格坐标 (Vector2i)。
## @param value: 方块的数值。
## @param type: 方块的类型 (Tile.TileType.PLAYER 或 Tile.TileType.MONSTER)。
func spawn_specific_tile(grid_pos: Vector2i, value: int, type: Tile.TileType) -> void:
	# 检查坐标是否在棋盘有效范围内。
	if not (grid_pos.x >= 0 and grid_pos.x < grid_size and grid_pos.y >= 0 and grid_pos.y < grid_size):
		push_error("Spawn position is out of bounds.")
		return
		
	# 如果该位置已有方块，先将其安全移除。
	if grid[grid_pos.x][grid_pos.y] != null:
		grid[grid_pos.x][grid_pos.y].queue_free()
		grid[grid_pos.x][grid_pos.y] = null
		
	var new_tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[grid_pos.x][grid_pos.y] = new_tile
	
	new_tile.setup(value, type)
	new_tile.position = _grid_to_pixel_center(grid_pos)
	new_tile.animate_spawn()

## 重置整个棋盘并应用新的尺寸。
##
## @param new_size: 新的棋盘边长。
func reset_and_resize(new_size: int) -> void:
	# 清理旧的方块和背景单元格
	for child in board_container.get_children():
		child.queue_free()
	
	grid.clear()
	is_initialized = false
	grid_size = new_size
	
	# 重新开始初始化流程
	_initialize_board()
	board_resized.emit(grid_size)

## 在游戏进行中扩建棋盘（只能变大）。
##
## @param new_size: 新的棋盘边长，必须大于当前尺寸。
func live_expand(new_size: int) -> void:
	if new_size <= grid_size:
		push_warning("Live expand only supports increasing the grid size.")
		return
	
	var old_size = grid_size
	
	# 步骤1: 更新数据结构
	grid_size = new_size
	# 扩展现有的列
	for x in range(old_size):
		grid[x].resize(grid_size)
		grid[x].slice(old_size, grid_size - 1).fill(null)
	# 添加新的行
	grid.resize(grid_size)
	for x in range(old_size, grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)
	
	# 步骤2: 执行动画
	_animate_expansion(old_size, new_size)
	board_resized.emit(grid_size)

# --- 初始化与布局 ---

## 首次初始化棋盘或在重置后重新初始化。
func _initialize_board() -> void:
	_initialize_grid()
	_update_board_layout()
	# 确保在第一次布局完成后才生成方块
	if not is_initialized:
		_draw_board_cells()
		spawn_tile()
		spawn_tile()
		is_initialized = true

## 当GameBoard控件尺寸改变时，重新计算所有内部元素的位置和缩放。
func _update_board_layout() -> void:
	var layout_params = _calculate_layout_params(grid_size)
	if layout_params.is_empty():
		return

	# 应用变换到背景Panel和方块容器Node2D。
	board_background.position = layout_params.offset
	board_background.size = layout_params.scaled_size
	board_container.position = layout_params.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * layout_params.scale_ratio
	board_container.scale = Vector2(layout_params.scale_ratio, layout_params.scale_ratio)

# --- 内部核心逻辑 ---

## 处理单行（或列）的移动、合并与战斗逻辑。这是整个游戏的核心算法。
##
## @param line: 一个包含方块或 'null' 的一维数组。
## @return: 一个包含两个元素的数组：[处理后的新行, 是否发生了移动]。
func _process_line(line: Array) -> Array:
	# 步骤1: 移除所有空格，将所有方块紧贴在一起，方便后续处理。
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
				# 仅当数值相同时才合并。
				if current_tile.value == next_tile.value:
					next_tile.setup(current_tile.value * 2, current_tile.type)
					merged_line.append(next_tile)
					current_tile.queue_free() # 销毁被合并的方块。
					i += 2; continue # 跳过两个已处理的方块。
			
			# 情况B: 两个方块类型不同（玩家 vs 怪物），触发战斗。
			else:
				var player_tile = current_tile if current_tile.type == current_tile.TileType.PLAYER else next_tile
				var monster_tile = current_tile if current_tile.type == current_tile.TileType.MONSTER else next_tile
				
				# 子情况B1: 玩家胜，玩家数值变为除法结果，怪物消失。
				if player_tile.value > monster_tile.value:
					player_tile.setup(int(player_tile.value / monster_tile.value), player_tile.type)
					merged_line.append(player_tile)
					monster_tile.queue_free()
					monster_killed.emit()
				# 子情况B2: 怪物胜，怪物数值变为除法结果，玩家消失。
				elif player_tile.value < monster_tile.value:
					monster_tile.setup(int(monster_tile.value / player_tile.value), monster_tile.type)
					merged_line.append(monster_tile)
					player_tile.queue_free()
				# 子情况B3: 数值相等，同归于尽。
				else:
					player_tile.queue_free()
					monster_tile.queue_free()
					monster_killed.emit()
				i += 2; continue
				
		# 如果没有发生合并或战斗，则直接将当前方块加入结果行。
		merged_line.append(current_tile)
		i += 1
		
	# 步骤3: 用 'null' 填充行末的空格，使其恢复标准长度。
	var result_line = merged_line.duplicate()
	while result_line.size() < grid_size: result_line.append(null)
	
	# 步骤4: 比较处理后的行与原始行，判断是否发生了实质性移动。
	var has_moved = false
	if result_line.size() != line.size(): has_moved = true
	else:
		for idx in range(result_line.size()):
			# 只要对应位置的方块实例ID不同，就认为发生了移动。
			if (result_line[idx] == null and line[idx] != null) or \
			   (result_line[idx] != null and line[idx] == null) or \
			   (result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true; break
				
	return [result_line, has_moved]

## 检查游戏是否结束。
## 仅在棋盘已满时触发检查，判断是否还有任何可能的移动。
func _check_game_over() -> void:
	# 如果棋盘仍有空位，游戏不可能结束。
	if not _get_empty_cells().is_empty():
		return

	# 遍历棋盘，检查是否存在任何可能的移动（相邻方块可合并或战斗）。
	for x in range(grid_size):
		for y in range(grid_size):
			var current_tile = grid[x][y]
			if current_tile == null: continue
			
			# 检查右侧相邻方块。
			if x + 1 < grid_size:
				var right_tile = grid[x + 1][y]
				# 如果类型不同（可战斗）或类型相同且数值相等（可合并），则存在移动可能。
				if right_tile != null and (current_tile.type != right_tile.type or current_tile.value == right_tile.value):
					return # 找到一个可能移动，提前退出。
					
			# 检查下方相邻方块。
			if y + 1 < grid_size:
				var down_tile = grid[x][y + 1]
				if down_tile != null and (current_tile.type != down_tile.type or current_tile.value == down_tile.value):
					return # 找到一个可能移动，提前退出。
					
	# 如果遍历完所有方块都没有找到可移动的组合，则游戏失败。
	game_lost.emit()

# --- 视觉与动画 ---

## 根据 `grid` 数组中的数据，更新场景中所有方块节点的实际位置。
##
## @return: 返回一个包含所有活动移动动画 (Tween) 的数组。
func _update_board_visuals() -> Array:
	var active_tweens = []
	for x in grid_size:
		for y in grid_size:
			if grid[x][y] != null:
				var tile = grid[x][y]
				var new_pixel_pos = _grid_to_pixel_center(Vector2i(x, y))
				# 如果方块的当前视觉位置与数据模型中的目标位置不符，则为其创建移动动画。
				if tile.position != new_pixel_pos:
					var move_tween = tile.animate_move(new_pixel_pos)
					active_tweens.append(move_tween)
	return active_tweens

## 绘制棋盘的灰色背景单元格，作为视觉基础。
func _draw_board_cells():
	# 先清除旧的单元格背景
	for child in board_container.get_children():
		if child is Panel:
			child.queue_free()
			
	for x in grid_size:
		for y in grid_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = Color("3c3c3c")
			stylebox.corner_radius_top_left = 8
			stylebox.corner_radius_top_right = 8
			stylebox.corner_radius_bottom_right = 8
			stylebox.corner_radius_bottom_left = 8
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			
			cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell_bg.position = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))
			board_container.add_child(cell_bg)
			# 将背景格子置于底层
			board_container.move_child(cell_bg, 0)

## 执行棋盘扩建动画。
func _animate_expansion(old_size: int, new_size: int) -> void:
	# 步骤 1: 计算最终的布局参数
	var final_layout = _calculate_layout_params(new_size)
	if final_layout.is_empty(): return # 如果布局无效则提前退出

	# 步骤 2: 创建并行动画，让所有容器的属性一步到位地过渡到最终状态
	var main_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	
	# 动画 2a: 背景面板平滑地移动到新位置并调整大小
	main_tween.tween_property(board_background, "position", final_layout.offset, 0.3)
	main_tween.tween_property(board_background, "size", final_layout.scaled_size, 0.3)
	
	# 动画 2b: 方块容器也直接平滑地移动到新位置并缩放到最终比例
	var final_container_pos = final_layout.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * final_layout.scale_ratio
	main_tween.tween_property(board_container, "position", final_container_pos, 0.3)
	main_tween.tween_property(board_container, "scale", Vector2(final_layout.scale_ratio, final_layout.scale_ratio), 0.3)
	
	# 等待主过渡动画完成
	await main_tween.finished
	
	# 步骤 3: 清理旧的背景格子
	for child in board_container.get_children():
		if child is Panel:
			child.queue_free()

	# 步骤 4: 创建并行动画，重新绘制所有背景格子，并为新格子添加出现动画
	var new_cells_tween = create_tween().set_parallel(true)
	for x in new_size:
		for y in new_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = Color("3c3c3c")
			stylebox.corner_radius_top_left = 8
			stylebox.corner_radius_top_right = 8
			stylebox.corner_radius_bottom_right = 8
			stylebox.corner_radius_bottom_left = 8
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			
			var final_size = Vector2(CELL_SIZE, CELL_SIZE)
			var final_pos = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))

			board_container.add_child(cell_bg)
			board_container.move_child(cell_bg, 0) # 确保在最底层

			# 为新增加的格子创建“从中心扩大”的出现动画
			if x >= old_size or y >= old_size:
				var center_pos = final_pos + final_size / 2.0
				cell_bg.size = Vector2.ZERO
				cell_bg.position = center_pos
				
				# 同时动画化 size 和 position，实现平滑的从中心放大效果
				new_cells_tween.tween_property(cell_bg, "size", final_size, 0.2).set_delay(0.05 * (x + y))
				new_cells_tween.tween_property(cell_bg, "position", final_pos, 0.2).set_delay(0.05 * (x + y))
			# 对于原有的格子，直接设置最终状态，确保它们正确显示
			else:
				cell_bg.size = final_size
				cell_bg.position = final_pos

	# 等待新格子出现动画完成
	await new_cells_tween.finished
	
	# 步骤 5: 最后，调用一次视觉更新，确保所有数字方块都精确地在其网格位置上
	_update_board_visuals()

# --- 辅助函数 ---

## 初始化核心数据 `grid`，创建一个填满 'null' 的二维数组。
func _initialize_grid():
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)

## 遍历网格，返回所有玩家方块节点的数组。
##
## @return: 一个包含场景中所有玩家方块 (Tile) 节点的数组。
func _get_all_player_tiles() -> Array:
	var player_tiles = []
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER:
				player_tiles.append(tile)
	return player_tiles

## 遍历网格，返回所有怪物方块节点的数组。
##
## @return: 一个包含场景中所有怪物方块 (Tile) 节点的数组。
func _get_all_monster_tiles() -> Array:
	var monster_tiles = []
	for x in grid_size:
		for y in grid_size:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.MONSTER:
				monster_tiles.append(tile)
	return monster_tiles

## 遍历整个网格，返回所有空格子坐标的数组。
##
## @return: 一个包含所有空单元格 Vector2i 坐标的数组。
func _get_empty_cells() -> Array:
	var empty_cells = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells

## 根据移动方向，返回一个旋转后的虚拟网格。
## 这个技巧可以将所有方向的移动逻辑（上、下、右）统一为向左移动。
##
## @param direction: 移动方向向量。
## @return: 一个新的二维数组，代表旋转后的网格。
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

## 将一个被旋转过的网格数据恢复到其原始的对应位置。
##
## @param rotated_grid: 经过 `_get_rotated_grid` 处理后的网格。
## @param direction: 原始的移动方向。
## @return: 恢复了正确方向的新网格数据。
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

## 将网格坐标转换为 board_container 内的局部像素坐标（返回格子中心点）。
##
## @param grid_pos: 网格坐标 (Vector2i)。
## @return: 对应的局部中心点像素坐标 (Vector2)。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos = Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))
	return top_left_pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

## [辅助函数] 抽离出布局计算逻辑，方便复用。
##
## @param p_size: 用于计算的棋盘边长。
## @return: 一个包含 scale_ratio, scaled_size, offset 的字典。
func _calculate_layout_params(p_size: int) -> Dictionary:
	var grid_area_side = p_size * CELL_SIZE + (p_size - 1) * SPACING
	var logical_board_side = grid_area_side + BOARD_PADDING * 2
	
	var current_size = self.size
	if current_size.x == 0 or current_size.y == 0:
		return {}

	var scale_ratio = min(current_size.x / logical_board_side, current_size.y / logical_board_side)
	var scaled_size = Vector2(logical_board_side, logical_board_side) * scale_ratio
	var offset = (current_size - scaled_size) / 2.0

	return {
		"scale_ratio": scale_ratio,
		"scaled_size": scaled_size,
		"offset": offset
	}
