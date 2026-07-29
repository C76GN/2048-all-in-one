## 渲染模式入口：采集代表性 GF UI 路由与场景路由性能证据。
##
## 运行：
## godot --path . --script res://tools/run_ui_route_performance_acceptance.gd
extends SceneTree


# --- 常量 ---

const HarnessType = preload(
	"res://tools/ui_route_performance_acceptance_harness.gd"
)
const _REPORT_PATH: String = (
	"res://build/ui_route_performance/route_timing_report.json"
)
const _MODE_SELECTION_PATH: String = (
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)
const _MAIN_MENU_PATH: String = (
	"res://features/navigation/scenes/menus/main_menu.tscn"
)
const _UI_ROUTE_IDS: Array[StringName] = [
	GameUiRouterUtility.ROUTE_TILE_CATALOG,
	GameUiRouterUtility.ROUTE_TILE_LAB,
	GameUiRouterUtility.ROUTE_PLAYER_PROFILE,
	GameUiRouterUtility.ROUTE_ACHIEVEMENTS,
]


# --- 生命周期 ---

func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[UiRoutePerformance] 必须在渲染模式运行。")
		quit(64)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	var boot_scene: PackedScene = load("res://app/scenes/boot.tscn")
	if boot_scene == null:
		push_error("[UiRoutePerformance] 无法加载 Boot 场景。")
		quit(2)
		return
	root.add_child(boot_scene.instantiate())
	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[UiRoutePerformance] MainMenu 启动超时。")
		quit(3)
		return
	await _settle_frames(4)

	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		push_error("[UiRoutePerformance] 缺少 Gf 根节点。")
		quit(4)
		return
	var ui_router_value: Variant = gf_node.call(
		"get_utility",
		GameUiRouterUtility
	)
	var scene_utility_value: Variant = gf_node.call(
		"get_utility",
		GFSceneUtility
	)
	var screen_transition_value: Variant = gf_node.call(
		"get_utility",
		GFScreenTransitionUtility
	)
	var scene_router_value: Variant = gf_node.call(
		"get_system",
		SceneRouterSystem
	)
	if (
		not ui_router_value is GameUiRouterUtility
		or not scene_utility_value is GFSceneUtility
		or not screen_transition_value is GFScreenTransitionUtility
		or not scene_router_value is SceneRouterSystem
	):
		push_error("[UiRoutePerformance] 路由验收依赖不完整。")
		quit(5)
		return
	var ui_router: GameUiRouterUtility = ui_router_value
	var scene_utility: GFSceneUtility = scene_utility_value
	var screen_transition: GFScreenTransitionUtility = screen_transition_value
	var scene_router: SceneRouterSystem = scene_router_value
	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_ui_route_samples": _UI_ROUTE_IDS.size(),
		"minimum_scene_route_samples": 2,
		"metadata": {
			"godot_version": Engine.get_version_info(),
			"os": OS.get_name(),
			"display_server": DisplayServer.get_name(),
			"rendering_method": RenderingServer.get_current_rendering_method(),
			"viewport": Vector2i(1280, 720),
		},
	})
	if not harness.bind_scene_utility(scene_utility):
		push_error("[UiRoutePerformance] 无法监听 GFSceneUtility。")
		quit(6)
		return
	if not harness.bind_screen_transition_utility(screen_transition):
		harness.unbind_scene_utility()
		push_error(
			"[UiRoutePerformance] 无法监听 GFScreenTransitionUtility。"
		)
		quit(6)
		return

	for route_index: int in range(_UI_ROUTE_IDS.size()):
		var route_id: StringName = _UI_ROUTE_IDS[route_index]
		var route_result: GFUIRouteResult = await (
			ui_router.push_owned_route_async(main_menu, route_id)
		)
		var _ui_route_record: Dictionary = harness.record_ui_route_result(
			route_result,
			{
				"route_id": route_id,
				"sequence_index": route_index,
				"cache_state": "first_open_in_process",
			}
		)
		if route_result == null or not route_result.is_successful():
			continue
		await _settle_frames(2)
		var _closed: bool = ui_router.back(route_result.get_layer())
		await _settle_frames(4)

	var mode_selection: Node = await _run_scene_route(
		harness,
		scene_router,
		&"main_menu_to_mode_selection",
		_MODE_SELECTION_PATH,
		&"ModeSelection"
	)
	if is_instance_valid(mode_selection):
		main_menu = await _run_scene_route(
			harness,
			scene_router,
			&"mode_selection_to_main_menu",
			_MAIN_MENU_PATH,
			&"MainMenu"
		)

	await _settle_frames(2)
	var report: Dictionary = harness.build_report({
		"main_menu_restored": is_instance_valid(main_menu),
	})
	var report_passed: bool = GFVariantData.get_option_bool(report, "passed")
	var write_error: Error = harness.write_report(report, _REPORT_PATH)
	harness.unbind_scene_utility()
	harness.unbind_screen_transition_utility()
	if write_error != OK:
		push_error(
			"[UiRoutePerformance] 报告写入失败，错误码：%d。" % write_error
		)
		harness = null
		ui_router = null
		scene_utility = null
		screen_transition = null
		scene_router = null
		call_deferred(&"_cleanup_and_quit", 7)
		return
	print(
		"[UiRoutePerformance] report=%s passed=%s ui_routes=%d scene_routes=%d"
		% [
			_REPORT_PATH,
			str(report_passed),
			GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(report, "summary"),
				"ui_route_count"
			),
			GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(report, "summary"),
				"scene_route_count"
			),
		]
	)
	var exit_code: int = 0 if report_passed else 1
	report = {}
	harness = null
	ui_router = null
	scene_utility = null
	screen_transition = null
	scene_router = null
	main_menu = null
	gf_node = null
	boot_scene = null
	call_deferred(
		&"_cleanup_and_quit",
		exit_code
	)


# --- 私有/辅助方法 ---

func _run_scene_route(
	harness: HarnessType,
	scene_router: SceneRouterSystem,
	route_id: StringName,
	target_path: String,
	target_name: StringName
) -> Node:
	if not harness.call(
		"begin_scene_route",
		route_id,
		target_path,
		{"cache_state": "runtime_preload_map"}
	):
		return null
	scene_router.goto_scene(target_path)
	var target: Node = await _wait_for_node(target_name, 900)
	var route_idle: bool = await _wait_for_scene_change_idle(
		scene_router,
		5.0
	)
	if route_idle and is_instance_valid(target):
		await _settle_frames(2)
	var interactive_ready: bool = (
		route_idle
		and is_instance_valid(target)
		and target.is_inside_tree()
	)
	var _record: Variant = harness.call(
		"complete_scene_route",
		interactive_ready,
		{
			"interactive_ready": interactive_ready,
			"target_node": String(target_name),
		}
	)
	return target if interactive_ready else null


func _wait_for_scene_change_idle(
	scene_router: SceneRouterSystem,
	timeout_seconds: float
) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ceili(
		timeout_seconds * 1000.0
	)
	while Time.get_ticks_msec() <= deadline_msec:
		var snapshot: Dictionary = scene_router.get_debug_snapshot()
		if not GFVariantData.get_option_bool(
			snapshot,
			"scene_change_active",
			false
		):
			return true
		await create_timer(0.02, true, false, true).timeout
	return false


func _wait_for_node(node_name: StringName, frame_budget: int) -> Node:
	for _frame: int in range(frame_budget):
		var node: Node = root.find_child(String(node_name), true, false)
		if is_instance_valid(node):
			return node
		await process_frame
	return null


func _settle_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
	await RenderingServer.frame_post_draw


func _cleanup_and_quit(exit_code: int) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	GFExtensionSettings.clear_manifest_cache()
	quit(exit_code)
