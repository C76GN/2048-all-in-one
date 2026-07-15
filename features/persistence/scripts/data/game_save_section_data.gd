## GameSaveSectionData: 玩家数据 SaveGraph 子作用域的数据协议。
##
## 每个 Feature 通过子类拥有自己的业务 schema；本类只统一 section 标识、
## schema 版本和 GFSaveDataSource 使用的 to_dict/replace_from_dict 协议。
class_name GameSaveSectionData
extends Resource


# --- 导出变量 ---

## SaveGraph 中的稳定子作用域标识。
@export var section_id: StringName = &""

## 当前 section 的严格 schema 版本。
@export_range(1, 2147483647, 1) var schema_version: int = 1


# --- 公共方法 ---

## 获取业务数据副本，不暴露内部可变引用。
func get_section_data() -> Dictionary:
	return _gather_section_data().duplicate(true)


## 用当前 schema 的业务数据替换 section。
## @param data: 当前 section 的完整业务数据。
func replace_section_data(data: Dictionary) -> Error:
	if section_id == &"" or schema_version <= 0:
		return ERR_UNCONFIGURED
	return _replace_section_data(data.duplicate(true))


## 生成 GFSaveDataSource 使用的严格 envelope。
func to_dict() -> Dictionary:
	return {
		"section_id": String(section_id),
		"schema_version": schema_version,
		"data": get_section_data(),
	}


## 应用 GFSaveDataSource 载荷；不接受旧 schema 或未知根字段。
## @param payload: 包含 section 标识、版本和业务数据的完整 envelope。
func replace_from_dict(payload: Dictionary) -> Error:
	if payload.size() != 3:
		return ERR_INVALID_DATA
	if not (GFVariantData.get_option_value(payload, "section_id") is String):
		return ERR_INVALID_DATA
	if not (GFVariantData.get_option_value(payload, "schema_version") is int):
		return ERR_INVALID_DATA
	if not (GFVariantData.get_option_value(payload, "data") is Dictionary):
		return ERR_INVALID_DATA
	if GFVariantData.get_option_string_name(payload, "section_id") != section_id:
		return ERR_INVALID_DATA
	if GFVariantData.get_option_int(payload, "schema_version") != schema_version:
		return ERR_INVALID_DATA

	return replace_section_data(GFVariantData.get_option_dictionary(payload, "data"))


# --- 可重写钩子 ---

## 子类返回当前业务数据。
func _gather_section_data() -> Dictionary:
	return {}


## 子类校验完整业务数据后一次性替换内部状态。
func _replace_section_data(_data: Dictionary) -> Error:
	return ERR_UNAVAILABLE
