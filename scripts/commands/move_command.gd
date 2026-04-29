## MoveCommand: 封装玩家滑动操作的具体命令，用于执行和撤销。
##
## 该命令保存移动前的完整游戏快照，并在撤销时恢复游戏状态。
class_name MoveCommand
extends GFUndoableCommand


# --- 私有变量 ---

var _direction: Vector2i
var _reverse_target_map: Dictionary = {}
var _is_baseline: bool = false


# --- Godot 生命周期方法 ---

func _init(direction: Vector2i) -> void:
	_direction = direction


# --- 公共方法 ---

func get_direction() -> Vector2i:
	return _direction


func mark_as_baseline() -> void:
	_is_baseline = true


func is_baseline() -> bool:
	return _is_baseline


func execute() -> Variant:
	var grid_model := get_model(GridModel) as GridModel
	var game_state_system := get_system(GameStateSystem) as GameStateSystem

	if not is_instance_valid(grid_model) or not is_instance_valid(game_state_system):
		push_error("MoveCommand: GridModel 或 GameStateSystem 不可用。")
		return null

	set_snapshot(game_state_system.get_full_game_state(grid_model.grid_size))

	_reverse_target_map.clear()
	var architecture := _get_architecture_or_null()
	if architecture != null:
		architecture.register_simple_event_owned(self, EventNames.BOARD_ANIMATION_REQUESTED, _on_animation_requested)

	var move_sys := get_system(GridMovementSystem) as GridMovementSystem
	var result: Variant = null
	if is_instance_valid(move_sys):
		result = move_sys.handle_move(_direction)

	if architecture != null:
		architecture.unregister_owner_events(self)
	return result


func undo() -> Variant:
	var snapshot_value: Variant = get_snapshot()
	if not snapshot_value is Dictionary:
		return null

	var snapshot: Dictionary = snapshot_value
	if snapshot.is_empty():
		return null

	var game_state_system := get_system(GameStateSystem) as GameStateSystem
	if not is_instance_valid(game_state_system):
		push_error("MoveCommand: GameStateSystem 不可用，无法撤销。")
		return null

	game_state_system.restore_state(snapshot)

	var board_snapshot: Dictionary = snapshot.get(
		&"board_snapshot",
		snapshot.get(&"grid_snapshot", {})
	)
	send_simple_event(
		EventNames.BOARD_UNDO_ANIMATION_REQUESTED,
		[board_snapshot, _reverse_target_map]
	)
	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	return null


func should_record(execute_result: Variant) -> bool:
	return execute_result is MoveData


func serialize() -> Dictionary:
	return {
		&"direction_x": _direction.x,
		&"direction_y": _direction.y,
		&"snapshot": get_snapshot(),
		&"reverse_map": _reverse_target_map,
		&"is_baseline": _is_baseline,
	}


static func deserialize(data: Dictionary) -> MoveCommand:
	var direction := Vector2i(
		data.get(&"direction_x", data.get("direction_x", 0)),
		data.get(&"direction_y", data.get("direction_y", 0))
	)
	var cmd := MoveCommand.new(direction)
	cmd.set_snapshot(data.get(&"snapshot", data.get("snapshot", {})))
	cmd._reverse_target_map = data.get(&"reverse_map", data.get("reverse_map", {}))
	cmd._is_baseline = data.get(&"is_baseline", data.get("is_baseline", false))
	return cmd


# --- 信号处理函数 ---

func _on_animation_requested(instructions: Array) -> void:
	for instr in instructions:
		if instr[&"type"] == &"MOVE":
			var from_pos: Vector2i = instr[&"from_grid_pos"]
			var key := "%d,%d" % [from_pos.x, from_pos.y]
			_reverse_target_map[key] = instr[&"to_grid_pos"]
		elif instr[&"type"] == &"MERGE":
			var from_consumed: Vector2i = instr[&"from_grid_pos_consumed"]
			var from_merged: Vector2i = instr[&"from_grid_pos_merged"]
			var to_pos: Vector2i = instr[&"to_grid_pos"]
			_reverse_target_map["%d,%d" % [from_consumed.x, from_consumed.y]] = to_pos
			_reverse_target_map["%d,%d" % [from_merged.x, from_merged.y]] = to_pos
