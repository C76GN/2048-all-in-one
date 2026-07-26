## LimitedMoveLevelCatalogUtility: 连接 GFLevelCatalog 与项目层限步关卡资源。
class_name LimitedMoveLevelCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const CATALOG_PATH: String = "res://features/levels/resources/limited_move_level_catalog.tres"
const EXPECTED_LEVEL_COUNT: int = 10
const _DEFINITION_PATH_KEY: StringName = &"definition_path"


# --- 私有变量 ---

var _catalog: GFLevelCatalog
var _definitions: Dictionary = {}


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFLevelUtility]


func ready() -> void:
	var catalog_resource: Resource = load(CATALOG_PATH)
	if catalog_resource is GFLevelCatalog:
		_catalog = catalog_resource
	if not get_validation_report().is_ok():
		push_error("[LimitedMoveLevelCatalogUtility] 原创限步关卡目录校验失败。")
		_catalog = null
		_definitions.clear()
		return

	var level_utility: GFLevelUtility = _get_level_utility()
	if not is_instance_valid(level_utility):
		push_error("[LimitedMoveLevelCatalogUtility] GFLevelUtility 未注册。")
		return
	level_utility.set_catalog(_catalog)


func dispose() -> void:
	var level_utility: GFLevelUtility = _get_level_utility()
	if is_instance_valid(level_utility) and level_utility.get_catalog() == _catalog:
		level_utility.set_catalog(null)
	_catalog = null
	_definitions.clear()


# --- 公共方法 ---

func get_catalog() -> GFLevelCatalog:
	return _catalog


func get_levels() -> Array[GFLevelEntry]:
	if not is_instance_valid(_catalog):
		return []
	return _catalog.get_levels(LimitedMoveLevelDefinition.PACK_ID)


func get_definition(level_id: StringName) -> LimitedMoveLevelDefinition:
	var cached_value: Variant = _definitions.get(level_id)
	if cached_value is LimitedMoveLevelDefinition:
		return cached_value
	if not is_instance_valid(_catalog):
		return null
	var entry: GFLevelEntry = _catalog.get_entry(level_id)
	if not is_instance_valid(entry):
		return null
	var definition: LimitedMoveLevelDefinition = _load_definition(entry)
	if is_instance_valid(definition):
		_definitions[level_id] = definition
	return definition


func get_first_level_id() -> StringName:
	var levels: Array[GFLevelEntry] = get_levels()
	return levels[0].get_level_id() if not levels.is_empty() else &""


func get_next_level_id(level_id: StringName) -> StringName:
	if not is_instance_valid(_catalog):
		return &""
	return _catalog.get_next_level_id(level_id)


func get_previous_level_id(level_id: StringName) -> StringName:
	if not is_instance_valid(_catalog):
		return &""
	return _catalog.get_previous_level_id(level_id)


func has_level(level_id: StringName) -> bool:
	return get_definition(level_id) != null


## 完整校验 GF 目录与项目关卡资产之间的一致性。
func get_validation_report() -> GFValidationReport:
	_definitions.clear()
	var report: GFValidationReport = GFValidationReport.new(
		"LimitedMoveLevelCatalog",
		{&"catalog_path": CATALOG_PATH}
	)
	if not is_instance_valid(_catalog):
		var _missing_catalog: RefCounted = report.add_error(
			&"missing_catalog",
			"无法加载 GFLevelCatalog。",
			&"catalog",
			CATALOG_PATH
		)
		return report

	var levels: Array[GFLevelEntry] = _catalog.get_levels(
		LimitedMoveLevelDefinition.PACK_ID
	)
	if levels.size() != EXPECTED_LEVEL_COUNT:
		var _count_issue: RefCounted = report.add_error(
			&"unexpected_level_count",
			"原创限步关卡包必须恰好包含 %d 关。" % EXPECTED_LEVEL_COUNT,
			&"entries",
			CATALOG_PATH
		)

	var seen_sort_orders: Dictionary = {}
	for index: int in range(levels.size()):
		var entry: GFLevelEntry = levels[index]
		if entry.get_level_id() == &"":
			var _id_issue: RefCounted = report.add_error(
				&"missing_level_id",
				"GFLevelEntry.level_id 不能为空。",
				index,
				CATALOG_PATH
			)
			continue
		if entry.pack_id != LimitedMoveLevelDefinition.PACK_ID:
			var _pack_issue: RefCounted = report.add_error(
				&"invalid_pack_id",
				"GFLevelEntry.pack_id 与项目关卡包不一致。",
				entry.get_level_id(),
				CATALOG_PATH
			)
		if seen_sort_orders.has(entry.sort_order):
			var _sort_issue: RefCounted = report.add_error(
				&"duplicate_sort_order",
				"原创限步关卡 sort_order 必须唯一。",
				entry.sort_order,
				CATALOG_PATH
			)
		seen_sort_orders[entry.sort_order] = true

		var definition: LimitedMoveLevelDefinition = _load_definition(entry)
		if not is_instance_valid(definition):
			var _definition_issue: RefCounted = report.add_error(
				&"missing_definition",
				"GFLevelEntry metadata 必须引用有效限步关卡定义。",
				entry.get_level_id(),
				CATALOG_PATH
			)
			continue
		if definition.level_id != entry.get_level_id():
			var _identity_issue: RefCounted = report.add_error(
				&"definition_identity_mismatch",
				"GFLevelEntry 与关卡定义的 level_id 不一致。",
				entry.get_level_id(),
				definition.resource_path
			)
		var _merged_report: RefCounted = report.merge(
			definition.get_validation_report(),
			false
		)
		_definitions[entry.get_level_id()] = definition

		var expected_next_id: StringName = (
			levels[index + 1].get_level_id()
			if index + 1 < levels.size()
			else &""
		)
		var declared_next_ids: Array[StringName] = entry.unlocks_on_complete
		if (
			(expected_next_id == &"" and not declared_next_ids.is_empty())
			or (
				expected_next_id != &""
				and declared_next_ids != [expected_next_id]
			)
		):
			var _unlock_issue: RefCounted = report.add_error(
				&"invalid_unlock_chain",
				"每关只能解锁目录中的下一关。",
				entry.get_level_id(),
				CATALOG_PATH
			)
	return report


# --- 私有/辅助方法 ---

func _get_level_utility() -> GFLevelUtility:
	var utility_value: Object = get_utility(GFLevelUtility)
	if utility_value is GFLevelUtility:
		return utility_value
	return null


func _load_definition(entry: GFLevelEntry) -> LimitedMoveLevelDefinition:
	if not is_instance_valid(entry):
		return null
	var definition_path: String = GFVariantData.get_option_string(
		entry.metadata,
		_DEFINITION_PATH_KEY
	)
	if (
		definition_path.is_empty()
		or not ResourceLoader.exists(definition_path, "Resource")
	):
		return null
	var definition_resource: Resource = load(definition_path)
	if definition_resource is LimitedMoveLevelDefinition:
		return definition_resource
	return null
