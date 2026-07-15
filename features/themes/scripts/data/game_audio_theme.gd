## GameAudioTheme: 定义可切换的主题音效银行和事件 ID。
class_name GameAudioTheme
extends Resource


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var audio_bank_id: StringName = &""
@export var audio_bank: GFAudioBank

@export var ui_select_event: StringName = &"ui/select"
@export var ui_confirm_event: StringName = &"ui/confirm"
@export var tile_spawn_event: StringName = &"tile/spawn"
@export var tile_move_event: StringName = &"tile/move"
@export var tile_merge_event: StringName = &"tile/merge"
@export var game_over_event: StringName = &"game/over"


# --- 公共方法 ---

func get_display_text() -> String:
	if not display_name_key.is_empty():
		return tr(display_name_key)
	if theme_id != &"":
		return String(theme_id)
	return tr("UI_UNKNOWN")


func get_resolved_bank_id() -> StringName:
	if audio_bank_id != &"":
		return audio_bank_id
	return theme_id


## 生成音效主题及其 GF 音频银行校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameAudioTheme:%s" % String(theme_id),
		{
			"resource_path": resource_path,
			"theme_id": theme_id,
			"audio_bank_id": get_resolved_bank_id(),
		}
	)
	if theme_id == &"":
		_add_error(report, &"missing_sound_theme_id", "theme_id 未配置。", &"theme_id")
	if get_resolved_bank_id() == &"":
		_add_error(report, &"missing_audio_bank_id", "audio_bank_id 未配置。", &"audio_bank_id")
	if not is_instance_valid(audio_bank):
		_add_error(report, &"missing_audio_bank", "audio_bank 未配置。", &"audio_bank")
		return report

	var bank_report: GFValidationReport = audio_bank.validate_bank(true)
	var _bank_merge: RefCounted = report.merge(bank_report, false)
	if not bank_report.is_healthy():
		_add_error(
			report,
			&"unhealthy_audio_bank",
			"audio_bank 包含错误或警告，不能作为运行时音效主题。",
			&"audio_bank"
		)
	var required_events: Dictionary = _get_required_events()
	for raw_event_field: Variant in required_events.keys():
		var event_field: StringName = GFVariantData.to_string_name(raw_event_field)
		var event_id: StringName = GFVariantData.to_string_name(required_events[raw_event_field])
		if event_id == &"":
			_add_error(report, &"missing_audio_event_id", "音效事件 ID 未配置。", event_field)
		elif not audio_bank.has_clip(event_id):
			_add_error(
				report,
				&"unresolved_audio_event",
				"音频银行缺少主题事件：%s。" % String(event_id),
				event_field
			)
	return report


# --- 私有/辅助方法 ---

func _get_required_events() -> Dictionary:
	return {
		&"ui_select_event": ui_select_event,
		&"ui_confirm_event": ui_confirm_event,
		&"tile_spawn_event": tile_spawn_event,
		&"tile_move_event": tile_move_event,
		&"tile_merge_event": tile_merge_event,
		&"game_over_event": game_over_event,
	}


func _add_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
