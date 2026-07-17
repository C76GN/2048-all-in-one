## 验证游戏模式配置通过 GFResourceRegistry 暴露并接入 GFAssetUtility 分组。
extends GutTest


# --- 常量 ---

const EXPECTED_MODE_CONFIG_PATHS: Array[String] = [
	"res://features/gameplay/resources/modes/classic_mode_config.tres",
	"res://features/gameplay/resources/modes/fibonacci_mode_config.tres",
	"res://features/gameplay/resources/modes/lucas_fibonacci_mode_config.tres",
	"res://features/gameplay/resources/modes/progressive_mode_config.tres",
	"res://features/gameplay/resources/modes/step_by_step_mode_config.tres",
	"res://features/gameplay/resources/modes/ratio_mode_config.tres",
]

const EXPECTED_MODE_RESOURCE_KEYS: Array[String] = [
	"game.mode_config.classic",
	"game.mode_config.fibonacci",
	"game.mode_config.lucas_fibonacci",
	"game.mode_config.progressive",
	"game.mode_config.step_by_step",
	"game.mode_config.ratio",
]


# --- 测试用例 ---

func test_registered_mode_paths_match_registry_order() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var mode_paths: PackedStringArray = mode_catalog.get_registered_config_paths()

	assert_true(
		_packed_paths_to_array(mode_paths) == EXPECTED_MODE_CONFIG_PATHS,
		"模式配置路径应由 GFResourceRegistry 按注册顺序提供。"
	)

	architecture.dispose()


func test_registered_mode_paths_load_valid_game_mode_configs() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	for config_path: String in mode_catalog.get_registered_config_paths():
		var mode_config: GameModeConfig = mode_catalog.get_config(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		assert_true(mode_config.validate(), "注册表中的模式配置应通过自身校验: %s" % config_path)

	architecture.dispose()


func test_classic_style_modes_define_optional_2048_target() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	for config_path: String in mode_catalog.get_registered_config_paths():
		var mode_config: GameModeConfig = mode_catalog.get_config(config_path)
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
			assert_true(not mode_config.is_target_reached(floori(float(expected_target) / 2.0)), "未达到目标值时不应判定目标达成。")

	architecture.dispose()


func test_mode_registry_registers_asset_group_paths_when_utility_is_ready() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var asset_utility: GFAssetUtility = _get_asset_utility(setup)

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"game_modes")
	var sorted_group_paths: Array[String] = _packed_paths_to_array(group_paths)
	var sorted_expected_paths: Array[String] = EXPECTED_MODE_CONFIG_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_true(sorted_group_paths == sorted_expected_paths, "模式缓存 Utility ready 后应把注册表路径登记为 GFAssetUtility 分组。")

	architecture.dispose()


func test_mode_registry_registers_resolver_resource_keys_when_utility_is_ready() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resolver(setup)

	for resource_key: String in EXPECTED_MODE_RESOURCE_KEYS:
		assert_true(
			resolver.has_registered_key(StringName(resource_key)),
			"模式缓存 Utility ready 后应把模式配置注册为 GFResourceResolverUtility 资源键: %s" % resource_key
		)

	var resource: Resource = resolver.load(&"game.mode_config.classic", "Resource")
	assert_true(resource is GameModeConfig, "应能通过稳定资源键加载经典模式配置。")

	architecture.dispose()


func test_mode_validation_rejects_unknown_spawn_definition_reference() -> void:
	var resource: Resource = load("res://features/gameplay/resources/modes/ratio_mode_config.tres")
	assert_true(resource is GameModeConfig, "应加载比值模式配置。")
	if not resource is GameModeConfig:
		return
	var mode_config: GameModeConfig = resource.duplicate(true)
	var ratio_spawn_rule: ProbabilisticRatioSpawnRule = null
	for spawn_rule: SpawnRule in mode_config.spawn_rules:
		if spawn_rule is ProbabilisticRatioSpawnRule:
			ratio_spawn_rule = spawn_rule
			break
	assert_not_null(ratio_spawn_rule, "比值模式应包含概率因子方块生成规则。")
	if ratio_spawn_rule == null:
		return
	ratio_spawn_rule.alternate_definition_id = &"tile.ratio.unknown"

	var report: GFValidationReport = mode_config.get_validation_report()
	assert_false(report.is_ok(), "生成规则引用未声明定义时模式配置必须无效。")
	assert_true(
		GFVariantData.get_option_int(report.get_issue_counts_by_kind(), &"unknown_spawn_definition_id") == 1,
		"模式校验应明确报告未知的生成 definition_id。"
	)


# --- 私有/辅助方法 ---

func _create_mode_catalog_setup() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var mode_catalog: GameModeCatalogUtility = GameModeCatalogUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameModeCatalogUtility, mode_catalog)
	await architecture.init()

	return {
		"architecture": architecture,
		"asset_utility": asset_utility,
		"resolver": resolver,
		"catalog": catalog,
		"mode_catalog": mode_catalog,
	}


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_asset_utility(setup: Dictionary) -> GFAssetUtility:
	var value: Variant = setup.get("asset_utility")
	if value is GFAssetUtility:
		var asset_utility: GFAssetUtility = value
		return asset_utility
	assert_true(false, "测试 setup 缺少 GFAssetUtility。")
	return GFAssetUtility.new()


func _get_resolver(setup: Dictionary) -> GFResourceResolverUtility:
	var value: Variant = setup.get("resolver")
	if value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = value
		return resolver
	assert_true(false, "测试 setup 缺少 GFResourceResolverUtility。")
	return GFResourceResolverUtility.new()


func _get_mode_catalog(setup: Dictionary) -> GameModeCatalogUtility:
	var value: Variant = setup.get("mode_catalog")
	if value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = value
		return mode_catalog
	assert_true(false, "测试 setup 缺少 GameModeCatalogUtility。")
	return GameModeCatalogUtility.new()


func _packed_paths_to_array(paths: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for path: String in paths:
		result.append(path)
	return result


func _get_expected_target_for_mode(config_path: String) -> int:
	match config_path:
		"res://features/gameplay/resources/modes/classic_mode_config.tres":
			return 2048
		"res://features/gameplay/resources/modes/progressive_mode_config.tres":
			return 2048
		"res://features/gameplay/resources/modes/step_by_step_mode_config.tres":
			return 2048
		_:
			return 0
