## 验证真实 GF 弹层栈中的主题切换保留已有暂停/结算页及其交互状态。
extends "res://tests/gut/support/gf_test_case.gd"


# --- 私有变量 ---

var _architecture: GFArchitecture
var _context: TestArchitectureContext
var _ui: GFUIUtility
var _router: GameUiRouterUtility
var _themes: _ControlledThemeUtility
var _signals: GFSignalUtility


# --- GUT 生命周期方法 ---

func after_each() -> void:
	if is_instance_valid(_ui):
		_ui.clear_layer(GFUIUtility.Layer.POPUP)
	if _architecture != null:
		_architecture.dispose()
	await get_tree().process_frame
	if is_instance_valid(_context):
		_context.free()
	_architecture = null
	_context = null
	_ui = null
	_router = null
	_themes = null
	_signals = null
	super.after_each()
	await get_tree().process_frame


# --- 测试用例 ---

func test_pause_settings_switch_and_back_refreshes_existing_panel_and_preserves_focus() -> void:
	await _make_live_stack()
	var panel: PauseMenu = _router.push_route(&"pause_menu") as PauseMenu
	assert_not_null(panel)
	if panel == null:
		return
	await _settle_layout()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var original_id: int = panel.get_instance_id()
	var original_title: String = panel._title_label.text
	panel._settings_button.grab_focus()
	var settings_page: SettingsMenu = _open_settings()
	await _settle_layout()
	assert_true(panel.is_inside_tree(), "设置上方入栈时，原暂停面板必须仍在树中。")
	assert_true(_ui.get_top_panel(GFUIUtility.Layer.POPUP) == settings_page)
	assert_true(settings_page.is_node_ready(), "必须执行真实设置页 ready 与可见树刷新分支。")
	_select_theme(settings_page, &"quiet_paper")
	await _settle_layout()
	_assert_primary_button_palette(panel._continue_button)
	assert_true(panel._title_label.get_theme_font("font") == _themes.current.ui_palette.display_font)
	assert_true(panel._surface.corner_radius == _themes.current.ui_palette.shell_corner_radius)
	assert_true(panel._surface.surface_color.is_equal_approx(_themes.current.ui_palette.panel_surface_color))
	assert_true(panel._title_label.text == original_title)
	settings_page._back_button.pressed.emit()
	await _settle_layout()
	assert_true(_ui.get_top_panel(GFUIUtility.Layer.POPUP) == panel)
	assert_true(panel.get_instance_id() == original_id, "返回时不得重建暂停页掩盖旧主题。")
	assert_true(panel._settings_button.has_focus(), "主题刷新不得破坏 GF 弹层返回焦点。")
	_assert_primary_button_palette(panel._continue_button)
	assert_true(
		GFVariantData.to_int(panel._continue_button.get_meta(&"_game_ui_style_button_role"))
		== GameUiStyleUtility.ButtonRole.PRIMARY
	)


func test_game_over_theme_refresh_preserves_expanded_summary_and_closed_owner_disconnects() -> void:
	await _make_live_stack()
	var connections_before: int = _signals.get_connection_count()
	var panel: GameOverMenu = _router.push_route(
		&"game_over_menu", {}, {}, _configure_game_over
	) as GameOverMenu
	assert_not_null(panel)
	if panel == null:
		return
	await _settle_layout()
	panel._details_button.pressed.emit()
	var original_summary: String = panel._summary_label.text
	var original_button_text: String = panel._details_button.text
	assert_true(panel._details_expanded)
	var settings_page: SettingsMenu = _open_settings()
	await _settle_layout()
	_select_theme(settings_page, &"quiet_paper")
	await _settle_layout()
	_assert_primary_button_palette(panel._restart_button)
	assert_true(panel._summary_surface.corner_radius == _themes.current.ui_palette.shell_corner_radius)
	assert_true(panel._details_expanded, "切主题不能重置结算详情展开状态。")
	assert_true(panel._summary_label.visible)
	assert_true(panel._summary_label.text == original_summary)
	assert_true(panel._details_button.text == original_button_text)
	settings_page._back_button.pressed.emit()
	await _settle_layout()
	assert_true(_ui.get_top_panel(GFUIUtility.Layer.POPUP) == panel)
	assert_true(panel._details_expanded)
	var closed_panel_id: int = panel.get_instance_id()
	assert_true(_router.back(GFUIUtility.Layer.POPUP, false))
	assert_false(panel.is_inside_tree())
	assert_true(_signals.get_connection_count() == connections_before)
	_themes.refreshed_roots.clear()
	var _switched: bool = _themes.set_current_visual_theme_id(&"halftone_atlas")
	assert_false(
		_themes.refreshed_roots.has(closed_panel_id),
		"弹层移出树后，即使实例尚未 free，也必须释放主题订阅。"
	)
	panel.free()


# --- 私有/辅助方法 ---

func _make_live_stack() -> void:
	_architecture = GFArchitecture.new()
	_ui = GFUIUtility.new()
	_router = GameUiRouterUtility.new()
	_signals = GFSignalUtility.new()
	_themes = _ControlledThemeUtility.new()
	await _architecture.register_utility(GFResourceBroker, GFResourceBroker.new())
	await _architecture.register_utility(GFAssetUtility, GFAssetUtility.new())
	await _architecture.register_utility(GFResourceResolverUtility, GFResourceResolverUtility.new())
	await _architecture.register_utility(GFUIUtility, _ui)
	await _architecture.register_utility(GFViewportUtility, GFViewportUtility.new())
	await _architecture.register_utility(ProjectResourceCatalogUtility, ProjectResourceCatalogUtility.new())
	await _architecture.register_utility(GameUiRouterUtility, _router)
	_architecture.register_utility_alias(GFUIRouterUtility, GameUiRouterUtility)
	_architecture.register_utility_alias(GameUiRouterPort, GameUiRouterUtility)
	await _architecture.register_utility(GFSignalUtility, _signals)
	await _architecture.register_utility(GameUiStyleUtility, _StyleWithoutAssetLoading.new())
	await _architecture.register_utility(GameThemeUtility, _themes)
	await _architecture.register_model(GameStatusModel, GameStatusModel.new())
	await _architecture.register_model(CurrentGameModel, CurrentGameModel.new())
	assert_true(await _architecture.init())
	_context = TestArchitectureContext.new()
	_context.test_architecture = _architecture
	add_child(_context)
	for layer: int in [GFUIUtility.Layer.HUD, GFUIUtility.Layer.POPUP, GFUIUtility.Layer.TOP]:
		var layer_root: CanvasLayer = _ui.get_layer_root(layer)
		if is_instance_valid(layer_root):
			layer_root.reparent(_context)


func _open_settings() -> SettingsMenu:
	return _router.push_route(
		&"settings_menu",
		{GameUiRouterPort.PARAM_SETTINGS_RETURN_TO_MAIN_MENU_ON_BACK: false},
		{},
		_configure_settings
	) as SettingsMenu


func _configure_settings(panel: Node) -> void:
	panel.set_script(_SettingsWithOptionalServices)
	var settings_page: SettingsMenu = panel as SettingsMenu
	settings_page.return_to_main_menu_on_back = false
	settings_page.process_mode = Node.PROCESS_MODE_ALWAYS


func _configure_game_over(panel: Node) -> void:
	panel.set_script(_GameOverWithoutFlow)


func _select_theme(page: SettingsMenu, theme_id: StringName) -> void:
	var option: OptionButton = page._visual_theme_option
	var index: int = page._get_option_index_for_string_name(option, theme_id)
	option.select(index)
	option.item_selected.emit(index)
	assert_true(_themes.get_current_visual_theme_id() == theme_id)
	assert_false(page._theme_switch_pending)


func _assert_primary_button_palette(button: Button) -> void:
	var box: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(box)
	if box != null:
		assert_true(box.bg_color.is_equal_approx(_themes.current.ui_palette.primary_button_color))
	assert_true(button.get_theme_color("font_color").is_equal_approx(_themes.current.ui_palette.primary_button_font_color))


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- 内部类 ---

## 本测试只替换资源装载阶段；树样式刷新继续执行真实 GameThemeUtility 实现。
class _ControlledThemeUtility extends GameThemeUtility:
	var current: GameTheme = preload("res://features/themes/resources/themes/game/halftone_atlas_theme.tres")
	var quiet: GameTheme = preload("res://features/themes/resources/themes/game/quiet_paper/quiet_paper_theme.tres")
	var refreshed_roots: Array[int] = []


	func get_required_utilities() -> Array[Script]:
		return [GameUiStyleUtility]


	func ready() -> void:
		_style = get_utility(GameUiStyleUtility) as GameUiStyleUtility
		_style.apply_palette(current.ui_palette)


	func get_current_visual_theme() -> GameTheme:
		return current


	func get_visual_theme_descriptors() -> Array[GameThemeDescriptor]:
		var result: Array[GameThemeDescriptor] = []
		for theme_resource: GameTheme in [current, quiet]:
			var descriptor: GameThemeDescriptor = GameThemeDescriptor.new()
			descriptor.theme_id = theme_resource.theme_id
			descriptor.display_name_key = theme_resource.display_name_key
			result.append(descriptor)
		return result


	## @param theme_id: 测试选择的主题 ID。
	func set_current_visual_theme_id(theme_id: StringName) -> bool:
		visual_theme_activation_started.emit(theme_id)
		current = quiet if theme_id == &"quiet_paper" else load("res://features/themes/resources/themes/game/halftone_atlas_theme.tres") as GameTheme
		_style.apply_palette(current.ui_palette)
		visual_theme_changed.emit(current)
		visual_theme_activation_finished.emit(theme_id, true)
		return true


	## @param root: 记录实际刷新并继续交给真实样式逻辑的页面根节点。
	func apply_current_theme_to_tree(root: Node) -> int:
		refreshed_roots.append(root.get_instance_id())
		return super.apply_current_theme_to_tree(root)


class _StyleWithoutAssetLoading extends GameUiStyleUtility:
	func get_required_utilities() -> Array[Script]:
		return []


	func ready() -> void:
		pass


## 保留真实设置页生命周期、picker 和返回逻辑，仅隔离本测试不改变的外部设置服务。
class _SettingsWithOptionalServices extends SettingsMenu:
	## @param utility_type: 此交互切片可用的 Utility 类型。
	func get_utility(utility_type: Script) -> Object:
		return _find_optional_utility(utility_type)


	func _get_current_locale() -> String:
		return "zh"


	func _get_current_window_mode() -> DisplayServer.WindowMode:
		return DisplayServer.WINDOW_MODE_WINDOWED


	func _get_current_vsync_mode() -> DisplayServer.VSyncMode:
		return DisplayServer.VSYNC_ENABLED


	func _get_current_audio_bus_volume(_bus_name: String) -> float:
		return 1.0


class _GameOverWithoutFlow extends GameOverMenu:
	func _get_game_flow_system() -> GameFlowSystem:
		return null
