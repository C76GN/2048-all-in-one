## AchievementProgressRecord: 一个成就的严格本地进度记录。
class_name AchievementProgressRecord
extends Resource


# --- 公共变量 ---

var achievement_id: StringName = &""
var criteria_fingerprint: String = ""
var current_value: int = 0
var completed_at: int = 0
var last_progress_at: int = 0


# --- 公共方法 ---

func to_dict() -> Dictionary:
	return {
		"achievement_id": String(achievement_id),
		"criteria_fingerprint": criteria_fingerprint,
		"current_value": current_value,
		"completed_at": completed_at,
		"last_progress_at": last_progress_at,
	}


func duplicate_record() -> AchievementProgressRecord:
	return from_dict(to_dict())


## 创建并校验一个进度记录。
## @param p_achievement_id: 成就定义的稳定标识。
## @param p_criteria_fingerprint: 当前达成条件的内容指纹。
## @param p_current_value: 已持久化的单调进度值。
## @param p_completed_at: 达成时间；未达成时必须为 0。
## @param p_last_progress_at: 最近一次进度变化时间。
static func create(
	p_achievement_id: StringName,
	p_criteria_fingerprint: String,
	p_current_value: int = 0,
	p_completed_at: int = 0,
	p_last_progress_at: int = 0
) -> AchievementProgressRecord:
	var record: AchievementProgressRecord = AchievementProgressRecord.new()
	record.achievement_id = p_achievement_id
	record.criteria_fingerprint = p_criteria_fingerprint
	record.current_value = p_current_value
	record.completed_at = p_completed_at
	record.last_progress_at = p_last_progress_at
	return record if record.is_valid_record() else null


## 从严格字典恢复进度记录。
## @param data: 只包含当前 schema 字段的记录字典。
static func from_dict(data: Dictionary) -> AchievementProgressRecord:
	if data.size() != 5:
		return null
	if not (
		GFVariantData.get_option_value(data, "achievement_id") is String
		and GFVariantData.get_option_value(data, "criteria_fingerprint") is String
		and GFVariantData.get_option_value(data, "current_value") is int
		and GFVariantData.get_option_value(data, "completed_at") is int
		and GFVariantData.get_option_value(data, "last_progress_at") is int
	):
		return null
	return create(
		GFVariantData.get_option_string_name(data, "achievement_id"),
		GFVariantData.get_option_string(data, "criteria_fingerprint"),
		GFVariantData.get_option_int(data, "current_value"),
		GFVariantData.get_option_int(data, "completed_at"),
		GFVariantData.get_option_int(data, "last_progress_at")
	)


func is_valid_record() -> bool:
	if (
		achievement_id == &""
		or criteria_fingerprint.is_empty()
		or current_value < 0
		or completed_at < 0
		or last_progress_at < 0
	):
		return false
	if current_value == 0:
		return completed_at == 0 and last_progress_at == 0
	return last_progress_at > 0
