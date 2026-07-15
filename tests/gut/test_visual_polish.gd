## 验证第一轮视觉增强资源与 Tile 动画基础行为。
extends GutTest


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://scenes/components/tile.tscn")
const _GAME_OVER_SCENE: PackedScene = preload("res://scenes/ui/game_over_menu.tscn")
const _TARGET_REACHED_SCENE: PackedScene = preload("res://scenes/ui/target_reached_menu.tscn")
const _BOOKMARK_ITEM_SCENE: PackedScene = preload("res://scenes/ui/bookmark_list_item.tscn")
const _REPLAY_ITEM_SCENE: PackedScene = preload("res://scenes/ui/replay_list_item.tscn")
const _BOOT_SCENE: PackedScene = preload("res://scenes/boot/boot.tscn")
const _BACKGROUND_SHADER_PATH: String = "res://asset_library/shaders/background/halftone_paper_background.gdshader"
const _SCENE_TRANSITION_SHADER_PATH: String = "res://asset_library/shaders/transition/halftone_wipe_transition.gdshader"
const _BUTTON_FOCUS_RING_SHADER_PATH: String = "res://asset_library/shaders/ui/button_focus_dash.gdshader"
const _STARTUP_PROGRESS_SHADER_PATH: String = "res://asset_library/shaders/ui/startup_progress_bar.gdshader"
const _CELEBRATION_CONFETTI_SHADER_PATH: String = "res://asset_library/vfx/celebration_confetti_canvas.gdshader"
const _VISUAL_STYLE_DOC_PATH: String = "res://docs/VISUAL_STYLE.md"
const _BOOT_SCRIPT_PATH: String = "res://scripts/boot/boot.gd"
const _GAME_PLAY_CONTROLLER_PATH: String = "res://scripts/controllers/game_play_controller.gd"
const _HALFTONE_UI_PALETTE: GameUiPalette = preload("res://resources/themes/game/halftone_atlas_ui_palette.tres")
const _HALFTONE_CELEBRATION_VFX_THEME: GameCelebrationVfxTheme = preload("res://resources/themes/game/vfx/halftone_atlas_celebration_theme.tres")
const _CLASSIC_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/classic_tile_theme.tres")
const _FIBONACCI_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/fibonacci_tile_theme.tres")
const _LUCAS_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/lucas_tile_theme.tres")
const _RED_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/red_tile_theme.tres")
const _BLUE_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/blue_tile_theme.tres")
const _MIN_TILE_TEXT_CONTRAST: float = 3.0
const _MIN_UI_TEXT_CONTRAST: float = 4.5


# --- 测试用例 ---

func test_game_background_shader_loads() -> void:
	var shader: Shader = _load_shader(_BACKGROUND_SHADER_PATH)

	assert_true(is_instance_valid(shader), "游戏背景 shader 应能正常加载。")


func test_game_background_shader_keeps_light_paper_texture_defaults() -> void:
	var shader_text: String = _read_text(_BACKGROUND_SHADER_PATH)

	assert_true(shader_text.contains("grid_mask"), "背景 shader 应融合低对比虚线网格纸纹。")
	assert_true(shader_text.contains("cell_color_1"), "背景 shader 应支持棋盘式纸面色块。")
	assert_true(shader_text.contains("sub_grid_size"), "背景 shader 应支持细分副网格。")
	assert_true(shader_text.contains("pixel_cloud_mask"), "背景 shader 应支持程序化像素云/墨流层。")
	assert_true(shader_text.contains("cloud_scroll_speed_1"), "背景墨流层应暴露第一层滚动速度。")
	assert_true(shader_text.contains("cloud_scroll_speed_2"), "背景墨流层应暴露第二层滚动速度。")
	assert_true(shader_text.contains("TIME"), "背景墨流层应使用时间驱动的轻量动效。")
	_assert_shader_float_default_in_range(shader_text, "grain_strength", 0.008, 0.020)
	_assert_shader_float_default_in_range(shader_text, "stipple_strength", 0.000, 0.006)
	_assert_shader_float_default_in_range(shader_text, "scanline_strength", 0.000, 0.008)
	_assert_shader_float_default_in_range(shader_text, "glow_strength", 0.000, 0.100)
	_assert_shader_float_default_in_range(shader_text, "pulse_speed", 0.000, 0.080)
	_assert_shader_float_default_in_range(shader_text, "line_thickness", 0.000, 0.100)
	_assert_shader_float_default_in_range(shader_text, "sub_line_thickness", 0.40, 1.20)
	_assert_shader_float_default_in_range(shader_text, "sub_dash_length", 4.0, 12.0)
	_assert_shader_float_default_in_range(shader_text, "cloud_position_impact", 0.45, 0.70)
	_assert_shader_float_default_in_range(shader_text, "cloud_strength", 0.010, 0.050)


func test_scene_transition_shader_loads_and_keeps_print_defaults() -> void:
	var shader: Shader = _load_shader(_SCENE_TRANSITION_SHADER_PATH)
	var shader_text: String = _read_text(_SCENE_TRANSITION_SHADER_PATH)

	assert_true(is_instance_valid(shader), "半调纸媒场景转场 shader 应能正常加载。")
	assert_true(shader_text.contains("dot_pattern"), "场景转场应使用程序化半调点，不依赖外部形状贴图。")
	assert_true(shader_text.contains("hatch_pattern"), "场景转场应保留印刷斜线纹理。")
	assert_true(shader_text.contains("leading_edge"), "场景转场应有明确移动边缘，而不是静态全屏贴图。")
	assert_true(shader_text.contains("combined_alpha"), "场景转场应组合半透明铺墨和边缘遮罩。")
	assert_true(shader_text.contains("shape_mask_pattern"), "场景转场应使用程序化形状遮罩推进，不依赖外部 shape texture。")
	assert_true(shader_text.contains("shaped_gradient"), "场景转场应由形状扰动擦除边缘，而不是单纯线性淡入。")
	assert_true(shader_text.contains("node_resolution"), "场景转场应按视口比例修正遮罩方向。")
	assert_true(shader_text.contains("reverse_progress"), "同一转场 shader 应支持由主题资源配置覆盖与揭示方向。")
	_assert_shader_float_default_in_range(shader_text, "width", 0.20, 0.36)
	_assert_shader_float_default_in_range(shader_text, "dot_tiling", 24.0, 48.0)
	_assert_shader_float_default_in_range(shader_text, "shape_tiling", 12.0, 28.0)
	_assert_shader_float_default_in_range(shader_text, "shape_feathering", 0.08, 0.20)
	_assert_shader_float_default_in_range(shader_text, "shape_threshold", 0.45, 0.62)
	_assert_shader_float_default_in_range(shader_text, "shape_influence", 0.32, 0.58)
	_assert_shader_float_default_in_range(shader_text, "grain_strength", 0.008, 0.020)
	_assert_shader_float_default_in_range(shader_text, "band_strength", 0.04, 0.16)
	_assert_shader_float_default_in_range(shader_text, "fill_opacity", 0.70, 0.92)
	_assert_shader_float_default_in_range(shader_text, "edge_opacity", 0.88, 1.0)
	_assert_shader_float_default_in_range(shader_text, "edge_strength", 0.60, 0.95)
	_assert_shader_float_default_in_range(shader_text, "registration_offset", 0.008, 0.030)


func test_button_focus_ring_shader_loads_and_uses_dashed_rounded_path() -> void:
	var shader: Shader = _load_shader(_BUTTON_FOCUS_RING_SHADER_PATH)
	var shader_text: String = _read_text(_BUTTON_FOCUS_RING_SHADER_PATH)

	assert_true(is_instance_valid(shader), "按钮选中态虚线描边 shader 应能正常加载。")
	assert_true(shader_text.contains("rounded_box_sdf"), "按钮选中态描边应使用圆角矩形 SDF。")
	assert_true(shader_text.contains("dash_count"), "按钮选中态描边应支持虚线分段。")
	assert_true(shader_text.contains("TIME"), "按钮选中态描边应有轻量移动感。")
	_assert_shader_float_default_in_range(shader_text, "thickness", 2.0, 4.0)
	_assert_shader_float_default_in_range(shader_text, "dash_count", 12.0, 24.0)
	_assert_shader_float_default_in_range(shader_text, "dash_ratio", 0.42, 0.66)


func test_startup_progress_shader_loads_and_uses_print_progress_motif() -> void:
	var shader: Shader = _load_shader(_STARTUP_PROGRESS_SHADER_PATH)
	var shader_text: String = _read_text(_STARTUP_PROGRESS_SHADER_PATH)

	assert_true(is_instance_valid(shader), "启动进度条 shader 应能正常加载。")
	assert_true(shader_text.contains("sd_rounded_box"), "启动进度条应使用圆角 SDF 边框。")
	assert_true(shader_text.contains("sd_rounded_star"), "启动进度条填充应带有星纹印刷图案。")
	assert_true(shader_text.contains("GRAIN_DARKNESS"), "启动进度条空槽应保留轻微颗粒感。")
	assert_true(shader_text.contains("progress"), "启动进度条应暴露 progress 参数供 Boot 驱动。")


func test_boot_scene_uses_startup_screen_and_gf_preload_progress() -> void:
	var boot_node: Node = _BOOT_SCENE.instantiate()
	assert_true(boot_node is Boot, "启动场景根节点应为 Boot。")
	assert_true(boot_node is Control, "启动场景根节点应是可绘制全屏 UI 的 Control。")
	if is_instance_valid(boot_node):
		boot_node.free()

	var boot_source: String = _read_text(_BOOT_SCRIPT_PATH)
	assert_true(boot_source.contains("GFAsyncProgress"), "Boot 应使用 GFAsyncProgress 统一启动进度。")
	assert_true(boot_source.contains("GFAsyncWaitUtility.wait_until"), "Boot 应使用 GFAsyncWaitUtility 统一预加载条件与超时。")
	assert_true(boot_source.contains("GFAsyncWaitUtility.delay_seconds"), "Boot 启动画面延迟应受 GF 生命周期保护。")
	assert_true(boot_source.contains("preload_scene(MAIN_MENU_SCENE_PATH, true)"), "Boot 应通过 GFSceneUtility 预热主菜单。")
	assert_true(boot_source.contains(_STARTUP_PROGRESS_SHADER_PATH), "Boot 应使用正式登记的启动进度条 shader。")
	assert_true(boot_source.contains("_setup_startup_screen"), "Boot 应创建启动画面内容，而不是空白等待。")


func test_celebration_confetti_shader_loads_and_keeps_print_defaults() -> void:
	var shader: Shader = _load_shader(_CELEBRATION_CONFETTI_SHADER_PATH)
	var shader_text: String = _read_text(_CELEBRATION_CONFETTI_SHADER_PATH)

	assert_true(is_instance_valid(shader), "庆祝纸屑 shader 应能正常加载。")
	assert_true(shader_text.contains("PARTICLE_COUNT = 88"), "庆祝纸屑数量应克制，避免廉价全屏彩纸噪音。")
	assert_true(shader_text.contains("palette_color"), "庆祝纸屑应使用主题化 CMYK 色板。")
	assert_true(shader_text.contains("rotate2d"), "庆祝纸屑应有轻量旋转，而不是静态贴片。")
	_assert_shader_float_default_in_range(shader_text, "speed", 80.0, 130.0)
	_assert_shader_float_default_in_range(shader_text, "sway_strength", 24.0, 54.0)
	_assert_shader_float_default_in_range(shader_text, "spin_speed", 1.8, 3.4)
	_assert_shader_float_default_in_range(shader_text, "piece_size", 5.0, 9.0)


func test_halftone_ui_palette_keeps_text_readable_on_light_surfaces() -> void:
	assert_true(is_instance_valid(_HALFTONE_UI_PALETTE), "halftone_atlas UI 色板应能加载。")

	var issues: Array[String] = []
	_collect_palette_contrast_issue(
		"主文字 / 面板",
		_HALFTONE_UI_PALETTE.text_primary_color,
		_HALFTONE_UI_PALETTE.panel_surface_color,
		issues
	)
	_collect_palette_contrast_issue(
		"次级文字 / 面板",
		_HALFTONE_UI_PALETTE.text_secondary_color,
		_HALFTONE_UI_PALETTE.panel_surface_color,
		issues
	)
	_collect_palette_contrast_issue(
		"按钮文字 / 默认按钮",
		_HALFTONE_UI_PALETTE.button_font_color,
		_HALFTONE_UI_PALETTE.button_normal_color,
		issues
	)
	_collect_palette_contrast_issue(
		"输入文字 / 输入框",
		_HALFTONE_UI_PALETTE.text_primary_color,
		_HALFTONE_UI_PALETTE.field_surface_color,
		issues
	)

	assert_true(
		issues.is_empty(),
		"浅色纸面主题的 UI 文字对比度不能低于 %.1f:1：\n%s" % [
			_MIN_UI_TEXT_CONTRAST,
			_join_lines(issues),
		]
	)


func test_gameplay_controller_applies_theme_to_non_menu_controls() -> void:
	var source: String = _read_text(_GAME_PLAY_CONTROLLER_PATH)

	assert_true(
		source.contains("apply_current_theme_to_tree(self)"),
		"游戏局内不是 GameUIController，必须主动把主题应用到 HUD / TestPanel。"
	)
	assert_true(
		source.contains("bind_interactive_controls(self)"),
		"游戏局内必须主动绑定测试面板等按钮的主题样式。"
	)


func test_visual_style_document_records_retro_print_direction() -> void:
	var text: String = _read_text(_VISUAL_STYLE_DOC_PATH)
	var missing_terms: Array[String] = []
	for term: String in [
		"CMYK 半调纸媒游戏",
		"risograph",
		"半调网点",
		"侧边重复印刷条纹",
		"粗描边",
		"不是深色玻璃 UI",
		"TilePatternOverlay",
		"grain_strength",
		"stipple_strength",
		"halftone_wipe_transition.gdshader",
		"印刷擦除",
		"resources/themes/tile_schemes",
		"GameUiMotionUtility",
	]:
		if not text.contains(term):
			_append_string(missing_terms, term)

	assert_true(
		missing_terms.is_empty(),
		"视觉规范文档应固定 CMYK 半调纸媒方向和关键落地点，缺少：\n%s" % _join_lines(missing_terms)
	)


func test_tile_setup_applies_pixel_textured_style() -> void:
	var tile: Tile = await _create_tile()

	tile.setup(2048, Tile.TileType.PLAYER, Color(0.8, 0.5, 0.2, 1.0), Color.WHITE)

	var stylebox: StyleBoxFlat = _get_stylebox_flat(tile.background, &"panel")
	assert_not_null(stylebox, "Tile 背景应使用 StyleBoxFlat。")
	assert_true(stylebox.shadow_size == 0, "Tile 背景应保持无阴影的平面色块。")
	assert_true(stylebox.get_border_width(SIDE_TOP) >= 3, "Tile 背景应使用粗像素描边。")
	assert_true(stylebox.bg_color == Color(0.8, 0.5, 0.2, 1.0), "Tile 背景应直接使用实心色块。")

	var pattern_node: Node = tile.get_node_or_null("PatternOverlay")
	assert_true(pattern_node is Control, "Tile 应包含低对比度纹理叠层。")
	if pattern_node is Control:
		var pattern_control: Control = pattern_node
		assert_true(pattern_control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "纹理叠层不应阻挡输入。")


func test_game_board_controller_uses_configured_tile_scheme_colors() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var grid_model: GridModel = GridModel.new()
	grid_model.interaction_rule = ClassicInteractionRule.new()
	controller.model = grid_model
	controller.color_schemes = {
		Tile.TileType.PLAYER: _CLASSIC_TILE_THEME,
	}

	var value_2_colors: Dictionary = controller._get_tile_colors(2, Tile.TileType.PLAYER)
	var value_4_colors: Dictionary = controller._get_tile_colors(4, Tile.TileType.PLAYER)
	var value_2_style: TileLevelStyle = _get_tile_level_style(_CLASSIC_TILE_THEME, 0)
	var value_4_style: TileLevelStyle = _get_tile_level_style(_CLASSIC_TILE_THEME, 1)

	assert_true(
		_get_color(value_2_colors, &"bg") == value_2_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块背景色。"
	)
	assert_true(
		_get_color(value_2_colors, &"font") == value_2_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块字体色。"
	)
	assert_true(
		_get_color(value_4_colors, &"bg") == value_4_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块背景色。"
	)
	assert_true(
		_get_color(value_4_colors, &"font") == value_4_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块字体色。"
	)
	controller.free()


func test_tile_color_schemes_keep_large_number_text_readable() -> void:
	var issues: Array[String] = []
	_collect_tile_scheme_contrast_issues("classic", _CLASSIC_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("fibonacci", _FIBONACCI_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("lucas", _LUCAS_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("red", _RED_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("blue", _BLUE_TILE_THEME, issues)

	assert_true(
		issues.is_empty(),
		"方块主题的数字文字应保持至少 %.1f:1 的大字号对比度，避免半调纹理和印刷色牺牲可读性：\n%s" % [
			_MIN_TILE_TEXT_CONTRAST,
			_join_lines(issues),
		]
	)


func test_tile_visual_animations_return_live_tweens() -> void:
	var tile: Tile = await _create_tile()
	tile.setup(2, Tile.TileType.PLAYER, Color(0.9, 0.75, 0.45, 1.0), Color.BLACK)

	var spawn_tween: Tween = tile.animate_spawn()
	assert_true(is_instance_valid(spawn_tween) and spawn_tween.is_valid(), "生成动画应返回有效 Tween。")

	tile.reset_animation_state()
	var move_tween: Tween = tile.animate_move(Vector2(48.0, 32.0))
	assert_true(is_instance_valid(move_tween) and move_tween.is_valid(), "移动动画应返回有效 Tween。")

	tile.reset_animation_state()
	var merge_tween: Tween = tile.animate_merge()
	assert_true(is_instance_valid(merge_tween) and merge_tween.is_valid(), "合并动画应返回有效 Tween。")

	tile.reset_animation_state()
	var transform_tween: Tween = tile.animate_transform()
	assert_true(is_instance_valid(transform_tween) and transform_tween.is_valid(), "转化动画应返回有效 Tween。")

	tile.reset_animation_state()

func test_ui_motion_utility_binds_buttons_recursively_once() -> void:
	var root: Control = Control.new()
	var container: VBoxContainer = VBoxContainer.new()
	var button: Button = Button.new()
	root.add_child(container)
	container.add_child(button)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiMotionUtility, motion_utility)
	await architecture.init()
	motion_utility.apply_palette(_HALFTONE_UI_PALETTE)
	var emitted_events: Dictionary = {
		&"selected": 0,
		&"confirmed": 0,
	}
	var _selected_connect: int = motion_utility.interactive_control_selected.connect(func(_control: Control) -> void:
		emitted_events[&"selected"] = GFVariantData.to_int(emitted_events.get(&"selected", 0), 0) + 1
	)
	var _confirmed_connect: int = motion_utility.interactive_control_confirmed.connect(func(_control: Control) -> void:
		emitted_events[&"confirmed"] = GFVariantData.to_int(emitted_events.get(&"confirmed", 0), 0) + 1
	)

	assert_true(motion_utility.bind_interactive_controls(root) == 1, "UI 动效 Utility 应递归绑定按钮。")
	assert_true(motion_utility.bind_interactive_controls(root) == 0, "重复绑定不应重复连接同一按钮。")
	button.mouse_entered.emit()
	button.button_down.emit()

	var button_style: StyleBoxFlat = _get_stylebox_flat(button, &"normal")
	assert_not_null(button_style, "按钮绑定后应获得统一 StyleBoxFlat。")
	assert_true(button_style.get_border_width(SIDE_TOP) >= 2, "统一按钮样式应使用像素菜单描边。")
	assert_true(button_style.shadow_size == 0, "统一按钮样式应保持无阴影。")

	var ring_node: Node = button.get_node_or_null("ButtonFocusRing")
	assert_true(ring_node is ColorRect, "按钮绑定后应自动挂载选中态虚线描边 overlay。")
	if ring_node is ColorRect:
		var ring: ColorRect = ring_node
		assert_true(ring.mouse_filter == Control.MOUSE_FILTER_IGNORE, "选中态描边不应阻挡按钮输入。")
		assert_true(ring.material is ShaderMaterial, "选中态描边应使用共享 shader 材质。")
		assert_true(ring.visible, "hover 后选中态描边应可见。")
		if ring.material is ShaderMaterial:
			var ring_material: ShaderMaterial = ring.material
			var ring_color_value: Variant = ring_material.get_shader_parameter(&"color")
			var ring_color: Color = Color.TRANSPARENT
			if ring_color_value is Color:
				ring_color = ring_color_value
			assert_true(
				is_equal_approx(GFVariantData.to_float(ring_material.get_shader_parameter(&"dash_count")), 18.0),
				"按钮焦点描边应由主题 GFShaderParameterProfile 写入虚线数量。"
			)
			assert_true(
				ring_color == _HALFTONE_UI_PALETTE.button_focus_border_color,
				"按钮焦点描边颜色应跟随当前 UI 色板。"
			)

	button.mouse_exited.emit()
	if ring_node is ColorRect:
		var hidden_ring: ColorRect = ring_node
		assert_false(hidden_ring.visible, "hover 结束后选中态描边应隐藏。")

	assert_true(_get_event_count(emitted_events, &"selected") == 1, "hover/focus 应发出 UI 选择音效语义信号。")
	assert_true(_get_event_count(emitted_events, &"confirmed") == 1, "button down 应发出 UI 确认音效语义信号。")
	architecture.dispose()


func test_ui_motion_utility_styles_spinbox_as_readable_light_field() -> void:
	var root: Control = Control.new()
	var spin_box: SpinBox = SpinBox.new()
	root.add_child(spin_box)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	var _applied_count: int = motion_utility.apply_palette_to_tree(root, _HALFTONE_UI_PALETTE)

	var line_edit: LineEdit = spin_box.get_line_edit()
	assert_true(is_instance_valid(line_edit), "SpinBox 应暴露可统一刷色的内部 LineEdit。")
	if is_instance_valid(line_edit):
		var font_color: Color = line_edit.get_theme_color("font_color")
		var normal_style: StyleBoxFlat = _get_stylebox_flat(line_edit, &"normal")
		assert_not_null(normal_style, "SpinBox 内部输入框应获得主题 StyleBoxFlat。")
		if is_instance_valid(normal_style):
			assert_true(
				_get_contrast_ratio(font_color, normal_style.bg_color) >= _MIN_UI_TEXT_CONTRAST,
				"SpinBox 字体在浅色字段上必须保持可读。"
			)


func test_ui_motion_utility_reveals_panel_with_tween() -> void:
	var panel: Control = Control.new()
	panel.position = Vector2(12.0, 20.0)
	panel.scale = Vector2.ONE
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	var tween: Tween = motion_utility.play_panel_intro(panel)

	assert_true(is_instance_valid(tween) and tween.is_valid(), "面板入场应返回有效 Tween。")
	assert_gt(panel.position.y, 20.0, "面板入场起点应带有轻微下移。")
	assert_lt(panel.modulate.a, 1.0, "面板入场起点应先淡入。")


func test_ui_motion_utility_reveals_visible_children_only() -> void:
	var container: VBoxContainer = VBoxContainer.new()
	var first_child: Button = Button.new()
	var second_child: Label = Label.new()
	var hidden_child: Button = Button.new()
	hidden_child.visible = false
	container.add_child(first_child)
	container.add_child(second_child)
	container.add_child(hidden_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()

	assert_true(motion_utility.play_children_reveal(container) == 2, "列表刷新动效应只作用于可见子控件。")
	assert_lt(first_child.modulate.a, 1.0, "可见子控件应从淡入状态开始。")
	assert_lt(second_child.modulate.a, 1.0, "第二个可见子控件也应从淡入状态开始。")
	assert_true(hidden_child.modulate.a == 1.0, "隐藏子控件不应被动效修改。")


func test_ui_motion_utility_does_not_move_container_managed_children() -> void:
	var container: VBoxContainer = VBoxContainer.new()
	var first_child: Label = Label.new()
	var second_child: Label = Label.new()
	first_child.text = "A"
	second_child.text = "B"
	container.add_child(first_child)
	container.add_child(second_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var first_position: Vector2 = first_child.position
	var second_position: Vector2 = second_child.position
	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()

	assert_true(motion_utility.play_children_reveal(container, Vector2(20.0, 0.0)) == 2, "容器子控件仍应播放淡入动效。")
	assert_true(first_child.position == first_position, "VBoxContainer 子控件不应被动效改写位置。")
	assert_true(second_child.position == second_position, "第二个 VBoxContainer 子控件也不应被动效改写位置。")
	assert_lt(first_child.modulate.a, 1.0, "容器子控件仍应从淡入状态开始。")


func test_game_over_menu_contains_result_summary_labels() -> void:
	var panel: Control = _instantiate_control(_GAME_OVER_SCENE)
	assert_true(is_instance_valid(panel), "游戏结束场景应能实例化为 Control。")
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var title_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(title_node is Label, "游戏结束菜单应包含标题 Label。")
	assert_true(summary_node is Label, "游戏结束菜单应包含结算摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(
			summary_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"结算摘要应允许自动换行，避免窄屏溢出。"
		)


func test_game_over_menu_summary_uses_safe_format_fallback() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.score.set_value(8192)
	status_model.move_count.set_value(42)
	status_model.highest_tile.set_value(2048)
	status_model.high_score.set_value(16384)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.init()

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_GAME_OVER_SCENE)
	assert_true(is_instance_valid(panel), "游戏结束场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(summary_node is Label, "游戏结束菜单应包含结算摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(summary_label.text.contains("8192"), "结算摘要应显示本局分数。")
		assert_true(summary_label.text.contains("42"), "结算摘要应显示本局步数。")
		assert_true(summary_label.text.contains("2048"), "结算摘要应显示本局最大方块。")
		assert_true(summary_label.text.contains("16384"), "结算摘要应显示历史最高分。")
	architecture.dispose()


func test_game_text_format_utility_uses_safe_fallbacks() -> void:
	var fallback: String = "%s | %s %d | %s %dx%d"
	var missing_key_text: String = GameTextFormatUtility.format_template(
		"MISSING_BOOKMARK_INFO_FORMAT",
		fallback,
		["2026-06-19", "分数", 128, "尺寸", 4, 4]
	)
	var malformed_text: String = GameTextFormatUtility.format_template(
		"%s | %s",
		fallback,
		["2026-06-19", "分数", 256, "尺寸", 5, 5]
	)
	var translated_text: String = GameTextFormatUtility.format_template(
		"%s / %s %d / %s %dx%d",
		fallback,
		["2026-06-19", "分数", 512, "尺寸", 6, 6]
	)
	var percent_text: String = GameTextFormatUtility.format_template(
		"目标达成率 %d%%",
		"目标达成率 %d%%",
		[73]
	)

	assert_true(missing_key_text.contains("128"), "缺失翻译 key 时 fallback 应保留分数。")
	assert_true(missing_key_text.contains("4x4"), "缺失翻译 key 时 fallback 应保留棋盘尺寸。")
	assert_true(malformed_text.contains("256"), "占位符数量不匹配时 fallback 应保留分数。")
	assert_true(malformed_text.contains("5x5"), "占位符数量不匹配时 fallback 应保留棋盘尺寸。")
	assert_true(translated_text.contains("512"), "合法翻译格式串应正常保留数值。")
	assert_true(translated_text.contains("6x6"), "合法翻译格式串应正常保留棋盘尺寸。")
	assert_true(percent_text.contains("73%"), "合法格式串中的 %% 应作为转义百分号处理。")


func test_target_reached_menu_contains_non_forced_choice_controls() -> void:
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var title_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	var message_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/MessageLabel")
	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	var continue_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/ContinueButton")
	var restart_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/RestartButton")
	var main_menu_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/MainMenuButton")

	assert_true(title_node is Label, "目标达成菜单应包含标题 Label。")
	assert_true(message_node is Label, "目标达成菜单应包含说明 Label。")
	assert_true(summary_node is Label, "目标达成菜单应包含本局目标摘要 Label。")
	assert_true(continue_node is Button, "目标达成菜单应提供继续挑战按钮。")
	assert_true(restart_node is Button, "目标达成菜单应提供重新开始按钮。")
	assert_true(main_menu_node is Button, "目标达成菜单应提供返回主界面按钮。")
	if message_node is Label:
		var message_label: Label = message_node
		assert_true(
			message_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"目标达成说明应允许自动换行，避免窄屏溢出。"
		)
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(
			summary_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"目标达成摘要应允许自动换行，避免窄屏溢出。"
		)


func test_target_reached_menu_summary_uses_status_model() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.set_target_state(2048, true)
	status_model.score.set_value(8192)
	status_model.move_count.set_value(23)
	status_model.highest_tile.set_value(4096)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.init()

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(summary_node is Label, "目标达成菜单应包含本局目标摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(summary_label.text.contains("2048"), "目标摘要应显示目标方块值。")
		assert_true(summary_label.text.contains("8192"), "目标摘要应显示当前分数。")
		assert_true(summary_label.text.contains("23"), "目标摘要应显示当前步数。")
		assert_true(summary_label.text.contains("4096"), "目标摘要应显示当前最大方块。")
	architecture.dispose()


func test_target_reached_menu_buttons_emit_flow_events() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.init()
	var emitted_events: Dictionary = {
		&"resume": 0,
		&"restart": 0,
		&"main_menu": 0,
	}
	architecture.register_simple_event(
		EventNames.RESUME_GAME_REQUESTED,
		GFEventListener.from_callable(func(_payload: Variant) -> void: emitted_events[&"resume"] = GFVariantData.to_int(emitted_events.get(&"resume", 0), 0) + 1, 1)
	)
	architecture.register_simple_event(
		EventNames.RESTART_GAME_REQUESTED,
		GFEventListener.from_callable(func(_payload: Variant) -> void: emitted_events[&"restart"] = GFVariantData.to_int(emitted_events.get(&"restart", 0), 0) + 1, 1)
	)
	architecture.register_simple_event(
		EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED,
		GFEventListener.from_callable(func(_payload: Variant) -> void: emitted_events[&"main_menu"] = GFVariantData.to_int(emitted_events.get(&"main_menu", 0), 0) + 1, 1)
	)

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame

	_press_button(panel, "CenterContainer/VBoxContainer/ContinueButton")
	_press_button(panel, "CenterContainer/VBoxContainer/RestartButton")
	_press_button(panel, "CenterContainer/VBoxContainer/MainMenuButton")

	assert_true(_get_event_count(emitted_events, &"resume") == 1, "继续挑战按钮应请求恢复游戏。")
	assert_true(_get_event_count(emitted_events, &"restart") == 1, "重新开始按钮应请求重启当前局。")
	assert_true(_get_event_count(emitted_events, &"main_menu") == 1, "返回主界面按钮应请求从游戏内返回主菜单。")
	architecture.dispose()


func test_board_feedback_utility_spawns_effect_nodes() -> void:
	var board_container: Node2D = Node2D.new()
	add_child_autoqfree(board_container)
	await get_tree().process_frame

	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	var created_count: int = feedback_utility.play_feedback(board_container, Vector2(64.0, 72.0), &"merge", "4")

	assert_gt(created_count, 1, "棋盘反馈应创建粒子和浮动文字。")
	assert_true(board_container.get_child_count() == 1, "反馈节点应挂到棋盘容器下。")

	var feedback_root: Node2D = _get_node2d_child(board_container, 0)
	assert_true(is_instance_valid(feedback_root), "反馈根节点应为 Node2D。")
	assert_true(feedback_root.position == Vector2(64.0, 72.0), "反馈根节点应使用传入局部坐标。")
	assert_true(feedback_root.get_child_count() == created_count, "反馈子节点数量应与返回值一致。")


func test_board_feedback_utility_plays_gf_shake_feedback() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var shake_utility: GFShakeUtility = GFShakeUtility.new()
	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	await architecture.register_utility(GFShakeUtility, shake_utility)
	await architecture.register_utility(GameBoardFeedbackUtility, feedback_utility)
	await architecture.init()

	var board_container: Node2D = Node2D.new()
	add_child_autoqfree(board_container)
	await get_tree().process_frame

	var _created_count: int = feedback_utility.play_feedback(board_container, Vector2(24.0, 36.0), &"merge", "8")

	assert_true(
		shake_utility.get_active_shake_count(&"board") == 1,
		"棋盘反馈应同时通过 GFShakeUtility 播放语义化 board channel 反馈。"
	)
	architecture.dispose()


func test_celebration_vfx_utility_spawns_fullscreen_confetti_overlay() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var celebration_vfx: GameCelebrationVfxUtility = GameCelebrationVfxUtility.new()
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameCelebrationVfxUtility, celebration_vfx)
	await architecture.init()
	assert_true(celebration_vfx.apply_theme(_HALFTONE_CELEBRATION_VFX_THEME), "庆祝 VFX 应接受完整主题资源。")
	var played: bool = celebration_vfx.play_target_reached_celebration()
	await get_tree().process_frame

	var layer_node: Node = get_tree().root.get_node_or_null("GameCelebrationVfxLayer")
	assert_true(played, "庆祝 VFX Utility 应能播放目标达成反馈。")
	assert_true(layer_node is CanvasLayer, "庆祝 VFX 应创建全局 CanvasLayer。")
	if layer_node is CanvasLayer:
		var layer: CanvasLayer = layer_node
		assert_true(layer.process_mode == Node.PROCESS_MODE_ALWAYS, "庆祝 VFX 在暂停目标达成面板下仍应播放。")
		assert_true(layer.get_child_count() == 1, "一次庆祝播放应创建一个全屏 ColorRect。")
		var rect_node: Node = layer.get_child(0)
		assert_true(rect_node is ColorRect, "庆祝 VFX 子节点应是 ColorRect。")
		if rect_node is ColorRect:
			var rect: ColorRect = rect_node
			assert_true(rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "庆祝 VFX 不应阻挡 UI 输入。")
			assert_true(rect.material is ShaderMaterial, "庆祝 VFX 应使用 shader 材质。")
			assert_true(rect.modulate.a < 1.0, "庆祝 VFX 默认透明度应克制。")
			if rect.material is ShaderMaterial:
				var material: ShaderMaterial = rect.material
				var primary_color_value: Variant = material.get_shader_parameter(&"col0")
				var primary_color: Color = Color.TRANSPARENT
				if primary_color_value is Color:
					primary_color = primary_color_value
				assert_true(
					is_equal_approx(GFVariantData.to_float(material.get_shader_parameter(&"speed")), 94.0),
					"目标达成事件应应用主题 preset 的速度参数。"
				)
				assert_true(
					primary_color == Color(0.61960787, 0.85882354, 0.8352941, 1.0),
					"庆祝纸屑色板应来自主题 GFShaderParameterProfile。"
				)

	architecture.dispose()
	await get_tree().process_frame


# --- 私有/辅助方法 ---

func _create_tile() -> Tile:
	var tile: Tile = _instantiate_tile(_TILE_SCENE)
	if not is_instance_valid(tile):
		assert_true(false, "Tile 场景应能实例化为 Tile。")
		return null
	add_child_autoqfree(tile)
	await get_tree().process_frame
	return tile


func _load_shader(path: String) -> Shader:
	var resource: Resource = load(path)
	if resource is Shader:
		var shader: Shader = resource
		return shader
	return null


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _assert_shader_float_default_in_range(
	shader_text: String,
	uniform_name: String,
	min_value: float,
	max_value: float
) -> void:
	var default_value: float = _get_shader_float_default(shader_text, uniform_name, -1.0)
	assert_true(
		default_value >= min_value and default_value <= max_value,
		"%s 默认值 %.3f 应保持在 %.3f 到 %.3f，避免背景变粗糙或刺眼。" % [
			uniform_name,
			default_value,
			min_value,
			max_value,
		]
	)


func _get_shader_float_default(shader_text: String, uniform_name: String, fallback: float) -> float:
	var prefix: String = "uniform float %s " % uniform_name
	var lines: PackedStringArray = shader_text.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if not line.begins_with(prefix):
			continue
		return _parse_shader_default_float(line, fallback)
	return fallback


func _parse_shader_default_float(line: String, fallback: float) -> float:
	var equals_index: int = line.find("=")
	if equals_index == -1:
		return fallback
	var semicolon_index: int = line.find(";", equals_index)
	if semicolon_index == -1:
		semicolon_index = line.length()
	var value_text: String = line.substr(equals_index + 1, semicolon_index - equals_index - 1).strip_edges()
	if not value_text.is_valid_float():
		return fallback
	return float(value_text)


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_stylebox_flat(control: Control, stylebox_name: StringName) -> StyleBoxFlat:
	var stylebox: StyleBox = control.get_theme_stylebox(stylebox_name)
	if stylebox is StyleBoxFlat:
		var flat_stylebox: StyleBoxFlat = stylebox
		return flat_stylebox
	return null


func _get_tile_level_style(theme: TileColorScheme, index: int) -> TileLevelStyle:
	if not is_instance_valid(theme):
		return null
	if index < 0 or index >= theme.styles.size():
		return null
	return theme.styles[index]


func _collect_tile_scheme_contrast_issues(
	scheme_name: String,
	scheme: TileColorScheme,
	issues: Array[String]
) -> void:
	if not is_instance_valid(scheme):
		_append_string(issues, "%s 主题资源应能加载。" % scheme_name)
		return

	for index: int in range(scheme.styles.size()):
		var style: TileLevelStyle = _get_tile_level_style(scheme, index)
		if not is_instance_valid(style):
			_append_string(issues, "%s[%d] 应配置 TileLevelStyle。" % [scheme_name, index])
			continue

		var contrast_ratio: float = _get_contrast_ratio(style.background_color, style.font_color)
		if contrast_ratio < _MIN_TILE_TEXT_CONTRAST:
			_append_string(
				issues,
				"%s[%d] 文字对比度 %.2f 低于 %.2f。" % [
					scheme_name,
					index,
					contrast_ratio,
					_MIN_TILE_TEXT_CONTRAST,
				]
			)


func _collect_palette_contrast_issue(
	label: String,
	foreground: Color,
	background: Color,
	issues: Array[String]
) -> void:
	var contrast_ratio: float = _get_contrast_ratio(background, foreground)
	if contrast_ratio < _MIN_UI_TEXT_CONTRAST:
		_append_string(
			issues,
			"%s 对比度 %.2f 低于 %.2f。" % [
				label,
				contrast_ratio,
				_MIN_UI_TEXT_CONTRAST,
			]
		)


func _get_contrast_ratio(left: Color, right: Color) -> float:
	var left_luminance: float = _get_relative_luminance(left)
	var right_luminance: float = _get_relative_luminance(right)
	var lighter: float = left_luminance
	var darker: float = right_luminance
	if right_luminance > left_luminance:
		lighter = right_luminance
		darker = left_luminance
	return (lighter + 0.05) / (darker + 0.05)


func _get_relative_luminance(color: Color) -> float:
	return (
		_get_linear_channel(color.r) * 0.2126
		+ _get_linear_channel(color.g) * 0.7152
		+ _get_linear_channel(color.b) * 0.0722
	)


func _get_linear_channel(value: float) -> float:
	if value <= 0.03928:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _get_node2d_child(parent: Node, index: int) -> Node2D:
	if not is_instance_valid(parent):
		return null
	if index < 0 or index >= parent.get_child_count():
		return null
	var child: Node = parent.get_child(index)
	if child is Node2D:
		var child_node2d: Node2D = child
		return child_node2d
	return null


func _instantiate_tile(scene: PackedScene) -> Tile:
	var instance: Node = scene.instantiate()
	if instance is Tile:
		var tile: Tile = instance
		return tile
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _instantiate_control(scene: PackedScene) -> Control:
	var instance: Node = scene.instantiate()
	if instance is Control:
		var control: Control = instance
		return control
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _get_color(source: Dictionary, key: StringName) -> Color:
	var value: Variant = source.get(key, source.get(String(key), Color.TRANSPARENT))
	return value if value is Color else Color.TRANSPARENT


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)


func _press_button(root: Control, path: NodePath) -> void:
	var node: Node = root.get_node_or_null(path)
	if node is Button:
		var button: Button = node
		button.pressed.emit()


func _get_event_count(events: Dictionary, key: StringName) -> int:
	return GFVariantData.to_int(events.get(key, 0), 0)
