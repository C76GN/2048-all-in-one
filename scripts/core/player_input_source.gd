# scripts/core/player_input_source.gd

## PlayerInputSource: 实现了从玩家实时输入生成动作的策略。
##
## 该节点捕获所有与游戏玩法相关的输入事件 (如移动)，
## 并将它们转换为标准的 `action_triggered` 信号。
class_name PlayerInputSource
extends BaseInputSource


# --- Godot 生命周期方法 ---

func _unhandled_input(event: InputEvent) -> void:
	# 游戏暂停时不处理移动输入
	if get_tree().paused:
		return

	var direction := Vector2i.ZERO

	if event.is_action_pressed("move_up"):
		direction = Vector2i.UP
	elif event.is_action_pressed("move_down"):
		direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"):
		direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"):
		direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		action_triggered.emit(direction)
		get_viewport().set_input_as_handled()
