## GameModeCatalogUtility: 提供类型安全的游戏模式资源目录。
##
## 资源缓存、解析和卸载完全委托给 ProjectResourceCatalogUtility 与 GFAssetUtility。
class_name GameModeCatalogUtility
extends GFUtility


# --- 常量 ---

const DEFAULT_MODE_REGISTRY: GFResourceRegistry = preload("res://features/gameplay/resources/registries/game_mode_registry.tres")

const _CATALOG_ID: StringName = &"game_modes"
const _MODE_CONFIG_GROUP_ID: StringName = &"game_modes"
const _MODE_RESOURCE_KEY_PREFIX: String = "game.mode_config."
const _MODE_TYPE_HINT: String = "Resource"


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _mode_registry: GFResourceRegistry = DEFAULT_MODE_REGISTRY
var _preload_session: GFAssetLoadSession = null
var _setup_failure_reason: StringName = &""


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [ProjectResourceCatalogUtility]


func ready() -> void:
	_preload_session = null
	_setup_failure_reason = &""
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		_setup_failure_reason = &"dependency_missing"
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
		_setup_failure_reason = &"registration_failed"
		push_error("[GameModeCatalogUtility] 模式资源目录注册失败：%s" % report.make_summary())
		return

	_preload_session = _resource_catalog.start_catalog_preload_session(
		_CATALOG_ID,
		{
			"plan_id": &"game_modes.preload",
			"max_concurrent_loads": 2,
			"lane_id": &"game_mode_catalog",
			"metadata": {"registry": "game_mode_registry"},
		}
	)
	if not is_instance_valid(_preload_session):
		_setup_failure_reason = &"session_unavailable"
		push_error("[GameModeCatalogUtility] 无法启动模式配置 GFAssetLoadSession。")


func dispose() -> void:
	var _rollback_started: bool = rollback_preload_session(&"catalog_disposed")
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID)
	_preload_session = null
	_resource_catalog = null
	_setup_failure_reason = &"disposed"


# --- 公共方法 ---

## 获取指定路径的模式配置资源。
## @param config_path: 已登记到模式目录的资源路径。
func get_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty() or not is_instance_valid(_resource_catalog):
		return null

	var resource: Resource = _resource_catalog.get_cached_resource_by_path(
		_CATALOG_ID,
		config_path
	)
	if resource is GameModeConfig:
		var mode_config: GameModeConfig = resource
		return mode_config
	if not _is_preload_in_progress():
		push_error("[GameModeCatalogUtility] 模式配置缓存不可用：%s。" % config_path)
	return null


## 返回本轮目录预载的框架事务句柄。句柄由 Utility 拥有；调用方只等待和读取。
func get_preload_session() -> GFAssetLoadSession:
	return _preload_session


## 请求回滚仍在进行的模式目录预载会话。
## @param reason: 写入 GF typed 终态的稳定回滚原因。
func rollback_preload_session(reason: StringName) -> bool:
	if not is_instance_valid(_preload_session) or _preload_session.is_completed():
		return false
	return _preload_session.rollback(reason)


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
	var preload_session_snapshot: Dictionary = _make_preload_session_snapshot()
	return {
		"registry": registry_snapshot,
		"resource_keys": resource_keys,
		"catalog_id": String(_CATALOG_ID),
		"preload_session": preload_session_snapshot,
		"setup_failure_reason": String(_setup_failure_reason),
	}


# --- 私有/辅助方法 ---

func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null


func _is_preload_in_progress() -> bool:
	return (
		is_instance_valid(_preload_session)
		and _preload_session.get_state() in [
			GFAssetLoadSession.State.CREATED,
			GFAssetLoadSession.State.LOADING,
			GFAssetLoadSession.State.ROLLBACK_PENDING,
		]
	)


func _make_preload_session_snapshot() -> Dictionary:
	if not is_instance_valid(_preload_session):
		return {}
	var result_snapshot: Dictionary = {}
	var result: GFAssetLoadSessionResult = _preload_session.get_result()
	if result != null:
		result_snapshot = result.to_dict()
	return {
		"session_id": String(_preload_session.get_session_id()),
		"group_id": String(_preload_session.get_group_id()),
		"state": _preload_session.get_state(),
		"completed": _preload_session.is_completed(),
		"load_report": _preload_session.get_load_report(),
		"result": result_snapshot,
	}
