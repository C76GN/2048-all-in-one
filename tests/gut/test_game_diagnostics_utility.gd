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
	var support_reports: GFSupportReportUtility = GFSupportReportUtility.new()
	var asset_metadata: GFAssetMetadataUtility = GFAssetMetadataUtility.new()
	var debug_overlay: GFDebugOverlayUtility = GFDebugOverlayUtility.new()
	var runtime_inspector: GFRuntimeInspectorUtility = GFRuntimeInspectorUtility.new()
	var screenshots: GFScreenshotUtility = GFScreenshotUtility.new()
	var project_diagnostics: GFUtility = _GAME_DIAGNOSTICS_UTILITY_SCRIPT.new()

	await architecture.register_utility(GFLogUtility, log_utility)
	await architecture.register_utility(GFConsoleUtility, console)
	await architecture.register_utility(GFDiagnosticsUtility, diagnostics)
	await architecture.register_utility(GFSupportReportUtility, support_reports)
	await architecture.register_utility(GFAssetMetadataUtility, asset_metadata)
	await architecture.register_utility(GFDebugOverlayUtility, debug_overlay)
	await architecture.register_utility(GFRuntimeInspectorUtility, runtime_inspector)
	await architecture.register_utility(GFScreenshotUtility, screenshots)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT, project_diagnostics)
	await architecture.init()
	await get_tree().process_frame

	assert_true(console.has_command("diagnostics"), "GFDiagnosticsUtility 应提供标准 diagnostics 命令。")
	assert_true(console.has_command("support_report"), "项目诊断应提供支持报告落盘命令。")
	assert_true(console.has_command("screenshot"), "项目诊断应提供 GF Viewport 截图命令。")
	assert_true(
		diagnostics.has_tool_snapshot(&"resource_catalog"),
		"项目资源目录应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"project_diagnostics"),
		"项目诊断接入状态应能被 GF 诊断快照观察。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"tile_catalog"),
		"方块资源目录应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"tile_discoveries"),
		"方块发现进度应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"achievement_catalog"),
		"成就资源目录应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"achievements"),
		"成就进度应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"architecture_dependencies"),
		"GF 声明式依赖图应进入项目诊断快照。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"scene_asset_metadata"),
		"当前场景的 GF 资产元数据报告应进入项目诊断快照。"
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
	assert_true(tools.has(&"project_diagnostics"), "GF 标准快照应聚合项目诊断状态。")
	assert_true(tools.has(&"architecture_dependencies"), "GF 标准快照应聚合声明式依赖诊断。")
	assert_true(tools.has(&"scene_asset_metadata"), "GF 标准快照应聚合场景资产元数据。")
	assert_true(tools.has(&"tile_catalog"), "GF 标准快照应聚合方块资源目录。")
	assert_true(tools.has(&"tile_discoveries"), "GF 标准快照应聚合方块发现进度。")
	assert_true(tools.has(&"achievement_catalog"), "GF 标准快照应聚合成就资源目录。")
	assert_true(tools.has(&"achievements"), "GF 标准快照应聚合成就进度。")

	architecture.dispose()
	await get_tree().process_frame
	assert_false(console.has_command("support_report"), "销毁 Architecture 时应注销项目支持报告命令。")
	assert_false(console.has_command("screenshot"), "销毁 Architecture 时应注销截图命令。")
	assert_false(
		diagnostics.has_tool_snapshot(&"project_diagnostics"),
		"销毁 Architecture 时应移除项目诊断快照。"
	)


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
