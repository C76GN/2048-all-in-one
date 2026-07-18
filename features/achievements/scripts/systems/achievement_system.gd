## AchievementSystem: 把项目领域高水位指标投影到 GFQuestUtility。
##
## SaveGraph 是玩家成就进度真源，GFQuestUtility 是运行时状态机。系统先原子保存
## 提议进度，再推进 GF Quest，避免持久化失败后运行时状态领先于真源。
class_name AchievementSystem
extends GFSystem


# --- 信号 ---

signal achievement_progress_changed(
	achievement_id: StringName,
	current_value: int,
	target_value: int
)
signal achievement_unlocked(achievement_id: StringName)


# --- 常量 ---

const METRIC_COMPLETED_GAMES: StringName = &"game.completed_count"
const METRIC_TARGET_REACHED: StringName = &"game.target_reached_count"
const METRIC_BEST_SCORE: StringName = &"game.best_score"
const METRIC_MAX_TILE: StringName = &"game.max_tile"
const METRIC_TILE_COMPOSITIONS: StringName = &"catalog.tile_composition_count"
const METRIC_BOARD_TOPOLOGIES: StringName = &"catalog.board_topology_count"

const _QUEST_EVENT_PREFIX: String = "achievement.progress."
const _KEY_STATS: String = "stats"
const _STAT_PLAYS: String = "plays"
const _STAT_BEST_SCORE: String = "best_score"
const _STAT_MAX_TILE: String = "max_tile"
const _STAT_TARGET_REACHED_COUNT: String = "target_reached_count"
const _MAX_PROGRESS_VALUE: int = 2147483647


# --- 私有变量 ---

var _catalog: AchievementCatalogUtility = null
var _clock: GameClockUtility = null
var _quest: GFQuestUtility = null
var _save_graph: GameSaveGraphUtility = null
var _records_by_id: Dictionary = {}
var _needs_save_cleanup: bool = false


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		AchievementCatalogUtility,
		GameClockUtility,
		GameSaveGraphUtility,
		GFQuestUtility,
	]


func ready() -> void:
	_catalog = _resolve_catalog_utility()
	_clock = _resolve_clock_utility()
	_quest = _resolve_quest_utility()
	_save_graph = _resolve_save_graph_utility()
	register_event(
		GameResultRecordedData,
		GFEventListener.from_method(self, &"_on_game_result_recorded", 1)
	)
	register_event(
		DiscoveryProgressChangedData,
		GFEventListener.from_method(self, &"_on_discovery_progress_changed", 1)
	)
	_initialize_quest_projection()
	var reconciliation_error: Error = reconcile_progress()
	if reconciliation_error != OK:
		push_error(
			"[AchievementSystem] 初始成就进度协调失败，错误码：%d。"
			% reconciliation_error
		)


func dispose() -> void:
	_catalog = null
	_clock = null
	_quest = null
	_save_graph = null
	_records_by_id.clear()
	_needs_save_cleanup = false


# --- 公共方法 ---

## 从已持久化统计与发现 section 重新计算全部单调指标。
func reconcile_progress() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var metric_values: Dictionary = _collect_metric_values()
	var proposed_records: Dictionary = _duplicate_records(_records_by_id)
	var changed_ids: Array[StringName] = []
	var unlocked_ids: Array[StringName] = []
	var now: int = maxi(_clock.get_unix_timestamp(), 1)

	for definition: AchievementDefinition in _catalog.get_definitions():
		var record: AchievementProgressRecord = _get_record_from(
			proposed_records,
			definition.achievement_id
		)
		if record == null:
			record = AchievementProgressRecord.create(
				definition.achievement_id,
				definition.get_criteria_fingerprint()
			)
		if record == null:
			return ERR_INVALID_DATA
		var observed_value: int = maxi(
			GFVariantData.get_option_int(metric_values, String(definition.metric_id), 0),
			0
		)
		var next_value: int = mini(
			maxi(record.current_value, observed_value),
			definition.target_value
		)
		if next_value <= record.current_value:
			proposed_records[definition.achievement_id] = record
			continue
		var was_completed: bool = record.completed_at > 0
		record.current_value = next_value
		record.last_progress_at = now
		if next_value >= definition.target_value and not was_completed:
			record.completed_at = now
			unlocked_ids.append(definition.achievement_id)
		proposed_records[definition.achievement_id] = record
		changed_ids.append(definition.achievement_id)

	if changed_ids.is_empty() and not _needs_save_cleanup:
		return OK
	var save_error: Error = _save_records(proposed_records)
	if save_error != OK:
		return save_error

	var previous_records: Dictionary = _records_by_id
	_records_by_id = proposed_records
	_needs_save_cleanup = false
	_apply_persisted_changes(previous_records, changed_ids, unlocked_ids)
	return OK


## 返回目录顺序下的 UI 只读条目。
func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_catalog):
		return result
	for definition: AchievementDefinition in _catalog.get_definitions():
		var entry: Dictionary = definition.to_descriptor()
		var record: AchievementProgressRecord = _get_record(definition.achievement_id)
		var current_value: int = record.current_value if record != null else 0
		var completed_at: int = record.completed_at if record != null else 0
		entry[&"current_value"] = current_value
		entry[&"completed"] = completed_at > 0
		entry[&"completed_at"] = completed_at
		entry[&"last_progress_at"] = record.last_progress_at if record != null else 0
		entry[&"progress"] = clampf(
			float(current_value) / float(definition.target_value),
			0.0,
			1.0
		)
		result.append(entry)
	return result


## 获取指定成就的展示快照。
## @param achievement_id: 成就定义的稳定标识。
func get_entry(achievement_id: StringName) -> Dictionary:
	for entry: Dictionary in get_entries():
		if GFVariantData.get_option_string_name(entry, &"achievement_id") == achievement_id:
			return entry
	return {}


## 查询指定成就是否已由本地真源确认达成。
## @param achievement_id: 成就定义的稳定标识。
func is_unlocked(achievement_id: StringName) -> bool:
	var record: AchievementProgressRecord = _get_record(achievement_id)
	return record != null and record.completed_at > 0


func get_summary() -> Dictionary:
	var entries: Array[Dictionary] = get_entries()
	var unlocked_count: int = 0
	for entry: Dictionary in entries:
		if GFVariantData.get_option_bool(entry, &"completed"):
			unlocked_count += 1
	return {
		"achievement_count": entries.size(),
		"unlocked_count": unlocked_count,
		"completion_ratio": (
			0.0 if entries.is_empty() else float(unlocked_count) / float(entries.size())
		),
	}


func get_debug_snapshot() -> Dictionary:
	var quest_reports: Dictionary = {}
	if is_instance_valid(_quest) and is_instance_valid(_catalog):
		for achievement_id: StringName in _catalog.get_definition_ids():
			quest_reports[String(achievement_id)] = _quest.get_quest_report(achievement_id)
	return {
		"summary": get_summary(),
		"record_count": _records_by_id.size(),
		"needs_save_cleanup": _needs_save_cleanup,
		"quest_reports": quest_reports,
	}


# --- 私有/辅助方法 ---

func _initialize_quest_projection() -> void:
	_records_by_id.clear()
	_needs_save_cleanup = false
	if not _is_configured():
		return
	var section_data: Dictionary = _save_graph.get_section_data(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID
	)
	var raw_records: Array = GFVariantData.get_option_array(section_data, "records")
	for value: Variant in raw_records:
		if not value is Dictionary:
			_needs_save_cleanup = true
			continue
		var record: AchievementProgressRecord = AchievementProgressRecord.from_dict(
			GFVariantData.as_dictionary(value)
		)
		var definition: AchievementDefinition = (
			_catalog.get_definition(record.achievement_id) if record != null else null
		)
		if not _is_record_compatible(record, definition):
			_needs_save_cleanup = true
			continue
		_records_by_id[record.achievement_id] = record

	for definition: AchievementDefinition in _catalog.get_definitions():
		_quest.start_quest(
			definition.achievement_id,
			_make_quest_event_id(definition.achievement_id),
			definition.target_value
		)
		var record: AchievementProgressRecord = _get_record(definition.achievement_id)
		if record == null:
			record = AchievementProgressRecord.create(
				definition.achievement_id,
				definition.get_criteria_fingerprint()
			)
			_records_by_id[definition.achievement_id] = record
		if record != null and record.current_value > 0:
			_quest.emit_quest_event(
				_make_quest_event_id(definition.achievement_id),
				record.current_value
			)


func _collect_metric_values() -> Dictionary:
	var completed_games: int = 0
	var reached_targets: int = 0
	var best_score: int = 0
	var max_tile: int = 0
	var progress_section: Dictionary = _save_graph.get_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	var stats: Dictionary = GFVariantData.get_option_dictionary(
		progress_section,
		_KEY_STATS
	)
	for mode_value: Variant in stats.values():
		if not mode_value is Dictionary:
			continue
		var mode_stats: Dictionary = GFVariantData.as_dictionary(mode_value)
		for entry_value: Variant in mode_stats.values():
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
			completed_games = _add_nonnegative_saturated(
				completed_games,
				GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
			)
			reached_targets = _add_nonnegative_saturated(
				reached_targets,
				GFVariantData.get_option_int(entry, _STAT_TARGET_REACHED_COUNT, 0)
			)
			best_score = maxi(
				best_score,
				GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0)
			)
			max_tile = maxi(
				max_tile,
				GFVariantData.get_option_int(entry, _STAT_MAX_TILE, 0)
			)

	var discovery_section: Dictionary = _save_graph.get_section_data(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID
	)
	var tile_records: Array = GFVariantData.get_option_array(
		discovery_section,
		"tile_compositions"
	)
	for record_value: Variant in tile_records:
		if record_value is Dictionary:
			max_tile = maxi(
				max_tile,
				GFVariantData.get_option_int(
					GFVariantData.as_dictionary(record_value),
					"max_observed_value",
					0
				)
			)
	return {
		String(METRIC_COMPLETED_GAMES): completed_games,
		String(METRIC_TARGET_REACHED): reached_targets,
		String(METRIC_BEST_SCORE): best_score,
		String(METRIC_MAX_TILE): max_tile,
		String(METRIC_TILE_COMPOSITIONS): tile_records.size(),
		String(METRIC_BOARD_TOPOLOGIES): GFVariantData.get_option_array(
			discovery_section,
			"board_topologies"
		).size(),
	}


func _save_records(records_by_id: Dictionary) -> Error:
	var records: Array[AchievementProgressRecord] = []
	for value: Variant in records_by_id.values():
		if value is AchievementProgressRecord:
			var record: AchievementProgressRecord = value
			if record.current_value > 0:
				records.append(record)
	records.sort_custom(func(left: AchievementProgressRecord, right: AchievementProgressRecord) -> bool:
		return String(left.achievement_id) < String(right.achievement_id)
	)
	var payload: Array[Dictionary] = []
	for record: AchievementProgressRecord in records:
		payload.append(record.to_dict())
	return _save_graph.replace_section_data(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID,
		{"records": payload}
	)


func _apply_persisted_changes(
	previous_records: Dictionary,
	changed_ids: Array[StringName],
	unlocked_ids: Array[StringName]
) -> void:
	for achievement_id: StringName in changed_ids:
		var definition: AchievementDefinition = _catalog.get_definition(achievement_id)
		var record: AchievementProgressRecord = _get_record(achievement_id)
		if definition == null or record == null:
			continue
		var previous: AchievementProgressRecord = _get_record_from(
			previous_records,
			achievement_id
		)
		var previous_value: int = previous.current_value if previous != null else 0
		var delta: int = maxi(record.current_value - previous_value, 0)
		if delta > 0:
			_quest.emit_quest_event(_make_quest_event_id(achievement_id), delta)
		achievement_progress_changed.emit(
			achievement_id,
			record.current_value,
			definition.target_value
		)
		send_event(AchievementProgressChangedData.new(
			achievement_id,
			record.current_value,
			definition.target_value
		))

	for achievement_id: StringName in unlocked_ids:
		var record: AchievementProgressRecord = _get_record(achievement_id)
		if record == null:
			continue
		achievement_unlocked.emit(achievement_id)
		send_event(AchievementUnlockedData.new(achievement_id, record.completed_at))


func _is_record_compatible(
	record: AchievementProgressRecord,
	definition: AchievementDefinition
) -> bool:
	if record == null or definition == null:
		return false
	if (
		record.criteria_fingerprint != definition.get_criteria_fingerprint()
		or record.current_value > definition.target_value
	):
		return false
	var should_be_completed: bool = record.current_value >= definition.target_value
	return should_be_completed == (record.completed_at > 0)


func _duplicate_records(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in source.keys():
		var value: Variant = source[key_value]
		if value is AchievementProgressRecord:
			var record: AchievementProgressRecord = value
			result[key_value] = record.duplicate_record()
	return result


func _get_record(achievement_id: StringName) -> AchievementProgressRecord:
	return _get_record_from(_records_by_id, achievement_id)


func _get_record_from(
	records: Dictionary,
	achievement_id: StringName
) -> AchievementProgressRecord:
	var value: Variant = records.get(achievement_id)
	if value is AchievementProgressRecord:
		var record: AchievementProgressRecord = value
		return record
	return null


func _is_configured() -> bool:
	return (
		is_instance_valid(_catalog)
		and is_instance_valid(_clock)
		and is_instance_valid(_quest)
		and is_instance_valid(_save_graph)
		and _save_graph.is_profile_loaded()
	)


func _make_quest_event_id(achievement_id: StringName) -> StringName:
	return StringName(_QUEST_EVENT_PREFIX + String(achievement_id))


static func _add_nonnegative_saturated(left: int, right: int) -> int:
	var safe_left: int = clampi(left, 0, _MAX_PROGRESS_VALUE)
	var safe_right: int = clampi(right, 0, _MAX_PROGRESS_VALUE)
	if safe_left > _MAX_PROGRESS_VALUE - safe_right:
		return _MAX_PROGRESS_VALUE
	return safe_left + safe_right


func _resolve_catalog_utility() -> AchievementCatalogUtility:
	var value: Object = get_utility(AchievementCatalogUtility)
	if value is AchievementCatalogUtility:
		var utility: AchievementCatalogUtility = value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	if value is GameClockUtility:
		var utility: GameClockUtility = value
		return utility
	return null


func _resolve_quest_utility() -> GFQuestUtility:
	var value: Object = get_utility(GFQuestUtility)
	if value is GFQuestUtility:
		var utility: GFQuestUtility = value
		return utility
	return null


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var value: Object = get_utility(GameSaveGraphUtility)
	if value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = value
		return utility
	return null


# --- 信号处理函数 ---

func _on_game_result_recorded(payload: GameResultRecordedData) -> void:
	if payload != null and payload.is_valid():
		var _reconciliation_error: Error = reconcile_progress()


func _on_discovery_progress_changed(payload: DiscoveryProgressChangedData) -> void:
	if payload != null and payload.is_valid():
		var _reconciliation_error: Error = reconcile_progress()
