## GameArchitectureInstaller: registers the project-wide GF modules.
class_name GameArchitectureInstaller
extends GFInstaller


# --- Public Methods ---

func install(architecture: GFArchitecture) -> void:
	_register_utilities(architecture)
	_register_models(architecture)
	_register_systems(architecture)


# --- Private Methods ---

func _register_utilities(architecture: GFArchitecture) -> void:
	architecture.register_utility(GFStorageUtility, GFStorageUtility.new())
	architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	architecture.register_utility(GFAssetUtility, GFAssetUtility.new())

	var history_util := GFCommandHistoryUtility.new()
	history_util.max_history_size = 0
	architecture.register_utility(GFCommandHistoryUtility, history_util)

	architecture.register_utility(GFTimeUtility, GFTimeUtility.new())
	architecture.register_utility(GFLogUtility, GFLogUtility.new())
	architecture.register_utility(GFSceneUtility, GFSceneUtility.new())
	architecture.register_utility(GFUIUtility, GFUIUtility.new())
	architecture.register_utility(GFLevelUtility, GFLevelUtility.new())
	architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	architecture.register_utility(GFInputMappingUtility, GFInputMappingUtility.new())

	var object_pool := GFObjectPoolUtility.new()
	object_pool.max_available_per_scene = 128
	architecture.register_utility(GFObjectPoolUtility, object_pool)

	if _are_dev_tools_enabled():
		architecture.register_utility(TestToolUtility, TestToolUtility.new())
		architecture.register_utility(GFConsoleUtility, GFConsoleUtility.new())


func _register_models(architecture: GFArchitecture) -> void:
	architecture.register_model(AppConfigModel, AppConfigModel.new())
	architecture.register_model(GridModel, GridModel.new())
	architecture.register_model(GameStatusModel, GameStatusModel.new())
	architecture.register_model(CurrentGameModel, CurrentGameModel.new())


func _register_systems(architecture: GFArchitecture) -> void:
	architecture.register_system(GameStateSystem, GameStateSystem.new())
	architecture.register_system(SceneRouterSystem, SceneRouterSystem.new())
	architecture.register_system(SaveSystem, SaveSystem.new())
	architecture.register_system(BookmarkSystem, BookmarkSystem.new())
	architecture.register_system(ReplaySystem, ReplaySystem.new())
	architecture.register_system(GameFlowSystem, GameFlowSystem.new())
	architecture.register_system(GridMovementSystem, GridMovementSystem.new())
	architecture.register_system(GFActionQueueSystem, GFActionQueueSystem.new())
	architecture.register_system(RuleSystem, RuleSystem.new())
	architecture.register_system(GridSpawnSystem, GridSpawnSystem.new())
	architecture.register_system(GameInitSystem, GameInitSystem.new())
	architecture.register_system(PlayerInputSystem, PlayerInputSystem.new())
	architecture.register_system(ReplayInputSystem, ReplayInputSystem.new())


func _are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")
