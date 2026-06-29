## GameModeConfigCacheUtility: 提供 GameModeConfig 资源注册表访问。
##
## 统一处理模式配置注册表、类型校验与运行时缓存，并优先复用 GFAssetUtility 的资源缓存。
class_name GameModeConfigCacheUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


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
	_asset_utility = _resolve_asset_utility()
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
	var cache: GameModeConfigCacheUtility = _get_registered_cache()
	if is_instance_valid(cache):
		return cache.get_cached_config(config_path)

	return _get_fallback_config(config_path)


## 获取模式注册表中的配置路径列表。
## @return: 按注册表顺序排列的 GameModeConfig 资源路径。
static func get_config_paths() -> PackedStringArray:
	var cache: GameModeConfigCacheUtility = _get_registered_cache()
	if is_instance_valid(cache):
		return cache.get_registered_config_paths()

	return _get_registry_config_paths(DEFAULT_MODE_REGISTRY)


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
	var cache: GameModeConfigCacheUtility = _get_registered_cache()
	if is_instance_valid(cache):
		cache.clear_runtime_cache()

	_fallback_config_cache.clear()
	_fallback_missing_paths.clear()


## 清空当前 Utility 维护的运行时缓存。
func clear_runtime_cache() -> void:
	_local_config_cache.clear()
	_missing_paths.clear()


# --- 私有/辅助方法 ---

static func _get_registered_cache() -> GameModeConfigCacheUtility:
	var architecture: GFArchitecture = GFAutoload.get_architecture_or_null()
	if architecture == null:
		return null

	var cache_script: Script = _load_cache_script()
	if cache_script == null:
		return null

	var cache_value: Object = architecture.get_utility(cache_script)
	if cache_value is GameModeConfigCacheUtility:
		var cache: GameModeConfigCacheUtility = cache_value
		return cache
	return null


static func _get_fallback_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	if _fallback_config_cache.has(config_path):
		var cached_value: Variant = _fallback_config_cache[config_path]
		if cached_value is GameModeConfig:
			var cached_config: GameModeConfig = cached_value
			if is_instance_valid(cached_config):
				return cached_config
		var _erase_result: bool = _fallback_config_cache.erase(config_path)

	if _fallback_missing_paths.has(config_path):
		return null

	var mode_config: GameModeConfig = _load_config_from_registry_static(config_path, DEFAULT_MODE_REGISTRY)
	if is_instance_valid(mode_config):
		_fallback_config_cache[config_path] = mode_config
		return mode_config

	_fallback_missing_paths[config_path] = true
	return null


static func _get_registry_config_paths(registry: GFResourceRegistry) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not is_instance_valid(registry):
		return result

	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		var config_path: String = entry.path
		if ResourceLoader.exists(config_path):
			var _append_result: bool = result.append(config_path)
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

	if resource is GameModeConfig:
		var mode_config: GameModeConfig = resource
		return mode_config
	return null


func _get_cached_config_from_asset_utility(config_path: String) -> GameModeConfig:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if not is_instance_valid(asset_utility):
		return null

	var cached_resource: Variant = asset_utility.get_cached(config_path)
	if cached_resource is GameModeConfig:
		var mode_config: GameModeConfig = cached_resource
		return mode_config
	return null


func _cache_config(config_path: String, mode_config: GameModeConfig) -> void:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if is_instance_valid(asset_utility):
		asset_utility.put_cache(config_path, mode_config)
		return

	_local_config_cache[config_path] = mode_config


func _load_config_from_registry(config_path: String) -> GameModeConfig:
	return _load_config_from_registry_static(config_path, _mode_registry)


func _register_mode_group_paths() -> void:
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if not is_instance_valid(asset_utility) or not is_instance_valid(_mode_registry):
		return

	for entry: GFResourceRegistryEntry in _mode_registry.entries:
		if not _is_valid_registry_entry(entry):
			continue

		asset_utility.register_group_path(_MODE_CONFIG_GROUP_ID, entry.path, true)


func _get_asset_utility() -> GFAssetUtility:
	if is_instance_valid(_asset_utility):
		return _asset_utility

	_asset_utility = _resolve_asset_utility()
	return _asset_utility


func _resolve_asset_utility() -> GFAssetUtility:
	var utility_value: Object = get_utility(GFAssetUtility)
	if utility_value is GFAssetUtility:
		var asset_utility: GFAssetUtility = utility_value
		return asset_utility
	return null


static func _load_cache_script() -> Script:
	var script_value: Variant = load(_SCRIPT_PATH)
	if script_value is Script:
		var cache_script: Script = script_value
		return cache_script
	return null


static func _get_type_hint_for_path(config_path: String, registry: GFResourceRegistry) -> String:
	if not is_instance_valid(registry):
		return _MODE_TYPE_HINT

	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		if entry.path == config_path:
			return entry.type_hint if not entry.type_hint.is_empty() else _MODE_TYPE_HINT

	return _MODE_TYPE_HINT


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()


static func _array_to_packed_string_array(values: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		if value is String:
			var string_value: String = value
			var _append_result: bool = result.append(string_value)
	return result
