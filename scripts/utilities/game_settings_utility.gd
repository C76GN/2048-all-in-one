## GameSettingsUtility: 项目设置工具，过滤存储层保留元信息。
class_name GameSettingsUtility
extends "res://addons/gf/standard/utilities/settings/gf_settings_utility.gd"


# --- 公共方法 ---

## 将设置导出为字典，并移除存储层元信息。
## @param persistent_only: 是否只导出持久化设置。
func to_dict(persistent_only: bool = true) -> Dictionary:
	var data: Dictionary = super.to_dict(persistent_only)
	var _erase_result: bool = data.erase(GFStorageCodec.META_KEY)
	return data


## 从字典恢复设置，并忽略存储层元信息。
## @param data: 设置字典。
## @param emit_changes: 是否派发设置变更通知。
func from_dict(data: Dictionary, emit_changes: bool = true) -> void:
	var clean_data: Dictionary = data.duplicate(true)
	var _erase_result: bool = clean_data.erase(GFStorageCodec.META_KEY)
	super.from_dict(clean_data, emit_changes)
