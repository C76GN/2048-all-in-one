## 通过 GFStorageUtility public async delete 并发回收固定 chunk logical families。
##
## 每个 identity 都提交一次精确 delete。caller outcome-unknown 只更新诊断；
## runner 始终等待同一 Operation 的 physical completed 后才释放整个 cleanup。
class_name ChunkProfileCleanupRunner
extends RefCounted


# --- 常量 ---

# Cleanup 自身始终等待每个 delete 的物理终态；caller deadline 不能作为
# 内部物理回收的执行预算。cooperative Storage 每帧只接纳一个 worker，若从
# 入队时开始计 5 秒，合法 family 队尾会在慢帧设备上于接纳前被物理取消。
const _DELETE_CALLER_TIMEOUT_MSEC: int = 0


# --- 私有变量 ---

var _storage: GFStorageUtility = null
var _request: ChunkProfileCleanupRequest = null
var _operation: ChunkProfileCleanupOperation = null
var _delete_operations: Dictionary = {}
var _identity_by_handle: Dictionary = {}
var _physical_settled_handles: Dictionary = {}
var _caller_unknown_handles: Dictionary = {}
var _physical_poll_handles: Dictionary = {}
var _caller_poll_handles: Dictionary = {}
var _started: bool = false
var _submitting: bool = false
var _deleted_count: int = 0
var _not_found_count: int = 0
var _failed_count: int = 0
var _skipped_count: int = 0
var _first_error_code: Error = OK
var _first_failed_bank: StringName = ChunkManifest.BANK_NONE
var _first_failed_chunk_index: int = -1
var _first_delete_failure_kind: GFStorageDeleteResult.FailureKind = (
	GFStorageDeleteResult.FailureKind.NONE
)


# --- 生命周期方法 ---

func _init(storage: GFStorageUtility = null) -> void:
	_storage = storage


# --- 公共方法 ---

## 启动一次 bounded cleanup；物理 delete 在 deferred 边界提交。
## @param request: 已严格派生并冻结的有界回收请求。
## @param operation: 接收取消意图、进度和唯一物理终态的 Operation。
func start(
	request: ChunkProfileCleanupRequest,
	operation: ChunkProfileCleanupOperation
) -> bool:
	if (
		_storage == null
		or request == null
		or not request.is_valid()
		or operation == null
		or operation.is_completed()
		or _request != null
		or _operation != null
	):
		return false
	_request = request
	_operation = operation
	if not operation.attach_runner_for_persistence(self):
		_request = null
		_operation = null
		return false
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = operation.cancellation_requested.connect(
		_on_cancellation_requested,
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		_complete_invalid(connect_error, "Cleanup cancellation observer failed.")
		return false
	var _deferred: Variant = call_deferred(&"_begin")
	return true


# --- 私有/辅助方法 ---

func _begin() -> void:
	if _operation == null or _request == null or _started:
		return
	_started = true
	if _operation.is_cancel_requested():
		_skipped_count = _request.get_identity_count()
		_complete()
		return
	var _phase_changed: bool = _operation.set_phase_for_persistence(
		ChunkProfileCleanupOperation.PHASE_DELETING
	)
	_submitting = true
	for index: int in range(_request.get_identity_count()):
		var identity: ChunkProfileIdentity = _request.get_identity(index)
		if identity == null:
			_record_synthetic_failure(null, ERR_INVALID_DATA)
			continue
		var options: GFStorageAsyncRequestOptions = (
			GFStorageAsyncRequestOptions.create(
				self,
				null,
				_DELETE_CALLER_TIMEOUT_MSEC
			)
		)
		var delete_operation: GFStorageAsyncOperation = (
			_storage.delete_file_request_async(
				identity.get_file_name(),
				options
			)
		)
		if delete_operation == null:
			_record_synthetic_failure(identity, ERR_CANT_CREATE)
			continue
		var handle_id: int = delete_operation.get_instance_id()
		_delete_operations[handle_id] = delete_operation
		_identity_by_handle[handle_id] = identity
		_observe_delete_operation(delete_operation, handle_id)
	_submitting = false
	_update_progress()
	_try_complete()


func _observe_delete_operation(
	delete_operation: GFStorageAsyncOperation,
	handle_id: int
) -> void:
	if not delete_operation.is_completed():
		var physical_error: Error = _connect_delete_physical_completed(
			delete_operation,
			handle_id
		)
		if physical_error != OK:
			# 连接失败时仍保留原句柄，并以逐帧 polling 收敛真实物理终态。
			# 禁止递归 call_deferred：SceneTree 会在同一 idle drain 持续处理
			# 新增 deferred call，pending handle 会因此形成单帧热循环。
			if not _physical_poll_handles.has(handle_id):
				_physical_poll_handles[handle_id] = true
				var _poll_deferred: Variant = call_deferred(
					&"_poll_delete_operation",
					handle_id
				)
	if not delete_operation.is_caller_completed():
		var caller_error: Error = _connect_delete_caller_completed(
			delete_operation,
			handle_id
		)
		if caller_error != OK:
			if not _caller_poll_handles.has(handle_id):
				_caller_poll_handles[handle_id] = true
				var _caller_poll_deferred: Variant = call_deferred(
					&"_poll_delete_caller",
					handle_id
				)
	_process_caller_terminal(delete_operation, handle_id)
	_process_physical_terminal(delete_operation, handle_id)


func _connect_delete_physical_completed(
	delete_operation: GFStorageAsyncOperation,
	handle_id: int
) -> Error:
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = delete_operation.completed.connect(
		Callable(self, &"_on_delete_physical_completed").bind(handle_id),
		CONNECT_ONE_SHOT
	)
	return connect_error


func _connect_delete_caller_completed(
	delete_operation: GFStorageAsyncOperation,
	handle_id: int
) -> Error:
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = delete_operation.caller_completed.connect(
		Callable(self, &"_on_delete_caller_completed").bind(handle_id),
		CONNECT_ONE_SHOT
	)
	return connect_error


func _poll_delete_operation(handle_id: int) -> void:
	while _operation != null and not _operation.is_completed():
		var delete_operation: GFStorageAsyncOperation = (
			_get_delete_operation(handle_id)
		)
		if delete_operation == null:
			break
		if delete_operation.is_completed():
			_process_physical_terminal(delete_operation, handle_id)
			break
		var main_loop: MainLoop = Engine.get_main_loop()
		if not main_loop is SceneTree:
			break
		var scene_tree: SceneTree = main_loop
		await scene_tree.process_frame
	var _poll_erased: bool = _physical_poll_handles.erase(handle_id)


func _poll_delete_caller(handle_id: int) -> void:
	while _operation != null and not _operation.is_completed():
		var delete_operation: GFStorageAsyncOperation = (
			_get_delete_operation(handle_id)
		)
		if delete_operation == null:
			break
		if delete_operation.is_caller_completed():
			_process_caller_terminal(delete_operation, handle_id)
			break
		var main_loop: MainLoop = Engine.get_main_loop()
		if not main_loop is SceneTree:
			break
		var scene_tree: SceneTree = main_loop
		await scene_tree.process_frame
	var _poll_erased: bool = _caller_poll_handles.erase(handle_id)


func _process_caller_terminal(
	delete_operation: GFStorageAsyncOperation,
	handle_id: int
) -> void:
	if (
		delete_operation == null
		or not delete_operation.is_caller_completed()
		or _caller_unknown_handles.has(handle_id)
	):
		return
	var _poll_erased: bool = _caller_poll_handles.erase(handle_id)
	var caller_result: GFStorageAsyncCallerResult = (
		delete_operation.get_caller_result()
	)
	if caller_result != null and caller_result.is_outcome_unknown():
		_caller_unknown_handles[handle_id] = true
		var _phase_changed: bool = _operation.set_phase_for_persistence(
			ChunkProfileCleanupOperation.PHASE_WAITING_FOR_PHYSICAL
		)
	_update_progress()


func _process_physical_terminal(
	delete_operation: GFStorageAsyncOperation,
	handle_id: int
) -> void:
	if (
		delete_operation == null
		or not delete_operation.is_completed()
		or _physical_settled_handles.has(handle_id)
	):
		return
	_physical_settled_handles[handle_id] = true
	var _poll_erased: bool = _physical_poll_handles.erase(handle_id)
	_process_caller_terminal(delete_operation, handle_id)
	var identity: ChunkProfileIdentity = _get_identity(handle_id)
	var physical_result: GFStorageAsyncResult = delete_operation.get_result()
	if physical_result != null and physical_result.is_cancelled():
		_skipped_count += 1
	elif physical_result != null and physical_result.is_successful():
		_deleted_count += 1
	else:
		var delete_result: GFStorageDeleteResult = (
			physical_result.get_delete_result()
			if physical_result != null
			else null
		)
		if (
			delete_result != null
			and delete_result.get_failure_kind()
			== GFStorageDeleteResult.FailureKind.NOT_FOUND
		):
			_not_found_count += 1
		else:
			_record_failure(identity, physical_result, delete_result)
	_update_progress()
	_try_complete()


func _record_failure(
	identity: ChunkProfileIdentity,
	physical_result: GFStorageAsyncResult,
	delete_result: GFStorageDeleteResult
) -> void:
	_failed_count += 1
	if _first_failed_chunk_index >= 0:
		return
	_first_error_code = (
		physical_result.get_error_code()
		if physical_result != null
		else FAILED
	)
	_first_failed_bank = (
		identity.get_bank()
		if identity != null
		else ChunkManifest.BANK_NONE
	)
	_first_failed_chunk_index = (
		identity.get_chunk_index() if identity != null else 0
	)
	_first_delete_failure_kind = (
		delete_result.get_failure_kind()
		if delete_result != null
		else GFStorageDeleteResult.FailureKind.IO_FAILED
	)


func _record_synthetic_failure(
	identity: ChunkProfileIdentity,
	error_code: Error
) -> void:
	_failed_count += 1
	if _first_failed_chunk_index >= 0:
		return
	_first_error_code = error_code
	_first_failed_bank = (
		identity.get_bank()
		if identity != null
		else ChunkManifest.BANK_NONE
	)
	_first_failed_chunk_index = (
		identity.get_chunk_index() if identity != null else 0
	)
	_first_delete_failure_kind = GFStorageDeleteResult.FailureKind.IO_FAILED


func _on_cancellation_requested(_reason: StringName) -> void:
	if _operation == null or _operation.is_completed():
		return
	if not _started:
		return
	for operation_value: Variant in _delete_operations.values():
		if not operation_value is GFStorageAsyncOperation:
			continue
		var delete_operation: GFStorageAsyncOperation = operation_value
		if delete_operation.is_caller_pending():
			var _cancelled: bool = delete_operation.cancel_observation(
				&"chunk_cleanup_cancelled"
			)
	_update_progress()
	_try_complete()


func _on_delete_caller_completed(
	_result: GFStorageAsyncCallerResult,
	handle_id: int
) -> void:
	var delete_operation: GFStorageAsyncOperation = _get_delete_operation(handle_id)
	_process_caller_terminal(delete_operation, handle_id)


func _on_delete_physical_completed(
	_result: GFStorageAsyncResult,
	handle_id: int
) -> void:
	var delete_operation: GFStorageAsyncOperation = _get_delete_operation(handle_id)
	_process_physical_terminal(delete_operation, handle_id)


func _get_delete_operation(handle_id: int) -> GFStorageAsyncOperation:
	var value: Variant = _delete_operations.get(handle_id)
	if value is GFStorageAsyncOperation:
		return value
	return null


func _get_identity(handle_id: int) -> ChunkProfileIdentity:
	var value: Variant = _identity_by_handle.get(handle_id)
	if value is ChunkProfileIdentity:
		return value
	return null


func _update_progress() -> void:
	if _operation == null or _request == null or _operation.is_completed():
		return
	var _updated: bool = _operation.update_progress_for_persistence({
		&"kind": _request.get_kind(),
		&"total_count": _request.get_identity_count(),
		&"physical_settled_count": _physical_settled_handles.size(),
		&"physical_pending_count": maxi(
			_delete_operations.size() - _physical_settled_handles.size(),
			0
		),
		&"deleted_count": _deleted_count,
		&"not_found_count": _not_found_count,
		&"failed_count": _failed_count,
		&"skipped_count": _skipped_count,
		&"caller_outcome_unknown_count": _caller_unknown_handles.size(),
		&"physical_poll_count": _physical_poll_handles.size(),
		&"caller_poll_count": _caller_poll_handles.size(),
	})


func _try_complete() -> void:
	if (
		_submitting
		or _operation == null
		or _request == null
		or _operation.is_completed()
	):
		return
	# Synthetic failures没有 GF handle；physical failure 已包含在 settled handles。
	var synthetic_failure_count: int = (
		_request.get_identity_count() - _delete_operations.size()
	)
	var accounted_count: int = (
		_physical_settled_handles.size() + synthetic_failure_count
	)
	if accounted_count < _request.get_identity_count():
		return
	_complete()


func _complete() -> void:
	if _operation == null or _request == null or _operation.is_completed():
		return
	var status: StringName = ChunkProfileCleanupResult.STATUS_CLEANED
	var error_code: Error = OK
	var error: String = ""
	if _operation.is_cancel_requested():
		status = ChunkProfileCleanupResult.STATUS_CANCELLED
		error_code = ERR_SKIP
		error = String(_operation.get_cancel_reason())
	elif _failed_count > 0 or _skipped_count > 0:
		status = ChunkProfileCleanupResult.STATUS_PARTIAL_FAILURE
		error_code = (
			_first_error_code
			if _first_error_code != OK
			else ERR_SKIP
		)
		error = (
			"One or more derived chunk families could not be deleted."
			if _failed_count > 0
			else "One or more chunk deletes ended before physical work."
		)
	var result: ChunkProfileCleanupResult = ChunkProfileCleanupResult.create(
		status,
		error_code,
		error,
		_request.get_identity_count(),
		_deleted_count,
		_not_found_count,
		_failed_count,
		_skipped_count,
		_caller_unknown_handles.size(),
		_first_failed_bank,
		_first_failed_chunk_index,
		_first_delete_failure_kind
	)
	var operation: ChunkProfileCleanupOperation = _operation
	_disconnect_signals()
	_request = null
	_operation = null
	_storage = null
	_delete_operations.clear()
	_identity_by_handle.clear()
	_physical_settled_handles.clear()
	_caller_unknown_handles.clear()
	_physical_poll_handles.clear()
	_caller_poll_handles.clear()
	var _completed: bool = operation.complete_for_persistence(result)


func _complete_invalid(error_code: Error, error: String) -> void:
	if _operation == null:
		return
	var operation: ChunkProfileCleanupOperation = _operation
	var total_count: int = (
		_request.get_identity_count() if _request != null else 0
	)
	_disconnect_signals()
	_request = null
	_operation = null
	_storage = null
	_delete_operations.clear()
	_identity_by_handle.clear()
	_physical_settled_handles.clear()
	_caller_unknown_handles.clear()
	_physical_poll_handles.clear()
	_caller_poll_handles.clear()
	var _completed: bool = operation.complete_for_persistence(
		ChunkProfileCleanupResult.create(
			ChunkProfileCleanupResult.STATUS_INVALID_REQUEST,
			error_code,
			error,
			total_count,
			0,
			0,
			0,
			total_count,
			0
		)
	)


func _disconnect_signals() -> void:
	if (
		_operation != null
		and _operation.cancellation_requested.is_connected(
			_on_cancellation_requested
		)
	):
		_operation.cancellation_requested.disconnect(_on_cancellation_requested)
	for handle_id_value: Variant in _delete_operations.keys():
		if not handle_id_value is int:
			continue
		var handle_id: int = handle_id_value
		var delete_operation: GFStorageAsyncOperation = _get_delete_operation(
			handle_id
		)
		if delete_operation == null:
			continue
		var physical_callable: Callable = Callable(
			self,
			&"_on_delete_physical_completed"
		).bind(handle_id)
		if delete_operation.completed.is_connected(physical_callable):
			delete_operation.completed.disconnect(physical_callable)
		var caller_callable: Callable = Callable(
			self,
			&"_on_delete_caller_completed"
		).bind(handle_id)
		if delete_operation.caller_completed.is_connected(caller_callable):
			delete_operation.caller_completed.disconnect(caller_callable)
