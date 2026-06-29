## MoveCommand: 封装玩家滑动操作的具体命令，用于执行和撤销。
##
## 该命令保存移动前的完整游戏快照，并在撤销时恢复游戏状态。
class_name MoveCommand
extends "res://addons/gf/standard/command/gf_undoable_command.gd"


# --- 常量 ---

const _LOG_TAG: String = "MoveCommand"


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
	var grid_model: GridModel = _get_grid_model()
	var game_state_system: GameStateSystem = _get_game_state_system()

	if not is_instance_valid(grid_model) or not is_instance_valid(game_state_system):
		_log_error("GridModel 或 GameStateSystem 不可用。")
		return null

	set_snapshot(game_state_system.get_full_game_state(grid_model.grid_size))

	_reverse_target_map.clear()
	var move_sys: GridMovementSystem = _get_grid_movement_system()
	var result: Variant = null
	if is_instance_valid(move_sys):
		result = move_sys.handle_move(_direction)
		if result is MoveData:
			var move_data: MoveData = result
			_reverse_target_map = move_data.reverse_target_map.duplicate()
	return result


func undo() -> Variant:
	var snapshot_value: Variant = get_snapshot()
	if not snapshot_value is Dictionary:
		return null

	var snapshot: Dictionary = snapshot_value
	if snapshot.is_empty():
		return null

	var game_state_system: GameStateSystem = _get_game_state_system()
	if not is_instance_valid(game_state_system):
		_log_error("GameStateSystem 不可用，无法撤销。")
		return null

	game_state_system.restore_state(snapshot)

	var board_snapshot: Dictionary = _get_dictionary_with_fallback(snapshot, &"board_snapshot", &"grid_snapshot")
	send_simple_event(
		EventNames.BOARD_UNDO_ANIMATION_REQUESTED,
		[board_snapshot, _reverse_target_map]
	)
	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	return null


## 判断命令执行结果是否应该写入历史。
## @param execute_result: execute() 返回的执行结果。
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


## 从序列化字典恢复移动命令。
## @param data: serialize() 产生的命令数据。
static func deserialize(data: Dictionary) -> MoveCommand:
	var direction: Vector2i = Vector2i(
		_get_int(data, &"direction_x", 0),
		_get_int(data, &"direction_y", 0)
	)
	var cmd: MoveCommand = MoveCommand.new(direction)
	cmd.set_snapshot(data.get(&"snapshot", data.get("snapshot", {})))
	cmd._reverse_target_map = GFVariantData.to_dictionary(data.get(&"reverse_map", data.get("reverse_map", {})))
	cmd._is_baseline = GFVariantData.to_bool(data.get(&"is_baseline", data.get("is_baseline", false)), false)
	return cmd


# --- 私有/辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_game_state_system() -> GameStateSystem:
	var system_value: Object = get_system(GameStateSystem)
	if system_value is GameStateSystem:
		var game_state_system: GameStateSystem = system_value
		return game_state_system
	return null


func _get_grid_movement_system() -> GridMovementSystem:
	var system_value: Object = get_system(GridMovementSystem)
	if system_value is GridMovementSystem:
		var movement_system: GridMovementSystem = system_value
		return movement_system
	return null


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


static func _get_dictionary_with_fallback(data: Dictionary, key: StringName, fallback_key: StringName) -> Dictionary:
	var value: Variant = data.get(key, data.get(fallback_key, data.get(String(fallback_key), {})))
	return GFVariantData.to_dictionary(value)


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


func _log_error(message: String) -> void:
	var log_utility: GFLogUtility = _get_log_utility()
	if is_instance_valid(log_utility):
		log_utility.error(_LOG_TAG, message)
		return

	push_error("[%s] %s" % [_LOG_TAG, message])
