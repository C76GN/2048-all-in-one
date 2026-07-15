## BoardUndoAnimationAction: 封装棋盘撤回时的反向过渡动画。
##
## 根据前置滑动记录的反向映射表，将棋盘上的方块反向“退回”到原先的位置，
## execute() 会立即恢复准确的视觉节点并启动非阻塞位移动画，不等待 Tween 完成。
class_name BoardUndoAnimationAction
extends "res://addons/gf/extensions/action_queue/actions/gf_visual_action.gd"


# --- 私有变量 ---

var _snapshot: Dictionary
var _reverse_target_map: Dictionary
var _game_board: GameBoardController


# --- Godot 生命周期方法 ---

func _init(snapshot: Dictionary, reverse_target_map: Dictionary, game_board: GameBoardController) -> void:
	_snapshot = snapshot
	_reverse_target_map = reverse_target_map
	_game_board = game_board
	var _fire_and_forget_action: GFVisualAction = as_fire_and_forget()


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board):
		return null

	_game_board.restore_from_snapshot_with_reverse_animation(_snapshot, _reverse_target_map)
	
	return null
