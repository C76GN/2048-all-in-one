## GameArchitectureInstaller: 注册项目级 GF 模块。
class_name GameArchitectureInstaller
extends "res://addons/gf/kernel/core/gf_installer.gd"


# --- 常量 ---

const _VERBOSE_LOGGING_FEATURE: String = "verbose_logging"
const _DEV_TOOLS_FEATURE: String = "with_dev_tools"
const _PLATFORM_SMOKE_FEATURE: String = "platform_smoke"
const _DEV_TOOLS_INSTALLER_PATH: String = (
	"res://features/diagnostics/scripts/installers/game_diagnostics_installer.gd"
)
const _COMMAND_HISTORY_LIMIT: int = 1024
const _ASSET_CACHE_CAPACITY: int = 256
const _ASSET_MAX_CONCURRENT_LOADS: int = 4
const _PROJECT_CONTENT_CATALOG_UTILITY_SCRIPT: Script = preload("res://shared/scripts/utilities/project_content_catalog_utility.gd")
const _PROJECT_RESOURCE_CATALOG_UTILITY_SCRIPT: Script = preload("res://shared/scripts/utilities/project_resource_catalog_utility.gd")
const _GAME_CLOCK_UTILITY_SCRIPT: Script = preload("res://shared/scripts/utilities/game_clock_utility.gd")
const _LOCAL_ACCOUNT_CATALOG_UTILITY_SCRIPT: Script = preload(
	"res://features/player_profiles/scripts/utilities/local_account_catalog_utility.gd"
)
const _LOCAL_ACCOUNT_SYSTEM_SCRIPT: Script = preload(
	"res://features/player_profiles/scripts/systems/local_account_system.gd"
)
const _GAME_SAVE_GRAPH_UTILITY_SCRIPT: Script = preload("res://features/persistence/scripts/utilities/game_save_graph_utility.gd")
const _GAME_MODE_CATALOG_UTILITY_SCRIPT: Script = preload("res://features/gameplay/scripts/utilities/game_mode_catalog_utility.gd")
const _GAME_DETERMINISM_UTILITY_SCRIPT: Script = preload("res://features/gameplay/scripts/utilities/game_determinism_utility.gd")
const _GAME_PERFORMANCE_TRACE_UTILITY_SCRIPT: Script = preload(
	"res://features/gameplay/scripts/utilities/game_performance_trace_utility.gd"
)
const _TILE_CATALOG_UTILITY_SCRIPT: Script = preload("res://features/tile_catalog/scripts/utilities/tile_catalog_utility.gd")
const _ACHIEVEMENT_CATALOG_UTILITY_SCRIPT: Script = preload("res://features/achievements/scripts/utilities/achievement_catalog_utility.gd")
const _GAME_PAUSE_UTILITY_SCRIPT: Script = preload("res://features/gameplay/scripts/utilities/game_pause_utility.gd")
const _GAME_INPUT_PROFILE_UTILITY_SCRIPT: Script = preload("res://features/settings/scripts/utilities/game_input_profile_utility.gd")
const _GAME_ACCESSIBILITY_UTILITY_SCRIPT: Script = preload("res://features/settings/scripts/utilities/game_accessibility_utility.gd")
const _GAME_ACCESSIBILITY_SUMMARY_UTILITY_SCRIPT: Script = preload(
	"res://features/accessibility/scripts/utilities/game_accessibility_summary_utility.gd"
)
const _GAME_BOARD_ANIMATION_UTILITY_SCRIPT: Script = preload("res://features/gameplay/scripts/utilities/game_board_animation_utility.gd")
const _TILE_COMPOSITION_UTILITY_SCRIPT: Script = preload("res://features/gameplay/scripts/tiles/utilities/tile_composition_utility.gd")
const _GAME_UI_ROUTER_UTILITY_SCRIPT: Script = preload("res://features/navigation/scripts/utilities/game_ui_router_utility.gd")
const _GAME_UI_STYLE_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_ui_style_utility.gd")
const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_ui_motion_utility.gd")
const _GAME_BOARD_FEEDBACK_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_board_feedback_utility.gd")
const _GAME_ASSET_LIBRARY_UTILITY_SCRIPT: Script = preload("res://features/asset_library/scripts/utilities/game_asset_library_utility.gd")
const _GAME_BACKGROUND_MUSIC_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_background_music_utility.gd"
)
const _GAME_CELEBRATION_VFX_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_celebration_vfx_utility.gd")
const _GAME_THEME_CATALOG_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_catalog_utility.gd")
const _GAME_THEME_UTILITY_SCRIPT: Script = preload("res://features/themes/scripts/utilities/game_theme_utility.gd")
const _GAME_PLATFORM_UTILITY_SCRIPT: Script = preload("res://features/platform_runtime/scripts/utilities/game_platform_utility.gd")


# --- 私有变量 ---

var _clock: GFClock = GFClock.new()


# --- 公共方法 ---

## 配置 gf.save 扩展已经注册的共享 Storage。
##
## GF 11 的扩展 Installer 先于项目 Installer 执行；项目必须配置同一实例，
## 不能再注册第二份 Storage，否则 Profile 依赖可能绑定到默认配置。
## @param architecture: GF 尚未发布的候选架构。
## @param scope: 本轮安装的协作取消作用域。
func install(architecture: GFArchitecture, scope: GFAsyncScope) -> void:
	if architecture == null or scope == null:
		var invalid_reason: String = (
			"[GameArchitectureInstaller] install 失败：候选架构或 scope 为空。"
		)
		if architecture != null:
			architecture.fail_initialization(invalid_reason)
		else:
			push_error(invalid_reason)
		if scope != null:
			var _cancelled_invalid_install: bool = scope.cancel(
				"project_storage_configuration_invalid"
			)
		return
	if scope.is_cancel_requested():
		return
	var storage_value: Object = architecture.get_local_utility(
		GFStorageUtility
	)
	if not storage_value is GFStorageUtility:
		var missing_storage_reason: String = (
			"[GameArchitectureInstaller] gf.save 未提供 GFStorageUtility。"
		)
		# GF 11.0.0-dev.0 仅取消 Installer scope 时不会保证 installers-running
		# 收敛；显式失败候选架构可让本轮启动确定终结并允许后续重试。
		architecture.fail_initialization(missing_storage_reason)
		var _cancelled_missing_storage: bool = scope.cancel(
			"project_storage_dependency_missing"
		)
		return
	var storage: GFStorageUtility = storage_value
	_configure_storage_utility(storage)


## 使用声明式 Binder 注册项目级 Model、Utility 和 System。
## @param binder: GF 传入的绑定器实例。
## @param scope: GF 为本次安装创建的可取消异步作用域。
func install_bindings(binder: Variant, scope: GFAsyncScope) -> void:
	if not binder is GFBinder:
		push_error("[GameArchitectureInstaller] install_bindings 失败：binder 为空或类型错误。")
		return
	if scope == null:
		push_error("[GameArchitectureInstaller] install_bindings 失败：scope 为空。")
		return
	if scope.is_cancel_requested():
		return
	var gf_binder: GFBinder = binder

	await _bind_models(gf_binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_utilities(gf_binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_systems(gf_binder, scope)
	if scope.is_cancel_requested():
		return


# --- 私有/辅助方法 ---

func _bind_models(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_model(AppConfigModel).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_model(GridModel).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_model(GameStatusModel).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_model(CurrentGameModel).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_utilities(binder: GFBinder, scope: GFAsyncScope) -> void:
	await _bind_runtime_foundation_utilities(binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_content_and_gameplay_utilities(binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_presentation_utilities(binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_input_and_platform_utilities(binder, scope)
	if scope.is_cancel_requested():
		return

	if _are_dev_tools_enabled():
		await _install_dev_tools(binder, scope)
		if scope.is_cancel_requested():
			return


func _bind_runtime_foundation_utilities(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_utility(GFResourceBroker).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFBackgroundWorkUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	var operation_diagnostics_binding: GFBindBuilder = binder.bind_utility(
		GFOperationDiagnosticsUtility
	)
	operation_diagnostics_binding = operation_diagnostics_binding.from_instance(
		_create_operation_diagnostics_utility()
	)
	await operation_diagnostics_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GameSettingsUtility).from_instance(_create_settings_utility()).with_alias(GFSettingsUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFDisplaySettingsUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFViewportUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFAudioUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	if OS.has_feature(_PLATFORM_SMOKE_FEATURE):
		await binder.bind_utility(GFHttpClientUtility).as_singleton()
		if scope.is_cancel_requested():
			return
	await binder.bind_utility(GFSeedUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFAssetUtility).from_instance(_create_asset_utility()).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFResourceResolverUtility).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_content_and_gameplay_utilities(binder: GFBinder, scope: GFAsyncScope) -> void:
	var content_catalog_binding: GFBindBuilder = (
		binder.bind_utility(_PROJECT_CONTENT_CATALOG_UTILITY_SCRIPT)
	)
	content_catalog_binding = content_catalog_binding.from_instance(
		_create_project_content_catalog_utility()
	)
	await content_catalog_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFShaderParameterUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFSignalUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFNotificationUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFDiagnosticsUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFSessionTraceUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	var performance_trace_binding: GFBindBuilder = binder.bind_utility(
		_GAME_PERFORMANCE_TRACE_UTILITY_SCRIPT
	)
	await performance_trace_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_PROJECT_RESOURCE_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFTimeUtility).from_instance(_create_time_utility()).as_singleton()
	if scope.is_cancel_requested():
		return
	var game_clock_binding: GFBindBuilder = binder.bind_utility(
		_GAME_CLOCK_UTILITY_SCRIPT
	).from_instance(
		_create_game_clock_utility()
	)
	await game_clock_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_LOCAL_ACCOUNT_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_SAVE_GRAPH_UTILITY_SCRIPT).from_instance(_create_game_save_graph_utility()).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_MODE_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_DETERMINISM_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_TILE_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_ACHIEVEMENT_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_TILE_COMPOSITION_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFCommandHistoryUtility).from_instance(_create_history_utility()).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_PAUSE_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFLogUtility).from_instance(_create_log_utility()).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_presentation_utilities(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_utility(GFBuildInfoUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFSceneUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFRenderWarmupUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFScreenTransitionUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFUIUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_UI_ROUTER_UTILITY_SCRIPT).with_alias(GFUIRouterUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_ASSET_LIBRARY_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_BACKGROUND_MUSIC_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_ACCESSIBILITY_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_ACCESSIBILITY_SUMMARY_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_UI_STYLE_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_UI_MOTION_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_BOARD_FEEDBACK_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_CELEBRATION_VFX_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_THEME_CATALOG_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_THEME_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_input_and_platform_utilities(binder: GFBinder, scope: GFAsyncScope) -> void:
	var platform_runtime_binding: GFBindBuilder = binder.bind_utility(GFPlatformRuntime).from_instance(
		_create_platform_runtime()
	)
	await platform_runtime_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFInputDeviceUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFInputMappingUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFInputAssistUtility).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_INPUT_PROFILE_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_BOARD_ANIMATION_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(_GAME_PLATFORM_UTILITY_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_utility(GFObjectPoolUtility).from_instance(_create_object_pool_utility()).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_systems(binder: GFBinder, scope: GFAsyncScope) -> void:
	await _bind_state_and_navigation_systems(binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_progression_systems(binder, scope)
	if scope.is_cancel_requested():
		return
	await _bind_gameplay_systems(binder, scope)
	if scope.is_cancel_requested():
		return


func _bind_state_and_navigation_systems(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_system(GameStateSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(SceneRouterSystem).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_progression_systems(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_system(_LOCAL_ACCOUNT_SYSTEM_SCRIPT).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(ProgressStatsSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(BookmarkSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(CustomBoardSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(ReplaySystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(TileDiscoverySystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(TileLabSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(AchievementSystem).as_singleton()
	if scope.is_cancel_requested():
		return


func _bind_gameplay_systems(binder: GFBinder, scope: GFAsyncScope) -> void:
	await binder.bind_system(GameFlowSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(GridMovementSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(RuleSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(GameTurnSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(GridSpawnSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(GameInitSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(PlayerInputSystem).as_singleton()
	if scope.is_cancel_requested():
		return
	await binder.bind_system(ReplayInputSystem).as_singleton()
	if scope.is_cancel_requested():
		return


func _configure_storage_utility(storage: GFStorageUtility) -> void:
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.save_version = 1


func _create_time_utility() -> GFTimeUtility:
	var time_utility: GFTimeUtility = GFTimeUtility.new()
	var _clock_set: bool = time_utility.set_clock(_clock)
	return time_utility


func _create_asset_utility() -> GFAssetUtility:
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	asset_utility.max_cache_size = _ASSET_CACHE_CAPACITY
	asset_utility.default_max_concurrent_loads = _ASSET_MAX_CONCURRENT_LOADS
	return asset_utility


func _create_game_clock_utility() -> GameClockUtility:
	var clock_utility: GameClockUtility = GameClockUtility.new()
	var _clock_set: bool = clock_utility.set_clock(_clock)
	return clock_utility


func _create_platform_runtime() -> GFPlatformRuntime:
	return GFPlatformRuntime.new(_clock)


func _create_game_save_graph_utility() -> GameSaveGraphUtility:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	save_graph.auto_load_legacy_profile_on_ready = false
	var progress_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GameSaveGraphUtility.SectionOrder.EARLY
	)
	var bookmarks_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		BookmarkCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var custom_boards_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID,
		CustomBoardCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var discoveries_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		TileDiscoverySaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var tile_blueprints_registered: bool = save_graph.register_section(
		TileLabSaveData.SECTION_ID,
		TileLabSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var achievements_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID,
		AchievementSaveData.new(),
		GameSaveGraphUtility.SectionOrder.LATE
	)
	var replays_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		ReplayCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.LATE
	)
	if (
		not progress_registered
		or not bookmarks_registered
		or not custom_boards_registered
		or not discoveries_registered
		or not tile_blueprints_registered
		or not achievements_registered
		or not replays_registered
	):
		push_error("[GameArchitectureInstaller] 玩家数据 GFSaveProfile provider 注册失败。")
	return save_graph


func _create_project_content_catalog_utility() -> ProjectContentCatalogUtility:
	var catalog: ProjectContentCatalogUtility = ProjectContentCatalogUtility.new()
	return catalog.configure_source_roots(PackedStringArray([
		"res://features/asset_library/resources",
		"res://features/themes/resources",
		"user://content_packages",
	]))


func _create_settings_utility() -> GameSettingsUtility:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	var _clock_set: bool = settings.set_clock(_clock)
	settings.register_project_defaults()
	return settings


func _create_operation_diagnostics_utility() -> GFOperationDiagnosticsUtility:
	var diagnostics: GFOperationDiagnosticsUtility = (
		GFOperationDiagnosticsUtility.new()
	)
	diagnostics.max_completed_operations = 32
	diagnostics.max_active_operations = 16
	diagnostics.max_incidents = 32
	diagnostics.max_state_trace_entries = 16
	diagnostics.max_sample_stats = 64
	diagnostics.max_metadata_keys = 12
	diagnostics.slow_operation_threshold_ms = 100.0
	return diagnostics


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


func _are_dev_tools_enabled() -> bool:
	return OS.has_feature(_DEV_TOOLS_FEATURE)


func _install_dev_tools(binder: GFBinder, scope: GFAsyncScope) -> void:
	var installer_resource: Resource = ResourceLoader.load(
		_DEV_TOOLS_INSTALLER_PATH,
		"GDScript",
		ResourceLoader.CACHE_MODE_REUSE
	)
	if not installer_resource is GDScript:
		push_error(
			"[GameArchitectureInstaller] diagnostics Installer 加载失败：%s。"
			% _DEV_TOOLS_INSTALLER_PATH
		)
		return
	var installer_script: GDScript = installer_resource
	var installer_value: Variant = installer_script.new()
	if not installer_value is GFInstaller:
		push_error("[GameArchitectureInstaller] diagnostics Installer 无法实例化。")
		return
	var installer: GFInstaller = installer_value
	# 唯一反射边界：保持 diagnostics 脚本在 with_dev_tools 之外不进入解析依赖链。
	var install_callback: Callable = Callable(installer, &"install_bindings")
	await install_callback.call(binder, scope)
	if scope.is_cancel_requested():
		return


func _is_verbose_logging_enabled() -> bool:
	return OS.has_feature(_VERBOSE_LOGGING_FEATURE)
