## GamePerformanceAcceptanceHarness: 可重复的确定性热路径与生命周期平台验收工具。
##
## 采样统一记录到 GFMetricSeries；预算刻意宽松，只拦截数量级回退与持续增长，
## 不把共享 CI 上的微小计时波动当作产品缺陷。
class_name GamePerformanceAcceptanceHarness
extends RefCounted


# --- 常量 ---

const DEFAULT_CHECKPOINT_SAMPLE_COUNT: int = 36
const DEFAULT_CHECKPOINT_BATCH_SIZE: int = 3
const DEFAULT_FULL_TURN_SAMPLE_COUNT: int = 24
const DEFAULT_FULL_TURN_WARMUP_COUNT: int = 4
const DEFAULT_LIFECYCLE_CYCLES: int = 14
const DEFAULT_LIFECYCLE_WARMUP_CYCLES: int = 5

## Debug/headless 下仍应在 100ms P95 内完成；max 只拦截停顿级回退。
## 预算覆盖共享 CI 同时运行多个 Godot 进程时的抖动，不用于发布帧时 KPI。
const CHECKPOINT_P95_BUDGET_USEC: float = 100_000.0
const CHECKPOINT_MAX_BUDGET_USEC: float = 250_000.0
## 这是本机 headless/debug 的回归门禁，不是真机通过声明。正式性能证据仍由
## GamePerformanceTraceUtility 在完全匹配的观测矩阵中采集。
const FULL_TURN_P95_BUDGET_USEC: float = 16_667.0
const FULL_TURN_MAX_BUDGET_USEC: float = 50_000.0
const LIFECYCLE_NODE_TAIL_SPREAD_BUDGET: float = 8.0
const LIFECYCLE_RESOURCE_TAIL_SPREAD_BUDGET: float = 24.0
const LIFECYCLE_NODE_TAIL_GROWTH_BUDGET: float = 4.0
const LIFECYCLE_RESOURCE_TAIL_GROWTH_BUDGET: float = 12.0

const _TOPOLOGY_SIZES: Array[Vector2i] = [
	Vector2i(3, 3),
	Vector2i(4, 4),
	Vector2i(8, 8),
]
const _REPRESENTATIVE_SCENE_PATHS: PackedStringArray = [
	"res://features/themes/scenes/ui/board/board_grid_cell.tscn",
	"res://features/navigation/scenes/ui/mode_card.tscn",
	"res://features/bookmarks/scenes/ui/bookmark_list_item.tscn",
	"res://features/replays/scenes/ui/replay_list_item.tscn",
]


# --- 公共方法 ---

## 对注册模式 × 支持拓扑执行 checkpoint 热路径采样。
## @param sample_count: 每个 case 的计时样本数。
## @param batch_size: 单样本包含的 checkpoint 次数，用于降低计时器量化噪声。
func benchmark_checkpoint_generation(
	sample_count: int = DEFAULT_CHECKPOINT_SAMPLE_COUNT,
	batch_size: int = DEFAULT_CHECKPOINT_BATCH_SIZE
) -> Dictionary:
	var normalized_sample_count: int = maxi(sample_count, 12)
	var normalized_batch_size: int = maxi(batch_size, 1)
	var mode_paths: PackedStringArray = (
		GameModeCatalogUtility.DEFAULT_MODE_REGISTRY.get_all_paths()
	)
	var topology_rows: Array[Dictionary] = _make_topology_rows()
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var cases: Array[Dictionary] = []
	var all_passed: bool = not mode_paths.is_empty() and not topology_rows.is_empty()

	for mode_path: String in mode_paths:
		var mode_resource: Resource = load(mode_path)
		if not mode_resource is GameModeConfig:
			all_passed = false
			cases.append({
				&"case_id": mode_path,
				&"passed": false,
				&"reason": &"mode_load_failed",
			})
			continue
		var mode_config: GameModeConfig = mode_resource
		var ruleset_fingerprint: String = (
			determinism.calculate_ruleset_fingerprint(mode_config)
		)
		for topology_row: Dictionary in topology_rows:
			var topology_value: Variant = topology_row.get(&"topology")
			if not topology_value is BoardTopology:
				all_passed = false
				continue
			var topology: BoardTopology = topology_value
			var topology_id: StringName = GFVariantData.get_option_string_name(
				topology_row,
				&"id"
			)
			var case_id: String = "%s|%s" % [
				String(mode_config.ruleset_id),
				String(topology_id),
			]
			var full_state: Dictionary = _make_full_state(
				topology,
				mode_config,
				case_id.hash()
			)
			var series: GFMetricSeries = GFMetricSeries.new().configure(
				StringName("checkpoint_usec.%s" % case_id),
				{
					&"label": "Checkpoint generation (usec)",
					&"group": "Runtime acceptance",
					&"max_samples": normalized_sample_count,
					&"metadata": {
						&"mode_path": mode_path,
						&"topology_id": topology_id,
						&"batch_size": normalized_batch_size,
					},
				}
			)
			var checkpoints_valid: bool = true
			for _warmup_index: int in range(3):
				checkpoints_valid = (
					determinism.create_checkpoint_for_session(
						1,
						full_state,
						ruleset_fingerprint
					)
					!= null
					and checkpoints_valid
				)

			for sample_index: int in range(normalized_sample_count):
				var started_usec: int = Time.get_ticks_usec()
				for batch_index: int in range(normalized_batch_size):
					var checkpoint: ReplayCheckpoint = (
						determinism.create_checkpoint_for_session(
							sample_index * normalized_batch_size + batch_index + 1,
							full_state,
							ruleset_fingerprint
						)
					)
					checkpoints_valid = checkpoint != null and checkpoints_valid
				var elapsed_usec: int = Time.get_ticks_usec() - started_usec
				series.add_sample(
					float(elapsed_usec) / float(normalized_batch_size),
					float(sample_index),
					{&"case_id": case_id}
				)

			var statistics: Dictionary = _summarize_series(series)
			var case_passed: bool = (
				checkpoints_valid
				and GFVariantData.get_option_float(statistics, &"p95") <= (
					CHECKPOINT_P95_BUDGET_USEC
				)
				and GFVariantData.get_option_float(statistics, &"max") <= (
					CHECKPOINT_MAX_BUDGET_USEC
				)
			)
			all_passed = all_passed and case_passed
			cases.append({
				&"case_id": case_id,
				&"mode_path": mode_path,
				&"mode_id": mode_config.ruleset_id,
				&"topology_id": topology_id,
				&"passed": case_passed,
				&"statistics_usec": statistics,
				&"metric_series": series.to_dict(true, 16),
			})

	return {
		&"passed": all_passed,
		&"mode_count": mode_paths.size(),
		&"topology_count": topology_rows.size(),
		&"case_count": cases.size(),
		&"sample_count_per_case": normalized_sample_count,
		&"batch_size": normalized_batch_size,
		&"budgets_usec": {
			&"p95": CHECKPOINT_P95_BUDGET_USEC,
			&"max": CHECKPOINT_MAX_BUDGET_USEC,
		},
		&"cases": cases,
	}


## 验证冻结规则集热路径没有改变既有 checkpoint 字段或哈希。
func verify_checkpoint_hash_compatibility() -> Dictionary:
	var mode_paths: PackedStringArray = (
		GameModeCatalogUtility.DEFAULT_MODE_REGISTRY.get_all_paths()
	)
	var topology_rows: Array[Dictionary] = _make_topology_rows()
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var failures: Array[Dictionary] = []
	var checked_cases: int = 0
	for mode_path: String in mode_paths:
		var mode_resource: Resource = load(mode_path)
		if not mode_resource is GameModeConfig:
			failures.append({&"mode_path": mode_path, &"reason": &"mode_load_failed"})
			continue
		var mode_config: GameModeConfig = mode_resource
		var fingerprint: String = determinism.calculate_ruleset_fingerprint(
			mode_config
		)
		for topology_row: Dictionary in topology_rows:
			var topology_value: Variant = topology_row.get(&"topology")
			if not topology_value is BoardTopology:
				failures.append({
					&"mode_path": mode_path,
					&"reason": &"topology_missing",
				})
				continue
			var topology: BoardTopology = topology_value
			var full_state: Dictionary = _make_full_state(
				topology,
				mode_config,
				checked_cases + 2048
			)
			var compatibility: ReplayCheckpoint = determinism.create_checkpoint(
				1,
				full_state,
				mode_config
			)
			var session: ReplayCheckpoint = (
				determinism.create_checkpoint_for_session(
					1,
					full_state,
					fingerprint
				)
			)
			checked_cases += 1
			if (
				compatibility == null
				or session == null
				or compatibility.to_dict() != session.to_dict()
			):
				failures.append({
					&"mode_path": mode_path,
					&"topology_id": GFVariantData.get_option_string_name(
						topology_row,
						&"id"
					),
					&"reason": &"checkpoint_mismatch",
				})
	return {
		&"passed": failures.is_empty() and checked_cases > 0,
		&"checked_cases": checked_cases,
		&"failures": failures,
	}


## 在真实 GFCommandHistoryUtility + MoveCommand、项目规则、checkpoint 与
## 无障碍表现投影上测量经典 4x4 的同步完整回合。每个样本前的确定性恢复与
## 历史清理不计入回合时间；报告明确标为 desktop headless diagnostic，不能
## 代替微信真机的 120 样本验收证据。
## @param sample_count: 计时样本数，最低 12。
## @param warmup_count: 不进入统计的预热回合数，最低 2。
func benchmark_classic_4x4_full_turn(
	sample_count: int = DEFAULT_FULL_TURN_SAMPLE_COUNT,
	warmup_count: int = DEFAULT_FULL_TURN_WARMUP_COUNT
) -> Dictionary:
	var normalized_sample_count: int = maxi(sample_count, 12)
	var normalized_warmup_count: int = maxi(warmup_count, 2)
	var fixture: Dictionary = await _create_full_turn_fixture()
	if not GFVariantData.get_option_bool(fixture, &"ok"):
		return {
			&"passed": false,
			&"reason": GFVariantData.get_option_string_name(
				fixture,
				&"reason"
			),
			&"evidence_scope": &"desktop_headless_diagnostic",
		}

	var architecture_value: Variant = fixture.get(&"architecture")
	var grid_value: Variant = fixture.get(&"grid")
	var state_system_value: Variant = fixture.get(&"state_system")
	var rule_system_value: Variant = fixture.get(&"rule_system")
	var history_value: Variant = fixture.get(&"history")
	var flow_value: Variant = fixture.get(&"flow")
	var summary_value: Variant = fixture.get(&"summary")
	if not (
		architecture_value is GFArchitecture
		and grid_value is GridModel
		and state_system_value is GameStateSystem
		and rule_system_value is RuleSystem
		and history_value is GFCommandHistoryUtility
		and flow_value is InstrumentedGameFlowSystem
		and summary_value is GameAccessibilitySummaryUtility
	):
		return {
			&"passed": false,
			&"reason": &"fixture_type_mismatch",
			&"evidence_scope": &"desktop_headless_diagnostic",
		}
	var architecture: GFArchitecture = architecture_value
	var grid: GridModel = grid_value
	var state_system: GameStateSystem = state_system_value
	var rule_system: RuleSystem = rule_system_value
	var history: GFCommandHistoryUtility = history_value
	var flow: InstrumentedGameFlowSystem = flow_value
	var summary: GameAccessibilitySummaryUtility = summary_value
	var baseline_state: Dictionary = GFVariantData.get_option_dictionary(
		fixture,
		&"baseline_state"
	)
	var phase_ids: Array[StringName] = [
		&"command",
		&"turn_state_snapshot",
		&"rules",
		&"checkpoint_without_snapshot",
		&"settlement",
		&"presentation",
		&"full_turn",
	]
	var series_by_phase: Dictionary = {}
	for phase_id: StringName in phase_ids:
		series_by_phase[phase_id] = GFMetricSeries.new().configure(
			StringName("full_turn_usec.%s" % String(phase_id)),
			{
				&"label": "Classic 4x4 %s (usec)" % String(phase_id),
				&"group": "Runtime acceptance",
				&"max_samples": normalized_sample_count,
				&"metadata": {
					&"evidence_scope": &"desktop_headless_diagnostic",
					&"topology": &"4x4",
					&"mode": &"gameplay.classic",
				},
			}
		)

	var all_valid: bool = true
	for iteration: int in range(normalized_warmup_count + normalized_sample_count):
		if not state_system.restore_state(baseline_state):
			all_valid = false
			break
		history.clear()
		flow.reset_benchmark_turn()
		var started_usec: int = Time.get_ticks_usec()
		var command_started_usec: int = started_usec
		var command_result: Variant = await history.execute_command(
			MoveCommand.new(Vector2i.LEFT)
		)
		var command_usec: int = Time.get_ticks_usec() - command_started_usec
		if not command_result is TurnResult:
			all_valid = false
			break
		var turn_result: TurnResult = command_result
		flow.apply_move_turn(turn_result)
		var rules_started_usec: int = Time.get_ticks_usec()
		rule_system.execute_move_rules(turn_result)
		var rules_usec: int = Time.get_ticks_usec() - rules_started_usec
		var checkpoint_started_usec: int = Time.get_ticks_usec()
		var checkpoint: ReplayCheckpoint = flow.finalize_turn_result(turn_result)
		var checkpoint_inclusive_usec: int = (
			Time.get_ticks_usec() - checkpoint_started_usec
		)
		var snapshot_usec: int = flow.take_last_snapshot_usec()
		var settlement_started_usec: int = Time.get_ticks_usec()
		flow.settle_move_turn()
		var settlement_usec: int = Time.get_ticks_usec() - settlement_started_usec
		var presentation_started_usec: int = Time.get_ticks_usec()
		var board_snapshot: Dictionary = grid.get_snapshot()
		var turn_summary: GameAccessibilitySummary = summary.build_turn_summary(
			turn_result,
			board_snapshot,
			flow.get_accessibility_context(),
			checkpoint.board_checksum if checkpoint != null else ""
		)
		var presentation_usec: int = (
			Time.get_ticks_usec() - presentation_started_usec
		)
		var full_turn_usec: int = Time.get_ticks_usec() - started_usec
		all_valid = (
			checkpoint != null
			and turn_summary != null
			and history.undo_count == 1
			and all_valid
		)
		if iteration < normalized_warmup_count:
			continue
		var sample_index: int = iteration - normalized_warmup_count
		_add_phase_sample(series_by_phase, &"command", command_usec, sample_index)
		_add_phase_sample(
			series_by_phase,
			&"turn_state_snapshot",
			snapshot_usec,
			sample_index
		)
		_add_phase_sample(series_by_phase, &"rules", rules_usec, sample_index)
		_add_phase_sample(
			series_by_phase,
			&"checkpoint_without_snapshot",
			maxi(checkpoint_inclusive_usec - snapshot_usec, 0),
			sample_index
		)
		_add_phase_sample(
			series_by_phase,
			&"settlement",
			settlement_usec,
			sample_index
		)
		_add_phase_sample(
			series_by_phase,
			&"presentation",
			presentation_usec,
			sample_index
		)
		_add_phase_sample(
			series_by_phase,
			&"full_turn",
			full_turn_usec,
			sample_index
		)

	var statistics_by_phase: Dictionary = {}
	for phase_id: StringName in phase_ids:
		var series_value: Variant = series_by_phase.get(phase_id)
		if series_value is GFMetricSeries:
			var series: GFMetricSeries = series_value
			statistics_by_phase[phase_id] = _summarize_series(series)
	var full_turn_statistics: Dictionary = GFVariantData.get_option_dictionary(
		statistics_by_phase,
		&"full_turn"
	)
	var passed: bool = (
		all_valid
		and GFVariantData.get_option_int(
			full_turn_statistics,
			&"sample_count"
		) == normalized_sample_count
		and GFVariantData.get_option_float(full_turn_statistics, &"p95")
		<= FULL_TURN_P95_BUDGET_USEC
		and GFVariantData.get_option_float(full_turn_statistics, &"max")
		<= FULL_TURN_MAX_BUDGET_USEC
	)
	architecture.dispose()
	return {
		&"passed": passed,
		&"pipeline_valid": all_valid,
		&"evidence_scope": &"desktop_headless_diagnostic",
		&"mobile_acceptance_claim": false,
		&"mode_id": &"gameplay.classic",
		&"topology_id": &"4x4",
		&"sample_count": normalized_sample_count,
		&"warmup_count": normalized_warmup_count,
		&"budgets_usec": {
			&"p95": FULL_TURN_P95_BUDGET_USEC,
			&"max": FULL_TURN_MAX_BUDGET_USEC,
		},
		&"statistics_usec": statistics_by_phase,
	}


## 重复实例化/释放代表性 UI 与玩法资源，检查预热后的对象计数是否进入平台。
## @param host: 已进入 SceneTree 的临时父节点。
## @param cycles: 总循环数。
## @param warmup_cycles: 不参与平台判断的预热循环数。
func run_lifecycle_plateau(
	host: Node,
	cycles: int = DEFAULT_LIFECYCLE_CYCLES,
	warmup_cycles: int = DEFAULT_LIFECYCLE_WARMUP_CYCLES
) -> Dictionary:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return {
			&"passed": false,
			&"reason": &"host_not_inside_tree",
		}
	var normalized_cycles: int = maxi(cycles, 8)
	var normalized_warmup: int = clampi(
		warmup_cycles,
		2,
		normalized_cycles - 3
	)
	var packed_scenes: Array[PackedScene] = []
	for scene_path: String in _REPRESENTATIVE_SCENE_PATHS:
		var scene_resource: Resource = load(scene_path)
		if scene_resource is PackedScene:
			var packed_scene: PackedScene = scene_resource
			packed_scenes.append(packed_scene)
	if packed_scenes.size() != _REPRESENTATIVE_SCENE_PATHS.size():
		return {
			&"passed": false,
			&"reason": &"representative_scene_load_failed",
			&"loaded_scene_count": packed_scenes.size(),
		}

	var mode_resources: Array[GameModeConfig] = []
	for mode_path: String in (
		GameModeCatalogUtility.DEFAULT_MODE_REGISTRY.get_all_paths()
	):
		var mode_resource: Resource = load(mode_path)
		if mode_resource is GameModeConfig:
			var mode_config: GameModeConfig = mode_resource
			mode_resources.append(mode_config)
	if mode_resources.is_empty():
		return {
			&"passed": false,
			&"reason": &"representative_resource_load_failed",
		}

	var node_series: GFMetricSeries = GFMetricSeries.new().configure(
		&"lifecycle.object_node_count",
		{
			&"label": "Object node count",
			&"group": "Runtime acceptance",
			&"max_samples": normalized_cycles,
		}
	)
	var resource_series: GFMetricSeries = GFMetricSeries.new().configure(
		&"lifecycle.object_resource_count",
		{
			&"label": "Object resource count",
			&"group": "Runtime acceptance",
			&"max_samples": normalized_cycles,
		}
	)
	var baseline_nodes: float = Performance.get_monitor(
		Performance.OBJECT_NODE_COUNT
	)
	var baseline_resources: float = Performance.get_monitor(
		Performance.OBJECT_RESOURCE_COUNT
	)

	for cycle_index: int in range(normalized_cycles):
		var instances: Array[Node] = []
		for packed_scene: PackedScene in packed_scenes:
			var instance: Node = packed_scene.instantiate()
			host.add_child(instance)
			instances.append(instance)
		var resource_copies: Array[Resource] = []
		for mode_config: GameModeConfig in mode_resources:
			var copied_resource: Resource = mode_config.duplicate(true)
			resource_copies.append(copied_resource)
		var transient_topology: BoardTopology = BoardTopology.create_cross(
			3,
			1,
			StringName("acceptance.lifecycle.%d" % cycle_index)
		)
		resource_copies.append(transient_topology)

		await host.get_tree().process_frame
		for instance: Node in instances:
			instance.queue_free()
		instances.clear()
		resource_copies.clear()
		transient_topology = null
		await host.get_tree().process_frame
		await host.get_tree().process_frame

		node_series.add_sample(
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			float(cycle_index),
			{&"cycle": cycle_index}
		)
		resource_series.add_sample(
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			float(cycle_index),
			{&"cycle": cycle_index}
		)

	var node_tail: Dictionary = _summarize_tail(node_series, normalized_warmup)
	var resource_tail: Dictionary = _summarize_tail(
		resource_series,
		normalized_warmup
	)
	var passed: bool = (
		GFVariantData.get_option_float(node_tail, &"spread") <= (
			LIFECYCLE_NODE_TAIL_SPREAD_BUDGET
		)
		and GFVariantData.get_option_float(resource_tail, &"spread") <= (
			LIFECYCLE_RESOURCE_TAIL_SPREAD_BUDGET
		)
		and GFVariantData.get_option_float(node_tail, &"growth") <= (
			LIFECYCLE_NODE_TAIL_GROWTH_BUDGET
		)
		and GFVariantData.get_option_float(resource_tail, &"growth") <= (
			LIFECYCLE_RESOURCE_TAIL_GROWTH_BUDGET
		)
	)
	return {
		&"passed": passed,
		&"cycles": normalized_cycles,
		&"warmup_cycles": normalized_warmup,
		&"baseline": {
			&"node_count": baseline_nodes,
			&"resource_count": baseline_resources,
		},
		&"node_tail": node_tail,
		&"resource_tail": resource_tail,
		&"budgets": {
			&"node_spread": LIFECYCLE_NODE_TAIL_SPREAD_BUDGET,
			&"resource_spread": LIFECYCLE_RESOURCE_TAIL_SPREAD_BUDGET,
			&"node_growth": LIFECYCLE_NODE_TAIL_GROWTH_BUDGET,
			&"resource_growth": LIFECYCLE_RESOURCE_TAIL_GROWTH_BUDGET,
		},
		&"node_metric_series": node_series.to_dict(true, 20),
		&"resource_metric_series": resource_series.to_dict(true, 20),
	}


# --- 私有/辅助方法 ---

func _create_full_turn_fixture() -> Dictionary:
	var mode_value: Resource = load(
		"res://features/gameplay/resources/modes/classic_mode_config.tres"
	)
	if not mode_value is GameModeConfig:
		return {&"ok": false, &"reason": &"classic_mode_load_failed"}
	var duplicated_mode_value: Resource = mode_value.duplicate(true)
	if not duplicated_mode_value is GameModeConfig:
		return {&"ok": false, &"reason": &"classic_mode_duplicate_failed"}
	var mode: GameModeConfig = duplicated_mode_value
	var architecture: GFArchitecture = GFArchitecture.new()
	var capability: GFCapabilityUtility = GFCapabilityUtility.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	var history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	var grid: GridModel = GridModel.new()
	var status: GameStatusModel = GameStatusModel.new()
	var state_system: GameStateSystem = GameStateSystem.new()
	var movement_system: GridMovementSystem = GridMovementSystem.new()
	var rule_system: RuleSystem = RuleSystem.new()
	var spawn_system: GridSpawnSystem = GridSpawnSystem.new()
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var registered: bool = true
	registered = await architecture.register_utility(
		GFCapabilityUtility,
		capability
	) and registered
	registered = await architecture.register_utility(
		TileCompositionUtility,
		composition
	) and registered
	registered = await architecture.register_utility(
		GFSeedUtility,
		seed_utility
	) and registered
	registered = await architecture.register_utility(
		GFCommandHistoryUtility,
		history
	) and registered
	registered = await architecture.register_utility(
		GFLogUtility,
		GFLogUtility.new()
	) and registered
	registered = await architecture.register_utility(
		GameDeterminismUtility,
		determinism
	) and registered
	registered = await architecture.register_model(GridModel, grid) and registered
	registered = await architecture.register_model(GameStatusModel, status) and registered
	registered = await architecture.register_system(
		RuleSystem,
		rule_system
	) and registered
	registered = await architecture.register_system(
		GameStateSystem,
		state_system
	) and registered
	registered = await architecture.register_system(
		GridMovementSystem,
		movement_system
	) and registered
	registered = await architecture.register_system(
		GridSpawnSystem,
		spawn_system
	) and registered
	if not registered:
		architecture.dispose()
		return {&"ok": false, &"reason": &"architecture_registration_failed"}
	await architecture.init()
	seed_utility.set_global_seed(2048)
	if not grid.initialize(
		BoardTopology.create_rectangle(Vector2i(4, 4), &"board.acceptance.4x4"),
		mode.interaction_rule,
		mode.movement_rule
	):
		architecture.dispose()
		return {&"ok": false, &"reason": &"grid_initialization_failed"}
	if not rule_system.register_rules(mode.spawn_rules):
		architecture.dispose()
		return {&"ok": false, &"reason": &"rule_registration_failed"}
	var definition: TileDefinition = mode.interaction_rule.get_default_tile_definition()
	if definition == null:
		architecture.dispose()
		return {&"ok": false, &"reason": &"tile_definition_missing"}
	if not grid.place_tile(
		composition.create_tile(definition, 2),
		Vector2i(1, 0)
	):
		architecture.dispose()
		return {&"ok": false, &"reason": &"fixture_tile_placement_failed"}
	status.set_target_state(mode.target_tile_value, false)
	status.sync_highest_tile_from_grid(grid)
	var baseline_state: Dictionary = state_system.get_full_game_state()
	if not GameStateSystem.is_state_envelope_valid(baseline_state):
		architecture.dispose()
		return {&"ok": false, &"reason": &"baseline_state_invalid"}
	var flow: InstrumentedGameFlowSystem = InstrumentedGameFlowSystem.new()
	flow.benchmark_state_system = state_system
	flow._grid_model = grid
	flow._game_status_model = status
	flow._determinism = determinism
	flow._mode_config = mode
	flow._game_over_rule = mode.game_over_rule
	flow._session_ruleset_fingerprint = (
		determinism.calculate_ruleset_fingerprint(mode)
	)
	return {
		&"ok": true,
		&"architecture": architecture,
		&"grid": grid,
		&"state_system": state_system,
		&"rule_system": rule_system,
		&"history": history,
		&"flow": flow,
		&"summary": GameAccessibilitySummaryUtility.new(),
		&"baseline_state": baseline_state,
	}


func _add_phase_sample(
	series_by_phase: Dictionary,
	phase_id: StringName,
	value_usec: int,
	sample_index: int
) -> void:
	var series_value: Variant = series_by_phase.get(phase_id)
	if not series_value is GFMetricSeries:
		return
	var series: GFMetricSeries = series_value
	series.add_sample(float(value_usec), float(sample_index), {
		&"phase": phase_id,
	})

func _make_topology_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for size: Vector2i in _TOPOLOGY_SIZES:
		var topology: BoardTopology = BoardTopology.create_rectangle(
			size,
			StringName("board.acceptance.%dx%d" % [size.x, size.y])
		)
		rows.append({
			&"id": StringName("%dx%d" % [size.x, size.y]),
			&"topology": topology,
		})
	return rows


func _make_full_state(
	topology: BoardTopology,
	mode_config: GameModeConfig,
	seed_hint: int
) -> Dictionary:
	var tiles: Array[Dictionary] = []
	var cells: Array[Vector2i] = topology.get_active_cells()
	var tile_count: int = mini(cells.size(), 8)
	for index: int in range(tile_count):
		tiles.append({
			&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
			&"tile_id": GFUuid.generate_v7(10_000 + index),
			&"definition_id": &"tile.acceptance.numeric",
			&"value": 1 << ((index % 6) + 1),
			&"capability_recipe_ids": [&"tile.recipe.acceptance"],
			&"capability_state": {},
			&"pos": cells[index],
		})
	return {
		&"board_snapshot": {
			&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
			&"topology": topology.to_dict(),
			&"tiles": tiles,
		},
		&"rng_full_state": {
			&"root_seed": seed_hint,
			&"branch_counters": {
				&"game_board_spawn": 12,
				&"rule_spawn": 4,
			},
		},
		&"score": 4096,
		&"move_count": 128,
		&"highest_tile": 512,
		&"ratio_resolutions": 3,
		&"target_tile_value": mode_config.target_tile_value,
		&"target_reached": mode_config.is_target_reached(512),
		&"extra_stats": {&"acceptance": 1},
		&"rules_states": {&"spawn": {&"count": 12}},
	}


func _summarize_series(series: GFMetricSeries) -> Dictionary:
	var values: Array[float] = _get_series_values(series)
	if values.is_empty():
		return {
			&"p50": 0.0,
			&"p95": 0.0,
			&"max": 0.0,
			&"sample_count": 0,
		}
	values.sort()
	return {
		&"p50": _nearest_rank(values, 0.50),
		&"p95": _nearest_rank(values, 0.95),
		&"max": values.back(),
		&"sample_count": values.size(),
	}


func _summarize_tail(series: GFMetricSeries, start_index: int) -> Dictionary:
	var values: Array[float] = _get_series_values(series)
	var tail: Array[float] = []
	for index: int in range(clampi(start_index, 0, values.size()), values.size()):
		tail.append(values[index])
	if tail.is_empty():
		return {
			&"first": 0.0,
			&"last": 0.0,
			&"min": 0.0,
			&"max": 0.0,
			&"spread": 0.0,
			&"growth": 0.0,
			&"sample_count": 0,
		}
	var sorted_tail: Array[float] = tail.duplicate()
	sorted_tail.sort()
	return {
		&"first": tail.front(),
		&"last": tail.back(),
		&"min": sorted_tail.front(),
		&"max": sorted_tail.back(),
		&"spread": sorted_tail.back() - sorted_tail.front(),
		&"growth": tail.back() - tail.front(),
		&"sample_count": tail.size(),
	}


func _get_series_values(series: GFMetricSeries) -> Array[float]:
	var values: Array[float] = []
	for sample: Dictionary in series.get_samples():
		values.append(GFVariantData.get_option_float(sample, &"value"))
	return values


func _nearest_rank(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var rank_index: int = clampi(
		ceili(clampf(percentile, 0.0, 1.0) * float(sorted_values.size())) - 1,
		0,
		sorted_values.size() - 1
	)
	return sorted_values[rank_index]


## 只为性能夹具分离 finalize_turn_result 内部的状态快照耗时；生产实现不依赖
## 此替身，也不改变 checkpoint、命令历史或规则语义。
class InstrumentedGameFlowSystem extends GameFlowSystem:
	var benchmark_state_system: GameStateSystem = null
	var _last_snapshot_usec: int = 0


	func reset_benchmark_turn() -> void:
		_player_actions.clear()
		_turn_checkpoints.clear()
		_last_snapshot_usec = 0


	func take_last_snapshot_usec() -> int:
		var result: int = _last_snapshot_usec
		_last_snapshot_usec = 0
		return result


	func _get_full_game_state() -> Dictionary:
		if not is_instance_valid(benchmark_state_system):
			return {}
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = benchmark_state_system.get_full_game_state()
		_last_snapshot_usec = Time.get_ticks_usec() - started_usec
		return result


	func _get_replay_system() -> ReplaySystem:
		return null
