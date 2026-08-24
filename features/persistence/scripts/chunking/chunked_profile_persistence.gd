## 将完整 chunk bundle 写入 inactive bank 的项目级 staging 核心。
##
## 核心不是最终提交 owner：它只面向 GF public Profile request/operation/result，
## 把 chunk 交给未来 Provider 从 opaque Lease claim，并返回尚未可见的候选
## Manifest。主玩家 Profile 的 manifest flip 必须由外部 persistence owner 完成。
class_name ChunkedProfilePersistence
extends RefCounted


# --- 常量 ---

const _CHUNK_LEASE_KEY: StringName = (
	ChunkBlobSaveSectionProvider.SAVE_LEASE_CONTEXT_KEY
)


# --- 私有变量 ---

var _executor: ChunkProfileExecutor = null
var _active_state: StageState = null
var _fenced: bool = false
var _fence_section_id: StringName = &""
var _fence_target_bank: StringName = ChunkManifest.BANK_NONE
var _fence_chunk_index: int = -1


# --- 生命周期方法 ---

func _init(executor: ChunkProfileExecutor = null) -> void:
	_executor = executor


# --- 公共方法 ---

## 将一个冻结 bundle 全部写入 inactive bank。
##
## @param request: 与调用方载荷隔离的 typed request。
## @return 可取消且只完成一次的 staging operation。
func stage(request: ChunkStageRequest) -> ChunkStageOperation:
	var operation: ChunkStageOperation = ChunkStageOperation.new()
	if _executor == null or request == null or not request.is_valid():
		_complete_immediately(
			operation,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_INVALID_REQUEST,
				ERR_INVALID_DATA,
				"Chunk stage request or executor is invalid."
			)
		)
		return operation
	if _active_state != null or _fenced:
		var busy_error: String = (
			"Target bank reconciliation is required before another stage."
			if _fenced
			else "Another chunk stage is active."
		)
		_complete_immediately(
			operation,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_BUSY,
				ERR_BUSY,
				busy_error
			)
		)
		return operation

	var manifest: ChunkManifest = request.build_manifest()
	if manifest == null:
		_complete_immediately(
			operation,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_INVALID_REQUEST,
				ERR_INVALID_DATA,
				"Chunk manifest could not be constructed."
			)
		)
		return operation

	var state: StageState = StageState.new()
	state.request = request
	state.operation = operation
	state.manifest = manifest
	_active_state = state
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = operation.cancellation_requested.connect(
		Callable(self, &"_on_cancellation_requested").bind(state),
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_INVALID_REQUEST,
				connect_error,
				"Chunk cancellation observer could not be connected.",
				-1,
				manifest
			)
		)
		return operation
	var _deferred_start: Variant = call_deferred(&"_advance_stage", state)
	return operation


## 查询 outcome-unknown reconciliation fence 是否仍被持有。
func is_fenced() -> bool:
	return _fenced


## 获取不包含 payload 或物理路径的 fence 证据。
##
## @return 未 fenced 时为空 Dictionary。
func get_fence_snapshot() -> Dictionary:
	if not _fenced:
		return {}
	return {
		&"section_id": _fence_section_id,
		&"target_bank": _fence_target_bank,
		&"chunk_index": _fence_chunk_index,
	}


# --- 私有/辅助方法 ---

func _advance_stage(state: StageState) -> void:
	if state != _active_state or state.awaiting_profile:
		return
	if state.operation.is_cancel_requested():
		_finish_cancelled(state)
		return
	if state.next_chunk_index < state.manifest.get_chunk_count():
		_start_chunk_save(state)
		return
	_finish(
		state,
		ChunkStageResult.create(
			ChunkStageResult.STATUS_STAGED,
			OK,
			"",
			-1,
			state.manifest,
			state.last_profile_result
		)
	)


func _start_chunk_save(state: StageState) -> void:
	var chunk_index: int = state.next_chunk_index
	var payload: PackedByteArray = state.request.duplicate_chunk(chunk_index)
	if not state.manifest.verify_chunk(chunk_index, payload):
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_INVALID_REQUEST,
				ERR_INVALID_DATA,
				"Frozen chunk no longer matches its manifest.",
				chunk_index,
				state.manifest
			)
		)
		return

	var lease: ChunkProfileSaveLease = (
		ChunkProfileSaveLease.take_ownership(payload)
	)
	if lease == null:
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_INVALID_REQUEST,
				ERR_INVALID_DATA,
				"Chunk payload violates the runtime Profile budget.",
				chunk_index,
				state.manifest
			)
		)
		return
	var context: Dictionary = {
		_CHUNK_LEASE_KEY: lease,
		&"section_id": state.manifest.get_section_id(),
		&"target_bank": state.manifest.get_bank(),
		&"chunk_index": chunk_index,
	}
	var result_metadata: Dictionary = {
		&"write_kind": &"chunk_stage",
		&"chunk_index": chunk_index,
	}
	var profile_request: GFSaveProfileRequest = (
		GFSaveProfileRequest.take_ownership({}, context, result_metadata)
	)
	var profile_id: StringName = state.request.get_chunk_profile_id(chunk_index)
	var profile_operation: GFSaveProfileOperation = _executor.save_profile(
		profile_id,
		profile_request
	)
	if profile_operation == null:
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_CHUNK_PROFILE_FAILED,
				ERR_CANT_CREATE,
				"Chunk Profile executor rejected the request.",
				chunk_index,
				state.manifest
			)
		)
		return
	var _phase_changed: bool = state.operation.set_phase_for_persistence(
		ChunkStageOperation.PHASE_WRITING_CHUNKS
	)
	_observe_profile_operation(
		state,
		profile_operation,
		chunk_index
	)


func _observe_profile_operation(
	state: StageState,
	profile_operation: GFSaveProfileOperation,
	chunk_index: int
) -> void:
	state.awaiting_profile = true
	if profile_operation.is_completed():
		var completed_result: GFSaveProfileResult = profile_operation.get_result()
		var _deferred_completion: Variant = call_deferred(
			&"_on_profile_operation_completed",
			completed_result,
			state,
			chunk_index
		)
		return
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = profile_operation.completed.connect(
		Callable(self, &"_on_profile_operation_completed").bind(
			state,
			chunk_index
		),
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		state.awaiting_profile = false
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_CHUNK_PROFILE_FAILED,
				connect_error,
				"GF Profile completion observer could not be connected.",
				chunk_index,
				state.manifest
			)
		)


func _profile_save_succeeded(result: GFSaveProfileResult) -> bool:
	return (
		result != null
		and result.is_successful()
		and result.get_operation() == GFSaveProfileOperation.OPERATION_SAVE
		and result.get_status() == GFSaveProfileResult.STATUS_SAVED
	)


func _handle_profile_failure(
	state: StageState,
	result: GFSaveProfileResult,
	chunk_index: int
) -> void:
	if (
		result != null
		and result.get_status() == GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	):
		_fenced = true
		_fence_section_id = state.manifest.get_section_id()
		_fence_target_bank = state.manifest.get_bank()
		_fence_chunk_index = chunk_index
		_finish(
			state,
			ChunkStageResult.create(
				ChunkStageResult.STATUS_OUTCOME_UNKNOWN,
				result.get_error_code(),
				"GF Profile write outcome is unknown; reconciliation is required.",
				chunk_index,
				state.manifest,
				result
			)
		)
		return
	var error_code: Error = (
		result.get_error_code()
		if result != null
		else FAILED
	)
	_finish(
		state,
		ChunkStageResult.create(
			ChunkStageResult.STATUS_CHUNK_PROFILE_FAILED,
			error_code,
			"GF Profile write failed before inactive bank staging completed.",
			chunk_index,
			state.manifest,
			result
		)
	)


func _finish_cancelled(state: StageState) -> void:
	_finish(
		state,
		ChunkStageResult.create(
			ChunkStageResult.STATUS_CANCELLED,
			ERR_SKIP,
			String(state.operation.get_cancel_reason()),
			-1,
			state.manifest
		)
	)


func _finish(state: StageState, result: ChunkStageResult) -> void:
	if state != _active_state:
		return
	_active_state = null
	var _completed: bool = state.operation.complete_for_persistence(result)


func _complete_immediately(
	operation: ChunkStageOperation,
	result: ChunkStageResult
) -> void:
	var _completed: bool = operation.complete_for_persistence(result)


# --- 信号回调 ---

func _on_cancellation_requested(
	_reason: StringName,
	state: StageState
) -> void:
	if state != _active_state or state.awaiting_profile:
		return
	var _deferred_advance: Variant = call_deferred(&"_advance_stage", state)


func _on_profile_operation_completed(
	result: GFSaveProfileResult,
	state: StageState,
	chunk_index: int
) -> void:
	if state != _active_state or not state.awaiting_profile:
		return
	state.awaiting_profile = false
	if not _profile_save_succeeded(result):
		_handle_profile_failure(state, result, chunk_index)
		return
	if state.operation.is_cancel_requested():
		_finish_cancelled(state)
		return
	state.last_profile_result = result.duplicate_result()
	state.next_chunk_index += 1
	var _deferred_advance: Variant = call_deferred(&"_advance_stage", state)


# --- 内部类 ---

class StageState extends RefCounted:
	var request: ChunkStageRequest = null
	var operation: ChunkStageOperation = null
	var manifest: ChunkManifest = null
	var next_chunk_index: int = 0
	var awaiting_profile: bool = false
	var last_profile_result: GFSaveProfileResult = null
