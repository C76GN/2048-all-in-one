## AssetSlotBinding: 将一个稳定用途槽位绑定到当前采用的素材。
class_name AssetSlotBinding
extends Resource


# --- 导出变量 ---

@export var slot_id: StringName = &""
@export var display_name: String = ""
@export var expected_kind: StringName = &"other"
@export var current_asset_key: StringName = &""
@export var current_library_path: String = ""
@export var fallback_asset_key: StringName = &""
@export var candidate_asset_ids: PackedStringArray = PackedStringArray()
@export var tags: PackedStringArray = PackedStringArray()
@export var notes: String = ""


# --- 公共方法 ---

func has_runtime_binding() -> bool:
	return current_asset_key != &"" or not current_library_path.is_empty()


func get_binding_text() -> String:
	if current_asset_key != &"":
		return String(current_asset_key)
	if not current_library_path.is_empty():
		return current_library_path
	return "<unbound>"
