## 验证项目 UI 路由表通过 GFUIRouterUtility 暴露。
extends GutTest


# --- 常量 ---

const EXPECTED_UI_ROUTE_PATHS: Array[String] = [
	"res://features/navigation/resources/ui_routes/pause_menu_route.tres",
	"res://features/navigation/resources/ui_routes/game_over_menu_route.tres",
	"res://features/navigation/resources/ui_routes/target_reached_menu_route.tres",
	"res://features/navigation/resources/ui_routes/settings_menu_route.tres",
	"res://features/navigation/resources/ui_routes/tile_catalog_route.tres",
	"res://features/navigation/resources/ui_routes/achievements_route.tres",
	"res://features/navigation/resources/ui_routes/board_editor_route.tres",
]

const EXPECTED_UI_ROUTE_RESOURCE_KEYS: Array[String] = [
	"game.ui_route.pause_menu",
	"game.ui_route.game_over_menu",
	"game.ui_route.target_reached_menu",
	"game.ui_route.settings_menu",
	"game.ui_route.tile_catalog",
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
		"settings_menu",
		"target_reached_menu",
		"tile_catalog",
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
		ui_router.get_route(&"achievements").scene_path == "res://features/achievements/scenes/ui/achievement_list_dialog.tscn",
		"成就路由应指向 achievements Feature 面板。"
	)

	architecture.dispose()
	await get_tree().process_frame


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
