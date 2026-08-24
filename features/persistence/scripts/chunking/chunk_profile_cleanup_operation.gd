## 持有一次 chunk family 回收的取消意图、进度诊断与唯一物理终态。
##
## `completed` 只表示所有已接纳 GF delete 都获得物理终态；底层 caller 的
## outcome-unknown 不会让本 Operation 提前完成，也不会释放 scope 复用权。
class_name ChunkProfileCleanupOperation
extends RefCounted


# --- 信号 ---

signal completed(result: ChunkProfileCleanupResult)
signal cancellation_requested(reason: StringName)


# --- 常量 ---

const PHASE_PENDING: StringName = &"pending"
const PHASE_DELETING: StringName = &"deleting"
const PHASE_WAITING_FOR_PHYSICAL: StringName = &"waiting_for_physical"
const PHASE_COMPLETED: StringName = &"completed"


# --- 私有变量 ---

var _operation_id: StringName = &""
var _phase: StringName = PHASE_PENDING
var _cancel_requested: bool = false
var _cancel_reason: StringName = &""
var _result: ChunkProfileCleanupResult = null
var _runner: ChunkProfileCleanupRunner = null
var _progress: Dictionary = {}


# --- 公共方法 ---

func get_operation_id() -> StringName:
	return _operation_id


func is_pending() -> bool:
	return _result == null


func is_completed() -> bool:
	return _result != null


func get_phase() -> StringName:
	return _phase


## @param reason: 首次取消请求使用的稳定原因码。
func request_cancel(reason: StringName = &"caller_cancelled") -> bool:
	if _result != null or _cancel_requested:
		return false
	_cancel_requested = true
	_cancel_reason = reason if reason != &"" else &"caller_cancelled"
	cancellation_requested.emit(_cancel_reason)
	return true


func is_cancel_requested() -> bool:
	return _cancel_requested


func get_cancel_reason() -> StringName:
	return _cancel_reason


func get_result() -> ChunkProfileCleanupResult:
	return _result.duplicate_result() if _result != null else null


## 获取路径无关、payload 无关的实时诊断快照。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = _progress.duplicate(true)
	snapshot[&"operation_id"] = _operation_id
	snapshot[&"phase"] = _phase
	snapshot[&"cancel_requested"] = _cancel_requested
	snapshot[&"completed"] = _result != null
	return snapshot


# --- persistence Module 方法 ---

## @param operation_id: Utility 为本次回收分配的稳定操作 ID。
func configure_for_persistence(operation_id: StringName) -> bool:
	if not _operation_id.is_empty() or operation_id.is_empty():
		return false
	_operation_id = operation_id
	return true


## @param runner: 在物理终态前持有回收流程的 Runner。
func attach_runner_for_persistence(runner: ChunkProfileCleanupRunner) -> bool:
	if _result != null or _runner != null or runner == null:
		return false
	_runner = runner
	return true


## @param phase: PHASE_PENDING、PHASE_DELETING 或 PHASE_WAITING_FOR_PHYSICAL。
func set_phase_for_persistence(phase: StringName) -> bool:
	if _result != null or phase not in [
		PHASE_PENDING,
		PHASE_DELETING,
		PHASE_WAITING_FOR_PHYSICAL,
	]:
		return false
	_phase = phase
	return true


## @param progress: 不含路径或 payload 的实时诊断字段。
func update_progress_for_persistence(progress: Dictionary) -> bool:
	if _result != null:
		return false
	_progress = progress.duplicate(true)
	return true


## @param result: 所有已接纳 delete 收敛后的 typed 物理终态。
func complete_for_persistence(result: ChunkProfileCleanupResult) -> bool:
	if _result != null or result == null:
		return false
	_result = result.duplicate_result()
	_phase = PHASE_COMPLETED
	_runner = null
	completed.emit(_result.duplicate_result())
	return true
