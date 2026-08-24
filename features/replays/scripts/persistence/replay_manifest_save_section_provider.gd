## replays 目录的 manifest-backed GF Profile Provider。
##
## 主 Profile section 只保存 schema 8 ChunkManifest。业务 schema 6 仍由
## ReplayCatalogSaveData 拥有并执行严格 replace；chunk staging 与主 generation
## 可见性由外部 persistence owner 通过 ChunkSaveLease 编排。
class_name ReplayManifestSaveSectionProvider
extends ManifestBackedSaveSectionProvider


# --- 常量 ---

const PERSISTENCE_SCHEMA_VERSION: int = 8

## 每次 process_frame 最多解码的有界 replay frame 数。
const MATERIALIZATION_FRAMES_PER_PROCESS_FRAME: int = 16


# --- 私有变量 ---

var _business_provider: ReplayCatalogSaveData = null


# --- Godot 生命周期方法 ---

func _init(business_provider: ReplayCatalogSaveData = null) -> void:
	section_id = &"replays"
	schema_version = PERSISTENCE_SCHEMA_VERSION
	_business_provider = (
		business_provider
		if business_provider != null
		else ReplayCatalogSaveData.new()
	)


# --- 公共方法 ---

## 获取被包装的业务 Provider。
func get_business_provider() -> ReplayCatalogSaveData:
	return _business_provider


## 生产加载使用逐 frame 解码器，避免在单帧同步扫描完整 replay stream。
## @param chunks: 移交所有权的规范 replay stream 分块。
## @param manifest: 已通过主 Profile 身份绑定校验的分块清单。
## @param main_profile_id: 当前主 Profile 的稳定逻辑 ID。
## @param canonical_file_name: 当前主 Profile 的规范文件名。
## @param continuation_lease: 可选的异步继续执行授权。
func make_materialization_lease_async_taking_ownership(
	chunks: Array[PackedByteArray],
	manifest: ChunkManifest,
	main_profile_id: StringName,
	canonical_file_name: String,
	continuation_lease: GFAsyncGateLease = null
) -> ChunkMaterializationLease:
	if (
		chunks.is_empty()
		or chunks.size() > ChunkManifest.MAX_CHUNK_COUNT
		or not _manifest_matches_provider(manifest)
		or not _materialization_can_continue(continuation_lease)
	):
		chunks.clear()
		return null
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.begin_decode(chunks)
	# decoder 已接管独立数组根；调用方的根从这里起不可再用。
	chunks.clear()
	if decoder == null:
		return null
	var main_loop: MainLoop = Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null
	var tree: SceneTree = main_loop
	while not decoder.is_complete() and not decoder.is_failed():
		if not _materialization_can_continue(continuation_lease):
			return null
		var consumed_units: int = decoder.advance(
			MATERIALIZATION_FRAMES_PER_PROCESS_FRAME
		)
		if decoder.is_failed() or consumed_units <= 0:
			return null
		if not decoder.is_complete():
			await tree.process_frame
	if (
		decoder.is_failed()
		or not decoder.is_complete()
		or not _materialization_can_continue(continuation_lease)
	):
		return null
	var prepared_state: ReplayCatalogPreparedState = (
		decoder.take_prepared_state_taking_ownership()
	)
	if prepared_state == null:
		return null
	return ChunkMaterializationLease.take_ownership(
		prepared_state,
		manifest,
		main_profile_id,
		canonical_file_name
	)


# --- 可重写钩子 ---

func _begin_save_snapshot(
	context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	if not _is_business_provider_valid():
		return null
	var lease: ChunkSaveLease = get_save_lease(context)
	if lease == null:
		if needs_chunk_stage():
			return null
		var active_manifest: ChunkManifest = get_active_manifest()
		if active_manifest == null:
			return null
		return make_completed_snapshot(active_manifest.to_dict())
	if lease.get_status() != ChunkSaveLease.STATUS_WAITING_FOR_PROVIDER:
		return null
	var source: ReplayChunkSourceSnapshot = (
		_business_provider.make_chunk_source_snapshot()
	)
	var codec: ReplayChunkCodec = ReplayChunkCodec.begin_encode(source)
	if codec == null:
		return null
	return _ReplayManifestSnapshotOperation.new(
		self,
		lease,
		codec,
		get_active_manifest()
	)


func _capture_business_payload() -> Dictionary:
	if not _is_business_provider_valid():
		return {}
	var rollback_candidate: Dictionary = (
		_business_provider.make_transaction_rollback_candidate()
	)
	var data_value: Variant = rollback_candidate.get(&"data")
	if not data_value is Dictionary:
		return {}
	return GFVariantData.as_dictionary(data_value)


func _apply_materialized_payload(payload: Variant) -> Error:
	if (
		not _is_business_provider_valid()
		or not payload is ReplayCatalogPreparedState
	):
		return ERR_INVALID_DATA
	var prepared_state: ReplayCatalogPreparedState = payload
	return _business_provider.replace_prepared_state_taking_ownership(
		prepared_state
	)


func _restore_business_payload(payload: Dictionary) -> Error:
	if not _is_business_provider_valid():
		return ERR_UNCONFIGURED
	return _business_provider.replace_section_data_taking_ownership(payload)


func _uses_context_shallow_rollback_root() -> bool:
	return true


func _capture_shallow_rollback_root() -> Variant:
	if not _is_business_provider_valid():
		return null
	return _business_provider.make_shallow_prepared_state()


func _restore_shallow_rollback_root(root: Variant) -> Error:
	if (
		not _is_business_provider_valid()
		or not root is ReplayCatalogPreparedState
	):
		return ERR_INVALID_DATA
	var prepared_state: ReplayCatalogPreparedState = root
	return _business_provider.replace_prepared_state_taking_ownership(
		prepared_state
	)


func _decode_materialized_chunks_taking_ownership(
	chunks: Array[PackedByteArray]
) -> Variant:
	var decoded_value: Variant = ReplayChunkCodec.decode_prepared_state(chunks)
	chunks.clear()
	return decoded_value


# --- 私有/辅助方法 ---

func _is_business_provider_valid() -> bool:
	return (
		_business_provider != null
		and _business_provider.section_id == section_id
		and _business_provider.schema_version
		== ReplayCatalogSaveData.SCHEMA_VERSION
	)


# --- 内部类 ---

class _ReplayManifestSnapshotOperation extends GFSaveSectionSnapshotOperation:
	var _provider: ReplayManifestSaveSectionProvider = null
	var _lease: ChunkSaveLease = null
	var _codec: ReplayChunkCodec = null
	var _active_manifest: ChunkManifest = null
	var _offered: bool = false

	func _init(
		provider: ReplayManifestSaveSectionProvider,
		lease: ChunkSaveLease,
		codec: ReplayChunkCodec,
		active_manifest: ChunkManifest
	) -> void:
		_provider = provider
		_lease = lease
		_codec = codec
		_active_manifest = active_manifest

	func _advance_snapshot(step_budget: int) -> int:
		if not _offered:
			var consumed_units: int = _codec.advance(step_budget)
			if _codec.is_failed():
				var _failed_encode: bool = _fail_snapshot(
					_codec.get_error_code(),
					_codec.get_error()
				)
				return maxi(consumed_units, 1)
			if not _codec.is_complete():
				return maxi(consumed_units, 1)
			var chunks: Array[PackedByteArray] = (
				_codec.take_chunks_taking_ownership()
			)
			_codec = null
			if not _lease.offer_chunks_taking_ownership(
				chunks,
				_lease.get_producer_revision(),
				_provider.section_id,
				_provider.schema_version,
				_active_manifest
			):
				var _failed_offer: bool = _fail_snapshot(
					ERR_ALREADY_IN_USE,
					"Replay chunks could not be offered to their save lease."
				)
				return maxi(consumed_units, 1)
			_offered = true
			_active_manifest = null
			return maxi(consumed_units, 1)

		if _lease.is_staged():
			var manifest: ChunkManifest = _lease.claim_manifest_for_provider()
			if manifest == null:
				var _failed_claim: bool = _fail_snapshot(
					ERR_ALREADY_IN_USE,
					"Replay staged Manifest was unavailable."
				)
				return 1
			var snapshot: GFSaveSectionSnapshot = _provider.make_snapshot(
				manifest.to_dict()
			)
			if snapshot == null or not _complete_snapshot(snapshot):
				var _failed_snapshot: bool = _fail_snapshot(
					ERR_INVALID_DATA,
					"Replay Manifest snapshot could not be completed."
				)
			return 1

		if _lease.is_terminal():
			var lease_error: Error = _lease.get_error_code()
			var _failed_stage: bool = _fail_snapshot(
				lease_error if lease_error != OK else FAILED,
				_lease.get_error()
			)
		return 1

	func _cancel_snapshot() -> void:
		_codec = null
		_provider = null
		_lease = null
		_active_manifest = null
