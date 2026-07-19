## GameUiPalette: 定义一套主题可切换的通用 UI 色板。
class_name GameUiPalette
extends Resource


# --- 导出变量 ---

@export var text_primary_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
@export var text_secondary_color: Color = Color(0.4, 0.35686275, 0.32156864, 0.96)
@export var text_shadow_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.52)

@export_group("Typography")
@export var body_font: Font
@export var display_font: Font
@export var numeric_font: Font

@export_group("Buttons")

@export var button_normal_color: Color = Color(1.0, 0.972549, 0.9098039, 0.96)
@export var button_hover_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
@export var button_pressed_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
@export var button_focus_border_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
@export var button_disabled_color: Color = Color(0.95686275, 0.92941177, 0.8666667, 0.46)
@export var button_font_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
@export var button_font_disabled_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.42)
@export var primary_button_color: Color = Color(0.49411765, 0.79607844, 0.827451, 1.0)
@export var primary_button_hover_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
@export var primary_button_pressed_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
@export var quiet_button_hover_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.08)

@export_group("Fields")

@export var field_surface_color: Color = Color(1.0, 0.972549, 0.9098039, 0.94)
@export var field_focus_surface_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.88)
@export var field_border_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.72)
@export var field_focus_border_color: Color = Color(0.8745098, 0.29411766, 0.6039216, 1.0)

@export var panel_surface_color: Color = Color(1.0, 0.972549, 0.9098039, 0.88)
@export var selected_surface_color: Color = Color(0.8745098, 0.29411766, 0.6039216, 0.72)
@export var selected_border_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)

@export var slider_track_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 0.42)
@export var slider_grabber_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.92)
@export var slider_grabber_highlight_color: Color = Color(0.8745098, 0.29411766, 0.6039216, 0.88)

@export var button_focus_shader_profile: GFShaderParameterProfile


# --- 公共方法 ---

## 生成 UI 色板校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameUiPalette",
		{"resource_path": resource_path}
	)
	if body_font == null:
		_add_error(report, &"missing_body_font", "body_font 未配置。", &"body_font")
	else:
		_validate_export_font(report, body_font, &"body_font", true)
	if display_font == null:
		_add_error(report, &"missing_display_font", "display_font 未配置。", &"display_font")
	else:
		_validate_export_font(report, display_font, &"display_font", false)
	if numeric_font == null:
		_add_error(report, &"missing_numeric_font", "numeric_font 未配置。", &"numeric_font")
	else:
		_validate_export_font(report, numeric_font, &"numeric_font", false)
	if button_focus_shader_profile == null:
		_add_error(
			report,
			&"missing_button_focus_shader_profile",
			"button_focus_shader_profile 未配置。",
			&"button_focus_shader_profile"
		)
	elif button_focus_shader_profile.get_parameter_names().is_empty():
		_add_error(
			report,
			&"empty_button_focus_shader_profile",
			"button_focus_shader_profile 未声明任何参数。",
			&"button_focus_shader_profile"
		)
	return report


# --- 私有/辅助方法 ---

func _add_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)


func _validate_export_font(
	report: GFValidationReport,
	font: Font,
	property_name: StringName,
	require_cjk: bool
) -> void:
	if font is SystemFont:
		_add_error(
			report,
			&"system_font_not_export_safe",
			"%s 不能使用跨平台不可控的 SystemFont。" % property_name,
			property_name
		)
	if not font.has_char("2".unicode_at(0)):
		_add_error(
			report,
			&"missing_numeric_glyph",
			"%s 缺少基础数字字形。" % property_name,
			property_name
		)
	if require_cjk and not font.has_char("中".unicode_at(0)):
		_add_error(
			report,
			&"missing_cjk_glyph",
			"%s 缺少简体中文字形。" % property_name,
			property_name
		)
