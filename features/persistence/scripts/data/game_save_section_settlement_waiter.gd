## GameSaveSectionSettlementWaiter: 单个 section transaction 的权威终态等待者。
##
## 本 Module 独占 operation completion、latest evidence 快路径、signal race 重检、
## transaction matching 与取消；消费者只接收 typed settlement result。
class_name GameSaveSectionSettlementWaiter
extends RefCounted


signal settled(result: GameSaveSectionSettlementResult)


# --- 私有变量 ---

var _operation: GameSaveSectionOperation = null
var _save_graph: GameSaveGraphUtility = null
var _signal_utility: GFSignalUtility = null
var _owner: Object = null
var _connection: GFSignalConnection = null
var _result: GameSaveSectionSettlementResult = null
var _running: bool = false
var _transaction_id: int = 0


# --- 公共方法 ---

## 配置一个由 operation 句柄驱动的唯一结算等待。
## @param operation: 待消费的一次性 Section operation。
## @param save_graph: 提供 latest evidence 与迟到对账信号的权威 Utility。
## @param signal_utility: 持有安全信号连接的 GF Utility。
## @param owner: 等待生命周期 owner。
## @return: 配置仅成功一次且全部依赖有效时返回 true。
func configure(
	operation: GameSaveSectionOperation,
	save_graph: GameSaveGraphUtility,
	signal_utility: GFSignalUtility,
	owner: Object
) -> bool:
	if (
		_operation != null
		or operation == null
		or save_graph == null
		or signal_utility == null
		or owner == null
	):
		return false
	_operation = operation
	_transaction_id = operation.get_transaction_id()
	_save_graph = save_graph
	_signal_utility = signal_utility
	_owner = owner
	return true


## 只等待 SaveGraph 已持有、但调用方不再持有 operation 句柄的 reconciliation。
## @param transaction_id: SaveGraph 当前持有的 transaction ID。
## @param save_graph: 提供 latest evidence 与迟到对账信号的权威 Utility。
## @param signal_utility: 持有安全信号连接的 GF Utility。
## @param owner: 等待生命周期 owner。
## @return: 配置仅成功一次且全部依赖有效时返回 true。
func configure_reconciliation(
	transaction_id: int,
	save_graph: GameSaveGraphUtility,
	signal_utility: GFSignalUtility,
	owner: Object
) -> bool:
	if (
		_operation != null
		or _transaction_id > 0
		or transaction_id <= 0
		or save_graph == null
		or signal_utility == null
		or owner == null
	):
		return false
	_transaction_id = transaction_id
	_save_graph = save_graph
	_signal_utility = signal_utility
	_owner = owner
	return true


## 等待即时或迟到的唯一业务结算终态。
## @param observed_result: 调用方已经消费的初始结果，避免重复 await operation。
## @return: 不可变 settlement；依赖无效时失败关闭。
func await_settlement(
	observed_result: GameSaveSectionResult = null
) -> GameSaveSectionSettlementResult:
	if _result != null:
		return _result.duplicate_result()
	if _operation == null and _transaction_id <= 0:
		return GameSaveSectionSettlementResult.failed(ERR_UNCONFIGURED)
	if _running:
		var shared_result: GameSaveSectionSettlementResult = await settled
		return shared_result.duplicate_result()
	_running = true
	var initial_result: GameSaveSectionResult = observed_result
	if initial_result == null and _operation != null:
		initial_result = await _operation.await_result()
	if _result != null:
		return _result.duplicate_result()
	if initial_result != null and not initial_result.requires_reconciliation():
		_complete(GameSaveSectionSettlementResult.from_section_result(initial_result))
		return _result.duplicate_result()
	var transaction_id: int = (
		initial_result.get_transaction_id()
		if initial_result != null
		else _transaction_id
	)
	var fallback_status: StringName = (
		initial_result.get_status()
		if initial_result != null
		else GameSaveSectionSettlementResult.STATUS_UNAVAILABLE
	)
	var fallback_error: Error = (
		initial_result.get_error_code() if initial_result != null else ERR_BUSY
	)
	var latest_result: GameSaveSectionSettlementResult = (
		_try_make_reconciliation_result(
			transaction_id,
			fallback_status,
			fallback_error
		)
	)
	if latest_result != null:
		_complete(latest_result)
		return _result.duplicate_result()
	_connection = _signal_utility.connect_signal(
		_save_graph.section_reconciliation_settled,
		_on_reconciliation_settled.bind(
			transaction_id,
			fallback_status,
			fallback_error
		),
		_owner
	)
	if _connection == null or not _connection.is_active():
		_complete(
			GameSaveSectionSettlementResult.from_section_result(initial_result)
			if initial_result != null
			else GameSaveSectionSettlementResult.failed(ERR_UNCONFIGURED)
		)
		return _result.duplicate_result()
	# 连接后重检，闭合 latest-evidence 与 signal 订阅之间的竞态窗口。
	latest_result = _try_make_reconciliation_result(
		transaction_id,
		fallback_status,
		fallback_error
	)
	if latest_result != null:
		_complete(latest_result)
		return _result.duplicate_result()
	var terminal_result: GameSaveSectionSettlementResult = await settled
	return terminal_result.duplicate_result()


func cancel() -> void:
	if _result != null:
		return
	_complete(GameSaveSectionSettlementResult.cancelled(_transaction_id))


# --- 私有/辅助方法 ---

func _try_make_reconciliation_result(
	transaction_id: int,
	fallback_status: StringName,
	fallback_error: Error
) -> GameSaveSectionSettlementResult:
	if _save_graph == null:
		return null
	return GameSaveSectionSettlementResult.from_reconciliation_evidence(
		_save_graph.get_last_section_reconciliation_evidence(),
		transaction_id,
		fallback_status,
		fallback_error
	)


func _on_reconciliation_settled(
	evidence: Dictionary,
	transaction_id: int,
	fallback_status: StringName,
	fallback_error: Error
) -> void:
	if _result != null:
		return
	var terminal_result: GameSaveSectionSettlementResult = (
		GameSaveSectionSettlementResult.from_reconciliation_evidence(
			evidence,
			transaction_id,
			fallback_status,
			fallback_error
		)
	)
	if terminal_result != null:
		_complete(terminal_result)


func _complete(result: GameSaveSectionSettlementResult) -> void:
	if _result != null or result == null:
		return
	_result = result.duplicate_result()
	_running = false
	_disconnect()
	settled.emit(_result.duplicate_result())


func _disconnect() -> void:
	if _connection != null:
		_connection.disconnect_signal()
	_connection = null
	_save_graph = null
	_signal_utility = null
	_owner = null
