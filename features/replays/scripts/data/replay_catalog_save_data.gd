## ReplayCatalogSaveData: replays Feature 的严格 GFSaveProfile section。
class_name ReplayCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 6
## 玩家 Profile 中最多保留的回放数；最新 UUID v7 优先。
const MAX_REPLAY_COUNT: int = 128


# --- 私有变量 ---

var _items: Array[ReplayData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.REPLAYS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 公共方法 ---

## 捕获供分块 codec 消费的请求时刻目录根。
##
## Provider 内部 ReplayData 在严格构造后不再原地修改，且所有读取入口都返回
## 深复制，因此这里只需冻结数组根；编码器再按 metadata/step 逐片隔离。
func make_chunk_source_snapshot() -> ReplayChunkSourceSnapshot:
	var item_snapshot: Array[ReplayData] = _items.duplicate()
	return ReplayChunkSourceSnapshot.take_ownership_of_immutable_items(
		item_snapshot
	)


## 捕获只复制目录数组根的事务状态；ReplayData 继续由 Provider 私有且不可变。
func make_shallow_prepared_state() -> ReplayCatalogPreparedState:
	var item_snapshot: Array[ReplayData] = _items.duplicate()
	return ReplayCatalogPreparedState.take_ownership_of_validated_items(
		item_snapshot
	)


## 从严格 decoder 或浅层 rollback state 一次性替换目录根。
## @param state: 待一次性消费的已验证回放目录状态。
func replace_prepared_state_taking_ownership(
	state: ReplayCatalogPreparedState
) -> Error:
	if state == null:
		return ERR_INVALID_DATA
	var expected_count: int = state.get_item_count()
	if expected_count < 0 or expected_count > MAX_REPLAY_COUNT:
		return ERR_INVALID_DATA
	var next_items: Array[ReplayData] = state.take_items_taking_ownership()
	if next_items.size() != expected_count:
		return ERR_INVALID_DATA
	_items = next_items
	return OK


## 返回当前私有 ReplayData 的稳定身份，不暴露对象 alias。
func get_replay_instance_ids() -> PackedInt64Array:
	var identities: PackedInt64Array = PackedInt64Array()
	for item: ReplayData in _items:
		var _appended: bool = identities.append(item.get_instance_id())
	return identities


# --- 可重写钩子 ---

func _begin_save_snapshot(
	_context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	# 生产持久化只注册 Manifest wrapper。保留的直接 snapshot 兼容入口只允许
	# 小型根，避免旧路径在一个 work unit 内复制大 topology/tile。
	if not _is_legacy_snapshot_root_bounded():
		return null
	var item_snapshot: Array[ReplayData] = _items.duplicate()
	return _ReplayCatalogSnapshotOperation.new(
		section_id,
		schema_version,
		item_snapshot
	)


func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: ReplayData in _items:
		if item != null:
			serialized_items.append(item.to_dict())
	return {
		"items": serialized_items,
	}


func _make_runtime_section_cache_snapshot() -> Dictionary:
	var decoded_items: Array[ReplayData] = []
	for item: ReplayData in _items:
		if item == null:
			continue
		# Provider 内的已验证 Resource 是权威缓存；调用方仍取得深复制，
		# 避免列表/回放控制器改写 actions、checkpoints 或嵌套快照。
		var duplicate_value: Resource = item.duplicate(true)
		if duplicate_value is ReplayData:
			var duplicate_item: ReplayData = duplicate_value
			decoded_items.append(duplicate_item)
	return {&"items": decoded_items}


func _validate_section_data_boundary(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, &"items")
	if not items_value is Array:
		return ERR_INVALID_DATA
	var items: Array = items_value
	# 该检查发生在 GameSaveSectionData 的 deep duplicate 之前。
	return OK if items.size() <= MAX_REPLAY_COUNT else ERR_INVALID_DATA


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not (items_value is Array):
		return ERR_INVALID_DATA
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > MAX_REPLAY_COUNT:
		return ERR_INVALID_DATA

	var next_items: Array[ReplayData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in item_values:
		if not (item_value is Dictionary):
			return ERR_INVALID_DATA
		var item: ReplayData = ReplayData.from_dict(GFVariantData.as_dictionary(item_value))
		if item == null or seen_ids.has(item.replay_id):
			return ERR_INVALID_DATA
		seen_ids[item.replay_id] = true
		next_items.append(item)

	next_items.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	_items = next_items
	return OK


func _is_legacy_snapshot_root_bounded() -> bool:
	for item: ReplayData in _items:
		if item == null:
			return false
		var cells_value: Variant = item.initial_board_topology.get(
			&"active_cells"
		)
		var tiles_value: Variant = item.final_board_snapshot.get(&"tiles")
		if not cells_value is Array or not tiles_value is Array:
			return false
		var cells: Array = cells_value
		var tiles: Array = tiles_value
		if (
			cells.size() > ReplayChunkSourceSnapshot.TOPOLOGY_CELL_BATCH_SIZE
			or tiles.size() > ReplayChunkSourceSnapshot.FINAL_TILE_BATCH_SIZE
		):
			return false
		for tile_value: Variant in tiles:
			if not ReplayChunkSourceSnapshot.is_tile_variant_within_budget(
				tile_value
			):
				return false
	return true


# --- 内部类 ---

class _ReplayCatalogSnapshotOperation extends GFSaveSectionSnapshotOperation:
	var _snapshot_section_id: StringName = &""
	var _snapshot_schema_version: int = 0
	var _source_items: Array[ReplayData] = []
	var _source_index: int = 0
	var _serialized_items: Array[Dictionary] = []
	var _current_item: ReplayData = null
	var _current_payload: Dictionary = {}
	var _current_actions: Array[Vector2i] = []
	var _current_checkpoints: Array[Dictionary] = []
	var _action_index: int = 0
	var _checkpoint_index: int = 0

	func _init(
		snapshot_section_id: StringName,
		snapshot_schema_version: int,
		source_items: Array[ReplayData]
	) -> void:
		_snapshot_section_id = snapshot_section_id
		_snapshot_schema_version = snapshot_schema_version
		_source_items = source_items

	func _advance_snapshot(step_budget: int) -> int:
		var consumed_units: int = 0
		while consumed_units < step_budget and is_pending():
			if _current_item == null:
				if _source_index >= _source_items.size():
					_complete_catalog_snapshot()
					break
				var item: ReplayData = _source_items[_source_index]
				_source_index += 1
				consumed_units += 1
				if item != null:
					_begin_item_snapshot(item)
				continue

			if _action_index < _current_item.actions.size():
				_current_actions.append(_current_item.actions[_action_index])
				_action_index += 1
				consumed_units += 1
				continue

			if _checkpoint_index < _current_item.checkpoints.size():
				var checkpoint: ReplayCheckpoint = (
					_current_item.checkpoints[_checkpoint_index]
				)
				_checkpoint_index += 1
				if checkpoint != null:
					_current_checkpoints.append(checkpoint.to_dict())
				consumed_units += 1
				continue

			_finish_item_snapshot()
			consumed_units += 1

		return maxi(consumed_units, 1)

	func _cancel_snapshot() -> void:
		_clear_working_state()

	func _begin_item_snapshot(item: ReplayData) -> void:
		_current_item = item
		_current_actions = []
		_current_checkpoints = []
		_action_index = 0
		_checkpoint_index = 0
		_current_payload = {
			&"schema_version": ReplayData.SCHEMA_VERSION,
			&"replay_id": item.replay_id,
			&"timestamp": item.timestamp,
			&"mode_config_path": item.mode_config_path,
			&"ruleset_id": item.ruleset_id,
			&"ruleset_version": item.ruleset_version,
			&"ruleset_fingerprint": item.ruleset_fingerprint,
			&"initial_seed": item.initial_seed,
			&"session_metadata": item.session_metadata.duplicate(true),
			&"initial_board_topology": item.initial_board_topology.duplicate(true),
			&"final_score": item.final_score,
			&"final_board_snapshot": item.final_board_snapshot.duplicate(true),
		}

	func _finish_item_snapshot() -> void:
		_current_payload[&"actions"] = _current_actions
		_current_payload[&"checkpoints"] = _current_checkpoints
		_serialized_items.append(_current_payload)
		_current_item = null
		_current_payload = {}
		_current_actions = []
		_current_checkpoints = []
		_action_index = 0
		_checkpoint_index = 0

	func _complete_catalog_snapshot() -> void:
		var owned_items: Array[Dictionary] = _serialized_items
		_serialized_items = []
		_source_items = []
		var snapshot: GFSaveSectionSnapshot = (
			GFSaveSectionSnapshot.take_ownership(
				_snapshot_section_id,
				_snapshot_schema_version,
				{&"items": owned_items}
			)
		)
		if snapshot == null:
			var _failed: bool = _fail_snapshot(
				ERR_INVALID_DATA,
				"Replay catalog snapshot identity is invalid."
			)
			return
		var _completed: bool = _complete_snapshot(snapshot)

	func _clear_working_state() -> void:
		_source_items = []
		_serialized_items = []
		_current_item = null
		_current_payload = {}
		_current_actions = []
		_current_checkpoints = []
