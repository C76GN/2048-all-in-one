## 验证方块定义目录、组合身份与严格发现数据契约。
extends GutTest


# --- 常量 ---

const EXPECTED_DEFINITION_IDS: Array[StringName] = [
	&"tile.classic.numeric",
	&"tile.fibonacci.numeric",
	&"tile.classic_fibonacci.hybrid",
	&"tile.lucas_fibonacci.hybrid",
	&"tile.ratio.base",
	&"tile.ratio.factor",
]
const TILE_CATALOG_DIALOG_SCENE: PackedScene = preload(
	"res://features/tile_catalog/scenes/ui/tile_catalog_dialog.tscn"
)


# --- 测试用例 ---

func test_tile_registry_loads_all_valid_definitions_in_order() -> void:
	var setup: Dictionary = await _create_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: TileCatalogUtility = _get_catalog(setup)

	assert_true(catalog.get_definition_ids() == EXPECTED_DEFINITION_IDS, "方块目录顺序应由 GF Resource Registry 决定。")
	assert_true(catalog.get_registered_definition_paths().size() == 6, "当前六个方块定义都应进入类型安全目录。")
	assert_true(catalog.get_validation_report().is_ok(), "方块目录和全部定义应通过严格校验。")
	for definition_id: StringName in EXPECTED_DEFINITION_IDS:
		assert_not_null(catalog.get_definition(definition_id), "注册定义应可按稳定 ID 解析：%s" % definition_id)

	architecture.dispose()


func test_all_mode_tile_definitions_are_covered_by_catalog() -> void:
	var setup: Dictionary = await _create_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: TileCatalogUtility = _get_catalog(setup)
	var mode_registry: GFResourceRegistry = load(
		"res://features/gameplay/resources/registries/game_mode_registry.tres"
	)

	for entry: GFResourceRegistryEntry in mode_registry.entries:
		var mode_config: GameModeConfig = load(entry.path)
		assert_not_null(mode_config, "模式配置应可加载：%s" % entry.path)
		if mode_config == null or mode_config.interaction_rule == null:
			continue
		for definition: TileDefinition in mode_config.interaction_rule.tile_definitions:
			assert_not_null(
				catalog.get_definition(definition.definition_id),
				"模式引用的方块定义必须登记到图鉴目录：%s" % definition.definition_id
			)

	architecture.dispose()


func test_composition_key_is_canonical_for_recipe_order() -> void:
	var left_ids: Array[StringName] = [
		&"tile.recipe.classic_merge",
		&"tile.recipe.fibonacci_merge",
	]
	var right_ids: Array[StringName] = [
		&"tile.recipe.fibonacci_merge",
		&"tile.recipe.classic_merge",
	]
	var left_key: String = TileCatalogUtility.make_composition_key(
		&"tile.classic_fibonacci.hybrid",
		left_ids
	)
	var right_key: String = TileCatalogUtility.make_composition_key(
		&"tile.classic_fibonacci.hybrid",
		right_ids
	)

	assert_false(left_key.is_empty(), "合法组合应生成稳定身份键。")
	assert_true(left_key == right_key, "Recipe 输入顺序不得改变组合身份。")
	assert_true(
		TileCatalogUtility.make_composition_key(&"tile.classic.numeric", [
			&"tile.recipe.classic_merge",
			&"tile.recipe.classic_merge",
		]).is_empty(),
		"重复 Recipe ID 必须使组合身份无效。"
	)


func test_composition_descriptor_projects_localized_recipe_metadata() -> void:
	var setup: Dictionary = await _create_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: TileCatalogUtility = _get_catalog(setup)
	var descriptor: Dictionary = catalog.get_composition_descriptor(
		&"tile.classic_fibonacci.hybrid",
		[&"tile.recipe.fibonacci_merge", &"tile.recipe.classic_merge"]
	)
	var recipes: Array = GFVariantData.get_option_array(descriptor, &"recipes")
	var presentation: Dictionary = GFVariantData.get_option_dictionary(
		descriptor,
		&"presentation"
	)

	assert_false(descriptor.is_empty(), "已登记定义的合法 Recipe 组合应可投影。")
	assert_true(recipes.size() == 2, "复合方块应暴露两个独立 Recipe 描述。")
	for recipe_value: Variant in recipes:
		var recipe: Dictionary = GFVariantData.as_dictionary(recipe_value)
		assert_true(
			GFVariantData.get_option_string_name(recipe, &"display_name_key") != &"",
			"图鉴 Recipe 描述必须提供本地化名称键。"
		)
	assert_true(
		GFVariantData.get_option_array(presentation, &"visual_layer_ids").size() == 2,
		"表现投影应保留两个语义标记层。"
	)

	architecture.dispose()


func test_discovery_save_data_round_trips_strict_records() -> void:
	var tile_record: TileDiscoveryRecord = TileDiscoveryRecord.create(
		&"tile.classic.numeric",
		[&"tile.recipe.classic_merge"],
		100,
		128
	)
	var topology: BoardTopology = BoardTopology.create_cross(2, 1, &"board.cross.five")
	var board_record: BoardDiscoveryRecord = BoardDiscoveryRecord.create(topology, 101)
	var provider: TileDiscoverySaveData = TileDiscoverySaveData.new()
	var section_data: Dictionary = {
		"tile_compositions": [tile_record.to_dict()],
		"board_topologies": [board_record.to_dict()],
	}

	assert_true(provider.replace_section_data(section_data) == OK, "合法发现记录应原子写入 section。")
	assert_true(provider.get_section_data() == section_data, "发现 section 应无损往返。")


func test_discovery_save_data_rejects_duplicate_and_unknown_fields() -> void:
	var record: TileDiscoveryRecord = TileDiscoveryRecord.create(
		&"tile.classic.numeric",
		[&"tile.recipe.classic_merge"],
		100,
		64
	)
	var provider: TileDiscoverySaveData = TileDiscoverySaveData.new()
	var valid_data: Dictionary = {
		"tile_compositions": [record.to_dict()],
		"board_topologies": [],
	}
	assert_true(provider.replace_section_data(valid_data) == OK, "前置合法发现数据应写入成功。")

	var duplicate_data: Dictionary = {
		"tile_compositions": [record.to_dict(), record.to_dict()],
		"board_topologies": [],
	}
	assert_true(provider.replace_section_data(duplicate_data) == ERR_INVALID_DATA, "重复组合键必须被拒绝。")
	var unknown_field_data: Dictionary = valid_data.duplicate(true)
	unknown_field_data["legacy"] = true
	assert_true(provider.replace_section_data(unknown_field_data) == ERR_INVALID_DATA, "未知根字段必须被拒绝。")
	assert_true(provider.get_section_data() == valid_data, "失败替换不得污染既有发现状态。")


func test_composition_observation_persists_and_reloads_discovery_progress() -> void:
	var save_dir_name: String = "gut_tile_discovery_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_discovery_setup(save_dir_name)
	var catalog: TileCatalogUtility = _get_catalog(setup)
	var composition: TileCompositionUtility = _get_composition(setup)
	var discovery: TileDiscoverySystem = _get_discovery_system(setup)
	var definition: TileDefinition = catalog.get_definition(&"tile.classic.numeric")
	var low_tile: TileState = composition.create_tile(definition, 2)
	var high_tile: TileState = composition.create_tile(definition, 128)

	assert_not_null(low_tile, "测试方块应创建成功。")
	assert_not_null(high_tile, "更高数值测试方块应创建成功。")
	var tile_records: Array[TileDiscoveryRecord] = discovery.get_tile_discoveries()
	assert_true(tile_records.size() == 1, "同一组合被多次观察时只应保留一条发现记录。")
	assert_true(tile_records[0].max_observed_value == 128, "发现记录应持续提升最高观察值。")

	var topology: BoardTopology = BoardTopology.create_cross(2, 1, &"board.catalog.cross")
	assert_true(discovery.observe_board(topology) == OK, "合法拓扑应可进入棋盘发现记录。")
	assert_true(discovery.observe_board(topology) == OK, "重复观察同一拓扑应幂等。")
	assert_true(discovery.get_board_discoveries().size() == 1, "同一稳定棋盘键只能保存一次。")

	composition.release_tile(low_tile)
	composition.release_tile(high_tile)
	_dispose_discovery_setup(setup, false)

	var reloaded: Dictionary = await _create_discovery_setup(save_dir_name)
	var reloaded_discovery: TileDiscoverySystem = _get_discovery_system(reloaded)
	var reloaded_records: Array[TileDiscoveryRecord] = reloaded_discovery.get_tile_discoveries()
	assert_true(reloaded_records.size() == 1, "重启架构后应从 SaveGraph 恢复方块发现记录。")
	assert_true(reloaded_records[0].max_observed_value == 128, "重载不得丢失最高观察值。")
	assert_true(
		reloaded_discovery.get_board_discoveries().size() == 1,
		"重启架构后应从 SaveGraph 恢复棋盘发现记录。"
	)
	_dispose_discovery_setup(reloaded)


func test_tile_catalog_dialog_renders_registry_and_adapts_layout() -> void:
	var setup: Dictionary = await _create_discovery_setup(
		"gut_tile_catalog_ui_%d" % Time.get_ticks_usec()
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel_node: Node = TILE_CATALOG_DIALOG_SCENE.instantiate()
	assert_true(panel_node is TileCatalogDialog, "图鉴场景根节点应使用强类型控制器。")
	if not panel_node is TileCatalogDialog:
		_dispose_discovery_setup(setup)
		return
	var panel: TileCatalogDialog = panel_node
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(1600.0, 900.0)
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var grid: GridContainer = panel.get_node(
		"OuterMargin/CatalogPanel/InnerMargin/RootVBox/Content/CatalogArea/CatalogScroll/CatalogGrid"
	) as GridContainer
	var content: BoxContainer = panel.get_node(
		"OuterMargin/CatalogPanel/InnerMargin/RootVBox/Content"
	) as BoxContainer
	var filters: BoxContainer = panel.get_node(
		"OuterMargin/CatalogPanel/InnerMargin/RootVBox/Filters"
	) as BoxContainer
	var catalog_area: VBoxContainer = content.get_node("CatalogArea") as VBoxContainer
	assert_true(grid.get_child_count() == EXPECTED_DEFINITION_IDS.size(), "图鉴应呈现目录中的全部基础组合。")
	assert_false(content.vertical, "宽屏图鉴应使用左右分栏。")
	assert_true(grid.columns == 3, "宽屏图鉴应使用三列卡片网格。")

	panel.size = Vector2(390.0, 844.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(content.vertical, "窄屏图鉴应切换为上下布局。")
	assert_true(filters.vertical, "窄屏筛选控件应纵向排列，避免最小宽度相互挤压。")
	assert_true(
		catalog_area.custom_minimum_size.is_equal_approx(Vector2.ZERO),
		"窄屏目录区不得保留桌面最小宽度。"
	)
	assert_true(grid.columns == 1, "窄屏图鉴应使用单列卡片。")

	context.remove_child(panel)
	panel.queue_free()
	await get_tree().process_frame
	_dispose_discovery_setup(setup)


# --- 私有/辅助方法 ---

func _create_catalog_setup() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = GFAssetUtility.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var resource_catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var tile_catalog: TileCatalogUtility = TileCatalogUtility.new()

	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, resource_catalog)
	await architecture.register_utility(TileCatalogUtility, tile_catalog)
	await architecture.init()
	return {
		"architecture": architecture,
		"catalog": tile_catalog,
	}


func _create_discovery_setup(save_dir_name: String) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var tile_catalog: TileCatalogUtility = TileCatalogUtility.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var discovery: TileDiscoverySystem = TileDiscoverySystem.new()

	storage.save_dir_name = save_dir_name
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	assert_true(
		save_graph.register_section(
			GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
			TileDiscoverySaveData.new(),
			GFSaveScope.Phase.NORMAL
		),
		"发现系统测试应注册独立 SaveGraph section。"
	)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, GFSaveGraphUtility.new())
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFViewportUtility, GFViewportUtility.new())
	await architecture.register_utility(GFAssetUtility, GFAssetUtility.new())
	await architecture.register_utility(GFResourceResolverUtility, GFResourceResolverUtility.new())
	await architecture.register_utility(
		ProjectResourceCatalogUtility,
		ProjectResourceCatalogUtility.new()
	)
	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCatalogUtility, tile_catalog)
	await architecture.register_utility(TileCompositionUtility, composition)
	await architecture.register_system(TileDiscoverySystem, discovery)
	await architecture.init()
	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"catalog": tile_catalog,
		"composition": composition,
		"discovery": discovery,
	}


func _dispose_discovery_setup(
	setup: Dictionary,
	delete_profile: bool = true
) -> void:
	var save_graph_value: Variant = setup.get("save_graph")
	if save_graph_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = save_graph_value
		assert_true(
			save_graph.flush_pending_save() == OK,
			"发现系统测试结束前应收敛排队玩家数据。"
		)
	var storage_value: Variant = setup.get("storage")
	if delete_profile and storage_value is GFStorageUtility:
		var storage: GFStorageUtility = storage_value
		var delete_error: Error = storage.delete_file(GameSaveGraphUtility.PROFILE_FILE_NAME)
		assert_true(
			delete_error == OK or delete_error == ERR_FILE_NOT_FOUND,
			"发现系统测试玩家数据应可清理。"
		)
	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_catalog(setup: Dictionary) -> TileCatalogUtility:
	var value: Variant = setup.get("catalog")
	if value is TileCatalogUtility:
		var catalog: TileCatalogUtility = value
		return catalog
	assert_true(false, "测试 setup 缺少 TileCatalogUtility。")
	return TileCatalogUtility.new()


func _get_composition(setup: Dictionary) -> TileCompositionUtility:
	var value: Variant = setup.get("composition")
	if value is TileCompositionUtility:
		var composition: TileCompositionUtility = value
		return composition
	assert_true(false, "测试 setup 缺少 TileCompositionUtility。")
	return TileCompositionUtility.new()


func _get_discovery_system(setup: Dictionary) -> TileDiscoverySystem:
	var value: Variant = setup.get("discovery")
	if value is TileDiscoverySystem:
		var discovery: TileDiscoverySystem = value
		return discovery
	assert_true(false, "测试 setup 缺少 TileDiscoverySystem。")
	return TileDiscoverySystem.new()
