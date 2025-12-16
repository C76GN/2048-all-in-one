# scripts/core/replay_game_controller.gd

## ReplayGameController: 回放模式的控制器。
##
## 处理回放流程，包括回放按钮状态更新。
class_name ReplayGameController
extends GameController


func start() -> void:
	game_play.input_source.start()
	game_play.update_replay_buttons_state()


func stop() -> void:
	game_play.input_source.stop()


func handle_action(action: Variant) -> void:
	var move_was_valid: bool = game_play.game_board.handle_move(action)
	if move_was_valid:
		game_play.save_current_state(action)
		game_play.update_and_publish_hud_data()
		game_play.update_replay_buttons_state()


func on_game_over() -> void:
	game_play.replay_next_step_button.disabled = true

