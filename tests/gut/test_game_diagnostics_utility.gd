## 验证项目诊断通过 GF Diagnostics 和 Support Report 扩展点接入。
extends GutTest


# --- 常量 ---

const _GAME_DIAGNOSTICS_UTILITY_SCRIPT = preload("res://features/diagnostics/scripts/utilities/game_diagnostics_utility.gd")


# --- 测试用例 ---

func test_project_diagnostics_registers_and_releases_gf_extensions() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var log_utility: GFLogUtility = GFLogUtility.new()
	var console: GFConsoleUtility = GFConsoleUtility.new()
	var diagnostics: GFDiagnosticsUtility = GFDiagnosticsUtility.new()
	var session_trace: GFSessionTraceUtility = GFSessionTraceUtility.new()
	var performance_trace: GamePerformanceTraceUtility = (
		GamePerformanceTraceUtility.new()
	)
	var support_reports: GFSupportReportUtility = GFSupportReportUtility.new()
	var asset_metadata: GFAssetMetadataUtility = GFAssetMetadataUtility.new()
	var debug_overlay: GFDebugOverlayUtility = GFDebugOverlayUtility.new()
	var runtime_inspector: GFRuntimeInspectorUtility = GFRuntimeInspectorUtility.new()
	var screenshots: GFScreenshotUtility = GFScreenshotUtility.new()
	var project_diagnostics: GFUtility = _GAME_DIAGNOSTICS_UTILITY_SCRIPT.new()

	await architecture.register_utility(GFLogUtility, log_utility)
	await architecture.register_utility(GFConsoleUtility, console)
	await architecture.register_utility(GFDiagnosticsUtility, diagnostics)
	await architecture.register_utility(GFSessionTraceUtility, session_trace)
	await architecture.register_utility(
		GamePerformanceTraceUtility,
		performance_trace
	)
	await architecture.register_utility(GFSupportReportUtility, support_reports)
	await architecture.register_utility(GFAssetMetadataUtility, asset_metadata)
	await architecture.register_utility(GFDebugOverlayUtility, debug_overlay)
	await architecture.register_utility(GFRuntimeInspectorUtility, runtime_inspector)
	await architecture.register_utility(GFScreenshotUtility, screenshots)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT, project_diagnostics)
	await architecture.init()

	assert_true(console.has_command("diagnostics"), "GFDiagnosticsUtility 应提供标准 diagnostics 命令。")
	assert_true(console.has_command("support_report"), "项目诊断应提供支持报告落盘命令。")
	assert_true(console.has_command("screenshot"), "项目诊断应提供 GF Viewport 截图命令。")
	assert_true(
		diagnostics.has_diagnostic_provider(&"resource_catalog"),
		"项目资源目录应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"project_diagnostics"),
		"项目诊断接入状态应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"tile_catalog"),
		"方块资源目录应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"tile_discoveries"),
		"方块发现进度应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"achievement_catalog"),
		"成就资源目录应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"achievements"),
		"成就进度应通过 GF 惰性 Provider 按需采集。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"architecture_dependencies"),
		"GF 声明式依赖图应进入项目诊断快照。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"gameplay_acceptance_matrix"),
		"输入、尺寸和性能验收矩阵应进入项目诊断快照。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"scene_asset_metadata"),
		"当前场景的 GF 资产元数据报告应仅在显式请求时采集。"
	)
	assert_true(
		diagnostics.has_diagnostic_provider(&"gameplay_move_trace"),
		"移动卡顿轨迹应通过有界 GF 惰性 Provider 导出。"
	)
	assert_true(debug_overlay.has_panel(&"game.project_diagnostics"), "项目状态应进入 GF Debug Overlay。")
	assert_true(
		runtime_inspector.has_target(&"game.debug_overlay"),
		"GF Runtime Inspector 应暴露 Overlay 调试参数。"
	)
	assert_true(
		runtime_inspector.has_target(&"game.screenshots"),
		"GF Runtime Inspector 应暴露截图参数。"
	)
	assert_true(
		runtime_inspector.set_property_value(
			&"game.debug_overlay",
			&"refresh_interval_seconds",
			0.5
		),
		"Runtime Inspector 应能通过显式 schema 调整 Overlay 刷新间隔。"
	)
	assert_true(
		is_equal_approx(debug_overlay.refresh_interval_seconds, 0.5),
		"Overlay 刷新间隔写入应调用 GF 的公开 setter。"
	)

	var snapshot: Dictionary = diagnostics.collect_snapshot({"include_recent_logs": false})
	var tools: Dictionary = GFVariantData.get_option_dictionary(snapshot, "tools")
	assert_true(tools.has(&"architecture_dependencies"), "GF 标准快照应聚合声明式依赖诊断。")
	assert_true(
		tools.has(&"gameplay_acceptance_matrix"),
		"GF 标准快照应聚合输入、尺寸和性能验收矩阵。"
	)
	assert_false(
		tools.has(&"scene_asset_metadata"),
		"普通快照不得隐式扫描当前场景资产元数据。"
	)
	assert_false(
		snapshot.has("diagnostic_providers"),
		"未显式提供 Provider ID 时不得执行任何动态项目采集。"
	)

	var requested_snapshot: Dictionary = diagnostics.collect_snapshot({
		"include_recent_logs": false,
		"diagnostic_provider_ids": PackedStringArray([
			"project_diagnostics",
			"tile_catalog",
			"gameplay_move_trace",
		]),
		"diagnostic_provider_request": {"reason": "gut_explicit_request"},
	})
	var provider_batch: Dictionary = GFVariantData.get_option_dictionary(
		requested_snapshot,
		"diagnostic_providers"
	)
	assert_true(
		GFVariantData.get_option_int(provider_batch, "executed_count") == 3,
		"显式请求只应执行列出的三个 Provider。"
	)
	assert_true(
		GFVariantData.get_option_int(provider_batch, "success_count") == 3,
		"可用与 unavailable 快照都应形成成功、类型化的 Provider 结果。"
	)

	architecture.dispose()
	await get_tree().process_frame
	assert_false(console.has_command("support_report"), "销毁 Architecture 时应注销项目支持报告命令。")
	assert_false(console.has_command("screenshot"), "销毁 Architecture 时应注销截图命令。")
	assert_false(
		diagnostics.has_diagnostic_provider(&"project_diagnostics"),
		"销毁 Architecture 时应注销项目惰性诊断 Provider。"
	)


func test_gameplay_move_trace_is_bounded_and_exposes_only_phase_metrics() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var session_trace: GFSessionTraceUtility = GFSessionTraceUtility.new()
	var performance_trace: GamePerformanceTraceUtility = (
		GamePerformanceTraceUtility.new()
	)
	await architecture.register_utility(GFSessionTraceUtility, session_trace)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(
		GamePerformanceTraceUtility,
		performance_trace
	)
	await architecture.init()

	assert_true(performance_trace.start_gameplay_trace(false))
	var attempt_id: int = performance_trace.begin_move(Vector2i.RIGHT)
	performance_trace.mark_presentation_enqueued(false)
	performance_trace.complete_move(attempt_id, true)
	performance_trace.mark_presentation_settled()

	var events: Array[Dictionary] = session_trace.get_events()
	var event_ids: PackedStringArray = PackedStringArray()
	for event: Dictionary in events:
		var _event_id_appended: bool = event_ids.append(
			String(GFVariantData.get_option_string_name(event, "event_id"))
		)
	assert_true(
		event_ids == PackedStringArray([
			"move_requested",
			"move_presentation_enqueued",
			"move_command_completed",
			"move_presentation_settled",
		]),
		"轨迹应保留输入、入队、命令完成和表现完成的可关联阶段。"
	)
	var serialized: String = JSON.stringify(events)
	for forbidden_field: String in [
		"account",
		"board_snapshot",
		"save_path",
		"absolute_path",
	]:
		assert_false(
			serialized.contains(forbidden_field),
			"移动轨迹不得包含业务或身份字段：%s。" % forbidden_field
		)

	assert_true(performance_trace.start_gameplay_trace(false))
	var immediate_attempt_id: int = performance_trace.begin_move(Vector2i.UP)
	performance_trace.mark_presentation_enqueued(false)
	performance_trace.mark_presentation_settled()
	performance_trace.complete_move(immediate_attempt_id, true)
	assert_false(
		GFVariantData.get_option_bool(
			performance_trace.get_debug_snapshot(),
			"active_attempt"
		),
		"无动效批次同步排空时，迟到的命令终态仍必须释放尝试。"
	)

	for _index: int in range(80):
		var rejected_attempt_id: int = performance_trace.begin_move(Vector2i.LEFT)
		performance_trace.complete_move(rejected_attempt_id, false)
	assert_true(
		session_trace.get_events().size() <= 96,
		"GF Session Trace 必须按项目预算淘汰旧事件。"
	)

	architecture.dispose()


func test_scene_router_reuses_gf_operation_start_tick() -> void:
	var operation_diagnostics: GFOperationDiagnosticsUtility = GFOperationDiagnosticsUtility.new()
	operation_diagnostics.init()
	var router: SceneRouterSystem = SceneRouterSystem.new()
	router.set("_operation_diagnostics", operation_diagnostics)

	var _begin_result: Variant = router.call(
		"_begin_scene_change_operation",
		"res://features/navigation/scenes/menus/main_menu.tscn"
	)
	var router_snapshot: Dictionary = router.get_debug_snapshot()
	var operations: Array[Dictionary] = operation_diagnostics.get_operations(1, {
		"operation_type": &"game.scene_change",
	})
	var operation: Dictionary = operations[0] if not operations.is_empty() else {}
	var router_started_ticks: int = GFVariantData.get_option_int(router_snapshot, "scene_change_started_usec")
	var operation_started_ticks: int = GFVariantData.get_option_int(operation, "started_ticks_usec")

	assert_gt(router_started_ticks, 0, "场景路由诊断应暴露 GF 操作记录的起始 tick。")
	assert_true(router_started_ticks == operation_started_ticks, "场景路由不得平行维护另一份操作起始 tick。")

	router.dispose()
	operation_diagnostics.dispose()
