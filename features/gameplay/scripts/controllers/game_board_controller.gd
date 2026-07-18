## GameBoardController: 负责游戏棋盘的视觉呈现和输入转发。
##
## 它持有 GridModel (逻辑核心)，并根据 Model 的信号更新 Tile 节点的位置和状态。
## 它是棋盘模型的表现层控制器。
class_name GameBoardController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 信号 ---

## 棋盘局部世界包围盒改变后发出，由外层世界视口负责重新聚焦或约束相机。
signal board_geometry_changed(board_rect: Rect2)




# --- 常量 ---

## 预加载方块场景，用于在运行时动态实例化。
const TileScene: PackedScene = preload("res://features/gameplay/scenes/components/tile.tscn")
const _GAME_BOARD_FEEDBACK_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_board_feedback_utility.gd")
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")

## 每个单元格的像素尺寸。
const CELL_SIZE: int = 100

## 单元格之间的间距。
const SPACING: int = 15

## 棋盘背景的内边距。
const BOARD_PADDING: int = 15

## 用于让旧动画回调识别节点是否已被复用。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"

const _LOG_TAG: String = "GameBoardController"
const _BOARD_INTRO_DURATION: float = 0.22
const _CULL_MARGIN_CELLS: int = 2
const _MIN_PROJECTED_CELL_DETAIL_SIZE: float = 12.0
const _MAX_VISIBLE_NODE_COUNT: int = 12288


# --- 导出变量 ---

## 用于生成棋盘背景格子的场景文件。
@export var grid_cell_scene: PackedScene = preload("res://features/gameplay/scenes/components/board_grid_cell.tscn")


# --- 公共变量 ---

## 逻辑模型引用。
var model: GridModel

## 外部注入的配色方案字典。
var color_schemes: Dictionary

## 外部注入的棋盘与背景主题。
var board_theme: BoardTheme


# --- 私有变量 ---

## 逻辑数据到视觉节点的映射字典 { TileState: Tile }
var _visual_map: Dictionary = {}

## 当前可见背景格映射 { Vector2i: Control }。
var _grid_cell_map: Dictionary = {}

## 外层世界视口换算后的棋盘局部可见矩形。
var _visible_world_rect: Rect2 = Rect2()

var _has_visible_world_rect: bool = false
var _world_view_scale: float = 1.0
var _logical_board_size: Vector2 = Vector2.ZERO
var _is_rebuilding_visuals: bool = false

var _log: GFLogUtility
var _pool: GFObjectPoolUtility
var _action_queue: GFActionQueueSystem

## 标记是否已完成清理。
var _is_cleaned_up: bool = false

## 棋盘扩展动画版本号，用于丢弃旧 Tween 的延迟回调。
var _expansion_token: int = 0

var _board_intro_tween: Tween


# --- @onready 变量 (节点引用) ---

@onready var board_background: Panel = %BoardBackground
@onready var board_container: Node2D = %BoardContainer


# --- Godot 生命周期方法 ---

func _ready() -> void:
	model = _get_grid_model()
	_log = _get_log_utility()
	_pool = _get_object_pool_utility()
	_action_queue = _get_action_queue_system()
	if not _has_required_dependencies():
		return
	
	# --- 注册 GF 事件监听 ---
	register_simple_event(EventNames.BOARD_ANIMATION_REQUESTED, GFEventListener.from_method(self, &"_on_board_animation_requested", 1))
	register_simple_event(EventNames.BOARD_UNDO_ANIMATION_REQUESTED, GFEventListener.from_method(self, &"_on_board_undo_animation_requested", 1))
	register_simple_event(EventNames.BOARD_REFRESH_REQUESTED, GFEventListener.from_method(self, &"_on_board_refresh_requested", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))
	register_simple_event(EventNames.BOARD_LIVE_EXPAND_REQUESTED, GFEventListener.from_method(self, &"_on_board_live_expand_requested", 1))


func _exit_tree() -> void:
	_cleanup_listeners()
	super._exit_tree()


# --- 公共方法 ---

## 设置并同步棋盘视觉。
## @param p_color_schemes: 配色方案字典。
## @param p_board_theme: 棋盘主题。
func setup(
	p_color_schemes: Dictionary,
	p_board_theme: BoardTheme
) -> void:
	# 清理上一局遗留的方块节点和映射，防止幽灵方块
	var old_tile_count: int = 0
	for child: Node in board_container.get_children():
		if child is Tile:
			var old_tile: Tile = child
			old_tile_count += 1
			_release_visual_tile(old_tile)
	
	if _log:
		_log.debug(
			_LOG_TAG,
			"初始化棋盘前已回收旧方块: tiles=%d, visual_map=%d" % [old_tile_count, _visual_map.size()]
		)
	
	_visual_map.clear()
	_clear_grid_cells()
	self.color_schemes = p_color_schemes
	self.board_theme = p_board_theme

	# GridModel 的逻辑初始化由 GameInitSystem 完成，表现层只建立局部世界几何与可见节点。
	_update_board_layout()
	_sync_visible_region()
	call_deferred(&"_play_board_intro")
	
	if is_instance_valid(_pool):
		var required_tile_count: int = mini(_get_visible_cells().size(), 128)
		var available_tile_count: int = _pool.get_available_count(TileScene)
		var missing_tile_count: int = max(required_tile_count - available_tile_count, 0)
		if missing_tile_count > 0:
			_pool.prewarm(TileScene, board_container, missing_tile_count)

		for child: Node in board_container.get_children():
			if child is Tile:
				var tile_child: Tile = child
				tile_child.visible = false


## 返回棋盘在自身局部世界中的完整包围盒。
func get_board_world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _logical_board_size)


## 更新外层视口当前可见的棋盘局部矩形，并窗口化背景格与方块节点。
## @param visible_world_rect: 棋盘自身局部坐标中的可见矩形。
## @param world_view_scale: 棋盘局部单位到屏幕像素的当前缩放。
func set_visible_world_rect(
	visible_world_rect: Rect2,
	world_view_scale: float
) -> void:
	_visible_world_rect = visible_world_rect
	_world_view_scale = maxf(world_view_scale, 0.0001)
	_has_visible_world_rect = true
	_sync_visible_region()


## 在动画或模型事务结束后按当前可见区域重建窗口化节点集。
func sync_visible_region() -> void:
	_sync_visible_region()


## 清理所有视觉方块节点并重置映射表，通常在撤回动画启动前调用。
func clear_visual_tiles() -> void:
	for child: Node in board_container.get_children():
		if child is Tile:
			var tile_child: Tile = child
			_release_visual_tile(tile_child)
	
	_visual_map.clear()
	if _log:
		_log.debug(_LOG_TAG, "已回收所有视觉方块并清空映射。")


## 供棋盘动画 Action 归还已离场的视觉方块，避免 Action 直接依赖对象池实现细节。
## @param tile: 要释放或回收到对象池的视觉方块节点。
func release_visual_tile(tile: Tile) -> void:
	_release_visual_tile(tile)


## 在指定方块位置播放棋盘反馈特效。
## @param tile: 作为反馈定位来源的视觉方块。
## @param feedback_type: 反馈类型，如 merge、spawn、transform。
## @param label_text: 可选浮动文字。
func play_tile_feedback(tile: Tile, feedback_type: StringName, label_text: String = "") -> void:
	if not is_instance_valid(tile) or not is_instance_valid(board_container):
		return

	var feedback_utility: GameBoardFeedbackUtility = _get_board_feedback_utility()
	if is_instance_valid(feedback_utility):
		var _feedback_count: int = feedback_utility.play_feedback(board_container, tile.position, feedback_type, label_text)

	_play_tile_feedback_sound(feedback_type)


## 获取当前棋盘上的最高方块值。
## @return: 最大方块数值。
func get_max_tile_value() -> int:
	if not model:
		return 0
	return model.get_max_tile_value()


## 游戏中扩建棋盘。
## @param new_size: 新的棋盘尺寸。
func live_expand(new_size: int) -> void:
	if not model or not is_instance_valid(model.topology) or not model.topology.is_rectangle():
		return
	var bounds_size: Vector2i = model.get_bounds_size()
	if bounds_size.x != bounds_size.y:
		return
	var old_size: int = bounds_size.x
	if new_size <= old_size:
		return

	var next_topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(new_size, new_size))
	if not model.replace_topology(next_topology):
		return
	_animate_expansion(old_size, new_size)
	send_simple_event(EventNames.BOARD_RESIZED, new_size)


## 遍历整个网格，返回所有空格子坐标的数组。
## @return: 一个包含所有空单元格 Vector2i 坐标的数组。
func get_empty_cells() -> Array[Vector2i]:
	if not model:
		return []
	return model.get_empty_cells()


## 遍历整个网格，返回所有方块数值的数组。
## @return: 一个已排序的方块数值数组。
func get_all_tile_values() -> Array[int]:
	if not model:
		return []
	return model.get_all_tile_values()


## 获取当前棋盘所有方块状态的可序列化快照。
## @return: 一个字典，包含严格拓扑和所有方块数据。
func get_state_snapshot() -> Dictionary:
	if not model:
		return {
			&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
			&"topology": BoardTopology.create_rectangle(Vector2i(4, 4)).to_dict(),
			&"tiles": [],
		}
	return model.get_snapshot()


## 从快照恢复。
## @param snapshot: 包含棋盘状态的字典。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	var _restore_tweens: Array[Tween] = _restore_from_snapshot(snapshot, {})


## 从快照恢复，并从撤回前的位置播放非阻塞过渡。
## @param snapshot: 包含棋盘状态的字典。
## @param reverse_target_map: 原始位置到撤回前位置的映射。
## @return: 本次恢复启动的全部 Tween，由 GF ActionQueue 跟踪完成状态。
func restore_from_snapshot_with_reverse_animation(
	snapshot: Dictionary,
	reverse_target_map: Dictionary
) -> Array[Tween]:
	return _restore_from_snapshot(snapshot, reverse_target_map)


# --- 私有/辅助方法 ---

func _restore_from_snapshot(snapshot: Dictionary, reverse_target_map: Dictionary) -> Array[Tween]:
	_is_rebuilding_visuals = true
	var animation_tweens: Array[Tween] = []
	var current_tiles: Array[Tile] = []
	for child: Node in board_container.get_children():
		if child is Tile:
			var tile_child: Tile = child
			current_tiles.append(tile_child)

	if reverse_target_map.is_empty():
		for tile: Tile in current_tiles:
			_release_visual_tile(tile)
	else:
		var reverse_start_tiles: Dictionary = _build_reverse_start_tiles_map(snapshot, reverse_target_map)
		for tile: Tile in current_tiles:
			if _should_animate_undo_despawn(tile, reverse_start_tiles):
				var despawn_tween: Tween = _animate_release_visual_tile(tile)
				if is_instance_valid(despawn_tween) and despawn_tween.is_valid():
					animation_tweens.append(despawn_tween)
			else:
				_release_visual_tile(tile)

	_visual_map.clear()

	if not model:
		_is_rebuilding_visuals = false
		return animation_tweens
	_update_board_layout()
	var visible_cells: Array[Vector2i] = _get_visible_cells()
	_sync_grid_cells(visible_cells)
	var visible_cell_lookup: Dictionary = {}
	for visible_cell: Vector2i in visible_cells:
		visible_cell_lookup[visible_cell] = true

	var tiles_data: Array = GFVariantData.to_array(snapshot.get(&"tiles", snapshot.get("tiles", [])))
	for raw_tile_data_snapshot: Variant in tiles_data:
		if not raw_tile_data_snapshot is Dictionary:
			continue
		var tile_data_snapshot: Dictionary = raw_tile_data_snapshot
		var pos: Vector2i = _get_vector2i(tile_data_snapshot, &"pos", Vector2i.ZERO)
		if not model.is_active_cell(pos):
			continue
		var key: String = "%d,%d" % [pos.x, pos.y]
		var start_grid_pos: Vector2i = _get_vector2i(reverse_target_map, StringName(key), pos)
		if not visible_cell_lookup.has(pos) and not visible_cell_lookup.has(start_grid_pos):
			continue

		var tile_data: TileState = _get_model_tile_data(pos)
		if tile_data == null:
			if _log:
				_log.error(_LOG_TAG, "模型缺少快照位置 %s 对应的 TileState。" % pos)
			continue

		var new_tile: Tile = _create_visual_tile(tile_data)
		if not is_instance_valid(new_tile):
			continue
		_visual_map[tile_data] = new_tile
		new_tile.position = _grid_to_pixel_center(start_grid_pos)
		new_tile.scale = Vector2.ONE
		new_tile.rotation_degrees = 0

		if start_grid_pos != pos:
			var move_tween: Tween = new_tile.animate_move(_grid_to_pixel_center(pos))
			if is_instance_valid(move_tween) and move_tween.is_valid():
				animation_tweens.append(move_tween)

	_is_rebuilding_visuals = false
	return animation_tweens


func _cleanup_listeners() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_owner_events(self)
	if _log:
		_log.debug(_LOG_TAG, "已清理 GF 事件监听。")


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_object_pool_utility() -> GFObjectPoolUtility:
	var utility_value: Object = get_utility(GFObjectPoolUtility)
	if utility_value is GFObjectPoolUtility:
		var pool_utility: GFObjectPoolUtility = utility_value
		return pool_utility
	return null


func _get_action_queue_system() -> GFActionQueueSystem:
	var system_value: Object = get_system(GFActionQueueSystem)
	if system_value is GFActionQueueSystem:
		var action_queue: GFActionQueueSystem = system_value
		return action_queue
	return null


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(model):
		var _model_appended: bool = missing.append("GridModel")
	if not is_instance_valid(_pool):
		var _pool_appended: bool = missing.append("GFObjectPoolUtility")
	if not is_instance_valid(_action_queue):
		var _queue_appended: bool = missing.append("GFActionQueueSystem")
	if missing.is_empty():
		return true
	push_error("[GameBoardController] 缺少必需架构依赖：%s。" % ", ".join(missing))
	return false


func _get_board_feedback_utility() -> GameBoardFeedbackUtility:
	var utility_value: Object = get_utility(_GAME_BOARD_FEEDBACK_UTILITY_SCRIPT)
	if utility_value is GameBoardFeedbackUtility:
		var feedback_utility: GameBoardFeedbackUtility = utility_value
		return feedback_utility
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _create_visual_tile(tile_data: TileState) -> Tile:
	if tile_data == null:
		return null
	var new_tile: Tile = _acquire_visual_tile()
	if not is_instance_valid(new_tile):
		push_error("[GameBoardController] 方块场景必须实例化为 Tile。")
		return null
	
	new_tile.reset_animation_state()
	new_tile.set_meta(RELEASE_TOKEN_META, 0)
	var colors: Dictionary = _get_tile_colors(tile_data.value, tile_data.definition_id)
	var presentation: Dictionary = _get_tile_presentation_descriptor(tile_data)
	new_tile.setup(
		tile_data.value,
		tile_data.definition_id,
		_get_color(colors, &"bg", Color.WHITE),
		_get_color(colors, &"font", Color.BLACK),
		GFVariantData.to_string_name(
			GFVariantData.get_option_value(presentation, &"visual_family_id")
		),
		_get_string_name_array(presentation, &"visual_layer_ids")
	)
	return new_tile


func _get_tile_presentation_descriptor(tile_data: TileState) -> Dictionary:
	if tile_data == null or not is_instance_valid(model) or model.interaction_rule == null:
		return {}
	var definition: TileDefinition = model.interaction_rule.get_tile_definition(tile_data.definition_id)
	if definition == null:
		return {}
	return definition.get_presentation_descriptor(tile_data.capability_recipe_ids)


func _acquire_visual_tile() -> Tile:
	if not is_instance_valid(_pool):
		push_error("[GameBoardController] GFObjectPoolUtility 不可用。")
		return null
	var tile_node: Node = _pool.acquire(TileScene, board_container)

	if tile_node is Tile:
		var tile: Tile = tile_node
		tile.visible = true
		return tile

	if is_instance_valid(tile_node):
		tile_node.queue_free()
	return null


func _release_visual_tile(tile: Tile) -> void:
	if not is_instance_valid(tile):
		return

	tile.reset_animation_state()
	tile.set_meta(RELEASE_TOKEN_META, 0)
	if not is_instance_valid(_pool):
		push_error("[GameBoardController] GFObjectPoolUtility 不可用，无法归还 Tile。")
		return
	_pool.release(tile, TileScene)
	tile.visible = false


func _animate_release_visual_tile(tile: Tile) -> Tween:
	if not is_instance_valid(tile):
		return null

	var release_token: RefCounted = RefCounted.new()
	tile.set_meta(RELEASE_TOKEN_META, release_token)
	tile.move_to_front()

	var despawn_tween: Tween = tile.animate_despawn()
	if is_instance_valid(despawn_tween) and despawn_tween.is_valid():
		var _release_connected: int = despawn_tween.finished.connect(
			_release_visual_tile_if_valid.bind(tile, release_token)
		)
		return despawn_tween
	else:
		_release_visual_tile_if_valid(tile, release_token)
	return null


func _release_visual_tile_if_valid(tile: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(tile):
		return
	if not tile.has_meta(RELEASE_TOKEN_META):
		return
	if tile.get_meta(RELEASE_TOKEN_META) != release_token:
		return

	_release_visual_tile(tile)


func _build_reverse_start_tiles_map(snapshot: Dictionary, reverse_target_map: Dictionary) -> Dictionary:
	var reverse_start_tiles: Dictionary = {}
	var tiles_data: Array = GFVariantData.to_array(snapshot.get(&"tiles", snapshot.get("tiles", [])))

	for raw_tile_data_snapshot: Variant in tiles_data:
		if not raw_tile_data_snapshot is Dictionary:
			continue
		var tile_data_snapshot: Dictionary = raw_tile_data_snapshot
		var pos: Vector2i = _get_vector2i(tile_data_snapshot, &"pos", Vector2i.ZERO)
		if not is_instance_valid(model) or not model.is_active_cell(pos):
			continue

		var value: int = _get_int(tile_data_snapshot, &"value", 0)
		var definition_id: StringName = GFVariantData.get_option_string_name(
			tile_data_snapshot,
			&"definition_id"
		)
		var pos_key: String = "%d,%d" % [pos.x, pos.y]
		var start_grid_pos: Vector2i = _get_vector2i(reverse_target_map, StringName(pos_key), pos)
		var start_key: String = "%d,%d" % [start_grid_pos.x, start_grid_pos.y]

		if not reverse_start_tiles.has(start_key):
			reverse_start_tiles[start_key] = []

		var start_tile_entries: Array = GFVariantData.to_array(reverse_start_tiles[start_key])
		start_tile_entries.append({
			&"value": value,
			&"definition_id": definition_id,
		})
		reverse_start_tiles[start_key] = start_tile_entries

	return reverse_start_tiles


func _should_animate_undo_despawn(tile: Tile, reverse_start_tiles: Dictionary) -> bool:
	if not is_instance_valid(tile):
		return false

	var current_grid_pos: Vector2i = _pixel_center_to_grid(tile.position)
	var current_key: String = "%d,%d" % [current_grid_pos.x, current_grid_pos.y]
	var candidates: Array = GFVariantData.to_array(reverse_start_tiles.get(current_key, []))

	if candidates.size() != 1:
		return true

	var candidate: Dictionary = GFVariantData.to_dictionary(candidates[0])
	return (
		candidate.get(&"value", 0) != tile.value
		or GFVariantData.get_option_string_name(candidate, &"definition_id") != tile.definition_id
	)


func _get_model_tile_data(grid_pos: Vector2i) -> TileState:
	if not is_instance_valid(model):
		return null
	return model.get_tile(grid_pos)


func _get_tile_colors(value: int, definition_id: StringName) -> Dictionary:
	var bg_color: Color = Color.WHITE
	var font_color: Color = Color.BLACK
	
	if not model or not model.interaction_rule:
		return {"bg": bg_color, "font": font_color}
		
	var scheme_index: int = model.interaction_rule.get_color_scheme_index(value, definition_id)
		
	var current_scheme: TileColorScheme = _get_tile_color_scheme(scheme_index)
	if is_instance_valid(current_scheme) and not current_scheme.styles.is_empty():
		var level: int = model.interaction_rule.get_level_by_value(value)
		if level >= current_scheme.styles.size():
			level = current_scheme.styles.size() - 1
		var current_style: TileLevelStyle = _get_tile_level_style(current_scheme, level)
		if is_instance_valid(current_style):
			bg_color = current_style.background_color
			font_color = current_style.font_color
			
	return {"bg": bg_color, "font": font_color}


func _get_tile_color_scheme(scheme_index: int) -> TileColorScheme:
	var scheme_value: Variant = color_schemes.get(scheme_index)
	if scheme_value is TileColorScheme:
		var scheme: TileColorScheme = scheme_value
		return scheme
	return null


func _get_tile_level_style(scheme: TileColorScheme, level: int) -> TileLevelStyle:
	if not is_instance_valid(scheme) or level < 0 or level >= scheme.styles.size():
		return null

	return scheme.styles[level]


## 更新棋盘自身的稳定局部世界尺寸；外层视口独占缩放和平移。
func _update_board_layout() -> void:
	if not is_instance_valid(model):
		return
	var board_size: Vector2i = model.get_bounds_size()
	if board_size.x <= 0 or board_size.y <= 0:
		return
	var grid_area_size: Vector2 = Vector2(
		board_size.x * CELL_SIZE + (board_size.x - 1) * SPACING,
		board_size.y * CELL_SIZE + (board_size.y - 1) * SPACING
	)
	_logical_board_size = grid_area_size + Vector2.ONE * BOARD_PADDING * 2.0
	var board_control: Control = _get_host_control()
	if is_instance_valid(board_control):
		board_control.size = _logical_board_size

	if is_instance_valid(board_theme):
		_apply_board_background_style()

	board_background.position = Vector2.ZERO
	board_background.size = _logical_board_size
	board_container.position = Vector2.ONE * BOARD_PADDING
	board_container.scale = Vector2.ONE
	board_geometry_changed.emit(get_board_world_rect())


func _apply_board_background_style() -> void:
	var panel_style: StyleBoxFlat = _duplicate_flat_panel_style(board_background)
	if not is_instance_valid(panel_style):
		return

	panel_style.bg_color = board_theme.board_panel_color
	panel_style.border_color = board_theme.board_border_color
	panel_style.set_border_width_all(6)
	panel_style.set_corner_radius_all(6)
	panel_style.shadow_color = Color.TRANSPARENT
	panel_style.shadow_size = 0
	panel_style.shadow_offset = Vector2.ZERO
	board_background.add_theme_stylebox_override("panel", panel_style)


func _sync_visible_region() -> void:
	if _is_rebuilding_visuals:
		return
	if not is_instance_valid(model) or not is_instance_valid(model.topology):
		return
	var visible_cells: Array[Vector2i] = _get_visible_cells()
	_sync_grid_cells(visible_cells)
	if not is_instance_valid(_action_queue) or not _action_queue.is_processing:
		_sync_visual_tiles(visible_cells)


func _get_visible_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_instance_valid(model) or not is_instance_valid(model.topology):
		return result
	if _world_view_scale * CELL_SIZE < _MIN_PROJECTED_CELL_DETAIL_SIZE:
		return result

	var visible_rect: Rect2 = (
		_visible_world_rect
		if _has_visible_world_rect
		else get_board_world_rect()
	)
	var step: float = CELL_SIZE + SPACING
	var container_rect: Rect2 = Rect2(
		visible_rect.position - board_container.position,
		visible_rect.size
	).grow(step * _CULL_MARGIN_CELLS)
	var query_start: Vector2i = Vector2i(
		floori(container_rect.position.x / step),
		floori(container_rect.position.y / step)
	)
	var query_end: Vector2i = Vector2i(
		ceili(container_rect.end.x / step),
		ceili(container_rect.end.y / step)
	)
	result = model.topology.get_cells_in_rect(
		Rect2i(query_start, query_end - query_start)
	)
	if result.size() > _MAX_VISIBLE_NODE_COUNT:
		result.clear()
	return result


func _sync_grid_cells(visible_cells: Array[Vector2i]) -> void:
	var desired_cells: Dictionary = {}
	for cell: Vector2i in visible_cells:
		desired_cells[cell] = true

	for cell_value: Variant in _grid_cell_map.keys():
		if not cell_value is Vector2i or desired_cells.has(cell_value):
			continue
		var stale_cell: Vector2i = cell_value
		var stale_control: Control = _get_grid_cell_control(stale_cell)
		var _cell_erased: bool = _grid_cell_map.erase(stale_cell)
		_release_grid_cell(stale_control)

	for cell: Vector2i in visible_cells:
		if _grid_cell_map.has(cell):
			continue
		var cell_instance: Control = _acquire_grid_cell()
		if not is_instance_valid(cell_instance):
			continue
		cell_instance.size = Vector2.ONE * CELL_SIZE
		cell_instance.position = Vector2(cell) * (CELL_SIZE + SPACING)
		cell_instance.z_index = -10
		_style_grid_cell(cell_instance)
		_grid_cell_map[cell] = cell_instance


func _sync_visual_tiles(visible_cells: Array[Vector2i]) -> void:
	var desired_tiles: Dictionary = {}
	for cell: Vector2i in visible_cells:
		var tile_data: TileState = model.get_tile(cell)
		if tile_data != null:
			desired_tiles[tile_data] = cell

	for tile_data_value: Variant in _visual_map.keys():
		if desired_tiles.has(tile_data_value):
			continue
		if tile_data_value is TileState:
			var stale_tile_data: TileState = tile_data_value
			var stale_tile: Tile = _get_visual_tile(stale_tile_data)
			var _tile_erased: bool = _visual_map.erase(stale_tile_data)
			_release_visual_tile(stale_tile)

	for tile_data_value: Variant in desired_tiles.keys():
		if not tile_data_value is TileState:
			continue
		var tile_data: TileState = tile_data_value
		if is_instance_valid(_get_visual_tile(tile_data)):
			continue
		var tile: Tile = _create_visual_tile(tile_data)
		if not is_instance_valid(tile):
			continue
		var tile_cell_value: Variant = desired_tiles[tile_data]
		if not tile_cell_value is Vector2i:
			_release_visual_tile(tile)
			continue
		var tile_cell: Vector2i = tile_cell_value
		tile.position = _grid_to_pixel_center(tile_cell)
		_visual_map[tile_data] = tile


func _clear_grid_cells() -> void:
	for cell_value: Variant in _grid_cell_map.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value
		_release_grid_cell(_get_grid_cell_control(cell))
	_grid_cell_map.clear()


## 执行棋盘从旧尺寸到新尺寸的扩建动画。
func _animate_expansion(old_size: int, _new_size: int) -> void:
	_expansion_token += 1
	if _board_intro_tween and _board_intro_tween.is_valid():
		_board_intro_tween.kill()
	_update_board_layout()
	_sync_visible_region()
	var expansion_tween: Tween = create_tween().set_parallel(true)
	var _transition_result: Tween = expansion_tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = expansion_tween.set_ease(Tween.EASE_OUT)
	for cell_value: Variant in _grid_cell_map.keys():
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value
		if cell.x < old_size and cell.y < old_size:
			continue
		var cell_instance: Control = _get_grid_cell_control(cell)
		if not is_instance_valid(cell_instance):
			continue
		cell_instance.pivot_offset = cell_instance.size * 0.5
		cell_instance.scale = Vector2.ONE * 0.72
		var _scale_tweener: PropertyTweener = expansion_tween.tween_property(
			cell_instance,
			"scale",
			Vector2.ONE,
			0.18
		)


func _configure_cell_style(stylebox: StyleBoxFlat) -> void:
	stylebox.bg_color = board_theme.empty_cell_color
	stylebox.border_color = board_theme.empty_cell_border_color
	stylebox.set_border_width_all(3)
	stylebox.set_corner_radius_all(4)
	stylebox.shadow_color = Color.TRANSPARENT
	stylebox.shadow_size = 0
	stylebox.shadow_offset = Vector2.ZERO


func _style_grid_cell(cell_control: Control) -> void:
	if not is_instance_valid(board_theme) or not cell_control is Panel:
		return
	var stylebox: StyleBoxFlat = _duplicate_flat_panel_style(cell_control)
	if is_instance_valid(stylebox):
		_configure_cell_style(stylebox)
		cell_control.add_theme_stylebox_override("panel", stylebox)


func _acquire_grid_cell() -> Control:
	if not is_instance_valid(_pool) or not is_instance_valid(grid_cell_scene):
		return null
	var cell_node: Node = _pool.acquire(grid_cell_scene, board_container)
	if cell_node is Control:
		var cell_control: Control = cell_node
		cell_control.visible = true
		cell_control.scale = Vector2.ONE
		return cell_control

	if is_instance_valid(cell_node):
		push_error("[GameBoardController] 棋盘背景格子场景必须实例化为 Control。")
		_pool.release(cell_node, grid_cell_scene)
	return null


func _release_grid_cell(cell_control: Control) -> void:
	if not is_instance_valid(cell_control):
		return
	cell_control.scale = Vector2.ONE
	if not is_instance_valid(_pool):
		cell_control.queue_free()
		return
	_pool.release(cell_control, grid_cell_scene)


func _get_grid_cell_control(cell: Vector2i) -> Control:
	var cell_value: Variant = _grid_cell_map.get(cell)
	if cell_value is Control:
		var cell_control: Control = cell_value
		return cell_control
	return null


func _get_host_control() -> Control:
	var host_value: Node = get_host_as(Control)
	if host_value is Control:
		var host_control: Control = host_value
		return host_control
	return null


func _duplicate_flat_panel_style(control: Control) -> StyleBoxFlat:
	if not is_instance_valid(control):
		return null

	var stylebox_value: Variant = control.get_theme_stylebox("panel").duplicate()
	if stylebox_value is StyleBoxFlat:
		var flat_stylebox: StyleBoxFlat = stylebox_value
		return flat_stylebox
	return null


func _play_board_intro() -> void:
	if not is_instance_valid(board_background) or not is_instance_valid(board_container):
		return
	if not is_instance_valid(model):
		return
	if _board_intro_tween and _board_intro_tween.is_valid():
		_board_intro_tween.kill()

	board_background.modulate = Color(1.0, 1.0, 1.0, 0.0)
	board_container.modulate = Color(1.0, 1.0, 1.0, 0.0)
	board_container.scale = Vector2.ONE * 0.98

	_board_intro_tween = create_tween().set_parallel(true)
	var _transition_result: Tween = _board_intro_tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = _board_intro_tween.set_ease(Tween.EASE_OUT)
	var _background_fade_tweener: PropertyTweener = _board_intro_tween.tween_property(board_background, "modulate:a", 1.0, _BOARD_INTRO_DURATION)
	var _container_fade_tweener: PropertyTweener = _board_intro_tween.tween_property(board_container, "modulate:a", 1.0, _BOARD_INTRO_DURATION)
	var _container_scale_tweener: PropertyTweener = _board_intro_tween.tween_property(
		board_container,
		"scale",
		Vector2.ONE,
		_BOARD_INTRO_DURATION
	)


## 将网格坐标转换为棋盘容器内的局部像素中心点坐标。
## @return: 对应于网格中心的像素坐标 (Vector2)。
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	var top_left_pos: Vector2 = Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))
	return top_left_pos + Vector2.ONE * (CELL_SIZE / 2.0)


func _pixel_center_to_grid(pixel_pos: Vector2) -> Vector2i:
	var step: float = CELL_SIZE + SPACING
	return Vector2i(
		roundi((pixel_pos.x - CELL_SIZE / 2.0) / step),
		roundi((pixel_pos.y - CELL_SIZE / 2.0) / step)
	)


static func _get_instruction_type(data: Dictionary) -> StringName:
	var value: Variant = data.get(&"type", data.get("type", &""))
	if value is StringName:
		return value
	return StringName(str(value))


static func _get_game_tile_data(data: Dictionary, key: StringName) -> TileState:
	var value: Variant = data.get(key, data.get(String(key), null))
	if value is TileState:
		return value
	return null


func _get_visual_tile(tile_data: TileState) -> Tile:
	if tile_data == null:
		return null
	var value: Variant = _visual_map.get(tile_data, null)
	if value is Tile:
		var tile: Tile = value
		return tile
	return null


static func _get_vector2i(data: Dictionary, key: StringName, default_value: Vector2i) -> Vector2i:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is Vector2i:
		return value
	if value is Vector2:
		var vector_value: Vector2 = value
		return Vector2i(roundi(vector_value.x), roundi(vector_value.y))
	return default_value


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


static func _get_bool(data: Dictionary, key: StringName, default_value: bool) -> bool:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is bool:
		return value
	return default_value


static func _get_string_name_array(data: Dictionary, key: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in GFVariantData.get_option_array(data, key):
		result.append(GFVariantData.to_string_name(value))
	return result


static func _get_color(data: Dictionary, key: StringName, default_value: Color) -> Color:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is Color:
		return value
	return default_value


func _play_tile_feedback_sound(feedback_type: StringName) -> void:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if not is_instance_valid(theme_utility):
		return

	match feedback_type:
		&"spawn":
			theme_utility.play_tile_spawn_sound()
		&"merge":
			theme_utility.play_tile_merge_sound()


func _play_tile_move_sound() -> void:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		theme_utility.play_tile_move_sound()


func _ensure_animation_tile(tile_data: TileState, start_cell: Vector2i) -> Tile:
	if tile_data == null:
		return null
	var existing_tile: Tile = _get_visual_tile(tile_data)
	if is_instance_valid(existing_tile):
		return existing_tile
	var tile: Tile = _create_visual_tile(tile_data)
	if not is_instance_valid(tile):
		return null
	tile.position = _grid_to_pixel_center(start_cell)
	tile.scale = Vector2.ONE
	_visual_map[tile_data] = tile
	return tile


func _release_mapped_visual_tile(tile_data: TileState) -> void:
	if tile_data == null:
		return
	var tile: Tile = _get_visual_tile(tile_data)
	var _erased: bool = _visual_map.erase(tile_data)
	_release_visual_tile(tile)


func _find_tile_cell_in_visible_cells(
	tile_data: TileState,
	visible_cells: Array[Vector2i]
) -> Vector2i:
	if tile_data == null or not is_instance_valid(model):
		return Vector2i(-1, -1)
	for cell: Vector2i in visible_cells:
		if model.get_tile(cell) == tile_data:
			return cell
	return Vector2i(-1, -1)


# --- 信号处理函数 ---

## 接收撤回动画请求，播放平滑动画。
func _on_board_undo_animation_requested(payload: Array) -> void:
	if payload.size() < 2:
		return
	var snapshot: Dictionary = GFVariantData.to_dictionary(payload[0])
	var reverse_map: Dictionary = GFVariantData.to_dictionary(payload[1])
	
	if _log:
		_log.debug(_LOG_TAG, "收到撤回动画请求。")
	
	var undo_action: BoardUndoAnimationAction = BoardUndoAnimationAction.new(snapshot, reverse_map, self)
	if not is_instance_valid(_action_queue):
		push_error("[GameBoardController] GFActionQueueSystem 不可用，撤回动画被拒绝。")
		return
	_action_queue.enqueue(undo_action)

## 接收到逻辑层的动画请求，将其包装为 Action 推入动画队列。
func _on_board_animation_requested(instructions: Array) -> void:
	var visual_instructions: Array[Dictionary] = []
	var needs_visual_resync: bool = false
	var has_move_sound: bool = false
	var visible_cells: Array[Vector2i] = _get_visible_cells()
	var visible_cell_lookup: Dictionary = {}
	for visible_cell: Vector2i in visible_cells:
		visible_cell_lookup[visible_cell] = true
	if _log:
		_log.debug(_LOG_TAG, "收到棋盘动画请求: instructions=%d, visual_map=%d" % [instructions.size(), _visual_map.size()])
	
	for raw_instr: Variant in instructions:
		if not raw_instr is Dictionary:
			needs_visual_resync = true
			continue
		var instr: Dictionary = raw_instr
		var visual_instr: Dictionary = instr.duplicate()
		var instruction_type: StringName = _get_instruction_type(instr)
		
		# 转换逻辑数据到视觉节点
		match instruction_type:
			&"MOVE":
				var move_data: TileState = _get_game_tile_data(instr, &"tile_data")
				if move_data == null:
					needs_visual_resync = true
					continue
				var move_from: Vector2i = _get_vector2i(instr, &"from_grid_pos", Vector2i.ZERO)
				var move_to: Vector2i = _get_vector2i(instr, &"to_grid_pos", move_from)
				if not visible_cell_lookup.has(move_from) and not visible_cell_lookup.has(move_to):
					_release_mapped_visual_tile(move_data)
					continue
				var move_tile_node: Tile = _ensure_animation_tile(move_data, move_from)
				if not is_instance_valid(move_tile_node):
					needs_visual_resync = true
					continue
				visual_instr[&"tile"] = move_tile_node
			&"MERGE":
				var consumed_data: TileState = _get_game_tile_data(instr, &"consumed_data")
				var merged_data: TileState = _get_game_tile_data(instr, &"merged_data")
				if consumed_data == null or merged_data == null:
					needs_visual_resync = true
					continue
				var consumed_from: Vector2i = _get_vector2i(
					instr,
					&"from_grid_pos_consumed",
					Vector2i.ZERO
				)
				var merged_from: Vector2i = _get_vector2i(
					instr,
					&"from_grid_pos_merged",
					Vector2i.ZERO
				)
				var merge_to: Vector2i = _get_vector2i(instr, &"to_grid_pos", merged_from)
				var merge_is_visible: bool = (
					visible_cell_lookup.has(consumed_from)
					or visible_cell_lookup.has(merged_from)
					or visible_cell_lookup.has(merge_to)
				)
				if not merge_is_visible:
					_release_mapped_visual_tile(consumed_data)
					_release_mapped_visual_tile(merged_data)
					continue

				var consumed_node: Tile = _ensure_animation_tile(consumed_data, consumed_from)
				var merged_node: Tile = _ensure_animation_tile(merged_data, merged_from)
				if is_instance_valid(consumed_node):
					visual_instr[&"consumed_tile"] = consumed_node
				if is_instance_valid(merged_node):
					visual_instr[&"merged_tile"] = merged_node
				if not is_instance_valid(consumed_node) and not is_instance_valid(merged_node):
					needs_visual_resync = true
					continue
				
				# 延迟更新合并后的视觉状态
				if is_instance_valid(merged_node):
					var merge_colors: Dictionary = _get_tile_colors(
						merged_data.value,
						merged_data.definition_id
					)
					var merge_presentation: Dictionary = _get_tile_presentation_descriptor(merged_data)
					visual_instr[&"target_setup_data"] = {
						&"value": merged_data.value,
						&"definition_id": merged_data.definition_id,
						&"bg": merge_colors.bg,
						&"font": merge_colors.font,
						&"visual_family_id": GFVariantData.get_option_value(
							merge_presentation,
							&"visual_family_id"
						),
						&"visual_layer_ids": GFVariantData.get_option_array(
							merge_presentation,
							&"visual_layer_ids"
						),
						&"do_transform": instr.has(&"transform")
					}
						
				# 从映射中移除被消耗的节点
				if consumed_data != null:
					var _erase_result: bool = _visual_map.erase(consumed_data)
			&"SPAWN":
				var spawn_data: TileState = _get_game_tile_data(instr, &"tile_data")
				if spawn_data == null:
					needs_visual_resync = true
					continue
				var spawn_cell: Vector2i = _get_vector2i(instr, &"to_grid_pos", Vector2i.ZERO)
				if not visible_cell_lookup.has(spawn_cell):
					continue
				var new_tile: Tile = _create_visual_tile(spawn_data)
				if not is_instance_valid(new_tile):
					needs_visual_resync = true
					continue
				_visual_map[spawn_data] = new_tile
				new_tile.position = _grid_to_pixel_center(spawn_cell)
				new_tile.scale = Vector2.ZERO
				
				visual_instr[&"tile"] = new_tile
			&"TRANSFORM":
				var transform_data: TileState = _get_game_tile_data(instr, &"tile_data")
				var transform_tile_node: Tile = _get_visual_tile(transform_data)
				if not is_instance_valid(transform_tile_node):
					var transform_cell: Vector2i = _find_tile_cell_in_visible_cells(
						transform_data,
						visible_cells
					)
					if transform_cell.x < 0:
						continue
					transform_tile_node = _ensure_animation_tile(transform_data, transform_cell)
					if not is_instance_valid(transform_tile_node):
						needs_visual_resync = true
						continue

				var transform_colors: Dictionary = _get_tile_colors(
					transform_data.value,
					transform_data.definition_id
				)
				var transform_presentation: Dictionary = _get_tile_presentation_descriptor(transform_data)
				visual_instr[&"tile"] = transform_tile_node
				visual_instr[&"target_setup_data"] = {
					&"value": transform_data.value,
					&"definition_id": transform_data.definition_id,
					&"bg": transform_colors.bg,
					&"font": transform_colors.font,
					&"visual_family_id": GFVariantData.get_option_value(
						transform_presentation,
						&"visual_family_id"
					),
					&"visual_layer_ids": GFVariantData.get_option_array(
						transform_presentation,
						&"visual_layer_ids"
					),
					&"do_merge": _get_bool(instr, &"do_merge", false),
					&"do_transform": _get_bool(instr, &"do_transform", false),
				}
		
		# 计算像素坐标
		if visual_instr.has(&"to_grid_pos"):
			visual_instr[&"to_pos"] = _grid_to_pixel_center(_get_vector2i(visual_instr, &"to_grid_pos", Vector2i.ZERO))

		if instruction_type == &"MOVE" or instruction_type == &"MERGE":
			has_move_sound = true
			
		visual_instructions.append(visual_instr)

	if needs_visual_resync and model:
		if _log:
			_log.debug(_LOG_TAG, "视觉映射缺失动画目标，按当前可见区域重同步。")
		call_deferred(&"_sync_visible_region")

	if visual_instructions.is_empty():
		call_deferred(&"_sync_visible_region")
		return

	if has_move_sound:
		_play_tile_move_sound()
			
	# 2. 实例化视觉动作
	var action: BoardAnimationAction = BoardAnimationAction.new(visual_instructions, self)
	
	# 3. 推入 GFActionQueueSystem 执行
	if not is_instance_valid(_action_queue):
		push_error("[GameBoardController] GFActionQueueSystem 不可用，棋盘动画被拒绝。")
		return
	_action_queue.enqueue(action)


## 接收到全量刷新请求（如撤回操作），直接重置棋盘视觉状态。
func _on_board_refresh_requested(board_snapshot: Dictionary) -> void:
	restore_from_snapshot(board_snapshot)


## 接收到棋盘动态扩建请求。
func _on_board_live_expand_requested(new_size: int) -> void:
	live_expand(new_size)


## 当场景即将改变时调用，确保释放旧场景前断开监听
func _on_scene_will_change(_payload: Variant = null) -> void:
	_cleanup_listeners()
