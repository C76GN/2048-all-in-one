## 验证快速方向接管、碰撞提交和装饰尾效的独立生命周期。
extends GutTest

# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://features/themes/scenes/ui/tiles/tile.tscn")


# --- 测试用例 ---

func test_direction_retarget_starts_at_the_current_visible_position() -> void:
	var tile: Tile = _make_tile()
	var first: Tween = tile.animate_move(Vector2(200.0, 0.0))
	var _first_step: bool = first.custom_step(0.035)
	var visible_position: Vector2 = tile.position
	assert_gt(visible_position.x, 0.0)
	assert_lt(visible_position.x, 200.0)
	var second: Tween = tile.animate_move(Vector2(visible_position.x, 150.0))
	assert_true(tile.position == visible_position, "改变方向不能先吸附到旧格点。")
	assert_false(first.is_valid(), "旧方向 Tween 不得继续写入 position。")
	var _second_step: bool = second.custom_step(1.0)
	assert_true(tile.position == Vector2(visible_position.x, 150.0))


func test_retarget_to_current_pixel_cancels_the_previous_destination() -> void:
	var tile: Tile = _make_tile()
	var first: Tween = tile.animate_move(Vector2(200.0, 0.0))
	var _first_step: bool = first.custom_step(0.035)
	var visible_position: Vector2 = tile.position
	var replacement: Tween = tile.animate_move(visible_position)
	assert_null(replacement)
	assert_false(first.is_valid(), "零距离接管仍须取消旧目的地。")
	assert_true(tile.position == visible_position)


func test_spawn_decoration_does_not_hold_the_board_action_queue() -> void:
	var board: ContinuityBoard = ContinuityBoard.new()
	autofree(board)
	var tile: Tile = _make_tile()
	var action: BoardAnimationAction = BoardAnimationAction.new([
		{&"type": &"SPAWN", &"tile": tile},
	], board)
	var result: Variant = action.execute()
	assert_true(result == null, "生成尾效不能阻塞后续方向或回放动作。")
	assert_true(tile._active_rotation_tween.is_valid(), "队列结束时生成动画仍可自然完成。")
	assert_gt(tile.scale.x, 0.0, "新方块必须在同批提交时可见。")


func test_stationary_survivor_commits_at_collision_and_pulse_does_not_hold_admission() -> void:
	var board: ContinuityBoard = ContinuityBoard.new()
	autofree(board)
	var survivor: Tile = _make_tile()
	var consumed: Tile = _make_tile()
	consumed.position = Vector2(200.0, 0.0)
	var action: BoardAnimationAction = _make_merge(board, consumed, survivor)
	var result: Variant = action.execute()
	var completed: Array[bool] = [false]
	if result is Signal:
		var completion: Signal = result
		var _connected: int = completion.connect(func() -> void: completed[0] = true)
	assert_true(survivor.value == 2, "静止目标应等来方到达后再显示合并值。")
	var arrival: Tween = consumed._active_move_tween
	var _travel_step: bool = arrival.custom_step(1.0)
	assert_true(survivor.value == 4)
	assert_true(survivor.value_label.text == "4", "方块数字不得穿过未存在的中间数值。")
	assert_true(completed[0], "碰撞提交后应开放下一动作。")
	assert_true(survivor._active_scale_tween.is_valid(), "本地脉冲可在下一操作期间收束。")
	assert_true(board.released_tiles == 1)


func test_cancelled_collision_cannot_overwrite_a_reused_survivor() -> void:
	var board: ContinuityBoard = ContinuityBoard.new()
	autofree(board)
	var survivor: Tile = _make_tile()
	var consumed: Tile = _make_tile()
	consumed.position = Vector2(200.0, 0.0)
	var action: BoardAnimationAction = _make_merge(board, consumed, survivor)
	var _result: Variant = action.execute()
	var old_arrival: Tween = consumed._active_move_tween
	action.cancel()
	survivor.setup(8, &"test", Color.WHITE, Color.BLACK, &"", [], null)
	old_arrival.finished.emit()
	assert_true(survivor.value == 8, "迟到碰撞回调不得覆盖新回合的权威值。")
	assert_true(board.released_tiles == 1, "迟到完成不得重复回收已消费方块。")
	board._release_visual_tile_if_valid(consumed, RefCounted.new())
	assert_true(is_instance_valid(consumed), "撤回离场的过期回调同样不得释放已重置的方块。")


func test_realtime_input_admission_replaces_an_active_action_without_position_snap() -> void:
	var board: ContinuityBoard = ContinuityBoard.new()
	var _surface: Node2D = _attach_board_surface(board)
	var model: GridModel = GridModel.new()
	model.topology = BoardTopology.create_rectangle(Vector2i(2, 2))
	var data: TileState = TileState.new()
	data.value = 4
	assert_true(model.place_tile(data, Vector2i.ZERO))
	board.model = model
	var tile: Tile = _make_tile()
	tile.position = Vector2(150.0, 50.0)
	board._visual_map[data] = tile
	var queue: GFActionQueueSystem = GFActionQueueSystem.new()
	queue.init()
	var utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	utility._input_profile = GameInputProfileUtility.new()
	utility._board_queue = queue
	utility._board = board
	queue.enqueue(BoardAnimationAction.new([
		{&"type": &"MOVE", &"tile": tile, &"to_pos": Vector2(50.0, 50.0)},
	], board))
	var previous_travel: Tween = tile._active_move_tween
	var _first_step: bool = previous_travel.custom_step(0.02)
	var visible_position: Vector2 = tile.position
	assert_true(utility.is_busy())
	assert_true(utility.prepare_for_move(), "真实队列繁忙时下一方向仍应被接纳。")
	assert_false(previous_travel.is_valid())
	assert_true(tile.position == visible_position, "准入过程只能接管动画，不能把整盘吸附到终点。")
	assert_true(tile.value == 4, "接管时数值必须与已提交模型一致。")
	assert_true(is_same(board._visual_map[data], tile))
	queue.enqueue(BoardAnimationAction.new([
		{&"type": &"MOVE", &"tile": tile, &"to_pos": Vector2(50.0, 150.0)},
	], board))
	assert_true(tile.position == visible_position, "新方向必须从刚看到的位置开始。")
	queue.finish_current_action()
	assert_true(tile.position == Vector2(50.0, 150.0))
	queue.dispose()
	board.model = null
	model.dispose()


func test_scene_exit_cancels_a_moving_merge_without_reparenting_children_to_pool() -> void:
	var board: LiveBoard = LiveBoard.new()
	var scene: CancelOnExitScene = CancelOnExitScene.new()
	var _surface: Node2D = _attach_board_surface(board, scene)
	var pool: ReleaseTrackingPool = ReleaseTrackingPool.new()
	pool.init()
	board._pool = pool
	var consumed: Tile = pool.acquire(_TILE_SCENE, board.board_container) as Tile
	var survivor: Tile = pool.acquire(_TILE_SCENE, board.board_container) as Tile
	consumed.setup(2, &"test", Color.WHITE, Color.BLACK, &"", [], null)
	survivor.setup(2, &"test", Color.WHITE, Color.BLACK, &"", [], null)
	consumed.position = Vector2(200.0, 0.0)
	scene.action = _make_merge(board, consumed, survivor)
	var completion: Variant = scene.action.execute()
	assert_true(completion is Signal)
	assert_true(pool.get_active_count(_TILE_SCENE) == 2)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(consumed))
	assert_false(is_instance_valid(survivor))
	assert_true(pool.release_calls == 0, "拆除场景时不得重新创建池根或重挂正在退出的孩子。")
	pool.prune_invalid_nodes()
	assert_true(pool.get_active_count(_TILE_SCENE) == 0, "销毁后不得残留有效借用。")
	pool.dispose()


func test_active_board_cancellation_still_returns_consumed_tiles_to_pool() -> void:
	var board: LiveBoard = LiveBoard.new()
	var surface: Node2D = _attach_board_surface(board)
	var pool: ReleaseTrackingPool = ReleaseTrackingPool.new()
	pool.init()
	board._pool = pool
	var consumed: Tile = pool.acquire(_TILE_SCENE, board.board_container) as Tile
	var survivor: Tile = pool.acquire(_TILE_SCENE, board.board_container) as Tile
	consumed.position = Vector2(200.0, 0.0)
	var action: BoardAnimationAction = _make_merge(board, consumed, survivor)
	var _completion: Variant = action.execute()
	action.cancel()
	assert_true(pool.release_calls == 1, "活跃棋盘快速接管仍必须复用方块。")
	assert_true(pool.get_available_count(_TILE_SCENE) == 1)
	surface.queue_free()
	await get_tree().process_frame
	pool.dispose()


func test_board_retarget_keeps_identity_and_finishes_even_without_a_next_move() -> void:
	var board: ContinuityBoard = ContinuityBoard.new()
	autofree(board)
	var model: GridModel = GridModel.new()
	model.topology = BoardTopology.create_rectangle(Vector2i(2, 2))
	var data: TileState = TileState.new()
	data.value = 4
	assert_true(model.place_tile(data, Vector2i.ZERO))
	board.model = model
	var tile: Tile = _make_tile()
	tile.position = Vector2(125.0, 50.0)
	board._visual_map[data] = tile
	board.retarget_visuals_to_model_state()
	assert_true(is_same(board._visual_map[data], tile), "接管不能回收再重建整盘节点。")
	assert_true(tile.position == Vector2(125.0, 50.0), "校准身份与数值不能改变当前像素位置。")
	assert_true(tile.value == 4)
	var continuation: Tween = tile._active_move_tween
	assert_not_null(continuation)
	var _settled: bool = continuation.custom_step(1.0)
	assert_true(tile.position == Vector2(50.0, 50.0), "后续方向无效时旧移动仍应自然到达格点。")
	board.model = null
	model.dispose()


# --- 私有/辅助方法 ---

func _make_tile() -> Tile:
	var tile: Tile = _TILE_SCENE.instantiate() as Tile
	add_child_autofree(tile)
	tile.setup(2, &"test", Color.WHITE, Color.BLACK, &"", [], null)
	return tile


func _make_merge(board: GameBoardController, consumed: Tile, survivor: Tile) -> BoardAnimationAction:
	return BoardAnimationAction.new([{
		&"type": &"MERGE", &"consumed_tile": consumed, &"merged_tile": survivor,
		&"to_pos": Vector2.ZERO,
		&"target_setup_data": {&"value": 4, &"definition_id": &"test"},
	}], board)


func _attach_board_surface(board: GameBoardController, surface: Node2D = null) -> Node2D:
	var owner_node: Node2D = surface if surface != null else Node2D.new()
	var nodes: Array[Node] = [
		Panel.new(), Node2D.new(), Node2D.new(), BoardFeedbackCanvas.new(), BoardMotionBackdrop.new(),
	]
	var names: Array[StringName] = [
		&"BoardBackground", &"BoardContainer", &"BoardFeedbackRoot", &"BoardFeedbackCanvas", &"BoardMotionBackdrop",
	]
	for index: int in range(nodes.size()):
		var child: Node = nodes[index]
		child.name = names[index]
		owner_node.add_child(child)
		child.owner = owner_node
		child.unique_name_in_owner = true
	owner_node.add_child(board)
	board.owner = owner_node
	add_child_autofree(owner_node)
	return owner_node


# --- 内部类 ---

class LiveBoard extends GameBoardController:
	func _ready() -> void:
		pass


	func _get_board_feedback_utility() -> GameBoardFeedbackUtility:
		return null


class CancelOnExitScene extends Node2D:
	var action: BoardAnimationAction


	func _exit_tree() -> void:
		if action != null:
			action.cancel()


class ReleaseTrackingPool extends GFObjectPoolUtility:
	var release_calls: int = 0


	## @param node: 本次归还的节点。
	## @param scene: 节点所属的场景资源。
	func release(node: Node, scene: PackedScene) -> void:
		release_calls += 1
		super.release(node, scene)


class ContinuityBoard extends LiveBoard:
	var released_tiles: int = 0


	## @param tile: 用于验证取消时只回收一次的视觉方块。
	func release_visual_tile(tile: Tile) -> void:
		released_tiles += 1
		tile.reset_animation_state()
		tile.set_meta(RELEASE_TOKEN_META, 0)
		tile.hide()


	func _get_board_feedback_utility() -> GameBoardFeedbackUtility:
		return null


	func _get_visible_cells() -> Array[Vector2i]:
		return [Vector2i.ZERO]


	func _sync_grid_cells(_visible_cells: Array[Vector2i]) -> void:
		pass
