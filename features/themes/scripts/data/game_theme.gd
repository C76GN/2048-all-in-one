## GameTheme: 定义一套完整游戏主题的视觉与音频资源。
class_name GameTheme
extends Resource


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""

@export var board_theme: BoardTheme
@export var color_schemes: Dictionary = {}
@export var tile_visual_theme: TileVisualTheme
@export var ui_palette: GameUiPalette
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


## 生成完整视觉主题校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameTheme:%s" % String(theme_id),
		{
			"resource_path": resource_path,
			"theme_id": theme_id,
		}
	)
	if theme_id == &"":
		_add_error(report, &"missing_theme_id", "theme_id 未配置。", &"theme_id")
	if not is_instance_valid(board_theme):
		_add_error(report, &"missing_board_theme", "board_theme 未配置。", &"board_theme")
	_validate_color_schemes(report)
	if not is_instance_valid(tile_visual_theme):
		_add_error(
			report,
			&"missing_tile_visual_theme",
			"tile_visual_theme 未配置。",
			&"tile_visual_theme"
		)
	else:
		var _tile_visual_report: RefCounted = report.merge(
			tile_visual_theme.get_validation_report(),
			false
		)
	if not is_instance_valid(ui_palette):
		_add_error(report, &"missing_ui_palette", "ui_palette 未配置。", &"ui_palette")
	else:
		var _palette_report: RefCounted = report.merge(ui_palette.get_validation_report(), false)
	if background_shader_profile == null:
		_add_error(
			report,
			&"missing_background_shader_profile",
			"background_shader_profile 未配置。",
			&"background_shader_profile"
		)
	elif background_shader_profile.get_parameter_names().is_empty():
		_add_error(
			report,
			&"empty_background_shader_profile",
			"background_shader_profile 未声明任何参数。",
			&"background_shader_profile"
		)
	if not is_instance_valid(celebration_vfx_theme):
		_add_error(
			report,
			&"missing_celebration_vfx_theme",
			"celebration_vfx_theme 未配置。",
			&"celebration_vfx_theme"
		)
	else:
		var _celebration_report: RefCounted = report.merge(
			celebration_vfx_theme.get_validation_report(),
			false
		)
	if not is_instance_valid(scene_transition_cover_effect):
		_add_error(
			report,
			&"missing_cover_transition",
			"scene_transition_cover_effect 未配置。",
			&"scene_transition_cover_effect"
		)
	if not is_instance_valid(scene_transition_reveal_effect):
		_add_error(
			report,
			&"missing_reveal_transition",
			"scene_transition_reveal_effect 未配置。",
			&"scene_transition_reveal_effect"
		)
	return report


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


## 获取当前主题完整的方块身份视觉目录。
func get_tile_visual_theme() -> TileVisualTheme:
	return tile_visual_theme


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


# --- 私有/辅助方法 ---

func _validate_color_schemes(report: GFValidationReport) -> void:
	if color_schemes.is_empty():
		_add_error(report, &"empty_color_schemes", "color_schemes 为空。", &"color_schemes")
		return
	for key: Variant in color_schemes.keys():
		if not (color_schemes[key] is TileColorScheme):
			_add_error(
				report,
				&"invalid_color_scheme",
				"color_schemes 中存在非 TileColorScheme 资源。",
				key
			)


func _add_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
