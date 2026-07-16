## TileDefinition: 方块身份、表现族与 GF Capability 配方的稳定资产定义。
class_name TileDefinition
extends Resource


# --- 导出变量 ---

@export var definition_id: StringName = &""
@export var display_name_key: StringName = &""
@export_range(0, 64, 1) var color_scheme_index: int = 0
@export var capability_recipes: Array[GFCapabilityRecipe] = []
@export var initial_recipe_ids: Array[StringName] = []
@export var visual_family_id: StringName = &""
@export var audio_family_id: StringName = &""
@export var tags: PackedStringArray = PackedStringArray()


# --- 公共方法 ---

## 按稳定 ID 解析此定义允许使用的 GF Capability Recipe。
## @param recipe_id: Recipe 的稳定 ID。
func get_capability_recipe(recipe_id: StringName) -> GFCapabilityRecipe:
	for recipe: GFCapabilityRecipe in capability_recipes:
		if recipe != null and recipe.recipe_id == recipe_id:
			return recipe
	return null


## 返回定义的初始 GF Capability Recipe，顺序与 initial_recipe_ids 一致。
func get_initial_capability_recipes() -> Array[GFCapabilityRecipe]:
	var result: Array[GFCapabilityRecipe] = []
	for recipe_id: StringName in initial_recipe_ids:
		var recipe: GFCapabilityRecipe = get_capability_recipe(recipe_id)
		if recipe != null:
			result.append(recipe)
	return result


## 根据当前 Recipe 清单生成表现与音频分层描述。
## @param active_recipe_ids: 方块当前实际挂载的 Recipe ID。
func get_presentation_descriptor(active_recipe_ids: Array[StringName]) -> Dictionary:
	var visual_layer_ids: Array[StringName] = []
	var audio_layer_ids: Array[StringName] = []
	for recipe_id: StringName in active_recipe_ids:
		var recipe: GFCapabilityRecipe = get_capability_recipe(recipe_id)
		if recipe == null:
			continue
		var visual_layer_id: StringName = GFVariantData.to_string_name(
			GFVariantData.get_option_value(recipe.metadata, &"visual_layer_id")
		)
		var audio_layer_id: StringName = GFVariantData.to_string_name(
			GFVariantData.get_option_value(recipe.metadata, &"audio_layer_id")
		)
		if visual_layer_id != &"":
			visual_layer_ids.append(visual_layer_id)
		if audio_layer_id != &"":
			audio_layer_ids.append(audio_layer_id)
	return {
		&"visual_family_id": visual_family_id,
		&"visual_layer_ids": visual_layer_ids,
		&"audio_family_id": audio_family_id,
		&"audio_layer_ids": audio_layer_ids,
	}


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"TileDefinition:%s" % String(definition_id),
		{
			"definition_id": String(definition_id),
			"resource_path": resource_path,
		}
	)
	if definition_id == &"":
		var _id_issue: RefCounted = report.add_error(
			&"missing_definition_id",
			"TileDefinition.definition_id 不能为空。",
			&"definition_id",
			resource_path
		)
	if display_name_key == &"":
		var _name_issue: RefCounted = report.add_error(
			&"missing_display_name_key",
			"TileDefinition.display_name_key 不能为空。",
			&"display_name_key",
			resource_path
		)
	_validate_capability_recipes(report)
	_validate_initial_recipe_ids(report)
	if visual_family_id == &"":
		var _visual_issue: RefCounted = report.add_error(
			&"missing_visual_family_id",
			"TileDefinition.visual_family_id 不能为空。",
			&"visual_family_id",
			resource_path
		)
	if audio_family_id == &"":
		var _audio_issue: RefCounted = report.add_error(
			&"missing_audio_family_id",
			"TileDefinition.audio_family_id 不能为空。",
			&"audio_family_id",
			resource_path
		)
	return report


func to_descriptor() -> Dictionary:
	var recipe_ids: Array[StringName] = []
	for recipe: GFCapabilityRecipe in capability_recipes:
		if recipe != null:
			recipe_ids.append(recipe.recipe_id)
	return {
		&"definition_id": definition_id,
		&"display_name_key": display_name_key,
		&"color_scheme_index": color_scheme_index,
		&"capability_recipe_ids": recipe_ids,
		&"initial_recipe_ids": initial_recipe_ids.duplicate(),
		&"visual_family_id": visual_family_id,
		&"audio_family_id": audio_family_id,
		&"tags": tags.duplicate(),
	}


# --- 私有/辅助方法 ---

func _validate_capability_recipes(report: GFValidationReport) -> void:
	if capability_recipes.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_capability_recipes",
			"TileDefinition.capability_recipes 不能为空。",
			&"capability_recipes",
			resource_path
		)
		return

	var seen_recipe_ids: Dictionary = {}
	var capability_owners: Dictionary = {}
	for recipe: GFCapabilityRecipe in capability_recipes:
		if recipe == null:
			var _null_issue: RefCounted = report.add_error(
				&"null_capability_recipe",
				"TileDefinition 包含空 GF Capability Recipe。",
				&"capability_recipes",
				resource_path
			)
			continue
		if recipe.recipe_id == &"":
			var _missing_id_issue: RefCounted = report.add_error(
				&"missing_recipe_id",
				"TileDefinition 中的 GF Capability Recipe 缺少 recipe_id。",
				&"capability_recipes",
				recipe.resource_path
			)
		elif seen_recipe_ids.has(recipe.recipe_id):
			var _duplicate_id_issue: RefCounted = report.add_error(
				&"duplicate_recipe_id",
				"TileDefinition 包含重复 Recipe ID：%s。" % recipe.recipe_id,
				recipe.recipe_id,
				recipe.resource_path
			)
		seen_recipe_ids[recipe.recipe_id] = true

		if not recipe.validate_recipe_report().is_ok():
			var _invalid_recipe_issue: RefCounted = report.add_error(
				&"invalid_capability_recipe",
				"TileDefinition 的 GF Capability Recipe 校验失败。",
				recipe.recipe_id,
				recipe.resource_path
			)
		_validate_recipe_metadata(report, recipe)
		_validate_recipe_capability_ownership(report, recipe, capability_owners)


func _validate_initial_recipe_ids(report: GFValidationReport) -> void:
	if initial_recipe_ids.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_initial_recipe_ids",
			"TileDefinition.initial_recipe_ids 不能为空。",
			&"initial_recipe_ids",
			resource_path
		)
		return

	var seen_ids: Dictionary = {}
	for recipe_id: StringName in initial_recipe_ids:
		if recipe_id == &"" or get_capability_recipe(recipe_id) == null:
			var _unknown_issue: RefCounted = report.add_error(
				&"unknown_initial_recipe_id",
				"初始 Recipe ID 不在定义目录中：%s。" % recipe_id,
				recipe_id,
				resource_path
			)
		elif seen_ids.has(recipe_id):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_initial_recipe_id",
				"初始 Recipe ID 重复：%s。" % recipe_id,
				recipe_id,
				resource_path
			)
		seen_ids[recipe_id] = true


func _validate_recipe_metadata(report: GFValidationReport, recipe: GFCapabilityRecipe) -> void:
	for metadata_key: StringName in [&"visual_layer_id", &"audio_layer_id"]:
		var metadata_value: StringName = GFVariantData.to_string_name(
			GFVariantData.get_option_value(recipe.metadata, metadata_key)
		)
		if metadata_value == &"":
			var _metadata_issue: RefCounted = report.add_error(
				&"missing_recipe_presentation_metadata",
				"方块 Recipe %s 缺少 %s。" % [recipe.recipe_id, metadata_key],
				metadata_key,
				recipe.resource_path
			)


func _validate_recipe_capability_ownership(
	report: GFValidationReport,
	recipe: GFCapabilityRecipe,
	capability_owners: Dictionary
) -> void:
	for entry: GFCapabilityRecipeEntry in recipe.entries:
		if entry == null or entry.capability_type == null:
			continue
		var capability_key: String = _get_script_key(entry.capability_type)
		if capability_key.is_empty():
			continue
		if capability_owners.has(capability_key):
			var _overlap_issue: RefCounted = report.add_error(
				&"overlapping_recipe_capability",
				"多个可拆卸 Recipe 不能共同拥有同一顶层能力：%s。" % capability_key,
				capability_key,
				recipe.resource_path
			)
		capability_owners[capability_key] = recipe.recipe_id


static func _get_script_key(script: Script) -> String:
	if script == null:
		return ""
	var global_name: StringName = script.get_global_name()
	if global_name != &"":
		return String(global_name)
	return script.resource_path
