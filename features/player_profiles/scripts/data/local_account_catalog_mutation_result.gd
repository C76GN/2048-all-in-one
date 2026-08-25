## LocalAccountCatalogMutationResult: 单次设备账号目录事务的不可变类型化终态。
class_name LocalAccountCatalogMutationResult
extends RefCounted


# --- 常量 ---

const STATUS_SUCCEEDED: StringName = &"succeeded"
const STATUS_FAILED: StringName = &"failed"
const STATUS_OUTCOME_UNKNOWN: StringName = &"outcome_unknown"


# --- 私有变量 ---

var _action: StringName = &""
var _status: StringName = STATUS_FAILED
var _error_code: Error = ERR_INVALID_PARAMETER
var _account: LocalPlayerAccount = null
var _storage_evidence: Dictionary = {}


# --- 公共方法 ---

func is_successful() -> bool:
	return _status == STATUS_SUCCEEDED and _error_code == OK


func is_outcome_unknown() -> bool:
	return _status == STATUS_OUTCOME_UNKNOWN


func get_action() -> StringName:
	return _action


func get_status() -> StringName:
	return _status


func get_error_code() -> Error:
	return _error_code


func get_account() -> LocalPlayerAccount:
	return (
		LocalPlayerAccount.from_dict(_account.to_dict())
		if _account != null
		else null
	)


func get_storage_evidence() -> Dictionary:
	return _storage_evidence.duplicate(true)


func to_dict() -> Dictionary:
	return {
		&"action": String(_action),
		&"status": String(_status),
		&"error_code": int(_error_code),
		&"account": _account.to_dict() if _account != null else {},
		&"storage_evidence": _storage_evidence.duplicate(true),
	}


func duplicate_result() -> LocalAccountCatalogMutationResult:
	var result: LocalAccountCatalogMutationResult = (
		LocalAccountCatalogMutationResult.new()
	)
	var _configured: bool = result.configure_for_catalog(
		_action,
		_status,
		_error_code,
		_account,
		_storage_evidence
	)
	return result


# --- 公共方法（Catalog 协议） ---

## 由 LocalAccountCatalogUtility 初始化唯一终态。
## @param action: 目录事务类型。
## @param status: STATUS_* 类型化终态。
## @param error_code: 与终态对应的 Godot 错误码。
## @param account: 事务完成后的相关账号快照；没有单一相关账号时可为空。
## @param storage_evidence: 本次请求的隔离 GFStorage 终态证据。
func configure_for_catalog(
	action: StringName,
	status: StringName,
	error_code: Error,
	account: LocalPlayerAccount = null,
	storage_evidence: Dictionary = {}
) -> bool:
	if _action != &"" or action == &"":
		return false
	if status not in [STATUS_SUCCEEDED, STATUS_FAILED, STATUS_OUTCOME_UNKNOWN]:
		return false
	if (status == STATUS_SUCCEEDED) != (error_code == OK):
		return false
	_action = action
	_status = status
	_error_code = error_code
	_account = (
		LocalPlayerAccount.from_dict(account.to_dict())
		if account != null
		else null
	)
	_storage_evidence = storage_evidence.duplicate(true)
	return true
