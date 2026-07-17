## GameStatsSaveData: progress Feature 的严格 SaveGraph section。
class_name GameStatsSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 3


# --- 私有变量 ---

var _stats: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.PROGRESS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	return {
		"stats": _stats.duplicate(true),
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var stats_value: Variant = GFVariantData.get_option_value(data, "stats")
	if not (stats_value is Dictionary):
		return ERR_INVALID_DATA

	_stats = GFVariantData.as_dictionary(stats_value).duplicate(true)
	return OK
