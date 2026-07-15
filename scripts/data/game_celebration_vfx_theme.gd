## GameCelebrationVfxTheme: 定义主题可切换的庆祝特效资源与事件 preset。
class_name GameCelebrationVfxTheme
extends Resource


# --- 常量 ---

const EVENT_TARGET_REACHED: StringName = &"target_reached"
const EVENT_NEW_RECORD: StringName = &"new_record"


# --- 导出变量 ---

@export var shader_asset_key: StringName = &""
@export var shader_parameter_profile: GFShaderParameterProfile
@export var presets: Dictionary = {}


# --- 公共方法 ---

## 获取事件对应的庆祝特效 preset。
## @param event_id: 庆祝事件标识。
func get_preset(event_id: StringName) -> GameCelebrationVfxPreset:
	var value: Variant = presets.get(event_id)
	if value is GameCelebrationVfxPreset:
		var preset: GameCelebrationVfxPreset = value
		return preset
	return null


## 生成主题资源校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameCelebrationVfxTheme",
		{
			"resource_path": resource_path,
			"shader_asset_key": shader_asset_key,
		}
	)
	if shader_asset_key == &"":
		_add_error(report, &"missing_shader_asset_key", "shader_asset_key 未配置。", &"shader_asset_key")
	if shader_parameter_profile == null:
		_add_error(report, &"missing_shader_profile", "shader_parameter_profile 未配置。", &"shader_parameter_profile")
	_validate_required_preset(report, EVENT_TARGET_REACHED)
	_validate_required_preset(report, EVENT_NEW_RECORD)
	return report


# --- 私有/辅助方法 ---

func _validate_required_preset(report: GFValidationReport, event_id: StringName) -> void:
	var preset: GameCelebrationVfxPreset = get_preset(event_id)
	if preset == null:
		_add_error(
			report,
			&"missing_event_preset",
			"缺少庆祝事件 preset：%s。" % String(event_id),
			event_id
		)
		return
	if preset.duration <= 0.0:
		_add_error(
			report,
			&"invalid_event_duration",
			"庆祝事件时长必须大于 0：%s。" % String(event_id),
			event_id
		)


func _add_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
