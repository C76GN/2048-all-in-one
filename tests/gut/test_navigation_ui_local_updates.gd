## 验证代表性导航界面只在需要时重绘，并把切换动效限制在局部详情。
extends GutTest


# --- 常量 ---

const _MODE_SELECTION_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)


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
	motif.play_semantic_response(
		MainMenuBoardMotif.InteractionKind.START_EXPERIMENT
	)
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


func test_main_menu_board_motif_keeps_semantic_response_in_reduced_motion() -> void:
	var motif: MainMenuBoardMotif = MainMenuBoardMotif.new()
	motif.custom_minimum_size = Vector2(220.0, 140.0)
	add_child_autoqfree(motif)

	motif.play_intro(true)
	motif.play_semantic_response(MainMenuBoardMotif.InteractionKind.CALIBRATION)

	assert_null(motif._interaction_tween)
	assert_true(
		motif._interaction_kind == MainMenuBoardMotif.InteractionKind.CALIBRATION
	)
	assert_almost_eq(
		motif._interaction_progress,
		0.5,
		0.001,
		"Reduced Motion 应保留静态套印标记，而不是完全丢失动作语义。"
	)


func test_main_menu_keeps_micro_board_in_compact_layouts() -> void:
	assert_true(
		MainMenu._get_board_preview_minimum_size(
			GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
		) == Vector2(224.0, 128.0),
		"紧凑横屏仍应保留可识别的微缩棋盘，而不是退化为按钮页。"
	)
	assert_true(
		MainMenu._get_board_preview_minimum_size(
			GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		) == Vector2(240.0, 164.0),
		"竖屏应保留棋盘工坊主物件。"
	)


func test_mode_selection_switches_only_the_detail_surface() -> void:
	var motion: _MotionProbe = _MotionProbe.new()
	var selection: _ModeSelectionProbe = _ModeSelectionProbe.new()
	var detail: VBoxContainer = VBoxContainer.new()
	var proof: ModeRuleProof = ModeRuleProof.new()
	var configuration: VBoxContainer = VBoxContainer.new()
	autofree(selection)
	selection.add_child(detail)
	selection.add_child(proof)
	selection.add_child(configuration)
	selection.motion_probe = motion
	selection._info_panel_container = detail
	selection._mode_rule_proof = proof
	selection._right_panel_container = configuration

	selection._reveal_selection_detail()

	assert_true(motion.switched_controls.size() == 2)
	assert_true(
		motion.switched_controls.has(detail)
		and motion.switched_controls.has(proof),
		"模式焦点切换只应更新详情与规则样张，不得重播整个配置栏。"
	)
	assert_false(motion.switched_controls.has(configuration))


func test_mode_pagination_rebinds_persistent_slots_without_frame_churn() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://features/navigation/scripts/menus/mode_selection.gd"
	)
	var method_start: int = source.find("func _refresh_mode_page_and_focus(")
	var method_end: int = source.find("\nfunc _focus_last_selected_card", method_start)
	assert_true(method_start >= 0 and method_end > method_start)
	if method_start < 0 or method_end <= method_start:
		return
	var method_source: String = source.substr(
		method_start,
		method_end - method_start
	)
	assert_true(
		source.contains("var _mode_card_slots: Array[ModeCard]")
		and method_source.contains("_ensure_mode_card_slots(_items_per_page)"),
		"模式分页必须复用固定 ModeCard 卡槽并按页重绑。"
	)
	assert_false(
		method_source.contains("queue_free(")
		or method_source.contains("GFAsyncWaitUtility.next_frame(")
		or method_source.contains("await "),
		"模式翻页不得销毁卡片或等待两帧制造交互空窗。"
	)


func test_mode_pagination_slot_growth_preserves_identity_and_focus() -> void:
	var selection_node: Node = _MODE_SELECTION_SCENE.instantiate()
	selection_node.set_script(_ModeSelectionProbe)
	var selection: _ModeSelectionProbe = selection_node as _ModeSelectionProbe
	assert_not_null(selection)
	if selection == null:
		selection_node.free()
		return
	add_child_autoqfree(selection)
	await get_tree().process_frame

	selection._ensure_mode_card_slots(3)
	assert_true(selection._mode_card_slots.size() == 3)
	var first_card: ModeCard = selection._mode_card_slots[0]
	var first_instance_id: int = first_card.get_instance_id()
	first_card.grab_focus()
	selection._ensure_mode_card_slots(3)
	selection._ensure_mode_card_slots(5)

	assert_true(
		selection._mode_card_slots.size() == 5
		and selection._mode_card_slots[0].get_instance_id() == first_instance_id,
		"响应式页容量增长只能追加卡槽，不得替换已经物化的 ModeCard。"
	)
	assert_same(
		get_viewport().gui_get_focus_owner(),
		first_card,
		"固定卡槽扩容不得夺走当前模式卡的键盘或手柄焦点。"
	)


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


	func _ready() -> void:
		pass


	func _get_game_ui_motion_utility() -> GameUiMotionUtility:
		return motion_probe
