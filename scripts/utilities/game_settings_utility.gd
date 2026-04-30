## GameSettingsUtility: 项目设置工具，过滤存储层保留元信息。
class_name GameSettingsUtility
extends GFSettingsUtility


# --- 公共方法 ---

func to_dict(persistent_only: bool = true) -> Dictionary:
	var data := super.to_dict(persistent_only)
	data.erase(GFStorageCodec.META_KEY)
	return data


func from_dict(data: Dictionary, emit_changes: bool = true) -> void:
	var clean_data := data.duplicate(true)
	clean_data.erase(GFStorageCodec.META_KEY)
	super.from_dict(clean_data, emit_changes)
