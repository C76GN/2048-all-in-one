## 验证 GF Capability 驱动的方块组合、仲裁与严格快照恢复。
extends GutTest


# --- 常量 ---

const _CLASSIC_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/classic_numeric_tile.tres"
const _FIBONACCI_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/fibonacci_numeric_tile.tres"
const _HYBRID_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/classic_fibonacci_hybrid_tile.tres"
const _LUCAS_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/lucas_fibonacci_hybrid_tile.tres"
const _RATIO_BASE_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/ratio_base_tile.tres"
const _RATIO_FACTOR_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/ratio_factor_tile.tres"


# --- 测试用例 ---

func test_classic_recipe_creates_capabilities_and_resolves_merge() -> void:
	var setup: Dictionary = await _create_composition_architecture()
	var composition: TileCompositionUtility = _get_composition(setup)
	var capabilities: GFCapabilityUtility = _get_capabilities(setup)
	var definition: TileDefinition = _load_definition(_CLASSIC_DEFINITION_PATH)

	assert_true(definition.get_validation_report().is_ok(), "经典方块定义与 Recipe 应通过 GF 校验。")
	var source: TileState = composition.create_tile(definition, 2)
	var target: TileState = composition.create_tile(definition, 2)
	assert_not_null(source, "应创建经典源方块。")
	assert_not_null(target, "应创建经典目标方块。")
	assert_true(
		source.capability_recipe_ids == [&"tile.recipe.classic_merge"],
		"方块状态应记录实际挂载的 GF Recipe，而不是只依赖定义隐式推断。"
	)
	assert_true(capabilities.has_capability(source, ClassicMergeCapability), "经典 Recipe 应挂载 ClassicMergeCapability。")
	assert_true(composition.can_interact(source, target), "同值经典方块应可合并。")

	var result: Dictionary = composition.apply_interaction(source, target)
	var merged_value: Variant = GFVariantData.get_option_value(result, &"merged_tile")
	var merged_tile: TileState = merged_value if merged_value is TileState else null
	assert_true(target.value == 4, "经典能力应将目标数值翻倍。")
	assert_same(merged_tile, target, "经典合并应保留目标方块。")
	assert_true(GFVariantData.get_option_int(result, &"score") == 4, "经典合并应产生新值等额分数。")
	assert_false(capabilities.has_capability(source, ClassicMergeCapability), "被消耗方块应从 GF Capability 注册表释放。")

	_dispose_setup(setup)


func test_hybrid_tile_interacts_through_each_shared_capability_only() -> void:
	var setup: Dictionary = await _create_composition_architecture()
	var composition: TileCompositionUtility = _get_composition(setup)
	var classic: TileDefinition = _load_definition(_CLASSIC_DEFINITION_PATH)
	var fibonacci: TileDefinition = _load_definition(_FIBONACCI_DEFINITION_PATH)
	var hybrid: TileDefinition = _load_definition(_HYBRID_DEFINITION_PATH)

	var classic_tile: TileState = composition.create_tile(classic, 2)
	var fibonacci_tile: TileState = composition.create_tile(fibonacci, 2)
	assert_false(
		composition.can_interact(classic_tile, fibonacci_tile),
		"没有共享能力的经典与斐波那契方块不得仅凭数值相同合并。"
	)

	var hybrid_classic: TileState = composition.create_tile(hybrid, 2)
	assert_true(
		hybrid_classic.capability_recipe_ids.has(&"tile.recipe.classic_merge")
		and hybrid_classic.capability_recipe_ids.has(&"tile.recipe.fibonacci_merge"),
		"混合方块应由两个独立 GF Recipe 组合，而不是依赖专用复合能力。"
	)
	var presentation: Dictionary = hybrid.get_presentation_descriptor(
		hybrid_classic.capability_recipe_ids
	)
	assert_true(
		GFVariantData.get_option_array(presentation, &"visual_layer_ids").size() == 2,
		"混合规则应投影为独立视觉标记层，不应合并成不可拆卸的专用纹理。"
	)
	var classic_target: TileState = composition.create_tile(classic, 2)
	assert_true(composition.can_interact(hybrid_classic, classic_target), "混合方块应通过共享经典能力交互。")
	var classic_result: Dictionary = composition.apply_interaction(hybrid_classic, classic_target)
	assert_true(GFVariantData.get_option_int(classic_result, &"score") == 4, "混合方块的经典路径应生成 4。")

	var hybrid_fibonacci: TileState = composition.create_tile(hybrid, 2)
	var fibonacci_target: TileState = composition.create_tile(fibonacci, 3)
	assert_true(composition.can_interact(hybrid_fibonacci, fibonacci_target), "混合方块应通过共享斐波那契能力交互。")
	var fibonacci_result: Dictionary = composition.apply_interaction(hybrid_fibonacci, fibonacci_target)
	assert_true(GFVariantData.get_option_int(fibonacci_result, &"score") == 5, "混合方块的斐波那契路径应生成 5。")

	composition.release_tile(classic_tile)
	composition.release_tile(fibonacci_tile)
	composition.release_tile(classic_target)
	composition.release_tile(fibonacci_target)
	_dispose_setup(setup)


func test_lucas_and_ratio_definitions_mount_their_composed_rules() -> void:
	var setup: Dictionary = await _create_composition_architecture()
	var composition: TileCompositionUtility = _get_composition(setup)
	var capabilities: GFCapabilityUtility = _get_capabilities(setup)
	var lucas: TileDefinition = _load_definition(_LUCAS_DEFINITION_PATH)
	var ratio_base: TileDefinition = _load_definition(_RATIO_BASE_DEFINITION_PATH)
	var ratio_factor: TileDefinition = _load_definition(_RATIO_FACTOR_DEFINITION_PATH)

	var lucas_tile: TileState = composition.create_tile(lucas, 1)
	assert_true(capabilities.has_capability(lucas_tile, FibonacciMergeCapability), "卢卡斯模式应组合斐波那契能力。")
	assert_true(capabilities.has_capability(lucas_tile, LucasMergeCapability), "卢卡斯模式应组合卢卡斯能力。")
	assert_true(capabilities.has_capability(lucas_tile, LucasBridgeCapability), "卢卡斯模式应组合桥接能力。")

	var base_tile: TileState = composition.create_tile(ratio_base, 8)
	var factor_tile: TileState = composition.create_tile(ratio_factor, 2)
	var ratio_result: Dictionary = composition.apply_interaction(base_tile, factor_tile)
	var ratio_merged_value: Variant = GFVariantData.get_option_value(ratio_result, &"merged_tile")
	var ratio_merged_tile: TileState = ratio_merged_value if ratio_merged_value is TileState else null
	assert_same(ratio_merged_tile, base_tile, "较大数所在方块应承载求商结果。")
	assert_true(base_tile.value == 4, "跨定义规则应按 8 / 2 得到 4。")
	assert_true(base_tile.definition_id == ratio_base.definition_id, "求商不得改写结果方块的定义身份。")
	assert_true(GFVariantData.get_option_int(ratio_result, &"ratio_resolved") == 1, "求商结果应保留中性统计元数据。")
	assert_false(
		capabilities.has_capability(factor_tile, CrossDefinitionRatioCapability),
		"被消费方块的求商能力应从 GF 注册表释放。"
	)

	composition.release_tile(lucas_tile)
	composition.release_tile(base_tile)
	_dispose_setup(setup)


func test_ratio_definitions_are_rules_not_factions() -> void:
	var setup: Dictionary = await _create_composition_architecture()
	var composition: TileCompositionUtility = _get_composition(setup)
	var ratio_base: TileDefinition = _load_definition(_RATIO_BASE_DEFINITION_PATH)
	var ratio_factor: TileDefinition = _load_definition(_RATIO_FACTOR_DEFINITION_PATH)

	var same_definition_source: TileState = composition.create_tile(ratio_base, 2)
	var same_definition_target: TileState = composition.create_tile(ratio_base, 2)
	var addition_result: Dictionary = composition.apply_interaction(
		same_definition_source,
		same_definition_target
	)
	assert_true(same_definition_target.value == 4, "同定义方块应通过经典能力执行 2 + 2 = 4。")
	assert_false(addition_result.has(&"ratio_resolved"), "普通相加不应计入求商次数。")

	var cross_definition_source: TileState = composition.create_tile(ratio_base, 2)
	var cross_definition_target: TileState = composition.create_tile(ratio_factor, 2)
	var division_result: Dictionary = composition.apply_interaction(
		cross_definition_source,
		cross_definition_target
	)
	assert_true(cross_definition_target.value == 1, "跨定义方块应通过求商能力执行 2 / 2 = 1。")
	assert_true(GFVariantData.get_option_int(division_result, &"ratio_resolved") == 1, "跨定义求商应记录一次结算。")

	composition.release_tile(same_definition_target)
	composition.release_tile(cross_definition_target)
	_dispose_setup(setup)


func test_recipe_can_be_granted_and_revoked_at_runtime() -> void:
	var setup: Dictionary = await _create_composition_architecture()
	var composition: TileCompositionUtility = _get_composition(setup)
	var capabilities: GFCapabilityUtility = _get_capabilities(setup)
	var hybrid: TileDefinition = _load_definition(_HYBRID_DEFINITION_PATH).duplicate(true)
	hybrid.initial_recipe_ids = [&"tile.recipe.classic_merge"]

	var tile: TileState = composition.create_tile(hybrid, 2)
	assert_true(capabilities.has_capability(tile, ClassicMergeCapability), "初始 Recipe 应挂载经典能力。")
	assert_false(capabilities.has_capability(tile, FibonacciMergeCapability), "未授予的能力不得提前挂载。")

	assert_true(
		composition.grant_recipe(tile, hybrid, &"tile.recipe.fibonacci_merge"),
		"运行时应能通过定义目录授予新的 GF Recipe。"
	)
	assert_true(capabilities.has_capability(tile, FibonacciMergeCapability), "授予 Recipe 后应立即具备对应能力。")
	assert_true(capabilities.get_receiver_groups(tile).has(&"tile.fibonacci"), "授予 Recipe 应同步登记 GF 查询分组。")
	tile.capability_state[&"tile.recipe.fibonacci_merge"] = {&"acquired_from": &"consume"}

	assert_true(
		composition.revoke_recipe(tile, hybrid, &"tile.recipe.fibonacci_merge"),
		"运行时应能拆卸已授予的 GF Recipe。"
	)
	assert_false(capabilities.has_capability(tile, FibonacciMergeCapability), "拆卸 Recipe 后不得残留对应能力。")
	assert_false(capabilities.get_receiver_groups(tile).has(&"tile.fibonacci"), "拆卸 Recipe 后不得残留专属分组。")
	assert_true(capabilities.get_receiver_groups(tile).has(&"tile.classic"), "拆卸一个 Recipe 不得误删其他 Recipe 的分组。")
	assert_false(
		tile.capability_state.has(&"tile.recipe.fibonacci_merge"),
		"拆卸 Recipe 时应同步移除该 Recipe 的持久化状态命名空间。"
	)

	composition.release_tile(tile)
	_dispose_setup(setup)


func test_grid_snapshot_restores_definition_identity_and_recipe() -> void:
	var setup: Dictionary = await _create_composition_architecture(true)
	var composition: TileCompositionUtility = _get_composition(setup)
	var capabilities: GFCapabilityUtility = _get_capabilities(setup)
	var grid: GridModel = _get_grid(setup)
	var definition: TileDefinition = _load_definition(_CLASSIC_DEFINITION_PATH)
	var interaction_rule: ClassicInteractionRule = ClassicInteractionRule.new()
	interaction_rule.tile_definitions = [definition]
	interaction_rule.default_definition_id = definition.definition_id
	assert_true(
		grid.initialize(
			BoardTopology.create_rectangle(Vector2i(4, 4)),
			interaction_rule,
			ClassicMovementRule.new()
		),
		"快照测试棋盘应初始化成功。"
	)

	var original: TileState = composition.create_tile(definition, 8)
	original.capability_state[&"tile.recipe.classic_merge"] = {&"merge_count": 3}
	assert_true(grid.place_tile(original, Vector2i(1, 2)), "原始方块应放置成功。")
	var original_id: String = original.tile_id
	var snapshot: Dictionary = grid.get_snapshot()
	var serialized_tiles: Array = GFVariantData.get_option_array(snapshot, &"tiles")
	assert_true(serialized_tiles.size() == 1, "快照应包含当前方块。")
	if serialized_tiles.size() == 1 and serialized_tiles[0] is Dictionary:
		var serialized_tile: Dictionary = serialized_tiles[0]
		assert_false(serialized_tile.has(&"role") or serialized_tile.has(&"type"), "方块快照不得持久化阵营或角色字段。")
	assert_true(
		GFVariantData.get_option_int(snapshot, &"schema_version") == GridModel.SNAPSHOT_SCHEMA_VERSION,
		"棋盘快照应声明当前严格 schema。"
	)
	assert_true(grid.restore_from_snapshot(snapshot), "当前严格快照应恢复成功。")

	var restored: TileState = grid.get_tile(Vector2i(1, 2))
	assert_true(restored != null, "严格快照应恢复 TileState。")
	if restored != null:
		assert_true(restored.tile_id == original_id, "快照恢复应保留稳定 tile_id。")
		assert_true(restored.definition_id == definition.definition_id, "快照恢复应保留 definition_id。")
		assert_true(
			restored.capability_recipe_ids == [&"tile.recipe.classic_merge"],
			"快照恢复应保留实际挂载的 GF Recipe 清单。"
		)
		assert_true(
			GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					restored.capability_state,
					&"tile.recipe.classic_merge"
				),
				&"merge_count"
			) == 3,
			"快照恢复应保留 Recipe 隔离的能力状态。"
		)
		assert_true(capabilities.has_capability(restored, ClassicMergeCapability), "恢复时应按 Recipe 重建能力。")

	_dispose_setup(setup)


func test_grid_snapshot_rejects_legacy_fields_and_duplicate_ids_atomically() -> void:
	var setup: Dictionary = await _create_composition_architecture(true)
	var composition: TileCompositionUtility = _get_composition(setup)
	var grid: GridModel = _get_grid(setup)
	var definition: TileDefinition = _load_definition(_CLASSIC_DEFINITION_PATH)
	var interaction_rule: ClassicInteractionRule = ClassicInteractionRule.new()
	interaction_rule.tile_definitions = [definition]
	interaction_rule.default_definition_id = definition.definition_id
	assert_true(
		grid.initialize(
			BoardTopology.create_rectangle(Vector2i(4, 4)),
			interaction_rule,
			ClassicMovementRule.new()
		),
		"原子恢复测试棋盘应初始化成功。"
	)

	var original: TileState = composition.create_tile(definition, 8)
	assert_true(grid.place_tile(original, Vector2i(1, 2)), "原子恢复测试方块应放置成功。")
	var baseline: Dictionary = grid.get_snapshot()

	var legacy_snapshot: Dictionary = baseline.duplicate(true)
	var legacy_tiles: Array = legacy_snapshot[&"tiles"]
	var legacy_tile: Dictionary = legacy_tiles[0]
	legacy_tile[&"role"] = 0
	assert_false(grid.restore_from_snapshot(legacy_snapshot), "旧字段快照必须被拒绝。")
	assert_push_error("拒绝恢复不符合当前严格结构")
	assert_same(_get_grid_tile(grid, Vector2i(1, 2)), original, "拒绝旧字段后原棋盘必须保持不变。")

	var duplicate_snapshot: Dictionary = baseline.duplicate(true)
	var duplicate_tiles: Array = duplicate_snapshot[&"tiles"]
	var duplicate_source: Dictionary = duplicate_tiles[0]
	var duplicate_tile: Dictionary = duplicate_source.duplicate(true)
	duplicate_tile[&"pos"] = Vector2i(2, 2)
	duplicate_tiles.append(duplicate_tile)
	assert_false(grid.restore_from_snapshot(duplicate_snapshot), "重复 UUID 快照必须被拒绝。")
	assert_push_error("拒绝恢复不符合当前严格结构")
	assert_same(_get_grid_tile(grid, Vector2i(1, 2)), original, "拒绝重复 UUID 后原棋盘必须保持不变。")
	assert_null(_get_grid_tile(grid, Vector2i(2, 2)), "失败恢复不得写入部分新棋盘。")

	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _create_composition_architecture(include_grid: bool = false) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var capabilities: GFCapabilityUtility = GFCapabilityUtility.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var grid: GridModel = GridModel.new() if include_grid else null
	await architecture.register_utility(GFCapabilityUtility, capabilities)
	await architecture.register_utility(TileCompositionUtility, composition)
	if grid != null:
		await architecture.register_model(GridModel, grid)
	await architecture.init()
	return {
		&"architecture": architecture,
		&"capabilities": capabilities,
		&"composition": composition,
		&"grid": grid,
	}


func _load_definition(path: String) -> TileDefinition:
	var resource: Resource = load(path)
	if resource is TileDefinition:
		var definition: TileDefinition = resource
		return definition
	assert_true(false, "无法加载 TileDefinition：%s" % path)
	return null


func _get_composition(setup: Dictionary) -> TileCompositionUtility:
	var value: Variant = GFVariantData.get_option_value(setup, &"composition")
	if value is TileCompositionUtility:
		var composition: TileCompositionUtility = value
		return composition
	assert_true(false, "测试 setup 缺少 TileCompositionUtility。")
	return null


func _get_capabilities(setup: Dictionary) -> GFCapabilityUtility:
	var value: Variant = GFVariantData.get_option_value(setup, &"capabilities")
	if value is GFCapabilityUtility:
		var capabilities: GFCapabilityUtility = value
		return capabilities
	assert_true(false, "测试 setup 缺少 GFCapabilityUtility。")
	return null


func _get_grid(setup: Dictionary) -> GridModel:
	var value: Variant = GFVariantData.get_option_value(setup, &"grid")
	if value is GridModel:
		var grid: GridModel = value
		return grid
	assert_true(false, "测试 setup 缺少 GridModel。")
	return null


func _get_grid_tile(grid: GridModel, pos: Vector2i) -> TileState:
	return grid.get_tile(pos)


func _dispose_setup(setup: Dictionary) -> void:
	var architecture_value: Variant = GFVariantData.get_option_value(setup, &"architecture")
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()
	setup.clear()
