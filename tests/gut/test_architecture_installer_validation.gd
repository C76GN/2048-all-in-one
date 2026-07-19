## 验证项目 Installer 不重复装配 GF 扩展已拥有的 Module。
extends GutTest


# --- 常量 ---

const PROJECT_INSTALLER_PATH: String = "res://app/scripts/game_architecture_installer.gd"
const GAME_BOARD_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_board_controller.gd"
const GAME_PLAY_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_play_controller.gd"
const GAME_PLAY_SCENE_PATH: String = "res://features/gameplay/scenes/game/game_play.tscn"
const GAME_STATUS_MODEL_PATH: String = "res://features/gameplay/scripts/models/game_status_model.gd"
const GAME_STATE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_state_system.gd"
const GAME_FLOW_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_flow_system.gd"
const GAME_PAUSE_UTILITY_PATH: String = "res://features/gameplay/scripts/utilities/game_pause_utility.gd"
const GAME_BOARD_ANIMATION_UTILITY_PATH: String = "res://features/gameplay/scripts/utilities/game_board_animation_utility.gd"
const GAME_INPUT_PROFILE_UTILITY_PATH: String = "res://features/settings/scripts/utilities/game_input_profile_utility.gd"
const GAME_INIT_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_init_system.gd"
const GAME_TURN_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_turn_system.gd"
const GAME_MOVE_TURN_ACTION_PATH: String = "res://features/gameplay/scripts/actions/game_move_turn_action.gd"
const RULE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/rule_system.gd"
const PLAYER_INPUT_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/player_input_system.gd"
const HUD_PATH: String = "res://features/gameplay/scripts/ui/hud.gd"
const BOOKMARK_DATA_PATH: String = "res://features/bookmarks/scripts/data/bookmark_data.gd"
const REMOVED_HUD_PAYLOAD_PATH: String = "res://features/gameplay/scripts/events/hud_message_payload.gd"
const SCENE_ROUTER_SYSTEM_PATH: String = "res://features/navigation/scripts/systems/scene_router_system.gd"
const BASE_LIST_MENU_PATH: String = "res://features/navigation/scripts/menus/base_list_menu.gd"
const MODE_SELECTION_PATH: String = "res://features/navigation/scripts/menus/mode_selection.gd"
const GAME_DIAGNOSTICS_UTILITY_PATH: String = "res://features/diagnostics/scripts/utilities/game_diagnostics_utility.gd"
const SETTINGS_MENU_PATH: String = "res://features/settings/scripts/menus/settings_menu.gd"
const GAME_UI_CONTROLLER_PATH: String = "res://features/themes/scripts/ui/game_ui_controller.gd"
const THEME_CATALOG_UTILITY_PATH: String = "res://features/themes/scripts/utilities/game_theme_catalog_utility.gd"
const THEME_UTILITY_PATH: String = "res://features/themes/scripts/utilities/game_theme_utility.gd"
const PROJECT_CONTENT_CATALOG_UTILITY_PATH: String = "res://shared/scripts/utilities/project_content_catalog_utility.gd"
const EVENT_NAMES_PATH: String = "res://shared/scripts/contracts/event_names.gd"
const PROJECT_SETTINGS_PATH: String = "res://project.godot"
const EXTENSION_OWNED_MODULES: Array[Dictionary] = [
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
	var signal_position: int = source.find("bind_utility(GFSignalUtility)")
	var theme_position: int = source.find("bind_utility(_GAME_THEME_UTILITY_SCRIPT)")

	assert_true(signal_position >= 0, "项目 Installer 应注册 GFSignalUtility。")
	assert_true(theme_position >= 0, "项目 Installer 应注册 GameThemeUtility。")
	assert_true(
		signal_position < theme_position,
		"GFSignalUtility 必须先于依赖它的 GameThemeUtility 注册。"
	)


func test_project_installer_binds_input_device_before_input_mapping() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var device_position: int = source.find("bind_utility(GFInputDeviceUtility)")
	var mapping_position: int = source.find("bind_utility(GFInputMappingUtility)")

	assert_true(device_position >= 0, "项目 Installer 应注册 GFInputDeviceUtility。")
	assert_true(mapping_position >= 0, "项目 Installer 应注册 GFInputMappingUtility。")
	assert_true(
		device_position < mapping_position,
		"GFInputDeviceUtility 必须先于依赖它的 GFInputMappingUtility 注册。"
	)


func test_project_installer_orders_input_profile_and_board_animation_adapters() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var input_mapping_position: int = installer_source.find("bind_utility(GFInputMappingUtility)")
	var input_profile_position: int = installer_source.find(
		"bind_utility(_GAME_INPUT_PROFILE_UTILITY_SCRIPT)"
	)
	var board_animation_position: int = installer_source.find(
		"bind_utility(_GAME_BOARD_ANIMATION_UTILITY_SCRIPT)"
	)
	var input_profile_source: String = _read_text(GAME_INPUT_PROFILE_UTILITY_PATH)
	var board_animation_source: String = _read_text(GAME_BOARD_ANIMATION_UTILITY_PATH)

	assert_true(input_profile_position > input_mapping_position, "输入覆盖 Adapter 必须在 GF 映射工具之后注册。")
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
	var viewport_position: int = source.find("bind_utility(GFViewportUtility)")
	var http_position: int = source.find("bind_utility(GFHttpClientUtility)")
	var gesture_position: int = source.find("bind_utility(GFPointerGestureUtility)")
	var platform_position: int = source.find("bind_utility(_GAME_PLATFORM_UTILITY_SCRIPT)")

	assert_true(viewport_position >= 0, "项目 Installer 应注册 GFViewportUtility。")
	assert_true(http_position >= 0, "项目 Installer 应注册 GFHttpClientUtility。")
	assert_true(gesture_position >= 0, "项目 Installer 应注册 GFPointerGestureUtility。")
	assert_true(platform_position >= 0, "项目 Installer 应注册 GamePlatformUtility。")
	assert_true(viewport_position < platform_position, "显示能力应先于项目平台边界注册。")
	assert_true(http_position < platform_position, "HTTP 能力应先于项目平台边界注册。")
	assert_true(gesture_position < platform_position, "手势能力应先于项目平台边界注册。")


func test_project_installer_binds_pause_adapter_after_gf_time_provider() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var time_position: int = source.find("bind_utility(GFTimeUtility)")
	var pause_position: int = source.find("bind_utility(_GAME_PAUSE_UTILITY_SCRIPT)")

	assert_true(time_position >= 0, "项目 Installer 应注册 GFTimeUtility。")
	assert_true(pause_position >= 0, "项目 Installer 应注册 GamePauseUtility。")
	assert_true(
		time_position < pause_position,
		"GFTimeUtility 必须先于同步逻辑时间的 GamePauseUtility 注册。"
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
	var list: VBoxContainer = VBoxContainer.new()
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
	assert_true(first_card.get_node_or_null(first_card.focus_neighbor_bottom) == last_card, "模式卡应按 GF 顺序向下移动。")
	assert_true(last_card.get_node_or_null(last_card.focus_neighbor_bottom) == previous_page, "末张模式卡向下应进入分页。")
	assert_true(previous_page.get_node_or_null(previous_page.focus_neighbor_bottom) == back, "分页向下应闭环到返回键。")
	assert_true(next_page.get_node_or_null(next_page.focus_neighbor_top) == last_card, "下一页按钮向上应回到末张模式卡。")
	assert_true(first_card.get_node_or_null(first_card.focus_neighbor_right) == grid_size, "模式卡向右应进入配置列。")


func test_project_installer_binds_asset_library_before_ui_consumers() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var project_catalog_position: int = source.find("bind_utility(_PROJECT_CONTENT_CATALOG_UTILITY_SCRIPT)")
	var asset_library_position: int = source.find("bind_utility(_GAME_ASSET_LIBRARY_UTILITY_SCRIPT)")
	var style_position: int = source.find("bind_utility(_GAME_UI_STYLE_UTILITY_SCRIPT)")
	var motion_position: int = source.find("bind_utility(_GAME_UI_MOTION_UTILITY_SCRIPT)")
	var board_feedback_position: int = source.find("bind_utility(_GAME_BOARD_FEEDBACK_UTILITY_SCRIPT)")

	assert_true(project_catalog_position >= 0, "项目 Installer 应注册唯一内容包目录 Utility。")
	assert_true(asset_library_position >= 0, "项目 Installer 应注册 GameAssetLibraryUtility。")
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
		style_position < motion_position,
		"GameUiStyleUtility 必须先于依赖静态样式的 GameUiMotionUtility 注册。"
	)
	assert_true(
		asset_library_position < board_feedback_position,
		"GameAssetLibraryUtility 必须先于读取稳定素材键的 GameBoardFeedbackUtility 注册。"
	)


func test_project_installer_binds_gf_standard_observability_tools_for_dev_builds() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)

	assert_true(settings_source.contains("\"gf.asset_metadata\""), "项目应启用 GF Asset Metadata 扩展。")
	assert_true(source.contains("bind_utility(GFDebugOverlayUtility)"), "开发构建应绑定 GF Debug Overlay。")
	assert_true(source.contains("bind_utility(GFRuntimeInspectorUtility)"), "开发构建应绑定 GF Runtime Inspector。")
	assert_true(source.contains("bind_utility(GFScreenshotUtility)"), "开发构建应绑定 GF Screenshot Utility。")
	assert_false(
		_source_binds_symbol(source, "GFAssetMetadataUtility"),
		"GFAssetMetadataUtility 由 gf.asset_metadata 扩展装配，项目不得重复绑定。"
	)


func test_release_scene_router_only_uses_local_lookup_for_optional_diagnostics() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var router_source: String = _read_text(
		"res://features/navigation/scripts/systems/scene_router_system.gd"
	)

	var dev_block_position: int = installer_source.find("if _are_dev_tools_enabled():")
	var diagnostics_position: int = installer_source.find(
		"bind_utility(GFOperationDiagnosticsUtility)"
	)
	assert_true(dev_block_position >= 0, "项目 Installer 应声明开发工具条件块。")
	assert_true(
		diagnostics_position > dev_block_position,
		"GFOperationDiagnosticsUtility 只能在开发工具条件块中注册。"
	)
	assert_true(
		router_source.contains(
			"architecture.get_local_utility(GFOperationDiagnosticsUtility)"
		),
		"发布态可选诊断依赖必须使用 GF 本架构 local lookup。"
	)
	assert_false(
		router_source.contains("get_utility(GFOperationDiagnosticsUtility)"),
		"SceneRouterSystem 不得把开发期诊断工具当作严格运行时依赖。"
	)


func test_tile_composition_uses_capability_extension_ownership() -> void:
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)

	assert_true(settings_source.contains("\"gf.capability\""), "项目应显式启用 gf.capability 扩展。")
	assert_true(
		installer_source.contains("bind_utility(_TILE_COMPOSITION_UTILITY_SCRIPT)"),
		"项目 Installer 应注册项目侧 TileCompositionUtility。"
	)
	assert_true(
		installer_source.contains("bind_utility(_TILE_CATALOG_UTILITY_SCRIPT)"),
		"项目 Installer 应注册项目侧 TileCatalogUtility。"
	)
	assert_true(
		installer_source.find("bind_utility(_TILE_CATALOG_UTILITY_SCRIPT)")
		< installer_source.find("bind_utility(_TILE_COMPOSITION_UTILITY_SCRIPT)"),
		"静态方块目录必须先于运行时组合 Utility 注册。"
	)
	assert_true(
		installer_source.contains("bind_system(TileDiscoverySystem)"),
		"项目 Installer 应注册方块发现系统。"
	)
	assert_true(
		installer_source.contains("bind_utility(_ACHIEVEMENT_CATALOG_UTILITY_SCRIPT)"),
		"项目 Installer 应注册项目侧 AchievementCatalogUtility。"
	)
	assert_true(
		installer_source.contains("bind_system(AchievementSystem)"),
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

	assert_true(installer_source.contains("bind_utility(GFNotificationUtility)"), "项目 Installer 应注册 GFNotificationUtility。")
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
	assert_true(installer_source.contains("bind_system(GameTurnSystem)"), "项目 Installer 应注册移动回合 Adapter。")
	assert_true(turn_source.contains("get_system(GFTurnFlowSystem)"), "回合 Adapter 应使用扩展拥有的 GFTurnFlowSystem。")
	assert_true(turn_source.contains("enqueue_action(GameMoveTurnAction.new"), "有效移动应进入 GF 回合行动队列。")
	assert_true(turn_source.contains("resolve_actions()"), "回合行动只能由 GFTurnFlowSystem 解析。")
	assert_true(action_source.contains("extends GFTurnAction"), "移动回合应实现强类型 GFTurnAction。")
	assert_true(action_source.contains("_inject_dependencies"), "移动回合依赖应由 GF Flow 注入。")
	assert_true(action_source.contains("_rule_system.execute_move_rules"), "移动回合 Action 必须执行项目规则链。")
	assert_false(flow_source.contains("register_event(MoveData"), "GameFlowSystem 不得旁路 GF 回合行动消费移动。")
	assert_false(rule_source.contains("register_event(MoveData"), "RuleSystem 不得旁路 GF 回合行动消费移动。")
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


func _source_binds_symbol(source: String, symbol: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if line.begins_with("#"):
			continue
		if _line_binds_symbol(line, symbol):
			return true
	return false


func _line_binds_symbol(line: String, symbol: String) -> bool:
	var bind_patterns: Array[String] = [
		"bind_utility(%s" % symbol,
		"bind_system(%s" % symbol,
		"register_utility(%s" % symbol,
		"register_system(%s" % symbol,
		"register_utility_instance(%s.new()" % symbol,
		"register_system_instance(%s.new()" % symbol,
	]
	for pattern: String in bind_patterns:
		if line.contains(pattern):
			return true
	return false


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
