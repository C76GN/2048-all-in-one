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

	assert_not_null(summary_bar, "HUD 必须提供稳定的移动端摘要栏。")
	assert_not_null(score_value)
	assert_not_null(move_value)
	assert_not_null(highest_tile_value)
	assert_not_null(details_toggle, "低频状态必须可在紧凑布局中按需展开。")
	assert_not_null(details_panel)
	assert_not_null(move_up_button, "HUD 应为鼠标和触屏提供完整方向操作。")
	assert_not_null(pause_button, "HUD 应为鼠标和触屏提供非移动玩法操作。")
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
