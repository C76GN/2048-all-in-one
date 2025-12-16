# scripts/states/state_game_over.gd

## StateGameOver: 游戏结束状态。
##
## 停止输入，触发结算逻辑。
extends GameState


func enter(_msg: Dictionary = {}) -> void:
	if game_play.current_controller:
		game_play.current_controller.stop()
		game_play.current_controller.on_game_over()
	
	for rule in game_play.all_spawn_rules:
		rule.teardown()


func exit() -> void:
	pass

