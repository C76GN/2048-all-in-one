## GameModeConfigCacheUtility: 提供 GameModeConfig 资源注册表访问。
##
## 统一处理模式配置注册表、类型校验与运行时缓存，并优先复用 GFAssetUtility 的资源缓存。
class_name GameModeConfigCacheUtility
extends GFUtility


# --- 常量 ---

## 项目默认模式注册表资源。
const DEFAULT_MODE_REGISTRY: GFResourceRegistry = preload("res://resources/registries/game_mode_registry.tres")

const _SCRIPT_PATH: String = "res://scripts/utilities/game_mode_config_cache_utility.gd"
const _MODE_CONFIG_GROUP_ID: StringName = &"game_modes"
const _MODE_TYPE_HINT: String = "GameModeConfig"


# --- 私有变量 ---

static var _fallback_config_cache: Dictionary = {}
static var _fallback_missing_paths: Dictionary = {}

var _asset_utility: GFAssetUtility = null
var _mode_registry: GFResourceRegistry = DEFAULT_MODE_REGISTRY
var _local_config_cache: Dictionary = {}
var _missing_paths: Dictionary = {}


# --- Godot 生命周期方法 ---

func ready() -> void:
	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility
	_register_mode_group_paths()


func dispose() -> void:
	_asset_utility = null
	_local_config_cache.clear()
	_missing_paths.clear()


# --- 公共方法 ---

## 获取指定路径的模式配置资源。
## @param config_path: GameModeConfig 资源路径。
## @return: 成功时返回已缓存或新加载的 GameModeConfig，否则返回 null。
static func get_config(config_path: String) -> GameModeConfig:
	var cache := _get_registered_cache()
	if cache != null and cache.has_method("get_cached_config"):
		return cache.get_cached_config(config_path) as GameModeConfig

	return _get_fallback_config(config_path)


## 获取模式注册表中的配置路径列表。
## @return: 按注册表顺序排列的 GameModeConfig 资源路径。
static func get_config_paths() -> PackedStringArray:
	var cache := _get_registered_cache()
	if cache != null and cache.has_method("get_registered_config_paths"):
		return cache.get_registered_config_paths()

	return _get_registry_config_paths(DEFAULT_MODE_REGISTRY)


## 获取指定路径的模式配置资源。
## @param config_path: GameModeConfig 资源路径。
## @return: 成功时返回已缓存或新加载的 GameModeConfig，否则返回 null。
func get_cached_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var cached_config := _get_cached_config_from_asset_utility(config_path)
	if is_instance_valid(cached_config):
		return cached_config

	if _local_config_cache.has(config_path):
		cached_config = _local_config_cache[config_path] as GameModeConfig
		if is_instance_valid(cached_config):
			return cached_config
		_local_config_cache.erase(config_path)

	if _missing_paths.has(config_path):
		return null

	var mode_config := _load_config_from_registry(config_path)
	if is_instance_valid(mode_config):
		_cache_config(config_path, mode_config)
		return mode_config

	_missing_paths[config_path] = true
	return null


## 获取当前注册表中的配置路径列表。
## @return: 按注册表顺序排列的 GameModeConfig 资源路径。
func get_registered_config_paths() -> PackedStringArray:
	return _get_registry_config_paths(_mode_registry)


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
	}


## 清空全部缓存。
static func clear() -> void:
	var cache := _get_registered_cache()
	if cache != null and cache.has_method("clear_runtime_cache"):
		cache.clear_runtime_cache()

	_fallback_config_cache.clear()
	_fallback_missing_paths.clear()


## 清空当前 Utility 维护的运行时缓存。
func clear_runtime_cache() -> void:
	_local_config_cache.clear()
	_missing_paths.clear()


# --- 私有/辅助方法 ---

static func _get_registered_cache() -> Object:
	var architecture := GFAutoload.get_architecture_or_null()
	if architecture == null:
		return null

	var cache_script := load(_SCRIPT_PATH) as Script
	if cache_script == null:
		return null

	return architecture.get_utility(cache_script)


static func _get_fallback_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	if _fallback_config_cache.has(config_path):
		var cached_config := _fallback_config_cache[config_path] as GameModeConfig
		if is_instance_valid(cached_config):
			return cached_config
		_fallback_config_cache.erase(config_path)

	if _fallback_missing_paths.has(config_path):
		return null

	var mode_config := _load_config_from_registry_static(config_path, DEFAULT_MODE_REGISTRY)
	if is_instance_valid(mode_config):
		_fallback_config_cache[config_path] = mode_config
		return mode_config

	_fallback_missing_paths[config_path] = true
	return null


static func _get_registry_config_paths(registry: GFResourceRegistry) -> PackedStringArray:
	var result := PackedStringArray()
	if not is_instance_valid(registry):
		return result

	for entry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		var config_path: String = entry.path
		if ResourceLoader.exists(config_path):
			result.append(config_path)
		else:
			push_warning("[GameModeConfigCacheUtility] 注册表中的模式配置资源缺失: %s" % config_path)

	return result


static func _load_config_from_registry_static(
	config_path: String,
	registry: GFResourceRegistry
) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var type_hint: String = _get_type_hint_for_path(config_path, registry)
	var resource: Resource = null
	if not type_hint.is_empty():
		resource = ResourceLoader.load(config_path, type_hint)
	if resource == null:
		resource = ResourceLoader.load(config_path)

	return resource as GameModeConfig


func _get_cached_config_from_asset_utility(config_path: String) -> GameModeConfig:
	var asset_utility := _get_asset_utility()
	if not is_instance_valid(asset_utility):
		return null

	return asset_utility.get_cached(config_path) as GameModeConfig


func _cache_config(config_path: String, mode_config: GameModeConfig) -> void:
	var asset_utility := _get_asset_utility()
	if is_instance_valid(asset_utility):
		asset_utility.put_cache(config_path, mode_config)
		return

	_local_config_cache[config_path] = mode_config


func _load_config_from_registry(config_path: String) -> GameModeConfig:
	return _load_config_from_registry_static(config_path, _mode_registry)


func _register_mode_group_paths() -> void:
	var asset_utility := _get_asset_utility()
	if not is_instance_valid(asset_utility) or not is_instance_valid(_mode_registry):
		return

	for entry in _mode_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		asset_utility.register_group_path(_MODE_CONFIG_GROUP_ID, entry.path, true)


func _get_asset_utility() -> GFAssetUtility:
	if is_instance_valid(_asset_utility):
		return _asset_utility

	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility
	return _asset_utility


static func _get_type_hint_for_path(config_path: String, registry: GFResourceRegistry) -> String:
	if not is_instance_valid(registry):
		return _MODE_TYPE_HINT

	for entry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		if entry.path == config_path:
			return entry.type_hint if not entry.type_hint.is_empty() else _MODE_TYPE_HINT

	return _MODE_TYPE_HINT


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()
