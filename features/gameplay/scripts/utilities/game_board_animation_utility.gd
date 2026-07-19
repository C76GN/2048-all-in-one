## GameBoardAnimationUtility: 棋盘动画队列与输入响应策略的项目适配器。
##
## 使用 GFActionQueueSystem 的命名生命周期队列，使棋盘动画不再污染默认队列，
## 并在一个位置实现缓冲、阻断、实时重定向三种策略。
class_name GameBoardAnimationUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const BOARD_QUEUE_NAME: StringName = &"gameplay.board_animation"


# --- 私有变量 ---

var _action_queue_system: GFActionQueueSystem
var _board_queue: GFActionQueueSystem
var _input_profile: GameInputProfileUtility
var _board: GameBoardController


# --- GF 生命周期方法 ---

func get_required_systems() -> Array[Script]:
	return [GFActionQueueSystem]


func get_required_utilities() -> Array[Script]:
	return [GameInputProfileUtility]


func ready() -> void:
	_action_queue_system = _get_action_queue_system()
	_input_profile = _get_input_profile_utility()
	if not is_instance_valid(_action_queue_system) or not is_instance_valid(_input_profile):
		push_error("[GameBoardAnimationUtility] 缺少动作队列或输入配置依赖。")


func dispose() -> void:
	clear(true)
	_board_queue = null
	_board = null
	_action_queue_system = null
	_input_profile = null


# --- 公共方法 ---

## 绑定当前棋盘节点，并创建随其生命周期释放的 GF 命名队列。
## @param board: 当前棋盘表现控制器。
## @return 队列绑定成功时返回 true。
func bind_board(board: GameBoardController) -> bool:
	if not is_instance_valid(board) or not is_instance_valid(_action_queue_system):
		return false
	_board = board
	_board_queue = _action_queue_system.get_linked_queue(BOARD_QUEUE_NAME, board)
	return is_instance_valid(_board_queue)


## 解绑当前棋盘，并按调用阶段决定是否停止尚未完成的视觉动作。
## @param board: 要解绑的棋盘表现控制器。
## @param stop_actions: 架构仍可用时设为 true；节点退出兜底路径只解除引用。
func unbind_board(board: GameBoardController, stop_actions: bool = true) -> void:
	if board != _board:
		return
	if stop_actions:
		clear(true)
	_board_queue = null
	_board = null


## 向棋盘专用队列加入一个视觉动作。
## @param action: 实现 GF 动作协议的对象。
## @return 入队成功时返回 true。
func enqueue(action: Object) -> bool:
	if action == null or not _ensure_board_queue():
		return false
	_board_queue.enqueue(action)
	return true


func is_busy() -> bool:
	return is_instance_valid(_board_queue) and _board_queue.is_processing


## 清空棋盘视觉队列。
## @param stop_current: 是否同时取消当前视觉动作。
func clear(stop_current: bool = true) -> void:
	if is_instance_valid(_board_queue):
		_board_queue.clear_queue(stop_current)


## 在逻辑移动前应用用户选择的动画响应策略。
func prepare_for_move() -> bool:
	if not is_instance_valid(_input_profile):
		return true
	match _input_profile.get_input_timing_mode():
		GameInputProfileUtility.InputTimingMode.BLOCK_WHILE_ANIMATING:
			return not is_busy()
		GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET:
			if is_busy():
				clear(true)
				if is_instance_valid(_board):
					_board.restore_from_snapshot(_board.get_state_snapshot())
			return true
		_:
			return true


# --- 私有/辅助方法 ---

func _ensure_board_queue() -> bool:
	if not is_instance_valid(_action_queue_system) or not is_instance_valid(_board):
		return false
	# GFLevelUtility 会在新关卡开始时释放上一关的全部命名队列。
	# 每次入队前重新解析，避免继续持有仍有效但已经 dispose 的旧 RefCounted。
	_board_queue = _action_queue_system.get_linked_queue(BOARD_QUEUE_NAME, _board)
	return is_instance_valid(_board_queue)


func _get_action_queue_system() -> GFActionQueueSystem:
	var system_value: Object = get_system(GFActionQueueSystem)
	if system_value is GFActionQueueSystem:
		var action_queue: GFActionQueueSystem = system_value
		return action_queue
	return null


func _get_input_profile_utility() -> GameInputProfileUtility:
	var utility_value: Object = get_utility(GameInputProfileUtility)
	if utility_value is GameInputProfileUtility:
		var input_profile: GameInputProfileUtility = utility_value
		return input_profile
	return null
