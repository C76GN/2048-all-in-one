## PlayerInputSystem: 负责处理标准模式下的玩家输入，并将抽象动作转换为游戏命令。
class_name PlayerInputSystem
extends GFSystem


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://resources/input/gameplay_input_context.tres")
const ACTION_PAUSE: StringName = &"pause"
const ACTION_UNDO: StringName = &"undo"
const ACTION_SAVE_BOOKMARK: StringName = &"save_bookmark"
const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"


# --- 私有变量 ---

var _input_mapping: GFInputMappingUtility
var _is_playing: bool = false
var _is_active: bool = false


# --- Godot 生命周期方法 ---

func ready() -> void:
	_input_mapping = get_utility(GFInputMappingUtility) as GFInputMappingUtility
	if is_instance_valid(_input_mapping):
		_input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)


func dispose() -> void:
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)

	if is_instance_valid(_input_mapping):
		_input_mapping.disable_context(GAMEPLAY_INPUT_CONTEXT)
	_input_mapping = null


func tick(_delta: float) -> void:
	if not _is_active or not is_instance_valid(_input_mapping):
		return

	if _consume_action(ACTION_PAUSE):
		send_simple_event(EventNames.UI_PAUSE_REQUESTED)

	if not _is_playing:
		return

	if _consume_action(ACTION_UNDO):
		send_simple_event(EventNames.UNDO_REQUESTED)
		return

	if _consume_action(ACTION_SAVE_BOOKMARK):
		send_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED)
		return

	var direction := Vector2i.ZERO
	if _consume_action(ACTION_MOVE_UP):
		direction = Vector2i.UP
	elif _consume_action(ACTION_MOVE_DOWN):
		direction = Vector2i.DOWN
	elif _consume_action(ACTION_MOVE_LEFT):
		direction = Vector2i.LEFT
	elif _consume_action(ACTION_MOVE_RIGHT):
		direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		_execute_move_command(direction)


# --- 私有/辅助方法 ---

func _execute_move_command(direction: Vector2i) -> void:
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if not is_instance_valid(history):
		return

	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	if result == null:
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


func _consume_action(action_id: StringName) -> bool:
	if not is_instance_valid(_input_mapping):
		return false

	return _input_mapping.consume_action(action_id)


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	_is_active = not data.is_replay_mode


func _on_game_state_changed(state: StringName) -> void:
	_is_playing = state == EventNames.STATE_PLAYING


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	if is_instance_valid(_input_mapping):
		_input_mapping.clear_input_state()
