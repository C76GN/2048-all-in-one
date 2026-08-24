## 持有一次 inactive-bank staging 的取消请求与唯一 typed 终态。
class_name ChunkStageOperation
extends RefCounted


# --- 信号 ---

## 操作进入唯一终态时发出。
signal completed(result: ChunkStageResult)

## 首次接受取消请求时发出。
signal cancellation_requested(reason: StringName)


# --- 常量 ---

## 尚未向 executor 提交 GF 操作。
const PHASE_PENDING: StringName = &"pending"

## 正在依次保存 inactive-bank chunk Profiles。
const PHASE_WRITING_CHUNKS: StringName = &"writing_chunks"

## 已进入唯一终态。
const PHASE_COMPLETED: StringName = &"completed"


# --- 私有变量 ---

var _phase: StringName = PHASE_PENDING
var _cancel_requested: bool = false
var _cancel_reason: StringName = &""
var _result: ChunkStageResult = null


# --- 公共方法 ---

## 查询操作是否仍在等待终态。
func is_pending() -> bool:
	return _result == null


## 查询操作是否已经完成。
func is_completed() -> bool:
	return _result != null


## 获取当前阶段。
func get_phase() -> StringName:
	return _phase


## 请求取消 staging。
##
## 已接纳的 GF Profile 操作不会被伪取消；Module 会等待它结算后终结。
## @param reason: 首次取消原因。
## @return 首次接受取消请求时返回 true。
func request_cancel(reason: StringName = &"caller_cancelled") -> bool:
	if _result != null or _cancel_requested:
		return false
	_cancel_requested = true
	_cancel_reason = reason if reason != &"" else &"caller_cancelled"
	cancellation_requested.emit(_cancel_reason)
	return true


## 查询是否已经接受取消请求。
func is_cancel_requested() -> bool:
	return _cancel_requested


## 获取首次取消原因。
func get_cancel_reason() -> StringName:
	return _cancel_reason


## 获取隔离终态；等待中返回 null。
func get_result() -> ChunkStageResult:
	return _result.duplicate_result() if _result != null else null


## 由 persistence Module 推进当前阶段。
##
## @param phase: PHASE_PENDING 或 PHASE_WRITING_CHUNKS。
## @return 合法且仍 pending 时返回 true。
func set_phase_for_persistence(phase: StringName) -> bool:
	if (
		_result != null
		or phase not in [PHASE_PENDING, PHASE_WRITING_CHUNKS]
	):
		return false
	_phase = phase
	return true


## 由 persistence Module 写入唯一终态并发出信号。
##
## @param result: typed staging 终态。
## @return 首次完成时返回 true。
func complete_for_persistence(result: ChunkStageResult) -> bool:
	if _result != null or result == null:
		return false
	_result = result.duplicate_result()
	_phase = PHASE_COMPLETED
	completed.emit(_result.duplicate_result())
	return true
