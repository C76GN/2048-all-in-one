## GameArchitectureInstaller: 注册项目级 GF 模块。
class_name GameArchitectureInstaller
extends GFInstaller


# --- 常量 ---

const _VERBOSE_LOGGING_FEATURE: String = "verbose_logging"
const _COMMAND_HISTORY_LIMIT: int = 1024
const _AUDIO_BUS_MASTER: String = "Master"
const _GAME_MODE_CONFIG_CACHE_UTILITY_SCRIPT = preload("res://scripts/utilities/game_mode_config_cache_utility.gd")


# --- 公共方法 ---

## 兼容 GFInstaller 的旧式安装入口；当前项目使用 install_bindings() 注册模块。
## @param _architecture: 当前 GF 架构实例。
func install(_architecture: GFArchitecture) -> void:
	pass


## 使用声明式 Binder 注册项目级 Model、Utility 和 System。
## @param binder: GF 传入的绑定器实例。
func install_bindings(binder: Variant) -> void:
	var gf_binder := binder as GFBinder
	if gf_binder == null:
		push_error("[GameArchitectureInstaller] install_bindings 失败：binder 为空或类型错误。")
		return

	await _bind_models(gf_binder)
	await _bind_utilities(gf_binder)
	await _bind_systems(gf_binder)


# --- 私有/辅助方法 ---

func _bind_models(binder: GFBinder) -> void:
	await binder.bind_model(AppConfigModel).as_singleton()
	await binder.bind_model(GridModel).as_singleton()
	await binder.bind_model(GameStatusModel).as_singleton()
	await binder.bind_model(CurrentGameModel).as_singleton()


func _bind_utilities(binder: GFBinder) -> void:
	await binder.bind_utility(GFStorageUtility).from_instance(_create_storage_utility()).as_singleton()
	await binder.bind_utility(GameSettingsUtility).from_instance(_create_settings_utility()).with_alias(GFSettingsUtility).as_singleton()
	await binder.bind_utility(GFDisplaySettingsUtility).as_singleton()
	await binder.bind_utility(GFSeedUtility).as_singleton()
	await binder.bind_utility(GFAssetUtility).as_singleton()
	await binder.bind_utility(_GAME_MODE_CONFIG_CACHE_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(GFCommandHistoryUtility).from_instance(_create_history_utility()).as_singleton()
	await binder.bind_utility(GFTimeUtility).as_singleton()
	await binder.bind_utility(GFLogUtility).from_instance(_create_log_utility()).as_singleton()
	await binder.bind_utility(GFSceneUtility).as_singleton()
	await binder.bind_utility(GFUIUtility).as_singleton()
	await binder.bind_utility(GFLevelUtility).as_singleton()
	await binder.bind_utility(GFSignalUtility).as_singleton()
	await binder.bind_utility(GFInputMappingUtility).as_singleton()
	await binder.bind_utility(GFObjectPoolUtility).from_instance(_create_object_pool_utility()).as_singleton()

	if _are_dev_tools_enabled():
		await binder.bind_utility(TestToolUtility).as_singleton()
		await binder.bind_utility(GFConsoleUtility).as_singleton()


func _bind_systems(binder: GFBinder) -> void:
	await binder.bind_system(GameStateSystem).as_singleton()
	await binder.bind_system(SceneRouterSystem).as_singleton()
	await binder.bind_system(SaveSystem).as_singleton()
	await binder.bind_system(BookmarkSystem).as_singleton()
	await binder.bind_system(ReplaySystem).as_singleton()
	await binder.bind_system(GameFlowSystem).as_singleton()
	await binder.bind_system(GridMovementSystem).as_singleton()
	await binder.bind_system(GFActionQueueSystem).as_singleton()
	await binder.bind_system(RuleSystem).as_singleton()
	await binder.bind_system(GridSpawnSystem).as_singleton()
	await binder.bind_system(GameInitSystem).as_singleton()
	await binder.bind_system(PlayerInputSystem).as_singleton()
	await binder.bind_system(ReplayInputSystem).as_singleton()


func _create_storage_utility() -> GFStorageUtility:
	var storage := GFStorageUtility.new()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.save_version = 1
	return storage


func _create_settings_utility() -> GameSettingsUtility:
	var settings := GameSettingsUtility.new()
	settings.register_setting(
		GFDisplaySettingsUtility.LOCALE_KEY,
		"zh",
		GFSettingDefinition.ValueType.STRING
	)
	settings.register_setting(
		StringName("audio/%s/volume" % _AUDIO_BUS_MASTER),
		1.0,
		GFSettingDefinition.ValueType.FLOAT
	)
	return settings


func _create_history_utility() -> GFCommandHistoryUtility:
	var history_util := GFCommandHistoryUtility.new()
	history_util.max_history_size = _COMMAND_HISTORY_LIMIT
	return history_util


func _create_log_utility() -> GFLogUtility:
	var log_utility := GFLogUtility.new()
	log_utility.min_level = (
		GFLogUtility.LogLevel.DEBUG
		if _is_verbose_logging_enabled()
		else GFLogUtility.LogLevel.INFO
	)
	return log_utility


func _create_object_pool_utility() -> GFObjectPoolUtility:
	var object_pool := GFObjectPoolUtility.new()
	object_pool.max_available_per_scene = 128
	return object_pool


func _are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")


func _is_verbose_logging_enabled() -> bool:
	return OS.has_feature(_VERBOSE_LOGGING_FEATURE)
