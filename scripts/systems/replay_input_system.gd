## ReplayInputSystem: 负责处理回放模式下的播放逻辑，并发射命令。
class_name ReplayInputSystem
extends GFSystem

var _is_playing: bool = false
var _is_active: bool = false
var _replay_data: ReplayData = null

func ready() -> void:
	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	register_simple_event(EventNames.REPLAY_NEXT_STEP, _on_next_step)
	register_simple_event(EventNames.REPLAY_PREV_STEP, _on_prev_step)


func dispose() -> void:
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	unregister_simple_event(EventNames.REPLAY_NEXT_STEP, _on_next_step)
	unregister_simple_event(EventNames.REPLAY_PREV_STEP, _on_prev_step)


func _on_game_ready(data: GameReadyData) -> void:
	_is_active = data.is_replay_mode
	if _is_active:
		_replay_data = data.replay_data_resource
	else:
		_replay_data = null


func _on_game_state_changed(state: Variant) -> void:
	_is_playing = (state == EventNames.STATE_PLAYING)


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	_replay_data = null


func _execute_replay_step(direction: Vector2i) -> void:
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if not is_instance_valid(history):
		return

	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	if result == null:
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


func _on_next_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or not is_instance_valid(_replay_data):
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	var step_index: int = history.undo_count - 1 if history else 0
	
	if step_index < _replay_data.actions.size():
		var direction: Vector2i = _replay_data.actions[step_index]
		_execute_replay_step(direction)

func _on_prev_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing:
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if history and history.undo_count > 1:
		if await history.undo_last_async():
			send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
