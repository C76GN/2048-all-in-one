## LocalAccountReconciliationSaga: 账号目录补偿与 Profile 对齐的唯一类型化状态所有者。
##
## LocalAccountSystem 继续拥有 GF IO、signal lifecycle 与业务事件发布；本 Saga
## 只冻结一次账号事务的协调身份，维护互斥 phase，并把目录 cleanup 作为目录
## 补偿的内部子阶段。任一时刻只允许 CatalogCompensationState 或
## ProfileAlignmentState 之一存在。
class_name LocalAccountReconciliationSaga
extends RefCounted


# --- 常量 ---

const KIND_CATALOG_COMPENSATION: StringName = &"catalog_compensation"
const KIND_PROFILE_ALIGNMENT: StringName = &"profile_alignment"

const PHASE_WAITING: StringName = &"waiting"
const PHASE_READY: StringName = &"ready"
const PHASE_RUNNING: StringName = &"running"
const PHASE_RETRY_REQUIRED: StringName = &"retry_required"
const PHASE_COMPLETED: StringName = &"completed"

const CONDITION_NONE: StringName = &"none"
const CONDITION_WAIT_CATALOG_SETTLEMENT: StringName = (
	&"wait_catalog_settlement"
)
const CONDITION_WAIT_PROFILE_SETTLEMENT: StringName = (
	&"wait_profile_settlement"
)
const CONDITION_WAIT_CLEANUP_TERMINAL: StringName = (
	&"wait_cleanup_terminal"
)
const CONDITION_BLOCKED_CATALOG_APPLY: StringName = (
	&"blocked_catalog_apply"
)
const CONDITION_BLOCKED_KNOWN_FAILURE: StringName = (
	&"blocked_known_failure"
)
const CONDITION_CLEANUP_RETRY_REQUIRED: StringName = (
	&"cleanup_retry_required"
)


# --- 私有变量 ---

var _kind: StringName = &""
var _phase: StringName = PHASE_WAITING
var _condition: StringName = CONDITION_NONE
var _catalog_state: CatalogCompensationState = null
var _profile_state: ProfileAlignmentState = null


# --- 工厂方法 ---

## 冻结一次等待目录物理终态的补偿身份。
## @param operation: 尚未发布调用方终态的账号操作。
## @param account: 操作返回的账号快照；没有账号时可为空。
## @param previous_account_id: 操作前的活动账号身份。
## @param cleanup_profile_file: 可选的补偿清理 Profile 规范路径。
## @param cleanup_account_id: 与清理路径严格对应的账号身份。
static func create_catalog_compensation(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String,
	cleanup_profile_file: String = "",
	cleanup_account_id: String = ""
) -> LocalAccountReconciliationSaga:
	if operation == null or not operation.is_pending():
		return null
	if not _is_valid_optional_cleanup_target(
		cleanup_profile_file,
		cleanup_account_id
	):
		return null
	var state: CatalogCompensationState = CatalogCompensationState.new()
	state.operation = operation.get_operation()
	state.target_account_id = operation.get_target_account_id()
	state.result_account_id = account.account_id if account != null else ""
	state.previous_account_id = previous_account_id
	state.cleanup_required = not cleanup_profile_file.is_empty()
	state.cleanup_profile_file = cleanup_profile_file
	state.cleanup_account_id = cleanup_account_id
	state.publish_events = not (
		state.operation == LocalAccountOperation.OPERATION_CREATE
		and state.cleanup_required
	)
	return _from_catalog_state(
		state,
		PHASE_WAITING,
		CONDITION_WAIT_CATALOG_SETTLEMENT
	)


## 冻结一次等待 GF Profile 精确 settled-idle 证据的对齐身份。
## @param operation: 尚未发布调用方终态的账号操作。
## @param account: 操作返回的账号快照；没有账号时可为空。
## @param previous_account_id: 操作前的活动账号身份。
## @param profile_id: 当前 outcome-unknown GF Profile 身份；证据损坏时可为空并保持锁定。
static func create_profile_alignment(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String,
	profile_id: StringName
) -> LocalAccountReconciliationSaga:
	if operation == null or not operation.is_pending():
		return null
	var state: ProfileAlignmentState = ProfileAlignmentState.new()
	state.operation = operation.get_operation()
	state.target_account_id = operation.get_target_account_id()
	state.result_account_id = account.account_id if account != null else ""
	state.previous_account_id = previous_account_id
	state.profile_id = profile_id
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.new()
	)
	saga._kind = KIND_PROFILE_ALIGNMENT
	saga._condition = CONDITION_WAIT_PROFILE_SETTLEMENT
	saga._profile_state = state
	return saga


## 冻结一次目录补偿内部的 Profile cleanup 子阶段。
## @param operation: 尚未发布调用方终态的账号操作。
## @param account: 操作返回的账号快照；没有账号时可为空。
## @param previous_account_id: 操作前的活动账号身份。
## @param cleanup_profile_file: 必须清理的规范 Profile 路径。
## @param cleanup_account_id: 与清理路径严格对应的账号身份。
## @param initial_cleanup_error: 触发补偿的非成功错误码。
static func create_cleanup_compensation(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String,
	cleanup_profile_file: String,
	cleanup_account_id: String,
	initial_cleanup_error: Error
) -> LocalAccountReconciliationSaga:
	if (
		operation == null
		or not operation.is_pending()
		or initial_cleanup_error == OK
		or not _is_valid_optional_cleanup_target(
			cleanup_profile_file,
			cleanup_account_id
		)
		or cleanup_profile_file.is_empty()
	):
		return null
	var waits_for_terminal: bool = initial_cleanup_error in [
		ERR_TIMEOUT,
		ERR_BUSY,
	]
	var state: CatalogCompensationState = CatalogCompensationState.new()
	state.operation = operation.get_operation()
	state.target_account_id = operation.get_target_account_id()
	state.result_account_id = account.account_id if account != null else ""
	state.previous_account_id = previous_account_id
	state.settlement_received = true
	state.publish_success = true
	state.publish_events = false
	state.success_events_published = true
	state.cleanup_required = true
	state.cleanup_profile_file = cleanup_profile_file
	state.cleanup_account_id = cleanup_account_id
	state.cleanup_only = true
	return _from_catalog_state(
		state,
		PHASE_WAITING if waits_for_terminal else PHASE_RETRY_REQUIRED,
		(
			CONDITION_WAIT_CLEANUP_TERMINAL
			if waits_for_terminal
			else CONDITION_CLEANUP_RETRY_REQUIRED
		)
	)


# --- 查询方法 ---

func get_kind() -> StringName:
	return _kind


func get_phase() -> StringName:
	return _phase


func get_condition() -> StringName:
	return _condition


func is_pending() -> bool:
	return _kind != &"" and _phase != PHASE_COMPLETED


func is_catalog_compensation() -> bool:
	return _kind == KIND_CATALOG_COMPENSATION and _catalog_state != null


func is_profile_alignment() -> bool:
	return _kind == KIND_PROFILE_ALIGNMENT and _profile_state != null


func is_ready() -> bool:
	return _phase == PHASE_READY


func is_running() -> bool:
	return _phase == PHASE_RUNNING


func is_cleanup_pending() -> bool:
	return (
		is_catalog_compensation()
		and _condition == CONDITION_WAIT_CLEANUP_TERMINAL
	)


func is_cleanup_retry_explicit_required() -> bool:
	return (
		is_catalog_compensation()
		and _phase == PHASE_RETRY_REQUIRED
		and _condition == CONDITION_CLEANUP_RETRY_REQUIRED
	)


func is_waiting_for_catalog_settlement() -> bool:
	return (
		is_catalog_compensation()
		and _phase == PHASE_WAITING
		and _condition == CONDITION_WAIT_CATALOG_SETTLEMENT
	)


func is_waiting_for_profile_settlement() -> bool:
	return (
		is_pending()
		and _phase == PHASE_WAITING
		and _condition == CONDITION_WAIT_PROFILE_SETTLEMENT
	)


func is_waiting_for_cleanup_terminal() -> bool:
	return is_cleanup_pending()


func is_blocked_by_catalog_apply_failure() -> bool:
	return (
		is_catalog_compensation()
		and _phase == PHASE_WAITING
		and _condition == CONDITION_BLOCKED_CATALOG_APPLY
	)


func is_blocked_by_known_failure() -> bool:
	return (
		is_pending()
		and _phase == PHASE_WAITING
		and _condition == CONDITION_BLOCKED_KNOWN_FAILURE
	)


func has_catalog_settlement() -> bool:
	return (
		is_catalog_compensation()
		and _catalog_state.settlement_received
	)


func get_operation() -> StringName:
	if is_catalog_compensation():
		return _catalog_state.operation
	return _profile_state.operation if is_profile_alignment() else &""


func get_target_account_id() -> String:
	if is_catalog_compensation():
		return _catalog_state.target_account_id
	return (
		_profile_state.target_account_id if is_profile_alignment() else ""
	)


func get_result_account_id() -> String:
	if is_catalog_compensation():
		return _catalog_state.result_account_id
	return (
		_profile_state.result_account_id if is_profile_alignment() else ""
	)


func get_previous_account_id() -> String:
	if is_catalog_compensation():
		return _catalog_state.previous_account_id
	return (
		_profile_state.previous_account_id if is_profile_alignment() else ""
	)


func get_profile_id() -> StringName:
	if is_catalog_compensation():
		return _catalog_state.profile_id
	return _profile_state.profile_id if is_profile_alignment() else &""


func get_cleanup_profile_file() -> String:
	return (
		_catalog_state.cleanup_profile_file
		if is_catalog_compensation()
		else ""
	)


func get_cleanup_account_id() -> String:
	return (
		_catalog_state.cleanup_account_id
		if is_catalog_compensation()
		else ""
	)


func is_cleanup_required() -> bool:
	return (
		is_catalog_compensation()
		and _catalog_state.cleanup_required
	)


func is_cleanup_only() -> bool:
	return (
		is_catalog_compensation()
		and _catalog_state.cleanup_only
	)


func should_publish_success() -> bool:
	return (
		is_catalog_compensation()
		and _catalog_state.publish_success
	)


func get_storage_result() -> Dictionary:
	return (
		_catalog_state.storage_result.duplicate(true)
		if is_catalog_compensation()
		else {}
	)


## 返回复制隔离的状态证据；调用方不得据此推进 Saga。
func make_state_snapshot() -> Dictionary:
	if is_profile_alignment():
		return {
			&"kind": _kind,
			&"phase": _phase,
			&"condition": _condition,
			&"operation": _profile_state.operation,
			&"target_account_id": _profile_state.target_account_id,
			&"result_account_id": _profile_state.result_account_id,
			&"previous_account_id": _profile_state.previous_account_id,
			&"profile_id": _profile_state.profile_id,
		}
	if not is_catalog_compensation():
		return {}
	return {
		&"kind": _kind,
		&"phase": _phase,
		&"condition": _condition,
		&"operation": _catalog_state.operation,
		&"target_account_id": _catalog_state.target_account_id,
		&"result_account_id": _catalog_state.result_account_id,
		&"previous_account_id": _catalog_state.previous_account_id,
		&"profile_id": _catalog_state.profile_id,
		&"settlement_received": _catalog_state.settlement_received,
		&"publish_success": _catalog_state.publish_success,
		&"publish_events": _catalog_state.publish_events,
		&"success_events_published": (
			_catalog_state.success_events_published
		),
		&"failure_catalog_event_published": (
			_catalog_state.failure_catalog_event_published
		),
		&"cleanup_required": _catalog_state.cleanup_required,
		&"cleanup_profile_file": _catalog_state.cleanup_profile_file,
		&"cleanup_account_id": _catalog_state.cleanup_account_id,
		&"cleanup_only": _catalog_state.cleanup_only,
		&"cleanup_pending": is_cleanup_pending(),
		&"cleanup_retry_explicit_required": (
			is_cleanup_retry_explicit_required()
		),
		&"storage_succeeded": _catalog_state.storage_succeeded,
		&"candidate_apply_error": int(
			_catalog_state.candidate_apply_error
		),
		&"storage_result": _catalog_state.storage_result.duplicate(true),
		&"catalog_previous_active_account_id": (
			_catalog_state.catalog_previous_active_account_id
		),
		&"catalog_active_account_id": (
			_catalog_state.catalog_active_account_id
		),
	}


## 投影 cleanup 等待物理终态时的兼容诊断状态；不得用于推进 Saga。
## @param cleanup_error: 本次 cleanup caller 观察到的错误码。
func make_cleanup_pending_evidence_status(cleanup_error: Error) -> StringName:
	if not is_catalog_compensation() or not _catalog_state.cleanup_required:
		return &""
	if _catalog_state.operation == LocalAccountOperation.OPERATION_CREATE:
		return (
			&"create_rollback_cleanup_outcome_unknown"
			if cleanup_error == ERR_TIMEOUT
			else &"create_rollback_cleanup_pending"
		)
	if cleanup_error == ERR_TIMEOUT:
		return (
			&"cleanup_outcome_unknown"
			if _catalog_state.cleanup_only
			else &"catalog_late_success_cleanup_outcome_unknown"
		)
	return (
		&"cleanup_reconciliation_pending"
		if _catalog_state.cleanup_only
		else &"catalog_late_success_cleanup_pending"
	)


## 投影 cleanup 已抵达确定终态时的兼容诊断状态；不得用于推进 Saga。
## @param cleanup_error: cleanup 的确定终态错误码。
func make_cleanup_terminal_evidence_status(cleanup_error: Error) -> StringName:
	if not is_catalog_compensation() or not _catalog_state.cleanup_required:
		return &""
	if _catalog_state.operation == LocalAccountOperation.OPERATION_CREATE:
		return (
			&"create_rollback_cleanup_reconciled"
			if cleanup_error == OK
			else &"create_rollback_cleanup_failed"
		)
	if cleanup_error == OK:
		return (
			&"cleanup_outcome_unknown_reconciled"
			if _catalog_state.cleanup_only
			else &"catalog_late_success_cleanup_succeeded"
		)
	return (
		&"cleanup_reconciliation_failed"
		if _catalog_state.cleanup_only
		else &"catalog_late_success_cleanup_failed"
	)


## 投影 cleanup 等待显式重试时的兼容诊断状态；不得用于推进 Saga。
func make_cleanup_retry_required_evidence_status() -> StringName:
	if not is_catalog_compensation() or not _catalog_state.cleanup_required:
		return &""
	if _catalog_state.operation == LocalAccountOperation.OPERATION_CREATE:
		return &"create_rollback_cleanup_retry_required"
	return (
		&"cleanup_retry_required"
		if _catalog_state.cleanup_only
		else &"catalog_late_success_cleanup_retry_required"
	)


# --- 状态推进方法 ---

## 接纳目录物理终态；成功写但候选 apply 失败时保持 fail-closed 等待态。
## @param result: 目录写请求的 GF 物理终态；缺失视为失败。
## @param candidate_apply_error: 迟到成功后重放候选目录的错误码。
## @param previous_active_account_id: 目录事务前的活动账号身份。
## @param active_account_id: 迟到终态处理后的活动账号身份。
func accept_catalog_settlement(
	result: GFStorageAsyncResult,
	candidate_apply_error: Error,
	previous_active_account_id: String,
	active_account_id: String
) -> bool:
	if (
		not is_catalog_compensation()
		or not is_waiting_for_catalog_settlement()
		or _catalog_state.settlement_received
	):
		return false
	var storage_succeeded: bool = result != null and result.is_successful()
	_catalog_state.settlement_received = true
	_catalog_state.publish_success = (
		storage_succeeded and candidate_apply_error == OK
	)
	_catalog_state.storage_succeeded = storage_succeeded
	_catalog_state.candidate_apply_error = candidate_apply_error
	_catalog_state.storage_result = (
		result.to_dict() if result != null else {}
	)
	_catalog_state.catalog_previous_active_account_id = (
		previous_active_account_id
	)
	_catalog_state.catalog_active_account_id = active_account_id
	if storage_succeeded and candidate_apply_error != OK:
		_condition = CONDITION_BLOCKED_CATALOG_APPLY
	else:
		_condition = CONDITION_NONE
		_phase = PHASE_READY
	return true


## 接纳与当前等待身份严格一致的 GF Profile settled-idle 证据。
## @param profile_id: 已抵达 settled-idle 的精确 GF Profile 身份。
func accept_profile_settled_idle(profile_id: StringName) -> bool:
	if (
		_phase != PHASE_WAITING
		or _condition != CONDITION_WAIT_PROFILE_SETTLEMENT
		or profile_id == &""
		or profile_id != get_profile_id()
	):
		return false
	_condition = CONDITION_NONE
	_phase = PHASE_READY
	return true


## 接纳与当前 cleanup 身份严格一致的物理终态证据。
## @param profile_file: 已结束 cleanup 的规范 Profile 路径。
func accept_cleanup_terminal(profile_file: String) -> bool:
	if (
		not is_catalog_compensation()
		or _phase != PHASE_WAITING
		or _condition != CONDITION_WAIT_CLEANUP_TERMINAL
		or profile_file.is_empty()
		or profile_file != _catalog_state.cleanup_profile_file
	):
		return false
	_condition = CONDITION_NONE
	_phase = PHASE_READY
	return true


## 显式重臂确定性失败的 cleanup；tick 不得调用此方法形成 IO 热循环。
func rearm_cleanup_retry() -> bool:
	if (
		not is_catalog_compensation()
		or _phase != PHASE_RETRY_REQUIRED
		or _condition != CONDITION_CLEANUP_RETRY_REQUIRED
	):
		return false
	_condition = CONDITION_NONE
	_phase = PHASE_READY
	return true


## 取得当前唯一 runner 执行权。
func begin_run() -> bool:
	if _phase != PHASE_READY or _condition != CONDITION_NONE:
		return false
	_phase = PHASE_RUNNING
	return true


## 本次 runner 遭遇已知失败，保持协调锁且禁止自动重臂。
func block_known_failure() -> bool:
	if _phase != PHASE_RUNNING:
		return false
	_condition = CONDITION_BLOCKED_KNOWN_FAILURE
	_phase = PHASE_WAITING
	return true


## Profile 对齐再次 outcome-unknown，冻结新的精确 Profile 身份后等待。
## @param profile_id: 新一次结果未知所绑定的精确 GF Profile 身份。
func wait_for_profile_settlement(profile_id: StringName) -> bool:
	if _phase != PHASE_RUNNING or profile_id == &"":
		return false
	if is_catalog_compensation():
		_catalog_state.profile_id = profile_id
	elif is_profile_alignment():
		_profile_state.profile_id = profile_id
	else:
		return false
	_condition = CONDITION_WAIT_PROFILE_SETTLEMENT
	_phase = PHASE_WAITING
	return true


## cleanup caller 未证明物理终态，继续持有目录补偿身份等待 exact terminal。
func wait_for_cleanup_terminal() -> bool:
	if not is_catalog_compensation() or _phase != PHASE_RUNNING:
		return false
	_condition = CONDITION_WAIT_CLEANUP_TERMINAL
	_phase = PHASE_WAITING
	return true


## cleanup 确定性失败，保留身份直到调用方显式重试。
func require_cleanup_retry() -> bool:
	if not is_catalog_compensation() or _phase != PHASE_RUNNING:
		return false
	_condition = CONDITION_CLEANUP_RETRY_REQUIRED
	_phase = PHASE_RETRY_REQUIRED
	return true


## 形成本 Saga 的唯一终态。
func complete() -> bool:
	if _phase != PHASE_RUNNING:
		return false
	_condition = CONDITION_NONE
	_phase = PHASE_COMPLETED
	return true


## 认领一次目录成功 publication effect。
func claim_catalog_success_publication() -> bool:
	if (
		not is_catalog_compensation()
		or not _catalog_state.publish_success
		or not _catalog_state.publish_events
		or _catalog_state.success_events_published
	):
		return false
	_catalog_state.success_events_published = true
	return true


## 返回失败路径中可能仍留在内存目录的 create 候选身份。
func get_retained_create_candidate_id() -> String:
	if (
		not is_catalog_compensation()
		or _catalog_state.operation != LocalAccountOperation.OPERATION_CREATE
		or _catalog_state.failure_catalog_event_published
	):
		return ""
	return (
		_catalog_state.cleanup_account_id
		if not _catalog_state.cleanup_account_id.is_empty()
		else _catalog_state.result_account_id
	)


## 标记失败路径的 create 候选目录事件已发布。
func mark_retained_create_candidate_published() -> bool:
	if get_retained_create_candidate_id().is_empty():
		return false
	_catalog_state.failure_catalog_event_published = true
	return true


# --- 私有/辅助方法 ---

static func _from_catalog_state(
	state: CatalogCompensationState,
	phase: StringName,
	condition: StringName
) -> LocalAccountReconciliationSaga:
	if (
		state == null
		or phase not in [PHASE_WAITING, PHASE_RETRY_REQUIRED]
		or condition not in [
			CONDITION_WAIT_CATALOG_SETTLEMENT,
			CONDITION_WAIT_CLEANUP_TERMINAL,
			CONDITION_CLEANUP_RETRY_REQUIRED,
		]
	):
		return null
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.new()
	)
	saga._kind = KIND_CATALOG_COMPENSATION
	saga._phase = phase
	saga._condition = condition
	saga._catalog_state = state
	return saga


static func _is_valid_optional_cleanup_target(
	profile_file: String,
	account_id: String
) -> bool:
	if profile_file.is_empty() and account_id.is_empty():
		return true
	if profile_file.is_empty() or not GFUuid.is_valid(account_id, 7):
		return false
	return profile_file == LocalAccountCatalogUtility.make_profile_file_name(
		account_id
	)


# --- 内部类 ---

class CatalogCompensationState extends RefCounted:
	var operation: StringName = &""
	var target_account_id: String = ""
	var result_account_id: String = ""
	var previous_account_id: String = ""
	var profile_id: StringName = &""
	var settlement_received: bool = false
	var publish_success: bool = false
	var publish_events: bool = true
	var success_events_published: bool = false
	var failure_catalog_event_published: bool = false
	var cleanup_required: bool = false
	var cleanup_profile_file: String = ""
	var cleanup_account_id: String = ""
	var cleanup_only: bool = false
	var storage_succeeded: bool = false
	var candidate_apply_error: Error = OK
	var storage_result: Dictionary = {}
	var catalog_previous_active_account_id: String = ""
	var catalog_active_account_id: String = ""


class ProfileAlignmentState extends RefCounted:
	var operation: StringName = &""
	var target_account_id: String = ""
	var result_account_id: String = ""
	var previous_account_id: String = ""
	var profile_id: StringName = &""
