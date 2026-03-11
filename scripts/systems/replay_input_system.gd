# scripts/systems/replay_input_system.gd

## ReplayInputSystem: 负责处理回放模式下的播放逻辑，并发射命令。
class_name ReplayInputSystem
extends GFSystem

var _is_playing: bool = false
var _is_active: bool = false
var _replay_data: ReplayData = null

func init() -> void:
	pass

func ready() -> void:
	Gf.listen(GameReadyData, _on_game_ready)
	Gf.listen_simple(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	Gf.listen_simple(EventNames.REPLAY_NEXT_STEP, _on_next_step)
	Gf.listen_simple(EventNames.REPLAY_PREV_STEP, _on_prev_step)

func _on_game_ready(data: GameReadyData) -> void:
	_is_active = data.is_replay_mode
	if _is_active:
		_replay_data = data.replay_data_resource

func _on_game_state_changed(state: Variant) -> void:
	_is_playing = (state == EventNames.STATE_PLAYING)

func _on_next_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing or not is_instance_valid(_replay_data):
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	var step_index: int = history.undo_count - 1 if history else 0
	
	if step_index < _replay_data.actions.size():
		var direction: Vector2i = _replay_data.actions[step_index]
		var cmd := MoveCommand.new(direction)
		Gf.send_command(cmd)
		
		if history:
			history.record(cmd)
		
		Gf.send_simple_event(EventNames.HUD_UPDATE_REQUESTED)

func _on_prev_step(_payload: Variant = null) -> void:
	if not _is_active or not _is_playing:
		return
		
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	if history and history.undo_count > 1:
		history.undo_last()
		Gf.send_simple_event(EventNames.HUD_UPDATE_REQUESTED)
