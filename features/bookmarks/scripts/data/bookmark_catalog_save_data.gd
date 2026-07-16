## BookmarkCatalogSaveData: bookmarks Feature 的严格 SaveGraph section。
class_name BookmarkCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 3


# --- 私有变量 ---

var _items: Array[BookmarkData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: BookmarkData in _items:
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

	var next_items: Array[BookmarkData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in GFVariantData.as_array(items_value):
		if not (item_value is Dictionary):
			return ERR_INVALID_DATA
		var item: BookmarkData = BookmarkData.from_dict(GFVariantData.as_dictionary(item_value))
		if item == null or seen_ids.has(item.bookmark_id):
			return ERR_INVALID_DATA
		seen_ids[item.bookmark_id] = true
		next_items.append(item)

	next_items.sort_custom(func(left: BookmarkData, right: BookmarkData) -> bool:
		return left.bookmark_id > right.bookmark_id
	)
	_items = next_items
	return OK
