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
