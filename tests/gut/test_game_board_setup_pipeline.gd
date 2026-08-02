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
