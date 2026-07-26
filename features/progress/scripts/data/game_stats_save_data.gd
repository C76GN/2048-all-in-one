## GameStatsSaveData: progress Feature 的严格 SaveGraph section。
class_name GameStatsSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 5
const MAX_RECENT_RESULTS: int = 128
const MAX_LEADERBOARD_ENTRIES: int = 50
const MAX_LEADERBOARD_GROUPS: int = 256


# --- 私有变量 ---

var _stats: Dictionary = {}
var _results: Array[Dictionary] = []
var _leaderboards: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.PROGRESS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	return {
		"stats": _stats.duplicate(true),
		"results": _results.duplicate(true),
		"leaderboards": _leaderboards.duplicate(true),
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 3:
		return ERR_INVALID_DATA
	var stats_value: Variant = GFVariantData.get_option_value(data, "stats")
	var results_value: Variant = GFVariantData.get_option_value(data, "results")
	var leaderboards_value: Variant = GFVariantData.get_option_value(
		data,
		"leaderboards"
	)
	if not (
		stats_value is Dictionary
		and results_value is Array
		and leaderboards_value is Dictionary
	):
		return ERR_INVALID_DATA

	var next_results: Array[Dictionary] = []
	for result_value: Variant in GFVariantData.as_array(results_value):
		if not result_value is Dictionary:
			return ERR_INVALID_DATA
		var result_data: Dictionary = result_value
		var result: GameResultRecordedData = GameResultRecordedData.from_dict(
			result_data
		)
		if result == null:
			return ERR_INVALID_DATA
		next_results.append(result.to_dict())
	if next_results.size() > MAX_RECENT_RESULTS:
		return ERR_INVALID_DATA

	var next_leaderboards: Dictionary = GFVariantData.as_dictionary(
		leaderboards_value
	).duplicate(true)
	if not _are_leaderboards_valid(next_leaderboards):
		return ERR_INVALID_DATA

	_stats = GFVariantData.as_dictionary(stats_value).duplicate(true)
	_results = next_results
	_leaderboards = next_leaderboards
	return OK


# --- 私有/辅助方法 ---

static func _are_leaderboards_valid(leaderboards: Dictionary) -> bool:
	if leaderboards.size() > MAX_LEADERBOARD_GROUPS:
		return false
	for group_key_value: Variant in leaderboards.keys():
		if not group_key_value is String:
			return false
		var group_key: String = group_key_value
		var bucket_value: Variant = leaderboards[group_key_value]
		if not bucket_value is Dictionary:
			return false
		var bucket: Dictionary = bucket_value
		if not (
			bucket.size() == 2
			and GFVariantData.get_option_value(bucket, &"identity") is Dictionary
			and GFVariantData.get_option_value(bucket, &"entries") is Array
		):
			return false
		var identity: Dictionary = GFVariantData.get_option_dictionary(
			bucket,
			&"identity"
		)
		if (
			not GameResultRecordedData.is_leaderboard_identity_valid(identity)
			or GameResultRecordedData.calculate_leaderboard_group_key(identity)
			!= group_key
		):
			return false
		var entries: Array = GFVariantData.get_option_array(bucket, &"entries")
		if entries.size() > MAX_LEADERBOARD_ENTRIES:
			return false
		for entry_value: Variant in entries:
			if not entry_value is Dictionary:
				return false
			var entry_data: Dictionary = entry_value
			var result: GameResultRecordedData = GameResultRecordedData.from_dict(
				entry_data
			)
			if (
				result == null
				or not result.is_competition_eligible()
				or result.get_leaderboard_group_key() != group_key
				or result.get_leaderboard_identity() != identity
			):
				return false
	return true
