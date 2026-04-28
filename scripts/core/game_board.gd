# scripts/core/game_board.gd

## GameBoard: 负责游戏棋盘的视觉呈现和输入转发。
##
## 它持有 GridModel (逻辑核心)，并根据 Model 的信号更新 Tile 节点的位置和状态。
## 它是 Model 的 View。
class_name GameBoard
extends GFController





# --- 常量 ---

## 预加载方块场景，用于在运行时动态实例化。
const TileScene: PackedScene = preload("res://scenes/components/tile.tscn")

## 每个单元格的像素尺寸。
const CELL_SIZE: int = 100

## 单元格之间的间距。
const SPACING: int = 15

## 棋盘背景的内边距。
const BOARD_PADDING: int = 15

## 用于让旧动画回调识别节点是否已被复用。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"


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
var pool: GFObjectPoolUtility

## 标记是否已完成清理。
var _is_cleaned_up: bool = false

## 棋盘扩展动画版本号，用于丢弃旧 Tween 的延迟回调。
var _expansion_token: int = 0


# --- @onready 变量 (节点引用) ---

@onready var board_background: Panel = %BoardBackground
@onready var board_container: Node2D = %BoardContainer


# --- Godot 生命周期方法 ---

func _ready() -> void:
	model = get_model(GridModel) as GridModel
	_log = get_utility(GFLogUtility) as GFLogUtility
	pool = get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
	
	var parent_control := get_parent() as Control
	if is_instance_valid(parent_control):
		parent_control.resized.connect(_on_resized)
	
	# --- 注册 GF 事件监听 ---
	register_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, _on_board_animation_requested)
	register_simple_event(EventNames.BOARD_UNDO_ANIMATION_REQUESTED, _on_board_undo_animation_requested)
	register_simple_event(EventNames.BOARD_REFRESH_REQUESTED, _on_board_refresh_requested)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	register_simple_event(EventNames.BOARD_LIVE_EXPAND_REQUESTED, _on_board_live_expand_requested)


func _exit_tree() -> void:
	_cleanup_listeners()
	super._exit_tree()


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
	for child in board_container.get_children():
		if child is Tile:
			old_tile_count += 1
			_release_visual_tile(child as Tile)
	
	if _log:
		_log.info("GameBoard", "setup() - Cleaned %d old tiles, _visual_map had %d entries" % [old_tile_count, _visual_map.size()])
	
	_visual_map.clear()
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme

	model.initialize(p_grid_size, p_interaction_rule, p_movement_rule)

	call_deferred(&"_update_board_layout")
	_draw_board_cells()
	
	if is_instance_valid(pool):
		var required_tile_count: int = model.grid_size * model.grid_size
		var available_tile_count: int = pool.get_available_count(TileScene)
		var missing_tile_count: int = max(required_tile_count - available_tile_count, 0)
		if missing_tile_count > 0:
			pool.prewarm(TileScene, board_container, missing_tile_count)

		for child in board_container.get_children():
			if child is Tile:
				child.visible = false
		
	_is_initialized = true


## 清理所有视觉方块节点并重置映射表，通常在撤回动画启动前调用。
func clear_visual_tiles() -> void:
	for child in board_container.get_children():
		if child is Tile:
			_release_visual_tile(child as Tile)
	
	_visual_map.clear()
	if _log:
		_log.info("GameBoard", "clear_visual_tiles: Visual tiles released and map cleared.")


## 供棋盘动画 Action 归还已离场的视觉方块，避免 Action 直接依赖对象池实现细节。
func release_visual_tile(tile: Tile) -> void:
	_release_visual_tile(tile)





## 获取当前棋盘上数值最大的玩家方块的值。
## @return: 最大的玩家方块数值。
func get_max_player_value() -> int:
	if not model:
		return 0
	return model.get_max_player_value()





## 游戏中扩建棋盘。
## @param new_size: 新的棋盘尺寸。
func live_expand(new_size: int) -> void:
	if not model:
		return
	var old_size: int = model.grid_size
	if new_size <= old_size:
		return

	model.expand_grid(new_size)
	_animate_expansion(old_size, new_size)
	send_simple_event(EventNames.BOARD_RESIZED, new_size)


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
	_restore_from_snapshot(snapshot, {})


## 从快照恢复，并从撤回前的位置播放非阻塞过渡。
## @param snapshot: 包含棋盘状态的字典。
## @param reverse_target_map: 原始位置到撤回前位置的映射。
func restore_from_snapshot_with_reverse_animation(snapshot: Dictionary, reverse_target_map: Dictionary) -> void:
	_restore_from_snapshot(snapshot, reverse_target_map)


# --- 私有/辅助方法 ---

func _restore_from_snapshot(snapshot: Dictionary, reverse_target_map: Dictionary) -> void:
	var current_tiles: Array[Tile] = []
	for child in board_container.get_children():
		if child is Tile:
			current_tiles.append(child as Tile)

	if reverse_target_map.is_empty():
		for tile in current_tiles:
			_release_visual_tile(tile)
	else:
		var reverse_start_tiles := _build_reverse_start_tiles_map(snapshot, reverse_target_map)
		for tile in current_tiles:
			if _should_animate_undo_despawn(tile, reverse_start_tiles):
				_animate_release_visual_tile(tile)
			else:
				_release_visual_tile(tile)

	_visual_map.clear()

	if not model:
		return

	var grid_size: int = snapshot.get(&"grid_size", snapshot.get("grid_size", 4))
	var interaction_rule: InteractionRule = model.interaction_rule
	var movement_rule: MovementRule = model.movement_rule
	model.initialize(grid_size, interaction_rule, movement_rule)

	var tiles_data: Array = snapshot.get(&"tiles", snapshot.get("tiles", []))
	for tile_data_snapshot in tiles_data:
		var pos: Vector2i = tile_data_snapshot.get(&"pos", tile_data_snapshot.get("pos", Vector2i.ZERO))
		var value: int = tile_data_snapshot.get(&"value", tile_data_snapshot.get("value", 0))
		var type: Tile.TileType = tile_data_snapshot.get(&"type", tile_data_snapshot.get("type", Tile.TileType.PLAYER))

		var new_tile: Tile = _create_visual_tile(value, type)
		var tile_data := GameTileData.new(value, type)
		_visual_map[tile_data] = new_tile
		
		var key := "%d,%d" % [pos.x, pos.y]
		var start_grid_pos: Vector2i = reverse_target_map.get(key, pos)
		new_tile.position = _grid_to_pixel_center(start_grid_pos)
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0

		model.place_tile(tile_data, pos)

		if start_grid_pos != pos:
			new_tile.animate_move(_grid_to_pixel_center(pos))


func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	unregister_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, _on_board_animation_requested)
	unregister_simple_event(EventNames.BOARD_UNDO_ANIMATION_REQUESTED, _on_board_undo_animation_requested)
	unregister_simple_event(EventNames.BOARD_REFRESH_REQUESTED, _on_board_refresh_requested)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	unregister_simple_event(EventNames.BOARD_LIVE_EXPAND_REQUESTED, _on_board_live_expand_requested)
	if _log:
		_log.info("GameBoard", "_cleanup_listeners: cleaned up GF listeners")


func _create_visual_tile(value: int, type: Tile.TileType) -> Tile:
	var new_tile: Tile
	if pool:
		new_tile = pool.acquire(TileScene, board_container) as Tile
		new_tile.visible = true
	else:
		new_tile = TileScene.instantiate() as Tile
		board_container.add_child(new_tile)
	
	new_tile.reset_animation_state()
	new_tile.set_meta(RELEASE_TOKEN_META, 0)
	var colors := _get_tile_colors(value, type)
	new_tile.setup(value, type, colors.bg, colors.font)
	return new_tile


func _release_visual_tile(tile: Tile) -> void:
	if not is_instance_valid(tile):
		return

	tile.reset_animation_state()
	tile.set_meta(RELEASE_TOKEN_META, 0)
	if pool:
		pool.release(tile, TileScene)
		tile.visible = false
	else:
		tile.queue_free()


func _animate_release_visual_tile(tile: Tile) -> void:
	if not is_instance_valid(tile):
		return

	var release_token := RefCounted.new()
	tile.set_meta(RELEASE_TOKEN_META, release_token)
	tile.move_to_front()

	var despawn_tween: Tween = tile.animate_despawn()
	if is_instance_valid(despawn_tween) and despawn_tween.is_valid():
		despawn_tween.finished.connect(func(): _release_visual_tile_if_valid(tile, release_token))
	else:
		_release_visual_tile_if_valid(tile, release_token)


func _release_visual_tile_if_valid(tile: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(tile):
		return
	if tile.get_meta(RELEASE_TOKEN_META, null) != release_token:
		return

	_release_visual_tile(tile)


func _build_reverse_start_tiles_map(snapshot: Dictionary, reverse_target_map: Dictionary) -> Dictionary:
	var reverse_start_tiles: Dictionary = {}
	var tiles_data: Array = snapshot.get(&"tiles", snapshot.get("tiles", []))

	for tile_data_snapshot in tiles_data:
		var pos: Vector2i = tile_data_snapshot.get(&"pos", tile_data_snapshot.get("pos", Vector2i.ZERO))
		var value: int = tile_data_snapshot.get(&"value", tile_data_snapshot.get("value", 0))
		var type: Tile.TileType = tile_data_snapshot.get(&"type", tile_data_snapshot.get("type", Tile.TileType.PLAYER))
		var pos_key := "%d,%d" % [pos.x, pos.y]
		var start_grid_pos: Vector2i = reverse_target_map.get(pos_key, pos)
		var start_key := "%d,%d" % [start_grid_pos.x, start_grid_pos.y]

		if not reverse_start_tiles.has(start_key):
			reverse_start_tiles[start_key] = []

		reverse_start_tiles[start_key].append({
			&"value": value,
			&"type": type,
		})

	return reverse_start_tiles


func _should_animate_undo_despawn(tile: Tile, reverse_start_tiles: Dictionary) -> bool:
	if not is_instance_valid(tile):
		return false

	var current_grid_pos: Vector2i = _pixel_center_to_grid(tile.position)
	var current_key := "%d,%d" % [current_grid_pos.x, current_grid_pos.y]
	var candidates: Array = reverse_start_tiles.get(current_key, [])

	if candidates.size() != 1:
		return true

	var candidate: Dictionary = candidates[0]
	return (
		candidate.get(&"value", 0) != tile.value
		or candidate.get(&"type", Tile.TileType.PLAYER) != tile.type
	)


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
	_expansion_token += 1
	var expansion_token: int = _expansion_token
	var final_layout: Dictionary = _calculate_layout_params(new_size)
	if final_layout.is_empty(): return
	var main_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	main_tween.tween_property(board_background, "position", final_layout.offset, 0.3)
	main_tween.tween_property(board_background, "size", final_layout.scaled_size, 0.3)
	var final_container_pos: Vector2 = final_layout.offset + Vector2(BOARD_PADDING, BOARD_PADDING) * final_layout.scale_ratio
	main_tween.tween_property(board_container, "position", final_container_pos, 0.3)
	main_tween.tween_property(board_container, "scale", Vector2.ONE * final_layout.scale_ratio, 0.3)
	main_tween.finished.connect(func(): _draw_expanded_cells(old_size, new_size, expansion_token), CONNECT_ONE_SHOT)


func _draw_expanded_cells(old_size: int, new_size: int, expansion_token: int) -> void:
	if expansion_token != _expansion_token:
		return

	# 清理旧格子 (非 Tile 节点)
	for child in board_container.get_children():
		if child is Control and not child is Tile:
			child.queue_free()

	if not is_instance_valid(grid_cell_scene): return

	var new_cells_tween := create_tween().set_parallel(true)

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


## 将网格坐标转换为棋盘容器内的局部像素中心点坐标。
## @return: 对应于网格中心的像素坐标 (Vector2)。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos := Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))
	return top_left_pos + Vector2.ONE * (CELL_SIZE / 2.0)


func _pixel_center_to_grid(pixel_pos: Vector2) -> Vector2i:
	var step: float = CELL_SIZE + SPACING
	return Vector2i(
		roundi((pixel_pos.x - CELL_SIZE / 2.0) / step),
		roundi((pixel_pos.y - CELL_SIZE / 2.0) / step)
	)


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


# --- 信号处理函数 ---

## 接收撤回动画请求，播放平滑动画。
func _on_board_undo_animation_requested(payload: Array) -> void:
	if payload.size() < 2: return
	var snapshot: Dictionary = payload[0]
	var reverse_map: Dictionary = payload[1]
	
	if _log: _log.info("GameBoard", "_on_board_undo_animation_requested: starting reverse animation.")
	
	var undo_action := BoardUndoAnimationAction.new(snapshot, reverse_map, self)
	var action_sys := get_system(GFActionQueueSystem) as GFActionQueueSystem
	if action_sys:
		action_sys.enqueue(undo_action)
	else:
		undo_action.execute()

## 接收到逻辑层的动画请求，将其包装为 Action 推入动画队列。
func _on_board_animation_requested(instructions: Array) -> void:
	var visual_instructions: Array = []
	var needs_visual_resync: bool = false
	if _log: _log.info("GameBoard", "_on_board_animation_requested: %d instructions, _visual_map.size=%d" % [instructions.size(), _visual_map.size()])
	
	for instr in instructions:
		var visual_instr: Dictionary = instr.duplicate()
		
		# 转换逻辑数据到视觉节点
		match instr[&"type"]:
			&"MOVE":
				var move_data: GameTileData = instr[&"tile_data"]
				var move_tile_node: Tile = _visual_map.get(move_data)
				if is_instance_valid(move_tile_node):
					visual_instr[&"tile"] = move_tile_node
				else:
					needs_visual_resync = true
					continue
			&"MERGE":
				var consumed_data: GameTileData = instr[&"consumed_data"]
				var merged_data: GameTileData = instr[&"merged_data"]
				
				var consumed_node: Tile = _visual_map.get(consumed_data)
				var merged_node: Tile = _visual_map.get(merged_data)
				
				if not is_instance_valid(consumed_node):
					needs_visual_resync = true
					continue
				if not is_instance_valid(merged_node):
					needs_visual_resync = true
					continue
				
				visual_instr[&"consumed_tile"] = consumed_node
				visual_instr[&"merged_tile"] = merged_node
				
				# 延迟更新合并后的视觉状态
				if is_instance_valid(merged_node):
					var merge_colors := _get_tile_colors(merged_data.value, merged_data.type)
					visual_instr[&"target_setup_data"] = {
						&"value": merged_data.value,
						&"type": merged_data.type,
						&"bg": merge_colors.bg,
						&"font": merge_colors.font,
						&"do_transform": instr.has(&"transform")
					}
						
				# 从映射中移除被消耗的节点
				if consumed_data != null:
					_visual_map.erase(consumed_data)
			&"SPAWN":
				var spawn_data: GameTileData = instr[&"tile_data"]
				var new_tile: Tile = _create_visual_tile(spawn_data.value, spawn_data.type)
				_visual_map[spawn_data] = new_tile
				new_tile.position = _grid_to_pixel_center(instr[&"to_grid_pos"])
				new_tile.scale = Vector2.ZERO
				
				visual_instr[&"tile"] = new_tile
			&"TRANSFORM":
				var transform_data: GameTileData = instr[&"tile_data"]
				var transform_tile_node: Tile = _visual_map.get(transform_data)
				if not is_instance_valid(transform_tile_node):
					needs_visual_resync = true
					continue

				var transform_colors := _get_tile_colors(transform_data.value, transform_data.type)
				visual_instr[&"tile"] = transform_tile_node
				visual_instr[&"target_setup_data"] = {
					&"value": transform_data.value,
					&"type": transform_data.type,
					&"bg": transform_colors.bg,
					&"font": transform_colors.font,
					&"do_merge": instr.get(&"do_merge", false),
					&"do_transform": instr.get(&"do_transform", false),
				}
		
		# 计算像素坐标
		if visual_instr.has(&"to_grid_pos"):
			visual_instr[&"to_pos"] = _grid_to_pixel_center(visual_instr[&"to_grid_pos"])
			
		visual_instructions.append(visual_instr)

	if needs_visual_resync and model:
		if _log: _log.debug("GameBoard", "Visual map missed an animation target; resyncing from model snapshot.")
		call_deferred(&"restore_from_snapshot", model.get_snapshot())

	if visual_instructions.is_empty():
		return
			
	# 2. 实例化视觉动作
	var action := BoardAnimationAction.new(visual_instructions, self) as GFVisualAction
	
	# 3. 推入 GFActionQueueSystem 执行
	var queue_sys := get_system(GFActionQueueSystem) as GFActionQueueSystem
	if queue_sys:
		queue_sys.enqueue(action)


## 接收到全量刷新请求（如撤回操作），直接重置棋盘视觉状态。
func _on_board_refresh_requested(grid_snapshot: Dictionary) -> void:
	restore_from_snapshot(grid_snapshot)


## 接收到棋盘动态扩建请求。
func _on_board_live_expand_requested(new_size: int) -> void:
	live_expand(new_size)


## 当场景即将改变时调用，确保释放旧场景前断开监听
func _on_scene_will_change(_payload: Variant = null) -> void:
	_cleanup_listeners()


## 当棋盘尺寸改变时，更新布局。
func _on_resized() -> void:
	_update_board_layout()
