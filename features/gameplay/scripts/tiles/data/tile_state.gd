## TileState: 方块运行时状态与 GF Capability 接收者，纯数据，不依赖 Node。
class_name TileState
extends RefCounted


# --- 常量 ---

const SERIALIZATION_SCHEMA_VERSION: int = 1


# --- 公共变量 ---

## 单局内稳定的方块实例 ID，用于快照、动画映射和诊断。
var tile_id: String = ""

## 创建此方块的稳定定义 ID。
var definition_id: StringName = &""

## 当前数值。
var value: int = 0

## 当前实际挂载的 GF Capability Recipe ID，既包含初始能力也包含运行时获得能力。
var capability_recipe_ids: Array[StringName] = []

## 各 Recipe 拥有的可持久化状态，键为稳定 Recipe ID。
var capability_state: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init(
	p_value: int = 0,
	p_definition_id: StringName = &"",
	p_tile_id: String = ""
) -> void:
	value = p_value
	definition_id = p_definition_id
	tile_id = p_tile_id if not p_tile_id.is_empty() else GFUuid.generate_v7()


# --- 公共方法 ---

## 导出严格快照；能力实例本身由 TileCompositionUtility 按 definition_id 重建。
func to_dict() -> Dictionary:
	return {
		&"schema_version": SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": tile_id,
		&"definition_id": definition_id,
		&"value": value,
		&"capability_recipe_ids": capability_recipe_ids.duplicate(),
		&"capability_state": capability_state.duplicate(true),
	}


## 判断状态是否满足当前方块 schema。
func is_valid_state() -> bool:
	if not (
		GFUuid.is_valid(tile_id, 7)
		and definition_id != &""
		and value > 0
		and not capability_recipe_ids.is_empty()
	):
		return false

	var seen_recipe_ids: Dictionary = {}
	for recipe_id: StringName in capability_recipe_ids:
		if recipe_id == &"" or seen_recipe_ids.has(recipe_id):
			return false
		seen_recipe_ids[recipe_id] = true
	for state_key: Variant in capability_state:
		if not state_key is StringName or not seen_recipe_ids.has(state_key):
			return false
	return true
