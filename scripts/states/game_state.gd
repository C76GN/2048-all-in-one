# scripts/states/game_state.gd

## GameState: 游戏状态的基类。
##
## 所有具体的游戏状态都应继承此类，实现状态对象模式。
class_name GameState
extends Node


## 对 GamePlay 的引用。
var game_play: Control


## 进入此状态时被调用。
## @param _msg: 可选的附加信息字典。
func enter(_msg: Dictionary = {}) -> void:
	pass


## 退出此状态时被调用。
func exit() -> void:
	pass


## 在此状态下每帧被调用。
## @param _delta: 帧间隔时间。
func update(_delta: float) -> void:
	pass


## 处理输入事件。
## @param _event: 输入事件。
func handle_input(_event: InputEvent) -> void:
	pass

