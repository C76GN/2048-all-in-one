## GameModeConfigCacheUtility: 提供 GameModeConfig 资源注册表访问。
##
## 统一处理模式配置注册表、类型校验与运行时缓存，并优先复用 GFAssetUtility 的资源缓存。
class_name GameModeConfigCacheUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

## 项目默认模式注册表资源。
const DEFAULT_MODE_REGISTRY: GFResourceRegistry = preload("res://resources/registries/game_mode_registry.tres")

const _CATALOG_ID: StringName = &"game_modes"
const _MODE_CONFIG_GROUP_ID: StringName = &"game_modes"
const _MODE_RESOURCE_KEY_PREFIX: String = "game.mode_config."
const _MODE_TYPE_HINT: String = "GameModeConfig"


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _mode_registry: GFResourceRegistry = DEFAULT_MODE_REGISTRY
var _local_config_cache: Dictionary = {}
var _missing_paths: Dictionary = {}


# --- Godot 生命周期方法 ---

func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	_register_mode_registry_resources()


func dispose() -> void:
	_resource_catalog = null
	_local_config_cache.clear()
	_missing_paths.clear()


# --- 公共方法 ---

## 获取指定路径的模式配置资源。
## @param config_path: GameModeConfig 资源路径。
## @return: 成功时返回已缓存或新加载的 GameModeConfig，否则返回 null。
func get_cached_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var cached_config: GameModeConfig = _get_cached_config_from_asset_utility(config_path)
	if is_instance_valid(cached_config):
		return cached_config

	if _local_config_cache.has(config_path):
		var cached_value: Variant = _local_config_cache[config_path]
		if cached_value is GameModeConfig:
			cached_config = cached_value
			if is_instance_valid(cached_config):
				return cached_config
		var _erase_result: bool = _local_config_cache.erase(config_path)

	if _missing_paths.has(config_path):
		return null

	var mode_config: GameModeConfig = _load_config_from_registry(config_path)
	if is_instance_valid(mode_config):
		_cache_config(config_path, mode_config)
		return mode_config

	_missing_paths[config_path] = true
	return null


## 获取当前注册表中的配置路径列表。
## @return: 按注册表顺序排列的 GameModeConfig 资源路径。
func get_registered_config_paths() -> PackedStringArray:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if is_instance_valid(catalog):
		return catalog.get_registered_paths(_CATALOG_ID, true)

	return _get_registry_paths_without_catalog()


## 获取模式注册表调试快照。
## @return: 注册表与运行时缓存状态。
func get_debug_snapshot() -> Dictionary:
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_mode_registry):
		registry_snapshot = _mode_registry.get_debug_snapshot()

	return {
		"registry": registry_snapshot,
		"local_cache_count": _local_config_cache.size(),
		"missing_path_count": _missing_paths.size(),
		"resource_keys": _get_registered_mode_resource_keys(),
		"catalog_id": String(_CATALOG_ID),
	}


## 清空当前 Utility 维护的运行时缓存。
func clear_runtime_cache() -> void:
	_local_config_cache.clear()
	_missing_paths.clear()


# --- 私有/辅助方法 ---


func _get_cached_config_from_asset_utility(config_path: String) -> GameModeConfig:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog):
		return null

	var resource: Resource = catalog.load_resource_by_path(_CATALOG_ID, config_path)
	if resource is GameModeConfig:
		var mode_config: GameModeConfig = resource
		return mode_config
	return null


func _cache_config(config_path: String, mode_config: GameModeConfig) -> void:
	_local_config_cache[config_path] = mode_config


func _load_config_from_registry(config_path: String) -> GameModeConfig:
	var entry: GFResourceRegistryEntry = _get_entry_for_path(config_path, _mode_registry)
	if not _is_valid_registry_entry(entry):
		push_warning("[GameModeConfigCacheUtility] 未在模式注册表中找到配置路径: %s" % config_path)
		return null

	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog):
		push_error("[GameModeConfigCacheUtility] 缺少 ProjectResourceCatalogUtility，无法加载模式配置：%s。" % config_path)
		return null

	var resource: Resource = catalog.load_resource_by_entry(
		_CATALOG_ID,
		entry,
		ResourceLoader.CACHE_MODE_REUSE
	)
	if resource is GameModeConfig:
		var mode_config: GameModeConfig = resource
		return mode_config
	return null


func _register_mode_registry_resources() -> void:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if not is_instance_valid(catalog) or not is_instance_valid(_mode_registry):
		return

	var report: Dictionary = catalog.register_catalog(
		_CATALOG_ID,
		_mode_registry,
		_MODE_RESOURCE_KEY_PREFIX,
		_MODE_TYPE_HINT,
		_MODE_CONFIG_GROUP_ID,
		{"registry": "game_mode_registry"}
	)
	if not GFVariantData.get_option_bool(report, "ok", false):
		push_error("[GameModeConfigCacheUtility] 模式资源目录注册失败。")


func _get_registered_mode_resource_keys() -> PackedStringArray:
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog()
	if is_instance_valid(catalog):
		return catalog.get_registered_resource_keys(_CATALOG_ID)
	return _get_registered_mode_resource_keys_without_catalog()


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


func _get_registry_paths_without_catalog() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_mode_registry):
		return result

	for entry: GFResourceRegistryEntry in _mode_registry.entries:
		if _is_valid_registry_entry(entry):
			var _append_result: bool = result.append(entry.path)
	return result


func _get_registered_mode_resource_keys_without_catalog() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_mode_registry):
		return result

	for entry: GFResourceRegistryEntry in _mode_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		var _append_result: bool = result.append(String(_get_resource_key_for_entry(entry)))
	return result


static func _get_entry_for_path(config_path: String, registry: GFResourceRegistry) -> GFResourceRegistryEntry:
	if config_path.is_empty() or not is_instance_valid(registry):
		return null

	for entry: GFResourceRegistryEntry in registry.entries:
		if _is_valid_registry_entry(entry) and entry.path == config_path:
			return entry
	return null


static func _get_resource_key_for_entry(entry: GFResourceRegistryEntry) -> StringName:
	if not _is_valid_registry_entry(entry):
		return &""
	return StringName("%s%s" % [_MODE_RESOURCE_KEY_PREFIX, String(entry.id)])


static func _get_type_hint_for_entry(entry: GFResourceRegistryEntry) -> String:
	if entry != null and not entry.type_hint.is_empty():
		return entry.type_hint
	return _MODE_TYPE_HINT


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()
