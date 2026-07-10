## SaveSystem: 负责处理游戏最高分与轻量统计数据持久化的系统。
##
## 最高分和统计使用 GF save slot 工作流，设置交给 GFSettingsUtility 管理。
class_name SaveSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SaveSystem"
const _KEY_SCORES: String = "scores"
const _KEY_STATS: String = "stats"
const _STAT_PLAYS: String = "plays"
const _STAT_BEST_SCORE: String = "best_score"
const _STAT_BEST_STEPS: String = "best_steps"
const _STAT_MAX_TILE: String = "max_tile"
const _STAT_TOTAL_SCORE: String = "total_score"
const _STAT_TOTAL_STEPS: String = "total_steps"
const _STAT_STEP_SAMPLES: String = "step_samples"
const _STAT_AVERAGE_SCORE: String = "average_score"
const _STAT_AVERAGE_STEPS: String = "average_steps"
const _STAT_TARGET_VALUE: String = "target_value"
const _STAT_TARGET_REACHED_COUNT: String = "target_reached_count"
const _STAT_TARGET_REACHED_RATE: String = "target_reached_rate"
const _STAT_LAST_TARGET_REACHED: String = "last_target_reached"
const _STAT_LAST_SCORE: String = "last_score"
const _STAT_LAST_STEPS: String = "last_steps"
const _STAT_LAST_MAX_TILE: String = "last_max_tile"
const _STAT_LAST_PLAYED_AT: String = "last_played_at"


# --- 私有变量 ---

var _storage: GFStorageUtility
var _save_data: Dictionary = {}
var _is_game_data_loaded: bool = false
var _log: GFLogUtility
var _clock: GameClockUtility
var _save_slot_workflow: GameSaveSlotWorkflowUtility


# --- Godot 生命周期方法 ---

func ready() -> void:
	_storage = _get_storage_utility()
	_log = _get_log_utility()
	_clock = _get_clock_utility()
	_save_slot_workflow = _get_save_slot_workflow_utility()
	_load_game_data()


func dispose() -> void:
	_storage = null
	_save_data.clear()
	_is_game_data_loaded = false
	_log = null
	_clock = null
	_save_slot_workflow = null


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param grid_size: 棋盘边长。
func get_high_score(mode_id: String, grid_size: int) -> int:
	_ensure_game_data_loaded()
	if mode_id.is_empty() or grid_size <= 0:
		return 0

	var grid_size_str: String = _get_grid_size_key(grid_size)
	var stored_high_score: int = _get_high_score_from_scores(mode_id, grid_size_str)
	var stats_entry: Dictionary = _get_stats_entry(mode_id, grid_size_str)
	var stats_high_score: int = _variant_to_int(stats_entry.get(_STAT_BEST_SCORE, 0), 0)
	return max(stored_high_score, stats_high_score)


## 获取某个模式和棋盘大小的轻量统计。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param grid_size: 棋盘边长。
func get_game_stats(mode_id: String, grid_size: int) -> Dictionary:
	_ensure_game_data_loaded()
	if mode_id.is_empty() or grid_size <= 0:
		return _make_default_stats()

	var grid_size_str: String = _get_grid_size_key(grid_size)
	var legacy_high_score: int = _get_high_score_from_scores(mode_id, grid_size_str)
	return _normalize_stats_entry(_get_stats_entry(mode_id, grid_size_str), legacy_high_score)


## 设置或更新一个模式在特定棋盘大小下的最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param grid_size: 棋盘边长。
## @param score: 本次尝试写入的分数。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	_ensure_game_data_loaded()
	if mode_id.is_empty() or grid_size <= 0:
		return

	var grid_size_str: String = _get_grid_size_key(grid_size)
	if not _set_high_score_if_better(mode_id, grid_size_str, score):
		return

	_sync_stats_best_score(mode_id, grid_size_str, score)
	if is_instance_valid(_log):
		_log.info(_LOG_TAG, "新纪录: mode=%s, grid=%s, score=%d" % [mode_id, grid_size_str, score])
	_save_game_data()


## 记录一局完整游戏结果，并维护最高分、最佳步数、最大方块、平均表现和最近一局摘要。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param grid_size: 棋盘边长。
## @param score: 本局最终分数。
## @param steps: 本局有效移动步数。
## @param max_tile: 本局达到的最大玩家方块值。
## @param played_at: 本局结束时间戳；为 0 时使用当前系统时间。
## @param target_value: 当前模式配置的目标方块值；为 0 表示此模式未定义目标。
## @param target_reached: 本局是否达成目标。
func record_game_result(
	mode_id: String,
	grid_size: int,
	score: int,
	steps: int,
	max_tile: int,
	played_at: int = 0,
	target_value: int = 0,
	target_reached: bool = false
) -> void:
	_ensure_game_data_loaded()
	if mode_id.is_empty() or grid_size <= 0:
		return

	var grid_size_str: String = _get_grid_size_key(grid_size)
	var normalized_score: int = max(score, 0)
	var normalized_steps: int = max(steps, 0)
	var normalized_max_tile: int = max(max_tile, 0)
	var normalized_target_value: int = max(target_value, 0)
	var resolved_played_at: int = played_at if played_at > 0 else _get_unix_timestamp()
	var legacy_high_score: int = _get_high_score_from_scores(mode_id, grid_size_str)
	var entry: Dictionary = _normalize_stats_entry(_get_stats_entry(mode_id, grid_size_str), legacy_high_score)

	var previous_plays: int = _variant_to_int(entry.get(_STAT_PLAYS, 0), 0)
	entry[_STAT_PLAYS] = previous_plays + 1
	entry[_STAT_BEST_SCORE] = max(
		max(_variant_to_int(entry.get(_STAT_BEST_SCORE, 0), 0), legacy_high_score),
		normalized_score
	)
	entry[_STAT_TOTAL_SCORE] = _variant_to_int(entry.get(_STAT_TOTAL_SCORE, 0), 0) + normalized_score
	if normalized_steps > 0:
		var best_steps: int = _variant_to_int(entry.get(_STAT_BEST_STEPS, 0), 0)
		if best_steps <= 0 or normalized_steps < best_steps:
			entry[_STAT_BEST_STEPS] = normalized_steps
		entry[_STAT_TOTAL_STEPS] = _variant_to_int(entry.get(_STAT_TOTAL_STEPS, 0), 0) + normalized_steps
		entry[_STAT_STEP_SAMPLES] = _variant_to_int(entry.get(_STAT_STEP_SAMPLES, 0), 0) + 1
	entry[_STAT_MAX_TILE] = max(_variant_to_int(entry.get(_STAT_MAX_TILE, 0), 0), normalized_max_tile)
	entry[_STAT_LAST_SCORE] = normalized_score
	entry[_STAT_LAST_STEPS] = normalized_steps
	entry[_STAT_LAST_MAX_TILE] = normalized_max_tile
	entry[_STAT_LAST_PLAYED_AT] = resolved_played_at
	if normalized_target_value > 0:
		entry[_STAT_TARGET_VALUE] = normalized_target_value
		if target_reached:
			entry[_STAT_TARGET_REACHED_COUNT] = _variant_to_int(entry.get(_STAT_TARGET_REACHED_COUNT, 0), 0) + 1
		entry[_STAT_LAST_TARGET_REACHED] = target_reached
	_update_average_stats(entry)
	_update_target_stats(entry)

	var _high_score_changed: bool = _set_high_score_if_better(mode_id, grid_size_str, normalized_score)

	var stats: Dictionary = _get_stats()
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	mode_stats[grid_size_str] = entry
	stats[mode_id] = mode_stats
	_save_game_data()


# --- 私有方法 ---

func _save_game_data() -> void:
	if not is_instance_valid(_storage) or not is_instance_valid(_save_slot_workflow):
		return

	var error: int = _save_slot_workflow.save_stats_payload(_storage, _save_data)
	if error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "保存最高分失败，错误码: %d" % error)


func _load_game_data() -> void:
	_save_data = {}
	if is_instance_valid(_storage) and is_instance_valid(_save_slot_workflow):
		_save_data = _save_slot_workflow.load_stats_payload(_storage)

	var _erase_result: bool = _save_data.erase(GFStorageCodec.META_KEY)
	_ensure_game_data_defaults()
	_is_game_data_loaded = true


func _ensure_game_data_loaded() -> void:
	if _is_game_data_loaded:
		return

	_load_game_data()


func _ensure_game_data_defaults() -> void:
	if not _save_data.has(_KEY_SCORES) or not (_save_data[_KEY_SCORES] is Dictionary):
		_save_data[_KEY_SCORES] = {}
	if not _save_data.has(_KEY_STATS) or not (_save_data[_KEY_STATS] is Dictionary):
		_save_data[_KEY_STATS] = {}


func _get_scores() -> Dictionary:
	_ensure_game_data_defaults()
	var scores_value: Variant = _save_data[_KEY_SCORES]
	if scores_value is Dictionary:
		var scores: Dictionary = scores_value
		return scores
	return {}


func _get_stats() -> Dictionary:
	_ensure_game_data_defaults()
	var stats_value: Variant = _save_data[_KEY_STATS]
	if stats_value is Dictionary:
		var stats: Dictionary = stats_value
		return stats
	return {}


func _get_mode_scores(scores: Dictionary, mode_id: String) -> Dictionary:
	var mode_scores_value: Variant = scores.get(mode_id, {})
	if mode_scores_value is Dictionary:
		var mode_scores: Dictionary = mode_scores_value
		return mode_scores

	return {}


func _get_mode_stats(stats: Dictionary, mode_id: String) -> Dictionary:
	var mode_stats_value: Variant = stats.get(mode_id, {})
	if mode_stats_value is Dictionary:
		var mode_stats: Dictionary = mode_stats_value
		return mode_stats

	return {}


func _get_stats_entry(mode_id: String, grid_size_str: String) -> Dictionary:
	var stats: Dictionary = _get_stats()
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	var entry_value: Variant = mode_stats.get(grid_size_str, {})
	if entry_value is Dictionary:
		var entry: Dictionary = entry_value
		return entry

	return {}


func _get_high_score_from_scores(mode_id: String, grid_size_str: String) -> int:
	var scores: Dictionary = _get_scores()
	var mode_scores_value: Variant = scores.get(mode_id, {})
	if mode_scores_value is Dictionary:
		var mode_scores: Dictionary = mode_scores_value
		if mode_scores.has(grid_size_str):
			return _variant_to_int(mode_scores[grid_size_str], 0)

	return 0


func _set_high_score_if_better(mode_id: String, grid_size_str: String, score: int) -> bool:
	var normalized_score: int = max(score, 0)
	var current_high_score: int = max(
		_get_high_score_from_scores(mode_id, grid_size_str),
		_variant_to_int(_get_stats_entry(mode_id, grid_size_str).get(_STAT_BEST_SCORE, 0), 0)
	)
	if normalized_score <= current_high_score:
		return false

	var scores: Dictionary = _get_scores()
	var mode_scores: Dictionary = _get_mode_scores(scores, mode_id)
	mode_scores[grid_size_str] = normalized_score
	scores[mode_id] = mode_scores
	return true


func _sync_stats_best_score(mode_id: String, grid_size_str: String, score: int) -> void:
	var legacy_high_score: int = _get_high_score_from_scores(mode_id, grid_size_str)
	var entry: Dictionary = _normalize_stats_entry(_get_stats_entry(mode_id, grid_size_str), legacy_high_score)
	entry[_STAT_BEST_SCORE] = max(_variant_to_int(entry.get(_STAT_BEST_SCORE, 0), 0), max(score, 0))

	var stats: Dictionary = _get_stats()
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	mode_stats[grid_size_str] = entry
	stats[mode_id] = mode_stats


func _normalize_stats_entry(entry: Dictionary, legacy_high_score: int = 0) -> Dictionary:
	var normalized: Dictionary = _make_default_stats(legacy_high_score)
	for key: Variant in entry.keys():
		normalized[key] = entry[key]

	normalized[_STAT_PLAYS] = max(_variant_to_int(normalized.get(_STAT_PLAYS, 0), 0), 0)
	normalized[_STAT_BEST_SCORE] = max(
		_variant_to_int(normalized.get(_STAT_BEST_SCORE, 0), 0),
		max(legacy_high_score, 0)
	)
	normalized[_STAT_BEST_STEPS] = max(_variant_to_int(normalized.get(_STAT_BEST_STEPS, 0), 0), 0)
	normalized[_STAT_MAX_TILE] = max(_variant_to_int(normalized.get(_STAT_MAX_TILE, 0), 0), 0)
	normalized[_STAT_LAST_SCORE] = max(_variant_to_int(normalized.get(_STAT_LAST_SCORE, 0), 0), 0)
	normalized[_STAT_LAST_STEPS] = max(_variant_to_int(normalized.get(_STAT_LAST_STEPS, 0), 0), 0)
	normalized[_STAT_LAST_MAX_TILE] = max(_variant_to_int(normalized.get(_STAT_LAST_MAX_TILE, 0), 0), 0)
	normalized[_STAT_LAST_PLAYED_AT] = max(_variant_to_int(normalized.get(_STAT_LAST_PLAYED_AT, 0), 0), 0)
	normalized[_STAT_TOTAL_SCORE] = max(_variant_to_int(normalized.get(_STAT_TOTAL_SCORE, 0), 0), 0)
	normalized[_STAT_TOTAL_STEPS] = max(_variant_to_int(normalized.get(_STAT_TOTAL_STEPS, 0), 0), 0)
	normalized[_STAT_STEP_SAMPLES] = max(_variant_to_int(normalized.get(_STAT_STEP_SAMPLES, 0), 0), 0)
	normalized[_STAT_TARGET_VALUE] = max(_variant_to_int(normalized.get(_STAT_TARGET_VALUE, 0), 0), 0)
	normalized[_STAT_TARGET_REACHED_COUNT] = _normalize_target_reached_count(normalized)
	normalized[_STAT_TARGET_REACHED_RATE] = max(_variant_to_int(normalized.get(_STAT_TARGET_REACHED_RATE, 0), 0), 0)
	normalized[_STAT_LAST_TARGET_REACHED] = _variant_to_bool(normalized.get(_STAT_LAST_TARGET_REACHED, false), false)

	var plays: int = _variant_to_int(normalized.get(_STAT_PLAYS, 0), 0)
	var last_score: int = _variant_to_int(normalized.get(_STAT_LAST_SCORE, 0), 0)
	if _variant_to_int(normalized.get(_STAT_TOTAL_SCORE, 0), 0) <= 0 and plays > 0 and last_score > 0:
		normalized[_STAT_TOTAL_SCORE] = last_score * plays

	var last_steps: int = _variant_to_int(normalized.get(_STAT_LAST_STEPS, 0), 0)
	var total_steps: int = _variant_to_int(normalized.get(_STAT_TOTAL_STEPS, 0), 0)
	if _variant_to_int(normalized.get(_STAT_STEP_SAMPLES, 0), 0) <= 0:
		if total_steps > 0:
			normalized[_STAT_STEP_SAMPLES] = max(plays, 1)
		elif plays > 0 and last_steps > 0:
			normalized[_STAT_STEP_SAMPLES] = plays
	if total_steps <= 0 and _variant_to_int(normalized.get(_STAT_STEP_SAMPLES, 0), 0) > 0 and last_steps > 0:
		normalized[_STAT_TOTAL_STEPS] = last_steps * _variant_to_int(normalized.get(_STAT_STEP_SAMPLES, 0), 0)

	_update_average_stats(normalized)
	_update_target_stats(normalized)
	return normalized


func _make_default_stats(legacy_high_score: int = 0) -> Dictionary:
	return {
		_STAT_PLAYS: 0,
		_STAT_BEST_SCORE: max(legacy_high_score, 0),
		_STAT_BEST_STEPS: 0,
		_STAT_MAX_TILE: 0,
		_STAT_TOTAL_SCORE: 0,
		_STAT_TOTAL_STEPS: 0,
		_STAT_STEP_SAMPLES: 0,
		_STAT_AVERAGE_SCORE: 0,
		_STAT_AVERAGE_STEPS: 0,
		_STAT_TARGET_VALUE: 0,
		_STAT_TARGET_REACHED_COUNT: 0,
		_STAT_TARGET_REACHED_RATE: 0,
		_STAT_LAST_TARGET_REACHED: false,
		_STAT_LAST_SCORE: 0,
		_STAT_LAST_STEPS: 0,
		_STAT_LAST_MAX_TILE: 0,
		_STAT_LAST_PLAYED_AT: 0,
	}


static func _update_average_stats(entry: Dictionary) -> void:
	var plays: int = _variant_to_int(entry.get(_STAT_PLAYS, 0), 0)
	var total_score: int = _variant_to_int(entry.get(_STAT_TOTAL_SCORE, 0), 0)
	var step_samples: int = _variant_to_int(entry.get(_STAT_STEP_SAMPLES, 0), 0)
	var total_steps: int = _variant_to_int(entry.get(_STAT_TOTAL_STEPS, 0), 0)
	entry[_STAT_AVERAGE_SCORE] = _rounded_average(total_score, plays)
	entry[_STAT_AVERAGE_STEPS] = _rounded_average(total_steps, step_samples)


static func _update_target_stats(entry: Dictionary) -> void:
	var plays: int = _variant_to_int(entry.get(_STAT_PLAYS, 0), 0)
	var target_value: int = _variant_to_int(entry.get(_STAT_TARGET_VALUE, 0), 0)
	var reached_count: int = _normalize_target_reached_count(entry)
	entry[_STAT_TARGET_REACHED_COUNT] = reached_count
	if target_value <= 0 or plays <= 0:
		entry[_STAT_TARGET_REACHED_RATE] = 0
		return
	entry[_STAT_TARGET_REACHED_RATE] = _rounded_average(reached_count * 100, plays)


static func _normalize_target_reached_count(entry: Dictionary) -> int:
	var plays: int = _variant_to_int(entry.get(_STAT_PLAYS, 0), 0)
	var target_value: int = _variant_to_int(entry.get(_STAT_TARGET_VALUE, 0), 0)
	var reached_count: int = _variant_to_int(entry.get(_STAT_TARGET_REACHED_COUNT, 0), 0)
	if plays <= 0 or target_value <= 0:
		return 0
	return clampi(reached_count, 0, plays)


static func _rounded_average(total_value: int, sample_count: int) -> int:
	if sample_count <= 0:
		return 0
	var normalized_total: int = maxi(total_value, 0)
	return roundi(float(normalized_total) / float(sample_count))


static func _variant_to_bool(value: Variant, default_value: bool) -> bool:
	if value is bool:
		return value
	if value is int:
		var int_value: int = value
		return int_value != 0
	return default_value


func _get_grid_size_key(grid_size: int) -> String:
	return "%dx%d" % [grid_size, grid_size]


func _get_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_save_slot_workflow_utility() -> GameSaveSlotWorkflowUtility:
	var utility_value: Object = get_utility(GameSaveSlotWorkflowUtility)
	if utility_value is GameSaveSlotWorkflowUtility:
		var save_slot_workflow: GameSaveSlotWorkflowUtility = utility_value
		return save_slot_workflow
	return null


func _get_unix_timestamp() -> int:
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	_clock = _get_clock_utility()
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	push_error("[SaveSystem] 缺少 GameClockUtility，无法记录游戏结果时间戳。")
	return 0


static func _variant_to_int(value: Variant, default_value: int) -> int:
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value
