## 渲染模式入口：采集代表性 GF UI 路由与场景路由性能证据。
##
## 请通过 tools/run_ui_route_performance_acceptance.ps1 运行；wrapper 提供进程级
## deadline、隔离日志、旧报告清理与终态校验，避免裸脚本等待渲染信号时失去收敛边界。
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
const _SETTINGS_PATH: String = (
	"res://features/settings/scenes/menus/settings_menu.tscn"
)
const _BOOKMARK_LIST_PATH: String = (
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
)
const _REPLAY_LIST_PATH: String = (
	"res://features/replays/scenes/menus/replay_list.tscn"
)
const _GAMEPLAY_PATH: String = (
	"res://features/gameplay/scenes/game/game_play.tscn"
)
const _MAIN_MENU_UI_ROUTE_IDS: Array[StringName] = [
	GameUiRouterUtility.ROUTE_SETTINGS_MENU,
	GameUiRouterUtility.ROUTE_TILE_CATALOG,
	GameUiRouterUtility.ROUTE_TILE_LAB,
	GameUiRouterUtility.ROUTE_PLAYER_PROFILE,
	GameUiRouterUtility.ROUTE_ACHIEVEMENTS,
	GameUiRouterUtility.ROUTE_MODAL_DIALOG,
]
const _MODE_SELECTION_UI_ROUTE_IDS: Array[StringName] = [
	GameUiRouterUtility.ROUTE_BOARD_EDITOR,
]
const _GAMEPLAY_UI_ROUTE_IDS: Array[StringName] = [
	GameUiRouterUtility.ROUTE_PAUSE_MENU,
	GameUiRouterUtility.ROUTE_TARGET_REACHED_MENU,
	GameUiRouterUtility.ROUTE_GAME_OVER_MENU,
]
const _UI_ROUTE_COUNT: int = 10
const _UI_ROUTE_SAMPLE_PASSES: int = 2
const _MOTION_SETTLE_TIMEOUT_SECONDS: float = 2.0
const _MOTION_SETTLE_QUIET_FRAMES: int = 3
const _SEMANTIC_READY_TIMEOUT_SECONDS: float = 4.0
const _PRELOAD_DRAIN_TIMEOUT_SECONDS: float = 1.25


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

	var harness: HarnessType = HarnessType.new()
	var _configured_harness: RefCounted = harness.configure({
		"minimum_boot_samples": 1,
		"minimum_ui_route_samples": (
			_UI_ROUTE_COUNT * _UI_ROUTE_SAMPLE_PASSES
		),
		"minimum_scene_route_samples": 9,
		"require_phase_evidence": true,
		"metadata": {
			"godot_version": Engine.get_version_info(),
			"os": OS.get_name(),
			"display_server": DisplayServer.get_name(),
			"rendering_method": RenderingServer.get_current_rendering_method(),
			"viewport": Vector2i(1280, 720),
		},
	})
	var boot_started_usec: int = Time.get_ticks_usec()
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
	var boot_ready_usec: int = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var boot_post_draw_usec: int = Time.get_ticks_usec()
	var boot_motion: Dictionary = await _wait_for_motion_settled()
	var boot_motion_settled_usec: int = Time.get_ticks_usec()
	var _boot_record: Dictionary = harness.record_boot_observation(
		boot_started_usec,
		boot_ready_usec,
		boot_post_draw_usec,
		boot_motion_settled_usec,
		{
			"cache_state": "process_first_boot",
			"motion_settled_observed": GFVariantData.get_option_bool(
				boot_motion,
				"settled"
			),
			"motion_settle": boot_motion,
		}
	)
	await _settle_frames(2)

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
	var asset_utility_value: Variant = gf_node.call(
		"get_utility",
		GFAssetUtility
	)
	var operation_diagnostics_value: Variant = gf_node.call(
		"get_utility",
		GFOperationDiagnosticsUtility
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
		or not asset_utility_value is GFAssetUtility
		or not operation_diagnostics_value is GFOperationDiagnosticsUtility
		or not screen_transition_value is GFScreenTransitionUtility
		or not scene_router_value is SceneRouterSystem
	):
		push_error("[UiRoutePerformance] 路由验收依赖不完整。")
		quit(5)
		return
	var ui_router: GameUiRouterUtility = ui_router_value
	var scene_utility: GFSceneUtility = scene_utility_value
	var asset_utility: GFAssetUtility = asset_utility_value
	var operation_diagnostics: GFOperationDiagnosticsUtility = (
		operation_diagnostics_value
	)
	var boot_operation_diagnostics: Dictionary = (
		operation_diagnostics.get_debug_snapshot()
	)
	var screen_transition: GFScreenTransitionUtility = screen_transition_value
	var scene_router: SceneRouterSystem = scene_router_value
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

	main_menu = await _run_main_menu_round_trip(
		harness,
		scene_router,
		scene_utility,
		&"main_menu_to_settings",
		_SETTINGS_PATH,
		&"SettingsMenu",
		&"settings_to_main_menu"
	)
	if is_instance_valid(main_menu):
		main_menu = await _run_main_menu_round_trip(
			harness,
			scene_router,
			scene_utility,
			&"main_menu_to_bookmarks",
			_BOOKMARK_LIST_PATH,
			&"BookmarkList",
			&"bookmarks_to_main_menu"
		)
	if is_instance_valid(main_menu):
		main_menu = await _run_main_menu_round_trip(
			harness,
			scene_router,
			scene_utility,
			&"main_menu_to_replays",
			_REPLAY_LIST_PATH,
			&"ReplayList",
			&"replays_to_main_menu"
		)

	var ui_sequence_index: int = -1
	if is_instance_valid(main_menu):
		ui_sequence_index = await _measure_ui_route_group(
			harness,
			ui_router,
			main_menu,
			_MAIN_MENU_UI_ROUTE_IDS,
			&"main_menu",
			0
		)

	var mode_selection: Node = null
	if ui_sequence_index >= 0 and is_instance_valid(main_menu):
		mode_selection = await _run_scene_route(
			harness,
			scene_router,
			scene_utility,
			&"main_menu_to_mode_selection",
			_MODE_SELECTION_PATH,
			&"ModeSelection"
		)
	if ui_sequence_index >= 0 and is_instance_valid(mode_selection):
		ui_sequence_index = await _measure_ui_route_group(
			harness,
			ui_router,
			mode_selection,
			_MODE_SELECTION_UI_ROUTE_IDS,
			&"mode_selection",
			ui_sequence_index
		)
	var game_play: Node = null
	if ui_sequence_index >= 0 and is_instance_valid(mode_selection):
		game_play = await _run_scene_route(
			harness,
			scene_router,
			scene_utility,
			&"mode_selection_to_gameplay",
			_GAMEPLAY_PATH,
			&"GamePlay",
			Callable(self, &"_start_gameplay_from_mode_selection").bind(
				mode_selection
			)
		)
	if ui_sequence_index >= 0 and is_instance_valid(game_play):
		ui_sequence_index = await _measure_ui_route_group(
			harness,
			ui_router,
			game_play,
			_GAMEPLAY_UI_ROUTE_IDS,
			&"gameplay",
			ui_sequence_index
		)
		if ui_sequence_index >= 0:
			main_menu = await _run_scene_route(
				harness,
				scene_router,
				scene_utility,
				&"gameplay_to_main_menu",
				_MAIN_MENU_PATH,
				&"MainMenu"
			)

	await _settle_frames(2)
	var preload_drain: Dictionary = await _wait_for_scene_preloads_settled(
		harness,
		_PRELOAD_DRAIN_TIMEOUT_SECONDS
	)
	var asset_preload_drain: Dictionary = await _wait_for_asset_preloads_settled(
		asset_utility,
		_PRELOAD_DRAIN_TIMEOUT_SECONDS
	)
	var report: Dictionary = harness.build_report({
		"main_menu_restored": is_instance_valid(main_menu),
		"ui_route_sequence_count": maxi(ui_sequence_index, 0),
		"ui_route_cleanup_failed": ui_sequence_index < 0,
		"preload_drain": preload_drain,
		"asset_preload_drain": asset_preload_drain,
		"active_asset_preload_session_count": (
			asset_utility.get_active_preload_session_count()
		),
		"boot_operation_diagnostics": boot_operation_diagnostics,
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

func _measure_ui_route_group(
	harness: HarnessType,
	ui_router: GameUiRouterUtility,
	owner: Node,
	route_ids: Array[StringName],
	owner_context: StringName,
	sequence_index: int
) -> int:
	var next_sequence_index: int = sequence_index
	for route_id: StringName in route_ids:
		for sample_pass: int in range(_UI_ROUTE_SAMPLE_PASSES):
			var cache_state: String = (
				"first_open_in_process"
				if sample_pass == 0
				else "warm_reopen_in_process"
			)
			var measured: bool = await _measure_ui_route(
				harness,
				ui_router,
				owner,
				route_id,
				owner_context,
				next_sequence_index,
				cache_state
			)
			if not measured:
				return -1
			next_sequence_index += 1
	return next_sequence_index


func _measure_ui_route(
	harness: HarnessType,
	ui_router: GameUiRouterUtility,
	owner: Node,
	route_id: StringName,
	owner_context: StringName,
	sequence_index: int,
	cache_state: String
) -> bool:
	var config_callback: Callable = _get_ui_route_config_callback(
		owner,
		route_id
	)
	var preload_policy: StringName = _get_ui_route_preload_policy(route_id)
	var started_usec: int = Time.get_ticks_usec()
	var route_result: GFUIRouteResult = await ui_router.push_owned_route_async(
		owner,
		route_id,
		{},
		{},
		config_callback,
		preload_policy
	)
	var panel: Node = (
		route_result.get_panel()
		if route_result != null and route_result.is_successful()
		else null
	)
	var node_ready_observed: bool = (
		is_instance_valid(panel)
		and panel.is_inside_tree()
		and panel.is_node_ready()
	)
	var semantic_ready_observed: bool = (
		node_ready_observed
		and await _wait_for_semantic_ready(
			panel,
			_SEMANTIC_READY_TIMEOUT_SECONDS
		)
	)
	var ready_observed: bool = (
		node_ready_observed and semantic_ready_observed
	)
	var ready_usec: int = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var post_draw_usec: int = Time.get_ticks_usec()
	var motion: Dictionary = await _wait_for_motion_settled()
	var motion_settled_usec: int = Time.get_ticks_usec()
	var motion_settled_observed: bool = (
		ready_observed
		and GFVariantData.get_option_bool(motion, "settled")
	)
	var _ui_route_record: Dictionary = harness.record_ui_route_result(
		route_result,
		{
			"route_id": route_id,
			"owner_context": owner_context,
			"sequence_index": sequence_index,
			"cache_state": cache_state,
			"sample_pass": (
				"first_open" if cache_state == "first_open_in_process"
				else "warm_reopen"
			),
			"preload_policy": preload_policy,
			"node_ready_observed": node_ready_observed,
			"semantic_ready_observed": semantic_ready_observed,
			"semantic_ready_contract": _get_semantic_ready_contract(panel),
			"ready_observed": ready_observed,
			"motion_settle": motion,
		},
		{
			"started_usec": started_usec,
			"ready_usec": ready_usec,
			"post_draw_usec": post_draw_usec,
			"motion_settled_usec": motion_settled_usec,
			"motion_settled_observed": motion_settled_observed,
		}
	)
	if route_result == null or not route_result.is_successful():
		return false
	var closed: bool = ui_router.back(route_result.get_layer())
	if not closed:
		var _close_failure_record: Dictionary = harness.record_ui_route_result(
			null,
			{
				"route_id": route_id,
				"owner_context": owner_context,
				"sequence_index": sequence_index,
				"cache_state": cache_state,
				"measurement_failure": &"route_close_rejected",
			}
		)
		return false
	await _settle_frames(2)
	var _close_motion: Dictionary = await _wait_for_motion_settled()
	if is_instance_valid(panel) and panel.is_inside_tree():
		var _exit_failure_record: Dictionary = harness.record_ui_route_result(
			null,
			{
				"route_id": route_id,
				"owner_context": owner_context,
				"sequence_index": sequence_index,
				"cache_state": cache_state,
				"measurement_failure": &"panel_remained_in_tree",
			}
		)
		return false
	return true


func _get_ui_route_config_callback(
	owner: Node,
	route_id: StringName
) -> Callable:
	if route_id == GameUiRouterUtility.ROUTE_MODAL_DIALOG:
		return Callable(self, &"_configure_measurement_modal").bind(owner)
	if route_id == GameUiRouterUtility.ROUTE_SETTINGS_MENU:
		return Callable(self, &"_configure_measurement_settings")
	if (
		route_id == GameUiRouterUtility.ROUTE_BOARD_EDITOR
		and is_instance_valid(owner)
		and owner.has_method(&"_configure_board_editor")
	):
		return Callable(owner, &"_configure_board_editor")
	return Callable()


func _get_ui_route_preload_policy(route_id: StringName) -> StringName:
	if route_id == GameUiRouterUtility.ROUTE_BOARD_EDITOR:
		return GFUIRouterUtility.PRELOAD_REQUIRED
	if route_id == GameUiRouterUtility.ROUTE_SETTINGS_MENU:
		return GFUIRouterUtility.PRELOAD_NONE
	return GFUIRouterUtility.PRELOAD_BEST_EFFORT


func _configure_measurement_settings(panel: Node) -> void:
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if panel is SettingsMenu:
		var settings_menu: SettingsMenu = panel
		settings_menu.return_to_main_menu_on_back = false


func _configure_measurement_modal(panel: Node, owner: Node) -> void:
	if not panel is GameModalRoutePanel:
		return
	var modal_panel: GameModalRoutePanel = panel
	modal_panel.configure(
		GameUiRouterUtility.make_acknowledgement_modal_config(
			"Performance probe",
			"Bounded route timing fixture.",
			"Close"
		),
		{"source": &"ui_route_performance"},
		owner
	)


func _start_gameplay_from_mode_selection(mode_selection: Node) -> bool:
	if not is_instance_valid(mode_selection):
		return false
	var start_button_value: Node = mode_selection.find_child(
		"StartGameButton",
		true,
		false
	)
	if not start_button_value is Button:
		return false
	var start_button: Button = start_button_value
	if start_button.disabled:
		return false
	start_button.pressed.emit()
	return true


func _run_main_menu_round_trip(
	harness: HarnessType,
	scene_router: SceneRouterSystem,
	scene_utility: GFSceneUtility,
	forward_route_id: StringName,
	target_path: String,
	target_name: StringName,
	return_route_id: StringName
) -> Node:
	var target: Node = await _run_scene_route(
		harness,
		scene_router,
		scene_utility,
		forward_route_id,
		target_path,
		target_name
	)
	if not is_instance_valid(target):
		return null
	return await _run_scene_route(
		harness,
		scene_router,
		scene_utility,
		return_route_id,
		_MAIN_MENU_PATH,
		&"MainMenu"
	)


func _run_scene_route(
	harness: HarnessType,
	scene_router: SceneRouterSystem,
	scene_utility: GFSceneUtility,
	route_id: StringName,
	target_path: String,
	target_name: StringName,
	request_callback: Callable = Callable()
) -> Node:
	if not harness.call(
		"begin_scene_route",
		route_id,
		target_path,
		{
			"cache_state": _get_scene_cache_state_label(
				scene_utility,
				target_path
			),
			"motion_settle_policy": "global_tween_quiet_window",
		}
	):
		return null
	var request_accepted: bool = true
	if request_callback.is_valid():
		var request_result: Variant = request_callback.call()
		if request_result is bool:
			request_accepted = request_result
	else:
		scene_router.goto_scene(target_path)
	if not request_accepted:
		var _rejected_record: Variant = harness.call(
			"complete_scene_route",
			false,
			{
				"interactive_ready": false,
				"target_node": String(target_name),
				"request_accepted": false,
				"motion_settled_observed": false,
			}
		)
		return null
	var target: Node = await _wait_for_node(target_name, 900)
	var node_ready_observed: bool = (
		is_instance_valid(target)
		and target.is_inside_tree()
		and target.is_node_ready()
	)
	var semantic_ready_observed: bool = (
		node_ready_observed
		and await _wait_for_semantic_ready(
			target,
			_SEMANTIC_READY_TIMEOUT_SECONDS
		)
	)
	var ready_observed: bool = (
		node_ready_observed and semantic_ready_observed
	)
	if ready_observed:
		var _ready_marked: Variant = harness.call(
			"mark_scene_route_milestone",
			&"ready"
		)
		await RenderingServer.frame_post_draw
		var _post_draw_marked: Variant = harness.call(
			"mark_scene_route_milestone",
			&"post_draw"
		)
	var route_idle: bool = await _wait_for_scene_change_idle(
		scene_router,
		10.0
	)
	var route_ready_usec: int = Time.get_ticks_usec()
	var motion: Dictionary = await _wait_for_motion_settled()
	var motion_settled_observed: bool = (
		ready_observed
		and route_idle
		and GFVariantData.get_option_bool(motion, "settled")
	)
	if motion_settled_observed:
		var _motion_marked: Variant = harness.call(
			"mark_scene_route_milestone",
			&"motion_settled"
		)
	var interactive_ready: bool = (
		route_idle
		and ready_observed
	)
	var _record: Variant = harness.call(
		"complete_scene_route",
		interactive_ready,
		{
			"interactive_ready": interactive_ready,
			"target_node": String(target_name),
			"node_ready_observed": node_ready_observed,
			"semantic_ready_observed": semantic_ready_observed,
			"semantic_ready_contract": _get_semantic_ready_contract(target),
			"request_accepted": request_accepted,
			"route_ready_usec": route_ready_usec,
			"motion_settled_observed": motion_settled_observed,
			"motion_settle": motion,
		}
	)
	return target if interactive_ready else null


func _get_scene_cache_state_label(
	scene_utility: GFSceneUtility,
	target_path: String
) -> String:
	if not is_instance_valid(scene_utility):
		return "scene_utility_unavailable"
	match scene_utility.get_scene_resource_state(target_path):
		GFSceneUtility.SceneResourceState.PRELOADING:
			return "preloading_before_request"
		GFSceneUtility.SceneResourceState.PRELOADED:
			return "preloaded_before_request"
		GFSceneUtility.SceneResourceState.ACTIVE_LOADING:
			return "active_loading_before_request"
		_:
			return "not_loaded_before_request"


func _wait_for_semantic_ready(
	target: Node,
	timeout_seconds: float
) -> bool:
	var deadline_usec: int = Time.get_ticks_usec() + ceili(
		maxf(timeout_seconds, 0.0) * 1_000_000.0
	)
	while is_instance_valid(target) and Time.get_ticks_usec() <= deadline_usec:
		if _is_semantic_ready(target):
			return true
		await process_frame
	return false


func _is_semantic_ready(target: Node) -> bool:
	if target is BoardEditorDialog:
		var board_editor: BoardEditorDialog = target
		return board_editor.is_interaction_ready()
	if target is GamePlayController:
		var game_play: GamePlayController = target
		return game_play.is_interaction_ready()
	if target is BaseListMenu:
		var list_menu: BaseListMenu = target
		return list_menu.is_content_ready()
	if target is PlayerProfileDialog:
		var profile_dialog: PlayerProfileDialog = target
		return profile_dialog.is_content_ready()
	return true


func _get_semantic_ready_contract(target: Node) -> StringName:
	if target is BoardEditorDialog:
		return &"board_editor_interaction_ready"
	if target is GamePlayController:
		return &"gameplay_board_ready"
	if target is BaseListMenu:
		return &"list_content_ready"
	if target is PlayerProfileDialog:
		return &"profile_progress_snapshot_terminal"
	return &"node_ready"


func _wait_for_scene_preloads_settled(
	harness: HarnessType,
	timeout_seconds: float
) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + ceili(
		maxf(timeout_seconds, 0.0) * 1_000_000.0
	)
	while Time.get_ticks_usec() <= deadline_usec:
		var pending_count: int = harness.get_pending_scene_preload_count()
		if pending_count == 0:
			return {
				"settled": true,
				"pending_count": 0,
				"elapsed_msec": float(
					Time.get_ticks_usec() - started_usec
				) / 1000.0,
			}
		await process_frame
	return {
		"settled": false,
		"pending_count": harness.get_pending_scene_preload_count(),
		"elapsed_msec": float(
			Time.get_ticks_usec() - started_usec
		) / 1000.0,
		"timeout_seconds": timeout_seconds,
	}


func _wait_for_asset_preloads_settled(
	asset_utility: GFAssetUtility,
	timeout_seconds: float
) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + ceili(
		maxf(timeout_seconds, 0.0) * 1_000_000.0
	)
	while Time.get_ticks_usec() <= deadline_usec:
		var pending_count: int = asset_utility.get_active_preload_session_count()
		if pending_count == 0:
			return {
				"settled": true,
				"pending_count": 0,
				"elapsed_msec": float(
					Time.get_ticks_usec() - started_usec
				) / 1000.0,
			}
		await process_frame
	return {
		"settled": false,
		"pending_count": asset_utility.get_active_preload_session_count(),
		"elapsed_msec": float(
			Time.get_ticks_usec() - started_usec
		) / 1000.0,
		"timeout_seconds": timeout_seconds,
	}


func _wait_for_motion_settled() -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + ceili(
		_MOTION_SETTLE_TIMEOUT_SECONDS * 1_000_000.0
	)
	var quiet_frames: int = 0
	var max_active_tweens: int = 0
	while Time.get_ticks_usec() <= deadline_usec:
		var active_tweens: int = 0
		for tween: Tween in get_processed_tweens():
			if tween != null and tween.is_valid() and tween.is_running():
				active_tweens += 1
		max_active_tweens = maxi(max_active_tweens, active_tweens)
		if active_tweens == 0:
			quiet_frames += 1
			if quiet_frames >= _MOTION_SETTLE_QUIET_FRAMES:
				return {
					"settled": true,
					"policy": "global_tween_quiet_window",
					"quiet_frames": quiet_frames,
					"max_active_tweens": max_active_tweens,
					"elapsed_msec": float(
						Time.get_ticks_usec() - started_usec
					) / 1000.0,
				}
		else:
			quiet_frames = 0
		await process_frame
	return {
		"settled": false,
		"policy": "global_tween_quiet_window",
		"quiet_frames": quiet_frames,
		"max_active_tweens": max_active_tweens,
		"elapsed_msec": float(
			Time.get_ticks_usec() - started_usec
		) / 1000.0,
		"timeout_seconds": _MOTION_SETTLE_TIMEOUT_SECONDS,
	}


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
