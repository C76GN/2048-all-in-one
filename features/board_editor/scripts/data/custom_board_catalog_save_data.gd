## CustomBoardCatalogSaveData: board_editor Feature 的严格 SaveGraph section。
class_name CustomBoardCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 1


# --- 私有变量 ---

var _items: Array[CustomBoardData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: CustomBoardData in _items:
		if item != null:
			serialized_items.append(item.to_dict())
	return {
		"items": serialized_items,
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not items_value is Array:
		return ERR_INVALID_DATA

	var next_items: Array[CustomBoardData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in GFVariantData.as_array(items_value):
		if not item_value is Dictionary:
			return ERR_INVALID_DATA
		var item: CustomBoardData = CustomBoardData.from_dict(GFVariantData.as_dictionary(item_value))
		if item == null or seen_ids.has(item.custom_board_id):
			return ERR_INVALID_DATA
		seen_ids[item.custom_board_id] = true
		next_items.append(item)

	next_items.sort_custom(_is_newer_board)
	_items = next_items
	return OK


# --- 私有/辅助方法 ---

static func _is_newer_board(left: CustomBoardData, right: CustomBoardData) -> bool:
	if left.updated_at != right.updated_at:
		return left.updated_at > right.updated_at
	return left.custom_board_id > right.custom_board_id
