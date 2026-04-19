# scripts/commands/move_command.gd

## MoveCommand: 封装玩家滑动操作的具体命令，用于执行和撤销。
##
## 该命令保存移动前网格状态和分数的快照，在撤销时恢复游戏状态。
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
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var game_state_system := arch.get_system(GameStateSystem) as GameStateSystem
	
	if not is_instance_valid(grid_model):
		return null
		
	var snapshot: Dictionary = {}
	if is_instance_valid(game_state_system):
		snapshot = game_state_system.get_full_game_state(grid_model.grid_size)
	else:
		snapshot = _create_legacy_snapshot()
	set_snapshot(snapshot)
	
	_reverse_target_map.clear()
	Gf.listen_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_animation_requested)
	
	var move_sys := arch.get_system(GridMovementSystem) as GridMovementSystem
	var result: Variant = null
	if is_instance_valid(move_sys):
		result = move_sys.handle_move(_direction)
		
	Gf.unlisten_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_animation_requested)
	return result


func undo() -> Variant:
	var snapshot_value: Variant = get_snapshot()
	if not snapshot_value is Dictionary:
		return null

	var snapshot: Dictionary = snapshot_value
	if snapshot.is_empty():
		return null

	var arch := Gf.get_architecture()
	var game_state_system := arch.get_system(GameStateSystem) as GameStateSystem

	if is_instance_valid(game_state_system):
		game_state_system.restore_state(snapshot)
	else:
		_restore_legacy_snapshot(snapshot)

	var board_snapshot: Dictionary = snapshot.get(
		&"board_snapshot",
		snapshot.get(&"grid_snapshot", {})
	)
	Gf.send_simple_event(
		EventNames.BOARD_UNDO_ANIMATION_REQUESTED,
		[board_snapshot, _reverse_target_map]
	)
	Gf.send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	return null


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


# --- 私有/辅助方法 ---

func _create_legacy_snapshot() -> Dictionary:
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var status_model := arch.get_model(GameStatusModel) as GameStatusModel
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility

	if not is_instance_valid(grid_model) or not is_instance_valid(status_model):
		return {}

	return {
		&"board_snapshot": grid_model.get_snapshot(),
		&"grid_snapshot": grid_model.get_snapshot(),
		&"score": status_model.score.get_value(),
		&"move_count": status_model.move_count.get_value(),
		&"highest_tile": status_model.highest_tile.get_value(),
		&"monsters_killed": status_model.monsters_killed.get_value(),
		&"status_message": status_model.status_message.get_value(),
		&"extra_stats": status_model.extra_stats.get_value().duplicate(true),
		&"rng_state": seed_util.get_state() if is_instance_valid(seed_util) else 0,
	}


func _restore_legacy_snapshot(snapshot: Dictionary) -> void:
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var status_model := arch.get_model(GameStatusModel) as GameStatusModel
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility

	if is_instance_valid(grid_model):
		var board_snapshot: Dictionary = snapshot.get(
			&"board_snapshot",
			snapshot.get(&"grid_snapshot", {})
		)
		if not board_snapshot.is_empty():
			grid_model.restore_from_snapshot(board_snapshot)

	if is_instance_valid(status_model):
		status_model.score.set_value(snapshot.get(&"score", 0))
		status_model.move_count.set_value(snapshot.get(&"move_count", 0))
		var highest_tile := 0
		if is_instance_valid(grid_model):
			highest_tile = grid_model.get_max_player_value()
		status_model.highest_tile.set_value(snapshot.get(&"highest_tile", highest_tile))
		status_model.monsters_killed.set_value(snapshot.get(&"monsters_killed", 0))
		status_model.status_message.set_value(snapshot.get(&"status_message", ""))
		var extra_stats: Dictionary = snapshot.get(&"extra_stats", {})
		status_model.extra_stats.set_value(extra_stats.duplicate(true))

	if is_instance_valid(seed_util) and snapshot.has(&"rng_state"):
		seed_util.set_state(snapshot[&"rng_state"])


# --- 信号处理函数 ---

func _on_animation_requested(instructions: Array) -> void:
	for instr in instructions:
		if instr[&"type"] == &"MOVE":
			var from_pos: Vector2i = instr[&"from_grid_pos"]
			var key := "%d,%d" % [from_pos.x, from_pos.y]
			_reverse_target_map[key] = instr[&"to_grid_pos"]
		elif instr[&"type"] == &"MERGE":
			var from_c: Vector2i = instr[&"from_grid_pos_consumed"]
			var from_m: Vector2i = instr[&"from_grid_pos_merged"]
			var to_pos: Vector2i = instr[&"to_grid_pos"]
			_reverse_target_map["%d,%d" % [from_c.x, from_c.y]] = to_pos
			_reverse_target_map["%d,%d" % [from_m.x, from_m.y]] = to_pos
