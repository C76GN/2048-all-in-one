## AchievementSaveData: achievements Feature 的严格 SaveGraph section。
class_name AchievementSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 1


# --- 私有变量 ---

var _records: Array[AchievementProgressRecord] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var records: Array[Dictionary] = []
	for record: AchievementProgressRecord in _records:
		if record != null:
			records.append(record.to_dict())
	return {"records": records}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var records_value: Variant = GFVariantData.get_option_value(data, "records")
	if not records_value is Array:
		return ERR_INVALID_DATA

	var next_records: Array[AchievementProgressRecord] = []
	var seen_ids: Dictionary = {}
	for record_value: Variant in GFVariantData.as_array(records_value):
		if not record_value is Dictionary:
			return ERR_INVALID_DATA
		var record: AchievementProgressRecord = AchievementProgressRecord.from_dict(
			GFVariantData.as_dictionary(record_value)
		)
		if record == null or seen_ids.has(record.achievement_id):
			return ERR_INVALID_DATA
		seen_ids[record.achievement_id] = true
		next_records.append(record)
	next_records.sort_custom(_is_record_before)
	_records = next_records
	return OK


# --- 私有/辅助方法 ---

static func _is_record_before(
	left: AchievementProgressRecord,
	right: AchievementProgressRecord
) -> bool:
	return String(left.achievement_id) < String(right.achievement_id)
