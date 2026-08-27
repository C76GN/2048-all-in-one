## GameSaveProfileSettlementEvidence: 对 GF 公共 Profile 快照的严格类型化投影。
##
## Outcome-unknown 栅栏、Materialization Lease 与 Profile 注销只能消费同一份
## fail-closed 判定。缺字段、错类型或未知 generation 都保持未结算，调用方不得
## 用默认零值推断空闲。
class_name GameSaveProfileSettlementEvidence
extends RefCounted


# --- 私有变量 ---

var _valid: bool = false
var _profile_id: StringName = &""
var _state: StringName = &""
var _persisted_generation: int = -1
var _save_queue_size: int = -1
var _load_queue_size: int = -1
var _flush_queue_size: int = -1
var _write_outcome_unknown: bool = true
var _unknown_write_generations: PackedInt64Array = PackedInt64Array()
var _detached_write_count: int = -1
var _detached_storage_request_ids: PackedInt64Array = PackedInt64Array()


# --- 公共方法 ---

## 严格解析 GFSaveProfileUtility.get_profile_state_snapshot() 的公开 schema。
## @param snapshot: GF 返回的 Profile 状态快照。
## @return: 始终返回 evidence；调用方通过 is_valid() 判断 schema 是否完整。
static func from_snapshot(snapshot: Dictionary) -> GameSaveProfileSettlementEvidence:
	var evidence: GameSaveProfileSettlementEvidence = (
		GameSaveProfileSettlementEvidence.new()
	)
	evidence._parse(snapshot)
	return evidence


## 返回快照是否包含全部结算字段且类型、范围一致。
func is_valid() -> bool:
	return _valid


## 返回快照是否是指定 Profile 的严格空闲终态。
## @param expected_profile_id: 调用方冻结的 Profile 身份。
func is_settled_idle(expected_profile_id: StringName) -> bool:
	return (
		_valid
		and expected_profile_id != &""
		and _profile_id == expected_profile_id
		and _state == GFSaveProfileUtility.STATE_IDLE
		and _save_queue_size == 0
		and _load_queue_size == 0
		and _flush_queue_size == 0
		and not _write_outcome_unknown
		and _unknown_write_generations.is_empty()
		and _detached_write_count == 0
		and _detached_storage_request_ids.is_empty()
	)


## 返回指定 Profile 的严格空闲快照是否确认精确持久化 generation。
## @param expected_profile_id: 调用方冻结的 Profile 身份。
## @param persisted_generation: 调用方需要确认的精确 generation。
func confirms_persisted_generation(
	expected_profile_id: StringName,
	persisted_generation: int
) -> bool:
	return (
		persisted_generation >= 0
		and is_settled_idle(expected_profile_id)
		and _persisted_generation == persisted_generation
	)


## 返回严格解析后的持久化 generation；无效快照返回 -1。
func get_persisted_generation() -> int:
	return _persisted_generation if _valid else -1


# --- 私有/辅助方法 ---

func _parse(snapshot: Dictionary) -> void:
	var profile_id_value: Variant = snapshot.get("profile_id")
	var state_value: Variant = snapshot.get("state")
	var persisted_generation_value: Variant = snapshot.get("persisted_generation")
	var save_queue_size_value: Variant = snapshot.get("save_queue_size")
	var load_queue_size_value: Variant = snapshot.get("load_queue_size")
	var flush_queue_size_value: Variant = snapshot.get("flush_queue_size")
	var write_outcome_unknown_value: Variant = snapshot.get("write_outcome_unknown")
	var unknown_write_generations_value: Variant = snapshot.get(
		"unknown_write_generations"
	)
	var detached_write_count_value: Variant = snapshot.get("detached_write_count")
	var detached_storage_request_ids_value: Variant = snapshot.get(
		"detached_storage_request_ids"
	)
	if (
		not profile_id_value is StringName
		or not state_value is StringName
		or not persisted_generation_value is int
		or not save_queue_size_value is int
		or not load_queue_size_value is int
		or not flush_queue_size_value is int
		or not write_outcome_unknown_value is bool
		or not unknown_write_generations_value is PackedInt64Array
		or not detached_write_count_value is int
		or not detached_storage_request_ids_value is PackedInt64Array
	):
		return

	_profile_id = profile_id_value
	_state = state_value
	_persisted_generation = persisted_generation_value
	_save_queue_size = save_queue_size_value
	_load_queue_size = load_queue_size_value
	_flush_queue_size = flush_queue_size_value
	_write_outcome_unknown = write_outcome_unknown_value
	var unknown_write_generations: PackedInt64Array = (
		unknown_write_generations_value
	)
	_unknown_write_generations = unknown_write_generations.duplicate()
	_detached_write_count = detached_write_count_value
	var detached_storage_request_ids: PackedInt64Array = (
		detached_storage_request_ids_value
	)
	_detached_storage_request_ids = detached_storage_request_ids.duplicate()
	_valid = (
		_profile_id != &""
		and _state != &""
		and _persisted_generation >= 0
		and _save_queue_size >= 0
		and _load_queue_size >= 0
		and _flush_queue_size >= 0
		and _detached_write_count >= 0
		and _detached_write_count == _detached_storage_request_ids.size()
		and _write_outcome_unknown == not _unknown_write_generations.is_empty()
	)
