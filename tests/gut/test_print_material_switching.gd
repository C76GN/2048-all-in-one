## 印刷与安静纸面必须通过同一套语义 API 完整切换材质。
extends GutTest


const _PRINT: GameUiPalette = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_palette.tres"
)
const _QUIET: GameUiPalette = preload(
	"res://features/themes/resources/themes/game/quiet_paper/ui_palette.tres"
)


func test_primary_material_switch_restores_shape_font_and_shadow() -> void:
	var button: Button = Button.new()
	add_child_autoqfree(button)
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.set_static_visuals_enabled(true)
	for palette: GameUiPalette in [_PRINT, _QUIET, _PRINT]:
		style.apply_palette(palette)
		style.style_button(button, GameUiStyleUtility.ButtonRole.PRIMARY)
		var face: StyleBoxFlat = _flat_style(button, &"normal")
		assert_true(face.bg_color == palette.primary_button_color)
		assert_true(face.corner_radius_top_left == palette.button_corner_radius)
		assert_true(face.border_width_left == palette.primary_button_border_width)
		assert_true(face.shadow_offset == palette.primary_button_shadow_offset)
		assert_true(is_equal_approx(face.shadow_color.a, palette.primary_button_shadow_opacity))
		assert_true(button.get_theme_font("font") == palette.display_font)
		assert_true(button.get_theme_color("font_color") == palette.primary_button_font_color)
	assert_true(_PRINT.button_corner_radius == 0)
	assert_true(_QUIET.button_corner_radius > 0)
	assert_true(_PRINT.primary_button_shadow_offset == Vector2.ZERO)
	assert_true(_QUIET.primary_button_shadow_offset.y > 0.0)


func test_print_roles_distinguish_actions_fields_tabs_and_shell_rules() -> void:
	var root: Control = Control.new()
	add_child_autoqfree(root)
	var secondary: Button = Button.new()
	var field: LineEdit = LineEdit.new()
	var tabs: TabBar = TabBar.new()
	var shell: PanelContainer = PanelContainer.new()
	root.add_child(secondary)
	root.add_child(field)
	root.add_child(tabs)
	root.add_child(shell)
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.set_static_visuals_enabled(true)
	style.apply_palette(_PRINT)
	style.style_button(secondary, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_control(field)
	style.style_control(tabs)
	style.style_panel_container(shell, GameUiStyleUtility.SurfaceRole.SHELL)
	var action: StyleBoxFlat = _flat_style(secondary, &"normal")
	var field_face: StyleBoxFlat = _flat_style(field, &"normal")
	var tab: StyleBoxFlat = _flat_style(tabs, &"tab_selected")
	var shell_face: StyleBoxFlat = _flat_style(shell, &"panel")
	assert_true(action.border_width_left == 0 and action.border_width_top == 0)
	assert_true(action.border_width_bottom == _PRINT.secondary_button_rule_width)
	assert_true(field_face.border_width_left == 1)
	assert_true(field_face.border_width_bottom == _PRINT.field_bottom_rule_width)
	assert_true(tab.bg_color == _PRINT.text_primary_color)
	assert_true(tabs.get_theme_color("font_selected_color") == _PRINT.panel_surface_color)
	assert_true(shell_face.border_width_left == 0 and shell_face.border_width_bottom == 0)
	assert_true(shell_face.border_width_top == _PRINT.shell_top_rule_width)
	assert_true(shell_face.shadow_offset == Vector2.ZERO)
	var _quiet_refreshed: int = style.apply_palette_to_tree(root, _QUIET)
	assert_true(_flat_style(secondary, &"normal").border_width_left == 1)
	assert_true(_flat_style(tabs, &"tab_selected").bg_color == _QUIET.selected_surface_color)


func test_board_theme_projects_geometry_without_changing_cell_layout() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var cell_style: StyleBoxFlat = StyleBoxFlat.new()
	var print_board: BoardTheme = load(
		"res://features/themes/resources/themes/mode_visuals/defaults/default_board_theme.tres"
	)
	var quiet_board: BoardTheme = load(
		"res://features/themes/resources/themes/game/quiet_paper/board_theme.tres"
	)
	for board: BoardTheme in [print_board, quiet_board, print_board]:
		controller.board_theme = board
		controller._configure_cell_style(cell_style)
		assert_true(cell_style.corner_radius_top_left == board.empty_cell_corner_radius)
		assert_true(cell_style.border_width_left == board.empty_cell_border_width)
	assert_true(print_board.board_corner_radius == 0)
	assert_true(quiet_board.board_corner_radius == 12)
	controller.free()


func test_reused_tile_updates_numeric_font_and_clears_old_override() -> void:
	var scene: PackedScene = load("res://features/themes/scenes/ui/tiles/tile.tscn")
	var instance: Node = scene.instantiate()
	add_child_autoqfree(instance)
	assert_true(instance is Tile)
	if not instance is Tile:
		return
	var tile: Tile = instance
	var visual_theme: TileVisualTheme = load(
		"res://features/themes/resources/themes/game/halftone_atlas_tile_visual_theme.tres"
	)
	var family: TileVisualFamilyStyle = visual_theme.get_family_style(&"tile.visual.classic_numeric")
	for palette: GameUiPalette in [_PRINT, _QUIET, _PRINT]:
		tile.setup(
			128, &"tile.classic.numeric", palette.primary_button_color,
			palette.primary_button_font_color, family.family_id, [], family,
			palette.numeric_font
		)
		assert_true(tile.value_label.get_theme_font("font") == palette.numeric_font)
		assert_true(tile.value_label.text == "128")
	tile.setup(2, &"tile.classic.numeric", Color.WHITE, Color.BLACK, family.family_id, [], family)
	assert_false(tile.value_label.has_theme_font_override("font"))


func test_real_hud_score_reference_keeps_semantic_rail_across_refresh() -> void:
	var scene: PackedScene = load("res://features/game_session/scenes/ui/hud.tscn")
	var instance: Node = scene.instantiate()
	assert_true(instance is Hud)
	if not instance is Hud:
		instance.free()
		return
	var hud: Hud = instance
	var score_node: Node = hud.get_node_or_null("%TopScorePanel")
	assert_true(score_node is PanelContainer, "真实场景必须允许 HUD 以唯一名称解析记分栏。")
	if not score_node is PanelContainer:
		hud.free()
		return
	var score_panel: PanelContainer = score_node
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	style.set_static_visuals_enabled(true)
	style.apply_palette(_PRINT)
	style.style_panel_container(score_panel, GameUiStyleUtility.SurfaceRole.SHELL)
	var _refreshed_count: int = style.refresh_tree(hud)
	var print_face: StyleBoxFlat = _flat_style(score_panel, &"panel")
	assert_true(print_face.border_width_left == 0 and print_face.border_width_bottom == 0)
	assert_true(print_face.border_width_top == _PRINT.shell_top_rule_width)
	var _quiet_refreshed_count: int = style.apply_palette_to_tree(hud, _QUIET)
	assert_true(_flat_style(score_panel, &"panel").border_width_left == 1)
	assert_true(_flat_style(score_panel, &"panel").corner_radius_top_left == _QUIET.panel_corner_radius)
	hud.free()


# --- 私有方法 ---

## @param control: 已应用样式的控件。
## @param style_name: 要验证的状态样式名。
func _flat_style(control: Control, style_name: StringName) -> StyleBoxFlat:
	var value: StyleBox = control.get_theme_stylebox(style_name)
	assert_true(value is StyleBoxFlat)
	if value is StyleBoxFlat:
		var flat: StyleBoxFlat = value
		return flat
	return StyleBoxFlat.new()
