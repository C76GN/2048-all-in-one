## AssetSlotMap: 维护主题、音频、shader 等稳定用途槽位到素材的映射。
class_name AssetSlotMap
extends Resource


# --- 导出变量 ---

@export var map_id: StringName = &"c76.asset_slots.default"
@export var display_name: String = "Default Asset Slot Map"
@export var bindings: Array[Resource] = []
@export var updated_at: String = ""
@export var notes: String = ""


# --- 公共方法 ---

## 查找指定用途槽位。
## @param slot_id: 稳定用途槽位 ID。
func find_binding(slot_id: StringName) -> Resource:
	for binding: Resource in bindings:
		if binding != null and _get_binding_slot_id(binding) == slot_id:
			return binding
	return null


## 写入或替换一个用途槽位绑定。
## @param binding: 要保存的槽位绑定。
func upsert_binding(binding: Resource) -> void:
	var slot_id: StringName = _get_binding_slot_id(binding)
	if binding == null or slot_id == &"":
		return
	for index: int in range(bindings.size()):
		var existing: Resource = bindings[index]
		if existing != null and _get_binding_slot_id(existing) == slot_id:
			bindings[index] = binding
			return
	bindings.append(binding)


func get_bound_count() -> int:
	var count: int = 0
	for binding: Resource in bindings:
		if binding != null and _binding_has_runtime_binding(binding):
			count += 1
	return count


# --- 私有/辅助方法 ---

func _get_binding_slot_id(binding: Resource) -> StringName:
	if binding == null:
		return &""
	var value: Variant = binding.get("slot_id")
	return GFVariantData.to_string_name(value)


func _binding_has_runtime_binding(binding: Resource) -> bool:
	if binding == null:
		return false
	var asset_key_value: Variant = binding.get("current_asset_key")
	var library_path_value: Variant = binding.get("current_library_path")
	return (
		GFVariantData.to_string_name(asset_key_value) != &""
		or not GFVariantData.to_text(library_path_value).is_empty()
	)
