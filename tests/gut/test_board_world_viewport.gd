## 验证可缩放棋盘世界的纯变换算法与场景空间分层契约。
extends GutTest


# --- 常量 ---

const _GAME_PLAY_SCENE: PackedScene = preload("res://features/gameplay/scenes/game/game_play.tscn")


# --- 测试用例 ---

func test_fit_zoom_uses_tighter_viewport_axis_and_margin() -> void:
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		Vector2(500.0, 400.0),
		Rect2(Vector2.ZERO, Vector2(1000.0, 500.0)),
		20.0,
		3.0
	)

	assert_almost_eq(fit_zoom, 0.46, 0.0001, "适配比例应由扣除留白后的较紧轴决定。")


func test_centered_position_maps_content_center_to_viewport_center() -> void:
	var viewport_size: Vector2 = Vector2(640.0, 480.0)
	var content_rect: Rect2 = Rect2(Vector2(50.0, 30.0), Vector2(800.0, 600.0))
	var zoom: float = 0.5
	var world_position: Vector2 = CanvasViewportMath.calculate_centered_world_position(
		viewport_size,
		content_rect,
		zoom
	)
	var mapped_center: Vector2 = world_position + content_rect.get_center() * zoom

	assert_true(
		mapped_center.is_equal_approx(viewport_size * 0.5),
		"完整聚焦后内容中心应与视口中心重合。"
	)


func test_zoomed_position_preserves_world_point_under_anchor() -> void:
	var current_position: Vector2 = Vector2(50.0, 30.0)
	var anchor: Vector2 = Vector2(200.0, 100.0)
	var current_zoom: float = 1.0
	var next_zoom: float = 2.0
	var next_position: Vector2 = CanvasViewportMath.calculate_zoomed_world_position(
		current_position,
		anchor,
		current_zoom,
		next_zoom
	)
	var world_point_before: Vector2 = (anchor - current_position) / current_zoom
	var world_point_after: Vector2 = (anchor - next_position) / next_zoom

	assert_true(
		world_point_after.is_equal_approx(world_point_before),
		"围绕锚点缩放时锚点下的棋盘世界坐标必须保持不变。"
	)


func test_clamped_position_centers_small_content_and_keeps_large_content_reachable() -> void:
	var small_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(200.0, 100.0))
	var centered: Vector2 = CanvasViewportMath.calculate_clamped_world_position(
		Vector2(500.0, 400.0),
		small_rect,
		1.0,
		Vector2(-1000.0, 900.0),
		36.0
	)
	assert_true(
		centered.is_equal_approx(Vector2(150.0, 150.0)),
		"小于视口的内容应固定居中，避免被拖到不可见区域。"
	)

	var large_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(1000.0, 800.0))
	var clamped: Vector2 = CanvasViewportMath.calculate_clamped_world_position(
		Vector2(500.0, 400.0),
		large_rect,
		1.0,
		Vector2(900.0, -900.0),
		36.0
	)
	assert_true(
		clamped.is_equal_approx(Vector2(36.0, -436.0)),
		"大内容平移应至少保留边缘余量，并允许访问另一侧边界。"
	)


func test_swipe_classification_accepts_clear_cardinal_gestures() -> void:
	assert_true(
		BoardWorldViewportController.classify_swipe(
			Vector2(100.0, 100.0),
			Vector2(174.0, 108.0),
			0.24
		) == Vector2i.RIGHT,
		"短促且主轴明确的右滑应映射为向右移动。"
	)
	assert_true(
		BoardWorldViewportController.classify_swipe(
			Vector2(100.0, 160.0),
			Vector2(94.0, 92.0),
			0.31
		) == Vector2i.UP,
		"短促且主轴明确的上滑应映射为向上移动。"
	)


func test_swipe_classification_rejects_short_slow_and_ambiguous_tracks() -> void:
	assert_true(
		BoardWorldViewportController.classify_swipe(
			Vector2.ZERO,
			Vector2(20.0, 3.0),
			0.2
		) == Vector2i.ZERO,
		"短触摸轨迹不得触发棋盘移动。"
	)
	assert_true(
		BoardWorldViewportController.classify_swipe(
			Vector2.ZERO,
			Vector2(80.0, 4.0),
			1.2
		) == Vector2i.ZERO,
		"长按拖动不得误判为棋盘滑动。"
	)
	assert_true(
		BoardWorldViewportController.classify_swipe(
			Vector2.ZERO,
			Vector2(70.0, 66.0),
			0.3
		) == Vector2i.ZERO,
		"方向含糊的斜向轨迹必须被拒绝。"
	)


func test_gameplay_input_actions_map_only_cardinal_directions() -> void:
	assert_true(
		GameplayInputActions.action_for_direction(Vector2i.LEFT) == GameplayInputActions.MOVE_LEFT
	)
	assert_true(
		GameplayInputActions.action_for_direction(Vector2i(1, 1)) == &"",
		"触控适配层不得为非四向轨迹伪造玩法动作。"
	)


func test_game_scene_keeps_hud_outside_board_world_and_excludes_diagnostics_ui() -> void:
	var scene_root: Node = _GAME_PLAY_SCENE.instantiate()
	var board_viewport: Control = scene_root.get_node(
		"MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/BoardViewport"
	) as Control
	var board_world: Node2D = board_viewport.get_node("BoardWorld") as Node2D
	var game_board_host: Control = board_world.get_node("GameBoardHost") as Control
	var game_board_controller: Node = game_board_host.get_node("GameBoard")
	var hud: Node = scene_root.get_node("MarginContainer/ColumnsContainer/LeftColumn/HUD")
	var right_column: VBoxContainer = scene_root.get_node(
		"MarginContainer/ColumnsContainer/RightColumn"
	) as VBoxContainer
	var mobile_hud_host: PanelContainer = scene_root.get_node("MobileHudHost") as PanelContainer
	var responsive_controller: Node = scene_root.get_node("GameplayResponsiveLayoutController")

	assert_true(board_viewport.clip_contents, "棋盘视口必须裁剪移出边界的世界内容。")
	assert_same(game_board_controller.get_parent(), game_board_host, "GF Controller 应由棋盘表现宿主承载。")
	assert_false(board_world.is_ancestor_of(hud), "HUD 必须保持在独立屏幕空间。")
	assert_false(right_column.visible, "玩法场景不得为开发诊断工具预留玩家画面栏位。")
	assert_null(
		right_column.get_node_or_null("TestPanel"),
		"TestPanel 必须由 diagnostics feature 的独立 Window 承载。"
	)
	assert_false(board_world.is_ancestor_of(mobile_hud_host), "移动 HUD 宿主不得进入棋盘世界。")
	assert_true(
		responsive_controller is GameplayResponsiveLayoutController,
		"玩法场景必须由专用响应式控制器管理移动布局。"
	)

	scene_root.free()
