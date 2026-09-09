## 验证内容包主题目录、事务激活、设置接入和主题资源解析。
extends GutTest


# --- 常量 ---

const _THEME_MANIFEST_PATH: String = "res://features/themes/resources/gf_content_package.json"
const _BACKGROUND_SHADER_PATH: String = "res://features/asset_library/resources/shaders/background/halftone_paper_background.gdshader"
const _DEFAULT_BOARD_THEME: BoardTheme = preload(
	"res://features/themes/resources/themes/mode_visuals/defaults/default_board_theme.tres"
)
const _CLASSIC_TILE_THEME: TileColorScheme = preload(
	"res://features/themes/resources/themes/mode_visuals/defaults/classic_tile_theme.tres"
)


# --- 私有变量 ---

var _asset_tick_architecture: GFArchitecture = null


# --- Godot 生命周期方法 ---

func _process(delta: float) -> void:
	if is_instance_valid(_asset_tick_architecture):
		_asset_tick_architecture.tick(delta)


# --- 测试用例 ---

func test_theme_catalog_discovers_and_validates_default_theme_pack() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: GameThemeCatalogUtility = _get_theme_catalog(setup)
	var report: GFValidationReport = catalog.validate_all_theme_resources()

	assert_true(report.is_ok(), "默认主题内容包及全部主题资源应通过 GFValidationReport。")
	assert_true(catalog.get_default_visual_theme_id() == &"halftone_atlas", "默认视觉主题应来自 manifest metadata。")
	assert_true(catalog.get_default_sound_theme_id() == &"printworks", "默认音效主题应来自 manifest metadata。")
	assert_true(catalog.get_visual_theme_descriptors().size() == 2, "印刷和素纸应通过两个轻量描述符按需加载。")
	assert_true(catalog.get_sound_theme_descriptors().size() == 1, "音效主题列表应由轻量描述符构成。")

	var theme: GameTheme = catalog.load_visual_theme(catalog.get_default_visual_theme_id())
	assert_true(is_instance_valid(theme), "默认视觉主题资源应存在。")
	assert_true(theme.theme_id == &"halftone_atlas", "默认视觉主题 ID 应稳定。")
	assert_true(is_instance_valid(theme.board_theme), "主题应引用棋盘主题资源。")
	assert_true(is_instance_valid(theme.ui_palette), "主题应引用 UI 色板资源。")
	assert_false(theme.ui_palette.body_font is SystemFont, "跨平台主题不得依赖 Web/小游戏不可控的系统字体。")
	assert_true(theme.ui_palette.body_font.has_char("中".unicode_at(0)), "正文主题字体必须随包提供中文字形。")
	assert_true(theme.ui_palette.numeric_font.has_char("2".unicode_at(0)), "数字主题字体必须随包提供基础数字字形。")
	assert_true(theme.ui_palette.body_font is FontVariation, "正文主题应使用可审计的打包字体变体。")
	assert_true(theme.ui_palette.display_font is FontVariation, "展示主题应使用可审计的打包字体变体。")
	var weight_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	if theme.ui_palette.body_font is FontVariation:
		var body_variation: FontVariation = theme.ui_palette.body_font
		assert_true(
			body_variation.variation_opentype.has(weight_tag),
			"正文可变字体必须使用 TextServer OpenType tag 配置字重。"
		)
	if theme.ui_palette.display_font is FontVariation:
		var display_variation: FontVariation = theme.ui_palette.display_font
		assert_true(
			display_variation.base_font.resource_path
			== "res://shared/assets/fonts/dm_serif_display_regular.ttf",
			"印刷展示数字必须使用随包 DM Serif 字体。"
		)
		assert_true(display_variation.fallbacks.size() == 1)
		if display_variation.fallbacks.size() == 1:
			var cjk_fallback: Font = display_variation.fallbacks[0]
			assert_true(cjk_fallback is FontVariation)
			if cjk_fallback is FontVariation:
				var cjk_variation: FontVariation = cjk_fallback
				assert_true(cjk_variation.variation_opentype.has(weight_tag))
				assert_true(cjk_variation.has_char("中".unicode_at(0)))
	assert_true(is_instance_valid(theme.ui_palette.button_focus_shader_profile), "UI 色板应引用按钮焦点 GF Profile。")
	assert_true(theme.ui_palette.button_focus_shader_profile.get_parameter_names().size() == 5, "按钮焦点 Profile 应声明 5 个静态样式参数。")
	assert_true(is_instance_valid(theme.background_shader_profile), "主题应引用 GF 背景 Shader 参数 Profile。")
	var background_parameter_names: PackedStringArray = (
		theme.background_shader_profile.get_parameter_names()
	)
	assert_true(
		background_parameter_names.has("grid_scroll_speed"),
		"背景 Profile 应显式声明移动网格速度。"
	)
	assert_true(
		background_parameter_names.size() == 33,
		"背景 Profile 应完整声明当前 shader 的 33 个主题、网格与操作反馈参数。"
	)
	assert_true(is_instance_valid(theme.board_feedback_profile), "主题应引用棋盘反馈 Profile。")
	assert_true(theme.board_feedback_profile.get_validation_report().is_ok(), "棋盘反馈 Profile 应完整声明 GF Shake 与 Haptic 预设。")
	assert_true(is_instance_valid(theme.celebration_vfx_theme), "主题应引用庆祝 VFX 主题资源。")
	assert_true(theme.celebration_vfx_theme.get_validation_report().is_ok(), "庆祝 VFX 主题应通过 GFValidationReport。")
	assert_true(
		theme.celebration_vfx_theme.shader_parameter_profile.get_parameter_names().size() == 10,
		"庆祝 VFX Profile 应声明 8 个主题色与 2 个单纸片印刷参数。"
	)
	assert_true(is_instance_valid(theme.scene_transition_cover_effect), "主题应声明覆盖旧场景的 GF 转场效果。")
	assert_true(is_instance_valid(theme.scene_transition_reveal_effect), "主题应声明揭示新场景的 GF 转场效果。")
	assert_true(theme.scene_transition_cover_effect.shader_material != null, "覆盖转场应由主题提供 ShaderMaterial。")
	assert_true(theme.scene_transition_reveal_effect.shader_material != null, "揭示转场应由主题提供 ShaderMaterial。")
	assert_false(
		GFVariantData.to_bool(theme.scene_transition_cover_effect.shader_material.get_shader_parameter(&"reverse_progress")),
		"覆盖转场应正向推进半调遮罩。"
	)
	assert_true(
		GFVariantData.to_bool(theme.scene_transition_reveal_effect.shader_material.get_shader_parameter(&"reverse_progress")),
		"揭示转场应反向推进半调遮罩。"
	)
	assert_true(theme.color_schemes.has(0), "主题应覆盖默认方块色阶槽位。")

	await _dispose_architecture(architecture)


func test_theme_manifest_uses_descriptors_instead_of_central_registry() -> void:
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(
		_THEME_MANIFEST_PATH
	)
	assert_true(manifest != null, "主题内容包 manifest 应能加载。")
	assert_false(manifest.get_resource_keys().has("game.theme_registry"), "主题包不得再登记中央直引用注册表。")

	var visual_defaults: int = 0
	var sound_defaults: int = 0
	for entry: Dictionary in manifest.get_normalized_resources():
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
		if not GFVariantData.get_option_bool(metadata, "is_default", false):
			continue
		var catalog_role: String = GFVariantData.get_option_string(metadata, "catalog_role")
		if catalog_role == GameThemeCatalogUtility.VISUAL_THEME_CATALOG_ROLE:
			visual_defaults += 1
		elif catalog_role == GameThemeCatalogUtility.SOUND_THEME_CATALOG_ROLE:
			sound_defaults += 1
		assert_true(
			GFVariantData.get_option_string(entry, "type_hint")
				== GameThemeCatalogUtility.RESOURCE_TYPE_HINT,
			"脚本资源必须使用导出稳定的内置 Resource 类型提示。"
		)
	assert_true(visual_defaults == 1, "manifest 必须声明且只声明一个默认视觉主题。")
	assert_true(sound_defaults == 1, "manifest 必须声明且只声明一个默认音效主题。")


func test_audio_theme_validation_requires_registered_semantic_events() -> void:
	var audio_theme: GameAudioTheme = GameAudioTheme.new()
	audio_theme.theme_id = &"empty_bank"
	audio_theme.audio_bank_id = &"empty_bank"
	audio_theme.audio_bank = GFAudioBank.new()

	var report: GFValidationReport = audio_theme.get_validation_report()
	var counts_by_kind: Dictionary = report.get_issue_counts_by_kind()

	assert_false(report.is_ok(), "缺少语义事件音频的主题必须校验失败。")
	assert_true(
		GFVariantData.get_option_int(counts_by_kind, &"unresolved_audio_event") == 11,
		"音效主题应逐项校验基础事件和层级语义事件。"
	)


func test_scene_router_delegates_theme_transitions_to_gf_utility() -> void:
	var setup: Dictionary = await _create_theme_architecture(true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var transition_utility: GFScreenTransitionUtility = _get_screen_transition_utility(setup)
	var router: SceneRouterSystem = _get_scene_router_system(setup)

	router.call("_play_scene_transition_cover")
	var cover_snapshot: Dictionary = transition_utility.get_debug_snapshot()
	var cover_effect: Dictionary = GFVariantData.get_option_dictionary(cover_snapshot, "active_effect")
	var cover_metadata: Dictionary = GFVariantData.get_option_dictionary(cover_effect, "metadata")

	assert_true(GFVariantData.get_option_bool(cover_snapshot, "transition_active"), "覆盖阶段应由 GFScreenTransitionUtility 推进。")
	assert_true(GFVariantData.get_option_bool(cover_effect, "has_shader_material"), "主题覆盖阶段应携带 ShaderMaterial。")
	assert_true(GFVariantData.get_option_int(cover_effect, "layer") == 1024, "主题资源应控制转场覆盖层级。")
	assert_true(GFVariantData.to_string_name(cover_metadata.get("phase")) == &"cover", "活动效果应保留覆盖阶段元数据。")
	assert_true(GFVariantData.to_string_name(cover_metadata.get("theme_id")) == &"halftone_atlas", "活动效果应记录当前主题。")

	assert_true(transition_utility.complete_transition(), "覆盖转场应能通过 GF 服务完成。")
	router.call("_play_scene_transition_reveal")
	var reveal_snapshot: Dictionary = transition_utility.get_debug_snapshot()
	var reveal_effect: Dictionary = GFVariantData.get_option_dictionary(reveal_snapshot, "active_effect")
	var reveal_metadata: Dictionary = GFVariantData.get_option_dictionary(reveal_effect, "metadata")

	assert_true(GFVariantData.get_option_bool(reveal_snapshot, "transition_active"), "揭示阶段应由同一个 GF 服务接管。")
	assert_true(GFVariantData.to_string_name(reveal_metadata.get("phase")) == &"reveal", "活动效果应保留揭示阶段元数据。")
	assert_true(transition_utility.complete_transition(), "揭示转场应能通过 GF 服务完成。")
	assert_false(
		GFVariantData.get_option_bool(transition_utility.get_debug_snapshot(), "overlay_visible"),
		"揭示完成后应通过 GF 完成回调隐藏覆盖层。"
	)

	await _dispose_architecture(architecture)


func test_scene_router_reduced_motion_uses_instant_shaderless_transition() -> void:
	var setup: Dictionary = await _create_theme_architecture(true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var settings: GFSettingsUtility = _get_settings(setup)
	var router: SceneRouterSystem = _get_scene_router_system(setup)
	settings.set_value(GameAccessibilityState.REDUCED_MOTION_SETTING_KEY, true)

	var effect_value: Variant = router.call("_resolve_scene_transition_effect", &"cover")
	assert_true(effect_value is GFScreenTransitionEffect, "减少动态仍需保留场景覆盖语义。")
	if effect_value is GFScreenTransitionEffect:
		var effect: GFScreenTransitionEffect = effect_value
		assert_true(effect.duration_seconds == 0.0, "减少动态的场景转场必须立即完成。")
		assert_null(effect.shader_material, "减少动态不得运行图案擦除 Shader。")
	var config_value: Variant = router.call(
		"_make_scene_transition_config",
		"res://features/navigation/scenes/menus/main_menu.tscn"
	)
	assert_true(config_value is GFSceneTransitionConfig)
	if config_value is GFSceneTransitionConfig:
		var config: GFSceneTransitionConfig = config_value
		assert_true(config.minimum_duration_seconds == 0.0, "减少动态不得人为延长加载等待。")
		assert_false(
			config.preload_before_change,
			"路由已显式 prime 场景，正式切换不得再次提交预加载请求。"
		)
		assert_false(config.preload_as_fixed_cache, "普通目标场景不得永久固定在预加载缓存。")

	settings.set_value(GameAccessibilityState.REDUCED_MOTION_SETTING_KEY, false)
	var normal_config_value: Variant = router.call(
		"_make_scene_transition_config",
		"res://features/navigation/scenes/menus/main_menu.tscn"
	)
	assert_true(normal_config_value is GFSceneTransitionConfig)
	if normal_config_value is GFSceneTransitionConfig:
		var normal_config: GFSceneTransitionConfig = normal_config_value
		assert_true(
			normal_config.minimum_duration_seconds == 0.0,
			"正常转场已有不透明 cover，不得再叠加固定加载等待。"
		)

	await _dispose_architecture(architecture)


func test_scene_router_can_prime_scene_through_gf_cache_before_cover_finishes() -> void:
	var setup: Dictionary = await _create_theme_architecture(true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var router: SceneRouterSystem = _get_scene_router_system(setup)
	var scene_utility_value: Variant = setup.get("scene_utility")
	assert_true(scene_utility_value is GFSceneUtility)
	if not scene_utility_value is GFSceneUtility:
		await _dispose_architecture(architecture)
		return
	var scene_utility: GFSceneUtility = scene_utility_value
	var target_path: String = (
		"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
	)

	var first_error: Error = router.prime_scene(target_path)
	var first_status: Dictionary = scene_utility.get_scene_resource_info(target_path)
	var second_error: Error = router.prime_scene(target_path)

	assert_true(first_error == OK, "场景路由应能通过 GFSceneUtility 发起预加载。")
	assert_true(second_error == OK, "重复预加载请求应复用同一个 GF 请求或缓存。")
	assert_true(
		GFVariantData.get_option_bool(first_status, "is_preloading")
		or GFVariantData.get_option_bool(first_status, "is_preloaded"),
		"预加载提示返回时，目标应已经进入 GF 的加载请求或缓存。"
	)
	scene_utility.cancel_scene_preload(target_path)
	await _dispose_architecture(architecture)


func test_scene_router_transition_wait_has_timeout_and_clears_overlay() -> void:
	var setup: Dictionary = await _create_theme_architecture(true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var transition_utility: GFScreenTransitionUtility = _get_screen_transition_utility(setup)
	var router: SceneRouterSystem = _get_scene_router_system(setup)
	router._transition_timeout_seconds = 0.02

	var cover_error: Error = router.call("_play_scene_transition_cover")
	assert_true(cover_error == OK)
	var completed: bool = await router.call("_await_screen_transition")

	assert_false(completed, "失去 tick 的屏幕转场应在项目时限内退出等待。")
	assert_false(transition_utility.is_transition_active(), "超时后必须取消仍在运行的转场。")
	assert_false(
		GFVariantData.get_option_bool(
			transition_utility.get_debug_snapshot(),
			"overlay_visible"
		),
		"超时降级路径必须解除覆盖层，避免界面永久被遮挡。"
	)
	await _dispose_architecture(architecture)


func test_theme_asset_session_wait_has_timeout() -> void:
	var theme_utility: GameThemeUtility = GameThemeUtility.new()
	theme_utility._asset_session_timeout_seconds = 0.02
	var never_started_session: GFAssetLoadSession = GFAssetLoadSession.new()
	var started_msec: int = Time.get_ticks_msec()

	var session_ready: bool = await theme_utility.call(
		"_wait_for_asset_session_ready",
		never_started_session
	)

	assert_false(session_ready, "没有进入终态的主题资源会话必须按时失败。")
	assert_lt(
		Time.get_ticks_msec() - started_msec,
		1000,
		"主题资源等待不得无限锁住设置或启动流程。"
	)


func test_game_settings_utility_registers_theme_settings_and_theme_utility_resolves_defaults() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var settings: GFSettingsUtility = _get_settings(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)

	assert_true(settings.has_setting(GameThemeUtility.VISUAL_THEME_SETTING_KEY), "项目设置 Utility 应注册视觉主题设置。")
	assert_true(settings.has_setting(GameThemeUtility.SOUND_THEME_SETTING_KEY), "项目设置 Utility 应注册音效主题设置。")
	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.VISUAL_THEME_SETTING_KEY), &"") == &"halftone_atlas",
		"视觉主题设置默认值应写入 GFSettingsUtility。"
	)
	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.SOUND_THEME_SETTING_KEY), &"") == &"printworks",
		"音效主题设置默认值应写入 GFSettingsUtility。"
	)
	assert_true(theme_utility.get_current_visual_theme().theme_id == &"halftone_atlas", "应能解析当前视觉主题。")
	assert_true(theme_utility.get_current_sound_theme().theme_id == &"printworks", "应能解析当前音效主题。")
	assert_true(theme_utility.get_current_visual_theme_id() == &"halftone_atlas", "应通过主题 Utility 查询当前视觉主题 ID。")
	assert_true(theme_utility.get_current_sound_theme_id() == &"printworks", "应通过主题 Utility 查询当前音效主题 ID。")
	assert_false(
		theme_utility.get_visual_theme_display_text(&"halftone_atlas").is_empty(),
		"视觉主题显示文本应由主题 Utility 提供。"
	)
	assert_false(
		theme_utility.get_sound_theme_display_text(&"printworks").is_empty(),
		"音效主题显示文本应由主题 Utility 提供。"
	)

	await _dispose_architecture(architecture)


func test_print_and_quiet_switch_as_complete_themes_and_commit_the_selected_id() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var themes: GameThemeUtility = _get_theme_utility(setup)
	var settings: GFSettingsUtility = _get_settings(setup)
	var print_theme: GameTheme = themes.get_current_visual_theme()
	_asset_tick_architecture = architecture

	assert_true(await themes.set_current_visual_theme_id(&"quiet_paper"))
	var quiet_theme: GameTheme = themes.get_current_visual_theme()
	assert_true(quiet_theme.theme_id == &"quiet_paper")
	assert_true(quiet_theme.ui_palette != print_theme.ui_palette)
	assert_true(quiet_theme.ui_motion_profile != print_theme.ui_motion_profile)
	assert_true(quiet_theme.board_theme != print_theme.board_theme)
	assert_true(quiet_theme.tile_visual_theme != print_theme.tile_visual_theme)
	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.VISUAL_THEME_SETTING_KEY))
		== &"quiet_paper",
		"成功切换的稳定主题 ID 必须提交给持久化设置 owner。"
	)
	assert_true(await themes.set_current_visual_theme_id(&"halftone_atlas"))
	assert_true(themes.get_current_visual_theme() == print_theme)
	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.VISUAL_THEME_SETTING_KEY))
		== &"halftone_atlas"
	)
	await _dispose_architecture(architecture)


func test_settings_picker_uses_catalog_and_observes_owned_theme_activation() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var themes: GameThemeUtility = _get_theme_utility(setup)
	var scene: PackedScene = load("res://features/settings/scenes/menus/settings_menu.tscn")
	var page: SettingsMenu = scene.instantiate()
	autofree(page)
	page._theme_utility = themes
	page._visual_theme_option = page.get_node("%VisualThemeOptionButton")
	page._visual_theme_status = page.get_node("%VisualThemeStatus")
	page._setup_visual_theme_options()
	assert_true(page._visual_theme_option.item_count == 2)
	var _started_connection: int = themes.visual_theme_activation_started.connect(
		page._on_visual_theme_activation_started
	)
	var _finished_connection: int = themes.visual_theme_activation_finished.connect(
		page._on_visual_theme_activation_finished
	)
	_asset_tick_architecture = architecture
	var quiet_index: int = page._get_option_index_for_string_name(
		page._visual_theme_option, &"quiet_paper"
	)
	page._on_visual_theme_selected(quiet_index)
	for _frame: int in range(240):
		if not page._theme_switch_pending:
			break
		await get_tree().process_frame
	assert_false(page._theme_switch_pending, "设置页必须消费主题切换的终态。")
	assert_false(page._visual_theme_option.disabled)
	assert_true(themes.get_current_visual_theme_id() == &"quiet_paper")
	assert_true(page._visual_theme_option.selected == quiet_index)
	await _dispose_architecture(architecture)


func test_theme_utility_tracks_cross_utility_signals_with_gf_signal_utility() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var signal_value: Variant = setup.get("signal_utility")
	var signal_utility: GFSignalUtility = null
	if signal_value is GFSignalUtility:
		signal_utility = signal_value

	assert_true(is_instance_valid(signal_utility), "主题测试架构应注册 GFSignalUtility。")
	if is_instance_valid(signal_utility):
		assert_true(
			signal_utility.get_connection_count() == 6,
			"素材目录、主题与无障碍 Utility 应由 GFSignalUtility 统一追踪跨 Utility 信号。"
		)

	await _dispose_architecture(architecture)
	if is_instance_valid(signal_utility):
		assert_true(signal_utility.get_connection_count() == 0, "架构释放后 GF 信号连接必须清空。")


func test_optional_shader_warmup_runs_once_on_enable_edge_and_releases_cache() -> void:
	var required_utilities: Array[Script] = GameThemeUtility.new().get_required_utilities()
	assert_true(
		required_utilities.has(GFRenderWarmupUtility),
		"GameThemeUtility 必须声明 GFRenderWarmupUtility 严格依赖。"
	)
	assert_true(
		required_utilities.has(GFOperationDiagnosticsUtility),
		"GameThemeUtility 必须声明 GFOperationDiagnosticsUtility 严格依赖。"
	)
	var initial_accessibility_state: GameAccessibilityState = GameAccessibilityState.new()
	initial_accessibility_state.shader_effects_enabled = false
	initial_accessibility_state.vfx_quality = GameAccessibilityState.VfxQuality.MINIMAL
	var setup: Dictionary = await _create_theme_architecture(
		false,
		true,
		initial_accessibility_state
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var accessibility_value: Variant = setup.get("accessibility")
	var accessibility: GameAccessibilityUtility = null
	if accessibility_value is GameAccessibilityUtility:
		accessibility = accessibility_value
	var render_warmup_value: Variant = setup.get("render_warmup")
	var render_warmup: GFRenderWarmupUtility = null
	if render_warmup_value is GFRenderWarmupUtility:
		render_warmup = render_warmup_value
	var diagnostics_value: Variant = setup.get("operation_diagnostics")
	var diagnostics: GFOperationDiagnosticsUtility = null
	if diagnostics_value is GFOperationDiagnosticsUtility:
		diagnostics = diagnostics_value
	var signal_utility_value: Variant = setup.get("signal_utility")
	var signal_utility: GFSignalUtility = null
	if signal_utility_value is GFSignalUtility:
		signal_utility = signal_utility_value
	var style_value: Variant = setup.get("style")
	var style: GameUiStyleUtility = null
	if style_value is GameUiStyleUtility:
		style = style_value

	assert_true(is_instance_valid(accessibility), "测试架构应提供 GameAccessibilityUtility。")
	assert_true(is_instance_valid(render_warmup), "测试架构应提供 GFRenderWarmupUtility。")
	assert_true(is_instance_valid(diagnostics), "测试架构应提供 GFOperationDiagnosticsUtility。")
	assert_true(is_instance_valid(signal_utility), "测试架构应提供 GFSignalUtility。")
	assert_true(is_instance_valid(style), "测试架构应提供 GameUiStyleUtility。")
	assert_true(style.is_static_visuals_enabled(), "初始 MINIMAL 档必须先应用静态视觉策略。")
	var completion_observation: Dictionary = {
		"count": 0,
		"style_was_static": false,
	}
	var _warmup_connected: Error = render_warmup.warmup_completed.connect(
		func(_queue_id: int, _completion_summary: Dictionary) -> void:
			completion_observation["count"] = (
				GFVariantData.get_option_int(completion_observation, "count", 0) + 1
			)
			completion_observation["style_was_static"] = (
				style.is_static_visuals_enabled()
			)
	) as Error
	var initial_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		theme_utility.get_debug_snapshot(),
		"optional_shader_warmup"
	)
	assert_true(
		GFVariantData.get_option_array(initial_snapshot, "warmed_roles").is_empty(),
		"初始 MINIMAL 档只记录禁用状态，不得预热可选 Shader。"
	)
	assert_true(
		render_warmup.get_cached_resource_count(
			GameThemeUtility.OPTIONAL_SHADER_WARMUP_CACHE_GROUP
		) == 0,
		"初始 MINIMAL 档不得为可选 Shader 增加 startup cache 成本。"
	)
	assert_true(
		diagnostics.get_operations(
			0,
			{&"operation_type": GameThemeUtility.OPTIONAL_SHADER_WARMUP_OPERATION_TYPE}
		).is_empty(),
		"初始化禁用状态不得伪造运行时启用边沿。"
	)

	accessibility.set_vfx_quality(GameAccessibilityState.VfxQuality.FULL)
	assert_true(
		diagnostics.get_operations(
			0,
			{&"operation_type": GameThemeUtility.OPTIONAL_SHADER_WARMUP_OPERATION_TYPE}
		).is_empty(),
		"Shader 总开关仍关闭时，提升 VFX 档位不得触发可选 Shader 预热。"
	)

	accessibility.set_shader_effects_enabled(true)
	assert_true(
		GFVariantData.get_option_int(completion_observation, "count", 0) == 1,
		"启用边沿必须同步完成一次 GF RID warmup。"
	)
	assert_true(
		GFVariantData.get_option_bool(completion_observation, "style_was_static", false),
		"warmup_completed 发出时仍应保持旧静态策略，避免先启用后冷加载。"
	)
	assert_false(style.is_static_visuals_enabled(), "RID warmup 完成后才应应用新的动态视觉策略。")
	var operations: Array[Dictionary] = diagnostics.get_operations(
		0,
		{&"operation_type": GameThemeUtility.OPTIONAL_SHADER_WARMUP_OPERATION_TYPE}
	)
	assert_true(operations.size() == 1, "一次禁用到启用边沿必须只产生一次同步预热操作。")
	assert_true(
		diagnostics.get_incidents(
			0,
			{&"code": &"game_theme_optional_shader_warmup_failed"}
		).is_empty(),
		"成功 RID warmup 不得产生失败 incident。"
	)
	if operations.size() == 1:
		assert_true(
			GFVariantData.get_option_bool(operations[0], "success"),
			"背景与庆祝 Shader RID 预热必须成功后再应用动态视觉策略。"
		)
		var operation_metadata: Dictionary = GFVariantData.get_option_dictionary(
			operations[0],
			"metadata"
		)
		var warmup_summary: Dictionary = GFVariantData.get_option_dictionary(
			operation_metadata,
			"summary"
		)
		var warmup_results: Array = GFVariantData.get_option_array(
			warmup_summary,
			"results"
		)
		assert_true(warmup_results.size() == 2, "同步预热摘要必须覆盖两个启用 role。")
		for result_value: Variant in warmup_results:
			var result: Dictionary = GFVariantData.as_dictionary(result_value)
			assert_true(
				GFVariantData.get_option_int(result, "touched_count", 0) == 1,
				"每个 Shader 条目必须通过 RID_ONLY 精确触碰一个 RID。"
			)
			assert_true(
				GFVariantData.get_option_bool(result, "cache_retained", false),
				"每个启用 role 都必须保留在项目 cache group。"
			)
	var warmup_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		theme_utility.get_debug_snapshot(),
		"optional_shader_warmup"
	)
	var warmed_roles: Array = GFVariantData.get_option_array(
		warmup_snapshot,
		"warmed_roles"
	)
	assert_true(warmed_roles.has(&"background"), "启用边沿必须预热 startup manifest 的 background role。")
	assert_true(warmed_roles.has(&"celebration"), "启用边沿必须预热 startup manifest 的 celebration role。")
	assert_true(
		render_warmup.get_cached_resource_count(
			GameThemeUtility.OPTIONAL_SHADER_WARMUP_CACHE_GROUP
		) == 2,
		"两项可选 Shader 必须由项目专属 cache group 持有。"
	)

	accessibility.state_changed.emit(accessibility.get_state())
	assert_true(
		GFVariantData.get_option_int(completion_observation, "count", 0) == 1,
		"重复通知不得再次调用 GFRenderWarmupUtility。"
	)
	assert_true(
		diagnostics.get_operations(
			0,
			{&"operation_type": GameThemeUtility.OPTIONAL_SHADER_WARMUP_OPERATION_TYPE}
		).size() == 1,
		"重复 state_changed 通知不得重复预热已成功缓存的 role。"
	)
	assert_true(
		render_warmup.get_cached_resource_count(
			GameThemeUtility.OPTIONAL_SHADER_WARMUP_CACHE_GROUP
		) == 2,
		"重复通知不得扩张可选 Shader cache。"
	)

	await _dispose_architecture(architecture)
	assert_true(
		render_warmup.get_cached_resource_count(
			GameThemeUtility.OPTIONAL_SHADER_WARMUP_CACHE_GROUP
		) == 0,
		"GameThemeUtility dispose 必须释放项目专属可选 Shader cache group。"
	)
	if is_instance_valid(signal_utility):
		assert_true(signal_utility.get_connection_count() == 0, "dispose 必须释放 owner-bound 无障碍信号。")


func test_theme_content_package_registers_selectable_theme_resources_only() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resource_resolver(setup)

	var resolve_report: Dictionary = resolver.resolve(
		&"game.theme.halftone_atlas",
		GameThemeCatalogUtility.RESOURCE_TYPE_HINT
	)
	var resource: Resource = resolver.load(
		&"game.theme.halftone_atlas",
		GameThemeCatalogUtility.RESOURCE_TYPE_HINT
	)
	var audio_bank_resource: Resource = resolver.load(&"game.audio_bank.printworks", "Resource")

	assert_true(
		GFVariantData.get_option_bool(resolve_report, "ok", false),
		"主题内容包应把独立主题资源键注册到 GFResourceResolverUtility。"
	)
	assert_true(resource is GameTheme, "视觉主题应能通过独立资源键加载。")
	assert_false(resolver.has_registered_key(&"game.theme_registry"), "Resolver 不应保留旧中央注册表资源键。")
	assert_false(
		resolver.has_registered_key(&"game.tile_scheme.blue"),
		"玩法默认色阶由 gameplay 模式配置直接拥有，不应作为可选择主题资源重复登记。"
	)
	assert_true(audio_bank_resource is GFAudioBank, "主题内容包应登记 printworks 音频银行。")

	await _dispose_architecture(architecture)


func test_theme_debug_snapshot_exposes_content_package_and_resolver_state() -> void:
	var setup: Dictionary = await _create_theme_architecture(false, false)
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var theme_catalog: GameThemeCatalogUtility = _get_theme_catalog(setup)
	var asset_utility: GFAssetUtility = _get_asset_utility(setup)

	var snapshot: Dictionary = theme_utility.get_debug_snapshot()
	var catalog_snapshot: Dictionary = GFVariantData.get_option_dictionary(snapshot, "catalog")
	var catalog_validation: Dictionary = GFVariantData.get_option_dictionary(
		catalog_snapshot,
		"catalog_validation"
	)
	var project_catalog_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		catalog_snapshot,
		"project_content_catalog"
	)
	var resolver_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		project_catalog_snapshot,
		"resolver"
	)
	var visual_slot_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		snapshot,
		"visual_theme_slot"
	)
	var sound_slot_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		snapshot,
		"sound_theme_slot"
	)
	var registered_keys: PackedStringArray = GFVariantData.get_option_packed_string_array(
		resolver_snapshot,
		"registered_keys"
	)

	assert_true(
		registered_keys.has("game.theme.halftone_atlas"),
		"主题诊断快照应包含独立视觉主题资源键。"
	)
	assert_true(
		GFVariantData.get_option_bool(catalog_validation, "ok"),
		"主题诊断快照应公开通过的描述符目录校验报告。"
	)
	assert_true(GFVariantData.get_option_int(snapshot, "active_audio_mount_token") > 0, "声音主题应暴露有效 GF 挂载令牌。")
	assert_true(
		GFVariantData.to_int(snapshot.get("available_visual_theme_count"), 0) > 0,
		"主题诊断快照应暴露可用视觉主题数量。"
	)
	var visual_group_id: StringName = GFVariantData.get_option_string_name(
		snapshot,
		"active_visual_asset_group_id"
	)
	var sound_group_id: StringName = GFVariantData.get_option_string_name(
		snapshot,
		"active_sound_asset_group_id"
	)
	assert_false(visual_group_id == &"", "视觉主题应持有已提交的 GF 资源组。")
	assert_false(sound_group_id == &"", "声音主题应持有独立的 GF 资源组。")
	assert_true(
		asset_utility.get_group_paths(visual_group_id).has(
			theme_catalog.get_visual_theme_resource_path(&"halftone_atlas")
		),
		"视觉主题资源组必须包含 manifest 解析出的主题根资源。"
	)
	assert_true(
		asset_utility.get_group_paths(sound_group_id).has(
			theme_catalog.get_sound_theme_resource_path(&"printworks")
		),
		"声音主题资源组必须包含 manifest 解析出的主题根资源。"
	)
	assert_true(
		asset_utility.get_active_preload_session_count() == 0,
		"主题激活完成后不得遗留 GFAssetLoadSession。"
	)
	assert_true(
		GFVariantData.get_option_bool(visual_slot_snapshot, "configured")
		and GFVariantData.get_option_bool(visual_slot_snapshot, "has_resource"),
		"当前视觉主题应由已配置的 GFAssetSlot 强持有。"
	)
	assert_true(
		GFVariantData.get_option_string_name(visual_slot_snapshot, "resource_key")
			== &"slot.theme.visual.current",
		"视觉主题槽位应保留稳定用途资源键，而不是绑定某个主题路径。"
	)
	assert_true(
		GFVariantData.get_option_bool(sound_slot_snapshot, "configured")
		and GFVariantData.get_option_bool(sound_slot_snapshot, "has_resource"),
		"当前声音主题应由独立的 GFAssetSlot 强持有。"
	)
	assert_true(
		GFVariantData.get_option_int(visual_slot_snapshot, "generation") >= 2
		and GFVariantData.get_option_int(sound_slot_snapshot, "generation") >= 2,
		"主题初次激活应推进 GFAssetSlot 的单调 generation。"
	)
	var visual_slot: GFAssetSlot = theme_utility._visual_theme_slot
	var sound_slot: GFAssetSlot = theme_utility._sound_theme_slot

	await _dispose_architecture(architecture)
	assert_true(visual_slot.is_released(), "主题 Utility dispose 后必须终态释放视觉资源槽位。")
	assert_true(sound_slot.is_released(), "主题 Utility dispose 后必须终态释放声音资源槽位。")


func test_theme_group_release_preserves_other_group_cache_ownership() -> void:
	var assets: GFAssetUtility = GFAssetUtility.new()
	assets.max_cache_size = 8
	assets.init()
	var theme_utility: GameThemeUtility = GameThemeUtility.new()
	theme_utility._assets = assets
	var shared_path: String = _DEFAULT_BOARD_THEME.resource_path
	assets.put_cache(shared_path, _DEFAULT_BOARD_THEME)
	assets.register_group_path(&"theme.previous", shared_path, true)
	assets.register_group_path(&"theme.shared.consumer", shared_path, true)

	theme_utility._release_asset_group(&"theme.previous")

	assert_true(
		assets.get_group_paths(&"theme.previous").is_empty(),
		"替换主题后必须释放旧主题组。"
	)
	assert_true(
		assets.get_group_paths(&"theme.shared.consumer").has(shared_path),
		"释放旧主题组不得删除其他资源组对共享路径的 ownership。"
	)
	assert_same(
		assets.get_cached(shared_path),
		_DEFAULT_BOARD_THEME,
		"共享资源仍有其他组持有时必须保留 GF 有界缓存。"
	)
	assert_true(assets.is_cache_pinned(shared_path))
	assets.unload_group(&"theme.shared.consumer", false)
	assets.dispose()


func test_game_theme_utility_resolves_board_and_tile_schemes() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var board_feedback_value: Variant = setup.get("board_feedback")
	var board_feedback: GameBoardFeedbackUtility = null
	if board_feedback_value is GameBoardFeedbackUtility:
		board_feedback = board_feedback_value
	var celebration_value: Variant = setup.get("celebration_vfx")
	var celebration_vfx: GameCelebrationVfxUtility = null
	if celebration_value is GameCelebrationVfxUtility:
		celebration_vfx = celebration_value
	var background_rect: ColorRect = ColorRect.new()
	var background_material: ShaderMaterial = ShaderMaterial.new()
	var shader_resource: Resource = load(_BACKGROUND_SHADER_PATH)
	if shader_resource is Shader:
		var background_shader: Shader = shader_resource
		background_material.shader = background_shader
	background_rect.material = background_material

	var resolved_board: BoardTheme = theme_utility.resolve_board_theme_for_mode(&"classic")
	var resolved_schemes: Dictionary = theme_utility.resolve_color_schemes_for_mode(&"classic")
	var default_scheme_value: Variant = resolved_schemes.get(0)
	var resolved_default_scheme: TileColorScheme = null
	if default_scheme_value is TileColorScheme:
		resolved_default_scheme = default_scheme_value

	assert_true(resolved_board == _DEFAULT_BOARD_THEME, "当前主题应覆盖模式默认棋盘主题。")
	assert_true(
		resolved_default_scheme == _CLASSIC_TILE_THEME,
		"当前主题应覆盖默认方块色阶槽位。"
	)
	resolved_schemes.clear()
	assert_true(
		theme_utility.resolve_color_schemes_for_mode(&"classic").has(0),
		"模式视觉色阶结果必须复制隔离。"
	)
	var unknown_board: BoardTheme = theme_utility.resolve_board_theme_for_mode(&"unknown")
	assert_push_error("未知模式视觉 profile")
	assert_null(
		unknown_board,
		"未知模式视觉 profile 必须失败关闭。"
	)
	var unknown_schemes: Dictionary = theme_utility.resolve_color_schemes_for_mode(&"unknown")
	assert_push_error("未知模式视觉 profile")
	assert_true(
		unknown_schemes.is_empty(),
		"未知模式视觉 profile 不得隐式回退到业务路径资源。"
	)
	assert_true(
		is_instance_valid(board_feedback)
		and board_feedback.get_profile()
			== theme_utility.get_current_visual_theme().board_feedback_profile,
		"GameThemeUtility 应把当前棋盘反馈 Profile 注入运行时 Utility。"
	)
	assert_true(
		is_instance_valid(celebration_vfx) and celebration_vfx.get_theme() == theme_utility.get_current_visual_theme().celebration_vfx_theme,
		"GameThemeUtility 应把当前庆祝 VFX 主题注入运行时 Utility。"
	)
	theme_utility.apply_background_to_color_rect(background_rect)
	assert_true(
		is_zero_approx(GFVariantData.to_float(background_material.get_shader_parameter(&"grain_strength"))),
		"GameThemeUtility 应通过 GFShaderParameterUtility 应用背景 Profile。"
	)
	assert_true(
		GFVariantData.to_vector2(background_material.get_shader_parameter(&"cloud_pixelation")) == Vector2(176.0, 99.0),
		"GF 背景 Profile 应完整写入向量参数。"
	)
	var accessibility_value: Variant = setup.get("accessibility")
	if accessibility_value is GameAccessibilityUtility:
		var accessibility: GameAccessibilityUtility = accessibility_value
		accessibility.set_shader_effects_enabled(false)
		theme_utility.apply_background_to_color_rect(background_rect)
		var driver_node: Node = background_rect.get_node_or_null(
			"ShaderAnimationDriver"
		)
		assert_true(driver_node is GameShaderAnimationDriver, "主题背景应挂载项目自有时间 Driver。")
		assert_true(background_rect.material == null, "关闭 Shader 后背景必须成为纯静态 ColorRect。")
		assert_true(
			background_rect.process_mode == Node.PROCESS_MODE_DISABLED,
			"静态背景不得保留节点处理。"
		)
		if driver_node is GameShaderAnimationDriver:
			var driver: GameShaderAnimationDriver = driver_node
			assert_false(driver.is_animation_enabled(), "静态背景 Driver 必须停止时间推进。")
		accessibility.set_shader_effects_enabled(true)
		theme_utility.apply_background_to_color_rect(background_rect)
		assert_true(background_rect.material == background_material, "重新启用 Shader 应恢复主题材质。")
		assert_true(
			background_rect.process_mode == Node.PROCESS_MODE_DISABLED,
			"默认静态纸纹恢复材质后仍不应推进背景时间。"
		)
		var active_theme: GameTheme = GameTheme.new()
		active_theme.board_theme = resolved_board
		active_theme.background_shader_profile = GFShaderParameterProfile.new()
		active_theme.background_shader_profile.parameters = (
			theme_utility.get_current_visual_theme().background_shader_profile.parameters.duplicate(true)
		)
		var _active_profile: GFShaderParameterProfile = active_theme.background_shader_profile.set_parameter(
			&"cloud_strength", 0.02
		)
		theme_utility._apply_background_to_color_rect(background_rect, active_theme)
		assert_true(
			background_rect.process_mode == Node.PROCESS_MODE_INHERIT,
			"显式启用环境动态的其他主题仍应恢复时间 Driver。"
		)
		if driver_node is GameShaderAnimationDriver:
			var active_driver: GameShaderAnimationDriver = driver_node
			assert_true(active_driver.is_animation_enabled())
	else:
		assert_true(false, "测试 setup 应提供 GameAccessibilityUtility。")
	background_rect.material = null
	background_rect.free()

	await _dispose_architecture(architecture)


func test_board_preview_uses_current_theme_for_preview_styles() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_config: GameModeConfig = GameModeConfig.new()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	var preview: BoardPreview = BoardPreview.new()

	mode_config.visual_profile_id = &"classic"
	mode_config.interaction_rule = ClassicInteractionRule.new()
	context.test_architecture = architecture

	add_child_autoqfree(context)
	context.add_child(preview)
	await get_tree().process_frame

	var preview_topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	preview.show_snapshot(
		{
			&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
			&"topology": preview_topology.to_dict(),
			&"tiles": [],
		},
		mode_config
	)

	var panel_value: Node = preview.get_node_or_null("BackgroundPanel")
	assert_true(panel_value is Panel, "预览应创建可检查的背景面板。")
	if panel_value is Panel:
		var panel: Panel = panel_value
		var style_value: StyleBox = panel.get_theme_stylebox("panel")
		assert_true(style_value is StyleBoxFlat, "预览背景应使用 StyleBoxFlat。")
		if style_value is StyleBoxFlat:
			var flat_style: StyleBoxFlat = style_value
			assert_true(
				flat_style.bg_color == _DEFAULT_BOARD_THEME.board_panel_color,
				"回放/存档预览应跟随当前主题棋盘面板色，而不是模式默认色。"
			)

	await _dispose_architecture(architecture)


func test_current_audio_theme_defines_stable_event_ids() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var audio_utility: GFAudioUtility = _get_audio_utility(setup)
	var audio_theme: GameAudioTheme = theme_utility.get_current_sound_theme()

	assert_true(is_instance_valid(audio_theme), "当前音效主题应能解析。")
	assert_true(audio_theme.get_resolved_bank_id() == &"printworks", "音效主题应提供稳定音频银行 ID。")
	assert_true(is_instance_valid(audio_theme.audio_bank), "音效主题应引用可注册的 GFAudioBank。")
	assert_false(audio_theme.tile_spawn_event == &"", "方块生成音效事件 ID 不应为空。")
	assert_false(audio_theme.tile_move_event == &"", "方块移动音效事件 ID 不应为空。")
	assert_false(audio_theme.tile_merge_event == &"", "方块合并音效事件 ID 不应为空。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.ui_select_event), "音频银行应提供 UI 选择音效。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.ui_confirm_event), "音频银行应提供 UI 确认音效。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.tile_spawn_event), "音频银行应提供方块生成音效。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.tile_move_event), "音频银行应提供方块移动音效。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.tile_merge_event), "音频银行应提供方块合并音效。")
	assert_true(audio_theme.audio_bank.has_clip(audio_theme.game_over_event), "音频银行应提供游戏结束音效。")
	assert_true(
		GFVariantData.get_option_bool(
			audio_theme.audio_bank.resolve_clip(audio_theme.tile_merge_chain_event),
			&"ok"
		),
		"连续合并事件应通过 GFAudioBank 层级回退解析。"
	)
	assert_true(
		GFVariantData.get_option_bool(
			audio_theme.audio_bank.resolve_clip(audio_theme.tile_move_blocked_event),
			&"ok"
		),
		"受阻移动事件应通过 GFAudioBank 层级回退解析。"
	)
	assert_true(
		audio_utility.get_audio_bank(audio_theme.get_resolved_bank_id()) == audio_theme.audio_bank,
		"主题 Utility ready 后应把当前音效主题注册到 GFAudioUtility。"
	)

	await _dispose_architecture(architecture)


func test_theme_utility_plays_semantic_sound_events_through_gf_audio() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var audio_utility: GFAudioUtility = _get_audio_utility(setup)
	var backend: TestRecordingAudioBackend = TestRecordingAudioBackend.new()
	var backend_configured: bool = audio_utility.set_audio_backend(backend)
	assert_true(backend_configured, "测试音频后端必须完成配置。")

	theme_utility.play_ui_select_sound()
	theme_utility.play_ui_confirm_sound()
	theme_utility.play_tile_spawn_sound()
	theme_utility.play_tile_move_sound()
	theme_utility.play_tile_merge_sound()
	theme_utility.play_game_over_sound()
	var audio_theme: GameAudioTheme = theme_utility.get_current_sound_theme()
	theme_utility.play_current_sound_event(
		audio_theme.tile_merge_chain_event,
		{&"merge_count": 2}
	)

	assert_true(backend.sfx_clip_count == 7, "主题语义音效应全部通过 GFAudioUtility 播放。")
	assert_true(
		backend.paths.has("res://features/asset_library/resources/audio/ui/printworks_select_soft_01.ogg"),
		"UI 选择音效应来自当前音效主题音频银行。"
	)
	assert_true(
		backend.paths.has("res://features/asset_library/resources/audio/game/printworks_game_over_soft_01.ogg"),
		"游戏结束音效应来自当前音效主题音频银行。"
	)

	await _dispose_architecture(architecture)


func test_audio_theme_selects_one_primary_event_from_typed_turn_result() -> void:
	var audio_theme: GameAudioTheme = preload(
		"res://features/themes/resources/themes/game/printworks_audio_theme.tres"
	)
	var movement_turn: TurnResult = TurnResult.new()
	movement_turn.direction = Vector2i.RIGHT
	movement_turn.movements.append(
		TileMovementResult.new(TileState.new(2), Vector2i.ZERO, Vector2i.RIGHT)
	)
	assert_true(
		audio_theme.resolve_turn_event(movement_turn) == audio_theme.tile_move_event,
		"纯移动回合应只选择移动主事件。"
	)

	var first_merge: TileMergeResult = _make_audio_merge_result(2, 4)
	var second_merge: TileMergeResult = _make_audio_merge_result(4, 8)
	movement_turn.add_merge(first_merge)
	assert_true(
		audio_theme.resolve_turn_event(movement_turn) == audio_theme.tile_merge_event,
		"单次合并应覆盖普通移动事件。"
	)
	movement_turn.add_merge(second_merge)
	assert_true(
		audio_theme.resolve_turn_event(movement_turn) == audio_theme.tile_merge_chain_event,
		"多次合并应选择连续合并事件。"
	)
	movement_turn.add_transform(TileTransformResult.new(TileState.new(8)))
	assert_true(
		audio_theme.resolve_turn_event(movement_turn) == audio_theme.tile_transform_event,
		"转化语义应优先于连续合并。"
	)
	assert_true(
		audio_theme.resolve_turn_event(movement_turn, true) == audio_theme.target_reached_event,
		"里程碑事件应成为当前回合唯一最高优先级事件。"
	)


# --- 私有/辅助方法 ---

func _make_audio_merge_result(consumed_value: int, survivor_value: int) -> TileMergeResult:
	var interaction: TileInteractionResult = TileInteractionResult.new()
	interaction.consumed = TileState.new(consumed_value)
	interaction.survivor = TileState.new(survivor_value)
	interaction.interaction_rule_id = &"test.audio.merge"
	var merge: TileMergeResult = TileMergeResult.new()
	merge.interaction = interaction
	return merge


func _create_theme_architecture(
	include_scene_router: bool = false,
	prime_asset_cache: bool = true,
	initial_accessibility_state: GameAccessibilityState = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var assets: GFAssetUtility = GFAssetUtility.new()
	assets.max_cache_size = 256
	var content_packages: GFContentPackageUtility = GFContentPackageUtility.new()
	var project_content_catalog: ProjectContentCatalogUtility = (
		ProjectContentCatalogUtility.new().configure_source_roots(PackedStringArray([
			"res://features/asset_library/resources",
			"res://features/themes/resources",
		]))
	)
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.persistence_enabled = false
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	if initial_accessibility_state != null:
		settings.set_value(
			GameAccessibilityState.REDUCED_MOTION_SETTING_KEY,
			initial_accessibility_state.reduced_motion,
			false
		)
		settings.set_value(
			GameAccessibilityState.SHADER_EFFECTS_ENABLED_SETTING_KEY,
			initial_accessibility_state.shader_effects_enabled,
			false
		)
		settings.set_value(
			GameAccessibilityState.VFX_QUALITY_SETTING_KEY,
			initial_accessibility_state.vfx_quality,
			false
		)
	var storage: GFStorageUtility = GFStorageUtility.new()
	var audio: GFAudioUtility = GFAudioUtility.new()
	var style: GameUiStyleUtility = GameUiStyleUtility.new()
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var shake: GFShakeUtility = GFShakeUtility.new()
	var haptic: GFHapticUtility = GFHapticUtility.new()
	var board_feedback: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	var celebration_vfx: GameCelebrationVfxUtility = GameCelebrationVfxUtility.new()
	var clock_utility: GameClockUtility = GameClockUtility.new()
	var theme_catalog: GameThemeCatalogUtility = GameThemeCatalogUtility.new()
	var theme_utility: GameThemeUtility = GameThemeUtility.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var render_warmup: GFRenderWarmupUtility = GFRenderWarmupUtility.new()
	var operation_diagnostics: GFOperationDiagnosticsUtility = (
		GFOperationDiagnosticsUtility.new()
	)
	var timer_utility: GFTimerUtility = GFTimerUtility.new()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	var scene_utility: GFSceneUtility = null
	var screen_transition: GFScreenTransitionUtility = null
	var platform_runtime: GFPlatformRuntime = null
	var platform_utility: GamePlatformUtility = null
	var scene_router: SceneRouterSystem = null

	await architecture.register_utility(GFResourceBroker, GFResourceBroker.new())
	await architecture.register_utility(GFAssetUtility, assets)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFContentPackageUtility, content_packages)
	await architecture.register_utility(
		ProjectContentCatalogUtility,
		project_content_catalog
	)
	await architecture.register_utility(GameAssetLibraryUtility, asset_library)
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		operation_diagnostics
	)
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFAudioUtility, audio)
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GFRenderWarmupUtility, render_warmup)
	await architecture.register_utility(GFTimerUtility, timer_utility)
	await architecture.register_utility(GFSignalUtility, signal_utility)
	await architecture.register_utility(GameAccessibilityUtility, accessibility)
	await architecture.register_utility(GameUiStyleUtility, style)
	await architecture.register_utility(GameUiMotionUtility, motion)
	await architecture.register_utility(GFShakeUtility, shake)
	await architecture.register_utility(GFHapticUtility, haptic)
	await architecture.register_utility(GameBoardFeedbackUtility, board_feedback)
	await architecture.register_utility(GameClockUtility, clock_utility)
	await architecture.register_utility(GameCelebrationVfxUtility, celebration_vfx)
	await architecture.register_utility(GameThemeCatalogUtility, theme_catalog)
	await architecture.register_utility(GameThemeUtility, theme_utility)
	if include_scene_router:
		scene_utility = GFSceneUtility.new()
		screen_transition = GFScreenTransitionUtility.new()
		platform_runtime = GFPlatformRuntime.new()
		platform_utility = GamePlatformUtility.new()
		scene_router = SceneRouterSystem.new()
		await architecture.register_utility(GFSceneUtility, scene_utility)
		await architecture.register_utility(GFScreenTransitionUtility, screen_transition)
		await architecture.register_utility(GFPlatformRuntime, platform_runtime)
		await architecture.register_utility(GamePlatformUtility, platform_utility)
		await architecture.register_system(SceneRouterSystem, scene_router)
	await architecture.init()
	if prime_asset_cache:
		_prime_theme_asset_cache(assets, theme_catalog)
	else:
		_asset_tick_architecture = architecture
	var initial_themes_ready: bool = await theme_utility.ensure_initial_themes_ready()
	if _asset_tick_architecture == architecture:
		_asset_tick_architecture = null
	assert_true(initial_themes_ready, "测试主题必须通过 GFAssetLoadSession 完成初始激活。")
	await get_tree().process_frame

	return {
		"architecture": architecture,
		"assets": assets,
		"resolver": resolver,
		"content_packages": content_packages,
		"project_content_catalog": project_content_catalog,
		"asset_library": asset_library,
		"settings": settings,
		"audio": audio,
		"style": style,
		"board_feedback": board_feedback,
		"celebration_vfx": celebration_vfx,
		"theme_catalog": theme_catalog,
		"theme_utility": theme_utility,
		"shader_parameters": shader_parameters,
		"render_warmup": render_warmup,
		"operation_diagnostics": operation_diagnostics,
		"signal_utility": signal_utility,
		"accessibility": accessibility,
		"scene_utility": scene_utility,
		"screen_transition": screen_transition,
		"platform_runtime": platform_runtime,
		"platform_utility": platform_utility,
		"scene_router": scene_router,
	}


func _dispose_architecture(architecture: GFArchitecture) -> void:
	if _asset_tick_architecture == architecture:
		_asset_tick_architecture = null
	if architecture != null:
		architecture.dispose()
	await get_tree().process_frame


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_settings(setup: Dictionary) -> GFSettingsUtility:
	var value: Variant = setup.get("settings")
	if value is GFSettingsUtility:
		var settings: GFSettingsUtility = value
		return settings
	assert_true(false, "测试 setup 缺少 GFSettingsUtility。")
	return GFSettingsUtility.new()


func _get_resource_resolver(setup: Dictionary) -> GFResourceResolverUtility:
	var value: Variant = setup.get("resolver")
	if value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = value
		return resolver
	assert_true(false, "测试 setup 缺少 GFResourceResolverUtility。")
	return GFResourceResolverUtility.new()


func _get_asset_utility(setup: Dictionary) -> GFAssetUtility:
	var value: Variant = setup.get("assets")
	if value is GFAssetUtility:
		var asset_utility: GFAssetUtility = value
		return asset_utility
	assert_true(false, "测试 setup 缺少 GFAssetUtility。")
	return GFAssetUtility.new()


func _get_theme_utility(setup: Dictionary) -> GameThemeUtility:
	var value: Variant = setup.get("theme_utility")
	if value is GameThemeUtility:
		var theme_utility: GameThemeUtility = value
		return theme_utility
	assert_true(false, "测试 setup 缺少 GameThemeUtility。")
	return GameThemeUtility.new()


func _get_theme_catalog(setup: Dictionary) -> GameThemeCatalogUtility:
	var value: Variant = setup.get("theme_catalog")
	if value is GameThemeCatalogUtility:
		var catalog: GameThemeCatalogUtility = value
		return catalog
	assert_true(false, "测试 setup 缺少 GameThemeCatalogUtility。")
	return GameThemeCatalogUtility.new()


func _get_screen_transition_utility(setup: Dictionary) -> GFScreenTransitionUtility:
	var value: Variant = setup.get("screen_transition")
	if value is GFScreenTransitionUtility:
		var transition_utility: GFScreenTransitionUtility = value
		return transition_utility
	assert_true(false, "测试 setup 缺少 GFScreenTransitionUtility。")
	return GFScreenTransitionUtility.new()


func _get_scene_router_system(setup: Dictionary) -> SceneRouterSystem:
	var value: Variant = setup.get("scene_router")
	if value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = value
		return scene_router
	assert_true(false, "测试 setup 缺少 SceneRouterSystem。")
	return SceneRouterSystem.new()


func _get_audio_utility(setup: Dictionary) -> GFAudioUtility:
	var value: Variant = setup.get("audio")
	if value is GFAudioUtility:
		var audio: GFAudioUtility = value
		return audio
	assert_true(false, "测试 setup 缺少 GFAudioUtility。")
	return GFAudioUtility.new()


func _prime_theme_asset_cache(
	asset_utility: GFAssetUtility,
	theme_catalog: GameThemeCatalogUtility
) -> void:
	_prime_asset_dependency_tree(
		asset_utility,
		theme_catalog.get_visual_theme_resource_path(&"halftone_atlas")
	)
	_prime_asset_dependency_tree(
		asset_utility,
		theme_catalog.get_sound_theme_resource_path(&"printworks")
	)


func _prime_asset_dependency_tree(asset_utility: GFAssetUtility, root_path: String) -> void:
	var paths: PackedStringArray = GFResourceRegistryTools.collect_dependency_paths(
		root_path,
		{
			"recursive": true,
			"include_root": true,
		}
	)
	for path: String in paths:
		var resource: Resource = ResourceLoader.load(path)
		if resource != null:
			asset_utility.put_cache(path, resource)
