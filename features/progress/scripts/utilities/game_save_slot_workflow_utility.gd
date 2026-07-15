## GameSaveSlotWorkflowUtility: 项目存档槽工作流 Adapter。
##
## 把 GFSaveSlotWorkflow、GFSaveSlotMetadata、GFSaveSlotCard 和 GFSaveSlotStorageAdapter
## 组合成项目稳定的“玩家统计槽”Interface，让 SaveSystem 不需要了解槽位元数据细节。
class_name GameSaveSlotWorkflowUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const MAIN_STATS_SLOT_INDEX: int = 0
const STATS_SCHEMA_ID: StringName = &"game_stats"
const STATS_SCHEMA_VERSION: int = 2
const _SLOT_ID_TEMPLATE: String = "profile_{index}"
const _SLOT_ROLE: StringName = &"profile"
const _EMPTY_DISPLAY_NAME_TEMPLATE: String = "Profile {index}"
const _DISPLAY_NAME: String = "2048 Stats"
const _PROJECT_VERSION_SETTING: String = "application/config/version"


# --- 私有变量 ---

var _workflow: GFSaveSlotWorkflow
var _slot_store: GFSaveSlotStorageAdapter


# --- GF 生命周期方法 ---

func init() -> void:
	_workflow = _create_workflow()
	_slot_store = GFSaveSlotStorageAdapter.new()


func ready() -> void:
	_slot_store = _slot_store.setup(_get_storage_utility())


func dispose() -> void:
	_slot_store = null
	_workflow = null


# --- 公共方法 ---

## 保存玩家统计载荷到 GF 存档槽。
## @param payload: SaveSystem 维护的统计载荷。
## @return: Godot Error 结果码。
func save_stats_payload(payload: Dictionary) -> Error:
	if not _is_slot_store_configured():
		return ERR_UNCONFIGURED
	if payload.size() != 1 or not (GFVariantData.get_option_value(payload, "stats") is Dictionary):
		return ERR_INVALID_DATA
	var metadata: GFSaveSlotMetadata = build_stats_metadata(payload)
	return _slot_store.save_slot(MAIN_STATS_SLOT_INDEX, payload, metadata.to_dict(true))


## 读取玩家统计载荷。
## @return: SaveSystem 统计载荷；无槽位时返回空字典。
func load_stats_payload() -> Dictionary:
	if not has_stats_payload():
		return {}
	var metadata: Dictionary = _slot_store.load_slot_metadata(MAIN_STATS_SLOT_INDEX)
	if not _is_current_stats_metadata(metadata):
		return {}
	var payload: Dictionary = _slot_store.load_slot(MAIN_STATS_SLOT_INDEX)
	var stats_value: Variant = GFVariantData.get_option_value(payload, "stats")
	if not (stats_value is Dictionary):
		return {}
	return {
		"stats": GFVariantData.as_dictionary(stats_value).duplicate(true),
	}


## 查询当前 GF 槽位是否具备完整的数据和元数据文件。
func has_stats_payload() -> bool:
	return _is_slot_store_configured() and _slot_store.has_slot(MAIN_STATS_SLOT_INDEX)


## 删除玩家统计槽。
## @return: Godot Error 结果码。
func delete_stats_payload() -> Error:
	if not _is_slot_store_configured():
		return ERR_UNCONFIGURED
	return _slot_store.delete_slot(MAIN_STATS_SLOT_INDEX)


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
## @return: GF 存档槽卡片。
func build_stats_card() -> GFSaveSlotCard:
	if not _is_slot_store_configured():
		return _get_workflow().build_empty_card(MAIN_STATS_SLOT_INDEX)
	var cards: Array[GFSaveSlotCard] = _get_workflow().build_cards_from_slot_store(
		_slot_store,
		[MAIN_STATS_SLOT_INDEX]
	)
	if cards.is_empty():
		return _get_workflow().build_empty_card(MAIN_STATS_SLOT_INDEX)
	return cards[0]


func get_debug_snapshot() -> Dictionary:
	return {
		"slot_index": MAIN_STATS_SLOT_INDEX,
		"slot_id": String(_get_workflow().get_slot_id_for_index(MAIN_STATS_SLOT_INDEX)),
		"schema_id": String(STATS_SCHEMA_ID),
		"schema_version": STATS_SCHEMA_VERSION,
		"storage_configured": _is_slot_store_configured(),
		"data_file_template": _slot_store.data_file_template if _slot_store != null else "",
		"metadata_file_template": _slot_store.metadata_file_template if _slot_store != null else "",
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


func _is_slot_store_configured() -> bool:
	return _slot_store != null and _slot_store.get_storage() != null


func _is_current_stats_metadata(metadata_data: Dictionary) -> bool:
	var metadata: GFSaveSlotMetadata = GFSaveSlotMetadata.from_dict(metadata_data)
	return (
		metadata.schema_id == STATS_SCHEMA_ID
		and metadata.schema_version == STATS_SCHEMA_VERSION
	)


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


func _get_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null
