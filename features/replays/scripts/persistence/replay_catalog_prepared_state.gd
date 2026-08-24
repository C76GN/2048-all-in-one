## 已严格物化、可一次性交给 ReplayCatalogSaveData 的不透明目录根。
##
## 该对象只在 load context/MaterializationLease 内存活，不进入持久化 Variant。
## 构造只检查最多 128 个目录根不变量；ReplayData 的深层 schema 已由逐 frame
## decoder 验证，避免在 GF apply/rollback callback 中再次遍历 8192 steps。
class_name ReplayCatalogPreparedState
extends RefCounted


# --- 私有变量 ---

var _items: Array[ReplayData] = []
var _available: bool = false


# --- 公共方法 ---

## 接管已由可信 decoder 或当前业务 Provider 验证的 ReplayData 根。
## @param items: 移交唯一数组根的已验证 ReplayData 集合。
static func take_ownership_of_validated_items(
	items: Array[ReplayData]
) -> ReplayCatalogPreparedState:
	if items.size() > ReplayCatalogSaveData.MAX_REPLAY_COUNT:
		return null
	var seen_ids: Dictionary = {}
	for item: ReplayData in items:
		if not _has_valid_bounded_root(item) or seen_ids.has(item.replay_id):
			return null
		seen_ids[item.replay_id] = true
	items.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	var state: ReplayCatalogPreparedState = ReplayCatalogPreparedState.new()
	state._items = items
	state._available = true
	return state


func get_item_count() -> int:
	return _items.size() if _available else 0


## 返回稳定对象身份，仅用于 rollback/诊断验证，不暴露可变 ReplayData alias。
func get_item_instance_ids() -> PackedInt64Array:
	var identities: PackedInt64Array = PackedInt64Array()
	if not _available:
		return identities
	for item: ReplayData in _items:
		var _appended: bool = identities.append(item.get_instance_id())
	return identities


## 一次性移出目录根；重复调用返回空数组。
func take_items_taking_ownership() -> Array[ReplayData]:
	if not _available:
		return []
	var owned_items: Array[ReplayData] = _items
	_items = []
	_available = false
	return owned_items


## 仅供同步 codec 单元测试恢复旧 Dictionary 断言；生产加载不得调用。
func make_serialized_payload_for_tests() -> Dictionary:
	if not _available:
		return {}
	var serialized_items: Array[Dictionary] = []
	for item: ReplayData in _items:
		serialized_items.append(item.to_dict())
	return {&"items": serialized_items}


# --- 私有/辅助方法 ---

static func _has_valid_bounded_root(item: ReplayData) -> bool:
	if (
		item == null
		or item.schema_version != ReplayData.SCHEMA_VERSION
		or not GFUuid.is_valid(item.replay_id, 7)
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
