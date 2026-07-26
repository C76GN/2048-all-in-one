## 验证 GFMetricSeries 驱动的性能与生命周期 smoke 可重复执行。
extends GutTest


# --- 常量 ---

const HarnessType = preload(
	"res://tools/game_performance_acceptance_harness.gd"
)


# --- 测试用例 ---

func test_checkpoint_benchmark_covers_registered_modes_and_topologies() -> void:
	var harness: GamePerformanceAcceptanceHarness = HarnessType.new()
	var report: Dictionary = harness.benchmark_checkpoint_generation(18, 2)
	var expected_mode_count: int = (
		GameModeCatalogUtility.DEFAULT_MODE_REGISTRY.get_all_paths().size()
	)

	assert_true(GFVariantData.get_option_bool(report, &"passed"), str(report))
	assert_true(
		GFVariantData.get_option_int(report, &"mode_count") == expected_mode_count,
		"性能基准必须从 GFResourceRegistry 读取全部已登记模式。"
	)
	assert_true(
		GFVariantData.get_option_int(report, &"topology_count") == 3,
		"性能基准必须覆盖最小、默认和最大三种支持拓扑。"
	)
	assert_true(
		GFVariantData.get_option_int(report, &"case_count") == (
			expected_mode_count * 3
		),
		"每个注册模式都必须执行三种拓扑的 checkpoint 基准。"
	)
	for case_report: Dictionary in GFVariantData.get_option_array(
		report,
		&"cases"
	):
		var metric: Dictionary = GFVariantData.get_option_dictionary(
			case_report,
			&"metric_series"
		)
		assert_true(
			GFVariantData.get_option_int(metric, &"sample_count") >= 18,
			"每个 case 必须保留 GFMetricSeries 实测样本。"
		)


func test_session_checkpoint_path_preserves_registered_mode_hashes() -> void:
	var harness: GamePerformanceAcceptanceHarness = HarnessType.new()
	var report: Dictionary = harness.verify_checkpoint_hash_compatibility()

	assert_true(GFVariantData.get_option_bool(report, &"passed"), str(report))
	assert_true(
		GFVariantData.get_option_int(report, &"checked_cases") > 0,
		"哈希兼容验收不得空跑。"
	)


func test_representative_ui_and_resource_lifecycle_reaches_plateau() -> void:
	var harness: GamePerformanceAcceptanceHarness = HarnessType.new()
	var host: Node = Node.new()
	add_child_autoqfree(host)
	var report: Dictionary = await harness.run_lifecycle_plateau(host, 10, 4)

	assert_true(GFVariantData.get_option_bool(report, &"passed"), str(report))
	var node_metric: Dictionary = GFVariantData.get_option_dictionary(
		report,
		&"node_metric_series"
	)
	var resource_metric: Dictionary = GFVariantData.get_option_dictionary(
		report,
		&"resource_metric_series"
	)
	assert_true(
		GFVariantData.get_option_int(node_metric, &"sample_count") == 10,
		"节点生命周期 smoke 必须记录每轮 GF 指标。"
	)
	assert_true(
		GFVariantData.get_option_int(resource_metric, &"sample_count") == 10,
		"资源生命周期 smoke 必须记录每轮 GF 指标。"
	)
