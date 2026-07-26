## 验证菜单任务页共享的断点、安全区与滚动布局契约。
extends GutTest


# --- 常量 ---

const _SAFE_AREA_PAGE_SCRIPTS: Array[String] = [
	"res://features/navigation/scripts/menus/main_menu.gd",
	"res://features/settings/scripts/menus/settings_menu.gd",
	"res://features/navigation/scripts/menus/mode_selection.gd",
	"res://features/navigation/scripts/menus/base_list_menu.gd",
]


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
