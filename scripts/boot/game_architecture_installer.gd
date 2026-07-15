## GameArchitectureInstaller: 注册项目级 GF 模块。
class_name GameArchitectureInstaller
extends "res://addons/gf/kernel/core/gf_installer.gd"


# --- 常量 ---

const _VERBOSE_LOGGING_FEATURE: String = "verbose_logging"
const _COMMAND_HISTORY_LIMIT: int = 1024
const _PROJECT_RESOURCE_CATALOG_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/project_resource_catalog_utility.gd")
const _GAME_CLOCK_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_clock_utility.gd")
const _GAME_SAVE_SLOT_WORKFLOW_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_save_slot_workflow_utility.gd")
const _GAME_MODE_CONFIG_CACHE_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_mode_config_cache_utility.gd")
const _SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/saved_resource_collection_utility.gd")
const _GAME_UI_ROUTER_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_ui_router_utility.gd")
const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_ui_motion_utility.gd")
const _GAME_BOARD_FEEDBACK_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_board_feedback_utility.gd")
const _GAME_ASSET_LIBRARY_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_asset_library_utility.gd")
const _GAME_CELEBRATION_VFX_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_celebration_vfx_utility.gd")
const _GAME_THEME_CATALOG_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_theme_catalog_utility.gd")
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_theme_utility.gd")
const _GAME_DIAGNOSTICS_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_diagnostics_utility.gd")


# --- 公共方法 ---

## 使用声明式 Binder 注册项目级 Model、Utility 和 System。
## @param binder: GF 传入的绑定器实例。
## @param _scope: GF 为本次安装创建的可取消异步作用域。
func install_bindings(binder: Variant, _scope: GFAsyncScope) -> void:
	if not binder is GFBinder:
		push_error("[GameArchitectureInstaller] install_bindings 失败：binder 为空或类型错误。")
		return
	var gf_binder: GFBinder = binder

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
	await binder.bind_utility(GFAudioUtility).as_singleton()
	await binder.bind_utility(GFSeedUtility).as_singleton()
	await binder.bind_utility(GFAssetUtility).as_singleton()
	await binder.bind_utility(GFResourceResolverUtility).as_singleton()
	await binder.bind_utility(GFShaderParameterUtility).as_singleton()
	await binder.bind_utility(GFSignalUtility).as_singleton()
	await binder.bind_utility(_PROJECT_RESOURCE_CATALOG_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_CLOCK_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_SAVE_SLOT_WORKFLOW_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_MODE_CONFIG_CACHE_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(GFCommandHistoryUtility).from_instance(_create_history_utility()).as_singleton()
	await binder.bind_utility(GFTimeUtility).as_singleton()
	await binder.bind_utility(GFLogUtility).from_instance(_create_log_utility()).as_singleton()
	await binder.bind_utility(GFBuildInfoUtility).as_singleton()
	await binder.bind_utility(GFSceneUtility).as_singleton()
	await binder.bind_utility(GFScreenTransitionUtility).as_singleton()
	await binder.bind_utility(GFUIUtility).as_singleton()
	await binder.bind_utility(_GAME_UI_ROUTER_UTILITY_SCRIPT).with_alias(GFUIRouterUtility).as_singleton()
	await binder.bind_utility(_GAME_UI_MOTION_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_BOARD_FEEDBACK_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_ASSET_LIBRARY_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_CELEBRATION_VFX_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_THEME_CATALOG_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(_GAME_THEME_UTILITY_SCRIPT).as_singleton()
	await binder.bind_utility(GFInputMappingUtility).as_singleton()
	await binder.bind_utility(GFObjectPoolUtility).from_instance(_create_object_pool_utility()).as_singleton()

	if _are_dev_tools_enabled():
		await binder.bind_utility(GFConsoleUtility).as_singleton()
		await binder.bind_utility(GFAsyncTrackerUtility).from_instance(_create_async_tracker_utility()).as_singleton()
		await binder.bind_utility(GFOperationDiagnosticsUtility).as_singleton()
		await binder.bind_utility(GFDiagnosticsUtility).as_singleton()
		await binder.bind_utility(GFSupportReportUtility).as_singleton()
		await binder.bind_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT).as_singleton()
		await binder.bind_utility(TestToolUtility).as_singleton()


func _bind_systems(binder: GFBinder) -> void:
	await binder.bind_system(GameStateSystem).as_singleton()
	await binder.bind_system(SceneRouterSystem).as_singleton()
	await binder.bind_system(SaveSystem).as_singleton()
	await binder.bind_system(BookmarkSystem).as_singleton()
	await binder.bind_system(ReplaySystem).as_singleton()
	await binder.bind_system(GameFlowSystem).as_singleton()
	await binder.bind_system(GridMovementSystem).as_singleton()
	await binder.bind_system(RuleSystem).as_singleton()
	await binder.bind_system(GridSpawnSystem).as_singleton()
	await binder.bind_system(GameInitSystem).as_singleton()
	await binder.bind_system(PlayerInputSystem).as_singleton()
	await binder.bind_system(ReplayInputSystem).as_singleton()


func _create_storage_utility() -> GFStorageUtility:
	var storage: GFStorageUtility = GFStorageUtility.new()
	storage.allow_absolute_paths = false
	storage.allow_resource_loads = true
	storage.allowed_resource_load_extensions = PackedStringArray(["tres"])
	storage.allowed_resource_load_type_hints = PackedStringArray(["BookmarkData", "ReplayData"])
	storage.create_directories_for_nested_paths = true
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.save_version = 1
	return storage


func _create_settings_utility() -> GameSettingsUtility:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()
	return settings


func _create_history_utility() -> GFCommandHistoryUtility:
	var history_util: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	history_util.max_history_size = _COMMAND_HISTORY_LIMIT
	return history_util


func _create_log_utility() -> GFLogUtility:
	var log_utility: GFLogUtility = GFLogUtility.new()
	log_utility.min_level = (
		GFLogUtility.LogLevel.DEBUG
		if _is_verbose_logging_enabled()
		else GFLogUtility.LogLevel.INFO
	)
	return log_utility


func _create_object_pool_utility() -> GFObjectPoolUtility:
	var object_pool: GFObjectPoolUtility = GFObjectPoolUtility.new()
	object_pool.max_available_per_scene = 128
	return object_pool


func _create_async_tracker_utility() -> GFAsyncTrackerUtility:
	var tracker: GFAsyncTrackerUtility = GFAsyncTrackerUtility.new()
	tracker.tracking_enabled = true
	tracker.stack_trace_enabled = _is_verbose_logging_enabled()
	return tracker


func _are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")


func _is_verbose_logging_enabled() -> bool:
	return OS.has_feature(_VERBOSE_LOGGING_FEATURE)
