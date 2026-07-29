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
	harness.configure({
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


func test_ui_route_budget_failure_is_not_hidden_by_success_status() -> void:
	var harness: HarnessType = HarnessType.new()
	harness.configure({
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
	harness.configure({
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
		assert_true(
			GFVariantData.get_option_string(
				transitions[0],
				"phase"
			) == "cover",
			"首段转场必须是 cover。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transitions[0],
				"configured_duration_msec"
			),
			240.0,
			0.001
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transitions[0],
				"wall_duration_msec"
			),
			240.0,
			0.001
		)
		assert_true(
			GFVariantData.get_option_string(
				transitions[1],
				"phase"
			) == "reveal",
			"第二段转场必须是 reveal。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transitions[1],
				"configured_duration_msec"
			),
			260.0,
			0.001
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transitions[1],
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


func test_cancelled_transition_is_recorded_as_incomplete_evidence() -> void:
	_fake_times_usec = [
		3_000_000,
		3_010_000,
		3_080_000,
		3_100_000,
	]
	var harness: HarnessType = HarnessType.new()
	harness.configure({
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
		assert_true(
			GFVariantData.get_option_string(
				transitions[0],
				"status"
			) == "cancelled",
			"取消信号必须写入 cancelled 终态。"
		)
		assert_almost_eq(
			GFVariantData.get_option_float(
				transitions[0],
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
	harness.configure({
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
	var report_path: String = "user://ui_route_performance_test.json"

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


# --- 私有/辅助方法 ---

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
