## bookmarks stream v2 的只读请求时刻源。
##
## Snapshot 接管有限目录数组根；内部 envelope 在 Provider 中不可变，因此可按
## scalar metadata、四个状态根、棋盘小批、历史字节批和 replay 单步读取。
## 任何 var_to_bytes 或递归复制之前都必须先通过本类的结构预算。
class_name BookmarkChunkSourceSnapshot
extends RefCounted


# --- 常量 ---

const TOPOLOGY_CELL_BATCH_SIZE: int = 64
const FINAL_TILE_BATCH_SIZE: int = 1
const HISTORY_BYTE_BATCH_SIZE: int = 64 * 1024

const STATE_SESSION_METADATA: StringName = &"session_metadata"
const STATE_EXTRA_STATS: StringName = &"extra_stats"
const STATE_RNG_FULL_STATE: StringName = &"rng_full_state"
const STATE_RULES_STATES: StringName = &"rules_states"
const STATE_KINDS: Array[StringName] = [
	STATE_SESSION_METADATA,
	STATE_EXTRA_STATS,
	STATE_RNG_FULL_STATE,
	STATE_RULES_STATES,
]


# --- 私有变量 ---

var _items: Array[Dictionary] = []
## 每条只缓存一次小 metadata 与冻结大根 alias；helper 不再重新深复制整棋盘。
var _record_views: Array[Dictionary] = []


# --- 公共方法 ---

## 接管仅含当前 schema、不可变规范 envelope 的有限目录根。
## @param items: 已验证并由调用方移交唯一所有权的书签 envelope 根。
static func take_ownership_of_immutable_items(
	items: Array[Dictionary]
) -> BookmarkChunkSourceSnapshot:
	if items.size() > BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT:
		return null
	var record_views: Array[Dictionary] = []
	for item: Dictionary in items:
		if (
			GFVariantData.get_option_int(item, &"schema_version", 0)
			!= BookmarkData.SCHEMA_VERSION
			or not BookmarkData.is_persisted_envelope_copy_boundary_valid(item)
		):
			return null
		var record_view: Dictionary = _make_record_view(item)
		if record_view.is_empty():
			return null
		record_views.append(record_view)
	var snapshot: BookmarkChunkSourceSnapshot = BookmarkChunkSourceSnapshot.new()
	snapshot._items = items
	snapshot._record_views = record_views
	return snapshot


func get_record_count() -> int:
	return _items.size()


## 获取不含任何大数组/字节载荷的 scalar metadata。
## @param index: 书签记录在冻结目录根中的索引。
func make_record_metadata(index: int) -> Variant:
	var record_view: Dictionary = _get_record_view(index)
	if record_view.is_empty():
		return null
	var metadata_value: Variant = record_view.get(&"metadata")
	return metadata_value if metadata_value is Dictionary else null


## 获取固定状态序列中指定位置的状态种类。
## @param state_index: STATE_KINDS 中的状态序号。
func get_state_kind(state_index: int) -> StringName:
	if state_index < 0 or state_index >= STATE_KINDS.size():
		return &""
	return STATE_KINDS[state_index]


## 返回一个不可变、小根状态 alias；codec 在序列化前扫描完整结构预算。
## @param index: 书签记录在冻结目录根中的索引。
## @param state_index: STATE_KINDS 中的状态序号。
func get_state_value(index: int, state_index: int) -> Variant:
	var item: Dictionary = _get_item(index)
	var state_kind: StringName = get_state_kind(state_index)
	if item.is_empty() or state_kind == &"":
		return null
	var value: Variant = item.get(state_kind)
	return value if value is Dictionary else null


## @param index: 书签记录在冻结目录根中的索引。
func get_topology_cell_count(index: int) -> int:
	return _get_metadata_count(index, &"active_cell_count")


## @param index: 书签记录在冻结目录根中的索引。
func get_tile_count(index: int) -> int:
	return _get_metadata_count(index, &"tile_count")


## @param index: 书签记录在冻结目录根中的索引。
func get_history_byte_count(index: int) -> int:
	return _get_metadata_count(index, &"history_byte_count")


## @param index: 书签记录在冻结目录根中的索引。
func get_replay_step_count(index: int) -> int:
	return _get_metadata_count(index, &"replay_step_count")


## 构造一个固定上限的拓扑单元批次。
## @param index: 书签记录在冻结目录根中的索引。
## @param start_index: 本批在 active_cells 中的起始索引。
func make_topology_cell_batch(index: int, start_index: int) -> Variant:
	var record_view: Dictionary = _get_record_view(index)
	var cells_value: Variant = record_view.get(&"cells")
	if not cells_value is Array:
		return null
	var cells: Array = GFVariantData.as_array(cells_value)
	if start_index < 0 or start_index >= cells.size():
		return null
	var end_index: int = mini(
		start_index + TOPOLOGY_CELL_BATCH_SIZE,
		cells.size()
	)
	var batch: Array[Vector2i] = []
	for cell_index: int in range(start_index, end_index):
		var cell_value: Variant = cells[cell_index]
		if not cell_value is Vector2i:
			return null
		batch.append(cell_value)
	return batch


## 构造一个固定上限的方块 envelope 批次。
## @param index: 书签记录在冻结目录根中的索引。
## @param start_index: 本批在 tiles 中的起始索引。
func make_tile_batch(index: int, start_index: int) -> Variant:
	var record_view: Dictionary = _get_record_view(index)
	var tiles_value: Variant = record_view.get(&"tiles")
	if not tiles_value is Array:
		return null
	var tiles: Array = GFVariantData.as_array(tiles_value)
	if start_index < 0 or start_index >= tiles.size():
		return null
	var end_index: int = mini(start_index + FINAL_TILE_BATCH_SIZE, tiles.size())
	var batch: Array[Dictionary] = []
	for tile_index: int in range(start_index, end_index):
		var tile_value: Variant = tiles[tile_index]
		if (
			not tile_value is Dictionary
			or not is_variant_within_frame_budget(tile_value)
		):
			return null
		batch.append(GFVariantData.as_dictionary(tile_value))
	return batch


## 构造一个固定字节上限的历史载荷批次。
## @param index: 书签记录在冻结目录根中的索引。
## @param start_offset: 本批在历史字节中的起始偏移。
func make_history_byte_batch(index: int, start_offset: int) -> Variant:
	var record_view: Dictionary = _get_record_view(index)
	var payload_value: Variant = record_view.get(&"history_payload")
	if not payload_value is PackedByteArray:
		return null
	var payload: PackedByteArray = payload_value
	if start_offset < 0 or start_offset >= payload.size():
		return null
	return payload.slice(
		start_offset,
		mini(start_offset + HISTORY_BYTE_BATCH_SIZE, payload.size())
	)


## 构造一个动作与检查点严格配对的回放步骤。
## @param index: 书签记录在冻结目录根中的索引。
## @param step_index: 本步骤在回放轨迹中的零基索引。
func make_replay_step(index: int, step_index: int) -> Variant:
	var record_view: Dictionary = _get_record_view(index)
	var actions_value: Variant = record_view.get(&"actions")
	var checkpoints_value: Variant = record_view.get(&"checkpoints")
	if not actions_value is Array or not checkpoints_value is Array:
		return null
	var actions: Array = actions_value
	var checkpoints: Array = checkpoints_value
	if (
		step_index < 0
		or step_index >= actions.size()
		or checkpoints.size() != actions.size()
	):
		return null
	var action_value: Variant = actions[step_index]
	var checkpoint_value: Variant = checkpoints[step_index]
	if not action_value is Vector2i or not checkpoint_value is Dictionary:
		return null
	return {
		&"action": action_value,
		&"checkpoint": checkpoint_value,
	}


## 对单个 frame 或待放入 frame 的值执行严格递归预算。
##
## 复用 persistence-owned 通用扫描器；它拒绝 Object/Callable/RID/Signal、
## 环、非有限数，并限制深度、节点、容器、文本与 PackedArray bytes。
## @param value: 要在进入 frame 序列化前扫描的纯 Variant 值。
static func is_variant_within_frame_budget(value: Variant) -> bool:
	return ChunkFrameVariantBudget.is_value_within_default_budget(value)


func release() -> void:
	_items.clear()
	_record_views.clear()


# --- 私有/辅助方法 ---

func _get_item(index: int) -> Dictionary:
	if index < 0 or index >= _items.size():
		return {}
	return _items[index]


func _get_record_view(index: int) -> Dictionary:
	if index < 0 or index >= _record_views.size():
		return {}
	return _record_views[index]


func _get_metadata_count(index: int, key: StringName) -> int:
	var record_view: Dictionary = _get_record_view(index)
	var metadata_value: Variant = record_view.get(&"metadata")
	if not metadata_value is Dictionary:
		return -1
	return GFVariantData.get_option_int(
		GFVariantData.as_dictionary(metadata_value),
		key,
		-1
	)


static func _make_record_view(item: Dictionary) -> Dictionary:
	var board_value: Variant = GFVariantData.get_option_value(
		item,
		&"board_snapshot"
	)
	var history_value: Variant = GFVariantData.get_option_value(
		item,
		&"game_state_history"
	)
	var actions_value: Variant = GFVariantData.get_option_value(
		item,
		&"replay_actions"
	)
	var checkpoints_value: Variant = GFVariantData.get_option_value(
		item,
		&"replay_checkpoints"
	)
	if (
		not board_value is Dictionary
		or not history_value is Dictionary
		or not actions_value is Array
		or not checkpoints_value is Array
	):
		return {}
	var board: Dictionary = GFVariantData.as_dictionary(board_value)
	var history: Dictionary = GFVariantData.as_dictionary(history_value)
	var topology_value: Variant = GFVariantData.get_option_value(
		board,
		&"topology"
	)
	var tiles_value: Variant = GFVariantData.get_option_value(
		board,
		&"tiles"
	)
	var payload_value: Variant = GFVariantData.get_option_value(
		history,
		&"payload"
	)
	if (
		not topology_value is Dictionary
		or not tiles_value is Array
		or not payload_value is PackedByteArray
	):
		return {}
	var topology: Dictionary = GFVariantData.as_dictionary(topology_value)
	var cells_value: Variant = GFVariantData.get_option_value(
		topology,
		&"active_cells"
	)
	if not cells_value is Array:
		return {}
	var cells: Array = GFVariantData.as_array(cells_value)
	var tiles: Array = GFVariantData.as_array(tiles_value)
	var history_payload: PackedByteArray = payload_value
	var actions: Array = GFVariantData.as_array(actions_value)
	var checkpoints: Array = GFVariantData.as_array(checkpoints_value)
	if (
		cells.is_empty()
		or cells.size() > BookmarkData.PERSISTED_BOARD_CELL_LIMIT
		or tiles.size() > cells.size()
		or history_payload.is_empty()
		or history_payload.size() > BookmarkData.MAX_HISTORY_PAYLOAD_BYTES
		or actions.size() > BookmarkData.PERSISTED_REPLAY_TRACE_LIMIT
		or checkpoints.size() != actions.size()
	):
		return {}
	var metadata: Dictionary = {
		&"schema_version": item.get(&"schema_version"),
		&"bookmark_id": item.get(&"bookmark_id"),
		&"timestamp": item.get(&"timestamp"),
		&"mode_config_path": item.get(&"mode_config_path"),
		&"ruleset_id": item.get(&"ruleset_id"),
		&"ruleset_version": item.get(&"ruleset_version"),
		&"ruleset_fingerprint": item.get(&"ruleset_fingerprint"),
		&"initial_seed": item.get(&"initial_seed"),
		&"score": item.get(&"score"),
		&"move_count": item.get(&"move_count"),
		&"ratio_resolutions": item.get(&"ratio_resolutions"),
		&"highest_tile": item.get(&"highest_tile"),
		&"target_tile_value": item.get(&"target_tile_value"),
		&"target_reached": item.get(&"target_reached"),
		&"board_schema_version": board.get(&"schema_version"),
		&"topology_schema_version": topology.get(&"schema_version"),
		&"topology_id": topology.get(&"topology_id"),
		&"active_cell_count": cells.size(),
		&"tile_count": tiles.size(),
		&"history_byte_count": history_payload.size(),
		&"replay_step_count": actions.size(),
	}
	return {
		&"metadata": metadata,
		&"cells": cells,
		&"tiles": tiles,
		&"history_payload": history_payload,
		&"actions": actions,
		&"checkpoints": checkpoints,
	}
