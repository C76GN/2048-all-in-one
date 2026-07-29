## LocalAccountOperationResult: 本地账号事务的不可变类型化终态。
class_name LocalAccountOperationResult
extends RefCounted


# --- 常量 ---

const STATUS_SUCCEEDED: StringName = &"succeeded"
const STATUS_INVALID_REQUEST: StringName = &"invalid_request"
const STATUS_BUSY: StringName = &"busy"
const STATUS_PROFILE_FAILED: StringName = &"profile_failed"
const STATUS_PROFILE_OUTCOME_UNKNOWN: StringName = &"profile_outcome_unknown"
const STATUS_CATALOG_FAILED: StringName = &"catalog_failed"
const STATUS_CATALOG_OUTCOME_UNKNOWN: StringName = &"catalog_outcome_unknown"
const STATUS_CLEANUP_FAILED: StringName = &"cleanup_failed"
const STATUS_CLEANUP_OUTCOME_UNKNOWN: StringName = &"cleanup_outcome_unknown"
const STATUS_ROLLBACK_FAILED: StringName = &"rollback_failed"
const STATUS_DISPOSED: StringName = &"disposed"


# --- 私有变量 ---

var _operation: StringName = &""
var _status: StringName = STATUS_INVALID_REQUEST
var _error_code: Error = ERR_INVALID_PARAMETER
var _account: LocalPlayerAccount = null
var _previous_account_id: String = ""
var _profile_evidence: Dictionary = {}
var _catalog_evidence: Dictionary = {}


# --- 公共方法 ---

func is_successful() -> bool:
	return _status == STATUS_SUCCEEDED and _error_code == OK


func get_operation() -> StringName:
	return _operation


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


func get_previous_account_id() -> String:
	return _previous_account_id


func get_profile_evidence() -> Dictionary:
	return _profile_evidence.duplicate(true)


func get_catalog_evidence() -> Dictionary:
	return _catalog_evidence.duplicate(true)


func to_dict() -> Dictionary:
	return {
		&"operation": String(_operation),
		&"status": String(_status),
		&"error_code": int(_error_code),
		&"account": _account.to_dict() if _account != null else {},
		&"previous_account_id": _previous_account_id,
		&"profile_evidence": _profile_evidence.duplicate(true),
		&"catalog_evidence": _catalog_evidence.duplicate(true),
	}


func duplicate_result() -> LocalAccountOperationResult:
	var result: LocalAccountOperationResult = LocalAccountOperationResult.new()
	var _configured: bool = result.configure_for_system(
		_operation,
		_status,
		_error_code,
		_account,
		_previous_account_id,
		_profile_evidence,
		_catalog_evidence
	)
	return result


# --- 公共方法（System 协议） ---

## 由 LocalAccountSystem 初始化不可变终态。
## @param operation: 账号事务类型。
## @param status: 规范业务终态。
## @param error_code: 与终态对应的 Godot 错误码。
## @param account: 成功或失败证据关联的账号快照。
## @param previous_account_id: 事务开始前的活动账号标识。
## @param profile_evidence: GF Profile 操作的终态证据。
## @param catalog_evidence: 账号目录写入的终态证据。
func configure_for_system(
	operation: StringName,
	status: StringName,
	error_code: Error,
	account: LocalPlayerAccount = null,
	previous_account_id: String = "",
	profile_evidence: Dictionary = {},
	catalog_evidence: Dictionary = {}
) -> bool:
	if _operation != &"" or operation == &"":
		return false
	_operation = operation
	_status = status
	_error_code = error_code
	_account = (
		LocalPlayerAccount.from_dict(account.to_dict())
		if account != null
		else null
	)
	_previous_account_id = previous_account_id
	_profile_evidence = profile_evidence.duplicate(true)
	_catalog_evidence = catalog_evidence.duplicate(true)
	return true
