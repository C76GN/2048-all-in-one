## BoardTopology: 定义一张棋盘中可参与玩法的活跃单元。
##
## 坐标必须规范化到以 (0, 0) 为包围盒左上角。拓扑只描述空间，不保存方块状态。
class_name BoardTopology
extends Resource


# --- 常量 ---

const SERIALIZATION_SCHEMA_VERSION: int = 1
## 领域/工具拓扑的序列化防御上限。它不代表当前可玩棋盘容量。
const MAX_SERIALIZED_CELL_COUNT: int = 262144
## 规范化坐标的序列化防御上限，确保包围盒加一和面积计算不会溢出。
const MAX_SERIALIZED_COORDINATE: int = MAX_SERIALIZED_CELL_COUNT - 1
## 当前 GridModel、逐格表现和无障碍密集投影共同接受的可玩预算。
const MAX_PLAYABLE_CELL_COUNT: int = 256
const MAX_PLAYABLE_BOUNDS_WIDTH: int = 256
const MAX_PLAYABLE_BOUNDS_HEIGHT: int = 256
const MAX_PLAYABLE_BOUNDS_AREA: int = 256


# --- 导出变量 ---

## 拓扑的稳定语义 ID。自定义棋盘仍会附加内容指纹以形成完整统计键。
@export var topology_id: StringName = &""

## 规范化、无重复的活跃单元列表。
@export var active_cells: Array[Vector2i]:
	get:
		return _active_cells.duplicate()
	set(value):
		_active_cells = value.duplicate()
		_cached_cell_count = -1
		_cached_bounds_size = Vector2i(-1, -1)
		_cached_content_fingerprint = ""
		_cached_row_range_count = -1


# --- 私有变量 ---

var _cell_lookup: Dictionary = {}
var _cached_cell_count: int = -1
var _cached_bounds_size: Vector2i = Vector2i(-1, -1)
var _cached_content_fingerprint: String = ""
var _row_ranges: Dictionary = {}
var _cached_row_range_count: int = -1
var _active_cells: Array[Vector2i] = []


# --- 构造方法 ---

## 创建任意矩形拓扑。
## @param size: 矩形的宽高，两个轴都必须大于零。
## @param requested_id: 可选稳定语义 ID；为空时按尺寸生成。
static func create_rectangle(size: Vector2i, requested_id: StringName = &"") -> BoardTopology:
	var topology: BoardTopology = BoardTopology.new()
	topology.topology_id = (
		requested_id
		if requested_id != &""
		else StringName("board.rectangle.%dx%d" % [size.x, size.y])
	)
	if (
		size.x <= 0
		or size.y <= 0
		or size.x > MAX_SERIALIZED_CELL_COUNT
		or size.y > MAX_SERIALIZED_CELL_COUNT
		or size.x * size.y > MAX_SERIALIZED_CELL_COUNT
	):
		return topology

	var cells: Array[Vector2i] = []
	for y: int in range(size.y):
		for x: int in range(size.x):
			cells.append(Vector2i(x, y))
	topology.active_cells = cells
	return topology


## 创建中心臂宽为 arm_thickness、四侧臂长为 arm_length 的十字形拓扑。
## @param arm_length: 中心区域向四侧延伸的单元数。
## @param arm_thickness: 中心横纵臂的宽度。
## @param requested_id: 可选稳定语义 ID；为空时按参数生成。
static func create_cross(
	arm_length: int,
	arm_thickness: int = 1,
	requested_id: StringName = &""
) -> BoardTopology:
	var topology: BoardTopology = BoardTopology.new()
	topology.topology_id = (
		requested_id
		if requested_id != &""
		else StringName("board.cross.%d.%d" % [arm_length, arm_thickness])
	)
	if (
		arm_length < 0
		or arm_thickness <= 0
		or arm_length > MAX_SERIALIZED_CELL_COUNT
		or arm_thickness > MAX_SERIALIZED_CELL_COUNT
	):
		return topology

	var side: int = arm_length * 2 + arm_thickness
	var cell_count: int = 2 * side * arm_thickness - arm_thickness * arm_thickness
	if cell_count > MAX_SERIALIZED_CELL_COUNT:
		return topology
	var center_start: int = arm_length
	var center_end: int = center_start + arm_thickness
	var cells: Array[Vector2i] = []
	for y: int in range(side):
		for x: int in range(side):
			if (x >= center_start and x < center_end) or (y >= center_start and y < center_end):
				cells.append(Vector2i(x, y))
	topology.active_cells = cells
	return topology


## 从玩家或工具提供的单元创建规范化拓扑。
## @param cells: 待平移、去重并按行优先排序的原始坐标。
## @param requested_id: 可选稳定语义 ID；为空时按内容指纹生成。
static func create_custom(
	cells: Array[Vector2i],
	requested_id: StringName = &""
) -> BoardTopology:
	var topology: BoardTopology = BoardTopology.new()
	topology.active_cells = _canonicalize_cells(cells)
	if requested_id != &"":
		topology.topology_id = requested_id
	else:
		topology.topology_id = StringName("board.custom.%s" % topology.get_content_fingerprint())
	return topology


## 从当前严格持久化结构恢复拓扑；无效数据返回 null。
## @param data: BoardTopology.to_dict() 产生的严格结构。
static func from_dict(data: Dictionary) -> BoardTopology:
	if not _has_strict_serialized_shape(data):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SERIALIZATION_SCHEMA_VERSION:
		return null
	var cell_values: Array = GFVariantData.get_option_array(data, &"active_cells")
	if cell_values.is_empty() or cell_values.size() > MAX_SERIALIZED_CELL_COUNT:
		return null

	var topology: BoardTopology = BoardTopology.new()
	topology.topology_id = StringName(GFVariantData.get_option_string(data, &"topology_id"))
	var cells: Array[Vector2i] = []
	for cell_value: Variant in cell_values:
		if not cell_value is Vector2i:
			return null
		var cell: Vector2i = cell_value
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x > MAX_SERIALIZED_COORDINATE
			or cell.y > MAX_SERIALIZED_COORDINATE
		):
			return null
		cells.append(cell)
	topology.active_cells = cells

	if not topology.get_validation_report().is_ok():
		return null
	return topology


# --- 公共方法 ---

## 返回不允许调用方修改资源内部数组的活跃单元副本。
func get_active_cells() -> Array[Vector2i]:
	return _active_cells.duplicate()


func get_cell_count() -> int:
	return _active_cells.size()


## @param cell: 待查询的棋盘坐标。
func contains_cell(cell: Vector2i) -> bool:
	_ensure_cell_lookup()
	return _cell_lookup.has(cell)


## 返回与给定单元矩形相交的活跃坐标，结果保持行优先顺序。
##
## 该查询使用按行缓存和二分边界，供超大稀疏棋盘的可见区域渲染使用，
## 不要求调用方遍历全部 active_cells。
## @param cell_rect: 左闭右开的棋盘单元矩形。
func get_cells_in_rect(cell_rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if cell_rect.size.x <= 0 or cell_rect.size.y <= 0 or _active_cells.is_empty():
		return result

	var bounds_size: Vector2i = get_bounds_size()
	var query_start: Vector2i = Vector2i(
		clampi(cell_rect.position.x, 0, bounds_size.x),
		clampi(cell_rect.position.y, 0, bounds_size.y)
	)
	var requested_end: Vector2i = cell_rect.position + cell_rect.size
	var query_end: Vector2i = Vector2i(
		clampi(requested_end.x, 0, bounds_size.x),
		clampi(requested_end.y, 0, bounds_size.y)
	)
	if query_start.x >= query_end.x or query_start.y >= query_end.y:
		return result

	_ensure_row_ranges()
	for y: int in range(query_start.y, query_end.y):
		var row_range_value: Variant = _row_ranges.get(y)
		if not row_range_value is Vector2i:
			continue
		var row_range: Vector2i = row_range_value
		var cell_index: int = _lower_bound_row_x(
			row_range.x,
			row_range.y,
			query_start.x
		)
		while cell_index < row_range.y:
			var cell: Vector2i = _active_cells[cell_index]
			if cell.x >= query_end.x:
				break
			result.append(cell)
			cell_index += 1
	return result


## 返回以 (0, 0) 为起点的最小包围盒尺寸。
func get_bounds_size() -> Vector2i:
	if _cached_bounds_size.x >= 0 and _cached_bounds_size.y >= 0:
		return _cached_bounds_size
	var maximum: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in _active_cells:
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	_cached_bounds_size = (
		maximum + Vector2i.ONE
		if maximum.x >= 0 and maximum.y >= 0
		else Vector2i.ZERO
	)
	return _cached_bounds_size


## 判断当前拓扑是否完整填满其矩形包围盒。
func is_rectangle() -> bool:
	var bounds_size: Vector2i = get_bounds_size()
	return (
		bounds_size.x > 0
		and bounds_size.y > 0
		and _active_cells.size() == bounds_size.x * bounds_size.y
	)


## 按移动方向返回连续 lane。每条 lane 从移动前沿向后排列，空洞会切断 lane。
## @param direction: 仅接受 LEFT、RIGHT、UP、DOWN 四个单位方向。
func get_move_lanes(direction: Vector2i) -> Array:
	if not _is_cardinal_direction(direction):
		return []

	_ensure_cell_lookup()
	var cell_lookup: Dictionary = _cell_lookup

	var starts: Array[Vector2i] = []
	for cell: Vector2i in _active_cells:
		if not cell_lookup.has(cell + direction):
			starts.append(cell)

	if direction.x != 0:
		starts.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
			return left.y < right.y or (left.y == right.y and left.x < right.x)
		)
	else:
		starts.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
			return left.x < right.x or (left.x == right.x and left.y < right.y)
		)

	var lanes: Array = []
	for start: Vector2i in starts:
		var lane: Array[Vector2i] = []
		var current: Vector2i = start
		while cell_lookup.has(current):
			lane.append(current)
			current -= direction
		lanes.append(lane)
	return lanes


## 内容指纹只取规范化单元，不受 topology_id 影响。
func get_content_fingerprint() -> String:
	if not _cached_content_fingerprint.is_empty():
		return _cached_content_fingerprint
	var parts: PackedStringArray = []
	if parts.resize(_active_cells.size()) != OK:
		return ""
	for index: int in range(_active_cells.size()):
		var cell: Vector2i = _active_cells[index]
		parts[index] = "%d,%d" % [cell.x, cell.y]
	_cached_content_fingerprint = ";".join(parts).sha256_text().substr(0, 16)
	return _cached_content_fingerprint


## 统计、排行榜和关卡身份使用 ID 与内容指纹的组合，防止自定义 ID 碰撞。
func get_stable_key() -> String:
	return "%s@%s" % [String(topology_id), get_content_fingerprint()]


func get_size_label() -> String:
	var size: Vector2i = get_bounds_size()
	if is_rectangle():
		return "%dx%d" % [size.x, size.y]
	return "%dx%d / %d" % [size.x, size.y, get_cell_count()]


## 转换为可由 GFSaveProfile、Command History 和回放持久化的严格字典。
func to_dict() -> Dictionary:
	return {
		&"schema_version": SERIALIZATION_SCHEMA_VERSION,
		&"topology_id": String(topology_id),
		&"active_cells": _active_cells.duplicate(),
	}


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"BoardTopology:%s" % topology_id,
		{
			&"topology_id": topology_id,
			&"resource_path": resource_path,
		}
	)
	if topology_id == &"":
		var _missing_id_issue: RefCounted = report.add_error(
			&"missing_topology_id",
			"topology_id 不能为空。",
			&"topology_id",
			resource_path
		)
	if _active_cells.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_active_cells",
			"active_cells 不能为空。",
			&"active_cells",
			resource_path
		)
		return report
	if _active_cells.size() > MAX_SERIALIZED_CELL_COUNT:
		var _capacity_issue: RefCounted = report.add_error(
			&"cell_capacity_exceeded",
			"active_cells 超过序列化安全上限 %d。" % MAX_SERIALIZED_CELL_COUNT,
			&"active_cells",
			resource_path
		)

	var seen: Dictionary = {}
	var minimum: Vector2i = _active_cells[0]
	var previous: Vector2i = Vector2i(-1, -1)
	for index: int in range(_active_cells.size()):
		var cell: Vector2i = _active_cells[index]
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		if cell.x < 0 or cell.y < 0:
			var _negative_issue: RefCounted = report.add_error(
				&"negative_cell",
				"活跃单元不能使用负坐标：%s。" % cell,
				index,
				resource_path
			)
		elif (
			cell.x > MAX_SERIALIZED_COORDINATE
			or cell.y > MAX_SERIALIZED_COORDINATE
		):
			var _coordinate_capacity_issue: RefCounted = report.add_error(
				&"coordinate_capacity_exceeded",
				"活跃单元坐标超过序列化安全上限 %d：%s。" % [
					MAX_SERIALIZED_COORDINATE,
					cell,
				],
				index,
				resource_path
			)
		if seen.has(cell):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_cell",
				"活跃单元重复：%s。" % cell,
				index,
				resource_path
			)
		seen[cell] = true
		if index > 0 and not _is_row_major_before(previous, cell):
			var _order_issue: RefCounted = report.add_error(
				&"non_canonical_cell_order",
				"active_cells 必须按 y、x 升序保存。",
				index,
				resource_path
			)
		previous = cell

	if minimum != Vector2i.ZERO:
		var _origin_issue: RefCounted = report.add_error(
			&"non_canonical_origin",
			"活跃单元包围盒必须从 (0, 0) 开始。",
			&"active_cells",
			resource_path
		)
	return report


## 返回当前逐格玩法、表现与密集辅助投影共享的严格预算报告。
##
## 领域拓扑可以合法表示更大的稀疏空间；只有进入 GridModel 或需要逐格物化
## 时才必须通过本报告。调用方不得只检查活跃格数量而忽略坐标和包围盒面积。
func get_playable_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"PlayableBoardTopology:%s" % topology_id,
		{
			&"topology_id": topology_id,
			&"resource_path": resource_path,
			&"max_cell_count": MAX_PLAYABLE_CELL_COUNT,
			&"max_bounds_width": MAX_PLAYABLE_BOUNDS_WIDTH,
			&"max_bounds_height": MAX_PLAYABLE_BOUNDS_HEIGHT,
			&"max_bounds_area": MAX_PLAYABLE_BOUNDS_AREA,
		}
	)
	var _domain_report: RefCounted = report.merge(get_validation_report(), false)
	if not report.is_ok():
		return report

	var bounds_size: Vector2i = get_bounds_size()
	var bounds_area: int = bounds_size.x * bounds_size.y
	if _active_cells.size() > MAX_PLAYABLE_CELL_COUNT:
		var _playable_cell_issue: RefCounted = report.add_error(
			&"playable_cell_capacity_exceeded",
			"可玩棋盘活跃单元超过上限 %d。" % MAX_PLAYABLE_CELL_COUNT,
			&"active_cells",
			resource_path
		)
	var first_outside_coordinate: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in _active_cells:
		if (
			cell.x >= MAX_PLAYABLE_BOUNDS_WIDTH
			or cell.y >= MAX_PLAYABLE_BOUNDS_HEIGHT
		):
			first_outside_coordinate = cell
			break
	if first_outside_coordinate.x >= 0:
		var _playable_coordinate_issue: RefCounted = report.add_error(
			&"playable_coordinate_capacity_exceeded",
			"活跃单元坐标超出当前可玩范围：%s。" % first_outside_coordinate,
			&"active_cells",
			resource_path
		)
	if bounds_size.x > MAX_PLAYABLE_BOUNDS_WIDTH:
		var _playable_width_issue: RefCounted = report.add_error(
			&"playable_bounds_width_exceeded",
			"可玩棋盘包围盒宽度 %d 超过上限 %d。" % [
				bounds_size.x,
				MAX_PLAYABLE_BOUNDS_WIDTH,
			],
			&"active_cells",
			resource_path
		)
	if bounds_size.y > MAX_PLAYABLE_BOUNDS_HEIGHT:
		var _playable_height_issue: RefCounted = report.add_error(
			&"playable_bounds_height_exceeded",
			"可玩棋盘包围盒高度 %d 超过上限 %d。" % [
				bounds_size.y,
				MAX_PLAYABLE_BOUNDS_HEIGHT,
			],
			&"active_cells",
			resource_path
		)
	if bounds_area > MAX_PLAYABLE_BOUNDS_AREA:
		var _playable_area_issue: RefCounted = report.add_error(
			&"playable_bounds_area_exceeded",
			"可玩棋盘包围盒面积 %d 超过逐格物化上限 %d。" % [
				bounds_area,
				MAX_PLAYABLE_BOUNDS_AREA,
			],
			&"active_cells",
			resource_path
		)
	report.extra_fields = {
		&"cell_count": _active_cells.size(),
		&"bounds_size": bounds_size,
		&"bounds_area": bounds_area,
	}
	return report


# --- 私有/辅助方法 ---

static func _canonicalize_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.is_empty() or cells.size() > MAX_SERIALIZED_CELL_COUNT:
		return []
	var minimum: Vector2i = cells[0]
	var maximum: Vector2i = cells[0]
	for cell: Vector2i in cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	if (
		maximum.x - minimum.x > MAX_SERIALIZED_COORDINATE
		or maximum.y - minimum.y > MAX_SERIALIZED_COORDINATE
	):
		return []

	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		var normalized_cell: Vector2i = cell - minimum
		if seen.has(normalized_cell):
			continue
		seen[normalized_cell] = true
		result.append(normalized_cell)
	result.sort_custom(_is_row_major_before)
	return result


func _ensure_cell_lookup() -> void:
	if _cached_cell_count == _active_cells.size():
		return
	_cell_lookup.clear()
	for cell: Vector2i in _active_cells:
		_cell_lookup[cell] = true
	_cached_cell_count = _active_cells.size()


func _ensure_row_ranges() -> void:
	if _cached_row_range_count == _active_cells.size():
		return
	_row_ranges.clear()
	var row_start: int = 0
	while row_start < _active_cells.size():
		var row_y: int = _active_cells[row_start].y
		var row_end: int = row_start + 1
		while row_end < _active_cells.size() and _active_cells[row_end].y == row_y:
			row_end += 1
		_row_ranges[row_y] = Vector2i(row_start, row_end)
		row_start = row_end
	_cached_row_range_count = _active_cells.size()


func _lower_bound_row_x(row_start: int, row_end: int, target_x: int) -> int:
	var low: int = row_start
	var high: int = row_end
	while low < high:
		var middle: int = low + ((high - low) >> 1)
		if _active_cells[middle].x < target_x:
			low = middle + 1
		else:
			high = middle
	return low


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)


static func _is_cardinal_direction(direction: Vector2i) -> bool:
	return (
		direction == Vector2i.LEFT
		or direction == Vector2i.RIGHT
		or direction == Vector2i.UP
		or direction == Vector2i.DOWN
	)


static func _has_strict_serialized_shape(data: Dictionary) -> bool:
	return (
		data.size() == 3
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"topology_id") is String
		and GFVariantData.get_option_value(data, &"active_cells") is Array
	)
