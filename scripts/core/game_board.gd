# scripts/core/game_board.gd

## GameBoard: 负责游戏棋盘的视觉呈现和输入转发。
##
## 它持有 GridModel (逻辑核心)，并根据 Model 的信号更新 Tile 节点的位置和状态。
## 它是 Model 的 View。
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

## 外部注入的游戏结束判断规则。
var game_over_rule: GameOverRule


# --- 私有变量 ---

## 防止在窗口大小改变时重复初始化棋盘。
var _is_initialized: bool = false


# --- @onready 变量 (节点引用) ---

@onready var board_background: Panel = %BoardBackground
@onready var board_container: Node2D = %BoardContainer


# --- Godot 生命周期方法 ---

func _ready() -> void:
	resized.connect(_on_resized)


# --- 公共方法 ---

## 设置并初始化棋盘。
## @param grid_size: 棋盘尺寸。
## @param interaction_rule: 交互规则实例。
## @param movement_rule: 移动规则实例。
## @param p_game_over_rule: 游戏结束规则。
## @param p_color_schemes: 配色方案字典。
## @param p_board_theme: 棋盘主题。
func setup(grid_size: int, interaction_rule: InteractionRule, movement_rule: MovementRule, p_game_over_rule: GameOverRule, p_color_schemes: Dictionary, p_board_theme: BoardTheme) -> void:
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme
	self.game_over_rule = p_game_over_rule

	model = GridModel.new()
	model.initialize(grid_size, interaction_rule, movement_rule)

	model.board_changed.connect(_on_model_board_changed)
	model.tile_spawned.connect(_on_model_tile_spawned)
	model.score_updated.connect(_on_model_score_updated)

	_update_board_layout()
	_draw_board_cells()
	_is_initialized = true


## 处理移动请求（转发给模型）。
## @param direction: 移动方向向量。
## @return: 如果发生了有效移动，返回 true。
func handle_move(direction: Vector2i) -> bool:
	var moved: bool = model.move(direction)
	if moved:
		var move_data: Dictionary = {
			"direction": direction,
			"moved_lines": []
		}
		EventBus.move_made.emit(move_data)
		_check_game_over()
	return moved


## 根据 spawn_data 生成方块（由 RuleManager 调用）。
## @param spawn_data: 包含生成信息的字典。
func spawn_tile(spawn_data: Dictionary) -> void:
	var value: int = spawn_data.get("value", 2)
	var type: Tile.TileType = spawn_data.get("type", Tile.TileType.PLAYER)
	var is_priority: bool = spawn_data.get("is_priority", false)
	var spawn_pos: Vector2i

	if spawn_data.has("position"):
		spawn_pos = spawn_data["position"]
	else:
		var empty_cells: Array[Vector2i] = model.get_empty_cells()
		if not empty_cells.is_empty():
			spawn_pos = empty_cells[RNGManager.get_rng().randi_range(0, empty_cells.size() - 1)]
		else:
			if is_priority:
				_handle_priority_spawn(value, type)
			return

	var new_tile: Tile = _create_visual_tile(value, type)
	model.place_tile(new_tile, spawn_pos)
	new_tile.position = _grid_to_pixel_center(spawn_pos)
	var instruction: Array = [{"type": "SPAWN", "tile": new_tile}]
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
		push_error("Spawn position is out of bounds.")
		return

	if model.grid[grid_pos.x][grid_pos.y] != null:
		model.grid[grid_pos.x][grid_pos.y].queue_free()
		model.grid[grid_pos.x][grid_pos.y] = null

	var new_tile: Tile = _create_visual_tile(value, type)
	model.place_tile(new_tile, grid_pos)
	new_tile.position = _grid_to_pixel_center(grid_pos)
	var instruction: Array = [{"type": "SPAWN", "tile": new_tile}]
	play_animations_requested.emit(instruction)


## 游戏中扩建棋盘。
## @param new_size: 新的棋盘尺寸。
func live_expand(new_size: int) -> void:
	if not model:
		return
	var old_size: int = model.grid_size
	model.expand_grid(new_size)
	_animate_expansion(old_size, new_size)
	EventBus.board_resized.emit(new_size)


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
	for child in board_container.get_children():
		if child is Tile:
			child.queue_free()

	if not model:
		return

	var grid_size: int = snapshot.get("grid_size", 4)
	var interaction_rule: InteractionRule = model.interaction_rule
	var movement_rule: MovementRule = model.movement_rule
	model.initialize(grid_size, interaction_rule, movement_rule)

	var tiles_data: Array = snapshot.get("tiles", [])
	for tile_data in tiles_data:
		var pos: Vector2i = tile_data["pos"]
		var value: int = tile_data["value"]
		var type: Tile.TileType = tile_data["type"]

		var new_tile: Tile = _create_visual_tile(value, type)
		new_tile.position = _grid_to_pixel_center(pos)
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0

		model.place_tile(new_tile, pos)


# --- 私有/辅助方法 ---

func _create_visual_tile(value: int, type: Tile.TileType) -> Tile:
	var new_tile := TileScene.instantiate() as Tile
	board_container.add_child(new_tile)
	new_tile.setup(value, type, model.interaction_rule, color_schemes)
	return new_tile


func _handle_priority_spawn(value: int, type: Tile.TileType) -> void:
	var player_tiles: Array[Tile] = []
	for x in model.grid_size:
		for y in model.grid_size:
			var tile = model.grid[x][y]
			if tile and tile.get("type") == 0:
				player_tiles.append(tile)

	if not player_tiles.is_empty():
		var tile_to_transform: Tile = player_tiles[RNGManager.get_rng().randi_range(0, player_tiles.size() - 1)]
		tile_to_transform.setup(value, type, model._interaction_rule, color_schemes)
		tile_to_transform.animate_transform()
	else:
		var monster_tiles: Array[Tile] = []
		for x in model.grid_size:
			for y in model.grid_size:
				var tile = model.grid[x][y]
				if tile and tile.get("type") == 1:
					monster_tiles.append(tile)
		if not monster_tiles.is_empty():
			var tile_to_empower: Tile = monster_tiles[RNGManager.get_rng().randi_range(0, monster_tiles.size() - 1)]
			tile_to_empower.setup(tile_to_empower.value * 2, type, model._interaction_rule, color_schemes)


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
		push_error("GameBoard: 未配置 grid_cell_scene！")
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


## 检查游戏是否结束，委托给 game_over_rule。
func _check_game_over() -> void:
	if not model or not game_over_rule:
		return
	if game_over_rule.is_game_over(model, model.interaction_rule):
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
		if instr.has("to_grid_pos"):
			instr["to_pos"] = _grid_to_pixel_center(instr["to_grid_pos"])

	play_animations_requested.emit(instructions)


func _on_model_tile_spawned(_tile: Node) -> void:
	pass


func _on_model_score_updated(amount: int) -> void:
	EventBus.score_updated.emit(amount)


# --- 信号处理函数 ---

## 当棋盘尺寸改变时，更新布局。
func _on_resized() -> void:
	_update_board_layout()
