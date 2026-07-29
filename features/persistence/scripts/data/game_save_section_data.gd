## GameSaveSectionData: 玩家 Profile section 的项目业务协议。
##
## 每个 Feature 通过子类拥有自己的业务 schema；GFSaveSectionProvider 负责
## section 身份、采集、事务应用与回滚协议，本类只补充项目使用的严格字典入口。
class_name GameSaveSectionData
extends GFSaveSectionProvider


# --- 公共方法 ---

## 获取业务数据副本，不暴露内部可变引用。
func get_section_data() -> Dictionary:
	return _gather_section_data().duplicate(true)


## 获取不进入持久化文档、可跨帧持有的 Feature 运行时缓存快照。
##
## 返回值必须与 provider 内部可变对象隔离，调用方拥有该快照并可安全缓存；
## 默认回退到隔离的业务字典，需要复用已验证对象的 provider 可重写对应钩子。
func get_runtime_section_cache_snapshot() -> Dictionary:
	return _make_runtime_section_cache_snapshot()


## 用当前 schema 的业务数据替换 section。
## @param data: 当前 section 的完整业务数据。
func replace_section_data(data: Dictionary) -> Error:
	if section_id == &"" or schema_version <= 0:
		return ERR_UNCONFIGURED
	return _replace_section_data(data.duplicate(true))


## 生成项目工具与诊断使用的严格 envelope。
func to_dict() -> Dictionary:
	return {
		"section_id": String(section_id),
		"schema_version": schema_version,
		"data": get_section_data(),
	}


## 应用项目 envelope；不接受旧 schema 或未知根字段。
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


# --- 可重写钩子（GFSaveSectionProvider） ---

func _gather_section(_context: Dictionary = {}) -> GFSaveSection:
	return make_section(get_section_data())


func _capture_section(_context: Dictionary = {}) -> GFSaveSection:
	return make_section(get_section_data())


func _apply_section(
	section: GFSaveSection,
	_context: Dictionary = {}
) -> Error:
	if section == null:
		return ERR_INVALID_DATA
	var payload: Variant = section.get_payload()
	if not payload is Dictionary:
		return ERR_INVALID_DATA
	return replace_section_data(GFVariantData.as_dictionary(payload))


func _rollback_section(
	previous_section: GFSaveSection,
	context: Dictionary = {}
) -> Error:
	return _apply_section(previous_section, context)


## 子类返回当前业务数据。
func _gather_section_data() -> Dictionary:
	return {}


## 子类返回与内部状态隔离的运行时缓存快照；该结果绝不进入 GFSaveProfile。
func _make_runtime_section_cache_snapshot() -> Dictionary:
	return get_section_data()


## 子类校验完整业务数据后一次性替换内部状态。
func _replace_section_data(_data: Dictionary) -> Error:
	return ERR_UNAVAILABLE
