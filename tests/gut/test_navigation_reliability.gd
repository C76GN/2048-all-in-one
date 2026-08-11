## 验证主菜单继续流程与历史列表的破坏性操作、焦点可靠性。
extends GutTest


# --- 常量 ---

const _MAIN_MENU_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/main_menu.tscn"
)
const _BOOKMARK_LIST_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
)
const _REPLAY_LIST_SCENE: PackedScene = preload(
	"res://features/replays/scenes/menus/replay_list.tscn"
)
const _CLASSIC_MODE_CONFIG: GameModeConfig = preload(
	"res://features/gameplay/resources/modes/classic_mode_config.tres"
)
const _GAME_SCENE_PATH: String = "res://features/gameplay/scenes/game/game_play.tscn"
const _MODE_SELECTION_SCENE_PATH: String = (
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)
const _SCENE_PRELOAD_MAP: GFScenePreloadMap = preload(
	"res://features/navigation/resources/scene_preload_map.tres"
)


# --- 测试用例 ---

func test_persistence_reconciliation_messages_have_translation_entries() -> void:
	for key: StringName in [
		&"LIST_DELETE_PERSISTENCE_OUTCOME_UNKNOWN",
		&"LIST_DELETE_RECONCILIATION_SUCCEEDED",
		&"LIST_DELETE_RECONCILIATION_ROLLED_BACK",
		&"LIST_DELETE_RECONCILIATION_UNRESOLVED",
		&"BOARD_EDITOR_PERSISTENCE_OUTCOME_UNKNOWN",
		&"BOARD_EDITOR_RECONCILIATION_SUCCEEDED",
		&"BOARD_EDITOR_RECONCILIATION_ROLLED_BACK",
		&"TILE_LAB_PERSISTENCE_OUTCOME_UNKNOWN",
		&"TILE_LAB_RECONCILIATION_SUCCEEDED",
		&"TILE_LAB_RECONCILIATION_ROLLED_BACK",
		&"LOCAL_LEADERBOARD_LOADING",
		&"PLAYER_PROFILE_LOADING",
		&"PLAYER_PROFILE_PARTIAL",
	]:
		assert_true(
			tr(key) != String(key),
			"玩家可见持久化文案缺少翻译条目：%s。" % key
		)


func test_main_menu_splits_continue_and_load_save_actions() -> void:
	var menu_node: Node = _MAIN_MENU_SCENE.instantiate()
	assert_true(menu_node is MainMenu, "主菜单场景应实例化为 MainMenu。")
	if not menu_node is MainMenu:
		menu_node.free()
		return
	var menu: MainMenu = menu_node
	var continue_button: Node = menu.find_child("ContinueGameButton", true, false)
	var load_button: Node = menu.find_child("LoadBookmarkButton", true, false)
	assert_true(continue_button is Button, "主菜单应提供独立的继续游戏按钮。")
	assert_true(load_button is Button, "主菜单应保留独立的读取存档按钮。")
	assert_ne(continue_button, load_button, "继续游戏与读取存档不得复用同一动作按钮。")
	assert_true(
		menu.game_scene_path == _GAME_SCENE_PATH,
		"继续游戏必须声明目标游戏场景。"
	)
	menu.free()


func test_quit_is_idempotent_and_waits_for_gf_architecture_shutdown() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var router: _QuitProbe = _QuitProbe.new()
	await architecture.register_system(SceneRouterSystem, router)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "退出路由夹具必须完成 GF 架构初始化。")
	if not initialized:
		architecture.dispose()
		return

	var first: GFAsyncCompletion = router.quit_game()
	var second: GFAsyncCompletion = router.quit_game()
	assert_same(first, second, "重复退出请求必须共享同一个关闭流程。")
	var quit_probe: Dictionary = router.quit_probe
	router = null
	if first != null and first.is_pending():
		await first.completed
	assert_true(
		first != null and first.is_successful(),
		"退出完成源必须反映 GF 架构已完成 graceful shutdown。"
	)
	assert_true(architecture.is_disposed(), "SceneTree 退出前 GF 架构必须已释放。")
	assert_true(
		GFVariantData.get_option_int(quit_probe, &"count") == 1,
		"即使调用者不保留路由引用，重复退出也只能调用 SceneTree.quit 一次。"
	)


func test_continue_accepts_only_current_matching_bookmark_contract() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.mode_config_path = _CLASSIC_MODE_CONFIG.resource_path
	bookmark.ruleset_id = _CLASSIC_MODE_CONFIG.ruleset_id
	bookmark.ruleset_version = _CLASSIC_MODE_CONFIG.ruleset_version
	bookmark.ruleset_fingerprint = determinism.calculate_ruleset_fingerprint(
		_CLASSIC_MODE_CONFIG
	)
	bookmark.target_tile_value = _CLASSIC_MODE_CONFIG.target_tile_value

	assert_true(
		MainMenu._is_bookmark_valid_for_resume(
			bookmark,
			_CLASSIC_MODE_CONFIG,
			determinism
		),
		"规则集与目标契约匹配的书签应允许一键继续。"
	)
	bookmark.target_tile_value += 1
	assert_false(
		MainMenu._is_bookmark_valid_for_resume(
			bookmark,
			_CLASSIC_MODE_CONFIG,
			determinism
		),
		"目标契约漂移的书签不得被一键继续。"
	)


func test_resume_bookmark_sets_launch_state_and_routes_to_game() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var app_config: AppConfigModel = AppConfigModel.new()
	var router: _RouteSpy = _RouteSpy.new()
	await architecture.register_model(AppConfigModel, app_config)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var menu_node: Node = _MAIN_MENU_SCENE.instantiate()
	assert_true(menu_node is MainMenu, "主菜单场景应实例化为 MainMenu。")
	if menu_node is MainMenu:
		var menu: MainMenu = menu_node
		context.add_child(menu)
		await get_tree().process_frame
		var bookmark: BookmarkData = BookmarkData.new()
		bookmark.bookmark_id = GFUuid.generate_v7()
		app_config.current_replay_data.set_value(ReplayData.new())
		menu._resume_bookmark(bookmark)
		var selected_value: Variant = app_config.selected_bookmark_data.get_value()
		assert_true(
			selected_value is BookmarkData,
			"继续游戏必须写入 BookmarkData 启动状态。"
		)
		if selected_value is BookmarkData:
			var selected_bookmark: BookmarkData = selected_value
			assert_same(
				selected_bookmark,
				bookmark,
				"继续游戏必须把最近有效书签写入启动状态。"
			)
		var replay_cleared: bool = app_config.current_replay_data.get_value() == null
		assert_true(
			replay_cleared,
			"继续书签前必须清除回放启动状态。"
		)
		assert_true(
			router.last_scene_path == _GAME_SCENE_PATH,
			"继续游戏应路由到游戏场景。"
		)
	architecture.dispose()


func test_main_menu_primes_full_scene_targets_from_navigation_intent() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var router: _RouteSpy = _RouteSpy.new()
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var menu_node: Node = _MAIN_MENU_SCENE.instantiate()
	assert_true(menu_node is MainMenu, "主菜单场景应实例化为 MainMenu。")
	if menu_node is MainMenu:
		var menu: MainMenu = menu_node
		context.add_child(menu)
		await get_tree().process_frame
		var load_button: Button = menu.find_child(
			"LoadBookmarkButton",
			true,
			false
		) as Button
		var settings_button: Button = menu.find_child(
			"SettingsButton",
			true,
			false
		) as Button
		assert_not_null(load_button)
		assert_not_null(settings_button)
		if is_instance_valid(load_button):
			load_button.grab_focus()
		if is_instance_valid(settings_button):
			settings_button.mouse_entered.emit()
		await get_tree().process_frame
		assert_has(
			router.primed_scene_paths,
			menu.bookmark_list_scene_path,
			"键盘/手柄焦点抵达完整场景入口时应交给 GF 预加载。"
		)
		assert_has(
			router.primed_scene_paths,
			menu.settings_scene_path,
			"鼠标意图抵达完整场景入口时应交给 GF 预加载。"
		)
	architecture.dispose()


func test_mode_selection_primes_gameplay_from_start_intent() -> void:
	var router: _RouteSpy = _RouteSpy.new()
	var preload_error: Error = ModeSelection._prime_scene_with_router(
		router,
		_GAME_SCENE_PATH
	)
	assert_true(preload_error == OK)
	assert_has(
		router.primed_scene_paths,
		_GAME_SCENE_PATH,
		"模式页开始意图应在正式切换前交给 GFSceneUtility 预加载玩法场景。"
	)


func test_mode_selection_includes_gameplay_in_neighbor_preload_plan() -> void:
	var plan: Dictionary = _SCENE_PRELOAD_MAP.get_preload_plan(
		_MODE_SELECTION_SCENE_PATH,
		1,
		false
	)
	var temporary_paths: PackedStringArray = (
		GFVariantData.get_option_packed_string_array(
			plan,
			"temporary_paths",
			PackedStringArray()
		)
	)
	assert_has(
		temporary_paths,
		_GAME_SCENE_PATH,
		"模式页停留期间应由 GF 邻接预载在后台温热玩法场景；开始意图仍可幂等提速。"
	)


func test_scene_change_completion_supersedes_only_unaccepted_request() -> void:
	var router: _SceneRequestProbe = _SceneRequestProbe.new()
	router.prepare()
	var first: GFAsyncCompletion = router.request_scene_change(
		_GAME_SCENE_PATH
	)
	var second: GFAsyncCompletion = router.request_scene_change(
		_MODE_SELECTION_SCENE_PATH
	)

	assert_true(first.is_cancelled(), "尚未交给 GF 的旧路由应被新意图取消。")
	assert_true(
		first.get_cancel_reason() == &"superseded",
		"旧路由必须保留 superseded 取消原因。"
	)
	assert_true(second.is_pending(), "替代请求应持有独立的一次性终态。")
	var snapshot: Dictionary = router.get_debug_snapshot()
	assert_true(
		GFVariantData.get_option_string(snapshot, "pending_scene_path")
			== _MODE_SELECTION_SCENE_PATH,
		"诊断快照必须只投影当前活动请求。"
	)
	router.dispose()
	assert_true(second.is_cancelled(), "系统释放必须取消仍未终结的替代请求。")


func test_scene_change_rejects_concurrency_after_gf_acceptance() -> void:
	var router: _SceneRequestProbe = _SceneRequestProbe.new()
	router.prepare()
	var active: GFAsyncCompletion = router.request_scene_change(
		_GAME_SCENE_PATH
	)
	router.mark_active_request_accepted()
	var rejected: GFAsyncCompletion = router.request_scene_change(
		_MODE_SELECTION_SCENE_PATH
	)

	assert_true(active.is_pending(), "GF 已接管的活动路由不得被并发意图伪取消。")
	assert_true(rejected.is_failed(), "GF 接管后的并发路由应以 typed busy 终态拒绝。")
	assert_true(
		GFVariantData.get_option_int(rejected.get_metadata(), "error")
			== ERR_BUSY,
		"busy 终态必须保留可机读错误码。"
	)
	router.dispose()
	assert_true(active.is_cancelled(), "系统释放仍必须终结 GF 已接管的活动路由。")


func test_scene_change_owner_and_late_signals_settle_once() -> void:
	var router: _SceneRequestProbe = _SceneRequestProbe.new()
	router.prepare()
	var request_owner_node: Node = Node.new()
	add_child_autoqfree(request_owner_node)
	var owner_completion: GFAsyncCompletion = router.request_scene_change(
		_GAME_SCENE_PATH,
		request_owner_node
	)
	request_owner_node.queue_free()
	await get_tree().process_frame
	assert_true(
		owner_completion.is_cancelled(),
		"请求 owner 在 GF 接管前退出场景树时必须取消路由。"
	)
	assert_true(
		owner_completion.get_cancel_reason() == &"owner_released",
		"owner 取消必须保留稳定原因。"
	)

	var completion_count: Array[int] = [0]
	var completion: GFAsyncCompletion = router.request_scene_change(
		_GAME_SCENE_PATH
	)
	var connect_error: int = completion.completed.connect(
		func(_settled: GFAsyncCompletion) -> void:
			completion_count[0] += 1
	)
	assert_true(connect_error == OK)
	router.mark_active_request_accepted()
	router.call(
		"_on_scene_switch_completed",
		_MODE_SELECTION_SCENE_PATH,
		""
	)
	await get_tree().process_frame
	assert_true(completion.is_pending(), "其他路径的全局 Signal 不得终结当前请求。")

	router.call("_on_scene_switch_completed", _GAME_SCENE_PATH, "")
	router.call("_on_scene_switch_completed", _GAME_SCENE_PATH, "")
	await get_tree().process_frame
	assert_true(completion.is_successful(), "匹配请求应以成功终态收敛。")
	assert_true(completion_count[0] == 1, "重复完成 Signal 只能提交一次终态。")
	router.call(
		"_on_scene_switch_failed",
		_GAME_SCENE_PATH,
		"",
		"late failure"
	)
	router.dispose()
	assert_true(completion_count[0] == 1, "晚到失败与 dispose 不得重写已提交终态。")


func test_empty_history_lists_focus_back_button() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.init()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)

	for list_scene: PackedScene in [_BOOKMARK_LIST_SCENE, _REPLAY_LIST_SCENE]:
		var list_node: Node = list_scene.instantiate()
		assert_true(list_node is BaseListMenu, "历史列表场景应继承 BaseListMenu。")
		if not list_node is BaseListMenu:
			list_node.free()
			continue
		var list_menu: BaseListMenu = list_node
		context.add_child(list_menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var back_button: Node = list_menu.find_child("BackButton", true, false)
		assert_true(back_button is Button, "空历史列表必须保留返回按钮。")
		if back_button is Button:
			var back_control: Button = back_button
			assert_true(
				back_control.has_focus(),
				"空历史列表应把键盘/手柄焦点交给返回按钮。"
			)
		var list_surface: Node = list_menu.find_child("ListSurface", true, false)
		assert_true(list_surface is PanelContainer, "空历史页仍应保留唯一说明表面。")
		if list_surface is PanelContainer:
			var empty_surface: PanelContainer = list_surface
			assert_lte(
				empty_surface.custom_minimum_size.y,
				260.0,
				"空历史页不得保留 540px 的伪列表空白表面。"
			)
		var preview: Node = list_menu.find_child("PreviewContainer", true, false)
		var detail: Node = list_menu.find_child("DetailInfoLabel", true, false)
		assert_true(
			preview is Control and not (preview as Control).visible,
			"空历史页不得显示没有内容的棋盘预览纸片。"
		)
		assert_true(
			detail is Control and not (detail as Control).visible,
			"空历史页说明应集中在唯一表面，不重复显示详情占位。"
		)
		assert_null(
			list_menu.find_child("DeleteConfirmationDialog", true, false),
			"历史列表不得再实例化绕过 GF Router 的原生确认 Window。"
		)
		assert_null(
			list_menu.find_child("DeleteErrorDialog", true, false),
			"历史列表错误提示也应统一进入 GF modal 路由。"
		)
		var confirmation: GFModalConfig = (
			GameUiRouterUtility.make_confirmation_modal_config(
				tr("DELETE_CONFIRM_TITLE"),
				"确认删除？",
				tr("DELETE_CONFIRM_ACTION"),
				tr("DELETE_CANCEL_ACTION")
			)
		)
		var actions: Array[GFModalAction] = confirmation.get_actions()
		assert_true(actions.size() == 2)
		assert_true(
			actions[0].result_status == GFModalResult.STATUS_CANCELLED
			and actions[0].grab_focus,
			"危险操作必须把默认焦点留给 GF modal 的取消动作。"
		)
		assert_true(
			actions[1].result_status == GFModalResult.STATUS_CONFIRMED,
			"删除动作必须返回唯一的 GFModalResult confirmed 终态。"
		)
		assert_gte(
			GameModalRoutePanel._MINIMUM_ACTION_WIDTH,
			112.0,
			"项目 modal 操作按钮宽度不得小于 112px。"
		)
		assert_gte(
			GameModalRoutePanel._MINIMUM_TOUCH_TARGET_SIZE,
			44.0,
			"项目 modal 操作按钮高度不得小于 44px。"
		)
		context.remove_child(list_menu)
		list_menu.free()
		await get_tree().process_frame
	architecture.dispose()


func test_replay_list_virtual_list_binder_bounds_focus_repairs_and_disposes() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.init()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)

	var list_node: Node = _REPLAY_LIST_SCENE.instantiate()
	assert_true(list_node is ReplayList, "回放列表场景应实例化为 ReplayList。")
	if not list_node is ReplayList:
		list_node.free()
		architecture.dispose()
		return
	var replay_list: ReplayList = list_node
	replay_list.set_anchors_preset(Control.PRESET_TOP_LEFT)
	replay_list.size = Vector2(1280.0, 720.0)
	context.add_child(replay_list)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		replay_list.items_container.get_parent() == replay_list._list_scroll,
		"GFVirtualListBinder 的 content root 必须是 ScrollContainer 的直接子节点。"
	)
	assert_false(
		replay_list.items_container is Container,
		"回放 content root 必须是 Binder 可写绝对位置的普通 Control。"
	)

	var replay_data_list: Array[Resource] = []
	for item_index: int in range(ReplayCatalogSaveData.MAX_REPLAY_COUNT):
		var replay: ReplayData = ReplayData.new()
		replay.replay_id = "virtual-replay-%03d" % item_index
		replay.final_score = item_index * 16
		replay_data_list.append(replay)

	await replay_list._clear_list_content()
	await replay_list._populate_virtual_list(
		replay_data_list,
		replay_list._get_repeater_template()
	)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var binder: GFVirtualListBinder = replay_list._virtual_list_binder
	assert_true(
		is_instance_valid(binder) and binder.is_bound(),
		"长回放列表必须由 owner-bound GFVirtualListBinder 持有。"
	)
	assert_true(
		replay_list._virtual_list_model.get_item_count()
		== ReplayCatalogSaveData.MAX_REPLAY_COUNT,
		"GFVirtualListModel 必须拥有完整的 128 项回放目录计数。"
	)
	assert_true(
		replay_list._virtual_focus_model.focused_index == 0,
		"长回放列表初次打开必须把虚拟焦点设为第一项。"
	)
	var initial_result: GFVirtualListSyncResult = binder.get_last_sync_result()
	assert_true(
		initial_result.is_successful(),
		"GFVirtualListBinder 首轮物化必须成功，实际状态：%s。"
		% String(initial_result.get_status())
	)
	var initial_snapshot: Dictionary = binder.get_debug_snapshot()
	var initial_active_count: int = GFVariantData.get_option_int(
		initial_snapshot,
		"active_count",
		0
	)
	assert_gt(initial_active_count, 0, "Binder 必须物化首屏回放项。")
	assert_lte(
		initial_active_count,
		BaseListMenu._VIRTUAL_LIST_MAX_MATERIALIZED_ITEMS,
		"128 项回放目录的活动节点不得超过显式 materialization 上限。"
	)
	assert_true(
		initial_active_count < ReplayCatalogSaveData.MAX_REPLAY_COUNT,
		"128 项回放目录不得一次性创建 128 个 UI 节点。"
	)
	assert_true(
		replay_list._get_list_item_controls().size() == initial_active_count,
		"项目看到的活动回放按钮必须与 Binder 活动节点数一致。"
	)
	for item_index: int in initial_result.get_materialized_indices():
		assert_true(
			replay_list._virtual_list_model.is_item_measured(item_index),
			"Binder 必须把活动行的真实高度写回 GFVirtualListModel。"
		)

	var projected_focus_index: int = 110
	replay_list._project_virtual_focus(projected_focus_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var projected_host: Control = binder.get_materialized_control(
		projected_focus_index
	)
	var projected_button: Control = replay_list._get_virtual_list_item_control(
		projected_host
	)
	assert_true(
		is_instance_valid(projected_button) and projected_button.has_focus(),
		"跨窗虚拟焦点必须自动滚动、物化并交接到真实回放按钮。"
	)
	assert_gt(
		replay_list._list_scroll.scroll_vertical,
		0,
		"跨窗焦点必须推动 Binder 所属的回放滚动容器。"
	)
	assert_lte(
		GFVariantData.get_option_int(
			binder.get_debug_snapshot(),
			"active_count",
			0
		),
		BaseListMenu._VIRTUAL_LIST_MAX_MATERIALIZED_ITEMS,
		"跨窗焦点投影后活动节点仍必须保持有界。"
	)

	if is_instance_valid(projected_button):
		var navigation_event: InputEventAction = InputEventAction.new()
		navigation_event.action = &"ui_down"
		navigation_event.pressed = true
		navigation_event.strength = 1.0
		replay_list._on_virtual_item_gui_input(
			navigation_event,
			projected_button
		)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(
			replay_list._virtual_focus_model.focused_index
			== projected_focus_index + 1,
			"键盘或手柄向下动作必须推进 Binder 共享的虚拟焦点索引。"
		)
		var next_host: Control = binder.get_materialized_control(
			projected_focus_index + 1
		)
		var next_button: Control = replay_list._get_virtual_list_item_control(
			next_host
		)
		assert_true(
			is_instance_valid(next_button) and next_button.has_focus(),
			"跨窗键盘导航后 Binder 必须把焦点交给下一真实按钮。"
		)

	replay_list.size = Vector2(720.0, 960.0)
	replay_list._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	var compact_focus_index: int = 64
	replay_list._project_virtual_focus(compact_focus_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		replay_list._page_scroll.visible,
		"紧凑页仍须保留页面级滚动以访问预览与操作区。"
	)
	assert_true(
		replay_list._list_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO,
		"紧凑回放页必须保留 Binder 所属的有界内部滚动。"
	)
	var compact_host: Control = binder.get_materialized_control(
		compact_focus_index
	)
	var compact_button: Control = replay_list._get_virtual_list_item_control(
		compact_host
	)
	assert_true(
		is_instance_valid(compact_button) and compact_button.has_focus(),
		"紧凑布局下跨窗焦点仍必须投影到真实回放按钮。"
	)

	var retained_data: Array[Resource] = []
	for item_index: int in range(1):
		retained_data.append(replay_data_list[item_index])
	var active_host_ids_before_refresh: Dictionary = {}
	var released_data_probe: WeakRef = null
	for active_index: int in binder.get_last_sync_result().get_materialized_indices():
		var active_host: Control = binder.get_materialized_control(active_index)
		if is_instance_valid(active_host):
			active_host_ids_before_refresh[active_host.get_instance_id()] = true
		if active_index > 0 and released_data_probe == null:
			released_data_probe = weakref(replay_data_list[active_index])
	assert_not_null(
		released_data_probe,
		"刷新前应至少物化一个将被淘汰的回放资源，用于验证池化解绑。"
	)
	await replay_list._populate_virtual_list(
		retained_data,
		replay_list._get_repeater_template(),
		ReplayCatalogSaveData.MAX_REPLAY_COUNT - 1
	)
	replay_data_list.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_same(
		replay_list._virtual_list_binder,
		binder,
		"目录刷新应复用同一个未 dispose 的 Binder 生命周期句柄。"
	)
	assert_true(
		replay_list._virtual_focus_model.focused_index
		== retained_data.size() - 1,
		"目录从 128 项缩短后虚拟焦点必须修复到最后一个合法索引。"
	)
	assert_true(
		replay_list._virtual_list_model.get_item_count() == retained_data.size(),
		"目录缩短后布局模型计数必须同步收敛。"
	)
	var reused_host_count: int = 0
	for active_index: int in binder.get_last_sync_result().get_materialized_indices():
		var active_host: Control = binder.get_materialized_control(active_index)
		if (
			is_instance_valid(active_host)
			and active_host_ids_before_refresh.has(active_host.get_instance_id())
		):
			reused_host_count += 1
	assert_gt(
		reused_host_count,
		0,
		"目录刷新必须通过 Binder invalidate 复用活动/池化行，而不是全量销毁重建。"
	)
	assert_gt(
		binder.get_last_sync_result().get_reused_count(),
		0,
		"GF 同步结果必须明确记录刷新期间复用的行。"
	)
	for active_index: int in binder.get_last_sync_result().get_materialized_indices():
		var rebound_host: Control = binder.get_materialized_control(active_index)
		var rebound_control: Control = replay_list._get_virtual_list_item_control(
			rebound_host
		)
		assert_true(
			rebound_control is BaseListMenuItem,
			"刷新后的活动行必须仍由 BaseListMenuItem 承载。"
		)
		if rebound_control is BaseListMenuItem:
			var rebound_item: BaseListMenuItem = rebound_control
			assert_same(
				rebound_item.get_data(),
				retained_data[active_index],
				"复用行必须绑定刷新后的 ReplayData，而不是继续持有旧资源。"
			)
	if released_data_probe != null:
		var released_data_is_gone: bool = released_data_probe.get_ref() == null
		assert_true(
			released_data_is_gone,
			"进入 Binder parentless pool 的回放行不得继续强持有已淘汰 ReplayData。"
		)
	assert_lte(
		GFVariantData.get_option_int(
			binder.get_debug_snapshot(),
			"active_count",
			0
		),
		retained_data.size(),
		"目录缩短后不得保留越界活动节点。"
	)

	replay_list._content_ready = false
	replay_list._virtual_population_terminal_pending = true
	replay_list._on_virtual_list_sync_completed(
		_VirtualSyncResultProbe.new(GFVirtualListSyncResult.STATUS_DEFERRED)
	)
	assert_false(
		replay_list.is_content_ready(),
		"GF deferred 仅表示已排队下一轮，不能提前宣告首窗内容就绪。"
	)
	replay_list._on_virtual_list_sync_completed(
		_VirtualSyncResultProbe.new(GFVirtualListSyncResult.STATUS_SYNCED)
	)
	assert_true(
		replay_list.is_content_ready(),
		"deferred 后首个明确成功同步必须完成列表内容屏障。"
	)

	replay_list._content_ready = false
	replay_list._virtual_population_terminal_pending = true
	replay_list._on_virtual_list_sync_completed(
		_VirtualSyncResultProbe.new(GFVirtualListSyncResult.STATUS_BIND_FAILED)
	)
	assert_push_error("GFVirtualListBinder 延迟同步失败")
	assert_false(
		replay_list.is_content_ready(),
		"deferred 后失败不得被当成已完成水合。"
	)
	assert_false(
		replay_list._virtual_population_terminal_pending,
		"明确失败必须关闭本轮等待，避免后续无关同步误完成旧屏障。"
	)

	binder.dispose()
	var disposed_snapshot: Dictionary = binder.get_debug_snapshot()
	assert_true(binder.is_disposed(), "显式 teardown 必须让 Binder 进入 disposed 终态。")
	assert_false(binder.is_bound(), "disposed Binder 不得继续报告有效绑定。")
	assert_true(
		GFVariantData.get_option_int(disposed_snapshot, "active_count", -1) == 0,
		"dispose 必须释放全部活动回放行。"
	)
	assert_true(
		GFVariantData.get_option_int(disposed_snapshot, "pooled_count", -1) == 0,
		"dispose 必须释放全部池化回放行。"
	)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		replay_list.items_container.get_child_count() == 0,
		"dispose 后 Binder-owned Control 必须从 content root 完全清除。"
	)

	context.remove_child(replay_list)
	replay_list.free()
	await get_tree().process_frame
	architecture.dispose()


func test_delete_failure_preserves_selection_and_skips_refresh() -> void:
	var menu: _DeleteProbeMenu = _DeleteProbeMenu.new()
	var selected: Resource = Resource.new()
	selected.resource_name = "selected"
	menu._selected_resource = selected
	menu._pending_delete_resource = selected
	menu.delete_result = ERR_CANT_CREATE
	await menu._on_delete_confirmed()
	assert_push_error(
		"删除操作失败",
		"删除持久化失败仍应进入诊断日志。"
	)
	assert_same(menu._selected_resource, selected, "删除失败后必须保留当前选择。")
	assert_true(menu.populate_count == 0, "删除失败后不得刷新并伪装成成功。")

	menu._pending_delete_resource = selected
	menu.delete_result = OK
	await menu._on_delete_confirmed()
	assert_null(menu._selected_resource, "删除成功后应清空旧选择。")
	assert_true(menu.populate_count == 1, "只有删除成功后才能刷新列表。")
	menu.free()


func test_delete_busy_guard_and_late_rollback_unlock_once() -> void:
	var menu: _DeleteProbeMenu = _DeleteProbeMenu.new()
	var selected: Resource = Resource.new()
	selected.resource_name = "retained"
	menu._selected_resource = selected
	menu._pending_delete_resource = selected
	menu._delete_operation_busy = true

	await menu._on_delete_confirmed()
	assert_true(menu.delete_call_count == 0, "在途删除期间的重复确认必须被忽略。")

	menu._delete_operation_busy = false
	menu._delete_outcome_unknown = true
	menu._pending_delete_transaction_id = 41
	menu._pending_delete_resource_identity = "retained"
	menu._delete_operation_token = 7
	await menu._on_section_reconciliation_settled({
		&"transaction_id": 40,
		&"status": "late_failure_rolled_back",
		&"candidate_persisted": false,
		&"memory_rolled_back": true,
	})
	assert_true(menu._delete_outcome_unknown, "其他事务的对账证据不得解锁当前删除。")
	assert_true(menu.populate_count == 0, "其他事务不得触发列表刷新。")

	await menu._on_section_reconciliation_settled({
		&"transaction_id": 41,
		&"status": "late_failure_rolled_back",
		&"candidate_persisted": false,
		&"memory_rolled_back": true,
	})
	assert_false(menu._delete_outcome_unknown, "目标事务回滚收敛后必须解除页面锁定。")
	assert_false(menu._delete_operation_busy, "对账刷新结束后必须解除忙碌态。")
	assert_same(menu._selected_resource, selected, "晚到回滚必须保留原选择。")
	assert_true(menu.populate_count == 1, "目标事务收敛后列表只能刷新一次。")
	menu.free()


# --- 内部类 ---

class _VirtualSyncResultProbe extends GFVirtualListSyncResult:
	var _probe_status: StringName = GFVirtualListSyncResult.STATUS_UNBOUND

	func _init(status: StringName) -> void:
		_probe_status = status

	func is_successful() -> bool:
		return _probe_status in [
			GFVirtualListSyncResult.STATUS_SYNCED,
			GFVirtualListSyncResult.STATUS_UNCHANGED,
			GFVirtualListSyncResult.STATUS_TRUNCATED,
		]

	func get_status() -> StringName:
		return _probe_status


class _SceneRequestProbe extends SceneRouterSystem:
	func prepare() -> void:
		_scene_utility = GFSceneUtility.new()
		_clock_utility = GameClockUtility.new()

	## @param _path: 待预热的场景资源路径；探针不执行真实预热。
	func prime_scene(_path: String) -> Error:
		return OK

	func _run_scene_change(_request_id: int) -> void:
		pass

	func _complete_scene_change(
		request_id: int,
		success: bool,
		error: Error,
		error_message: String
	) -> void:
		var request: Variant = call("_get_scene_request", request_id)
		if request == null:
			return
		if success:
			var _success_settled: Variant = call(
				"_finish_scene_request_success",
				request
			)
			return
		var _failure_settled: Variant = call(
			"_finish_scene_request_failure",
			request,
			&"scene_switch_failed",
			error,
			error_message
		)

	func mark_active_request_accepted() -> void:
		var request_value: Variant = get("_active_scene_request")
		if request_value is RefCounted:
			var request: RefCounted = request_value
			request.set("accepted_by_scene_utility", true)


class _QuitProbe extends SceneRouterSystem:
	var quit_probe: Dictionary = {&"count": 0}

	func get_required_utilities() -> Array[Script]:
		return []

	func ready() -> void:
		pass

	func _quit_scene_tree(_tree: SceneTree) -> void:
		quit_probe[&"count"] = GFVariantData.get_option_int(
			quit_probe,
			&"count"
		) + 1


class _RouteSpy extends SceneRouterSystem:
	var last_scene_path: String = ""
	var primed_scene_paths: Array[String] = []

	func get_required_utilities() -> Array[Script]:
		return []

	func ready() -> void:
		pass

	## 记录最后一次场景导航目标。
	## @param path: 要导航到的 Godot 资源路径。
	func goto_scene(path: String) -> void:
		last_scene_path = path

	## @param path: 测试记录的待预加载场景路径。
	func prime_scene(path: String) -> Error:
		primed_scene_paths.append(path)
		return OK


class _DeleteProbeMenu extends BaseListMenu:
	var delete_result: Error = OK
	var populate_count: int = 0
	var delete_call_count: int = 0
	var transaction_id: int = 1

	func _ready() -> void:
		pass

	func _get_data_identity(data: Resource) -> String:
		return data.resource_name if data != null else ""

	func _is_current_delete_operation(token: int) -> bool:
		return token == _delete_operation_token

	func _do_delete_logic(_data: Resource) -> GameSaveSectionOperation:
		delete_call_count += 1
		var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
		var section_ids: PackedStringArray = PackedStringArray([&"test"])
		var configured: bool = operation.configure_for_utility(
			transaction_id,
			&"test_profile",
			section_ids
		)
		var result: GameSaveSectionResult = GameSaveSectionResult.new()
		var result_configured: bool = result.configure_for_utility(
			transaction_id,
			&"test_profile",
			section_ids,
			(
				GameSaveSectionResult.STATUS_PERSISTED
				if delete_result == OK
				else GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK
			),
			delete_result,
			true,
			delete_result != OK
		)
		transaction_id += 1
		if configured and result_configured:
			var _completed: bool = operation.complete_for_utility(result)
		return operation

	func _populate_list() -> void:
		populate_count += 1
