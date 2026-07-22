## ReplayInputSystem: 负责处理回放模式下的输入和逐步播放逻辑。
class_name ReplayInputSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const REPLAY_INPUT_CONTEXT: GFInputContext = preload("res://features/replays/resources/input/replay_input_context.tres")
const ACTION_REPLAY_PREV_STEP: StringName = &"replay_prev_step"
const ACTION_REPLAY_NEXT_STEP: StringName = &"replay_next_step"
const ACTION_REPLAY_CONTINUE: StringName = &"replay_continue"
const ACTION_REPLAY_BACK: StringName = &"replay_back"
const _REPLAY_INPUT_PRIORITY: int = 200


# --- 私有变量 ---

var _input_mapping: GFInputMappingUtility
var _is_playing: bool = false
var _is_active: bool = false
var _replay_data: ReplayData = null
var _is_step_processing: bool = false


# --- Godot 生命周期方法 ---

func get_required_systems() -> Array[Script]:
	return [ReplaySystem]


func get_required_utilities() -> Array[Script]:
	return [GFCommandHistoryUtility, GFInputMappingUtility]


func ready() -> void:
	_input_mapping = _get_input_mapping_utility()

	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready", 1))
	register_simple_event(EventNames.GAME_STATE_CHANGED, GFEventListener.from_method(self, &"_on_game_state_changed", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))
	register_simple_event(EventNames.REPLAY_NEXT_STEP, GFEventListener.from_method(self, &"_on_next_step", 1))
	register_simple_event(EventNames.REPLAY_PREV_STEP, GFEventListener.from_method(self, &"_on_prev_step", 1))
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, GFEventListener.from_method(self, &"_on_replay_continued_as_game", 1))


func dispose() -> void:
	_set_replay_input_enabled(false)
	_input_mapping = null


## 轮询回放输入上下文并驱动回放步进。
## @param _delta: 当前帧间隔；该系统使用输入缓冲，不直接依赖该值。
func tick(_delta: float) -> void:
	if not _is_active or not is_instance_valid(_input_mapping):
		return

	if _consume_action(ACTION_REPLAY_BACK):
		send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)
		return

	if not _is_playing:
		return

	var replay_system: ReplaySystem = _get_replay_system()
	if not is_instance_valid(replay_system):
		return

	if _consume_action(ACTION_REPLAY_PREV_STEP):
		replay_system.step_backward()
		return

	if _consume_action(ACTION_REPLAY_NEXT_STEP):
		replay_system.step_forward()
		return

	if _consume_action(ACTION_REPLAY_CONTINUE):
		replay_system.continue_from_current_step()


# --- 私有/辅助方法 ---

func _consume_action(action_id: StringName) -> bool:
	if not is_instance_valid(_input_mapping):
		return false

	return _input_mapping.consume_action(action_id)


func _set_replay_input_enabled(is_enabled: bool) -> void:
	if not is_instance_valid(_input_mapping):
		return

	if is_enabled:
		if not _input_mapping.is_context_enabled(REPLAY_INPUT_CONTEXT):
			_input_mapping.enable_context(REPLAY_INPUT_CONTEXT, _REPLAY_INPUT_PRIORITY)
	else:
		_input_mapping.disable_context(REPLAY_INPUT_CONTEXT)

	_input_mapping.clear_input_state()


func _execute_replay_step(direction: Vector2i) -> void:
	if _is_step_processing:
		return

	var history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(history):
		return

	_is_step_processing = true
	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	_is_step_processing = false
	if result == null:
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
	var replay_system: ReplaySystem = _get_replay_system()
	if is_instance_valid(replay_system):
		replay_system.notify_playback_step_settled()


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_replay_system() -> ReplaySystem:
	var system_value: Object = get_system(ReplaySystem)
	if system_value is ReplaySystem:
		var replay_system: ReplaySystem = system_value
		return replay_system
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


func _get_replay_action_direction(step_index: int) -> Vector2i:
	if not is_instance_valid(_replay_data):
		return Vector2i.ZERO
	if step_index < 0 or step_index >= _replay_data.actions.size():
		return Vector2i.ZERO

	var action_value: Variant = _replay_data.actions[step_index]
	if action_value is Vector2i:
		var direction: Vector2i = action_value
		return direction
	return Vector2i.ZERO


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	_is_active = data.is_replay_mode
	if _is_active:
		_replay_data = data.replay_data_resource
	else:
		_replay_data = null
	_set_replay_input_enabled(_is_active)


func _on_game_state_changed(state: Variant) -> void:
	_is_playing = state == EventNames.STATE_PLAYING


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	_is_step_processing = false
	_replay_data = null
	_set_replay_input_enabled(false)


func _on_next_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or not is_instance_valid(_replay_data):
		return
		
	var history: GFCommandHistoryUtility = _get_command_history_utility()
	var step_index: int = maxi(history.undo_count - 1, 0) if is_instance_valid(history) else 0
	
	if step_index < _replay_data.actions.size():
		var direction: Vector2i = _get_replay_action_direction(step_index)
		if direction == Vector2i.ZERO:
			return
		call_deferred(&"_execute_replay_step", direction)


func _on_prev_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or _is_step_processing:
		return
		
	var history: GFCommandHistoryUtility = _get_command_history_utility()
	if is_instance_valid(history) and history.undo_count > 1:
		_is_step_processing = true
		if await history.undo_last_async():
			send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
			var replay_system: ReplaySystem = _get_replay_system()
			if is_instance_valid(replay_system):
				replay_system.notify_playback_step_settled()
		_is_step_processing = false


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	_is_step_processing = false
	_replay_data = null
	_set_replay_input_enabled(false)
