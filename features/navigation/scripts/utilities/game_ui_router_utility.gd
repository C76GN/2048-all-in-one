## GameUiRouterUtility: 配置项目内常用 UI 面板路由。
##
## 作为 GFUIRouterUtility 的项目级 Adapter，从项目资源目录加载类型安全的路由资源。
class_name GameUiRouterUtility
extends "res://addons/gf/standard/utilities/ui/gf_ui_router_utility.gd"


# --- 常量 ---

const DEFAULT_UI_ROUTE_REGISTRY: GFResourceRegistry = preload("res://features/navigation/resources/registries/ui_route_registry.tres")

const ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const ROUTE_TARGET_REACHED_MENU: StringName = &"target_reached_menu"
const ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const ROUTE_TILE_CATALOG: StringName = &"tile_catalog"
const ROUTE_TILE_LAB: StringName = &"tile_lab"
const ROUTE_ACHIEVEMENTS: StringName = &"achievements"
const ROUTE_BOARD_EDITOR: StringName = &"board_editor"
const ROUTE_PLAYER_PROFILE: StringName = &"player_profile"

const _CATALOG_ID: StringName = &"ui_routes"
const _UI_ROUTE_GROUP_ID: StringName = &"ui_routes"
const _UI_ROUTE_RESOURCE_KEY_PREFIX: String = "game.ui_route."
const _ROUTE_TYPE_HINT: String = "Resource"
const _DEFAULT_PRELOAD_PLAN_OPTIONS: Dictionary = {
	"max_depth": 1,
	"max_routes": 4,
	"include_source": true,
}


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _route_registry: GFResourceRegistry = DEFAULT_UI_ROUTE_REGISTRY


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFUIUtility, ProjectResourceCatalogUtility]


func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		push_error("[GameUiRouterUtility] ProjectResourceCatalogUtility 未注册。")
		return

	var report: GFValidationReport = _resource_catalog.register_catalog(
		_CATALOG_ID,
		_route_registry,
		_UI_ROUTE_RESOURCE_KEY_PREFIX,
		_ROUTE_TYPE_HINT,
		_UI_ROUTE_GROUP_ID,
		{"registry": "ui_route_registry"}
	)
	if not report.is_ok():
		push_error("[GameUiRouterUtility] UI 路由目录注册失败：%s" % report.make_summary())
		return

	var ui_utility: GFUIUtility = _resolve_ui_utility()
	if not is_instance_valid(ui_utility):
		push_error("[GameUiRouterUtility] GFUIUtility 未注册。")
		return
	configure(_load_routes_from_registry(), ui_utility)


func dispose() -> void:
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID, true)
	_resource_catalog = null
	super.dispose()


# --- 公共方法 ---

## 获取 UI 路由注册表中的资源路径列表。
func get_registered_route_paths() -> PackedStringArray:
	if not is_instance_valid(_resource_catalog):
		return PackedStringArray()
	return _resource_catalog.get_registered_paths(_CATALOG_ID)


## 获取项目 UI 路由诊断快照。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_route_registry):
		registry_snapshot = _route_registry.get_debug_snapshot()

	var resource_keys: PackedStringArray = PackedStringArray()
	if is_instance_valid(_resource_catalog):
		resource_keys = _resource_catalog.get_registered_resource_keys(_CATALOG_ID)
	snapshot["registry"] = registry_snapshot
	snapshot["route_paths"] = get_registered_route_paths()
	snapshot["route_resource_keys"] = resource_keys
	return snapshot


## 以项目统一策略异步打开路由，并在调用方离开场景树后回滚迟到的面板。
##
## GFUIRouterUtility 负责预加载、并发去重与唯一终态；此方法只补充项目 owner
## 生命周期和默认的相邻路由预加载预算。
func push_owned_route_async(
	owner: Node,
	route_id: StringName,
	params: Dictionary = {},
	option_overrides: Dictionary = {},
	config_callback: Callable = Callable(),
	preload_policy: StringName = GFUIRouterUtility.PRELOAD_BEST_EFFORT
) -> GFUIRouteResult:
	if not _is_live_route_owner(owner):
		return null

	var owner_ref: WeakRef = weakref(owner)
	var operation: GFUIRouteOperation = push_route_async(
		route_id,
		params,
		option_overrides,
		config_callback,
		{
			"preload_policy": preload_policy,
			"preload_plan_options": _DEFAULT_PRELOAD_PLAN_OPTIONS.duplicate(true),
			"metadata": {
				"owner_instance_id": owner.get_instance_id(),
				"owner_path": String(owner.get_path()),
			},
		}
	)
	if operation == null:
		return null

	var result: GFUIRouteResult = operation.get_result()
	if result == null:
		result = await operation.completed
	if _is_live_route_owner_ref(owner_ref):
		return result

	_rollback_stale_route_result(result)
	return null


# --- 私有/辅助方法 ---

func _load_routes_from_registry() -> Array[GFUIRoute]:
	var routes: Array[GFUIRoute] = []
	if not is_instance_valid(_route_registry):
		return routes

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if entry == null or not entry.is_valid_entry():
			continue
		var route: GFUIRoute = _load_route_entry(entry)
		if is_instance_valid(route):
			routes.append(route)
	return routes


func _is_live_route_owner(owner: Node) -> bool:
	return is_instance_valid(owner) and owner.is_inside_tree()


func _is_live_route_owner_ref(owner_ref: WeakRef) -> bool:
	if owner_ref == null:
		return false
	var value: Object = owner_ref.get_ref()
	return value is Node and _is_live_route_owner(value as Node)


func _rollback_stale_route_result(result: GFUIRouteResult) -> void:
	if result == null or not result.is_successful():
		return
	if get_current_route_id(result.get_layer()) != result.get_route_id():
		return
	var _closed: bool = back(result.get_layer())


func _load_route_entry(entry: GFResourceRegistryEntry) -> GFUIRoute:
	if not is_instance_valid(_resource_catalog):
		return null
	var resource: Resource = _resource_catalog.load_resource_by_entry(_CATALOG_ID, entry)
	if resource is GFUIRoute:
		var route: GFUIRoute = resource
		return route
	push_error("[GameUiRouterUtility] UI 路由资源加载失败：%s。" % entry.path)
	return null


func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null


func _resolve_ui_utility() -> GFUIUtility:
	var utility_value: Object = get_utility(GFUIUtility)
	if utility_value is GFUIUtility:
		var ui_utility: GFUIUtility = utility_value
		return ui_utility
	return null
