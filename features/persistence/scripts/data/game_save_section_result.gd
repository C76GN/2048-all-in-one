## GameSaveSectionResult: section 持久化事务的不可变类型化终态。
##
## 结果保留 GF 保存和补偿 operation 的完整证据，使 UI 不必从 Error 或文本
## 猜测候选数据是否已持久化、已回滚或仍处于 outcome_unknown。
class_name GameSaveSectionResult
extends RefCounted


# --- 常量 ---

const STATUS_PERSISTED: StringName = &"persisted"
const STATUS_INVALID_REQUEST: StringName = &"invalid_request"
const STATUS_BUSY: StringName = &"busy"
const STATUS_APPLY_FAILED: StringName = &"apply_failed"
const STATUS_SAVE_FAILED_ROLLED_BACK: StringName = &"save_failed_rolled_back"
const STATUS_ROLLBACK_FAILED: StringName = &"rollback_failed"
const STATUS_COMPENSATION_FAILED: StringName = &"compensation_failed"
const STATUS_OUTCOME_UNKNOWN: StringName = &"outcome_unknown"
const STATUS_ROLLBACK_OUTCOME_UNKNOWN: StringName = &"rollback_outcome_unknown"
const STATUS_DISPOSED: StringName = &"disposed"

const _VALID_STATUSES: Array[StringName] = [
	STATUS_PERSISTED,
	STATUS_INVALID_REQUEST,
	STATUS_BUSY,
	STATUS_APPLY_FAILED,
	STATUS_SAVE_FAILED_ROLLED_BACK,
	STATUS_ROLLBACK_FAILED,
	STATUS_COMPENSATION_FAILED,
	STATUS_OUTCOME_UNKNOWN,
	STATUS_ROLLBACK_OUTCOME_UNKNOWN,
	STATUS_DISPOSED,
]


# --- 私有变量 ---

var _transaction_id: int = 0
var _profile_id: StringName = &""
var _section_ids: PackedStringArray = PackedStringArray()
var _status: StringName = STATUS_INVALID_REQUEST
var _error_code: Error = ERR_INVALID_PARAMETER
var _candidate_applied: bool = false
var _memory_rolled_back: bool = false
var _save_result: GFSaveProfileResult = null
var _compensation_result: GFSaveProfileResult = null


# --- 公共方法 ---

## 返回事务是否已确认持久化。
func is_successful() -> bool:
	return _status == STATUS_PERSISTED and _error_code == OK


## 返回项目内单调递增的事务标识。
func get_transaction_id() -> int:
	return _transaction_id


## 返回事务开始时冻结的 GF Profile 标识。
func get_profile_id() -> StringName:
	return _profile_id


## 返回按字典序冻结的 section 标识副本。
func get_section_ids() -> PackedStringArray:
	return _section_ids.duplicate()


## 返回稳定业务终态。
func get_status() -> StringName:
	return _status


## 返回与业务终态对应的 Godot Error。
func get_error_code() -> Error:
	return _error_code


## 返回候选 section 是否曾应用到权威内存状态。
func was_candidate_applied() -> bool:
	return _candidate_applied


## 返回候选 section 是否已在内存中恢复为事务前快照。
func was_memory_rolled_back() -> bool:
	return _memory_rolled_back


## 返回是否必须等待 GF detached 写入收敛后才能继续修改 Profile。
func requires_reconciliation() -> bool:
	return _status in [
		STATUS_OUTCOME_UNKNOWN,
		STATUS_ROLLBACK_OUTCOME_UNKNOWN,
		STATUS_ROLLBACK_FAILED,
	]


## 返回原始 GF 保存终态副本。
func get_save_result() -> GFSaveProfileResult:
	return _save_result.duplicate_result() if _save_result != null else null


## 返回回滚补偿 GF 保存终态副本。
func get_compensation_result() -> GFSaveProfileResult:
	return (
		_compensation_result.duplicate_result()
		if _compensation_result != null
		else null
	)


## 返回可用于诊断和测试的隔离字典。
func to_dict() -> Dictionary:
	return {
		&"transaction_id": _transaction_id,
		&"profile_id": String(_profile_id),
		&"section_ids": _section_ids.duplicate(),
		&"status": String(_status),
		&"error_code": int(_error_code),
		&"candidate_applied": _candidate_applied,
		&"memory_rolled_back": _memory_rolled_back,
		&"save_result": _save_result.to_dict() if _save_result != null else {},
		&"compensation_result": (
			_compensation_result.to_dict()
			if _compensation_result != null
			else {}
		),
	}


## 返回完全隔离的不可变结果副本。
func duplicate_result() -> GameSaveSectionResult:
	var result: GameSaveSectionResult = GameSaveSectionResult.new()
	var _configured: bool = result.configure_for_utility(
		_transaction_id,
		_profile_id,
		_section_ids,
		_status,
		_error_code,
		_candidate_applied,
		_memory_rolled_back,
		_save_result,
		_compensation_result
	)
	return result


# --- 公共方法（GameSaveGraphUtility 协议） ---

## 由 GameSaveGraphUtility 初始化不可变终态。
##
## @param transaction_id: 与一次性操作句柄一致的事务标识。
## @param profile_id: 事务开始时冻结的 GF Profile 标识。
## @param section_ids: 与一次性操作句柄一致的 section 标识。
## @param status: 稳定业务终态。
## @param error_code: 与终态对应的 Godot Error。
## @param candidate_applied: 候选数据是否曾进入权威内存状态。
## @param memory_rolled_back: 内存是否已恢复到事务前快照。
## @param save_result: 原始 GF 保存终态。
## @param compensation_result: 回滚后的 GF 补偿保存终态。
func configure_for_utility(
	transaction_id: int,
	profile_id: StringName,
	section_ids: PackedStringArray,
	status: StringName,
	error_code: Error,
	candidate_applied: bool,
	memory_rolled_back: bool,
	save_result: GFSaveProfileResult = null,
	compensation_result: GFSaveProfileResult = null
) -> bool:
	if (
		_transaction_id > 0
		or transaction_id <= 0
		or section_ids.is_empty()
		or status not in _VALID_STATUSES
	):
		return false
	_transaction_id = transaction_id
	_profile_id = profile_id
	_section_ids = section_ids.duplicate()
	_section_ids.sort()
	_status = status
	_error_code = error_code
	_candidate_applied = candidate_applied
	_memory_rolled_back = memory_rolled_back
	_save_result = save_result.duplicate_result() if save_result != null else null
	_compensation_result = (
		compensation_result.duplicate_result()
		if compensation_result != null
		else null
	)
	return true
