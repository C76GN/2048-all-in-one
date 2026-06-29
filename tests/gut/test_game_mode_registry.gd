## 验证游戏模式配置通过 GFResourceRegistry 暴露并接入 GFAssetUtility 分组。
extends GutTest


# --- 常量 ---

const EXPECTED_MODE_CONFIG_PATHS: Array[String] = [
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

	assert_true(
		_packed_paths_to_array(mode_paths) == EXPECTED_MODE_CONFIG_PATHS,
		"模式配置路径应由 GFResourceRegistry 按注册顺序提供。"
	)


func test_registered_mode_paths_load_valid_game_mode_configs() -> void:
	for config_path: String in GameModeConfigCacheUtility.get_config_paths():
		var mode_config: GameModeConfig = GameModeConfigCacheUtility.get_config(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		assert_true(mode_config.validate(), "注册表中的模式配置应通过自身校验: %s" % config_path)


func test_classic_style_modes_define_optional_2048_target() -> void:
	for config_path: String in GameModeConfigCacheUtility.get_config_paths():
		var mode_config: GameModeConfig = GameModeConfigCacheUtility.get_config(config_path)
		var expected_target: int = _get_expected_target_for_mode(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		if not is_instance_valid(mode_config):
			continue
		assert_true(
			mode_config.target_tile_value == expected_target,
			"模式目标值应与玩法语义一致: %s" % config_path
		)
		assert_true(
			mode_config.has_target() == (expected_target > 0),
			"has_target() 应仅在配置目标值时返回 true: %s" % config_path
		)
		if expected_target > 0:
			assert_true(mode_config.is_target_reached(expected_target), "达到目标值时应判定目标达成。")
			assert_true(not mode_config.is_target_reached(int(expected_target / 2)), "未达到目标值时不应判定目标达成。")


func test_mode_registry_registers_asset_group_paths_when_utility_is_ready() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var mode_cache: GameModeConfigCacheUtility = GameModeConfigCacheUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GameModeConfigCacheUtility, mode_cache)
	await architecture.init()

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"game_modes")
	var sorted_group_paths: Array[String] = _packed_paths_to_array(group_paths)
	var sorted_expected_paths: Array[String] = EXPECTED_MODE_CONFIG_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_true(sorted_group_paths == sorted_expected_paths, "模式缓存 Utility ready 后应把注册表路径登记为 GFAssetUtility 分组。")

	architecture.dispose()


# --- 私有/辅助方法 ---

func _packed_paths_to_array(paths: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for path: String in paths:
		result.append(path)
	return result


func _get_expected_target_for_mode(config_path: String) -> int:
	match config_path:
		"res://resources/modes/classic_mode_config.tres":
			return 2048
		"res://resources/modes/progressive_mode_config.tres":
			return 2048
		"res://resources/modes/step_by_step_mode_config.tres":
			return 2048
		_:
			return 0
