## TileCompositionUtility: 使用 GF Capability Recipe 创建、恢复与解析组合方块。
class_name TileCompositionUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

## 有效方块被创建、恢复或改变组合后发出，供图鉴等外部 Feature 观察。
signal tile_composition_observed(tile: TileState)


# --- 私有变量 ---

var _capability_utility: GFCapabilityUtility = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFCapabilityUtility]


func ready() -> void:
	var utility_value: Variant = get_utility(GFCapabilityUtility)
	if utility_value is GFCapabilityUtility:
		_capability_utility = utility_value


func dispose() -> void:
	_capability_utility = null


# --- 公共方法 ---

## 按定义创建方块并以事务方式挂载 GF Capability Recipe。
## @param definition: 方块的稳定资产定义。
## @param value: 方块初始数值。
## @param tile_id: 可选的既有 UUID v7；为空时生成新 ID。
## @param capability_state: 需要随方块持久化的能力状态。
func create_tile(
	definition: TileDefinition,
	value: int,
	tile_id: String = "",
	capability_state: Dictionary = {}
) -> TileState:
	if not _is_definition_valid(definition) or value <= 0:
		return null
	var tile: TileState = TileState.new(value, definition.definition_id, tile_id)
	tile.capability_state = capability_state.duplicate(true)
	if not _mount_recipe_ids(tile, definition, definition.initial_recipe_ids):
		release_tile(tile)
		return null
	if not tile.is_valid_state():
		release_tile(tile)
		return null
	_emit_observation(tile)
	return tile


## 从严格快照恢复方块并重新挂载能力配方。
## @param data: TileState 的序列化字典。
## @param definition: 与快照 definition_id 对应的定义。
func restore_tile(data: Dictionary, definition: TileDefinition) -> TileState:
	if not _has_strict_snapshot_shape(data):
		return null
	var schema_version: int = data[&"schema_version"]
	var tile_id: String = data[&"tile_id"]
	var definition_id: StringName = data[&"definition_id"]
	var value: int = data[&"value"]
	if (
		schema_version != TileState.SERIALIZATION_SCHEMA_VERSION
		or not GFUuid.is_valid(tile_id, 7)
		or definition == null
		or definition_id != definition.definition_id
	):
		return null
	if not _is_definition_valid(definition) or value <= 0:
		return null
	var recipe_ids: Array[StringName] = _get_recipe_ids(data)
	var tile: TileState = TileState.new(value, definition.definition_id, tile_id)
	var snapshot_capability_state: Dictionary = data[&"capability_state"]
	tile.capability_state = snapshot_capability_state.duplicate(true)
	if not _mount_recipe_ids(tile, definition, recipe_ids) or not tile.is_valid_state():
		release_tile(tile)
		return null
	_emit_observation(tile)
	return tile


## 将既有方块原子切换到另一个定义及初始能力组合。
## @param tile: 需要重新组合的方块。
## @param current_definition: 当前定义，用于失败时回滚能力。
## @param next_definition: 新方块定义。
func recompose_tile(
	tile: TileState,
	current_definition: TileDefinition,
	next_definition: TileDefinition
) -> bool:
	if (
		tile == null
		or current_definition == null
		or tile.definition_id != current_definition.definition_id
		or not current_definition.get_validation_report().is_ok()
		or next_definition == null
		or not _is_definition_valid(next_definition)
	):
		return false

	var previous_definition_id: StringName = tile.definition_id
	var previous_recipe_ids: Array[StringName] = tile.capability_recipe_ids.duplicate()
	var previous_capability_state: Dictionary = tile.capability_state.duplicate(true)
	release_tile(tile)
	tile.definition_id = next_definition.definition_id
	tile.capability_recipe_ids.clear()
	tile.capability_state.clear()
	if _mount_recipe_ids(tile, next_definition, next_definition.initial_recipe_ids):
		_emit_observation(tile)
		return true

	release_tile(tile)
	tile.definition_id = previous_definition_id
	tile.capability_recipe_ids.clear()
	tile.capability_state = previous_capability_state
	if not _mount_recipe_ids(tile, current_definition, previous_recipe_ids):
		push_error("[TileCompositionUtility] 方块重组失败且无法恢复原 Recipe 组合。")
	return false


## 在定义允许的目录内为方块授予一个 GF Capability Recipe。
## @param tile: 接收新能力的方块。
## @param definition: 方块当前定义。
## @param recipe_id: 要授予的稳定 Recipe ID。
func grant_recipe(
	tile: TileState,
	definition: TileDefinition,
	recipe_id: StringName
) -> bool:
	if (
		tile == null
		or definition == null
		or tile.definition_id != definition.definition_id
		or recipe_id == &""
		or tile.capability_recipe_ids.has(recipe_id)
	):
		return false
	var recipe: GFCapabilityRecipe = definition.get_capability_recipe(recipe_id)
	if recipe == null or not _apply_recipe(tile, recipe):
		return false
	tile.capability_recipe_ids.append(recipe_id)
	_emit_observation(tile)
	return true


## 从方块拆卸一个 GF Capability Recipe 及其持久化状态。
## @param tile: 需要拆卸能力的方块。
## @param definition: 方块当前定义。
## @param recipe_id: 要拆卸的稳定 Recipe ID。
func revoke_recipe(
	tile: TileState,
	definition: TileDefinition,
	recipe_id: StringName
) -> bool:
	if (
		tile == null
		or definition == null
		or tile.definition_id != definition.definition_id
		or not tile.capability_recipe_ids.has(recipe_id)
		or tile.capability_recipe_ids.size() <= 1
		or _capability_utility == null
	):
		return false
	var recipe: GFCapabilityRecipe = definition.get_capability_recipe(recipe_id)
	if recipe == null:
		return false
	var result: Dictionary = _capability_utility.remove_recipe(tile, recipe, false)
	if not GFVariantData.get_option_bool(result, &"ok"):
		return false
	tile.capability_recipe_ids.erase(recipe_id)
	var _erased_state: bool = tile.capability_state.erase(recipe_id)
	_sync_receiver_groups(tile, definition)
	_emit_observation(tile)
	return true


## 释放方块接收者上挂载的全部 GF Capability 状态。
## @param tile: 即将销毁或被消费的方块。
func release_tile(tile: TileState) -> void:
	if tile == null or _capability_utility == null:
		return
	_capability_utility.clear_capabilities(tile)
	_capability_utility.clear_receiver_groups(tile)


## 收集共同激活能力的提案并确定唯一结果。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func evaluate_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or _capability_utility == null:
		return null
	var proposals: Array[TileInteractionProposal] = []
	var target_types: Array[Script] = _capability_utility.get_capability_types(target)
	for capability_type: Script in _capability_utility.get_capability_types(source):
		if capability_type == null or not target_types.has(capability_type):
			continue
		if not _capability_utility.is_capability_active(source, capability_type):
			continue
		if not _capability_utility.is_capability_active(target, capability_type):
			continue
		var capability_value: Variant = _capability_utility.get_capability(source, capability_type)
		if not capability_value is TileInteractionCapability:
			continue
		var capability: TileInteractionCapability = capability_value
		var proposal: TileInteractionProposal = capability.propose_interaction(source, target)
		if proposal != null and proposal.is_valid_proposal():
			proposals.append(proposal)

	if proposals.is_empty():
		return null
	proposals.sort_custom(_proposal_precedes)
	var winner: TileInteractionProposal = proposals[0]
	for index: int in range(1, proposals.size()):
		var candidate: TileInteractionProposal = proposals[index]
		if candidate.priority != winner.priority:
			break
		if not winner.has_same_effect(candidate):
			push_error(
				"[TileCompositionUtility] 方块交互存在同优先级冲突：%s 与 %s。" % [
					winner.rule_id,
					candidate.rule_id,
				]
			)
			return null
	return winner


## 判断两个方块是否存在无冲突的交互提案。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func can_interact(source: TileState, target: TileState) -> bool:
	return evaluate_interaction(source, target) != null


## 应用仲裁后的提案并释放被消费方块的能力。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func apply_interaction(source: TileState, target: TileState) -> Dictionary:
	var proposal: TileInteractionProposal = evaluate_interaction(source, target)
	if proposal == null:
		return {}
	var survivor: TileState = (
		source
		if proposal.survivor_side == TileInteractionProposal.SurvivorSide.SOURCE
		else target
	)
	var consumed: TileState = target if survivor == source else source
	for state_key: Variant in proposal.state_patch:
		if not survivor.capability_recipe_ids.has(GFVariantData.to_string_name(state_key)):
			push_error(
				"[TileCompositionUtility] 交互状态补丁必须写入已挂载 Recipe 的命名空间。"
			)
			return {}
	survivor.value = proposal.result_value
	for key: Variant in proposal.state_patch:
		survivor.capability_state[key] = proposal.state_patch[key]
	var result: Dictionary = proposal.to_result_dictionary(source, target)
	release_tile(consumed)
	_emit_observation(survivor)
	return result


## 获取方块状态及 GF Capability 挂载报告。
## @param tile: 需要检查的方块。
func inspect_tile(tile: TileState) -> Dictionary:
	if tile == null or _capability_utility == null:
		return {&"ok": false, &"error": "tile or capability utility is unavailable"}
	var report: Dictionary = _capability_utility.inspect_receiver(tile)
	report[&"tile"] = tile.to_dict()
	return report


# --- 私有/辅助方法 ---

func _apply_recipe(tile: TileState, recipe: GFCapabilityRecipe) -> bool:
	if _capability_utility == null:
		return false
	var result: Dictionary = _capability_utility.apply_recipe(
		tile,
		recipe,
		{&"transactional": true, &"validate_after_apply": true}
	)
	return GFVariantData.get_option_bool(result, &"ok")


func _emit_observation(tile: TileState) -> void:
	if tile != null and tile.is_valid_state():
		tile_composition_observed.emit(tile)


func _mount_recipe_ids(
	tile: TileState,
	definition: TileDefinition,
	recipe_ids: Array[StringName]
) -> bool:
	if tile == null or definition == null or recipe_ids.is_empty():
		return false
	for recipe_id: StringName in recipe_ids:
		if tile.capability_recipe_ids.has(recipe_id):
			release_tile(tile)
			tile.capability_recipe_ids.clear()
			return false
		var recipe: GFCapabilityRecipe = definition.get_capability_recipe(recipe_id)
		if recipe == null or not _apply_recipe(tile, recipe):
			release_tile(tile)
			tile.capability_recipe_ids.clear()
			return false
		tile.capability_recipe_ids.append(recipe_id)
	return true


func _sync_receiver_groups(tile: TileState, definition: TileDefinition) -> void:
	if tile == null or definition == null or _capability_utility == null:
		return
	_capability_utility.clear_receiver_groups(tile)
	for recipe_id: StringName in tile.capability_recipe_ids:
		var recipe: GFCapabilityRecipe = definition.get_capability_recipe(recipe_id)
		if recipe == null:
			continue
		for group_name: StringName in recipe.groups:
			if group_name != &"":
				_capability_utility.add_receiver_to_group(tile, group_name)


static func _get_recipe_ids(data: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_recipe_id: Variant in data[&"capability_recipe_ids"]:
		var recipe_id: StringName = raw_recipe_id
		result.append(recipe_id)
	return result


static func _has_strict_snapshot_shape(data: Dictionary) -> bool:
	if data.size() != 6:
		return false
	if not (
		data.has(&"schema_version")
		and data[&"schema_version"] is int
		and data.has(&"tile_id")
		and data[&"tile_id"] is String
		and data.has(&"definition_id")
		and data[&"definition_id"] is StringName
		and data.has(&"value")
		and data[&"value"] is int
		and data.has(&"capability_recipe_ids")
		and data[&"capability_recipe_ids"] is Array
		and data.has(&"capability_state")
		and data[&"capability_state"] is Dictionary
	):
		return false
	for recipe_id: Variant in data[&"capability_recipe_ids"]:
		if not recipe_id is StringName:
			return false
	for state_key: Variant in data[&"capability_state"]:
		if not state_key is StringName:
			return false
	return true


func _is_definition_valid(definition: TileDefinition) -> bool:
	return (
		definition != null
		and definition.get_validation_report().is_ok()
	)


func _proposal_precedes(left: TileInteractionProposal, right: TileInteractionProposal) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return String(left.rule_id) < String(right.rule_id)
