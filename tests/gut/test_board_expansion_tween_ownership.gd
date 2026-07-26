## 验证连续扩建与场景退出时的棋盘 Tween 所有权。
extends GutTest


func test_cancelled_expansion_kills_owned_tween_and_normalizes_cells() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var cell: Panel = Panel.new()
	add_child_autoqfree(cell)
	cell.scale = Vector2.ONE * 0.72
	controller._grid_cell_map[Vector2i.ZERO] = cell
	controller._expansion_tween = cell.create_tween()
	var _scale_tweener: PropertyTweener = controller._expansion_tween.tween_property(
		cell,
		"scale",
		Vector2.ONE * 0.5,
		1.0
	)
	var previous_token: int = controller._expansion_token

	controller._cancel_expansion_animation()

	assert_true(controller._expansion_token == previous_token + 1)
	assert_null(controller._expansion_tween)
	assert_true(cell.scale.is_equal_approx(Vector2.ONE))
	controller.free()


func test_stale_expansion_completion_cannot_finish_newer_animation() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var cell: Panel = Panel.new()
	add_child_autoqfree(cell)
	controller._grid_cell_map[Vector2i.ZERO] = cell
	controller._expansion_token = 4
	cell.scale = Vector2.ONE * 0.72

	controller._on_expansion_animation_finished(3)
	assert_true(
		cell.scale.is_equal_approx(Vector2.ONE * 0.72),
		"旧 Tween 的迟到终态不得覆盖新扩建的起始比例。"
	)

	controller._on_expansion_animation_finished(4)
	assert_true(cell.scale.is_equal_approx(Vector2.ONE))
	controller.free()
