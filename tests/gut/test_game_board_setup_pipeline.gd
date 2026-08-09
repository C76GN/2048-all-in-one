## 验证棋盘首轮可见节点在揭示前通过 GF 对象池完成预算化预热。
extends GutTest


func test_visible_tile_and_grid_cell_pools_are_prewarmed_without_hiding_active_tiles() -> void:
	var pool: GFObjectPoolUtility = GFObjectPoolUtility.new()
	pool.init()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var board_container: Node2D = Node2D.new()
	add_child_autofree(board_container)
	board.board_container = board_container
	board._pool = pool
	var visible_cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]

	await board._prewarm_visible_node_pools(visible_cells)

	assert_true(
		pool.get_available_count(GameBoardController.TileScene) == visible_cells.size(),
		"首轮揭示前应预热可见窗口对应的 Tile 节点。"
	)
	assert_true(
		pool.get_available_count(board.grid_cell_scene) == visible_cells.size(),
		"首轮揭示前应同时预热可见窗口对应的 GridCell 节点。"
	)

	var active_node: Node = pool.acquire(
		GameBoardController.TileScene,
		board_container
	)
	assert_true(active_node is Tile)
	if active_node is Tile:
		var active_tile: Tile = active_node
		assert_true(active_tile.visible)
		await board._prewarm_visible_node_pools(visible_cells)
		assert_true(
			active_tile.visible,
			"后台补足对象池时不得把已经激活的方块重新隐藏。"
		)

	pool.dispose()
	await get_tree().process_frame


func test_full_player_board_window_is_prewarmed_before_reveal() -> void:
	var pool: _PrewarmSpyPool = _PrewarmSpyPool.new()
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var board_container: Node2D = Node2D.new()
	add_child_autofree(board_container)
	board.board_container = board_container
	board._pool = pool
	var visible_cells: Array[Vector2i] = []
	for y: int in range(16):
		for x: int in range(16):
			visible_cells.append(Vector2i(x, y))

	await board._prewarm_visible_node_pools(visible_cells)

	assert_true(
		pool.get_requested_count(GameBoardController.TileScene) == 256,
		"256 格玩家棋盘应在揭示前完整预热 Tile，而不是停在旧的 128 上限。"
	)
	assert_true(
		pool.get_requested_count(board.grid_cell_scene) == 256,
		"256 格玩家棋盘应在揭示前完整预热 GridCell。"
	)


func test_stale_setup_generation_does_not_continue_with_second_pool() -> void:
	var pool: _PrewarmSpyPool = _PrewarmSpyPool.new()
	pool.pause_first_call = true
	var board: GameBoardController = GameBoardController.new()
	autofree(board)
	var board_container: Node2D = Node2D.new()
	add_child_autofree(board_container)
	board.board_container = board_container
	board._pool = pool
	board._setup_generation = 1
	var visible_cells: Array[Vector2i] = []
	for index: int in range(96):
		visible_cells.append(Vector2i(index, 0))

	@warning_ignore("missing_await")
	board._prewarm_visible_node_pools(visible_cells, 1)
	await get_tree().process_frame
	board._setup_generation = 2
	pool.resume_requested.emit()
	await get_tree().process_frame

	assert_true(
		pool.calls.size() == 1,
		"旧 setup 在第一类节点预热后应观察 generation，不能继续预热第二类节点。"
	)
	var first_call_is_tile_scene: bool = (
		pool.calls[0].get(&"scene") == GameBoardController.TileScene
	)
	assert_true(
		first_call_is_tile_scene,
		"旧 setup 只能完成已经开始的 Tile 预热调用。"
	)


# --- 内部类 ---

class _PrewarmSpyPool extends GFObjectPoolUtility:
	signal resume_requested

	var calls: Array[Dictionary] = []
	var pause_first_call: bool = false


	## @param scene: 记录本次预热对应的节点场景。
	## @param _parent: 测试替身不使用的节点父级。
	## @param count: 记录本次请求的预热数量。
	## @param _msec_budget_per_frame: 测试替身不消费的帧预算。
	## @param _before_add: 测试替身不调用的实例配置回调。
	func prewarm_async_budget(
		scene: PackedScene,
		_parent: Node,
		count: int,
		_msec_budget_per_frame: float = 8.0,
		_before_add: Callable = Callable()
	) -> void:
		calls.append({&"scene": scene, &"count": count})
		if pause_first_call and calls.size() == 1:
			await resume_requested


	## @param scene: 需要查询已记录预热数量的场景。
	func get_requested_count(scene: PackedScene) -> int:
		for call_data: Dictionary in calls:
			if call_data.get(&"scene") == scene:
				return GFVariantData.get_option_int(call_data, &"count")
		return 0
