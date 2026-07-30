## 验证代表性导航界面只在需要时重绘，并把切换动效限制在局部详情。
extends GutTest


func test_main_menu_board_motif_stops_processing_after_settle() -> void:
	var motif: MainMenuBoardMotif = MainMenuBoardMotif.new()
	motif.custom_minimum_size = Vector2(360.0, 360.0)
	add_child_autoqfree(motif)

	motif.play_intro(false, true)
	await wait_seconds(0.45)

	assert_null(motif._intro_tween)
	assert_false(
		motif.is_processing(),
		"首页棋盘落定后不得继续用逐帧处理制造无意义漂移。"
	)
	motif.play_interaction_response(0)
	assert_not_null(
		motif._interaction_tween,
		"首页控件交互仍应触发一次短促棋盘响应。"
	)
	await wait_seconds(0.24)
	assert_null(motif._interaction_tween)
	assert_false(
		motif.is_processing(),
		"局部交互响应结束后仍必须保持静态。"
	)


func test_mode_selection_switches_only_the_detail_surface() -> void:
	var motion: _MotionProbe = _MotionProbe.new()
	var selection: _ModeSelectionProbe = _ModeSelectionProbe.new()
	var detail: VBoxContainer = VBoxContainer.new()
	var configuration: VBoxContainer = VBoxContainer.new()
	autofree(selection)
	selection.add_child(detail)
	selection.add_child(configuration)
	selection.motion_probe = motion
	selection._info_panel_container = detail
	selection._right_panel_container = configuration

	selection._reveal_selection_detail()

	assert_true(motion.switched_controls.size() == 1)
	assert_true(
		motion.switched_controls[0] == detail,
		"模式焦点切换只应更新详情面板，不得重播整个配置栏。"
	)
	assert_false(motion.switched_controls.has(configuration))


# --- 内部类 ---

class _MotionProbe extends GameUiMotionUtility:
	var switched_controls: Array[Control] = []


	## 记录详情控件的局部切换请求，不创建真实 Tween。
	## @param control: 收到切换请求的详情控件。
	## @param _direction: 本探针不使用的语义进入方向。
	## @return: 探针不创建 Tween，始终返回 null。
	func play_content_switch(
		control: Control,
		_direction: float = 1.0
	) -> Tween:
		switched_controls.append(control)
		return null


class _ModeSelectionProbe extends ModeSelection:
	var motion_probe: GameUiMotionUtility = null


	func _get_game_ui_motion_utility() -> GameUiMotionUtility:
		return motion_probe
