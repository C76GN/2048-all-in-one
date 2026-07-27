## 验证菜单任务页共享的断点、安全区与滚动布局契约。
extends GutTest


# --- 常量 ---

const _SAFE_AREA_PAGE_SCRIPTS: Array[String] = [
	"res://features/navigation/scripts/menus/main_menu.gd",
	"res://features/settings/scripts/menus/settings_menu.gd",
	"res://features/navigation/scripts/menus/mode_selection.gd",
	"res://features/navigation/scripts/menus/base_list_menu.gd",
]
const _MODE_SELECTION_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)
const _CAPTURE_MATRIX_PATH: String = "res://tools/capture_ui_vfx_matrix.gd"
const _VISUAL_REVIEW_CAPTURE_PATH: String = "res://tools/capture_visual_review.gd"
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
	"res://features/gameplay/scenes/game/game_play.tscn"
)
const _PAUSE_MENU_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/pause_menu.tscn"
)
const _TARGET_REACHED_MENU_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/target_reached_menu.tscn"
)
const _GAME_OVER_MENU_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/game_over_menu.tscn"
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


func test_mode_selection_keeps_960x540_as_actionable_two_pane_layout() -> void:
	assert_true(
		ModeSelection._uses_side_by_side_layout(Vector2(960.0, 540.0)),
		"960×540 应保留模式列表与关键配置双栏，而不是把开始操作压到列表末尾。"
	)
	assert_false(
		ModeSelection._uses_side_by_side_layout(Vector2(720.0, 1558.0)),
		"竖屏仍应采用可滚动单列。"
	)
	var column_widths: Vector2 = ModeSelection._get_compact_two_pane_widths(960.0)
	assert_gte(column_widths.x, 500.0, "紧凑横屏模式列表仍应保持可读宽度。")
	assert_gte(column_widths.y, 300.0, "紧凑横屏配置栏应容纳完整关键操作。")
	assert_true(
		is_equal_approx(column_widths.x + column_widths.y + 56.0, 960.0),
		"双栏、栏距和安全留白不得产生横向溢出。"
	)


func test_mode_selection_paginates_from_available_first_screen_height() -> void:
	assert_true(
		ModeSelection._get_items_per_page_for_viewport(Vector2(1280.0, 720.0)) == 4,
		"720px 高桌面页只能放四张模式卡，必须为分页和返回按钮保留首屏空间。"
	)
	assert_true(
		ModeSelection._get_items_per_page_for_viewport(Vector2(960.0, 540.0)) == 3,
		"540px 高紧凑横屏只能放三张模式卡，右侧开始操作和左侧分页都应保持可见。"
	)
	assert_true(
		ModeSelection._get_items_per_page_for_viewport(Vector2(720.0, 1558.0)) == 5,
		"高竖屏可以使用完整的五项分页上限。"
	)


func test_mode_selection_key_controls_preserve_touch_target_contract() -> void:
	var menu: Node = _MODE_SELECTION_SCENE.instantiate()
	autofree(menu)
	for control_name: StringName in [
		&"PrevPageButton",
		&"NextPageButton",
		&"BackButton",
		&"GridSizeOptionButton",
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
	for script_path: String in _SAFE_AREA_PAGE_SCRIPTS:
		var source: String = FileAccess.get_file_as_string(script_path)
		assert_false(source.is_empty(), "任务页脚本必须可读取：%s" % script_path)
		assert_true(
			source.contains("apply_display_safe_area_margins"),
			"任务页必须通过 GFViewportUtility 叠加设备安全区：%s" % script_path
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
		"_move_mode_selection_to_first_page",
		"_mode_selection_has_visible_ratio_card",
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


func test_visual_review_injects_history_items_into_the_shared_container() -> void:
	var source: String = FileAccess.get_file_as_string(_VISUAL_REVIEW_CAPTURE_PATH)
	assert_false(source.is_empty(), "真实移动与回放验收脚本必须可读取。")
	assert_true(
		source.contains('find_child("ItemsContainer", true, false)'),
		"视觉验收必须使用 BaseListMenu 的共享 ItemsContainer。"
	)
	assert_false(
		source.contains('find_child("ReplayItemsContainer", true, false)'),
		"视觉验收不得继续引用已经移除的 ReplayItemsContainer。"
	)
	assert_true(
		source.contains("list_menu._setup_item(item_control, data)")
		and source.contains("list_menu._connect_item_signals(item_control, data)")
		and source.contains("list_menu._on_empty_state_changed(false)")
		and source.contains("list_menu._apply_list_focus_order([item_control])")
		and source.contains("item_control.grab_focus()"),
		"真实视觉验收必须按生产列表契约配置项目，并恢复信号、动作与首项焦点。"
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
		source.contains('root.get_node_or_null("Gf")')
		and source.contains("if child == gf_node or child is CanvasLayer:"),
		"视觉验收必须先释放玩法场景，并把架构拥有的 CanvasLayer 留给 GF 释放。"
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
