## GameModeVisualProfile: 某个玩法模式的稳定默认视觉配置。
##
## 该资源只归 themes 所有；gameplay 仅通过 StringName profile id 选择它，
## 从而避免模式规则资源直接引用表现资源。
class_name GameModeVisualProfile
extends Resource


@export var profile_id: StringName = &""
@export var board_theme: BoardTheme
@export var color_schemes: Dictionary = {}


## 返回复制隔离的有效色阶字典，调用方不能改写注册表真源。
func get_color_schemes_copy() -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in color_schemes.keys():
		var scheme_value: Variant = color_schemes[key]
		if key is int and scheme_value is TileColorScheme:
			result[key] = scheme_value
	return result


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameModeVisualProfile:%s" % String(profile_id),
		{
			"profile_id": profile_id,
			"resource_path": resource_path,
		}
	)
	if profile_id == &"":
		_add_error(report, &"missing_profile_id", "profile_id 不能为空。", &"profile_id")
	if not is_instance_valid(board_theme):
		_add_error(report, &"missing_board_theme", "board_theme 未配置。", &"board_theme")
	if color_schemes.is_empty():
		_add_error(report, &"empty_color_schemes", "color_schemes 不能为空。", &"color_schemes")
	for key: Variant in color_schemes.keys():
		if not key is int:
			_add_error(
				report,
				&"invalid_color_scheme_index",
				"color_schemes 的键必须是非负整数。",
				key
			)
			continue
		var scheme_index: int = key
		if scheme_index < 0:
			_add_error(
				report,
				&"invalid_color_scheme_index",
				"color_schemes 的键必须是非负整数。",
				key
			)
			continue
		if not color_schemes[key] is TileColorScheme:
			_add_error(
				report,
				&"invalid_color_scheme",
				"color_schemes 中存在非 TileColorScheme 资源。",
				key
			)
	return report


# --- 私有/辅助方法 ---

func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
