## 验证 UI/场景路由性能工具保留 GF 原生证据并严格执行预算。
extends GutTest


# --- 常量 ---

const HarnessType = preload(
	"res://tools/ui_route_performance_acceptance_harness.gd"
)


# --- 私有变量 ---

var _fake_times_usec: Array[int] = []


# --- 测试用例 ---

func test_ui_route_result_preserves_duration_and_preload_evidence() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_scene_route_samples": 0,
		"budgets": {"ui_route_max_msec": 500.0},
	})
	var result: GFUIRouteResult = _make_ui_route_result(
		1,
		&"tile_catalog",
		180,
		true
	)

	var record: Dictionary = harness.record_ui_route_result(result, {
		"cache_state": "first_open_in_process",
	})
	var preload_evidence: Dictionary = GFVariantData.get_option_dictionary(
		record,
		"preload"
	)
	var report: Dictionary = harness.build_report()

	assert_true(GFVariantData.get_option_bool(record, "passed"), str(record))
	assert_true(
		GFVariantData.get_option_float(record, "duration_msec") == 180.0,
		"UI 路由记录必须保留 GF 终态中的耗时。"
	)
	assert_true(GFVariantData.get_option_bool(preload_evidence, "attempted"))
	assert_true(GFVariantData.get_option_bool(preload_evidence, "successful"))
	assert_false(GFVariantData.get_option_bool(preload_evidence, "degraded"))
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.get_option_dictionary(record, "context"),
			"cache_state"
		) == "first_open_in_process",
		"UI 路由记录必须保留首次打开上下文。"
	)
	assert_true(GFVariantData.get_option_bool(report, "passed"), str(report))


func test_report_rejects_unsettled_asset_preload_sessions() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_scene_route_samples": 0,
	})
	var _record: Dictionary = harness.record_ui_route_result(
		_make_ui_route_result(11, &"tile_catalog", 120, true)
	)
	var report: Dictionary = harness.build_report({
		"active_asset_preload_session_count": 1,
	})
	var summary: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"summary"
	)

	assert_false(
		GFVariantData.get_option_bool(report, "passed"),
		"GFAssetLoadSession 尚未收敛时，性能报告不得提前宣告无活动工作。"
	)
	assert_false(GFVariantData.get_option_bool(summary, "no_active_asset_work"))
	assert_true(
		GFVariantData.get_option_int(
			summary,
			"active_asset_preload_session_count"
		) == 1
	)


func test_ui_route_budget_failure_is_not_hidden_by_success_status() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_scene_route_samples": 0,
		"budgets": {"ui_route_max_msec": 500.0},
	})
	var result: GFUIRouteResult = _make_ui_route_result(
		2,
		&"player_profile",
		650,
		false
	)

	var record: Dictionary = harness.record_ui_route_result(result)
	var report: Dictionary = harness.build_report()
	var summary: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"summary"
	)

	assert_true(GFVariantData.get_option_bool(record, "ok"))
	assert_false(GFVariantData.get_option_bool(record, "within_budget"))
	assert_false(GFVariantData.get_option_bool(record, "passed"))
	assert_false(GFVariantData.get_option_bool(report, "passed"))
	assert_true(
		GFVariantData.get_option_int(
			summary,
			"ui_route_failure_count"
		) == 1,
		"超过预算的 UI 路由必须计入失败样本。"
	)


func test_metric_series_preserves_execution_order_while_percentiles_sort_copy() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 3,
		"minimum_scene_route_samples": 0,
	})
	var durations: Array[int] = [300, 100, 200]
	for index: int in range(durations.size()):
		var _record: Dictionary = harness.record_ui_route_result(
			_make_ui_route_result(
				100 + index,
				&"tile_catalog",
				durations[index],
				false
			),
			{
				"cache_state": (
					"first_open_in_process"
					if index == 0
					else "warm_reopen_in_process"
				),
			}
		)

	var report: Dictionary = harness.build_report()
	var metrics: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"metrics"
	)
	var aggregate: Dictionary = GFVariantData.get_option_dictionary(
		metrics,
		"ui_route_duration_msec"
	)
	var samples: Array = GFVariantData.get_option_array(aggregate, "samples")
	assert_true(samples.size() == 3)
	if samples.size() == 3:
		assert_almost_eq(
			GFVariantData.get_option_float(
				GFVariantData.as_dictionary(samples[0]),
				"value"
			),
			300.0,
			0.001
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				GFVariantData.as_dictionary(samples[2]),
				"value"
			),
			200.0,
			0.001
		)
	assert_almost_eq(
		GFVariantData.get_option_float(aggregate, "latest_value"),
		200.0,
		0.001,
		"latest 必须代表最后发生的样本，而不是排序后的最大值。"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(aggregate, "p95"),
		300.0,
		0.001
	)
	var route_groups: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"route_groups"
	)
	var ui_groups: Dictionary = GFVariantData.get_option_dictionary(
		route_groups,
		"ui"
	)
	var tile_group: Dictionary = GFVariantData.get_option_dictionary(
		ui_groups,
		"tile_catalog"
	)
	var tile_metric: Dictionary = GFVariantData.get_option_dictionary(
		tile_group,
		"metric"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(tile_metric, "latest_value"),
		200.0,
		0.001,
		"按 route 分组后仍必须保留真实执行顺序。"
	)


func test_boot_and_ui_phase_observations_use_explicit_monotonic_boundaries() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_boot_samples": 1,
		"minimum_ui_route_samples": 1,
		"minimum_scene_route_samples": 0,
		"require_phase_evidence": true,
	})
	var boot_record: Dictionary = harness.record_boot_observation(
		1_000_000,
		1_120_000,
		1_150_000,
		1_420_000,
		{
			"cache_state": "process_first_boot",
			"motion_settled_observed": true,
		}
	)
	var ui_record: Dictionary = harness.record_ui_route_result(
		_make_ui_route_result(200, &"settings_menu", 80, false),
		{"cache_state": "first_open_in_process"},
		{
			"started_usec": 2_000_000,
			"ready_usec": 2_090_000,
			"post_draw_usec": 2_110_000,
			"motion_settled_usec": 2_250_000,
			"motion_settled_observed": true,
		}
	)

	var boot_phases: Dictionary = GFVariantData.get_option_dictionary(
		boot_record,
		"phases"
	)
	var ui_phases: Dictionary = GFVariantData.get_option_dictionary(
		ui_record,
		"phases"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(boot_phases, "ready_msec"),
		120.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			boot_phases,
			"motion_settled_msec"
		),
		420.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(ui_phases, "post_draw_msec"),
		110.0,
		0.001
	)
	assert_true(GFVariantData.get_option_bool(harness.build_report(), "passed"))


func test_ui_route_phase_budget_rejects_slow_visual_settlement() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 1,
		"minimum_scene_route_samples": 0,
		"require_phase_evidence": true,
		"budgets": {
			"ui_route_max_msec": 500.0,
			"ui_route_post_draw_max_msec": 100.0,
			"ui_route_motion_settled_max_msec": 200.0,
		},
	})
	var record: Dictionary = harness.record_ui_route_result(
		_make_ui_route_result(201, &"settings_menu", 80, false),
		{"cache_state": "first_open_in_process"},
		{
			"started_usec": 3_000_000,
			"ready_usec": 3_080_000,
			"post_draw_usec": 3_110_000,
			"motion_settled_usec": 3_250_000,
			"motion_settled_observed": true,
		}
	)

	assert_true(GFVariantData.get_option_bool(record, "within_budget"))
	assert_false(
		GFVariantData.get_option_bool(record, "passed"),
		"GF 路由终态很快时，超预算首绘或动效终态仍必须让验收失败。"
	)
	var phase_budget: Dictionary = GFVariantData.get_option_dictionary(
		record,
		"phase_budget"
	)
	assert_false(
		GFVariantData.get_option_bool(phase_budget, "post_draw_within_budget")
	)
	assert_false(
		GFVariantData.get_option_bool(
			phase_budget,
			"motion_settled_within_budget"
		)
	)


func test_scene_signals_capture_load_switch_preload_and_total_duration() -> void:
	_fake_times_usec = [
		1_000_000,
		1_010_000,
		1_250_000,
		1_260_000,
		1_270_000,
		1_560_000,
		1_570_000,
		1_580_000,
		1_840_000,
		1_900_000,
		2_000_000,
		2_120_000,
	]
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 0,
		"minimum_scene_route_samples": 1,
		"budgets": {
			"scene_route_total_max_msec": 1000.0,
			"scene_load_max_msec": 400.0,
			"scene_preload_max_msec": 200.0,
		},
		"now_usec_provider": Callable(self, &"_next_fake_time_usec"),
	})
	var scene_utility: GFSceneUtility = GFSceneUtility.new()
	var screen_transition: GFScreenTransitionUtility = (
		GFScreenTransitionUtility.new()
	)
	assert_true(harness.bind_scene_utility(scene_utility))
	assert_true(
		harness.bind_screen_transition_utility(screen_transition)
	)
	assert_true(
		harness.begin_scene_route(
			&"main_to_mode",
			"res://mode_selection.tscn"
		)
	)

	var cover_effect: GFScreenTransitionEffect = _make_transition_effect(
		&"cover",
		0.24
	)
	var reveal_effect: GFScreenTransitionEffect = _make_transition_effect(
		&"reveal",
		0.26
	)
	screen_transition.transition_started.emit(cover_effect)
	screen_transition.transition_finished.emit(cover_effect)
	scene_utility.scene_load_started.emit("res://mode_selection.tscn")
	scene_utility.scene_switch_started.emit(
		"res://mode_selection.tscn",
		"res://main_menu.tscn"
	)
	scene_utility.scene_load_completed.emit(
		"res://mode_selection.tscn",
		null
	)
	scene_utility.scene_switch_completed.emit(
		"res://mode_selection.tscn",
		"res://main_menu.tscn"
	)
	screen_transition.transition_started.emit(reveal_effect)
	screen_transition.transition_finished.emit(reveal_effect)
	var scene_record: Dictionary = harness.complete_scene_route(true, {
		"interactive_ready": true,
	})
	scene_utility.scene_preload_started.emit("res://game_play.tscn")
	scene_utility.scene_preload_completed.emit(
		"res://game_play.tscn",
		null
	)
	var preload_records: Array[Dictionary] = (
		harness.get_scene_preload_records()
	)
	var report: Dictionary = harness.build_report()
	harness.unbind_scene_utility()
	harness.unbind_screen_transition_utility()

	assert_almost_eq(
		GFVariantData.get_option_float(scene_record, "duration_msec"),
		900.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			GFVariantData.get_option_dictionary(scene_record, "load"),
			"duration_msec"
		),
		300.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			GFVariantData.get_option_dictionary(scene_record, "switch"),
			"duration_msec"
		),
		300.0,
		0.001
	)
	var transitions_value: Variant = scene_record.get("transitions", [])
	assert_true(transitions_value is Array)
	var transitions: Array = transitions_value if transitions_value is Array else []
	assert_true(
		transitions.size() == 2,
		"完整场景路由必须记录 cover 与 reveal 两段转场。"
	)
	if transitions.size() == 2:
		var cover_transition: Dictionary = GFVariantData.as_dictionary(
			transitions[0]
		)
		var reveal_transition: Dictionary = GFVariantData.as_dictionary(
			transitions[1]
		)
		assert_true(
			GFVariantData.get_option_string(
				cover_transition,
				"phase"
			) == "cover",
			"首段转场必须是 cover。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				cover_transition,
				"configured_duration_msec"
			),
			240.0,
			0.001
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				cover_transition,
				"wall_duration_msec"
			),
			240.0,
			0.001
		)
		assert_true(
			GFVariantData.get_option_string(
				reveal_transition,
				"phase"
			) == "reveal",
			"第二段转场必须是 reveal。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				reveal_transition,
				"configured_duration_msec"
			),
			260.0,
			0.001
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				reveal_transition,
				"wall_duration_msec"
			),
			260.0,
			0.001
		)
	var transition_summary: Dictionary = GFVariantData.get_option_dictionary(
		scene_record,
		"transition_summary"
	)
	assert_true(
		GFVariantData.get_option_bool(
			transition_summary,
			"evidence_complete"
		)
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			transition_summary,
			"configured_total_msec"
		),
		500.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			transition_summary,
			"wall_total_msec"
		),
		500.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			transition_summary,
			"orchestration_residual_msec"
		),
		100.0,
		0.001
	)
	var wall_composition: Dictionary = GFVariantData.get_option_dictionary(
		transition_summary,
		"wall_composition"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			wall_composition,
			"request_to_cover_start_msec"
		),
		10.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			wall_composition,
			"cover_complete_to_load_start_msec"
		),
		10.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			wall_composition,
			"load_complete_to_reveal_start_msec"
		),
		20.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			wall_composition,
			"reveal_complete_to_route_ready_msec"
		),
		60.0,
		0.001
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			wall_composition,
			"unattributed_msec"
		),
		0.0,
		0.001
	)
	assert_true(
		preload_records.size() == 1,
		"场景预加载信号必须形成一个独立记录。"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(
			preload_records[0],
			"duration_msec"
		),
		120.0,
		0.001
	)
	assert_true(GFVariantData.get_option_bool(report, "passed"), str(report))


func test_scene_record_requires_completed_load_and_switch_terminals() -> void:
	var failed_load_record: Dictionary = _make_scene_terminal_record(
		"failed",
		"completed"
	)
	assert_false(
		GFVariantData.get_option_bool(failed_load_record, "passed"),
		"即使调用方误传 succeeded=true，failed load 信号也必须否决场景验收。"
	)
	assert_false(
		GFVariantData.get_option_bool(
			GFVariantData.get_option_dictionary(failed_load_record, "load"),
			"terminal_success"
		)
	)

	var missing_switch_record: Dictionary = _make_scene_terminal_record(
		"completed",
		"pending"
	)
	assert_false(
		GFVariantData.get_option_bool(missing_switch_record, "passed"),
		"缺少 completed switch 终态时不得仅凭目标节点可见而通过。"
	)
	assert_false(
		GFVariantData.get_option_bool(
			GFVariantData.get_option_dictionary(missing_switch_record, "switch"),
			"terminal_success"
		)
	)


func test_scene_preload_failure_without_started_signal_is_not_dropped() -> void:
	_fake_times_usec = [4_000_000]
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 0,
		"minimum_scene_route_samples": 0,
		"now_usec_provider": Callable(self, &"_next_fake_time_usec"),
	})
	var scene_utility: GFSceneUtility = GFSceneUtility.new()
	assert_true(harness.bind_scene_utility(scene_utility))

	scene_utility.scene_preload_failed.emit("res://missing_scene.tscn")
	var preload_records: Array[Dictionary] = (
		harness.get_scene_preload_records()
	)
	var report: Dictionary = harness.build_report()
	harness.unbind_scene_utility()

	assert_true(preload_records.size() == 1)
	var record: Dictionary = preload_records[0]
	assert_true(GFVariantData.get_option_string(record, "status") == "failed")
	assert_false(GFVariantData.get_option_bool(record, "evidence_complete"))
	assert_false(GFVariantData.get_option_bool(record, "passed"))
	assert_false(
		GFVariantData.get_option_bool(report, "passed"),
		"没有 started 前置信号的同步预载失败也必须进入失败计数。"
	)


func test_preload_already_running_at_bind_blocks_terminal_report() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_boot_samples": 0,
		"minimum_ui_route_samples": 0,
		"minimum_scene_route_samples": 0,
	})
	var path: String = "res://already_running.tscn"
	harness._preloading_scene_paths_at_bind[path] = true

	var pending_report: Dictionary = harness.build_report()
	var pending_summary: Dictionary = GFVariantData.get_option_dictionary(
		pending_report,
		"summary"
	)
	assert_false(GFVariantData.get_option_bool(pending_report, "passed"))
	assert_true(
		GFVariantData.get_option_int(
			pending_summary,
			"preexisting_scene_preload_pending_count"
		) == 1
	)

	harness._on_scene_preload_completed(path, null)
	var settled_report: Dictionary = harness.build_report()
	assert_true(
		GFVariantData.get_option_bool(settled_report, "passed"),
		"绑定前已在途的成功预载终态应清除 pending gate。"
	)


func test_cancelled_transition_is_recorded_as_incomplete_evidence() -> void:
	_fake_times_usec = [
		3_000_000,
		3_010_000,
		3_080_000,
		3_100_000,
	]
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 0,
		"minimum_scene_route_samples": 1,
		"now_usec_provider": Callable(self, &"_next_fake_time_usec"),
	})
	var screen_transition: GFScreenTransitionUtility = (
		GFScreenTransitionUtility.new()
	)
	assert_true(
		harness.bind_screen_transition_utility(screen_transition)
	)
	assert_true(
		harness.begin_scene_route(
			&"cancelled_route",
			"res://cancelled.tscn"
		)
	)
	var cover_effect: GFScreenTransitionEffect = _make_transition_effect(
		&"cover",
		0.24
	)
	screen_transition.transition_started.emit(cover_effect)
	screen_transition.transition_cancelled.emit(cover_effect)
	var record: Dictionary = harness.complete_scene_route(false)
	harness.unbind_screen_transition_utility()

	var transitions_value: Variant = record.get("transitions", [])
	assert_true(transitions_value is Array)
	var transitions: Array = transitions_value if transitions_value is Array else []
	assert_true(
		transitions.size() == 1,
		"取消场景路由应保留已开始的单段转场证据。"
	)
	if transitions.size() == 1:
		var transition: Dictionary = GFVariantData.as_dictionary(
			transitions[0]
		)
		assert_true(
			GFVariantData.get_option_string(
				transition,
				"status"
			) == "cancelled",
			"取消信号必须写入 cancelled 终态。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transition,
				"wall_duration_msec"
			),
			70.0,
			0.001
		)
	assert_false(
		GFVariantData.get_option_bool(
			GFVariantData.get_option_dictionary(
				record,
				"transition_summary"
			),
			"evidence_complete"
		)
	)
	assert_false(GFVariantData.get_option_bool(record, "passed"))


func test_report_writer_emits_parseable_json() -> void:
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_scene_route_samples": 0,
	})
	var result: GFUIRouteResult = _make_ui_route_result(
		3,
		&"achievements",
		90,
		false
	)
	var _record: Dictionary = harness.record_ui_route_result(result)
	var report: Dictionary = harness.build_report({
		"viewport": Vector2i(1280, 720),
	})
	var report_path: String = (
		"user://ui_route_performance/route_performance_test.json"
	)

	assert_true(harness.write_report(report, report_path) == OK)
	assert_true(
		GFVariantData.get_option_bool(report, "passed"),
		"写报告不得原地改写调用方仍需用于退出码判断的报告。"
	)
	var file: FileAccess = FileAccess.open(report_path, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary)
	if parsed is Dictionary:
		var parsed_report: Dictionary = parsed
		assert_true(
			GFVariantData.get_option_bool(parsed_report, "passed"),
			str(parsed_report)
		)


func test_report_writer_rejects_paths_outside_owned_report_roots() -> void:
	var harness: HarnessType = HarnessType.new()
	var forbidden_path: String = (
		"res://features/__ui_route_performance_forbidden_report.json"
	)

	assert_true(
		harness.write_report({"passed": true}, forbidden_path)
		== ERR_INVALID_PARAMETER
	)
	assert_push_error("输出路径不在允许的生成根目录内")
	assert_false(
		FileAccess.file_exists(forbidden_path),
		"性能证据只能写入工具拥有的 build 或 user 报告根。"
	)


# --- 私有/辅助方法 ---

func _make_scene_terminal_record(
	load_status: String,
	switch_status: String
) -> Dictionary:
	_fake_times_usec = [1_000_000, 2_000_000]
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": 0,
		"minimum_scene_route_samples": 1,
		"require_phase_evidence": true,
		"budgets": {
			"scene_route_total_max_msec": 1500.0,
			"scene_load_max_msec": 500.0,
			"scene_route_post_draw_max_msec": 1500.0,
			"scene_route_motion_settled_max_msec": 1800.0,
		},
		"now_usec_provider": Callable(self, &"_next_fake_time_usec"),
	})
	assert_true(
		harness.begin_scene_route(
			&"terminal_contract",
			"res://target.tscn"
		)
	)
	harness._active_scene_route["load_status"] = load_status
	harness._active_scene_route["load_started_usec"] = 1_200_000
	harness._active_scene_route["load_completed_usec"] = 1_300_000
	harness._active_scene_route["load_duration_msec"] = 100.0
	harness._active_scene_route["switch_status"] = switch_status
	harness._active_scene_route["switch_started_usec"] = 1_220_000
	harness._active_scene_route["switch_completed_usec"] = 1_350_000
	harness._active_scene_route["switch_duration_msec"] = (
		130.0 if switch_status != "pending" else -1.0
	)
	harness._active_scene_route["transitions"] = [
		{
			"phase": "cover",
			"status": "completed",
			"configured_duration_msec": 100.0,
			"wall_duration_msec": 100.0,
			"_started_usec": 1_050_000,
			"_ended_usec": 1_150_000,
			"_effect_instance_id": 1,
		},
		{
			"phase": "reveal",
			"status": "completed",
			"configured_duration_msec": 100.0,
			"wall_duration_msec": 100.0,
			"_started_usec": 1_400_000,
			"_ended_usec": 1_500_000,
			"_effect_instance_id": 2,
		},
	]
	harness._active_scene_route["milestones_usec"] = {
		&"ready": 1_550_000,
		&"post_draw": 1_600_000,
		&"motion_settled": 1_700_000,
	}
	return harness.complete_scene_route(true, {
		"interactive_ready": true,
		"route_ready_usec": 1_800_000,
		"motion_settled_observed": true,
	})


func _make_ui_route_result(
	request_id: int,
	route_id: StringName,
	duration_msec: int,
	preload_attempted: bool
) -> GFUIRouteResult:
	var result: GFUIRouteResult = GFUIRouteResult.new()
	var configured: bool = result.configure_for_framework(
		request_id,
		route_id,
		&"push",
		GFUIRouteResult.STATUS_OPENED,
		&"",
		GFUIUtility.Layer.POPUP,
		null,
		GFUIRouterUtility.PRELOAD_BEST_EFFORT,
		preload_attempted,
		preload_attempted,
		{
			"route_ids": PackedStringArray([
				String(route_id),
				"neighbor",
			]),
		},
		null,
		1000,
		1000 + duration_msec,
		{"owner_instance_id": 42}
	)
	assert_true(configured)
	return result


func _make_transition_effect(
	phase: StringName,
	duration_seconds: float
) -> GFScreenTransitionEffect:
	var effect: GFScreenTransitionEffect = GFScreenTransitionEffect.new()
	effect.duration_seconds = duration_seconds
	effect.metadata = {
		"phase": phase,
		"theme_id": &"test_theme",
	}
	return effect


func _next_fake_time_usec() -> int:
	if _fake_times_usec.is_empty():
		return 0
	return _fake_times_usec.pop_front()
