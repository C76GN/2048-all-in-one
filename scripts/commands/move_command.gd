# scripts/commands/move_command.gd

## MoveCommand: 封装玩家滑动操作的具体命令，用于执行和撤销。
##
## 该命令保存移动前网格状态和分数的快照，在撤销时恢复游戏状态。
class_name MoveCommand
extends GFUndoableCommand

var _direction: Vector2i


func _init(direction: Vector2i) -> void:
	_direction = direction


func get_direction() -> Vector2i:
	return _direction


func execute() -> Variant:
	var arch := Gf.get_architecture()
	var grid_model := arch.get_model(GridModel) as GridModel
	var status_model := arch.get_model(GameStatusModel) as GameStatusModel
	
	if not grid_model or not status_model:
		return null
		
	# 1. 保存执行前的状态快照 (含网格数据与分数/步数)
	var snapshot := {
		&"grid_snapshot": grid_model.get_snapshot(),
		&"score": status_model.score.get_value(),
		&"move_count": status_model.move_count.get_value()
	}
	set_snapshot(snapshot)
	
	# 2. 调用系统执行移动逻辑
	var move_sys := arch.get_system(GridMovementSystem) as GridMovementSystem
	if move_sys:
		return move_sys.handle_move(_direction)
		
	return null


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
	
	# 2. 发送全量刷新事件，通知视图层 (GameBoard) 彻底重绘
	Gf.send_simple_event(EventNames.BOARD_REFRESH_REQUESTED, snapshot.grid_snapshot)

func serialize() -> Dictionary:
	return {
		&"direction_x": _direction.x,
		&"direction_y": _direction.y,
		&"snapshot": get_snapshot()
	}

static func deserialize(data: Dictionary) -> MoveCommand:
	var cmd := MoveCommand.new(Vector2i(data.get("direction_x", 0), data.get("direction_y", 0)))
	cmd.set_snapshot(data.get("snapshot"))
	return cmd
