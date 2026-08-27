## GameSaveSectionSettlementResult: section operation 的权威、不可变消费终态。
##
## 它把即时 GameSaveSectionResult 与迟到 reconciliation evidence 投影为同一
## typed Interface；调用方无需理解 evidence Dictionary 或重算错误码。
class_name GameSaveSectionSettlementResult
extends RefCounted


const STATUS_CANCELLED: StringName = &"cancelled"
const STATUS_UNAVAILABLE: StringName = &"unavailable"


# --- 私有变量 ---

var _transaction_id: int = 0
var _status: StringName = STATUS_UNAVAILABLE
var _candidate_persisted: bool = false
var _memory_rolled_back: bool = false
var _error_code: Error = FAILED


# --- 工厂方法 ---

## 把即时 Section operation 终态投影为业务可消费的不可变结果。
## @param result: SaveGraph 返回的即时类型化终态；null 会失败关闭。
## @return: 与输入 transaction/status 对应的不可变 settlement。
static func from_section_result(
	result: GameSaveSectionResult
) -> GameSaveSectionSettlementResult:
	if result == null:
		return failed(ERR_UNCONFIGURED)
	return _create(
		result.get_transaction_id(),
		result.get_status(),
		result.is_successful(),
		result.was_memory_rolled_back(),
		OK if result.is_successful() else result.get_error_code()
	)


## 把匹配 transaction 的迟到对账证据投影为不可变终态。
## @param evidence: SaveGraph 发布的只读 reconciliation evidence。
## @param transaction_id: 调用方冻结并等待的 transaction ID。
## @param fallback_status: evidence 未提供 status 时使用的初始终态。
## @param fallback_error: 候选未持久化时保留的初始错误码。
## @return: 匹配且未取消时返回 settlement，否则返回 null。
static func from_reconciliation_evidence(
	evidence: Dictionary,
	transaction_id: int,
	fallback_status: StringName,
	fallback_error: Error
) -> GameSaveSectionSettlementResult:
	if (
		transaction_id <= 0
		or GFVariantData.get_option_int(
			evidence,
			&"transaction_id",
			0
		) != transaction_id
		or GFVariantData.get_option_bool(evidence, &"cancelled", false)
	):
		return null
	var candidate_persisted: bool = GFVariantData.get_option_bool(
		evidence,
		&"candidate_persisted",
		false
	)
	var status: StringName = GFVariantData.get_option_string_name(
		evidence,
		&"status",
		fallback_status
	)
	return _create(
		transaction_id,
		status,
		candidate_persisted,
		GFVariantData.get_option_bool(
			evidence,
			&"memory_rolled_back",
			false
		),
		OK if candidate_persisted else fallback_error
	)


## 创建一个指定 transaction 的取消终态。
## @param transaction_id: 被取消等待的 transaction ID。
## @return: 不可变取消结果。
static func cancelled(
	transaction_id: int
) -> GameSaveSectionSettlementResult:
	return _create(
		transaction_id,
		STATUS_CANCELLED,
		false,
		false,
		ERR_UNAVAILABLE
	)


## 创建未绑定 transaction 的失败关闭终态。
## @param error_code: 失败原因。
## @return: 不可变失败结果。
static func failed(error_code: Error) -> GameSaveSectionSettlementResult:
	return _create(0, STATUS_UNAVAILABLE, false, false, error_code)


# --- 查询方法 ---

func get_transaction_id() -> int:
	return _transaction_id


func get_status() -> StringName:
	return _status


func is_candidate_persisted() -> bool:
	return _candidate_persisted


func was_memory_rolled_back() -> bool:
	return _memory_rolled_back


func get_error_code() -> Error:
	return _error_code


func is_cancelled() -> bool:
	return _status == STATUS_CANCELLED


func duplicate_result() -> GameSaveSectionSettlementResult:
	return _create(
		_transaction_id,
		_status,
		_candidate_persisted,
		_memory_rolled_back,
		_error_code
	)


# --- 私有/辅助方法 ---

static func _create(
	transaction_id: int,
	status: StringName,
	candidate_persisted: bool,
	memory_rolled_back: bool,
	error_code: Error
) -> GameSaveSectionSettlementResult:
	var result: GameSaveSectionSettlementResult = (
		GameSaveSectionSettlementResult.new()
	)
	result._transaction_id = max(transaction_id, 0)
	result._status = status if not status.is_empty() else STATUS_UNAVAILABLE
	result._candidate_persisted = candidate_persisted
	result._memory_rolled_back = memory_rolled_back
	result._error_code = error_code
	return result
