## manifest-backed 大型 section 的公共 GF Provider 基类。
##
## 子类仍拥有业务编码与严格校验；本类只统一主 Profile 中的 Manifest 形状、
## MaterializationLease 单次移交、回滚快照和已提交 revision。chunk 文件与 GF
## Profile generation 的编排由 ChunkProfileUtility / GameSaveGraphUtility 拥有。
class_name ManifestBackedSaveSectionProvider
extends GFSaveSectionProvider


# --- 常量 ---

## 主 Profile save context 中按 section_id 索引的 ChunkSaveLease。
const SAVE_LEASES_CONTEXT_KEY: StringName = &"chunk_save_leases"

## 主 Profile load context 中按 section_id 索引的 MaterializationLease。
const LOAD_LEASES_CONTEXT_KEY: StringName = &"chunk_materialization_leases"

## 内部 preflight 绑定的主 Profile 逻辑身份。
const LOAD_MAIN_PROFILE_ID_CONTEXT_KEY: StringName = &"chunk_main_profile_id"

## 内部 preflight 绑定的主 Profile 规范文件名。
const LOAD_CANONICAL_FILE_CONTEXT_KEY: StringName = &"chunk_profile_file_name"

const _ROLLBACK_MANIFEST_KEY: StringName = &"chunk_active_manifest"
const _ROLLBACK_REVISION_KEY: StringName = &"chunk_revision"
const _ROLLBACK_COMMITTED_REVISION_KEY: StringName = (
	&"chunk_committed_revision"
)
const _ROLLBACK_ROOT_SENTINEL_KEY: StringName = &"chunk_shallow_root"


# --- 私有变量 ---

var _active_manifest: ChunkManifest = null
var _producer_revision: int = 0
var _committed_revision: int = -1


# --- 公共方法 ---

## 获取当前业务候选 revision。
func get_producer_revision() -> int:
	return _producer_revision


## 查询当前业务 revision 是否还没有对应的已提交 Manifest。
func needs_chunk_stage() -> bool:
	return (
		_active_manifest == null
		or _committed_revision != _producer_revision
	)


## 获取当前主 Profile 已知提交的 Manifest。
func get_active_manifest() -> ChunkManifest:
	return (
		_active_manifest.duplicate_manifest()
		if _active_manifest != null
		else null
	)


## 由 SaveGraph 在业务 Provider 成功替换当前值后标记 dirty。
func mark_business_data_changed() -> void:
	_producer_revision += 1


## 捕获跨账号切换失败时恢复所需的无业务载荷运行时状态。
func make_manifest_runtime_state_snapshot() -> Dictionary:
	return {
		&"manifest": (
			_active_manifest.to_dict()
			if _active_manifest != null
			else {}
		),
		&"producer_revision": _producer_revision,
		&"committed_revision": _committed_revision,
	}


## 恢复先前捕获的 Manifest/revision 状态；不触碰业务 Provider。
## @param snapshot: make_manifest_runtime_state_snapshot() 返回的严格三字段快照。
func restore_manifest_runtime_state(snapshot: Dictionary) -> Error:
	if snapshot.size() != 3:
		return ERR_INVALID_DATA
	var manifest_value: Variant = snapshot.get(&"manifest")
	var producer_value: Variant = snapshot.get(&"producer_revision")
	var committed_value: Variant = snapshot.get(&"committed_revision")
	if (
		not manifest_value is Dictionary
		or not producer_value is int
		or not committed_value is int
	):
		return ERR_INVALID_DATA
	var producer_revision: int = producer_value
	var committed_revision: int = committed_value
	if (
		producer_revision < 0
		or committed_revision < -1
		or committed_revision > producer_revision
	):
		return ERR_INVALID_DATA
	var manifest_payload: Dictionary = manifest_value
	var manifest: ChunkManifest = null
	if not manifest_payload.is_empty():
		manifest = ChunkManifest.from_dict(manifest_payload)
		if (
			manifest == null
			or manifest.get_section_id() != section_id
			or manifest.get_section_schema_version() != schema_version
			or committed_revision < 0
		):
			return ERR_INVALID_DATA
	elif committed_revision != -1:
		return ERR_INVALID_DATA
	_active_manifest = manifest
	_producer_revision = producer_revision
	_committed_revision = committed_revision
	return OK


## 切入尚未加载/首次创建的主 Profile 前清除上一账号 Manifest 所有权。
func reset_manifest_runtime_state() -> void:
	_active_manifest = null
	_producer_revision = 0
	_committed_revision = -1


## 在 GF Provider callback 外把已校验 chunks 解码为一次性业务物化 Lease。
##
## 调用方无论成功或失败都必须放弃 chunks 数组及其元素 alias；具体 codec 与
## 业务 schema 仍由 Feature 子类拥有。
## @param chunks: 按 Manifest 顺序移交唯一所有权的 chunk bytes。
## @param manifest: 已校验且与当前 Provider identity 匹配的 Manifest。
## @param main_profile_id: 当前 load context 的可信主 Profile ID。
## @param canonical_file_name: 当前 load context 的规范主 Profile 文件名。
func make_materialization_lease_taking_ownership(
	chunks: Array[PackedByteArray],
	manifest: ChunkManifest,
	main_profile_id: StringName,
	canonical_file_name: String
) -> ChunkMaterializationLease:
	if (
		chunks.is_empty()
		or chunks.size() > ChunkManifest.MAX_CHUNK_COUNT
		or not _manifest_matches_provider(manifest)
	):
		chunks.clear()
		return null
	var payload_value: Variant = (
		_decode_materialized_chunks_taking_ownership(chunks)
	)
	if typeof(payload_value) == TYPE_NIL:
		return null
	return ChunkMaterializationLease.take_ownership(
		payload_value,
		manifest,
		main_profile_id,
		canonical_file_name
	)


## 在 GF Provider callback 外可推进地创建一次性业务物化 Lease。
##
## 默认 Provider 复用同步 codec；大型 Feature 可重写为逐 frame 解码并在每批
## 之间让出 process_frame。continue_check 失效时必须放弃全部输入与中间状态。
## @param chunks: 按 Manifest 顺序移交唯一所有权的 chunk bytes。
## @param manifest: 已校验且与当前 Provider identity 匹配的 Manifest。
## @param main_profile_id: 当前 load context 的可信主 Profile ID。
## @param canonical_file_name: 当前 load context 的规范主 Profile 文件名。
## @param continuation_lease: 可选的 load context 生命周期门闩。
func make_materialization_lease_async_taking_ownership(
	chunks: Array[PackedByteArray],
	manifest: ChunkManifest,
	main_profile_id: StringName,
	canonical_file_name: String,
	continuation_lease: GFAsyncGateLease = null
) -> ChunkMaterializationLease:
	if (
		not _materialization_can_continue(continuation_lease)
		or not _manifest_matches_provider(manifest)
	):
		chunks.clear()
		return null
	# 保持基类入口为真实 coroutine，使调用方可以强类型 await；默认 codec
	# 只让出一次后立即复用同步路径，不引入第二套物化实现。
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		await tree.process_frame
	if not _materialization_can_continue(continuation_lease):
		chunks.clear()
		return null
	return make_materialization_lease_taking_ownership(
		chunks,
		manifest,
		main_profile_id,
		canonical_file_name
	)


## 主 GF Profile generation 已知成功后提交候选 Manifest。
##
## @param manifest: 本次主 section 实际写入的候选 Manifest。
## @param producer_revision: 创建对应 ChunkSaveLease 时冻结的 revision。
## @return 身份匹配且不会越过更新业务 revision 时返回 true。
func commit_candidate_manifest(
	manifest: ChunkManifest,
	producer_revision: int
) -> bool:
	if (
		manifest == null
		or not manifest.is_valid()
		or manifest.get_section_id() != section_id
		or manifest.get_section_schema_version() != schema_version
		or producer_revision < 0
		or producer_revision > _producer_revision
	):
		return false
	_active_manifest = manifest.duplicate_manifest()
	_committed_revision = producer_revision
	return _active_manifest != null


## 从 save context 取得属于当前 section/revision 的 lease。
##
## @param context: 当前 GF Provider save context。
## @return 匹配时返回原 opaque lease；不匹配时返回 null。
func get_save_lease(context: Dictionary) -> ChunkSaveLease:
	var leases_value: Variant = context.get(SAVE_LEASES_CONTEXT_KEY)
	if not leases_value is Dictionary:
		return null
	var leases: Dictionary = leases_value
	var lease_value: Variant = leases.get(section_id)
	if not lease_value is ChunkSaveLease:
		return null
	var lease: ChunkSaveLease = lease_value
	if (
		lease.get_section_id() != section_id
		or lease.get_section_schema_version() != schema_version
		or lease.get_producer_revision() != _producer_revision
	):
		return null
	return lease


# --- 可重写钩子（GFSaveSectionProvider） ---

func _capture_section(context: Dictionary = {}) -> GFSaveSection:
	var payload: Dictionary = {}
	if _uses_context_shallow_rollback_root():
		var materialization: ChunkMaterializationLease = (
			_get_materialization_lease(context)
		)
		if materialization == null:
			return null
		var rollback_root: Variant = _capture_shallow_rollback_root()
		if (
			typeof(rollback_root) == TYPE_NIL
			or not materialization.stage_rollback_root_taking_ownership(
				rollback_root,
				_get_load_main_profile_id(context),
				_get_load_canonical_file_name(context),
				section_id,
				schema_version
			)
		):
			return null
		payload = {_ROLLBACK_ROOT_SENTINEL_KEY: true}
	else:
		payload = _capture_business_payload()
	var metadata: Dictionary = {
		_ROLLBACK_REVISION_KEY: _producer_revision,
		_ROLLBACK_COMMITTED_REVISION_KEY: _committed_revision,
	}
	if _active_manifest != null:
		metadata[_ROLLBACK_MANIFEST_KEY] = _active_manifest.to_dict()
	return make_section(payload, metadata)


func _apply_section(
	section: GFSaveSection,
	context: Dictionary = {}
) -> Error:
	if section == null:
		return ERR_INVALID_DATA
	var manifest_value: Variant = section.get_payload()
	if not manifest_value is Dictionary:
		return ERR_INVALID_DATA
	var manifest: ChunkManifest = ChunkManifest.from_dict(
		GFVariantData.as_dictionary(manifest_value)
	)
	if (
		manifest == null
		or manifest.get_section_id() != section_id
		or manifest.get_section_schema_version() != schema_version
	):
		return ERR_INVALID_DATA
	var materialization: ChunkMaterializationLease = (
		_get_materialization_lease(context)
	)
	if materialization == null:
		return ERR_UNAVAILABLE
	var materialized_value: Variant = materialization.claim_for_manifest(
		manifest,
		_get_load_main_profile_id(context),
		_get_load_canonical_file_name(context),
		section_id,
		schema_version
	)
	if typeof(materialized_value) == TYPE_NIL:
		return ERR_INVALID_DATA
	var apply_error: Error = _apply_materialized_payload(materialized_value)
	if apply_error != OK:
		return apply_error
	_active_manifest = manifest.duplicate_manifest()
	if _active_manifest == null:
		return ERR_INVALID_DATA
	_producer_revision += 1
	_committed_revision = _producer_revision
	return OK


func _rollback_section(
	previous_section: GFSaveSection,
	context: Dictionary = {}
) -> Error:
	if (
		previous_section == null
		or previous_section.get_section_id() != section_id
		or previous_section.get_schema_version() != schema_version
	):
		return ERR_INVALID_DATA
	var previous_value: Variant = previous_section.get_payload()
	if not previous_value is Dictionary:
		return ERR_INVALID_DATA
	var previous_payload: Dictionary = GFVariantData.as_dictionary(previous_value)
	var rollback_state: Dictionary = _parse_rollback_runtime_state(
		previous_section.get_metadata()
	)
	if not GFVariantData.get_option_bool(rollback_state, &"ok", false):
		return ERR_INVALID_DATA
	# 所有 section identity、revision 与 Manifest 约束都必须在 claim/业务
	# root 交换前完成；畸形 rollback 因而不消费 lease，可用合法 section 重试。
	var restore_error: Error = OK
	if _is_shallow_rollback_sentinel(previous_payload):
		var materialization: ChunkMaterializationLease = (
			_get_materialization_lease(context)
		)
		if materialization == null:
			return ERR_UNAVAILABLE
		var rollback_root: Variant = (
			materialization.claim_rollback_root_for_authority(
				_get_load_main_profile_id(context),
				_get_load_canonical_file_name(context),
				section_id,
				schema_version
			)
		)
		if typeof(rollback_root) == TYPE_NIL:
			return ERR_INVALID_DATA
		restore_error = _restore_shallow_rollback_root(rollback_root)
	else:
		restore_error = _restore_business_payload(previous_payload)
	if restore_error != OK:
		return restore_error
	var manifest_value: Variant = rollback_state.get(&"manifest")
	_active_manifest = (
		manifest_value
		if manifest_value is ChunkManifest
		else null
	)
	_producer_revision = GFVariantData.get_option_int(
		rollback_state,
		&"producer_revision"
	)
	_committed_revision = GFVariantData.get_option_int(
		rollback_state,
		&"committed_revision"
	)
	return OK


## 子类捕获当前业务 Provider 的回滚 payload。
func _capture_business_payload() -> Dictionary:
	return {}


## 子类应用已经由 chunk codec 严格解码的业务 payload。
func _apply_materialized_payload(_payload: Variant) -> Error:
	return ERR_UNAVAILABLE


## 子类恢复应用前业务 payload；默认复用正常应用入口。
func _restore_business_payload(payload: Dictionary) -> Error:
	return _apply_materialized_payload(payload)


## 子类声明 rollback 根只暂存在本次 materialization lease 中。
func _uses_context_shallow_rollback_root() -> bool:
	return false


## 子类捕获只复制有限容器根、不复制嵌套业务对象的回滚状态。
func _capture_shallow_rollback_root() -> Variant:
	return null


## 子类接管先前浅层根并恢复业务状态。
func _restore_shallow_rollback_root(_root: Variant) -> Error:
	return ERR_UNAVAILABLE


## 子类在主 Profile load 之前、Provider callback 外严格解码 chunks。
func _decode_materialized_chunks_taking_ownership(
	_chunks: Array[PackedByteArray]
) -> Variant:
	return null


## 查询异步物化请求是否仍属于当前外部事务。
static func _materialization_can_continue(
	continuation_lease: GFAsyncGateLease
) -> bool:
	return continuation_lease == null or continuation_lease.is_active()


# --- 私有/辅助方法 ---

func _get_materialization_lease(
	context: Dictionary
) -> ChunkMaterializationLease:
	if not _has_valid_load_authority(context):
		return null
	var leases_value: Variant = context.get(LOAD_LEASES_CONTEXT_KEY)
	if not leases_value is Dictionary:
		return null
	var leases: Dictionary = leases_value
	var lease_value: Variant = leases.get(section_id)
	if lease_value is ChunkMaterializationLease:
		var lease: ChunkMaterializationLease = lease_value
		if lease.matches_authority(
			_get_load_main_profile_id(context),
			_get_load_canonical_file_name(context),
			section_id,
			schema_version
		):
			return lease
	return null


func _manifest_matches_provider(manifest: ChunkManifest) -> bool:
	return (
		manifest != null
		and manifest.is_valid()
		and manifest.get_section_id() == section_id
		and manifest.get_section_schema_version() == schema_version
	)


func _has_valid_load_authority(context: Dictionary) -> bool:
	return (
		context.get(LOAD_MAIN_PROFILE_ID_CONTEXT_KEY) is StringName
		and _get_load_main_profile_id(context) != &""
		and context.get(LOAD_CANONICAL_FILE_CONTEXT_KEY) is String
		and not _get_load_canonical_file_name(context).is_empty()
	)


func _get_load_main_profile_id(context: Dictionary) -> StringName:
	var value: Variant = context.get(LOAD_MAIN_PROFILE_ID_CONTEXT_KEY)
	return value if value is StringName else &""


func _get_load_canonical_file_name(context: Dictionary) -> String:
	var value: Variant = context.get(LOAD_CANONICAL_FILE_CONTEXT_KEY)
	return value if value is String else ""


static func _is_shallow_rollback_sentinel(payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get(_ROLLBACK_ROOT_SENTINEL_KEY) is bool
		and GFVariantData.get_option_bool(
			payload,
			_ROLLBACK_ROOT_SENTINEL_KEY,
			false
		)
	)


## 完整解析且验证 rollback runtime metadata；本方法不消费任何 lease/root。
func _parse_rollback_runtime_state(metadata: Dictionary) -> Dictionary:
	var expected_size: int = 3 if metadata.has(_ROLLBACK_MANIFEST_KEY) else 2
	if metadata.size() != expected_size:
		return {&"ok": false}
	var producer_value: Variant = metadata.get(_ROLLBACK_REVISION_KEY)
	var committed_value: Variant = metadata.get(
		_ROLLBACK_COMMITTED_REVISION_KEY
	)
	if not producer_value is int or not committed_value is int:
		return {&"ok": false}
	var producer_revision: int = producer_value
	var committed_revision: int = committed_value
	if (
		producer_revision < 0
		or committed_revision < -1
		or committed_revision > producer_revision
	):
		return {&"ok": false}
	var restored_manifest: ChunkManifest = null
	if metadata.has(_ROLLBACK_MANIFEST_KEY):
		var manifest_value: Variant = metadata.get(_ROLLBACK_MANIFEST_KEY)
		if not manifest_value is Dictionary:
			return {&"ok": false}
		restored_manifest = ChunkManifest.from_dict(
			GFVariantData.as_dictionary(manifest_value)
		)
		if (
			restored_manifest == null
			or restored_manifest.get_section_id() != section_id
			or restored_manifest.get_section_schema_version() != schema_version
			or committed_revision < 0
		):
			return {&"ok": false}
	elif committed_revision != -1:
		return {&"ok": false}
	return {
		&"ok": true,
		&"manifest": restored_manifest,
		&"producer_revision": producer_revision,
		&"committed_revision": committed_revision,
	}
