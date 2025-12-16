# scripts/core/standard_game_controller.gd

## StandardGameController: 标准游戏模式的控制器。
##
## 处理普通游戏流程，包括输入处理、状态保存和回放保存。
class_name StandardGameController
extends GameController


func start() -> void:
	game_play.input_source.start()


func stop() -> void:
	game_play.input_source.stop()


func handle_action(action: Variant) -> void:
	var move_was_valid: bool = game_play.game_board.handle_move(action)
	if move_was_valid:
		game_play.save_current_state(action)
		game_play.update_and_publish_hud_data()


func on_game_over() -> void:
	var mode_id: String = game_play.mode_config.resource_path.get_file().get_basename()
	SaveManager.set_high_score(mode_id, game_play.current_grid_size, game_play.score)
	
	var replay_data := ReplayData.new()
	replay_data.timestamp = int(Time.get_unix_time_from_system())
	replay_data.mode_config_path = game_play.mode_config.resource_path
	replay_data.initial_seed = game_play.initial_seed_of_session
	replay_data.grid_size = game_play.current_grid_size
	replay_data.actions = game_play.history_manager.get_action_sequence()
	replay_data.final_board_snapshot = game_play.game_board.model.get_snapshot()
	replay_data.final_score = game_play.score
	
	if not game_play.is_game_state_tainted_by_test_tools and not replay_data.actions.is_empty():
		ReplayManager.save_replay(replay_data)
	
	game_play.ui_manager.show_ui(UIManager.UIType.GAME_OVER)

