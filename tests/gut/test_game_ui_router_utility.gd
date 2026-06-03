## 验证项目 UI 路由表通过 GFUIRouterUtility 暴露。
extends GutTest


# --- 常量 ---

const _GAME_UI_ROUTER_UTILITY_SCRIPT = preload("res://scripts/utilities/game_ui_router_utility.gd")
const EXPECTED_UI_ROUTE_PATHS: Array = [
	"res://resources/ui_routes/pause_menu_route.tres",
	"res://resources/ui_routes/game_over_menu_route.tres",
	"res://resources/ui_routes/settings_menu_route.tres",
]


# --- 测试用例 ---

func test_game_ui_router_registers_project_panel_routes() -> void:
	var architecture := GFArchitecture.new()
	var ui_router = _GAME_UI_ROUTER_UTILITY_SCRIPT.new()

	architecture.register_utility(_GAME_UI_ROUTER_UTILITY_SCRIPT, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, _GAME_UI_ROUTER_UTILITY_SCRIPT)
	await architecture.init()

	var route_ids: Array = Array(ui_router.get_route_ids())
	assert_eq(route_ids, ["game_over_menu", "pause_menu", "settings_menu"], "项目 UI 路由应提供稳定 route_id。")
	assert_eq(ui_router.get_route(&"pause_menu").scene_path, "res://scenes/ui/pause_menu.tscn", "暂停菜单路由应指向暂停面板。")
	assert_eq(ui_router.get_route(&"game_over_menu").scene_path, "res://scenes/ui/game_over_menu.tscn", "游戏结束路由应指向游戏结束面板。")
	assert_eq(ui_router.get_route(&"settings_menu").scene_path, "res://scenes/menus/settings_menu.tscn", "设置路由应指向设置菜单。")

	architecture.dispose()


func test_game_ui_router_uses_ui_route_registry_order() -> void:
	var architecture := GFArchitecture.new()
	var ui_router = _GAME_UI_ROUTER_UTILITY_SCRIPT.new()

	architecture.register_utility(_GAME_UI_ROUTER_UTILITY_SCRIPT, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, _GAME_UI_ROUTER_UTILITY_SCRIPT)
	await architecture.init()

	assert_eq(
		Array(ui_router.get_registered_route_paths()),
		EXPECTED_UI_ROUTE_PATHS,
		"项目 UI 路由资源路径应由 GFResourceRegistry 按注册顺序提供。"
	)

	architecture.dispose()


func test_game_ui_router_registers_asset_group_paths_when_utility_is_ready() -> void:
	var architecture := GFArchitecture.new()
	var asset_utility := GFAssetUtility.new()
	var ui_router = _GAME_UI_ROUTER_UTILITY_SCRIPT.new()

	architecture.register_utility(GFAssetUtility, asset_utility)
	architecture.register_utility(_GAME_UI_ROUTER_UTILITY_SCRIPT, ui_router)
	architecture.register_utility_alias(GFUIRouterUtility, _GAME_UI_ROUTER_UTILITY_SCRIPT)
	await architecture.init()

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"ui_routes")
	var sorted_group_paths: Array = Array(group_paths)
	var sorted_expected_paths: Array = EXPECTED_UI_ROUTE_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_eq(sorted_group_paths, sorted_expected_paths, "UI Router Utility ready 后应把路由资源登记为 GFAssetUtility 分组。")

	architecture.dispose()
