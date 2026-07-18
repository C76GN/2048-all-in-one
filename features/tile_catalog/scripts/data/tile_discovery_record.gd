## TileDiscoveryRecord: 一个已发现方块组合的严格玩家进度记录。
class_name TileDiscoveryRecord
extends Resource


# --- 公共变量 ---

var composition_key: String = ""
var definition_id: StringName = &""
var recipe_ids: Array[StringName] = []
var discovered_at: int = 0
var max_observed_value: int = 0


# --- 公共方法 ---

## 创建并校验一次方块组合发现。
## @param p_definition_id: 方块定义的稳定 ID。
## @param p_recipe_ids: 实际挂载的 Recipe ID。
## @param p_discovered_at: 首次发现 Unix 时间戳。
## @param p_observed_value: 本次观察到的方块数值。
static func create(
	p_definition_id: StringName,
	p_recipe_ids: Array[StringName],
	p_discovered_at: int,
	p_observed_value: int
) -> TileDiscoveryRecord:
	var normalized_recipe_ids: Array[StringName] = TileCatalogUtility.normalize_recipe_ids(
		p_recipe_ids
	)
	var key: String = TileCatalogUtility.make_composition_key(
		p_definition_id,
		normalized_recipe_ids
	)
	if key.is_empty() or p_discovered_at <= 0 or p_observed_value <= 0:
		return null
	var record: TileDiscoveryRecord = TileDiscoveryRecord.new()
	record.composition_key = key
	record.definition_id = p_definition_id
	record.recipe_ids = normalized_recipe_ids
	record.discovered_at = p_discovered_at
	record.max_observed_value = p_observed_value
	return record


## 从当前严格 schema 恢复记录。
## @param data: 完整持久化字典。
static func from_dict(data: Dictionary) -> TileDiscoveryRecord:
	if not _has_strict_shape(data):
		return null
	var restored_recipe_ids: Array[StringName] = []
	for recipe_value: Variant in GFVariantData.get_option_array(data, "recipe_ids"):
		restored_recipe_ids.append(StringName(GFVariantData.to_text(recipe_value)))
	var record: TileDiscoveryRecord = create(
		StringName(GFVariantData.get_option_string(data, "definition_id")),
		restored_recipe_ids,
		GFVariantData.get_option_int(data, "discovered_at"),
		GFVariantData.get_option_int(data, "max_observed_value")
	)
	if record == null:
		return null
	if record.composition_key != GFVariantData.get_option_string(data, "composition_key"):
		return null
	return record


## 导出严格持久化字典。
func to_dict() -> Dictionary:
	var serialized_recipe_ids: Array[String] = []
	for recipe_id: StringName in recipe_ids:
		serialized_recipe_ids.append(String(recipe_id))
	return {
		"composition_key": composition_key,
		"definition_id": String(definition_id),
		"recipe_ids": serialized_recipe_ids,
		"discovered_at": discovered_at,
		"max_observed_value": max_observed_value,
	}


# --- 私有/辅助方法 ---

static func _has_strict_shape(data: Dictionary) -> bool:
	if not (
		data.size() == 5
		and GFVariantData.get_option_value(data, "composition_key") is String
		and GFVariantData.get_option_value(data, "definition_id") is String
		and GFVariantData.get_option_value(data, "recipe_ids") is Array
		and GFVariantData.get_option_value(data, "discovered_at") is int
		and GFVariantData.get_option_value(data, "max_observed_value") is int
	):
		return false
	for recipe_value: Variant in GFVariantData.get_option_array(data, "recipe_ids"):
		if not recipe_value is String:
			return false
	return true
