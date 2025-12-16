# scripts/core/game_controller.gd

## GameController: 游戏控制器的基类。
##
## 负责处理不同游戏模式下的控制逻辑，消除 GamePlay 中的 if-else 判断。
class_name GameController
extends RefCounted


## 对 GamePlay 的引用。
var game_play: Control


## 设置控制器。
## @param p_game_play: GamePlay 实例。
func setup(p_game_play: Control) -> void:
	game_play = p_game_play


## 启动控制器。
func start() -> void:
	pass


## 停止控制器。
func stop() -> void:
	pass


## 处理游戏动作。
## @param _action: 动作数据。
func handle_action(_action: Variant) -> void:
	pass


## 游戏结束时被调用。
func on_game_over() -> void:
	pass
