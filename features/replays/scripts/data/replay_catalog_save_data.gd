## ReplayCatalogSaveData: replays Feature 的严格 SaveGraph section。
class_name ReplayCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 3


# --- 私有变量 ---

var _items: Array[ReplayData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.REPLAYS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: ReplayData in _items:
		if item != null:
			serialized_items.append(item.to_dict())
	return {
		"items": serialized_items,
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not (items_value is Array):
		return ERR_INVALID_DATA

	var next_items: Array[ReplayData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in GFVariantData.as_array(items_value):
		if not (item_value is Dictionary):
			return ERR_INVALID_DATA
		var item: ReplayData = ReplayData.from_dict(GFVariantData.as_dictionary(item_value))
		if item == null or seen_ids.has(item.replay_id):
			return ERR_INVALID_DATA
		seen_ids[item.replay_id] = true
		next_items.append(item)

	next_items.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	_items = next_items
	return OK
