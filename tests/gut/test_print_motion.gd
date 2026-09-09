## 验证印刷动效的稳定命中、连续打断、减少动态和安静纸面切换。
extends GutTest


# --- 常量 ---

const _PRINT: GameUiMotionProfile = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_motion_profile.tres"
)
const _QUIET: GameUiMotionProfile = preload(
	"res://features/themes/resources/themes/game/quiet_paper/ui_motion_profile.tres"
)
const _FEEDBACK: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)
const _TILE_SCENE: PackedScene = preload("res://features/themes/scenes/ui/tiles/tile.tscn")


# --- 测试用例 ---

func test_stamp_release_and_repress_continue_from_visible_paper_without_moving_hitbox() -> void:
	var button: Button = _make_button()
	var presenter: GameButtonMotionPresenter = _make_presenter(button)
	await get_tree().process_frame
	var hit_rect: Rect2 = button.get_global_rect()
	var face: Panel = presenter.get_face()
	var rest_rect: Rect2 = face.get_rect()
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.PRESSED)
	_step_presenter(presenter, 0.04)
	assert_gt(face.position.y, rest_rect.position.y, "按下应把纸面压向下边缘。")
	assert_lt(face.size.y, rest_rect.size.y, "压印只改变内部纸面。")
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	var pressed_rect: Rect2 = face.get_rect()
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.REST)
	assert_true(face.get_rect().is_equal_approx(pressed_rect), "释放不得先跳回静止纸面。")
	var release_tween: Tween = presenter._motion_tween
	_step_presenter(presenter, 0.05)
	var mid_release_rect: Rect2 = face.get_rect()
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.PRESSED)
	assert_false(release_tween.is_valid(), "再次按下必须取消旧回弹的写入。")
	assert_true(face.get_rect().is_equal_approx(mid_release_rect), "再次按下从当前纸面接力。")
	_step_presenter(presenter, 0.04)
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.REST)
	_step_presenter(presenter, 0.2)
	assert_true(face.get_rect().is_equal_approx(rest_rect))
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	assert_true(button.scale.is_equal_approx(Vector2.ONE))
	assert_almost_eq(face.rotation, 0.0, 0.001)


func test_reduced_motion_cancels_stamp_and_profile_switch_reprojects_current_state() -> void:
	var button: Button = _make_button()
	var presenter: GameButtonMotionPresenter = _make_presenter(button)
	await get_tree().process_frame
	var hit_rect: Rect2 = button.get_global_rect()
	var rest_rect: Rect2 = presenter.get_face().get_rect()
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.PRESSED)
	var stamp: Tween = presenter._motion_tween
	_step_presenter(presenter, 0.012)
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.REST, true, true)
	assert_false(stamp.is_valid())
	assert_true(presenter._motion_tween == null, "减少动态应直接静止，不保留不可见动画。")
	assert_true(presenter.get_face().get_rect().is_equal_approx(rest_rect))
	presenter.set_motion_state(GameButtonMotionPresenter.MotionState.PRESSED, false)
	var print_pressed: Rect2 = presenter.get_face().get_rect()
	presenter.apply_motion_profile(_QUIET)
	var quiet_pressed: Rect2 = presenter.get_face().get_rect()
	assert_false(quiet_pressed.is_equal_approx(print_pressed), "主题切换必须重投影已按下状态。")
	assert_true(quiet_pressed.position.is_equal_approx(Vector2(3.0, 3.0)))
	presenter.apply_motion_profile(_PRINT)
	assert_true(presenter.get_face().get_rect().is_equal_approx(print_pressed))
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))


func test_print_content_interruption_keeps_buttons_and_text_at_final_geometry() -> void:
	var surface: Control = _make_interactive_surface()
	var button: Button = _get_surface_button(surface)
	var motion: GameUiMotionUtility = _make_print_motion()
	var hit_rect: Rect2 = button.get_global_rect()
	var surface_rect: Rect2 = surface.get_rect()
	var first: Tween = motion.play_content_switch(surface)
	assert_not_null(first)
	assert_true(surface.get_rect().is_equal_approx(surface_rect))
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	assert_true(surface.modulate.is_equal_approx(Color.WHITE), "文字不能跟随整个面板淡入。")
	assert_false(surface.self_modulate.is_equal_approx(Color.WHITE), "印色只在自身表面短暂落印。")
	var _first_step: bool = first.custom_step(0.03)
	var visible_ink: Color = surface.self_modulate
	var second: Tween = motion.play_content_switch(surface, -1.0)
	assert_false(first.is_valid())
	assert_true(surface.self_modulate.is_equal_approx(visible_ink), "连续切换不能重放初始印色。")
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	motion.complete_control_motion(surface)
	assert_false(second.is_valid())
	assert_true(surface.self_modulate.is_equal_approx(Color.WHITE))
	assert_true(surface.scale.is_equal_approx(Vector2.ONE))
	assert_true(surface.get_rect().is_equal_approx(surface_rect))


func test_print_modal_reverse_preserves_dimmer_and_reduced_motion_commits_terminal() -> void:
	var surface: Control = _make_interactive_surface()
	var button: Button = _get_surface_button(surface)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.size = Vector2(640.0, 360.0)
	add_child_autofree(backdrop)
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	var state: GameAccessibilityState = GameAccessibilityState.new()
	accessibility.set("_state", state)
	var motion: GameUiMotionUtility = _make_print_motion()
	motion.set("_accessibility", accessibility)
	var hit_rect: Rect2 = button.get_global_rect()
	var intro: Tween = motion.play_modal_intro(backdrop, surface)
	assert_not_null(intro)
	assert_true(surface.modulate.is_equal_approx(Color.WHITE))
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	var _intro_step: bool = intro.custom_step(0.04)
	var outro: Tween = motion.play_modal_outro(backdrop, surface)
	assert_false(intro.is_valid())
	var _outro_step: bool = outro.custom_step(0.025)
	var visible_alpha: float = backdrop.modulate.a
	assert_gt(visible_alpha, 0.0)
	var reopened: Tween = motion.play_modal_intro(backdrop, surface)
	assert_false(outro.is_valid())
	assert_almost_eq(backdrop.modulate.a, visible_alpha, 0.001, "反向打开不能闪回透明遮罩。")
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	state.reduced_motion = true
	assert_true(motion.play_modal_intro(backdrop, surface) == null)
	assert_false(reopened.is_valid())
	assert_almost_eq(backdrop.modulate.a, 1.0, 0.001)
	assert_true(surface.self_modulate.is_equal_approx(Color.WHITE))
	assert_true(motion.play_modal_outro(backdrop, surface) == null)
	assert_almost_eq(backdrop.modulate.a, 0.0, 0.001)
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))


func test_quiet_theme_keeps_its_reveal_and_print_deals_start_readable() -> void:
	assert_false(_QUIET.print_motion)
	var content: Control = Control.new()
	content.position = Vector2(80.0, 40.0)
	content.size = Vector2(240.0, 120.0)
	add_child_autofree(content)
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	assert_true(motion.apply_profile(_QUIET))
	var quiet: Tween = motion.play_content_switch(content)
	assert_not_null(quiet)
	assert_almost_eq(content.modulate.a, 0.0, 0.001, "安静纸面保留原有淡入节奏。")
	motion.complete_control_motion(content)
	assert_true(motion.apply_profile(_PRINT))
	var printed: Tween = motion.play_content_switch(content)
	assert_not_null(printed)
	assert_almost_eq(content.modulate.a, 1.0, 0.001, "印刷纸片不能从透明开始。")
	motion.complete_control_motion(content)
	var button: Button = _make_button()
	var presenter: GameButtonMotionPresenter = _make_presenter(button)
	await get_tree().process_frame
	var hit_rect: Rect2 = button.get_global_rect()
	presenter.play_deal_in(Vector2(0.0, 6.0), GameButtonMotionPresenter.MotionState.REST)
	assert_almost_eq(presenter.get_face().modulate.a, 1.0, 0.001)
	assert_true(button.get_global_rect().is_equal_approx(hit_rect))
	presenter.complete_motion()


func test_print_merge_is_local_and_reduced_motion_does_not_delay_impact() -> void:
	var tile: Tile = _TILE_SCENE.instantiate()
	add_child_autofree(tile)
	tile.setup(2, &"test", Color.WHITE, Color.BLACK, &"", [], null)
	var origin: Vector2 = tile.position
	var impacts: Array[int] = [0]
	var impact: Callable = func() -> void: impacts[0] += 1
	var merged: Tween = tile.animate_merge(
		impact, 0.0, _FEEDBACK.tile_motion_profile
	)
	assert_not_null(merged)
	var _impact_step: bool = merged.custom_step(0.04)
	assert_true(impacts[0] == 1)
	assert_gt(tile.scale.x, 1.0)
	assert_lt(tile.scale.y, 1.0, "局部落印应短暂横展纵压。")
	assert_true(tile.position.is_equal_approx(origin))
	assert_almost_eq(tile.rotation, 0.0, 0.001)
	var budget: GameFeedbackBudget = GameFeedbackBudget.new()
	budget.motion_scale = 0.0
	var reduced: Tween = tile.animate_merge(
		impact, 0.2, _FEEDBACK.tile_motion_profile, budget
	)
	assert_true(reduced == null)
	assert_false(merged.is_valid())
	assert_true(impacts[0] == 2, "减少动态不等待传入的装饰延迟才提交碰撞。")
	assert_true(tile.scale.is_equal_approx(Vector2.ONE))
	assert_true(tile.position.is_equal_approx(origin))


# --- 私有/辅助方法 ---

func _make_button() -> Button:
	var button: Button = Button.new()
	button.position = Vector2(80.0, 40.0)
	button.size = Vector2(200.0, 52.0)
	add_child_autofree(button)
	return button


func _make_presenter(button: Button) -> GameButtonMotionPresenter:
	var presenter: GameButtonMotionPresenter = GameButtonMotionPresenter.new()
	presenter.size = button.size
	button.add_child(presenter)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	presenter.configure(button, style, style, style, style, style)
	presenter.apply_motion_profile(_PRINT)
	return presenter


func _step_presenter(presenter: GameButtonMotionPresenter, seconds: float) -> void:
	var tween: Tween = presenter._motion_tween
	assert_not_null(tween)
	if tween != null:
		var _active: bool = tween.custom_step(seconds)


func _make_interactive_surface() -> Control:
	var surface: Control = Control.new()
	surface.position = Vector2(80.0, 40.0)
	surface.size = Vector2(240.0, 120.0)
	var button: Button = Button.new()
	button.position = Vector2(20.0, 50.0)
	button.size = Vector2(120.0, 44.0)
	surface.add_child(button)
	add_child_autofree(surface)
	return surface


func _make_print_motion() -> GameUiMotionUtility:
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	assert_true(motion.apply_profile(_PRINT))
	return motion


func _get_surface_button(surface: Control) -> Button:
	var child: Node = surface.get_child(0)
	if child is Button:
		return child
	return null
