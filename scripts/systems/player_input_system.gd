# scripts/systems/player_input_system.gd

## PlayerInputSystem: 负责处理标准模式下的玩家输入，并将其转换为游戏命令(MoveCommand)。
class_name PlayerInputSystem
extends GFSystem

var _is_playing: bool = false
var _is_active: bool = false

func ready() -> void:
	register_event(GameReadyData, _on_game_ready)
	register_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	register_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)


func dispose() -> void:
	unregister_event(GameReadyData, _on_game_ready)
	unregister_simple_event(EventNames.GAME_STATE_CHANGED, _on_game_state_changed)
	unregister_simple_event(EventNames.SCENE_WILL_CHANGE, _on_scene_will_change)


func _on_game_ready(data: GameReadyData) -> void:
	_is_active = not data.is_replay_mode


func _on_game_state_changed(state: StringName) -> void:
	_is_playing = (state == EventNames.STATE_PLAYING)


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false


func _execute_move_command(direction: Vector2i) -> void:
	var cmd := MoveCommand.new(direction)
	var history := get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility
	var result: Variant = await history.execute_command(cmd) if history else Gf.send_command(cmd)
	if result == null:
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


func tick(_delta: float) -> void:
	if not _is_active:
		return
		
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("ui_pause"):
		send_simple_event(EventNames.UI_PAUSE_REQUESTED)
		
	if not _is_playing:
		return
		
	if Input.is_action_just_pressed("undo"):
		send_simple_event(EventNames.UNDO_REQUESTED)
		return
		
	if Input.is_action_just_pressed("save_bookmark"):
		send_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED)
		return
		
	var direction := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"): direction = Vector2i.UP
	elif Input.is_action_just_pressed("move_down"): direction = Vector2i.DOWN
	elif Input.is_action_just_pressed("move_left"): direction = Vector2i.LEFT
	elif Input.is_action_just_pressed("move_right"): direction = Vector2i.RIGHT
	
	if direction != Vector2i.ZERO:
		_execute_move_command(direction)
