## 验证第一轮视觉增强资源与 Tile 动画基础行为。
extends GutTest


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://features/gameplay/scenes/components/tile.tscn")
const _GAME_OVER_SCENE: PackedScene = preload("res://features/gameplay/scenes/ui/game_over_menu.tscn")
const _TARGET_REACHED_SCENE: PackedScene = preload("res://features/gameplay/scenes/ui/target_reached_menu.tscn")
const _BOOKMARK_ITEM_SCENE: PackedScene = preload("res://features/bookmarks/scenes/ui/bookmark_list_item.tscn")
const _REPLAY_ITEM_SCENE: PackedScene = preload("res://features/replays/scenes/ui/replay_list_item.tscn")
const _BOOKMARK_LIST_SCENE: PackedScene = preload("res://features/bookmarks/scenes/menus/bookmark_list.tscn")
const _REPLAY_LIST_SCENE: PackedScene = preload("res://features/replays/scenes/menus/replay_list.tscn")
const _BOOT_SCENE: PackedScene = preload("res://app/scenes/boot.tscn")
const _MODE_SELECTION_SCENE_PATH: String = "res://features/navigation/scenes/menus/mode_selection.tscn"
const _BACKGROUND_SHADER_PATH: String = "res://features/asset_library/resources/shaders/background/halftone_paper_background.gdshader"
const _SCENE_TRANSITION_SHADER_PATH: String = "res://features/asset_library/resources/shaders/transition/halftone_wipe_transition.gdshader"
const _BUTTON_FOCUS_RING_SHADER_PATH: String = "res://features/asset_library/resources/shaders/ui/button_focus_dash.gdshader"
const _STARTUP_PROGRESS_SHADER_PATH: String = "res://features/asset_library/resources/shaders/ui/startup_progress_bar.gdshader"
const _CELEBRATION_CONFETTI_SHADER_PATH: String = "res://features/asset_library/resources/vfx/celebration_confetti_canvas.gdshader"
const _VISUAL_STYLE_DOC_PATH: String = "res://docs/visual_style.md"
const _BOOT_SCRIPT_PATH: String = "res://app/scripts/boot.gd"
const _BOOT_RUNTIME_SCRIPT_PATH: String = "res://app/scripts/boot_runtime.gd"
const _BOOT_MARK_TEXTURE_PATH: String = "res://features/asset_library/resources/textures/branding/printworks_boot_mark.png"
const _BOOT_SPLASH_TEXTURE_PATH: String = "res://features/asset_library/resources/textures/branding/printworks_boot_splash.png"
const _UI_STYLE_UTILITY_PATH: String = "res://features/themes/scripts/utilities/game_ui_style_utility.gd"
const _HUD_SCRIPT_PATH: String = "res://features/gameplay/scripts/ui/hud.gd"
const _MAIN_MENU_BOARD_MOTIF_PATH: String = "res://features/navigation/scripts/ui/main_menu_board_motif.gd"
const _SCENE_PRELOAD_MAP: GFScenePreloadMap = preload("res://features/navigation/resources/scene_preload_map.tres")
const _GAMEPLAY_VISUAL_WARMUP_SCRIPT: GDScript = preload("res://features/gameplay/scripts/ui/gameplay_visual_warmup.gd")
const _GAME_PLAY_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_play_controller.gd"
const _SCENE_ROUTER_SCRIPT_PATH: String = "res://features/navigation/scripts/systems/scene_router_system.gd"
const _TEST_TOOL_UTILITY_PATH: String = "res://features/diagnostics/scripts/utilities/test_tool_utility.gd"
const _HALFTONE_UI_PALETTE: GameUiPalette = preload("res://features/themes/resources/themes/game/halftone_atlas_ui_palette.tres")
const _HALFTONE_CELEBRATION_VFX_THEME: GameCelebrationVfxTheme = preload("res://features/themes/resources/themes/game/vfx/halftone_atlas_celebration_theme.tres")
const _HALFTONE_BOARD_FEEDBACK_PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)
const _HALFTONE_TILE_VISUAL_THEME: TileVisualTheme = preload("res://features/themes/resources/themes/game/halftone_atlas_tile_visual_theme.tres")
const _CLASSIC_TILE_THEME: TileColorScheme = preload("res://features/themes/resources/themes/tile_schemes/classic_tile_theme.tres")
const _FIBONACCI_TILE_THEME: TileColorScheme = preload("res://features/themes/resources/themes/tile_schemes/fibonacci_tile_theme.tres")
const _LUCAS_TILE_THEME: TileColorScheme = preload("res://features/themes/resources/themes/tile_schemes/lucas_tile_theme.tres")
const _RED_TILE_THEME: TileColorScheme = preload("res://features/themes/resources/themes/tile_schemes/red_tile_theme.tres")
const _BLUE_TILE_THEME: TileColorScheme = preload("res://features/themes/resources/themes/tile_schemes/blue_tile_theme.tres")
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
	assert_true(shader_text.contains("grid_scroll_speed"), "背景网格应有独立的低速滚动参数。")
	assert_true(shader_text.contains("moving_grid_pos"), "主网格和副网格应共享连续移动坐标。")
	assert_true(shader_text.contains("pixel_cloud_mask"), "背景 shader 应支持程序化像素云/墨流层。")
	assert_true(shader_text.contains("cloud_scroll_speed_1"), "背景墨流层应暴露第一层滚动速度。")
	assert_true(shader_text.contains("cloud_scroll_speed_2"), "背景墨流层应暴露第二层滚动速度。")
	assert_true(shader_text.contains("TIME"), "背景墨流层应使用时间驱动的轻量动效。")
	_assert_shader_float_default_in_range(shader_text, "grain_strength", 0.008, 0.020)
	_assert_shader_float_default_in_range(shader_text, "stipple_strength", 0.000, 0.006)
	_assert_shader_float_default_in_range(shader_text, "scanline_strength", 0.000, 0.008)
	_assert_shader_float_default_in_range(shader_text, "glow_strength", 0.000, 0.100)
	_assert_shader_float_default_in_range(shader_text, "pulse_speed", 0.000, 0.080)
	_assert_shader_float_default_in_range(shader_text, "line_thickness", 0.650, 1.250)
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
	assert_true(shader_text.contains("combined_alpha"), "场景转场应组合不透明纸面和边缘遮罩。")
	assert_true(shader_text.contains("shape_mask_pattern"), "场景转场应使用程序化形状遮罩推进，不依赖外部 shape texture。")
	assert_true(shader_text.contains("shaped_gradient"), "场景转场应由形状扰动擦除边缘，而不是单纯线性淡入。")
	assert_true(shader_text.contains("node_resolution"), "场景转场应按视口比例修正遮罩方向。")
	assert_true(shader_text.contains("reverse_progress"), "同一转场 shader 应支持由主题资源配置覆盖与揭示方向。")
	_assert_shader_float_default_in_range(shader_text, "width", 0.10, 0.18)
	_assert_shader_float_default_in_range(shader_text, "dot_tiling", 24.0, 48.0)
	_assert_shader_float_default_in_range(shader_text, "shape_tiling", 12.0, 28.0)
	_assert_shader_float_default_in_range(shader_text, "shape_feathering", 0.08, 0.20)
	_assert_shader_float_default_in_range(shader_text, "shape_threshold", 0.45, 0.62)
	_assert_shader_float_default_in_range(shader_text, "shape_influence", 0.08, 0.20)
	_assert_shader_float_default_in_range(shader_text, "grain_strength", 0.008, 0.020)
	_assert_shader_float_default_in_range(shader_text, "band_strength", 0.04, 0.16)
	_assert_shader_float_default_in_range(shader_text, "fill_opacity", 0.98, 1.0)
	_assert_shader_float_default_in_range(shader_text, "edge_opacity", 0.88, 1.0)
	_assert_shader_float_default_in_range(shader_text, "edge_strength", 0.60, 0.95)
	_assert_shader_float_default_in_range(shader_text, "registration_offset", 0.008, 0.030)


func test_scene_router_sequences_cover_load_and_inverse_reveal() -> void:
	var router_source: String = _read_text(_SCENE_ROUTER_SCRIPT_PATH)
	var cover_index: int = router_source.find("var cover_error: Error = _play_scene_transition_cover()")
	var load_index: int = router_source.find("_scene_utility.load_scene_with_transition(config)")
	var reveal_index: int = router_source.find("var reveal_error: Error = _play_scene_transition_reveal()")

	assert_gte(cover_index, 0, "场景路由应先播放覆盖旧页面的阶段。")
	assert_gt(load_index, cover_index, "目标场景只能在旧页面完全覆盖后切换。")
	assert_gt(reveal_index, load_index, "目标场景完成后应播放反向揭示阶段。")
	assert_gte(
		router_source.count("await _await_screen_transition()"),
		2,
		"覆盖与揭示两个阶段都必须等待 GFScreenTransitionUtility 完成。"
	)


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
	if boot_node is Boot:
		var boot: Boot = boot_node
		var progress_fill_node: Node = boot.get_node_or_null("PulseClip/ProgressFill")
		var startup_pulse_node: Node = boot.get_node_or_null("PulseClip/ProgressFill/StartupPulse")
		assert_true(progress_fill_node is ColorRect, "静态启动壳应直接承载进度填充。")
		assert_true(startup_pulse_node is ColorRect, "进度脉冲应裁切在真实填充区域内。")
		if progress_fill_node is ColorRect and startup_pulse_node is ColorRect:
			var progress_fill: ColorRect = progress_fill_node
			var startup_pulse: ColorRect = startup_pulse_node
			boot._progress_fill = progress_fill
			boot._startup_pulse = startup_pulse
			boot.set_runtime_progress(0.5)
			boot._update_progress_fill(0.1)
			boot._update_startup_pulse()
			assert_true(progress_fill.size.x == 235.0, "启动进度应按真实归一化值填充，而不是显示固定装饰块。")
			assert_true(progress_fill.clip_contents, "进度脉冲不得越过当前已完成进度。")
		boot_node.free()

	var boot_source: String = _read_text(_BOOT_SCRIPT_PATH)
	var runtime_source: String = _read_text(_BOOT_RUNTIME_SCRIPT_PATH)
	assert_true(boot_source.contains("load_threaded_request"), "首帧 Boot 应在线程中加载正式启动编排器。")
	assert_true(boot_source.contains(_BOOT_RUNTIME_SCRIPT_PATH), "首帧 Boot 应持有唯一启动编排器路径。")
	assert_false(boot_source.contains("GFAsyncProgress"), "首帧 Boot 不得静态引用 GF 依赖链。")
	assert_true(
		boot_source.contains("DisplayServer.get_name() == \"headless\""),
		"无头审计应跳过仅为可见首帧服务的线程轮询。"
	)
	assert_true(runtime_source.contains("GFAsyncProgress"), "启动编排器应使用 GFAsyncProgress 统一启动进度。")
	assert_true(runtime_source.contains("GFAsyncWaitUtility.wait_until"), "启动编排器应使用 GFAsyncWaitUtility 统一预加载条件与超时。")
	assert_true(runtime_source.contains("GFAsyncWaitUtility.delay_seconds"), "启动画面延迟应受 GF 生命周期保护。")
	assert_true(runtime_source.contains("preload_scene(startup_scene_path, true)"), "启动编排器应通过 GFSceneUtility 预热实际入口场景。")
	assert_true(runtime_source.contains("_get_scene_router_system"), "启动编排器应把最终场景切换交给 SceneRouterSystem。")
	assert_false(runtime_source.contains("change_scene_to_file"), "GF 初始化后不应保留绕过 SceneRouterSystem 的场景切换旁路。")
	assert_true(boot_source.contains("set_runtime_progress"), "正式编排器应只更新同一个静态启动壳。")
	assert_true(boot_source.contains("ProgressFill"), "首帧壳应直接驱动进度条，不等待 GF 资源。")
	assert_false(runtime_source.contains("_setup_startup_screen"), "启动运行时不得再创建第二套加载页面。")
	assert_false(runtime_source.contains("StartupPanel"), "启动运行时不得用动态面板替换原生启动构图。")
	assert_false(runtime_source.contains("_PROGRESS_SHADER"), "首帧进度不得依赖二次加载 shader 后才出现。")
	assert_true(runtime_source.contains("configure_scene_preload_map"), "启动编排器应使用 GFScenePreloadMap 描述稳定场景流。")
	assert_true(runtime_source.contains("preload_scene_map_for"), "启动编排器应通过 GFSceneUtility 预热入口场景的相邻页面。")
	assert_true(runtime_source.contains("_prime_gameplay_visuals"), "启动编排器应在 GF 初始化后、静态遮罩下预绘制首轮反馈管线。")
	assert_true(
		runtime_source.contains("DisplayServer.get_name() != \"headless\""),
		"无头审计不得等待永远不会到达的 frame_post_draw。"
	)
	assert_true(
		str(ProjectSettings.get_setting("application/boot_splash/image", ""))
		== _BOOT_SPLASH_TEXTURE_PATH,
		"Godot 原生启动阶段应直接显示与项目加载页同构的完整首帧。"
	)
	assert_true(ResourceLoader.exists(_BOOT_MARK_TEXTURE_PATH), "项目加载页使用的微型棋盘标记必须存在。")
	assert_true(ResourceLoader.exists(_BOOT_SPLASH_TEXTURE_PATH), "原生完整启动首帧必须存在。")
	var stretch_mode_value: Variant = ProjectSettings.get_setting(
		"application/boot_splash/stretch_mode",
		-1
	)
	assert_true(stretch_mode_value is int, "Godot 4.7 原生启动图拉伸模式应保持 int 类型。")
	if stretch_mode_value is int:
		var stretch_mode: int = stretch_mode_value
		assert_true(
			stretch_mode == RenderingServer.SPLASH_STRETCH_MODE_COVER,
			"完整启动首帧应覆盖项目视口，同时保持原始宽高比。"
		)
	var minimum_display_time_value: Variant = ProjectSettings.get_setting(
		"application/boot_splash/minimum_display_time",
		-1
	)
	assert_true(minimum_display_time_value is int, "原生启动图最短显示时间应使用整数毫秒。")
	if minimum_display_time_value is int:
		var minimum_display_time: int = minimum_display_time_value
		assert_true(minimum_display_time == 0, "原生启动图不应额外占用固定等待时间。")


func test_main_menu_board_motif_uses_neutral_palette_without_dense_patterns() -> void:
	var motif_source: String = _read_text(_MAIN_MENU_BOARD_MOTIF_PATH)

	assert_false(motif_source.contains("_PINK_COLOR"), "主菜单棋盘不应继续使用品红错版底板。")
	assert_false(motif_source.contains("_CYAN_COLOR"), "主菜单棋盘不应继续使用高饱和青色底板。")
	assert_false(motif_source.contains("_draw_tile_pattern"), "经典数字方块不应叠加无语义的密集点阵或斜纹。")
	assert_true(motif_source.contains("_draw_tile_surface"), "主菜单方块应通过统一表面绘制保留克制的层次。")


func test_navigation_scene_preload_map_is_valid_and_primes_gameplay_route() -> void:
	var report: Dictionary = _SCENE_PRELOAD_MAP.validate_map({"check_exists": true})
	assert_true(GFVariantData.get_option_int(report, &"error_count") == 0, "场景预载图不应包含阻断错误。")
	assert_true(GFVariantData.get_option_int(report, &"warning_count") == 0, "场景预载图不应包含缺失或重复路径。")

	var plan: Dictionary = _SCENE_PRELOAD_MAP.get_preload_plan(
		"res://features/navigation/scenes/menus/mode_selection.tscn",
		1,
		true
	)
	var planned_paths_value: Variant = plan.get(&"paths", PackedStringArray())
	assert_true(planned_paths_value is PackedStringArray, "GFScenePreloadMap 计划应返回 PackedStringArray 路径。")
	var planned_paths: PackedStringArray = PackedStringArray()
	if planned_paths_value is PackedStringArray:
		planned_paths = planned_paths_value
	assert_has(
		planned_paths,
		"res://features/gameplay/scenes/game/game_play.tscn",
		"进入模式选择时应提前准备正式游戏场景。"
	)
	assert_lte(_SCENE_PRELOAD_MAP.max_scheduled_scenes, 2, "启动预载图不得并发调度所有低频菜单。")


func test_hud_action_icons_resolve_through_asset_library_keys() -> void:
	var style_source: String = _read_text(_UI_STYLE_UTILITY_PATH)
	var hud_source: String = _read_text(_HUD_SCRIPT_PATH)
	assert_true(
		style_source.contains("set_button_icon_from_asset"),
		"UI 样式 Utility 应负责把稳定素材键解析为按钮图标。"
	)
	for asset_key: String in [
		"asset.texture.icon.pause",
		"asset.texture.icon.undo_2",
		"asset.texture.icon.redo_2",
		"asset.texture.icon.bookmark_plus",
	]:
		assert_true(hud_source.contains(asset_key), "HUD 应使用素材键而不是缺字风险较高的 Unicode 符号：%s" % asset_key)


func test_gameplay_visual_warmup_primes_tiles_and_feedback_without_runtime_assets() -> void:
	var warmup_value: Object = _GAMEPLAY_VISUAL_WARMUP_SCRIPT.new()
	assert_true(warmup_value is Node2D, "视觉预热脚本应实例化为 Node2D。")
	if not warmup_value is Node2D:
		return
	var warmup: Node2D = warmup_value
	add_child_autofree(warmup)
	warmup.call(&"prime")
	await get_tree().process_frame

	var primed_value: Variant = warmup.call(&"is_primed")
	assert_true(primed_value is bool, "视觉预热完成状态应返回 bool。")
	if primed_value is bool:
		var primed: bool = primed_value
		assert_true(primed, "游戏视觉预热节点应记录完成状态。")
	assert_gt(warmup.get_child_count(), 1, "视觉预热应覆盖方块轮廓和常驻反馈绘制。")


func test_celebration_confetti_shader_loads_and_keeps_print_defaults() -> void:
	var shader: Shader = _load_shader(_CELEBRATION_CONFETTI_SHADER_PATH)
	var shader_text: String = _read_text(_CELEBRATION_CONFETTI_SHADER_PATH)

	assert_true(is_instance_valid(shader), "庆祝纸屑 shader 应能正常加载。")
	assert_true(shader_text.contains("PARTICLE_COUNT = 88"), "庆祝纸屑数量应克制，避免廉价全屏彩纸噪音。")
	assert_true(shader_text.contains("palette_color"), "庆祝纸屑应使用主题化 CMYK 色板。")
	assert_true(shader_text.contains("rotate2d"), "庆祝纸屑应有轻量旋转，而不是静态贴片。")
	assert_true(shader_text.contains("drain_started_at"), "庆祝纸屑应支持停止循环后自然落出画面。")
	assert_true(shader_text.contains("cycle_visibility"), "纸屑退场不得直接隐藏半空中的当前周期。")
	_assert_shader_float_default_in_range(shader_text, "speed", 80.0, 130.0)
	_assert_shader_float_default_in_range(shader_text, "sway_strength", 24.0, 54.0)
	_assert_shader_float_default_in_range(shader_text, "spin_speed", 1.8, 3.4)
	_assert_shader_float_default_in_range(shader_text, "piece_size", 5.0, 9.0)


func test_list_items_do_not_leak_resource_debug_text_into_button_content() -> void:
	var replay_item_node: Node = _REPLAY_ITEM_SCENE.instantiate()
	assert_true(replay_item_node is ReplayListItem, "回放列表项场景应实例化为 ReplayListItem。")
	if replay_item_node is ReplayListItem:
		var replay_item: ReplayListItem = replay_item_node
		replay_item.text = "<Resource#123>"
		replay_item.set_repeater_item(null, 0)
		assert_true(replay_item.text.is_empty(), "GFRepeaterBinder 不应把 Resource 调试字符串写进回放按钮正文。")
		replay_item.free()

	var bookmark_item_node: Node = _BOOKMARK_ITEM_SCENE.instantiate()
	assert_true(bookmark_item_node is BookmarkListItem, "存档列表项场景应实例化为 BookmarkListItem。")
	if bookmark_item_node is BookmarkListItem:
		var bookmark_item: BookmarkListItem = bookmark_item_node
		bookmark_item.text = "<Resource#456>"
		bookmark_item.set_repeater_item(null, 0)
		assert_true(bookmark_item.text.is_empty(), "GFRepeaterBinder 不应把 Resource 调试字符串写进存档按钮正文。")
		bookmark_item.free()

	assert_no_new_orphans("列表项 binder 回归测试不得把 UI 节点留到 GUT 退出阶段。")


func test_record_list_previews_fit_inside_their_sidebar_surfaces() -> void:
	for packed_scene: PackedScene in [_BOOKMARK_LIST_SCENE, _REPLAY_LIST_SCENE]:
		var page: Node = packed_scene.instantiate()
		var preview_node: Node = page.find_child("BoardPreview", true, false)
		var preview_surface_node: Node = page.find_child("PreviewContainer", true, false)
		assert_true(preview_node is BoardPreview, "记录页应包含 BoardPreview。")
		assert_true(preview_surface_node is PanelContainer, "记录页应包含预览面板。")
		if preview_node is BoardPreview and preview_surface_node is PanelContainer:
			var preview: BoardPreview = preview_node
			var preview_surface: PanelContainer = preview_surface_node
			var has_preview_size: bool = false
			for property: Dictionary in preview.get_property_list():
				if GFVariantData.get_option_string_name(property, &"name") == &"preview_size":
					has_preview_size = true
					break
			assert_true(has_preview_size, "BoardPreview 应暴露可由承载页面约束的预览尺寸。")
			if has_preview_size:
				var preview_size: float = GFVariantData.to_float(preview.get(&"preview_size"), 0.0)
				assert_lte(
					preview_size + 12.0,
					preview_surface.custom_minimum_size.y,
					"预览棋盘必须完整留在侧栏面板内，并保留至少 6px 四周留白。"
				)
		page.free()

	assert_no_new_orphans("记录页预览布局测试不得残留 UI 节点。")


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


func test_non_menu_surfaces_apply_theme_and_motion_in_their_own_feature() -> void:
	var gameplay_source: String = _read_text(_GAME_PLAY_CONTROLLER_PATH)
	var diagnostics_source: String = _read_text(_TEST_TOOL_UTILITY_PATH)

	assert_true(
		gameplay_source.contains("apply_current_theme_to_tree(self)"),
		"游戏局内不是 GameUiController，必须主动把主题应用到 HUD。"
	)
	assert_true(
		gameplay_source.contains("bind_interactive_controls(self)"),
		"游戏局内必须主动绑定 HUD 和棋盘控件的交互动效。"
	)
	assert_true(
		diagnostics_source.contains("apply_current_theme_to_tree(_test_window)"),
		"独立诊断窗口必须由 diagnostics feature 自行应用当前主题。"
	)
	assert_true(
		diagnostics_source.contains("bind_interactive_controls(_test_window)"),
		"独立诊断窗口必须自行绑定交互动效。"
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
		"features/themes/resources/themes/tile_schemes",
		"GameUiStyleUtility",
		"GameUiMotionUtility",
	]:
		if not text.contains(term):
			_append_string(missing_terms, term)

	assert_true(
		missing_terms.is_empty(),
		"视觉规范文档应固定 CMYK 半调纸媒方向和关键落地点，缺少：\n%s" % _join_lines(missing_terms)
	)


func test_tile_setup_applies_sparse_theme_driven_identity_style() -> void:
	var tile: Tile = await _create_tile()
	var no_layers: Array[StringName] = []
	var classic_style: TileVisualFamilyStyle = _HALFTONE_TILE_VISUAL_THEME.get_family_style(
		&"tile.visual.classic_numeric"
	)

	tile.setup(
		2147483647,
		&"tile.classic.numeric",
		Color(0.8, 0.5, 0.2, 1.0),
		Color.WHITE,
		classic_style.family_id,
		no_layers,
		classic_style
	)

	assert_true(tile.background.get_fill_color() == Color(0.8, 0.5, 0.2, 1.0))
	assert_true(tile.background.get_silhouette_id() == &"soft_square")
	assert_gt(tile.background.get_shape_points().size(), 3, "方块应有可绘制的稳定轮廓。")

	var pattern_node: Node = tile.get_node_or_null("PatternOverlay")
	assert_true(pattern_node is Control, "Tile 应包含稀疏身份母题叠层。")
	if pattern_node is Control:
		var pattern_control: Control = pattern_node
		assert_true(pattern_control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "纹理叠层不应阻挡输入。")
		assert_true(pattern_control.clip_contents, "身份母题必须裁切在方块安全区内。")
		assert_lte(pattern_control.size.x, 84.0, "身份母题绘制层必须缩进到方块轮廓内。")
		assert_lte(pattern_control.size.y, 84.0, "身份母题绘制层必须缩进到方块轮廓内。")
	var font_size: int = tile.value_label.get_theme_font_size("font_size")
	assert_between(font_size, 12, 48, "方块字号应保持在明确的可读范围内。")
	assert_lt(font_size, 48, "大数值文本应触发字号收缩。")

	var fibonacci_style: TileVisualFamilyStyle = _HALFTONE_TILE_VISUAL_THEME.get_family_style(
		&"tile.visual.fibonacci_numeric"
	)
	tile.setup(
		3,
		&"tile.fibonacci.numeric",
		Color("#c0977a"),
		Color("#594a45"),
		fibonacci_style.family_id,
		no_layers,
		fibonacci_style
	)
	assert_ne(
		tile.background.get_silhouette_id(),
		classic_style.silhouette_id,
		"纹理之外还应有稳定的家族轮廓，避免低分辨率下全部看成同一种方块。"
	)
	var fibonacci_pattern: TilePatternOverlay.PatternType = tile._get_pattern_type()

	tile.setup(
		13,
		&"tile.fibonacci.numeric",
		Color("#944431"),
		Color.WHITE,
		fibonacci_style.family_id,
		no_layers,
		fibonacci_style
	)
	assert_true(tile.background.get_silhouette_id() == fibonacci_style.silhouette_id)
	assert_true(tile._get_pattern_type() == fibonacci_pattern)
	assert_true(fibonacci_style.shadow_offset == Vector2(1.5, 1.5), "方块只应保留统一短投影，不使用彩色错版偏移。")


func test_all_tile_visual_families_have_unique_base_signatures() -> void:
	var visual_family_ids: Array[StringName] = [
		&"tile.visual.classic_numeric",
		&"tile.visual.fibonacci_numeric",
		&"tile.visual.classic_fibonacci_hybrid",
		&"tile.visual.lucas_fibonacci_hybrid",
		&"tile.visual.ratio_base",
		&"tile.visual.ratio_factor",
	]
	var signatures: Dictionary = {}
	for visual_family_id: StringName in visual_family_ids:
		var style: TileVisualFamilyStyle = _HALFTONE_TILE_VISUAL_THEME.get_family_style(
			visual_family_id
		)
		assert_not_null(style, "%s 必须在主题中注册。" % visual_family_id)
		if style == null:
			continue
		var signature: String = "%s|%s|%s|%.2f,%.2f|%.1f" % [
			style.silhouette_id,
			style.motif_id,
			style.border_color.to_html(true),
			style.shape_scale.x,
			style.shape_scale.y,
			style.shape_rotation_degrees,
		]
		assert_false(
			signatures.has(signature),
			"%s 与 %s 的轮廓和纹理签名重复。" % [
				visual_family_id,
				signatures.get(signature, &""),
			]
		)
		signatures[signature] = visual_family_id
	assert_true(signatures.size() == visual_family_ids.size())


func test_game_board_controller_uses_configured_tile_scheme_colors() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var grid_model: GridModel = GridModel.new()
	grid_model.interaction_rule = ClassicInteractionRule.new()
	controller.model = grid_model
	controller.color_schemes = {
		0: _CLASSIC_TILE_THEME,
	}

	var value_2_colors: Dictionary = controller._get_tile_colors(2, &"tile.classic.numeric")
	var value_4_colors: Dictionary = controller._get_tile_colors(4, &"tile.classic.numeric")
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
	var style: TileVisualFamilyStyle = _HALFTONE_TILE_VISUAL_THEME.get_family_style(
		&"tile.visual.classic_numeric"
	)
	var no_layers: Array[StringName] = []
	tile.setup(
		2,
		&"tile.classic.numeric",
		Color(0.9, 0.75, 0.45, 1.0),
		Color.BLACK,
		style.family_id,
		no_layers,
		style
	)

	var spawn_tween: Tween = tile.animate_spawn()
	assert_true(is_instance_valid(spawn_tween) and spawn_tween.is_valid(), "生成动画应返回有效 Tween。")

	tile.reset_animation_state()
	var move_tween: Tween = tile.animate_move(Vector2(48.0, 32.0))
	assert_true(is_instance_valid(move_tween) and move_tween.is_valid(), "移动动画应返回有效 Tween。")

	tile.reset_animation_state()
	var merge_tween: Tween = tile.animate_merge()
	assert_true(is_instance_valid(merge_tween) and merge_tween.is_valid(), "合并动画应返回有效 Tween。")

	tile.reset_animation_state()
	var delayed_merge_tween: Tween = tile.animate_merge(
		tile.set_meta.bind(&"_test_merge_impact", true),
		Tile.get_move_animation_duration()
	)
	assert_false(
		GFVariantData.to_bool(tile.get_meta(&"_test_merge_impact", false)),
		"移动尚未结束时不得提前触发合并冲击。"
	)
	var _partial_step_active: bool = delayed_merge_tween.custom_step(
		Tile.get_move_animation_duration() * 0.5
	)
	assert_false(
		GFVariantData.to_bool(tile.get_meta(&"_test_merge_impact", false)),
		"合并冲击回调必须等待移动动画完成。"
	)
	var _impact_step_active: bool = delayed_merge_tween.custom_step(
		Tile.get_move_animation_duration() * 0.6
	)
	assert_true(
		GFVariantData.to_bool(tile.get_meta(&"_test_merge_impact", false)),
		"移动完成后应立即触发合并冲击。"
	)

	tile.reset_animation_state()
	var transform_tween: Tween = tile.animate_transform()
	assert_true(is_instance_valid(transform_tween) and transform_tween.is_valid(), "转化动画应返回有效 Tween。")

	tile.reset_animation_state()


func test_ui_motion_utility_binds_buttons_recursively_once() -> void:
	var root: Control = Control.new()
	var container: VBoxContainer = VBoxContainer.new()
	var button: Button = Button.new()
	var item_list: ItemList = ItemList.new()
	root.add_child(container)
	container.add_child(button)
	container.add_child(item_list)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var style_utility: GameUiStyleUtility = GameUiStyleUtility.new()
	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	await _register_asset_library_stack(architecture)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiStyleUtility, style_utility)
	await architecture.register_utility(GameUiMotionUtility, motion_utility)
	await architecture.init()
	style_utility.apply_palette(_HALFTONE_UI_PALETTE)
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
	var selected_style: StyleBoxFlat = _get_stylebox_flat(item_list, &"selected")
	assert_not_null(selected_style, "列表绑定后应获得主题化选中态。")
	if selected_style != null:
		assert_true(
			selected_style.bg_color == _HALFTONE_UI_PALETTE.selected_surface_color,
			"列表选中背景应跟随当前 UI 色板。"
		)
		assert_true(
			selected_style.border_color == _HALFTONE_UI_PALETTE.selected_border_color,
			"列表选中边框应跟随当前 UI 色板。"
		)

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


func test_ui_motion_utility_animates_numeric_change_with_delta_label() -> void:
	var root: Control = Control.new()
	var value_label: Label = Label.new()
	var delta_label: Label = Label.new()
	root.add_child(value_label)
	value_label.add_child(delta_label)
	add_child(root)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	var tween: Tween = motion_utility.play_numeric_change(value_label, 16, 48, delta_label)

	assert_true(is_instance_valid(tween) and tween.is_valid(), "整数变化反馈应返回有效 Tween。")
	assert_true(value_label.text == "16", "计数反馈应从旧值开始。")
	assert_true(delta_label.visible and delta_label.text == "+32", "正向变化应显示可读的增量飘字。")
	var _finished_step_active: bool = tween.custom_step(1.0)
	assert_true(value_label.text == "48", "计数反馈结束后必须落在模型最终值。")
	assert_false(delta_label.visible, "增量飘字完成后应恢复隐藏状态。")
	tween.kill()
	root.free()


func test_ui_style_utility_styles_spinbox_as_readable_light_field() -> void:
	var root: Control = Control.new()
	var spin_box: SpinBox = SpinBox.new()
	root.add_child(spin_box)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var style_utility: GameUiStyleUtility = GameUiStyleUtility.new()
	await _register_asset_library_stack(architecture)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiStyleUtility, style_utility)
	await architecture.init()
	var _applied_count: int = style_utility.apply_palette_to_tree(root, _HALFTONE_UI_PALETTE)

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
	architecture.dispose()


func test_ui_style_utility_rebuilds_semantic_styles_after_palette_change() -> void:
	var root: Control = Control.new()
	var label: Label = Label.new()
	var panel: Panel = Panel.new()
	root.add_child(label)
	root.add_child(panel)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var style_utility: GameUiStyleUtility = GameUiStyleUtility.new()
	await _register_asset_library_stack(architecture)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiStyleUtility, style_utility)
	await architecture.init()

	style_utility.apply_palette(_HALFTONE_UI_PALETTE)
	style_utility.style_label(label, GameUiStyleUtility.TextRole.SECONDARY)
	style_utility.style_panel(
		panel,
		GameUiStyleUtility.SurfaceRole.SELECTED,
		GameUiStyleUtility.BorderRole.FOCUS,
		3
	)

	var duplicate_resource: Resource = _HALFTONE_UI_PALETTE.duplicate(true)
	assert_true(duplicate_resource is GameUiPalette, "测试色板必须可深复制。")
	if duplicate_resource is GameUiPalette:
		var alternate_palette: GameUiPalette = duplicate_resource
		alternate_palette.text_secondary_color = Color(0.24, 0.31, 0.38, 1.0)
		alternate_palette.selected_surface_color = Color(0.78, 0.52, 0.63, 1.0)
		alternate_palette.field_focus_border_color = Color(0.12, 0.67, 0.61, 1.0)
		var _refresh_count: int = style_utility.apply_palette_to_tree(root, alternate_palette)

		assert_true(
			label.get_theme_color("font_color") == alternate_palette.text_secondary_color,
			"语义文本应在色板切换后保持 SECONDARY 角色。"
		)
		var panel_style: StyleBoxFlat = _get_stylebox_flat(panel, &"panel")
		assert_not_null(panel_style, "语义面板应在色板切换后重建 StyleBox。")
		if panel_style != null:
			assert_true(
				panel_style.border_color == alternate_palette.field_focus_border_color,
				"语义面板应在色板切换后保持 FOCUS 边框角色。"
			)
			assert_true(
				panel_style.bg_color == alternate_palette.selected_surface_color.lightened(0.035),
				"语义面板应在色板切换后保持 SELECTED 表面角色。"
			)
	architecture.dispose()


func test_ui_style_utility_styles_option_button_popup_as_light_surface() -> void:
	var option: OptionButton = OptionButton.new()
	option.add_item("关闭")
	option.add_item("开启")
	add_child(option)
	await get_tree().process_frame

	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var style_utility: GameUiStyleUtility = GameUiStyleUtility.new()
	await _register_asset_library_stack(architecture)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiStyleUtility, style_utility)
	await architecture.init()
	style_utility.apply_palette(_HALFTONE_UI_PALETTE)
	style_utility.prepare_button(option)

	var popup: PopupMenu = option.get_popup()
	popup.about_to_popup.emit()
	var popup_panel: StyleBoxFlat = null
	var popup_stylebox: StyleBox = popup.get_theme_stylebox(&"panel")
	if popup_stylebox is StyleBoxFlat:
		popup_panel = popup_stylebox
	assert_not_null(popup_panel, "OptionButton 的 PopupMenu 应获得统一浅色面板样式。")
	if popup_panel != null:
		assert_gt(
			popup_panel.bg_color.get_luminance(),
			0.70,
			"浅色纸面主题不应弹出 Godot 默认深色菜单。"
		)
		assert_true(
			_get_contrast_ratio(popup.get_theme_color("font_color"), popup_panel.bg_color)
			>= _MIN_UI_TEXT_CONTRAST,
			"下拉项文字必须在弹层表面保持可读。"
		)
	assert_true(popup.transparent_bg, "嵌入式 PopupMenu 应让项目面板样式完整接管背景。")
	assert_false(popup.prefer_native_menu, "主题化下拉菜单不得回退到不可控的原生菜单。")
	architecture.dispose()
	option.free()
	await get_tree().process_frame


func test_mode_selection_seed_action_uses_packaged_icon_instead_of_emoji() -> void:
	var scene_resource: Resource = ResourceLoader.load(
		_MODE_SELECTION_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	assert_true(scene_resource is PackedScene, "模式选择场景资源应能以无缓存模式加载。")
	if not scene_resource is PackedScene:
		return
	var mode_scene: PackedScene = scene_resource
	var scene_root: Control = _instantiate_control(mode_scene)
	assert_not_null(scene_root, "模式选择场景应能实例化。")
	if scene_root == null:
		return
	var seed_button_node: Node = scene_root.get_node_or_null(
		"MarginContainer/ColumnsContainer/RightColumn/SeedContainer/RefreshSeedButton"
	)
	assert_true(seed_button_node is Button, "模式配置应保留独立的随机种子按钮。")
	if seed_button_node is Button:
		var seed_button: Button = seed_button_node
		assert_true(seed_button.text.is_empty(), "随机种子按钮不应依赖平台 emoji 字形。")
	var mode_source: String = _read_text(
		"res://features/navigation/scripts/menus/mode_selection.gd"
	)
	assert_true(
		mode_source.contains("asset.texture.icon.randomize"),
		"随机种子按钮应通过素材键使用项目内可审计图标。"
	)
	scene_root.free()
	await get_tree().process_frame


func test_ui_motion_utility_reveals_panel_with_tween() -> void:
	var panel: Control = Control.new()
	panel.position = Vector2(12.0, 20.0)
	panel.size = Vector2(120.0, 40.0)
	panel.scale = Vector2(1.2, 0.8)
	panel.modulate = Color(0.9, 0.8, 0.7, 1.0)
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var base_scale: Vector2 = panel.scale
	var base_modulate: Color = panel.modulate
	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	var tween: Tween = motion_utility.play_panel_intro(panel)

	assert_true(is_instance_valid(tween) and tween.is_valid(), "面板入场应返回有效 Tween。")
	assert_gt(panel.position.y, 20.0, "面板入场起点应带有轻微下移。")
	assert_lt(panel.modulate.a, 1.0, "面板入场起点应先淡入。")
	var feedback_color: Color = Color(0.95, 0.75, 0.3, 1.0)
	var first_pulse: Tween = motion_utility.play_control_pulse(panel, 1.1, feedback_color, 0.2)

	assert_false(tween.is_valid(), "强调反馈应先打断同一控件的入场 Tween。")
	assert_true(is_instance_valid(first_pulse) and first_pulse.is_valid(), "强调反馈应返回有效 Tween。")
	assert_true(panel.scale.is_equal_approx(base_scale * 1.1), "强调反馈应从基础缩放的倍率开始。")
	assert_true(panel.modulate.is_equal_approx(feedback_color), "强调反馈应从调用方指定颜色开始。")

	var second_pulse: Tween = motion_utility.play_control_pulse(panel, 1.05, feedback_color, 0.2)
	assert_false(first_pulse.is_valid(), "重复反馈应打断旧 Tween，避免动效叠加。")
	assert_true(is_instance_valid(second_pulse) and second_pulse.is_valid(), "重复反馈应创建新的有效 Tween。")
	assert_true(panel.scale.is_equal_approx(base_scale * 1.05), "重复反馈不得把瞬时缩放累计为新基础状态。")
	second_pulse.kill()
	panel.scale = base_scale
	panel.modulate = base_modulate


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
	panel.free()


func test_game_over_menu_summary_uses_safe_format_fallback() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var style_utility: GameUiStyleUtility = GameUiStyleUtility.new()
	status_model.score.set_value(8192)
	status_model.move_count.set_value(42)
	status_model.highest_tile.set_value(2048)
	status_model.high_score.set_value(16384)
	await _register_asset_library_stack(architecture)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameUiStyleUtility, style_utility)
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
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var ui_router: GFUIRouterUtility = GFUIRouterUtility.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(GFUIRouterUtility, ui_router)
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
	await get_tree().process_frame
	var popup_root: CanvasLayer = ui_utility.get_layer_root(GFUIUtility.Layer.POPUP)
	assert_true(is_instance_valid(popup_root), "GFUIUtility 应创建弹层根节点。")
	if is_instance_valid(popup_root):
		popup_root.reparent(context)

	var target_route: GFUIRoute = GFUIRoute.new()
	target_route.route_id = &"target_reached_menu"
	target_route.scene_path = _TARGET_REACHED_SCENE.resource_path
	target_route.layer = GFUIUtility.Layer.POPUP
	ui_router.configure([target_route], ui_utility)

	var button_paths: Array[NodePath] = [
		NodePath("CenterContainer/VBoxContainer/ContinueButton"),
		NodePath("CenterContainer/VBoxContainer/RestartButton"),
		NodePath("CenterContainer/VBoxContainer/MainMenuButton"),
	]
	for button_path: NodePath in button_paths:
		var panel_value: Node = ui_router.push_route(&"target_reached_menu")
		assert_true(panel_value is Control, "目标达成场景应通过 GF UI 路由打开为 Control。")
		if panel_value is Control:
			var panel: Control = panel_value
			await get_tree().process_frame
			_press_button(panel, button_path)
			assert_true(
				ui_router.get_current_route_id(GFUIUtility.Layer.POPUP) == &"",
				"目标达成按钮派发业务事件前应关闭自身 GF UI 路由。"
			)
		await get_tree().process_frame

	assert_true(_get_event_count(emitted_events, &"resume") == 1, "继续挑战按钮应请求恢复游戏。")
	assert_true(_get_event_count(emitted_events, &"restart") == 1, "重新开始按钮应请求重启当前局。")
	assert_true(_get_event_count(emitted_events, &"main_menu") == 1, "返回主界面按钮应请求从游戏内返回主菜单。")
	architecture.dispose()


func test_board_feedback_utility_reuses_persistent_canvas_without_child_growth() -> void:
	var feedback_canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	add_child_autoqfree(feedback_canvas)
	await get_tree().process_frame

	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	var initial_child_count: int = feedback_canvas.get_child_count()
	for index: int in range(12):
		var created_count: int = feedback_utility.play_feedback(
			feedback_canvas,
			Vector2(64.0 + float(index), 72.0),
			&"merge",
			"4"
		)
		assert_gt(created_count, 1, "棋盘反馈应包含碎片和多方向飘字。")

	assert_true(
		feedback_canvas.get_child_count() == initial_child_count,
		"高频操作反馈必须复用常驻绘制层，不能为每次操作追加 Control、StyleBox 和 Tween 节点。"
	)
	var directions: PackedVector2Array = feedback_canvas.get_score_particle_directions()
	var has_left: bool = false
	var has_right: bool = false
	var has_up: bool = false
	var has_down: bool = false
	for direction: Vector2 in directions:
		has_left = has_left or direction.x < -0.5
		has_right = has_right or direction.x > 0.5
		has_up = has_up or direction.y < -0.5
		has_down = has_down or direction.y > 0.5
	assert_true(
		has_left and has_right and has_up and has_down,
		"合并数字必须覆盖四面八方，不能只沿单一方向漂浮。"
	)


func test_board_feedback_utility_orchestrates_gf_shake_and_background_feedback() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var shake_utility: GFShakeUtility = GFShakeUtility.new()
	var haptic_utility: GFHapticUtility = GFHapticUtility.new()
	var shader_parameter_utility: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	await architecture.register_utility(GFShakeUtility, shake_utility)
	await architecture.register_utility(GFHapticUtility, haptic_utility)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameter_utility)
	await architecture.register_utility(GameBoardFeedbackUtility, feedback_utility)
	await architecture.init()
	assert_true(
		feedback_utility.apply_profile(_HALFTONE_BOARD_FEEDBACK_PROFILE),
		"棋盘反馈 Utility 应接受主题化 GF 反馈 Profile。"
	)

	var feedback_root: Node2D = Node2D.new()
	feedback_root.set_meta(&"feedback_base_position", Vector2(200.0, 200.0))
	feedback_root.position = Vector2(200.0, 200.0)
	add_child_autoqfree(feedback_root)
	var feedback_canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	feedback_root.add_child(feedback_canvas)
	var background: ColorRect = ColorRect.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _load_shader(_BACKGROUND_SHADER_PATH)
	background.material = material
	add_child_autoqfree(background)
	await get_tree().process_frame

	var tier: GameBoardFeedbackUtility.FeedbackTier = feedback_utility.classify_turn(2, 64, 128)
	var created_count: int = feedback_utility.play_turn_feedback(
		feedback_root,
		feedback_canvas,
		background,
		Vector2i.RIGHT,
		tier,
		Rect2(Vector2(-200.0, -200.0), Vector2(400.0, 400.0)),
		Color("#9ed2ce")
	)

	assert_true(tier == GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE)
	assert_true(created_count == 13, "高价值合并应提升边缘碎片数量。")
	assert_true(
		shake_utility.get_active_shake_count(&"board") == 1,
		"整批操作反馈应通过 GFShakeUtility 播放一次 board channel 反馈。"
	)
	assert_true(
		haptic_utility.get_active_haptic_count(&"board") == 1,
		"整批操作反馈应通过 GFHapticUtility 播放一次 board channel 反馈。"
	)
	var energy_value: Variant = material.get_shader_parameter("interaction_energy")
	assert_true(energy_value is float, "背景操作能量 uniform 应保持 float 类型。")
	if energy_value is float:
		var interaction_energy: float = energy_value
		assert_gt(
			interaction_energy,
			0.0,
			"背景应在操作当帧收到方向性能量。"
		)
	architecture.dispose()


func test_celebration_vfx_utility_spawns_fullscreen_confetti_overlay() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var clock_utility: GameClockUtility = GameClockUtility.new()
	var celebration_vfx: GameCelebrationVfxUtility = GameCelebrationVfxUtility.new()
	await _register_asset_library_stack(architecture)
	await architecture.register_utility(GameClockUtility, clock_utility)
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

	var persistent_played: bool = celebration_vfx.play_new_record_celebration()
	await get_tree().process_frame
	assert_true(persistent_played, "新纪录庆祝应能创建持续播放的纸屑层。")
	if layer_node is CanvasLayer:
		var layer: CanvasLayer = layer_node
		var persistent_rect_node: Node = layer.get_child(layer.get_child_count() - 1)
		assert_true(persistent_rect_node is ColorRect, "持续纸屑实例应是全屏 ColorRect。")
		if persistent_rect_node is ColorRect:
			var persistent_rect: ColorRect = persistent_rect_node
			celebration_vfx.drain_active_celebrations()
			await get_tree().process_frame
			assert_true(is_instance_valid(persistent_rect), "纸屑清退不能在玩家选择当帧直接消失。")
			assert_true(
				GFVariantData.to_bool(
					persistent_rect.get_meta(&"celebration_draining", false),
					false
				),
				"纸屑清退应进入停止新周期的 draining 状态。"
			)
			if persistent_rect.material is ShaderMaterial:
				var persistent_material: ShaderMaterial = persistent_rect.material
				assert_gte(
					GFVariantData.to_float(
						persistent_material.get_shader_parameter(&"drain_started_at"),
						-1.0
					),
					0.0,
					"清退必须把准确开始时间传给纸屑 shader。"
				)

	architecture.dispose()
	await get_tree().process_frame


# --- 私有/辅助方法 ---

func _register_asset_library_stack(architecture: GFArchitecture) -> void:
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var content_packages: GFContentPackageUtility = GFContentPackageUtility.new()
	var project_catalog: ProjectContentCatalogUtility = ProjectContentCatalogUtility.new()
	var _configured_project_catalog: ProjectContentCatalogUtility = project_catalog.configure_source_roots(PackedStringArray([
		GameAssetLibraryUtility.ASSET_LIBRARY_SOURCE_ROOT,
	]))
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFContentPackageUtility, content_packages)
	await architecture.register_utility(ProjectContentCatalogUtility, project_catalog)
	await architecture.register_utility(GameAssetLibraryUtility, asset_library)


func _create_tile() -> Tile:
	var tile: Tile = _instantiate_tile(_TILE_SCENE)
	if not is_instance_valid(tile):
		assert_true(false, "Tile 场景应能实例化为 Tile。")
		return null
	add_child_autofree(tile)
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
