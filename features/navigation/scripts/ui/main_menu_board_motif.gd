## MainMenuBoardMotif: 主菜单上的只读棋盘印刷构图。
class_name MainMenuBoardMotif
extends Control


# --- 常量 ---

const _GRID_SIZE: int = 4
const _BOARD_COLOR: Color = Color("#594a45")
const _EMPTY_COLOR: Color = Color("#a9a994")
const _INK_COLOR: Color = Color("#2f3037")
const _PAPER_COLOR: Color = Color("#f1e2be")
const _MUSTARD_COLOR: Color = Color("#e6d1a1")
const _OCHRE_COLOR: Color = Color("#f0d696")
const _APRICOT_COLOR: Color = Color("#caac77")
const _BRICK_COLOR: Color = Color("#c0977a")
const _SLATE_COLOR: Color = Color("#445162")
const _TILE_VALUES: Array[int] = [
	2, 4, 0, 8,
	0, 16, 0, 0,
	2, 0, 32, 4,
	64, 0, 8, 128,
]


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _resize_connection: int = resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 1.0:
		return
	var board_size: float = minf(side, 336.0)
	var origin: Vector2 = Vector2(
		(size.x - board_size) * 0.5,
		(size.y - board_size) * 0.5
	)
	var board_rect: Rect2 = Rect2(origin, Vector2.ONE * board_size)
	var board_shadow: Color = _INK_COLOR
	board_shadow.a = 0.20
	draw_rect(Rect2(board_rect.position + Vector2(6.0, 7.0), board_rect.size), board_shadow, true)
	draw_rect(board_rect, _BOARD_COLOR, true)
	draw_rect(board_rect, _INK_COLOR, false, 4.0)

	var outer_padding: float = board_size * 0.055
	var gap: float = board_size * 0.028
	var cell_size: float = (
		board_size - outer_padding * 2.0 - gap * float(_GRID_SIZE - 1)
	) / float(_GRID_SIZE)
	var font: Font = get_theme_font("font", "Label")

	for index: int in range(_TILE_VALUES.size()):
		var column: int = index % _GRID_SIZE
		var row: int = floori(float(index) / float(_GRID_SIZE))
		var cell_origin: Vector2 = origin + Vector2(
			outer_padding + float(column) * (cell_size + gap),
			outer_padding + float(row) * (cell_size + gap)
		)
		var cell_rect: Rect2 = Rect2(cell_origin, Vector2.ONE * cell_size)
		var value: int = _TILE_VALUES[index]
		var fill: Color = _EMPTY_COLOR if value == 0 else _get_tile_color(value)
		_draw_tile_surface(cell_rect, fill, value != 0, board_size)
		if value == 0:
			continue
		var text: String = str(value)
		var font_size: int = clampi(roundi(cell_size * (0.34 if value >= 100 else 0.42)), 16, 40)
		var text_size: Vector2 = font.get_string_size(
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		)
		var baseline: Vector2 = cell_rect.position + Vector2(
			(cell_size - text_size.x) * 0.5,
			(cell_size + text_size.y) * 0.5 - 3.0
		)
		var text_shadow: Color = _INK_COLOR
		text_shadow.a = 0.18
		draw_string(font, baseline + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_shadow)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_text_color(fill))


# --- 私有/辅助方法 ---

func _draw_tile_surface(rect: Rect2, fill: Color, occupied: bool, board_size: float) -> void:
	var border_width: float = maxf(board_size * 0.008, 2.0)
	if occupied:
		var shadow_color: Color = _INK_COLOR
		shadow_color.a = 0.22
		var shadow_rect: Rect2 = Rect2(
			rect.position + Vector2(2.0, 2.0),
			rect.size - Vector2(2.0, 2.0)
		)
		draw_rect(shadow_rect, shadow_color, true)
	draw_rect(rect, fill, true)
	draw_rect(rect, _INK_COLOR, false, border_width)
	if not occupied:
		return
	var highlight: Color = fill.lightened(0.34)
	highlight.a = 0.52
	draw_line(rect.position + Vector2(4.0, 3.0), rect.end - Vector2(4.0, rect.size.y - 3.0), highlight, 1.5, true)
	draw_line(rect.position + Vector2(3.0, 4.0), rect.end - Vector2(rect.size.x - 3.0, 4.0), highlight, 1.5, true)


func _get_tile_color(value: int) -> Color:
	if value <= 2:
		return _PAPER_COLOR
	if value <= 4:
		return _MUSTARD_COLOR
	if value <= 8:
		return _OCHRE_COLOR
	if value <= 16:
		return _APRICOT_COLOR
	if value <= 32:
		return _BRICK_COLOR
	if value <= 64:
		return Color("#944431")
	return _SLATE_COLOR


func _get_text_color(fill: Color) -> Color:
	return _PAPER_COLOR if fill.get_luminance() < 0.42 else _INK_COLOR
