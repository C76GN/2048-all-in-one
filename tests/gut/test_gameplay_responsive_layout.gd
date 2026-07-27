## 验证玩法页断点选择和移动 HUD 场景契约。
extends GutTest


# --- 常量 ---

const _HUD_SCENE: PackedScene = preload("res://features/gameplay/scenes/ui/hud.tscn")


# --- 测试用例 ---

func test_layout_classifier_selects_desktop_compact_and_portrait_modes() -> void:
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(1280.0, 720.0))
		== GameplayResponsiveLayoutController.LayoutMode.DESKTOP
	)
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(960.0, 540.0))
		== GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE
	)
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(720.0, 1558.0))
		== GameplayResponsiveLayoutController.LayoutMode.PORTRAIT
	)


func test_mobile_preference_forces_compact_landscape_without_affecting_portrait() -> void:
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(1280.0, 720.0), true)
		== GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
		"移动设备横屏不应显示桌面诊断三栏。"
	)


func test_board_viewport_fills_safe_gameplay_area() -> void:
	var viewport_minimum: Vector2 = GameplayResponsiveLayoutController.calculate_board_viewport_minimum(
		Vector2(1280.0, 720.0),
		{"left": 20.0, "right": 20.0, "top": 10.0, "bottom": 10.0},
		16.0
	)

	assert_true(viewport_minimum == Vector2(1208.0, 668.0))
	assert_gt(viewport_minimum.x, 0.0, "棋盘视口不得被 CenterContainer 收缩为零宽。")
	assert_gt(viewport_minimum.y, 0.0, "棋盘视口不得被 CenterContainer 收缩为零高。")
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(720.0, 1558.0), true)
		== GameplayResponsiveLayoutController.LayoutMode.PORTRAIT
	)


func test_board_fit_insets_keep_hud_outside_primary_board_composition() -> void:
	var desktop: Dictionary = GameplayResponsiveLayoutController.get_board_fit_insets(
		GameplayResponsiveLayoutController.LayoutMode.DESKTOP
	)
	var portrait: Dictionary = GameplayResponsiveLayoutController.get_board_fit_insets(
		GameplayResponsiveLayoutController.LayoutMode.PORTRAIT
	)

	assert_gt(
		GFVariantData.get_option_float(desktop, "top"),
		GFVariantData.get_option_float(desktop, "bottom"),
		"桌面计分栏需要顶部构图留白。"
	)
	assert_gt(
		GFVariantData.get_option_float(portrait, "bottom"),
		GFVariantData.get_option_float(desktop, "bottom"),
		"竖屏应给底部触控操作保留更多镜头构图区。"
	)
	var compact_near_square: Dictionary = (
		GameplayResponsiveLayoutController.get_board_fit_insets(
			GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
			Vector2(973.0, 781.0)
		)
	)
	assert_gte(
		GFVariantData.get_option_float(compact_near_square, "right"),
		330.0,
		"近方形横屏必须为右侧反馈轨、44px 操作栏和动效包络预留空间。"
	)
	var desktop_motion_safe: Dictionary = (
		GameplayResponsiveLayoutController.get_board_fit_insets(
			GameplayResponsiveLayoutController.LayoutMode.DESKTOP,
			Vector2(1280.0, 720.0)
		)
	)
	assert_gte(
		GFVariantData.get_option_float(desktop_motion_safe, "right"),
		110.0,
		"标准横屏也必须为棋盘冲量和旋转保留动态安全包络。"
	)


func test_wide_board_fit_stays_left_of_landscape_action_panel_motion_boundary() -> void:
	var desktop_viewport_size: Vector2 = Vector2(1248.0, 688.0)
	var desktop_insets: Dictionary = GameplayResponsiveLayoutController.get_board_fit_insets(
		GameplayResponsiveLayoutController.LayoutMode.DESKTOP,
		desktop_viewport_size,
		1.5
	)
	var desktop_board_rect: Rect2 = (
		BoardWorldViewportController.calculate_fitted_content_screen_rect(
			desktop_viewport_size,
			desktop_insets,
			1.5
		)
	)
	assert_lte(
		desktop_board_rect.end.x,
		desktop_viewport_size.x - 342.0 - 50.0,
		"12×8 棋盘在桌面横屏必须停在 ActionPanel 左缘外至少 50px。"
	)

	var compact_viewport_size: Vector2 = Vector2(940.0, 520.0)
	var compact_insets: Dictionary = GameplayResponsiveLayoutController.get_board_fit_insets(
		GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
		compact_viewport_size,
		1.5
	)
	var compact_board_rect: Rect2 = (
		BoardWorldViewportController.calculate_fitted_content_screen_rect(
			compact_viewport_size,
			compact_insets,
			1.5
		)
	)
	assert_lte(
		compact_board_rect.end.x,
		compact_viewport_size.x - 282.0 - 50.0,
		"12×8 棋盘在紧凑横屏也必须停在 ActionPanel 左缘外至少 50px。"
	)


func test_board_geometry_change_publishes_new_content_aspect_ratio() -> void:
	var controller: BoardWorldViewportController = BoardWorldViewportController.new()
	var published_rects: Array[Rect2] = []
	var _geometry_connection: int = controller.content_geometry_changed.connect(
		func(board_rect: Rect2) -> void:
			published_rects.append(board_rect)
	)
	var wide_board_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(1200.0, 800.0))

	controller._on_board_geometry_changed(wide_board_rect)

	assert_almost_eq(
		controller.get_content_aspect_ratio(),
		1.5,
		0.0001,
		"响应式布局必须能读取最新棋盘实际宽高比。"
	)
	assert_true(
		published_rects == [wide_board_rect],
		"棋盘几何变化必须触发布局重算信号。"
	)
	controller.free()


func test_hud_exposes_stable_summary_and_collapsible_details() -> void:
	var hud_root: Node = _HUD_SCENE.instantiate()
	var summary_bar: Node = hud_root.get_node_or_null("SafeArea/TopScorePanel/Margin/SummaryBar")
	var score_value: Node = hud_root.get_node_or_null(
		"SafeArea/TopScorePanel/Margin/SummaryBar/ScoreMetric/ScoreValueLabel"
	)
	var move_value: Node = hud_root.get_node_or_null(
		"SafeArea/TopScorePanel/Margin/SummaryBar/MovesMetric/MoveCountValueLabel"
	)
	var highest_tile_value: Label = hud_root.get_node(
		"SafeArea/TopScorePanel/Margin/SummaryBar/HighestTileMetric/HighestTileValueLabel"
	) as Label
	var details_toggle: Node = hud_root.get_node_or_null("SafeArea/DetailsToggleButton")
	var details_panel: Node = hud_root.get_node_or_null("SafeArea/DetailsPanel")
	var move_up_button: Node = hud_root.get_node_or_null(
		"SafeArea/ControlHintPanel/Margin/Content/DPad/MoveUpButton"
	)
	var pause_button: Node = hud_root.get_node_or_null(
		"SafeArea/ActionPanel/Margin/Buttons/PauseButton"
	)
	var feedback_rail: Node = hud_root.get_node_or_null("SafeArea/FeedbackRail")
	var notification_panel: Node = hud_root.get_node_or_null(
		"SafeArea/FeedbackRail/NotificationPanel"
	)
	var subtitle_panel: Node = hud_root.get_node_or_null(
		"SafeArea/FeedbackRail/AccessibilitySubtitlePanel"
	)
	var notification_label: Node = hud_root.get_node_or_null(
		"SafeArea/FeedbackRail/NotificationPanel/Margin/NotificationLabel"
	)

	assert_not_null(summary_bar, "HUD 必须提供稳定的移动端摘要栏。")
	assert_not_null(score_value)
	assert_not_null(move_value)
	assert_not_null(highest_tile_value)
	assert_not_null(details_toggle, "低频状态必须可在紧凑布局中按需展开。")
	assert_not_null(details_panel)
	assert_not_null(move_up_button, "HUD 应为鼠标和触屏提供完整方向操作。")
	assert_not_null(pause_button, "HUD 应为鼠标和触屏提供非移动玩法操作。")
	assert_true(feedback_rail is VBoxContainer, "瞬时玩法消息必须共用屏幕边缘反馈轨。")
	assert_true(notification_panel is PanelContainer, "GF 通知必须拥有高对比承载表面。")
	assert_true(
		subtitle_panel is PanelContainer and subtitle_panel.get_parent() == feedback_rail,
		"回合字幕必须属于反馈轨，不能固定覆盖棋盘第一行。"
	)
	if notification_panel is PanelContainer and notification_label is RichTextLabel:
		var typed_notification_panel: PanelContainer = notification_panel
		var typed_notification_label: RichTextLabel = notification_label
		var notification_surface: StyleBox = typed_notification_panel.get_theme_stylebox(
			"panel"
		)
		assert_true(notification_surface is StyleBoxFlat, "通知表面必须提供稳定的实色背景。")
		if notification_surface is StyleBoxFlat:
			var flat_surface: StyleBoxFlat = notification_surface
			var foreground: Color = typed_notification_label.get_theme_color(
				"default_color"
			)
			assert_gt(
				absf(
					foreground.get_luminance()
					- flat_surface.bg_color.get_luminance()
				),
				0.70,
				"通知文字与表面必须保持明显明度差，不能再用黄色直接压在纸底上。"
			)
	assert_gte(
		(move_up_button as Control).custom_minimum_size.y,
		44.0,
		"触屏方向按钮必须达到最小触摸目标高度。"
	)
	assert_gte(
		(pause_button as Control).custom_minimum_size.y,
		44.0,
		"触屏动作按钮必须达到最小触摸目标高度。"
	)

	hud_root.free()
