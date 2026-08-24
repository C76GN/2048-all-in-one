## 验证项目 Installer 不重复装配 GF 扩展已拥有的 Module。
extends GutTest


# --- 常量 ---

const PROJECT_INSTALLER_PATH: String = "res://app/scripts/game_architecture_installer.gd"
const PROJECT_REQUIRED_BINDING_PATH: String = (
	"res://shared/scripts/foundation/project_required_binding.gd"
)
const BOOT_RUNTIME_PATH: String = "res://app/scripts/boot_runtime.gd"
const STARTUP_RENDER_WARMUP_MANIFEST: GFRenderWarmupManifest = preload(
	"res://features/themes/resources/themes/boot/startup_render_warmup_manifest.tres"
)
const GAME_BOARD_CONTROLLER_PATH: String = "res://features/game_session/scripts/controllers/game_board_controller.gd"
const GAME_PLAY_CONTROLLER_PATH: String = "res://features/game_session/scripts/controllers/game_play_controller.gd"
const GAME_PLAY_SCENE_PATH: String = "res://features/game_session/scenes/game/game_play.tscn"
const GAME_STATUS_MODEL_PATH: String = "res://features/gameplay/scripts/models/game_status_model.gd"
const GAME_STATE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_state_system.gd"
const GAME_FLOW_SYSTEM_PATH: String = "res://features/game_session/scripts/systems/game_flow_system.gd"
const GAME_PAUSE_UTILITY_PATH: String = "res://features/game_session/scripts/utilities/game_pause_utility.gd"
const GAME_REALTIME_TIMER_UTILITY_PATH: String = "res://features/game_session/scripts/utilities/game_realtime_timer_utility.gd"
const GAME_BOARD_ANIMATION_UTILITY_PATH: String = "res://features/game_session/scripts/utilities/game_board_animation_utility.gd"
const GAME_INPUT_PROFILE_UTILITY_PATH: String = "res://features/game_session/scripts/utilities/game_input_profile_utility.gd"
const GAME_INIT_SYSTEM_PATH: String = "res://features/game_session/scripts/systems/game_init_system.gd"
const GAME_TURN_SYSTEM_PATH: String = "res://features/game_session/scripts/systems/game_turn_system.gd"
const GAME_MOVE_TURN_ACTION_PATH: String = "res://features/game_session/scripts/actions/game_move_turn_action.gd"
const RULE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/rule_system.gd"
const PLAYER_INPUT_SYSTEM_PATH: String = "res://features/game_session/scripts/systems/player_input_system.gd"
const HUD_PATH: String = "res://features/game_session/scripts/ui/hud.gd"
const BOOKMARK_DATA_PATH: String = "res://features/bookmarks/scripts/data/bookmark_data.gd"
const REMOVED_HUD_PAYLOAD_PATH: String = "res://features/gameplay/scripts/events/hud_message_payload.gd"
const SCENE_ROUTER_SYSTEM_PATH: String = "res://features/navigation/scripts/systems/scene_router_system.gd"
const BASE_LIST_MENU_PATH: String = (
	"res://features/saved_content_browser/scripts/menus/base_list_menu.gd"
)
const MODE_SELECTION_PATH: String = "res://features/navigation/scripts/menus/mode_selection.gd"
const MODE_SELECTION_SCENE_PATH: String = "res://features/navigation/scenes/menus/mode_selection.tscn"
const GAME_DIAGNOSTICS_UTILITY_PATH: String = "res://features/diagnostics/scripts/utilities/game_diagnostics_utility.gd"
const GAME_DIAGNOSTICS_INSTALLER_PATH: String = "res://features/diagnostics/scripts/installers/game_diagnostics_installer.gd"
const PLATFORM_SMOKE_CONTROLLER_PATH: String = (
	"res://features/platform_runtime/scripts/controllers/platform_smoke_controller.gd"
)
const SETTINGS_MENU_PATH: String = "res://features/settings/scripts/menus/settings_menu.gd"
const GAME_UI_CONTROLLER_PATH: String = "res://features/themes/scripts/ui/game_ui_controller.gd"
const THEME_CATALOG_UTILITY_PATH: String = "res://features/themes/scripts/utilities/game_theme_catalog_utility.gd"
const THEME_UTILITY_PATH: String = "res://features/themes/scripts/utilities/game_theme_utility.gd"
const PROJECT_CONTENT_CATALOG_UTILITY_PATH: String = "res://shared/scripts/utilities/project_content_catalog_utility.gd"
const EVENT_NAMES_PATH: String = "res://shared/scripts/contracts/event_names.gd"
const PROJECT_SETTINGS_PATH: String = "res://project.godot"
const EXTENSION_OWNED_MODULES: Array[Dictionary] = [
	{
		"symbol": "GFStorageUtility",
		"extension": "gf.save",
		"owner": "addons/gf/extensions/save/extension.gd",
	},
	{
		"symbol": "GFLevelUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFQuestUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFActionQueueSystem",
		"extension": "gf.action_queue",
		"owner": "addons/gf/extensions/action_queue/extension.gd",
	},
	{
		"symbol": "GFContentPackageUtility",
		"extension": "gf.content_package",
		"owner": "addons/gf/extensions/content_package/extension.gd",
	},
	{
		"symbol": "GFAssetMetadataUtility",
		"extension": "gf.asset_metadata",
		"owner": "addons/gf/extensions/asset_metadata/extension.gd",
	},
	{
		"symbol": "GFCapabilityUtility",
		"extension": "gf.capability",
		"owner": "addons/gf/extensions/capability/extension.gd",
	},
	{
		"symbol": "GFTurnFlowSystem",
		"extension": "gf.turn_based",
		"owner": "addons/gf/extensions/turn_based/extension.gd",
	},
	{
		"symbol": "GFShakeUtility",
		"extension": "gf.feedback",
		"owner": "addons/gf/extensions/feedback/extension.gd",
	},
	{
		"symbol": "GFHapticUtility",
		"extension": "gf.feedback",
		"owner": "addons/gf/extensions/feedback/extension.gd",
	},
]


# --- 测试用例 ---

func test_project_installer_does_not_bind_extension_owned_modules() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var issues: Array[String] = []
	if source.is_empty():
		_append_string(issues, "%s 无法读取或为空。" % PROJECT_INSTALLER_PATH)

	for module: Dictionary in EXTENSION_OWNED_MODULES:
		var symbol: String = _get_dictionary_text(module, "symbol")
		var extension_id: String = _get_dictionary_text(module, "extension")
		var owner_path: String = _get_dictionary_text(module, "owner")
		if _source_binds_symbol(source, symbol):
			_append_string(issues, "%s 不应在项目 Installer 中手动绑定；它由 %s (%s) 自动装配。" % [
				symbol,
				owner_path,
				extension_id,
			])

	assert_true(
		issues.is_empty(),
		"项目 Installer 应只注册项目自身 Module，避免和 GF 扩展 Installer 重复注册：\n%s" % _join_lines(issues)
	)


func test_project_installer_binds_signal_utility_before_theme_consumers() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var signal_position: int = _find_project_binding_position(source, "GFSignalUtility")
	var theme_position: int = _find_project_binding_position(
		source,
		"_GAME_THEME_UTILITY_SCRIPT"
	)

	assert_true(signal_position >= 0, "项目 Installer 应注册 GFSignalUtility。")
	assert_true(theme_position >= 0, "项目 Installer 应注册 GameThemeUtility。")
	assert_true(
		signal_position < theme_position,
		"GFSignalUtility 必须先于依赖它的 GameThemeUtility 注册。"
	)


func test_project_installer_shares_resource_broker_before_load_consumers() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var broker_position: int = _find_project_binding_position(source, "GFResourceBroker")
	var background_work_position: int = _find_project_binding_position(
		source,
		"GFBackgroundWorkUtility"
	)
	var asset_position: int = _find_project_binding_position(source, "GFAssetUtility")
	var scene_position: int = _find_project_binding_position(source, "GFSceneUtility")

	assert_true(broker_position >= 0, "Composition Root 应注册共享 GFResourceBroker。")
	assert_true(background_work_position >= 0, "Composition Root 应注册 GFBackgroundWorkUtility。")
	assert_true(asset_position >= 0, "Composition Root 应注册 GFAssetUtility。")
	assert_true(scene_position >= 0, "Composition Root 应注册 GFSceneUtility。")
	assert_true(
		broker_position < background_work_position
		and broker_position < asset_position
		and broker_position < scene_position,
		"GFResourceBroker 必须先于所有 threaded 资源消费者注册。"
	)


func test_registered_resource_loading_consumers_resolve_one_broker() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var broker: GFResourceBroker = GFResourceBroker.new()
	var assets: GFAssetUtility = GFAssetUtility.new()
	var scenes: GFSceneUtility = GFSceneUtility.new()
	var jobs: GFBackgroundWorkUtility = GFBackgroundWorkUtility.new()
	await architecture.register_utility(GFResourceBroker, broker)
	await architecture.register_utility(GFAssetUtility, assets)
	await architecture.register_utility(GFSceneUtility, scenes)
	await architecture.register_utility(GFBackgroundWorkUtility, jobs)
	var initialized: bool = await architecture.init()

	assert_true(initialized, "资源加载 Composition Root slice 应完成真实架构初始化。")
	assert_same(assets.get_resource_broker(), broker, "Asset 必须取得项目共享 Broker。")
	assert_same(scenes.get_resource_broker(), broker, "Scene 必须取得项目共享 Broker。")
	assert_same(jobs.get_resource_broker(), broker, "BackgroundWork 必须取得项目共享 Broker。")
	architecture.dispose()
	await get_tree().process_frame


func test_shared_resource_broker_reuses_path_with_independent_cancellation() -> void:
	var broker: GFResourceBroker = GFResourceBroker.new()
	broker.init()
	var resource_path: String = (
		"res://features/themes/resources/themes/boot/"
		+ "startup_render_warmup_manifest.tres"
	)
	var first: GFResourceLease = broker.request(
		resource_path,
		"Resource",
		{&"consumer_id": &"project_asset_consumer"}
	)
	var second: GFResourceLease = broker.request(
		resource_path,
		"Resource",
		{&"consumer_id": &"project_scene_consumer"}
	)

	var admission: Dictionary = broker.get_debug_snapshot()
	assert_true(
		GFVariantData.get_option_int(admission, "active_count") == 1,
		"同资源的两个项目消费者必须复用一个底层请求。"
	)
	first.cancel(&"first_consumer_left")
	for _poll_index: int in range(120):
		if second.is_terminal():
			break
		broker.pump()
		await get_tree().process_frame

	assert_true(first.get_status() == GFResourceLease.STATUS_CANCELLED, "取消必须只终结当前 Lease。")
	assert_true(
		second.get_status() == GFResourceLease.STATUS_COMPLETED,
		"另一消费者必须继续收到共享资源。"
	)
	assert_not_null(second.get_resource(), "存活消费者应取得加载结果。")
	second.release()
	broker.pump()
	assert_true(broker.is_idle(), "共享 Lease 收敛后 Broker 必须回到 idle。")
	broker.dispose()


func test_project_installer_groups_internal_bindings_by_runtime_ownership() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var helper_names: Array[String] = [
		"_bind_runtime_foundation_utilities",
		"_bind_content_and_gameplay_utilities",
		"_bind_presentation_utilities",
		"_bind_input_and_platform_utilities",
		"_bind_state_and_navigation_systems",
		"_bind_progression_systems",
		"_bind_gameplay_systems",
	]
	for helper_name: String in helper_names:
		assert_true(
			source.contains("func %s(" % helper_name),
			"Composition Root 应保留内部装配分组：%s。" % helper_name
		)
	assert_true(
		_source_binds_symbol(source, "ProgressStatsSystem"),
		"进度统计所有者必须以 ProgressStatsSystem 的准确语义注册。"
	)
	assert_true(
		_source_binds_symbol(source, "TileLabSystem"),
		"方块试验台必须由项目 Composition Root 注册为独立 System。"
	)
	assert_true(
		source.contains("TileLabSaveData.SECTION_ID"),
		"方块蓝图必须进入统一玩家 SaveGraph。"
	)
	assert_false(
		_source_binds_symbol(source, "SaveSystem"),
		"Composition Root 不得再暗示项目存在第二个通用存档 System。"
	)


func test_project_installer_binds_input_device_before_input_mapping() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var canonical_timer_position: int = _find_project_binding_position(source, "GFTimerUtility")
	var device_position: int = _find_project_binding_position(source, "GFInputDeviceUtility")
	var realtime_timer_position: int = _find_project_binding_position(
		source,
		"_GAME_REALTIME_TIMER_UTILITY_SCRIPT"
	)
	var mapping_position: int = _find_project_binding_position(source, "GFInputMappingUtility")

	assert_true(canonical_timer_position >= 0, "项目 Installer 应保留随 GFTime 推进的 canonical GFTimerUtility。")
	assert_true(device_position >= 0, "项目 Installer 应注册 GFInputDeviceUtility。")
	assert_true(realtime_timer_position >= 0, "项目 Installer 应注册 GF 实时输入脉冲定时器。")
	assert_true(mapping_position >= 0, "项目 Installer 应注册 GFInputMappingUtility。")
	assert_true(
		device_position < mapping_position,
		"GFInputDeviceUtility 必须先于依赖它的 GFInputMappingUtility 注册。"
	)
	assert_true(
		realtime_timer_position < mapping_position,
		"实时 GFTimerUtility 策略必须先于创建虚拟输入源的 Mapping 消费方注册。"
	)
	var realtime_timer_source: String = _read_text(GAME_REALTIME_TIMER_UTILITY_PATH)
	assert_true(realtime_timer_source.contains("extends GFTimerUtility"))
	assert_true(realtime_timer_source.contains("ignore_pause = true"))
	assert_true(realtime_timer_source.contains("ignore_time_scale = true"))


func test_project_installer_orders_input_profile_and_board_animation_adapters() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var input_mapping_position: int = _find_project_binding_position(
		installer_source,
		"GFInputMappingUtility"
	)
	var input_assist_position: int = _find_project_binding_position(
		installer_source,
		"GFInputAssistUtility"
	)
	var input_profile_position: int = _find_project_binding_position(
		installer_source,
		"_GAME_INPUT_PROFILE_UTILITY_SCRIPT"
	)
	var board_animation_position: int = _find_project_binding_position(
		installer_source,
		"_GAME_BOARD_ANIMATION_UTILITY_SCRIPT"
	)
	var input_profile_source: String = _read_text(GAME_INPUT_PROFILE_UTILITY_PATH)
	var board_animation_source: String = _read_text(GAME_BOARD_ANIMATION_UTILITY_PATH)

	assert_true(input_assist_position > input_mapping_position, "GF 输入缓冲必须在映射工具之后注册。")
	assert_true(input_profile_position > input_assist_position, "输入覆盖 Adapter 必须在 GF 输入缓冲之后注册。")
	assert_true(board_animation_position > input_profile_position, "棋盘动画 Adapter 必须在输入策略之后注册。")
	assert_true(
		input_profile_source.contains("GFInputConflictAnalyzer.build_rebind_report"),
		"按键重映射必须复用 GF 冲突分析器。"
	)
	assert_true(
		board_animation_source.contains("get_linked_queue(BOARD_QUEUE_NAME, board)"),
		"棋盘动画必须使用绑定棋盘生命周期的 GF 命名队列。"
	)


func test_project_installer_registers_platform_primitives_before_platform_boundary() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var smoke_source: String = _read_text(PLATFORM_SMOKE_CONTROLLER_PATH)
	var runtime_position: int = _find_project_binding_position(source, "GFPlatformRuntime")
	var viewport_position: int = _find_project_binding_position(source, "GFViewportUtility")
	var http_position: int = _find_project_binding_position(source, "GFHttpClientUtility")
	var platform_position: int = _find_project_binding_position(
		source,
		"_GAME_PLATFORM_UTILITY_SCRIPT"
	)

	assert_true(runtime_position >= 0, "项目 Installer 应注册 GFPlatformRuntime。")
	assert_true(viewport_position >= 0, "项目 Installer 应注册 GFViewportUtility。")
	assert_true(http_position >= 0, "平台冒烟构建应注册 GFHttpClientUtility。")
	assert_true(
		source.contains("if OS.has_feature(_PLATFORM_SMOKE_FEATURE):"),
		"GFHttpClientUtility 只能在 platform_smoke 构建边界注册。"
	)
	assert_false(
		_source_binds_symbol(source, "GFPointerGestureUtility"),
		"可变配置的指针手势工具不得作为跨画布 singleton 注册。"
	)
	assert_true(
		smoke_source.contains("GFPointerGestureUtility.new()"),
		"平台冒烟场景应拥有隔离的指针手势实例。"
	)
	assert_true(platform_position >= 0, "项目 Installer 应注册 GamePlatformUtility。")
	assert_true(runtime_position < platform_position, "GF 平台运行时必须先于项目平台选择边界注册。")
	assert_true(viewport_position < platform_position, "显示能力应先于项目平台边界注册。")
	assert_true(http_position < platform_position, "HTTP 能力应先于项目平台边界注册。")


func test_project_installer_binds_pause_adapter_after_gf_time_provider() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var time_position: int = _find_project_binding_position(source, "GFTimeUtility")
	var pause_position: int = _find_project_binding_position(
		source,
		"_GAME_PAUSE_UTILITY_SCRIPT"
	)

	assert_true(time_position >= 0, "项目 Installer 应注册 GFTimeUtility。")
	assert_true(pause_position >= 0, "项目 Installer 应注册 GamePauseUtility。")
	assert_true(
		time_position < pause_position,
		"GFTimeUtility 必须先于同步逻辑时间的 GamePauseUtility 注册。"
	)


func test_project_clock_adapts_one_shared_gf_clock() -> void:
	var manual_clock: GFManualClock = GFManualClock.new(1_234_000, 9_876_000)
	var game_clock: GameClockUtility = GameClockUtility.new()
	var clock_set: bool = game_clock.set_clock(manual_clock)
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)

	assert_true(clock_set, "项目时钟 Adapter 应接受 GFClock 注入。")
	assert_true(game_clock.get_tick_usec() == 1_234_000, "微秒 tick 必须委托给 GFClock。")
	assert_true(game_clock.get_tick_msec() == 1234, "单调 tick 必须委托给 GFClock。")
	assert_true(game_clock.get_unix_timestamp() == 9876, "Unix 时间必须委托给 GFClock。")
	assert_true(
		installer_source.count("set_clock(_clock)") == 3,
		(
			"Composition Root 必须向 GFTimeUtility、GameClockUtility 与"
			+ " GameSettingsUtility 注入同一 GFClock。"
		)
	)
	assert_false(
		installer_source.contains("Time.get_ticks_"),
		"Composition Root 阶段计时必须复用已注入各运行时服务的共享 GFClock。"
	)


func test_project_installer_binds_storage_settings_store_before_game_settings() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var store_position: int = _find_project_binding_position(
		source,
		"GFStorageSettingsStoreUtility"
	)
	var settings_position: int = _find_project_binding_position(source, "GameSettingsUtility")

	assert_true(store_position >= 0, "项目 Installer 应注册 GF Storage Settings Store。")
	assert_true(
		source.contains("with_alias(GFSettingsStoreUtility)"),
		"Storage Settings Store 必须以精确 GFSettingsStoreUtility alias 注册。"
	)
	assert_true(settings_position >= 0, "项目 Installer 应注册 GameSettingsUtility。")
	assert_true(
		store_position < settings_position,
		"Settings Store 必须先于依赖它的 GameSettingsUtility 注册。"
	)


func test_project_installer_registers_router_port_as_a_direct_alias() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var alias_call_position: int = source.find("_architecture.register_utility_alias(")
	var port_position: int = source.find("GameUiRouterPort", alias_call_position)
	var target_position: int = source.find(
		"_GAME_UI_ROUTER_UTILITY_SCRIPT",
		port_position
	)

	assert_true(
		source.contains("with_alias(GFUIRouterUtility)"),
		"项目 Router 必须继续提供 GFUIRouterUtility alias。"
	)
	assert_true(
		alias_call_position >= 0
		and port_position > alias_call_position
		and target_position > port_position
		and target_position - port_position < 160,
		"跨 Feature 的 GameUiRouterPort 必须直接指向项目 Router Adapter。"
	)
	assert_false(
		source.contains("register_utility_alias(GameUiRouterPort, GFUIRouterUtility)"),
		"GameUiRouterPort 不得通过 GFUIRouterUtility 形成 alias 链。"
	)
	assert_true(
		source.contains(
			"binder.bind_system(SceneRouterSystem).with_alias(GameSceneRouterPort)"
		),
		"跨 Feature 的 GameSceneRouterPort 必须直接 alias 到唯一 SceneRouterSystem。"
	)
	assert_false(
		source.contains(
			"register_system_alias(GameSceneRouterPort, SceneRouterSystem)"
		),
		"GameSceneRouterPort 应由 Binder 原子注册，不能形成第二条手工 alias 路径。"
	)
	assert_true(
		source.contains(
			"binder.bind_system(GameSessionLaunchSystem).with_alias("
		),
		"跨 Feature 的 GameSessionLaunchPort 必须直接 alias 到唯一启动 System。"
	)
	assert_false(
		source.contains(
			"register_system_alias(GameSessionLaunchPort, GameSessionLaunchSystem)"
		),
		"GameSessionLaunchPort 应由 Binder 原子注册，不能形成第二条手工 alias 路径。"
	)


func test_project_installer_binds_chunk_profiles_and_wraps_large_sections() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var chunk_position: int = _find_project_binding_position(
		source,
		"_CHUNK_PROFILE_UTILITY_SCRIPT"
	)
	var save_graph_position: int = _find_project_binding_position(
		source,
		"_GAME_SAVE_GRAPH_UTILITY_SCRIPT"
	)

	assert_true(chunk_position >= 0, "Composition Root 应注册 ChunkProfileUtility。")
	assert_true(save_graph_position >= 0, "Composition Root 应注册 GameSaveGraphUtility。")
	assert_true(
		chunk_position < save_graph_position,
		"ChunkProfileUtility 必须先于依赖它的 GameSaveGraphUtility 注册。"
	)
	assert_true(
		source.contains("BookmarkManifestSaveSectionProvider.new(bookmark_data)"),
		"生产 Composition Root 必须让 bookmarks 使用共享业务 Provider 的 Manifest wrapper。"
	)
	assert_true(
		source.contains("ReplayManifestSaveSectionProvider.new(replay_data)"),
		"生产 Composition Root 必须让 replays 使用共享业务 Provider 的 Manifest wrapper。"
	)


func test_startup_render_warmup_uses_gf_manifest_and_utility() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var boot_source: String = _read_text(BOOT_RUNTIME_PATH)

	assert_true(
		_source_binds_symbol(installer_source, "GFRenderWarmupUtility"),
		"项目 Installer 应注册 GFRenderWarmupUtility。"
	)
	assert_true(
		boot_source.contains("build_manifest_from_tree("),
		"启动链应让 GF 收集预热节点树中的渲染资源。"
	)
	assert_true(
		boot_source.contains("warmup_manifest_now("),
		"启动链应通过 GFRenderWarmupUtility 执行清单预热。"
	)
	assert_true(
		STARTUP_RENDER_WARMUP_MANIFEST.get_entry_count() == 4,
		"启动渲染清单应覆盖背景、转场、焦点和庆祝四类首轮 Shader。"
	)
	for entry: Dictionary in STARTUP_RENDER_WARMUP_MANIFEST.get_entries():
		var resource_path: String = GFVariantData.get_option_string(entry, "resource_path")
		assert_true(
			ResourceLoader.exists(resource_path, "Shader"),
			"启动渲染清单条目必须解析为 Shader：%s" % resource_path
		)


func test_gameplay_pause_state_has_one_writable_adapter() -> void:
	var controller_source: String = _read_text(GAME_PLAY_CONTROLLER_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var pause_source: String = _read_text(GAME_PAUSE_UTILITY_PATH)

	assert_false(controller_source.contains(".paused ="), "Controller 不得旁路统一暂停 Adapter。")
	assert_false(flow_source.contains(".paused ="), "流程 System 不得旁路统一暂停 Adapter。")
	assert_true(pause_source.contains("_time_utility.is_paused = paused"), "暂停 Adapter 应同步 GF 逻辑时间。")
	assert_true(pause_source.contains("tree.paused = paused"), "暂停 Adapter 应同步 Godot 场景树。")


func test_navigation_focus_order_uses_gf_control_focus_utility() -> void:
	var list_source: String = _read_text(BASE_LIST_MENU_PATH)
	var mode_source: String = _read_text(MODE_SELECTION_PATH)

	assert_true(
		list_source.contains("GFControlFocusUtility.apply_focus_order"),
		"通用列表应把纵向循环焦点顺序委托给 GFControlFocusUtility。"
	)
	assert_true(
		mode_source.contains("GFControlFocusUtility.apply_focus_order"),
		"模式选择应把卡片纵向焦点顺序委托给 GFControlFocusUtility。"
	)
	assert_false(
		list_source.contains("items[0].focus_neighbor_top"),
		"通用列表不得保留手工首尾循环实现。"
	)
	assert_false(
		mode_source.contains("current_card.focus_neighbor_top"),
		"模式选择不得逐卡手工计算纵向邻居。"
	)


func test_mode_selection_focus_graph_keeps_vertical_loop_and_cross_column_target() -> void:
	var menu: ModeSelection = ModeSelection.new()
	autofree(menu)
	var root: Control = Control.new()
	add_child_autofree(root)
	var list: GridContainer = GridContainer.new()
	list.columns = 2
	var pagination: HBoxContainer = HBoxContainer.new()
	var back: Button = Button.new()
	var previous_page: Button = Button.new()
	var next_page: Button = Button.new()
	var grid_size: OptionButton = OptionButton.new()
	var first_card: Button = Button.new()
	var last_card: Button = Button.new()
	var cards: Array[Control] = [first_card, last_card]

	root.add_child(list)
	root.add_child(pagination)
	root.add_child(back)
	root.add_child(grid_size)
	pagination.visible = false
	pagination.add_child(previous_page)
	pagination.add_child(next_page)
	list.add_child(first_card)
	list.add_child(last_card)
	menu._mode_list_container = list
	menu._pagination_container = pagination
	menu._back_button = back
	menu._prev_page_button = previous_page
	menu._next_page_button = next_page
	menu._grid_size_option_button = grid_size
	await get_tree().process_frame

	menu._apply_mode_focus_graph(cards)

	assert_true(back.get_node_or_null(back.focus_neighbor_bottom) == first_card, "返回键向下应进入第一张模式卡。")
	assert_true(first_card.get_node_or_null(first_card.focus_neighbor_top) == back, "第一张模式卡向上应返回。")
	assert_true(first_card.get_node_or_null(first_card.focus_neighbor_right) == last_card, "两列模式索引应在同行向右移动。")
	assert_true(first_card.get_node_or_null(first_card.focus_neighbor_bottom) == back, "只有一行时向下应回到返回键。")
	assert_true(last_card.get_node_or_null(last_card.focus_neighbor_bottom) == back, "单页末张模式卡向下应闭环到返回键。")
	assert_true(next_page.focus_neighbor_top.is_empty(), "单页隐藏分页不得参与焦点图。")
	assert_true(last_card.get_node_or_null(last_card.focus_neighbor_right) == grid_size, "行末模式卡向右应进入配置列。")


func test_mode_selection_exposes_configuration_leaderboard_without_daily_control() -> void:
	var scene_source: String = _read_text(MODE_SELECTION_SCENE_PATH)
	var script_source: String = _read_text(MODE_SELECTION_PATH)

	assert_false(
		scene_source.contains("DailyChallengeButton"),
		"模式选择场景不得保留已删除的 Daily Challenge 控件。"
	)
	assert_true(scene_source.contains("CompetitionStatusLabel"))
	assert_true(scene_source.contains("AdvancedSettingsButton"))
	assert_true(scene_source.contains("AdvancedSettingsContainer"))
	assert_true(
		scene_source.contains("visible = false")
		and script_source.contains("_set_advanced_settings_visible(false)"),
		"种子、自定义棋盘和比赛信息必须默认折叠。"
	)
	assert_true(
		script_source.contains("get_local_leaderboard(")
		and script_source.contains("COMPETITION_CONFIG_STATUS_FORMAT"),
		"模式选择应继续展示当前规则集与拓扑配置的本地榜状态。"
	)


func test_removed_daily_challenge_types_cannot_reenter_composition_root() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var init_source: String = _read_text(GAME_INIT_SYSTEM_PATH)
	var mode_source: String = _read_text(MODE_SELECTION_PATH)

	assert_false(
		FileAccess.file_exists(
			"res://features/gameplay/scripts/data/game_challenge_metadata.gd"
		)
	)
	assert_false(
		FileAccess.file_exists(
			"res://features/gameplay/scripts/utilities/game_challenge_utility.gd"
		)
	)
	for removed_symbol: String in [
		"GameChallengeMetadata",
		"GameChallengeUtility",
		"SEED_SOURCE_DAILY",
	]:
		assert_false(installer_source.contains(removed_symbol))
		assert_false(init_source.contains(removed_symbol))
		assert_false(mode_source.contains(removed_symbol))


func test_project_installer_binds_asset_library_before_ui_consumers() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var project_catalog_position: int = _find_project_binding_position(
		source,
		"_PROJECT_CONTENT_CATALOG_UTILITY_SCRIPT"
	)
	var asset_library_position: int = _find_project_binding_position(
		source,
		"_GAME_ASSET_LIBRARY_UTILITY_SCRIPT"
	)
	var background_music_position: int = _find_project_binding_position(
		source,
		"_GAME_BACKGROUND_MUSIC_UTILITY_SCRIPT"
	)
	var style_position: int = _find_project_binding_position(
		source,
		"_GAME_UI_STYLE_UTILITY_SCRIPT"
	)
	var motion_position: int = _find_project_binding_position(
		source,
		"_GAME_UI_MOTION_UTILITY_SCRIPT"
	)
	var board_feedback_position: int = _find_project_binding_position(
		source,
		"_GAME_BOARD_FEEDBACK_UTILITY_SCRIPT"
	)

	assert_true(project_catalog_position >= 0, "项目 Installer 应注册唯一内容包目录 Utility。")
	assert_true(asset_library_position >= 0, "项目 Installer 应注册 GameAssetLibraryUtility。")
	assert_true(background_music_position >= 0, "项目 Installer 应注册本地内容包 BGM 消费者。")
	assert_true(style_position >= 0, "项目 Installer 应注册 GameUiStyleUtility。")
	assert_true(motion_position >= 0, "项目 Installer 应注册 GameUiMotionUtility。")
	assert_true(board_feedback_position >= 0, "项目 Installer 应注册 GameBoardFeedbackUtility。")
	assert_true(
		project_catalog_position < asset_library_position,
		"ProjectContentCatalogUtility 必须先于所有内容包消费者注册。"
	)
	assert_true(
		asset_library_position < style_position,
		"GameAssetLibraryUtility 必须先于读取稳定素材键的 GameUiStyleUtility 注册。"
	)
	assert_true(
		asset_library_position < background_music_position,
		"本地 BGM 必须在 GF 内容包目录与项目素材目录就绪后注册。"
	)
	assert_true(
		style_position < motion_position,
		"GameUiStyleUtility 必须先于依赖静态样式的 GameUiMotionUtility 注册。"
	)
	assert_true(
		asset_library_position < board_feedback_position,
		"GameAssetLibraryUtility 必须先于读取稳定素材键的 GameBoardFeedbackUtility 注册。"
	)


func test_runtime_content_roots_never_index_arbitrary_workstation_directories() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	for expected_root: String in [
		"res://features/asset_library/resources",
		"res://features/themes/resources",
		"user://content_packages",
	]:
		assert_true(
			source.contains("\"%s\"" % expected_root),
			"运行时内容目录应显式保留受控根：%s。" % expected_root
		)
	for workstation_prefix: String in ["C:/", "C:\\", "E:/", "E:\\"]:
		assert_false(
			source.contains(workstation_prefix),
			"Composition Root 不得索引任意工作站目录：%s。" % workstation_prefix
		)


func test_project_installer_binds_gf_standard_observability_tools_for_dev_builds() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var diagnostics_source: String = _read_text(GAME_DIAGNOSTICS_INSTALLER_PATH)
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)

	assert_true(settings_source.contains("\"gf.asset_metadata\""), "项目应启用 GF Asset Metadata 扩展。")
	assert_true(source.contains("OS.has_feature(_DEV_TOOLS_FEATURE)"), "开发工具必须由显式构建 feature 启用。")
	assert_false(source.contains("OS.is_debug_build()"), "普通 debug 运行不得自动承担 diagnostics 启动成本。")
	assert_true(source.contains("_DEV_TOOLS_INSTALLER_PATH"), "Composition Root 应按需加载 diagnostics Installer。")
	assert_true(
		_source_binds_symbol(source, "GFDiagnosticsUtility"),
		"运行时应直接绑定 GF Diagnostics 聚合核心。"
	)
	assert_false(
		source.contains("game_runtime_diagnostics_utility.gd"),
		"GF 11 已修复可选 Console 查询，运行时不得保留项目适配。"
	)
	assert_true(
		_source_binds_symbol(source, "GFSessionTraceUtility"),
		"运行时应绑定 GF 有界 Session Trace 核心。"
	)
	assert_true(
		source.contains("_GAME_PERFORMANCE_TRACE_UTILITY_SCRIPT"),
		"项目应以独立 Utility 拥有移动卡顿事件 schema 与隐私边界。"
	)
	assert_true(diagnostics_source.contains("bind_utility(GFDebugOverlayUtility)"), "开发构建应绑定 GF Debug Overlay。")
	assert_true(diagnostics_source.contains("bind_utility(GFRuntimeInspectorUtility)"), "开发构建应绑定 GF Runtime Inspector。")
	assert_true(diagnostics_source.contains("bind_utility(GFScreenshotUtility)"), "开发构建应绑定 GF Screenshot Utility。")
	assert_false(
		diagnostics_source.contains("bind_utility(GFDiagnosticsUtility)"),
		"开发包不得重复注册运行时已提供的 GF Diagnostics 别名。"
	)
	assert_false(
		_source_binds_symbol(source, "GFAssetMetadataUtility"),
		"GFAssetMetadataUtility 由 gf.asset_metadata 扩展装配，项目不得重复绑定。"
	)


func test_runtime_diagnostics_treats_console_as_optional_under_strict_lookup() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	architecture.strict_dependency_lookup = true
	var diagnostics: GFDiagnosticsUtility = GFDiagnosticsUtility.new()

	await architecture.register_utility(GFDiagnosticsUtility, diagnostics)
	var initialized: bool = await architecture.init()

	assert_true(initialized, "缺少可选 Console 时 Diagnostics 仍应完成严格初始化。")
	assert_null(
		architecture.find_utility(GFConsoleUtility),
		"发布态回归场景不得为了消除错误而安装 Console。"
	)
	assert_push_error_count(0, "GF 11 的可选 Console 查询不应产生 strict miss。")
	architecture.dispose()


func test_runtime_diagnostics_still_binds_console_when_dev_tools_install_it() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	architecture.strict_dependency_lookup = true
	var log_utility: GFLogUtility = GFLogUtility.new()
	var console: GFConsoleUtility = GFConsoleUtility.new()
	var diagnostics: GFDiagnosticsUtility = GFDiagnosticsUtility.new()

	await architecture.register_utility(GFLogUtility, log_utility)
	await architecture.register_utility(GFConsoleUtility, console)
	await architecture.register_utility(GFDiagnosticsUtility, diagnostics)
	var initialized: bool = await architecture.init()

	assert_true(initialized, "安装 Console 的开发态 Diagnostics 应完成严格初始化。")
	assert_true(
		console.get_command_names().has("diagnostics"),
		"存在本架构 Console 时 GF Diagnostics 必须保留标准命令桥。"
	)
	assert_push_error_count(0, "开发态 Console 桥接不应产生 strict miss。")
	architecture.dispose()
	await get_tree().process_frame


func test_runtime_uses_official_gf_audio_and_diagnostics_utilities() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)

	assert_true(
		_source_binds_symbol(installer_source, "GFAudioUtility"),
		"GF 11 已修复 BGM teardown，运行时应直接绑定官方 GFAudioUtility。"
	)
	assert_true(
		_source_binds_symbol(installer_source, "GFDiagnosticsUtility"),
		"GF 11 已修复可选依赖查询，运行时应直接绑定官方 GFDiagnosticsUtility。"
	)
	assert_false(
		installer_source.contains("game_audio_utility.gd"),
		"不得恢复旧版 GF 音频 teardown 适配。"
	)
	assert_false(
		installer_source.contains("game_runtime_diagnostics_utility.gd"),
		"不得恢复旧版 GF Diagnostics 适配。"
	)


func test_async_installers_check_scope_after_every_await() -> void:
	var issues: Array[String] = []
	for installer_path: String in [
		PROJECT_INSTALLER_PATH,
		GAME_DIAGNOSTICS_INSTALLER_PATH,
	]:
		var source: String = _read_text(installer_path)
		assert_true(
			source.contains("\n\tawait ") or source.contains("if not await _bind_required("),
			"%s 应至少包含一个需要取消检查的异步安装步骤。" % installer_path
		)
		for issue: String in _collect_missing_cancel_checkpoints(installer_path, source):
			_append_string(issues, issue)

	assert_true(
		issues.is_empty(),
		"GF Installer 必须在每个 await 恢复后立即检查取消作用域：\n%s"
		% _join_lines(issues)
	)


func test_required_project_singleton_results_are_centralized() -> void:
	var singleton_method_call: String = "." + "as_singleton()"
	for installer_path: String in [
		PROJECT_INSTALLER_PATH,
		GAME_DIAGNOSTICS_INSTALLER_PATH,
	]:
		var source: String = _read_text(installer_path)
		assert_false(
			source.contains(singleton_method_call),
			"%s 的必需绑定必须通过 ProjectRequiredBinding 消费 bool 终态。" % installer_path
		)
		assert_true(
			source.contains("if not await _bind_required("),
			"%s 必须在首个失败绑定后立即退出。" % installer_path
		)

	var helper_source: String = _read_text(PROJECT_REQUIRED_BINDING_PATH)
	assert_true(
		helper_source.count(singleton_method_call) == 1,
		"只有项目绑定终态 helper 可以直接提交 GF singleton 绑定。"
	)
	assert_true(
		helper_source.contains("binding_succeeded = await binding.as_singleton()")
		and helper_source.contains("if scope.is_cancel_requested():")
		and helper_source.contains("_alias_resolves_to_target(")
		and helper_source.contains("architecture.fail_initialization(failure_reason)"),
		"统一 helper 必须观察 bool、检查 scope、验证 alias 并失败候选架构。"
	)


func test_cancelled_project_installer_does_not_mutate_candidate_architecture() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var scope: GFAsyncScope = GFAsyncScope.new()
	assert_true(scope.cancel("test cancellation"), "测试应先取消 Installer scope。")
	var installer: GFInstaller = GameArchitectureInstaller.new()

	installer.install_bindings(architecture.create_binder(), scope)

	assert_null(
		architecture.get_local_model(AppConfigModel),
		"已取消的项目 Installer 不得向候选架构注册首个 Model。"
	)
	architecture.dispose()


func test_rejected_required_model_binding_fails_candidate_and_stops_later_bindings() -> void:
	var architecture: _RecordingBindingArchitecture = _RecordingBindingArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	assert_true(await architecture.register_utility(GFStorageUtility, storage))
	assert_true(await architecture.register_model(AppConfigModel, AppConfigModel.new()))
	architecture.model_binding_attempts.clear()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameArchitectureInstaller = GameArchitectureInstaller.new()
	installer.install(architecture, scope)

	await installer._bind_models(architecture.create_binder(), scope)
	assert_push_warning("类型已注册", "测试应触发真实的重复 Model 拒绝。")
	assert_push_error("必需 model 绑定失败", "项目应报告首个失败的绑定种类。")

	assert_true(scope.is_cancel_requested(), "绑定失败必须取消 Installer scope。")
	assert_true(
		architecture.model_binding_attempts == [AppConfigModel],
		"首个必需 Model 失败后不得继续尝试 GridModel。"
	)
	assert_true(architecture.has_initialization_failed(), "绑定失败必须失败候选架构。")
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("AppConfigModel"),
		"失败原因必须识别首个失败目标。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_rejected_required_utility_binding_fails_candidate_and_stops_later_bindings() -> void:
	var architecture: _RecordingBindingArchitecture = _RecordingBindingArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	assert_true(await architecture.register_utility(GFStorageUtility, storage))
	assert_true(
		await architecture.register_utility(GFResourceBroker, GFResourceBroker.new())
	)
	architecture.utility_binding_attempts.clear()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameArchitectureInstaller = GameArchitectureInstaller.new()
	installer.install(architecture, scope)

	await installer._bind_runtime_foundation_utilities(architecture.create_binder(), scope)
	assert_push_warning("类型已注册", "测试应触发真实的重复 Utility 拒绝。")
	assert_push_error("必需 utility 绑定失败", "项目应报告首个失败的绑定种类。")

	assert_true(scope.is_cancel_requested(), "绑定失败必须取消 Installer scope。")
	assert_true(
		architecture.utility_binding_attempts == [GFResourceBroker],
		"首个必需 Utility 失败后不得继续尝试 GFBackgroundWorkUtility。"
	)
	assert_true(architecture.has_initialization_failed(), "绑定失败必须失败候选架构。")
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("GFResourceBroker"),
		"失败原因必须识别首个失败目标。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_rejected_required_system_binding_fails_candidate_and_stops_later_bindings() -> void:
	var architecture: _RecordingBindingArchitecture = _RecordingBindingArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	assert_true(await architecture.register_utility(GFStorageUtility, storage))
	assert_true(await architecture.register_system(GameStateSystem, GameStateSystem.new()))
	architecture.system_binding_attempts.clear()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameArchitectureInstaller = GameArchitectureInstaller.new()
	installer.install(architecture, scope)

	await installer._bind_state_and_navigation_systems(architecture.create_binder(), scope)
	assert_push_warning("类型已注册", "测试应触发真实的重复 System 拒绝。")
	assert_push_error("必需 system 绑定失败", "项目应报告首个失败的绑定种类。")

	assert_true(scope.is_cancel_requested(), "绑定失败必须取消 Installer scope。")
	assert_true(
		architecture.system_binding_attempts == [GameStateSystem],
		"首个必需 System 失败后不得继续尝试 SceneRouterSystem。"
	)
	assert_true(architecture.has_initialization_failed(), "绑定失败必须失败候选架构。")
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("GameStateSystem"),
		"失败原因必须识别首个失败目标。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_rejected_alias_binding_fails_candidate_and_stops_later_bindings() -> void:
	var architecture: _RecordingBindingArchitecture = _RecordingBindingArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	assert_true(await architecture.register_utility(GFStorageUtility, storage))
	architecture.utility_binding_attempts.clear()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameArchitectureInstaller = GameArchitectureInstaller.new()
	installer.install(architecture, scope)
	var binder: GFBinder = architecture.create_binder()
	var incompatible_alias_binding: GFBindBuilder = binder.bind_utility(
		GFConsoleUtility
	).with_alias(
		GFSettingsStoreUtility
	)

	var alias_succeeded: bool = await installer._bind_required(
		incompatible_alias_binding,
		scope,
		&"utility",
		GFConsoleUtility,
		GFSettingsStoreUtility
	)
	if alias_succeeded:
		await installer._bind_required(
			binder.bind_utility(GFSupportReportUtility),
			scope,
			&"utility",
			GFSupportReportUtility
		)
	assert_push_error("target 必须继承或等于 alias", "测试应触发真实的 GF alias 拒绝。")
	assert_push_error("必需 utility alias 绑定失败", "项目应区分 alias 绑定失败种类。")

	assert_false(alias_succeeded, "真实 alias 拒绝必须转换为项目绑定失败。")
	assert_true(scope.is_cancel_requested(), "alias 绑定失败必须取消 Installer scope。")
	assert_true(
		architecture.utility_binding_attempts == [GFConsoleUtility],
		"首个 alias 失败后不得提交 GFSupportReportUtility。"
	)
	assert_true(architecture.has_initialization_failed(), "alias 失败必须失败候选架构。")
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("GFConsoleUtility")
		and architecture.last_initialization_error.contains("GFSettingsStoreUtility"),
		"失败原因必须同时识别首个 target 与 alias。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_rejected_diagnostics_binding_fails_candidate_and_stops_later_bindings() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameDiagnosticsInstaller = GameDiagnosticsInstaller.new()
	installer.install(architecture, scope)
	var binder: _RejectingBinder = _RejectingBinder.new(
		architecture,
		null,
		GFConsoleUtility
	)

	await installer.install_bindings(binder, scope)
	assert_push_error("必需 utility 绑定失败", "diagnostics 应报告首个失败的绑定种类。")

	assert_true(scope.is_cancel_requested(), "diagnostics 绑定失败必须取消 Installer scope。")
	assert_true(binder.binding_attempts.size() == 1, "首个 diagnostics 绑定失败后不得继续提交。")
	var raw_failed_target: Variant = binder.binding_attempts[0].get("target")
	var failed_target: Script = raw_failed_target if raw_failed_target is Script else null
	assert_same(
		failed_target,
		GFConsoleUtility,
		"diagnostics 失败记录必须识别具体绑定目标。"
	)
	assert_true(architecture.has_initialization_failed(), "diagnostics 失败必须失败候选架构。")
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("GFConsoleUtility"),
		"失败原因必须识别首个 diagnostics 目标。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_false_binding_still_fails_candidate_when_builder_cancels_scope() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)
	var initialization_failures: Array[String] = []
	var _connected_initialization_failure: int = architecture.initialization_failed.connect(
		func(reason: String) -> void:
			initialization_failures.append(reason)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameDiagnosticsInstaller = GameDiagnosticsInstaller.new()
	installer.install(architecture, scope)
	var binder: _RejectingBinder = _RejectingBinder.new(
		architecture,
		null,
		GFConsoleUtility,
		scope
	)

	await installer.install_bindings(binder, scope)
	assert_push_error("必需 utility 绑定失败", "false 终态不能被同期 scope 取消吞掉。")

	assert_true(scope.is_cancel_requested(), "Builder 先取消后 scope 必须保持取消终态。")
	assert_true(
		String(scope.get_cancel_reason()) == "builder cancelled before returning false",
		"重复 cancel 不得覆盖 scope 的首次终态原因。"
	)
	assert_true(
		architecture.has_initialization_failed(),
		"as_singleton false 即使与取消同期发生也必须失败候选架构。"
	)
	assert_true(initialization_failures.size() == 1, "候选架构只能进入一次失败终态。")
	assert_true(
		architecture.last_initialization_error.contains("GFConsoleUtility"),
		"同期取消时仍必须记录首个失败绑定目标。"
	)
	assert_false(scope.cancel("second terminal"), "Installer scope 只能进入一次取消终态。")
	architecture.dispose()


func test_project_installer_configures_extension_owned_storage_instance() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	assert_true(
		await architecture.register_utility(GFStorageUtility, storage)
	)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GFInstaller = GameArchitectureInstaller.new()

	installer.install(architecture, scope)

	assert_false(scope.is_cancel_requested())
	assert_same(
		architecture.get_local_utility(GFStorageUtility),
		storage,
		"项目 Installer 必须配置 gf.save 已注册的同一 Storage 实例。"
	)
	assert_true(storage.file_format == GFStorageCodec.Format.BINARY)
	assert_true(storage.include_storage_metadata)
	assert_true(storage.use_integrity_checksum)
	assert_true(storage.save_version == 1)
	architecture.dispose()


func test_project_installer_fails_candidate_when_save_extension_is_missing() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var scope: GFAsyncScope = GFAsyncScope.new()
	var installer: GameArchitectureInstaller = GameArchitectureInstaller.new()
	assert_true(
		architecture.begin_project_installers(),
		"测试必须真实进入 GF project installers-running 状态。"
	)

	installer.install(architecture, scope)
	assert_push_error(
		"gf.save 未提供 GFStorageUtility",
		"项目应明确报告扩展 Installer 缺失。"
	)

	assert_true(scope.is_cancel_requested())
	assert_true(
		architecture.has_initialization_failed(),
		"仅取消 GF 11 Installer scope 可能悬挂；项目必须同时失败候选架构。"
	)
	assert_false(
		architecture.is_project_installers_running(),
		"显式失败必须唤醒并清理本轮 project installers-running 状态。"
	)
	assert_true(
		architecture.begin_project_installers(),
		"失败候选必须能开始后续 Installer 重试，不能永久悬挂。"
	)
	architecture.finish_project_installers()
	architecture.dispose()


func test_save_graph_lifecycle_policy_is_configured_before_registration() -> void:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	assert_true(save_graph.ignore_pause)
	assert_true(save_graph.ignore_time_scale)
	assert_true(
		save_graph.lifecycle_priority == -100,
		"GF 11 在模块 init() 前冻结生命周期计划，SaveGraph 优先级必须在构造时生效。"
	)


func test_cancelled_diagnostics_installer_does_not_mutate_candidate_architecture() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var scope: GFAsyncScope = GFAsyncScope.new()
	assert_true(scope.cancel("test cancellation"), "测试应先取消 diagnostics scope。")
	var installer: GFInstaller = GameDiagnosticsInstaller.new()

	installer.install_bindings(architecture.create_binder(), scope)

	assert_null(
		architecture.get_local_utility(GFConsoleUtility),
		"已取消的 diagnostics Installer 不得向候选架构注册首个 Utility。"
	)
	architecture.dispose()


func test_runtime_diagnostics_baseline_is_bounded_and_dev_installer_does_not_rebind() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var diagnostics_installer_source: String = _read_text(GAME_DIAGNOSTICS_INSTALLER_PATH)
	var router_source: String = _read_text(
		"res://features/navigation/scripts/systems/scene_router_system.gd"
	)

	var dev_block_position: int = installer_source.find("if _are_dev_tools_enabled():")
	var dev_diagnostics_position: int = diagnostics_installer_source.find(
		"bind_utility(GFOperationDiagnosticsUtility)"
	)
	assert_true(dev_block_position >= 0, "项目 Installer 应声明开发工具条件块。")
	assert_true(
		installer_source.contains("GFOperationDiagnosticsUtility")
		and installer_source.contains("_create_operation_diagnostics_utility()"),
		"Composition Root 应注册无 UI、有界的运行时操作诊断基线。"
	)
	assert_true(
		installer_source.contains("max_completed_operations = 32")
		and installer_source.contains("max_active_operations = 16")
		and installer_source.contains("max_metadata_keys = 12"),
		"运行时操作诊断必须声明小容量硬预算。"
	)
	assert_true(
		dev_diagnostics_position < 0,
		"开发诊断 Installer 不得重复注册运行时操作诊断基线。"
	)
	assert_true(
		router_source.contains("get_utility(GFOperationDiagnosticsUtility)"),
		"SceneRouterSystem 应通过正式 GF 依赖声明解析运行时诊断基线。"
	)
	assert_true(
		router_source.contains("get_utility(GameClockUtility)")
		and router_source.contains("_clock_utility.get_tick_usec()"),
		"SceneRouterSystem 阶段计时应通过正式依赖解析项目共享时钟。"
	)
	assert_false(
		router_source.contains("Time.get_ticks_"),
		"SceneRouterSystem 不得绕过项目共享时钟直接读取引擎 tick。"
	)
	assert_false(
		router_source.contains(
			"architecture.get_local_utility(GFOperationDiagnosticsUtility)"
		),
		"SceneRouterSystem 不得绕过严格依赖查找隐藏 Composition Root 漏配。"
	)


func test_tile_composition_uses_capability_extension_ownership() -> void:
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)

	assert_true(settings_source.contains("\"gf.capability\""), "项目应显式启用 gf.capability 扩展。")
	assert_true(
		_source_binds_symbol(installer_source, "_TILE_COMPOSITION_UTILITY_SCRIPT"),
		"项目 Installer 应注册项目侧 TileCompositionUtility。"
	)
	assert_true(
		_source_binds_symbol(installer_source, "_TILE_CATALOG_UTILITY_SCRIPT"),
		"项目 Installer 应注册项目侧 TileCatalogUtility。"
	)
	assert_true(
		_find_project_binding_position(installer_source, "_TILE_CATALOG_UTILITY_SCRIPT")
		< _find_project_binding_position(installer_source, "_TILE_COMPOSITION_UTILITY_SCRIPT"),
		"静态方块目录必须先于运行时组合 Utility 注册。"
	)
	assert_true(
		_source_binds_symbol(installer_source, "TileDiscoverySystem"),
		"项目 Installer 应注册方块发现系统。"
	)
	assert_true(
		_source_binds_symbol(installer_source, "_ACHIEVEMENT_CATALOG_UTILITY_SCRIPT"),
		"项目 Installer 应注册项目侧 AchievementCatalogUtility。"
	)
	assert_true(
		_source_binds_symbol(installer_source, "AchievementSystem"),
		"项目 Installer 应注册成就进度系统。"
	)
	assert_false(
		_source_binds_symbol(installer_source, "GFQuestUtility"),
		"GFQuestUtility 应由 gf.domain 扩展拥有，项目不得重复绑定。"
	)
	assert_false(
		_source_binds_symbol(installer_source, "GFCapabilityUtility"),
		"GFCapabilityUtility 应由 gf.capability 扩展拥有，项目不得重复绑定。"
	)


func test_transient_feedback_uses_gf_notification_utility_only() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var controller_source: String = _read_text(GAME_PLAY_CONTROLLER_PATH)
	var scene_source: String = _read_text(GAME_PLAY_SCENE_PATH)
	var status_source: String = _read_text(GAME_STATUS_MODEL_PATH)
	var game_state_source: String = _read_text(GAME_STATE_SYSTEM_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var input_source: String = _read_text(PLAYER_INPUT_SYSTEM_PATH)
	var hud_source: String = _read_text(HUD_PATH)
	var bookmark_source: String = _read_text(BOOKMARK_DATA_PATH)

	assert_true(
		_source_binds_symbol(installer_source, "GFNotificationUtility"),
		"项目 Installer 应注册 GFNotificationUtility。"
	)
	assert_true(flow_source.contains("push_notification("), "游戏流程反馈应写入 GF 通知队列。")
	assert_true(input_source.contains("push_notification("), "输入反馈应写入 GF 通知队列。")
	assert_true(hud_source.contains("notification_started"), "HUD 应消费 GF 通知生命周期信号。")
	assert_false(FileAccess.file_exists(REMOVED_HUD_PAYLOAD_PATH), "不得保留重复的 HudMessagePayload 协议。")
	assert_false(scene_source.contains("HUDMessageTimer"), "通知超时应由 GFNotificationUtility 管理。")
	assert_false(controller_source.contains("HudMessagePayload"), "游戏控制器不得承担通知队列职责。")
	assert_false(status_source.contains("status_message"), "瞬时通知不得进入运行时统计 Model。")
	assert_false(game_state_source.contains("status_message"), "瞬时通知不得进入撤销或书签状态快照。")
	assert_false(bookmark_source.contains("status_message"), "瞬时通知不得进入书签 schema。")


func test_hud_delegates_feedback_motion_to_game_ui_motion_utility() -> void:
	var source: String = _read_text(HUD_PATH)

	assert_true(source.contains("get_utility(GameUiMotionUtility)"), "HUD 应从 GF Architecture 获取统一 UI 动效 Utility。")
	assert_true(source.contains("play_control_pulse("), "HUD 应通过 GameUiMotionUtility 表达状态强调意图。")
	assert_false(source.contains("create_tween()"), "HUD 不得重复实现控件 Tween 生命周期。")
	assert_false(source.contains("_hud_feedback_tween"), "HUD 不得保留私有 Tween 元数据协议。")


func test_move_turn_pipeline_uses_gf_turn_action_lifecycle() -> void:
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var turn_source: String = _read_text(GAME_TURN_SYSTEM_PATH)
	var action_source: String = _read_text(GAME_MOVE_TURN_ACTION_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var rule_source: String = _read_text(RULE_SYSTEM_PATH)
	var event_source: String = _read_text(EVENT_NAMES_PATH)

	assert_true(settings_source.contains("\"gf.turn_based\""), "项目应显式启用 gf.turn_based 扩展。")
	assert_true(
		_source_binds_symbol(installer_source, "GameTurnSystem"),
		"项目 Installer 应注册移动回合 Adapter。"
	)
	assert_true(turn_source.contains("get_system(GFTurnFlowSystem)"), "回合 Adapter 应使用扩展拥有的 GFTurnFlowSystem。")
	assert_true(turn_source.contains("enqueue_action(GameMoveTurnAction.new"), "有效移动应进入 GF 回合行动队列。")
	assert_true(turn_source.contains("resolve_actions()"), "回合行动只能由 GFTurnFlowSystem 解析。")
	assert_true(action_source.contains("extends GFTurnAction"), "移动回合应实现强类型 GFTurnAction。")
	assert_true(action_source.contains("_inject_dependencies"), "移动回合依赖应由 GF Flow 注入。")
	assert_true(action_source.contains("_rule_system.execute_move_rules"), "移动回合 Action 必须执行项目规则链。")
	assert_false(flow_source.contains("register_event(TurnResult"), "GameFlowSystem 不得旁路 GF 回合行动消费结果。")
	assert_false(rule_source.contains("register_event(TurnResult"), "RuleSystem 不得旁路 GF 回合行动消费结果。")
	assert_false(event_source.contains("TURN_FINISHED"), "不得保留重复的 TURN_FINISHED 项目事件协议。")


func test_required_gf_modules_have_no_manual_runtime_fallbacks() -> void:
	var board_source: String = _read_text(GAME_BOARD_CONTROLLER_PATH)
	var controller_source: String = _read_text(GAME_PLAY_CONTROLLER_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var init_source: String = _read_text(GAME_INIT_SYSTEM_PATH)
	var router_source: String = _read_text(SCENE_ROUTER_SYSTEM_PATH)
	var mode_selection_source: String = _read_text(MODE_SELECTION_PATH)
	var diagnostics_source: String = _read_text(GAME_DIAGNOSTICS_UTILITY_PATH)
	var settings_source: String = _read_text(SETTINGS_MENU_PATH)
	var ui_controller_source: String = _read_text(GAME_UI_CONTROLLER_PATH)
	var theme_catalog_source: String = _read_text(THEME_CATALOG_UTILITY_PATH)
	var theme_source: String = _read_text(THEME_UTILITY_PATH)
	var project_content_catalog_source: String = _read_text(PROJECT_CONTENT_CATALOG_UTILITY_PATH)

	assert_true(board_source.contains("_has_required_dependencies"), "棋盘控制器应显式校验 GF 必需依赖。")
	assert_false(board_source.contains("TileScene.instantiate()"), "Tile 只能通过 GFObjectPoolUtility 获取。")
	assert_false(
		board_source.contains("_pool.prewarm(TileScene"),
		"最多 128 个 Tile 的对象池预热不得在棋盘初始化帧同步完成。"
	)
	assert_true(
		board_source.contains("_pool.prewarm_async_budget("),
		"棋盘应使用 GFObjectPoolUtility 的逐帧预算预热。"
	)
	assert_false(board_source.contains("undo_action.execute()"), "视觉 Action 只能由 GFActionQueueSystem 执行。")
	assert_true(router_source.contains("_has_required_dependencies"), "场景路由应显式校验 GF 必需依赖。")
	assert_false(router_source.contains("change_scene_to_packed("), "场景切换不能绕过 GFSceneUtility。")
	assert_false(router_source.contains("scene_switch_started.connect("), "跨生命周期信号只能由 GFSignalUtility 管理。")
	assert_false(controller_source.contains("func _get_ui_utility"), "游戏控制器不得保留 GFUIUtility 兼容入口。")
	assert_false(controller_source.contains(".pop_panel("), "游戏控制器只能通过 GFUIRouterUtility 关闭面板。")
	assert_true(ui_controller_source.contains("_close_current_popup_route_and_send_event"), "游戏菜单应捕获架构、关闭自身 GF UI 路由后再派发业务事件。")
	assert_false(flow_source.contains("GFUIUtility"), "GameFlowSystem 不得拥有表现层 UI 栈。")
	assert_false(flow_source.contains(".clear_all("), "业务系统不得越权清空 UI 栈。")
	assert_false(init_source.contains("elif is_instance_valid(_command_history)"), "关卡清理不得绕过 GFLevelUtility。")
	assert_false(settings_source.contains("TranslationServer.set_locale("), "设置写入不得绕过 GFDisplaySettingsUtility。")
	assert_false(settings_source.contains("DisplayServer.window_get_mode("), "设置读取不得绕过 GFDisplaySettingsUtility。")
	assert_false(settings_source.contains("DisplayServer.window_get_vsync_mode("), "垂直同步读取不得绕过 GFDisplaySettingsUtility。")
	assert_false(settings_source.contains("func _get_ui_utility"), "设置菜单不得保留 GFUIUtility 兼容入口。")
	assert_false(theme_catalog_source.contains("register_source_root("), "主题 Feature 不得修改 GF 全局内容包目录。")
	assert_false(theme_catalog_source.contains("rebuild_catalog("), "主题 Feature 不得重复重建 GF 内容包目录。")
	assert_false(theme_source.contains("register_audio_bank("), "声音主题应使用 GF 挂载令牌，而不是永久注册银行。")
	assert_true(theme_source.contains("GFActivationTransaction"), "主题切换应使用 GF 激活事务。")
	assert_true(project_content_catalog_source.contains("rebuild_catalog("), "项目内容目录 Module 应独占 GF 目录重建职责。")
	assert_true(mode_selection_source.contains("GFSeedUtility.make_stable_seed("), "模式种子应通过 GF 稳定种子算法派生。")
	assert_true(mode_selection_source.contains("seed_utility.next_uint32()"), "模式种子应消费 GF 管理的随机流。")
	assert_true(diagnostics_source.contains("_clock_utility.get_unix_timestamp()"), "支持报告文件名应使用项目 wall-clock Adapter。")
	assert_true(router_source.contains("_operation_diagnostics.get_operation("), "场景耗时应复用 GF 操作诊断记录的起始时间。")


# --- 私有/辅助方法 ---

func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _collect_missing_cancel_checkpoints(path: String, source: String) -> Array[String]:
	var issues: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if not line.begins_with("await "):
			continue
		var checkpoint_index: int = _find_next_code_line(lines, line_index + 1)
		var checkpoint: String = _get_packed_line(lines, checkpoint_index).strip_edges()
		if checkpoint != "if scope.is_cancel_requested():":
			_append_string(
				issues,
				"%s:%d 的 await 后缺少 scope.is_cancel_requested()。"
				% [path, line_index + 1]
			)
			continue
		var return_index: int = _find_next_code_line(lines, checkpoint_index + 1)
		if _get_packed_line(lines, return_index).strip_edges() != "return":
			_append_string(
				issues,
				"%s:%d 的取消检查未立即退出 Installer。"
				% [path, checkpoint_index + 1]
			)
	return issues


func _find_next_code_line(lines: PackedStringArray, start_index: int) -> int:
	for line_index: int in range(start_index, lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if not line.is_empty() and not line.begins_with("#"):
			return line_index
	return -1


func _source_binds_symbol(source: String, symbol: String) -> bool:
	return _find_project_binding_position(source, symbol) >= 0


func _find_project_binding_position(source: String, symbol: String) -> int:
	var binding_function_name: String = "_bind_" + "models"
	var bindings_start: int = source.find("func %s(" % binding_function_name)
	var bindings_end: int = source.find("func _configure_storage_utility(", bindings_start)
	if bindings_start < 0 or bindings_end < 0:
		return -1
	var symbol_position: int = source.find(symbol, bindings_start)
	if symbol_position < 0 or symbol_position >= bindings_end:
		return -1
	return symbol_position


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_dictionary_text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: Variant = fallback
	if source.has(key):
		value = source[key]
	return GFVariantData.to_text(value, fallback)


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var _append_result: bool = packed.append(line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


# --- 内部类 ---

class _RecordingBindingArchitecture extends GFArchitecture:
	var model_binding_attempts: Array[Script] = []
	var utility_binding_attempts: Array[Script] = []
	var system_binding_attempts: Array[Script] = []

	## @param instance: 要记录并交给 GF 注册的 Model 实例。
	func register_model_instance(instance: Object) -> bool:
		var raw_script: Variant = instance.get_script()
		var instance_script: Script = raw_script if raw_script is Script else null
		model_binding_attempts.append(instance_script)
		return await super.register_model_instance(instance)

	## @param instance: 要记录并交给 GF 注册的 Utility 实例。
	func register_utility_instance(instance: Object) -> bool:
		var raw_script: Variant = instance.get_script()
		var instance_script: Script = raw_script if raw_script is Script else null
		utility_binding_attempts.append(instance_script)
		return await super.register_utility_instance(instance)

	## @param instance: 要记录并交给 GF 注册的 System 实例。
	func register_system_instance(instance: Object) -> bool:
		var raw_script: Variant = instance.get_script()
		var instance_script: Script = raw_script if raw_script is Script else null
		system_binding_attempts.append(instance_script)
		return await super.register_system_instance(instance)


class _AliasPlanBindBuilder extends GFBindBuilder:
	var _binding_attempts: Array[Dictionary] = []
	var _rejected_alias: Script = null
	var _rejected_target: Script = null
	var _scope_to_cancel: GFAsyncScope = null
	var _target_script: Script = null
	var _alias_script: Script = null

	func _init(
		architecture: GFArchitecture,
		binding_attempts: Array[Dictionary],
		rejected_alias: Script,
		rejected_target: Script,
		scope_to_cancel: GFAsyncScope,
		target_script: Script
	) -> void:
		super(architecture, GFBindBuilder.TargetKind.UTILITY, target_script)
		_binding_attempts = binding_attempts
		_rejected_alias = rejected_alias
		_rejected_target = rejected_target
		_scope_to_cancel = scope_to_cancel
		_target_script = target_script

	## @param _unused_instance: 测试不使用的绑定实例。
	func from_instance(_unused_instance: Object) -> GFBindBuilder:
		return self

	## @param alias_script: 要记录到绑定尝试中的查询 alias。
	func with_alias(alias_script: Script) -> GFBindBuilder:
		_alias_script = alias_script
		return self

	func as_singleton() -> bool:
		_binding_attempts.append({
			"target": _target_script,
			"alias": _alias_script,
		})
		var binding_succeeded: bool = (
			(_rejected_alias == null or _alias_script != _rejected_alias)
			and (_rejected_target == null or _target_script != _rejected_target)
		)
		if not binding_succeeded and _scope_to_cancel != null:
			var _cancelled_before_failure: bool = _scope_to_cancel.cancel(
				"builder cancelled before returning false"
			)
		return binding_succeeded


class _RejectingBinder extends GFBinder:
	var binding_attempts: Array[Dictionary] = []
	var rejected_alias: Script = null
	var rejected_target: Script = null
	var scope_to_cancel: GFAsyncScope = null
	var _candidate_architecture: GFArchitecture = null

	func _init(
		architecture: GFArchitecture,
		alias_script: Script,
		target_script: Script = null,
		cancel_scope: GFAsyncScope = null
	) -> void:
		super(architecture)
		_candidate_architecture = architecture
		rejected_alias = alias_script
		rejected_target = target_script
		scope_to_cancel = cancel_scope

	## @param script_cls: 要创建记录型 Builder 的 Utility 目标。
	func bind_utility(script_cls: Script) -> GFBindBuilder:
		return _AliasPlanBindBuilder.new(
			_candidate_architecture,
			binding_attempts,
			rejected_alias,
			rejected_target,
			scope_to_cancel,
			script_cls
		)
