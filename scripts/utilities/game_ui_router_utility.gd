## GameUiRouterUtility: 配置项目内常用 UI 面板路由。
##
## 作为 GFUIRouterUtility 的项目级 Adapter，从 GFResourceRegistry 读取项目 UI 路由资源。
class_name GameUiRouterUtility
extends GFUIRouterUtility


# --- 常量 ---

## 项目默认 UI 路由注册表资源。
const DEFAULT_UI_ROUTE_REGISTRY: GFResourceRegistry = preload("res://resources/registries/ui_route_registry.tres")

const ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const ROUTE_SETTINGS_MENU: StringName = &"settings_menu"

const _UI_ROUTE_GROUP_ID: StringName = &"ui_routes"
const _ROUTE_TYPE_HINT: String = "GFUIRoute"


# --- 私有变量 ---

var _asset_utility: GFAssetUtility = null
var _route_registry: GFResourceRegistry = DEFAULT_UI_ROUTE_REGISTRY


# --- Godot 生命周期方法 ---

func ready() -> void:
	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility
	_register_route_group_paths()
	configure(_load_routes_from_registry(), get_utility(GFUIUtility) as GFUIUtility)


func dispose() -> void:
	super.dispose()
	_release_route_assets()
	_asset_utility = null


# --- 公共方法 ---

## 获取 UI 路由注册表中的资源路径列表。
## @return: 按注册表顺序排列的 GFUIRoute 资源路径。
func get_registered_route_paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_route_registry):
		return result

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		var _append_result: bool = result.append(entry.path)
	return result


## 获取项目 UI 路由诊断快照。
## @return: 路由表、注册表与资源分组状态。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_route_registry):
		registry_snapshot = _route_registry.get_debug_snapshot()

	snapshot["registry"] = registry_snapshot
	snapshot["route_paths"] = get_registered_route_paths()
	return snapshot


# --- 私有/辅助方法 ---

func _load_routes_from_registry() -> Array[GFUIRoute]:
	var routes: Array[GFUIRoute] = []
	if not is_instance_valid(_route_registry):
		return routes

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		var route: GFUIRoute = _load_route_entry(entry)
		if is_instance_valid(route):
			routes.append(route)

	return routes


func _load_route_entry(entry: GFResourceRegistryEntry) -> GFUIRoute:
	var cached_route: GFUIRoute = _get_cached_route(entry.path)
	if is_instance_valid(cached_route):
		return cached_route

	var route_resource: Resource = _route_registry.load_entry(
		entry.id,
		_resolve_type_hint(entry),
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if not route_resource is GFUIRoute:
		push_warning("[GameUiRouterUtility] UI 路由资源加载失败: %s" % entry.path)
		return null
	var route: GFUIRoute = route_resource
	if not is_instance_valid(route):
		push_warning("[GameUiRouterUtility] UI 路由资源加载失败: %s" % entry.path)
		return null

	var asset_utility: GFAssetUtility = _get_asset_utility()
	if is_instance_valid(asset_utility):
		asset_utility.put_cache(entry.path, route)
	return route


func _register_route_group_paths() -> void:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if not is_instance_valid(asset_utility) or not is_instance_valid(_route_registry):
		return

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		asset_utility.register_group_path(_UI_ROUTE_GROUP_ID, entry.path, true)


func _release_route_assets() -> void:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if not is_instance_valid(asset_utility):
		return

	asset_utility.unload_group(_UI_ROUTE_GROUP_ID, true)


func _get_cached_route(route_path: String) -> GFUIRoute:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if not is_instance_valid(asset_utility):
		return null

	var cached_value: Variant = asset_utility.get_cached(route_path)
	if cached_value is GFUIRoute:
		return cached_value
	return null


func _get_asset_utility() -> GFAssetUtility:
	if is_instance_valid(_asset_utility):
		return _asset_utility

	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility
	return _asset_utility


func _resolve_type_hint(entry: GFResourceRegistryEntry) -> String:
	if entry != null and not entry.type_hint.is_empty():
		return entry.type_hint
	return _ROUTE_TYPE_HINT


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()
