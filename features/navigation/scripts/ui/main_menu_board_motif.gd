## MainMenuBoardMotif: 主菜单上的只读棋盘印刷构图。
class_name MainMenuBoardMotif
extends Control


# --- 常量 ---

const _GRID_SIZE: int = 4
const _BOARD_COLOR: Color = Color("#302136")
const _EMPTY_COLOR: Color = Color("#174957")
const _INK_COLOR: Color = Color("#23272b")
const _PAPER_COLOR: Color = Color("#f8f2e4")
const _CYAN_COLOR: Color = Color("#4bbdc5")
const _PINK_COLOR: Color = Color("#e34b93")
const _YELLOW_COLOR: Color = Color("#f1d65e")
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
	draw_rect(Rect2(board_rect.position + Vector2(7.0, 7.0), board_rect.size), _PINK_COLOR, true)
	draw_rect(Rect2(board_rect.position + Vector2(-4.0, 3.0), board_rect.size), _CYAN_COLOR, true)
	draw_rect(board_rect, _BOARD_COLOR, true)
	draw_rect(board_rect, _INK_COLOR, false, 5.0)

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
		draw_rect(cell_rect, fill, true)
		draw_rect(cell_rect, _INK_COLOR, false, maxf(board_size * 0.009, 2.0))
		if value == 0:
			continue
		_draw_tile_pattern(cell_rect, value)
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
		draw_string(font, baseline + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(1.0, 0.4, 0.55, 0.48))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _INK_COLOR)


# --- 私有/辅助方法 ---

func _draw_tile_pattern(rect: Rect2, value: int) -> void:
	var pattern_color: Color = _INK_COLOR
	pattern_color.a = 0.12
	if value <= 4:
		var dot_gap: float = maxf(rect.size.x / 7.0, 8.0)
		for x_index: int in range(1, 7):
			for y_index: int in range(1, 7):
				if (x_index + y_index) % 2 == 0:
					draw_circle(
						rect.position + Vector2(float(x_index), float(y_index)) * dot_gap,
						1.3,
						pattern_color
					)
		return
	var line_gap: float = maxf(rect.size.x / 6.0, 9.0)
	var start_offset: float = -rect.size.y
	while start_offset < rect.size.x:
		var start: Vector2 = rect.position + Vector2(start_offset, rect.size.y)
		var end: Vector2 = rect.position + Vector2(start_offset + rect.size.y, 0.0)
		draw_line(start, end, pattern_color, 2.0)
		start_offset += line_gap


func _get_tile_color(value: int) -> Color:
	if value <= 2:
		return _PAPER_COLOR
	if value <= 8:
		return _YELLOW_COLOR
	if value <= 32:
		return Color("#f2a37c")
	if value <= 64:
		return _PINK_COLOR
	return _CYAN_COLOR
