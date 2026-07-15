## GameTheme: 定义一套完整游戏主题的视觉与音频资源。
class_name GameTheme
extends Resource


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""

@export var board_theme: BoardTheme
@export var color_schemes: Dictionary = {}
@export var ui_palette: GameUiPalette
@export var audio_theme: GameAudioTheme
@export var background_shader_profile: GFShaderParameterProfile
@export var celebration_vfx_theme: GameCelebrationVfxTheme
@export var scene_transition_cover_effect: GFScreenTransitionEffect
@export var scene_transition_reveal_effect: GFScreenTransitionEffect


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


## 获取背景 Profile 中声明的基础颜色。
## @param fallback: Profile 缺少 base_color 时使用的颜色。
func get_background_base_color(fallback: Color = Color.WHITE) -> Color:
	if background_shader_profile == null:
		return fallback
	var value: Variant = background_shader_profile.get_parameter(&"base_color", fallback)
	if value is Color:
		var color: Color = value
		return color
	return fallback


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
