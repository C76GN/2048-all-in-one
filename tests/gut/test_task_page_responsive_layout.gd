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
