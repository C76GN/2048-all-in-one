## 编排大型 section 的小型 GF chunk Profiles 与主 Profile 可见性。
##
## Provider 只通过 opaque ChunkSaveLease 交付载荷。本 Utility 在
## Provider callback 外使用 GFSaveProfileUtility public API 注册、保存、
## 读取和注销严格派生的 chunk Profiles。
class_name ChunkProfileUtility
extends GFUtility


# --- 信号 ---

## Lease 进入 committed/superseded/failed/cancelled 且已绑定主 operation 也获得
## 可判定物理终态后发出一次。
##
## 首次 outcome_unknown 不是最终结算；只在迟到对账后发出。
signal save_lease_settled(lease_id: StringName)

## 派生 chunk family cleanup 获得完整物理终态时发出一次。
signal cleanup_operation_settled(operation_id: StringName)


# --- 私有变量 ---

var _profile_utility: GFSaveProfileUtility = null
var _storage: GFStorageUtility = null
var _executor: GfChunkProfileExecutor = null
var _accepting: bool = false
var _disposed: bool = false
var _next_lease_serial: int = 1
var _next_cleanup_serial: int = 1
var _leases: Dictionary = {}
var _lease_scopes: Dictionary = {}
var _lease_order: Array[StringName] = []
var _scope_stage_owners: Dictionary = {}
## 每个已观测 scope 的进程内提交 basis。
##
## 该状态不从磁盘缓存 active Manifest；只由 exact COMMITTED lease 单调推进，
## 用于把已在队列中冻结旧 Manifest 的 WAITING/READY lease 重基线。
## basis 保留到 Utility dispose，以覆盖 fence 期间业务 revision 超越迟到
## Manifest、结算回调拒绝更新 Provider，之后才新建 lease 的窗口。
## 每个 scope 只保留 bank+epoch，不保留 payload 或 alias 链。
var _scope_basis_states: Dictionary = {}
var _outcome_unknown_scopes: Dictionary = {}
var _stage_unknown_profiles: Dictionary = {}
var _settled_notifications: Dictionary = {}
var _active_stage: ActiveStage = null
var _registered_profiles: Dictionary = {}
var _pending_unregister: Dictionary = {}
var _active_materializations: int = 0
## 每个可信 main Profile/section scope 的在途物化计数。
##
## cleanup 先取得 scope fence，再等当前计数归零，阻止 exact commit 回收
## 仍被旧 Manifest reader 使用的 active bank。
var _materialization_scope_counts: Dictionary = {}
var _cleanup_operations: Dictionary = {}
var _cleanup_scope_ids: Dictionary = {}
var _cleanup_operation_scopes: Dictionary = {}
## 已取得 cleanup scope fence、但仍等待同 scope reader 归零的固定请求。
var _deferred_cleanup_requests: Dictionary = {}
## exact commit 因同 scope sibling lease 尚未结算而暂缓的最新安全回收范围。
##
## 每个 scope 只保留最新 exact commit：后续 exact commit 会按新 active bank
## 完整替换旧意图；pre-stage/known failure 的最后一个 sibling 则消费该意图。
var _pending_exact_cleanup_requests: Dictionary = {}
var _cleanup_notifications: Dictionary = {}
var _last_cleanup_result: Dictionary = {}
var _quiesce_completion: GFAsyncCompletion = null


# --- GF 生命周期方法 ---

func _init() -> void:
	tick_enabled = true
	ignore_pause = true
	ignore_time_scale = true


func get_required_utilities() -> Array[Script]:
	return [GFSaveProfileUtility, GFStorageUtility]


func ready() -> void:
	var utility_value: Variant = get_utility(GFSaveProfileUtility)
	if utility_value is GFSaveProfileUtility:
		_profile_utility = utility_value
		_executor = GfChunkProfileExecutor.new(_profile_utility)
	var storage_value: Variant = get_utility(GFStorageUtility)
	if storage_value is GFStorageUtility:
		_storage = storage_value


## 激活 chunk Profile 编排能力。
## @param _scope: GF 生命周期传入的激活作用域；本 Utility 不持有它。
func begin_activation(_scope: GFAsyncScope) -> GFAsyncCompletion:
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	if (
		_disposed
		or _quiesce_completion != null
		or _profile_utility == null
		or _storage == null
		or _executor == null
	):
		var _failed: bool = completion.fail(
			"GF save/storage utilities are unavailable for chunk Profiles."
		)
		return completion
	_accepting = true
	var _succeeded: bool = completion.succeed()
	return completion


## 推进 staging、outcome-unknown 对账与 quiesce 收敛。
## @param _delta: GF 生命周期传入的帧间隔；本 Utility 不依赖时间缩放。
func tick(_delta: float = 0.0) -> void:
	if _disposed or _profile_utility == null:
		return
	_reconcile_stage_outcome_fences()
	_reconcile_main_outcome_fences()
	_poll_active_stage()
	_drain_pending_unregisters()
	_start_deferred_cleanup_requests()
	_drain_cleanup_terminals()
	if _accepting:
		_start_next_ready_stage()
	_try_complete_quiesce()


## 停止接纳新工作并等待已接纳操作收敛。
## @param scope: 可取消 quiesce completion 的异步作用域。
func begin_quiesce(scope: GFAsyncScope) -> GFAsyncCompletion:
	_accepting = false
	if _quiesce_completion != null:
		return _quiesce_completion
	_quiesce_completion = GFAsyncCompletion.new()
	if scope != null:
		var _bound: bool = _quiesce_completion.bind_cancel_token(scope)
	_cancel_not_started_leases_for_quiesce()
	if _active_stage != null and _active_stage.operation != null:
		var _cancel_requested: bool = (
			_active_stage.operation.request_cancel(&"chunk_utility_quiescing")
		)
	for operation_value: Variant in _cleanup_operations.values():
		if operation_value is ChunkProfileCleanupOperation:
			var cleanup: ChunkProfileCleanupOperation = operation_value
			if cleanup.is_pending():
				var _cleanup_cancelled: bool = cleanup.request_cancel(
					&"chunk_utility_quiescing"
				)
	_drain_pending_unregisters()
	_try_complete_quiesce()
	return _quiesce_completion


## dispose 不发起任何 Profile 或 Storage I/O。
func dispose() -> void:
	_accepting = false
	_disposed = true
	if _quiesce_completion != null and _quiesce_completion.is_pending():
		var _failed: bool = _quiesce_completion.fail(
			"Chunk Profile Utility disposed before quiesce converged."
		)
	_active_stage = null
	_registered_profiles.clear()
	_pending_unregister.clear()
	_scope_basis_states.clear()
	_materialization_scope_counts.clear()
	_cleanup_operations.clear()
	_cleanup_scope_ids.clear()
	_cleanup_operation_scopes.clear()
	_deferred_cleanup_requests.clear()
	_pending_exact_cleanup_requests.clear()
	_cleanup_notifications.clear()
	_last_cleanup_result.clear()
	_executor = null


func release_dependencies() -> void:
	_profile_utility = null
	_storage = null
	_executor = null
	super.release_dependencies()


# --- 公共方法 ---

## 常量时间创建一个不读取业务 payload 的 save lease。
##
## 同一主 Profile 身份与 section 存在未对账 outcome_unknown
## fence 时拒绝新 lease。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param section_id: manifest-backed section 的稳定 ID。
## @param section_schema_version: 候选 Manifest 绑定的 section schema 版本。
## @param producer_revision: Provider 在请求时冻结的业务 revision。
func create_save_lease(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName,
	section_schema_version: int,
	producer_revision: int
) -> ChunkSaveLease:
	if not _accepting or _disposed or _profile_utility == null:
		return null
	var profile_prefix: String = ChunkProfileRuntimeFactory.make_profile_prefix(
		main_profile_id,
		main_file_name,
		section_id
	)
	if profile_prefix.is_empty():
		return null
	var scope_key: String = profile_prefix
	if (
		_outcome_unknown_scopes.has(scope_key)
		or _cleanup_scope_ids.has(scope_key)
	):
		return null
	var lease_id: StringName = StringName("chunk_save.%d.%d" % [
		get_instance_id(),
		_next_lease_serial,
	])
	_next_lease_serial += 1
	var lease: ChunkSaveLease = ChunkSaveLease.create(
		lease_id,
		main_profile_id,
		main_file_name,
		section_id,
		section_schema_version,
		producer_revision,
		profile_prefix
	)
	if lease == null:
		return null
	var basis: ScopeBasis = _get_scope_basis(scope_key)
	if (
		basis != null
		and not lease.rebase_scope_basis_for_utility(
			basis.active_bank,
			basis.epoch
		)
	):
		return null
	_leases[lease_id] = lease
	_lease_scopes[lease_id] = scope_key
	_lease_order.append(lease_id)
	return lease


## 获取不暴露 payload 的 lease 句柄。
## @param lease_id: create_save_lease() 返回对象的稳定 lease ID。
func get_save_lease(lease_id: StringName) -> ChunkSaveLease:
	var lease_value: Variant = _leases.get(lease_id)
	if lease_value is ChunkSaveLease:
		return lease_value
	return null


## 获取仍受 Utility scope fence 持有的 cleanup operation。
## @param operation_id: cleanup_derived_family_async() 返回对象的稳定操作 ID。
func get_cleanup_operation(
	operation_id: StringName
) -> ChunkProfileCleanupOperation:
	var operation_value: Variant = _cleanup_operations.get(operation_id)
	if operation_value is ChunkProfileCleanupOperation:
		return operation_value
	return null


## 显式回收一次主 Profile/section 的全部 A/B 派生 chunk families。
##
## 本入口供主 Profile delete/reset owner 在其自身事务边界显式调用；Utility 不会
## 因主 Profile 切换、卸载或普通 quiesce 擅自触发。请求会先取得 cleanup scope
## fence，再等待既有 lease、outcome-unknown 与 materialization 全部收敛；只有
## 已有同 scope cleanup 时返回 typed busy 终态。
## @param main_profile_id: 待回收派生 family 的可信主 Profile ID。
## @param main_file_name: 可信主 Profile logical 文件名。
## @param section_id: 待回收派生 family 的稳定 Feature section ID。
func cleanup_derived_family_async(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName
) -> ChunkProfileCleanupOperation:
	var request: ChunkProfileCleanupRequest = (
		ChunkProfileCleanupRequest.entire_family(
			main_profile_id,
			main_file_name,
			section_id
		)
	)
	if (
		not _accepting
		or _disposed
		or _storage == null
		or request == null
		or not request.is_valid()
	):
		return _make_terminal_cleanup_operation(
			ChunkProfileCleanupResult.STATUS_INVALID_REQUEST,
			ERR_INVALID_PARAMETER,
			"Derived chunk family cleanup request is invalid."
		)
	var scope_key: String = ChunkProfileRuntimeFactory.make_profile_prefix(
		main_profile_id,
		main_file_name,
		section_id
	)
	if (
		scope_key.is_empty()
		or _cleanup_scope_ids.has(scope_key)
	):
		return _make_terminal_cleanup_operation(
			ChunkProfileCleanupResult.STATUS_BUSY,
			ERR_BUSY,
			"Derived chunk family is still owned by an active save or cleanup."
		)
	return _begin_cleanup_request(request, scope_key)


## 在 staging 接纳前以已知错误终结 lease 并释放 Utility 索引。
##
## 已在执行的 staging 必须先通过其 operation 收敛，本方法不伪造
## 已接纳 GF Profile 写入的取消终态。
## @param lease_id: 待终结 lease 的稳定 ID。
## @param error_code: 已知失败的非 OK Error 码。
## @param error: 不含业务载荷的稳定错误摘要。
## @return 首次合法终结时返回原 lease，否则返回 null。
func fail_save_lease(
	lease_id: StringName,
	error_code: Error,
	error: String
) -> ChunkSaveLease:
	var lease: ChunkSaveLease = get_save_lease(lease_id)
	if (
		lease == null
		or (
			_active_stage != null
			and _active_stage.lease_id == lease_id
		)
		or not lease.fail_for_utility(error_code, error)
	):
		return null
	_finish_known_lease(lease)
	return lease


## 以绑定主 GF save operation 的真实结果收敛 lease。
##
## @param lease_id: 待收敛 lease 的稳定 ID。
## @param result: 已完成且与 lease 绑定 operation 对应的主 Profile 结果。
## @return 成功绑定结果时返回原 lease，否则返回 null。
func settle_main_result(
	lease_id: StringName,
	result: GFSaveProfileResult
) -> ChunkSaveLease:
	var lease: ChunkSaveLease = get_save_lease(lease_id)
	if lease == null or not lease.settle_main_result_for_utility(result):
		return null
	var scope_key: String = _get_lease_scope(lease_id)
	if lease.is_outcome_unknown():
		_outcome_unknown_scopes[scope_key] = lease_id
	elif _is_known_final_status(lease.get_status()):
		_finish_known_lease(lease)
	return lease


## 查询可信主身份/section 的 outcome-unknown 或 cleanup physical fence。
##
## SaveGraph 用此只读边界停放 dirty save intent；cleanup caller outcome-unknown
## 也会一直保持 fence 到迟到物理终态。该边界不暴露 lease、路径或 payload。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param section_id: 待查询的 manifest-backed section ID。
func is_save_scope_fenced(
	main_profile_id: StringName,
	main_file_name: String,
	section_id: StringName
) -> bool:
	var scope_key: String = ChunkProfileRuntimeFactory.make_profile_prefix(
		main_profile_id,
		main_file_name,
		section_id
	)
	return (
		not scope_key.is_empty()
		and (
			_outcome_unknown_scopes.has(scope_key)
			or _cleanup_scope_ids.has(scope_key)
		)
	)


## 按 Manifest 顺序从严格派生的 chunk Profiles 预物化 bytes。
##
## 失败返回永远不包含已读取的部分 payload。已接纳调用在
## quiesce 期间继续收敛，但 quiesce 后不再接纳新调用。
## @param main_profile_id: 已验证的主 GF Profile ID。
## @param main_file_name: 已验证的主 Profile 逻辑文件名。
## @param manifest: 已由主 Profile 验证的可见 ChunkManifest。
func materialize_chunks_async(
	main_profile_id: StringName,
	main_file_name: String,
	manifest: ChunkManifest
) -> Dictionary:
	if (
		not _accepting
		or _disposed
		or _profile_utility == null
		or manifest == null
		or not manifest.is_valid()
	):
		return _make_materialization_result(
			false,
			ERR_UNAVAILABLE,
			"Chunk materialization is unavailable."
		)
	var section_id: StringName = manifest.get_section_id()
	var scope_key: String = ChunkProfileRuntimeFactory.make_profile_prefix(
		main_profile_id,
		main_file_name,
		section_id
	)
	if scope_key.is_empty():
		return _make_materialization_result(
			false,
			ERR_INVALID_PARAMETER,
			"Trusted main Profile identity is invalid."
		)
	if _cleanup_scope_ids.has(scope_key):
		return _make_materialization_result(
			false,
			ERR_BUSY,
			"Chunk family cleanup has not reached physical terminal."
		)

	_active_materializations += 1
	_increment_materialization_scope(scope_key)
	var chunks: Array[PackedByteArray] = []
	for chunk_index: int in range(manifest.get_chunk_count()):
		var profile: GFSaveProfile = ChunkProfileRuntimeFactory.make_profile(
			main_profile_id,
			main_file_name,
			section_id,
			manifest.get_bank(),
			chunk_index
		)
		if profile == null:
			return _finish_materialization_failure(
				ERR_INVALID_DATA,
				"Chunk Profile identity derivation failed.",
				chunks,
				scope_key
			)
		var register_error: Error = _register_profile(profile)
		if register_error != OK:
			return _finish_materialization_failure(
				register_error,
				"Chunk Profile registration failed.",
				chunks,
				scope_key
			)

		var profile_id: StringName = profile.profile_id
		var sink: ChunkProfileLoadSink = ChunkProfileLoadSink.new()
		var context: Dictionary = {
			ChunkBlobSaveSectionProvider.LOAD_SINK_CONTEXT_KEY: sink,
		}
		var metadata: Dictionary = {
			&"read_kind": &"chunk_materialization",
			&"chunk_index": chunk_index,
		}
		var operation: GFSaveProfileOperation = _profile_utility.load_profile(
			profile_id,
			context,
			metadata
		)
		var result: GFSaveProfileResult = await _await_profile_operation(
			operation
		)
		_queue_profile_unregister(profile_id)
		_drain_pending_unregisters()
		if not _is_successful_chunk_load(result, profile_id):
			var load_error: Error = (
				result.get_error_code()
				if result != null and result.get_error_code() != OK
				else ERR_CANT_OPEN
			)
			return _finish_materialization_failure(
				load_error,
				"Chunk Profile load failed.",
				chunks,
				scope_key
			)
		var payload: PackedByteArray = sink.claim()
		if (
			payload.is_empty()
			or not manifest.verify_chunk(chunk_index, payload)
		):
			return _finish_materialization_failure(
				ERR_FILE_CORRUPT,
				"Chunk payload does not match its Manifest descriptor.",
				chunks,
				scope_key
			)
		chunks.append(payload)

	return _finish_materialization_success(chunks, scope_key)


## 获取不包含 Profile ID、文件名或 payload 的运行摘要。
func get_debug_snapshot() -> Dictionary:
	return {
		&"accepting": _accepting,
		&"disposed": _disposed,
		&"lease_count": _leases.size(),
		&"lease_scope_count": _lease_scopes.size(),
		&"queued_lease_count": _lease_order.size(),
		&"staging": _active_stage != null,
		&"scope_basis_count": _scope_basis_states.size(),
		&"registered_profile_count": _registered_profiles.size(),
		&"pending_unregister_count": _pending_unregister.size(),
		&"outcome_unknown_scope_count": _outcome_unknown_scopes.size(),
		&"stage_unknown_profile_count": _stage_unknown_profiles.size(),
		&"settled_notification_count": _settled_notifications.size(),
		&"active_materialization_count": _active_materializations,
		&"materialization_scope_count": _materialization_scope_counts.size(),
		&"cleanup_operation_count": _cleanup_operations.size(),
		&"cleanup_scope_count": _cleanup_scope_ids.size(),
		&"deferred_cleanup_count": _deferred_cleanup_requests.size(),
		&"pending_exact_cleanup_count": (
			_pending_exact_cleanup_requests.size()
		),
		&"cleanup_caller_outcome_unknown_count": (
			_count_cleanup_caller_outcome_unknown()
		),
		&"cleanup_notification_count": _cleanup_notifications.size(),
		&"last_cleanup_result": _last_cleanup_result.duplicate(true),
	}


# --- 私有/辅助方法 ---

func _start_next_ready_stage() -> void:
	if _active_stage != null or _executor == null:
		return
	_compact_lease_order()
	for lease_id: StringName in _lease_order:
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease == null or not lease.is_ready_to_stage():
			continue
		var scope_key: String = _get_lease_scope(lease_id)
		if (
			_outcome_unknown_scopes.has(scope_key)
			or _cleanup_scope_ids.has(scope_key)
		):
			continue
		var owner_value: Variant = _scope_stage_owners.get(scope_key)
		if owner_value is StringName:
			var owner_id: StringName = owner_value
			if owner_id != lease_id:
				continue
		_begin_stage(lease, scope_key)
		return


func _begin_stage(lease: ChunkSaveLease, scope_key: String) -> void:
	var expected_active_bank: StringName = ChunkManifest.BANK_NONE
	var expected_basis_epoch: int = 0
	var basis: ScopeBasis = _get_scope_basis(scope_key)
	if basis != null:
		expected_active_bank = basis.active_bank
		expected_basis_epoch = basis.epoch
		if (
			not lease.matches_scope_basis_for_utility(
				expected_active_bank,
				expected_basis_epoch
			)
			and not lease.rebase_scope_basis_for_utility(
				expected_active_bank,
				expected_basis_epoch
			)
		):
			var _failed_rebase: bool = lease.fail_for_utility(
				ERR_INVALID_DATA,
				"Chunk save lease could not observe the latest scope basis."
			)
			_finish_known_lease(lease)
			return
	var request: ChunkStageRequest = lease.take_stage_request_for_utility(
		expected_active_bank,
		expected_basis_epoch
	)
	if request == null:
		if _is_known_final_status(lease.get_status()):
			_finish_known_lease(lease)
		return
	_scope_stage_owners[scope_key] = lease.get_lease_id()
	var manifest: ChunkManifest = request.build_manifest()
	var profile_ids: Array[StringName] = []
	if manifest == null:
		_fail_stage_before_operation(
			lease,
			scope_key,
			profile_ids,
			ERR_INVALID_DATA,
			"Chunk stage request has no valid Manifest."
		)
		return

	for chunk_index: int in range(request.get_chunk_count()):
		var profile: GFSaveProfile = ChunkProfileRuntimeFactory.make_profile(
			lease.get_main_profile_id(),
			lease.get_main_profile_file(),
			lease.get_section_id(),
			manifest.get_bank(),
			chunk_index
		)
		if (
			profile == null
			or profile.profile_id
			!= request.get_chunk_profile_id(chunk_index)
		):
			_fail_stage_before_operation(
				lease,
				scope_key,
				profile_ids,
				ERR_INVALID_DATA,
				"Chunk stage requested an untrusted Profile identity."
			)
			return
		var register_error: Error = _register_profile(profile)
		if register_error != OK:
			_fail_stage_before_operation(
				lease,
				scope_key,
				profile_ids,
				register_error,
				"Inactive-bank chunk Profile registration failed."
			)
			return
		profile_ids.append(profile.profile_id)

	var persistence: ChunkedProfilePersistence = (
		ChunkedProfilePersistence.new(_executor)
	)
	var operation: ChunkStageOperation = persistence.stage(request)
	var active: ActiveStage = ActiveStage.new()
	active.lease_id = lease.get_lease_id()
	active.scope_key = scope_key
	active.persistence = persistence
	active.operation = operation
	active.profile_ids = profile_ids
	_active_stage = active
	if not lease.bind_stage_operation_for_utility(operation):
		var _cancel_requested: bool = operation.request_cancel(
			&"lease_binding_failed"
		)
		var _failed_binding: bool = lease.fail_for_utility(
			ERR_INVALID_DATA,
			"Chunk stage operation could not bind to its save lease."
		)


func _poll_active_stage() -> void:
	if (
		_active_stage == null
		or _active_stage.operation == null
		or not _active_stage.operation.is_completed()
	):
		return
	var active: ActiveStage = _active_stage
	var lease: ChunkSaveLease = get_save_lease(active.lease_id)
	var result: ChunkStageResult = active.operation.get_result()
	if lease != null and result != null:
		var _settled: bool = lease.settle_stage_for_utility(result)
	if lease != null and not lease.is_terminal() and not lease.is_staged():
		var _failed: bool = lease.fail_for_utility(
			ERR_INVALID_DATA,
			"Chunk stage operation did not produce a valid lease state."
		)
	var cleanup_admitted: bool = true
	if lease != null and lease.is_stage_outcome_unknown():
		cleanup_admitted = _record_stage_unknown_profile(
			active,
			result
		)
	if cleanup_admitted:
		_queue_profiles_unregister(active.profile_ids)
	_active_stage = null
	if lease != null:
		if lease.is_outcome_unknown():
			_outcome_unknown_scopes[active.scope_key] = active.lease_id
		elif _is_known_final_status(lease.get_status()):
			_finish_known_lease(lease)
		_release_scope_if_safe(lease)


func _fail_stage_before_operation(
	lease: ChunkSaveLease,
	scope_key: String,
	profile_ids: Array[StringName],
	error_code: Error,
	error: String
) -> void:
	_queue_profiles_unregister(profile_ids)
	var _failed: bool = lease.fail_for_utility(error_code, error)
	_finish_known_lease(lease)
	var owner_value: Variant = _scope_stage_owners.get(scope_key)
	if owner_value is StringName:
		var owner_id: StringName = owner_value
		if owner_id == lease.get_lease_id():
			var _erased: bool = _scope_stage_owners.erase(scope_key)


func _register_profile(profile: GFSaveProfile) -> Error:
	if _profile_utility == null or profile == null:
		return ERR_UNAVAILABLE
	if _registered_profiles.has(profile.profile_id):
		return ERR_ALREADY_IN_USE
	var report: Dictionary = _profile_utility.register_profile(profile)
	var registered_value: Variant = report.get("registered", false)
	if not registered_value is bool:
		return ERR_CANT_CREATE
	var registered: bool = registered_value
	if not registered:
		return ERR_CANT_CREATE
	_registered_profiles[profile.profile_id] = true
	return OK


func _queue_profiles_unregister(profile_ids: Array[StringName]) -> void:
	for profile_id: StringName in profile_ids:
		_queue_profile_unregister(profile_id)


func _queue_profile_unregister(profile_id: StringName) -> void:
	if _registered_profiles.has(profile_id):
		_pending_unregister[profile_id] = true


func _drain_pending_unregisters() -> void:
	if _profile_utility == null:
		return
	for profile_id_value: Variant in _pending_unregister.keys():
		if not profile_id_value is StringName:
			continue
		var profile_id: StringName = profile_id_value
		var snapshot: Dictionary = (
			_profile_utility.get_profile_state_snapshot(profile_id)
		)
		if snapshot.is_empty():
			var _erased_missing: bool = _pending_unregister.erase(profile_id)
			var _forgotten_missing: bool = _registered_profiles.erase(profile_id)
			continue
		if not _is_profile_known_idle(snapshot, profile_id):
			continue
		if _profile_utility.unregister_profile(profile_id):
			var _erased: bool = _pending_unregister.erase(profile_id)
			var _forgotten: bool = _registered_profiles.erase(profile_id)


func _is_profile_known_idle(
	snapshot: Dictionary,
	profile_id: StringName
) -> bool:
	var evidence: GameSaveProfileSettlementEvidence = (
		GameSaveProfileSettlementEvidence.from_snapshot(snapshot)
	)
	return evidence.is_settled_idle(profile_id)


func _coerce_snapshot_int(value: Variant, fallback: int) -> int:
	if value is int:
		var int_value: int = value
		return int_value
	if value is bool:
		var bool_value: bool = value
		return int(bool_value)
	if value is float:
		var float_value: float = value
		return int(float_value)
	return fallback


func _record_stage_unknown_profile(
	active: ActiveStage,
	result: ChunkStageResult
) -> bool:
	if result == null:
		return false
	var failed_index: int = result.get_failed_chunk_index()
	var profile_result: GFSaveProfileResult = result.get_profile_result()
	if (
		failed_index < 0
		or failed_index >= active.profile_ids.size()
		or profile_result == null
		or profile_result.get_operation()
		!= GFSaveProfileOperation.OPERATION_SAVE
		or profile_result.get_status()
		!= GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		or profile_result.get_profile_id() != active.profile_ids[failed_index]
	):
		return false
	_stage_unknown_profiles[active.scope_key] = profile_result.get_profile_id()
	return true


func _reconcile_stage_outcome_fences() -> void:
	for scope_value: Variant in _stage_unknown_profiles.keys():
		if not scope_value is String:
			continue
		var scope_key: String = scope_value
		var lease_id_value: Variant = _outcome_unknown_scopes.get(scope_key)
		var profile_id_value: Variant = _stage_unknown_profiles.get(scope_key)
		if (
			not lease_id_value is StringName
			or not profile_id_value is StringName
		):
			continue
		var lease_id: StringName = lease_id_value
		var profile_id: StringName = profile_id_value
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease == null:
			var _erased_missing: bool = _stage_unknown_profiles.erase(
				scope_key
			)
			continue
		if not lease.is_stage_outcome_unknown():
			if _is_known_final_status(lease.get_status()):
				_finish_known_lease(lease)
			continue
		var evidence: Dictionary = _profile_utility.get_profile_state_snapshot(
			profile_id
		)
		if lease.reconcile_stage_outcome_for_utility(evidence):
			var _erased_stage_profile: bool = _stage_unknown_profiles.erase(
				scope_key
			)
			_finish_known_lease(lease)


func _reconcile_main_outcome_fences() -> void:
	for scope_value: Variant in _outcome_unknown_scopes.keys():
		if not scope_value is String:
			continue
		var scope_key: String = scope_value
		var lease_id_value: Variant = _outcome_unknown_scopes.get(scope_key)
		if not lease_id_value is StringName:
			continue
		var lease_id: StringName = lease_id_value
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease == null:
			var _erased_missing: bool = _outcome_unknown_scopes.erase(scope_key)
			continue
		if _is_known_final_status(lease.get_status()):
			_finish_known_lease(lease)
			continue
		if lease.is_stage_outcome_unknown():
			continue
		var main_result: GFSaveProfileResult = lease.get_main_result()
		if (
			main_result == null
			or main_result.get_status()
			!= GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		):
			continue
		var evidence: Dictionary = _profile_utility.get_profile_state_snapshot(
			lease.get_main_profile_id()
		)
		var persisted_value: Variant = evidence.get("persisted_generation")
		if not persisted_value is int:
			continue
		var persisted_generation: int = persisted_value
		var persisted: bool = (
			persisted_generation >= lease.get_main_requested_generation()
		)
		if lease.reconcile_main_outcome_for_utility(
			persisted,
			persisted_generation,
			evidence
		):
			_finish_known_lease(lease)


func _finish_known_lease(lease: ChunkSaveLease) -> void:
	if lease == null or not _is_known_final_status(lease.get_status()):
		return
	# Staging 可以在已绑定的主 save 之前已知失败；候选 bank 仍必须等该
	# main operation 的物理终态，避免提前释放 lease 后丢失回收证据。
	if lease.is_waiting_for_bound_main_terminal_for_utility():
		return
	var lease_id: StringName = lease.get_lease_id()
	if _settled_notifications.has(lease_id):
		return
	_settled_notifications[lease_id] = true
	var scope_key: String = _get_lease_scope(lease_id)
	if lease.get_status() == ChunkSaveLease.STATUS_COMMITTED:
		_advance_scope_basis_from_commit(lease, scope_key)
	_schedule_cleanup_for_settled_lease(lease, scope_key)
	var fence_value: Variant = _outcome_unknown_scopes.get(scope_key)
	if fence_value is StringName:
		var fence_lease_id: StringName = fence_value
		if fence_lease_id == lease_id:
			var _erased_fence: bool = _outcome_unknown_scopes.erase(scope_key)
			var _erased_stage_profile: bool = _stage_unknown_profiles.erase(
				scope_key
			)
	_lease_order.erase(lease_id)
	_release_scope_if_safe(lease)
	# Signal 是同步边界；监听器可在回调内 get_save_lease() 并提交
	# Provider Manifest。回调返回后立即释放已知终态的有界证据。
	save_lease_settled.emit(lease_id)
	var _forgotten_lease: bool = _leases.erase(lease_id)
	var _forgotten_scope: bool = _lease_scopes.erase(lease_id)
	var _forgotten_notification: bool = _settled_notifications.erase(lease_id)
	_start_deferred_cleanup_requests()


func _release_scope_if_safe(lease: ChunkSaveLease) -> void:
	if lease == null or not _is_known_final_status(lease.get_status()):
		return
	if lease.is_waiting_for_bound_main_terminal_for_utility():
		return
	var lease_id: StringName = lease.get_lease_id()
	if _active_stage != null and _active_stage.lease_id == lease_id:
		return
	var scope_key: String = _get_lease_scope(lease_id)
	var owner_value: Variant = _scope_stage_owners.get(scope_key)
	if owner_value is StringName:
		var owner_id: StringName = owner_value
		if owner_id == lease_id:
			var _erased: bool = _scope_stage_owners.erase(scope_key)


func _cancel_not_started_leases_for_quiesce() -> void:
	for lease_id: StringName in _lease_order.duplicate():
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease == null:
			continue
		if lease.get_status() in [
			ChunkSaveLease.STATUS_WAITING_FOR_PROVIDER,
			ChunkSaveLease.STATUS_READY_TO_STAGE,
		]:
			var _failed: bool = lease.fail_for_utility(
				ERR_BUSY,
				"Chunk save lease was not staged before quiesce."
			)
			_finish_known_lease(lease)


func _schedule_cleanup_for_settled_lease(
	lease: ChunkSaveLease,
	scope_key: String
) -> void:
	# 自动请求冻结于本 lease 的 Manifest。若已有同 scope sibling 被接纳，后者
	# 可能成为下一提交点；此时不能用旧请求取得 fence 并让 sibling 与“无 live
	# lease”条件互锁。由 sibling 的后续已知终态生成下一份仍然有效的 cleanup。
	if (
		lease == null
		or scope_key.is_empty()
		or _storage == null
		or _cleanup_scope_ids.has(scope_key)
	):
		return
	var request: ChunkProfileCleanupRequest = null
	if lease.get_status() == ChunkSaveLease.STATUS_COMMITTED:
		# 任一更新的 exact commit 都会改变 active bank；旧意图此后可能删除
		# 当前可见 bank，必须先无条件作废，再以最新 basis 重建。
		var _stale_exact_erased: bool = (
			_pending_exact_cleanup_requests.erase(scope_key)
		)
		request = ChunkProfileCleanupRequest.after_exact_commit(
			lease.get_main_profile_id(),
			lease.get_main_profile_file(),
			lease.get_section_id(),
			lease.get_previous_active_bank_for_utility(),
			lease.get_committed_manifest()
		)
		if request == null or not request.is_valid():
			return
		if _scope_has_other_live_lease(scope_key, lease.get_lease_id()):
			_pending_exact_cleanup_requests[scope_key] = request
			return
	elif lease.get_status() == ChunkSaveLease.STATUS_SUPERSEDED:
		# persisted_generation 已越过本 lease 时，候选 Manifest 的可见性未知；
		# 既不能回收候选 bank，也不能继续使用可能删除它的旧 exact 意图。
		var _unsafe_exact_erased: bool = (
			_pending_exact_cleanup_requests.erase(scope_key)
		)
		return
	elif _scope_has_other_live_lease(scope_key, lease.get_lease_id()):
		return
	elif lease.get_status() in [
		ChunkSaveLease.STATUS_FAILED,
		ChunkSaveLease.STATUS_CANCELLED,
	]:
		var pending_exact_value: Variant = (
			_pending_exact_cleanup_requests.get(scope_key)
		)
		if pending_exact_value is ChunkProfileCleanupRequest:
			request = pending_exact_value
			var _pending_exact_erased: bool = (
				_pending_exact_cleanup_requests.erase(scope_key)
			)
	# 有 exact 意图时，它会同时覆盖旧 inactive bank、当前 active tail，以及
	# sibling 失败后同一 inactive bank 的候选数据，不需要再提交第二次 discard。
	if request == null and lease.is_candidate_cleanup_known_safe_for_utility():
		request = ChunkProfileCleanupRequest.discard_candidate(
			lease.get_main_profile_id(),
			lease.get_main_profile_file(),
			lease.get_section_id(),
			lease.get_cleanup_manifest_for_utility()
		)
	if request != null and request.is_valid():
		var _cleanup: ChunkProfileCleanupOperation = _begin_cleanup_request(
			request,
			scope_key
		)


func _begin_cleanup_request(
	request: ChunkProfileCleanupRequest,
	scope_key: String
) -> ChunkProfileCleanupOperation:
	if (
		request == null
		or not request.is_valid()
		or scope_key.is_empty()
		or _storage == null
		or _cleanup_scope_ids.has(scope_key)
	):
		return _make_terminal_cleanup_operation(
			ChunkProfileCleanupResult.STATUS_BUSY,
			ERR_BUSY,
			"Chunk cleanup scope is already owned."
		)
	if request.get_kind() in [
		ChunkProfileCleanupRequest.KIND_EXACT_COMMIT,
		ChunkProfileCleanupRequest.KIND_ENTIRE_FAMILY,
	]:
		# 已接纳的 exact/entire-family 请求完整取代尚未启动的旧 exact 意图。
		var _pending_exact_erased: bool = (
			_pending_exact_cleanup_requests.erase(scope_key)
		)
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	var operation_id: StringName = _allocate_cleanup_operation_id()
	if not operation.configure_for_persistence(operation_id):
		return _make_terminal_cleanup_operation(
			ChunkProfileCleanupResult.STATUS_INVALID_REQUEST,
			ERR_CANT_CREATE,
			"Chunk cleanup operation identity could not be configured."
		)
	_cleanup_operations[operation_id] = operation
	_cleanup_scope_ids[scope_key] = operation_id
	_cleanup_operation_scopes[operation_id] = scope_key
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = operation.completed.connect(
		Callable(self, &"_on_cleanup_operation_completed").bind(
			operation_id,
			scope_key
		),
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		var _completed_connect_failure: bool = operation.complete_for_persistence(
			ChunkProfileCleanupResult.create(
				ChunkProfileCleanupResult.STATUS_INVALID_REQUEST,
				connect_error,
				"Chunk cleanup completion observer could not be connected.",
				request.get_identity_count(),
				0,
				0,
				0,
				request.get_identity_count(),
				0
			)
		)
		_drain_cleanup_terminals()
		return operation
	if _cleanup_scope_has_defer_barrier(scope_key):
		_deferred_cleanup_requests[operation_id] = request
	else:
		_start_cleanup_runner(operation_id, request)
	return operation


func _start_cleanup_runner(
	operation_id: StringName,
	request: ChunkProfileCleanupRequest
) -> void:
	var operation: ChunkProfileCleanupOperation = get_cleanup_operation(
		operation_id
	)
	if operation == null or operation.is_completed() or request == null:
		return
	var runner: ChunkProfileCleanupRunner = ChunkProfileCleanupRunner.new(
		_storage
	)
	if not runner.start(request, operation):
		if operation.is_pending():
			var _completed_start_failure: bool = operation.complete_for_persistence(
				ChunkProfileCleanupResult.create(
					ChunkProfileCleanupResult.STATUS_INVALID_REQUEST,
					ERR_CANT_CREATE,
					"Chunk cleanup runner could not start.",
					request.get_identity_count(),
					0,
					0,
					0,
					request.get_identity_count(),
					0
				)
			)
		_drain_cleanup_terminals()


func _start_deferred_cleanup_requests() -> void:
	for operation_id_value: Variant in _deferred_cleanup_requests.keys():
		if not operation_id_value is StringName:
			continue
		var operation_id: StringName = operation_id_value
		var scope_value: Variant = _cleanup_operation_scopes.get(operation_id)
		if not scope_value is String:
			var _invalid_erased: bool = _deferred_cleanup_requests.erase(
				operation_id
			)
			continue
		var scope_key: String = scope_value
		if _cleanup_scope_has_defer_barrier(scope_key):
			continue
		var request_value: Variant = _deferred_cleanup_requests.get(operation_id)
		var _erased: bool = _deferred_cleanup_requests.erase(operation_id)
		if request_value is ChunkProfileCleanupRequest:
			var request: ChunkProfileCleanupRequest = request_value
			_start_cleanup_runner(operation_id, request)


func _make_terminal_cleanup_operation(
	status: StringName,
	error_code: Error,
	error: String
) -> ChunkProfileCleanupOperation:
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	var _configured: bool = operation.configure_for_persistence(
		_allocate_cleanup_operation_id()
	)
	var _completed: bool = operation.complete_for_persistence(
		ChunkProfileCleanupResult.create(
			status,
			error_code,
			error,
			0,
			0,
			0,
			0,
			0,
			0
		)
	)
	return operation


func _allocate_cleanup_operation_id() -> StringName:
	var operation_id: StringName = StringName("chunk_cleanup.%d.%d" % [
		get_instance_id(),
		_next_cleanup_serial,
	])
	_next_cleanup_serial += 1
	return operation_id


func _on_cleanup_operation_completed(
	_result: ChunkProfileCleanupResult,
	operation_id: StringName,
	scope_key: String
) -> void:
	_finish_cleanup_operation(operation_id, scope_key)


func _drain_cleanup_terminals() -> void:
	for operation_id_value: Variant in _cleanup_operations.keys():
		if not operation_id_value is StringName:
			continue
		var operation_id: StringName = operation_id_value
		var operation: ChunkProfileCleanupOperation = get_cleanup_operation(
			operation_id
		)
		if operation == null or not operation.is_completed():
			continue
		var scope_value: Variant = _cleanup_operation_scopes.get(operation_id)
		var scope_key: String = scope_value if scope_value is String else ""
		_finish_cleanup_operation(operation_id, scope_key)


func _finish_cleanup_operation(
	operation_id: StringName,
	scope_key: String
) -> void:
	if (
		operation_id.is_empty()
		or not _cleanup_operations.has(operation_id)
		or _cleanup_notifications.has(operation_id)
	):
		return
	_cleanup_notifications[operation_id] = true
	var operation: ChunkProfileCleanupOperation = get_cleanup_operation(
		operation_id
	)
	var result: ChunkProfileCleanupResult = (
		operation.get_result() if operation != null else null
	)
	if result != null:
		_last_cleanup_result = result.to_dict()
	var scope_owner_value: Variant = _cleanup_scope_ids.get(scope_key)
	if scope_owner_value is StringName:
		var scope_owner_id: StringName = scope_owner_value
		if scope_owner_id == operation_id:
			var _scope_erased: bool = _cleanup_scope_ids.erase(scope_key)
	var _operation_erased: bool = _cleanup_operations.erase(operation_id)
	var _deferred_erased: bool = _deferred_cleanup_requests.erase(operation_id)
	var _operation_scope_erased: bool = _cleanup_operation_scopes.erase(
		operation_id
	)
	var _notification_erased: bool = _cleanup_notifications.erase(operation_id)
	# settlement 是“scope 已可复用”的边界。先释放全部 owner/index，再发布
	# signal，避免同步 waiter 被唤醒时仍见旧 fence、二次 await 后永远丢信号。
	cleanup_operation_settled.emit(operation_id)
	_try_complete_quiesce()


func _scope_has_live_lease(scope_key: String) -> bool:
	for lease_scope_value: Variant in _lease_scopes.values():
		if lease_scope_value is String and lease_scope_value == scope_key:
			return true
	return false


func _scope_has_other_live_lease(
	scope_key: String,
	excluded_lease_id: StringName
) -> bool:
	for lease_id_value: Variant in _lease_scopes.keys():
		if not lease_id_value is StringName:
			continue
		var lease_id: StringName = lease_id_value
		if lease_id == excluded_lease_id:
			continue
		var lease_scope_value: Variant = _lease_scopes.get(lease_id)
		if lease_scope_value is String and lease_scope_value == scope_key:
			return true
	return false


func _cleanup_scope_has_defer_barrier(scope_key: String) -> bool:
	return (
		_get_materialization_scope_count(scope_key) > 0
		or _scope_has_live_lease(scope_key)
		or _outcome_unknown_scopes.has(scope_key)
	)


func _count_cleanup_caller_outcome_unknown() -> int:
	var total_count: int = 0
	for operation_value: Variant in _cleanup_operations.values():
		if not operation_value is ChunkProfileCleanupOperation:
			continue
		var operation: ChunkProfileCleanupOperation = operation_value
		total_count += _coerce_snapshot_int(
			operation.get_debug_snapshot().get(
				"caller_outcome_unknown_count",
				0
			),
			0
		)
	return total_count


func _advance_scope_basis_from_commit(
	committed_lease: ChunkSaveLease,
	scope_key: String
) -> void:
	if committed_lease == null or scope_key.is_empty():
		return
	var manifest: ChunkManifest = committed_lease.get_committed_manifest()
	if manifest == null:
		return
	var basis: ScopeBasis = _get_scope_basis(scope_key)
	if basis == null:
		basis = ScopeBasis.new()
		_scope_basis_states[scope_key] = basis
	basis.epoch += 1
	basis.active_bank = manifest.get_bank()
	var committed_lease_id: StringName = committed_lease.get_lease_id()
	for lease_id: StringName in _lease_order:
		if (
			lease_id == committed_lease_id
			or _get_lease_scope(lease_id) != scope_key
		):
			continue
		var sibling: ChunkSaveLease = get_save_lease(lease_id)
		if sibling == null or sibling.get_status() not in [
			ChunkSaveLease.STATUS_WAITING_FOR_PROVIDER,
			ChunkSaveLease.STATUS_READY_TO_STAGE,
		]:
			continue
		var _rebased: bool = sibling.rebase_scope_basis_for_utility(
			basis.active_bank,
			basis.epoch
		)


func _get_scope_basis(scope_key: String) -> ScopeBasis:
	var basis_value: Variant = _scope_basis_states.get(scope_key)
	if basis_value is ScopeBasis:
		var basis: ScopeBasis = basis_value
		return basis
	return null


func _try_complete_quiesce() -> void:
	if _quiesce_completion == null or not _quiesce_completion.is_pending():
		return
	if (
		_active_stage != null
		or _active_materializations > 0
		or not _registered_profiles.is_empty()
		or not _pending_unregister.is_empty()
		or not _cleanup_operations.is_empty()
		or not _pending_exact_cleanup_requests.is_empty()
		or _has_unresolved_main_outcome()
	):
		return
	var _succeeded: bool = _quiesce_completion.succeed()


func _has_unresolved_main_outcome() -> bool:
	for lease_value: Variant in _leases.values():
		if not lease_value is ChunkSaveLease:
			continue
		var lease: ChunkSaveLease = lease_value
		if lease.is_waiting_for_bound_main_terminal_for_utility():
			return true
	for lease_id_value: Variant in _outcome_unknown_scopes.values():
		if not lease_id_value is StringName:
			continue
		var lease_id: StringName = lease_id_value
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease == null:
			continue
		if lease.is_stage_outcome_unknown():
			continue
		var result: GFSaveProfileResult = lease.get_main_result()
		if (
			result != null
			and result.get_status()
			== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		):
			return true
	return false


func _await_profile_operation(
	operation: GFSaveProfileOperation
) -> GFSaveProfileResult:
	if operation == null:
		return null
	if operation.is_completed():
		return operation.get_result()
	var completed_value: Variant = await operation.completed
	if completed_value is GFSaveProfileResult:
		return completed_value
	return operation.get_result()


func _is_successful_chunk_load(
	result: GFSaveProfileResult,
	profile_id: StringName
) -> bool:
	return (
		result != null
		and result.is_successful()
		and result.get_operation() == GFSaveProfileOperation.OPERATION_LOAD
		and result.get_status() == GFSaveProfileResult.STATUS_LOADED
		and result.get_profile_id() == profile_id
	)


func _finish_materialization_failure(
	error_code: Error,
	error: String,
	chunks: Array[PackedByteArray],
	scope_key: String
) -> Dictionary:
	chunks.clear()
	_active_materializations = maxi(_active_materializations - 1, 0)
	_decrement_materialization_scope(scope_key)
	_drain_pending_unregisters()
	_start_deferred_cleanup_requests()
	_try_complete_quiesce()
	return _make_materialization_result(false, error_code, error)


func _finish_materialization_success(
	chunks: Array[PackedByteArray],
	scope_key: String
) -> Dictionary:
	_active_materializations = maxi(_active_materializations - 1, 0)
	_decrement_materialization_scope(scope_key)
	_drain_pending_unregisters()
	_start_deferred_cleanup_requests()
	_try_complete_quiesce()
	return _make_materialization_result(true, OK, "", chunks)


func _increment_materialization_scope(scope_key: String) -> void:
	var current_count: int = _get_materialization_scope_count(scope_key)
	_materialization_scope_counts[scope_key] = current_count + 1


func _decrement_materialization_scope(scope_key: String) -> void:
	var current_count: int = _get_materialization_scope_count(scope_key)
	if current_count <= 1:
		var _erased: bool = _materialization_scope_counts.erase(scope_key)
	else:
		_materialization_scope_counts[scope_key] = current_count - 1


func _get_materialization_scope_count(scope_key: String) -> int:
	var count_value: Variant = _materialization_scope_counts.get(scope_key, 0)
	return count_value if count_value is int else 0


func _make_materialization_result(
	ok: bool,
	error_code: Error,
	error: String,
	chunks: Array[PackedByteArray] = []
) -> Dictionary:
	return {
		&"ok": ok,
		&"error_code": OK if ok else error_code,
		&"error": "" if ok else error.strip_edges(),
		&"chunks": chunks if ok else [],
	}


func _get_lease_scope(lease_id: StringName) -> String:
	var scope_value: Variant = _lease_scopes.get(lease_id, "")
	if scope_value is String:
		var scope_key: String = scope_value
		return scope_key
	return ""


func _compact_lease_order() -> void:
	var compacted: Array[StringName] = []
	for lease_id: StringName in _lease_order:
		var lease: ChunkSaveLease = get_save_lease(lease_id)
		if lease != null and not _is_known_final_status(lease.get_status()):
			compacted.append(lease_id)
	_lease_order = compacted


func _is_known_final_status(status: StringName) -> bool:
	return status in [
		ChunkSaveLease.STATUS_COMMITTED,
		ChunkSaveLease.STATUS_SUPERSEDED,
		ChunkSaveLease.STATUS_FAILED,
		ChunkSaveLease.STATUS_CANCELLED,
	]


# --- 内部类 ---

class ActiveStage extends RefCounted:
	var lease_id: StringName = &""
	var scope_key: String = ""
	var persistence: ChunkedProfilePersistence = null
	var operation: ChunkStageOperation = null
	var profile_ids: Array[StringName] = []


class ScopeBasis extends RefCounted:
	var active_bank: StringName = ChunkManifest.BANK_NONE
	var epoch: int = 0
