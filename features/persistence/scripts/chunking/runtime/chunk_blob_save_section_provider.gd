## 在一个小型 GF Profile 中保存或读取唯一 PackedByteArray section。
##
## 保存 bytes 只来自 context 内的一次性 Lease；读取 bytes 只进入本次 load 的
## 一次性 Sink，Provider 本身不保存跨操作的业务状态。
class_name ChunkBlobSaveSectionProvider
extends GFSaveSectionProvider


# --- 常量 ---

const SECTION_ID: StringName = &"blob"
const SECTION_SCHEMA_VERSION: int = 1
const SAVE_LEASE_CONTEXT_KEY: StringName = &"chunk_profile_save_lease"
const LOAD_SINK_CONTEXT_KEY: StringName = &"chunk_profile_load_sink"


# --- 生命周期方法 ---

func _init() -> void:
	section_id = SECTION_ID
	schema_version = SECTION_SCHEMA_VERSION
	save_enabled = true
	load_enabled = true
	required_on_load = true


# --- 可重写钩子 / 虚方法 ---

func _begin_save_snapshot(
	context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	var lease_value: Variant = context.get(SAVE_LEASE_CONTEXT_KEY)
	if not lease_value is ChunkProfileSaveLease:
		return null
	var lease: ChunkProfileSaveLease = lease_value
	if not lease.is_available():
		return null
	var payload: PackedByteArray = lease.claim()
	if not ChunkProfileSaveLease.is_valid_payload(payload):
		return null
	return make_completed_snapshot(payload)


func _capture_section(context: Dictionary = {}) -> GFSaveSection:
	var sink: ChunkProfileLoadSink = _get_load_sink(context)
	if sink == null or not sink.can_accept():
		return null
	return make_section(PackedByteArray())


func _apply_section(section: GFSaveSection, context: Dictionary = {}) -> Error:
	var sink: ChunkProfileLoadSink = _get_load_sink(context)
	if sink == null:
		return ERR_INVALID_DATA
	if not sink.can_accept():
		return ERR_ALREADY_IN_USE
	var payload_value: Variant = section.get_payload()
	if not payload_value is PackedByteArray:
		return ERR_INVALID_DATA
	var payload: PackedByteArray = payload_value
	if not ChunkProfileSaveLease.is_valid_payload(payload):
		return ERR_INVALID_DATA
	return sink.write_once(payload)


func _rollback_section(
	previous_section: GFSaveSection,
	context: Dictionary = {}
) -> Error:
	var sink: ChunkProfileLoadSink = _get_load_sink(context)
	if sink == null:
		return ERR_INVALID_DATA
	var previous_payload_value: Variant = previous_section.get_payload()
	if not previous_payload_value is PackedByteArray:
		return ERR_INVALID_DATA
	var previous_payload: PackedByteArray = previous_payload_value
	if not previous_payload.is_empty():
		return ERR_INVALID_DATA
	return sink.rollback_for_provider()


# --- 私有/辅助方法 ---

func _get_load_sink(context: Dictionary) -> ChunkProfileLoadSink:
	var sink_value: Variant = context.get(LOAD_SINK_CONTEXT_KEY)
	if not sink_value is ChunkProfileLoadSink:
		return null
	return sink_value
