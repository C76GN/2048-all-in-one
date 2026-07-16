## GameModeCatalogUtility: 提供类型安全的游戏模式资源目录。
##
## 资源缓存、解析和卸载完全委托给 ProjectResourceCatalogUtility 与 GFAssetUtility。
class_name GameModeCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const DEFAULT_MODE_REGISTRY: GFResourceRegistry = preload("res://features/gameplay/resources/registries/game_mode_registry.tres")

const _CATALOG_ID: StringName = &"game_modes"
const _MODE_CONFIG_GROUP_ID: StringName = &"game_modes"
const _MODE_RESOURCE_KEY_PREFIX: String = "game.mode_config."
const _MODE_TYPE_HINT: String = "GameModeConfig"


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _mode_registry: GFResourceRegistry = DEFAULT_MODE_REGISTRY


# --- Godot 生命周期方法 ---

func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		push_error("[GameModeCatalogUtility] ProjectResourceCatalogUtility 未注册。")
		return

	var report: GFValidationReport = _resource_catalog.register_catalog(
		_CATALOG_ID,
		_mode_registry,
		_MODE_RESOURCE_KEY_PREFIX,
		_MODE_TYPE_HINT,
		_MODE_CONFIG_GROUP_ID,
		{"registry": "game_mode_registry"}
	)
	if not report.is_ok():
		push_error("[GameModeCatalogUtility] 模式资源目录注册失败：%s" % report.make_summary())


func dispose() -> void:
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID, true)
	_resource_catalog = null


# --- 公共方法 ---

## 获取指定路径的模式配置资源。
## @param config_path: 已登记到模式目录的资源路径。
func get_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty() or not is_instance_valid(_resource_catalog):
		return null

	var resource: Resource = _resource_catalog.load_resource_by_path(_CATALOG_ID, config_path)
	if resource is GameModeConfig:
		var mode_config: GameModeConfig = resource
		return mode_config
	push_error("[GameModeCatalogUtility] 模式配置加载失败：%s。" % config_path)
	return null


## 获取当前注册表中的配置路径列表。
func get_registered_config_paths() -> PackedStringArray:
	if not is_instance_valid(_resource_catalog):
		return PackedStringArray()
	return _resource_catalog.get_registered_paths(_CATALOG_ID, true)


## 获取模式注册表调试快照。
func get_debug_snapshot() -> Dictionary:
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_mode_registry):
		registry_snapshot = _mode_registry.get_debug_snapshot()

	var resource_keys: PackedStringArray = PackedStringArray()
	if is_instance_valid(_resource_catalog):
		resource_keys = _resource_catalog.get_registered_resource_keys(_CATALOG_ID)
	return {
		"registry": registry_snapshot,
		"resource_keys": resource_keys,
		"catalog_id": String(_CATALOG_ID),
	}


# --- 私有/辅助方法 ---

func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null
