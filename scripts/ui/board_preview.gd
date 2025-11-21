# scripts/ui/board_preview.gd

## BoardPreview: 用于在UI中静态展示棋盘状态的组件。
##
## 它接收一个棋盘快照（Snapshot）和交互规则，渲染出一个缩小版的棋盘。
## 主要用于存档和回放列表的预览。会自动根据容器大小调整单元格尺寸。
class_name BoardPreview
extends Control

# --- 常量 ---

const TILE_SCENE: PackedScene = preload("res://scenes/components/tile.tscn")

## 预览区域的最大显示尺寸（像素）。
const MAX_PREVIEW_SIZE: float = 300.0

## 单元格之间的间距比例（相对于单元格大小）。
const SPACING_RATIO: float = 0.1


# --- 私有变量 ---

var _board_container: Control
var _background_panel: Panel
var _message_label: Label


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_background_panel = Panel.new()
	_background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_panel)

	_board_container = Control.new()
	_board_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_container)

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.anchors_preset = Control.PRESET_FULL_RECT
	_message_label.visible = false
	add_child(_message_label)

	# 设置自身大小限制
	custom_minimum_size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)


# --- 公共方法 ---

## 根据快照和配置显示预览。
## @param snapshot: 包含 "grid_size" 和 "tiles" 的字典。
## @param mode_config: 游戏模式配置，用于获取配色和规则。
func show_snapshot(snapshot: Dictionary, mode_config: GameModeConfig) -> void:
	_clear_preview()
	_message_label.visible = false

	if snapshot.is_empty() or not is_instance_valid(mode_config):
		show_message("暂无预览数据")
		return

	var grid_size: int = snapshot.get("grid_size", 4)
	var tiles_data: Array = snapshot.get("tiles", [])

	# 动态计算尺寸
	# 公式: grid_size * cell + (grid_size + 1) * spacing = MAX_PREVIEW_SIZE
	# spacing = cell * SPACING_RATIO
	var raw_cell_size: float = MAX_PREVIEW_SIZE / (grid_size + (grid_size + 1) * SPACING_RATIO)
	var cell_size: float = floor(raw_cell_size)
	var spacing: float = floor(cell_size * SPACING_RATIO)

	var total_content_size: float = grid_size * cell_size + (grid_size + 1) * spacing
	var offset_start: float = (MAX_PREVIEW_SIZE - total_content_size) / 2.0

	var style := StyleBoxFlat.new()
	style.bg_color = mode_config.board_theme.board_panel_color
	style.set_corner_radius_all(4)
	_background_panel.add_theme_stylebox_override("panel", style)

	_background_panel.size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)
	_background_panel.position = Vector2.ZERO

	for x in grid_size:
		for y in grid_size:
			var cell_bg := Panel.new()
			var cell_style := StyleBoxFlat.new()
			cell_style.bg_color = mode_config.board_theme.empty_cell_color
			cell_style.set_corner_radius_all(max(2, cell_size * 0.1))
			cell_bg.add_theme_stylebox_override("panel", cell_style)
			cell_bg.size = Vector2.ONE * cell_size
			cell_bg.position = _get_cell_position(x, y, cell_size, spacing, offset_start)
			_board_container.add_child(cell_bg)

	for tile_data in tiles_data:
		var pos: Vector2i = tile_data["pos"]
		var value: int = tile_data["value"]
		var type: int = tile_data["type"]

		var tile := TILE_SCENE.instantiate() as Tile
		_board_container.add_child(tile)

		var scale_factor: float = cell_size / 100.0
		tile.scale = Vector2.ONE * scale_factor

		var cell_top_left: Vector2 = _get_cell_position(pos.x, pos.y, cell_size, spacing, offset_start)
		tile.position = cell_top_left + Vector2.ONE * (cell_size / 2.0)

		tile.setup(value, type, mode_config.interaction_rule, mode_config.color_schemes)


## 在预览区域中心显示一条文本消息（如“无数据”）。
## 会自动清除当前的棋盘显示。
## @param text: 要显示的文本。
func show_message(text: String) -> void:
	_clear_preview()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1)
	style.set_corner_radius_all(4)
	_background_panel.add_theme_stylebox_override("panel", style)
	_background_panel.size = Vector2(MAX_PREVIEW_SIZE, MAX_PREVIEW_SIZE)

	_message_label.text = text
	_message_label.visible = true


# --- 私有/辅助方法 ---

func _clear_preview() -> void:
	for child in _board_container.get_children():
		child.queue_free()


func _get_cell_position(x: int, y: int, cell_size: float, spacing: float, offset: float) -> Vector2:
	return Vector2(
		offset + spacing + x * (cell_size + spacing),
		offset + spacing + y * (cell_size + spacing)
	)
