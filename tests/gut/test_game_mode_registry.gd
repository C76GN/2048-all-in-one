## 验证游戏模式配置通过 GFResourceRegistry 暴露并接入 GFAssetUtility 分组。
extends GutTest


# --- 常量 ---

const EXPECTED_MODE_CONFIG_PATHS: Array = [
	"res://resources/modes/classic_mode_config.tres",
	"res://resources/modes/fibonacci_mode_config.tres",
	"res://resources/modes/lucas_fibonacci_mode_config.tres",
	"res://resources/modes/progressive_mode_config.tres",
	"res://resources/modes/step_by_step_mode_config.tres",
	"res://resources/modes/battle_mode_config.tres",
]


# --- 测试用例 ---

func test_registered_mode_paths_match_registry_order() -> void:
	var mode_paths: PackedStringArray = GameModeConfigCacheUtility.get_config_paths()

	assert_eq(Array(mode_paths), EXPECTED_MODE_CONFIG_PATHS, "模式配置路径应由 GFResourceRegistry 按注册顺序提供。")


func test_registered_mode_paths_load_valid_game_mode_configs() -> void:
	for config_path: String in GameModeConfigCacheUtility.get_config_paths():
		var mode_config: GameModeConfig = GameModeConfigCacheUtility.get_config(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		assert_true(mode_config.validate(), "注册表中的模式配置应通过自身校验: %s" % config_path)


func test_mode_registry_registers_asset_group_paths_when_utility_is_ready() -> void:
	var architecture := GFArchitecture.new()
	var asset_utility := GFAssetUtility.new()
	var mode_cache := GameModeConfigCacheUtility.new()

	architecture.register_utility(GFAssetUtility, asset_utility)
	architecture.register_utility(GameModeConfigCacheUtility, mode_cache)
	await architecture.init()

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"game_modes")
	var sorted_group_paths: Array = Array(group_paths)
	var sorted_expected_paths: Array = EXPECTED_MODE_CONFIG_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_eq(sorted_group_paths, sorted_expected_paths, "模式缓存 Utility ready 后应把注册表路径登记为 GFAssetUtility 分组。")

	architecture.dispose()
