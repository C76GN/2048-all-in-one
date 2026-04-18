# scripts/commands/move_command.gd

## MoveCommand: 封装玩家滑动操作的具体命令，用于执行和撤销。
##
## 该命令保存移动前网格状态和分数的快照，在撤销时恢复游戏状态。
class_name MoveCommand
extends GFUndoableCommand

var _direction: Vector2i
var _reverse_target_map: Dictionary = {}
var _is_baseline: bool = false

func _init(direction: Vector2i) -> void:
	_direction = direction


func get_direction() -> Vector2i:
	return _direction


func mark_as_baseline() -> void:
	_is_baseline = true


func is_baseline() -> bool:
	return _is_baseline


func execute() -> Variant:
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var status_model := arch.get_model(GameStatusModel) as GameStatusModel
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility
	
	if not grid_model or not status_model:
		return null
		
	# 1. 保存执行前的状态快照 (含网格数据与分数/步数/随机数种子状态)
	var snapshot := {
		&"grid_snapshot": grid_model.get_snapshot(),
		&"score": status_model.score.get_value(),
		&"move_count": status_model.move_count.get_value(),
		&"rng_state": seed_util.get_state() if seed_util else 0
	}
	set_snapshot(snapshot)
	
	# 2. 临时监听动画请求获取来源点与目标点的映射
	_reverse_target_map.clear()
	Gf.listen_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_animation_requested)
	
	# 3. 调用系统执行移动逻辑
	var move_sys := arch.get_system(GridMovementSystem) as GridMovementSystem
	var result: Variant = null
	if move_sys:
		result = move_sys.handle_move(_direction)
		
	Gf.unlisten_simple(EventNames.BOARD_ANIMATION_REQUESTED, _on_animation_requested)
	return result

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

func undo() -> void:
	var snapshot = get_snapshot() as Dictionary
	if not snapshot:
		return
		
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var status_model := arch.get_model(GameStatusModel) as GameStatusModel
	
	if not grid_model or not status_model:
		return

	# 1. 还原 Model 数据
	grid_model.restore_from_snapshot(snapshot.grid_snapshot)
	status_model.score.set_value(snapshot.score)
	status_model.move_count.set_value(snapshot.move_count)
	
	var seed_util := arch.get_utility(GFSeedUtility) as GFSeedUtility
	if seed_util and snapshot.has(&"rng_state"):
		seed_util.set_state(snapshot.rng_state)
	
	# 2. 发送撤回动画事件，包含恢复后的快照和需要做反向平移的映射表
	Gf.send_simple_event(EventNames.BOARD_UNDO_ANIMATION_REQUESTED, [snapshot.grid_snapshot, _reverse_target_map])

func serialize() -> Dictionary:
	return {
		&"direction_x": _direction.x,
		&"direction_y": _direction.y,
		&"snapshot": get_snapshot(),
		&"reverse_map": _reverse_target_map,
		&"is_baseline": _is_baseline,
	}

static func deserialize(data: Dictionary) -> MoveCommand:
	var cmd := MoveCommand.new(Vector2i(data.get("direction_x", 0), data.get("direction_y", 0)))
	cmd.set_snapshot(data.get("snapshot"))
	cmd._reverse_target_map = data.get("reverse_map", {})
	cmd._is_baseline = data.get("is_baseline", false)
	return cmd
