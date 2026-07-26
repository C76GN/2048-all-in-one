## TileLabSaveData: tile_lab Feature 拥有的严格 SaveGraph section。
class_name TileLabSaveData
extends GameSaveSectionData


# --- 常量 ---

const SECTION_ID: StringName = &"tile_blueprints"
const SCHEMA_VERSION: int = 1
const MAX_BLUEPRINT_COUNT: int = 32


# --- 私有变量 ---

var _items: Array[CustomTileBlueprintData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: CustomTileBlueprintData in _items:
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
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > MAX_BLUEPRINT_COUNT:
		return ERR_OUT_OF_MEMORY

	var next_items: Array[CustomTileBlueprintData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in item_values:
		if not item_value is Dictionary:
			return ERR_INVALID_DATA
		var item: CustomTileBlueprintData = CustomTileBlueprintData.from_dict(
			GFVariantData.as_dictionary(item_value)
		)
		if item == null or seen_ids.has(item.blueprint_id):
			return ERR_INVALID_DATA
		seen_ids[item.blueprint_id] = true
		next_items.append(item)

	next_items.sort_custom(_is_newer_blueprint)
	_items = next_items
	return OK


# --- 私有/辅助方法 ---

static func _is_newer_blueprint(
	left: CustomTileBlueprintData,
	right: CustomTileBlueprintData
) -> bool:
	if left.updated_at != right.updated_at:
		return left.updated_at > right.updated_at
	return left.blueprint_id > right.blueprint_id
