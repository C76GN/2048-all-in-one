## 验证语义样式一次提交，避免每个 override 触发独立主题通知。
extends GutTest


const _PALETTE: GameUiPalette = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_palette.tres"
)
const _ARCHIVE_ITEM_SCENES: Array[PackedScene] = [
	preload("res://features/bookmarks/scenes/ui/bookmark_list_item.tscn"),
	preload("res://features/replays/scenes/ui/replay_list_item.tscn"),
]


func test_controls_commit_theme_overrides_in_one_notification() -> void:
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.apply_palette(_PALETTE)
	style.set_static_visuals_enabled(true)
	var root: Control = Control.new()
	add_child_autoqfree(root)
	var label: Label = Label.new()
	var button: Button = Button.new()
	var option: OptionButton = OptionButton.new()
	var line_edit: LineEdit = LineEdit.new()
	var controls: Array[Control] = [
		label, button, option, line_edit,
		RichTextLabel.new(), SpinBox.new(), ProgressBar.new(), HSlider.new(),
		HScrollBar.new(), TabBar.new(), TabContainer.new(), ItemList.new(),
	]
	for control: Control in controls:
		root.add_child(control)
	await get_tree().process_frame
	for control: Control in controls:
		watch_signals(control)
		style.style_control(control)
		assert_signal_emit_count(
			control, "theme_changed", 1,
			"%s 的完整样式应只提交一次主题通知。" % control.get_class()
		)
	assert_true(label.get_theme_color("font_color") == _PALETTE.text_primary_color)
	assert_true(label.get_theme_font("font") == _PALETTE.body_font)
	assert_true(button.get_theme_color("font_color") == _PALETTE.button_font_color)
	assert_true(option.get_theme_color("font_color") == _PALETTE.text_primary_color)
	assert_true(line_edit.get_theme_color("caret_color") == _PALETTE.field_focus_border_color)


func test_restyling_balances_batches_and_preserves_primary_focus_contrast() -> void:
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.apply_palette(_PALETTE)
	style.set_static_visuals_enabled(true)
	var button: Button = Button.new()
	add_child_autoqfree(button)
	await get_tree().process_frame
	watch_signals(button)
	style.style_button(button, GameUiStyleUtility.ButtonRole.PRIMARY)
	style.style_button(button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(button, GameUiStyleUtility.ButtonRole.PRIMARY)
	assert_signal_emit_count(button, "theme_changed", 3, "连续重设角色不得留下未结束批次。")
	assert_true(button.get_theme_color("font_color") == _PALETTE.primary_button_font_color)
	var focus: StyleBox = button.get_theme_stylebox("focus")
	assert_true(focus is StyleBoxFlat)
	if focus is StyleBoxFlat:
		var focus_style: StyleBoxFlat = focus
		assert_true(
			focus_style.border_color == _PALETTE.primary_button_font_color,
			"深色主按钮的静态焦点环应使用高对比前景色。"
		)
		assert_false(focus_style.border_color == _PALETTE.primary_button_color)


func test_archive_selection_uses_theme_without_replacing_focus_or_selection() -> void:
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.apply_palette(_PALETTE)
	style.set_static_visuals_enabled(true)
	for scene: PackedScene in _ARCHIVE_ITEM_SCENES:
		var item_node: Node = scene.instantiate()
		add_child_autoqfree(item_node)
		await get_tree().process_frame
		assert_true(item_node is BaseListMenuItem)
		if not item_node is BaseListMenuItem:
			continue
		var item: BaseListMenuItem = item_node
		item.set_selected(true)
		style.prepare_button(item)
		var highlight_node: Node = item.get_node("SelectionHighlight")
		assert_true(highlight_node is Panel)
		if highlight_node is Panel:
			var highlight: Panel = highlight_node
			assert_true(highlight.visible, "换主题不得清除持久选中。")
			var selected_style: StyleBox = highlight.get_theme_stylebox("panel")
			if selected_style is StyleBoxFlat:
				var selected: StyleBoxFlat = selected_style
				assert_true(selected.bg_color == _PALETTE.selected_surface_color)
				assert_true(selected.border_color == _PALETTE.selected_border_color)
				assert_true(selected.border_width_left == 1)
			assert_false(style.button_uses_embedded_focus_visual(item))
			item.set_selected(false)
			assert_false(highlight.visible)
