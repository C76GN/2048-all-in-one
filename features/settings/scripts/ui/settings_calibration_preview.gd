## SettingsCalibrationPreview: 设置页的只读视觉校准样张。
##
## 只把当前表单值投影为静态棋盘/套印示例；不读取或写入持久化状态。
class_name SettingsCalibrationPreview
extends Control


# --- 常量 ---

const _PAPER_COLOR: Color = Color("#f8f1df")
const _INK_COLOR: Color = Color("#2f3037")
const _CYAN_COLOR: Color = Color("#42b9c0")
const _MAGENTA_COLOR: Color = Color("#d44b84")
const _YELLOW_COLOR: Color = Color("#e6c654")
const _CELL_VALUES: Array[int] = [2, 4, 8, 16]
const _CELL_COLORS: Array[Color] = [
	_PAPER_COLOR,
	_YELLOW_COLOR,
	_CYAN_COLOR,
	_MAGENTA_COLOR,
]


# --- 私有变量 ---

var _reduced_motion: bool = false
var _high_contrast: bool = false
var _shader_effects_enabled: bool = true
var _vfx_quality: int = GameAccessibilityState.VfxQuality.FULL


# --- Godot 生命周期方法 ---

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 118.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _resize_connection: int = resized.connect(queue_redraw)


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var border_width: float = 3.0 if _high_contrast else 1.5
	var ink: Color = Color.BLACK if _high_contrast else _INK_COLOR
	draw_rect(Rect2(Vector2.ZERO, size), _PAPER_COLOR, true)
	draw_rect(Rect2(Vector2.ZERO, size), ink, false, border_width)

	var board_side: float = minf(size.y - 26.0, minf(size.x * 0.42, 92.0))
	var board_rect: Rect2 = Rect2(
		Vector2(14.0, (size.y - board_side) * 0.5),
		Vector2.ONE * board_side
	)
	_draw_board_sample(board_rect, ink, border_width)
	_draw_registration_sample(board_rect, ink)
	_draw_status_text(board_rect, ink)


# --- 公共方法 ---

## 更新只读校准样张；调用方仍负责写入真实无障碍状态。
## @param reduced_motion: 是否使用静态等价反馈。
## @param high_contrast: 是否增强边框与文字对比度。
## @param shader_effects_enabled: 是否展示动态 Shader 通道处于启用状态。
## @param vfx_quality: 当前特效质量枚举值。
func configure_preview(
	reduced_motion: bool,
	high_contrast: bool,
	shader_effects_enabled: bool,
	vfx_quality: int
) -> void:
	_reduced_motion = reduced_motion
	_high_contrast = high_contrast
	_shader_effects_enabled = shader_effects_enabled
	_vfx_quality = vfx_quality
	queue_redraw()


## 返回不含业务状态的预览快照，供无障碍描述与测试使用。
func get_preview_snapshot() -> Dictionary:
	return {
		&"reduced_motion": _reduced_motion,
		&"high_contrast": _high_contrast,
		&"shader_effects_enabled": _shader_effects_enabled,
		&"vfx_quality": int(_vfx_quality),
		&"motion_expression": &"static_peak" if _reduced_motion else &"animated_transition",
	}


# --- 私有/辅助方法 ---

func _draw_board_sample(board_rect: Rect2, ink: Color, border_width: float) -> void:
	var gap: float = 5.0
	var cell_size: float = (board_rect.size.x - gap) * 0.5
	for index: int in range(_CELL_VALUES.size()):
		var column: int = index % 2
		var row: int = floori(float(index) / 2.0)
		var cell_rect: Rect2 = Rect2(
			board_rect.position + Vector2(
				float(column) * (cell_size + gap),
				float(row) * (cell_size + gap)
			),
			Vector2.ONE * cell_size
		)
		var fill: Color = _CELL_COLORS[index]
		if _vfx_quality == GameAccessibilityState.VfxQuality.MINIMAL:
			fill = fill.lerp(_PAPER_COLOR, 0.38)
		draw_rect(cell_rect, fill, true)
		draw_rect(cell_rect, ink, false, border_width)
		var font: Font = get_theme_font("font", "Label")
		var font_size: int = clampi(roundi(cell_size * 0.34), 12, 22)
		var text: String = str(_CELL_VALUES[index])
		var text_size: Vector2 = font.get_string_size(
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		)
		draw_string(
			font,
			cell_rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.35),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			ink
		)


func _draw_registration_sample(board_rect: Rect2, ink: Color) -> void:
	var center: Vector2 = board_rect.get_center()
	var arm: float = board_rect.size.x * 0.18
	var offset: float = 0.0 if _reduced_motion else 2.5
	var channel_alpha: float = 0.88 if _shader_effects_enabled else 0.26
	if _vfx_quality == GameAccessibilityState.VfxQuality.MINIMAL:
		channel_alpha *= 0.45
	_draw_registration_channel(
		center + Vector2(-offset, 0.0),
		arm,
		_with_alpha(_CYAN_COLOR, channel_alpha)
	)
	_draw_registration_channel(
		center + Vector2(offset, 0.0),
		arm,
		_with_alpha(_MAGENTA_COLOR, channel_alpha)
	)
	if _high_contrast:
		draw_circle(center, 4.0, ink, false, 2.0, true)


func _draw_registration_channel(center: Vector2, arm: float, color: Color) -> void:
	draw_line(
		center - Vector2(arm, 0.0),
		center + Vector2(arm, 0.0),
		color,
		2.0,
		true
	)
	draw_line(
		center - Vector2(0.0, arm),
		center + Vector2(0.0, arm),
		color,
		2.0,
		true
	)


func _draw_status_text(board_rect: Rect2, ink: Color) -> void:
	var status_origin: Vector2 = Vector2(board_rect.end.x + 18.0, 24.0)
	var available_width: float = maxf(size.x - status_origin.x - 14.0, 40.0)
	var font: Font = get_theme_font("font", "Label")
	draw_string(
		font,
		status_origin,
		tr("SETTINGS_CALIBRATION_PREVIEW_TITLE"),
		HORIZONTAL_ALIGNMENT_LEFT,
		available_width,
		14,
		ink
	)
	var status_lines: PackedStringArray = PackedStringArray([
		tr("SETTINGS_CALIBRATION_MOTION_STATIC")
		if _reduced_motion
		else tr("SETTINGS_CALIBRATION_MOTION_ACTIVE"),
		tr("SETTINGS_CALIBRATION_CONTRAST_HIGH")
		if _high_contrast
		else tr("SETTINGS_CALIBRATION_CONTRAST_STANDARD"),
		tr("SETTINGS_CALIBRATION_SHADER_ON")
		if _shader_effects_enabled
		else tr("SETTINGS_CALIBRATION_SHADER_OFF"),
	])
	for line_index: int in range(status_lines.size()):
		draw_string(
			font,
			status_origin + Vector2(0.0, 25.0 + float(line_index) * 20.0),
			"• " + status_lines[line_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			available_width,
			12,
			ink
		)


func _with_alpha(color: Color, alpha: float) -> Color:
	var result: Color = color
	result.a = clampf(alpha, 0.0, 1.0)
	return result
