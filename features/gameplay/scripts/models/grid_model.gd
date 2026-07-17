## GridModel: 负责稀疏棋盘的逻辑状态管理。
##
## BoardTopology 是可用空间的唯一真源；方块只按活跃坐标存入稀疏字典。
class_name GridModel
extends "res://addons/gf/kernel/base/gf_model.gd"


# --- 常量 ---

const SNAPSHOT_SCHEMA_VERSION: int = 3


# --- 公共变量 ---

## 当前棋盘空间拓扑。
var topology: BoardTopology

## 交互规则的纯粹引用。
var interaction_rule: InteractionRule

## 移动规则的纯粹引用。
var movement_rule: MovementRule


# --- 私有变量 ---

var _tiles_by_cell: Dictionary = {}
var _tile_composition_utility: TileCompositionUtility = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [TileCompositionUtility]


func ready() -> void:
	var utility_value: Variant = get_utility(TileCompositionUtility)
	if utility_value is TileCompositionUtility:
		_tile_composition_utility = utility_value
	if interaction_rule != null:
		interaction_rule.setup(_tile_composition_utility)


func dispose() -> void:
	_release_grid_tiles()
	_tile_composition_utility = null
	topology = null
	interaction_rule = null
	movement_rule = null
	_tiles_by_cell.clear()


# --- 公共方法 ---

## 初始化或重置棋盘。
## @param p_topology: 棋盘空间的唯一活跃单元定义。
## @param p_interaction_rule: 当前模式的方块交互规则。
## @param p_movement_rule: 当前模式的 lane 处理规则。
func initialize(
	p_topology: BoardTopology,
	p_interaction_rule: InteractionRule,
	p_movement_rule: MovementRule
) -> bool:
	if not is_instance_valid(p_topology) or not p_topology.get_validation_report().is_ok():
		push_error("[GridModel] 无法使用无效 BoardTopology 初始化棋盘。")
		return false

	var topology_copy: BoardTopology = _duplicate_topology(p_topology)
	if topology_copy == null:
		push_error("[GridModel] 无法复制 BoardTopology。")
		return false

	_release_grid_tiles()
	topology = topology_copy
	interaction_rule = p_interaction_rule
	movement_rule = p_movement_rule
	if interaction_rule != null:
		interaction_rule.setup(_tile_composition_utility)
	_tiles_by_cell.clear()
	return true


## 获取用于撤回、书签和回放的严格快照。
func get_snapshot() -> Dictionary:
	var tiles_list: Array[Dictionary] = []
	if is_instance_valid(topology):
		for cell: Vector2i in topology.get_active_cells():
			var tile: TileState = get_tile(cell)
			if tile == null:
				continue
			var tile_snapshot: Dictionary = tile.to_dict()
			tile_snapshot[&"pos"] = cell
			tiles_list.append(tile_snapshot)
	return {
		&"schema_version": SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict() if is_instance_valid(topology) else {},
		&"tiles": tiles_list,
	}


## 从当前严格快照原子恢复棋盘；失败时保留原状态。
## @param snapshot: GridModel.get_snapshot() 产生的当前 schema 数据。
func restore_from_snapshot(snapshot: Dictionary) -> bool:
	if not is_snapshot_envelope_valid(snapshot):
		push_error("[GridModel] 拒绝恢复不符合当前严格结构的棋盘快照。")
		return false
	if GFVariantData.get_option_int(snapshot, &"schema_version", 0) != SNAPSHOT_SCHEMA_VERSION:
		push_error("[GridModel] 拒绝恢复未知棋盘快照 schema。")
		return false
	if interaction_rule == null or _tile_composition_utility == null:
		push_error("[GridModel] 无法恢复方块快照：组合工具或交互规则不可用。")
		return false

	var restored_topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(snapshot, &"topology")
	)
	if restored_topology == null:
		push_error("[GridModel] 棋盘快照包含无效拓扑。")
		return false

	var tiles_data: Array = GFVariantData.get_option_array(snapshot, &"tiles")
	if tiles_data.size() > restored_topology.get_cell_count():
		push_error("[GridModel] 棋盘快照方块数量超过活跃单元容量。")
		return false

	var restored_tiles_by_cell: Dictionary = {}
	var restored_tiles: Array[TileState] = []
	var seen_tile_ids: Dictionary = {}
	for raw_tile_info: Variant in tiles_data:
		if not raw_tile_info is Dictionary:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照包含非 Dictionary 项。")
			return false
		var tile_info: Dictionary = raw_tile_info
		if tile_info.size() != 7 or not tile_info.has(&"pos") or not tile_info[&"pos"] is Vector2i:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照条目结构无效。")
			return false
		var pos: Vector2i = tile_info[&"pos"]
		if not restored_topology.contains_cell(pos) or restored_tiles_by_cell.has(pos):
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照位置不活跃或重复：%s。" % pos)
			return false

		var tile_payload: Dictionary = tile_info.duplicate(true)
		var _position_erased: bool = tile_payload.erase(&"pos")
		if not tile_payload.has(&"tile_id") or not tile_payload[&"tile_id"] is String:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照缺少严格 tile_id。")
			return false
		var tile_id: String = tile_payload[&"tile_id"]
		if seen_tile_ids.has(tile_id):
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照包含重复 tile_id：%s。" % tile_id)
			return false
		seen_tile_ids[tile_id] = true

		var definition_id: StringName = (
			tile_payload[&"definition_id"]
			if tile_payload.has(&"definition_id") and tile_payload[&"definition_id"] is StringName
			else &""
		)
		var definition: TileDefinition = interaction_rule.get_tile_definition(definition_id)
		var tile: TileState = _tile_composition_utility.restore_tile(tile_payload, definition)
		if tile == null:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照不符合当前严格 schema：%s。" % tile_info)
			return false
		restored_tiles_by_cell[pos] = tile
		restored_tiles.append(tile)

	_release_grid_tiles()
	topology = restored_topology
	_tiles_by_cell = restored_tiles_by_cell
	return true


## 把方块放入一个空的活跃单元。
## @param tile: 待纳入棋盘所有权的方块状态。
## @param cell: 必须为空且属于当前拓扑的目标坐标。
func place_tile(tile: TileState, cell: Vector2i) -> bool:
	if tile == null or not is_active_cell(cell) or _tiles_by_cell.has(cell):
		return false
	if _tiles_by_cell.values().has(tile):
		return false
	_tiles_by_cell[cell] = tile
	return true


## 获取指定单元中的方块。
## @param cell: 待查询的棋盘坐标。
func get_tile(cell: Vector2i) -> TileState:
	var value: Variant = _tiles_by_cell.get(cell)
	if value is TileState:
		var tile: TileState = value
		return tile
	return null


## 移除并释放指定单元中的方块。
## @param cell: 待清空的棋盘坐标。
func remove_tile(cell: Vector2i) -> bool:
	var tile: TileState = get_tile(cell)
	if tile == null:
		return false
	var _erased: bool = _tiles_by_cell.erase(cell)
	if _tile_composition_utility != null:
		_tile_composition_utility.release_tile(tile)
	return true


## @param cell: 待查询的棋盘坐标。
func is_active_cell(cell: Vector2i) -> bool:
	return is_instance_valid(topology) and topology.contains_cell(cell)


## 原子替换方块位置映射，由移动系统提交完整移动结果。
## @param next_tiles_by_cell: 只含活跃坐标与唯一 TileState 的完整稀疏映射。
func replace_tiles(next_tiles_by_cell: Dictionary) -> bool:
	if not is_instance_valid(topology):
		return false
	var seen_tiles: Dictionary = {}
	for cell_value: Variant in next_tiles_by_cell.keys():
		if not cell_value is Vector2i:
			return false
		var cell: Vector2i = cell_value
		if not topology.contains_cell(cell):
			return false
		var tile_value: Variant = next_tiles_by_cell[cell]
		if not tile_value is TileState:
			return false
		var tile: TileState = tile_value
		var instance_id: int = tile.get_instance_id()
		if seen_tiles.has(instance_id):
			return false
		seen_tiles[instance_id] = true
	_tiles_by_cell = next_tiles_by_cell.duplicate()
	return true


## 替换棋盘空间，保留仍位于新拓扑活跃单元中的全部方块。
## @param next_topology: 必须容纳全部现有方块的新拓扑。
func replace_topology(next_topology: BoardTopology) -> bool:
	if not is_instance_valid(next_topology) or not next_topology.get_validation_report().is_ok():
		return false
	for cell_value: Variant in _tiles_by_cell.keys():
		var cell: Vector2i = cell_value
		if not next_topology.contains_cell(cell):
			return false
	var topology_copy: BoardTopology = _duplicate_topology(next_topology)
	if topology_copy == null:
		return false
	topology = topology_copy
	return true


func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	if not is_instance_valid(topology):
		return empty_cells
	for cell: Vector2i in topology.get_active_cells():
		if not _tiles_by_cell.has(cell):
			empty_cells.append(cell)
	return empty_cells


func get_occupied_cells() -> Array[Vector2i]:
	var occupied_cells: Array[Vector2i] = []
	if not is_instance_valid(topology):
		return occupied_cells
	for cell: Vector2i in topology.get_active_cells():
		if _tiles_by_cell.has(cell):
			occupied_cells.append(cell)
	return occupied_cells


func get_all_tiles() -> Array[TileState]:
	var tiles: Array[TileState] = []
	for cell: Vector2i in get_occupied_cells():
		var tile: TileState = get_tile(cell)
		if tile != null:
			tiles.append(tile)
	return tiles


func get_max_tile_value() -> int:
	var max_value: int = 0
	for tile: TileState in get_all_tiles():
		max_value = maxi(max_value, tile.value)
	return max_value


func get_all_tile_values() -> Array[int]:
	var values: Array[int] = []
	for tile: TileState in get_all_tiles():
		values.append(tile.value)
	values.sort()
	return values


func get_board_key() -> String:
	return topology.get_stable_key() if is_instance_valid(topology) else ""


func get_bounds_size() -> Vector2i:
	return topology.get_bounds_size() if is_instance_valid(topology) else Vector2i.ZERO


## GFModel 序列化协议。
func to_dict() -> Dictionary:
	return get_snapshot()


## @param data: 当前严格棋盘快照。
func from_dict(data: Dictionary) -> void:
	var _restored: bool = restore_from_snapshot(data)


## 在不依赖当前模式 TileDefinition 的前提下校验棋盘快照 envelope。
## @param snapshot: 待校验的棋盘快照字典。
static func is_snapshot_envelope_valid(snapshot: Dictionary) -> bool:
	if not (
		snapshot.size() == 3
		and GFVariantData.get_option_value(snapshot, &"schema_version") is int
		and GFVariantData.get_option_value(snapshot, &"topology") is Dictionary
		and GFVariantData.get_option_value(snapshot, &"tiles") is Array
	):
		return false
	if GFVariantData.get_option_int(snapshot, &"schema_version", 0) != SNAPSHOT_SCHEMA_VERSION:
		return false
	var topology_value: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(snapshot, &"topology")
	)
	if topology_value == null:
		return false
	var seen_cells: Dictionary = {}
	var seen_tile_ids: Dictionary = {}
	var tiles: Array = GFVariantData.get_option_array(snapshot, &"tiles")
	if tiles.size() > topology_value.get_cell_count():
		return false
	for tile_value: Variant in tiles:
		if not tile_value is Dictionary:
			return false
		var tile: Dictionary = tile_value
		if tile.size() != 7 or not tile.has(&"pos") or not tile[&"pos"] is Vector2i:
			return false
		if not _is_tile_snapshot_envelope_valid(tile, seen_tile_ids):
			return false
		var cell: Vector2i = tile[&"pos"]
		if not topology_value.contains_cell(cell) or seen_cells.has(cell):
			return false
		seen_cells[cell] = true
	return true


# --- 私有/辅助方法 ---

func _release_grid_tiles() -> void:
	_release_tiles(get_all_tiles())


func _release_tiles(tiles: Array[TileState]) -> void:
	if _tile_composition_utility == null:
		return
	for tile: TileState in tiles:
		_tile_composition_utility.release_tile(tile)


static func _duplicate_topology(source: BoardTopology) -> BoardTopology:
	var duplicated: Resource = source.duplicate(true)
	if duplicated is BoardTopology:
		var topology_copy: BoardTopology = duplicated
		return topology_copy
	return null


static func _is_tile_snapshot_envelope_valid(tile: Dictionary, seen_tile_ids: Dictionary) -> bool:
	if not (
		GFVariantData.get_option_value(tile, &"schema_version") is int
		and GFVariantData.get_option_int(tile, &"schema_version", 0) == TileState.SERIALIZATION_SCHEMA_VERSION
		and GFVariantData.get_option_value(tile, &"tile_id") is String
		and GFVariantData.get_option_value(tile, &"definition_id") is StringName
		and GFVariantData.get_option_value(tile, &"value") is int
		and GFVariantData.get_option_value(tile, &"capability_recipe_ids") is Array
		and GFVariantData.get_option_value(tile, &"capability_state") is Dictionary
	):
		return false

	var tile_id: String = GFVariantData.get_option_string(tile, &"tile_id")
	var definition_id: StringName = GFVariantData.to_string_name(
		GFVariantData.get_option_value(tile, &"definition_id")
	)
	if (
		not GFUuid.is_valid(tile_id, 7)
		or seen_tile_ids.has(tile_id)
		or definition_id == &""
		or GFVariantData.get_option_int(tile, &"value", 0) <= 0
	):
		return false
	seen_tile_ids[tile_id] = true

	var seen_recipe_ids: Dictionary = {}
	for recipe_id_value: Variant in GFVariantData.get_option_array(tile, &"capability_recipe_ids"):
		if not recipe_id_value is StringName:
			return false
		var recipe_id: StringName = recipe_id_value
		if recipe_id == &"" or seen_recipe_ids.has(recipe_id):
			return false
		seen_recipe_ids[recipe_id] = true
	if seen_recipe_ids.is_empty():
		return false

	var capability_state: Dictionary = GFVariantData.get_option_dictionary(tile, &"capability_state")
	for state_key: Variant in capability_state:
		if not state_key is StringName or not seen_recipe_ids.has(state_key):
			return false
	return true
