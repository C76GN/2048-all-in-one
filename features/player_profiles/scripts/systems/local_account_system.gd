## LocalAccountSystem: 原子协调设备账号目录与独立玩家 GF Save Profile。
class_name LocalAccountSystem
extends GFSystem


# --- 信号 ---

signal active_account_changed(account: LocalPlayerAccount)
signal account_catalog_changed()
## true 表示账号目录迟到终态尚未与 GF Profile 收敛，新 saga 会被拒绝。
signal account_reconciliation_state_changed(pending: bool)


# --- 私有变量 ---

var _catalog: LocalAccountCatalogUtility = null
var _save_graph: GameSaveGraphUtility = null
var _storage: GFStorageUtility = null
var _profile_utility: GFSaveProfileUtility = null
var _background_work: GFBackgroundWorkUtility = null
var _signal_utility: GFSignalUtility = null
## 仅开发构建安装；发布构建缺失时必须静默降级。
var _async_tracker: GFAsyncTrackerUtility = null
var _async_tracking_ids: Dictionary = {}
var _last_cleanup_error: Error = OK
var _pending_operation: LocalAccountOperation = null
var _disposed: bool = false
var _dispose_requested: bool = false
var _operation_runner_started: bool = false
var _legacy_cleanup_in_progress: bool = false
var _catalog_reconciliation: Dictionary = {}
var _catalog_reconciliation_running: bool = false
var _profile_reconciliation: Dictionary = {}
var _profile_reconciliation_running: bool = false
var _last_reconciliation_evidence: Dictionary = {}

const _DISPOSE_DRAIN_STEPS: int = 8_000


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GFStorageUtility,
		GFSaveProfileUtility,
		GFBackgroundWorkUtility,
		GFSignalUtility,
		GameSaveGraphUtility,
		LocalAccountCatalogUtility,
	]


func ready() -> void:
	_disposed = false
	_dispose_requested = false
	_legacy_cleanup_in_progress = false
	_catalog = _resolve_catalog_utility()
	_save_graph = _resolve_save_graph_utility()
	_storage = _resolve_storage_utility()
	_profile_utility = _resolve_profile_utility()
	_background_work = _resolve_background_work_utility()
	_signal_utility = _resolve_signal_utility()
	_async_tracker = _resolve_optional_async_tracker()
	if not _is_configured():
		push_error("[LocalAccountSystem] 本地账号或 SaveGraph Utility 未注册。")
		return
	var _late_settlement_connection: GFSignalConnection = _signal_utility.connect_signal(
			_catalog.catalog_storage_late_settled,
			_on_catalog_storage_late_settled,
			self
	)
	var _profile_state_connection: GFSignalConnection = _signal_utility.connect_signal(
			_profile_utility.profile_state_changed,
			_on_profile_state_changed,
			self
	)
	var _profile_cleanup_connection: GFSignalConnection = _signal_utility.connect_signal(
			_save_graph.profile_cleanup_task_terminal,
			_on_profile_cleanup_task_terminal,
			self
	)
	var active_account: LocalPlayerAccount = _catalog.get_active_account()
	if active_account == null:
		push_error("[LocalAccountSystem] 本地账号目录没有有效的当前账号。")
		return
	var activate_error: Error = _save_graph.activate_profile(
		LocalAccountCatalogUtility.make_profile_file_name(
			active_account.account_id
		),
		true
	)
	if activate_error != OK:
		push_error(
			"[LocalAccountSystem] 当前账号 Profile 激活失败，错误码：%d。"
			% activate_error
		)
	else:
		call_deferred(&"_cleanup_legacy_profile_async")


## 推进目录迟到终态与当前 Profile 的协调。
## @param _delta: 本帧增量；协调只依赖类型化终态，因此不使用该值。
func tick(_delta: float = 0.0) -> void:
	_maybe_start_catalog_reconciliation()
	_maybe_start_profile_reconciliation()


func dispose() -> void:
	_dispose_requested = true
	if (
		_pending_operation != null
		and _pending_operation.is_pending()
		and not _operation_runner_started
	):
		_complete_account_operation(
			_pending_operation,
			LocalAccountOperationResult.STATUS_DISPOSED,
			ERR_UNAVAILABLE
		)
	# 系统先于依赖 Utility 销毁；用 GF 公共 tick 有界排空已经开始的
	# 事务，使目录/Profile saga 在释放引用前抵达明确终态。
	for _step: int in range(_DISPOSE_DRAIN_STEPS):
		if not _has_account_work_in_progress():
			break
		if is_instance_valid(_storage):
			_storage.tick(0.0)
		if is_instance_valid(_profile_utility):
			_profile_utility.tick(0.0)
		if is_instance_valid(_background_work):
			_background_work.tick(0.0)
		if is_instance_valid(_catalog):
			_catalog.tick(0.0)
		if is_instance_valid(_save_graph):
			_save_graph.tick(0.0)
		_maybe_start_catalog_reconciliation()
		_maybe_start_profile_reconciliation()
		OS.delay_msec(1)
	_disposed = true
	if _pending_operation != null and _pending_operation.is_pending():
		_complete_account_operation(
			_pending_operation,
			(
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
				if (
					is_instance_valid(_save_graph)
					and _save_graph.was_last_profile_transition_outcome_unknown()
				)
				else (
					LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
					if _catalog_outcome_unknown()
					else LocalAccountOperationResult.STATUS_DISPOSED
				)
			),
			ERR_TIMEOUT
		)
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_clear_async_tracking()
	if not _catalog_reconciliation.is_empty():
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": "disposed_before_reconciliation",
			&"error_code": int(ERR_TIMEOUT),
			&"reconciliation": _catalog_reconciliation.duplicate(true),
		}
	elif not _profile_reconciliation.is_empty():
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": "disposed_before_profile_reconciliation",
			&"error_code": int(ERR_TIMEOUT),
			&"reconciliation": _profile_reconciliation.duplicate(true),
		}
	_catalog_reconciliation.clear()
	_catalog_reconciliation_running = false
	_profile_reconciliation.clear()
	_profile_reconciliation_running = false
	_catalog = null
	_save_graph = null
	_storage = null
	_profile_utility = null
	_background_work = null
	_signal_utility = null
	_async_tracker = null
	_pending_operation = null
	_last_cleanup_error = OK
	_operation_runner_started = false
	_legacy_cleanup_in_progress = false


# --- 公共方法 ---

## 返回设备账号目录。
func get_accounts() -> Array[LocalPlayerAccount]:
	if not is_instance_valid(_catalog):
		return []
	return _catalog.get_accounts()


## 返回当前账号。
func get_active_account() -> LocalPlayerAccount:
	return _catalog.get_active_account() if is_instance_valid(_catalog) else null


## 返回最近一次孤立 Profile 文件清理错误。
func get_last_cleanup_error() -> Error:
	return _last_cleanup_error


## 返回当前账号事务；没有在途事务时返回 null。
func get_pending_operation() -> LocalAccountOperation:
	return _pending_operation


## 目录迟到终态是否仍在等待或正在与 GF Profile 协调。
func is_account_reconciliation_pending() -> bool:
	return (
		not _catalog_reconciliation.is_empty()
		or not _profile_reconciliation.is_empty()
	)


## 返回最近一次目录/Profile 协调的类型化证据摘要。
func get_last_reconciliation_evidence() -> Dictionary:
	return _last_reconciliation_evidence.duplicate(true)


## 显式请求推进账号协调。
##
## GF Profile 或目录写仍未抵达可判定终态时返回 ERR_BUSY；请求已接受或当前
## 无需协调时返回 OK。实际 Profile 对齐继续由异步协调状态机完成。
func request_account_reconciliation() -> Error:
	if _disposed or not _is_configured():
		return ERR_UNAVAILABLE
	if _catalog_reconciliation.is_empty() and _profile_reconciliation.is_empty():
		return OK
	if not _catalog_reconciliation.is_empty():
		if GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"cleanup_pending",
			false
		):
			var cleanup_file: String = GFVariantData.get_option_string(
				_catalog_reconciliation,
				&"cleanup_profile_file"
			)
			if (
				not cleanup_file.is_empty()
				and not _save_graph.is_profile_cleanup_pending(cleanup_file)
			):
				_catalog_reconciliation[&"reconcile_ready"] = true
		_maybe_start_catalog_reconciliation()
		return (
			OK
			if _catalog_reconciliation_running
			or GFVariantData.get_option_bool(
				_catalog_reconciliation,
				&"reconcile_ready",
				false
			)
			else ERR_BUSY
		)
	if _profile_reconciliation_can_run():
		_profile_reconciliation[&"reconcile_ready"] = true
	_maybe_start_profile_reconciliation()
	return (
		OK
		if _profile_reconciliation_running
		or GFVariantData.get_option_bool(
			_profile_reconciliation,
			&"reconcile_ready",
			false
		)
		else ERR_BUSY
	)


## 异步创建账号并切换到其独立空 Profile。
## @param display_name: 新账号在此设备上的显示名称。
func request_create_account(
	display_name: String
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = _make_account_operation(
		LocalAccountOperation.OPERATION_CREATE
	)
	if not _begin_account_operation(operation):
		return operation
	call_deferred(&"_run_create_account_operation", operation, display_name)
	return operation


## 异步切换到既有账号；Profile IO 不阻塞 UI 主线程。
## @param account_id: 要激活的本地账号稳定 ID。
func request_switch_account(
	account_id: String
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = _make_account_operation(
		LocalAccountOperation.OPERATION_SWITCH,
		account_id
	)
	if not _begin_account_operation(operation):
		return operation
	call_deferred(&"_run_switch_account_operation", operation, account_id)
	return operation


## 异步重命名账号；目录写入不阻塞 UI 主线程。
## @param account_id: 要重命名的本地账号稳定 ID。
## @param display_name: 账号的新显示名称。
func request_rename_account(
	account_id: String,
	display_name: String
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = _make_account_operation(
		LocalAccountOperation.OPERATION_RENAME,
		account_id
	)
	if not _begin_account_operation(operation):
		return operation
	call_deferred(
		&"_run_rename_account_operation",
		operation,
		account_id,
		display_name
	)
	return operation


## 异步删除账号；删除当前账号时先事务切换到回退 Profile。
## @param account_id: 要删除的本地账号稳定 ID。
func request_delete_account(
	account_id: String
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = _make_account_operation(
		LocalAccountOperation.OPERATION_DELETE,
		account_id
	)
	if not _begin_account_operation(operation):
		return operation
	call_deferred(&"_run_delete_account_operation", operation, account_id)
	return operation


# --- 私有/辅助方法 ---

func _run_create_account_operation(
	operation: LocalAccountOperation,
	display_name: String
) -> void:
	if not _is_current_operation(operation):
		return
	_operation_runner_started = true
	var previous_account: LocalPlayerAccount = _catalog.get_active_account()
	var account: LocalPlayerAccount = await _catalog.create_account_async(
		display_name,
		false
	)
	if not _is_current_operation(operation):
		return
	if account == null:
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
				if _catalog_outcome_unknown()
				else LocalAccountOperationResult.STATUS_CATALOG_FAILED
			),
			_catalog.get_last_error(),
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return

	var profile_file_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(account.account_id)
	)
	var profile_error: Error = await _save_graph.activate_profile_async(
		profile_file_name,
		false
	)
	if not _is_current_operation(operation):
		return
	if profile_error != OK:
		if _save_graph.was_last_profile_transition_outcome_unknown():
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN,
				profile_error,
				account,
				previous_account.account_id if previous_account != null else ""
			)
			return
		var catalog_rollback_error: Error = (
			await _catalog.delete_account_async(
				account.account_id,
				false
			)
		)
		if not _is_current_operation(operation):
			return
		var profile_cleanup_error: Error = (
			await _save_graph.delete_inactive_profile_async(
				profile_file_name
			)
		)
		if not _is_current_operation(operation):
			return
		var rollback_error: Error = (
			catalog_rollback_error
			if catalog_rollback_error != OK
			else profile_cleanup_error
		)
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
				if _catalog_outcome_unknown()
				else (
					LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
					if profile_cleanup_error == ERR_TIMEOUT
					else LocalAccountOperationResult.STATUS_ROLLBACK_FAILED
				)
				if rollback_error != OK
				else LocalAccountOperationResult.STATUS_PROFILE_FAILED
			),
			rollback_error if rollback_error != OK else profile_error,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return

	var activate_error: Error = await _catalog.set_active_account_async(
		account.account_id,
		false
	)
	if not _is_current_operation(operation):
		return
	if activate_error != OK:
		if _catalog_outcome_unknown():
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN,
				activate_error,
				account,
				previous_account.account_id if previous_account != null else ""
			)
			return
		var profile_rollback_error: Error = OK
		if previous_account != null:
			profile_rollback_error = await _save_graph.activate_profile_async(
				LocalAccountCatalogUtility.make_profile_file_name(
					previous_account.account_id
				),
				false
			)
		if not _is_current_operation(operation):
			return
		if (
			profile_rollback_error != OK
			and _save_graph.was_last_profile_transition_outcome_unknown()
		):
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN,
				profile_rollback_error,
				account,
				previous_account.account_id if previous_account != null else ""
			)
			return
		if profile_rollback_error != OK:
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_ROLLBACK_FAILED,
				profile_rollback_error,
				account,
				previous_account.account_id if previous_account != null else ""
			)
			return
		var catalog_cleanup_error: Error = (
			await _catalog.delete_account_async(
				account.account_id,
				false
			)
		)
		if not _is_current_operation(operation):
			return
		var profile_cleanup_error: Error = (
			await _save_graph.delete_inactive_profile_async(
				profile_file_name
			)
		)
		if not _is_current_operation(operation):
			return
		var rollback_error: Error = profile_rollback_error
		if rollback_error == OK:
			rollback_error = catalog_cleanup_error
		if rollback_error == OK:
			rollback_error = profile_cleanup_error
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
				if _catalog_outcome_unknown()
				else (
					LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
					if profile_cleanup_error == ERR_TIMEOUT
					else LocalAccountOperationResult.STATUS_ROLLBACK_FAILED
				)
				if rollback_error != OK
				else LocalAccountOperationResult.STATUS_CATALOG_FAILED
			),
			rollback_error if rollback_error != OK else activate_error,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return

	_publish_account_change(
		previous_account.account_id if previous_account != null else "",
		account
	)
	_complete_account_operation(
		operation,
		LocalAccountOperationResult.STATUS_SUCCEEDED,
		OK,
		account,
		previous_account.account_id if previous_account != null else ""
	)


func _run_switch_account_operation(
	operation: LocalAccountOperation,
	account_id: String
) -> void:
	if not _is_current_operation(operation):
		return
	_operation_runner_started = true
	var previous_account: LocalPlayerAccount = _catalog.get_active_account()
	if previous_account != null and previous_account.account_id == account_id:
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_SUCCEEDED,
			OK,
			previous_account,
			previous_account.account_id
		)
		return
	var next_account: LocalPlayerAccount = _catalog.get_account(account_id)
	if next_account == null:
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_INVALID_REQUEST,
			ERR_DOES_NOT_EXIST,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return

	var profile_error: Error = await _save_graph.activate_profile_async(
		LocalAccountCatalogUtility.make_profile_file_name(account_id),
		false
	)
	if not _is_current_operation(operation):
		return
	if profile_error != OK:
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
				if _save_graph.was_last_profile_transition_outcome_unknown()
				else LocalAccountOperationResult.STATUS_PROFILE_FAILED
			),
			profile_error,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return
	var catalog_error: Error = await _catalog.set_active_account_async(
		account_id,
		false
	)
	if not _is_current_operation(operation):
		return
	if catalog_error != OK:
		if _catalog_outcome_unknown():
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN,
				catalog_error,
				next_account,
				previous_account.account_id if previous_account != null else ""
			)
			return
		var rollback_error: Error = OK
		if previous_account != null:
			rollback_error = await _save_graph.activate_profile_async(
				LocalAccountCatalogUtility.make_profile_file_name(
					previous_account.account_id
				),
				false
			)
		if not _is_current_operation(operation):
			return
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
				if (
					rollback_error != OK
					and _save_graph.was_last_profile_transition_outcome_unknown()
				)
				else LocalAccountOperationResult.STATUS_ROLLBACK_FAILED
				if rollback_error != OK
				else LocalAccountOperationResult.STATUS_CATALOG_FAILED
			),
			rollback_error if rollback_error != OK else catalog_error,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return

	_publish_account_change(
		previous_account.account_id if previous_account != null else "",
		next_account
	)
	_complete_account_operation(
		operation,
		LocalAccountOperationResult.STATUS_SUCCEEDED,
		OK,
		next_account,
		previous_account.account_id if previous_account != null else ""
	)


func _run_rename_account_operation(
	operation: LocalAccountOperation,
	account_id: String,
	display_name: String
) -> void:
	if not _is_current_operation(operation):
		return
	_operation_runner_started = true
	var previous_account: LocalPlayerAccount = _catalog.get_active_account()
	var rename_error: Error = await _catalog.rename_account_async(
		account_id,
		display_name,
		false
	)
	if not _is_current_operation(operation):
		return
	if rename_error != OK:
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
				if _catalog_outcome_unknown()
				else LocalAccountOperationResult.STATUS_CATALOG_FAILED
			),
			rename_error,
			null,
			previous_account.account_id if previous_account != null else ""
		)
		return
	var renamed: LocalPlayerAccount = _catalog.get_account(account_id)
	account_catalog_changed.emit()
	if (
		renamed != null
		and previous_account != null
		and previous_account.account_id == account_id
	):
		active_account_changed.emit(renamed)
	_complete_account_operation(
		operation,
		LocalAccountOperationResult.STATUS_SUCCEEDED,
		OK,
		renamed,
		previous_account.account_id if previous_account != null else ""
	)


func _run_delete_account_operation(
	operation: LocalAccountOperation,
	account_id: String
) -> void:
	if not _is_current_operation(operation):
		return
	_operation_runner_started = true
	var accounts: Array[LocalPlayerAccount] = _catalog.get_accounts()
	if accounts.size() <= 1:
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_INVALID_REQUEST,
			ERR_BUSY
		)
		return
	var target: LocalPlayerAccount = _catalog.get_account(account_id)
	if target == null:
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_INVALID_REQUEST,
			ERR_DOES_NOT_EXIST
		)
		return
	var active_account: LocalPlayerAccount = _catalog.get_active_account()
	var fallback: LocalPlayerAccount = null
	var deleted_active: bool = (
		active_account != null and active_account.account_id == account_id
	)
	if deleted_active:
		for candidate: LocalPlayerAccount in accounts:
			if candidate.account_id != account_id:
				fallback = candidate
				break
		if fallback == null:
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_INVALID_REQUEST,
				ERR_BUSY
			)
			return
		var switch_error: Error = await _save_graph.activate_profile_async(
			LocalAccountCatalogUtility.make_profile_file_name(
				fallback.account_id
			),
			false
		)
		if not _is_current_operation(operation):
			return
		if switch_error != OK:
			_complete_account_operation(
				operation,
				(
					LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
						if _save_graph.was_last_profile_transition_outcome_unknown()
						else LocalAccountOperationResult.STATUS_PROFILE_FAILED
				),
				switch_error,
				null,
				active_account.account_id
			)
			return

	var delete_error: Error = OK
	if deleted_active:
		delete_error = (
			await _catalog.delete_active_account_with_fallback_async(
				account_id,
				fallback.account_id,
				false
			)
		)
	else:
		delete_error = await _catalog.delete_account_async(
			account_id,
			false
		)
	if not _is_current_operation(operation):
		return
	if delete_error != OK:
		if _catalog_outcome_unknown():
			_complete_account_operation(
				operation,
				LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN,
				delete_error,
				target,
				active_account.account_id if active_account != null else ""
			)
			return
		var rollback_error: Error = OK
		if deleted_active and active_account != null:
			rollback_error = await _save_graph.activate_profile_async(
				LocalAccountCatalogUtility.make_profile_file_name(
					active_account.account_id
				),
				false
			)
		if not _is_current_operation(operation):
			return
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
				if (
					rollback_error != OK
					and _save_graph.was_last_profile_transition_outcome_unknown()
				)
				else LocalAccountOperationResult.STATUS_ROLLBACK_FAILED
				if rollback_error != OK
				else LocalAccountOperationResult.STATUS_CATALOG_FAILED
			),
			rollback_error if rollback_error != OK else delete_error,
			null,
			active_account.account_id if active_account != null else ""
		)
		return

	_last_cleanup_error = await _save_graph.delete_inactive_profile_async(
		LocalAccountCatalogUtility.make_profile_file_name(
			account_id
		)
	)
	if not _is_current_operation(operation):
		return
	if deleted_active and fallback != null and active_account != null:
		_publish_account_change(active_account.account_id, fallback)
	else:
		account_catalog_changed.emit()
	_complete_account_operation(
		operation,
		(
			LocalAccountOperationResult.STATUS_SUCCEEDED
			if _last_cleanup_error == OK
			else (
				LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
				if _last_cleanup_error == ERR_TIMEOUT
				else LocalAccountOperationResult.STATUS_CLEANUP_FAILED
			)
		),
		_last_cleanup_error,
		fallback if deleted_active else _catalog.get_active_account(),
		active_account.account_id if active_account != null else ""
	)


func _make_account_operation(
	operation_kind: StringName,
	target_account_id: String = ""
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = LocalAccountOperation.new()
	var _configured: bool = operation.configure_for_system(
		operation_kind,
		target_account_id
	)
	return operation


func _cleanup_legacy_profile_async() -> void:
	if _disposed or _dispose_requested or not is_instance_valid(_save_graph):
		return
	_legacy_cleanup_in_progress = true
	var legacy_cleanup_error: Error = (
		await _save_graph.delete_inactive_legacy_profile_async()
	)
	_legacy_cleanup_in_progress = false
	if _disposed or _dispose_requested:
		return
	if legacy_cleanup_error not in [OK, ERR_INVALID_PARAMETER]:
		push_error(
			(
				"[LocalAccountSystem] 当前账号已激活，但 legacy Profile "
				+ "异步清理失败，错误码：%d。"
			)
			% legacy_cleanup_error
		)


func _begin_account_operation(
	operation: LocalAccountOperation
) -> bool:
	if operation == null:
		return false
	if _disposed or _dispose_requested or not _is_configured():
		_complete_account_operation(
			operation,
			(
				LocalAccountOperationResult.STATUS_DISPOSED
				if _disposed or _dispose_requested
				else LocalAccountOperationResult.STATUS_INVALID_REQUEST
			),
			ERR_UNCONFIGURED
		)
		return false
	if is_account_reconciliation_pending():
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_BUSY,
			ERR_BUSY
		)
		return false
	if _has_pending_operation():
		_complete_account_operation(
			operation,
			LocalAccountOperationResult.STATUS_BUSY,
			ERR_BUSY
		)
		return false
	_pending_operation = operation
	_operation_runner_started = false
	_track_account_operation(operation)
	return true


func _complete_account_operation(
	operation: LocalAccountOperation,
	status: StringName,
	error_code: Error,
	account: LocalPlayerAccount = null,
	previous_account_id: String = ""
) -> void:
	if operation == null or operation.is_completed():
		return
	if (
		status == LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
		and not _disposed
	):
		_begin_catalog_reconciliation(
			operation,
			account,
			previous_account_id
		)
	elif (
		status == LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
		and not _disposed
	):
		_begin_profile_reconciliation(
			operation,
			account,
			previous_account_id
		)
	elif (
		status == LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
		and not _disposed
	):
		_begin_cleanup_reconciliation(
			operation,
			account,
			previous_account_id
		)
	if _pending_operation == operation:
		_pending_operation = null
		_operation_runner_started = false
	var result: LocalAccountOperationResult = (
		LocalAccountOperationResult.new()
	)
	var _configured: bool = result.configure_for_system(
		operation.get_operation(),
		status,
		error_code,
		account,
		previous_account_id,
		(
			_save_graph.get_debug_snapshot()
			if is_instance_valid(_save_graph)
			else {}
		),
		(
			_catalog.get_last_async_storage_result()
			if is_instance_valid(_catalog)
			else {}
		)
	)
	var _completed: bool = operation.complete_for_system(result)
	_untrack_account_operation(operation)


func _is_current_operation(
	operation: LocalAccountOperation
) -> bool:
	return (
		not _disposed
		and operation != null
		and operation.is_pending()
		and _pending_operation == operation
		and _is_configured()
	)


func _has_pending_operation() -> bool:
	return (
		_pending_operation != null
		and _pending_operation.is_pending()
	)


func _has_account_work_in_progress() -> bool:
	return (
		_has_pending_operation()
		or _legacy_cleanup_in_progress
		or is_account_reconciliation_pending()
		or (
			is_instance_valid(_catalog)
			and _catalog.has_pending_late_storage_settlement()
		)
	)


func _begin_catalog_reconciliation(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String
) -> void:
	if (
		operation == null
		or not _catalog_reconciliation.is_empty()
		or not _profile_reconciliation.is_empty()
	):
		return
	_catalog_reconciliation = {
		&"operation": operation.get_operation(),
		&"target_account_id": operation.get_target_account_id(),
		&"result_account_id": (
			account.account_id if account != null else ""
		),
		&"previous_account_id": previous_account_id,
		&"settlement_received": false,
		&"reconcile_ready": false,
		&"publish_success": false,
		&"publish_events": true,
	}
	_last_reconciliation_evidence = {
		&"ok": false,
		&"status": "catalog_outcome_unknown",
		&"error_code": int(ERR_TIMEOUT),
		&"operation": String(operation.get_operation()),
		&"previous_account_id": previous_account_id,
		&"catalog": (
			_catalog.get_last_async_storage_result()
			if is_instance_valid(_catalog)
			else {}
		),
	}
	account_reconciliation_state_changed.emit(true)


func _begin_profile_reconciliation(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String
) -> void:
	if (
		operation == null
		or not _catalog_reconciliation.is_empty()
		or not _profile_reconciliation.is_empty()
		or not is_instance_valid(_save_graph)
	):
		return
	var profile_evidence: Dictionary = (
		_save_graph.get_last_profile_transition_evidence()
	)
	var profile_id: StringName = GFVariantData.get_option_string_name(
		profile_evidence,
		&"profile_id"
	)
	_profile_reconciliation = {
		&"operation": operation.get_operation(),
		&"target_account_id": operation.get_target_account_id(),
		&"result_account_id": (
			account.account_id if account != null else ""
		),
		&"previous_account_id": previous_account_id,
		&"profile_id": profile_id,
		&"reconcile_ready": false,
	}
	_last_reconciliation_evidence = {
		&"ok": false,
		&"status": "profile_outcome_unknown",
		&"error_code": int(ERR_TIMEOUT),
		&"operation": String(operation.get_operation()),
		&"profile_id": String(profile_id),
		&"previous_account_id": previous_account_id,
		&"profile": profile_evidence.duplicate(true),
	}
	account_reconciliation_state_changed.emit(true)


func _begin_cleanup_reconciliation(
	operation: LocalAccountOperation,
	account: LocalPlayerAccount,
	previous_account_id: String
) -> void:
	if (
		operation == null
		or operation.get_operation()
		!= LocalAccountOperation.OPERATION_DELETE
		or not _catalog_reconciliation.is_empty()
		or not _profile_reconciliation.is_empty()
	):
		return
	var cleanup_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			operation.get_target_account_id()
		)
	)
	_catalog_reconciliation = {
		&"operation": operation.get_operation(),
		&"target_account_id": operation.get_target_account_id(),
		&"result_account_id": (
			account.account_id if account != null else ""
		),
		&"previous_account_id": previous_account_id,
		&"settlement_received": true,
		&"reconcile_ready": false,
		&"publish_success": true,
		&"publish_events": false,
		&"cleanup_pending": true,
		&"cleanup_profile_file": cleanup_profile_file,
		&"cleanup_only": true,
	}
	_last_reconciliation_evidence = {
		&"ok": false,
		&"status": "cleanup_outcome_unknown",
		&"error_code": int(ERR_TIMEOUT),
		&"operation": String(operation.get_operation()),
		&"target_account_id": operation.get_target_account_id(),
		&"cleanup_profile_file": cleanup_profile_file,
	}
	account_reconciliation_state_changed.emit(true)


func _on_catalog_storage_late_settled(
	result: GFStorageAsyncResult,
	candidate_apply_error: Error,
	previous_active_account_id: String,
	active_account_id: String
) -> void:
	if _disposed or _catalog_reconciliation.is_empty():
		return
	var storage_succeeded: bool = (
		result != null and result.is_successful()
	)
	_catalog_reconciliation[&"settlement_received"] = true
	_catalog_reconciliation[&"reconcile_ready"] = true
	_catalog_reconciliation[&"publish_success"] = (
		storage_succeeded and candidate_apply_error == OK
	)
	_catalog_reconciliation[&"storage_succeeded"] = storage_succeeded
	_catalog_reconciliation[&"candidate_apply_error"] = int(
		candidate_apply_error
	)
	_catalog_reconciliation[&"storage_result"] = (
		result.to_dict() if result != null else {}
	)
	_catalog_reconciliation[&"catalog_previous_active_account_id"] = (
		previous_active_account_id
	)
	_catalog_reconciliation[&"catalog_active_account_id"] = active_account_id
	_last_reconciliation_evidence = {
		&"ok": false,
		&"status": (
			"catalog_late_success"
			if storage_succeeded and candidate_apply_error == OK
			else (
				"catalog_late_apply_failed"
				if storage_succeeded
				else "catalog_late_failed"
			)
		),
		&"error_code": int(
			candidate_apply_error
			if storage_succeeded
			else (
				result.get_error_code()
				if result != null
				else ERR_CANT_CREATE
			)
		),
		&"operation": String(
			GFVariantData.get_option_string_name(
				_catalog_reconciliation,
				&"operation"
			)
		),
		&"storage_result": (
			result.to_dict() if result != null else {}
		),
		&"candidate_apply_error": int(candidate_apply_error),
		&"catalog_active_account_id": active_account_id,
	}
	# 写已成功但候选目录无法重放时，磁盘与内存权威状态不确定；
	# 保持阻塞并保留证据，不能擅自按旧目录切 Profile。
	if storage_succeeded and candidate_apply_error != OK:
		return
	call_deferred(&"_maybe_start_catalog_reconciliation")


func _on_profile_state_changed(
	profile_id: StringName,
	_previous_state: StringName,
	current_state: StringName
) -> void:
	if (
		current_state == GFSaveProfileUtility.STATE_IDLE
		and not _profile_reconciliation.is_empty()
		and profile_id
		== GFVariantData.get_option_string_name(
			_profile_reconciliation,
			&"profile_id"
		)
		and _profile_reconciliation_can_run()
	):
		_profile_reconciliation[&"reconcile_ready"] = true
		call_deferred(&"_maybe_start_profile_reconciliation")
	if (
		current_state == GFSaveProfileUtility.STATE_IDLE
		and not _catalog_reconciliation.is_empty()
		and not _catalog_reconciliation_running
		and GFVariantData.get_option_string_name(
			_last_reconciliation_evidence,
			&"status"
		)
		== &"profile_reconciliation_outcome_unknown"
	):
		_catalog_reconciliation[&"reconcile_ready"] = true
		call_deferred(&"_maybe_start_catalog_reconciliation")
	if (
		current_state == GFSaveProfileUtility.STATE_IDLE
		and not _catalog_reconciliation.is_empty()
		and GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"cleanup_pending",
			false
		)
		and profile_id == _profile_id_for_account(
			GFVariantData.get_option_string(
				_catalog_reconciliation,
				&"target_account_id"
			)
		)
	):
		_catalog_reconciliation[&"reconcile_ready"] = true
		call_deferred(&"_maybe_start_catalog_reconciliation")


func _on_profile_cleanup_task_terminal(_work_id: StringName) -> void:
	if (
		_disposed
		or _catalog_reconciliation.is_empty()
		or not GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"cleanup_pending",
			false
		)
		or not is_instance_valid(_save_graph)
	):
		return
	var cleanup_file: String = GFVariantData.get_option_string(
		_catalog_reconciliation,
		&"cleanup_profile_file"
	)
	if (
		cleanup_file.is_empty()
		or _save_graph.is_profile_cleanup_pending(cleanup_file)
	):
		return
	_catalog_reconciliation[&"reconcile_ready"] = true
	call_deferred(&"_maybe_start_catalog_reconciliation")


func _maybe_start_catalog_reconciliation() -> void:
	if (
		not _catalog_reconciliation.is_empty()
		and GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"cleanup_pending",
			false
		)
		and is_instance_valid(_save_graph)
	):
		var cleanup_file: String = GFVariantData.get_option_string(
			_catalog_reconciliation,
			&"cleanup_profile_file"
		)
		if (
			not cleanup_file.is_empty()
			and not _save_graph.is_profile_cleanup_pending(cleanup_file)
		):
			_catalog_reconciliation[&"reconcile_ready"] = true
	if (
		_disposed
		or _catalog_reconciliation_running
		or _catalog_reconciliation.is_empty()
		or not GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"settlement_received",
			false
		)
		or not GFVariantData.get_option_bool(
			_catalog_reconciliation,
			&"reconcile_ready",
			false
		)
		or not _is_configured()
	):
		return
	var status: StringName = GFVariantData.get_option_string_name(
		_last_reconciliation_evidence,
		&"status"
	)
	if status == &"catalog_late_apply_failed":
		return
	_catalog_reconciliation[&"reconcile_ready"] = false
	_catalog_reconciliation_running = true
	call_deferred(&"_run_catalog_reconciliation")


func _maybe_start_profile_reconciliation() -> void:
	if (
		_disposed
		or _profile_reconciliation_running
		or _profile_reconciliation.is_empty()
		or not _is_configured()
	):
		return
	if (
		not GFVariantData.get_option_bool(
			_profile_reconciliation,
			&"reconcile_ready",
			false
		)
		and GFVariantData.get_option_string_name(
			_last_reconciliation_evidence,
			&"status"
		)
		== &"profile_outcome_unknown"
		and _profile_reconciliation_can_run()
	):
		_profile_reconciliation[&"reconcile_ready"] = true
	if not GFVariantData.get_option_bool(
		_profile_reconciliation,
		&"reconcile_ready",
		false
	):
		return
	_profile_reconciliation[&"reconcile_ready"] = false
	_profile_reconciliation_running = true
	call_deferred(&"_run_profile_reconciliation")


func _run_profile_reconciliation() -> void:
	if _profile_reconciliation.is_empty() or not _is_configured():
		_profile_reconciliation_running = false
		return
	var authoritative_account: LocalPlayerAccount = (
		_catalog.get_active_account()
	)
	if authoritative_account == null:
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": "profile_reconciliation_catalog_missing",
			&"error_code": int(ERR_INVALID_DATA),
		}
		_profile_reconciliation_running = false
		return
	var profile_file_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			authoritative_account.account_id
		)
	)
	var reconcile_error: Error = OK
	if _save_graph.get_profile_file_name() != profile_file_name:
		reconcile_error = await _save_graph.activate_profile_async(
			profile_file_name,
			false
		)
	if _disposed or _profile_reconciliation.is_empty():
		_profile_reconciliation_running = false
		return
	if reconcile_error != OK:
		var outcome_unknown: bool = (
			_save_graph.was_last_profile_transition_outcome_unknown()
		)
		var profile_evidence: Dictionary = (
			_save_graph.get_last_profile_transition_evidence()
		)
		if outcome_unknown:
			_profile_reconciliation[&"profile_id"] = (
				GFVariantData.get_option_string_name(
					profile_evidence,
					&"profile_id"
				)
			)
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": (
				"profile_reconciliation_outcome_unknown"
				if outcome_unknown
				else "profile_reconciliation_failed"
			),
			&"error_code": int(reconcile_error),
			&"catalog_active_account_id": authoritative_account.account_id,
			&"profile_file": _save_graph.get_profile_file_name(),
			&"profile": profile_evidence,
		}
		_profile_reconciliation_running = false
		return
	var reconciliation: Dictionary = _profile_reconciliation.duplicate(true)
	_last_reconciliation_evidence = {
		&"ok": true,
		&"status": "profile_outcome_unknown_reconciled",
		&"error_code": int(OK),
		&"operation": String(
			GFVariantData.get_option_string_name(
				reconciliation,
				&"operation"
			)
		),
		&"catalog_active_account_id": authoritative_account.account_id,
		&"profile_file": _save_graph.get_profile_file_name(),
	}
	_profile_reconciliation.clear()
	_profile_reconciliation_running = false
	account_reconciliation_state_changed.emit(false)
	var operation_kind: StringName = GFVariantData.get_option_string_name(
		reconciliation,
		&"operation"
	)
	if operation_kind == LocalAccountOperation.OPERATION_CREATE:
		var result_account_id: String = GFVariantData.get_option_string(
			reconciliation,
			&"result_account_id"
		)
		if authoritative_account.account_id == result_account_id:
			_publish_account_change(
				GFVariantData.get_option_string(
					reconciliation,
					&"previous_account_id"
				),
				authoritative_account
			)
		else:
			account_catalog_changed.emit()


func _profile_reconciliation_can_run() -> bool:
	if (
		_profile_reconciliation.is_empty()
		or not is_instance_valid(_profile_utility)
	):
		return false
	var profile_id: StringName = GFVariantData.get_option_string_name(
		_profile_reconciliation,
		&"profile_id"
	)
	if profile_id == &"":
		return false
	var snapshot: Dictionary = (
		_profile_utility.get_profile_state_snapshot(profile_id)
	)
	return (
		not snapshot.is_empty()
		and GFVariantData.get_option_string_name(snapshot, &"state")
		== GFSaveProfileUtility.STATE_IDLE
		and GFVariantData.get_option_int(
			snapshot,
			&"save_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"load_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"flush_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"detached_write_count",
			0
		)
		== 0
		and not GFVariantData.get_option_bool(
			snapshot,
			&"write_outcome_unknown",
			false
		)
	)


func _run_catalog_reconciliation() -> void:
	if _catalog_reconciliation.is_empty() or not _is_configured():
		_catalog_reconciliation_running = false
		return
	var authoritative_account: LocalPlayerAccount = (
		_catalog.get_active_account()
	)
	if authoritative_account == null:
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": "catalog_authority_missing",
			&"error_code": int(ERR_INVALID_DATA),
			&"catalog": _catalog.get_last_async_storage_result(),
		}
		_catalog_reconciliation_running = false
		return
	var profile_file_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			authoritative_account.account_id
		)
	)
	var reconcile_error: Error = OK
	if _save_graph.get_profile_file_name() != profile_file_name:
		reconcile_error = await _save_graph.activate_profile_async(
			profile_file_name,
			false
		)
	if _disposed or _catalog_reconciliation.is_empty():
		_catalog_reconciliation_running = false
		return
	if reconcile_error != OK:
		_last_reconciliation_evidence = {
			&"ok": false,
			&"status": (
				"profile_reconciliation_outcome_unknown"
				if _save_graph.was_last_profile_transition_outcome_unknown()
				else "profile_reconciliation_failed"
			),
			&"error_code": int(reconcile_error),
			&"catalog_active_account_id": authoritative_account.account_id,
			&"profile_file": _save_graph.get_profile_file_name(),
			&"profile": _save_graph.get_last_profile_transition_evidence(),
			&"catalog": _catalog.get_last_async_storage_result(),
		}
		_catalog_reconciliation_running = false
		return

	var reconciliation: Dictionary = _catalog_reconciliation.duplicate(true)
	var publish_success: bool = GFVariantData.get_option_bool(
		reconciliation,
		&"publish_success",
		false
	)
	var operation_kind: StringName = GFVariantData.get_option_string_name(
		reconciliation,
		&"operation"
	)
	var cleanup_only: bool = GFVariantData.get_option_bool(
		reconciliation,
		&"cleanup_only",
		false
	)
	var cleanup_error: Error = OK
	var cleanup_profile_file: String = ""
	if (
		publish_success
		and operation_kind == LocalAccountOperation.OPERATION_DELETE
	):
		var target_account_id: String = GFVariantData.get_option_string(
			reconciliation,
			&"target_account_id"
		)
		cleanup_profile_file = (
			LocalAccountCatalogUtility.make_profile_file_name(
				target_account_id
			)
		)
		cleanup_error = await _save_graph.delete_inactive_profile_async(
			cleanup_profile_file
		)
		if _disposed or _catalog_reconciliation.is_empty():
			_catalog_reconciliation_running = false
			return
		_last_cleanup_error = cleanup_error
		if cleanup_error in [ERR_TIMEOUT, ERR_BUSY]:
			_catalog_reconciliation[&"cleanup_pending"] = true
			_catalog_reconciliation[&"cleanup_profile_file"] = (
				cleanup_profile_file
			)
			_last_reconciliation_evidence = {
				&"ok": false,
				&"status": (
					(
						"cleanup_outcome_unknown"
						if cleanup_only
						else "catalog_late_success_cleanup_outcome_unknown"
					)
					if cleanup_error == ERR_TIMEOUT
					else (
						"cleanup_reconciliation_pending"
						if cleanup_only
						else "catalog_late_success_cleanup_pending"
					)
				),
				&"error_code": int(cleanup_error),
				&"operation": String(operation_kind),
				&"target_account_id": target_account_id,
				&"catalog_active_account_id": authoritative_account.account_id,
				&"profile_file": _save_graph.get_profile_file_name(),
				&"cleanup_profile_file": cleanup_profile_file,
				&"storage_result": GFVariantData.get_option_dictionary(
					reconciliation,
					&"storage_result"
				),
			}
			_catalog_reconciliation_running = false
			return
	_last_reconciliation_evidence = {
		&"ok": cleanup_error == OK,
		&"status": (
			(
				(
					"cleanup_outcome_unknown_reconciled"
					if cleanup_only
					else "catalog_late_success_cleanup_succeeded"
				)
				if cleanup_error == OK
				else (
					"cleanup_reconciliation_failed"
					if cleanup_only
					else "catalog_late_success_cleanup_failed"
				)
			)
			if (
				publish_success
				and operation_kind == LocalAccountOperation.OPERATION_DELETE
			)
			else (
				"catalog_late_success_reconciled"
				if publish_success
				else "catalog_late_failure_rolled_back"
			)
		),
		&"error_code": int(cleanup_error),
		&"operation": String(
			operation_kind
		),
		&"catalog_active_account_id": authoritative_account.account_id,
		&"profile_file": _save_graph.get_profile_file_name(),
		&"cleanup_profile_file": cleanup_profile_file,
		&"storage_result": GFVariantData.get_option_dictionary(
			reconciliation,
			&"storage_result"
		),
	}
	_catalog_reconciliation.clear()
	_catalog_reconciliation_running = false
	account_reconciliation_state_changed.emit(false)
	if (
		publish_success
		and GFVariantData.get_option_bool(
			reconciliation,
			&"publish_events",
			true
		)
	):
		_publish_reconciled_catalog_success(
			reconciliation,
			authoritative_account
		)


func _publish_reconciled_catalog_success(
	reconciliation: Dictionary,
	active_account: LocalPlayerAccount
) -> void:
	if active_account == null:
		return
	var previous_account_id: String = GFVariantData.get_option_string(
		reconciliation,
		&"previous_account_id"
	)
	if previous_account_id != active_account.account_id:
		_publish_account_change(previous_account_id, active_account)
		return
	var operation_kind: StringName = GFVariantData.get_option_string_name(
		reconciliation,
		&"operation"
	)
	var target_account_id: String = GFVariantData.get_option_string(
		reconciliation,
		&"target_account_id"
	)
	if (
		operation_kind == LocalAccountOperation.OPERATION_RENAME
		and target_account_id == active_account.account_id
	):
		active_account_changed.emit(active_account)
	account_catalog_changed.emit()


func _catalog_outcome_unknown() -> bool:
	if not is_instance_valid(_catalog):
		return false
	return (
		GFVariantData.get_option_string_name(
			_catalog.get_last_async_storage_result(),
			&"status"
		)
		== &"outcome_unknown"
	)


func _publish_account_change(
	previous_account_id: String,
	account: LocalPlayerAccount
) -> void:
	var current_account: LocalPlayerAccount = _catalog.get_account(
		account.account_id
	)
	if current_account == null:
		return
	active_account_changed.emit(current_account)
	account_catalog_changed.emit()
	var event_data: ActiveLocalAccountChangedData = (
		ActiveLocalAccountChangedData.create(
			previous_account_id,
			current_account
		)
	)
	if event_data != null:
		send_event(event_data)


func _profile_id_for_account(account_id: String) -> StringName:
	if not GFUuid.is_valid(account_id, 7):
		return &""
	return StringName("player_data.%s" % account_id)


func _track_account_operation(operation: LocalAccountOperation) -> void:
	if operation == null or not operation.is_pending():
		return
	var tracker: GFAsyncTrackerUtility = _resolve_optional_async_tracker()
	if tracker == null:
		return
	var handle_instance_id: int = operation.get_instance_id()
	if _async_tracking_ids.has(handle_instance_id):
		return
	var tracking_id: int = tracker.track_handle(
		operation,
		&"local_account.operation",
		{
			&"owner": "LocalAccountSystem",
			&"operation": String(operation.get_operation()),
			&"target_account_id": operation.get_target_account_id(),
		}
	)
	if tracking_id > 0:
		_async_tracking_ids[handle_instance_id] = tracking_id


func _untrack_account_operation(operation: LocalAccountOperation) -> void:
	if operation == null:
		return
	var handle_instance_id: int = operation.get_instance_id()
	var tracking_id: int = GFVariantData.get_option_int(
		_async_tracking_ids,
		handle_instance_id,
		0
	)
	if tracking_id <= 0:
		return
	if is_instance_valid(_async_tracker):
		var _untracked: bool = _async_tracker.untrack_id(tracking_id)
	var _erased: bool = _async_tracking_ids.erase(handle_instance_id)


func _clear_async_tracking() -> void:
	if is_instance_valid(_async_tracker):
		for tracking_id_value: Variant in _async_tracking_ids.values():
			var tracking_id: int = GFVariantData.to_int(
				tracking_id_value
			)
			if tracking_id > 0:
				var _untracked: bool = (
					_async_tracker.untrack_id(tracking_id)
				)
	_async_tracking_ids.clear()


func _resolve_optional_async_tracker() -> GFAsyncTrackerUtility:
	if is_instance_valid(_async_tracker):
		return _async_tracker
	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return null
	# Tracker 只由开发诊断 Installer 安装；local lookup 不触发 strict miss。
	var utility_value: Object = architecture.get_local_utility(
		GFAsyncTrackerUtility
	)
	if utility_value is GFAsyncTrackerUtility:
		_async_tracker = utility_value
		return _async_tracker
	return null


func _is_configured() -> bool:
	return (
		is_instance_valid(_catalog)
		and is_instance_valid(_save_graph)
		and is_instance_valid(_storage)
		and is_instance_valid(_profile_utility)
		and is_instance_valid(_background_work)
		and is_instance_valid(_signal_utility)
	)


func _resolve_catalog_utility() -> LocalAccountCatalogUtility:
	var utility_value: Object = get_utility(LocalAccountCatalogUtility)
	if utility_value is LocalAccountCatalogUtility:
		var catalog: LocalAccountCatalogUtility = utility_value
		return catalog
	return null


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = utility_value
		return save_graph
	return null


func _resolve_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null


func _resolve_profile_utility() -> GFSaveProfileUtility:
	var utility_value: Object = get_utility(GFSaveProfileUtility)
	if utility_value is GFSaveProfileUtility:
		var profile_utility: GFSaveProfileUtility = utility_value
		return profile_utility
	return null


func _resolve_background_work_utility() -> GFBackgroundWorkUtility:
	var utility_value: Object = get_utility(GFBackgroundWorkUtility)
	if utility_value is GFBackgroundWorkUtility:
		var background_work: GFBackgroundWorkUtility = utility_value
		return background_work
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null
