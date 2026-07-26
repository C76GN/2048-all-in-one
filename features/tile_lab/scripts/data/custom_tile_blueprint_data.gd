## CustomTileBlueprintData: 玩家在试验台保存的一份严格方块组合蓝图。
class_name CustomTileBlueprintData
extends Resource


# --- 常量 ---

const SERIALIZATION_SCHEMA_VERSION: int = 1
const MAX_DISPLAY_NAME_LENGTH: int = 48
const MAX_PREVIEW_VALUE: int = 536870912


# --- 导出变量 ---

@export var blueprint_id: String = ""
@export var display_name: String = ""
@export var base_definition_id: StringName = &""
@export var recipe_ids: Array[StringName] = []
@export_range(1, MAX_PREVIEW_VALUE, 1) var preview_left_value: int = 2
@export_range(1, MAX_PREVIEW_VALUE, 1) var preview_right_value: int = 2
@export var created_at: int = 0
@export var updated_at: int = 0


# --- 公共方法 ---

## 导出当前严格 schema；未知字段由 from_dict 拒绝。
func to_dict() -> Dictionary:
	return {
		"schema_version": SERIALIZATION_SCHEMA_VERSION,
		"blueprint_id": blueprint_id,
		"display_name": display_name,
		"base_definition_id": base_definition_id,
		"recipe_ids": recipe_ids.duplicate(),
		"preview_left_value": preview_left_value,
		"preview_right_value": preview_right_value,
		"created_at": created_at,
		"updated_at": updated_at,
	}


func is_valid_data() -> bool:
	if not (
		GFUuid.is_valid(blueprint_id, 7)
		and _is_valid_display_name(display_name)
		and base_definition_id != &""
		and not recipe_ids.is_empty()
		and is_preview_value_valid(preview_left_value)
		and is_preview_value_valid(preview_right_value)
		and created_at > 0
		and updated_at >= created_at
	):
		return false
	var seen_recipe_ids: Dictionary = {}
	for recipe_id: StringName in recipe_ids:
		if recipe_id == &"" or seen_recipe_ids.has(recipe_id):
			return false
		seen_recipe_ids[recipe_id] = true
	return true


## 从当前严格 schema 恢复蓝图；不接受旧版本、额外字段或重复 Recipe。
## @param data: 当前版本的完整持久化字典。
static func from_dict(data: Dictionary) -> CustomTileBlueprintData:
	if not _has_strict_persisted_shape(data):
		return null
	if (
		GFVariantData.get_option_int(data, "schema_version")
		!= SERIALIZATION_SCHEMA_VERSION
	):
		return null

	var result: CustomTileBlueprintData = CustomTileBlueprintData.new()
	result.blueprint_id = GFVariantData.get_option_string(data, "blueprint_id")
	result.display_name = GFVariantData.get_option_string(data, "display_name")
	result.base_definition_id = GFVariantData.get_option_string_name(
		data,
		"base_definition_id"
	)
	result.recipe_ids = _get_recipe_ids(data)
	result.preview_left_value = GFVariantData.get_option_int(
		data,
		"preview_left_value"
	)
	result.preview_right_value = GFVariantData.get_option_int(
		data,
		"preview_right_value"
	)
	result.created_at = GFVariantData.get_option_int(data, "created_at")
	result.updated_at = GFVariantData.get_option_int(data, "updated_at")
	return result if result.is_valid_data() else null


## 规范化玩家输入名称；空白名称仍由调用方显式拒绝。
## @param value: 玩家输入的原始蓝图名称。
static func normalize_display_name(value: String) -> String:
	return value.strip_edges().substr(0, MAX_DISPLAY_NAME_LENGTH)


## 判断试验台预览值是否位于当前严格范围。
## @param value: 要校验的正整数预览值。
static func is_preview_value_valid(value: int) -> bool:
	return value > 0 and value <= MAX_PREVIEW_VALUE


# --- 私有/辅助方法 ---

static func _has_strict_persisted_shape(data: Dictionary) -> bool:
	if data.size() != 9:
		return false
	return (
		GFVariantData.get_option_value(data, "schema_version") is int
		and GFVariantData.get_option_value(data, "blueprint_id") is String
		and GFVariantData.get_option_value(data, "display_name") is String
		and GFVariantData.get_option_value(data, "base_definition_id") is StringName
		and GFVariantData.get_option_value(data, "recipe_ids") is Array
		and GFVariantData.get_option_value(data, "preview_left_value") is int
		and GFVariantData.get_option_value(data, "preview_right_value") is int
		and GFVariantData.get_option_value(data, "created_at") is int
		and GFVariantData.get_option_value(data, "updated_at") is int
		and _has_only_string_name_recipe_ids(
			GFVariantData.get_option_array(data, "recipe_ids")
		)
	)


static func _has_only_string_name_recipe_ids(values: Array) -> bool:
	for value: Variant in values:
		if not value is StringName:
			return false
	return true


static func _get_recipe_ids(data: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in GFVariantData.get_option_array(data, "recipe_ids"):
		var recipe_id: StringName = value
		result.append(recipe_id)
	return result


static func _is_valid_display_name(value: String) -> bool:
	return (
		not value.is_empty()
		and value == value.strip_edges()
		and value.length() <= MAX_DISPLAY_NAME_LENGTH
	)
