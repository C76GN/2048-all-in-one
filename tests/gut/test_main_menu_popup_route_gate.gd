## 验证主菜单四个同层弹层共享单一在途门闩与确定焦点终态。
extends GutTest


func test_popup_route_gate_disables_every_menu_action_and_restores_prior_states() -> void:
	var host: Control = Control.new()
	add_child_autoqfree(host)
	var menu: MainMenu = _make_test_menu(host)
	menu._continue_game_button.disabled = true

	assert_true(menu._begin_popup_route_open())
	assert_true(menu._popup_route_open_pending)
	for button: BaseButton in menu._get_menu_button_sequence():
		assert_true(button.disabled, "%s 应在任一弹层路由在途时禁用。" % button.name)
	assert_false(
		menu._begin_popup_route_open(),
		"第二个同层弹层请求必须被共享门闩拒绝。"
	)

	menu._finish_popup_route_open(menu._tile_catalog_button, true)
	assert_false(menu._popup_route_open_pending)
	for button: BaseButton in menu._get_menu_button_sequence():
		if button == menu._continue_game_button:
			assert_true(button.disabled, "原本不可用的继续游戏按钮不得被错误启用。")
		else:
			assert_false(button.disabled, "%s 应恢复原始可用状态。" % button.name)
	menu.free()


func test_popup_route_gate_preserves_popup_focus_and_restores_origin_on_failure() -> void:
	var host: Control = Control.new()
	add_child_autoqfree(host)
	var menu: MainMenu = _make_test_menu(host)
	var popup_button: Button = _add_button(host, &"PopupInitialFocus")
	var origin: Button = menu._player_profile_button

	origin.grab_focus()
	await get_tree().process_frame
	assert_true(origin.has_focus())
	assert_true(menu._begin_popup_route_open())
	assert_true(
		origin.has_focus(),
		"禁用在途按钮时应保留当前焦点，供 GF 记录弹层关闭后的恢复目标。"
	)
	popup_button.grab_focus()
	await get_tree().process_frame
	assert_true(popup_button.has_focus())
	menu._finish_popup_route_open(origin, true)
	await get_tree().process_frame
	assert_true(
		popup_button.has_focus(),
		"成功打开弹层后不得把焦点从弹层终态抢回主菜单。"
	)

	assert_true(menu._begin_popup_route_open())
	menu._finish_popup_route_open(origin, false)
	await get_tree().process_frame
	assert_true(origin.has_focus(), "路由失败后应唯一恢复到发起按钮。")
	menu.free()


func test_popup_intent_preload_release_keeps_cache_under_bounded_lru() -> void:
	var menu: MainMenu = MainMenu.new()
	var asset_utility: _PreloadReleaseSpyAssetUtility = _PreloadReleaseSpyAssetUtility.new()
	menu._popup_intent_asset_utility = asset_utility

	menu._release_popup_intent_preload()

	assert_true(asset_utility.unloaded_group_id == &"main_menu_popup_intent")
	assert_false(
		asset_utility.remove_unreferenced_cache,
		"GF #108 修复前，主菜单只能释放分组 pin，不能 eager 清除共享缓存。"
	)
	assert_null(menu._popup_intent_asset_utility)
	asset_utility.dispose()
	menu.free()


func test_popup_intent_preload_release_rolls_back_late_session_before_group_release() -> void:
	var menu: MainMenu = MainMenu.new()
	var asset_utility: _DeferredPreloadAssetUtility = _DeferredPreloadAssetUtility.new()
	var plan: GFAssetPreloadPlan = GFAssetPreloadPlan.new().configure(
		&"main_menu_popup_intent",
		[
			"res://features/tile_catalog/scenes/ui/tile_catalog_dialog.tscn",
		],
		{
			"plan_id": &"main_menu_popup_intent.preload",
			"pin_cache": true,
		}
	)
	var session: GFAssetLoadSession = asset_utility.start_preload_session(
		plan,
		{"auto_commit": true}
	)
	assert_true(session.get_state() == GFAssetLoadSession.State.LOADING)
	menu._popup_intent_asset_utility = asset_utility
	menu._popup_intent_preload_session = session

	menu._release_popup_intent_preload()

	assert_true(session.get_state() == GFAssetLoadSession.State.ROLLBACK_PENDING)
	asset_utility.settle_pending_success()
	assert_true(session.get_state() == GFAssetLoadSession.State.ROLLED_BACK)
	assert_true(
		asset_utility.get_group_paths(&"main_menu_popup_intent").is_empty(),
		"离页后的迟到物理加载不得重新提交主菜单目标分组。"
	)
	assert_true(asset_utility.get_active_preload_session_count() == 0)
	assert_false(asset_utility.last_remove_unreferenced_cache)
	asset_utility.dispose()
	menu.free()


# --- 私有/辅助方法 ---

func _make_test_menu(host: Control) -> MainMenu:
	var menu: MainMenu = MainMenu.new()
	menu._start_game_button = _add_button(host, &"StartGameButton")
	menu._continue_game_button = _add_button(host, &"ContinueGameButton")
	menu._load_bookmark_button = _add_button(host, &"LoadBookmarkButton")
	menu._replays_button = _add_button(host, &"ReplaysButton")
	menu._tile_catalog_button = _add_button(host, &"TileCatalogButton")
	menu._tile_lab_button = _add_button(host, &"TileLabButton")
	menu._player_profile_button = _add_button(host, &"PlayerProfileButton")
	menu._achievements_button = _add_button(host, &"AchievementsButton")
	menu._settings_button = _add_button(host, &"SettingsButton")
	menu._quit_button = _add_button(host, &"QuitButton")
	return menu


func _add_button(host: Control, button_name: StringName) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.focus_mode = Control.FOCUS_ALL
	host.add_child(button)
	return button


# --- 内部类 ---

class _PreloadReleaseSpyAssetUtility extends GFAssetUtility:
	var unloaded_group_id: StringName = &""
	var remove_unreferenced_cache: bool = true

	## 记录主菜单释放的资源组与缓存清理策略。
	## @param group_id: 要释放 pin 的稳定资源组标识。
	## @param remove_unreferenced_cache_value: 释放分组后是否立即清理无引用共享缓存。
	func unload_group(
		group_id: StringName,
		remove_unreferenced_cache_value: bool = false
	) -> void:
		unloaded_group_id = group_id
		remove_unreferenced_cache = remove_unreferenced_cache_value


class _DeferredPreloadAssetUtility extends GFAssetUtility:
	var pending_completion: Callable = Callable()
	var pending_group_id: StringName = &""
	var pending_entries: Array = []
	var last_remove_unreferenced_cache: bool = true

	## 截留异步预载请求，供测试显式触发迟到成功终态。
	## @param group_id: 预载资源所属的稳定分组标识。
	## @param entries: 本次预载的资源条目快照。
	## @param on_completed: 预载进入唯一终态时调用的完成回调。
	## @param _options: 本测试替身不消费的预载选项。
	func preload_group_async(
		group_id: StringName,
		entries: Array,
		on_completed: Callable = Callable(),
		_options: Dictionary = {}
	) -> void:
		pending_group_id = group_id
		pending_entries = entries.duplicate(true)
		pending_completion = on_completed

	## 释放预载分组并记录是否要清理无引用共享缓存。
	## @param group_id: 要释放 pin 的稳定资源组标识。
	## @param remove_unreferenced_cache_value: 释放分组后是否立即清理无引用共享缓存。
	func unload_group(
		group_id: StringName,
		remove_unreferenced_cache_value: bool = false
	) -> void:
		if group_id == &"main_menu_popup_intent":
			last_remove_unreferenced_cache = remove_unreferenced_cache_value
		super.unload_group(group_id, remove_unreferenced_cache_value)

	func settle_pending_success() -> void:
		if not pending_completion.is_valid():
			return
		var loaded_paths: PackedStringArray = PackedStringArray()
		for entry_value: Variant in pending_entries:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var path: String = GFVariantData.get_option_string(entry, "path")
			if path.is_empty():
				continue
			register_group_path(pending_group_id, path, false)
			var _appended: bool = loaded_paths.append(path)
		var completion: Callable = pending_completion
		pending_completion = Callable()
		completion.call({
			"ok": true,
			"group_id": pending_group_id,
			"paths": loaded_paths,
			"failed_paths": PackedStringArray(),
			"total": pending_entries.size(),
			"completed": pending_entries.size(),
		})
