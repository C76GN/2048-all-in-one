## 验证输入、尺寸和性能矩阵是可执行契约，而不是静态目标清单。
extends GutTest


# --- 测试用例 ---

func test_acceptance_matrix_has_complete_static_coverage() -> void:
	var report: GFValidationReport = GameplayAcceptanceMatrix.get_validation_report()
	var cases: Array[Dictionary] = GameplayAcceptanceMatrix.get_cases()

	assert_true(report.is_ok(), "验收矩阵的布局、输入、质量和棋盘形态覆盖必须完整。")
	assert_true(cases.size() == 6, "矩阵应覆盖六类主要发布环境。")
	assert_false(
		GameplayAcceptanceMatrix.get_case(&"steam_gamepad_large_irregular").is_empty(),
		"大型不规则棋盘必须进入桌面手柄验收范围。"
	)
	assert_false(
		GameplayAcceptanceMatrix.get_case(&"wechat_touch_landscape").is_empty(),
		"微信触屏横屏必须有独立验收用例。"
	)


func test_touch_cases_require_mobile_target_size_and_runtime_layout() -> void:
	for acceptance_case: Dictionary in GameplayAcceptanceMatrix.get_cases():
		var viewport_size: Vector2i = Vector2i(
			GFVariantData.get_option_vector2(acceptance_case, &"viewport_size")
		)
		var actual_layout: int = GameplayResponsiveLayoutController.classify_layout(
			Vector2(viewport_size),
			GFVariantData.get_option_bool(acceptance_case, &"prefer_compact")
		)
		assert_true(
			actual_layout == GFVariantData.get_option_int(acceptance_case, &"expected_layout"),
			"验收用例布局必须与运行时分类器同源。"
		)
		if (
			GFVariantData.get_option_int(acceptance_case, &"input_modality")
			== GameplayAcceptanceMatrix.InputModality.TOUCH
		):
			assert_gte(
				GFVariantData.get_option_float(
					acceptance_case,
					&"minimum_touch_target_px"
				),
				44.0,
				"触屏用例不得接受小于 44px 的目标。"
			)


func test_acceptance_evaluation_requires_enough_gf_metric_samples() -> void:
	var frame_series: GFMetricSeries = _make_series(&"frame_time_ms", 60, 10.0)
	var input_series: GFMetricSeries = _make_series(&"input_feedback_ms", 60, 20.0)
	var result: Dictionary = GameplayAcceptanceMatrix.evaluate_case(
		&"steam_keyboard_standard",
		frame_series,
		input_series
	)

	assert_false(GFVariantData.get_option_bool(result, &"passed"))
	assert_true(
		GFVariantData.get_option_string_name(result, &"reason") == &"insufficient_samples",
		"样本不足时不得把预算目标误报为实测通过。"
	)


func test_acceptance_evaluation_passes_and_rejects_p95_budget() -> void:
	var passing_frames: GFMetricSeries = _make_series(&"frame_time_ms", 120, 10.0)
	var passing_input: GFMetricSeries = _make_series(&"input_feedback_ms", 120, 24.0)
	var passing: Dictionary = GameplayAcceptanceMatrix.evaluate_case(
		&"steam_keyboard_standard",
		passing_frames,
		passing_input
	)
	assert_true(GFVariantData.get_option_bool(passing, &"passed"))

	var slow_frames: GFMetricSeries = _make_series(&"frame_time_ms", 120, 24.0)
	var failing: Dictionary = GameplayAcceptanceMatrix.evaluate_case(
		&"steam_keyboard_standard",
		slow_frames,
		passing_input
	)
	var measurements: Dictionary = GFVariantData.get_option_dictionary(
		failing,
		&"measurements"
	)
	assert_false(GFVariantData.get_option_bool(failing, &"passed"))
	assert_gt(
		GFVariantData.get_option_float(measurements, &"frame_p95_ms"),
		16.667,
		"超过桌面帧时 P95 预算时必须失败。"
	)


# --- 私有/辅助方法 ---

func _make_series(metric_id: StringName, sample_count: int, base_value: float) -> GFMetricSeries:
	var series: GFMetricSeries = GFMetricSeries.new().configure(
		metric_id,
		{&"max_samples": maxi(sample_count, 120)}
	)
	for index: int in range(sample_count):
		series.add_sample(base_value + float(index % 5) * 0.1, float(index))
	return series
