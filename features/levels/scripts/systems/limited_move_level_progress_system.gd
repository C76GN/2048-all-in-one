## LimitedMoveLevelProgressSystem: 原创限步关卡进度与顺序解锁的唯一写入者。
class_name LimitedMoveLevelProgressSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "LimitedMoveLevelProgressSystem"


# --- 私有变量 ---

var _progress: GFLevelProgressModel
var _levels: GFLevelUtility
var _catalog: LimitedMoveLevelCatalogUtility
var _save_graph: GameSaveGraphUtility
var _clock: GameClockUtility
var _log: GFLogUtility


# --- GF 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GFLevelProgressModel]


func get_required_utilities() -> Array[Script]:
	return [
		GFLevelUtility,
		LimitedMoveLevelCatalogUtility,
		GameSaveGraphUtility,
		GameClockUtility,
		GFLogUtility,
	]


func ready() -> void:
	_progress = _get_progress_model()
	_levels = _get_level_utility()
	_catalog = _get_catalog_utility()
	_save_graph = _get_save_graph_utility()
	_clock = _get_clock_utility()
	_log = _get_log_utility()
	_restore_or_initialize_progress()


func dispose() -> void:
	_progress = null
	_levels = null
	_catalog = null
	_save_graph = null
	_clock = null
	_log = null


# --- 公共方法 ---

func is_level_unlocked(level_id: StringName) -> bool:
	return (
		is_instance_valid(_progress)
		and _progress.is_level_unlocked(level_id)
	)


func is_level_completed(level_id: StringName) -> bool:
	return (
		is_instance_valid(_progress)
		and _progress.is_level_completed(level_id)
	)


func get_level_result(level_id: StringName) -> Dictionary:
	if not is_instance_valid(_progress):
		return {}
	return _progress.get_level_result(level_id)


func is_level_identity_current(
	level_id: StringName,
	pack_version: int,
	content_fingerprint: String
) -> bool:
	if (
		not is_instance_valid(_catalog)
		or pack_version != LimitedMoveLevelDefinition.PACK_VERSION
	):
		return false
	var definition: LimitedMoveLevelDefinition = _catalog.get_definition(level_id)
	return (
		is_instance_valid(definition)
		and definition.get_content_fingerprint() == content_fingerprint
	)


## 成功完成当前关卡，并原子持久化 GF 进度后才派发胜利信号。
func complete_current_level(
	definition: LimitedMoveLevelDefinition,
	score: int,
	moves: int,
	highest_tile: int
) -> Error:
	if not (
		is_instance_valid(definition)
		and is_instance_valid(_progress)
		and is_instance_valid(_levels)
		and is_instance_valid(_save_graph)
		and _levels.current_level_id == definition.level_id
		and is_level_unlocked(definition.level_id)
		and definition.is_completed(highest_tile)
		and moves > 0
		and moves <= definition.move_limit
	):
		return ERR_INVALID_DATA

	var previous_progress: Dictionary = _progress.to_dict()
	var previous_result: Dictionary = _progress.get_level_result(
		definition.level_id
	)
	var now: int = maxi(_clock.get_unix_timestamp(), 1)
	var first_completed_at: int = GFVariantData.get_option_int(
		previous_result,
		"first_completed_at",
		now
	)
	var previous_best_moves: int = GFVariantData.get_option_int(
		previous_result,
		"best_moves",
		0
	)
	var result: Dictionary = {
		"schema_version": LimitedMoveLevelProgressSaveData.RESULT_SCHEMA_VERSION,
		"pack_version": definition.pack_version,
		"content_fingerprint": definition.get_content_fingerprint(),
		"best_moves": (
			moves
			if previous_best_moves <= 0
			else mini(previous_best_moves, moves)
		),
		"best_score": maxi(
			GFVariantData.get_option_int(previous_result, "best_score", 0),
			maxi(score, 0)
		),
		"target_tile_value": definition.target_tile_value,
		"first_completed_at": first_completed_at,
		"last_completed_at": now,
		"completion_count": (
			GFVariantData.get_option_int(
				previous_result,
				"completion_count",
				0
			)
			+ 1
		),
	}
	_levels.complete_current_level(result, true, false)
	var save_error: Error = _save_progress()
	if save_error != OK:
		_progress.from_dict(previous_progress)
		return save_error
	_levels.win_current_level()
	return OK


func lose_current_level(definition: LimitedMoveLevelDefinition) -> Error:
	if not (
		is_instance_valid(definition)
		and is_instance_valid(_levels)
		and _levels.current_level_id == definition.level_id
	):
		return ERR_INVALID_DATA
	_levels.lose_current_level()
	return OK


# --- 私有/辅助方法 ---

func _restore_or_initialize_progress() -> void:
	if not (
		is_instance_valid(_progress)
		and is_instance_valid(_catalog)
		and is_instance_valid(_save_graph)
	):
		push_error("[LimitedMoveLevelProgressSystem] 依赖未注册。")
		return
	var section: Dictionary = _save_graph.get_section_data(
		GameSaveGraphUtility.LIMITED_LEVELS_SECTION_ID
	)
	var stored_progress: Dictionary = GFVariantData.get_option_dictionary(
		section,
		"progress"
	)
	_progress.from_dict(stored_progress)
	var changed: bool = false
	if not _is_model_semantically_current():
		_progress.clear_progress()
		changed = true
		if is_instance_valid(_log):
			_log.info(_LOG_TAG, "限步关卡包语义已变化；仅重建关卡进度。")
	var first_level_id: StringName = _catalog.get_first_level_id()
	if (
		first_level_id != &""
		and not _progress.is_level_unlocked(first_level_id)
	):
		_progress.unlock_level(first_level_id)
		changed = true
	if not changed:
		return
	var save_error: Error = _save_progress()
	if save_error != OK:
		push_error(
			"[LimitedMoveLevelProgressSystem] 初始化关卡进度失败，错误码：%d。"
			% save_error
		)


func _is_model_semantically_current() -> bool:
	var progress_data: Dictionary = _progress.to_dict()
	var completed: Dictionary = GFVariantData.get_option_dictionary(
		progress_data,
		"completed_levels"
	)
	var results: Dictionary = GFVariantData.get_option_dictionary(
		progress_data,
		"level_results"
	)
	for level_id_value: Variant in completed.keys():
		var level_id: StringName = StringName(str(level_id_value))
		var definition: LimitedMoveLevelDefinition = _catalog.get_definition(
			level_id
		)
		var result: Dictionary = GFVariantData.get_option_dictionary(
			results,
			String(level_id)
		)
		if (
			not is_instance_valid(definition)
			or GFVariantData.get_option_int(result, "pack_version")
			!= definition.pack_version
			or GFVariantData.get_option_string(
				result,
				"content_fingerprint"
			) != definition.get_content_fingerprint()
			or GFVariantData.get_option_int(
				result,
				"target_tile_value"
			) != definition.target_tile_value
		):
			return false
	return true


func _save_progress() -> Error:
	return _save_graph.replace_section_data(
		GameSaveGraphUtility.LIMITED_LEVELS_SECTION_ID,
		LimitedMoveLevelProgressSaveData.make_section_data(_progress.to_dict())
	)


func _get_progress_model() -> GFLevelProgressModel:
	var value: Object = get_model(GFLevelProgressModel)
	return value if value is GFLevelProgressModel else null


func _get_level_utility() -> GFLevelUtility:
	var value: Object = get_utility(GFLevelUtility)
	return value if value is GFLevelUtility else null


func _get_catalog_utility() -> LimitedMoveLevelCatalogUtility:
	var value: Object = get_utility(LimitedMoveLevelCatalogUtility)
	return value if value is LimitedMoveLevelCatalogUtility else null


func _get_save_graph_utility() -> GameSaveGraphUtility:
	var value: Object = get_utility(GameSaveGraphUtility)
	return value if value is GameSaveGraphUtility else null


func _get_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	return value if value is GameClockUtility else null


func _get_log_utility() -> GFLogUtility:
	var value: Object = get_utility(GFLogUtility)
	return value if value is GFLogUtility else null
