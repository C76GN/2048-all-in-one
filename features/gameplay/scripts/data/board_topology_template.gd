## BoardTopologyTemplate: 定义模式允许如何创建棋盘拓扑。
class_name BoardTopologyTemplate
extends Resource


# --- 枚举 ---

enum Kind {
	RESIZABLE_RECTANGLE,
	FIXED,
}


# --- 导出变量 ---

@export var template_id: StringName = &"board_template.default"
@export var kind: Kind = Kind.RESIZABLE_RECTANGLE

@export_group("可变矩形")
@export var default_size: Vector2i = Vector2i(4, 4)
@export var min_size: Vector2i = Vector2i(3, 3)
@export var max_size: Vector2i = Vector2i(8, 8)
@export var allow_custom_topology: bool = false

@export_group("固定拓扑")
@export var fixed_topology: BoardTopology


# --- 公共方法 ---

## @param requested_size: 可变矩形请求的宽高；零向量表示使用默认尺寸。
func create_topology(requested_size: Vector2i = Vector2i.ZERO) -> BoardTopology:
	if not get_validation_report().is_ok():
		return null

	if kind == Kind.FIXED:
		var duplicated: Resource = fixed_topology.duplicate(true)
		if duplicated is BoardTopology:
			var fixed_copy: BoardTopology = duplicated
			return fixed_copy
		return null

	var resolved_size: Vector2i = default_size if requested_size == Vector2i.ZERO else requested_size
	if not supports_size(resolved_size):
		return null
	return BoardTopology.create_rectangle(
		resolved_size,
		StringName("%s.%dx%d" % [template_id, resolved_size.x, resolved_size.y])
	)


## @param size: 待检查的矩形宽高。
func supports_size(size: Vector2i) -> bool:
	return (
		kind == Kind.RESIZABLE_RECTANGLE
		and size.x >= min_size.x
		and size.y >= min_size.y
		and size.x <= max_size.x
		and size.y <= max_size.y
		and _is_size_within_capacity(size)
	)


## @param topology: 待检查的完整棋盘拓扑。
func accepts_topology(topology: BoardTopology) -> bool:
	if not is_instance_valid(topology) or not topology.get_validation_report().is_ok():
		return false
	if kind == Kind.FIXED:
		return (
			is_instance_valid(fixed_topology)
			and topology.get_content_fingerprint() == fixed_topology.get_content_fingerprint()
		)
	if not supports_size(topology.get_bounds_size()):
		return false
	return topology.is_rectangle() or allow_custom_topology


## 当前模式选择 UI 使用单轴尺寸选项；仅方形范围可提供该选项。
func get_square_size_options() -> Array[int]:
	var result: Array[int] = []
	if (
		kind != Kind.RESIZABLE_RECTANGLE
		or default_size.x != default_size.y
		or min_size.x != min_size.y
		or max_size.x != max_size.y
	):
		return result
	for side: int in range(min_size.x, max_size.x + 1):
		result.append(side)
	return result


func get_default_square_size() -> int:
	return default_size.x if default_size.x == default_size.y else 0


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"BoardTopologyTemplate:%s" % template_id,
		{
			&"template_id": template_id,
			&"resource_path": resource_path,
		}
	)
	if template_id == &"":
		var _id_issue: RefCounted = report.add_error(
			&"missing_template_id",
			"template_id 不能为空。",
			&"template_id",
			resource_path
		)

	if kind == Kind.FIXED:
		if not is_instance_valid(fixed_topology):
			var _fixed_issue: RefCounted = report.add_error(
				&"missing_fixed_topology",
				"固定模板必须配置 fixed_topology。",
				&"fixed_topology",
				resource_path
			)
		else:
			var _merged_report: RefCounted = report.merge(fixed_topology.get_validation_report(), false)
		return report

	if min_size.x <= 0 or min_size.y <= 0:
		var _min_issue: RefCounted = report.add_error(
			&"invalid_min_size",
			"min_size 两个轴都必须大于 0。",
			&"min_size",
			resource_path
		)
	if max_size.x < min_size.x or max_size.y < min_size.y:
		var _max_issue: RefCounted = report.add_error(
			&"invalid_max_size",
			"max_size 不能小于 min_size。",
			&"max_size",
			resource_path
		)
	elif not _is_size_within_capacity(max_size):
		var _capacity_issue: RefCounted = report.add_error(
			&"topology_capacity_exceeded",
			"max_size 超过 BoardTopology 的活跃单元安全上限。",
			&"max_size",
			resource_path
		)
	if not supports_size(default_size):
		var _default_issue: RefCounted = report.add_error(
			&"invalid_default_size",
			"default_size 必须位于 min_size 与 max_size 之间。",
			&"default_size",
			resource_path
		)
	return report


# --- 私有/辅助方法 ---

static func _is_size_within_capacity(size: Vector2i) -> bool:
	return (
		size.x > 0
		and size.y > 0
		and size.x <= BoardTopology.MAX_CELL_COUNT
		and size.y <= BoardTopology.MAX_CELL_COUNT
		and size.x * size.y <= BoardTopology.MAX_CELL_COUNT
	)
