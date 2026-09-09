## 验证菜单任务页共享的断点、安全区与滚动布局契约。
extends GutTest


# --- 常量 ---

const _SAFE_AREA_PAGE_SCRIPTS: Array[String] = [
	"res://features/navigation/scripts/menus/main_menu.gd",
	"res://features/settings/scripts/menus/settings_menu.gd",
	"res://features/navigation/scripts/menus/mode_selection.gd",
	"res://features/saved_content_browser/scripts/menus/base_list_menu.gd",
]
const _MODE_SELECTION_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)
const _CAPTURE_MATRIX_PATH: String = "res://tools/capture_ui_vfx_matrix.gd"
const _VISUAL_REVIEW_CAPTURE_PATH: String = "res://tools/capture_visual_review.gd"
const _CAPTURE_ARTIFACT_SESSION_PATH: String = (
	"res://tools/visual_capture_artifact_session.gd"
)
const _BOOKMARK_LIST_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
)
const _REPLAY_LIST_SCENE: PackedScene = preload(
	"res://features/replays/scenes/menus/replay_list.tscn"
)
const _BOARD_EDITOR_SCENE: PackedScene = preload(
	"res://features/board_editor/scenes/ui/board_editor_dialog.tscn"
)
const _GAMEPLAY_SCENE: PackedScene = preload(
	"res://features/game_session/scenes/game/game_play.tscn"
)
const _PAUSE_MENU_SCENE: PackedScene = preload(
	"res://features/game_session/scenes/ui/pause_menu.tscn"
)
const _TARGET_REACHED_MENU_SCENE: PackedScene = preload(
	"res://features/game_session/scenes/ui/target_reached_menu.tscn"
)
const _GAME_OVER_MENU_SCENE: PackedScene = preload(
	"res://features/game_session/scenes/ui/game_over_menu.tscn"
)


# --- 测试用例 ---

func test_task_page_classifier_covers_desktop_compact_and_portrait_targets() -> void:
	assert_true(
		GameTaskPageLayoutUtility.classify_layout(Vector2(1280.0, 720.0))
		== GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	)
	assert_true(
		GameTaskPageLayoutUtility.classify_layout(Vector2(960.0, 540.0))
		== GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
	)
	assert_true(
		GameTaskPageLayoutUtility.classify_layout(Vector2(720.0, 1558.0))
		== GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
	)


func test_mode_selection_keeps_960x540_two_pane_after_density_reduction() -> void:
	assert_true(
		ModeSelection._uses_side_by_side_layout(Vector2(960.0, 540.0)),
		"删去独立样张栏并折叠高级设置后，960×540 应保留紧凑双栏。"
	)
	assert_true(
		ModeSelection._uses_side_by_side_layout(Vector2(1280.0, 720.0)),
		"宽屏仍应保留模式列表与关键配置双栏。"
	)
	assert_false(
		ModeSelection._uses_side_by_side_layout(Vector2(720.0, 1558.0)),
		"竖屏仍应采用可滚动单列。"
	)
	assert_false(
		ModeSelection._uses_side_by_side_layout(Vector2(897.0, 720.0)),
		"近方形紧凑窗口应提前堆叠，避免右侧纸面边框和阴影被视口裁切。"
	)
	var column_widths: Vector2 = ModeSelection._get_compact_two_pane_widths(960.0)
	assert_gte(column_widths.x, 500.0, "紧凑横屏模式列表仍应保持可读宽度。")
	assert_gte(column_widths.y, 300.0, "紧凑横屏配置栏应容纳完整关键操作。")
	assert_true(
		is_equal_approx(column_widths.x + column_widths.y + 78.0, 960.0),
		"双栏、栏距和安全留白不得产生横向溢出。"
	)


func test_mode_selection_uses_physical_safe_window_for_runtime_structure() -> void:
	var physical_size: Vector2 = ModeSelection._resolve_physical_layout_size(
		Vector2(1280.0, 720.0),
		{
			&"window_size": Vector2i(960, 540),
			&"safe_area": Rect2i(Vector2i.ZERO, Vector2i(960, 540)),
		}
	)
	assert_true(
		physical_size == Vector2(960.0, 540.0),
		"stretch 后的 1280×720 逻辑画布不得掩盖 960×540 物理窗口断点。"
	)

	var menu_node: Node = _MODE_SELECTION_SCENE.instantiate()
	assert_true(menu_node is ModeSelection)
	if menu_node is ModeSelection:
		var menu: ModeSelection = menu_node
		menu._columns_container = menu.find_child(
			"ColumnsContainer",
			true,
			false
		) as HBoxContainer
		menu._center_column = menu.find_child("CenterColumn", true, false) as VBoxContainer
		menu._center_content_holder = menu.find_child(
			"CenterContentHolder",
			true,
			false
		) as CenterContainer
		menu._left_panel_container = menu.find_child(
			"LeftColumn",
			true,
			false
		) as VBoxContainer
		menu._right_panel_container = menu.find_child(
			"RightColumn",
			true,
			false
		) as VBoxContainer
		menu._set_right_panel_stacked(false)
		var proof: Node = menu.find_child("ModeRuleProof", true, false)
		assert_same(
			menu._right_panel_container.get_parent(),
			menu._columns_container,
			"物理 960×540 运行时结构必须保留模式索引与唯一作业单双栏。"
		)
		assert_true(
			is_instance_valid(proof)
			and menu._right_panel_container.is_ancestor_of(proof),
			"紧凑规则示例必须并入右侧作业单，不得再次成为独立纸面。"
		)
		assert_false(
			menu._left_panel_container.visible,
			"两栏重构后旧 LeftColumn 必须保持隐藏，不能占据第三栏预算。"
		)
	menu_node.free()


func test_mode_selection_physical_960x540_focus_graph_matches_two_pane_layout() -> void:
	var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(960, 540),
		Vector2(1280.0, 720.0)
	)
	menu._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(menu._layout_reference_size == Vector2(960.0, 540.0))
	assert_almost_eq(
		menu._page_title.get_global_rect().position.x,
		menu._mode_list_container.get_global_rect().position.x,
		0.5,
		"缩放后的紧凑横屏标题必须与模式卡左边缘对齐。"
	)
	var safe_page_rect: Rect2 = menu.get_global_rect().grow(-20.0)
	assert_gte(
		menu._right_panel_container.get_global_rect().position.x
		- menu._mode_list_container.get_global_rect().end.x,
		32.0,
		"两栏间距必须容纳配置表面的外扩边缘并留下可见空隙。"
	)
	assert_true(
		safe_page_rect.encloses(menu._right_panel_container.get_global_rect()),
		"紧凑横屏配置面板必须留出完整边缘，不能贴住窗口右侧或顶部。"
	)
	assert_true(
		menu._side_by_side_layout_active,
		"960×540 物理窗口必须把视觉布局和焦点图统一解析为紧凑双栏。"
	)
	assert_same(
		menu._right_panel_container.get_parent(),
		menu._columns_container,
		"配置作业单必须保留为模式索引右侧的唯一第二栏。"
	)
	assert_false(
		menu._left_panel_container.visible,
		"单列任务流只能堆叠一张作业单，旧规则栏必须保持隐藏。"
	)
	assert_true(
		menu._right_panel_container.is_ancestor_of(menu._mode_rule_proof),
		"规则示例必须留在被堆叠的右侧作业单内。"
	)
	assert_false(
		menu._advanced_settings_container.visible,
		"首屏默认只保留棋盘尺寸、开始与高级设置入口。"
	)
	var card: ModeCard = menu._mode_card_slots[0]
	var row_end_card: ModeCard = menu._mode_card_slots[1]
	assert_same(
		card.get_node_or_null(card.focus_neighbor_right),
		row_end_card,
		"两列模式索引应先在同行移动。"
	)
	var expected_order: Array[Control] = [
		menu._grid_size_option_button,
		menu._start_game_button,
		menu._advanced_settings_button,
	]
	var current: Control = row_end_card
	for expected_control: Control in expected_order:
		var focus_path: NodePath = (
			current.focus_neighbor_right
			if current == row_end_card
			else current.focus_neighbor_bottom
		)
		var next_node: Node = current.get_node_or_null(focus_path)
		assert_same(
			next_node,
			expected_control,
			"紧凑双栏焦点必须从模式卡横向进入棋盘尺寸，再连续到达开始与高级设置。"
		)
		current = expected_control

	menu._set_advanced_settings_visible(true)
	menu._setup_focus_neighbors()
	assert_true(menu._advanced_settings_container.visible)
	var visible_controls: Array[Control] = menu._get_visible_configuration_controls()
	assert_true(visible_controls.has(menu._edit_board_button))
	assert_true(visible_controls.has(menu._seed_line_edit))
	assert_true(visible_controls.has(menu._refresh_seed_button))
	assert_same(
		menu._edit_board_button.get_node_or_null(
			menu._edit_board_button.focus_neighbor_bottom
		),
		menu._seed_line_edit,
		"展开高级设置后，自定义棋盘必须能向下抵达种子输入。"
	)
	assert_same(
		menu._seed_line_edit.get_node_or_null(
			menu._seed_line_edit.focus_neighbor_right
		),
		menu._refresh_seed_button,
		"种子输入必须能横向抵达随机种子操作。"
	)


func test_mode_selection_compact_landscape_keeps_one_right_job_sheet() -> void:
	for physical_size: Vector2i in [
		Vector2i(1152, 648),
		Vector2i(1280, 600),
	]:
		var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
			physical_size,
			Vector2(1430.0, 720.0)
		)
		menu._apply_responsive_layout()
		menu._margin_container.queue_sort()
		await get_tree().process_frame
		await get_tree().process_frame

		assert_true(
			menu._side_by_side_layout_active,
			"%s 应保留模式索引与配置作业单双栏。" % physical_size
		)
		assert_same(
			menu._right_panel_container.get_parent(),
			menu._columns_container,
			"紧凑双栏必须让配置作业单留在第二栏。"
		)
		assert_true(
			menu._right_panel_container.is_ancestor_of(menu._mode_rule_proof),
			"规则示例必须成为第二栏作业单的一部分。"
		)
		assert_false(
			menu._left_panel_container.visible,
			"1152px 及矮横屏不能重新显示旧第三栏。"
		)
		assert_false(
			menu._page_scroll.visible,
			"可容纳双栏时不应为了已删除的第三栏启用页面级滚动。"
		)
		assert_true(
			menu._mode_list_container.columns == 2,
			"非竖屏模式列表必须使用两列网格一次呈现六种模式。"
		)
		var compact_widths: Vector2 = ModeSelection._get_compact_two_pane_widths(
			float(physical_size.x)
		)
		assert_lte(
			compact_widths.x + compact_widths.y + 56.0,
			float(physical_size.x) + 0.5,
			"模式索引与作业单的宽度预算必须落在物理视口内。"
		)
		var card: ModeCard = menu._mode_card_slots[1]
		assert_same(
			card.get_node_or_null(card.focus_neighbor_right),
			menu._grid_size_option_button,
			"双栏模式卡必须能直接抵达配置作业单。"
		)
		assert_true(
			menu._start_game_button.is_visible_in_tree(),
			"两栏首屏必须直接显示开始操作。"
		)


func test_mode_selection_1180x620_uses_complete_two_pane_desktop() -> void:
	var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(1180, 620),
		Vector2(1280.0, 720.0)
	)
	menu._apply_responsive_layout()
	menu._margin_container.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		menu._layout_mode == GameTaskPageLayoutUtility.LayoutMode.DESKTOP,
		"1180×620 应命中共享桌面分类。"
	)
	assert_true(menu._side_by_side_layout_active)
	assert_false(
		menu._left_panel_container.visible,
		"桌面构图也只能保留模式索引与开始作业单两栏。"
	)
	assert_same(menu._right_panel_container.get_parent(), menu._columns_container)
	assert_true(
		menu._right_panel_container.is_ancestor_of(menu._mode_rule_proof),
		"规则示例必须留在右侧作业单内。"
	)
	assert_false(
		menu._page_scroll.visible,
		"1180×620 两栏工作区不需要页面级滚动。"
	)
	assert_lte(
		menu._columns_container.get_combined_minimum_size().x,
		menu._margin_container.size.x + 0.5,
		"1180×620 的两栏最小宽度必须落在可用视口内。"
	)
	var card: ModeCard = menu._mode_card_slots[1]
	assert_same(
		card.get_node_or_null(card.focus_neighbor_right),
		menu._grid_size_option_button,
		"降级双栏仍必须从模式卡抵达配置。"
	)
	assert_true(menu._start_game_button.is_visible_in_tree())


func test_mode_selection_1280x720_preserves_relaxed_two_pane_desktop() -> void:
	var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(1280, 720),
		Vector2(1280.0, 720.0)
	)
	menu._apply_responsive_layout()
	menu._margin_container.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(menu._side_by_side_layout_active, "1280×720 应保留完整两栏工作区。")
	assert_false(menu._left_panel_container.visible, "旧规则栏不得作为第三个等权纸面出现。")
	assert_same(menu._right_panel_container.get_parent(), menu._columns_container)
	assert_true(menu._right_panel_container.is_ancestor_of(menu._mode_rule_proof))
	assert_true(menu._mode_list_container.columns == 2)
	assert_false(menu._page_scroll.visible, "完整两栏不需要页面级滚动。")
	assert_true(
		menu._center_content_holder.size_flags_vertical == Control.SIZE_SHRINK_BEGIN,
		"桌面模式索引必须紧接标题顶对齐，不能在右侧工单旁垂直漂到页面中段。"
	)
	assert_lte(
		menu._columns_container.get_combined_minimum_size().x,
		menu._margin_container.size.x + 0.5,
		"1280×720 两栏 combined minimum 必须落在桌面安全区域内。"
	)
	var card: ModeCard = menu._mode_card_slots[1]
	assert_same(
		card.get_node_or_null(card.focus_neighbor_right),
		menu._grid_size_option_button,
		"桌面模式索引必须能横向进入开始作业单。"
	)


func test_mode_selection_portrait_keeps_rule_grid_below_visible_launch_ticket() -> void:
	var landscape: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(1152, 648),
		Vector2(1152.0, 648.0)
	)
	landscape._apply_responsive_layout()
	await get_tree().process_frame
	assert_true(landscape._mode_list_container.columns == 2)

	var portrait: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(720, 960),
		Vector2(720.0, 960.0)
	)
	portrait._apply_responsive_layout()
	await get_tree().process_frame
	assert_true(
		portrait._layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
	)
	assert_true(
		portrait._mode_list_container.columns == 2,
		"竖屏必须让六个模式保持两列可读索引。"
	)
	assert_true(
		portrait._right_panel_container.get_parent() is MarginContainer,
		"竖屏应把当前规则和开始操作堆叠在页面内。"
	)
	assert_same(
		portrait._back_button.get_parent(),
		portrait._center_column,
		"页级返回操作必须在堆叠模式索引之前，不得切断选择到开始的流程。"
	)
	assert_true(
		portrait._back_button.get_index() < portrait._center_content_holder.get_index()
	)
	assert_true(
		portrait._right_panel_container.is_ancestor_of(portrait._mode_rule_proof),
		"竖屏不得把规则示例拆成第二张堆叠纸面。"
	)

	assert_lt(
		portrait._right_panel_container.get_parent().get_index(),
		portrait._center_content_holder.get_index(),
		"当前选择与开始必须出现在规则牌之前。"
	)
	for _layout_pass: int in range(3):
		portrait._apply_responsive_layout()
		await get_tree().process_frame
		assert_lt(
			portrait._right_panel_container.get_parent().get_index(),
			portrait._center_content_holder.get_index(),
			"重复布局和主题刷新不能让当前规则与模式列表交替换位。"
		)
	await get_tree().process_frame
	assert_lte(
		portrait._start_game_button.get_global_rect().end.y,
		portrait.size.y,
		"竖屏开始按钮必须无需滚动即可看见。"
	)


func test_mode_selection_stacked_grid_wraps_to_header_after_launch_ticket_moves_above() -> void:
	for layout_case: Dictionary in [
		{
			&"physical_size": Vector2i(720, 960),
			&"logical_size": Vector2(720.0, 960.0),
		},
		{
			&"physical_size": Vector2i(850, 838),
			&"logical_size": Vector2(730.0, 720.0),
		},
	]:
		var physical_size: Vector2i = layout_case[&"physical_size"]
		var logical_size: Vector2 = layout_case[&"logical_size"]
		var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
			physical_size,
			logical_size
		)
		menu._apply_responsive_layout()
		await get_tree().process_frame

		assert_false(
			menu._side_by_side_layout_active,
			"%s 应使用模式索引接开始作业单的堆叠任务流。" % physical_size
		)
		var column_count: int = menu._mode_list_container.columns
		var cards: Array[ModeCard] = menu._mode_card_slots
		for index: int in range(cards.size()):
			if index + column_count < cards.size():
				continue
			var card: ModeCard = cards[index]
			assert_same(
				card.get_node_or_null(card.focus_neighbor_bottom),
				menu._back_button,
				"规则牌末行向下回到页首，开始区域现在位于网格之前。"
			)


func test_mode_selection_keeps_six_modes_on_one_page_and_folds_advanced_settings() -> void:
	var menu: _ModeSelectionLayoutProbe = _make_mode_selection_layout_probe(
		Vector2i(1280, 720),
		Vector2(1280.0, 720.0)
	)
	menu._mode_config_paths = PackedStringArray([
		"classic",
		"fibonacci",
		"lucas",
		"progressive",
		"step",
		"ratio",
	])
	menu._update_pagination_buttons_visibility()

	assert_true(menu._items_per_page == 6, "当前六种模式必须在同一页完整呈现。")
	assert_true(menu._total_pages == 1)
	assert_false(menu._pagination_container.visible, "六项模式不应引入上一页/下一页。")
	assert_false(
		menu._advanced_settings_container.visible,
		"自定义棋盘、种子和比赛信息默认应折叠。"
	)
	for control: Control in [
		menu._edit_board_button,
		menu._seed_line_edit,
		menu._refresh_seed_button,
	]:
		assert_true(
			menu._advanced_settings_container.is_ancestor_of(control),
			"高级功能必须保留，但统一归入折叠容器。"
		)
	assert_true(menu._advanced_settings_button.is_visible_in_tree())


func test_navigation_rule_cards_show_actual_mode_examples() -> void:
	var expected: Array[String] = [
		"2 + 2 = 4", "2 + 3 = 5", "1 + 3 = 4",
		"1024 + 1024 = 2048", "2 · · → · 2 ·", "8 ÷ 2 = 4",
	]
	for index: int in range(expected.size()):
		assert_true(
			ModeCard._get_rule_sample(ModeSelection.MODE_RULE_PROOF_DESCRIPTORS[index])
			== expected[index]
		)


func test_home_composition_keeps_primary_play_separate_from_compact_library_rail() -> void:
	var scene: PackedScene = load("res://features/navigation/scenes/menus/main_menu.tscn")
	var menu: Node = scene.instantiate()
	autofree(menu)
	var play: Button = menu.find_child("StartGameButton", true, false) as Button
	var rail: GridContainer = menu.find_child("LibraryRail", true, false) as GridContainer
	var motif: Control = menu.find_child("BoardMotif", true, false) as Control
	assert_not_null(play)
	assert_not_null(rail)
	assert_not_null(motif)
	assert_false(rail.is_ancestor_of(play))
	assert_true(rail.get_child_count() == 6)
	assert_gte(play.custom_minimum_size.y, 64.0)
	assert_gte(
		MainMenu._get_board_preview_minimum_size(GameTaskPageLayoutUtility.LayoutMode.PORTRAIT).y,
		240.0,
		"竖屏棋盘封面不再缩成 164px 的附属图标。"
	)


func test_home_responsive_axis_keeps_play_visible_below_poster_hero() -> void:
	var scene: PackedScene = load("res://features/navigation/scenes/menus/main_menu.tscn")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(720, 960)]:
		var node: Node = scene.instantiate()
		node.set_script(_MainMenuLayoutProbe)
		var menu: _MainMenuLayoutProbe = node as _MainMenuLayoutProbe
		menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child_autoqfree(menu)
		menu.size = Vector2(viewport_size)
		menu._viewport_utility = _PhysicalViewportUtility.new(viewport_size)
		menu._apply_responsive_layout()
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(menu._content.vertical)
		assert_true(menu._hero_row.vertical == (viewport_size.y > viewport_size.x))
		assert_false(
			menu._start_game_button.get_global_rect().intersects(
				menu._board_preview_frame.get_global_rect()
			)
		)
		assert_lte(menu._start_game_button.get_global_rect().end.y, menu.size.y)
		assert_lte(menu._library_rail.get_global_rect().end.x, menu.size.x)


func test_mode_selection_center_holder_preserves_centered_axis() -> void:
	var menu: Node = _MODE_SELECTION_SCENE.instantiate()
	var center_holder: CenterContainer = menu.find_child(
		"CenterContentHolder",
		true,
		false
	) as CenterContainer
	assert_not_null(center_holder)
	if center_holder != null:
		assert_false(
			center_holder.use_top_left,
			"两栏工作区必须保留原生居中语义，避免模式网格向左偏移半个宽度。"
		)
	menu.free()


func test_mode_selection_key_controls_preserve_touch_target_contract() -> void:
	var menu: Node = _MODE_SELECTION_SCENE.instantiate()
	autofree(menu)
	for control_name: StringName in [
		&"PrevPageButton",
		&"NextPageButton",
		&"BackButton",
		&"GridSizeOptionButton",
		&"AdvancedSettingsButton",
		&"EditBoardButton",
		&"SeedLineEdit",
		&"RefreshSeedButton",
		&"StartGameButton",
	]:
		var node: Node = menu.find_child(String(control_name), true, false)
		assert_true(node is Control, "模式选择应包含交互控件：%s。" % control_name)
		if not node is Control:
			continue
		var control: Control = node
		assert_gte(
			control.custom_minimum_size.y,
			44.0,
			"%s 必须保留至少 44px 的触控高度。" % control_name
		)


func test_history_list_pages_preserve_touch_target_and_centered_axis() -> void:
	_assert_history_list_touch_targets_and_axis(
		_BOOKMARK_LIST_SCENE,
		"读取存档",
		[&"LoadButton", &"DeleteButton", &"BackButton"]
	)
	_assert_history_list_touch_targets_and_axis(
		_REPLAY_LIST_SCENE,
		"回放列表",
		[&"PlayButton", &"DeleteButton", &"BackButton"]
	)


func test_history_list_compact_surface_width_reserves_safe_area_and_page_scrollbar() -> void:
	assert_true(
		BaseListMenu.get_compact_list_surface_width(
			730.0,
			GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
		) == 692.0,
		"850×838 真实拉伸得到的 730px 逻辑宽度不得把列表压成文字最小宽度。"
	)
	assert_true(
		BaseListMenu.get_compact_list_surface_width(
			720.0,
			GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		) == 674.0,
		"720px 竖屏应为安全区和页面滚动条留出空间，并保留完整列表宽度。"
	)


func test_history_list_empty_state_removes_dead_actions_and_focuses_back() -> void:
	await _assert_history_list_empty_state(
		_BOOKMARK_LIST_SCENE,
		[&"LoadButton", &"DeleteButton"]
	)
	await _assert_history_list_empty_state(
		_REPLAY_LIST_SCENE,
		[&"PlayButton", &"DeleteButton"]
	)


func test_empty_history_focus_survives_responsive_reparent() -> void:
	for list_scene: PackedScene in [
		_BOOKMARK_LIST_SCENE,
		_REPLAY_LIST_SCENE,
	]:
		var menu: BaseListMenu = list_scene.instantiate() as BaseListMenu
		menu._viewport_utility = GFViewportUtility.new()
		menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var back_node: Node = menu.find_child("BackButton", true, false)
		assert_true(back_node is Button)
		if not back_node is Button:
			menu.queue_free()
			await get_tree().process_frame
			continue
		var back_button: Button = back_node
		back_button.grab_focus()
		assert_true(back_button.has_focus())

		for viewport_size: Vector2 in [
			Vector2(1280.0, 720.0),
			Vector2(730.0, 720.0),
			Vector2(720.0, 960.0),
			Vector2(1280.0, 720.0),
		]:
			menu.size = viewport_size
			menu._apply_responsive_layout()
			await get_tree().process_frame
			assert_true(
				back_button.has_focus(),
				"空历史页响应式重排后必须保留返回焦点：%s。"
				% viewport_size
			)

		menu.queue_free()
		await get_tree().process_frame


func test_compact_margins_preserve_page_specific_desktop_composition() -> void:
	var desktop_margins: Dictionary = {
		"top": 54.0,
		"left": 56.0,
		"bottom": 54.0,
		"right": 56.0,
	}
	var desktop: Dictionary = GameTaskPageLayoutUtility.get_safe_area_extra_margins(
		GameTaskPageLayoutUtility.LayoutMode.DESKTOP,
		desktop_margins
	)
	var compact: Dictionary = GameTaskPageLayoutUtility.get_safe_area_extra_margins(
		GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE,
		desktop_margins
	)

	assert_true(desktop == desktop_margins, "桌面页应保留现有构图留白。")
	assert_lt(
		GFVariantData.get_option_float(compact, "left"),
		GFVariantData.get_option_float(desktop, "left"),
		"紧凑横屏应把可用宽度留给主任务内容。"
	)
	desktop["left"] = 0.0
	assert_true(
		GFVariantData.get_option_float(desktop_margins, "left") == 56.0,
		"布局工具不得修改调用方持有的边距字典。"
	)


func test_scroll_wrapper_keeps_content_full_width_and_disables_horizontal_scroll() -> void:
	var margin: MarginContainer = MarginContainer.new()
	add_child_autoqfree(margin)
	var content: VBoxContainer = VBoxContainer.new()
	margin.add_child(content)

	var scroll: ScrollContainer = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		content,
		&"TestScroll"
	)

	assert_not_null(scroll)
	assert_true(content.get_parent() == scroll)
	assert_true(scroll.get_parent() == margin)
	assert_true(
		scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
	)
	assert_true(scroll.follow_focus)
	assert_true(content.size_flags_horizontal == Control.SIZE_EXPAND_FILL)


func test_scroll_wrapper_fills_real_portrait_safe_area() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.size = Vector2(720.0, 960.0)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child_autoqfree(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size.y = 1170.0
	margin.add_child(content)

	var scroll: ScrollContainer = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		content,
		&"PortraitScroll"
	)
	margin.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		scroll.size == Vector2(688.0, 928.0),
		"可真实创建的 720×960 竖屏应让唯一滚动视口占满扣除 16px 安全留白后的区域。"
	)
	assert_true(
		scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"高于首屏的内容必须由该页面滚动容器完整承接。"
	)


func test_target_task_pages_delegate_safe_area_to_gf_viewport_utility() -> void:
	var layout_utility_source: String = FileAccess.get_file_as_string(
		"res://shared/scripts/ui/game_task_page_layout_utility.gd"
	)
	assert_true(
		layout_utility_source.contains("apply_required_safe_area_margins"),
		"任务页安全区应由唯一项目策略入口委托 GFViewportUtility。"
	)
	assert_false(
		layout_utility_source.contains("apply_margin_fallback"),
		"任务页不得恢复绕过 GFViewportUtility 的原生边距 fallback。"
	)
	for script_path: String in _SAFE_AREA_PAGE_SCRIPTS:
		var source: String = FileAccess.get_file_as_string(script_path)
		assert_false(source.is_empty(), "任务页脚本必须可读取：%s" % script_path)
		assert_true(
			source.contains("apply_required_safe_area_margins"),
			"任务页必须通过统一严格入口叠加设备安全区：%s" % script_path
		)
		assert_true(
			source.contains("ensure_vertical_scroll_parent"),
			"任务页必须提供矮屏可达的纵向滚动内容：%s" % script_path
		)


func test_capture_matrix_preserves_project_logical_viewport_contract() -> void:
	var source: String = FileAccess.get_file_as_string(_CAPTURE_MATRIX_PATH)
	assert_false(source.is_empty(), "视觉验收脚本必须可读取。")
	assert_true(
		source.contains("const _LOGICAL_DESIGN_SIZE: Vector2i = Vector2i(720, 720)"),
		"截图矩阵应显式复用项目 720×720 逻辑设计尺寸。"
	)
	assert_true(
		source.contains("Window.CONTENT_SCALE_ASPECT_EXPAND"),
		"截图矩阵应模拟项目真实 expand 拉伸策略。"
	)
	assert_true(
		source.contains("Vector2i(720, 960)"),
		"竖屏截图应使用桌面工作区可真实承载的 720×960 视口。"
	)
	assert_false(
		source.contains("Vector2i(720, 1558)"),
		"截图矩阵不得手动扩张被 Windows 截短的超高窗口并制造伪布局。"
	)
	assert_true(
		source.contains("root.size = resolution"),
		"截图矩阵应让 Root Window 与请求的物理渲染目标一致。"
	)
	assert_false(
		source.contains("root.content_scale_size = resolution"),
		"截图矩阵不得绕过项目逻辑视口。"
	)


func test_capture_matrix_exercises_real_player_gameplay_route_chain() -> void:
	var source: String = FileAccess.get_file_as_string(_CAPTURE_MATRIX_PATH)
	assert_false(source.is_empty(), "视觉验收脚本必须可读取。")
	for required_fragment: String in [
		"_capture_board_editor_player_flow",
		"&\"EditBoardButton\"",
		"&\"StartGameButton\"",
		"_wait_for_gameplay_ready",
		"\"PauseButton\"",
		"GameUiRouterUtility.ROUTE_TARGET_REACHED_MENU",
		"game_flow.check_game_over()",
		"_make_no_moves_snapshot",
		"_is_no_moves_fixture",
		"GAME_OVER_END_REASON_NO_MOVES",
		"_validate_initial_focus",
		'"%s 初始焦点" % String(page_id)',
		"_validate_visible_touch_targets",
		'"%s 空态" % page_id',
		"_validate_mode_selection_single_page",
		"settings_controls_bindings",
		"_validate_leaderboard_filter_label",
		"label.contains(\"board_template.\")",
		"cancel_button.text == \"UI_CANCEL\"",
	]:
		assert_true(
			source.contains(required_fragment),
			"真实玩家链路截图缺少验收片段：%s。" % required_fragment
		)
	for resolution_literal: String in [
		"Vector2i(1280, 720)",
		"Vector2i(960, 540)",
		"Vector2i(720, 960)",
	]:
		assert_true(
			source.contains(resolution_literal),
			"真实玩家链路必须覆盖关键尺寸：%s。" % resolution_literal
		)
	assert_gte(
		source.count("_validate_visible_touch_targets("),
		7,
		"通用页面矩阵与玩法、弹层验收都必须执行 44px 触控目标校验。"
	)
	assert_true(
		source.contains("invoke_godot_project_tool.ps1 放入隔离的 user://"),
		"结算弹层截图必须明确使用隔离 user://，不得污染玩家存档。"
	)


func test_visual_review_injects_history_items_through_the_active_list_backend() -> void:
	var source: String = FileAccess.get_file_as_string(_VISUAL_REVIEW_CAPTURE_PATH)
	assert_false(source.is_empty(), "真实移动与回放验收脚本必须可读取。")
	assert_false(
		source.contains('find_child("ItemsContainer", true, false)'),
		"视觉验收不得再假设共享内容根是 VBoxContainer。"
	)
	assert_false(
		source.contains('find_child("ReplayItemsContainer", true, false)'),
		"视觉验收不得继续引用已经移除的 ReplayItemsContainer。"
	)
	assert_true(
		source.contains("list_menu.items_container")
		and source.contains("list_menu._uses_virtual_list()")
		and source.contains("list_menu._populate_virtual_list(injected_data, template)")
		and source.contains("list_menu._get_list_item_controls()")
		and source.contains("list_menu._setup_item(item_control, data)")
		and source.contains("list_menu._connect_item_signals(item_control, data)")
		and source.contains("list_menu._on_empty_state_changed(false)")
		and source.contains("list_menu._apply_list_focus_order([item_control])")
		and source.contains("item_control.grab_focus()"),
		"视觉验收必须对回放复用 GFVirtualListBinder 生产路径，对书签复用共享内容根。"
	)
	assert_true(
		source.contains("not button.is_visible_in_tree() or button.disabled"),
		"真实视觉验收不得通过隐藏或禁用按钮伪造路由。"
	)
	assert_true(
		source.contains("for child: Node in root.get_children():"),
		"视觉验收退出前必须释放路由场景与 GF 根节点。"
	)
	assert_true(
		source.contains("child.queue_free()"),
		"视觉验收退出前必须排队释放根节点子树。"
	)
	assert_true(
		source.contains("GfToolArchitectureAccess.get_autoload(root)")
		and source.contains("if child == gf_node or child is CanvasLayer:"),
		"视觉验收必须经唯一工具架构边界解析 GF，先释放玩法场景，并把架构拥有的 CanvasLayer 留给 GF 释放。"
	)
	for required_state_fragment: String in [
		'_capture_history_delete_states(bookmark_list, "bookmark")',
		'_capture_history_delete_states(replay_list, "replay")',
		'"%s_delete_confirmation.png" % capture_prefix',
		'"%s_delete_error.png" % capture_prefix',
		"settings_save_failure.png",
	]:
		assert_true(
			source.contains(required_state_fragment),
			"真实视觉验收缺少关键确认/错误态：%s。" % required_state_fragment
		)
	assert_true(
		source.contains("_capture_history_delete_states")
		and source.contains("_capture_settings_persistence_failure"),
		"真实视觉验收必须通过可失败的状态辅助方法生成确认和错误证据。"
	)
	assert_true(
		source.contains("func _wait_for_game_modal_open(")
		and source.count("await _wait_for_game_modal_open()") == 2,
		"删除确认与错误态必须等待异步 GF 路由真正入栈，不能依赖固定帧数。"
	)
	assert_true(
		source.contains("func _wait_for_game_modal_visual_settle(")
		and source.count("await _wait_for_game_modal_visual_settle(") == 2
		and source.contains("_is_control_motion_running(surface)")
		and source.contains("_MODAL_STABLE_FRAME_COUNT"),
		"确认与错误截图必须等待遮罩和任务表面的动效终态连续稳定，不能截取淡入中间帧。"
	)
	assert_true(
		source.contains("controls_button.button_pressed = true"),
		"设置页视觉验收必须触发真实 toggle 终态，不能只伪造 pressed 信号。"
	)


func test_visual_capture_tools_publish_single_run_manifests() -> void:
	var session_source: String = FileAccess.get_file_as_string(
		_CAPTURE_ARTIFACT_SESSION_PATH
	)
	assert_false(session_source.is_empty(), "截图产物会话工具必须可读取。")
	for required_fragment: String in [
		'const _MANIFEST_FILE_NAME: String = "capture_manifest.json"',
		'not _output_directory.begins_with("res://build/")',
		'"head":',
		'"dirty":',
		'"gf_vendor":',
		'"expected_screenshots":',
		'"actual_screenshots":',
		'"terminal":',
	]:
		assert_true(
			session_source.contains(required_fragment),
			"截图 manifest 缺少可追溯字段：%s。" % required_fragment
		)
	for capture_path: String in [
		_CAPTURE_MATRIX_PATH,
		_VISUAL_REVIEW_CAPTURE_PATH,
	]:
		var capture_source: String = FileAccess.get_file_as_string(capture_path)
		assert_true(
			capture_source.contains("VisualCaptureArtifactSession.new("),
			"截图工具必须以单次产物会话清理旧证据：%s。" % capture_path
		)
		assert_true(
			capture_source.contains("_artifact_session.finalize("),
			"截图工具的成功和失败路径都必须写入终态：%s。" % capture_path
		)
	var matrix_source: String = FileAccess.get_file_as_string(
		_CAPTURE_MATRIX_PATH
	)
	var plan_start: int = matrix_source.find(
		"const _EXPECTED_SCREENSHOTS: Array[String] = ["
	)
	var plan_end: int = matrix_source.find("\n]", plan_start)
	assert_true(plan_start >= 0 and plan_end > plan_start)
	var plan_source: String = matrix_source.substr(
		plan_start,
		plan_end - plan_start
	)
	var screenshot_pattern: RegEx = RegEx.new()
	assert_true(screenshot_pattern.compile('"[^"]+\\.png"') == OK)
	assert_true(
		screenshot_pattern.search_all(plan_source).size() == 163,
		"UI 矩阵必须在运行前独立声明完整的 163 张截图契约。"
	)
	assert_false(
		matrix_source.contains("_artifact_session.expect_screenshot(file_name)"),
		"UI 矩阵不得由实际保存分支反向声明 expected。"
	)


func test_capture_matrix_covers_reduced_motion_for_every_page_matrix() -> void:
	var source: String = FileAccess.get_file_as_string(_CAPTURE_MATRIX_PATH)
	assert_true(
		source.contains("await _capture_reduced_motion_page_states(page, page_id)"),
		"所有页面矩阵都必须进入 reduced-motion 验收。"
	)
	assert_true(
		source.contains("const _REDUCED_MOTION_RESOLUTIONS")
		and source.contains("Vector2i(1280, 720)")
		and source.contains("Vector2i(720, 960)"),
		"reduced-motion 必须同时覆盖宽屏与竖屏。"
	)
	assert_true(
		source.contains('accessibility.set_reduced_motion(true)')
		and source.contains(
			"accessibility.set_reduced_motion(previous_state.reduced_motion)"
		),
		"验收必须显式进入 reduced-motion，并恢复原始玩家偏好。"
	)
	assert_true(
		source.contains("await _capture_gameplay_reduced_motion_states(game_play)")
		and source.contains("gameplay_intro_reduced_motion_1280x720.png")
		and source.contains("gameplay_merge_reduced_motion_1280x720.png"),
		"玩法矩阵必须分别保留入场与合并的 reduced-motion 静态终态证据。"
	)


func test_visual_review_separates_scene_reveal_from_gameplay_motion_evidence() -> void:
	var source: String = FileAccess.get_file_as_string(
		_VISUAL_REVIEW_CAPTURE_PATH
	)
	assert_true(
		source.contains("await _wait_for_scene_reveal_terminal(240)")
		and source.contains("gameplay_intro_0020ms.png")
		and source.contains("gameplay_intro_0520ms.png"),
		"棋盘入场时间切片必须在场景揭示终态后单独采样，并覆盖首帧脚点与最终回弹。"
	)
	assert_true(
		source.contains("gameplay_intro_reduced_motion.png")
		and source.contains("gameplay_merge_reduced_motion.png")
		and source.contains("_is_gameplay_intro_static"),
		"视觉复核必须验证玩法入场和合并的 reduced-motion 静态终态。"
	)


func test_player_flow_surfaces_preserve_44px_interaction_contract() -> void:
	_assert_scene_named_touch_targets(
		_BOARD_EDITOR_SCENE,
		[
			&"EditorSectionButton",
			&"LibrarySectionButton",
			&"BrushButton",
			&"EraserButton",
			&"UndoButton",
			&"RedoButton",
			&"RectangleButton",
			&"CrossButton",
			&"NormalizeButton",
			&"ClearButton",
			&"ZoomOutButton",
			&"FitButton",
			&"ZoomInButton",
			&"BoardNameEdit",
			&"SaveButton",
			&"LoadButton",
			&"DeleteButton",
			&"CancelButton",
			&"ApplyButton",
		]
	)
	_assert_scene_named_touch_targets(
		_GAMEPLAY_SCENE,
		[
			&"ZoomOutButton",
			&"FitButton",
			&"ZoomInButton",
			&"DetailsToggleButton",
			&"PauseButton",
			&"UndoButton",
			&"RedoButton",
			&"BookmarkButton",
			&"HintButton",
		]
	)
	_assert_scene_named_touch_targets(
		_PAUSE_MENU_SCENE,
		[
			&"ContinueButton",
			&"RestartButton",
			&"SettingsButton",
			&"MainMenuButton",
		]
	)
	_assert_scene_named_touch_targets(
		_TARGET_REACHED_MENU_SCENE,
		[
			&"ContinueButton",
			&"RestartButton",
			&"MainMenuButton",
		]
	)
	_assert_scene_named_touch_targets(
		_GAME_OVER_MENU_SCENE,
		[
			&"RestartButton",
			&"SettingsButton",
			&"MainMenuButton",
		]
	)


# --- 私有/辅助方法 ---

func _assert_history_list_touch_targets_and_axis(
	scene: PackedScene,
	page_label: String,
	action_names: Array[StringName]
) -> void:
	var menu: Node = scene.instantiate()
	autofree(menu)
	for control_name: StringName in action_names:
		var node: Node = menu.find_child(String(control_name), true, false)
		assert_true(
			node is Control,
			"%s页应包含交互控件：%s。" % [page_label, control_name]
		)
		if not node is Control:
			continue
		var control: Control = node
		assert_gte(
			control.custom_minimum_size.y,
			44.0,
			"%s 必须保留至少 44px 的触控高度。" % control_name
		)
	var title: Node = menu.find_child("PageTitle", true, false)
	assert_true(title is Label, "%s页应包含标题。" % page_label)
	if title is Label:
		var title_label: Label = title
		assert_true(
			title_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
			"%s标题应与列表面板共享稳定的中央轴线。" % page_label
		)


func _assert_history_list_empty_state(
	scene: PackedScene,
	dead_action_names: Array[StringName]
) -> void:
	var menu: BaseListMenu = scene.instantiate() as BaseListMenu
	menu._viewport_utility = GFViewportUtility.new()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var empty_state: Node = menu.find_child("EmptyStateLabel", true, false)
	assert_true(empty_state is Label, "空记录页应显示居中的空态说明。")
	var preview: Node = menu.find_child("PreviewContainer", true, false)
	assert_true(preview is Control, "历史记录页应保留可恢复的预览容器。")
	if preview is Control:
		var preview_control: Control = preview
		assert_false(preview_control.visible, "空态不应继续显示无内容的棋盘预览。")
	for action_name: StringName in dead_action_names:
		var action: Node = menu.find_child(String(action_name), true, false)
		assert_true(action is Control, "历史记录页应包含动作：%s。" % action_name)
		if action is Control:
			var action_control: Control = action
			assert_false(action_control.visible, "空态不应保留无效动作：%s。" % action_name)
	var back: Node = menu.find_child("BackButton", true, false)
	assert_true(back is Button, "空记录页必须保留返回按钮。")
	if back is Button:
		var back_button: Button = back
		assert_true(back_button.visible)
		assert_true(
			get_viewport().gui_get_focus_owner() == back_button,
			"空记录页应把键盘/手柄初始焦点交给返回按钮。"
		)

	menu.queue_free()
	await get_tree().process_frame


func _assert_scene_named_touch_targets(
	scene: PackedScene,
	control_names: Array[StringName]
) -> void:
	var instance: Node = scene.instantiate()
	autofree(instance)
	for control_name: StringName in control_names:
		var node: Node = instance.find_child(String(control_name), true, false)
		assert_true(
			node is Control,
			"玩家链路界面缺少交互控件：%s。" % control_name
		)
		if not node is Control:
			continue
		var control: Control = node
		assert_gte(
			control.custom_minimum_size.x,
			44.0,
			"%s 必须保留至少 44px 的触控宽度。" % control_name
		)
		assert_gte(
			control.custom_minimum_size.y,
			44.0,
			"%s 必须保留至少 44px 的触控高度。" % control_name
		)


func _make_mode_selection_layout_probe(
	physical_size: Vector2i,
	logical_size: Vector2
) -> _ModeSelectionLayoutProbe:
	var menu_node: Node = _MODE_SELECTION_SCENE.instantiate()
	menu_node.set_script(_ModeSelectionLayoutProbe)
	var menu: _ModeSelectionLayoutProbe = menu_node as _ModeSelectionLayoutProbe
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child_autoqfree(menu)
	menu.size = logical_size
	menu._page_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		menu._columns_container,
		&"ModeSelectionTestScroll"
	)
	menu.viewport_probe = _PhysicalViewportUtility.new(physical_size)
	menu._viewport_utility = menu.viewport_probe
	menu._pagination_container.visible = false
	menu._start_game_button.disabled = false
	for _slot_index: int in range(6):
		var card: ModeCard = ModeSelection.MODE_CARD_SCENE.instantiate() as ModeCard
		menu._mode_list_container.add_child(card)
		menu._mode_card_slots.append(card)
	return menu


# --- 内部类 ---

class _MainMenuLayoutProbe extends MainMenu:
	func _ready() -> void:
		pass


class _ModeSelectionLayoutProbe extends ModeSelection:
	var viewport_probe: GFViewportUtility = null


	func _ready() -> void:
		pass


class _PhysicalViewportUtility extends GFViewportUtility:
	var physical_size: Vector2i


	func _init(p_physical_size: Vector2i) -> void:
		physical_size = p_physical_size


	## 返回测试声明的物理窗口与安全区，同时复用 GF 的逻辑边距换算。
	## @param viewport: 用于换算逻辑边距的目标 Viewport。
	## @param extra_margins: 页面声明的附加逻辑边距。
	func get_display_safe_area_margins(
		viewport: Viewport = null,
		extra_margins: Dictionary = {}
	) -> Dictionary:
		var logical_size: Vector2 = Vector2(physical_size)
		if is_instance_valid(viewport):
			logical_size = viewport.get_visible_rect().size
		return calculate_safe_area_margins(
			Rect2i(Vector2i.ZERO, physical_size),
			physical_size,
			logical_size,
			extra_margins
		)
