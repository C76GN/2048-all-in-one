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


func test_animation_utility_starts_first_idle_visual_action_without_frame_gate() -> void:
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
	assert_true(
		execution_order == [&"first"],
		"空闲队列的首个主表现必须立即开始，不得人为等待一个 process frame。"
	)
	assert_true(animation_utility.enqueue(second_action))
	assert_true(
		execution_order == [&"first", &"second"],
		"移除首帧门后仍必须保持 GF 动作队列的 FIFO 顺序。"
	)
	animation_utility.unbind_board(board)
	queue_root.dispose()


func test_board_animation_action_reports_primary_feedback_only_when_execute_starts() -> void:
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var performance_trace: RecordingPerformanceTraceUtility = (
		RecordingPerformanceTraceUtility.new()
	)
	var action: BoardAnimationAction = BoardAnimationAction.new(
		[{&"type": &"PROBE"}],
		board
	)
	action.configure_primary_feedback_trace(performance_trace, 73)

	assert_true(
		performance_trace.marked_attempt_ids.is_empty(),
		"创建和配置动作不能被记作玩家首反馈。"
	)
	var _first_result: Variant = action.execute()
	assert_true(
		performance_trace.marked_attempt_ids == [73],
		"BoardAnimationAction.execute 起点必须记录一次首反馈。"
	)
	var _second_result: Variant = action.execute()
	assert_true(
		performance_trace.marked_attempt_ids == [73],
		"首反馈记录必须保持一次性，重复执行不得重复采样。"
	)


func test_board_reparent_keeps_animation_binding_and_paints_next_action() -> void:
	var first_parent: Node = Node.new()
	var stable_parent: Node = Node.new()
	var board_owner: Node = Node.new()
	first_parent.add_child(board_owner)
	var required_nodes: Array[Node] = [
		Panel.new(),
		Node2D.new(),
		Node2D.new(),
		BoardFeedbackCanvas.new(),
		BoardMotionBackdrop.new(),
	]
	var required_names: Array[StringName] = [
		&"BoardBackground",
		&"BoardContainer",
		&"BoardFeedbackRoot",
		&"BoardFeedbackCanvas",
		&"BoardMotionBackdrop",
	]
	for index: int in range(required_nodes.size()):
		var required_node: Node = required_nodes[index]
		required_node.name = required_names[index]
		board_owner.add_child(required_node)
		required_node.owner = board_owner
		required_node.unique_name_in_owner = true
	var board: ProbeReparentBoard = ProbeReparentBoard.new()
	var tile: Node2D = Node2D.new()
	tile.scale = Vector2.ZERO
	board.add_child(tile)
	board_owner.add_child(board)
	board.owner = board_owner
	add_child_autofree(first_parent)
	add_child_autofree(stable_parent)

	var queue_root: GFActionQueueSystem = GFActionQueueSystem.new()
	queue_root.init()
	var animation_utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	animation_utility._action_queue_system = queue_root
	board.install_animation_utility(animation_utility)
	assert_true(animation_utility.bind_board(board))

	board.reparent(stable_parent)
	await get_tree().process_frame
	assert_false(
		board.has_cleaned_up(),
		"稳定父级之间的临时 reparent 不得被当成永久离场。"
	)
	assert_same(
		animation_utility._board,
		board,
		"临时 reparent 后动画 Utility 必须仍绑定当前棋盘。"
	)

	var paint_action: ProbePaintAction = ProbePaintAction.new(tile)
	assert_true(
		animation_utility.enqueue(paint_action),
		"重挂后的棋盘必须能重新解析 linked queue 并接受首个视觉动作。"
	)
	for _frame: int in range(8):
		if paint_action.executed:
			break
		await get_tree().process_frame
	assert_true(paint_action.executed, "重挂后的首个棋盘动作必须实际执行。")
	assert_true(
		absf(tile.scale.x) > 0.1 and absf(tile.scale.y) > 0.1,
		"重挂后的首批方块不得停留在不可见的零缩放状态。"
	)

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


class ProbePaintAction extends BoardTweenBatchAction:
	var tile: Node2D
	var executed: bool = false

	func _init(p_tile: Node2D) -> void:
		tile = p_tile

	func execute() -> Variant:
		executed = true
		tile.scale = Vector2.ONE
		return null


class ProbeReparentBoard extends GameBoardController:
	func _ready() -> void:
		pass

	## @param animation_utility: 要注入测试棋盘的动画适配。
	func install_animation_utility(animation_utility: GameBoardAnimationUtility) -> void:
		_animation_utility = animation_utility

	func has_cleaned_up() -> bool:
		return _is_cleaned_up


class RecordingPerformanceTraceUtility extends GamePerformanceTraceUtility:
	var marked_attempt_ids: Array[int] = []

	## @param attempt_id: 要记录的测试移动尝试标识。
	func mark_primary_feedback_started(attempt_id: int) -> void:
		marked_attempt_ids.append(attempt_id)
