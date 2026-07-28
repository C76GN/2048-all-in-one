## GameBoardAnimationUtility: 棋盘动画队列与输入响应策略的项目适配器。
##
## 使用 GFActionQueueSystem 的命名生命周期队列，使棋盘动画不再污染默认队列，
## 并在一个位置实现缓冲、阻断、实时重定向三种策略。
class_name GameBoardAnimationUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const BOARD_QUEUE_NAME: StringName = &"gameplay.board_animation"
const _FIRST_FRAME_GATE_SECONDS: float = 0.001


# --- 私有变量 ---

var _action_queue_system: GFActionQueueSystem
var _board_queue: GFActionQueueSystem
var _input_profile: GameInputProfileUtility
var _feedback_utility: GameBoardFeedbackUtility
var _board: GameBoardController
var _presentation_suppression_depth: int = 0


# --- GF 生命周期方法 ---

func get_required_systems() -> Array[Script]:
	return [GFActionQueueSystem]


func get_required_utilities() -> Array[Script]:
	return [GameInputProfileUtility, GameBoardFeedbackUtility]


func ready() -> void:
	_action_queue_system = _get_action_queue_system()
	_input_profile = _get_input_profile_utility()
	_feedback_utility = _get_feedback_utility()
	if (
		not is_instance_valid(_action_queue_system)
		or not is_instance_valid(_input_profile)
		or not is_instance_valid(_feedback_utility)
	):
		push_error("[GameBoardAnimationUtility] 缺少动作队列、输入配置或棋盘反馈依赖。")


func dispose() -> void:
	clear(true)
	_board_queue = null
	_board = null
	_action_queue_system = null
	_input_profile = null
	_feedback_utility = null
	_presentation_suppression_depth = 0


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
	if (
		action == null
		or is_presentation_suppressed()
		or not _ensure_board_queue()
	):
		return false
	var motion_profile: GameTileMotionProfile
	var feedback_budget: GameFeedbackBudget
	if action is BoardTweenBatchAction:
		var board_action: BoardTweenBatchAction = action
		motion_profile = (
			_feedback_utility.get_tile_motion_profile()
			if is_instance_valid(_feedback_utility)
			else null
		)
		feedback_budget = (
			_feedback_utility.get_current_budget()
			if is_instance_valid(_feedback_utility)
			else null
		)
		board_action.configure_tile_motion(
			motion_profile,
			feedback_budget
		)
	if _should_gate_first_visual_action(action, motion_profile, feedback_budget):
		_board_queue.enqueue(_create_first_frame_gate())
	_board_queue.enqueue(action)
	return true


func is_busy() -> bool:
	return is_instance_valid(_board_queue) and _board_queue.is_processing


## 清空棋盘视觉队列。
## @param stop_current: 是否同时取消当前视觉动作。
func clear(stop_current: bool = true) -> void:
	if is_instance_valid(_board_queue):
		_board_queue.clear_queue(stop_current)


## 开始一段只推进确定性逻辑、不播放逐回合表现的批处理。
##
## 支持嵌套调用；首次进入时取消仍在播放的旧动作。
func begin_presentation_suppression() -> void:
	if _presentation_suppression_depth == 0:
		clear(true)
	_presentation_suppression_depth += 1


## 结束表现抑制，并在最外层结束时一次性同步最终模型状态。
func end_presentation_suppression() -> void:
	if _presentation_suppression_depth <= 0:
		return
	_presentation_suppression_depth -= 1
	if _presentation_suppression_depth == 0 and is_instance_valid(_board):
		_board.snap_visuals_to_model_state()


func is_presentation_suppressed() -> bool:
	return _presentation_suppression_depth > 0


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
					_board.snap_visuals_to_model_state()
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


## 空闲队列先占用一帧，再开始构建 Tween，避免把整批表现对象创建塞进输入事件栈。
## 同一回合后续 Spawn/Transform 动作看到队列忙碌，只会正常追加，不重复插帧。
func _should_gate_first_visual_action(
	action: Object,
	motion_profile: GameTileMotionProfile,
	feedback_budget: GameFeedbackBudget
) -> bool:
	if (
		not action is BoardTweenBatchAction
		or not is_instance_valid(_board_queue)
		or _board_queue.is_processing
	):
		return false
	return (
		not is_instance_valid(motion_profile)
		or motion_profile.is_motion_enabled(feedback_budget)
	)


func _create_first_frame_gate() -> GFWaitAction:
	var gate: GFWaitAction = GFWaitAction.new(_FIRST_FRAME_GATE_SECONDS, _board)
	gate.process_always = true
	gate.ignore_time_scale = true
	return gate


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


func _get_feedback_utility() -> GameBoardFeedbackUtility:
	var utility_value: Object = get_utility(GameBoardFeedbackUtility)
	if utility_value is GameBoardFeedbackUtility:
		var feedback_utility: GameBoardFeedbackUtility = utility_value
		return feedback_utility
	return null
