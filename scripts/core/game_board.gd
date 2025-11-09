# scripts/game_board.gd

## GameBoard: 负责管理整个游戏棋盘的核心逻辑。
##
## 该脚本处理棋盘的初始化、方块的生成、移动和交互。它被设计为一个通用的“执行者”，
## 自身不包含任何具体的游戏规则（如如何合并、如何算输），而是通过外部注入的规则对象来执行逻辑。
## 通过全局事件总线（EventBus）发布游戏事件，实现了逻辑与表现的分离。
extends Control

# --- 常量与预加载资源 ---

# 预加载方块场景，用于在运行时动态实例化。
const TileScene = preload("res://scenes/conponents/tile.tscn")

# 每个单元格的像素尺寸。
const CELL_SIZE: int = 100
# 单元格之间的间距。
const SPACING: int = 15
# 棋盘背景的内边距。
const BOARD_PADDING: int = 15

signal play_animations_requested(instructions: Array)

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
# 外部注入的方块移动规则。
var movement_rule: MovementRule
# 外部注入的游戏结束判断规则。
var game_over_rule: GameOverRule
# 外部注入的配色方案字典。
var color_schemes: Dictionary
# 外部注入的棋盘与背景主题。
var board_theme: BoardTheme

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

# --- 公共接口 ---

## 设置当前棋盘使用的规则集和主题。
## 这是外部（如GamePlay.gd）将具体玩法注入棋盘的入口。
func set_rules(p_interaction_rule: InteractionRule, p_movement_rule: MovementRule, p_game_over_rule: GameOverRule, p_color_schemes: Dictionary, p_board_theme: BoardTheme) -> void:
	self.interaction_rule = p_interaction_rule
	self.movement_rule = p_movement_rule
	self.game_over_rule = p_game_over_rule
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme

	# 将交互规则注入到移动规则中，因为移动时需要判断合并
	if is_instance_valid(self.movement_rule):
		self.movement_rule.setup(self.interaction_rule)

## 公共的初始化函数，由 GamePlay 在设置完规则后调用。
func initialize_board() -> void:
	_initialize_grid()
	_update_board_layout()
	if not is_initialized:
		_draw_board_cells()
		is_initialized = true

## 根据给定的方向向量处理一次完整的移动操作。
func handle_move(direction: Vector2i) -> bool:
	var moved = false
	var instructions: Array[Dictionary] = []
	var new_grid: Array = []
	new_grid.resize(grid_size)
	for i in range(grid_size):
		new_grid[i] = []; new_grid[i].resize(grid_size)
		new_grid[i].fill(null)

	# 追踪发生了移动的行/列的索引
	var moved_lines_indices: Array[int] = []

	# 逐行/逐列处理
	for i in range(grid_size):
		var line: Array[Tile] = []
		for j in range(grid_size):
			var coords = _get_coords_for_line(i, j, direction)
			line.append(grid[coords.x][coords.y])

		var result = movement_rule.process_line(line)
		var new_line: Array[Tile] = result.line
		var merges: Array[Dictionary] = result.merges

		# 检查这一行/列是否发生了移动
		if result.moved:
			moved = true
			if not i in moved_lines_indices:
				moved_lines_indices.append(i)

		# 处理合并动画指令
		for merge_info in merges:
			var consumed: Tile = merge_info.consumed_tile
			var merged: Tile = merge_info.merged_tile

			# 找到合并后方块在新行中的位置
			var final_line_pos = new_line.find(merged)
			var final_coords = _get_coords_for_line(i, final_line_pos, direction)

			instructions.append({
				"type": "MERGE",
				"consumed_tile": consumed,
				"merged_tile": merged,
				"to_pos": _grid_to_pixel_center(final_coords)
			})

		# 处理滑动动画指令
		var tiles_in_new_line: Dictionary = {}
		for tile in new_line:
			if tile: tiles_in_new_line[tile.get_instance_id()] = true

		for j in range(grid_size):
			var original_tile = line[j]
			if original_tile and not tiles_in_new_line.has(original_tile.get_instance_id()):
				continue

			var final_line_pos = new_line.find(original_tile)
			if original_tile and final_line_pos != -1 and final_line_pos != j:
				var final_coords = _get_coords_for_line(i, final_line_pos, direction)
				instructions.append({
					"type": "MOVE",
					"tile": original_tile,
					"to_pos": _grid_to_pixel_center(final_coords)
				})

		# 将处理完的行放回新的网格中
		for j in range(grid_size):
			var coords = _get_coords_for_line(i, j, direction)
			new_grid[coords.x][coords.y] = new_line[j]

	if moved:
		var move_data = {
			"direction": direction,
			"moved_lines": moved_lines_indices
		}

		grid = new_grid
		EventBus.move_made.emit(move_data)
		play_animations_requested.emit(instructions)

		# 逻辑层立即检查游戏是否结束
		_check_game_over()

	return moved

## 生成一个指定信息的方块。
func spawn_tile(spawn_data: Dictionary) -> void:
	var value = spawn_data.get("value", 2)
	var type = spawn_data.get("type", Tile.TileType.PLAYER)
	var is_priority = spawn_data.get("is_priority", false)

	# 检查是否提供了指定的生成位置
	var spawn_pos: Vector2i
	var has_specific_pos = spawn_data.has("position")

	if has_specific_pos:
		spawn_pos = spawn_data["position"]
		# 安全检查，确保指定位置是空的
		if grid[spawn_pos.x][spawn_pos.y] != null:
			push_error("生成失败：尝试在非空位置 %s 生成方块。" % str(spawn_pos))
			return
	else:
		var empty_cells = get_empty_cells()
		if not empty_cells.is_empty():
			spawn_pos = empty_cells[RNGManager.get_rng().randi_range(0, empty_cells.size() - 1)]
		else:
			# 棋盘已满
			if is_priority:
				var player_tiles = _get_all_player_tiles()
				if not player_tiles.is_empty():
					var tile_to_transform = player_tiles[RNGManager.get_rng().randi_range(0, player_tiles.size() - 1)]
					tile_to_transform.setup(value, type, interaction_rule, color_schemes)
					tile_to_transform.animate_transform()
				else:
					var monster_tiles = _get_all_monster_tiles()
					if not monster_tiles.is_empty():
						var tile_to_empower = monster_tiles[RNGManager.get_rng().randi_range(0, monster_tiles.size() - 1)]
						tile_to_empower.setup(tile_to_empower.value * 2, type, interaction_rule, color_schemes)
			return # 棋盘已满且非优先，直接返回

	var new_tile = _spawn_at(spawn_pos, value, type)
	var instruction = [{"type": "SPAWN", "tile": new_tile}]
	play_animations_requested.emit(instruction)

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

	var new_tile = _spawn_at(grid_pos, value, type)

	# 为测试工具生成的方块请求播放生成动画，使其可见。
	var instruction = [{"type": "SPAWN", "tile": new_tile}]
	play_animations_requested.emit(instruction)

## 重置整个棋盘并应用新的尺寸。
func reset_and_resize(new_size: int, p_board_theme: BoardTheme) -> void:
	self.board_theme = p_board_theme
	for child in board_container.get_children():
		child.queue_free()

	grid.clear()
	is_initialized = false
	grid_size = new_size

	EventBus.board_resized.emit(grid_size)

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
	EventBus.board_resized.emit(grid_size)

## 遍历整个网格，返回所有空格子坐标的数组。
func get_empty_cells() -> Array:
	var empty_cells = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells

## 遍历整个网格，返回所有玩家方块数值的数组。
func get_all_player_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile = grid[x][y]
			if tile != null and tile.type == Tile.TileType.PLAYER:
				values.append(tile.value)
	values.sort()
	return values

# --- 初始化与布局 ---

## 当GameBoard控件尺寸改变时，重新计算并应用所有内部元素的变换。
func _update_board_layout() -> void:
	var layout_params = _calculate_layout_params(grid_size)
	if layout_params.is_empty(): return
	if is_instance_valid(board_theme):
		var panel_style: StyleBoxFlat = board_background.get_theme_stylebox("panel").duplicate()
		panel_style.bg_color = board_theme.board_panel_color
		board_background.add_theme_stylebox_override("panel", panel_style)
	board_background.position = layout_params.offset
	board_background.size = layout_params.scaled_size
	board_container.position = layout_params.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * layout_params.scale_ratio
	board_container.scale = Vector2(layout_params.scale_ratio, layout_params.scale_ratio)

# --- 内部核心逻辑 ---

## 检查游戏是否结束，现在委托给 game_over_rule。
func _check_game_over() -> void:
	# 将判断逻辑委托给注入的规则对象。
	if game_over_rule.is_game_over(self, interaction_rule):
		EventBus.game_lost.emit()

# --- 视觉与动画 ---

## 绘制棋盘的静态背景单元格。
func _draw_board_cells():
	for child in board_container.get_children():
		if child is Panel: child.queue_free()

	var cell_color = Color("3c3c3c") # 默认后备颜色
	if is_instance_valid(board_theme):
		cell_color = board_theme.empty_cell_color

	for x in grid_size:
		for y in grid_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = cell_color
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

	var cell_color = Color("3c3c3c") # 默认后备颜色
	if is_instance_valid(board_theme):
		cell_color = board_theme.empty_cell_color

	for x in new_size:
		for y in new_size:
			var cell_bg = Panel.new()
			var stylebox = StyleBoxFlat.new()
			stylebox.bg_color = cell_color
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

# --- 辅助函数 ---

## 将棋盘容器内的局部像素坐标转换为网格坐标。
func _pixel_to_grid(pixel_pos: Vector2) -> Vector2i:
	var x = round(pixel_pos.x / (CELL_SIZE + SPACING))
	var y = round(pixel_pos.y / (CELL_SIZE + SPACING))
	return Vector2i(int(x), int(y))

## 在指定位置生成一个方块的内部实现。
func _spawn_at(grid_pos: Vector2i, value: int, type: Tile.TileType) -> Tile:
	var new_tile: Tile = TileScene.instantiate()
	board_container.add_child(new_tile)
	grid[grid_pos.x][grid_pos.y] = new_tile

	new_tile.setup(value, type, interaction_rule, color_schemes)
	new_tile.position = _grid_to_pixel_center(grid_pos)

	# 动画将由BoardAnimator触发，这里只设置初始状态
	new_tile.scale = Vector2.ZERO
	new_tile.rotation_degrees = -360

	return new_tile # 返回实例供外部生成指令

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

## 坐标转换辅助函数
## 根据方向，将“行索引”和“行内索引”转换为全局的grid坐标
func _get_coords_for_line(line_index: int, cell_index: int, direction: Vector2i) -> Vector2i:
	match direction:
		Vector2i.LEFT: return Vector2i(cell_index, line_index)
		Vector2i.RIGHT: return Vector2i(grid_size - 1 - cell_index, line_index)
		Vector2i.UP: return Vector2i(line_index, cell_index)
		Vector2i.DOWN: return Vector2i(line_index, grid_size - 1 - cell_index)
	return Vector2i.ZERO

# --- 状态保存与恢复 ---

## 获取当前棋盘所有方块状态的可序列化快照。
## @return: 一个字典，包含grid_size和所有方块的数据。
func get_state_snapshot() -> Dictionary:
	var tiles_data: Array[Dictionary] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile = grid[x][y]
			if tile != null:
				tiles_data.append({
					"pos": Vector2i(x, y),
					"value": tile.value,
					"type": tile.type
				})
	return {
		"grid_size": grid_size,
		"tiles": tiles_data
	}

## 从一个快照数据中完全恢复棋盘状态。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	# 步骤1: 清理当前所有方块。
	for child in board_container.get_children():
		if child is Tile:
			child.queue_free()

	# 步骤2: 重置grid并根据快照数据重新创建方块。
	_initialize_grid() # 确保grid数组结构正确

	var tiles_data = snapshot.get("tiles", [])
	for tile_data in tiles_data:
		var pos: Vector2i = tile_data["pos"]
		var value: int = tile_data["value"]
		var type: Tile.TileType = tile_data["type"]

		var new_tile: Tile = _spawn_at(pos, value, type)

		# 恢复时，方块直接出现，不播放生成动画。
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0
