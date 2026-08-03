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
	assert_true(
		ui_router.captured_async_options.get("owner") == self,
		"项目 Router Adapter 必须使用 GF 原生 owner 生命周期。"
	)
	assert_true(
		ui_router.captured_async_options.get("scope") == scope,
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
