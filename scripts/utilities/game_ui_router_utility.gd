## GameUiRouterUtility: 配置项目内常用 UI 面板路由。
##
## 作为 GFUIRouterUtility 的项目级 Adapter，从 GFResourceRegistry 读取项目 UI 路由资源。
class_name GameUiRouterUtility
extends "res://addons/gf/standard/utilities/ui/gf_ui_router_utility.gd"


# --- 常量 ---

## 项目默认 UI 路由注册表资源。
const DEFAULT_UI_ROUTE_REGISTRY: GFResourceRegistry = preload("res://resources/registries/ui_route_registry.tres")

const ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const ROUTE_TARGET_REACHED_MENU: StringName = &"target_reached_menu"
const ROUTE_SETTINGS_MENU: StringName = &"settings_menu"

const _CATALOG_ID: StringName = &"ui_routes"
const _UI_ROUTE_GROUP_ID: StringName = &"ui_routes"
const _UI_ROUTE_RESOURCE_KEY_PREFIX: String = "game.ui_route."
const _ROUTE_TYPE_HINT: String = "GFUIRoute"


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _route_registry: GFResourceRegistry = DEFAULT_UI_ROUTE_REGISTRY


# --- Godot 生命周期方法 ---

func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	_register_route_registry_resources()
	configure(_load_routes_from_registry(), _resolve_ui_utility_for_configure())


func dispose() -> void:
	super.dispose()
	_release_route_assets()
	_resource_catalog = null


# --- 公共方法 ---

## 获取 UI 路由注册表中的资源路径列表。
## @return: 按注册表顺序排列的 GFUIRoute 资源路径。
func get_registered_route_paths() -> PackedStringArray:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if is_instance_valid(catalog):
		return catalog.get_registered_paths(_CATALOG_ID)
	return _get_registry_paths_without_catalog()


## 获取项目 UI 路由诊断快照。
## @return: 路由表、注册表与资源分组状态。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_route_registry):
		registry_snapshot = _route_registry.get_debug_snapshot()

	snapshot["registry"] = registry_snapshot
	snapshot["route_paths"] = get_registered_route_paths()
	snapshot["route_resource_keys"] = _get_registered_route_resource_keys()
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

	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog):
		push_error("[GameUiRouterUtility] 缺少 ProjectResourceCatalogUtility，无法加载 UI 路由资源: %s" % entry.path)
		return null

	var route_resource: Resource = catalog.load_resource_by_entry(
		_CATALOG_ID,
		entry,
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if not route_resource is GFUIRoute:
		push_warning("[GameUiRouterUtility] UI 路由资源加载失败: %s" % entry.path)
		return null
	var route: GFUIRoute = route_resource
	if not is_instance_valid(route):
		push_warning("[GameUiRouterUtility] UI 路由资源加载失败: %s" % entry.path)
		return null

	return route


func _register_route_registry_resources() -> void:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog) or not is_instance_valid(_route_registry):
		return

	var report: Dictionary = catalog.register_catalog(
		_CATALOG_ID,
		_route_registry,
		_UI_ROUTE_RESOURCE_KEY_PREFIX,
		_ROUTE_TYPE_HINT,
		_UI_ROUTE_GROUP_ID,
		{"registry": "ui_route_registry"}
	)
	if not GFVariantData.get_option_bool(report, "ok", false):
		push_error("[GameUiRouterUtility] UI 路由资源目录注册失败。")


func _release_route_assets() -> void:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if is_instance_valid(catalog):
		catalog.unload_catalog_group(_CATALOG_ID, true)


func _get_cached_route(route_path: String) -> GFUIRoute:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog):
		return null

	var resource: Resource = catalog.load_resource_by_path(_CATALOG_ID, route_path, ResourceLoader.CACHE_MODE_IGNORE)
	if resource is GFUIRoute:
		var route: GFUIRoute = resource
		return route
	return null


func _get_resource_catalog() -> ProjectResourceCatalogUtility:
	if is_instance_valid(_resource_catalog):
		return _resource_catalog

	_resource_catalog = _resolve_resource_catalog_utility()
	return _resource_catalog


func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null


func _resolve_ui_utility_for_configure() -> GFUIUtility:
	var utility_value: Object = get_utility(GFUIUtility)
	if utility_value is GFUIUtility:
		var ui_utility: GFUIUtility = utility_value
		return ui_utility
	return null


func _resolve_type_hint(entry: GFResourceRegistryEntry) -> String:
	if entry != null and not entry.type_hint.is_empty():
		return entry.type_hint
	return _ROUTE_TYPE_HINT


func _get_registered_route_resource_keys() -> PackedStringArray:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if is_instance_valid(catalog):
		return catalog.get_registered_resource_keys(_CATALOG_ID)
	return _get_registered_route_resource_keys_without_catalog()


static func _get_resource_key_for_entry(entry: GFResourceRegistryEntry) -> StringName:
	if not _is_valid_registry_entry(entry):
		return &""
	return StringName("%s%s" % [_UI_ROUTE_RESOURCE_KEY_PREFIX, String(entry.id)])


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()


func _get_registry_paths_without_catalog() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_route_registry):
		return result

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if _is_valid_registry_entry(entry):
			var _append_result: bool = result.append(entry.path)
	return result


func _get_registered_route_resource_keys_without_catalog() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_route_registry):
		return result

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		var _append_result: bool = result.append(String(_get_resource_key_for_entry(entry)))
	return result
