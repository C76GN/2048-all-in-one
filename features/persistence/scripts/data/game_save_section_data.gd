## GameSaveSectionData: 玩家 Profile section 的项目业务协议。
##
## 每个 Feature 通过子类拥有自己的业务 schema；GFSaveSectionProvider 负责
## section 身份、采集、事务应用与回滚协议，本类只补充项目使用的严格字典入口。
class_name GameSaveSectionData
extends GFSaveSectionProvider


# --- 公共方法 ---

## 获取业务数据副本，不暴露内部可变引用。
func get_section_data() -> Dictionary:
	var isolated_value: Variant = GFVariantData.duplicate_variant(
		_gather_section_data(),
		true,
		false
	)
	if not isolated_value is Dictionary:
		return {}
	return GFVariantData.as_dictionary(isolated_value)


## 获取不进入持久化文档、可跨帧持有的 Feature 运行时缓存快照。
##
## 返回值必须与 provider 内部可变对象隔离，调用方拥有该快照并可安全缓存；
## 默认回退到隔离的业务字典，需要复用已验证对象的 provider 可重写对应钩子。
func get_runtime_section_cache_snapshot() -> Dictionary:
	return _make_runtime_section_cache_snapshot()


## 构造只读编辑候选；调用方只能替换根容器，不得修改任何嵌套别名。
##
## 默认返回完全隔离副本。持有不可变规范 envelope 的 provider 可重写钩子，
## 只复制待编辑根，以免每次小修改都递归复制大型二进制载荷。
func make_immutable_edit_candidate() -> Dictionary:
	return _make_immutable_edit_candidate()


## 捕获事务失败时才会消费的只读回滚候选。
##
## 返回 envelope 必须在 provider 后续整体替换根状态后仍保持请求时刻内容；
## 嵌套别名只允许读取或交回 replace_from_dict()，不得原地修改。
func make_transaction_rollback_candidate() -> Dictionary:
	return {
		&"section_id": String(section_id),
		&"schema_version": schema_version,
		&"data": _make_transaction_rollback_data(),
	}


## 用当前 schema 的业务数据替换 section。
## @param data: 当前 section 的完整业务数据。
func replace_section_data(data: Dictionary) -> Error:
	if section_id == &"" or schema_version <= 0:
		return ERR_UNCONFIGURED
	var boundary_error: Error = _validate_section_data_boundary(data)
	if boundary_error != OK:
		return boundary_error
	var isolated_value: Variant = GFVariantData.duplicate_variant(
		data,
		true,
		false
	)
	if not isolated_value is Dictionary:
		return ERR_INVALID_DATA
	return _replace_section_data(
		GFVariantData.as_dictionary(isolated_value)
	)


## 接管当前 schema 的业务候选并替换 section。
##
## 成功或失败返回后，调用方都不得再读取、修改或提交 data 及其任意嵌套别名。
## 该入口只供明确的项目内 move/ownership 链路使用；普通调用必须使用
## replace_section_data() 获取调用方隔离保证。
## @param data: 唯一所有权的完整候选业务数据。
func replace_section_data_taking_ownership(data: Dictionary) -> Error:
	if section_id == &"" or schema_version <= 0:
		return ERR_UNCONFIGURED
	var boundary_error: Error = _validate_section_data_boundary(data)
	if boundary_error != OK:
		return boundary_error
	return _replace_section_data(data)


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

func _begin_save_snapshot(
	_context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	return make_completed_snapshot(get_section_data())


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


## 子类在深复制调用方数据前执行有界的根形状、数量与载荷预算校验。
##
## 此钩子不得保留或修改 data，也不得递归处理未先受数量约束的大型容器。
func _validate_section_data_boundary(_data: Dictionary) -> Error:
	return OK


## 子类构造只读编辑候选；默认复制完整业务字典。
func _make_immutable_edit_candidate() -> Dictionary:
	return get_section_data()


## 子类冻结事务回滚数据；默认返回完全隔离副本。
func _make_transaction_rollback_data() -> Dictionary:
	return get_section_data()


## 子类返回与内部状态隔离的运行时缓存快照；该结果绝不进入 GFSaveProfile。
func _make_runtime_section_cache_snapshot() -> Dictionary:
	return get_section_data()


## 子类校验完整业务数据后一次性替换内部状态。
func _replace_section_data(_data: Dictionary) -> Error:
	return ERR_UNAVAILABLE
