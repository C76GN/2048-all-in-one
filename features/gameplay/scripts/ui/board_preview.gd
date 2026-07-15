## BoardPreview: 用于在UI中静态展示棋盘状态的组件。
##
## 它接收一个棋盘快照（Snapshot）和交互规则，渲染出一个缩小版的棋盘。
## 主要用于存档和回放列表的预览。会自动根据容器大小调整单元格尺寸。
class_name BoardPreview
extends Control

# --- 常量 ---

const TILE_SCENE: PackedScene = preload("res://features/gameplay/scenes/components/tile.tscn")
## 用于生成预览背景格子的场景。
const GRID_CELL_SCENE: PackedScene = preload("res://features/gameplay/scenes/components/board_grid_cell.tscn")
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")
const _GF_AUTOLOAD_SCRIPT = preload("res://addons/gf/kernel/core/gf_autoload.gd")
const GFNodeContextBase = preload("res://addons/gf/kernel/core/gf_node_context.gd")

## 预览区域的最大显示尺寸（像素）。
const MAX_PREVIEW_SIZE: float = 300.0

## 单元格之间的间距比例（相对于单元格大小）。
const SPACING_RATIO: float = 0.1


# --- 私有变量 ---

var _board_container: Control
var _background_panel: Panel
var _message_label: Label
var _theme_utility: GameThemeUtility


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_background_panel = Panel.new()
	_background_panel.name = "BackgroundPanel"
	_background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_panel)

	_board_container = Control.new()
	_board_container.name = "BoardContainer"
	_board_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_container)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.anchors_preset = Control.PRESET_FULL_RECT
	_message_label.visible = false
	add_child(_message_label)

	# 设置自身大小限制
	custom_minimum_size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)
	_theme_utility = _get_theme_utility()


# --- 公共方法 ---

## 根据快照和配置显示预览。
## @param snapshot: 包含 "grid_size" 和 "tiles" 的字典。
## @param mode_config: 游戏模式配置，用于获取配色和规则。
func show_snapshot(snapshot: Dictionary, mode_config: GameModeConfig) -> void:
	_clear_preview_internal()
	_message_label.visible = false

	if snapshot.is_empty() or not is_instance_valid(mode_config):
		show_message(tr("NO_PREVIEW_DATA")) # 本地化
		return

	var grid_size: int = GFVariantData.to_int(snapshot.get(&"grid_size", snapshot.get("grid_size", 4)), 4)
	var tiles_data: Array = GFVariantData.to_array(snapshot.get(&"tiles", snapshot.get("tiles", [])))
	var board_theme: BoardTheme = _resolve_board_theme(mode_config)
	var color_schemes: Dictionary = _resolve_color_schemes(mode_config)

	# 动态计算尺寸
	var raw_cell_size: float = MAX_PREVIEW_SIZE / (grid_size + (grid_size + 1) * SPACING_RATIO)
	var cell_size: float = floor(raw_cell_size)
	var spacing: float = floor(cell_size * SPACING_RATIO)

	var total_content_size: float = grid_size * cell_size + (grid_size + 1) * spacing
	var offset_start: float = (MAX_PREVIEW_SIZE - total_content_size) / 2.0

	_apply_background_panel_style(board_theme)

	_background_panel.size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)
	_background_panel.position = Vector2.ZERO

	# 绘制背景格子
	for x: int in range(grid_size):
		for y: int in range(grid_size):
			var cell_instance: Control = _instantiate_control(GRID_CELL_SCENE)
			if not is_instance_valid(cell_instance):
				continue
			_board_container.add_child(cell_instance)

			cell_instance.size = Vector2.ONE * cell_size
			cell_instance.position = _get_cell_position(x, y, cell_size, spacing, offset_start)

			# 兼容现有的主题颜色配置
			if cell_instance is Panel:
				var cell_style: StyleBoxFlat = _duplicate_cell_style(cell_instance)
				if is_instance_valid(board_theme):
					cell_style.bg_color = board_theme.empty_cell_color
					cell_style.border_color = board_theme.empty_cell_border_color
				cell_style.set_border_width_all(2)
				# 预览图稍微缩小圆角
				cell_style.set_corner_radius_all(maxi(2, roundi(cell_size * 0.1)))
				cell_instance.add_theme_stylebox_override("panel", cell_style)

	# 绘制方块
	for tile_value: Variant in tiles_data:
		if not tile_value is Dictionary:
			continue
		var tile_data: Dictionary = tile_value
		var pos: Vector2i = _to_vector2i(tile_data.get(&"pos", tile_data.get("pos", Vector2i.ZERO)))
		if not _is_grid_pos_in_bounds(pos, grid_size):
			continue

		var value: int = GFVariantData.to_int(tile_data.get(&"value", tile_data.get("value", 0)), 0)
		var type: Tile.TileType = _to_tile_type(tile_data.get(&"type", tile_data.get("type", Tile.TileType.PLAYER)))

		var tile: Tile = _instantiate_tile(TILE_SCENE)
		if not is_instance_valid(tile):
			continue
		_board_container.add_child(tile)

		var colors: Dictionary = _get_tile_colors(value, type, mode_config, color_schemes)
		var tile_bg_color: Color = _get_color(colors, &"bg", Color.WHITE)
		var tile_font_color: Color = _get_color(colors, &"font", Color.BLACK)
		tile.setup(value, type, tile_bg_color, tile_font_color)

		var scale_factor: float = cell_size / 100.0
		tile.scale = Vector2.ONE * scale_factor

		var cell_top_left: Vector2 = _get_cell_position(pos.x, pos.y, cell_size, spacing, offset_start)
		tile.position = cell_top_left + Vector2.ONE * (cell_size / 2.0)


## 在预览区域中心显示一条文本消息（如"无数据"）。
## 会自动清除当前的棋盘显示。
## @param text: 要显示的文本。
func show_message(text: String) -> void:
	_clear_preview_internal()
	_apply_background_panel_style(_resolve_board_theme(null))
	_background_panel.size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)

	_message_label.text = text
	_message_label.visible = true


## 完全清空预览区域，隐藏所有文字和背景。
## 使父容器的背景可以显示出来。
func clear() -> void:
	_clear_preview_internal()
	_message_label.visible = false
	
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	_background_panel.add_theme_stylebox_override("panel", style)


# --- 私有/辅助方法 ---

func _clear_preview_internal() -> void:
	for child: Node in _board_container.get_children():
		child.queue_free()


func _apply_background_panel_style(board_theme: BoardTheme) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.972549, 0.9098039, 1.0)
	style.border_color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
	if is_instance_valid(board_theme):
		style.bg_color = board_theme.board_panel_color
		style.border_color = board_theme.board_border_color
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	_background_panel.add_theme_stylebox_override("panel", style)


func _instantiate_control(scene: PackedScene) -> Control:
	var instance: Node = scene.instantiate()
	if instance is Control:
		var control: Control = instance
		return control
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _instantiate_tile(scene: PackedScene) -> Tile:
	var instance: Node = scene.instantiate()
	if instance is Tile:
		var tile: Tile = instance
		return tile
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _duplicate_cell_style(cell_instance: Control) -> StyleBoxFlat:
	var base_cell_style: StyleBox = cell_instance.get_theme_stylebox("panel")
	if base_cell_style is StyleBoxFlat:
		var base_flat_style: StyleBoxFlat = base_cell_style
		var duplicated_style: Resource = base_flat_style.duplicate()
		if duplicated_style is StyleBoxFlat:
			var flat_style: StyleBoxFlat = duplicated_style
			return flat_style
	return StyleBoxFlat.new()


func _get_cell_position(x: int, y: int, cell_size: float, spacing: float, offset: float) -> Vector2:
	return Vector2(
		offset + spacing + x * (cell_size + spacing),
		offset + spacing + y * (cell_size + spacing)
	)


func _is_grid_pos_in_bounds(grid_pos: Vector2i, grid_size: int) -> bool:
	return (
		grid_size > 0
		and grid_pos.x >= 0
		and grid_pos.x < grid_size
		and grid_pos.y >= 0
		and grid_pos.y < grid_size
	)


func _get_tile_colors(
	value: int,
	type: Tile.TileType,
	mode_config: GameModeConfig,
	color_schemes: Dictionary
) -> Dictionary:
	var bg_color: Color = Color.WHITE
	var font_color: Color = Color.BLACK
	
	if not is_instance_valid(mode_config) or not is_instance_valid(mode_config.interaction_rule):
		return {"bg": bg_color, "font": font_color}
		
	var scheme_index: int = type
	if type == Tile.TileType.PLAYER:
		scheme_index = mode_config.interaction_rule.get_color_scheme_index(value)
		
	var scheme_value: Variant = color_schemes.get(scheme_index)
	if not scheme_value is TileColorScheme:
		return {"bg": bg_color, "font": font_color}
	var current_scheme: TileColorScheme = scheme_value
	if is_instance_valid(current_scheme) and not current_scheme.styles.is_empty():
		var level: int = mode_config.interaction_rule.get_level_by_value(value)
		if level >= current_scheme.styles.size():
			level = current_scheme.styles.size() - 1
		var current_style: TileLevelStyle = current_scheme.styles[level]
		if is_instance_valid(current_style):
			bg_color = current_style.background_color
			font_color = current_style.font_color
			
	return {"bg": bg_color, "font": font_color}


func _resolve_board_theme(mode_config: GameModeConfig) -> BoardTheme:
	var fallback: BoardTheme = null
	if is_instance_valid(mode_config):
		fallback = mode_config.board_theme

	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		return theme_utility.resolve_board_theme(fallback)
	return fallback


func _resolve_color_schemes(mode_config: GameModeConfig) -> Dictionary:
	var fallback: Dictionary = {}
	if is_instance_valid(mode_config):
		fallback = mode_config.color_schemes

	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		return theme_utility.resolve_color_schemes(fallback)
	return fallback


func _get_theme_utility() -> GameThemeUtility:
	if is_instance_valid(_theme_utility):
		return _theme_utility

	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return null

	var utility_value: Object = architecture.get_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		_theme_utility = theme_utility
		return theme_utility
	return null


func _get_architecture_or_null() -> GFArchitecture:
	var context: GFNodeContextBase = _find_nearest_context()
	if context != null:
		var context_architecture: GFArchitecture = context.get_architecture()
		if context_architecture != null:
			return context_architecture

	return _GF_AUTOLOAD_SCRIPT.get_architecture_or_null()


func _find_nearest_context() -> GFNodeContextBase:
	var current_node: Node = self
	while current_node != null:
		if current_node is GFNodeContextBase:
			var context: GFNodeContextBase = current_node
			return context
		current_node = current_node.get_parent()

	return null


static func _to_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		var vector2i_value: Vector2i = value
		return vector2i_value
	if value is Vector2:
		var vector2_value: Vector2 = value
		return Vector2i(roundi(vector2_value.x), roundi(vector2_value.y))
	if value is Dictionary:
		var data: Dictionary = value
		return Vector2i(
			GFVariantData.to_int(data.get(&"x", data.get("x", 0)), 0),
			GFVariantData.to_int(data.get(&"y", data.get("y", 0)), 0)
		)
	return Vector2i.ZERO


static func _to_tile_type(value: Variant) -> Tile.TileType:
	var raw_type: int = GFVariantData.to_int(value, int(Tile.TileType.PLAYER))
	match raw_type:
		Tile.TileType.PLAYER:
			return Tile.TileType.PLAYER
		Tile.TileType.MONSTER:
			return Tile.TileType.MONSTER
		_:
			return Tile.TileType.PLAYER


static func _get_color(data: Dictionary, key: StringName, fallback: Color) -> Color:
	var color_value: Variant = data.get(key, data.get(String(key), fallback))
	if color_value is Color:
		return color_value
	return fallback
