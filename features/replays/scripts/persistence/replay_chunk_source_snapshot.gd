## replays 分块编码器的只读请求时刻源。
##
## Snapshot 接管一个独立数组根。ReplayCatalogSaveData 内部的 ReplayData
## 已通过严格 schema 校验、不会暴露可变别名，也不会原地修改；因此冻结根后
## 可以按 scalar metadata、拓扑单元批、最终方块批与单步记录逐片复制。
class_name ReplayChunkSourceSnapshot
extends RefCounted


# --- 常量 ---

## 单个 topology frame 最多复制的 active cell 数量。
const TOPOLOGY_CELL_BATCH_SIZE: int = 1024

## 单个 final snapshot frame 最多复制的 tile 数量。
const FINAL_TILE_BATCH_SIZE: int = 1

## 单个 tile 在复制/编码前必须满足的结构预算。
const MAX_TILE_VARIANT_DEPTH: int = ChunkFrameVariantBudget.MAX_VARIANT_DEPTH
const MAX_TILE_VARIANT_NODES: int = ChunkFrameVariantBudget.MAX_VARIANT_NODES
const MAX_TILE_CONTAINER_COUNT: int = ChunkFrameVariantBudget.MAX_CONTAINER_COUNT
const MAX_TILE_CONTAINER_ITEMS: int = ChunkFrameVariantBudget.MAX_CONTAINER_ITEMS
const MAX_TILE_PACKED_BYTES: int = ChunkFrameVariantBudget.MAX_PACKED_BYTES
const MAX_TILE_TEXT_CHARACTERS: int = (
	ChunkFrameVariantBudget.MAX_TEXT_CHARACTERS
)
const MAX_TILE_APPROX_BYTES: int = ChunkFrameVariantBudget.MAX_APPROX_BYTES


# --- 私有变量 ---

var _items: Array[ReplayData] = []


# --- 公共方法 ---

## 接管仅含 Provider 私有、不可变 ReplayData 的数组根。
##
## 返回后调用方必须放弃 items 数组根；ReplayData 在本 Snapshot 生命周期内
## 必须保持不可变。
## @param items: 移交唯一数组根的已验证 Replay 集合。
static func take_ownership_of_immutable_items(
	items: Array[ReplayData]
) -> ReplayChunkSourceSnapshot:
	if items.size() > ReplayCatalogSaveData.MAX_REPLAY_COUNT:
		return null
	for item: ReplayData in items:
		if not _has_bounded_roots(item):
			return null
	var snapshot: ReplayChunkSourceSnapshot = ReplayChunkSourceSnapshot.new()
	snapshot._items = items
	return snapshot


## 获取冻结目录的 Replay 数量。
func get_replay_count() -> int:
	return _items.size()


## 获取指定 Replay 的步数；越界或内部不变量失效时返回 -1。
## @param replay_index: 冻结目录中的 Replay 序号。
func get_step_count(replay_index: int) -> int:
	var replay: ReplayData = _get_replay(replay_index)
	if (
		replay == null
		or replay.actions.size() > ReplayData.MAX_STEP_COUNT
		or replay.checkpoints.size() != replay.actions.size()
	):
		return -1
	return replay.actions.size()


## 获取指定 Replay 的 topology cell 数量。
## @param replay_index: 冻结目录中的 Replay 序号。
func get_topology_cell_count(replay_index: int) -> int:
	var replay: ReplayData = _get_replay(replay_index)
	if replay == null:
		return -1
	var cells_value: Variant = replay.initial_board_topology.get(
		&"active_cells"
	)
	if not cells_value is Array:
		return -1
	var cells: Array = cells_value
	if cells.is_empty() or cells.size() > BoardTopology.MAX_CELL_COUNT:
		return -1
	return cells.size()


## 获取指定 Replay 最终快照的 tile 数量。
## @param replay_index: 冻结目录中的 Replay 序号。
func get_final_tile_count(replay_index: int) -> int:
	var replay: ReplayData = _get_replay(replay_index)
	var cell_count: int = get_topology_cell_count(replay_index)
	if replay == null or cell_count < 0:
		return -1
	var tiles_value: Variant = replay.final_board_snapshot.get(&"tiles")
	if not tiles_value is Array:
		return -1
	var tiles: Array = tiles_value
	return tiles.size() if tiles.size() <= cell_count else -1


## 获取指定 Replay 的隔离 scalar metadata frame。
##
## topology cells、final tiles、actions/checkpoints 均不进入此 frame。
## @param replay_index: 冻结目录中的 Replay 序号。
## @return 合法序号返回严格 Dictionary；越界返回 null。
func duplicate_replay_metadata(replay_index: int) -> Variant:
	var replay: ReplayData = _get_replay(replay_index)
	var step_count: int = get_step_count(replay_index)
	var cell_count: int = get_topology_cell_count(replay_index)
	var tile_count: int = get_final_tile_count(replay_index)
	if (
		replay == null
		or step_count < 0
		or cell_count < 0
		or tile_count < 0
	):
		return null
	var topology_schema_value: Variant = (
		replay.initial_board_topology.get(&"schema_version")
	)
	var topology_id_value: Variant = (
		replay.initial_board_topology.get(&"topology_id")
	)
	var snapshot_schema_value: Variant = (
		replay.final_board_snapshot.get(&"schema_version")
	)
	if (
		not topology_schema_value is int
		or not topology_id_value is String
		or not snapshot_schema_value is int
	):
		return null
	return {
		&"schema_version": ReplayData.SCHEMA_VERSION,
		&"replay_id": replay.replay_id,
		&"timestamp": replay.timestamp,
		&"mode_config_path": replay.mode_config_path,
		&"ruleset_id": replay.ruleset_id,
		&"ruleset_version": replay.ruleset_version,
		&"ruleset_fingerprint": replay.ruleset_fingerprint,
		&"initial_seed": replay.initial_seed,
		&"session_metadata": replay.session_metadata.duplicate(true),
		&"final_score": replay.final_score,
		&"topology_schema_version": topology_schema_value,
		&"topology_id": topology_id_value,
		&"active_cell_count": cell_count,
		&"snapshot_schema_version": snapshot_schema_value,
		&"tile_count": tile_count,
		&"step_count": step_count,
	}


## 复制一个固定上限的 topology active_cells 批。
## @param replay_index: 冻结目录中的 Replay 序号。
## @param start_index: 本批在 active_cells 中的起始序号。
func duplicate_topology_cell_batch(
	replay_index: int,
	start_index: int
) -> Variant:
	var replay: ReplayData = _get_replay(replay_index)
	var cell_count: int = get_topology_cell_count(replay_index)
	if replay == null or start_index < 0 or start_index >= cell_count:
		return null
	var cells_value: Variant = replay.initial_board_topology.get(
		&"active_cells"
	)
	if not cells_value is Array:
		return null
	var cells: Array = cells_value
	var end_index: int = mini(
		start_index + TOPOLOGY_CELL_BATCH_SIZE,
		cell_count
	)
	var batch: Array[Vector2i] = []
	for index: int in range(start_index, end_index):
		var cell_value: Variant = cells[index]
		if not cell_value is Vector2i:
			return null
		batch.append(cell_value)
	return batch


## 复制一个固定上限的 final snapshot tile 批。
## @param replay_index: 冻结目录中的 Replay 序号。
## @param start_index: 本批在 final snapshot tiles 中的起始序号。
func duplicate_final_tile_batch(
	replay_index: int,
	start_index: int
) -> Variant:
	var replay: ReplayData = _get_replay(replay_index)
	var tile_count: int = get_final_tile_count(replay_index)
	if replay == null or start_index < 0 or start_index >= tile_count:
		return null
	var tiles_value: Variant = replay.final_board_snapshot.get(&"tiles")
	if not tiles_value is Array:
		return null
	var tiles: Array = tiles_value
	var end_index: int = mini(
		start_index + FINAL_TILE_BATCH_SIZE,
		tile_count
	)
	var batch: Array[Dictionary] = []
	for index: int in range(start_index, end_index):
		var tile_value: Variant = tiles[index]
		if (
			not tile_value is Dictionary
			or not is_tile_variant_within_budget(tile_value)
		):
			return null
		var duplicate_value: Variant = GFVariantData.duplicate_variant(
			tile_value,
			true,
			false
		)
		if not duplicate_value is Dictionary:
			return null
		batch.append(GFVariantData.as_dictionary(duplicate_value))
	return batch


## 在任何 deep duplicate/var_to_bytes 前扫描单 tile 的严格有界结构。
##
## Object、Callable、RID、Signal、循环引用与非有限数均会被拒绝。
## @param value: 待执行结构与预算校验的 tile Variant。
static func is_tile_variant_within_budget(value: Variant) -> bool:
	return ChunkFrameVariantBudget.is_value_within_default_budget(value)


## 获取指定 Replay 单步的隔离 action/checkpoint 数据。
## @param replay_index: 冻结目录中的 Replay 序号。
## @param step_index: Replay 动作与检查点数组中的步序号。
func duplicate_step(replay_index: int, step_index: int) -> Variant:
	var replay: ReplayData = _get_replay(replay_index)
	var step_count: int = get_step_count(replay_index)
	if (
		replay == null
		or step_index < 0
		or step_index >= step_count
	):
		return null
	var checkpoint: ReplayCheckpoint = replay.checkpoints[step_index]
	if checkpoint == null:
		return null
	return {
		&"action": replay.actions[step_index],
		&"checkpoint": checkpoint.to_dict(),
	}


## 释放冻结根；用于取消或编码终态。
func release() -> void:
	_items.clear()


# --- 私有/辅助方法 ---

static func _has_bounded_roots(item: ReplayData) -> bool:
	if (
		item == null
		or item.timestamp < 0
		or item.final_score < 0
		or not ReplayData.is_canonical_ruleset_fingerprint(
			item.ruleset_fingerprint
		)
		or item.actions.size() > ReplayData.MAX_STEP_COUNT
		or item.checkpoints.size() != item.actions.size()
	):
		return false
	var cells_value: Variant = item.initial_board_topology.get(&"active_cells")
	var tiles_value: Variant = item.final_board_snapshot.get(&"tiles")
	if not cells_value is Array or not tiles_value is Array:
		return false
	var cells: Array = cells_value
	var tiles: Array = tiles_value
	return (
		not cells.is_empty()
		and cells.size() <= BoardTopology.MAX_CELL_COUNT
		and tiles.size() <= cells.size()
	)


func _get_replay(index: int) -> ReplayData:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]
