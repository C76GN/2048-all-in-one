## GameModeConfigCache: 提供 GameModeConfig 资源的轻量缓存访问。
##
## 统一处理模式配置的加载、类型校验与缺失路径缓存，减少菜单与列表预览中的重复加载逻辑。
extends RefCounted


# --- 私有变量 ---

static var _config_cache: Dictionary = {}
static var _missing_paths: Dictionary = {}


# --- 公共方法 ---

## 获取指定路径的模式配置资源。
## @param config_path: GameModeConfig 资源路径。
## @return: 成功时返回已缓存或新加载的 GameModeConfig，否则返回 null。
static func get_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	if _config_cache.has(config_path):
		var cached_config := _config_cache[config_path] as GameModeConfig
		if is_instance_valid(cached_config):
			return cached_config
		_config_cache.erase(config_path)

	if _missing_paths.has(config_path):
		return null

	var mode_config := load(config_path) as GameModeConfig
	if is_instance_valid(mode_config):
		_config_cache[config_path] = mode_config
		return mode_config

	_missing_paths[config_path] = true
	return null


## 清空全部缓存。
static func clear() -> void:
	_config_cache.clear()
	_missing_paths.clear()
