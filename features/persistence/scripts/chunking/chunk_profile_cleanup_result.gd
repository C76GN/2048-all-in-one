## 一次 chunk logical family 回收的不可变 typed 物理终态。
class_name ChunkProfileCleanupResult
extends RefCounted


# --- 常量 ---

const STATUS_CLEANED: StringName = &"cleaned"
const STATUS_PARTIAL_FAILURE: StringName = &"partial_failure"
const STATUS_CANCELLED: StringName = &"cancelled"
const STATUS_INVALID_REQUEST: StringName = &"invalid_request"
const STATUS_BUSY: StringName = &"busy"


# --- 私有变量 ---

var _status: StringName = STATUS_INVALID_REQUEST
var _error_code: Error = ERR_INVALID_PARAMETER
var _error: String = ""
var _total_count: int = 0
var _deleted_count: int = 0
var _not_found_count: int = 0
var _failed_count: int = 0
var _skipped_count: int = 0
var _caller_outcome_unknown_count: int = 0
var _first_failed_bank: StringName = ChunkManifest.BANK_NONE
var _first_failed_chunk_index: int = -1
var _first_delete_failure_kind: GFStorageDeleteResult.FailureKind = (
	GFStorageDeleteResult.FailureKind.NONE
)


# --- 公共方法 ---

## 创建隔离终态。
## @param status: STATUS_* 常量之一。
## @param error_code: 非成功终态对应的 Godot Error 码。
## @param error: 非成功终态对应的稳定错误摘要。
## @param total_count: 本次请求包含的派生身份总数。
## @param deleted_count: 物理删除成功的身份数量。
## @param not_found_count: 删除时已不存在的身份数量。
## @param failed_count: 物理删除失败的身份数量。
## @param skipped_count: 未获得物理删除结果的身份数量。
## @param caller_outcome_unknown_count: caller 层进入 outcome-unknown 的删除数量。
## @param first_failed_bank: 首个物理失败身份所属的 A/B bank。
## @param first_failed_chunk_index: 首个物理失败身份的 chunk 序号。
## @param first_delete_failure_kind: 首个 GFStorage delete 失败分类。
static func create(
	status: StringName,
	error_code: Error,
	error: String,
	total_count: int,
	deleted_count: int,
	not_found_count: int,
	failed_count: int,
	skipped_count: int,
	caller_outcome_unknown_count: int,
	first_failed_bank: StringName = ChunkManifest.BANK_NONE,
	first_failed_chunk_index: int = -1,
	first_delete_failure_kind: GFStorageDeleteResult.FailureKind = (
		GFStorageDeleteResult.FailureKind.NONE
	)
) -> ChunkProfileCleanupResult:
	var result: ChunkProfileCleanupResult = ChunkProfileCleanupResult.new()
	result._status = status
	result._error_code = OK if status == STATUS_CLEANED else error_code
	result._error = "" if status == STATUS_CLEANED else error.strip_edges()
	result._total_count = maxi(total_count, 0)
	result._deleted_count = maxi(deleted_count, 0)
	result._not_found_count = maxi(not_found_count, 0)
	result._failed_count = maxi(failed_count, 0)
	result._skipped_count = maxi(skipped_count, 0)
	result._caller_outcome_unknown_count = maxi(
		caller_outcome_unknown_count,
		0
	)
	result._first_failed_bank = first_failed_bank
	result._first_failed_chunk_index = first_failed_chunk_index
	result._first_delete_failure_kind = first_delete_failure_kind
	return result


func is_successful() -> bool:
	return _status == STATUS_CLEANED


func get_status() -> StringName:
	return _status


func get_error_code() -> Error:
	return _error_code


func get_error() -> String:
	return _error


func get_total_count() -> int:
	return _total_count


func get_deleted_count() -> int:
	return _deleted_count


func get_not_found_count() -> int:
	return _not_found_count


func get_failed_count() -> int:
	return _failed_count


func get_skipped_count() -> int:
	return _skipped_count


func get_caller_outcome_unknown_count() -> int:
	return _caller_outcome_unknown_count


func get_first_failed_bank() -> StringName:
	return _first_failed_bank


func get_first_failed_chunk_index() -> int:
	return _first_failed_chunk_index


func get_first_delete_failure_kind() -> GFStorageDeleteResult.FailureKind:
	return _first_delete_failure_kind


func duplicate_result() -> ChunkProfileCleanupResult:
	return ChunkProfileCleanupResult.create(
		_status,
		_error_code,
		_error,
		_total_count,
		_deleted_count,
		_not_found_count,
		_failed_count,
		_skipped_count,
		_caller_outcome_unknown_count,
		_first_failed_bank,
		_first_failed_chunk_index,
		_first_delete_failure_kind
	)


## 返回不含 Profile ID、logical 文件名或物理路径的诊断。
func to_dict() -> Dictionary:
	return {
		&"ok": is_successful(),
		&"status": _status,
		&"error_code": int(_error_code),
		&"error": _error,
		&"total_count": _total_count,
		&"deleted_count": _deleted_count,
		&"not_found_count": _not_found_count,
		&"failed_count": _failed_count,
		&"skipped_count": _skipped_count,
		&"caller_outcome_unknown_count": _caller_outcome_unknown_count,
		&"first_failed_bank": _first_failed_bank,
		&"first_failed_chunk_index": _first_failed_chunk_index,
		&"first_delete_failure_kind": int(_first_delete_failure_kind),
	}
