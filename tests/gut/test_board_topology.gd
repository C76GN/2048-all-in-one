## 验证稀疏棋盘拓扑、连续移动通道和相关系统边界。
extends GutTest


# --- 常量 ---

const _CLASSIC_DEFINITION_PATH: String = "res://features/gameplay/resources/tiles/definitions/classic_numeric_tile.tres"


# --- 测试用例 ---

func test_rectangle_topology_round_trips_with_stable_identity() -> void:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 3))
	var restored: BoardTopology = BoardTopology.from_dict(topology.to_dict())

	assert_true(topology.get_validation_report().is_ok(), "矩形拓扑应通过 GFValidationReport。")
	assert_true(topology.is_rectangle(), "完整矩形应被识别为矩形拓扑。")
	assert_true(topology.get_bounds_size() == Vector2i(4, 3), "矩形边界尺寸应保持宽高。")
	assert_true(topology.get_cell_count() == 12, "矩形活跃单元数应等于面积。")
	assert_true(restored != null, "当前严格拓扑 schema 应可反序列化。")
	if restored != null:
		assert_true(restored.get_active_cells() == topology.get_active_cells(), "拓扑往返不得改变活跃单元。")
		assert_true(restored.get_stable_key() == topology.get_stable_key(), "拓扑往返不得改变稳定统计键。")


func test_custom_topology_normalizes_origin_order_and_duplicate_input() -> void:
	var topology: BoardTopology = BoardTopology.create_custom(
		[
			Vector2i(5, 6),
			Vector2i(3, 4),
			Vector2i(5, 6),
			Vector2i(4, 4),
		]
	)

	assert_true(
		topology.get_active_cells() == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2)],
		"玩家绘制输入应统一平移、去重并按行优先排序。"
	)
	assert_true(topology.get_validation_report().is_ok(), "规范化自定义拓扑应有效。")
	assert_false(topology.is_rectangle(), "带空洞的自定义拓扑不应伪装成矩形。")
	var exposed_cells: Array[Vector2i] = topology.active_cells
	exposed_cells.clear()
	assert_true(topology.get_cell_count() == 3, "导出属性读取不得泄漏可变内部数组。")
	assert_true(topology.contains_cell(Vector2i(2, 2)), "替换前应先建立包含旧单元的查询缓存。")
	var previous_fingerprint: String = topology.get_content_fingerprint()
	topology.active_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	assert_false(topology.contains_cell(Vector2i(2, 2)), "同长度整体替换必须失效旧查询缓存。")
	assert_true(topology.contains_cell(Vector2i(1, 1)), "查询缓存应按替换后的活跃单元重建。")
	assert_true(topology.get_bounds_size() == Vector2i(2, 2), "整体替换必须失效包围盒缓存。")
	assert_true(topology.get_content_fingerprint() != previous_fingerprint, "整体替换必须失效内容指纹缓存。")

	var duplicate_payload: Dictionary = topology.to_dict()
	duplicate_payload[&"active_cells"] = [Vector2i.ZERO, Vector2i.ZERO]
	assert_null(BoardTopology.from_dict(duplicate_payload), "严格持久化结构必须拒绝重复活跃单元。")


func test_cross_topology_lanes_cover_every_active_cell_once() -> void:
	var topology: BoardTopology = BoardTopology.create_cross(2)
	var lanes: Array = topology.get_move_lanes(Vector2i.RIGHT)
	var coverage: Dictionary = {}

	for lane_value: Variant in lanes:
		assert_true(lane_value is Array, "移动 lane 必须是坐标数组。")
		if not lane_value is Array:
			continue
		var lane: Array = lane_value
		for cell_value: Variant in lane:
			assert_true(cell_value is Vector2i, "移动 lane 只能包含 Vector2i。")
			if cell_value is Vector2i:
				var cell: Vector2i = cell_value
				coverage[cell] = GFVariantData.get_option_int(coverage, cell, 0) + 1

	assert_true(topology.get_bounds_size() == Vector2i(5, 5), "十字棋盘应保留完整包围盒。")
	assert_true(topology.get_cell_count() == 9, "臂长 2、宽 1 的十字棋盘应有 9 个活跃单元。")
	assert_true(coverage.size() == topology.get_cell_count(), "所有活跃单元都必须进入一个移动 lane。")
	for count_value: Variant in coverage.values():
		assert_true(GFVariantData.to_int(count_value) == 1, "每个活跃单元在同一方向只能属于一个 lane。")
	assert_true(topology.get_move_lanes(Vector2i(1, 1)).is_empty(), "拓扑只接受四向移动。")


func test_gaps_split_movement_lanes() -> void:
	var topology: BoardTopology = BoardTopology.create_custom(
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(3, 0)],
		&"board.test.gapped"
	)
	var left_lanes: Array = topology.get_move_lanes(Vector2i.LEFT)

	assert_true(left_lanes.size() == 2, "空洞必须把同一行拆成两条独立 lane。")
	if left_lanes.size() == 2:
		var first_lane_matches: bool = false
		var second_lane_matches: bool = false
		var first_lane_value: Variant = left_lanes[0]
		var second_lane_value: Variant = left_lanes[1]
		if first_lane_value is Array:
			var first_lane: Array = first_lane_value
			first_lane_matches = first_lane == [Vector2i(0, 0)]
		if second_lane_value is Array:
			var second_lane: Array = second_lane_value
			second_lane_matches = second_lane == [Vector2i(2, 0), Vector2i(3, 0)]
		assert_true(first_lane_matches, "空洞左侧应形成独立 lane。")
		assert_true(second_lane_matches, "空洞右侧 lane 应从移动前沿向后排列。")


func test_sparse_topology_queries_only_cells_inside_visible_rect() -> void:
	var topology: BoardTopology = BoardTopology.create_custom(
		[
			Vector2i(0, 0),
			Vector2i(4, 0),
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(8, 5),
		],
		&"board.test.visible_window"
	)
	var visible_cells: Array[Vector2i] = topology.get_cells_in_rect(
		Rect2i(Vector2i(2, 1), Vector2i(2, 3))
	)

	assert_true(
		visible_cells == [Vector2i(2, 2), Vector2i(3, 2)],
		"可见窗口查询应只返回矩形内活跃单元，并保持行优先顺序。"
	)
	assert_true(
		topology.get_cells_in_rect(Rect2i(Vector2i(20, 20), Vector2i(3, 3))).is_empty(),
		"完全位于拓扑之外的可见窗口应返回空数组。"
	)
	assert_true(
		topology.get_cells_in_rect(Rect2i(Vector2i.ZERO, Vector2i.ZERO)).is_empty(),
		"空尺寸窗口不得返回活跃单元。"
	)


func test_topology_template_applies_bounds_to_custom_shapes() -> void:
	var template: BoardTopologyTemplate = BoardTopologyTemplate.new()
	template.template_id = &"board_template.test"
	template.default_size = Vector2i(4, 4)
	template.min_size = Vector2i(3, 3)
	template.max_size = Vector2i(8, 8)
	template.allow_custom_topology = true

	assert_true(template.accepts_topology(BoardTopology.create_cross(2)), "范围内十字棋盘应被自定义模板接受。")
	assert_false(
		template.accepts_topology(BoardTopology.create_custom([Vector2i(0, 0), Vector2i(3, 0)])),
		"自定义棋盘不得绕过模板最小包围盒。"
	)
	assert_false(
		template.accepts_topology(BoardTopology.create_rectangle(Vector2i(9, 9))),
		"任意形状都不得绕过模板最大包围盒。"
	)
	assert_true(
		BoardTopology.create_rectangle(Vector2i(BoardTopology.MAX_CELL_COUNT, 2)).get_cell_count() == 0,
		"矩形构造器必须在分配前拒绝超过安全上限的尺寸。"
	)
	var oversized_template: BoardTopologyTemplate = BoardTopologyTemplate.new()
	oversized_template.max_size = Vector2i(BoardTopology.MAX_CELL_COUNT, 2)
	assert_false(oversized_template.get_validation_report().is_ok(), "模板不得声明超出安全容量的矩形范围。")


func test_sparse_gameplay_systems_respect_active_cells_and_gaps() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid: GridModel = GridModel.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var movement_system: GridMovementSystem = GridMovementSystem.new()
	var spawn_system: GridSpawnSystem = GridSpawnSystem.new()

	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(TileCompositionUtility, composition)
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_model(GridModel, grid)
	await architecture.register_system(GridMovementSystem, movement_system)
	await architecture.register_system(GridSpawnSystem, spawn_system)
	await architecture.init()

	var definition: TileDefinition = _load_classic_definition()
	var interaction_rule: ClassicInteractionRule = ClassicInteractionRule.new()
	interaction_rule.tile_definitions = [definition]
	interaction_rule.default_definition_id = definition.definition_id
	var topology: BoardTopology = BoardTopology.create_custom(
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(3, 0)],
		&"board.test.gapped"
	)
	assert_true(
		grid.initialize(topology, interaction_rule, ClassicMovementRule.new()),
		"稀疏系统测试棋盘应初始化成功。"
	)

	var invalid_spawn: SpawnData = SpawnData.new()
	invalid_spawn.position = Vector2i(1, 0)
	invalid_spawn.value = 2
	spawn_system._on_spawn_tile_requested(invalid_spawn)
	assert_true(grid.get_all_tiles().is_empty(), "生成系统不得在拓扑空洞中创建方块。")

	var valid_spawn: SpawnData = SpawnData.new()
	valid_spawn.position = Vector2i(3, 0)
	valid_spawn.value = 2
	spawn_system._on_spawn_tile_requested(valid_spawn)
	var spawned_tile: TileState = grid.get_tile(Vector2i(3, 0))
	assert_true(spawned_tile != null, "生成系统应允许在活跃单元创建方块。")

	var move_data: MoveData = movement_system.handle_move(Vector2i.LEFT)
	assert_true(move_data != null, "右侧 lane 中的方块应产生有效移动。")
	assert_same(grid.get_tile(Vector2i(2, 0)), spawned_tile, "方块应移动到所属连续 lane 的前沿。")
	assert_null(grid.get_tile(Vector2i(0, 0)), "方块不得跨越空洞跳到另一条 lane。")

	if spawned_tile != null:
		spawned_tile.value = 4
	assert_true(
		grid.place_tile(composition.create_tile(definition, 2), Vector2i(0, 0)),
		"应能填充空洞左侧的独立活跃单元。"
	)
	assert_true(
		grid.place_tile(composition.create_tile(definition, 8), Vector2i(3, 0)),
		"应能填充右侧 lane 的末端。"
	)
	var game_over_rule: StandardGameOverRule = StandardGameOverRule.new()
	assert_true(game_over_rule.is_game_over(grid, interaction_rule), "满棋盘且真实相邻单元不可合并时应判负。")
	var trailing_tile: TileState = grid.get_tile(Vector2i(3, 0))
	if trailing_tile != null:
		trailing_tile.value = 4
	assert_false(game_over_rule.is_game_over(grid, interaction_rule), "真实相邻单元可合并时不得判负。")

	var snapshot: Dictionary = grid.get_snapshot()
	assert_true(GridModel.is_snapshot_envelope_valid(snapshot), "稀疏棋盘应生成当前严格快照。")
	assert_true(grid.restore_from_snapshot(snapshot), "稀疏棋盘快照应可原子恢复。")
	assert_true(grid.topology.get_stable_key() == topology.get_stable_key(), "快照恢复应保留拓扑身份。")
	assert_null(grid.get_tile(Vector2i(1, 0)), "快照恢复不得把空洞实体化。")

	architecture.dispose()


# --- 私有/辅助方法 ---

func _load_classic_definition() -> TileDefinition:
	var value: Resource = load(_CLASSIC_DEFINITION_PATH)
	if value is TileDefinition:
		var definition: TileDefinition = value
		return definition
	assert_true(false, "无法加载经典 TileDefinition。")
	return null
