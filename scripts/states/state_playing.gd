# scripts/states/state_playing.gd

## StatePlaying: 游戏进行中状态。
##
## 激活输入源，允许玩家操作。
extends GameState


func enter(_msg: Dictionary = {}) -> void:
	if game_play.current_controller:
		game_play.current_controller.start()


func exit() -> void:
	if game_play.current_controller:
		game_play.current_controller.stop()


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("undo"):
		game_play._on_undo_button_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("save_bookmark"):
		game_play._on_snapshot_button_pressed()
		get_viewport().set_input_as_handled()

