## BoardUndoAnimationAction: 封装棋盘撤回时的反向过渡动画。
##
## 根据前置滑动记录的反向映射表，将棋盘上的方块反向“退回”到原先的位置，
## execute() 会立即恢复准确的视觉节点并启动非阻塞位移动画，不等待 Tween 完成。
class_name BoardUndoAnimationAction
extends GFVisualAction


# --- 私有变量 ---

var _snapshot: Dictionary
var _reverse_target_map: Dictionary
var _game_board: Node


# --- Godot 生命周期方法 ---

func _init(snapshot: Dictionary, reverse_target_map: Dictionary, game_board: Node) -> void:
	_snapshot = snapshot
	_reverse_target_map = reverse_target_map
	_game_board = game_board
	as_fire_and_forget()


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board):
		return null

	if _game_board.has_method(&"restore_from_snapshot_with_reverse_animation"):
		_game_board.restore_from_snapshot_with_reverse_animation(_snapshot, _reverse_target_map)
	elif _game_board.has_method(&"restore_from_snapshot"):
		_game_board.restore_from_snapshot(_snapshot)
	
	return null
