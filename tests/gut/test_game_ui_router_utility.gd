## 验证项目 UI 路由表通过 GFUIRouterUtility 暴露。
extends GutTest


# --- 常量 ---

const EXPECTED_UI_ROUTE_PATHS: Array[String] = [
	"res://features/navigation/resources/ui_routes/pause_menu_route.tres",
	"res://features/navigation/resources/ui_routes/game_over_menu_route.tres",
	"res://features/navigation/resources/ui_routes/target_reached_menu_route.tres",
	"res://features/navigation/resources/ui_routes/settings_menu_route.tres",
	"res://features/navigation/resources/ui_routes/tile_catalog_route.tres",
	"res://features/navigation/resources/ui_routes/tile_lab_route.tres",
	"res://features/navigation/resources/ui_routes/player_profile_route.tres",
	"res://features/navigation/resources/ui_routes/achievements_route.tres",
	"res://features/navigation/resources/ui_routes/board_editor_route.tres",
	"res://features/navigation/resources/ui_routes/modal_dialog_route.tres",
]

const EXPECTED_UI_ROUTE_RESOURCE_KEYS: Array[String] = [
	"game.ui_route.pause_menu",
	"game.ui_route.game_over_menu",
	"game.ui_route.target_reached_menu",
	"game.ui_route.settings_menu",
	"game.ui_route.tile_catalog",
	"game.ui_route.tile_lab",
	"game.ui_route.player_profile",
	"game.ui_route.achievements",
	"game.ui_route.board_editor",
	"game.ui_route.modal_dialog",
]


# --- 测试用例 ---

func test_game_ui_router_registers_project_panel_routes() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameUiRouterUtility, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, GameUiRouterUtility)
	await architecture.init()

	var route_ids: Array[String] = _packed_strings_to_array(ui_router.get_route_ids())
	var expected_route_ids: Array[String] = [
		"achievements",
		"board_editor",
		"game_over_menu",
		"modal_dialog",
		"pause_menu",
		"player_profile",
		"settings_menu",
		"target_reached_menu",
		"tile_catalog",
		"tile_lab",
	]
	assert_true(route_ids == expected_route_ids, "项目 UI 路由应提供稳定 route_id。")
	assert_true(
		ui_router.get_route(&"pause_menu").scene_path == "res://features/gameplay/scenes/ui/pause_menu.tscn",
		"暂停菜单路由应指向暂停面板。"
	)
	assert_true(
		ui_router.get_route(&"game_over_menu").scene_path == "res://features/gameplay/scenes/ui/game_over_menu.tscn",
		"游戏结束路由应指向游戏结束面板。"
	)
	assert_true(
		ui_router.get_route(&"target_reached_menu").scene_path == "res://features/gameplay/scenes/ui/target_reached_menu.tscn",
		"目标达成路由应指向目标达成面板。"
	)
	assert_true(
		ui_router.get_route(&"settings_menu").scene_path == "res://features/settings/scenes/menus/settings_menu.tscn",
		"设置路由应指向设置菜单。"
	)
	assert_true(
		ui_router.get_route(&"board_editor").scene_path == "res://features/board_editor/scenes/ui/board_editor_dialog.tscn",
		"棋盘编辑器路由应指向 board_editor Feature 面板。"
	)
	assert_true(
		ui_router.get_route(&"tile_catalog").scene_path == "res://features/tile_catalog/scenes/ui/tile_catalog_dialog.tscn",
		"方块图鉴路由应指向 tile_catalog Feature 面板。"
	)
	assert_true(
		ui_router.get_route(&"tile_lab").scene_path == "res://features/tile_lab/scenes/ui/tile_lab_dialog.tscn",
		"方块试验台路由应指向 tile_lab Feature 面板。"
	)
	assert_true(
		ui_router.get_route(&"player_profile").scene_path == "res://features/player_profiles/scenes/ui/player_profile_dialog.tscn",
		"玩家档案路由应指向 player_profiles Feature 面板。"
	)
	assert_true(
		ui_router.get_route(&"achievements").scene_path == "res://features/achievements/scenes/ui/achievement_list_dialog.tscn",
		"成就路由应指向 achievements Feature 面板。"
	)
	assert_true(
		ui_router.get_route(&"modal_dialog").scene_path
		== "res://features/navigation/scenes/ui/game_modal_route_panel.tscn",
		"通用 modal 必须拥有稳定的项目路由。"
	)
	assert_true(
		ui_router.get_route(&"pause_menu").get_adjacent_route_ids() == PackedStringArray(
			["settings_menu"]
		),
		"暂停菜单应声明设置页为相邻预加载路由。"
	)
	assert_true(
		ui_router.get_route(&"tile_catalog").get_adjacent_route_ids().is_empty(),
		"没有页内互跳入口的收藏弹层不得伪造相邻关系并阻塞预载其他三页。"
	)
	for modal_route_id: StringName in [
		&"pause_menu",
		&"game_over_menu",
		&"target_reached_menu",
		&"settings_menu",
	]:
		var modal_route: GFUIRoute = ui_router.get_route(modal_route_id)
		var options: Dictionary = modal_route.default_options
		assert_true(
			GFVariantData.get_option_bool(options, "modal"),
			"游戏内弹层必须声明 GF modal 策略：%s。" % modal_route_id
		)
		assert_true(GFVariantData.get_option_bool(options, "focus_on_open"))
		assert_true(GFVariantData.get_option_bool(options, "restore_focus_on_close"))
		assert_false(GFVariantData.get_option_bool(options, "hide_under", true))
	var hub_route_plan: Dictionary = ui_router.build_preload_plan(
		&"tile_catalog",
		{
			"max_depth": 1,
			"max_routes": 4,
			"include_source": true,
			"check_exists": true,
		}
	)
	var hub_scene_paths: PackedStringArray = (
		GFVariantData.get_option_packed_string_array(hub_route_plan, "scene_paths")
	)
	assert_true(
		hub_scene_paths == PackedStringArray(
			["res://features/tile_catalog/scenes/ui/tile_catalog_dialog.tscn"]
		),
		"主菜单弹层首开预载计划应只等待当前页面。"
	)

	architecture.dispose()
	await get_tree().process_frame


func test_owned_async_route_returns_typed_terminal_result() -> void:
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()

	var result: GFUIRouteResult = await ui_router.push_owned_route_async(
		self,
		&"missing_test_route"
	)

	assert_not_null(result, "异步路由应对立即失败也返回类型化终态。")
	assert_false(result.is_successful(), "缺失路由不能报告成功。")
	assert_true(result.get_status() == GFUIRouteResult.STATUS_MISSING_ROUTE)
	assert_true(result.get_reason() == &"missing_route")


func test_modal_adapter_rejects_non_closing_terminal_actions() -> void:
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()
	var config: GFModalConfig = GFModalConfig.new()
	var action: GFModalAction = GFModalAction.new()
	action.action_id = &"preview"
	action.label = "预览"
	action.close_on_pressed = false
	config.actions = [action]

	var result: GFModalResult = await ui_router.show_modal_async(self, config)

	assert_not_null(result)
	assert_true(result.status == GFModalResult.STATUS_DISMISSED)
	assert_true(result.action_id == &"preview")
	assert_true(
		GFVariantData.get_option_string_name(
			result.metadata,
			&"reason"
		) == &"unsupported_non_closing_action",
		"一次性 GFModalResult 适配器必须在开栈前拒绝无法关闭的动作。"
	)


func test_modal_adapter_rejects_config_without_any_terminal_path() -> void:
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()
	var config: GFModalConfig = GFModalConfig.new()
	config.dismiss_on_cancel = false
	config.dismiss_on_backdrop = false

	var result: GFModalResult = await ui_router.show_modal_async(self, config)

	assert_not_null(result)
	assert_true(result.status == GFModalResult.STATUS_DISMISSED)
	assert_true(
		GFVariantData.get_option_string_name(
			result.metadata,
			&"reason"
		) == &"no_terminal_action",
		"没有按钮、取消或背景终止路径的配置必须在开栈前失败。"
	)


func test_modal_result_resumes_only_after_router_history_is_settled() -> void:
	var stack: _RouterTestStack = await _make_live_router_stack()
	var first_state: _ModalWaitState = _ModalWaitState.new()
	var second_state: _ModalWaitState = _ModalWaitState.new()
	var config: GFModalConfig = GameUiRouterUtility.make_acknowledgement_modal_config(
		"路由历史",
		"关闭后立即打开同一路由。",
		"继续"
	)
	call_deferred(
		&"_run_modal_reopen_sequence",
		stack,
		config,
		first_state,
		second_state
	)
	var first_panel: GameModalRoutePanel = await _wait_for_top_modal(
		stack
	)
	assert_not_null(
		first_panel,
		"首个真实 modal 必须打开；done=%s result=%s" % [
			first_state.done,
			first_state.result.to_dict() if first_state.result != null else {},
		]
	)
	if first_panel == null:
		stack.architecture.dispose()
		return

	first_panel.resolve_cancel()
	var second_panel: GameModalRoutePanel = await _wait_for_top_modal(
		stack,
		first_panel
	)

	assert_true(first_state.done, "第一弹层关闭后必须交付 typed 终态。")
	assert_not_null(second_panel, "await 续体应能立即打开同 route 的第二弹层。")
	assert_true(
		stack.ui_router.get_current_route_id(GFUIUtility.Layer.POPUP)
		== GameUiRouterUtility.ROUTE_MODAL_DIALOG,
		"旧 back() 不得误删续体刚写入的新路由历史。"
	)
	assert_true(
		stack.ui_utility.get_top_panel(GFUIUtility.Layer.POPUP) == second_panel,
		"第二弹层必须保持为 GF popup 栈顶。"
	)
	if second_panel != null:
		second_panel.resolve_cancel()
	await _wait_for_modal_state(stack, second_state)
	assert_true(second_state.done)
	stack.architecture.dispose()


func test_owner_exit_under_new_popup_closes_when_owned_modal_returns_to_top() -> void:
	var stack: _RouterTestStack = await _make_live_router_stack()
	var owned_state: _ModalWaitState = _ModalWaitState.new()
	var cover_state: _ModalWaitState = _ModalWaitState.new()
	var owned_owner: Node = Node.new()
	add_child(owned_owner)
	var config: GFModalConfig = GameUiRouterUtility.make_acknowledgement_modal_config(
		"所有权",
		"owner 退出后必须收束。",
		"知道了"
	)
	call_deferred(
		&"_run_modal_wait",
		stack,
		owned_owner,
		config,
		owned_state
	)
	var owned_panel: GameModalRoutePanel = await _wait_for_top_modal(
		stack
	)
	assert_not_null(
		owned_panel,
		"owner modal 必须打开；done=%s result=%s" % [
			owned_state.done,
			owned_state.result.to_dict() if owned_state.result != null else {},
		]
	)
	if owned_panel == null:
		owned_owner.queue_free()
		stack.architecture.dispose()
		return

	call_deferred(
		&"_run_modal_wait",
		stack,
		self,
		config,
		cover_state
	)
	var cover_panel: GameModalRoutePanel = await _wait_for_top_modal(
		stack,
		owned_panel
	)
	assert_not_null(cover_panel)
	if cover_panel == null:
		owned_owner.queue_free()
		stack.architecture.dispose()
		return

	owned_owner.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(owned_state.done, "被上层覆盖时，owner 弹层应等待精确出栈。")
	cover_panel.resolve_cancel()
	await _wait_for_modal_state(stack, cover_state)
	await _wait_for_modal_state(stack, owned_state)

	assert_true(cover_state.done)
	assert_true(owned_state.done, "上层关闭后必须继续收束已退出 owner 的旧弹层。")
	assert_not_null(owned_state.result)
	if owned_state.result != null:
		assert_true(owned_state.result.action_id == &"owner_exited")
	assert_null(stack.ui_utility.get_top_panel(GFUIUtility.Layer.POPUP))
	assert_true(
		stack.ui_router.get_current_route_id(GFUIUtility.Layer.POPUP) == &""
	)
	stack.architecture.dispose()


func test_owned_async_route_passes_owner_and_optional_scope_to_gf() -> void:
	var ui_router: _AsyncOptionsCaptureRouter = _AsyncOptionsCaptureRouter.new()
	var scope: GFAsyncScope = GFAsyncScope.new()

	var result: GFUIRouteResult = await ui_router.push_owned_route_async(
		self,
		&"missing_test_route",
		{},
		{},
		Callable(),
		GFUIRouterUtility.PRELOAD_NONE,
		scope
	)

	assert_not_null(result)
	var captured_owner_matches: bool = (
		ui_router.captured_async_options.get("owner") == self
	)
	assert_true(
		captured_owner_matches,
		"项目 Router Adapter 必须使用 GF 原生 owner 生命周期。"
	)
	var captured_scope_matches: bool = (
		ui_router.captured_async_options.get("scope") == scope
	)
	assert_true(
		captured_scope_matches,
		"可选 GFAsyncScope 必须原样透传给 GFUIRouterUtility。"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			ui_router.captured_async_options,
			"preload_policy"
		) == GFUIRouterUtility.PRELOAD_NONE
	)


func test_route_panels_defer_initial_focus_until_after_gf_capture() -> void:
	var route_panel_sources: Array[String] = [
		"res://features/gameplay/scripts/ui/pause_menu.gd",
		"res://features/gameplay/scripts/ui/game_over_menu.gd",
		"res://features/gameplay/scripts/ui/target_reached_menu.gd",
		"res://features/settings/scripts/menus/settings_menu.gd",
		"res://features/achievements/scripts/ui/achievement_list_dialog.gd",
		"res://features/tile_catalog/scripts/ui/tile_catalog_dialog.gd",
	]
	for source_path: String in route_panel_sources:
		var source: String = FileAccess.get_file_as_string(source_path)
		var ready_source: String = _get_function_source(source, "_ready")
		assert_true(
			ready_source.contains("call_deferred(&\"_focus_initial_control\")"),
			"路由面板初始焦点必须延迟到 GF 捕获 previous focus 之后：%s。" % source_path
		)
		assert_false(
			ready_source.contains(".grab_focus()"),
			"路由面板不得在同步 _ready 中破坏 GF restore_focus：%s。" % source_path
		)
	var settings_source: String = FileAccess.get_file_as_string(
		"res://features/settings/scripts/menus/settings_menu.gd"
	)
	var cancel_source: String = _get_function_source(
		settings_source,
		"_unhandled_input"
	)
	assert_true(
		cancel_source.contains("_try_handle_top_modal_cancel(event)"),
		"设置完整场景必须先把取消输入交给 GF 顶层 modal。"
	)
	assert_true(
		cancel_source.contains("_on_back_button_pressed()"),
		"GF popup 栈为空时，设置完整场景仍必须响应返回键。"
	)


func test_stale_owner_rollback_does_not_close_new_instance_of_same_route() -> void:
	var ui_utility: _TopPanelProbeUiUtility = _TopPanelProbeUiUtility.new()
	var ui_router: _RollbackProbeRouter = _RollbackProbeRouter.new()
	ui_router.configure([], ui_utility)
	var stale_panel: Control = Control.new()
	var replacement_panel: Control = Control.new()
	add_child_autoqfree(stale_panel)
	add_child_autoqfree(replacement_panel)
	var stale_result: GFUIRouteResult = _make_opened_route_result(
		stale_panel,
		&"settings_menu"
	)

	ui_utility.top_panel = replacement_panel
	ui_router._rollback_stale_route_result(stale_result)

	assert_true(
		ui_router.back_call_count == 0,
		"同 route 的新面板已成为栈顶时，不得用迟到结果盲目 back。"
	)
	ui_utility.top_panel = stale_panel
	ui_router._rollback_stale_route_result(stale_result)
	assert_true(
		ui_router.back_call_count == 1,
		"只有迟到结果实际提交的面板仍是栈顶时才允许回滚。"
	)


func test_game_ui_router_uses_ui_route_registry_order() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameUiRouterUtility, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, GameUiRouterUtility)
	await architecture.init()

	assert_true(
		_packed_strings_to_array(ui_router.get_registered_route_paths()) == EXPECTED_UI_ROUTE_PATHS,
		"项目 UI 路由资源路径应由 GFResourceRegistry 按注册顺序提供。"
	)

	architecture.dispose()
	await get_tree().process_frame


func test_game_ui_router_registers_asset_group_paths_when_utility_is_ready() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameUiRouterUtility, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, GameUiRouterUtility)
	await architecture.init()

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"ui_routes")
	var sorted_group_paths: Array[String] = _packed_strings_to_array(group_paths)
	var sorted_expected_paths: Array[String] = EXPECTED_UI_ROUTE_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_true(sorted_group_paths == sorted_expected_paths, "UI Router Utility ready 后应把路由资源登记为 GFAssetUtility 分组。")

	architecture.dispose()
	await get_tree().process_frame


func test_game_ui_router_registers_resolver_resource_keys_when_utility_is_ready() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var ui_router: GameUiRouterUtility = GameUiRouterUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameUiRouterUtility, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, GameUiRouterUtility)
	await architecture.init()

	for resource_key: String in EXPECTED_UI_ROUTE_RESOURCE_KEYS:
		assert_true(
			resolver.has_registered_key(StringName(resource_key)),
			"UI Router Utility ready 后应把路由注册为 GFResourceResolverUtility 资源键: %s" % resource_key
		)

	var route_resource: Resource = resolver.load(&"game.ui_route.pause_menu", "Resource")
	assert_true(route_resource is GFUIRoute, "应能通过稳定资源键加载暂停菜单路由。")

	architecture.dispose()
	await get_tree().process_frame


# --- 私有/辅助方法 ---

func _packed_strings_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value: String in values:
		result.append(value)
	return result


func _make_live_router_stack() -> _RouterTestStack:
	var stack: _RouterTestStack = _RouterTestStack.new()
	stack.architecture = GFArchitecture.new()
	stack.ui_utility = GFUIUtility.new()
	stack.ui_router = GameUiRouterUtility.new()
	await stack.architecture.register_utility(
		GFResourceBroker,
		GFResourceBroker.new()
	)
	await stack.architecture.register_utility(GFAssetUtility, GFAssetUtility.new())
	await stack.architecture.register_utility(
		GFResourceResolverUtility,
		GFResourceResolverUtility.new()
	)
	await stack.architecture.register_utility(GFUIUtility, stack.ui_utility)
	await stack.architecture.register_utility(
		ProjectResourceCatalogUtility,
		ProjectResourceCatalogUtility.new()
	)
	await stack.architecture.register_utility(
		GameUiRouterUtility,
		stack.ui_router
	)
	stack.architecture.register_utility_alias(
		GFUIRouterUtility,
		GameUiRouterUtility
	)
	await stack.architecture.init()
	stack.context = TestArchitectureContext.new()
	stack.context.test_architecture = stack.architecture
	add_child_autoqfree(stack.context)
	for layer: int in [
		GFUIUtility.Layer.HUD,
		GFUIUtility.Layer.POPUP,
		GFUIUtility.Layer.TOP,
	]:
		var layer_root: CanvasLayer = stack.ui_utility.get_layer_root(layer)
		if is_instance_valid(layer_root) and layer_root.get_parent() != stack.context:
			layer_root.reparent(stack.context)
	return stack


func _wait_for_top_modal(
	stack: _RouterTestStack,
	previous_panel: GameModalRoutePanel = null,
	max_frames: int = 180
) -> GameModalRoutePanel:
	for _frame_index: int in range(maxi(max_frames, 1)):
		stack.architecture.tick(0.0)
		var top_panel: Node = stack.ui_utility.get_top_panel(
			GFUIUtility.Layer.POPUP
		)
		if top_panel is GameModalRoutePanel and top_panel != previous_panel:
			var modal_panel: GameModalRoutePanel = top_panel
			return modal_panel
		await get_tree().process_frame
	return null


func _wait_for_modal_state(
	stack: _RouterTestStack,
	state: _ModalWaitState,
	max_frames: int = 180
) -> void:
	for _frame_index: int in range(maxi(max_frames, 1)):
		stack.architecture.tick(0.0)
		if state.done:
			return
		await get_tree().process_frame


func _run_modal_reopen_sequence(
	stack: _RouterTestStack,
	config: GFModalConfig,
	first_state: _ModalWaitState,
	second_state: _ModalWaitState
) -> void:
	first_state.result = await stack.ui_router.show_modal_async(self, config)
	first_state.done = true
	second_state.result = await stack.ui_router.show_modal_async(self, config)
	second_state.done = true


func _run_modal_wait(
	stack: _RouterTestStack,
	route_owner: Node,
	config: GFModalConfig,
	state: _ModalWaitState
) -> void:
	state.result = await stack.ui_router.show_modal_async(route_owner, config)
	state.done = true


func _get_function_source(source: String, function_name: String) -> String:
	var marker: String = "func %s(" % function_name
	var start_index: int = source.find(marker)
	if start_index < 0:
		return ""
	var next_index: int = source.find("\nfunc ", start_index + marker.length())
	if next_index < 0:
		return source.substr(start_index)
	return source.substr(start_index, next_index - start_index)


func _make_opened_route_result(
	panel: Node,
	route_id: StringName
) -> GFUIRouteResult:
	var result: GFUIRouteResult = GFUIRouteResult.new()
	var configured: bool = result.configure_for_framework(
		1,
		route_id,
		&"push",
		GFUIRouteResult.STATUS_OPENED,
		&"",
		GFUIUtility.Layer.POPUP,
		panel,
		GFUIRouterUtility.PRELOAD_BEST_EFFORT,
		false,
		false,
		{},
		null,
		10,
		11,
		{}
	)
	assert_true(configured, "测试路由结果应成功配置。")
	return result


# --- 内部类 ---

class _TopPanelProbeUiUtility extends GFUIUtility:
	var top_panel: Node = null


	## @param _layer: 测试忽略的 UI 层。
	func get_top_panel(_layer: int = Layer.POPUP) -> Node:
		return top_panel


class _RollbackProbeRouter extends GameUiRouterUtility:
	var back_call_count: int = 0


	## @param _layer: 测试忽略的 UI 层。
	## @param _do_free: 测试忽略的释放选项。
	func back(_layer: int = -1, _do_free: bool = true) -> bool:
		back_call_count += 1
		return true


class _AsyncOptionsCaptureRouter extends GameUiRouterUtility:
	var captured_async_options: Dictionary = {}


	## @param route_id: 测试捕获的目标 route ID。
	## @param params: 测试透传的路由参数。
	## @param option_overrides: 测试透传的面板选项。
	## @param config_callback: 测试透传的配置回调。
	## @param async_options: 要捕获并断言的异步协调选项。
	func push_route_async(
		route_id: StringName,
		params: Dictionary = {},
		option_overrides: Dictionary = {},
		config_callback: Callable = Callable(),
		async_options: Dictionary = {}
	) -> GFUIRouteOperation:
		captured_async_options = async_options.duplicate(false)
		return super.push_route_async(
			route_id,
			params,
			option_overrides,
			config_callback,
			async_options
		)


class _RouterTestStack extends RefCounted:
	var architecture: GFArchitecture
	var context: TestArchitectureContext
	var ui_utility: GFUIUtility
	var ui_router: GameUiRouterUtility


class _ModalWaitState extends RefCounted:
	var done: bool = false
	var result: GFModalResult = null
