extends SceneTree


const _OUTPUT_DIRECTORY: String = "res://build/ui_vfx_matrix"
const _LOGICAL_DESIGN_SIZE: Vector2i = Vector2i(720, 720)
const _GAMEPLAY_MOTION_GUARD_MARGIN: float = 50.0
const _RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1906, 943),
	Vector2i(850, 838),
	Vector2i(960, 540),
	Vector2i(720, 960),
]
const _PLAYER_FLOW_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(973, 781),
	Vector2i(960, 540),
	Vector2i(720, 960),
]

var _screenshot_utility: GFScreenshotUtility = null
var _capture_count: int = 0
var _validation_errors: PackedStringArray = PackedStringArray()
var _geometry_records: Array[Dictionary] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[UiVfxMatrix] Capture requires rendering display mode.")
		_finish(64)
		return
	_prepare_output_directory()
	_set_resolution(_RESOLUTIONS[0])
	var boot_scene: PackedScene = load("res://app/scenes/boot.tscn")
	var boot_preview: Node = boot_scene.instantiate()
	if boot_preview is Boot:
		var preview: Boot = boot_preview
		preview.auto_start_runtime = false
	root.add_child(boot_preview)
	await _settle_frames(4)
	_screenshot_utility = _resolve_screenshot_utility()
	await _capture_page_matrix(boot_preview, &"boot")
	boot_preview.queue_free()
	await _settle_frames(2)

	root.add_child(boot_scene.instantiate())
	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[UiVfxMatrix] MainMenu timeout.")
		_finish(1)
		return
	await _settle_frames(24)
	if not is_instance_valid(_screenshot_utility):
		push_error("[UiVfxMatrix] GFScreenshotUtility unavailable.")
		_finish(2)
		return

	await _capture_page_matrix(main_menu, &"main_menu")
	var mode_selection: Node = await _open_route(
		main_menu,
		&"StartGameButton",
		&"ModeSelection"
	)
	if not is_instance_valid(mode_selection):
		_finish(3)
		return
	await _capture_page_matrix(mode_selection, &"mode_selection")
	if not await _capture_mode_selection_second_page(mode_selection):
		_finish(24)
		return

	if not await _capture_board_editor_player_flow(mode_selection):
		_finish(20)
		return
	var game_play: Node = await _open_route(
		mode_selection,
		&"StartGameButton",
		&"GamePlay"
	)
	if not is_instance_valid(game_play):
		_finish(21)
		return
	if not await _wait_for_gameplay_ready(game_play):
		_finish(22)
		return
	if not await _capture_gameplay_player_flow(game_play):
		_finish(23)
		return

	main_menu = await _return_gameplay_to_main_menu(game_play)
	if not is_instance_valid(main_menu):
		_finish(4)
		return
	var settings_menu: Node = await _open_route(
		main_menu,
		&"SettingsButton",
		&"SettingsMenu"
	)
	if not is_instance_valid(settings_menu):
		_finish(5)
		return
	await _capture_page_matrix(settings_menu, &"settings")
	if not await _capture_settings_section_states(settings_menu):
		_finish(25)
		return

	main_menu = await _open_route(settings_menu, &"BackButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_finish(6)
		return
	var bookmark_list: Node = await _open_route(
		main_menu,
		&"LoadBookmarkButton",
		&"BookmarkList"
	)
	if not is_instance_valid(bookmark_list):
		_finish(7)
		return
	await _capture_page_matrix(bookmark_list, &"bookmark_list")

	main_menu = await _open_route(bookmark_list, &"BackButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_finish(8)
		return
	var replay_list: Node = await _open_route(
		main_menu,
		&"ReplaysButton",
		&"ReplayList"
	)
	if not is_instance_valid(replay_list):
		_finish(9)
		return
	await _capture_page_matrix(replay_list, &"replay_list")

	main_menu = await _open_route(replay_list, &"BackButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_finish(10)
		return
	var tile_catalog: Node = await _open_overlay(
		main_menu,
		&"TileCatalogButton",
		&"TileCatalogDialog"
	)
	if not is_instance_valid(tile_catalog):
		_finish(11)
		return
	await _capture_page_matrix(tile_catalog, &"tile_catalog")
	if not await _close_overlay(tile_catalog):
		_finish(12)
		return

	var tile_lab: Node = await _open_overlay(
		main_menu,
		&"TileLabButton",
		&"TileLabDialog"
	)
	if not is_instance_valid(tile_lab):
		_finish(13)
		return
	await _capture_page_matrix(tile_lab, &"tile_lab")
	if not await _close_overlay(tile_lab):
		_finish(14)
		return

	var player_profile: Node = await _open_overlay(
		main_menu,
		&"PlayerProfileButton",
		&"PlayerProfileDialog"
	)
	if not is_instance_valid(player_profile):
		_finish(15)
		return
	await _capture_page_matrix(player_profile, &"player_profile")
	if not await _capture_player_profile_leaderboard_states(player_profile):
		_finish(26)
		return
	if not await _close_overlay(player_profile):
		_finish(16)
		return

	var achievements: Node = await _open_overlay(
		main_menu,
		&"AchievementsButton",
		&"AchievementListDialog"
	)
	if not is_instance_valid(achievements):
		_finish(17)
		return
	await _capture_page_matrix(achievements, &"achievements")
	if not await _close_overlay(achievements):
		_finish(18)
		return

	_set_resolution(_RESOLUTIONS[0])
	await _settle_frames(8)
	await _capture_celebration_variants()

	if not _validation_errors.is_empty():
		for message: String in _validation_errors:
			push_error("[UiVfxMatrix] %s" % message)
		_finish(19)
		return
	print("[UiVfxMatrix] completed captures=%d" % _capture_count)
	_finish(0)


func _prepare_output_directory() -> void:
	var directory_path: String = ProjectSettings.globalize_path(_OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return
	var directory: DirAccess = DirAccess.open(_OUTPUT_DIRECTORY)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		var extension: String = file_name.get_extension().to_lower()
		if extension != "png" and extension != "json":
			continue
		var _remove_error: Error = directory.remove(file_name)


func _capture_page_matrix(page: Node, page_id: StringName) -> void:
	for resolution: Vector2i in _RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(4)
		_queue_container_layout(page)
		await _settle_frames(6)
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		if page_id != &"boot":
			_validate_initial_focus(
				page,
				logical_resolution,
				"%s 初始焦点" % String(page_id)
			)
		_record_page_geometry(page, page_id, resolution, logical_resolution)
		_validate_page_structure(page, page_id, logical_resolution)
		if page_id != &"boot":
			_validate_visible_touch_targets(
				page,
				logical_resolution,
				String(page_id)
			)
		_save_viewport(
			"%s_%dx%d.png" % [String(page_id), resolution.x, resolution.y],
			resolution
		)
		if (
			page_id == &"mode_selection"
			and GameTaskPageLayoutUtility.classify_layout(
				Vector2(logical_resolution)
			) == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		):
			await _capture_mode_selection_scroll_end(page, resolution)
		await _capture_page_scroll_end_if_needed(
			page,
			page_id,
			resolution,
			logical_resolution
		)
	_set_resolution(_RESOLUTIONS[0])
	await _settle_frames(8)


func _capture_mode_selection_second_page(mode_selection: Node) -> bool:
	var next_node: Node = mode_selection.find_child(
		"NextPageButton",
		true,
		false
	)
	var previous_node: Node = mode_selection.find_child(
		"PrevPageButton",
		true,
		false
	)
	if not next_node is Button:
		_record_error("mode_selection 缺少第二页入口 NextPageButton。")
		return false
	if not previous_node is Button:
		_record_error("mode_selection 缺少返回第一页入口 PrevPageButton。")
		return false
	var next_button: Button = next_node
	var previous_button: Button = previous_node

	for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(5)
		_queue_container_layout(mode_selection)
		await _settle_frames(6)
		if not await _move_mode_selection_to_first_page(
			mode_selection,
			previous_button
		):
			return false
		if not next_button.is_visible_in_tree() or next_button.disabled:
			_record_error(
				"mode_selection @ %s 第二页入口不可操作。"
				% resolution
			)
			return false
		# 每次改变分辨率后都从第一页执行真实“下一页”操作。模式页会按
		# 当前尺寸重算每页容量；只复用上个尺寸的页状态会造成文件名与画面错位。
		next_button.grab_focus()
		next_button.pressed.emit()
		# 页切换会重新播放右侧详情的交错 reveal；等完整节拍结束后再截图，
		# 否则底部的种子与开始按钮仍处于低透明度中，看起来像被裁掉。
		await _settle_frames(36)
		var current_page: int = _get_mode_selection_page_index(
			mode_selection
		)
		if current_page != 1:
			_record_error(
				"mode_selection @ %s 执行下一页后实际页码为 %d。"
				% [resolution, current_page + 1]
			)
			return false
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		_validate_page_structure(
			mode_selection,
			&"mode_selection",
			logical_resolution
		)
		_record_page_geometry(
			mode_selection,
			&"mode_selection_page_2",
			resolution,
			logical_resolution
		)
		_save_viewport(
			"mode_selection_page_2_%dx%d.png"
			% [resolution.x, resolution.y],
			resolution
		)
		if (
			GameTaskPageLayoutUtility.classify_layout(
				Vector2(logical_resolution)
			) == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		):
			await _capture_named_scroll_end(
				mode_selection,
				&"ModeSelectionScroll",
				&"StartGameButton",
				&"mode_selection_page_2",
				resolution,
				logical_resolution
			)
		if not await _capture_mode_selection_last_page_if_needed(
			mode_selection,
			next_button,
			resolution
		):
			return false

	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(8)
	return await _move_mode_selection_to_first_page(
		mode_selection,
		previous_button
	)


func _move_mode_selection_to_first_page(
	mode_selection: Node,
	previous_button: Button
) -> bool:
	var total_pages: int = GFVariantData.to_int(
		mode_selection.get("_total_pages"),
		0
	)
	if total_pages < 2:
		_record_error("mode_selection 没有可供截图的第二页。")
		return false
	for _attempt: int in range(total_pages):
		var current_page: int = _get_mode_selection_page_index(
			mode_selection
		)
		if current_page == 0:
			return true
		if (
			not previous_button.is_visible_in_tree()
			or previous_button.disabled
		):
			_record_error("mode_selection 无法通过真实上一页操作归回第一页。")
			return false
		previous_button.grab_focus()
		previous_button.pressed.emit()
		await _settle_frames(8)
	_record_error("mode_selection 在有限分页操作后仍未归回第一页。")
	return false


func _get_mode_selection_page_index(mode_selection: Node) -> int:
	return GFVariantData.to_int(
		mode_selection.get("_current_page"),
		-1
	)


func _capture_mode_selection_last_page_if_needed(
	mode_selection: Node,
	next_button: Button,
	physical_resolution: Vector2i
) -> bool:
	var total_pages: int = GFVariantData.to_int(
		mode_selection.get("_total_pages"),
		0
	)
	var current_page: int = _get_mode_selection_page_index(mode_selection)
	while current_page >= 0 and current_page < total_pages - 1:
		if not next_button.is_visible_in_tree() or next_button.disabled:
			_record_error(
				"mode_selection @ %s 无法通过真实下一页操作到达末页。"
				% physical_resolution
			)
			return false
		next_button.grab_focus()
		next_button.pressed.emit()
		await _settle_frames(8)
		current_page = _get_mode_selection_page_index(mode_selection)
	if current_page != total_pages - 1:
		_record_error(
			"mode_selection @ %s 未到达末页：%d / %d。"
			% [physical_resolution, current_page + 1, total_pages]
		)
		return false
	if not _mode_selection_has_visible_ratio_card(mode_selection):
		_record_error(
			"mode_selection @ %s 末页未覆盖比例模式。"
			% physical_resolution
		)
		return false
	if current_page == 1:
		return true

	_queue_container_layout(mode_selection)
	await _settle_frames(6)
	var logical_resolution: Vector2i = Vector2i(
		root.get_visible_rect().size.round()
	)
	var capture_id: StringName = StringName(
		"mode_selection_page_%d" % (current_page + 1)
	)
	_validate_page_structure(
		mode_selection,
		&"mode_selection",
		logical_resolution
	)
	_record_page_geometry(
		mode_selection,
		capture_id,
		physical_resolution,
		logical_resolution
	)
	_save_viewport(
		"%s_%dx%d.png"
		% [
			String(capture_id),
			physical_resolution.x,
			physical_resolution.y,
		],
		physical_resolution
	)
	return true


func _mode_selection_has_visible_ratio_card(
	mode_selection: Node
) -> bool:
	for card_node: Node in mode_selection.find_children(
		"*",
		"ModeCard",
		true,
		false
	):
		if not card_node is ModeCard:
			continue
		var card: ModeCard = card_node
		if (
			card.is_visible_in_tree()
			and card.get_config_path().ends_with(
				"/ratio_mode_config.tres"
			)
		):
			return true
	return false


func _capture_settings_section_states(settings_menu: Node) -> bool:
	var sections: Array[Dictionary] = [
		{
			"id": &"settings_general",
			"button": &"GeneralTabButton",
			"target": &"TurnSubtitlesToggle",
		},
		{
			"id": &"settings_audio",
			"button": &"AudioTabButton",
			"target": &"SfxVolumeSlider",
		},
		{
			"id": &"settings_controls",
			"button": &"ControlsTabButton",
			"target": &"ResetBindingsButton",
		},
	]
	for section: Dictionary in sections:
		var capture_id: StringName = GFVariantData.get_option_string_name(
			section,
			"id",
			&""
		)
		var button_name: StringName = GFVariantData.get_option_string_name(
			section,
			"button",
			&""
		)
		var target_name: StringName = GFVariantData.get_option_string_name(
			section,
			"target",
			&""
		)
		if not await _activate_named_button(settings_menu, button_name):
			return false
		for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
			_set_resolution(resolution)
			await _settle_frames(5)
			_queue_container_layout(settings_menu)
			await _settle_frames(6)
			var logical_resolution: Vector2i = Vector2i(
				root.get_visible_rect().size.round()
			)
			_validate_page_structure(
				settings_menu,
				&"settings",
				logical_resolution
			)
			_validate_initial_focus(
				settings_menu,
				logical_resolution,
				"%s 焦点" % capture_id
			)
			_validate_visible_touch_targets(
				settings_menu,
				logical_resolution,
				String(capture_id)
			)
			_record_page_geometry(
				settings_menu,
				capture_id,
				resolution,
				logical_resolution
			)
			_save_viewport(
				"%s_%dx%d.png"
				% [String(capture_id), resolution.x, resolution.y],
				resolution
			)
			await _capture_named_scroll_end(
				settings_menu,
				&"SettingsSectionScroll",
				target_name,
				capture_id,
				resolution,
				logical_resolution,
				true
			)
			if capture_id == &"settings_controls":
				await _capture_named_scroll_end(
					settings_menu,
					&"InputBindingsScroll",
					&"InputBindingsContainer",
					&"settings_controls_bindings",
					resolution,
					logical_resolution,
					true
				)
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(7)
	return true


func _capture_player_profile_leaderboard_states(
	player_profile: Node
) -> bool:
	var tabs_node: Node = player_profile.find_child("Tabs", true, false)
	if not tabs_node is TabContainer:
		_record_error("player_profile 缺少排行榜 TabContainer。")
		return false
	var tabs: TabContainer = tabs_node
	if tabs.get_tab_count() < 2:
		_record_error("player_profile 缺少本地排行榜分页。")
		return false
	tabs.current_tab = 1
	await _settle_frames(6)
	for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(5)
		_queue_container_layout(player_profile)
		await _settle_frames(6)
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		_validate_overlay_root(
			player_profile,
			logical_resolution,
			"player_profile_leaderboard"
		)
		var leaderboard_node: Node = tabs.get_tab_control(1)
		if not leaderboard_node is Control:
			_record_error(
				"player_profile_leaderboard @ %s 缺少排行榜内容。"
				% logical_resolution
			)
		else:
			var leaderboard: Control = leaderboard_node
			if not leaderboard.is_visible_in_tree():
				_record_error(
					"player_profile_leaderboard @ %s 排行榜分页不可见。"
					% logical_resolution
				)
		_validate_leaderboard_filter_label(
			player_profile,
			logical_resolution
		)
		_validate_visible_touch_targets(
			player_profile,
			logical_resolution,
			"player_profile_leaderboard"
		)
		_record_page_geometry(
			player_profile,
			&"player_profile_leaderboard",
			resolution,
			logical_resolution
		)
		_save_viewport(
			"player_profile_leaderboard_%dx%d.png"
			% [resolution.x, resolution.y],
			resolution
		)
		await _capture_named_scroll_end(
			player_profile,
			&"LeaderboardScroll",
			&"LeaderboardList",
			&"player_profile_leaderboard",
			resolution,
			logical_resolution
		)
	tabs.current_tab = 0
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(7)
	return true


func _validate_leaderboard_filter_label(
	player_profile: Node,
	resolution: Vector2i
) -> void:
	var option_node: Node = player_profile.find_child(
		"LeaderboardGroupOption",
		true,
		false
	)
	if not option_node is OptionButton:
		_record_error(
			"player_profile_leaderboard @ %s 缺少榜单筛选。"
			% resolution
		)
		return
	var option: OptionButton = option_node
	if option.selected < 0 or option.selected >= option.item_count:
		_record_error(
			"player_profile_leaderboard @ %s 榜单筛选没有有效选项。"
			% resolution
		)
		return
	var label: String = option.get_item_text(option.selected)
	if (
		label.strip_edges().is_empty()
		or label.contains("MODE_")
		or label.contains("board_template.")
		or label.contains("@")
	):
		_record_error(
			"player_profile_leaderboard @ %s 暴露内部身份文本：%s。"
			% [resolution, label]
		)


func _capture_board_editor_player_flow(mode_selection: Node) -> bool:
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(8)
	var editor: Node = await _open_overlay(
		mode_selection,
		&"EditBoardButton",
		&"BoardEditorDialog"
	)
	if not is_instance_valid(editor):
		return false
	await _settle_frames(12)
	var initial_resolution: Vector2i = Vector2i(
		root.get_visible_rect().size.round()
	)
	_validate_initial_focus(
		editor,
		initial_resolution,
		"board_editor 初始焦点"
	)
	_validate_board_editor_cancel_translation(editor)

	for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(5)
		_queue_container_layout(editor)
		await _settle_frames(7)
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		var layout_controller: BoardEditorResponsiveLayoutController = (
			_get_board_editor_layout_controller(editor)
		)
		var is_sectioned: bool = (
			is_instance_valid(layout_controller)
			and layout_controller.get_layout_mode()
			!= BoardEditorResponsiveLayoutController.LayoutMode.DESKTOP
		)
		if not is_sectioned:
			_validate_board_editor_structure(
				editor,
				logical_resolution,
				&"desktop"
			)
			_record_page_geometry(
				editor,
				&"board_editor",
				resolution,
				logical_resolution
			)
			_save_viewport(
				"board_editor_%dx%d.png" % [resolution.x, resolution.y],
				resolution
			)
			continue

		if not await _activate_board_editor_section(
			editor,
			&"EditorSectionButton"
		):
			return false
		_validate_board_editor_structure(
			editor,
			logical_resolution,
			&"editor"
		)
		_record_page_geometry(
			editor,
			&"board_editor_editor",
			resolution,
			logical_resolution
		)
		_save_viewport(
			"board_editor_editor_%dx%d.png"
			% [resolution.x, resolution.y],
			resolution
		)
		if (
			layout_controller.get_layout_mode()
			== BoardEditorResponsiveLayoutController.LayoutMode.PORTRAIT
		):
			_capture_board_editor_portrait_end(
				editor,
				&"board_editor_editor",
				resolution,
				logical_resolution
			)

		if not await _activate_board_editor_section(
			editor,
			&"LibrarySectionButton"
		):
			return false
		_validate_board_editor_structure(
			editor,
			logical_resolution,
			&"library"
		)
		_record_page_geometry(
			editor,
			&"board_editor_library",
			resolution,
			logical_resolution
		)
		_save_viewport(
			"board_editor_library_%dx%d.png"
			% [resolution.x, resolution.y],
			resolution
		)
		if (
			layout_controller.get_layout_mode()
			== BoardEditorResponsiveLayoutController.LayoutMode.PORTRAIT
		):
			_capture_board_editor_portrait_end(
				editor,
				&"board_editor_library",
				resolution,
				logical_resolution
			)

	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(8)
	return await _close_overlay_with_button(editor, &"CancelButton")


func _capture_board_editor_portrait_end(
	editor: Node,
	capture_id: StringName,
	physical_resolution: Vector2i,
	logical_resolution: Vector2i
) -> void:
	# 竖屏编辑器以固定 Footer 保持最终操作常驻，并不制造第二个页面滚动。
	# 仍输出 scroll_end 状态，证明“使用此棋盘”在内容末端无需滚动即可到达。
	var apply_node: Node = editor.find_child("ApplyButton", true, false)
	if not apply_node is Control:
		_record_error(
			"%s @ %s 缺少最终 ApplyButton。"
			% [capture_id, logical_resolution]
		)
		return
	var apply_button: Control = apply_node
	_validate_control_rect(
		apply_button,
		logical_resolution,
		"%s 最终操作" % capture_id
	)
	_save_viewport(
		"%s_%dx%d_scroll_end.png"
		% [
			String(capture_id),
			physical_resolution.x,
			physical_resolution.y,
		],
		physical_resolution
	)


func _activate_board_editor_section(
	editor: Node,
	button_name: StringName
) -> bool:
	var button_node: Node = editor.find_child(String(button_name), true, false)
	if not button_node is Button:
		_record_error("board_editor 缺少分区按钮 %s。" % button_name)
		return false
	var button: Button = button_node
	if not button.is_visible_in_tree() or button.disabled:
		_record_error("board_editor 分区按钮 %s 不可操作。" % button_name)
		return false
	button.grab_focus()
	button.pressed.emit()
	await _settle_frames(5)
	return true


func _capture_gameplay_player_flow(game_play: Node) -> bool:
	await _capture_gameplay_matrix(game_play)
	if not await _capture_pause_menu_player_flow(game_play):
		return false
	if not await _capture_target_reached_player_flow():
		return false
	if not await _capture_game_over_player_flow():
		return false
	return true


func _capture_gameplay_matrix(game_play: Node) -> void:
	for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(6)
		_queue_container_layout(game_play)
		await _settle_frames(8)
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		_validate_gameplay_structure(game_play, logical_resolution)
		_record_page_geometry(
			game_play,
			&"gameplay",
			resolution,
			logical_resolution
		)
		_save_viewport(
			"gameplay_%dx%d.png" % [resolution.x, resolution.y],
			resolution
		)
		await _capture_gameplay_feedback_states(game_play, resolution)
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(8)


func _capture_gameplay_feedback_states(
	game_play: Node,
	resolution: Vector2i
) -> void:
	var hud_node: Node = game_play.find_child("HUD", true, false)
	var board_node: Node = game_play.find_child("BoardBackground", true, false)
	if not hud_node is Hud or not board_node is Control:
		_record_error("gameplay 反馈状态缺少 HUD 或 BoardBackground。")
		return
	var hud: Hud = hud_node
	var board: Control = board_node
	var summary: GameAccessibilitySummary = _make_feedback_preview_summary()
	hud.call(&"_show_accessibility_summary", summary)
	await _settle_frames(5)
	var subtitle_node: Node = game_play.find_child(
		"AccessibilitySubtitlePanel",
		true,
		false
	)
	if not subtitle_node is Control:
		_record_error("gameplay 缺少 AccessibilitySubtitlePanel。")
	else:
		var subtitle: Control = subtitle_node
		if subtitle.get_global_rect().intersects(
			board.get_global_rect().grow(_GAMEPLAY_MOTION_GUARD_MARGIN)
		):
			_record_error(
				"gameplay @ %s 回合字幕进入棋盘动态安全包络。" % resolution
			)
		_save_viewport(
			"gameplay_turn_subtitle_%dx%d.png" % [resolution.x, resolution.y],
			resolution
		)
	hud.call(&"_hide_accessibility_subtitle")
	await _settle_frames(3)

	hud.call(
		&"_set_notification_message",
		9001,
		"这个方向无法移动。",
		GFNotificationUtility.Level.WARNING
	)
	await _settle_frames(5)
	var notification_node: Node = game_play.find_child(
		"NotificationPanel",
		true,
		false
	)
	if not notification_node is Control:
		_record_error("gameplay 缺少 NotificationPanel。")
	else:
		var notification_control: Control = notification_node
		if notification_control.get_global_rect().intersects(
			board.get_global_rect().grow(_GAMEPLAY_MOTION_GUARD_MARGIN)
		):
			_record_error(
				"gameplay @ %s 无效移动提示进入棋盘动态安全包络。" % resolution
			)
		_save_viewport(
			"gameplay_invalid_move_%dx%d.png" % [resolution.x, resolution.y],
			resolution
		)
	hud.call(
		&"_set_notification_message",
		0,
		"",
		GFNotificationUtility.Level.INFO
	)
	await _settle_frames(3)


func _make_feedback_preview_summary() -> GameAccessibilitySummary:
	var summary: GameAccessibilitySummary = GameAccessibilitySummary.new()
	summary.sequence = 1
	summary.kind = GameAccessibilitySummary.KIND_TURN
	summary.board_checksum = "0".repeat(64)
	summary.canonical_payload = {
		&"schema_version": GameAccessibilitySummary.SCHEMA_VERSION,
		&"kind": GameAccessibilitySummary.KIND_TURN,
		&"direction": Vector2i.RIGHT,
	}
	summary.announcement_text = "向右移动，6 个方块位移，生成 1 个方块。"
	summary.subtitle_text = "向右移动：6 个方块位移，合并 0 次，生成 1 个，变化 0 个，得分 +0。"
	summary.board_text = "棋盘摘要预览。"
	return summary


func _capture_pause_menu_player_flow(game_play: Node) -> bool:
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(6)
	var pause_button_node: Node = game_play.find_child(
		"PauseButton",
		true,
		false
	)
	if not pause_button_node is Button:
		_record_error("gameplay 缺少真实暂停入口 PauseButton。")
		return false
	var pause_button: Button = pause_button_node
	if not pause_button.is_visible_in_tree() or pause_button.disabled:
		_record_error("gameplay 暂停入口不可操作。")
		return false
	pause_button.grab_focus()
	pause_button.pressed.emit()
	var pause_menu: Node = await _wait_for_node(&"PauseMenu", 600)
	if not is_instance_valid(pause_menu):
		_record_error("PauseMenu 真实玩家入口打开超时。")
		return false
	if not await _wait_for_pause_state(true, 3.0):
		_record_error("PauseMenu 已打开但对局未进入暂停状态。")
		return false
	await _settle_frames(6)
	_validate_initial_focus(
		pause_menu,
		Vector2i(root.get_visible_rect().size.round()),
		"pause_menu 初始焦点"
	)
	await _capture_gameplay_overlay_matrix(pause_menu, &"pause_menu")

	var continue_node: Node = pause_menu.find_child(
		"ContinueButton",
		true,
		false
	)
	if not continue_node is Button:
		_record_error("PauseMenu 缺少 ContinueButton。")
		return false
	var continue_button: Button = continue_node
	continue_button.grab_focus()
	continue_button.pressed.emit()
	if not await _wait_for_overlay_closed(pause_menu, 300):
		_record_error("PauseMenu 继续操作未关闭弹层。")
		return false
	if not await _wait_for_pause_state(false, 3.0):
		_record_error("PauseMenu 关闭后对局仍处于暂停状态。")
		return false
	return true


func _capture_routed_gameplay_overlay(
	route_id: StringName,
	target_name: StringName,
	capture_id: StringName
) -> bool:
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	var pause_utility: GamePauseUtility = _get_game_pause_utility()
	if not is_instance_valid(ui_router) or not is_instance_valid(pause_utility):
		_record_error("%s 缺少项目 UI 路由或暂停 Utility。" % capture_id)
		return false

	# 直接使用项目正式路由，避免伪造结算事件或写入任何进度/存档。
	# 验证工具由 invoke_godot_project_tool.ps1 放入隔离的 user://。
	var overlay: Node = ui_router.push_route(route_id)
	if not is_instance_valid(overlay) or overlay.name != target_name:
		_record_error("%s 项目路由打开失败。" % capture_id)
		return false
	await _settle_frames(5)
	if not pause_utility.pause():
		var _rolled_back: bool = ui_router.back(GFUIUtility.Layer.POPUP)
		_record_error("%s 无法建立安全的暂停截图状态。" % capture_id)
		return false
	await _settle_frames(5)
	_validate_initial_focus(
		overlay,
		Vector2i(root.get_visible_rect().size.round()),
		"%s 初始焦点" % capture_id
	)
	if capture_id == &"target_reached_menu":
		_validate_target_reached_overlay(overlay)
	await _capture_gameplay_overlay_matrix(overlay, capture_id)

	if not ui_router.back(GFUIUtility.Layer.POPUP):
		_record_error("%s 项目路由关闭失败。" % capture_id)
		return false
	await _settle_frames(3)
	if not pause_utility.resume():
		_record_error("%s 项目路由关闭后无法恢复对局。" % capture_id)
		return false
	await _settle_frames(4)
	return true


func _snapshot_status_model(status_model: GameStatusModel) -> Dictionary:
	return {
		&"score": status_model.score.get_value(),
		&"high_score": status_model.high_score.get_value(),
		&"highest_tile": status_model.highest_tile.get_value(),
		&"target_tile_value": status_model.target_tile_value.get_value(),
		&"target_reached": status_model.target_reached.get_value(),
		&"move_count": status_model.move_count.get_value(),
		&"ratio_resolutions": status_model.ratio_resolutions.get_value(),
		&"extra_stats": status_model.extra_stats.get_value(),
	}


func _restore_status_model(
	status_model: GameStatusModel,
	snapshot: Dictionary
) -> void:
	status_model.score.set_value(snapshot.get(&"score", 0))
	status_model.high_score.set_value(snapshot.get(&"high_score", 0))
	status_model.highest_tile.set_value(
		snapshot.get(&"highest_tile", 0)
	)
	status_model.target_tile_value.set_value(
		snapshot.get(&"target_tile_value", 0)
	)
	status_model.target_reached.set_value(
		snapshot.get(&"target_reached", false)
	)
	status_model.move_count.set_value(
		snapshot.get(&"move_count", 0)
	)
	status_model.ratio_resolutions.set_value(
		snapshot.get(&"ratio_resolutions", 0)
	)
	status_model.extra_stats.set_value(
		snapshot.get(&"extra_stats", {})
	)


func _make_no_moves_snapshot(grid_model: GridModel) -> Dictionary:
	var snapshot: Dictionary = grid_model.get_snapshot()
	var existing_tiles: Array = GFVariantData.get_option_array(
		snapshot,
		&"tiles"
	)
	if existing_tiles.is_empty() or not is_instance_valid(grid_model.topology):
		return {}
	var template_value: Variant = existing_tiles[0]
	if not template_value is Dictionary:
		return {}
	var template: Dictionary = template_value
	var fixture_tiles: Array[Dictionary] = []
	var index: int = 0
	for cell: Vector2i in grid_model.topology.get_active_cells():
		var tile: Dictionary = template.duplicate(true)
		tile[&"tile_id"] = GFUuid.generate_v7(
			1_788_000_000_000 + index
		)
		tile[&"value"] = 2 if (cell.x + cell.y) % 2 == 0 else 4
		tile[&"pos"] = cell
		fixture_tiles.append(tile)
		index += 1
	var fixture: Dictionary = snapshot.duplicate(true)
	fixture[&"tiles"] = fixture_tiles
	return fixture


func _is_no_moves_fixture(grid_model: GridModel) -> bool:
	if (
		not is_instance_valid(grid_model)
		or not is_instance_valid(grid_model.interaction_rule)
		or not grid_model.get_empty_cells().is_empty()
	):
		return false
	var rule: StandardGameOverRule = StandardGameOverRule.new()
	return rule.is_game_over(
		grid_model,
		grid_model.interaction_rule
	)


func _validate_target_reached_fixture(
	status_model: GameStatusModel,
	expected_target: int
) -> void:
	if (
		GFVariantData.to_int(
			status_model.target_tile_value.get_value(),
			0
		) != expected_target
		or GFVariantData.to_int(
			status_model.highest_tile.get_value(),
			0
		) != expected_target
		or not GFVariantData.to_bool(
			status_model.target_reached.get_value(),
			false
		)
	):
		_record_error("target_reached_menu 目标、最大方块或达成状态不一致。")


func _validate_target_reached_overlay(overlay: Node) -> void:
	var summary_node: Node = overlay.find_child(
		"SummaryLabel",
		true,
		false
	)
	if not summary_node is Label:
		_record_error("target_reached_menu 缺少 SummaryLabel。")
		return
	var summary: Label = summary_node
	var loading_text: String = tr("TARGET_REACHED_SUMMARY_LOADING")
	var unavailable_text: String = tr(
		"TARGET_REACHED_SUMMARY_UNAVAILABLE"
	)
	if (
		summary.text.strip_edges().is_empty()
		or summary.text == loading_text
		or summary.text == unavailable_text
	):
		_record_error("target_reached_menu 摘要尚未生成有效数据。")


func _validate_game_over_fixture(
	overlay: Node,
	grid_model: GridModel
) -> void:
	if not _is_no_moves_fixture(grid_model):
		_record_error("game_over_menu 截图时棋盘并非真实无路可走状态。")
	var game_flow: GameFlowSystem = _get_runtime_game_flow_system()
	if is_instance_valid(game_flow):
		var context: Dictionary = game_flow.get_accessibility_context()
		if (
			GFVariantData.get_option_string_name(
				context,
				&"end_reason",
				&""
			) != &"no_moves"
		):
			_record_error("game_over_menu 正式状态未声明 no_moves 结束原因。")
	var current_game: CurrentGameModel = _get_runtime_current_game_model()
	var result_value: Variant = (
		current_game.last_game_result.get_value()
		if is_instance_valid(current_game)
		else null
	)
	if (
		not is_instance_valid(current_game)
		or not result_value is GameResultRecordedData
	):
		_record_error("game_over_menu 没有生成正式且可用的本局结算数据。")

	var summary_node: Node = overlay.find_child(
		"SummaryLabel",
		true,
		false
	)
	if not summary_node is Label:
		_record_error("game_over_menu 缺少 SummaryLabel。")
		return
	var summary: Label = summary_node
	var loading_text: String = tr("GAME_OVER_SUMMARY_LOADING")
	var unavailable_text: String = tr("GAME_OVER_SUMMARY_UNAVAILABLE")
	if (
		summary.text.strip_edges().is_empty()
		or summary.text == loading_text
		or summary.text == unavailable_text
	):
		_record_error("game_over_menu 摘要尚未生成有效结算数据。")
	var end_reason_text: String = tr("GAME_OVER_END_REASON_NO_MOVES")
	if (
		end_reason_text == "GAME_OVER_END_REASON_NO_MOVES"
		or not summary.text.contains(end_reason_text)
	):
		_record_error("game_over_menu 摘要未展示无可用移动的结束原因。")


func _capture_target_reached_player_flow() -> bool:
	var grid_model: GridModel = _get_runtime_grid_model()
	var status_model: GameStatusModel = _get_runtime_status_model()
	if not is_instance_valid(grid_model) or not is_instance_valid(status_model):
		_record_error("target_reached_menu 缺少运行时棋盘或状态模型。")
		return false
	var original_status: Dictionary = _snapshot_status_model(status_model)
	var fixture_target: int = maxi(grid_model.get_max_tile_value(), 2)

	# 只修改工具进程内的运行时模型，且 invoke_godot_project_tool.ps1 会将
	# user:// 映射到临时目录。目标值与实时最大方块一致，不会再生成
	# “目标 2048 已完成、棋盘最大值却是 2”的矛盾截图。
	status_model.highest_tile.set_value(fixture_target)
	status_model.set_target_state(fixture_target, true)
	var captured: bool = await _capture_routed_gameplay_overlay(
		GameUiRouterUtility.ROUTE_TARGET_REACHED_MENU,
		&"TargetReachedMenu",
		&"target_reached_menu"
	)
	if captured:
		_validate_target_reached_fixture(
			status_model,
			fixture_target
		)
	_restore_status_model(status_model, original_status)
	return captured


func _capture_game_over_player_flow() -> bool:
	var grid_model: GridModel = _get_runtime_grid_model()
	var status_model: GameStatusModel = _get_runtime_status_model()
	var game_flow: GameFlowSystem = _get_runtime_game_flow_system()
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if (
		not is_instance_valid(grid_model)
		or not is_instance_valid(status_model)
		or not is_instance_valid(game_flow)
		or not is_instance_valid(ui_router)
	):
		_record_error("game_over_menu 缺少正式结算链路依赖。")
		return false

	var fixture_snapshot: Dictionary = _make_no_moves_snapshot(grid_model)
	if fixture_snapshot.is_empty():
		_record_error("game_over_menu 无法构造满棋盘测试快照。")
		return false
	if not grid_model.restore_from_snapshot(fixture_snapshot):
		_record_error("game_over_menu 无法恢复满棋盘测试快照。")
		return false
	var game_board_node: Node = root.find_child("GameBoard", true, false)
	if game_board_node is GameBoardController:
		var game_board: GameBoardController = game_board_node
		game_board.restore_from_snapshot(fixture_snapshot)
	status_model.score.set_value(4096)
	status_model.move_count.set_value(128)
	status_model.sync_highest_tile_from_grid(grid_model)
	status_model.high_score.set_value(
		maxi(
			GFVariantData.to_int(
				status_model.high_score.get_value(),
				0
			),
			4096
		)
	)
	await _settle_frames(10)
	if not _is_no_moves_fixture(grid_model):
		_record_error("game_over_menu 测试棋盘并非真实无路可走状态。")
		return false

	# 通过正式 GameFlowSystem 结算，GamePlayController 会响应状态事件并使用
	# 项目 GameUiRouterUtility 打开 GameOverMenu。结算产生的数据仅写入工具
	# 包装器隔离的临时 user://，不会触碰玩家账号、存档、回放或排行榜。
	if not game_flow.check_game_over():
		_record_error("game_over_menu 正式结算未进入终局状态。")
		return false
	var overlay: Node = await _wait_for_node(&"GameOverMenu", 600)
	if not is_instance_valid(overlay):
		_record_error("game_over_menu 正式结算路由打开超时。")
		return false
	await _settle_frames(10)
	_validate_initial_focus(
		overlay,
		Vector2i(root.get_visible_rect().size.round()),
		"game_over_menu 初始焦点"
	)
	_validate_game_over_fixture(overlay, grid_model)
	await _capture_gameplay_overlay_matrix(
		overlay,
		&"game_over_menu"
	)
	if not ui_router.back(GFUIUtility.Layer.POPUP):
		_record_error("game_over_menu 项目路由关闭失败。")
		return false
	await _settle_frames(4)
	# 结算样例高于隔离档案的初始成绩，会真实触发一次新纪录庆祝。
	# 在进入独立的动态/静态庆祝验收前清理该实例，避免两个阶段互相污染。
	await _clear_celebration_nodes()
	return true


func _capture_gameplay_overlay_matrix(
	overlay: Node,
	capture_id: StringName
) -> void:
	for resolution: Vector2i in _PLAYER_FLOW_RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(5)
		_queue_container_layout(overlay)
		await _settle_frames(6)
		var logical_resolution: Vector2i = Vector2i(
			root.get_visible_rect().size.round()
		)
		_validate_gameplay_overlay_structure(
			overlay,
			capture_id,
			logical_resolution
		)
		_record_page_geometry(
			overlay,
			capture_id,
			resolution,
			logical_resolution
		)
		_save_viewport(
			"%s_%dx%d.png"
			% [String(capture_id), resolution.x, resolution.y],
			resolution
		)
	_set_resolution(_PLAYER_FLOW_RESOLUTIONS[0])
	await _settle_frames(7)


func _capture_page_scroll_end_if_needed(
	page: Node,
	page_id: StringName,
	physical_resolution: Vector2i,
	logical_resolution: Vector2i
) -> void:
	match page_id:
		&"main_menu":
			await _capture_named_scroll_end(
				page,
				&"MainMenuScroll",
				&"QuitButton",
				page_id,
				physical_resolution,
				logical_resolution
			)
		&"bookmark_list", &"replay_list":
			await _capture_named_scroll_end(
				page,
				&"HistoryListPageScroll",
				&"BackButton",
				page_id,
				physical_resolution,
				logical_resolution
			)
		&"tile_lab":
			await _capture_named_scroll_end(
				page,
				&"BodyScroll",
				&"ResultPanel",
				page_id,
				physical_resolution,
				logical_resolution
			)
		&"tile_catalog":
			await _capture_named_scroll_end(
				page,
				&"CatalogScroll",
				&"CatalogGrid",
				page_id,
				physical_resolution,
				logical_resolution
			)
		&"player_profile":
			await _capture_named_scroll_end(
				page,
				&"ModeScroll",
				&"ModeList",
				page_id,
				physical_resolution,
				logical_resolution
			)
		&"achievements":
			await _capture_named_scroll_end(
				page,
				&"AchievementScroll",
				&"AchievementList",
				page_id,
				physical_resolution,
				logical_resolution
			)


func _capture_named_scroll_end(
	page: Node,
	scroll_name: StringName,
	target_name: StringName,
	capture_id: StringName,
	physical_resolution: Vector2i,
	logical_resolution: Vector2i,
	force_capture: bool = false
) -> void:
	var scroll_node: Node = page.find_child(String(scroll_name), true, false)
	if not scroll_node is ScrollContainer:
		if force_capture:
			_record_error(
				"%s @ %s 缺少主滚动 %s。"
				% [capture_id, logical_resolution, scroll_name]
			)
		return
	var scroll: ScrollContainer = scroll_node
	if not scroll.is_visible_in_tree():
		return
	var scroll_bar: VScrollBar = scroll.get_v_scroll_bar()
	var maximum_scroll: float = maxf(
		scroll_bar.max_value - scroll_bar.page,
		0.0
	)
	if maximum_scroll <= 0.5 and not force_capture:
		return
	var previous_scroll: int = scroll.scroll_vertical
	scroll.scroll_vertical = roundi(maximum_scroll)
	await _settle_frames(4)
	_validate_scroll_end_target(
		page,
		scroll,
		target_name,
		capture_id,
		logical_resolution
	)
	_save_viewport(
		"%s_%dx%d_scroll_end.png"
		% [
			String(capture_id),
			physical_resolution.x,
			physical_resolution.y,
		],
		physical_resolution
	)
	scroll.scroll_vertical = previous_scroll
	await _settle_frames(3)


func _validate_scroll_end_target(
	page: Node,
	scroll: ScrollContainer,
	target_name: StringName,
	capture_id: StringName,
	resolution: Vector2i
) -> void:
	var target_node: Node = page.find_child(String(target_name), true, false)
	if not target_node is Control:
		_record_error(
			"%s @ %s 滚动末端缺少目标 %s。"
			% [capture_id, resolution, target_name]
		)
		return
	var target: Control = _get_last_visible_control(target_node)
	if not is_instance_valid(target):
		target = target_node
	if not target.is_visible_in_tree():
		_record_error(
			"%s @ %s 滚动末端目标 %s 不可见。"
			% [capture_id, resolution, target_name]
		)
		return
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var target_rect: Rect2 = target.get_global_rect()
	if not viewport_rect.encloses(target_rect):
		_record_error(
			"%s @ %s 滚动末端目标 %s 未完整进入主滚动视口：%s / %s。"
			% [
				capture_id,
				resolution,
				target_name,
				target_rect,
				viewport_rect,
			]
		)


func _get_last_visible_control(root_node: Node) -> Control:
	var result: Control = root_node if root_node is Control else null
	for child: Node in root_node.get_children():
		var descendant: Control = _get_last_visible_control(child)
		if (
			is_instance_valid(descendant)
			and descendant.is_visible_in_tree()
			and descendant.size.x > 0.5
			and descendant.size.y > 0.5
		):
			result = descendant
	return result


func _activate_named_button(
	page: Node,
	button_name: StringName
) -> bool:
	var button_node: Node = page.find_child(String(button_name), true, false)
	if not button_node is Button:
		_record_error("%s 缺少状态按钮 %s。" % [page.name, button_name])
		return false
	var button: Button = button_node
	if not button.is_visible_in_tree() or button.disabled:
		_record_error("%s 状态按钮 %s 不可操作。" % [page.name, button_name])
		return false
	button.grab_focus()
	button.pressed.emit()
	await _settle_frames(5)
	return true


func _queue_container_layout(node: Node) -> void:
	if node is Container:
		var container: Container = node
		container.queue_sort()
	for child: Node in node.get_children():
		_queue_container_layout(child)


func _capture_mode_selection_scroll_end(
	page: Node,
	resolution: Vector2i
) -> void:
	var scroll_node: Node = page.find_child("ModeSelectionScroll", true, false)
	if not scroll_node is ScrollContainer:
		return
	var page_scroll: ScrollContainer = scroll_node
	var previous_scroll: int = page_scroll.scroll_vertical
	var scroll_bar: VScrollBar = page_scroll.get_v_scroll_bar()
	page_scroll.scroll_vertical = roundi(
		maxf(scroll_bar.max_value - scroll_bar.page, 0.0)
	)
	await _settle_frames(3)
	_save_viewport(
		"mode_selection_%dx%d_scroll_end.png" % [resolution.x, resolution.y],
		resolution
	)
	page_scroll.scroll_vertical = previous_scroll
	await _settle_frames(2)


func _capture_celebration_variants() -> void:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		_record_error("庆祝截图缺少 Gf 根节点。")
		return
	var vfx_value: Variant = gf_node.call(
		"get_utility",
		GameCelebrationVfxUtility
	)
	var accessibility_value: Variant = gf_node.call(
		"get_utility",
		GameAccessibilityUtility
	)
	if (
		not vfx_value is GameCelebrationVfxUtility
		or not accessibility_value is GameAccessibilityUtility
	):
		_record_error("庆祝截图缺少 VFX 或无障碍 Utility。")
		return
	var vfx: GameCelebrationVfxUtility = vfx_value
	var accessibility: GameAccessibilityUtility = accessibility_value
	accessibility.set_reduced_motion(false)
	accessibility.set_shader_effects_enabled(true)
	var _dynamic_played: bool = vfx.play_new_record_celebration()
	await _settle_frames(12)
	_validate_celebration_layer(false)
	_save_viewport("celebration_dynamic_1280x720.png", _RESOLUTIONS[0])
	await _clear_celebration_nodes()

	accessibility.set_reduced_motion(true)
	var _static_played: bool = vfx.play_new_record_celebration()
	await _settle_frames(4)
	_validate_celebration_layer(true)
	_save_viewport("celebration_static_1280x720.png", _RESOLUTIONS[0])
	accessibility.set_reduced_motion(false)
	await _clear_celebration_nodes()


func _validate_page_structure(
	page: Node,
	page_id: StringName,
	resolution: Vector2i
) -> void:
	if not is_instance_valid(page):
		_record_error("%s @ %s 页面实例无效。" % [page_id, resolution])
		return
	if page_id == &"boot":
		_validate_boot_structure(page, resolution)
		return
	var compact: bool = GameTaskPageLayoutUtility.is_compact_layout(
		Vector2(resolution)
	)
	if _page_requires_background_driver(page_id):
		var background_node: Node = page.find_child("Background", true, false)
		if background_node is ColorRect:
			var background: ColorRect = background_node
			var driver: Node = background.get_node_or_null("ShaderAnimationDriver")
			if not driver is GameShaderAnimationDriver:
				_record_error("%s @ %s 背景缺少可暂停时间 Driver。" % [page_id, resolution])
			elif driver.process_mode == Node.PROCESS_MODE_ALWAYS:
				_record_error("%s @ %s 背景 Driver 使用了 ALWAYS。" % [page_id, resolution])
		else:
			_record_error("%s @ %s 缺少 Background ColorRect。" % [page_id, resolution])

	match page_id:
		&"main_menu":
			var content_node: Node = page.find_child("Content", true, false)
			var title_node: Node = page.find_child("TitleLabel", true, false)
			var start_node: Node = page.find_child("StartGameButton", true, false)
			if not content_node is BoxContainer:
				_record_error("main_menu @ %s 缺少 Content。" % resolution)
			else:
				var content: BoxContainer = content_node
				if content.vertical != compact:
					_record_error("main_menu @ %s 单列策略错误。" % resolution)
			if compact and not page.find_child("MainMenuScroll", true, false) is ScrollContainer:
				_record_error("main_menu @ %s 缺少紧凑滚动容器。" % resolution)
			if title_node is Control:
				var title_control: Control = title_node
				_validate_control_rect(
					title_control,
					resolution,
					"main_menu 品牌标题"
				)
			if start_node is Control:
				var start_control: Control = start_node
				_validate_control_rect(
					start_control,
					resolution,
					"main_menu 开始游戏"
				)
		&"mode_selection":
			var right: Node = page.find_child("RightColumn", true, false)
			var center: Node = page.find_child("CenterColumn", true, false)
			var columns: Node = page.find_child("ColumnsContainer", true, false)
			var margin_node: Node = page.find_child("MarginContainer", true, false)
			var page_scroll_node: Node = page.find_child(
				"ModeSelectionScroll",
				true,
				false
			)
			var start_node: Node = page.find_child("StartGameButton", true, false)
			var content_node: Node = page.find_child(
				"CenterContentVBox",
				true,
				false
			)
			var layout_mode: int = GameTaskPageLayoutUtility.classify_layout(
				Vector2(resolution)
			)
			var side_by_side: bool = ModeSelection._uses_side_by_side_layout(
				Vector2(resolution)
			)
			var expected_parent: Node = columns if side_by_side else center
			if not is_instance_valid(right) or right.get_parent() != expected_parent:
				_record_error("mode_selection @ %s 右栏响应式归属错误。" % resolution)
			if (
				layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
				and content_node is Control
			):
				var content: Control = content_node
				if content.size.x < minf(float(resolution.x) * 0.75, 600.0):
					_record_error("mode_selection @ %s 模式列表宽度不足。" % resolution)
				_validate_mode_selection_portrait_scroll(
					page,
					margin_node,
					page_scroll_node,
					start_node,
					resolution
				)
			if (
				layout_mode == GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
				and side_by_side
			):
				if not start_node is Control:
					_record_error("mode_selection @ %s 缺少开始游戏按钮。" % resolution)
				else:
					var start_control: Control = start_node
					var start_rect: Rect2 = start_control.get_global_rect()
					if (
						not start_control.is_visible_in_tree()
						or start_rect.position.y < 0.0
						or start_rect.position.x < 0.0
						or start_rect.end.y > float(resolution.y)
						or start_rect.end.x > float(resolution.x)
					):
						_record_error(
							"mode_selection @ %s 开始游戏未处于首屏可达区域。"
							% resolution
						)
		&"settings":
			var body_node: Node = page.find_child("Body", true, false)
			var rail_node: Node = page.find_child("CategoryRail", true, false)
			if not body_node is BoxContainer or not rail_node is BoxContainer:
				_record_error("settings @ %s 缺少 Body/CategoryRail。" % resolution)
			else:
				var body: BoxContainer = body_node
				var rail: BoxContainer = rail_node
				if body.vertical != compact or rail.vertical == compact:
					_record_error("settings @ %s 单列/横向分类栏策略错误。" % resolution)
		&"bookmark_list", &"replay_list":
			var back_node: Node = page.find_child("BackButton", true, false)
			if back_node is Control:
				var back_control: Control = back_node
				_validate_control_rect(
					back_control,
					resolution,
					"%s 返回按钮" % page_id
				)
			var empty_node: Node = page.find_child("EmptyStateLabel", true, false)
			if empty_node is Control:
				var empty_control: Control = empty_node
				_validate_control_rect(
					empty_control,
					resolution,
					"%s 空态" % page_id
				)
		&"tile_lab":
			_validate_overlay_root(page, resolution, "tile_lab")
			_validate_tile_lab_scroll_ownership(page, resolution)
		&"tile_catalog", &"player_profile", &"achievements":
			_validate_overlay_root(page, resolution, String(page_id))


func _validate_mode_selection_portrait_scroll(
	page: Node,
	margin_node: Node,
	page_scroll_node: Node,
	start_node: Node,
	resolution: Vector2i
) -> void:
	if not margin_node is MarginContainer or not page_scroll_node is ScrollContainer:
		_record_error("mode_selection @ %s 缺少竖屏页面滚动所有者。" % resolution)
		return
	var margin: MarginContainer = margin_node
	var page_scroll: ScrollContainer = page_scroll_node
	var expected_height: float = (
		margin.size.y
		- float(margin.get_theme_constant("margin_top"))
		- float(margin.get_theme_constant("margin_bottom"))
	)
	if absf(page_scroll.size.y - expected_height) > 1.0:
		_record_error(
			"mode_selection @ %s 页面滚动视口未占满安全区高度：%.1f / %.1f。"
			% [resolution, page_scroll.size.y, expected_height]
		)
	var visible_vertical_scrolls: int = 0
	for scroll_node: Node in page.find_children("*", "ScrollContainer", true, false):
		if not scroll_node is ScrollContainer:
			continue
		var scroll: ScrollContainer = scroll_node
		if (
			scroll.is_visible_in_tree()
			and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		):
			visible_vertical_scrolls += 1
	if visible_vertical_scrolls != 1:
		_record_error(
			"mode_selection @ %s 竖屏必须只有一个纵向滚动所有者，实际为 %d。"
			% [resolution, visible_vertical_scrolls]
		)
	if not start_node is Control:
		_record_error("mode_selection @ %s 缺少开始游戏按钮。" % resolution)
		return
	var start_control: Control = start_node
	var scroll_rect: Rect2 = page_scroll.get_global_rect()
	var start_rect: Rect2 = start_control.get_global_rect()
	var scroll_bar: VScrollBar = page_scroll.get_v_scroll_bar()
	var maximum_scroll: float = maxf(scroll_bar.max_value - scroll_bar.page, 0.0)
	if (
		not start_control.is_visible_in_tree()
		or start_rect.end.y - maximum_scroll > scroll_rect.end.y + 1.0
	):
		_record_error(
			"mode_selection @ %s 开始游戏按钮无法通过唯一页面滚动到达。"
			% resolution
		)


func _page_requires_background_driver(page_id: StringName) -> bool:
	return page_id in [
		&"main_menu",
		&"mode_selection",
		&"settings",
		&"bookmark_list",
		&"replay_list",
	]


func _validate_overlay_root(
	page: Node,
	resolution: Vector2i,
	label: String
) -> void:
	if page is Control:
		var page_control: Control = page
		_validate_control_rect(page_control, resolution, "%s 对话框" % label)
	var back_node: Node = page.find_child("BackButton", true, false)
	if back_node is Control:
		var back_control: Control = back_node
		_validate_control_rect(
			back_control,
			resolution,
			"%s 返回按钮" % label
		)


func _validate_tile_lab_scroll_ownership(page: Node, resolution: Vector2i) -> void:
	var body_node: Node = page.find_child("BodyScroll", true, false)
	var recipes_node: Node = page.find_child("RecipesScroll", true, false)
	if not body_node is ScrollContainer or not recipes_node is ScrollContainer:
		_record_error("tile_lab @ %s 缺少滚动所有权节点。" % resolution)
		return
	var body_scroll: ScrollContainer = body_node
	var recipes_scroll: ScrollContainer = recipes_node
	var compact: bool = resolution.x < 900
	if compact:
		if body_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			_record_error("tile_lab @ %s 紧凑布局未启用页面滚动。" % resolution)
		if recipes_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_record_error("tile_lab @ %s 紧凑布局仍保留配方内层滚动。" % resolution)
	else:
		if body_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_record_error("tile_lab @ %s 桌面布局仍保留页面级滚动。" % resolution)
		if recipes_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			_record_error("tile_lab @ %s 桌面布局未保留配方列表滚动。" % resolution)


func _validate_board_editor_structure(
	editor: Node,
	resolution: Vector2i,
	section: StringName
) -> void:
	if editor is Control:
		var editor_control: Control = editor
		_validate_control_rect(editor_control, resolution, "board_editor 对话框")
	var panel_node: Node = editor.find_child("EditorPanel", true, false)
	if not panel_node is Control:
		_record_error("board_editor @ %s 缺少 EditorPanel。" % resolution)
	else:
		var panel: Control = panel_node
		_validate_control_rect(panel, resolution, "board_editor 主面板")

	var tools_node: Node = editor.find_child("Tools", true, false)
	var canvas_node: Node = editor.find_child("CanvasViewport", true, false)
	var library_node: Node = editor.find_child("Library", true, false)
	var sections_node: Node = editor.find_child("MobileSections", true, false)
	if (
		not tools_node is Control
		or not canvas_node is Control
		or not library_node is Control
		or not sections_node is Control
	):
		_record_error("board_editor @ %s 缺少响应式内容分区。" % resolution)
		return
	var tools: Control = tools_node
	var canvas: Control = canvas_node
	var library: Control = library_node
	var sections: Control = sections_node
	match section:
		&"desktop":
			if (
				not tools.is_visible_in_tree()
				or not canvas.is_visible_in_tree()
				or not library.is_visible_in_tree()
				or sections.is_visible_in_tree()
			):
				_record_error("board_editor @ %s 桌面三栏可见性错误。" % resolution)
		&"editor":
			if (
				not tools.is_visible_in_tree()
				or not canvas.is_visible_in_tree()
				or library.is_visible_in_tree()
				or not sections.is_visible_in_tree()
			):
				_record_error("board_editor @ %s 编辑分区可见性错误。" % resolution)
		&"library":
			if (
				tools.is_visible_in_tree()
				or canvas.is_visible_in_tree()
				or not library.is_visible_in_tree()
				or not sections.is_visible_in_tree()
			):
				_record_error("board_editor @ %s 模板分区可见性错误。" % resolution)
	_validate_initial_focus(editor, resolution, "board_editor %s 焦点" % section)
	_validate_visible_touch_targets(editor, resolution, "board_editor %s" % section)


func _validate_gameplay_structure(
	game_play: Node,
	resolution: Vector2i
) -> void:
	if game_play is Control:
		var game_control: Control = game_play
		_validate_control_rect(game_control, resolution, "gameplay 根页面")
	var background_node: Node = game_play.find_child(
		"BoardBackground",
		true,
		false
	)
	var hud_node: Node = game_play.find_child("HUD", true, false)
	var score_node: Node = game_play.find_child(
		"ScoreValueLabel",
		true,
		false
	)
	var action_panel_node: Node = game_play.find_child(
		"ActionPanel",
		true,
		false
	)
	if not background_node is Control:
		_record_error("gameplay @ %s 缺少 BoardBackground。" % resolution)
	else:
		var board_background: Control = background_node
		if (
			not board_background.is_visible_in_tree()
			or board_background.size.x <= 1.0
			or board_background.size.y <= 1.0
		):
			_record_error("gameplay @ %s 棋盘背景尚未可见。" % resolution)
	if not hud_node is Control:
		_record_error("gameplay @ %s 缺少 HUD。" % resolution)
	else:
		var hud: Control = hud_node
		_validate_control_rect(hud, resolution, "gameplay HUD")
	if not score_node is Control:
		_record_error("gameplay @ %s HUD 缺少分数指标。" % resolution)
	if background_node is Control and action_panel_node is Control:
		var board_control: Control = background_node
		var action_panel: Control = action_panel_node
		if (
			action_panel.is_visible_in_tree()
			and action_panel.get_global_rect().intersects(
				board_control.get_global_rect().grow(
					_GAMEPLAY_MOTION_GUARD_MARGIN
				)
			)
		):
			_record_error("gameplay @ %s 操作面板进入棋盘动态安全包络。" % resolution)
	if _count_visible_gameplay_tiles(game_play) <= 0:
		_record_error("gameplay @ %s 尚无可见方块。" % resolution)
	_validate_visible_touch_targets(game_play, resolution, "gameplay")


func _validate_gameplay_overlay_structure(
	overlay: Node,
	capture_id: StringName,
	resolution: Vector2i
) -> void:
	if overlay is Control:
		var overlay_control: Control = overlay
		_validate_control_rect(
			overlay_control,
			resolution,
			"%s 对话框" % capture_id
		)
	var center_node: Node = overlay.find_child("CenterContainer", true, false)
	if not center_node is Control:
		_record_error("%s @ %s 缺少 CenterContainer。" % [capture_id, resolution])
	else:
		var center: Control = center_node
		_validate_control_rect(center, resolution, "%s 主内容" % capture_id)
	_validate_initial_focus(
		overlay,
		resolution,
		"%s 初始焦点" % capture_id
	)
	_validate_visible_touch_targets(
		overlay,
		resolution,
		String(capture_id)
	)


func _validate_initial_focus(
	panel: Node,
	resolution: Vector2i,
	label: String
) -> void:
	var focus_owner: Control = root.gui_get_focus_owner()
	if not is_instance_valid(focus_owner):
		_record_error("%s @ %s 缺少键盘/手柄焦点。" % [label, resolution])
		return
	if not _is_descendant_or_self(focus_owner, panel):
		_record_error(
			"%s @ %s 焦点落在弹层外：%s。"
			% [label, resolution, focus_owner.get_path()]
		)
		return
	if not focus_owner.is_visible_in_tree():
		_record_error(
			"%s @ %s 焦点控件不可见：%s。"
			% [label, resolution, focus_owner.get_path()]
		)


func _validate_visible_touch_targets(
	panel: Node,
	resolution: Vector2i,
	label: String
) -> void:
	for node: Node in panel.find_children("*", "Control", true, false):
		if not node is Control:
			continue
		var control: Control = node
		if not _is_touch_interactive(control) or not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.size.x + 0.1 < 44.0 or rect.size.y + 0.1 < 44.0:
			_record_error(
				"%s @ %s 交互目标不足 44px：%s = %s。"
				% [label, resolution, control.get_path(), rect.size]
			)


func _is_touch_interactive(control: Control) -> bool:
	return (
		control is BaseButton
		or control is LineEdit
		or control is TextEdit
		or control is ItemList
		or control is SpinBox
		or control is Slider
	)


func _is_descendant_or_self(node: Node, ancestor: Node) -> bool:
	var current: Node = node
	while is_instance_valid(current):
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _count_visible_gameplay_tiles(game_play: Node) -> int:
	var count: int = 0
	for node: Node in game_play.find_children("*", "Tile", true, false):
		if node is CanvasItem:
			var canvas_item: CanvasItem = node
			if canvas_item.is_visible_in_tree():
				count += 1
	return count


func _validate_celebration_layer(expect_static: bool) -> void:
	var layer_node: Node = root.get_node_or_null("GameCelebrationVfxLayer")
	if not layer_node is CanvasLayer:
		_record_error("庆祝层未创建。")
		return
	var layer: CanvasLayer = layer_node
	if layer.process_mode != Node.PROCESS_MODE_PAUSABLE:
		_record_error("庆祝层未使用 PAUSABLE。")
	if layer.get_child_count() != 1:
		_record_error("庆祝层实例数不是 1。")
		return
	var effect: Node = layer.get_child(0)
	if expect_static:
		if not effect is ColorRect:
			_record_error("reduced-motion 庆祝未降级为 ColorRect。")
		else:
			var static_rect: ColorRect = effect
			if static_rect.process_mode != Node.PROCESS_MODE_DISABLED:
				_record_error("reduced-motion 庆祝仍保留节点处理。")
			elif static_rect.material != null:
				_record_error("reduced-motion 庆祝仍保留材质。")
	elif not effect is GameCelebrationConfettiEmitter:
		_record_error("动态庆祝未使用有界 GPU 粒子发射器。")
	else:
		var emitter: GameCelebrationConfettiEmitter = effect
		if emitter.amount > 88 or emitter.process_mode == Node.PROCESS_MODE_ALWAYS:
			_record_error("动态庆祝违反粒子数或 process mode 预算。")


func _validate_boot_structure(page: Node, resolution: Vector2i) -> void:
	var stack_node: Node = page.find_child("BootStack", true, false)
	var track_node: Node = page.find_child("ProgressTrack", true, false)
	var clip_node: Node = page.find_child("PulseClip", true, false)
	var fill_node: Node = page.find_child("ProgressFill", true, false)
	if not stack_node is Control or not track_node is Control or not clip_node is Control:
		_record_error("boot @ %s 缺少响应式启动构图节点。" % resolution)
		return
	var stack: Control = stack_node
	var track: Control = track_node
	var clip: Control = clip_node
	_validate_control_rect(stack, resolution, "boot 构图")
	_validate_control_rect(track, resolution, "boot 进度槽")
	if not fill_node is Control or fill_node.get_parent() != clip:
		_record_error("boot @ %s 动态填充未与裁切内槽共享坐标系。" % resolution)
		return
	var fill: Control = fill_node
	var clip_rect: Rect2 = clip.get_global_rect()
	var fill_rect: Rect2 = fill.get_global_rect()
	if not clip_rect.encloses(fill_rect):
		_record_error("boot @ %s 动态填充越过进度内槽。" % resolution)


func _validate_control_rect(
	control: Control,
	resolution: Vector2i,
	label: String
) -> void:
	if not control.is_visible_in_tree():
		_record_error("%s @ %s 不可见。" % [label, resolution])
		return
	var rect: Rect2 = control.get_global_rect()
	# 路由/庆祝 reveal 可能在截图帧保留小于 2px 的亚像素变换。
	# 结构验收容忍该渲染边缘，不容忍真正的控件裁切。
	var viewport_rect: Rect2 = Rect2(
		Vector2.ZERO,
		Vector2(resolution)
	).grow(2.0)
	if not viewport_rect.encloses(rect):
		_record_error("%s @ %s 超出逻辑首屏：%s。" % [label, resolution, rect])


func _clear_celebration_nodes() -> void:
	var layer: Node = root.get_node_or_null("GameCelebrationVfxLayer")
	if not is_instance_valid(layer):
		return
	for child: Node in layer.get_children():
		child.queue_free()
	await process_frame


func _open_route(
	source: Node,
	button_name: StringName,
	target_name: StringName
) -> Node:
	if not is_instance_valid(source):
		return null
	var button_node: Node = source.find_child(String(button_name), true, false)
	if not button_node is Button:
		_record_error("%s 缺少路由按钮 %s。" % [source.name, button_name])
		return null
	var button: Button = button_node
	button.pressed.emit()
	var target: Node = await _wait_for_node(target_name, 900)
	if not is_instance_valid(target):
		_record_error("%s 路由超时。" % target_name)
		return null
	if not await _wait_for_scene_change_idle(5.0):
		_record_error("%s 场景路由未在时限内完成。" % target_name)
		return null
	await _settle_frames(8)
	return target


func _open_overlay(
	source: Node,
	button_name: StringName,
	target_name: StringName
) -> Node:
	if not is_instance_valid(source):
		return null
	var button_node: Node = source.find_child(String(button_name), true, false)
	if not button_node is Button:
		_record_error("%s 缺少浮层按钮 %s。" % [source.name, button_name])
		return null
	var button: Button = button_node
	button.pressed.emit()
	var target: Node = await _wait_for_node(target_name, 300)
	if not is_instance_valid(target):
		_record_error("%s 浮层打开超时。" % target_name)
		return null
	await _settle_frames(8)
	return target


func _close_overlay(overlay: Node) -> bool:
	if not is_instance_valid(overlay):
		return true
	var button_node: Node = overlay.find_child("BackButton", true, false)
	if not button_node is Button:
		_record_error("%s 缺少关闭按钮。" % overlay.name)
		return false
	var button: Button = button_node
	button.pressed.emit()
	for _frame: int in range(180):
		if not is_instance_valid(overlay) or not overlay.is_inside_tree():
			await _settle_frames(4)
			return true
		await process_frame
	_record_error("%s 浮层关闭超时。" % overlay.name)
	return false


func _close_overlay_with_button(
	overlay: Node,
	button_name: StringName
) -> bool:
	if not is_instance_valid(overlay):
		return true
	var button_node: Node = overlay.find_child(
		String(button_name),
		true,
		false
	)
	if not button_node is Button:
		_record_error("%s 缺少关闭按钮 %s。" % [overlay.name, button_name])
		return false
	var button: Button = button_node
	button.grab_focus()
	button.pressed.emit()
	if await _wait_for_overlay_closed(overlay, 300):
		await _settle_frames(4)
		return true
	_record_error("%s 浮层关闭超时。" % overlay.name)
	return false


func _wait_for_overlay_closed(overlay: Node, frame_budget: int) -> bool:
	for _frame: int in range(frame_budget):
		if not is_instance_valid(overlay) or not overlay.is_inside_tree():
			return true
		await process_frame
	return false


func _wait_for_gameplay_ready(game_play: Node) -> bool:
	for _frame: int in range(1200):
		if not is_instance_valid(game_play):
			return false
		var board_node: Node = game_play.find_child(
			"BoardBackground",
			true,
			false
		)
		var hud_node: Node = game_play.find_child("HUD", true, false)
		if (
			board_node is Control
			and hud_node is Control
			and (board_node as Control).is_visible_in_tree()
			and (hud_node as Control).is_visible_in_tree()
			and _count_visible_gameplay_tiles(game_play) > 0
		):
			await _settle_frames(24)
			return true
		await process_frame
	_record_error("GamePlay 未在时限内完成棋盘、方块和 HUD 初始化。")
	return false


func _wait_for_pause_state(
	expected_paused: bool,
	timeout_seconds: float
) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ceili(
		timeout_seconds * 1000.0
	)
	while Time.get_ticks_msec() <= deadline_msec:
		var pause_utility: GamePauseUtility = _get_game_pause_utility()
		if (
			is_instance_valid(pause_utility)
			and pause_utility.is_paused() == expected_paused
			and paused == expected_paused
		):
			return true
		await create_timer(0.02, true, false, true).timeout
	return false


func _return_gameplay_to_main_menu(game_play: Node) -> Node:
	if not is_instance_valid(game_play):
		return null
	var pause_utility: GamePauseUtility = _get_game_pause_utility()
	if is_instance_valid(pause_utility) and pause_utility.is_paused():
		var _resumed: bool = pause_utility.resume()
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if (
		is_instance_valid(ui_router)
		and ui_router.get_current_route_id(GFUIUtility.Layer.POPUP) != &""
	):
		var _popup_closed: bool = ui_router.back(GFUIUtility.Layer.POPUP)
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		_record_error("GamePlay 返回主菜单时缺少 Gf 根节点。")
		return null
	var router_value: Variant = gf_node.call(
		"get_system",
		SceneRouterSystem
	)
	if not router_value is SceneRouterSystem:
		_record_error("GamePlay 返回主菜单时缺少 SceneRouterSystem。")
		return null
	var scene_router: SceneRouterSystem = router_value
	scene_router.return_to_main_menu()
	var main_menu: Node = await _wait_for_node(&"MainMenu", 900)
	if not is_instance_valid(main_menu):
		_record_error("GamePlay 返回主菜单超时。")
		return null
	if not await _wait_for_scene_change_idle(5.0):
		_record_error("GamePlay 返回主菜单的场景路由未完成。")
		return null
	await _settle_frames(12)
	return main_menu


func _get_board_editor_layout_controller(
	editor: Node
) -> BoardEditorResponsiveLayoutController:
	var controller_node: Node = editor.find_child(
		"BoardEditorResponsiveLayoutController",
		true,
		false
	)
	if controller_node is BoardEditorResponsiveLayoutController:
		var controller: BoardEditorResponsiveLayoutController = controller_node
		return controller
	return null


func _validate_board_editor_cancel_translation(editor: Node) -> void:
	var cancel_node: Node = editor.find_child(
		"CancelButton",
		true,
		false
	)
	if not cancel_node is Button:
		_record_error("board_editor 缺少 CancelButton。")
		return
	var cancel_button: Button = cancel_node
	if (
		cancel_button.text.strip_edges().is_empty()
		or cancel_button.text == "UI_CANCEL"
	):
		_record_error("board_editor CancelButton 暴露了空文本或原始翻译键。")


func _get_game_ui_router_utility() -> GameUiRouterUtility:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return null
	var utility_value: Variant = gf_node.call(
		"get_utility",
		GameUiRouterUtility
	)
	if utility_value is GameUiRouterUtility:
		var utility: GameUiRouterUtility = utility_value
		return utility
	return null


func _get_runtime_grid_model() -> GridModel:
	var value: Variant = _get_gf_member(&"get_model", GridModel)
	return value if value is GridModel else null


func _get_runtime_status_model() -> GameStatusModel:
	var value: Variant = _get_gf_member(
		&"get_model",
		GameStatusModel
	)
	return value if value is GameStatusModel else null


func _get_runtime_current_game_model() -> CurrentGameModel:
	var value: Variant = _get_gf_member(
		&"get_model",
		CurrentGameModel
	)
	return value if value is CurrentGameModel else null


func _get_runtime_game_flow_system() -> GameFlowSystem:
	var value: Variant = _get_gf_member(
		&"get_system",
		GameFlowSystem
	)
	return value if value is GameFlowSystem else null


func _get_gf_member(method: StringName, type_script: Script) -> Variant:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return null
	return gf_node.call(method, type_script)


func _get_game_pause_utility() -> GamePauseUtility:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return null
	var utility_value: Variant = gf_node.call(
		"get_utility",
		GamePauseUtility
	)
	if utility_value is GamePauseUtility:
		var utility: GamePauseUtility = utility_value
		return utility
	return null


func _wait_for_scene_change_idle(timeout_seconds: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ceili(
		timeout_seconds * 1000.0
	)
	while Time.get_ticks_msec() <= deadline_msec:
		var gf_node: Node = root.get_node_or_null("Gf")
		if is_instance_valid(gf_node):
			var router_value: Variant = gf_node.call(
				"get_system",
				SceneRouterSystem
			)
			if router_value is SceneRouterSystem:
				var router: SceneRouterSystem = router_value
				var snapshot: Dictionary = router.get_debug_snapshot()
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


func _resolve_screenshot_utility() -> GFScreenshotUtility:
	# 正式运行时诊断 Installer 可能未启用；工具仍复用 GF 的通用截图实现，
	# 避免触发严格架构对未注册 Utility 的查询错误。
	return GFScreenshotUtility.new()


func _save_viewport(file_name: String, resolution: Vector2i) -> void:
	var record: Dictionary = _screenshot_utility.save_viewport_screenshot(
		_OUTPUT_DIRECTORY.path_join(file_name),
		{
			"viewport": root,
			"format": GFScreenshotUtility.FORMAT_PNG,
			"resolution": resolution,
			"unique": false,
		}
	)
	if not GFVariantData.get_option_bool(record, "ok", false):
		_record_error(
			"截图失败 %s：%s"
			% [file_name, GFVariantData.get_option_string(record, "reason", "unknown")]
		)
		return
	_capture_count += 1


func _set_resolution(resolution: Vector2i) -> void:
	root.content_scale_size = _LOGICAL_DESIGN_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DisplayServer.window_set_size(resolution)
	# 截图矩阵只使用桌面工作区能够真实承载的窗口尺寸，避免把被 Windows
	# 截短的窗口再手动拉高后产生“背景变高、Container 仍保留旧高度”的伪影。
	root.size = resolution


func _settle_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
	await RenderingServer.frame_post_draw


func _record_error(message: String) -> void:
	var _appended: bool = _validation_errors.append(message)


func _record_page_geometry(
	page: Node,
	page_id: StringName,
	physical_resolution: Vector2i,
	logical_resolution: Vector2i
) -> void:
	var controls: Dictionary = {}
	var page_size: Vector2 = Vector2.ZERO
	if page is Control:
		var page_control: Control = page
		page_size = page_control.size
	for node_name: String in [
		"MarginContainer",
		"MainMenuScroll",
		"ModeSelectionScroll",
		"ColumnsContainer",
		"CenterColumn",
		"RightColumn",
		"EditorPanel",
		"MobileSections",
		"CanvasViewport",
		"Library",
		"BoardBackground",
		"HUD",
		"TopScorePanel",
		"ActionPanel",
		"StartGameButton",
		"BackButton",
		"CancelButton",
		"ApplyButton",
		"ContinueButton",
		"RestartButton",
		"MainMenuButton",
	]:
		var node: Node = page.find_child(node_name, true, false)
		if not node is Control:
			continue
		var control: Control = node
		controls[node_name] = {
			"position": control.get_global_rect().position,
			"size": control.get_global_rect().size,
			"visible": control.is_visible_in_tree(),
		}
	_geometry_records.append({
		"page": String(page_id),
		"physical": physical_resolution,
		"logical": logical_resolution,
		"page_size": page_size,
		"controls": controls,
	})


func _write_geometry_report() -> void:
	var directory_path: String = ProjectSettings.globalize_path(_OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return
	var file: FileAccess = FileAccess.open(
		_OUTPUT_DIRECTORY.path_join("geometry_report.json"),
		FileAccess.WRITE
	)
	if file == null:
		return
	var _geometry_bytes_written: bool = file.store_string(
		JSON.stringify(_geometry_records, "\t")
	)
	file.close()
	var validation_file: FileAccess = FileAccess.open(
		_OUTPUT_DIRECTORY.path_join("validation_report.json"),
		FileAccess.WRITE
	)
	if validation_file == null:
		return
	var _validation_bytes_written: bool = validation_file.store_string(
		JSON.stringify(Array(_validation_errors), "\t")
	)
	validation_file.close()


func _finish(exit_code: int) -> void:
	var _deferred_finish: Variant = call_deferred(
		&"_finish_after_cleanup",
		exit_code
	)


func _finish_after_cleanup(exit_code: int) -> void:
	_write_geometry_report()
	_screenshot_utility = null
	for child: Node in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	GFExtensionSettings.clear_manifest_cache()
	quit(exit_code)
