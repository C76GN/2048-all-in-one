## TileLabSystem: 管理玩家方块蓝图，并复用现有组合能力执行隔离沙盒交互。
class_name TileLabSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 信号 ---

signal blueprints_changed()


# --- 私有变量 ---

var _catalog: TileCatalogUtility = null
var _clock: GameClockUtility = null
var _composition: TileCompositionUtility = null
var _save_graph: GameSaveGraphUtility = null
var _recipes_by_id: Dictionary = {}
var _ambiguous_recipe_ids: Dictionary = {}
var _ordered_recipe_ids: Array[StringName] = []


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GameSaveGraphUtility,
		TileCatalogUtility,
		TileCompositionUtility,
	]


func ready() -> void:
	_clock = _resolve_clock_utility()
	_save_graph = _resolve_save_graph_utility()
	_catalog = _resolve_catalog_utility()
	_composition = _resolve_composition_utility()
	_rebuild_recipe_index()


func dispose() -> void:
	_recipes_by_id.clear()
	_ambiguous_recipe_ids.clear()
	_ordered_recipe_ids.clear()
	_catalog = null
	_clock = null
	_composition = null
	_save_graph = null


# --- 公共方法 ---

## 返回注册顺序下可作为外观基底的全部方块定义。
func get_base_definition_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		return result
	for definition: TileDefinition in catalog.get_definitions():
		result.append({
			&"definition_id": definition.definition_id,
			&"display_name_key": definition.display_name_key,
			&"visual_family_id": definition.visual_family_id,
			&"audio_family_id": definition.audio_family_id,
		})
	return result


## 返回一个基底定义声明的初始 Recipe 顺序。
## @param base_definition_id: 要查询的已登记 TileDefinition 稳定 ID。
func get_initial_recipe_ids(
	base_definition_id: StringName
) -> Array[StringName]:
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		return []
	var definition: TileDefinition = catalog.get_definition(base_definition_id)
	if definition == null:
		return []
	return definition.initial_recipe_ids.duplicate()


## 返回全局唯一 Recipe 目录，并标记它们能否加入当前选择。
## @param selected_recipe_ids: 当前保持顺序的 Recipe 清单。
func get_recipe_entries(
	selected_recipe_ids: Array[StringName] = []
) -> Array[Dictionary]:
	_ensure_recipe_index()
	var result: Array[Dictionary] = []
	for recipe_id: StringName in _ordered_recipe_ids:
		var recipe: GFCapabilityRecipe = _get_recipe(recipe_id)
		if recipe == null:
			continue
		var selected: bool = selected_recipe_ids.has(recipe_id)
		var candidate_ids: Array[StringName] = selected_recipe_ids.duplicate()
		if not selected:
			candidate_ids.append(recipe_id)
		var conflict: Dictionary = _find_recipe_capability_conflict(candidate_ids)
		result.append({
			&"recipe_id": recipe_id,
			&"display_name_key": GFVariantData.get_option_string_name(
				recipe.metadata,
				&"display_name_key"
			),
			&"selected": selected,
			&"compatible": selected or conflict.is_empty(),
			&"conflict": conflict,
		})
	return result


## 校验一组外观基底与有序 Recipe，不依赖蓝图身份或持久化时间。
## @param base_definition_id: 已登记的外观基底 TileDefinition 稳定 ID。
## @param recipe_ids: 按应用顺序排列的能力 Recipe 稳定 ID。
func validate_composition(
	base_definition_id: StringName,
	recipe_ids: Array[StringName]
) -> GFValidationReport:
	_ensure_recipe_index()
	var report: GFValidationReport = GFValidationReport.new(
		"TileLabComposition",
		{
			"base_definition_id": String(base_definition_id),
			"recipe_ids": recipe_ids.duplicate(),
		}
	)
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		var _catalog_issue: RefCounted = report.add_error(
			&"catalog_unavailable",
			"方块定义目录不可用。",
			base_definition_id
		)
		return report
	if base_definition_id == &"" or catalog.get_definition(base_definition_id) == null:
		var _base_issue: RefCounted = report.add_error(
			&"unknown_base_definition",
			"试验台蓝图引用了未知方块定义。",
			base_definition_id
		)
	if recipe_ids.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_recipe_selection",
			"试验台蓝图至少需要一个能力 Recipe。",
			&"recipe_ids"
		)

	var seen_recipe_ids: Dictionary = {}
	for recipe_id: StringName in recipe_ids:
		if recipe_id == &"":
			var _empty_id_issue: RefCounted = report.add_error(
				&"empty_recipe_id",
				"Recipe ID 不能为空。",
				&"recipe_ids"
			)
			continue
		if seen_recipe_ids.has(recipe_id):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_recipe_id",
				"试验台蓝图包含重复 Recipe：%s。" % recipe_id,
				recipe_id
			)
			continue
		seen_recipe_ids[recipe_id] = true
		if _ambiguous_recipe_ids.has(recipe_id):
			var _ambiguous_issue: RefCounted = report.add_error(
				&"ambiguous_recipe_id",
				"多个不同资源声明了同一 Recipe ID：%s。" % recipe_id,
				recipe_id
			)
			continue
		var recipe: GFCapabilityRecipe = _get_recipe(recipe_id)
		if recipe == null:
			var _missing_issue: RefCounted = report.add_error(
				&"unknown_recipe_id",
				"试验台蓝图引用了未知 Recipe：%s。" % recipe_id,
				recipe_id
			)
			continue
		var recipe_report: GFValidationReport = recipe.validate_recipe_report()
		if not recipe_report.is_ok():
			var _recipe_issue: RefCounted = report.add_error(
				&"invalid_recipe",
				"GF Capability Recipe 校验失败：%s。" % recipe_id,
				recipe_id,
				recipe.resource_path
			)

	var conflict: Dictionary = _find_recipe_capability_conflict(recipe_ids)
	if not conflict.is_empty():
		var _conflict_issue: RefCounted = report.add_error(
			&"overlapping_recipe_capability",
			"Recipe %s 与 %s 同时拥有能力 %s。" % [
				GFVariantData.get_option_string(conflict, &"owner_recipe_id"),
				GFVariantData.get_option_string(conflict, &"conflicting_recipe_id"),
				GFVariantData.get_option_string(conflict, &"capability_key"),
			],
			GFVariantData.get_option_string_name(
				conflict,
				&"conflicting_recipe_id"
			)
		)

	if report.is_ok():
		var runtime_definition: TileDefinition = _build_runtime_definition_unchecked(
			base_definition_id,
			recipe_ids
		)
		if runtime_definition == null:
			var _build_issue: RefCounted = report.add_error(
				&"runtime_definition_build_failed",
				"无法建立试验台运行时方块定义。",
				base_definition_id
			)
		else:
			var _merged_report: RefCounted = report.merge(
				runtime_definition.get_validation_report()
			)
	return report


## 校验一个当前 schema 蓝图及其方块能力组合。
## @param blueprint: 要校验的试验台蓝图。
func validate_blueprint(
	blueprint: CustomTileBlueprintData
) -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new("TileLabBlueprint")
	if blueprint == null or not blueprint.is_valid_data():
		var _shape_issue: RefCounted = report.add_error(
			&"invalid_blueprint_data",
			"试验台蓝图不符合当前严格 schema。",
			&"blueprint"
		)
		return report
	var _merged_report: RefCounted = report.merge(validate_composition(
		blueprint.base_definition_id,
		blueprint.recipe_ids
	))
	return report


## 生成仅由已登记 TileDefinition 与 GFCapabilityRecipe 组成的运行时定义。
## @param base_definition_id: 已登记的外观基底 TileDefinition 稳定 ID。
## @param recipe_ids: 按应用顺序排列的能力 Recipe 稳定 ID。
func build_runtime_definition(
	base_definition_id: StringName,
	recipe_ids: Array[StringName]
) -> TileDefinition:
	if not validate_composition(base_definition_id, recipe_ids).is_ok():
		return null
	return _build_runtime_definition_unchecked(base_definition_id, recipe_ids)


## 新建或更新一个玩家蓝图。空 ID 表示新建，非空 ID 必须已经存在。
## @param blueprint: 要持久化的新建或更新蓝图。
func save_blueprint(blueprint: CustomTileBlueprintData) -> Error:
	if blueprint == null:
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var clock: GameClockUtility = _get_clock()
	if save_graph == null or clock == null:
		return ERR_UNCONFIGURED

	var display_name: String = CustomTileBlueprintData.normalize_display_name(
		blueprint.display_name
	)
	if display_name.is_empty():
		return ERR_INVALID_DATA
	if not validate_composition(
		blueprint.base_definition_id,
		blueprint.recipe_ids
	).is_ok():
		return ERR_INVALID_DATA
	if not (
		CustomTileBlueprintData.is_preview_value_valid(blueprint.preview_left_value)
		and CustomTileBlueprintData.is_preview_value_valid(
			blueprint.preview_right_value
		)
	):
		return ERR_INVALID_DATA

	var blueprints: Array[CustomTileBlueprintData] = load_blueprints()
	var now: int = maxi(clock.get_unix_timestamp(), 1)
	var blueprint_id: String = blueprint.blueprint_id
	var created_at: int = now
	var replacing_index: int = -1
	if blueprint_id.is_empty():
		if blueprints.size() >= TileLabSaveData.MAX_BLUEPRINT_COUNT:
			return ERR_OUT_OF_MEMORY
		blueprint_id = _generate_unique_id(blueprints, now)
		if blueprint_id.is_empty():
			return FAILED
	else:
		if not GFUuid.is_valid(blueprint_id, 7):
			return ERR_INVALID_DATA
		replacing_index = _find_blueprint_index(blueprints, blueprint_id)
		if replacing_index < 0:
			return ERR_DOES_NOT_EXIST
		created_at = blueprints[replacing_index].created_at

	var candidate: CustomTileBlueprintData = CustomTileBlueprintData.new()
	candidate.blueprint_id = blueprint_id
	candidate.display_name = display_name
	candidate.base_definition_id = blueprint.base_definition_id
	candidate.recipe_ids = blueprint.recipe_ids.duplicate()
	candidate.preview_left_value = blueprint.preview_left_value
	candidate.preview_right_value = blueprint.preview_right_value
	candidate.created_at = created_at
	candidate.updated_at = maxi(now, created_at)
	var strict_candidate: CustomTileBlueprintData = (
		CustomTileBlueprintData.from_dict(candidate.to_dict())
	)
	if strict_candidate == null or not validate_blueprint(strict_candidate).is_ok():
		return ERR_INVALID_DATA

	if replacing_index >= 0:
		blueprints[replacing_index] = strict_candidate
	else:
		blueprints.append(strict_candidate)
	blueprints.sort_custom(_is_newer_blueprint)
	var replace_error: Error = save_graph.replace_section_data(
		TileLabSaveData.SECTION_ID,
		_serialize_blueprints(blueprints)
	)
	if replace_error != OK:
		return replace_error

	_copy_blueprint(strict_candidate, blueprint)
	blueprints_changed.emit()
	return OK


func load_blueprints() -> Array[CustomTileBlueprintData]:
	var result: Array[CustomTileBlueprintData] = []
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return result
	var section_data: Dictionary = save_graph.get_section_data(
		TileLabSaveData.SECTION_ID
	)
	for item_value: Variant in GFVariantData.get_option_array(
		section_data,
		"items"
	):
		if not item_value is Dictionary:
			continue
		var blueprint: CustomTileBlueprintData = (
			CustomTileBlueprintData.from_dict(
				GFVariantData.as_dictionary(item_value)
			)
		)
		if blueprint != null and validate_blueprint(blueprint).is_ok():
			result.append(blueprint)
	result.sort_custom(_is_newer_blueprint)
	return result


## @param blueprint_id: 待查询的 UUID v7。
func get_blueprint(blueprint_id: String) -> CustomTileBlueprintData:
	if not GFUuid.is_valid(blueprint_id, 7):
		return null
	for blueprint: CustomTileBlueprintData in load_blueprints():
		if blueprint.blueprint_id == blueprint_id:
			return blueprint
	return null


## @param blueprint_id: 待删除的 UUID v7。
func delete_blueprint(blueprint_id: String) -> Error:
	if not GFUuid.is_valid(blueprint_id, 7):
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED
	var blueprints: Array[CustomTileBlueprintData] = load_blueprints()
	var index: int = _find_blueprint_index(blueprints, blueprint_id)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	blueprints.remove_at(index)
	var replace_error: Error = save_graph.replace_section_data(
		TileLabSaveData.SECTION_ID,
		_serialize_blueprints(blueprints)
	)
	if replace_error == OK:
		blueprints_changed.emit()
	return replace_error


## 使用已保存或严格构造的蓝图执行左右两个方块的真实能力交互。
## @param blueprint: 提供组合定义与左右预览值的有效蓝图。
func simulate_pair(
	blueprint: CustomTileBlueprintData
) -> TileLabSimulationResult:
	if blueprint == null:
		return _make_invalid_simulation(
			ERR_INVALID_PARAMETER,
			"Blueprint is null."
		)
	return simulate_composition(
		blueprint.base_definition_id,
		blueprint.recipe_ids,
		blueprint.preview_left_value,
		blueprint.preview_right_value
	)


## 使用未保存的当前编辑值执行沙盒交互，不改变蓝图目录。
## @param base_definition_id: 已登记的外观基底 TileDefinition 稳定 ID。
## @param recipe_ids: 按应用顺序排列的能力 Recipe 稳定 ID。
## @param left_value: 左侧方块的正整数预览值。
## @param right_value: 右侧方块的正整数预览值。
func simulate_composition(
	base_definition_id: StringName,
	recipe_ids: Array[StringName],
	left_value: int,
	right_value: int
) -> TileLabSimulationResult:
	var composition: TileCompositionUtility = _get_composition()
	if composition == null:
		return _make_invalid_simulation(
			ERR_UNCONFIGURED,
			"TileCompositionUtility is unavailable."
		)
	if not (
		CustomTileBlueprintData.is_preview_value_valid(left_value)
		and CustomTileBlueprintData.is_preview_value_valid(right_value)
	):
		return _make_invalid_simulation(
			ERR_INVALID_PARAMETER,
			"Preview values are outside the supported range."
		)
	var validation: GFValidationReport = validate_composition(
		base_definition_id,
		recipe_ids
	)
	if not validation.is_ok():
		return _make_invalid_simulation(
			ERR_INVALID_DATA,
			validation.make_summary()
		)
	var definition: TileDefinition = _build_runtime_definition_unchecked(
		base_definition_id,
		recipe_ids
	)
	if definition == null:
		return _make_invalid_simulation(
			ERR_INVALID_DATA,
			"Runtime TileDefinition could not be built."
		)

	var left: TileState = composition.create_sandbox_tile(
		definition,
		left_value
	)
	if left == null:
		return _make_invalid_simulation(
			FAILED,
			"Left TileState could not be created."
		)
	var right: TileState = composition.create_sandbox_tile(
		definition,
		right_value
	)
	if right == null:
		composition.release_tile(left)
		return _make_invalid_simulation(
			FAILED,
			"Right TileState could not be created."
		)

	var result: TileLabSimulationResult = TileLabSimulationResult.new()
	result.left_before = left.to_dict()
	result.right_before = right.to_dict()
	var interaction: TileInteractionResult = (
		composition.apply_sandbox_interaction(
			left,
			right
		)
	)
	if interaction == null:
		result.status = TileLabSimulationResult.STATUS_NO_INTERACTION
		result.error_code = OK
		result.left_after = left.to_dict()
		result.right_after = right.to_dict()
	else:
		result.status = TileLabSimulationResult.STATUS_INTERACTED
		result.error_code = OK
		result.left_after = left.to_dict()
		result.right_after = right.to_dict()
		result.interaction_rule_id = interaction.interaction_rule_id
		result.feedback_cue_id = interaction.feedback_cue_id
		result.survivor_side = (
			&"left" if interaction.survivor == left else &"right"
		)
		result.result_value = interaction.survivor.value
		result.score_delta = interaction.score_delta
		result.ratio_resolution_count = interaction.ratio_resolution_count
		result.transformed = interaction.transformed

	# apply_interaction 已释放被消费方块；再次释放是幂等的，并确保存活方块不泄漏。
	composition.release_tile(left)
	composition.release_tile(right)
	return result


func get_debug_snapshot() -> Dictionary:
	return {
		"section_id": String(TileLabSaveData.SECTION_ID),
		"blueprint_count": load_blueprints().size(),
		"blueprint_limit": TileLabSaveData.MAX_BLUEPRINT_COUNT,
		"recipe_ids": _ordered_recipe_ids.duplicate(),
		"ambiguous_recipe_ids": _ambiguous_recipe_ids.keys(),
	}


# --- 私有/辅助方法 ---

func _rebuild_recipe_index() -> void:
	_recipes_by_id.clear()
	_ambiguous_recipe_ids.clear()
	_ordered_recipe_ids.clear()
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		return
	for definition: TileDefinition in catalog.get_definitions():
		for recipe: GFCapabilityRecipe in definition.capability_recipes:
			if recipe == null or recipe.recipe_id == &"":
				continue
			if not _recipes_by_id.has(recipe.recipe_id):
				_recipes_by_id[recipe.recipe_id] = recipe
				_ordered_recipe_ids.append(recipe.recipe_id)
				continue
			var existing: GFCapabilityRecipe = _get_recipe(recipe.recipe_id)
			if (
				existing != recipe
				and existing != null
				and existing.resource_path != recipe.resource_path
			):
				_ambiguous_recipe_ids[recipe.recipe_id] = true


func _ensure_recipe_index() -> void:
	if _recipes_by_id.is_empty() and _get_catalog() != null:
		_rebuild_recipe_index()


func _build_runtime_definition_unchecked(
	base_definition_id: StringName,
	recipe_ids: Array[StringName]
) -> TileDefinition:
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		return null
	var base: TileDefinition = catalog.get_definition(base_definition_id)
	if base == null:
		return null
	var recipes: Array[GFCapabilityRecipe] = []
	for recipe_id: StringName in recipe_ids:
		var recipe: GFCapabilityRecipe = _get_recipe(recipe_id)
		if recipe == null:
			return null
		recipes.append(recipe)
	var definition: TileDefinition = TileDefinition.new()
	definition.definition_id = base.definition_id
	definition.display_name_key = base.display_name_key
	definition.color_scheme_index = base.color_scheme_index
	definition.capability_recipes = recipes
	definition.initial_recipe_ids = recipe_ids.duplicate()
	definition.visual_family_id = base.visual_family_id
	definition.audio_family_id = base.audio_family_id
	definition.tags = base.tags.duplicate()
	return definition


func _find_recipe_capability_conflict(
	recipe_ids: Array[StringName]
) -> Dictionary:
	var owners: Dictionary = {}
	for recipe_id: StringName in recipe_ids:
		var recipe: GFCapabilityRecipe = _get_recipe(recipe_id)
		if recipe == null:
			continue
		for entry: GFCapabilityRecipeEntry in recipe.entries:
			var capability_key: String = _get_capability_entry_key(entry)
			if capability_key.is_empty():
				continue
			if owners.has(capability_key):
				return {
					&"capability_key": capability_key,
					&"owner_recipe_id": GFVariantData.to_string_name(
						owners[capability_key]
					),
					&"conflicting_recipe_id": recipe_id,
				}
			owners[capability_key] = recipe_id
	return {}


static func _get_capability_entry_key(
	entry: GFCapabilityRecipeEntry
) -> String:
	if entry == null:
		return ""
	if entry.capability_type != null:
		var global_name: StringName = entry.capability_type.get_global_name()
		if global_name != &"":
			return String(global_name)
		if not entry.capability_type.resource_path.is_empty():
			return entry.capability_type.resource_path
	if entry.scene != null:
		return "scene:%s" % entry.scene.resource_path
	return ""


func _get_recipe(recipe_id: StringName) -> GFCapabilityRecipe:
	var value: Variant = _recipes_by_id.get(recipe_id)
	if value is GFCapabilityRecipe:
		var recipe: GFCapabilityRecipe = value
		return recipe
	return null


func _get_catalog() -> TileCatalogUtility:
	if is_instance_valid(_catalog):
		return _catalog
	_catalog = _resolve_catalog_utility()
	return _catalog


func _get_clock() -> GameClockUtility:
	if is_instance_valid(_clock):
		return _clock
	_clock = _resolve_clock_utility()
	return _clock


func _get_composition() -> TileCompositionUtility:
	if is_instance_valid(_composition):
		return _composition
	_composition = _resolve_composition_utility()
	return _composition


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	return _save_graph


func _resolve_catalog_utility() -> TileCatalogUtility:
	var value: Object = get_utility(TileCatalogUtility)
	if value is TileCatalogUtility:
		var utility: TileCatalogUtility = value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	if value is GameClockUtility:
		var utility: GameClockUtility = value
		return utility
	return null


func _resolve_composition_utility() -> TileCompositionUtility:
	var value: Object = get_utility(TileCompositionUtility)
	if value is TileCompositionUtility:
		var utility: TileCompositionUtility = value
		return utility
	return null


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var value: Object = get_utility(GameSaveGraphUtility)
	if value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = value
		return utility
	return null


static func _serialize_blueprints(
	blueprints: Array[CustomTileBlueprintData]
) -> Dictionary:
	var items: Array[Dictionary] = []
	for blueprint: CustomTileBlueprintData in blueprints:
		if blueprint != null:
			items.append(blueprint.to_dict())
	return {
		"items": items,
	}


static func _copy_blueprint(
	source: CustomTileBlueprintData,
	target: CustomTileBlueprintData
) -> void:
	target.blueprint_id = source.blueprint_id
	target.display_name = source.display_name
	target.base_definition_id = source.base_definition_id
	target.recipe_ids = source.recipe_ids.duplicate()
	target.preview_left_value = source.preview_left_value
	target.preview_right_value = source.preview_right_value
	target.created_at = source.created_at
	target.updated_at = source.updated_at


static func _find_blueprint_index(
	blueprints: Array[CustomTileBlueprintData],
	blueprint_id: String
) -> int:
	for index: int in range(blueprints.size()):
		if blueprints[index].blueprint_id == blueprint_id:
			return index
	return -1


static func _generate_unique_id(
	blueprints: Array[CustomTileBlueprintData],
	timestamp: int
) -> String:
	var known_ids: Dictionary = {}
	for blueprint: CustomTileBlueprintData in blueprints:
		known_ids[blueprint.blueprint_id] = true
	for offset: int in range(8):
		var candidate: String = GFUuid.generate_v7(
			(timestamp * 1000) + blueprints.size() + offset
		)
		if GFUuid.is_valid(candidate, 7) and not known_ids.has(candidate):
			return candidate
	return ""


static func _is_newer_blueprint(
	left: CustomTileBlueprintData,
	right: CustomTileBlueprintData
) -> bool:
	if left.updated_at != right.updated_at:
		return left.updated_at > right.updated_at
	return left.blueprint_id > right.blueprint_id


static func _make_invalid_simulation(
	error_code: Error,
	summary: String
) -> TileLabSimulationResult:
	var result: TileLabSimulationResult = TileLabSimulationResult.new()
	result.status = TileLabSimulationResult.STATUS_INVALID
	result.error_code = error_code
	result.validation_summary = summary
	return result
