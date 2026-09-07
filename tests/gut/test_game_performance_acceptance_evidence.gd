## 验证真实运行时性能证据只在显式同意、条件匹配和完整采样后签署。
extends GutTest


# --- 测试用例 ---

func test_observed_contract_mismatch_never_starts_or_retains_private_fields() -> void:
	var fixture: Dictionary = await _create_fixture()
	var diagnostics: GameDiagnosticsUtility = fixture[&"diagnostics"]
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	var observed: Dictionary = _steam_standard_observation()
	observed[&"viewport_size"] = [1280, 720]
	observed[&"account"] = "must_not_be_retained"

	var rejected: Dictionary = diagnostics.begin_gameplay_acceptance_case(
		&"steam_keyboard_standard",
		observed
	)
	assert_false(GFVariantData.get_option_bool(rejected, &"accepted"))
	assert_true(
		GFVariantData.get_option_string_name(rejected, &"reason")
		== &"observed_contract_mismatch"
	)
	assert_false(
		GFVariantData.get_option_bool(
			trace.get_acceptance_measurement_state(),
			&"configured"
		),
		"条件不匹配时不得创建可被误签署的指标序列。"
	)
	assert_true(trace.start_gameplay_trace(true))
	var replay_rejected: Dictionary = diagnostics.begin_gameplay_acceptance_case(
		&"steam_keyboard_standard",
		_steam_standard_observation()
	)
	assert_false(GFVariantData.get_option_bool(replay_rejected, &"accepted"))
	assert_true(
		GFVariantData.get_option_string_name(replay_rejected, &"reason")
		== &"replay_mode_not_eligible",
		"自动回放不能冒充玩家有效输入的首反馈验收。"
	)
	assert_true(trace.start_gameplay_trace(false))

	observed = _steam_standard_observation()
	observed[&"account"] = "must_not_be_retained"
	var accepted: Dictionary = diagnostics.begin_gameplay_acceptance_case(
		&"steam_keyboard_standard",
		observed
	)
	assert_true(GFVariantData.get_option_bool(accepted, &"accepted"))
	trace.record_player_visible_frame(Vector2i(1920, 1080))
	assert_true(clock.advance_msec(10))
	trace.record_player_visible_frame(Vector2i(1920, 1080))
	var repeated: Dictionary = diagnostics.begin_gameplay_acceptance_case(
		&"steam_keyboard_standard",
		_steam_standard_observation()
	)
	assert_false(GFVariantData.get_option_bool(repeated, &"accepted"))
	assert_true(
		GFVariantData.get_option_string_name(repeated, &"reason")
		== &"capture_already_active"
	)
	var state: Dictionary = trace.get_acceptance_measurement_state()
	assert_true(
		GFVariantData.get_option_int(state, &"frame_sample_count") == 1,
		"重复 begin 必须拒绝并保留当前窗口的既有样本。"
	)
	var retained_observation: Dictionary = GFVariantData.get_option_dictionary(
		state,
		&"observation"
	)
	assert_false(
		retained_observation.has(&"account"),
		"验收 Observation 只能保留矩阵匹配所需的脱敏白名单字段。"
	)

	var architecture: GFArchitecture = fixture[&"architecture"]
	architecture.dispose()


func test_complete_real_series_reaches_120_samples_and_uses_p95() -> void:
	var fixture: Dictionary = await _create_fixture()
	var diagnostics: GameDiagnosticsUtility = fixture[&"diagnostics"]
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))

	_record_runtime_samples(trace, clock, 120, 10.0, 24)
	var snapshot: Dictionary = diagnostics.finish_gameplay_acceptance_case()
	assert_true(
		GFVariantData.get_option_string_name(snapshot, &"measurement_status")
		== &"evaluated"
	)
	var results: Array = GFVariantData.get_option_array(
		snapshot,
		&"measured_results"
	)
	assert_true(results.size() == 1)
	var result: Dictionary = GFVariantData.as_dictionary(results[0])
	assert_true(GFVariantData.get_option_bool(result, &"passed"))
	var series: Dictionary = GFVariantData.get_option_dictionary(result, &"series")
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(series, &"frame_time_ms"),
			&"sample_count"
		) == 120
	)
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(series, &"input_feedback_ms"),
			&"sample_count"
		) == 120
	)

	assert_true(trace.start_gameplay_trace(false))
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))
	_record_frame_samples(trace, clock, 120, 10.0)
	for index: int in range(120):
		_record_effective_move(trace, clock, 70 if index >= 113 else 24)
	var slow_snapshot: Dictionary = diagnostics.finish_gameplay_acceptance_case()
	var slow_results: Array = GFVariantData.get_option_array(
		slow_snapshot,
		&"measured_results"
	)
	var slow_result: Dictionary = GFVariantData.as_dictionary(slow_results[0])
	var measurements: Dictionary = GFVariantData.get_option_dictionary(
		slow_result,
		&"measurements"
	)
	assert_false(GFVariantData.get_option_bool(slow_result, &"passed"))
	assert_gt(
		GFVariantData.get_option_float(
			measurements,
			&"input_feedback_p95_ms"
		),
		50.0,
		"通过真实 begin_move -> Action execute 首反馈通路采集的 P95 超预算时必须失败。"
	)
	var session_trace: GFSessionTraceUtility = fixture[&"session_trace"]
	assert_lte(
		session_trace.get_events().size(),
		96,
		"独立的 256 样本指标窗口不得扩大原有 96 条 GFSessionTrace 预算。"
	)

	var architecture: GFArchitecture = fixture[&"architecture"]
	architecture.dispose()


func test_input_feedback_spans_input_mapping_and_next_presented_frame() -> void:
	var fixture: Dictionary = await _create_fixture()
	var diagnostics: GameDiagnosticsUtility = fixture[&"diagnostics"]
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))

	var receipt_id: int = trace.capture_move_input(
		GameplayInputActions.MOVE_RIGHT,
		GamePerformanceTraceUtility.MOVE_INPUT_SOURCE_TOUCH
	)
	assert_gt(receipt_id, 0)
	assert_true(clock.advance_msec(3))
	assert_true(
		trace.acknowledge_move_input_mapped(GameplayInputActions.MOVE_RIGHT)
		== receipt_id,
		"GF action_started 必须认领触控预捕获收据，保留 virtual pulse 前的延迟。"
	)
	assert_true(clock.advance_msec(2))
	var attempt_id: int = trace.begin_move(
		Vector2i.RIGHT,
		GameplayInputActions.MOVE_RIGHT
	)
	var presentation_id: int = trace.mark_presentation_enqueued(false)
	assert_true(presentation_id == attempt_id)
	assert_true(clock.advance_msec(5))
	trace.mark_primary_feedback_state_committed(presentation_id)
	trace.complete_move(attempt_id, true)
	trace.mark_presentation_settled()
	assert_true(
		GFVariantData.get_option_int(
			trace.get_acceptance_measurement_state(),
			&"input_feedback_sample_count"
		) == 0,
		"提交可见状态但尚未绘制时不得提前写入首反馈样本。"
	)
	assert_true(clock.advance_msec(16))
	trace._on_primary_feedback_frame_post_draw(
		presentation_id,
		trace._primary_feedback_frame_serial
	)
	var bundle: Dictionary = trace.get_acceptance_measurement_bundle()
	var input_series: GFMetricSeries = bundle[&"input_feedback_ms"]
	assert_true(input_series.get_sample_count() == 1)
	assert_true(
		is_equal_approx(input_series.get_latest_value(), 26.0),
		"指标必须覆盖输入接收、GF 映射、System 轮询、回合计算和下一次绘制。"
	)

	# 没有项目入口收据的合成 move 仍可保留阶段诊断，但不能污染验收结论。
	var synthetic_attempt_id: int = trace.begin_move(Vector2i.LEFT)
	var synthetic_presentation_id: int = trace.mark_presentation_enqueued(false)
	trace.mark_primary_feedback_state_committed(synthetic_presentation_id)
	trace.complete_move(synthetic_attempt_id, true)
	trace.mark_presentation_settled()
	assert_true(clock.advance_msec(16))
	trace._on_primary_feedback_frame_post_draw(
		synthetic_presentation_id,
		trace._primary_feedback_frame_serial
	)
	assert_true(
		GFVariantData.get_option_int(
			trace.get_acceptance_measurement_state(),
			&"input_feedback_sample_count"
		) == 1,
		"缺少真实输入入口的合成动作不得生成可签署样本。"
	)

	var architecture: GFArchitecture = fixture[&"architecture"]
	architecture.dispose()


func test_new_mapped_input_replaces_same_direction_buffered_receipt() -> void:
	var fixture: Dictionary = await _create_fixture()
	var diagnostics: GameDiagnosticsUtility = fixture[&"diagnostics"]
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))
	var first_receipt_id: int = trace.acknowledge_move_input_mapped(
		GameplayInputActions.MOVE_RIGHT
	)
	assert_gt(first_receipt_id, 0)
	assert_true(clock.advance_msec(100))
	var fresh_receipt_id: int = trace.acknowledge_move_input_mapped(
		GameplayInputActions.MOVE_RIGHT
	)
	assert_gt(fresh_receipt_id, first_receipt_id)
	assert_true(
		GFVariantData.get_option_int(
			trace.get_debug_snapshot(),
			&"pending_input_receipt_count"
		) == 1,
		"同方向新输入必须替代已映射的旧收据，不能积压收据。"
	)
	assert_true(clock.advance_msec(10))
	var attempt_id: int = trace.begin_move(
		Vector2i.RIGHT,
		GameplayInputActions.MOVE_RIGHT
	)
	var presentation_id: int = trace.mark_presentation_enqueued(false)
	trace.mark_primary_feedback_state_committed(presentation_id)
	trace.complete_move(attempt_id, true)
	trace.mark_presentation_settled()
	assert_true(clock.advance_msec(16))
	trace._on_primary_feedback_frame_post_draw(
		presentation_id,
		trace._primary_feedback_frame_serial
	)
	var bundle: Dictionary = trace.get_acceptance_measurement_bundle()
	var input_series: GFMetricSeries = bundle[&"input_feedback_ms"]
	assert_true(input_series.get_sample_count() == 1)
	assert_true(
		is_equal_approx(input_series.get_latest_value(), 26.0),
		"键盘/手柄的新 action_started 不得沿用旧缓冲收据而把 26 ms 误记为 126 ms。"
	)
	var architecture: GFArchitecture = fixture[&"architecture"]
	architecture.dispose()


func test_pending_presented_frame_is_cancelled_at_scene_lifecycle_boundary() -> void:
	var fixture: Dictionary = await _create_fixture()
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	var receipt_id: int = trace.capture_move_input(
		GameplayInputActions.MOVE_UP,
		GamePerformanceTraceUtility.MOVE_INPUT_SOURCE_TOUCH
	)
	assert_true(
		trace.acknowledge_move_input_mapped(GameplayInputActions.MOVE_UP)
		== receipt_id
	)
	var attempt_id: int = trace.begin_move(
		Vector2i.UP,
		GameplayInputActions.MOVE_UP
	)
	var presentation_id: int = trace.mark_presentation_enqueued(false)
	trace.mark_primary_feedback_state_committed(presentation_id)
	var late_frame_serial: int = trace._primary_feedback_frame_serial
	assert_true(
		GFVariantData.get_option_bool(
			trace.get_debug_snapshot(),
			&"primary_feedback_frame_pending"
		)
	)

	var _trace_summary: Dictionary = trace.stop_gameplay_trace(&"scene_change")
	assert_false(
		GFVariantData.get_option_bool(
			trace.get_debug_snapshot(),
			&"primary_feedback_frame_pending"
		),
		"场景销毁必须断开全局 RenderingServer 一次性监听。"
	)
	assert_true(clock.advance_msec(16))
	trace._on_primary_feedback_frame_post_draw(attempt_id, late_frame_serial)
	assert_true(
		GFVariantData.get_option_int(
			trace.get_acceptance_measurement_state(),
			&"input_feedback_sample_count"
		) == 0,
		"场景边界后的迟到绘制不得复活已取消尝试。"
	)

	var architecture: GFArchitecture = fixture[&"architecture"]
	architecture.dispose()


func test_partial_invalidated_and_lifecycle_cleanup_are_explicit() -> void:
	var fixture: Dictionary = await _create_fixture()
	var diagnostics: GameDiagnosticsUtility = fixture[&"diagnostics"]
	var trace: GamePerformanceTraceUtility = fixture[&"trace"]
	var clock: GFManualClock = fixture[&"clock"]
	var settings: GameSettingsUtility = fixture[&"settings"]
	var architecture: GFArchitecture = fixture[&"architecture"]
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))
	_record_runtime_samples(trace, clock, 60, 10.0, 24)
	var partial: Dictionary = diagnostics.finish_gameplay_acceptance_case()
	var finished_state: Dictionary = trace.get_acceptance_measurement_state()
	assert_true(
		GFVariantData.get_option_string_name(finished_state, &"reason")
		== &"capture_completed",
		"显式 finish 必须无条件记录终止原因，同时保留证据有效性。"
	)
	assert_true(
		GFVariantData.get_option_string_name(partial, &"measurement_status")
		== &"partial"
	)
	assert_true(
		GFVariantData.get_option_string_name(partial, &"measurement_reason")
		== &"insufficient_samples"
	)

	assert_true(trace.start_gameplay_trace(false))
	var new_session_state: Dictionary = trace.get_acceptance_measurement_state()
	assert_false(GFVariantData.get_option_bool(new_session_state, &"configured"))
	assert_true(
		GFVariantData.get_option_string_name(new_session_state, &"status")
		== &"not_measured",
		"新一局不得继承上一局的 60 个样本。"
	)
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))
	_record_runtime_samples(trace, clock, 120, 10.0, 24)
	trace.record_player_visible_frame(Vector2i(1280, 720))
	var invalidated: Dictionary = diagnostics.finish_gameplay_acceptance_case()
	assert_true(
		GFVariantData.get_option_string_name(invalidated, &"measurement_status")
		== &"partial"
	)
	assert_true(
		GFVariantData.get_option_string_name(invalidated, &"measurement_reason")
		== &"viewport_changed"
	)
	assert_true(
		GFVariantData.get_option_array(
			invalidated,
			&"measured_results"
		).is_empty(),
		"采样期间条件漂移后，即使已有 120 个样本也不得签署结果。"
	)

	assert_true(trace.start_gameplay_trace(false))
	assert_true(GFVariantData.get_option_bool(
		diagnostics.begin_gameplay_acceptance_case(
			&"steam_keyboard_standard",
			_steam_standard_observation()
		),
		&"accepted"
	))
	_record_runtime_samples(trace, clock, 10, 10.0, 24)
	settings.set_value(
		GamePerformanceTraceUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
		false,
		false
	)
	var revoked_state: Dictionary = trace.get_acceptance_measurement_state()
	assert_false(GFVariantData.get_option_bool(revoked_state, &"configured"))
	assert_true(
		GFVariantData.get_option_string_name(revoked_state, &"reason")
		== &"consent_required",
		"撤回同意必须立即清掉全部指标与 Observation。"
	)

	architecture.dispose()
	var disposed_state: Dictionary = trace.get_acceptance_measurement_state()
	assert_false(GFVariantData.get_option_bool(disposed_state, &"configured"))
	assert_true(
		GFVariantData.get_option_int(disposed_state, &"frame_sample_count") == 0
	)


# --- 私有/辅助方法 ---

func _create_fixture() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var session_trace: GFSessionTraceUtility = GFSessionTraceUtility.new()
	var trace: GamePerformanceTraceUtility = GamePerformanceTraceUtility.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.persistence_enabled = false
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var manual_clock: GFManualClock = GFManualClock.new(1_000, 1_000_000)
	var clock_utility: GameClockUtility = GameClockUtility.new()
	assert_true(clock_utility.set_clock(manual_clock))

	await architecture.register_utility(GFStorageUtility, GFStorageUtility.new())
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFSessionTraceUtility, session_trace)
	await architecture.register_utility(GameClockUtility, clock_utility)
	await architecture.register_utility(GamePerformanceTraceUtility, trace)
	await architecture.init()
	settings.set_value(
		GamePerformanceTraceUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
		true,
		false
	)
	assert_true(trace.start_gameplay_trace(false))
	var diagnostics: GameDiagnosticsUtility = GameDiagnosticsUtility.new()
	diagnostics.set("_performance_trace_utility", trace)
	return {
		&"architecture": architecture,
		&"session_trace": session_trace,
		&"trace": trace,
		&"settings": settings,
		&"clock": manual_clock,
		&"diagnostics": diagnostics,
	}


func _steam_standard_observation() -> Dictionary:
	return {
		&"platform": "steam_windows",
		&"input_modality": "keyboard_mouse",
		&"viewport_size": [1920, 1080],
		&"prefer_compact": false,
		&"board_bounds": [4, 4],
		&"active_cell_count": 16,
		&"shape": "rectangle",
		&"vfx_quality": "full",
	}


func _record_runtime_samples(
	trace: GamePerformanceTraceUtility,
	clock: GFManualClock,
	count: int,
	frame_time_ms: float,
	input_feedback_ms: int
) -> void:
	_record_frame_samples(trace, clock, count, frame_time_ms)
	for _index: int in range(count):
		_record_effective_move(trace, clock, input_feedback_ms)


func _record_frame_samples(
	trace: GamePerformanceTraceUtility,
	clock: GFManualClock,
	count: int,
	frame_time_ms: float
) -> void:
	trace.record_player_visible_frame(Vector2i(1920, 1080))
	var frame_usec: int = roundi(frame_time_ms * 1000.0)
	for _index: int in range(count):
		assert_true(clock.advance_usec(frame_usec))
		trace.record_player_visible_frame(Vector2i(1920, 1080))


func _record_effective_move(
	trace: GamePerformanceTraceUtility,
	clock: GFManualClock,
	input_feedback_ms: int
) -> void:
	var _receipt_id: int = trace.capture_move_input(
		GameplayInputActions.MOVE_RIGHT,
		GamePerformanceTraceUtility.MOVE_INPUT_SOURCE_MAPPED
	)
	var _mapped_receipt_id: int = trace.acknowledge_move_input_mapped(
		GameplayInputActions.MOVE_RIGHT
	)
	var attempt_id: int = trace.begin_move(
		Vector2i.RIGHT,
		GameplayInputActions.MOVE_RIGHT
	)
	var presentation_id: int = trace.mark_presentation_enqueued(false)
	assert_true(presentation_id == attempt_id)
	assert_true(clock.advance_msec(input_feedback_ms))
	trace.mark_primary_feedback_state_committed(presentation_id)
	trace.complete_move(attempt_id, true)
	trace.mark_presentation_settled()
	trace._on_primary_feedback_frame_post_draw(
		presentation_id,
		trace._primary_feedback_frame_serial
	)
