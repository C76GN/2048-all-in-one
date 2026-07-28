## MainMenuBoardMotif: 主菜单上的只读棋盘印刷构图。
class_name MainMenuBoardMotif
extends Control


# --- 常量 ---

const _GRID_SIZE: int = 4
const _INTRO_DURATION: float = 0.82
const _BOARD_REVEAL_PORTION: float = 0.24
const _TILE_REVEAL_START: float = 0.16
const _TILE_REVEAL_STAGGER: float = 0.032
const _TILE_REVEAL_DURATION: float = 0.28
const _DEMO_DURATION: float = 0.54
const _DEMO_SLIDE_PORTION: float = 0.62
const _DEMO_NEW_TILE_START: float = 0.72
const _IDLE_REDRAW_INTERVAL: float = 1.0 / 30.0
const _IDLE_OFFSET: float = 0.65
const _IDLE_ROTATION: float = 0.003
const _BOARD_COLOR: Color = Color("#594a45")
const _EMPTY_COLOR: Color = Color("#a9a994")
const _INK_COLOR: Color = Color("#2f3037")
const _PAPER_COLOR: Color = Color("#f1e2be")
const _MUSTARD_COLOR: Color = Color("#e6d1a1")
const _OCHRE_COLOR: Color = Color("#f0d696")
const _APRICOT_COLOR: Color = Color("#caac77")
const _BRICK_COLOR: Color = Color("#c0977a")
const _SLATE_COLOR: Color = Color("#445162")
const _DEMO_START_VALUES: Array[int] = [2, 2, 4, 8]
const _TILE_VALUES: Array[int] = [
	4, 4, 8, 2,
	0, 16, 0, 0,
	2, 0, 32, 4,
	64, 0, 8, 128,
]


# --- 私有变量 ---

var _intro_progress: float = 1.0
var _demo_progress: float = 1.0
var _idle_seconds: float = 0.0
var _idle_redraw_seconds: float = 0.0
var _reduced_motion: bool = false
var _intro_tween: Tween = null


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _resize_connection: int = resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(delta: float) -> void:
	if _reduced_motion or not is_visible_in_tree():
		return
	_idle_seconds += delta
	_idle_redraw_seconds += delta
	if _idle_redraw_seconds < _IDLE_REDRAW_INTERVAL:
		return
	_idle_redraw_seconds = 0.0
	queue_redraw()


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
	var board_progress: float = _ease_out_cubic(
		clampf(_intro_progress / _BOARD_REVEAL_PORTION, 0.0, 1.0)
	)
	board_shadow.a = 0.20 * board_progress
	draw_rect(Rect2(board_rect.position + Vector2(6.0, 7.0), board_rect.size), board_shadow, true)
	draw_rect(board_rect, _with_alpha(_BOARD_COLOR, board_progress), true)
	draw_rect(board_rect, _with_alpha(_INK_COLOR, board_progress), false, 4.0)

	var outer_padding: float = board_size * 0.055
	var gap: float = board_size * 0.028
	var cell_size: float = (
		board_size - outer_padding * 2.0 - gap * float(_GRID_SIZE - 1)
	) / float(_GRID_SIZE)
	var font: Font = get_theme_font("font", "Label")
	var demo_active: bool = _intro_progress >= 1.0 and _demo_progress < 1.0

	for index: int in range(_TILE_VALUES.size()):
		if demo_active and index < _GRID_SIZE:
			continue
		var column: int = index % _GRID_SIZE
		var row: int = floori(float(index) / float(_GRID_SIZE))
		var cell_origin: Vector2 = origin + Vector2(
			outer_padding + float(column) * (cell_size + gap),
			outer_padding + float(row) * (cell_size + gap)
		)
		var cell_rect: Rect2 = Rect2(cell_origin, Vector2.ONE * cell_size)
		var value: int = (
			_DEMO_START_VALUES[index]
			if index < _GRID_SIZE and _demo_progress < 1.0
			else _TILE_VALUES[index]
		)
		var fill: Color = _EMPTY_COLOR if value == 0 else _get_tile_color(value)
		_draw_intro_tile(
			cell_rect,
			fill,
			value,
			board_size,
			font,
			index
		)
	if demo_active:
		_draw_demo_row(
			origin,
			outer_padding,
			cell_size,
			gap,
			board_size,
			font
		)


# --- 公共方法 ---

## 播放微缩棋盘从纸面到方块逐项落定的开场展示。
## @param reduced_motion: 为 true 时直接提交最终静态构图。
## @param shortened: 再次回到主菜单时使用更短的展示。
func play_intro(reduced_motion: bool, shortened: bool = false) -> void:
	_reduced_motion = reduced_motion
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = null
	if reduced_motion:
		_set_intro_progress(1.0)
		_set_demo_progress(1.0)
		set_process(false)
		return

	_set_intro_progress(0.0)
	_set_demo_progress(1.0 if shortened else 0.0)
	set_process(true)
	var duration: float = 0.32 if shortened else _INTRO_DURATION
	_intro_tween = create_tween()
	var _pause_mode_result: Tween = _intro_tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS
	)
	var progress_tweener: MethodTweener = _intro_tween.tween_method(
		_set_intro_progress,
		0.0,
		1.0,
		duration
	)
	var _progress_transition: Tweener = progress_tweener.set_trans(
		Tween.TRANS_LINEAR
	)
	var _progress_ease: Tweener = progress_tweener.set_ease(
		Tween.EASE_IN_OUT
	)
	if not shortened:
		var demo_tweener: MethodTweener = _intro_tween.tween_method(
			_set_demo_progress,
			0.0,
			1.0,
			_DEMO_DURATION
		)
		var _demo_transition: Tweener = demo_tweener.set_trans(
			Tween.TRANS_LINEAR
		)
		var _demo_ease: Tweener = demo_tweener.set_ease(
			Tween.EASE_IN_OUT
		)
	var _finished_connection: int = _intro_tween.finished.connect(
		_on_intro_finished,
		CONNECT_ONE_SHOT
	)


## 跳过尚未结束的首页展示并立即提交最终棋盘。
func finish_intro() -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = null
	_set_intro_progress(1.0)
	_set_demo_progress(1.0)
	set_process(not _reduced_motion)


# --- 私有/辅助方法 ---

func _draw_intro_tile(
	cell_rect: Rect2,
	fill: Color,
	value: int,
	board_size: float,
	font: Font,
	index: int
) -> void:
	var tile_progress: float = clampf(
		(
			_intro_progress
			- _TILE_REVEAL_START
			- float(index) * _TILE_REVEAL_STAGGER
		) / _TILE_REVEAL_DURATION,
		0.0,
		1.0
	)
	if tile_progress <= 0.0:
		return
	var eased_progress: float = _ease_out_back(tile_progress)
	var entry_distance: float = cell_rect.size.x * 0.34
	var entry_direction: Vector2 = _get_entry_direction(index)
	var idle_offset: Vector2 = Vector2.ZERO
	var idle_rotation: float = 0.0
	if (
		not _reduced_motion
		and _intro_progress >= 1.0
		and value != 0
		and index % 3 == 1
	):
		var idle_phase: float = _idle_seconds * 0.82 + float(index) * 0.74
		idle_offset.y = sin(idle_phase) * _IDLE_OFFSET
		idle_rotation = sin(idle_phase * 0.73) * _IDLE_ROTATION
	var center: Vector2 = cell_rect.get_center()
	center += entry_direction * entry_distance * (1.0 - tile_progress)
	center += idle_offset
	var draw_rotation: float = (
		float((index % 5) - 2)
		* 0.035
		* (1.0 - tile_progress)
		+ idle_rotation
	)
	var scale_value: float = lerpf(0.58, 1.0, eased_progress)
	draw_set_transform(center, draw_rotation, Vector2.ONE * scale_value)
	var local_rect: Rect2 = Rect2(-cell_rect.size * 0.5, cell_rect.size)
	_draw_tile_surface(
		local_rect,
		fill,
		value != 0,
		board_size,
		tile_progress
	)
	if value != 0:
		_draw_tile_text(local_rect, fill, value, font, tile_progress)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_demo_row(
	origin: Vector2,
	outer_padding: float,
	cell_size: float,
	gap: float,
	board_size: float,
	font: Font
) -> void:
	var step: float = cell_size + gap
	var row_origin: Vector2 = origin + Vector2.ONE * outer_padding
	for column: int in range(_GRID_SIZE):
		var empty_rect: Rect2 = Rect2(
			row_origin + Vector2(float(column) * step, 0.0),
			Vector2.ONE * cell_size
		)
		_draw_tile_surface(empty_rect, _EMPTY_COLOR, false, board_size)

	var slide_progress: float = _ease_out_cubic(
		clampf(_demo_progress / _DEMO_SLIDE_PORTION, 0.0, 1.0)
	)
	if _demo_progress < _DEMO_SLIDE_PORTION:
		var target_columns: Array[int] = [0, 0, 1, 2]
		for source_column: int in range(_DEMO_START_VALUES.size()):
			var moving_x: float = lerpf(
				float(source_column) * step,
				float(target_columns[source_column]) * step,
				slide_progress
			)
			_draw_transformed_tile(
				row_origin + Vector2(moving_x, 0.0),
				cell_size,
				_DEMO_START_VALUES[source_column],
				board_size,
				font,
				1.0
			)
		return

	var merge_progress: float = clampf(
		(_demo_progress - _DEMO_SLIDE_PORTION) / 0.24,
		0.0,
		1.0
	)
	var merge_scale: float = 1.0 + sin(merge_progress * PI) * 0.12
	for column: int in range(3):
		_draw_transformed_tile(
			row_origin + Vector2(float(column) * step, 0.0),
			cell_size,
			_TILE_VALUES[column],
			board_size,
			font,
			merge_scale if column == 0 else 1.0
		)

	var new_tile_progress: float = clampf(
		(_demo_progress - _DEMO_NEW_TILE_START)
		/ (1.0 - _DEMO_NEW_TILE_START),
		0.0,
		1.0
	)
	if new_tile_progress > 0.0:
		_draw_transformed_tile(
			row_origin + Vector2(3.0 * step, 0.0),
			cell_size,
			_TILE_VALUES[3],
			board_size,
			font,
			lerpf(0.54, 1.0, _ease_out_back(new_tile_progress)),
			new_tile_progress
		)


func _draw_transformed_tile(
	tile_position: Vector2,
	cell_size: float,
	value: int,
	board_size: float,
	font: Font,
	scale_value: float,
	alpha: float = 1.0
) -> void:
	var center: Vector2 = tile_position + Vector2.ONE * cell_size * 0.5
	draw_set_transform(center, 0.0, Vector2.ONE * scale_value)
	var local_rect: Rect2 = Rect2(
		-Vector2.ONE * cell_size * 0.5,
		Vector2.ONE * cell_size
	)
	var fill: Color = _get_tile_color(value)
	_draw_tile_surface(local_rect, fill, true, board_size, alpha)
	_draw_tile_text(local_rect, fill, value, font, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tile_surface(
	rect: Rect2,
	fill: Color,
	occupied: bool,
	board_size: float,
	alpha: float = 1.0
) -> void:
	var border_width: float = maxf(board_size * 0.008, 2.0)
	if occupied:
		var shadow_color: Color = _INK_COLOR
		shadow_color.a = 0.22 * alpha
		var shadow_rect: Rect2 = Rect2(
			rect.position + Vector2(2.0, 2.0),
			rect.size - Vector2(2.0, 2.0)
		)
		draw_rect(shadow_rect, shadow_color, true)
	draw_rect(rect, _with_alpha(fill, alpha), true)
	draw_rect(rect, _with_alpha(_INK_COLOR, alpha), false, border_width)
	if not occupied:
		return
	var highlight: Color = fill.lightened(0.34)
	highlight.a = 0.52 * alpha
	draw_line(rect.position + Vector2(4.0, 3.0), rect.end - Vector2(4.0, rect.size.y - 3.0), highlight, 1.5, true)
	draw_line(rect.position + Vector2(3.0, 4.0), rect.end - Vector2(rect.size.x - 3.0, 4.0), highlight, 1.5, true)


func _draw_tile_text(
	rect: Rect2,
	fill: Color,
	value: int,
	font: Font,
	alpha: float
) -> void:
	var text: String = str(value)
	var font_size: int = clampi(
		roundi(rect.size.x * (0.34 if value >= 100 else 0.42)),
		16,
		40
	)
	var text_size: Vector2 = font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	var baseline: Vector2 = rect.position + Vector2(
		(rect.size.x - text_size.x) * 0.5,
		(rect.size.y + text_size.y) * 0.5 - 3.0
	)
	var text_shadow: Color = _INK_COLOR
	text_shadow.a = 0.18 * alpha
	draw_string(
		font,
		baseline + Vector2(1.0, 1.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		text_shadow
	)
	draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		_with_alpha(_get_text_color(fill), alpha)
	)


func _get_entry_direction(index: int) -> Vector2:
	match index % 4:
		0:
			return Vector2(-1.0, -0.35)
		1:
			return Vector2(0.25, -1.0)
		2:
			return Vector2(1.0, 0.30)
		_:
			return Vector2(-0.20, 1.0)


func _set_intro_progress(value: float) -> void:
	_intro_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _set_demo_progress(value: float) -> void:
	_demo_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _on_intro_finished() -> void:
	_intro_tween = null
	_set_intro_progress(1.0)
	_set_demo_progress(1.0)


func _ease_out_cubic(value: float) -> float:
	var inverse: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


func _ease_out_back(value: float) -> float:
	var clamped_value: float = clampf(value, 0.0, 1.0)
	const C1: float = 1.70158
	const C3: float = C1 + 1.0
	var shifted: float = clamped_value - 1.0
	return 1.0 + C3 * shifted * shifted * shifted + C1 * shifted * shifted


func _with_alpha(color: Color, alpha: float) -> Color:
	var result: Color = color
	result.a *= clampf(alpha, 0.0, 1.0)
	return result


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
