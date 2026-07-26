## GamePerformanceAcceptanceHarness: 可重复的确定性热路径与生命周期平台验收工具。
##
## 采样统一记录到 GFMetricSeries；预算刻意宽松，只拦截数量级回退与持续增长，
## 不把共享 CI 上的微小计时波动当作产品缺陷。
class_name GamePerformanceAcceptanceHarness
extends RefCounted


# --- 常量 ---

const DEFAULT_CHECKPOINT_SAMPLE_COUNT: int = 36
const DEFAULT_CHECKPOINT_BATCH_SIZE: int = 3
const DEFAULT_LIFECYCLE_CYCLES: int = 14
const DEFAULT_LIFECYCLE_WARMUP_CYCLES: int = 5

## Debug/headless 下仍应在 100ms P95 内完成；max 只拦截停顿级回退。
## 预算覆盖共享 CI 同时运行多个 Godot 进程时的抖动，不用于发布帧时 KPI。
const CHECKPOINT_P95_BUDGET_USEC: float = 100_000.0
const CHECKPOINT_MAX_BUDGET_USEC: float = 250_000.0
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
	"res://features/gameplay/scenes/components/board_grid_cell.tscn",
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
