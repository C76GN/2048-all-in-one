## ReplayInputSystem: 负责处理回放模式下的播放逻辑，并发射命令。
class_name ReplayInputSystem
extends GFSystem


# --- 私有变量 ---

var _is_playing: bool = false
var _is_active: bool = false
var _replay_data: ReplayData = null
var _is_step_processing: bool = false


# --- Godot 生命周期方法 ---

## 绑定回放控制相关事件。
func ready() -> void:
	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	register_simple_event(EventNames.REPLAY_NEXT_STEP, _on_next_step)
	register_simple_event(EventNames.REPLAY_PREV_STEP, _on_prev_step)
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, _on_replay_continued_as_game)


## 解绑回放控制相关事件。
func dispose() -> void:
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)
	unregister_simple_event(EventNames.REPLAY_NEXT_STEP, _on_next_step)
	unregister_simple_event(EventNames.REPLAY_PREV_STEP, _on_prev_step)
	unregister_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, _on_replay_continued_as_game)


# --- 私有/辅助方法 ---


func _execute_replay_step(direction: Vector2i) -> void:
	if _is_step_processing:
		return

	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if not is_instance_valid(history):
		return

	_is_step_processing = true
	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	_is_step_processing = false
	if result == null:
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	_is_active = data.is_replay_mode
	if _is_active:
		_replay_data = data.replay_data_resource
	else:
		_replay_data = null


func _on_game_state_changed(state: Variant) -> void:
	_is_playing = state == EventNames.STATE_PLAYING


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	_is_step_processing = false
	_replay_data = null


func _on_next_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or not is_instance_valid(_replay_data):
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	var step_index: int = maxi(history.undo_count - 1, 0) if history else 0
	
	if step_index < _replay_data.actions.size():
		var direction: Vector2i = _replay_data.actions[step_index]
		_execute_replay_step(direction)


func _on_prev_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or _is_step_processing:
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if history and history.undo_count > 1:
		_is_step_processing = true
		if await history.undo_last_async():
			send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
		_is_step_processing = false


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	_is_step_processing = false
	_replay_data = null
