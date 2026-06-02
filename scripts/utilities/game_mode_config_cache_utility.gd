## GameModeConfigCacheUtility: 提供 GameModeConfig 资源的轻量缓存访问。
##
## 统一处理模式配置的加载、类型校验与缺失路径缓存，并优先复用 GFAssetUtility 的资源缓存。
class_name GameModeConfigCacheUtility
extends GFUtility


# --- 常量 ---

const _SCRIPT_PATH: String = "res://scripts/utilities/game_mode_config_cache_utility.gd"


# --- 私有变量 ---

static var _fallback_config_cache: Dictionary = {}
static var _fallback_missing_paths: Dictionary = {}

var _asset_utility: GFAssetUtility = null
var _local_config_cache: Dictionary = {}
var _missing_paths: Dictionary = {}


# --- Godot 生命周期方法 ---

func ready() -> void:
	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility


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

	var mode_config := ResourceLoader.load(config_path) as GameModeConfig
	if is_instance_valid(mode_config):
		_cache_config(config_path, mode_config)
		return mode_config

	_missing_paths[config_path] = true
	return null


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

	var mode_config := ResourceLoader.load(config_path) as GameModeConfig
	if is_instance_valid(mode_config):
		_fallback_config_cache[config_path] = mode_config
		return mode_config

	_fallback_missing_paths[config_path] = true
	return null


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


func _get_asset_utility() -> GFAssetUtility:
	if is_instance_valid(_asset_utility):
		return _asset_utility

	_asset_utility = get_utility(GFAssetUtility) as GFAssetUtility
	return _asset_utility
