## TileCatalogUtility: 方块定义与组合身份的类型安全资源目录。
##
## TileDefinition 仍是内容真源；本 Utility 只负责 GF Resource Registry 接入、
## 唯一性校验和运行时组合描述投影。
class_name TileCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const DEFAULT_TILE_REGISTRY: GFResourceRegistry = preload(
	"res://features/tile_catalog/resources/registries/tile_definition_registry.tres"
)

const _CATALOG_ID: StringName = &"tile_definitions"
const _RESOURCE_GROUP_ID: StringName = &"tile_definitions"
const _RESOURCE_KEY_PREFIX: String = "game.tile_definition."
const _TYPE_HINT: String = "Resource"
const _COMPOSITION_KEY_PREFIX: String = "tile.composition."


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _tile_registry: GFResourceRegistry = DEFAULT_TILE_REGISTRY
var _definitions_by_id: Dictionary = {}
var _ordered_definition_ids: Array[StringName] = []
var _last_validation_report: GFValidationReport = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [ProjectResourceCatalogUtility]


func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		push_error("[TileCatalogUtility] ProjectResourceCatalogUtility 未注册。")
		return

	var registration_report: GFValidationReport = _resource_catalog.register_catalog(
		_CATALOG_ID,
		_tile_registry,
		_RESOURCE_KEY_PREFIX,
		_TYPE_HINT,
		_RESOURCE_GROUP_ID,
		{"registry": "tile_definition_registry"}
	)
	_last_validation_report = _build_catalog_index(registration_report)
	if not _last_validation_report.is_ok():
		push_error("[TileCatalogUtility] 方块定义目录无效：%s" % _last_validation_report.make_summary())


func dispose() -> void:
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID, true)
	_resource_catalog = null
	_definitions_by_id.clear()
	_ordered_definition_ids.clear()
	_last_validation_report = null


# --- 公共方法 ---

## 返回注册表顺序下的全部有效方块定义。
func get_definitions() -> Array[TileDefinition]:
	var result: Array[TileDefinition] = []
	for definition_id: StringName in _ordered_definition_ids:
		var definition: TileDefinition = get_definition(definition_id)
		if definition != null:
			result.append(definition)
	return result


## @param definition_id: 方块定义的稳定 ID。
func get_definition(definition_id: StringName) -> TileDefinition:
	var value: Variant = _definitions_by_id.get(definition_id)
	if value is TileDefinition:
		var definition: TileDefinition = value
		return definition
	return null


## 返回注册表顺序下的稳定定义 ID。
func get_definition_ids() -> Array[StringName]:
	return _ordered_definition_ids.duplicate()


## 返回方块定义资源路径，保持 GF Resource Registry 顺序。
func get_registered_definition_paths() -> PackedStringArray:
	if not is_instance_valid(_resource_catalog):
		return PackedStringArray()
	return _resource_catalog.get_registered_paths(_CATALOG_ID, true)


## 返回目录级校验报告。
func get_validation_report() -> GFValidationReport:
	return _last_validation_report


## 将定义与 Recipe 集合投影为图鉴可消费的只读组合描述。
## @param definition_id: 方块定义的稳定 ID。
## @param recipe_ids: 当前实际挂载的 Recipe ID。
func get_composition_descriptor(
	definition_id: StringName,
	recipe_ids: Array[StringName]
) -> Dictionary:
	var definition: TileDefinition = get_definition(definition_id)
	var normalized_recipe_ids: Array[StringName] = normalize_recipe_ids(recipe_ids)
	if definition == null or normalized_recipe_ids.is_empty():
		return {}
	for recipe_id: StringName in normalized_recipe_ids:
		if definition.get_capability_recipe(recipe_id) == null:
			return {}

	var recipe_descriptors: Array[Dictionary] = []
	for recipe_id: StringName in normalized_recipe_ids:
		var recipe: GFCapabilityRecipe = definition.get_capability_recipe(recipe_id)
		recipe_descriptors.append({
			&"recipe_id": recipe.recipe_id,
			&"display_name_key": GFVariantData.get_option_string_name(
				recipe.metadata,
				&"display_name_key"
			),
			&"visual_layer_id": GFVariantData.get_option_string_name(
				recipe.metadata,
				&"visual_layer_id"
			),
			&"audio_layer_id": GFVariantData.get_option_string_name(
				recipe.metadata,
				&"audio_layer_id"
			),
		})

	var descriptor: Dictionary = definition.to_descriptor()
	descriptor[&"composition_key"] = make_composition_key(definition_id, normalized_recipe_ids)
	descriptor[&"active_recipe_ids"] = normalized_recipe_ids
	descriptor[&"recipes"] = recipe_descriptors
	descriptor[&"presentation"] = definition.get_presentation_descriptor(normalized_recipe_ids)
	descriptor[&"is_initial_composition"] = (
		normalized_recipe_ids == normalize_recipe_ids(definition.initial_recipe_ids)
	)
	descriptor[&"definition"] = definition
	return descriptor


## 生成用于诊断和支持报告的目录快照。
func get_debug_snapshot() -> Dictionary:
	var resource_keys: PackedStringArray = PackedStringArray()
	if is_instance_valid(_resource_catalog):
		resource_keys = _resource_catalog.get_registered_resource_keys(_CATALOG_ID)
	return {
		"catalog_id": String(_CATALOG_ID),
		"definition_ids": get_definition_ids(),
		"definition_paths": get_registered_definition_paths(),
		"resource_keys": resource_keys,
		"valid": _last_validation_report != null and _last_validation_report.is_ok(),
	}


## 规范化 Recipe 集合；空 ID 或重复 ID 会使结果无效。
## @param recipe_ids: 待规范化的 Recipe ID。
static func normalize_recipe_ids(recipe_ids: Array[StringName]) -> Array[StringName]:
	var normalized: Array[StringName] = []
	for recipe_id: StringName in recipe_ids:
		if recipe_id == &"" or normalized.has(recipe_id):
			return []
		normalized.append(recipe_id)
	normalized.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return normalized


## 由定义 ID 与无序 Recipe 集合生成稳定、不暴露分隔符约束的组合键。
## @param definition_id: 方块定义的稳定 ID。
## @param recipe_ids: 当前实际挂载的 Recipe ID。
static func make_composition_key(
	definition_id: StringName,
	recipe_ids: Array[StringName]
) -> String:
	var normalized_recipe_ids: Array[StringName] = normalize_recipe_ids(recipe_ids)
	if definition_id == &"" or normalized_recipe_ids.is_empty():
		return ""
	var identity_parts: PackedStringArray = PackedStringArray([String(definition_id)])
	for recipe_id: StringName in normalized_recipe_ids:
		var _identity_appended: bool = identity_parts.append(String(recipe_id))
	return "%s%s" % [
		_COMPOSITION_KEY_PREFIX,
		"\n".join(identity_parts).sha256_text().substr(0, 24),
	]


# --- 私有/辅助方法 ---

func _build_catalog_index(registration_report: GFValidationReport) -> GFValidationReport:
	_definitions_by_id.clear()
	_ordered_definition_ids.clear()
	var report: GFValidationReport = GFValidationReport.new(
		"TileDefinitionCatalog",
		{"catalog_id": String(_CATALOG_ID)}
	)
	if registration_report == null or not registration_report.is_ok():
		var _registration_issue: RefCounted = report.add_error(
			&"catalog_registration_failed",
			"方块定义 GF Resource Registry 注册失败。",
			_CATALOG_ID
		)
		return report

	for resource_path: String in get_registered_definition_paths():
		var resource: Resource = _resource_catalog.load_resource_by_path(_CATALOG_ID, resource_path)
		if not resource is TileDefinition:
			var _type_issue: RefCounted = report.add_error(
				&"invalid_tile_definition_type",
				"方块目录条目不是 TileDefinition。",
				resource_path,
				resource_path
			)
			continue
		var definition: TileDefinition = resource
		if _definitions_by_id.has(definition.definition_id):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_tile_definition_id",
				"方块目录包含重复 definition_id：%s。" % definition.definition_id,
				definition.definition_id,
				resource_path
			)
			continue
		var definition_report: GFValidationReport = definition.get_validation_report()
		if not definition_report.is_ok():
			var _invalid_issue: RefCounted = report.add_error(
				&"invalid_tile_definition",
				"方块定义校验失败：%s。" % definition.definition_id,
				definition.definition_id,
				resource_path,
				{"validation": definition_report.to_dict()}
			)
			continue
		_definitions_by_id[definition.definition_id] = definition
		_ordered_definition_ids.append(definition.definition_id)

	if _ordered_definition_ids.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_tile_definition_catalog",
			"方块定义目录不能为空。",
			_CATALOG_ID
		)
	return report


func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null
