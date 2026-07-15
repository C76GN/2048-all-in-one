## GameTheme: 定义一套完整游戏主题的视觉资源和背景参数。
class_name GameTheme
extends Resource


# --- 常量 ---

const _BACKGROUND_SHADER_BASE_COLOR: StringName = &"base_color"
const _BACKGROUND_SHADER_ACCENT_COLOR: StringName = &"accent_color"
const _BACKGROUND_SHADER_SECONDARY_COLOR: StringName = &"secondary_color"
const _BACKGROUND_SHADER_WARM_COLOR: StringName = &"warm_color"
const _BACKGROUND_SHADER_CELL_COLOR_1: StringName = &"cell_color_1"
const _BACKGROUND_SHADER_CELL_COLOR_2: StringName = &"cell_color_2"
const _BACKGROUND_SHADER_GRID_SIZE: StringName = &"grid_size"
const _BACKGROUND_SHADER_LINE_THICKNESS: StringName = &"line_thickness"
const _BACKGROUND_SHADER_DASH_LENGTH: StringName = &"dash_length"
const _BACKGROUND_SHADER_GRID_COLOR: StringName = &"grid_color"
const _BACKGROUND_SHADER_SUB_GRID_SIZE: StringName = &"sub_grid_size"
const _BACKGROUND_SHADER_SUB_LINE_THICKNESS: StringName = &"sub_line_thickness"
const _BACKGROUND_SHADER_SUB_DASH_LENGTH: StringName = &"sub_dash_length"
const _BACKGROUND_SHADER_SUB_GRID_COLOR: StringName = &"sub_grid_color"
const _BACKGROUND_SHADER_GRID_STRENGTH: StringName = &"grid_strength"
const _BACKGROUND_SHADER_GLOW_STRENGTH: StringName = &"glow_strength"
const _BACKGROUND_SHADER_VIGNETTE_STRENGTH: StringName = &"vignette_strength"
const _BACKGROUND_SHADER_PULSE_SPEED: StringName = &"pulse_speed"
const _BACKGROUND_SHADER_GRAIN_STRENGTH: StringName = &"grain_strength"
const _BACKGROUND_SHADER_STIPPLE_STRENGTH: StringName = &"stipple_strength"
const _BACKGROUND_SHADER_FLOW_SCALE: StringName = &"flow_scale"
const _BACKGROUND_SHADER_SCANLINE_STRENGTH: StringName = &"scanline_strength"
const _BACKGROUND_SHADER_CLOUD_PIXELATION: StringName = &"cloud_pixelation"
const _BACKGROUND_SHADER_CLOUD_SCROLL_SPEED_1: StringName = &"cloud_scroll_speed_1"
const _BACKGROUND_SHADER_CLOUD_SCROLL_SPEED_2: StringName = &"cloud_scroll_speed_2"
const _BACKGROUND_SHADER_CLOUD_CENTER_POS: StringName = &"cloud_center_pos"
const _BACKGROUND_SHADER_CLOUD_POSITION_IMPACT: StringName = &"cloud_position_impact"
const _BACKGROUND_SHADER_CLOUD_STRENGTH: StringName = &"cloud_strength"


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""

@export var board_theme: BoardTheme
@export var color_schemes: Dictionary = {}
@export var ui_palette: GameUiPalette
@export var audio_theme: GameAudioTheme
@export var scene_transition_cover_effect: GFScreenTransitionEffect
@export var scene_transition_reveal_effect: GFScreenTransitionEffect

@export var background_base_color: Color = Color(0.95686275, 0.92941177, 0.8666667, 1.0)
@export var background_accent_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
@export var background_secondary_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
@export var background_warm_color: Color = Color(0.9607843, 0.6392157, 0.7882353, 1.0)
@export var background_cell_color_1: Color = Color(0.968, 0.956, 0.925, 0.18)
@export var background_cell_color_2: Color = Color(0.850, 0.835, 0.792, 0.16)
@export var background_grid_size: Vector2 = Vector2(192.0, 192.0)
@export_range(0.0, 8.0, 0.001) var background_line_thickness: float = 0.0
@export_range(0.0, 48.0, 0.001) var background_dash_length: float = 0.0
@export var background_grid_color: Color = Color(0.349, 0.290, 0.271, 0.075)
@export var background_sub_grid_size: Vector2 = Vector2(64.0, 64.0)
@export_range(0.0, 20.0, 0.001) var background_sub_line_thickness: float = 0.85
@export_range(0.0, 48.0, 0.001) var background_sub_dash_length: float = 7.0
@export var background_sub_grid_color: Color = Color(0.349, 0.290, 0.271, 0.105)
@export_range(0.0, 0.25, 0.001) var background_grid_strength: float = 0.05
@export_range(0.0, 0.6, 0.001) var background_glow_strength: float = 0.0
@export_range(0.0, 0.9, 0.001) var background_vignette_strength: float = 0.045
@export_range(0.0, 3.0, 0.001) var background_pulse_speed: float = 0.0
@export_range(0.0, 0.12, 0.001) var background_grain_strength: float = 0.018
@export_range(0.0, 0.12, 0.001) var background_stipple_strength: float = 0.006
@export_range(0.5, 8.0, 0.001) var background_flow_scale: float = 1.35
@export_range(0.0, 0.08, 0.001) var background_scanline_strength: float = 0.0
@export var background_cloud_pixelation: Vector2 = Vector2(192.0, 108.0)
@export var background_cloud_scroll_speed_1: Vector2 = Vector2(0.0040, 0.0014)
@export var background_cloud_scroll_speed_2: Vector2 = Vector2(-0.0032, -0.0009)
@export var background_cloud_center_pos: Vector2 = Vector2(0.5, 0.08)
@export_range(0.0, 1.0, 0.001) var background_cloud_position_impact: float = 0.58
@export_range(0.0, 0.16, 0.001) var background_cloud_strength: float = 0.024


# --- 公共方法 ---

func get_display_text() -> String:
	if not display_name_key.is_empty():
		return tr(display_name_key)
	if theme_id != &"":
		return String(theme_id)
	return tr("UI_UNKNOWN")


## 获取当前主题棋盘资源；未配置时返回调用方的模式默认资源。
## @param fallback: 模式配置提供的默认棋盘主题。
func get_board_theme_with_fallback(fallback: BoardTheme) -> BoardTheme:
	if is_instance_valid(board_theme):
		return board_theme
	return fallback


## 合并当前主题方块色阶和调用方默认色阶。
## @param fallback: 模式配置提供的默认色阶字典。
func get_color_schemes_with_fallback(fallback: Dictionary) -> Dictionary:
	var resolved_schemes: Dictionary = fallback.duplicate()
	for key: Variant in color_schemes.keys():
		var scheme_value: Variant = color_schemes[key]
		if scheme_value is TileColorScheme:
			resolved_schemes[key] = scheme_value
	return resolved_schemes


## 获取主题配置的场景转场效果。
## @param phase: `cover` 表示覆盖旧场景，`reveal` 表示揭示新场景。
func get_scene_transition_effect(phase: StringName) -> GFScreenTransitionEffect:
	match phase:
		&"cover":
			return scene_transition_cover_effect
		&"reveal":
			return scene_transition_reveal_effect
		_:
			return null


## 将当前主题背景颜色和 shader 参数写入 ColorRect。
## @param rect: 要应用背景的 ColorRect。
## @param fallback_board_theme: 主题未配置棋盘资源时使用的默认棋盘主题。
func apply_background_to_color_rect(rect: ColorRect, fallback_board_theme: BoardTheme = null) -> void:
	if not is_instance_valid(rect):
		return

	var resolved_board_theme: BoardTheme = get_board_theme_with_fallback(fallback_board_theme)
	rect.color = background_base_color
	if is_instance_valid(resolved_board_theme):
		rect.color = resolved_board_theme.game_background_color

	var shader_material: ShaderMaterial = _get_shader_material(rect)
	if not is_instance_valid(shader_material):
		return

	shader_material.set_shader_parameter(_BACKGROUND_SHADER_BASE_COLOR, background_base_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_ACCENT_COLOR, background_accent_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SECONDARY_COLOR, background_secondary_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_WARM_COLOR, background_warm_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CELL_COLOR_1, background_cell_color_1)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CELL_COLOR_2, background_cell_color_2)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_GRID_SIZE, background_grid_size)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_LINE_THICKNESS, background_line_thickness)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_DASH_LENGTH, background_dash_length)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_GRID_COLOR, background_grid_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SUB_GRID_SIZE, background_sub_grid_size)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SUB_LINE_THICKNESS, background_sub_line_thickness)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SUB_DASH_LENGTH, background_sub_dash_length)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SUB_GRID_COLOR, background_sub_grid_color)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_GRID_STRENGTH, background_grid_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_GLOW_STRENGTH, background_glow_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_VIGNETTE_STRENGTH, background_vignette_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_PULSE_SPEED, background_pulse_speed)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_GRAIN_STRENGTH, background_grain_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_STIPPLE_STRENGTH, background_stipple_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_FLOW_SCALE, background_flow_scale)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_SCANLINE_STRENGTH, background_scanline_strength)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_PIXELATION, background_cloud_pixelation)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_SCROLL_SPEED_1, background_cloud_scroll_speed_1)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_SCROLL_SPEED_2, background_cloud_scroll_speed_2)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_CENTER_POS, background_cloud_center_pos)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_POSITION_IMPACT, background_cloud_position_impact)
	shader_material.set_shader_parameter(_BACKGROUND_SHADER_CLOUD_STRENGTH, background_cloud_strength)


# --- 私有/辅助方法 ---

func _get_shader_material(rect: ColorRect) -> ShaderMaterial:
	var material_value: Material = rect.material
	if material_value is ShaderMaterial:
		var shader_material: ShaderMaterial = material_value
		return shader_material
	return null
