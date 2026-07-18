## BoardTopologyDraftModel: 玩家棋盘编辑器中的可变稀疏拓扑草稿。
##
## 草稿坐标保留在模板画布内；提交时由 BoardTopology 统一规范化到左上原点。
class_name BoardTopologyDraftModel
extends RefCounted


# --- 信号 ---

signal changed


# --- 私有变量 ---

var _topology_template: BoardTopologyTemplate
var _canvas_size: Vector2i = Vector2i.ZERO
var _active_cells: Dictionary = {}


# --- 公共方法 ---

## 以模式模板和可选初始拓扑配置草稿。
## @param topology_template: 当前模式允许的棋盘拓扑范围。
## @param initial_topology: 可选的初始棋盘形状。
func configure(
	topology_template: BoardTopologyTemplate,
	initial_topology: BoardTopology = null
) -> bool:
	if not is_instance_valid(topology_template):
		return false
	if not topology_template.get_validation_report().is_ok():
		return false

	_topology_template = topology_template
	_canvas_size = _resolve_canvas_size(topology_template)
	if _canvas_size.x <= 0 or _canvas_size.y <= 0:
		return false

	var initial_cells: Array[Vector2i] = []
	if is_instance_valid(initial_topology):
		initial_cells = initial_topology.get_active_cells()
	else:
		var default_topology: BoardTopology = topology_template.create_topology()
		if is_instance_valid(default_topology):
			initial_cells = default_topology.get_active_cells()
	return replace_cells(initial_cells)


func get_canvas_size() -> Vector2i:
	return _canvas_size


func get_active_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value: Variant in _active_cells.keys():
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			result.append(cell)
	result.sort_custom(_is_row_major_before)
	return result


## @param cell: 画布坐标。
func has_cell(cell: Vector2i) -> bool:
	return _active_cells.has(cell)


## 原子替换画布内全部活跃单元；允许空草稿，但拒绝越界输入。
## @param cells: 新的画布坐标集合。
func replace_cells(cells: Array[Vector2i]) -> bool:
	var next_cells: Dictionary = {}
	for cell: Vector2i in cells:
		if not _is_cell_in_canvas(cell):
			return false
		next_cells[cell] = true
	if next_cells == _active_cells:
		return true
	_active_cells = next_cells
	changed.emit()
	return true


## 批量绘制或擦除单元，返回真实发生变化的单元数。
## @param cells: 要更新的画布坐标集合。
## @param active: true 表示绘制，false 表示擦除。
func set_cells_active(cells: Array[Vector2i], active: bool) -> int:
	for cell: Vector2i in cells:
		if not _is_cell_in_canvas(cell):
			return 0

	var changed_count: int = 0
	for cell: Vector2i in cells:
		if active and not _active_cells.has(cell):
			_active_cells[cell] = true
			changed_count += 1
		elif not active and _active_cells.erase(cell):
			changed_count += 1
	if changed_count > 0:
		changed.emit()
	return changed_count


## 将当前活跃单元平移到画布左上原点。
func get_normalized_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = get_active_cells()
	if cells.is_empty():
		return cells
	var minimum: Vector2i = cells[0]
	for cell: Vector2i in cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	for index: int in range(cells.size()):
		cells[index] -= minimum
	return cells


## 构造当前规范化拓扑；草稿不满足模板时返回 null。
## @param requested_id: 可选的稳定拓扑 ID。
func create_topology(requested_id: StringName = &"") -> BoardTopology:
	var topology: BoardTopology = BoardTopology.create_custom(get_active_cells(), requested_id)
	if not is_instance_valid(_topology_template):
		return null
	if not _topology_template.accepts_topology(topology):
		return null
	return topology


## 返回 UI 可直接消费的草稿诊断，不暴露可变对象引用。
func get_validation_state() -> Dictionary:
	var cells: Array[Vector2i] = get_active_cells()
	var topology: BoardTopology = BoardTopology.create_custom(cells)
	var bounds_size: Vector2i = topology.get_bounds_size()
	var component_count: int = get_connected_component_count()
	var valid: bool = (
		is_instance_valid(_topology_template)
		and _topology_template.accepts_topology(topology)
	)
	var reason: StringName = &"ok"
	if cells.is_empty():
		reason = &"empty"
	elif not valid:
		reason = &"template_rejected"
	elif component_count > 1:
		reason = &"disconnected"
	return {
		"valid": valid,
		"reason": reason,
		"cell_count": cells.size(),
		"bounds_size": bounds_size,
		"component_count": component_count,
		"normalized": cells == get_normalized_cells(),
	}


## 按四向邻接统计连通分量；空草稿返回 0。
func get_connected_component_count() -> int:
	if _active_cells.is_empty():
		return 0

	var remaining: Dictionary = _active_cells.duplicate()
	var component_count: int = 0
	while not remaining.is_empty():
		var first_value: Variant = remaining.keys()[0]
		if not first_value is Vector2i:
			break
		var first: Vector2i = first_value
		var _first_removed: bool = remaining.erase(first)
		component_count += 1

		var queue: Array[Vector2i] = [first]
		var queue_index: int = 0
		while queue_index < queue.size():
			var cell: Vector2i = queue[queue_index]
			queue_index += 1
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if not remaining.erase(neighbor):
					continue
				queue.append(neighbor)
	return component_count


# --- 私有/辅助方法 ---

func _is_cell_in_canvas(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < _canvas_size.x
		and cell.y < _canvas_size.y
	)


static func _resolve_canvas_size(topology_template: BoardTopologyTemplate) -> Vector2i:
	if topology_template.kind == BoardTopologyTemplate.Kind.FIXED:
		if is_instance_valid(topology_template.fixed_topology):
			return topology_template.fixed_topology.get_bounds_size()
		return Vector2i.ZERO
	return topology_template.max_size


static func _is_row_major_before(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)
