## 连接一次真实主 Profile save 与一个 manifest-backed section 的暂存工作。
##
## Lease 本身不提交可见性。Provider 只移交 chunks 并在 staging 成功后一次性
## claim 候选 Manifest；只有绑定的主 GF Profile generation 已知保存成功，候选
## 才进入 COMMITTED。GF coalescing、已知失败和 outcome-unknown 保持独立终态。
class_name ChunkSaveLease
extends RefCounted


# --- 常量 ---

const STATUS_WAITING_FOR_PROVIDER: StringName = &"waiting_for_provider"
const STATUS_READY_TO_STAGE: StringName = &"ready_to_stage"
const STATUS_STAGING: StringName = &"staging"
const STATUS_STAGED: StringName = &"staged"
const STATUS_MANIFEST_CLAIMED: StringName = &"manifest_claimed"
const STATUS_COMMITTED: StringName = &"committed"
const STATUS_SUPERSEDED: StringName = &"superseded"
const STATUS_FAILED: StringName = &"failed"
const STATUS_OUTCOME_UNKNOWN: StringName = &"outcome_unknown"
const STATUS_CANCELLED: StringName = &"cancelled"

const _MAX_ID_LENGTH: int = 192


# --- 私有变量 ---

var _ready: bool = false
var _lease_id: StringName = &""
var _main_profile_id: StringName = &""
var _main_profile_file: String = ""
var _section_id: StringName = &""
var _section_schema_version: int = 0
var _producer_revision: int = -1
var _chunk_profile_prefix: String = ""
var _status: StringName = STATUS_FAILED
var _offered_chunks: Array[PackedByteArray] = []
var _offered_active_bank: StringName = ChunkManifest.BANK_NONE
## 同 scope 已知提交点向本 lease 传播的最新 active bank/epoch。
##
## epoch 只在 ChunkProfileUtility 的 live lease 队列内有效；它不持久化，也不
## 跨账号/Profile reload 复用。WAITING lease 先记录 basis，READY lease 则同时
## 重写尚未 claim 的 staging bank 选择，均不触碰 payload。
var _scope_basis_bank: StringName = ChunkManifest.BANK_NONE
var _scope_basis_epoch: int = 0
var _stage_request_claimed: bool = false
var _stage_operation: ChunkStageOperation = null
var _stage_result: ChunkStageResult = null
var _stage_outcome_unknown: bool = false
## staging 已知失败/取消后仍需保留到已绑定 main operation 获得物理终态。
var _known_stage_terminal_status: StringName = &""
var _known_stage_terminal_error_code: Error = OK
var _known_stage_terminal_error: String = ""
var _known_stage_main_outcome_unknown: bool = false
var _candidate_manifest: ChunkManifest = null
var _manifest_claimed: bool = false
var _main_operation: GFSaveProfileOperation = null
var _main_requested_generation: int = 0
var _main_result: GFSaveProfileResult = null
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 创建常量时间的 save lease；不会读取或复制业务 payload。
##
## @param lease_id: 当前 SaveGraph 内唯一的关联 ID。
## @param main_profile_id: 最终提交 Manifest 的主 GF Profile ID。
## @param main_profile_file: 主 Profile 的可信存储相对文件名。
## @param section_id: manifest-backed Feature section ID。
## @param section_schema_version: 当前 section schema 版本。
## @param producer_revision: Provider 在请求边界冻结的业务 revision。
## @param chunk_profile_prefix: 非持久化、由可信身份派生的 chunk Profile 前缀。
## @return 参数合法时返回 waiting lease，否则返回 null。
static func create(
	lease_id: StringName,
	main_profile_id: StringName,
	main_profile_file: String,
	section_id: StringName,
	section_schema_version: int,
	producer_revision: int,
	chunk_profile_prefix: String
) -> ChunkSaveLease:
	if (
		not _is_bounded_text(String(lease_id))
		or not _is_bounded_text(String(main_profile_id))
		or not _is_bounded_text(main_profile_file)
		or not _is_bounded_text(String(section_id))
		or section_schema_version <= 0
		or producer_revision < 0
		or not _is_bounded_text(chunk_profile_prefix)
	):
		return null
	var lease: ChunkSaveLease = ChunkSaveLease.new()
	lease._lease_id = lease_id
	lease._main_profile_id = main_profile_id
	lease._main_profile_file = main_profile_file
	lease._section_id = section_id
	lease._section_schema_version = section_schema_version
	lease._producer_revision = producer_revision
	lease._chunk_profile_prefix = chunk_profile_prefix
	lease._status = STATUS_WAITING_FOR_PROVIDER
	lease._ready = true
	return lease


## Provider 一次性移交按规范顺序构造的 chunks。
##
## 本方法只转移数组根；成功后调用方必须永久放弃 chunks 及其元素 alias。
## 本方法不遍历、复制或摘要 payload；严格预算校验延迟到
## take_stage_request_for_utility()。active_manifest 必须是同一 Provider
## 已校验的当前提交状态，这里只常量时间复核它的 identity 与 bank。
##
## @param chunks: 唯一所有权的候选 chunk bytes。
## @param producer_revision: 生成 chunks 的 Provider 业务 revision。
## @param section_id: 生成 chunks 的 Feature section ID。
## @param section_schema_version: 生成 chunks 的 section schema 版本。
## @param active_manifest: 当前已提交 Manifest；首次保存传 null。
## @return 首次合法移交返回 true。
func offer_chunks_taking_ownership(
	chunks: Array[PackedByteArray],
	producer_revision: int,
	section_id: StringName,
	section_schema_version: int,
	active_manifest: ChunkManifest = null
) -> bool:
	if not _ready or _status != STATUS_WAITING_FOR_PROVIDER:
		return false
	if (
		producer_revision != _producer_revision
		or section_id != _section_id
		or section_schema_version != _section_schema_version
		or chunks.is_empty()
		or chunks.size() > ChunkManifest.MAX_CHUNK_COUNT
	):
		return false
	var active_bank: StringName = ChunkManifest.BANK_NONE
	if active_manifest != null:
		active_bank = active_manifest.get_bank()
		if (
			active_manifest.get_section_id() != _section_id
			or active_manifest.get_section_schema_version()
			!= _section_schema_version
			or active_bank not in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]
		):
			return false
	_offered_chunks = chunks
	_offered_active_bank = (
		_scope_basis_bank
		if _scope_basis_epoch > 0
		else active_bank
	)
	_status = STATUS_READY_TO_STAGE
	return true


## 绑定调用方已经立即取得的真实主 GF save operation。
##
## @param operation: 与 main_profile_id 匹配的 save operation。
## @return 首次合法绑定返回 true。
func bind_main_operation(operation: GFSaveProfileOperation) -> bool:
	if (
		not _ready
		or is_terminal()
		or _main_operation != null
		or operation == null
		or operation.get_operation() != GFSaveProfileOperation.OPERATION_SAVE
		or operation.get_profile_id() != _main_profile_id
		or operation.get_requested_generation() <= 0
	):
		return false
	_main_operation = operation
	_main_requested_generation = operation.get_requested_generation()
	return true


## 获取稳定 lease ID。
func get_lease_id() -> StringName:
	return _lease_id


## 获取主 GF Profile ID。
func get_main_profile_id() -> StringName:
	return _main_profile_id


## 获取主 Profile 文件名。
func get_main_profile_file() -> String:
	return _main_profile_file


## 获取 Feature section ID。
func get_section_id() -> StringName:
	return _section_id


## 获取 section schema 版本。
func get_section_schema_version() -> int:
	return _section_schema_version


## 获取 Provider 请求边界的业务 revision。
func get_producer_revision() -> int:
	return _producer_revision


## 获取当前 typed 状态。
func get_status() -> StringName:
	return _status


## 获取主保存请求 generation；尚未绑定时为 0。
func get_main_requested_generation() -> int:
	return _main_requested_generation


## 查询 Provider 是否已经移交 chunks。
func is_ready_to_stage() -> bool:
	return _status == STATUS_READY_TO_STAGE


## 查询候选 Manifest 是否已经完整 staged。
func is_staged() -> bool:
	return _status in [STATUS_STAGED, STATUS_MANIFEST_CLAIMED, STATUS_COMMITTED]


## 查询是否已经进入不可丢弃的 outcome-unknown fence。
func is_outcome_unknown() -> bool:
	return _status == STATUS_OUTCOME_UNKNOWN


## 查询当前 fence 是否来自 chunk staging 写入。
func is_stage_outcome_unknown() -> bool:
	return _status == STATUS_OUTCOME_UNKNOWN and _stage_outcome_unknown


## 查询当前 lease 是否已经进入任一最终主提交终态。
func is_terminal() -> bool:
	return _status in [
		STATUS_COMMITTED,
		STATUS_SUPERSEDED,
		STATUS_FAILED,
		STATUS_OUTCOME_UNKNOWN,
		STATUS_CANCELLED,
	]


## 获取失败 Error 码。
func get_error_code() -> Error:
	return _error_code


## 获取不含 payload 的稳定错误摘要。
func get_error() -> String:
	return _error


## Provider 在 staging 成功后一次性取得要写入主 section 的 Manifest。
##
## @return 首次 claim 返回隔离 Manifest；其他状态返回 null。
func claim_manifest_for_provider() -> ChunkManifest:
	if _status != STATUS_STAGED or _candidate_manifest == null:
		return null
	_manifest_claimed = true
	_status = STATUS_MANIFEST_CLAIMED
	return _candidate_manifest.duplicate_manifest()


## 获取最终已提交 Manifest；只有主 GF generation 已知成功时可用。
func get_committed_manifest() -> ChunkManifest:
	return (
		_candidate_manifest.duplicate_manifest()
		if _status == STATUS_COMMITTED and _candidate_manifest != null
		else null
	)


## 获取本 lease staging 时观察到的上一 active bank。
##
## 仅供 persistence Module 在 exact commit 后派生旧 bank 回收范围；值从
## Provider 已验证 Manifest 或同 scope exact commit basis 获得。
func get_previous_active_bank_for_utility() -> StringName:
	return _offered_active_bank


## 获取已 staging 或已知失败 staging 的候选 Manifest 副本。
##
## 该证据只供 persistence Module 在 exact commit/known failure 后构造严格
## logical family cleanup；outcome-unknown 未对账时调用方不得据此回收。
func get_cleanup_manifest_for_utility() -> ChunkManifest:
	if _candidate_manifest != null:
		return _candidate_manifest.duplicate_manifest()
	if _stage_result != null:
		return _stage_result.get_manifest()
	return null


## 查询候选 bank 是否已有足够的 known-terminal 证据允许回收。
##
## 已绑定但尚未结算的主 save 仍可能发布 Manifest，因此即使调用方误把 lease
## 标成失败也不得清理候选 bank。
func is_candidate_cleanup_known_safe_for_utility() -> bool:
	return (
		_status in [STATUS_FAILED, STATUS_CANCELLED]
		and _stage_result != null
		and not _known_stage_main_outcome_unknown
		and (_main_operation == null or _main_result != null)
	)


## 查询已知 staging 终态是否仍被已绑定 main operation 的物理终态阻塞。
##
## Utility 必须继续持有 lease/scope；否则 main 迟到后将失去 candidate cleanup
## identity，或在 main 仍可能发布时过早删除 candidate bank。
func is_waiting_for_bound_main_terminal_for_utility() -> bool:
	return (
		_known_stage_terminal_status in [STATUS_FAILED, STATUS_CANCELLED]
		and _main_operation != null
		and (_main_result == null or _known_stage_main_outcome_unknown)
	)


## 获取主 Profile 终态证据副本。
func get_main_result() -> GFSaveProfileResult:
	return _main_result.duplicate_result() if _main_result != null else null


# --- persistence Module 方法 ---

## Module 在 Provider callback 外一次性取得 staging request。
##
## expected_basis_epoch 为 0 表示当前 scope 尚无本进程内的已知提交推进；此时
## active bank 仍由 Provider 已校验的 Manifest 提供。正 epoch 必须与 Utility
## 在同一 owner 临界区内传播的 bank/epoch 完全一致，随后才 claim payload。
## @param expected_active_bank: Utility 当前 scope basis 的 active bank。
## @param expected_basis_epoch: Utility 当前 scope basis 的单调 epoch。
func take_stage_request_for_utility(
	expected_active_bank: StringName = ChunkManifest.BANK_NONE,
	expected_basis_epoch: int = 0
) -> ChunkStageRequest:
	if not is_ready_to_stage() or _stage_request_claimed:
		return null
	if expected_basis_epoch < 0:
		return null
	if expected_basis_epoch == 0:
		if _scope_basis_epoch != 0:
			return null
	elif (
		expected_active_bank not in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]
		or _scope_basis_epoch != expected_basis_epoch
		or _scope_basis_bank != expected_active_bank
		or _offered_active_bank != expected_active_bank
	):
		return null
	_stage_request_claimed = true
	var owned_chunks: Array[PackedByteArray] = _offered_chunks
	_offered_chunks = []
	var request: ChunkStageRequest = ChunkStageRequest.create(
		_chunk_profile_prefix,
		_section_id,
		_section_schema_version,
		_offered_active_bank,
		owned_chunks
	)
	if request == null:
		var _failed_request: bool = _fail_for_utility(
			ERR_INVALID_DATA,
			"Provider chunks could not create a strict stage request."
		)
		return null
	_status = STATUS_STAGING
	return request


## 在 staging claim 前把 lease 重基线到同 scope 最新 exact commit。
##
## 本方法只替换两个标量，不遍历、不复制也不释放 chunks。相同 epoch/bank 的
## 重复传播幂等；旧 epoch、bank 冲突或已开始 staging 时拒绝。
## @param active_bank: 最新 exact commit 对应的 active bank。
## @param basis_epoch: Utility 为该 exact commit 分配的正数 epoch。
func rebase_scope_basis_for_utility(
	active_bank: StringName,
	basis_epoch: int
) -> bool:
	if (
		active_bank not in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]
		or basis_epoch <= 0
		or _stage_request_claimed
		or _status not in [STATUS_WAITING_FOR_PROVIDER, STATUS_READY_TO_STAGE]
		or basis_epoch < _scope_basis_epoch
	):
		return false
	if basis_epoch == _scope_basis_epoch:
		return _scope_basis_bank == active_bank
	_scope_basis_bank = active_bank
	_scope_basis_epoch = basis_epoch
	if _status == STATUS_READY_TO_STAGE:
		_offered_active_bank = active_bank
	return true


## 校验 lease 是否已观察到 Utility 当前 scope basis。
## @param active_bank: Utility 当前 scope basis 的 active bank。
## @param basis_epoch: Utility 当前 scope basis 的 epoch；零表示尚无推进。
func matches_scope_basis_for_utility(
	active_bank: StringName,
	basis_epoch: int
) -> bool:
	if basis_epoch == 0:
		return _scope_basis_epoch == 0
	return (
		basis_epoch > 0
		and active_bank in [ChunkManifest.BANK_A, ChunkManifest.BANK_B]
		and _scope_basis_epoch == basis_epoch
		and _scope_basis_bank == active_bank
		and (
			_status == STATUS_WAITING_FOR_PROVIDER
			or _offered_active_bank == active_bank
		)
	)


## Module 绑定底层 staging operation。
## @param operation: 已接纳当前 lease request 的唯一 staging operation。
func bind_stage_operation_for_utility(operation: ChunkStageOperation) -> bool:
	if _status != STATUS_STAGING or _stage_operation != null or operation == null:
		return false
	_stage_operation = operation
	return true


## Module 收敛 staging 终态。
## @param result: 与当前 staging operation 对应的唯一终态结果。
func settle_stage_for_utility(result: ChunkStageResult) -> bool:
	if _status != STATUS_STAGING or _stage_result != null or result == null:
		return false
	_stage_result = result.duplicate_result()
	if result.is_successful():
		_candidate_manifest = result.get_manifest()
		if (
			_candidate_manifest == null
			or _candidate_manifest.get_section_id() != _section_id
			or _candidate_manifest.get_section_schema_version()
			!= _section_schema_version
		):
			var _failed_manifest: bool = _fail_for_utility(
				ERR_INVALID_DATA,
				"Staged Manifest does not match its save lease."
			)
			return false
		_status = STATUS_STAGED
		return true
	if result.get_status() == ChunkStageResult.STATUS_OUTCOME_UNKNOWN:
		_stage_outcome_unknown = true
		_status = STATUS_OUTCOME_UNKNOWN
	else:
		_status = (
			STATUS_CANCELLED
			if result.get_status() == ChunkStageResult.STATUS_CANCELLED
			else STATUS_FAILED
		)
	_error_code = result.get_error_code()
	_error = result.get_error()
	if _status in [STATUS_FAILED, STATUS_CANCELLED]:
		_remember_known_stage_terminal()
	return true


## 使用 exact failed chunk Profile 的 GF public snapshot 解除 stage fence。
##
## 只有快照证明该 Profile 已 idle，且 unknown generation 与 detached
## 写入全部清空时，stage outcome-unknown 才能收敛为已知失败。
## 本路径永不提交 Manifest，也不保留 evidence 或 payload。
##
## @param evidence: failed chunk Profile 的当次 GF public state snapshot。
## @return 首次安全解除 stage fence 时返回 true。
## @schema evidence: GFSaveProfileUtility.get_profile_state_snapshot() result.
func reconcile_stage_outcome_for_utility(evidence: Dictionary) -> bool:
	if (
		_status != STATUS_OUTCOME_UNKNOWN
		or not _stage_outcome_unknown
		or _stage_result == null
		or not _is_settled_stage_snapshot(evidence)
	):
		return false
	var profile_result: GFSaveProfileResult = _stage_result.get_profile_result()
	_stage_outcome_unknown = false
	_candidate_manifest = null
	_manifest_claimed = false
	_status = STATUS_FAILED
	_error_code = profile_result.get_error_code()
	if _error_code == OK:
		_error_code = ERR_CANT_CREATE
	_error = "Chunk Profile outcome-unknown reconciled without a visible Manifest."
	_remember_known_stage_terminal()
	if (
		_main_result != null
		and _main_result.get_status()
		== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	):
		_known_stage_main_outcome_unknown = true
		_status = STATUS_OUTCOME_UNKNOWN
		_error_code = _main_result.get_error_code()
		_error = _main_result.get_error()
	return true


## Module 以真实主 GF Profile result 收敛可见性。
## @param result: 与已绑定主 save operation 对应的真实 GF 结果。
func settle_main_result_for_utility(result: GFSaveProfileResult) -> bool:
	if (
		_main_operation == null
		or _main_result != null
		or result == null
		or not _main_operation.is_completed()
		or result.get_operation() != GFSaveProfileOperation.OPERATION_SAVE
		or result.get_profile_id() != _main_profile_id
		or result.get_requested_generation() != _main_requested_generation
	):
		return false
	var operation_result: GFSaveProfileResult = _main_operation.get_result()
	if (
		operation_result == null
		or operation_result.get_operation()
		!= GFSaveProfileOperation.OPERATION_SAVE
		or operation_result.get_profile_id() != _main_profile_id
		or operation_result.get_requested_generation()
		!= _main_requested_generation
		or operation_result.to_dict() != result.to_dict()
	):
		return false
	_main_result = operation_result.duplicate_result()
	if _stage_outcome_unknown:
		return true
	if _known_stage_terminal_status in [STATUS_FAILED, STATUS_CANCELLED]:
		if (
			operation_result.get_status()
			== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		):
			_known_stage_main_outcome_unknown = true
			_status = STATUS_OUTCOME_UNKNOWN
			_error_code = operation_result.get_error_code()
			_error = operation_result.get_error()
		else:
			_restore_known_stage_terminal()
		return true
	if _status == STATUS_OUTCOME_UNKNOWN:
		return true
	if operation_result.get_status() == GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN:
		_status = STATUS_OUTCOME_UNKNOWN
		_error_code = operation_result.get_error_code()
		_error = operation_result.get_error()
		return true
	if (
		operation_result.is_successful()
		and operation_result.get_status() == GFSaveProfileResult.STATUS_SAVED
		and (
			operation_result.was_coalesced()
			or operation_result.get_persisted_generation()
			> _main_requested_generation
		)
	):
		_status = STATUS_SUPERSEDED
		_error_code = OK
		_error = ""
		return true
	if (
		operation_result.is_successful()
		and operation_result.get_status() == GFSaveProfileResult.STATUS_SAVED
		and operation_result.get_persisted_generation()
		== _main_requested_generation
		and _manifest_claimed
		and _candidate_manifest != null
	):
		_status = STATUS_COMMITTED
		_error_code = OK
		_error = ""
		return true
	_status = STATUS_FAILED
	_error_code = (
		operation_result.get_error_code()
		if operation_result.get_error_code() != OK
		else ERR_INVALID_DATA
	)
	_error = operation_result.get_error().strip_edges()
	if _error.is_empty():
		_error = "Main Profile did not commit the staged Manifest."
	return true


## 使用 GF public Profile state snapshot 收敛主写入的迟到结果。
##
## evidence 必须是对应 main_profile_id 的
## GFSaveProfileUtility.get_profile_state_snapshot() 当次返回值。本方法
## 只读取必要的有界字段，不保留 evidence 或任何 payload。
##
## @param persisted: 快照是否证明目标 generation 已持久化。
## @param persisted_generation: 快照中的 persisted_generation。
## @param evidence: GF public Profile state snapshot。
## @return 首次安全收敛 main outcome-unknown 时返回 true。
## @schema evidence: GFSaveProfileUtility.get_profile_state_snapshot() result.
func reconcile_main_outcome_for_utility(
	persisted: bool,
	persisted_generation: int,
	evidence: Dictionary = {}
) -> bool:
	if (
		_status != STATUS_OUTCOME_UNKNOWN
		or _stage_outcome_unknown
		or _main_result == null
		or _main_result.get_status()
		!= GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		or not _is_settled_main_snapshot(evidence, persisted_generation)
	):
		return false
	if _known_stage_main_outcome_unknown:
		_known_stage_main_outcome_unknown = false
		_restore_known_stage_terminal()
		return true
	if persisted:
		if persisted_generation > _main_requested_generation:
			_status = STATUS_SUPERSEDED
			_error_code = OK
			_error = ""
			return true
		if (
			persisted_generation != _main_requested_generation
			or not _manifest_claimed
			or _candidate_manifest == null
		):
			return false
		_status = STATUS_COMMITTED
		_error_code = OK
		_error = ""
		return true
	if persisted_generation >= _main_requested_generation:
		return false
	_status = STATUS_FAILED
	_error_code = ERR_CANT_CREATE
	_error = "Main Profile outcome-unknown reconciled without persistence."
	return true


## Module 在启动 staging 前终结无效 lease。
## @param error_code: 已知失败的非 OK Error 码。
## @param error: 不含业务载荷的稳定错误摘要。
func fail_for_utility(error_code: Error, error: String) -> bool:
	return _fail_for_utility(error_code, error)


# --- 私有/辅助方法 ---

static func _is_bounded_text(value: String) -> bool:
	return (
		not value.is_empty()
		and value == value.strip_edges()
		and value.length() <= _MAX_ID_LENGTH
		and not value.contains("\n")
		and not value.contains("\r")
	)


func _is_settled_stage_snapshot(evidence: Dictionary) -> bool:
	var profile_result: GFSaveProfileResult = _stage_result.get_profile_result()
	if (
		profile_result == null
		or profile_result.get_operation()
		!= GFSaveProfileOperation.OPERATION_SAVE
		or profile_result.get_status()
		!= GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
		or _stage_result.get_failed_chunk_index() < 0
	):
		return false
	var profile_id_value: Variant = evidence.get("profile_id")
	var state_value: Variant = evidence.get("state")
	var write_unknown_value: Variant = evidence.get("write_outcome_unknown")
	var unknown_generations_value: Variant = evidence.get(
		"unknown_write_generations"
	)
	var detached_count_value: Variant = evidence.get("detached_write_count")
	var detached_request_ids_value: Variant = evidence.get(
		"detached_storage_request_ids"
	)
	if not profile_id_value is StringName:
		return false
	var snapshot_profile_id: StringName = profile_id_value
	if not state_value is StringName:
		return false
	var snapshot_state: StringName = state_value
	if not write_unknown_value is bool:
		return false
	var snapshot_write_unknown: bool = write_unknown_value
	if not unknown_generations_value is PackedInt64Array:
		return false
	var unknown_generations: PackedInt64Array = unknown_generations_value
	if not detached_count_value is int:
		return false
	var detached_count: int = detached_count_value
	if not detached_request_ids_value is PackedInt64Array:
		return false
	var detached_request_ids: PackedInt64Array = detached_request_ids_value
	return (
		snapshot_profile_id == profile_result.get_profile_id()
		and snapshot_state == GFSaveProfileUtility.STATE_IDLE
		and not snapshot_write_unknown
		and unknown_generations.is_empty()
		and detached_count == 0
		and detached_request_ids.is_empty()
	)


func _is_settled_main_snapshot(
	evidence: Dictionary,
	persisted_generation: int
) -> bool:
	var profile_id_value: Variant = evidence.get("profile_id")
	var persisted_generation_value: Variant = evidence.get(
		"persisted_generation"
	)
	var write_unknown_value: Variant = evidence.get("write_outcome_unknown")
	var unknown_generations_value: Variant = evidence.get(
		"unknown_write_generations"
	)
	var detached_count_value: Variant = evidence.get("detached_write_count")
	var detached_request_ids_value: Variant = evidence.get(
		"detached_storage_request_ids"
	)
	if not profile_id_value is StringName:
		return false
	var snapshot_profile_id: StringName = profile_id_value
	if not persisted_generation_value is int:
		return false
	var snapshot_persisted_generation: int = persisted_generation_value
	if not write_unknown_value is bool:
		return false
	var snapshot_write_unknown: bool = write_unknown_value
	if not unknown_generations_value is PackedInt64Array:
		return false
	var unknown_generations: PackedInt64Array = unknown_generations_value
	if not detached_count_value is int:
		return false
	var detached_count: int = detached_count_value
	if not detached_request_ids_value is PackedInt64Array:
		return false
	var detached_request_ids: PackedInt64Array = detached_request_ids_value
	if (
		snapshot_profile_id != _main_profile_id
		or snapshot_persisted_generation != persisted_generation
		or snapshot_write_unknown
		or detached_count != 0
	):
		return false
	return unknown_generations.is_empty() and detached_request_ids.is_empty()


func _fail_for_utility(error_code: Error, error: String) -> bool:
	if is_terminal():
		return false
	_offered_chunks = []
	_status = STATUS_FAILED
	_error_code = error_code if error_code != OK else FAILED
	_error = error.strip_edges()
	if _error.is_empty():
		_error = "Chunk save lease failed."
	return true


func _remember_known_stage_terminal() -> void:
	if _status not in [STATUS_FAILED, STATUS_CANCELLED]:
		return
	_known_stage_terminal_status = _status
	_known_stage_terminal_error_code = _error_code
	_known_stage_terminal_error = _error


func _restore_known_stage_terminal() -> void:
	_status = _known_stage_terminal_status
	_error_code = _known_stage_terminal_error_code
	_error = _known_stage_terminal_error
