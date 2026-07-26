## 验证原创限步关卡包的目录、严格快照、确定性与黄金解法。
extends GutTest


# --- 常量 ---

const _CATALOG_PATH: String = (
	"res://features/levels/resources/limited_move_level_catalog.tres"
)
const _LEVEL_PATH_FORMAT: String = (
	"res://features/levels/resources/definitions/limited_level_%02d.tres"
)
const _GOLDEN_SOLUTIONS: Dictionary = {
	&"level.limited.01": [Vector2i.LEFT],
	&"level.limited.02": [Vector2i.LEFT, Vector2i.UP],
	&"level.limited.03": [Vector2i.RIGHT, Vector2i.DOWN],
	&"level.limited.04": [Vector2i.LEFT, Vector2i.LEFT],
	&"level.limited.05": [Vector2i.LEFT, Vector2i.UP],
	&"level.limited.06": [Vector2i.LEFT, Vector2i.UP],
	&"level.limited.07": [Vector2i.RIGHT, Vector2i.DOWN],
	&"level.limited.08": [Vector2i.LEFT, Vector2i.UP, Vector2i.UP],
	&"level.limited.09": [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.DOWN],
	&"level.limited.10": [Vector2i.LEFT, Vector2i.LEFT, Vector2i.UP, Vector2i.UP],
}


# --- 测试用例 ---

func test_catalog_has_ten_valid_original_levels_with_stable_chain() -> void:
	var utility: LimitedMoveLevelCatalogUtility = LimitedMoveLevelCatalogUtility.new()
	var catalog_resource: Resource = load(_CATALOG_PATH)
	assert_true(catalog_resource is GFLevelCatalog, "测试必须能加载 GFLevelCatalog。")
	if not catalog_resource is GFLevelCatalog:
		return
	utility._catalog = catalog_resource

	var report: GFValidationReport = utility.get_validation_report()
	assert_true(report.is_ok(), "全部原创限步关卡与 GF 目录必须通过严格校验。")
	var levels: Array[GFLevelEntry] = utility.get_levels()
	assert_eq(
		levels.size(),
		LimitedMoveLevelCatalogUtility.EXPECTED_LEVEL_COUNT,
		"关卡包必须恰好提供十关。"
	)
	assert_eq(utility.get_first_level_id(), &"level.limited.01", "首关 ID 必须稳定。")

	var fingerprints: Dictionary = {}
	for index: int in range(levels.size()):
		var entry: GFLevelEntry = levels[index]
		var definition: LimitedMoveLevelDefinition = utility.get_definition(
			entry.get_level_id()
		)
		assert_not_null(definition, "每个 GF 目录条目都必须解析项目关卡定义。")
		if not is_instance_valid(definition):
			continue
		var fingerprint: String = definition.get_content_fingerprint()
		assert_eq(fingerprint.length(), 64, "关卡内容指纹必须使用完整 SHA-256。")
		assert_false(
			fingerprints.has(fingerprint),
			"十关不得通过重复内容伪装成不同关卡。"
		)
		fingerprints[fingerprint] = true
		var expected_next: StringName = (
			levels[index + 1].get_level_id()
			if index + 1 < levels.size()
			else &""
		)
		assert_eq(
			utility.get_next_level_id(entry.get_level_id()),
			expected_next,
			"GFLevelCatalog 必须提供稳定的顺序关系。"
		)


func test_initial_snapshots_are_strict_and_semantically_deterministic() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	for level_number: int in range(1, 11):
		var definition: LimitedMoveLevelDefinition = _load_level(level_number)
		assert_not_null(definition, "关卡资源必须可加载。")
		if not is_instance_valid(definition):
			continue
		var first_snapshot: Dictionary = definition.build_initial_board_snapshot()
		var second_snapshot: Dictionary = definition.build_initial_board_snapshot()
		assert_true(
			GridModel.is_snapshot_envelope_valid(first_snapshot),
			"手工初始棋盘必须符合 GridModel 当前严格 schema。"
		)
		assert_true(
			GridModel.is_snapshot_envelope_valid(second_snapshot),
			"重复构建的初始棋盘必须继续符合严格 schema。"
		)
		assert_eq(
			determinism.calculate_board_checksum(first_snapshot),
			determinism.calculate_board_checksum(second_snapshot),
			"运行时 UUID 不得改变同一原创关卡的语义摘要。"
		)
		assert_eq(
			GFVariantData.get_option_array(first_snapshot, &"tiles").size(),
			definition.get_initial_tile_count(),
			"严格快照方块数必须与手工棋盘一致。"
		)


func test_all_golden_solutions_finish_within_declared_move_limits() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid: GridModel = GridModel.new()
	var movement_system: GridMovementSystem = GridMovementSystem.new()
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, TileCompositionUtility.new())
	await architecture.register_model(GridModel, grid)
	await architecture.register_system(GridMovementSystem, movement_system)
	await architecture.init()

	for level_number: int in range(1, 11):
		var definition: LimitedMoveLevelDefinition = _load_level(level_number)
		assert_not_null(definition, "黄金解法关卡资源必须可加载。")
		if not is_instance_valid(definition):
			continue
		var mode_config: GameModeConfig = definition.get_mode_config()
		var interaction_resource: Resource = mode_config.interaction_rule.duplicate(true)
		var movement_resource: Resource = mode_config.movement_rule.duplicate(true)
		assert_true(
			interaction_resource is InteractionRule
			and movement_resource is MovementRule,
			"关卡模式规则必须可独立复制。"
		)
		if (
			not interaction_resource is InteractionRule
			or not movement_resource is MovementRule
		):
			continue
		var interaction_rule: InteractionRule = interaction_resource
		var movement_rule: MovementRule = movement_resource
		assert_true(
			grid.initialize(
				definition.board_topology,
				interaction_rule,
				movement_rule
			),
			"黄金解法前必须初始化关卡棋盘。"
		)
		assert_true(
			grid.restore_from_snapshot(definition.build_initial_board_snapshot()),
			"黄金解法前必须原子恢复手工棋盘。"
		)

		var raw_solution: Variant = _GOLDEN_SOLUTIONS.get(definition.level_id)
		assert_true(raw_solution is Array, "每关必须声明黄金解法。")
		if not raw_solution is Array:
			continue
		var solution: Array = raw_solution
		assert_true(
			solution.size() <= definition.move_limit,
			"黄金解法不得超过关卡步数上限。"
		)
		for direction_value: Variant in solution:
			assert_true(direction_value is Vector2i, "黄金解法只能包含四向输入。")
			if direction_value is Vector2i:
				var direction: Vector2i = direction_value
				assert_not_null(
					movement_system.handle_move(direction),
					"黄金解法的每一步都必须是有效移动。"
				)
		assert_true(
			definition.is_completed(grid.get_max_tile_value()),
			"黄金解法必须合成声明的目标方块。"
		)

	architecture.dispose()


func test_gf_level_progress_unlocks_the_next_original_level() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var progress: GFLevelProgressModel = GFLevelProgressModel.new()
	var level_utility: GFLevelUtility = GFLevelUtility.new()
	await architecture.register_model(GFLevelProgressModel, progress)
	await architecture.register_utility(GFLevelUtility, level_utility)
	await architecture.register_utility(
		LimitedMoveLevelCatalogUtility,
		LimitedMoveLevelCatalogUtility.new()
	)
	await architecture.init()

	assert_true(
		level_utility.get_catalog() is GFLevelCatalog,
		"项目目录工具必须把原创关卡目录交给 GFLevelUtility。"
	)
	assert_true(
		progress.is_level_unlocked(&"level.limited.01"),
		"目录初始化时必须解锁首关。"
	)
	var level_data: Dictionary = level_utility.start_level(&"level.limited.01")
	assert_false(level_data.is_empty(), "GFLevelUtility 必须能从目录加载首关元数据。")
	level_utility.complete_current_level({
		&"moves": 1,
		&"target_tile": 4,
		&"content_fingerprint": _load_level(1).get_content_fingerprint(),
	})
	assert_true(progress.is_level_completed(&"level.limited.01"), "完成结果必须写入 GF 进度模型。")
	assert_true(progress.is_level_unlocked(&"level.limited.02"), "完成首关必须只解锁下一关。")
	assert_false(progress.is_level_unlocked(&"level.limited.03"), "不得跨关提前解锁。")

	architecture.dispose()


func test_invalid_level_contracts_are_rejected_without_runtime_mutation() -> void:
	var source: LimitedMoveLevelDefinition = _load_level(1)
	var duplicate_resource: Resource = source.duplicate(true)
	assert_true(
		duplicate_resource is LimitedMoveLevelDefinition,
		"关卡定义必须支持编辑器安全复制。"
	)
	if not duplicate_resource is LimitedMoveLevelDefinition:
		return
	var invalid: LimitedMoveLevelDefinition = duplicate_resource
	invalid.target_tile_value = 2
	assert_false(
		invalid.get_validation_report().is_ok(),
		"初始棋盘已满足的目标必须被拒绝。"
	)
	assert_true(
		invalid.build_initial_board_snapshot().is_empty(),
		"无效关卡不得产生可提交的运行时快照。"
	)


# --- 私有/辅助方法 ---

func _load_level(level_number: int) -> LimitedMoveLevelDefinition:
	var resource: Resource = load(_LEVEL_PATH_FORMAT % level_number)
	if resource is LimitedMoveLevelDefinition:
		return resource
	return null
