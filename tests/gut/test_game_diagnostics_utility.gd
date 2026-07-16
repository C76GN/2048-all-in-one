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
	var project_diagnostics: GFUtility = _GAME_DIAGNOSTICS_UTILITY_SCRIPT.new()

	await architecture.register_utility(GFLogUtility, log_utility)
	await architecture.register_utility(GFConsoleUtility, console)
	await architecture.register_utility(GFDiagnosticsUtility, diagnostics)
	await architecture.register_utility(GFSupportReportUtility, support_reports)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT, project_diagnostics)
	await architecture.init()

	assert_true(console.has_command("diagnostics"), "GFDiagnosticsUtility 应提供标准 diagnostics 命令。")
	assert_true(console.has_command("support_report"), "项目诊断应提供支持报告落盘命令。")
	assert_true(
		diagnostics.has_tool_snapshot(&"resource_catalog"),
		"项目资源目录应通过 GF 工具快照扩展诊断。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"project_diagnostics"),
		"项目诊断接入状态应能被 GF 诊断快照观察。"
	)
	assert_true(
		diagnostics.has_tool_snapshot(&"architecture_dependencies"),
		"GF 声明式依赖图应进入项目诊断快照。"
	)

	var snapshot: Dictionary = diagnostics.collect_snapshot({"include_recent_logs": false})
	var tools: Dictionary = GFVariantData.get_option_dictionary(snapshot, "tools")
	assert_true(tools.has(&"project_diagnostics"), "GF 标准快照应聚合项目诊断状态。")
	assert_true(tools.has(&"architecture_dependencies"), "GF 标准快照应聚合声明式依赖诊断。")

	architecture.dispose()
	await get_tree().process_frame
	assert_false(console.has_command("support_report"), "销毁 Architecture 时应注销项目支持报告命令。")
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
