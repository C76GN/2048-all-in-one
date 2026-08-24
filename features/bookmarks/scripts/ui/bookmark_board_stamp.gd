## BookmarkBoardStamp: 书签卡片中的有界棋盘样张印记。
##
## 只绘制已通过 BookmarkData 严格 schema 的快照摘要；最多扫描 256 个持久化
## 单元，不实例化 Tile/BoardGridCell，也不拥有玩法状态或资源生命周期。
class_name BookmarkBoardStamp
extends Control


# --- 常量 ---

const _MAX_RENDERED_CELLS: int = BookmarkData.PERSISTED_BOARD_CELL_LIMIT
const _INSET: float = 6.0
const _CELL_GAP_RATIO: float = 0.12


# --- 私有变量 ---

var _topology: BoardTopology = null
var _tile_value_by_cell: Dictionary = {}
var _tile_color_by_cell: Dictionary = {}
var _color_schemes: Dictionary = {}
var _paper_color: Color = Color(1.0, 0.972549, 0.909804, 1.0)
var _ink_color: Color = Color(0.184314, 0.188235, 0.215686, 1.0)
var _empty_cell_color: Color = Color(0.184314, 0.188235, 0.215686, 0.12)


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(104.0, 104.0)


func _draw() -> void:
	var proof_rect: Rect2 = Rect2(Vector2.ZERO, size)
	proof_rect = proof_rect.grow(-_INSET)
	proof_rect.size.x = maxf(proof_rect.size.x, 1.0)
	proof_rect.size.y = maxf(proof_rect.size.y, 1.0)
	draw_rect(proof_rect, _paper_color)
	draw_rect(proof_rect, _ink_color, false, 2.0)
	if not is_instance_valid(_topology):
		return
	var board_size: Vector2i = _topology.get_bounds_size()
	if board_size.x <= 0 or board_size.y <= 0:
		return
	var gap_ratio: float = _CELL_GAP_RATIO
	var cell_extent: float = minf(
		proof_rect.size.x / (float(board_size.x) + float(board_size.x + 1) * gap_ratio),
		proof_rect.size.y / (float(board_size.y) + float(board_size.y + 1) * gap_ratio)
	)
	var gap: float = maxf(cell_extent * gap_ratio, 1.0)
	var content_size: Vector2 = Vector2(
		float(board_size.x) * cell_extent + float(board_size.x + 1) * gap,
		float(board_size.y) * cell_extent + float(board_size.y + 1) * gap
	)
	var origin: Vector2 = proof_rect.position + (proof_rect.size - content_size) * 0.5
	var active_cells: Array[Vector2i] = _topology.get_active_cells()
	for cell_index: int in range(mini(active_cells.size(), _MAX_RENDERED_CELLS)):
		var cell: Vector2i = active_cells[cell_index]
		var cell_rect: Rect2 = Rect2(
			origin + Vector2(
				gap + float(cell.x) * (cell_extent + gap),
				gap + float(cell.y) * (cell_extent + gap)
			),
			Vector2.ONE * cell_extent
		)
		var value: int = GFVariantData.get_option_int(
			_tile_value_by_cell,
			cell,
			0
		)
		var fill_color: Color = (
			_get_tile_color(cell, value)
			if value > 0
			else _empty_cell_color
		)
		draw_rect(cell_rect, fill_color)
		if value > 0:
			draw_rect(cell_rect, _ink_color, false, maxf(cell_extent * 0.055, 1.0))


# --- 公共方法 ---

## 从严格书签棋盘快照更新有界缩略投影。
## @param snapshot: BookmarkData.board_snapshot 的当前 schema 字典。
## @param mode_config: 只用于解析棋盘和方块视觉，不作为玩法状态来源。
## @param theme_utility: 可选的当前主题解析服务；为空时使用模式自身视觉资源。
func configure(
	snapshot: Dictionary,
	mode_config: GameModeConfig,
	theme_utility: GameThemeUtility = null
) -> void:
	_topology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(snapshot, &"topology")
	)
	_tile_value_by_cell.clear()
	_tile_color_by_cell.clear()
	_apply_theme_colors(mode_config, theme_utility)
	if not is_instance_valid(_topology):
		queue_redraw()
		return
	var tiles: Array = GFVariantData.get_option_array(snapshot, &"tiles")
	for tile_index: int in range(mini(tiles.size(), _MAX_RENDERED_CELLS)):
		var tile_value: Variant = tiles[tile_index]
		if not tile_value is Dictionary:
			continue
		var tile_data: Dictionary = tile_value
		var cell: Vector2i = _to_vector2i(
			GFVariantData.get_option_value(tile_data, &"pos", Vector2i.ZERO)
		)
		if not _topology.contains_cell(cell):
			continue
		var value: int = GFVariantData.get_option_int(tile_data, &"value", 0)
		if value <= 0:
			continue
		_tile_value_by_cell[cell] = value
		# Ratio 等模式允许相同数值由不同 definition 表达；颜色必须归属
		# 具体方块/格子，不能只按 value 合并缓存。
		_tile_color_by_cell[cell] = _resolve_tile_color(
			value,
			GFVariantData.get_option_string_name(tile_data, &"definition_id"),
			mode_config
		)
	queue_redraw()


## 清除样张投影并释放快照派生缓存。
func clear() -> void:
	_topology = null
	_tile_value_by_cell.clear()
	_tile_color_by_cell.clear()
	_color_schemes.clear()
	queue_redraw()


## 返回本组件本轮最多会绘制的活跃单元数量。
func get_rendered_cell_count() -> int:
	return (
		mini(_topology.get_cell_count(), _MAX_RENDERED_CELLS)
		if is_instance_valid(_topology)
		else 0
	)


# --- 私有/辅助方法 ---

func _apply_theme_colors(
	mode_config: GameModeConfig,
	theme_utility: GameThemeUtility
) -> void:
	_color_schemes.clear()
	if not is_instance_valid(mode_config) or not is_instance_valid(theme_utility):
		return
	var board_theme: BoardTheme = theme_utility.resolve_board_theme_for_mode(
		mode_config.visual_profile_id
	)
	_color_schemes = theme_utility.resolve_color_schemes_for_mode(
		mode_config.visual_profile_id
	)
	if not is_instance_valid(board_theme):
		return
	_paper_color = board_theme.board_panel_color
	_ink_color = board_theme.board_border_color
	_empty_cell_color = board_theme.empty_cell_color


func _resolve_tile_color(
	value: int,
	definition_id: StringName,
	mode_config: GameModeConfig
) -> Color:
	if not is_instance_valid(mode_config) or not is_instance_valid(
		mode_config.interaction_rule
	):
		return _fallback_tile_color(value)
	var scheme_index: int = mode_config.interaction_rule.get_color_scheme_index(
		value,
		definition_id
	)
	var scheme_value: Variant = _color_schemes.get(scheme_index)
	if not scheme_value is TileColorScheme:
		return _fallback_tile_color(value)
	var color_scheme: TileColorScheme = scheme_value
	if color_scheme.styles.is_empty():
		return _fallback_tile_color(value)
	var level: int = clampi(
		mode_config.interaction_rule.get_level_by_value(value),
		0,
		color_scheme.styles.size() - 1
	)
	var style: TileLevelStyle = color_scheme.styles[level]
	return style.background_color if is_instance_valid(style) else _fallback_tile_color(value)


func _get_tile_color(cell: Vector2i, value: int) -> Color:
	var color_value: Variant = _tile_color_by_cell.get(cell)
	if color_value is Color:
		var tile_color: Color = color_value
		return tile_color
	return _fallback_tile_color(value)


func _fallback_tile_color(value: int) -> Color:
	var level: float = clampf(log(float(maxi(value, 2))) / log(2.0), 1.0, 16.0)
	return _paper_color.lerp(_ink_color, 0.16 + level * 0.035)


static func _to_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		var vector_value: Vector2i = value
		return vector_value
	if value is Vector2:
		var float_vector: Vector2 = value
		return Vector2i(roundi(float_vector.x), roundi(float_vector.y))
	return Vector2i.ZERO
