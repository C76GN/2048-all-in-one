## BoardDraftEditCommand: 通过纯数据快照替换棋盘草稿的可撤销命令。
class_name BoardDraftEditCommand
extends GFUndoableCommand


# --- 私有变量 ---

var _draft: BoardTopologyDraftModel
var _next_cells: Array[Vector2i] = []


# --- 公共方法 ---

## @param draft: 要替换的棋盘草稿 Model。
## @param next_cells: 命令执行后的完整活跃单元快照。
## @param requested_action_name: 命令历史显示的动作名称。
func configure(
	draft: BoardTopologyDraftModel,
	next_cells: Array[Vector2i],
	requested_action_name: String
) -> BoardDraftEditCommand:
	_draft = draft
	_next_cells = next_cells.duplicate()
	action_name = requested_action_name
	return self


func execute() -> Variant:
	if not is_instance_valid(_draft):
		return false
	var current_cells: Array[Vector2i] = _draft.get_active_cells()
	if current_cells == _next_cells:
		return false
	if not set_snapshot(current_cells):
		return false
	return _draft.replace_cells(_next_cells)


func undo() -> Variant:
	if not is_instance_valid(_draft):
		return false
	var snapshot_value: Variant = get_snapshot()
	if not snapshot_value is Array:
		return false
	var snapshot_cells: Array[Vector2i] = []
	for cell_value: Variant in GFVariantData.as_array(snapshot_value):
		if not cell_value is Vector2i:
			return false
		var cell: Vector2i = cell_value
		snapshot_cells.append(cell)
	return _draft.replace_cells(snapshot_cells)


## @param execute_result: execute() 返回的执行结果。
func should_record(execute_result: Variant) -> bool:
	return execute_result is bool and execute_result
