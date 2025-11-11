# scripts/core/game_board.gd

## GameBoard: 负责管理整个游戏棋盘的核心逻辑。
##
## 该脚本处理棋盘的初始化、方块的生成、移动和交互。它被设计为一个通用的“执行者”，
## 自身不包含任何具体的游戏规则（如如何合并、如何算输），而是通过外部注入的规则对象来执行逻辑。
## 通过全局事件总线（EventBus）发布游戏事件，实现了逻辑与表现的分离。
class_name GameBoard
extends Control


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


# --- 公共变量 ---

## 棋盘的尺寸（例如 4x4 中的 4）。
var grid_size: int = 4

## 存储棋盘上所有方块节点的二维数组引用。'null'代表空格。
var grid: Array = []


# --- 私有变量 ---

## 防止在窗口大小改变时重复初始化棋盘。
var _is_initialized: bool = false


# --- 规则引用 ---

## 外部注入的方块交互规则。
var interaction_rule: InteractionRule

## 外部注入的方块移动规则。
var movement_rule: MovementRule

## 外部注入的游戏结束判断规则。
var game_over_rule: GameOverRule

## 外部注入的配色方案字典。
var color_schemes: Dictionary

## 外部注入的棋盘与背景主题。
var board_theme: BoardTheme


# --- @onready 变量 (节点引用) ---

@onready var board_background: Panel = %BoardBackground
@onready var board_container: Node2D = %BoardContainer


# --- Godot 生命周期方法 ---

func _ready() -> void:
	resized.connect(_on_resized)


# --- 公共方法 ---

## 设置当前棋盘使用的规则集和主题。
##
## 这是外部（如GamePlay.gd）将具体玩法注入棋盘的入口。
## @param p_interaction_rule: 方块交互规则。
## @param p_movement_rule: 方块移动规则。
## @param p_game_over_rule: 游戏结束规则。
## @param p_color_schemes: 配色方案字典。
## @param p_board_theme: 棋盘主题。
func set_rules(p_interaction_rule: InteractionRule, p_movement_rule: MovementRule, p_game_over_rule: GameOverRule, p_color_schemes: Dictionary, p_board_theme: BoardTheme) -> void:
	self.interaction_rule = p_interaction_rule
	self.movement_rule = p_movement_rule
	self.game_over_rule = p_game_over_rule
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme

	if is_instance_valid(self.movement_rule):
		self.movement_rule.setup(self.interaction_rule)


## 初始化棋盘。
##
## 由 GamePlay 在设置完规则后调用。
func initialize_board() -> void:
	_initialize_grid()
	_update_board_layout()

	if not _is_initialized:
		_draw_board_cells()
		_is_initialized = true


## 根据给定的方向向量处理一次完整的移动操作。
## @param direction: 移动方向的向量 (例如 Vector2i.UP)。
## @return: 如果有任何方块发生移动或合并，则返回 true。
func handle_move(direction: Vector2i) -> bool:
	var moved: bool = false
	var instructions: Array[Dictionary] = []
	var new_grid: Array = []
	new_grid.resize(grid_size)

	for i in range(grid_size):
		new_grid[i] = []
		new_grid[i].resize(grid_size)
		new_grid[i].fill(null)

	var moved_lines_indices: Array[int] = []

	for i in range(grid_size):
		var line: Array[Tile] = []

		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction)
			line.append(grid[coords.x][coords.y])

		var result: Dictionary = movement_rule.process_line(line)
		var new_line: Array[Tile] = result.line
		var merges: Array[Dictionary] = result.merges

		if result.moved:
			moved = true
			if not i in moved_lines_indices:
				moved_lines_indices.append(i)

		for merge_info in merges:
			var consumed: Tile = merge_info.consumed_tile
			var merged: Tile = merge_info.merged_tile
			var final_line_pos: int = new_line.find(merged)
			var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction)
			instructions.append({
				"type": "MERGE",
				"consumed_tile": consumed,
				"merged_tile": merged,
				"to_pos": _grid_to_pixel_center(final_coords)
			})

		var tiles_in_new_line: Dictionary = {}
		for tile in new_line:
			if tile: tiles_in_new_line[tile.get_instance_id()] = true

		for j in range(grid_size):
			var original_tile: Tile = line[j]

			if original_tile and not tiles_in_new_line.has(original_tile.get_instance_id()):
				continue

			var final_line_pos: int = new_line.find(original_tile)

			if original_tile and final_line_pos != -1 and final_line_pos != j:
				var final_coords: Vector2i = _get_coords_for_line(i, final_line_pos, direction)

				instructions.append({
					"type": "MOVE",
					"tile": original_tile,
					"to_pos": _grid_to_pixel_center(final_coords)
				})

		for j in range(grid_size):
			var coords: Vector2i = _get_coords_for_line(i, j, direction)
			new_grid[coords.x][coords.y] = new_line[j]

	if moved:
		var move_data: Dictionary = {
			"direction": direction,
			"moved_lines": moved_lines_indices
		}

		grid = new_grid
		EventBus.move_made.emit(move_data)
		play_animations_requested.emit(instructions)
		_check_game_over()

	return moved


## 根据提供的spawn_data字典生成一个方块。
## @param spawn_data: 包含生成信息的字典。
func spawn_tile(spawn_data: Dictionary) -> void:
	var value: int = spawn_data.get("value", 2)
	var type: Tile.TileType = spawn_data.get("type", Tile.TileType.PLAYER)
	var is_priority: bool = spawn_data.get("is_priority", false)
	var spawn_pos: Vector2i
	var has_specific_pos: bool = spawn_data.has("position")

	if has_specific_pos:
		spawn_pos = spawn_data["position"]
		if grid[spawn_pos.x][spawn_pos.y] != null:
			push_error("生成失败：尝试在非空位置 %s 生成方块。" % str(spawn_pos))
			return
	else:
		var empty_cells: Array[Vector2i] = get_empty_cells()
		if not empty_cells.is_empty():
			spawn_pos = empty_cells[RNGManager.get_rng().randi_range(0, empty_cells.size() - 1)]
		else:
			if is_priority:
				var player_tiles: Array[Tile] = _get_all_player_tiles()
				if not player_tiles.is_empty():
					var tile_to_transform: Tile = player_tiles[RNGManager.get_rng().randi_range(0, player_tiles.size() - 1)]
					tile_to_transform.setup(value, type, interaction_rule, color_schemes)
					tile_to_transform.animate_transform()
				else:
					var monster_tiles: Array[Tile] = _get_all_monster_tiles()
					if not monster_tiles.is_empty():
						var tile_to_empower: Tile = monster_tiles[RNGManager.get_rng().randi_range(0, monster_tiles.size() - 1)]
						tile_to_empower.setup(tile_to_empower.value * 2, type, interaction_rule, color_schemes)
			return

	var new_tile: Tile = _spawn_at(spawn_pos, value, type)
	var instruction: Array = [{"type": "SPAWN", "tile": new_tile}]
	play_animations_requested.emit(instruction)


## 获取当前棋盘上数值最大的玩家方块的值。
## @return: 最大的玩家方块数值。
func get_max_player_value() -> int:
	if not _is_initialized:
		return 0
	var max_val: int = 0
	for x in grid_size:
		for y in grid_size:
			var tile: Tile = grid[x][y]
			if tile and tile.type == tile.TileType.PLAYER and tile.value > max_val:
				max_val = tile.value
	return max_val


## 在指定网格位置生成一个特定方块，主要用于测试。
## @param grid_pos: 生成位置的网格坐标。
## @param value: 生成方块的数值。
## @param type: 生成方块的类型。
func spawn_specific_tile(grid_pos: Vector2i, value: int, type: Tile.TileType) -> void:
	if not (grid_pos.x >= 0 and grid_pos.x < grid_size and grid_pos.y >= 0 and grid_pos.y < grid_size):
		push_error("Spawn position is out of bounds.")
		return

	if grid[grid_pos.x][grid_pos.y] != null:
		grid[grid_pos.x][grid_pos.y].queue_free()
		grid[grid_pos.x][grid_pos.y] = null

	var new_tile: Tile = _spawn_at(grid_pos, value, type)
	var instruction: Array = [{"type": "SPAWN", "tile": new_tile}]
	play_animations_requested.emit(instruction)


## 在游戏进行中扩建棋盘（只能变大）。
## @param new_size: 扩建后的新尺寸。
func live_expand(new_size: int) -> void:
	if new_size <= grid_size:
		push_warning("Live expand only supports increasing the grid size.")
		return

	var old_size: int = grid_size
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
## @return: 一个包含所有空单元格 Vector2i 坐标的数组。
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	for x in range(grid_size):
		for y in range(grid_size):
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells


## 遍历整个网格，返回所有玩家方块数值的数组。
## @return: 一个已排序的、包含所有玩家方块数值的数组。
func get_all_player_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile: Tile = grid[x][y]
			if tile and tile.type == Tile.TileType.PLAYER:
				values.append(tile.value)
	values.sort()
	return values


## 获取当前棋盘所有方块状态的可序列化快照。
## @return: 一个字典，包含grid_size和所有方块的数据。
func get_state_snapshot() -> Dictionary:
	var tiles_data: Array[Dictionary] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var tile: Tile = grid[x][y]
			if tile != null:
				tiles_data.append({
					"pos": Vector2i(x, y),
					"value": tile.value,
					"type": tile.type
				})
	return {
		"grid_size": grid_size,
		"tiles": tiles_data,
	}


## 从一个快照数据中完全恢复棋盘状态。
## @param snapshot: 包含棋盘状态的字典。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	for child in board_container.get_children():
		if child is Tile:
			child.queue_free()

	_initialize_grid()
	var tiles_data: Array = snapshot.get("tiles", [])
	for tile_data in tiles_data:
		var pos: Vector2i = tile_data["pos"]
		var value: int = tile_data["value"]
		var type: Tile.TileType = tile_data["type"]
		var new_tile: Tile = _spawn_at(pos, value, type)
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0


# --- 私有/辅助方法 ---

## 初始化核心数据 `grid`，创建一个填满 null 的二维数组。
func _initialize_grid() -> void:
	grid.resize(grid_size)
	for x in range(grid_size):
		grid[x] = []
		grid[x].resize(grid_size)
		grid[x].fill(null)


## 更新棋盘的整体布局以适应其容器大小。
func _update_board_layout() -> void:
	var layout_params: Dictionary = _calculate_layout_params(grid_size)
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
	for child in board_container.get_children():
		if child is Panel:
			child.queue_free()

	var cell_color := Color("3c3c3c")
	if is_instance_valid(board_theme):
		cell_color = board_theme.empty_cell_color

	for x in grid_size:
		for y in grid_size:
			var cell_bg := Panel.new()
			var stylebox := StyleBoxFlat.new()
			stylebox.bg_color = cell_color
			stylebox.set_corner_radius_all(8)
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			cell_bg.size = Vector2.ONE * CELL_SIZE
			cell_bg.position = Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))
			board_container.add_child(cell_bg)
			board_container.move_child(cell_bg, 0)


## 检查游戏是否结束，委托给 game_over_rule。
func _check_game_over() -> void:
	if game_over_rule.is_game_over(self, interaction_rule):
		EventBus.game_lost.emit()


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

	for child in board_container.get_children():
		if child is Panel: child.queue_free()

	var new_cells_tween := create_tween().set_parallel(true)
	var cell_color := Color("3c3c3c")
	if is_instance_valid(board_theme):
		cell_color = board_theme.empty_cell_color

	for x in new_size:
		for y in new_size:
			var cell_bg := Panel.new()
			var stylebox := StyleBoxFlat.new()
			stylebox.bg_color = cell_color
			stylebox.set_corner_radius_all(8)
			cell_bg.add_theme_stylebox_override("panel", stylebox)
			var final_size := Vector2.ONE * CELL_SIZE
			var final_pos := Vector2(x * (CELL_SIZE + SPACING), y * (CELL_SIZE + SPACING))
			board_container.add_child(cell_bg)
			board_container.move_child(cell_bg, 0)

			if x >= old_size or y >= old_size:
				var center_pos: Vector2 = final_pos + final_size / 2.0
				cell_bg.size = Vector2.ZERO
				cell_bg.position = center_pos
				new_cells_tween.tween_property(cell_bg, "size", final_size, 0.2).set_delay(0.05 * (x + y))
				new_cells_tween.tween_property(cell_bg, "position", final_pos, 0.2).set_delay(0.05 * (x + y))
			else:
				cell_bg.size = final_size
				cell_bg.position = final_pos
	await new_cells_tween.finished


## 在指定位置生成一个方块的内部实现。
## @return: 新创建的 Tile 实例。
func _spawn_at(grid_pos: Vector2i, value: int, type: Tile.TileType) -> Tile:
	var new_tile := TileScene.instantiate() as Tile
	board_container.add_child(new_tile)
	grid[grid_pos.x][grid_pos.y] = new_tile
	new_tile.setup(value, type, interaction_rule, color_schemes)
	new_tile.position = _grid_to_pixel_center(grid_pos)
	new_tile.scale = Vector2.ZERO
	new_tile.rotation_degrees = -360
	return new_tile


## 遍历网格，返回所有玩家方块节点的数组。
## @return: 一个包含所有 Tile 节点的数组，这些节点的类型是 PLAYER。
func _get_all_player_tiles() -> Array[Tile]:
	var player_tiles: Array[Tile] = []
	for x in grid_size:
		for y in grid_size:
			var tile: Tile = grid[x][y]
			if tile and tile.type == tile.TileType.PLAYER:
				player_tiles.append(tile)
	return player_tiles


## 遍历网格，返回所有怪物方块节点的数组。
## @return: 一个包含所有 Tile 节点的数组，这些节点的类型是 MONSTER。
func _get_all_monster_tiles() -> Array[Tile]:
	var monster_tiles: Array[Tile] = []
	for x in grid_size:
		for y in grid_size:
			var tile: Tile = grid[x][y]
			if tile and tile.type == tile.TileType.MONSTER:
				monster_tiles.append(tile)
	return monster_tiles


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


## 根据方向，将“行索引”和“行内索引”转换为全局的grid坐标。
## @return: 转换后的全局网格坐标 (Vector2i)。
func _get_coords_for_line(line_index: int, cell_index: int, direction: Vector2i) -> Vector2i:
	match direction:
		Vector2i.LEFT: return Vector2i(cell_index, line_index)
		Vector2i.RIGHT: return Vector2i(grid_size - 1 - cell_index, line_index)
		Vector2i.UP: return Vector2i(line_index, cell_index)
		Vector2i.DOWN: return Vector2i(line_index, grid_size - 1 - cell_index)
	return Vector2i.ZERO


# --- 信号处理函数 ---

## 当棋盘尺寸改变时，更新布局。
func _on_resized() -> void:
	_update_board_layout()
