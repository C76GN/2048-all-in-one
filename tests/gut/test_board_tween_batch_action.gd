## 验证棋盘 Tween 适配器遵守 GFVisualAction 的等待与取消契约。
extends GutTest


# --- 常量 ---

const _FEEDBACK_PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)


# --- 测试用例 ---

func test_action_queue_waits_for_board_tween_batch() -> void:
	var target: Node2D = Node2D.new()
	add_child_autofree(target)
	var queue: GFActionQueueSystem = GFActionQueueSystem.new()
	queue.init()
	var action: ProbeTweenBatchAction = ProbeTweenBatchAction.new(target, Vector2(32.0, 8.0), 10.0)
	var following_action_ran: Array[bool] = [false]
	var following_action: GFCallableAction = GFCallableAction.new(func() -> void:
		following_action_ran[0] = true
	)

	queue.enqueue(action)
	queue.enqueue(following_action)
	await get_tree().process_frame

	assert_false(following_action_ran[0], "GF 队列不应在棋盘 Tween 完成前执行下一动作。")
	queue.finish_current_action()
	await get_tree().process_frame
	assert_true(following_action_ran[0], "棋盘 Tween 完成后 GF 队列应继续消费。")
	assert_true(target.position.is_equal_approx(Vector2(32.0, 8.0)), "等待完成后目标应位于最终位置。")
	queue.dispose()


func test_cancel_releases_waiter_and_kills_tracked_tweens() -> void:
	var target: Node2D = Node2D.new()
	add_child_autofree(target)
	var action: ProbeTweenBatchAction = ProbeTweenBatchAction.new(target, Vector2(64.0, 0.0), 10.0)
	var result: Variant = action.execute()
	var completed: Array[bool] = [false]
	if result is Signal:
		var completion_signal: Signal = result
		var _completion_connected: int = completion_signal.connect(func() -> void:
			completed[0] = true
		)

	action.cancel()

	assert_true(result is Signal, "有时长的 Tween 批次必须返回可等待 Signal。")
	assert_true(completed[0], "取消 Tween 批次必须释放 GF 队列等待者。")


func test_finish_advances_tracked_tweens_to_final_state() -> void:
	var target: Node2D = Node2D.new()
	add_child_autofree(target)
	var action: ProbeTweenBatchAction = ProbeTweenBatchAction.new(target, Vector2(96.0, 24.0), 10.0)
	var result: Variant = action.execute()

	action.finish()

	assert_true(result is Signal, "有时长的 Tween 批次必须返回可等待 Signal。")
	assert_true(target.position.is_equal_approx(Vector2(96.0, 24.0)), "立即完成必须推进到 Tween 最终状态。")


func test_animation_utility_snapshots_feedback_motion_when_enqueuing() -> void:
	var queue_root: GFActionQueueSystem = GFActionQueueSystem.new()
	queue_root.init()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	assert_true(feedback.apply_profile(_FEEDBACK_PROFILE))
	var animation_utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	animation_utility._action_queue_system = queue_root
	animation_utility._feedback_utility = feedback
	assert_true(animation_utility.bind_board(board))
	var action: ProbeMotionAction = ProbeMotionAction.new()

	assert_true(animation_utility.enqueue(action))
	assert_same(
		action.get_motion_profile(),
		_FEEDBACK_PROFILE.tile_motion_profile,
		"棋盘动作必须使用入队时的主题 Tile 节拍。"
	)
	var budget: GameFeedbackBudget = action.get_feedback_budget()
	assert_not_null(budget, "棋盘动作必须固化入队时的无障碍表现预算。")
	assert_true(
		is_equal_approx(budget.motion_scale, 1.0)
		and is_equal_approx(budget.duration_scale, 1.0),
		"缺省无障碍状态应向核心 Tile 动画注入完整档预算。"
	)
	assert_has(
		animation_utility.get_required_utilities(),
		GameBoardFeedbackUtility,
		"动画 Utility 必须显式声明棋盘反馈依赖。"
	)

	animation_utility.unbind_board(board)
	queue_root.dispose()


func test_animation_utility_gates_only_first_idle_visual_action() -> void:
	var queue_root: GFActionQueueSystem = GFActionQueueSystem.new()
	queue_root.init()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var gate_host: Node = Node.new()
	add_child_autofree(gate_host)
	var feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	assert_true(feedback.apply_profile(_FEEDBACK_PROFILE))
	var animation_utility: ProbeGatedAnimationUtility = ProbeGatedAnimationUtility.new()
	animation_utility._action_queue_system = queue_root
	animation_utility._feedback_utility = feedback
	animation_utility.gate_host = gate_host
	assert_true(animation_utility.bind_board(board))
	var execution_order: Array[StringName] = []
	var first_action: ProbeQueuedMotionAction = ProbeQueuedMotionAction.new(
		&"first",
		execution_order
	)
	var second_action: ProbeQueuedMotionAction = ProbeQueuedMotionAction.new(
		&"second",
		execution_order
	)

	assert_true(animation_utility.enqueue(first_action))
	assert_true(animation_utility.is_busy(), "空闲队列入队后必须立即进入忙碌状态。")
	assert_true(execution_order.is_empty(), "首个视觉动作不得在输入事件栈内执行。")
	assert_true(animation_utility.enqueue(second_action))
	assert_true(
		GFVariantData.get_option_int(
			animation_utility._board_queue.get_debug_snapshot(),
			&"queued_count"
		) == 2,
		"队列忙碌时不得给同批后续动作重复插入帧门。"
	)

	for _frame: int in range(8):
		if execution_order.size() == 2:
			break
		await get_tree().process_frame

	assert_true(
		execution_order == [&"first", &"second"],
		"帧门后必须保持原动作 FIFO 顺序。"
	)
	animation_utility.unbind_board(board)
	queue_root.dispose()


func test_clearing_first_frame_gate_prevents_stale_visual_action() -> void:
	var queue_root: GFActionQueueSystem = GFActionQueueSystem.new()
	queue_root.init()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var gate_host: Node = Node.new()
	add_child_autofree(gate_host)
	var feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	assert_true(feedback.apply_profile(_FEEDBACK_PROFILE))
	var animation_utility: ProbeGatedAnimationUtility = ProbeGatedAnimationUtility.new()
	animation_utility._action_queue_system = queue_root
	animation_utility._feedback_utility = feedback
	animation_utility.gate_host = gate_host
	assert_true(animation_utility.bind_board(board))
	var execution_order: Array[StringName] = []
	var stale_action: ProbeQueuedMotionAction = ProbeQueuedMotionAction.new(
		&"stale",
		execution_order
	)

	assert_true(animation_utility.enqueue(stale_action))
	animation_utility.clear(true)
	for _frame: int in range(3):
		await get_tree().process_frame

	assert_true(execution_order.is_empty(), "取消帧门时不得补执行已经过时的视觉动作。")
	assert_false(animation_utility.is_busy())
	animation_utility.unbind_board(board)
	queue_root.dispose()


# --- 内部类 ---

class ProbeTweenBatchAction extends BoardTweenBatchAction:
	var target: Node2D
	var target_position: Vector2
	var duration: float

	func _init(p_target: Node2D, p_target_position: Vector2, p_duration: float) -> void:
		target = p_target
		target_position = p_target_position
		duration = p_duration

	func execute() -> Variant:
		var tween: Tween = target.create_tween()
		var _property_tweener: PropertyTweener = tween.tween_property(
			target,
			^"position",
			target_position,
			duration
		)
		return _wait_for_tweens([tween], target)


class ProbeMotionAction extends BoardTweenBatchAction:
	func execute() -> Variant:
		return null

	func get_motion_profile() -> GameTileMotionProfile:
		return _tile_motion_profile

	func get_feedback_budget() -> GameFeedbackBudget:
		return _feedback_budget


class ProbeQueuedMotionAction extends BoardTweenBatchAction:
	var label: StringName
	var execution_order: Array[StringName]

	func _init(p_label: StringName, p_execution_order: Array[StringName]) -> void:
		label = p_label
		execution_order = p_execution_order

	func execute() -> Variant:
		execution_order.append(label)
		return null


class ProbeGatedAnimationUtility extends GameBoardAnimationUtility:
	var gate_host: Node

	func _create_first_frame_gate() -> GFWaitAction:
		var gate: GFWaitAction = GFWaitAction.new(
			_FIRST_FRAME_GATE_SECONDS,
			gate_host
		)
		gate.process_always = true
		gate.ignore_time_scale = true
		return gate
