## GameStatsSaveData: progress Feature 的严格 GFSaveProfile section。
class_name GameStatsSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 5
const MAX_RECENT_RESULTS: int = 128
const MAX_LEADERBOARD_ENTRIES: int = 50
const MAX_LEADERBOARD_GROUPS: int = 256
const MAX_STATS_MODE_COUNT: int = 64
const MAX_STATS_BOARD_ENTRIES_PER_MODE: int = 256
## 任一 snapshot work unit 最多复制 256 KiB 的近似持久化载荷。
const MAX_SNAPSHOT_UNIT_APPROX_BYTES: int = 256 * 1024
## 整个 progress section 的同步边界扫描与所有权复制预算。
const MAX_SECTION_APPROX_BYTES: int = 8 * 1024 * 1024
const MAX_SECTION_VALUE_NODES: int = 131_072
const MAX_SNAPSHOT_UNIT_VALUE_NODES: int = 4096
const MAX_PERSISTED_VALUE_DEPTH: int = 8
const MAX_CONTAINER_ENTRIES: int = 1024
const MAX_PACKED_BYTE_ARRAY_BYTES: int = 64 * 1024
const MAX_TEXT_CHARACTERS: int = 16 * 1024


# --- 私有变量 ---

var _stats: Dictionary = {}
var _results: Array[Dictionary] = []
var _leaderboards: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.PROGRESS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _begin_save_snapshot(
	_context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	return _GameStatsSnapshotOperation.new(
		section_id,
		schema_version,
		# Provider 只整体替换根容器；Operation 持有旧根即可冻结请求时刻，
		# begin 阶段不再同步遍历整个 section。
		_stats,
		_results,
		_leaderboards
	)

func _validate_section_data_boundary(data: Dictionary) -> Error:
	if data.size() != 3:
		return ERR_INVALID_DATA
	var stats_value: Variant = GFVariantData.get_option_value(data, "stats")
	var results_value: Variant = GFVariantData.get_option_value(data, "results")
	var leaderboards_value: Variant = GFVariantData.get_option_value(
		data,
		"leaderboards"
	)
	if not (
		stats_value is Dictionary
		and results_value is Array
		and leaderboards_value is Dictionary
	):
		return ERR_INVALID_DATA

	var stats: Dictionary = GFVariantData.as_dictionary(stats_value)
	var results: Array = GFVariantData.as_array(results_value)
	var leaderboards: Dictionary = GFVariantData.as_dictionary(
		leaderboards_value
	)
	if (
		stats.size() > MAX_STATS_MODE_COUNT
		or results.size() > MAX_RECENT_RESULTS
		or leaderboards.size() > MAX_LEADERBOARD_GROUPS
	):
		return ERR_INVALID_DATA
	if not _is_value_within_snapshot_bounds(
		data,
		MAX_SECTION_VALUE_NODES,
		MAX_SECTION_APPROX_BYTES
	):
		return ERR_INVALID_DATA
	for mode_value: Variant in stats.values():
		if not _is_value_within_snapshot_unit_bounds(mode_value):
			return ERR_INVALID_DATA
	for result_value: Variant in results:
		if not _is_value_within_snapshot_unit_bounds(result_value):
			return ERR_INVALID_DATA
	for bucket_value: Variant in leaderboards.values():
		if not _is_value_within_snapshot_unit_bounds(bucket_value):
			return ERR_INVALID_DATA
	return OK

func _gather_section_data() -> Dictionary:
	return {
		"stats": _stats.duplicate(true),
		"results": _results.duplicate(true),
		"leaderboards": _leaderboards.duplicate(true),
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 3:
		return ERR_INVALID_DATA
	var stats_value: Variant = GFVariantData.get_option_value(data, "stats")
	var results_value: Variant = GFVariantData.get_option_value(data, "results")
	var leaderboards_value: Variant = GFVariantData.get_option_value(
		data,
		"leaderboards"
	)
	if not (
		stats_value is Dictionary
		and results_value is Array
		and leaderboards_value is Dictionary
	):
		return ERR_INVALID_DATA

	var next_results: Array[Dictionary] = []
	for result_value: Variant in GFVariantData.as_array(results_value):
		if not result_value is Dictionary:
			return ERR_INVALID_DATA
		var result_data: Dictionary = result_value
		var result: GameResultRecordedData = GameResultRecordedData.from_dict(
			result_data
		)
		if result == null:
			return ERR_INVALID_DATA
		next_results.append(result.to_dict())
	if next_results.size() > MAX_RECENT_RESULTS:
		return ERR_INVALID_DATA

	# GameSaveSectionData 已在边界校验后深复制一次；这里接管隔离副本，
	# 避免 progress section 在一次 apply 内重复整段复制。
	var next_leaderboards: Dictionary = GFVariantData.as_dictionary(
		leaderboards_value
	)
	var next_stats: Dictionary = GFVariantData.as_dictionary(stats_value)
	if not _are_stats_valid(next_stats):
		return ERR_INVALID_DATA
	if not _are_leaderboards_valid(next_leaderboards):
		return ERR_INVALID_DATA

	_stats = next_stats
	_results = next_results
	_leaderboards = next_leaderboards
	return OK


# --- 私有/辅助方法 ---

static func _are_stats_valid(stats: Dictionary) -> bool:
	if stats.size() > MAX_STATS_MODE_COUNT:
		return false
	for mode_key_value: Variant in stats.keys():
		if not mode_key_value is String:
			return false
		var mode_value: Variant = stats[mode_key_value]
		# v5 既有契约只声明 stats 为自由字典；历史测试与存档会把
		# 模式内的诊断标记直接保存为标量。这里只增加结构数量防御，
		# 不在无迁移的情况下收紧已有叶节点类型。
		if mode_value is Dictionary:
			var mode_stats: Dictionary = mode_value
			if mode_stats.size() > MAX_STATS_BOARD_ENTRIES_PER_MODE:
				return false
	return true

static func _are_leaderboards_valid(leaderboards: Dictionary) -> bool:
	if leaderboards.size() > MAX_LEADERBOARD_GROUPS:
		return false
	for group_key_value: Variant in leaderboards.keys():
		if not group_key_value is String:
			return false
		var group_key: String = group_key_value
		var bucket_value: Variant = leaderboards[group_key_value]
		if not bucket_value is Dictionary:
			return false
		var bucket: Dictionary = bucket_value
		if not (
			bucket.size() == 2
			and GFVariantData.get_option_value(bucket, &"identity") is Dictionary
			and GFVariantData.get_option_value(bucket, &"entries") is Array
		):
			return false
		var identity: Dictionary = GFVariantData.get_option_dictionary(
			bucket,
			&"identity"
		)
		if (
			not GameResultRecordedData.is_leaderboard_identity_valid(identity)
			or GameResultRecordedData.calculate_leaderboard_group_key(identity)
			!= group_key
		):
			return false
		var entries: Array = GFVariantData.get_option_array(bucket, &"entries")
		if entries.size() > MAX_LEADERBOARD_ENTRIES:
			return false
		for entry_value: Variant in entries:
			if not entry_value is Dictionary:
				return false
			var entry_data: Dictionary = entry_value
			var result: GameResultRecordedData = GameResultRecordedData.from_dict(
				entry_data
			)
			if (
				result == null
				or not result.is_competition_eligible()
				or result.get_leaderboard_group_key() != group_key
				or result.get_leaderboard_identity() != identity
			):
				return false
	return true


static func _is_value_within_snapshot_unit_bounds(value: Variant) -> bool:
	return _is_value_within_snapshot_bounds(
		value,
		MAX_SNAPSHOT_UNIT_VALUE_NODES,
		MAX_SNAPSHOT_UNIT_APPROX_BYTES
	)


static func _is_value_within_snapshot_bounds(
	value: Variant,
	max_nodes: int,
	max_bytes: int
) -> bool:
	var state: Dictionary = {
		&"node_count": 0,
		&"byte_count": 0,
		&"max_nodes": max_nodes,
		&"max_bytes": max_bytes,
	}
	return _scan_bounded_value(value, state, 0, [])


static func _scan_bounded_value(
	value: Variant,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if depth > MAX_PERSISTED_VALUE_DEPTH:
		return false
	state[&"node_count"] = (
		GFVariantData.get_option_int(state, &"node_count") + 1
	)
	if (
		GFVariantData.get_option_int(state, &"node_count")
		> GFVariantData.get_option_int(state, &"max_nodes")
	):
		return false

	match typeof(value):
		TYPE_NIL:
			return _consume_approx_bytes(state, 1)
		TYPE_BOOL:
			return _consume_approx_bytes(state, 1)
		TYPE_INT, TYPE_FLOAT:
			return _consume_approx_bytes(state, 8)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _consume_text(state, str(value))
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return _consume_approx_bytes(state, 16)
		TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I:
			return _consume_approx_bytes(state, 32)
		TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE:
			return _consume_approx_bytes(state, 64)
		TYPE_QUATERNION, TYPE_COLOR:
			return _consume_approx_bytes(state, 32)
		TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D:
			return _consume_approx_bytes(state, 128)
		TYPE_ARRAY:
			return _scan_bounded_array(
				GFVariantData.as_array(value),
				state,
				depth,
				active_containers
			)
		TYPE_DICTIONARY:
			return _scan_bounded_dictionary(
				GFVariantData.as_dictionary(value),
				state,
				depth,
				active_containers
			)
		TYPE_PACKED_BYTE_ARRAY:
			var bytes: PackedByteArray = value
			return (
				bytes.size() <= MAX_PACKED_BYTE_ARRAY_BYTES
				and _consume_approx_bytes(state, bytes.size())
			)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			return _consume_packed_array(state, value, 4)
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return _consume_packed_array(state, value, 8)
		TYPE_PACKED_VECTOR2_ARRAY:
			return _consume_packed_array(state, value, 8)
		TYPE_PACKED_VECTOR3_ARRAY:
			return _consume_packed_array(state, value, 12)
		TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return _consume_packed_array(state, value, 16)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = value
			if strings.size() > MAX_CONTAINER_ENTRIES:
				return false
			for text_value: String in strings:
				if not _consume_text(state, text_value):
					return false
			return true
		_:
			return false


static func _scan_bounded_array(
	value: Array,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if (
		value.size() > MAX_CONTAINER_ENTRIES
		or not _can_visit_children(state, value.size())
		or _contains_same_container(active_containers, value)
		or not _consume_approx_bytes(state, 16 + value.size() * 8)
	):
		return false
	active_containers.append(value)
	for child: Variant in value:
		if not _scan_bounded_value(
			child,
			state,
			depth + 1,
			active_containers
		):
			var _removed_on_failure: Variant = active_containers.pop_back()
			return false
	var _removed: Variant = active_containers.pop_back()
	return true


static func _scan_bounded_dictionary(
	value: Dictionary,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if (
		value.size() > MAX_CONTAINER_ENTRIES
		or not _can_visit_children(state, value.size() * 2)
		or _contains_same_container(active_containers, value)
		or not _consume_approx_bytes(state, 32 + value.size() * 16)
	):
		return false
	active_containers.append(value)
	for key: Variant in value.keys():
		if (
			not _scan_bounded_value(
				key,
				state,
				depth + 1,
				active_containers
			)
			or not _scan_bounded_value(
				value[key],
				state,
				depth + 1,
				active_containers
			)
		):
			var _removed_on_failure: Variant = active_containers.pop_back()
			return false
	var _removed: Variant = active_containers.pop_back()
	return true


static func _consume_packed_array(
	state: Dictionary,
	value: Variant,
	element_bytes: int
) -> bool:
	var element_count: int = len(value)
	return (
		element_count <= MAX_CONTAINER_ENTRIES
		and _consume_approx_bytes(state, element_count * element_bytes)
	)


static func _consume_text(state: Dictionary, value: String) -> bool:
	if value.length() > MAX_TEXT_CHARACTERS:
		return false
	# 先限制字符数，再计算 UTF-8 长度，避免对任意长文本分配临时字节数组。
	return _consume_approx_bytes(state, value.to_utf8_buffer().size())


static func _consume_approx_bytes(state: Dictionary, byte_count: int) -> bool:
	state[&"byte_count"] = (
		GFVariantData.get_option_int(state, &"byte_count")
		+ maxi(byte_count, 0)
	)
	return (
		GFVariantData.get_option_int(state, &"byte_count")
		<= GFVariantData.get_option_int(state, &"max_bytes")
	)


static func _can_visit_children(state: Dictionary, child_count: int) -> bool:
	return (
		GFVariantData.get_option_int(state, &"node_count")
		+ maxi(child_count, 0)
		<= GFVariantData.get_option_int(state, &"max_nodes")
	)


static func _contains_same_container(
	active_containers: Array,
	value: Variant
) -> bool:
	for active_value: Variant in active_containers:
		if is_same(active_value, value):
			return true
	return false


# --- 内部类 ---

class _GameStatsSnapshotOperation extends GFSaveSectionSnapshotOperation:
	const _PHASE_STATS: int = 0
	const _PHASE_RESULTS: int = 1
	const _PHASE_LEADERBOARDS: int = 2
	const _PHASE_COMPLETE: int = 3

	var _snapshot_section_id: StringName = &""
	var _snapshot_schema_version: int = 0
	var _source_stats: Dictionary = {}
	var _source_results: Array[Dictionary] = []
	var _source_leaderboards: Dictionary = {}
	var _stats_keys: Array = []
	var _leaderboard_keys: Array = []
	var _source_index: int = 0
	var _phase: int = _PHASE_STATS
	var _snapshot_stats: Dictionary = {}
	var _snapshot_results: Array[Dictionary] = []
	var _snapshot_leaderboards: Dictionary = {}

	func _init(
		snapshot_section_id: StringName,
		snapshot_schema_version: int,
		source_stats: Dictionary,
		source_results: Array[Dictionary],
		source_leaderboards: Dictionary
	) -> void:
		_snapshot_section_id = snapshot_section_id
		_snapshot_schema_version = snapshot_schema_version
		_source_stats = source_stats
		_source_results = source_results
		_source_leaderboards = source_leaderboards
		_stats_keys = source_stats.keys()
		_leaderboard_keys = source_leaderboards.keys()

	func _advance_snapshot(step_budget: int) -> int:
		var consumed_units: int = 0
		while consumed_units < step_budget and is_pending():
			match _phase:
				_PHASE_STATS:
					if _source_index >= _stats_keys.size():
						_advance_phase(_PHASE_RESULTS)
						continue
					var mode_key: Variant = _stats_keys[_source_index]
					_source_index += 1
					_snapshot_stats[mode_key] = _duplicate_persisted_value(
						_source_stats[mode_key]
					)
				_PHASE_RESULTS:
					if _source_index >= _source_results.size():
						_advance_phase(_PHASE_LEADERBOARDS)
						continue
					var result_value: Variant = GFVariantData.duplicate_variant(
						_source_results[_source_index],
						true,
						false
					)
					if not result_value is Dictionary:
						var _failed_result: bool = _fail_snapshot(
							ERR_INVALID_DATA,
							"Progress result snapshot is not a Dictionary."
						)
						break
					_snapshot_results.append(
						GFVariantData.as_dictionary(result_value)
					)
					_source_index += 1
				_PHASE_LEADERBOARDS:
					if _source_index >= _leaderboard_keys.size():
						_advance_phase(_PHASE_COMPLETE)
						continue
					var group_key: Variant = (
						_leaderboard_keys[_source_index]
					)
					_source_index += 1
					var leaderboard_value: Variant = (
						GFVariantData.duplicate_variant(
							_source_leaderboards[group_key],
							true,
							false
						)
					)
					if not leaderboard_value is Dictionary:
						var _failed_leaderboard: bool = _fail_snapshot(
							ERR_INVALID_DATA,
							"Progress leaderboard snapshot is not a Dictionary."
						)
						break
					_snapshot_leaderboards[group_key] = (
						GFVariantData.as_dictionary(leaderboard_value)
					)
				_PHASE_COMPLETE:
					_complete_stats_snapshot()
					break
			consumed_units += 1
		return maxi(consumed_units, 1)

	func _cancel_snapshot() -> void:
		_clear_working_state()

	func _advance_phase(next_phase: int) -> void:
		_phase = next_phase
		_source_index = 0

	func _complete_stats_snapshot() -> void:
		var payload: Dictionary = {
			&"stats": _snapshot_stats,
			&"results": _snapshot_results,
			&"leaderboards": _snapshot_leaderboards,
		}
		_snapshot_stats = {}
		_snapshot_results = []
		_snapshot_leaderboards = {}
		_source_stats = {}
		_source_results = []
		_source_leaderboards = {}
		_stats_keys = []
		_leaderboard_keys = []
		var snapshot: GFSaveSectionSnapshot = (
			GFSaveSectionSnapshot.take_ownership(
				_snapshot_section_id,
				_snapshot_schema_version,
				payload
			)
		)
		if snapshot == null:
			var _failed: bool = _fail_snapshot(
				ERR_INVALID_DATA,
				"Progress snapshot identity is invalid."
			)
			return
		var _completed: bool = _complete_snapshot(snapshot)

	func _clear_working_state() -> void:
		_source_stats = {}
		_source_results = []
		_source_leaderboards = {}
		_stats_keys = []
		_leaderboard_keys = []
		_snapshot_stats = {}
		_snapshot_results = []
		_snapshot_leaderboards = {}

	func _duplicate_persisted_value(value: Variant) -> Variant:
		# GF 的 Variant 边界会同时复制嵌套集合和 PackedArray；历史标量叶
		# 保持原值，Resource 则继续沿用明确的引用语义。
		return GFVariantData.duplicate_variant(value, true, false)
