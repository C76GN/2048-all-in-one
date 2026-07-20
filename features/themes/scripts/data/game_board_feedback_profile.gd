## GameBoardFeedbackProfile: 定义视觉主题的棋盘冲击与触觉反馈预设。
class_name GameBoardFeedbackProfile
extends Resource


# --- 常量 ---

const TIER_MOVE: StringName = &"move"
const TIER_MERGE: StringName = &"merge"
const TIER_HIGH_MERGE: StringName = &"high_merge"
const TIER_RECORD: StringName = &"record"


# --- 导出变量 ---

@export var move_shake: GFShakePreset
@export var merge_shake: GFShakePreset
@export var high_merge_shake: GFShakePreset
@export var record_shake: GFShakePreset
@export var move_haptic: GFHapticPreset
@export var merge_haptic: GFHapticPreset
@export var high_merge_haptic: GFHapticPreset
@export var record_haptic: GFHapticPreset


# --- 公共方法 ---

## 获取指定语义等级的 GF Shake 预设。
## @param tier_id: 稳定反馈等级 ID。
func get_shake_preset(tier_id: StringName) -> GFShakePreset:
	match tier_id:
		TIER_MOVE:
			return move_shake
		TIER_MERGE:
			return merge_shake
		TIER_HIGH_MERGE:
			return high_merge_shake
		TIER_RECORD:
			return record_shake
		_:
			return null


## 获取指定语义等级的 GF Haptic 预设。
## @param tier_id: 稳定反馈等级 ID。
func get_haptic_preset(tier_id: StringName) -> GFHapticPreset:
	match tier_id:
		TIER_MOVE:
			return move_haptic
		TIER_MERGE:
			return merge_haptic
		TIER_HIGH_MERGE:
			return high_merge_haptic
		TIER_RECORD:
			return record_haptic
		_:
			return null


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameBoardFeedbackProfile",
		{"resource_path": resource_path}
	)
	_validate_tier(report, TIER_MOVE, move_shake, move_haptic)
	_validate_tier(report, TIER_MERGE, merge_shake, merge_haptic)
	_validate_tier(report, TIER_HIGH_MERGE, high_merge_shake, high_merge_haptic)
	_validate_tier(report, TIER_RECORD, record_shake, record_haptic)
	return report


# --- 私有/辅助方法 ---

func _validate_tier(
	report: GFValidationReport,
	tier_id: StringName,
	shake_preset: GFShakePreset,
	haptic_preset: GFHapticPreset
) -> void:
	if shake_preset == null:
		var _missing_shake: RefCounted = report.add_error(
			&"missing_shake_preset",
			"反馈等级缺少 GFShakePreset。",
			tier_id,
			resource_path
		)
	elif shake_preset.get_duration_seconds() <= 0.0:
		var _invalid_shake: RefCounted = report.add_error(
			&"invalid_shake_duration",
			"反馈等级的 GFShakePreset 持续时间必须大于 0。",
			tier_id,
			resource_path
		)

	if haptic_preset == null:
		var _missing_haptic: RefCounted = report.add_error(
			&"missing_haptic_preset",
			"反馈等级缺少 GFHapticPreset。",
			tier_id,
			resource_path
		)
	elif haptic_preset.get_duration_seconds() <= 0.0:
		var _invalid_haptic: RefCounted = report.add_error(
			&"invalid_haptic_duration",
			"反馈等级的 GFHapticPreset 持续时间必须大于 0。",
			tier_id,
			resource_path
		)
