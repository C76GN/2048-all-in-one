## 验证项目主题注册表、设置接入和主题资源解析。
extends GutTest


# --- 常量 ---

const _THEME_REGISTRY_PATH: String = "res://resources/registries/game_theme_registry.tres"
const _BACKGROUND_SHADER_PATH: String = "res://asset_library/shaders/background/halftone_paper_background.gdshader"
const _DEFAULT_BOARD_THEME: BoardTheme = preload("res://resources/themes/board/default_board_theme.tres")
const _CLASSIC_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/classic_tile_theme.tres")


# --- 测试用例 ---

func test_theme_registry_loads_default_theme_pack() -> void:
	var registry: GameThemeRegistry = _load_theme_registry()

	assert_true(is_instance_valid(registry), "主题注册表应能加载。")
	assert_true(registry.default_theme_id == &"halftone_atlas", "默认视觉主题应是当前半调图集主题。")
	assert_true(registry.default_sound_theme_id == &"printworks", "默认音效主题应是印刷工坊。")

	var theme: GameTheme = registry.get_default_theme()
	assert_true(is_instance_valid(theme), "默认视觉主题资源应存在。")
	assert_true(theme.theme_id == &"halftone_atlas", "默认视觉主题 ID 应稳定。")
	assert_true(is_instance_valid(theme.board_theme), "主题应引用棋盘主题资源。")
	assert_true(is_instance_valid(theme.ui_palette), "主题应引用 UI 色板资源。")
	assert_true(is_instance_valid(theme.audio_theme), "主题应引用默认音效主题。")
	assert_true(is_instance_valid(theme.background_shader_profile), "主题应引用 GF 背景 Shader 参数 Profile。")
	assert_true(theme.background_shader_profile.get_parameter_names().size() == 28, "背景 Profile 应完整声明当前 shader 的 28 个主题参数。")
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
	assert_true(theme.color_schemes.has(Tile.TileType.PLAYER), "主题应覆盖玩家方块色阶。")


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


func test_theme_content_package_registers_theme_registry_resource_key() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resource_resolver(setup)

	var resolve_report: Dictionary = resolver.resolve(
		GameThemeUtility.THEME_REGISTRY_RESOURCE_KEY,
		"GameThemeRegistry"
	)
	var resource: Resource = resolver.load(
		GameThemeUtility.THEME_REGISTRY_RESOURCE_KEY,
		"GameThemeRegistry"
	)
	var blue_scheme_resource: Resource = resolver.load(&"game.tile_scheme.blue", "TileColorScheme")
	var audio_bank_resource: Resource = resolver.load(&"game.audio_bank.printworks", "GFAudioBank")

	assert_true(
		GFVariantData.get_option_bool(resolve_report, "ok", false),
		"主题内容包应把主题注册表资源键注册到 GFResourceResolverUtility。"
	)
	assert_true(resource is GameThemeRegistry, "主题注册表应能通过资源解析器加载。")
	assert_true(blue_scheme_resource is TileColorScheme, "主题内容包应登记完整的内置方块色阶资源。")
	assert_true(audio_bank_resource is GFAudioBank, "主题内容包应登记 printworks 音频银行。")

	await _dispose_architecture(architecture)


func test_theme_debug_snapshot_exposes_content_package_and_resolver_state() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)

	var snapshot: Dictionary = theme_utility.get_debug_snapshot()
	var catalog_snapshot: Dictionary = GFVariantData.get_option_dictionary(snapshot, "catalog")
	var resolver_snapshot: Dictionary = GFVariantData.get_option_dictionary(catalog_snapshot, "resolver")
	var registered_keys: PackedStringArray = GFVariantData.get_option_packed_string_array(
		resolver_snapshot,
		"registered_keys"
	)

	assert_true(
		GFVariantData.to_string_name(snapshot.get("theme_registry_key"), &"") == GameThemeUtility.THEME_REGISTRY_RESOURCE_KEY,
		"主题诊断快照应暴露稳定主题注册表资源键。"
	)
	assert_true(
		registered_keys.has(String(GameThemeUtility.THEME_REGISTRY_RESOURCE_KEY)),
		"主题诊断快照应包含 resolver 已注册资源键。"
	)
	assert_true(
		GFVariantData.to_int(snapshot.get("available_visual_theme_count"), 0) > 0,
		"主题诊断快照应暴露可用视觉主题数量。"
	)

	await _dispose_architecture(architecture)


func test_game_theme_utility_resolves_board_and_tile_schemes() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var theme_utility: GameThemeUtility = _get_theme_utility(setup)
	var fallback_board: BoardTheme = BoardTheme.new()
	var fallback_scheme: TileColorScheme = TileColorScheme.new()
	var background_rect: ColorRect = ColorRect.new()
	var background_material: ShaderMaterial = ShaderMaterial.new()
	var shader_resource: Resource = load(_BACKGROUND_SHADER_PATH)
	if shader_resource is Shader:
		var background_shader: Shader = shader_resource
		background_material.shader = background_shader
	background_rect.material = background_material

	var resolved_board: BoardTheme = theme_utility.resolve_board_theme(fallback_board)
	var resolved_schemes: Dictionary = theme_utility.resolve_color_schemes({
		Tile.TileType.PLAYER: fallback_scheme,
	})
	var player_scheme_value: Variant = resolved_schemes.get(Tile.TileType.PLAYER)
	var resolved_player_scheme: TileColorScheme = null
	if player_scheme_value is TileColorScheme:
		resolved_player_scheme = player_scheme_value

	assert_true(resolved_board == _DEFAULT_BOARD_THEME, "当前主题应覆盖模式默认棋盘主题。")
	assert_true(
		resolved_player_scheme == _CLASSIC_TILE_THEME,
		"当前主题应覆盖玩家方块色阶。"
	)
	theme_utility.apply_background_to_color_rect(background_rect)
	assert_true(
		is_equal_approx(GFVariantData.to_float(background_material.get_shader_parameter(&"grain_strength")), 0.038),
		"GameThemeUtility 应通过 GFShaderParameterUtility 应用背景 Profile。"
	)
	assert_true(
		GFVariantData.to_vector2(background_material.get_shader_parameter(&"cloud_pixelation")) == Vector2(176.0, 99.0),
		"GF 背景 Profile 应完整写入向量参数。"
	)
	background_rect.material = null
	background_rect.free()

	await _dispose_architecture(architecture)


func test_board_preview_uses_current_theme_for_preview_styles() -> void:
	var setup: Dictionary = await _create_theme_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var fallback_board: BoardTheme = BoardTheme.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	var preview: BoardPreview = BoardPreview.new()

	fallback_board.board_panel_color = Color(1.0, 0.0, 1.0, 1.0)
	fallback_board.board_border_color = Color(0.0, 1.0, 1.0, 1.0)
	fallback_board.empty_cell_color = Color(1.0, 0.0, 0.0, 1.0)
	fallback_board.empty_cell_border_color = Color(0.0, 1.0, 0.0, 1.0)
	mode_config.board_theme = fallback_board
	mode_config.interaction_rule = ClassicInteractionRule.new()
	mode_config.color_schemes = {}
	context.test_architecture = architecture

	add_child_autoqfree(context)
	context.add_child(preview)
	await get_tree().process_frame

	preview.show_snapshot({"grid_size": 4, "tiles": []}, mode_config)

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
			assert_false(
				flat_style.bg_color == fallback_board.board_panel_color,
				"回放/存档预览不应绕过 GameThemeUtility。"
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
	audio_utility.set_audio_backend(backend)

	theme_utility.play_ui_select_sound()
	theme_utility.play_ui_confirm_sound()
	theme_utility.play_tile_spawn_sound()
	theme_utility.play_tile_move_sound()
	theme_utility.play_tile_merge_sound()
	theme_utility.play_game_over_sound()

	assert_true(backend.sfx_clip_count == 6, "主题语义音效应全部通过 GFAudioUtility 播放。")
	assert_true(
		backend.paths.has("res://asset_library/audio/ui/printworks_select_soft_01.ogg"),
		"UI 选择音效应来自当前音效主题音频银行。"
	)
	assert_true(
		backend.paths.has("res://asset_library/audio/game/printworks_game_over_soft_01.ogg"),
		"游戏结束音效应来自当前音效主题音频银行。"
	)

	await _dispose_architecture(architecture)


# --- 私有/辅助方法 ---

func _create_theme_architecture(include_scene_router: bool = false) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var content_packages: GFContentPackageUtility = GFContentPackageUtility.new()
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var audio: GFAudioUtility = GFAudioUtility.new()
	var motion: GameUiMotionUtility = GameUiMotionUtility.new()
	var theme_catalog: GameThemeCatalogUtility = GameThemeCatalogUtility.new()
	var theme_utility: GameThemeUtility = GameThemeUtility.new()
	var shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()
	var screen_transition: GFScreenTransitionUtility = null
	var scene_router: SceneRouterSystem = null

	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFContentPackageUtility, content_packages)
	await architecture.register_utility(GameAssetLibraryUtility, asset_library)
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFAudioUtility, audio)
	await architecture.register_utility(GameUiMotionUtility, motion)
	await architecture.register_utility(GFShaderParameterUtility, shader_parameters)
	await architecture.register_utility(GameThemeCatalogUtility, theme_catalog)
	await architecture.register_utility(GameThemeUtility, theme_utility)
	if include_scene_router:
		screen_transition = GFScreenTransitionUtility.new()
		scene_router = SceneRouterSystem.new()
		await architecture.register_utility(GFScreenTransitionUtility, screen_transition)
		await architecture.register_system(SceneRouterSystem, scene_router)
	await architecture.init()
	await get_tree().process_frame

	return {
		"architecture": architecture,
		"resolver": resolver,
		"content_packages": content_packages,
		"asset_library": asset_library,
		"settings": settings,
		"audio": audio,
		"theme_catalog": theme_catalog,
		"theme_utility": theme_utility,
		"shader_parameters": shader_parameters,
		"screen_transition": screen_transition,
		"scene_router": scene_router,
	}


func _dispose_architecture(architecture: GFArchitecture) -> void:
	if architecture != null:
		architecture.dispose()
	await get_tree().process_frame


func _load_theme_registry() -> GameThemeRegistry:
	var resource: Resource = load(_THEME_REGISTRY_PATH)
	if resource is GameThemeRegistry:
		var registry: GameThemeRegistry = resource
		return registry
	return null


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


func _get_theme_utility(setup: Dictionary) -> GameThemeUtility:
	var value: Variant = setup.get("theme_utility")
	if value is GameThemeUtility:
		var theme_utility: GameThemeUtility = value
		return theme_utility
	assert_true(false, "测试 setup 缺少 GameThemeUtility。")
	return GameThemeUtility.new()


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
