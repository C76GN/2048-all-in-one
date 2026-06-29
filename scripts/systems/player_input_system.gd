## PlayerInputSystem: 负责处理标准模式下的玩家输入，并将抽象动作转换为游戏命令。
class_name PlayerInputSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://resources/input/gameplay_input_context.tres")
const ACTION_PAUSE: StringName = &"pause"
const ACTION_UNDO: StringName = &"undo"
const ACTION_REDO: StringName = &"redo"
const ACTION_SAVE_BOOKMARK: StringName = &"save_bookmark"
const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const _MOVE_FAIL_MESSAGE_FALLBACK: String = "[color=yellow]这个方向无法移动。[/color]"
const _MOVE_FAIL_MESSAGE_DURATION: float = 1.6


# --- 私有变量 ---

var _input_mapping: GFInputMappingUtility
var _is_playing: bool = false
var _is_active: bool = false


# --- Godot 生命周期方法 ---

func ready() -> void:
	_input_mapping = _get_input_mapping_utility()
	if is_instance_valid(_input_mapping):
		_input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)

	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, _on_replay_continued_as_game)


func dispose() -> void:
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	unregister_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, _on_replay_continued_as_game)

	if is_instance_valid(_input_mapping):
		_input_mapping.disable_context(GAMEPLAY_INPUT_CONTEXT)
	_input_mapping = null


## 轮询玩法输入上下文并派发对应游戏命令。
## @param _delta: 当前帧间隔；该系统使用输入缓冲，不直接依赖该值。
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

	if _consume_action(ACTION_REDO):
		send_simple_event(EventNames.REDO_REQUESTED)
		return

	if _consume_action(ACTION_SAVE_BOOKMARK):
		send_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED)
		return

	var direction: Vector2i = Vector2i.ZERO
	if _consume_action(ACTION_MOVE_UP):
		direction = Vector2i.UP
	elif _consume_action(ACTION_MOVE_DOWN):
		direction = Vector2i.DOWN
	elif _consume_action(ACTION_MOVE_LEFT):
		direction = Vector2i.LEFT
	elif _consume_action(ACTION_MOVE_RIGHT):
		direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		call_deferred(&"_execute_move_command", direction)


# --- 私有/辅助方法 ---

func _execute_move_command(direction: Vector2i) -> void:
	var history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(history):
		return

	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	if result == null:
		_show_invalid_move_feedback()
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


func _consume_action(action_id: StringName) -> bool:
	if not is_instance_valid(_input_mapping):
		return false

	return _input_mapping.consume_action(action_id)


func _show_invalid_move_feedback() -> void:
	send_event(_make_invalid_move_payload())


func _make_invalid_move_payload() -> HudMessagePayload:
	return HudMessagePayload.new(
		_translate_with_fallback("MOVE_FAIL_MSG", _MOVE_FAIL_MESSAGE_FALLBACK),
		_MOVE_FAIL_MESSAGE_DURATION
	)


func _translate_with_fallback(key: String, fallback: String) -> String:
	var text: String = tr(key)
	if text == key:
		return fallback
	return text


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


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


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_is_active = true
	_is_playing = true
	if is_instance_valid(_input_mapping):
		_input_mapping.clear_input_state()
