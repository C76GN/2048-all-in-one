## LimitedMoveLevelProgressSaveData: 原创限步关卡的严格 SaveGraph section。
##
## 关卡进度与普通统计隔离；任何关卡包版本或内容语义漂移都由项目层进度系统
## 显式拒绝或重建，避免 GFLevelProgressModel 接收半兼容数据。
class_name LimitedMoveLevelProgressSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const RESULT_SCHEMA_VERSION: int = 1
const _PROGRESS_KEYS: PackedStringArray = [
	"unlocked_levels",
	"completed_levels",
	"level_results",
]
const _RESULT_KEYS: PackedStringArray = [
	"schema_version",
	"pack_version",
	"content_fingerprint",
	"best_moves",
	"best_score",
	"target_tile_value",
	"first_completed_at",
	"last_completed_at",
	"completion_count",
]


# --- 私有变量 ---

var _progress: Dictionary = _make_empty_progress()


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.LIMITED_LEVELS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	return {
		"pack_id": String(LimitedMoveLevelDefinition.PACK_ID),
		"pack_version": LimitedMoveLevelDefinition.PACK_VERSION,
		"progress": _progress.duplicate(true),
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 3:
		return ERR_INVALID_DATA
	if not (
		GFVariantData.get_option_value(data, "pack_id") is String
		and GFVariantData.get_option_value(data, "pack_version") is int
		and GFVariantData.get_option_value(data, "progress") is Dictionary
	):
		return ERR_INVALID_DATA
	if (
		GFVariantData.get_option_string_name(data, "pack_id")
		!= LimitedMoveLevelDefinition.PACK_ID
		or GFVariantData.get_option_int(data, "pack_version")
		!= LimitedMoveLevelDefinition.PACK_VERSION
	):
		return ERR_INVALID_DATA

	var next_progress: Dictionary = GFVariantData.get_option_dictionary(
		data,
		"progress"
	).duplicate(true)
	if not _is_progress_valid(next_progress):
		return ERR_INVALID_DATA
	_progress = next_progress
	return OK


# --- 公共方法 ---

static func make_section_data(progress: Dictionary) -> Dictionary:
	return {
		"pack_id": String(LimitedMoveLevelDefinition.PACK_ID),
		"pack_version": LimitedMoveLevelDefinition.PACK_VERSION,
		"progress": progress.duplicate(true),
	}


static func make_empty_section_data() -> Dictionary:
	return make_section_data(_make_empty_progress())


# --- 私有/辅助方法 ---

static func _make_empty_progress() -> Dictionary:
	return {
		"unlocked_levels": {},
		"completed_levels": {},
		"level_results": {},
	}


static func _is_progress_valid(progress: Dictionary) -> bool:
	if not _has_exact_string_keys(progress, _PROGRESS_KEYS):
		return false
	var unlocked_value: Variant = progress.get("unlocked_levels")
	var completed_value: Variant = progress.get("completed_levels")
	var results_value: Variant = progress.get("level_results")
	if not (
		unlocked_value is Dictionary
		and completed_value is Dictionary
		and results_value is Dictionary
	):
		return false
	var unlocked: Dictionary = unlocked_value
	var completed: Dictionary = completed_value
	var results: Dictionary = results_value
	if unlocked.is_empty() and completed.is_empty() and results.is_empty():
		return true
	if not (
		_is_true_level_set_valid(unlocked)
		and _is_true_level_set_valid(completed)
		and _are_level_results_valid(results)
	):
		return false

	var unlocked_count: int = unlocked.size()
	var completed_count: int = completed.size()
	if (
		completed_count > LimitedMoveLevelCatalogUtility.EXPECTED_LEVEL_COUNT
		or unlocked_count
		!= mini(
			completed_count + 1,
			LimitedMoveLevelCatalogUtility.EXPECTED_LEVEL_COUNT
		)
		or results.size() != completed_count
	):
		return false
	for index: int in range(unlocked_count):
		if not unlocked.has(_level_id_for_index(index)):
			return false
	for index: int in range(completed_count):
		var level_id: String = _level_id_for_index(index)
		if not completed.has(level_id) or not results.has(level_id):
			return false
	return true


static func _is_true_level_set_valid(level_set: Dictionary) -> bool:
	for key: Variant in level_set.keys():
		if (
			not key is String
			or not _is_known_level_id(key)
			or not (level_set[key] is bool)
			or not level_set[key]
		):
			return false
	return true


static func _are_level_results_valid(results: Dictionary) -> bool:
	for key: Variant in results.keys():
		if not key is String or not _is_known_level_id(key):
			return false
		var result_value: Variant = results[key]
		if not result_value is Dictionary:
			return false
		var result: Dictionary = result_value
		if not _has_exact_string_keys(result, _RESULT_KEYS):
			return false
		if not (
			result.get("schema_version") is int
			and result.get("pack_version") is int
			and result.get("content_fingerprint") is String
			and result.get("best_moves") is int
			and result.get("best_score") is int
			and result.get("target_tile_value") is int
			and result.get("first_completed_at") is int
			and result.get("last_completed_at") is int
			and result.get("completion_count") is int
		):
			return false
		var first_completed_at: int = result["first_completed_at"]
		var last_completed_at: int = result["last_completed_at"]
		if (
			result["schema_version"] != RESULT_SCHEMA_VERSION
			or result["pack_version"] != LimitedMoveLevelDefinition.PACK_VERSION
			or not _is_sha256(result["content_fingerprint"])
			or result["best_moves"] <= 0
			or result["best_score"] < 0
			or result["target_tile_value"] <= 1
			or first_completed_at <= 0
			or last_completed_at < first_completed_at
			or result["completion_count"] <= 0
		):
			return false
	return true


static func _has_exact_string_keys(
	data: Dictionary,
	expected_keys: PackedStringArray
) -> bool:
	if data.size() != expected_keys.size():
		return false
	for key: Variant in data.keys():
		if not key is String or not expected_keys.has(key):
			return false
	return true


static func _is_known_level_id(level_id: String) -> bool:
	for index: int in range(
		LimitedMoveLevelCatalogUtility.EXPECTED_LEVEL_COUNT
	):
		if level_id == _level_id_for_index(index):
			return true
	return false


static func _level_id_for_index(index: int) -> String:
	return "%s%02d" % [LimitedMoveLevelDefinition.LEVEL_ID_PREFIX, index + 1]


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true
