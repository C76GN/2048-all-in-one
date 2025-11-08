# scripts/core/input_controller.gd

## InputController: 专门负责处理玩家原始输入的节点。
##
## 该节点捕获所有与游戏玩法相关的输入事件 (如移动、暂停)，
## 并将它们转换为更抽象的信号。这使得游戏主逻辑 (GamePlay)
## 无需关心具体的按键是什么，只需响应 "移动意图" 或 "暂停请求" 即可。
class_name InputController
extends Node

# --- 信号 ---

## 当检测到玩家的移动意图时发出。
## @param direction: 代表移动方向的单位向量 (Vector2i)。
signal move_intent_triggered(direction: Vector2i)

## 当检测到玩家的暂停/继续请求时发出。
signal pause_toggled


# --- Godot 生命周期方法 ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		pause_toggled.emit()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused:
		return

	var direction: Vector2i = Vector2i.ZERO

	if event.is_action_pressed("move_up"): direction = Vector2i.UP
	elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		move_intent_triggered.emit(direction)
		get_viewport().set_input_as_handled()
