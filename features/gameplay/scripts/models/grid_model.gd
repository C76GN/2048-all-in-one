## GridModel: 负责游戏棋盘的逻辑状态管理。
##
## 维护方块的二维网格数据，提供快照、恢复、初始化以及基础的网格查询能力。
class_name GridModel
extends "res://addons/gf/kernel/base/gf_model.gd"


# --- 常量 ---

const SNAPSHOT_SCHEMA_VERSION: int = 2


# --- 公共变量 ---

## 棋盘尺寸
var grid_size: int = 4

## 存储所有方块的二维数组 (纯数据)
var grid: Array = []

## 交互规则的纯粹引用
var interaction_rule: InteractionRule

## 移动规则的纯粹引用
var movement_rule: MovementRule


# --- 私有变量 ---

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
	interaction_rule = null
	movement_rule = null
	grid.clear()


# --- 公共方法 ---

## 初始化或重置数据
## @param size: 棋盘边长。
## @param p_interaction_rule: 当前模式使用的交互规则。
## @param p_movement_rule: 当前模式使用的移动规则。
func initialize(size: int, p_interaction_rule: InteractionRule, p_movement_rule: MovementRule) -> void:
	_release_grid_tiles()
	grid_size = size
	interaction_rule = p_interaction_rule
	movement_rule = p_movement_rule
	if interaction_rule != null:
		interaction_rule.setup(_tile_composition_utility)
	grid = _create_empty_grid(grid_size)


## 获取快照，用于撤回或保存
func get_snapshot() -> Dictionary:
	var tiles_list: Array[Dictionary] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var a_tile: TileState = row[y]
			if a_tile != null:
				var tile_snapshot: Dictionary = a_tile.to_dict()
				tile_snapshot[&"pos"] = Vector2i(x, y)
				tiles_list.append(tile_snapshot)
	return {
		&"schema_version": SNAPSHOT_SCHEMA_VERSION,
		&"grid_size": grid_size,
		&"tiles": tiles_list,
	}


## 从快照还原数据
## @param snapshot: get_snapshot() 产生的棋盘快照。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	if not _has_strict_snapshot_shape(snapshot):
		push_error("[GridModel] 拒绝恢复不符合当前严格结构的棋盘快照。")
		return
	var snapshot_schema_version: int = snapshot[&"schema_version"]
	if snapshot_schema_version != SNAPSHOT_SCHEMA_VERSION:
		push_error("[GridModel] 拒绝恢复未知棋盘快照 schema。")
		return
	if interaction_rule == null or _tile_composition_utility == null:
		push_error("[GridModel] 无法恢复方块快照：组合工具或交互规则不可用。")
		return

	var restored_size: int = snapshot[&"grid_size"]
	if restored_size <= 0:
		push_error("[GridModel] 棋盘快照 grid_size 必须大于 0。")
		return

	var restored_grid: Array = _create_empty_grid(restored_size)
	var restored_tiles: Array[TileState] = []
	var seen_tile_ids: Dictionary = {}
	var tiles_data: Array = snapshot[&"tiles"]
	if tiles_data.size() > restored_size * restored_size:
		push_error("[GridModel] 棋盘快照方块数量超过棋盘容量。")
		return
	for raw_tile_info: Variant in tiles_data:
		if not raw_tile_info is Dictionary:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照包含非 Dictionary 项。")
			return
		var tile_info: Dictionary = raw_tile_info
		if tile_info.size() != 7 or not tile_info.has(&"pos") or not tile_info[&"pos"] is Vector2i:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照条目结构无效。")
			return
		var pos: Vector2i = tile_info[&"pos"]
		if not _is_cell_in_bounds_for_size(pos, restored_size) or restored_grid[pos.x][pos.y] != null:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照位置无效或重复：%s。" % pos)
			return

		var tile_payload: Dictionary = tile_info.duplicate(true)
		var _position_erased: bool = tile_payload.erase(&"pos")
		if not tile_payload.has(&"tile_id") or not tile_payload[&"tile_id"] is String:
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照缺少严格 tile_id。")
			return
		var tile_id: String = tile_payload[&"tile_id"]
		if seen_tile_ids.has(tile_id):
			_release_tiles(restored_tiles)
			push_error("[GridModel] 方块快照包含重复 tile_id：%s。" % tile_id)
			return
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
			return
		restored_grid[pos.x][pos.y] = tile
		restored_tiles.append(tile)

	_release_grid_tiles()
	grid_size = restored_size
	grid = restored_grid


## 将指定的方块数据结构放入网格
## @param tile: 要放置的方块数据。
## @param grid_pos: 目标网格坐标。
func place_tile(tile: TileState, grid_pos: Vector2i) -> void:
	if _is_cell_in_bounds(grid_pos):
		grid[grid_pos.x][grid_pos.y] = tile


## 扩展网格尺寸
## @param new_size: 扩展后的棋盘边长。
func expand_grid(new_size: int) -> void:
	if new_size <= grid_size:
		return
	
	var new_grid: Array = _create_empty_grid(new_size)
		
	for x: int in range(grid_size):
		var source_row: Array = grid[x]
		var target_row: Array = new_grid[x]
		for y: int in range(grid_size):
			target_row[y] = source_row[y]
			
	grid_size = new_size
	grid = new_grid


## 获取所有空单元格的位置
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			if row[y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells


## 获取棋盘上的最高方块值。
func get_max_tile_value() -> int:
	var max_val: int = 0
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var tile: TileState = row[y]
			if tile != null and tile.value > max_val:
				max_val = tile.value
	return max_val


## 获取棋盘全部方块值并排序，供外部统计使用。
func get_all_tile_values() -> Array[int]:
	var values: Array[int] = []
	for x: int in range(grid_size):
		var row: Array = grid[x]
		for y: int in range(grid_size):
			var tile: TileState = row[y]
			if tile != null:
				values.append(tile.value)
	values.sort()
	return values


## GFModel 序列化协议：将模型状态导出为字典。
func to_dict() -> Dictionary:
	return get_snapshot()


## GFModel 序列化协议：从字典恢复模型状态。
## @param data: 序列化后的棋盘状态。
func from_dict(data: Dictionary) -> void:
	restore_from_snapshot(data)


# --- 私有/辅助方法 ---

func _create_empty_grid(size: int) -> Array:
	var result: Array = []
	var _resize_result: Variant = result.resize(size)
	for x: int in range(size):
		var row: Array = []
		var _row_resize_result: Variant = row.resize(size)
		row.fill(null)
		result[x] = row
	return result


func _is_cell_in_bounds(grid_pos: Vector2i) -> bool:
	return _is_cell_in_bounds_for_size(grid_pos, grid_size)


func _is_cell_in_bounds_for_size(grid_pos: Vector2i, size: int) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < size and grid_pos.y >= 0 and grid_pos.y < size


static func _has_strict_snapshot_shape(snapshot: Dictionary) -> bool:
	return (
		snapshot.size() == 3
		and snapshot.has(&"schema_version")
		and snapshot[&"schema_version"] is int
		and snapshot.has(&"grid_size")
		and snapshot[&"grid_size"] is int
		and snapshot.has(&"tiles")
		and snapshot[&"tiles"] is Array
	)


func _release_grid_tiles() -> void:
	if _tile_composition_utility == null:
		return
	var tiles: Array[TileState] = []
	for column_value: Variant in grid:
		if not column_value is Array:
			continue
		var column: Array = column_value
		for tile_value: Variant in column:
			if tile_value is TileState:
				tiles.append(tile_value)
	_release_tiles(tiles)


func _release_tiles(tiles: Array[TileState]) -> void:
	if _tile_composition_utility == null:
		return
	for tile: TileState in tiles:
		_tile_composition_utility.release_tile(tile)


static func _to_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		var vector2i_value: Vector2i = value
		return vector2i_value
	if value is Vector2:
		var vector2_value: Vector2 = value
		return Vector2i(roundi(vector2_value.x), roundi(vector2_value.y))
	if value is Dictionary:
		var data: Dictionary = value
		return Vector2i(
			GFVariantData.to_int(data.get(&"x", data.get("x", 0)), 0),
			GFVariantData.to_int(data.get(&"y", data.get("y", 0)), 0)
		)
	return Vector2i.ZERO
