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


func test_mode_selection_defers_gameplay_preload_until_start_intent() -> void:
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
	assert_does_not_have(
		temporary_paths,
		_GAME_SCENE_PATH,
		"模式场景刚切入时不应同帧预载 gameplay；玩法场景由开始意图触发。"
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


func test_replay_list_virtualizes_large_catalog_and_repairs_focus() -> void:
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

	assert_true(
		replay_list._virtual_list_model.get_item_count()
		== ReplayCatalogSaveData.MAX_REPLAY_COUNT,
		"GFVirtualListModel 必须拥有完整回放数据计数。"
	)
	assert_true(
		replay_list._virtual_focus_model.focused_index == 0,
		"长回放列表初次打开必须把逻辑焦点投影到第一项。"
	)
	var initial_items: Array[Control] = replay_list._get_list_item_controls()
	var viewport_capacity: int = ceili(
		replay_list._list_scroll.size.y
		/ replay_list._virtual_item_extent
	)
	var materialized_limit: int = (
		viewport_capacity
		+ BaseListMenu._VIRTUAL_LIST_OVERSCAN_ITEMS * 2
		+ 1
	)
	assert_gt(initial_items.size(), 0, "虚拟回放列表必须物化首屏记录。")
	assert_lte(
		initial_items.size(),
		materialized_limit,
		"回放节点数量必须由视口和 overscan 决定，不得随 128 条数据线性增长。"
	)
	assert_true(initial_items[0].has_focus(), "首个物化回放项必须获得真实 UI 焦点。")
	for item_control: Control in initial_items:
		var measured_index: int = replay_list._get_virtual_item_index(
			item_control
		)
		assert_true(
			replay_list._virtual_list_model.is_item_measured(measured_index),
			"物化后的回放项必须把真实行高写回 GFVirtualListModel。"
		)

	var target_scroll_index: int = 96
	replay_list._list_scroll.scroll_vertical = roundi(
		replay_list._virtual_list_model.get_item_offset(target_scroll_index)
	)
	replay_list._on_virtual_scroll_changed(
		float(replay_list._list_scroll.scroll_vertical)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var scrolled_items: Array[Control] = replay_list._get_list_item_controls()
	assert_lte(
		scrolled_items.size(),
		materialized_limit,
		"滚动后物化回放节点仍必须保持有界。"
	)
	var first_scrolled_index: int = replay_list._get_virtual_item_index(
		scrolled_items[0]
	)
	assert_gt(
		first_scrolled_index,
		0,
		"滚动到后段时可见窗口必须离开首条数据。"
	)
	var scroll_before_height_change: int = replay_list._list_scroll.scroll_vertical
	var anchor_item: Control = null
	var anchor_index: int = GFVirtualListFocusModel.NO_FOCUS
	var anchor_previous_extent: float = 0.0
	for item_control: Control in scrolled_items:
		var candidate_index: int = replay_list._get_virtual_item_index(
			item_control
		)
		var candidate_extent: float = (
			replay_list._virtual_list_model.get_item_extent(candidate_index)
		)
		var candidate_bottom: float = (
			replay_list._virtual_list_model.get_item_offset(candidate_index)
			+ candidate_extent
		)
		if candidate_bottom <= float(scroll_before_height_change) + 0.5:
			anchor_item = item_control
			anchor_index = candidate_index
			anchor_previous_extent = candidate_extent
			break
	assert_true(
		is_instance_valid(anchor_item),
		"overscan 窗口应包含一个位于视口锚点之前的可测量回放项。"
	)
	if is_instance_valid(anchor_item):
		anchor_item.custom_minimum_size.y = maxf(
			anchor_item.get_combined_minimum_size().y + 48.0,
			anchor_item.size.y + 48.0
		)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var anchor_next_extent: float = (
			replay_list._virtual_list_model.get_item_extent(anchor_index)
		)
		assert_gt(
			anchor_next_extent,
			anchor_previous_extent,
			"中文换行或字体缩放改变行高后必须刷新 GF 实测尺寸。"
		)
		assert_almost_eq(
			float(replay_list._list_scroll.scroll_vertical),
			float(scroll_before_height_change)
			+ anchor_next_extent
			- anchor_previous_extent,
			2.0,
			"锚点之前的行高变化必须同步修正滚动偏移，避免内容跳动。"
		)

	var projected_focus_index: int = 110
	var _focus_changed: bool = (
		replay_list._virtual_focus_model.set_focused_index(
			projected_focus_index
		)
	)
	replay_list._project_virtual_focus(projected_focus_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var projected_focus_found: bool = false
	var projected_focus_control: Control = null
	for item_control: Control in replay_list._get_list_item_controls():
		if (
			replay_list._get_virtual_item_index(item_control)
			== projected_focus_index
		):
			projected_focus_found = item_control.has_focus()
			projected_focus_control = item_control
			break
	assert_true(
		projected_focus_found,
		"GFVirtualListFocusModel 的逻辑索引必须滚动并投影到真实按钮焦点。"
	)
	if is_instance_valid(projected_focus_control):
		var navigation_event: InputEventAction = InputEventAction.new()
		navigation_event.action = &"ui_down"
		navigation_event.pressed = true
		navigation_event.strength = 1.0
		replay_list._on_virtual_item_gui_input(
			navigation_event,
			projected_focus_control
		)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(
			replay_list._virtual_focus_model.focused_index
			== projected_focus_index + 1,
			"键盘或手柄向下动作必须推进虚拟焦点索引。"
		)
		var next_focus_found: bool = false
		for item_control: Control in replay_list._get_list_item_controls():
			if (
				replay_list._get_virtual_item_index(item_control)
				== projected_focus_index + 1
			):
				next_focus_found = item_control.has_focus()
				break
		assert_true(
			next_focus_found,
			"虚拟焦点推进后必须落到新物化的真实按钮。"
		)

	replay_list.size = Vector2(720.0, 960.0)
	replay_list._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	var compact_focus_index: int = 64
	var _compact_focus_changed: bool = (
		replay_list._virtual_focus_model.set_focused_index(
			compact_focus_index
		)
	)
	replay_list._project_virtual_focus(compact_focus_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		replay_list._page_scroll.visible,
		"紧凑布局必须由页面级滚动容器承载虚拟列表。"
	)
	assert_gt(
		replay_list._page_scroll.scroll_vertical,
		0,
		"紧凑布局的焦点投影必须滚动页面以显示目标记录。"
	)
	var compact_materialized_limit: int = (
		ceili(
			replay_list._page_scroll.size.y
			/ replay_list._virtual_item_extent
		)
		+ BaseListMenu._VIRTUAL_LIST_OVERSCAN_ITEMS * 2
		+ 1
	)
	assert_lte(
		replay_list._get_list_item_controls().size(),
		compact_materialized_limit,
		"紧凑页面滚动下的回放节点数量也必须保持有界。"
	)
	var compact_focus_found: bool = false
	for item_control: Control in replay_list._get_list_item_controls():
		if (
			replay_list._get_virtual_item_index(item_control)
			== compact_focus_index
		):
			compact_focus_found = item_control.has_focus()
			break
	assert_true(
		compact_focus_found,
		"紧凑布局必须把虚拟焦点投影到目标回放按钮。"
	)

	var retained_data: Array[Resource] = []
	for item_index: int in range(12):
		retained_data.append(replay_data_list[item_index])
	var _last_focus_changed: bool = (
			replay_list._virtual_focus_model.set_focused_index(
			ReplayCatalogSaveData.MAX_REPLAY_COUNT - 1
			)
	)
	await replay_list._clear_list_content()
	await replay_list._populate_virtual_list(
		retained_data,
		replay_list._get_repeater_template(),
		ReplayCatalogSaveData.MAX_REPLAY_COUNT - 1
	)
	assert_true(
		replay_list._virtual_focus_model.focused_index
		== retained_data.size() - 1,
		"数据缩短后虚拟焦点必须修复到最后一个合法索引。"
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

class _SceneRequestProbe extends SceneRouterSystem:
	func prepare() -> void:
		_scene_utility = GFSceneUtility.new()

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
