## LocalAccountCatalogUtility: 持有设备本地账号目录与当前账号选择。
##
## 账号目录是进入任一玩家 Profile 之前必须可用的设备级身份索引；
## 每个账号的业务数据仍由独立 GF Save Profile 拥有。
class_name LocalAccountCatalogUtility
extends GFUtility


# --- 信号 ---

signal account_catalog_changed()
signal active_account_changed(account_id: String)
signal catalog_storage_poll()
## 自定义 deadline 后仍在运行的 GFStorage 请求抵达真实终态。
##
## result 是 GF 的类型化存储终态；candidate_apply_error 仅在迟到写成功后
## 应用候选目录失败时非 OK。System 用此边界协调 Profile 与目录权威状态。
signal catalog_storage_late_settled(
	result: GFStorageAsyncResult,
	candidate_apply_error: Error,
	previous_active_account_id: String,
	active_account_id: String
)


# --- 常量 ---

const CATALOG_FILE_NAME: String = "local_accounts.save"
const MAX_ACCOUNTS: int = 8
const CATALOG_SCHEMA_VERSION: int = 1
const PROFILE_DIRECTORY: String = "profiles"
const PROFILE_EXTENSION: String = ".save"
const _CATALOG_IO_TIMEOUT_MSEC: int = 5_000
const _DISPOSE_DRAIN_STEPS: int = 6_000
const _CATALOG_MUTATION_GATE_KEY: StringName = &"device_account_catalog"


# --- 私有变量 ---

var _storage: GFStorageUtility = null
var _clock: GameClockUtility = null
## 开发诊断可选能力；发布构建未安装时不得产生 strict lookup 错误。
var _async_tracker: GFAsyncTrackerUtility = null
var _async_tracking_ids: Dictionary = {}
var _accounts: Array[LocalPlayerAccount] = []
var _active_account_id: String = ""
var _last_error: Error = OK
var _last_async_storage_result: Dictionary = {}
var _disposed: bool = false
var _mutation_gate: GFAsyncKeyedGate = GFAsyncKeyedGate.new()
var _active_mutation_lease: GFAsyncGateLease = null
var _operation_diagnostics: GFOperationDiagnosticsUtility = null
var _catalog_diagnostic_operation_id: StringName = &""
var _pending_storage_operation: GFStorageAsyncOperation = null
var _pending_storage_deadline_msec: int = 0
var _detached_storage_operations: Dictionary = {}


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GFOperationDiagnosticsUtility,
		GFStorageUtility,
	]


func ready() -> void:
	_disposed = false
	_storage = _resolve_storage_utility()
	_clock = _resolve_clock_utility()
	_operation_diagnostics = _resolve_operation_diagnostics_utility()
	_async_tracker = _resolve_optional_async_tracker()
	_last_error = _load_catalog()
	if _last_error != OK:
		push_error(
			"[LocalAccountCatalogUtility] 本地账号目录加载失败，错误码：%d。"
			% _last_error
		)


## 轮询目录异步写入及其 deadline 后的真实终态。
## @param _delta: 本帧增量；存储操作使用 GFClock deadline，不使用该值。
func tick(_delta: float = 0.0) -> void:
	_poll_catalog_storage_operations()


func dispose() -> void:
	# 先用 GF 公共 tick 有界排空已提交写入，让候选目录在销毁前得到
	# 明确成功/失败；禁止调用 wait_for_async_tasks 阻塞等待线程。
	for _step: int in range(_DISPOSE_DRAIN_STEPS):
		if (
			_pending_storage_operation == null
			and _detached_storage_operations.is_empty()
		):
			break
		if is_instance_valid(_storage):
			_storage.tick(0.0)
		_poll_catalog_storage_operations()
		OS.delay_msec(1)
	_disposed = true
	_clear_async_tracking()
	_finish_catalog_diagnostic_operation(ERR_UNAVAILABLE)
	var _cleared_gate_entries: int = _mutation_gate.clear(
		&"catalog_disposed",
		{&"component": &"local_account_catalog"}
	)
	_active_mutation_lease = null
	_storage = null
	_clock = null
	_operation_diagnostics = null
	_async_tracker = null
	_accounts.clear()
	_active_account_id = ""
	_last_error = OK
	_last_async_storage_result.clear()
	_pending_storage_operation = null
	_pending_storage_deadline_msec = 0
	_detached_storage_operations.clear()


# --- 公共方法 ---

## 返回账号目录最近一次错误。
func get_last_error() -> Error:
	return _last_error


## 返回最近一次异步目录提交的 GFStorageAsyncResult 证据。
func get_last_async_storage_result() -> Dictionary:
	return _last_async_storage_result.duplicate(true)


## 是否仍有 deadline 后尚未抵达真实终态的目录写入。
func has_pending_late_storage_settlement() -> bool:
	return not _detached_storage_operations.is_empty()


## 返回当前账号目录的只读副本。
func get_accounts() -> Array[LocalPlayerAccount]:
	var result: Array[LocalPlayerAccount] = []
	for account: LocalPlayerAccount in _accounts:
		var copy: LocalPlayerAccount = LocalPlayerAccount.from_dict(account.to_dict())
		if copy != null:
			result.append(copy)
	return result


## 返回当前激活账号。
func get_active_account() -> LocalPlayerAccount:
	return get_account(_active_account_id)


## 返回当前激活账号 ID。
func get_active_account_id() -> String:
	return _active_account_id


## 按稳定 ID 返回账号只读副本。
## @param account_id: 要查找的本地账号稳定 ID。
func get_account(account_id: String) -> LocalPlayerAccount:
	var account: LocalPlayerAccount = _find_account(account_id)
	return (
		LocalPlayerAccount.from_dict(account.to_dict())
		if account != null
		else null
	)


## 异步创建但不激活账号；候选目录写入成功后才交换权威内存状态。
## @param display_name: 新账号在此设备上的显示名称。
## @param publish_signals: 成功后是否发布目录变更信号。
func create_account_async(
	display_name: String,
	publish_signals: bool = true
) -> LocalPlayerAccount:
	if not _begin_async_catalog_mutation(&"create"):
		return null
	var mutation_token: int = _get_active_mutation_token()
	if _accounts.size() >= MAX_ACCOUNTS:
		_finish_async_catalog_mutation(ERR_OUT_OF_MEMORY)
		return null
	var normalized_name: String = LocalPlayerAccount.normalize_display_name(
		display_name
	)
	if normalized_name.is_empty() or _has_display_name(normalized_name):
		_finish_async_catalog_mutation(
			ERR_ALREADY_EXISTS
			if not normalized_name.is_empty()
			else ERR_INVALID_PARAMETER
		)
		return null
	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		normalized_name,
		_get_unix_timestamp()
	)
	if account == null:
		_finish_async_catalog_mutation(ERR_INVALID_DATA)
		return null
	var candidate: Dictionary = _make_catalog_payload()
	var candidate_accounts: Array = GFVariantData.get_option_array(
		candidate,
		&"accounts"
	)
	candidate_accounts.append(account.to_dict())
	candidate[&"accounts"] = candidate_accounts
	var save_error: Error = await _save_catalog_async(candidate)
	if not _owns_async_catalog_mutation(mutation_token):
		return null
	if save_error != OK:
		_finish_async_catalog_mutation(save_error)
		return null
	var apply_error: Error = _apply_catalog_payload(candidate)
	if apply_error != OK:
		_finish_async_catalog_mutation(apply_error)
		return null
	_finish_async_catalog_mutation(OK)
	if publish_signals:
		account_catalog_changed.emit()
	return get_account(account.account_id)


## 异步重命名账号；失败时恢复内存名称且不发布目录信号。
## @param account_id: 要重命名的本地账号稳定 ID。
## @param display_name: 账号的新显示名称。
## @param publish_signals: 成功后是否发布目录变更信号。
func rename_account_async(
	account_id: String,
	display_name: String,
	publish_signals: bool = true
) -> Error:
	if not _begin_async_catalog_mutation(&"rename"):
		return _last_error
	var mutation_token: int = _get_active_mutation_token()
	var account: LocalPlayerAccount = _find_account(account_id)
	var normalized_name: String = LocalPlayerAccount.normalize_display_name(
		display_name
	)
	if account == null or normalized_name.is_empty():
		_finish_async_catalog_mutation(ERR_INVALID_PARAMETER)
		return _last_error
	if (
		account.display_name.to_lower() != normalized_name.to_lower()
		and _has_display_name(normalized_name)
	):
		_finish_async_catalog_mutation(ERR_ALREADY_EXISTS)
		return _last_error
	var candidate: Dictionary = _make_catalog_payload()
	var candidate_accounts: Array = GFVariantData.get_option_array(
		candidate,
		&"accounts"
	)
	var account_index: int = _find_account_index(account_id)
	var candidate_account: Dictionary = GFVariantData.as_dictionary(
		candidate_accounts[account_index]
	)
	candidate_account[&"display_name"] = normalized_name
	candidate_accounts[account_index] = candidate_account
	candidate[&"accounts"] = candidate_accounts
	var save_error: Error = await _save_catalog_async(candidate)
	if not _owns_async_catalog_mutation(mutation_token):
		return ERR_UNAVAILABLE
	if save_error != OK:
		_finish_async_catalog_mutation(save_error)
		return save_error
	var apply_error: Error = _apply_catalog_payload(candidate)
	if apply_error != OK:
		_finish_async_catalog_mutation(apply_error)
		return apply_error
	_finish_async_catalog_mutation(OK)
	if publish_signals:
		account_catalog_changed.emit()
	return OK


## 异步激活账号并持久化最近使用时间。
## @param account_id: 要激活的本地账号稳定 ID。
## @param publish_signals: 成功后是否发布激活账号与目录变更信号。
func set_active_account_async(
	account_id: String,
	publish_signals: bool = true
) -> Error:
	if not _begin_async_catalog_mutation(&"activate"):
		return _last_error
	var mutation_token: int = _get_active_mutation_token()
	var account: LocalPlayerAccount = _find_account(account_id)
	if account == null:
		_finish_async_catalog_mutation(ERR_DOES_NOT_EXIST)
		return _last_error
	if _active_account_id == account_id:
		_finish_async_catalog_mutation(OK)
		return OK
	var candidate: Dictionary = _make_catalog_payload()
	var candidate_accounts: Array = GFVariantData.get_option_array(
		candidate,
		&"accounts"
	)
	var account_index: int = _find_account_index(account_id)
	var candidate_account: Dictionary = GFVariantData.as_dictionary(
		candidate_accounts[account_index]
	)
	candidate_account[&"last_active_at"] = maxi(
		_get_unix_timestamp(),
		account.created_at
	)
	candidate_accounts[account_index] = candidate_account
	candidate[&"active_account_id"] = account_id
	candidate[&"accounts"] = candidate_accounts
	var save_error: Error = await _save_catalog_async(candidate)
	if not _owns_async_catalog_mutation(mutation_token):
		return ERR_UNAVAILABLE
	if save_error != OK:
		_finish_async_catalog_mutation(save_error)
		return save_error
	var apply_error: Error = _apply_catalog_payload(candidate)
	if apply_error != OK:
		_finish_async_catalog_mutation(apply_error)
		return apply_error
	_finish_async_catalog_mutation(OK)
	if publish_signals:
		active_account_changed.emit(account_id)
		account_catalog_changed.emit()
	return OK


## 异步删除非当前账号；候选目录写入成功后才交换内存状态。
## @param account_id: 要删除的非当前账号稳定 ID。
## @param publish_signals: 成功后是否发布目录变更信号。
func delete_account_async(
	account_id: String,
	publish_signals: bool = true
) -> Error:
	if not _begin_async_catalog_mutation(&"delete_inactive"):
		return _last_error
	var mutation_token: int = _get_active_mutation_token()
	if (
		_accounts.size() <= 1
		or account_id.is_empty()
		or account_id == _active_account_id
	):
		_finish_async_catalog_mutation(ERR_BUSY)
		return _last_error
	var index: int = _find_account_index(account_id)
	if index < 0:
		_finish_async_catalog_mutation(ERR_DOES_NOT_EXIST)
		return _last_error
	var candidate: Dictionary = _make_catalog_payload()
	var candidate_accounts: Array = GFVariantData.get_option_array(
		candidate,
		&"accounts"
	)
	candidate_accounts.remove_at(index)
	candidate[&"accounts"] = candidate_accounts
	var save_error: Error = await _save_catalog_async(candidate)
	if not _owns_async_catalog_mutation(mutation_token):
		return ERR_UNAVAILABLE
	if save_error != OK:
		_finish_async_catalog_mutation(save_error)
		return save_error
	var apply_error: Error = _apply_catalog_payload(candidate)
	if apply_error != OK:
		_finish_async_catalog_mutation(apply_error)
		return apply_error
	_finish_async_catalog_mutation(OK)
	if publish_signals:
		account_catalog_changed.emit()
	return OK


## 异步删除当前账号并在同一次目录写入中激活回退账号。
## @param account_id: 要删除的当前账号稳定 ID。
## @param fallback_account_id: 删除成功后要激活的既有回退账号稳定 ID。
## @param publish_signals: 成功后是否发布激活账号与目录变更信号。
func delete_active_account_with_fallback_async(
	account_id: String,
	fallback_account_id: String,
	publish_signals: bool = true
) -> Error:
	if not _begin_async_catalog_mutation(&"delete_active_with_fallback"):
		return _last_error
	var mutation_token: int = _get_active_mutation_token()
	if (
		_accounts.size() <= 1
		or account_id.is_empty()
		or fallback_account_id.is_empty()
		or account_id == fallback_account_id
		or account_id != _active_account_id
	):
		_finish_async_catalog_mutation(ERR_INVALID_PARAMETER)
		return _last_error
	var removed_index: int = _find_account_index(account_id)
	var fallback: LocalPlayerAccount = _find_account(fallback_account_id)
	if removed_index < 0 or fallback == null:
		_finish_async_catalog_mutation(ERR_DOES_NOT_EXIST)
		return _last_error
	var candidate: Dictionary = _make_catalog_payload()
	var candidate_accounts: Array = GFVariantData.get_option_array(
		candidate,
		&"accounts"
	)
	candidate_accounts.remove_at(removed_index)
	var fallback_candidate_index: int = -1
	for index: int in range(candidate_accounts.size()):
		if (
			GFVariantData.get_option_string(
				GFVariantData.as_dictionary(candidate_accounts[index]),
				&"account_id"
			)
			== fallback_account_id
		):
			fallback_candidate_index = index
			break
	if fallback_candidate_index < 0:
		_finish_async_catalog_mutation(ERR_DOES_NOT_EXIST)
		return _last_error
	var candidate_fallback: Dictionary = GFVariantData.as_dictionary(
		candidate_accounts[fallback_candidate_index]
	)
	candidate_fallback[&"last_active_at"] = maxi(
		_get_unix_timestamp(),
		fallback.created_at
	)
	candidate_accounts[fallback_candidate_index] = candidate_fallback
	candidate[&"active_account_id"] = fallback_account_id
	candidate[&"accounts"] = candidate_accounts
	var save_error: Error = await _save_catalog_async(candidate)
	if not _owns_async_catalog_mutation(mutation_token):
		return ERR_UNAVAILABLE
	if save_error != OK:
		_finish_async_catalog_mutation(save_error)
		return save_error
	var apply_error: Error = _apply_catalog_payload(candidate)
	if apply_error != OK:
		_finish_async_catalog_mutation(apply_error)
		return apply_error
	_finish_async_catalog_mutation(OK)
	if publish_signals:
		active_account_changed.emit(fallback_account_id)
		account_catalog_changed.emit()
	return OK


## 返回账号独立 Save Profile 的存储相对路径。
## @param account_id: 用于构造文件名的有效 UUID v7 账号 ID。
static func make_profile_file_name(account_id: String) -> String:
	if not GFUuid.is_valid(account_id, 7):
		return ""
	return "%s/%s%s" % [PROFILE_DIRECTORY, account_id, PROFILE_EXTENSION]


# --- 私有/辅助方法 ---

func _load_catalog() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var read_result: GFStorageReadResult = _storage.load_data(CATALOG_FILE_NAME)
	if not read_result.ok:
		if read_result.error_code == ERR_FILE_NOT_FOUND:
			return _create_default_catalog()
		if ProjectStorageRecoveryPolicy.should_reset_failed_read(read_result):
			var reset_error: Error = ProjectStorageRecoveryPolicy.reset_failed_file(
				_storage,
				CATALOG_FILE_NAME,
				read_result
			)
			return _create_default_catalog() if reset_error == OK else reset_error
		return read_result.error_code
	return _apply_catalog_payload(read_result.payload)


func _apply_catalog_payload(payload: Dictionary) -> Error:
	if not (
		payload.size() == 3
		and GFVariantData.get_option_value(payload, &"schema_version") is int
		and GFVariantData.get_option_value(payload, &"active_account_id") is String
		and GFVariantData.get_option_value(payload, &"accounts") is Array
		and GFVariantData.get_option_int(payload, &"schema_version", 0)
		== CATALOG_SCHEMA_VERSION
	):
		return ERR_INVALID_DATA

	var account_values: Array = GFVariantData.get_option_array(
		payload,
		&"accounts"
	)
	if account_values.is_empty() or account_values.size() > MAX_ACCOUNTS:
		return ERR_INVALID_DATA
	var next_accounts: Array[LocalPlayerAccount] = []
	var seen_ids: Dictionary = {}
	var seen_names: Dictionary = {}
	for account_value: Variant in account_values:
		if not account_value is Dictionary:
			return ERR_INVALID_DATA
		var account: LocalPlayerAccount = LocalPlayerAccount.from_dict(
			GFVariantData.as_dictionary(account_value)
		)
		if account == null:
			return ERR_INVALID_DATA
		var normalized_name_key: String = account.display_name.to_lower()
		if seen_ids.has(account.account_id) or seen_names.has(normalized_name_key):
			return ERR_INVALID_DATA
		seen_ids[account.account_id] = true
		seen_names[normalized_name_key] = true
		next_accounts.append(account)

	var next_active_id: String = GFVariantData.get_option_string(
		payload,
		&"active_account_id"
	)
	if not seen_ids.has(next_active_id):
		return ERR_INVALID_DATA
	_accounts = next_accounts
	_active_account_id = next_active_id
	_sort_accounts()
	return OK


func _create_default_catalog() -> Error:
	var timestamp: int = _get_unix_timestamp()
	var translated_name: String = TranslationServer.translate(
		&"PLAYER_DEFAULT_NAME"
	)
	if translated_name == "PLAYER_DEFAULT_NAME":
		translated_name = "Player 1"
	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		translated_name,
		timestamp
	)
	if account == null:
		return ERR_INVALID_DATA
	_accounts.clear()
	_accounts.append(account)
	_active_account_id = account.account_id
	return _save_catalog()


func _save_catalog() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var payload: Dictionary = _make_catalog_payload()
	if payload.is_empty():
		return ERR_INVALID_DATA
	return _storage.save_data(CATALOG_FILE_NAME, payload)


func _save_catalog_async(payload: Dictionary) -> Error:
	if not _is_configured():
		_last_async_storage_result = {
			&"ok": false,
			&"error_code": int(ERR_UNCONFIGURED),
		}
		return ERR_UNCONFIGURED
	if payload.is_empty():
		_last_async_storage_result = {
			&"ok": false,
			&"error_code": int(ERR_INVALID_DATA),
		}
		return ERR_INVALID_DATA
	var operation: GFStorageAsyncOperation = (
		_storage.save_data_request_async(CATALOG_FILE_NAME, payload)
	)
	if operation == null:
		_last_async_storage_result = {
			&"ok": false,
			&"status": "failed",
			&"error_code": int(ERR_CANT_CREATE),
			&"error": "GFStorageUtility returned no async operation.",
		}
		return ERR_CANT_CREATE
	_track_storage_operation(operation)
	_pending_storage_operation = operation
	_pending_storage_deadline_msec = (
		_clock.get_tick_msec() + _CATALOG_IO_TIMEOUT_MSEC
	)
	var result: GFStorageAsyncResult = operation.get_result()
	while (
		result == null
		and not _disposed
		and _clock.get_tick_msec() < _pending_storage_deadline_msec
	):
		await catalog_storage_poll
		result = operation.get_result()
	if _disposed:
		return ERR_UNAVAILABLE
	_pending_storage_operation = null
	_pending_storage_deadline_msec = 0
	if result == null:
		_detached_storage_operations[operation.get_request_id()] = {
			&"operation": operation,
			&"payload": payload.duplicate(true),
			&"previous_active_account_id": _active_account_id,
		}
		_last_async_storage_result = {
			&"ok": false,
			&"status": "outcome_unknown",
			&"error_code": int(ERR_TIMEOUT),
			&"request_id": operation.get_request_id(),
			&"file_name": operation.get_file_name(),
		}
		return ERR_TIMEOUT
	_untrack_storage_operation(operation)
	_last_async_storage_result = (
		result.to_dict()
		if result != null
		else {
			&"ok": false,
			&"error_code": int(ERR_CANT_CREATE),
		}
	)
	_last_async_storage_result[&"status"] = (
		"succeeded" if result != null and result.is_successful() else "failed"
	)
	return result.get_error_code() if result != null else ERR_CANT_CREATE


func _make_catalog_payload() -> Dictionary:
	var account_data: Array[Dictionary] = []
	for account: LocalPlayerAccount in _accounts:
		if account == null or not account.is_valid():
			return {}
		account_data.append(account.to_dict())
	return {
		&"schema_version": CATALOG_SCHEMA_VERSION,
		&"active_account_id": _active_account_id,
		&"accounts": account_data,
	}


func _begin_async_catalog_mutation(action: StringName) -> bool:
	if _disposed or not _is_configured():
		_last_error = ERR_UNCONFIGURED
		return false
	if not _detached_storage_operations.is_empty():
		_last_error = ERR_BUSY
		_last_async_storage_result = {
			&"ok": false,
			&"status": "outcome_unknown",
			&"error_code": int(ERR_BUSY),
			&"detached_request_count": (
				_detached_storage_operations.size()
			),
		}
		return false
	var lease_result: Dictionary = _mutation_gate.try_request_lease(
		_CATALOG_MUTATION_GATE_KEY,
		{
			&"metadata": {
				&"component": &"local_account_catalog",
				&"action": action,
			},
			&"max_concurrency": 1,
		}
	)
	var lease_value: Variant = GFVariantData.get_option_value(
		lease_result,
		&"lease"
	)
	if not lease_value is GFAsyncGateLease:
		_last_error = ERR_BUSY
		return false
	_active_mutation_lease = lease_value
	_begin_catalog_diagnostic_operation(action)
	_last_async_storage_result.clear()
	_last_error = OK
	return true


func _finish_async_catalog_mutation(error_code: Error) -> void:
	if _disposed:
		return
	_last_error = error_code
	_finish_catalog_diagnostic_operation(error_code)
	if _active_mutation_lease != null:
		var _released: bool = _mutation_gate.release_lease(
			_active_mutation_lease,
			&"catalog_mutation_finished"
		)
	_active_mutation_lease = null


func _owns_async_catalog_mutation(mutation_token: int) -> bool:
	return (
		not _disposed
		and _active_mutation_lease != null
		and _active_mutation_lease.is_active()
		and mutation_token > 0
		and _active_mutation_lease.get_lease_id() == mutation_token
	)


func _get_active_mutation_token() -> int:
	return (
		_active_mutation_lease.get_lease_id()
		if _active_mutation_lease != null
		else 0
	)


func _begin_catalog_diagnostic_operation(action: StringName) -> void:
	_finish_catalog_diagnostic_operation(ERR_BUSY)
	if not is_instance_valid(_operation_diagnostics):
		return
	_catalog_diagnostic_operation_id = _operation_diagnostics.begin_operation(
		&"game.account_catalog_mutation",
		{
			&"component": &"local_account_catalog",
			&"label": "Mutate local account catalog",
			&"metadata": {&"action": action},
		}
	)


func _finish_catalog_diagnostic_operation(error_code: Error) -> void:
	if (
		_catalog_diagnostic_operation_id == &""
		or not is_instance_valid(_operation_diagnostics)
	):
		_catalog_diagnostic_operation_id = &""
		return
	var _record: Dictionary = _operation_diagnostics.finish_operation(
		_catalog_diagnostic_operation_id,
		error_code == OK,
		{&"metadata": {&"error_code": int(error_code)}}
	)
	_catalog_diagnostic_operation_id = &""


func _poll_catalog_storage_operations() -> void:
	if _disposed:
		return
	if _pending_storage_operation != null:
		if (
			_pending_storage_operation.is_completed()
			or (
				is_instance_valid(_clock)
				and _clock.get_tick_msec()
				>= _pending_storage_deadline_msec
			)
		):
			catalog_storage_poll.emit()
	for request_id_value: Variant in (
		_detached_storage_operations.keys()
	):
		var request_id: int = GFVariantData.to_int(request_id_value)
		var entry: Dictionary = GFVariantData.get_option_dictionary(
			_detached_storage_operations,
			request_id
		)
		var operation_value: Variant = GFVariantData.get_option_value(
			entry,
			&"operation"
		)
		if not (operation_value is GFStorageAsyncOperation):
			var _invalid_erased: bool = (
				_detached_storage_operations.erase(request_id)
			)
			continue
		var operation: GFStorageAsyncOperation = operation_value
		if not operation.is_completed():
			continue
		var result: GFStorageAsyncResult = operation.get_result()
		var previous_active_account_id: String = (
			GFVariantData.get_option_string(
				entry,
				&"previous_active_account_id",
				_active_account_id
			)
		)
		var apply_error: Error = ERR_CANT_CREATE
		if result != null and result.is_successful():
			apply_error = _apply_catalog_payload(
				GFVariantData.get_option_dictionary(
					entry,
					&"payload"
				)
			)
			if apply_error == OK:
				# 迟到成功先交换目录权威状态，再把类型化终态交给
				# LocalAccountSystem 协调 Profile；目录自身只发布一次。
				if previous_active_account_id != _active_account_id:
					active_account_changed.emit(_active_account_id)
				account_catalog_changed.emit()
		_last_async_storage_result = (
			result.to_dict()
			if result != null
			else {
				&"ok": false,
				&"error_code": int(ERR_CANT_CREATE),
			}
		)
		_last_async_storage_result[&"status"] = "late_settled"
		_last_async_storage_result[&"late_apply_error"] = int(apply_error)
		_untrack_storage_operation(operation)
		var _erased: bool = (
			_detached_storage_operations.erase(request_id)
		)
		catalog_storage_late_settled.emit(
			result.duplicate_result() if result != null else null,
			apply_error,
			previous_active_account_id,
			_active_account_id
		)


func _find_account(account_id: String) -> LocalPlayerAccount:
	var index: int = _find_account_index(account_id)
	return _accounts[index] if index >= 0 else null


func _find_account_index(account_id: String) -> int:
	for index: int in range(_accounts.size()):
		if _accounts[index].account_id == account_id:
			return index
	return -1


func _has_display_name(display_name: String) -> bool:
	var normalized_key: String = display_name.to_lower()
	for account: LocalPlayerAccount in _accounts:
		if account.display_name.to_lower() == normalized_key:
			return true
	return false


func _sort_accounts() -> void:
	_accounts.sort_custom(func(left: LocalPlayerAccount, right: LocalPlayerAccount) -> bool:
		if left.last_active_at != right.last_active_at:
			return left.last_active_at > right.last_active_at
		return left.account_id < right.account_id
	)


func _get_unix_timestamp() -> int:
	return maxi(_clock.get_unix_timestamp(), 1) if is_instance_valid(_clock) else 1


func _track_storage_operation(
	operation: GFStorageAsyncOperation
) -> void:
	if operation == null or operation.is_completed():
		return
	var tracker: GFAsyncTrackerUtility = _resolve_optional_async_tracker()
	if tracker == null:
		return
	var handle_instance_id: int = operation.get_instance_id()
	if _async_tracking_ids.has(handle_instance_id):
		return
	var tracking_id: int = tracker.track_handle(
		operation,
		&"local_account.catalog_storage",
		{
			&"owner": "LocalAccountCatalogUtility",
			&"request_id": operation.get_request_id(),
			&"operation": String(operation.get_operation()),
			&"file_name": operation.get_file_name(),
		}
	)
	if tracking_id > 0:
		_async_tracking_ids[handle_instance_id] = tracking_id


func _untrack_storage_operation(
	operation: GFStorageAsyncOperation
) -> void:
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
	# 只查看当前架构的可选诊断服务，缺失时不触发严格依赖告警。
	var utility_value: Object = architecture.get_local_utility(
		GFAsyncTrackerUtility
	)
	if utility_value is GFAsyncTrackerUtility:
		_async_tracker = utility_value
		return _async_tracker
	return null


func _is_configured() -> bool:
	return (
		not _disposed
		and is_instance_valid(_storage)
		and is_instance_valid(_clock)
	)


func _resolve_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _resolve_operation_diagnostics_utility() -> GFOperationDiagnosticsUtility:
	var utility_value: Object = get_utility(GFOperationDiagnosticsUtility)
	if utility_value is GFOperationDiagnosticsUtility:
		var diagnostics: GFOperationDiagnosticsUtility = utility_value
		return diagnostics
	return null
