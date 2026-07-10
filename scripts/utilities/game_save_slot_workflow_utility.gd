## GameSaveSlotWorkflowUtility: 项目存档槽工作流 Adapter。
##
## 把 GFSaveSlotWorkflow、GFSaveSlotMetadata、GFSaveSlotCard 和 GFStorageUtility
## 组合成项目稳定的“玩家统计槽”Interface，让 SaveSystem 不需要了解槽位元数据细节。
class_name GameSaveSlotWorkflowUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const MAIN_STATS_SLOT_INDEX: int = 0
const STATS_SCHEMA_ID: StringName = &"game_stats"
const STATS_SCHEMA_VERSION: int = 1
const _SLOT_ID_TEMPLATE: String = "profile_{index}"
const _SLOT_ROLE: StringName = &"profile"
const _EMPTY_DISPLAY_NAME_TEMPLATE: String = "Profile {index}"
const _DISPLAY_NAME: String = "2048 Stats"
const _PROJECT_VERSION_SETTING: String = "application/config/version"


# --- 私有变量 ---

var _workflow: GFSaveSlotWorkflow


# --- GF 生命周期方法 ---

func init() -> void:
	_workflow = _create_workflow()


func dispose() -> void:
	_workflow = null


# --- 公共方法 ---

## 保存玩家统计载荷到 GF 存档槽。
## @param storage: GF 存储工具。
## @param payload: SaveSystem 维护的统计载荷。
## @return: Godot Error 结果码。
func save_stats_payload(storage: GFStorageUtility, payload: Dictionary) -> Error:
	if storage == null:
		return ERR_UNCONFIGURED
	var metadata: GFSaveSlotMetadata = build_stats_metadata(payload)
	return storage.save_slot(MAIN_STATS_SLOT_INDEX, payload, metadata.to_dict(true))


## 读取玩家统计载荷。
## @param storage: GF 存储工具。
## @return: SaveSystem 统计载荷；无槽位时返回空字典。
func load_stats_payload(storage: GFStorageUtility) -> Dictionary:
	if storage == null or not storage.has_slot(MAIN_STATS_SLOT_INDEX):
		return {}
	var payload: Dictionary = storage.load_slot(MAIN_STATS_SLOT_INDEX)
	var _erase_result: bool = payload.erase(GFStorageCodec.META_KEY)
	return payload


## 删除玩家统计槽。
## @param storage: GF 存储工具。
func delete_stats_payload(storage: GFStorageUtility) -> void:
	if storage == null:
		return
	storage.delete_slot(MAIN_STATS_SLOT_INDEX)


## 构建玩家统计槽元数据。
## @param payload: SaveSystem 维护的统计载荷。
## @return: GF 存档槽元数据。
func build_stats_metadata(payload: Dictionary) -> GFSaveSlotMetadata:
	var metadata: GFSaveSlotMetadata = _get_workflow().build_slot_metadata(
		MAIN_STATS_SLOT_INDEX,
		_DISPLAY_NAME,
		_make_custom_metadata(payload)
	)
	metadata.schema_id = STATS_SCHEMA_ID
	metadata.schema_version = STATS_SCHEMA_VERSION
	metadata.app_version = _get_project_version()
	metadata.description = _make_description(payload)
	var last_played_at: int = _get_latest_played_at(payload)
	if last_played_at > 0:
		metadata.updated_at_unix = last_played_at
		if metadata.created_at_unix <= 0:
			metadata.created_at_unix = last_played_at
	return metadata


## 构建玩家统计槽 UI 摘要卡。
## @param storage: GF 存储工具。
## @return: GF 存档槽卡片。
func build_stats_card(storage: GFStorageUtility) -> GFSaveSlotCard:
	var summary: Dictionary = _find_stats_slot_summary(storage)
	return _get_workflow().build_card_for_index(MAIN_STATS_SLOT_INDEX, summary)


func get_debug_snapshot() -> Dictionary:
	return {
		"slot_index": MAIN_STATS_SLOT_INDEX,
		"slot_id": String(_get_workflow().get_slot_id_for_index(MAIN_STATS_SLOT_INDEX)),
		"schema_id": String(STATS_SCHEMA_ID),
		"schema_version": STATS_SCHEMA_VERSION,
	}


# --- 私有/辅助方法 ---

func _create_workflow() -> GFSaveSlotWorkflow:
	var workflow: GFSaveSlotWorkflow = GFSaveSlotWorkflow.new()
	workflow.slot_id_template = _SLOT_ID_TEMPLATE
	workflow.empty_display_name_template = _EMPTY_DISPLAY_NAME_TEMPLATE
	workflow.slot_role = _SLOT_ROLE
	workflow.active_slot_index = MAIN_STATS_SLOT_INDEX
	return workflow


func _get_workflow() -> GFSaveSlotWorkflow:
	if _workflow == null:
		_workflow = _create_workflow()
	return _workflow


func _find_stats_slot_summary(storage: GFStorageUtility) -> Dictionary:
	if storage == null:
		return {}
	for summary: Dictionary in storage.list_slots():
		var summary_slot_index: int = GFVariantData.get_option_int(summary, "slot_id", -1)
		if summary_slot_index == MAIN_STATS_SLOT_INDEX:
			return summary
	return {}


func _make_custom_metadata(payload: Dictionary) -> Dictionary:
	return {
		"mode_count": _count_modes(payload),
		"total_plays": _count_total_plays(payload),
		"best_score": _find_best_score(payload),
	}


func _make_description(payload: Dictionary) -> String:
	var total_plays: int = _count_total_plays(payload)
	var best_score: int = _find_best_score(payload)
	if total_plays <= 0 and best_score <= 0:
		return "No recorded games"
	return "Plays %d | Best %d" % [total_plays, best_score]


func _count_modes(payload: Dictionary) -> int:
	var stats: Dictionary = GFVariantData.get_option_dictionary(payload, "stats")
	return stats.size()


func _count_total_plays(payload: Dictionary) -> int:
	var total: int = 0
	var stats: Dictionary = GFVariantData.get_option_dictionary(payload, "stats")
	for mode_value: Variant in stats.values():
		var mode_stats: Dictionary = GFVariantData.as_dictionary(mode_value)
		for entry_value: Variant in mode_stats.values():
			var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
			total += GFVariantData.get_option_int(entry, "plays", 0)
	return total


func _find_best_score(payload: Dictionary) -> int:
	var best_score: int = 0
	var scores: Dictionary = GFVariantData.get_option_dictionary(payload, "scores")
	for mode_scores_value: Variant in scores.values():
		var mode_scores: Dictionary = GFVariantData.as_dictionary(mode_scores_value)
		for score_value: Variant in mode_scores.values():
			best_score = maxi(best_score, GFVariantData.to_int(score_value, 0))

	var stats: Dictionary = GFVariantData.get_option_dictionary(payload, "stats")
	for mode_stats_value: Variant in stats.values():
		var mode_stats: Dictionary = GFVariantData.as_dictionary(mode_stats_value)
		for entry_value: Variant in mode_stats.values():
			var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
			best_score = maxi(best_score, GFVariantData.get_option_int(entry, "best_score", 0))
	return best_score


func _get_latest_played_at(payload: Dictionary) -> int:
	var latest: int = 0
	var stats: Dictionary = GFVariantData.get_option_dictionary(payload, "stats")
	for mode_stats_value: Variant in stats.values():
		var mode_stats: Dictionary = GFVariantData.as_dictionary(mode_stats_value)
		for entry_value: Variant in mode_stats.values():
			var entry: Dictionary = GFVariantData.as_dictionary(entry_value)
			latest = maxi(latest, GFVariantData.get_option_int(entry, "last_played_at", 0))
	return latest


func _get_project_version() -> String:
	return GFVariantData.to_text(ProjectSettings.get_setting(_PROJECT_VERSION_SETTING, ""))
