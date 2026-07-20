## SaveSystem: 负责处理游戏最高分与轻量统计数据持久化的系统。
##
## 最高分和统计作为 progress section 参与统一玩家数据 SaveGraph，设置交给 GFSettingsUtility 管理。
class_name SaveSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SaveSystem"
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

var _log: GFLogUtility
var _clock: GameClockUtility
var _save_graph: GameSaveGraphUtility


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameClockUtility, GameSaveGraphUtility, GFLogUtility]


func ready() -> void:
	_log = _get_log_utility()
	_clock = _get_clock_utility()
	_save_graph = _get_save_graph_utility()


func dispose() -> void:
	_log = null
	_clock = null
	_save_graph = null


# --- 公共方法 ---

## 根据模式 ID 和稳定棋盘拓扑键获取最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
func get_high_score(mode_id: String, board_key: String) -> int:
	if mode_id.is_empty() or board_key.is_empty():
		return 0

	var save_data: Dictionary = _get_save_data()
	var stats_entry: Dictionary = _get_stats_entry(save_data, mode_id, board_key)
	return maxi(GFVariantData.get_option_int(stats_entry, _STAT_BEST_SCORE, 0), 0)


## 获取某个模式和棋盘拓扑的轻量统计。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
func get_game_stats(mode_id: String, board_key: String) -> Dictionary:
	if mode_id.is_empty() or board_key.is_empty():
		return _make_default_stats()

	var save_data: Dictionary = _get_save_data()
	return _normalize_stats_entry(_get_stats_entry(save_data, mode_id, board_key))


## 设置或更新一个模式在特定棋盘拓扑下的最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
## @param score: 本次尝试写入的分数。
func set_high_score(mode_id: String, board_key: String, score: int) -> Error:
	if mode_id.is_empty() or board_key.is_empty():
		return ERR_INVALID_PARAMETER

	var save_data: Dictionary = _get_save_data()
	var entry: Dictionary = _normalize_stats_entry(_get_stats_entry(save_data, mode_id, board_key))
	var normalized_score: int = maxi(score, 0)
	if normalized_score <= GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0):
		return OK

	entry[_STAT_BEST_SCORE] = normalized_score
	_set_stats_entry(save_data, mode_id, board_key, entry)
	var save_error: Error = _queue_game_data(save_data)
	if save_error == OK and is_instance_valid(_log):
		_log.info(_LOG_TAG, "新纪录: mode=%s, board=%s, score=%d" % [mode_id, board_key, normalized_score])
	return save_error


## 记录一局完整游戏结果，并维护最高分、最佳步数、最大方块、平均表现和最近一局摘要。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
## @param score: 本局最终分数。
## @param steps: 本局有效移动步数。
## @param max_tile: 本局达到的最大方块值。
## @param played_at: 本局结束时间戳；为 0 时使用当前系统时间。
## @param target_value: 当前模式配置的目标方块值；为 0 表示此模式未定义目标。
## @param target_reached: 本局是否达成目标。
func record_game_result(
	mode_id: String,
	board_key: String,
	score: int,
	steps: int,
	max_tile: int,
	played_at: int = 0,
	target_value: int = 0,
	target_reached: bool = false
) -> Error:
	if mode_id.is_empty() or board_key.is_empty():
		return ERR_INVALID_PARAMETER

	var save_data: Dictionary = _get_save_data()
	var normalized_score: int = max(score, 0)
	var normalized_steps: int = max(steps, 0)
	var normalized_max_tile: int = max(max_tile, 0)
	var normalized_target_value: int = max(target_value, 0)
	var resolved_played_at: int = played_at if played_at > 0 else _get_unix_timestamp()
	var entry: Dictionary = _normalize_stats_entry(_get_stats_entry(save_data, mode_id, board_key))

	var previous_plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	entry[_STAT_PLAYS] = previous_plays + 1
	entry[_STAT_BEST_SCORE] = maxi(
		GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0),
		normalized_score
	)
	entry[_STAT_TOTAL_SCORE] = GFVariantData.get_option_int(entry, _STAT_TOTAL_SCORE, 0) + normalized_score
	if normalized_steps > 0:
		var best_steps: int = GFVariantData.get_option_int(entry, _STAT_BEST_STEPS, 0)
		if best_steps <= 0 or normalized_steps < best_steps:
			entry[_STAT_BEST_STEPS] = normalized_steps
		entry[_STAT_TOTAL_STEPS] = GFVariantData.get_option_int(entry, _STAT_TOTAL_STEPS, 0) + normalized_steps
		entry[_STAT_STEP_SAMPLES] = GFVariantData.get_option_int(entry, _STAT_STEP_SAMPLES, 0) + 1
	entry[_STAT_MAX_TILE] = maxi(GFVariantData.get_option_int(entry, _STAT_MAX_TILE, 0), normalized_max_tile)
	entry[_STAT_LAST_SCORE] = normalized_score
	entry[_STAT_LAST_STEPS] = normalized_steps
	entry[_STAT_LAST_MAX_TILE] = normalized_max_tile
	entry[_STAT_LAST_PLAYED_AT] = resolved_played_at
	if normalized_target_value > 0:
		entry[_STAT_TARGET_VALUE] = normalized_target_value
		if target_reached:
			entry[_STAT_TARGET_REACHED_COUNT] = GFVariantData.get_option_int(
				entry,
				_STAT_TARGET_REACHED_COUNT,
				0
			) + 1
		entry[_STAT_LAST_TARGET_REACHED] = target_reached
	_update_average_stats(entry)
	_update_target_stats(entry)

	_set_stats_entry(save_data, mode_id, board_key, entry)
	var save_error: Error = _save_game_data(save_data)
	if save_error == OK:
		send_event(GameResultRecordedData.new(
			StringName(mode_id),
			board_key,
			normalized_score,
			normalized_steps,
			normalized_max_tile,
			resolved_played_at,
			normalized_target_value,
			target_reached
		))
	return save_error


# --- 私有方法 ---

func _save_game_data(save_data: Dictionary) -> Error:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED
	var error: Error = save_graph.replace_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		save_data
	)
	if error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "保存统计 SaveGraph section 失败，错误码: %d" % error)
	return error


func _queue_game_data(save_data: Dictionary) -> Error:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED
	var error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		save_data
	)
	if error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "排队统计 SaveGraph section 失败，错误码: %d" % error)
	return error


func _get_save_data() -> Dictionary:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var save_data: Dictionary = {}
	if save_graph != null:
		save_data = save_graph.get_section_data(GameSaveGraphUtility.PROGRESS_SECTION_ID)
	_ensure_game_data_defaults(save_data)
	return save_data


func _ensure_game_data_defaults(save_data: Dictionary) -> void:
	if not save_data.has(_KEY_STATS) or not (save_data[_KEY_STATS] is Dictionary):
		save_data[_KEY_STATS] = {}


func _get_stats(save_data: Dictionary) -> Dictionary:
	_ensure_game_data_defaults(save_data)
	var stats_value: Variant = save_data[_KEY_STATS]
	if stats_value is Dictionary:
		var stats: Dictionary = stats_value
		return stats
	return {}


func _get_mode_stats(stats: Dictionary, mode_id: String) -> Dictionary:
	var mode_stats_value: Variant = stats.get(mode_id, {})
	if mode_stats_value is Dictionary:
		var mode_stats: Dictionary = mode_stats_value
		return mode_stats

	return {}


func _get_stats_entry(save_data: Dictionary, mode_id: String, board_key: String) -> Dictionary:
	var stats: Dictionary = _get_stats(save_data)
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	var entry_value: Variant = mode_stats.get(board_key, {})
	if entry_value is Dictionary:
		var entry: Dictionary = entry_value
		return entry

	return {}


func _set_stats_entry(
	save_data: Dictionary,
	mode_id: String,
	board_key: String,
	entry: Dictionary
) -> void:
	var stats: Dictionary = _get_stats(save_data)
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	mode_stats[board_key] = entry
	stats[mode_id] = mode_stats


func _normalize_stats_entry(entry: Dictionary) -> Dictionary:
	var normalized: Dictionary = _make_default_stats()
	for key: Variant in entry.keys():
		normalized[key] = entry[key]

	normalized[_STAT_PLAYS] = maxi(GFVariantData.get_option_int(normalized, _STAT_PLAYS, 0), 0)
	normalized[_STAT_BEST_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_BEST_SCORE, 0), 0)
	normalized[_STAT_BEST_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_BEST_STEPS, 0), 0)
	normalized[_STAT_MAX_TILE] = maxi(GFVariantData.get_option_int(normalized, _STAT_MAX_TILE, 0), 0)
	normalized[_STAT_LAST_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_SCORE, 0), 0)
	normalized[_STAT_LAST_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_STEPS, 0), 0)
	normalized[_STAT_LAST_MAX_TILE] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_MAX_TILE, 0), 0)
	normalized[_STAT_LAST_PLAYED_AT] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_PLAYED_AT, 0), 0)
	normalized[_STAT_TOTAL_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TOTAL_SCORE, 0), 0)
	normalized[_STAT_TOTAL_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_TOTAL_STEPS, 0), 0)
	normalized[_STAT_STEP_SAMPLES] = maxi(GFVariantData.get_option_int(normalized, _STAT_STEP_SAMPLES, 0), 0)
	normalized[_STAT_TARGET_VALUE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TARGET_VALUE, 0), 0)
	normalized[_STAT_TARGET_REACHED_COUNT] = _normalize_target_reached_count(normalized)
	normalized[_STAT_TARGET_REACHED_RATE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TARGET_REACHED_RATE, 0), 0)
	normalized[_STAT_LAST_TARGET_REACHED] = GFVariantData.get_option_bool(
		normalized,
		_STAT_LAST_TARGET_REACHED,
		false
	)

	_update_average_stats(normalized)
	_update_target_stats(normalized)
	return normalized


func _make_default_stats() -> Dictionary:
	return {
		_STAT_PLAYS: 0,
		_STAT_BEST_SCORE: 0,
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
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var total_score: int = GFVariantData.get_option_int(entry, _STAT_TOTAL_SCORE, 0)
	var step_samples: int = GFVariantData.get_option_int(entry, _STAT_STEP_SAMPLES, 0)
	var total_steps: int = GFVariantData.get_option_int(entry, _STAT_TOTAL_STEPS, 0)
	entry[_STAT_AVERAGE_SCORE] = _rounded_average(total_score, plays)
	entry[_STAT_AVERAGE_STEPS] = _rounded_average(total_steps, step_samples)


static func _update_target_stats(entry: Dictionary) -> void:
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var target_value: int = GFVariantData.get_option_int(entry, _STAT_TARGET_VALUE, 0)
	var reached_count: int = _normalize_target_reached_count(entry)
	entry[_STAT_TARGET_REACHED_COUNT] = reached_count
	if target_value <= 0 or plays <= 0:
		entry[_STAT_TARGET_REACHED_RATE] = 0
		return
	entry[_STAT_TARGET_REACHED_RATE] = _rounded_average(reached_count * 100, plays)


static func _normalize_target_reached_count(entry: Dictionary) -> int:
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var target_value: int = GFVariantData.get_option_int(entry, _STAT_TARGET_VALUE, 0)
	var reached_count: int = GFVariantData.get_option_int(entry, _STAT_TARGET_REACHED_COUNT, 0)
	if plays <= 0 or target_value <= 0:
		return 0
	return clampi(reached_count, 0, plays)


static func _rounded_average(total_value: int, sample_count: int) -> int:
	if sample_count <= 0:
		return 0
	var normalized_total: int = maxi(total_value, 0)
	return roundi(float(normalized_total) / float(sample_count))


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


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _get_save_graph_utility()
	return _save_graph


func _get_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = utility_value
		return save_graph
	return null


func _get_unix_timestamp() -> int:
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	_clock = _get_clock_utility()
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	push_error("[SaveSystem] 缺少 GameClockUtility，无法记录游戏结果时间戳。")
	return 0
