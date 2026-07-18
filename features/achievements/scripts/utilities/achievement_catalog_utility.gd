## AchievementCatalogUtility: 成就定义的类型安全 GF Resource Registry Adapter。
class_name AchievementCatalogUtility
extends GFUtility


# --- 常量 ---

const DEFAULT_ACHIEVEMENT_REGISTRY: GFResourceRegistry = preload(
	"res://features/achievements/resources/registries/achievement_definition_registry.tres"
)

const _CATALOG_ID: StringName = &"achievement_definitions"
const _RESOURCE_GROUP_ID: StringName = &"achievement_definitions"
const _RESOURCE_KEY_PREFIX: String = "game.achievement_definition."
const _TYPE_HINT: String = "Resource"


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _registry: GFResourceRegistry = DEFAULT_ACHIEVEMENT_REGISTRY
var _definitions_by_id: Dictionary = {}
var _ordered_ids: Array[StringName] = []
var _last_validation_report: GFValidationReport = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [ProjectResourceCatalogUtility]


func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		push_error("[AchievementCatalogUtility] ProjectResourceCatalogUtility 未注册。")
		return
	var registration_report: GFValidationReport = _resource_catalog.register_catalog(
		_CATALOG_ID,
		_registry,
		_RESOURCE_KEY_PREFIX,
		_TYPE_HINT,
		_RESOURCE_GROUP_ID,
		{"registry": "achievement_definition_registry"}
	)
	_last_validation_report = _build_catalog_index(registration_report)
	if not _last_validation_report.is_ok():
		push_error(
			"[AchievementCatalogUtility] 成就定义目录无效：%s"
			% _last_validation_report.make_summary()
		)


func dispose() -> void:
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(
			_CATALOG_ID,
			true
		)
	_resource_catalog = null
	_definitions_by_id.clear()
	_ordered_ids.clear()
	_last_validation_report = null


# --- 公共方法 ---

func get_definitions() -> Array[AchievementDefinition]:
	var result: Array[AchievementDefinition] = []
	for achievement_id: StringName in _ordered_ids:
		var definition: AchievementDefinition = get_definition(achievement_id)
		if definition != null:
			result.append(definition)
	return result


## 按稳定标识获取成就定义。
## @param achievement_id: 成就定义的稳定标识。
func get_definition(achievement_id: StringName) -> AchievementDefinition:
	var value: Variant = _definitions_by_id.get(achievement_id)
	if value is AchievementDefinition:
		var definition: AchievementDefinition = value
		return definition
	return null


func get_definition_ids() -> Array[StringName]:
	return _ordered_ids.duplicate()


func get_registered_definition_paths() -> PackedStringArray:
	if not is_instance_valid(_resource_catalog):
		return PackedStringArray()
	return _resource_catalog.get_registered_paths(_CATALOG_ID, true)


func get_validation_report() -> GFValidationReport:
	return _last_validation_report


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


# --- 私有/辅助方法 ---

func _build_catalog_index(
	registration_report: GFValidationReport
) -> GFValidationReport:
	_definitions_by_id.clear()
	_ordered_ids.clear()
	var report: GFValidationReport = GFValidationReport.new(
		"AchievementDefinitionCatalog",
		{"catalog_id": String(_CATALOG_ID)}
	)
	if registration_report == null or not registration_report.is_ok():
		var _registration_issue: RefCounted = report.add_error(
			&"catalog_registration_failed",
			"成就定义 GF Resource Registry 注册失败。",
			_CATALOG_ID
		)
		return report

	var definitions: Array[AchievementDefinition] = []
	for resource_path: String in get_registered_definition_paths():
		var resource: Resource = _resource_catalog.load_resource_by_path(
			_CATALOG_ID,
			resource_path
		)
		if not resource is AchievementDefinition:
			var _type_issue: RefCounted = report.add_error(
				&"invalid_achievement_definition_type",
				"成就目录条目不是 AchievementDefinition。",
				resource_path,
				resource_path
			)
			continue
		var definition: AchievementDefinition = resource
		if _definitions_by_id.has(definition.achievement_id):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_achievement_id",
				"成就目录包含重复 achievement_id：%s。" % definition.achievement_id,
				definition.achievement_id,
				resource_path
			)
			continue
		var definition_report: GFValidationReport = definition.get_validation_report()
		if not definition_report.is_ok():
			var _invalid_issue: RefCounted = report.add_error(
				&"invalid_achievement_definition",
				"成就定义校验失败：%s。" % definition.achievement_id,
				definition.achievement_id,
				resource_path,
				{"validation": definition_report.to_dict()}
			)
			continue
		_definitions_by_id[definition.achievement_id] = definition
		definitions.append(definition)

	definitions.sort_custom(_is_definition_before)
	for definition: AchievementDefinition in definitions:
		_ordered_ids.append(definition.achievement_id)
	if _ordered_ids.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_achievement_catalog",
			"成就定义目录不能为空。",
			_CATALOG_ID
		)
	return report


static func _is_definition_before(
	left: AchievementDefinition,
	right: AchievementDefinition
) -> bool:
	if left.sort_order == right.sort_order:
		return String(left.achievement_id) < String(right.achievement_id)
	return left.sort_order < right.sort_order


func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var utility: ProjectResourceCatalogUtility = utility_value
		return utility
	return null
