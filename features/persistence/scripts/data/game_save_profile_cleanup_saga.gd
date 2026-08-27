## GameSaveProfileCleanupSaga: 一次玩家 Profile 复合清理的内部状态所有者。
##
## 它冻结主删除身份，持有 caller/派生清理的观察权，并把主 Profile 与全部
## Chunk Bank family 的终态收敛为一份路径无关、payload 无关的证据。
## GameSaveGraphUtility 只负责编排异步工作和发布已收敛终态。
class_name GameSaveProfileCleanupSaga
extends RefCounted


# --- 常量 ---

const PHASE_MAIN_DELETE: StringName = &"main_delete"
const PHASE_DERIVED_CLEANUP: StringName = &"derived_cleanup"
const PHASE_COMPLETED: StringName = &"completed"


# --- 私有变量 ---

var _request_id: int = 0
var _canonical_name: String = ""
var _cleanup_kind: StringName = &""
var _main_operation: GFStorageAsyncOperation = null
var _active_derived_operation: ChunkProfileCleanupOperation = null
var _phase: StringName = PHASE_MAIN_DELETE
var _caller_waiter_attached: bool = false
var _caller_outcome_unknown: bool = false
var _main_error: Error = OK
var _derived_error: Error = OK
var _final_error: Error = OK
var _derived_total_count: int = 0
var _derived_completed_count: int = 0
var _derived_failed_count: int = 0
var _busy_retry_count: int = 0
var _derived_results: Array[ChunkProfileCleanupResult] = []
var _derived_plan_frozen: bool = false
var _derived_setup_failed: bool = false


# --- 工厂方法 ---

## 冻结主删除身份；canonical logical name 只保留在本内部类型中。
## @param canonical_name: 主 Storage 删除操作使用的规范逻辑文件名。
## @param cleanup_kind: 标识本次复合清理来源的稳定类型。
## @param main_operation: 已发起且身份匹配的主 Profile 删除操作。
## @param observe_caller: 是否由本 Saga 持有主操作 caller waiter 的观察权。
static func create(
	canonical_name: String,
	cleanup_kind: StringName,
	main_operation: GFStorageAsyncOperation,
	observe_caller: bool
) -> GameSaveProfileCleanupSaga:
	if (
		canonical_name.is_empty()
		or cleanup_kind.is_empty()
		or main_operation == null
		or main_operation.get_request_id() <= 0
		or main_operation.get_operation()
		!= GFStorageAsyncOperation.OPERATION_DELETE
		or main_operation.get_file_name() != canonical_name
	):
		return null
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.new()
	saga._request_id = main_operation.get_request_id()
	saga._canonical_name = canonical_name
	saga._cleanup_kind = cleanup_kind
	saga._main_operation = main_operation
	saga._caller_waiter_attached = observe_caller
	return saga


# --- 查询方法 ---

func get_request_id() -> int:
	return _request_id


func get_canonical_name() -> String:
	return _canonical_name


func get_main_operation() -> GFStorageAsyncOperation:
	return _main_operation


func get_phase() -> StringName:
	return _phase


func is_waiting_for_main_delete() -> bool:
	return _phase == PHASE_MAIN_DELETE


func is_completed() -> bool:
	return _phase == PHASE_COMPLETED


func has_caller_waiter() -> bool:
	return _caller_waiter_attached


func get_final_error() -> Error:
	return _final_error if is_completed() else ERR_BUSY


func get_active_derived_operation() -> ChunkProfileCleanupOperation:
	return _active_derived_operation


# --- 状态推进方法 ---

## caller deadline 结束观察，但物理删除和派生清理 ownership 保持不变。
## @param outcome_unknown: caller 是否因截止期而无法确认物理终态。
func detach_caller_waiter(outcome_unknown: bool = false) -> bool:
	if not _caller_waiter_attached:
		return false
	_caller_waiter_attached = false
	_caller_outcome_unknown = _caller_outcome_unknown or outcome_unknown
	return true


## 主删除物理终态成功后才能进入派生 family 清理。
##
## 主删除失败会直接形成唯一终态，派生 family 必须保持未启动。
## @param main_error: 主 Profile 物理删除取得的终态错误码。
func settle_main_delete(main_error: Error) -> bool:
	if _phase != PHASE_MAIN_DELETE or not _main_operation.is_completed():
		return false
	_main_error = main_error
	if main_error == OK:
		_phase = PHASE_DERIVED_CLEANUP
	else:
		_final_error = main_error
		_phase = PHASE_COMPLETED
	return true


## 冻结当前 Profile 注册的 manifest-backed Section 数量。
## @param total_count: 本次必须闭合终态的派生 family 总数。
func begin_derived_cleanup(total_count: int) -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or total_count < 0
		or _derived_plan_frozen
	):
		return false
	_derived_total_count = total_count
	_derived_plan_frozen = true
	return true


## 派生清理依赖无法建立时，直接形成唯一 typed 终态。
##
## 此 transition 只允许发生在主删除成功、派生 plan 尚未冻结且没有活动句柄时；
## 它保证调用方无需伪造 family 计数，也不会遗留 path ownership。
## @param error_code: 派生清理 setup 的非成功错误码。
func fail_derived_setup(error_code: Error) -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or error_code == OK
		or _derived_plan_frozen
		or _active_derived_operation != null
	):
		return false
	_derived_plan_frozen = true
	_derived_setup_failed = true
	_derived_error = error_code
	_final_error = error_code
	_phase = PHASE_COMPLETED
	return true


## 绑定当前唯一派生清理句柄，供 dispose 和 tick 观察。
## @param operation: 当前 family 已发起的类型化清理操作。
func bind_active_derived_operation(
	operation: ChunkProfileCleanupOperation
) -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or operation == null
		or _active_derived_operation != null
		or not _derived_plan_frozen
		or _derived_completed_count >= _derived_total_count
	):
		return false
	_active_derived_operation = operation
	return true


## typed BUSY 不算一次 family 终态，只累计有界重试诊断。
func release_busy_derived_operation() -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or _active_derived_operation == null
		or not _active_derived_operation.is_completed()
		or _derived_completed_count >= _derived_total_count
	):
		return false
	var result: ChunkProfileCleanupResult = (
		_active_derived_operation.get_result()
	)
	if (
		result == null
		or result.get_status() != ChunkProfileCleanupResult.STATUS_BUSY
	):
		return false
	_active_derived_operation = null
	_busy_retry_count += 1
	return true


## 接纳当前 family 的 typed 物理终态，并返回其 Error。
func settle_derived_operation() -> Error:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or _active_derived_operation == null
		or not _active_derived_operation.is_completed()
		or _derived_completed_count >= _derived_total_count
	):
		return ERR_BUSY
	var result: ChunkProfileCleanupResult = (
		_active_derived_operation.get_result()
	)
	if (
		result == null
		or result.get_status() == ChunkProfileCleanupResult.STATUS_BUSY
	):
		return ERR_INVALID_DATA
	_active_derived_operation = null
	_derived_results.append(result.duplicate_result())
	_derived_completed_count += 1
	if result.is_successful():
		return OK
	_derived_failed_count += 1
	var error_code: Error = result.get_error_code()
	return error_code if error_code != OK else FAILED


## 句柄未创建或违反 typed terminal 协议时，仍闭合当前冻结 family 的计数。
## @param error_code: 用于闭合该 family 的非成功错误码。
func settle_derived_without_result(error_code: Error) -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or not _derived_plan_frozen
		or _derived_completed_count >= _derived_total_count
		or error_code == OK
		or (
			_active_derived_operation != null
			and _active_derived_operation.is_pending()
		)
	):
		return false
	_active_derived_operation = null
	_derived_completed_count += 1
	_derived_failed_count += 1
	return true


## 所有冻结的派生 family 都已取得终态后，写入复合清理唯一终态。
## @param derived_error: 全部派生 family 收敛后的聚合错误码。
func complete_derived_cleanup(derived_error: Error) -> bool:
	if (
		_phase != PHASE_DERIVED_CLEANUP
		or _active_derived_operation != null
		or not _derived_plan_frozen
		or _derived_completed_count != _derived_total_count
		or ((_derived_failed_count == 0) != (derived_error == OK))
	):
		return false
	_derived_error = derived_error
	_final_error = derived_error
	_phase = PHASE_COMPLETED
	return true


## dispose 只请求当前派生句柄取消；主 Storage 物理请求仍由 GF 持有到终态。
## @param reason: 提交给当前派生清理操作的稳定取消原因。
func request_active_derived_cancel(reason: StringName) -> bool:
	return (
		_active_derived_operation != null
		and _active_derived_operation.is_pending()
		and _active_derived_operation.request_cancel(reason)
	)


## 返回路径无关、payload 无关的复合终态证据。
func make_terminal_evidence() -> Dictionary:
	if not is_completed():
		return {}
	var caller_result: GFStorageAsyncCallerResult = (
		_main_operation.get_caller_result()
		if _main_operation != null
		else null
	)
	var physical_result: GFStorageAsyncResult = (
		_main_operation.get_result() if _main_operation != null else null
	)
	var delete_result: GFStorageDeleteResult = (
		physical_result.get_delete_result()
		if physical_result != null
		else null
	)
	var first_derived: ChunkProfileCleanupResult = (
		_derived_results.front() if not _derived_results.is_empty() else null
	)
	var derived_result_dicts: Array[Dictionary] = []
	for result: ChunkProfileCleanupResult in _derived_results:
		derived_result_dicts.append(result.to_dict())
	var failure_phase: StringName = &"none"
	if _main_error != OK:
		failure_phase = PHASE_MAIN_DELETE
	elif _derived_error != OK:
		failure_phase = PHASE_DERIVED_CLEANUP
	var derived_status: StringName = &"cleaned"
	if _main_error != OK:
		derived_status = &"not_started"
	elif _derived_setup_failed:
		derived_status = &"setup_failed"
	elif _derived_error != OK:
		derived_status = &"partial_failure"
	return {
		&"ok": _final_error == OK,
		&"cleanup_kind": _cleanup_kind,
		&"phase": _phase,
		&"failure_phase": failure_phase,
		&"status": _get_terminal_status(),
		&"error_code": int(_final_error),
		&"main_error_code": int(_main_error),
		&"derived_error_code": int(_derived_error),
		&"derived_total_count": _derived_total_count,
		&"derived_completed_count": _derived_completed_count,
		&"derived_failed_count": _derived_failed_count,
		&"derived_status": derived_status,
		&"derived_first_status": (
			first_derived.get_status() if first_derived != null else &""
		),
		&"derived_first_error_code": (
			int(first_derived.get_error_code()) if first_derived != null else OK
		),
		&"derived_first_delete_failure_kind": (
			int(first_derived.get_first_delete_failure_kind())
			if first_derived != null
			else int(GFStorageDeleteResult.FailureKind.NONE)
		),
		&"busy_retry_count": _busy_retry_count,
		&"derived_results": derived_result_dicts,
		&"caller_outcome_unknown": _caller_outcome_unknown,
		&"main_caller_completed": caller_result != null,
		&"main_caller_status": (
			int(caller_result.get_status()) if caller_result != null else -1
		),
		&"main_caller_end_kind": (
			int(caller_result.get_end_kind()) if caller_result != null else -1
		),
		&"main_caller_reason": (
			caller_result.get_reason() if caller_result != null else &""
		),
		&"main_caller_error_code": (
			int(caller_result.get_error_code()) if caller_result != null else -1
		),
		&"main_physical_settled": physical_result != null,
		&"main_physical_settlement_kind": (
			int(physical_result.get_settlement_kind())
			if physical_result != null
			else -1
		),
		&"main_physical_cancelled": (
			physical_result.is_cancelled() if physical_result != null else false
		),
		&"main_physical_error_code": (
			int(physical_result.get_error_code())
			if physical_result != null
			else -1
		),
		&"main_delete_failure_kind": (
			int(delete_result.get_failure_kind())
			if delete_result != null
			else int(GFStorageDeleteResult.FailureKind.NONE)
		),
	}


# --- 私有/辅助方法 ---

func _get_terminal_status() -> StringName:
	if _final_error == OK:
		return &"cleaned"
	if _derived_setup_failed:
		return &"derived_setup_failed"
	return &"main_failed" if _main_error != OK else &"derived_partial"
