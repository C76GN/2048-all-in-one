## LocalAccountOperation: 本地账号事务的一次性异步句柄。
class_name LocalAccountOperation
extends RefCounted


# --- 信号 ---

signal completed(result: LocalAccountOperationResult)


# --- 常量 ---

const OPERATION_CREATE: StringName = &"create"
const OPERATION_SWITCH: StringName = &"switch"
const OPERATION_RENAME: StringName = &"rename"
const OPERATION_DELETE: StringName = &"delete"


# --- 私有变量 ---

var _operation: StringName = &""
var _target_account_id: String = ""
var _result: LocalAccountOperationResult = null


# --- 公共方法 ---

func get_operation() -> StringName:
	return _operation


func get_target_account_id() -> String:
	return _target_account_id


func is_pending() -> bool:
	return _operation != &"" and _result == null


func is_completed() -> bool:
	return _result != null


func get_result() -> LocalAccountOperationResult:
	return _result.duplicate_result() if _result != null else null


# --- 公共方法（System 协议） ---

## 由 LocalAccountSystem 初始化一次性操作句柄。
## @param operation: 账号事务类型。
## @param target_account_id: 事务目标账号；创建操作可为空。
func configure_for_system(
	operation: StringName,
	target_account_id: String = ""
) -> bool:
	if _operation != &"":
		return false
	if operation not in [
		OPERATION_CREATE,
		OPERATION_SWITCH,
		OPERATION_RENAME,
		OPERATION_DELETE,
	]:
		return false
	_operation = operation
	_target_account_id = target_account_id
	return true


## 由 LocalAccountSystem 写入唯一终态并发布完成信号。
## @param result: 与本操作类型一致的不可变终态。
func complete_for_system(result: LocalAccountOperationResult) -> bool:
	if not is_pending() or result == null:
		return false
	if result.get_operation() != _operation:
		return false
	_result = result.duplicate_result()
	completed.emit(_result.duplicate_result())
	return true
