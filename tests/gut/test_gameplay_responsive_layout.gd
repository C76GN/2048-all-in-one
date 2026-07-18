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
	assert_true(
		GameplayResponsiveLayoutController.classify_layout(Vector2(720.0, 1558.0), true)
		== GameplayResponsiveLayoutController.LayoutMode.PORTRAIT
	)


func test_hud_exposes_stable_summary_and_collapsible_details() -> void:
	var hud_root: Node = _HUD_SCENE.instantiate()
	var summary_bar: HBoxContainer = hud_root.get_node("SummaryBar") as HBoxContainer
	var score_value: Label = hud_root.get_node("SummaryBar/ScoreMetric/ScoreValueLabel") as Label
	var move_value: Label = hud_root.get_node("SummaryBar/MovesMetric/MoveCountValueLabel") as Label
	var highest_tile_value: Label = hud_root.get_node(
		"SummaryBar/HighestTileMetric/HighestTileValueLabel"
	) as Label
	var details_toggle: Button = hud_root.get_node("SummaryBar/DetailsToggleButton") as Button
	var details_panel: VBoxContainer = hud_root.get_node("DetailsPanel") as VBoxContainer

	assert_not_null(summary_bar, "HUD 必须提供稳定的移动端摘要栏。")
	assert_not_null(score_value)
	assert_not_null(move_value)
	assert_not_null(highest_tile_value)
	assert_not_null(details_toggle, "低频状态必须可在紧凑布局中按需展开。")
	assert_not_null(details_panel)

	hud_root.free()
