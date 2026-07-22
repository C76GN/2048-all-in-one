extends SceneTree


const _OUTPUT_DIRECTORY: String = "res://build/visual_review"
const _CLASSIC_MODE_CONFIG_PATH: String = (
	"res://features/gameplay/resources/modes/classic_mode_config.tres"
)
const _REPLAY_ITEM_SCENE: PackedScene = preload(
	"res://features/replays/scenes/ui/replay_list_item.tscn"
)
const _BOOKMARK_ITEM_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/ui/bookmark_list_item.tscn"
)


func _init() -> void:
	call_deferred(&"_run_capture")


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[VisualReview] Capture requires the rendering display mode.")
		_request_exit(64)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var boot_scene: PackedScene = load("res://app/scenes/boot.tscn")
	root.add_child(boot_scene.instantiate())
	await _settle_frames(2)
	_save_viewport("boot_loading.png")
	await create_timer(0.12, true, false, true).timeout
	if is_instance_valid(root.get_node_or_null("Boot")):
		await _settle_frames(1)
		_save_viewport("boot_loading_progress.png")

	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[VisualReview] MainMenu timeout.")
		_request_exit(1)
		return
	await _settle_frames(60)
	_save_viewport("main_menu.png")

	var main_start: Node = main_menu.find_child("StartGameButton", true, false)
	if main_start is Button:
		var start_button: Button = main_start
		start_button.pressed.emit()
	await create_timer(0.12, true, false, true).timeout
	await _settle_frames(2)
	_save_viewport("scene_transition_cover.png")
	var mode_selection: Node = await _wait_for_node(&"ModeSelection", 600)
	if not is_instance_valid(mode_selection):
		push_error("[VisualReview] ModeSelection timeout.")
		_request_exit(2)
		return
	await _settle_frames(2)
	_save_viewport("scene_transition_reveal.png")
	await _settle_frames(24)
	_save_viewport("mode_selection.png")

	var option_value: Node = mode_selection.find_child("GridSizeOptionButton", true, false)
	if option_value is OptionButton:
		var option_button: OptionButton = option_value
		option_button.show_popup()
		await _settle_frames(4)
		_save_viewport("mode_selection_popup.png")
		option_button.get_popup().hide()

	main_menu = await _return_to_main_menu(mode_selection)
	if not is_instance_valid(main_menu):
		_request_exit(3)
		return

	var bookmark_list: Node = await _open_route(
		main_menu,
		&"LoadBookmarkButton",
		&"BookmarkList"
	)
	if not is_instance_valid(bookmark_list):
		push_error("[VisualReview] BookmarkList timeout.")
		_request_exit(4)
		return
	await _settle_frames(12)
	await _inject_bookmark_preview(bookmark_list)
	await _settle_frames(12)
	_save_viewport("bookmark_list.png")

	main_menu = await _return_to_main_menu(bookmark_list)
	if not is_instance_valid(main_menu):
		_request_exit(5)
		return

	var replay_list: Node = await _open_route(main_menu, &"ReplaysButton", &"ReplayList")
	if not is_instance_valid(replay_list):
		push_error("[VisualReview] ReplayList timeout.")
		_request_exit(6)
		return
	await _settle_frames(12)
	var replay_preview: ReplayData = await _inject_replay_preview(replay_list)
	await _settle_frames(12)
	_save_viewport("replay_list.png")

	var replay_game: Node = await _open_route(replay_list, &"PlayButton", &"GamePlay")
	if not is_instance_valid(replay_game):
		push_error("[VisualReview] Replay GamePlay timeout.")
		_request_exit(7)
		return
	await create_timer(0.25, true, false, true).timeout
	await _settle_frames(12)
	_save_viewport("replay_playback.png")
	if not await _advance_replay_once(replay_game, replay_preview):
		push_error("[VisualReview] Replay did not advance after the next-step action.")
		_request_exit(8)
		return
	await _settle_frames(8)
	_save_viewport("replay_playback_step.png")

	main_menu = await _open_route(replay_game, &"ReplayExitButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_request_exit(9)
		return
	await _settle_frames(24)

	var settings_menu: Node = await _open_route(main_menu, &"SettingsButton", &"SettingsMenu")
	if not is_instance_valid(settings_menu):
		push_error("[VisualReview] SettingsMenu timeout.")
		_request_exit(10)
		return
	var controls_tab: Node = settings_menu.find_child("ControlsTabButton", true, false)
	if controls_tab is Button:
		var controls_button: Button = controls_tab
		controls_button.pressed.emit()
	await _settle_frames(12)
	_save_viewport("settings_controls.png")

	main_menu = await _return_to_main_menu(settings_menu)
	if not is_instance_valid(main_menu):
		_request_exit(11)
		return

	mode_selection = await _open_route(main_menu, &"StartGameButton", &"ModeSelection")
	if not is_instance_valid(mode_selection):
		push_error("[VisualReview] ModeSelection second pass timeout.")
		_request_exit(12)
		return
	await _settle_frames(24)

	var game_start: Node = mode_selection.find_child("StartGameButton", true, false)
	if game_start is Button:
		var start_game_button: Button = game_start
		start_game_button.pressed.emit()
	var game_play: Node = await _wait_for_node(&"GamePlay", 900)
	if not is_instance_valid(game_play):
		push_error("[VisualReview] GamePlay timeout.")
		_request_exit(13)
		return
	await create_timer(1.0, true, false, true).timeout
	await _settle_frames(60)
	_save_viewport("gameplay.png")
	await _settle_frames(30)
	_save_viewport("gameplay_grid_motion.png")
	await _capture_first_merge_feedback(game_play)
	_request_exit()


func _request_exit(exit_code: int = 0) -> void:
	call_deferred(&"_finish_capture", exit_code)


func _finish_capture(exit_code: int) -> void:
	GFExtensionSettings.clear_manifest_cache()
	quit(exit_code)


func _open_route(source: Node, button_name: StringName, target_name: StringName) -> Node:
	if not is_instance_valid(source):
		return null
	var button_node: Node = source.find_child(String(button_name), true, false)
	if not button_node is Button:
		return null
	var button: Button = button_node
	button.pressed.emit()
	var target: Node = await _wait_for_node(target_name, 900)
	if not is_instance_valid(target):
		return null
	if not await _wait_for_scene_change_idle(5.0):
		return null
	return target


func _wait_for_scene_change_idle(timeout_seconds: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ceili(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() <= deadline_msec:
		var gf_node: Node = root.get_node_or_null("Gf")
		if is_instance_valid(gf_node):
			var system_value: Variant = gf_node.call("get_system", SceneRouterSystem)
			if system_value is SceneRouterSystem:
				var router: SceneRouterSystem = system_value
				var snapshot: Dictionary = router.get_debug_snapshot()
				if not GFVariantData.get_option_bool(snapshot, "scene_change_active", false):
					return true
		await create_timer(0.02, true, false, true).timeout
	return false


func _return_to_main_menu(source: Node) -> Node:
	var main_menu: Node = await _open_route(source, &"BackButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		push_error("[VisualReview] MainMenu return timeout.")
		return null
	await _settle_frames(24)
	return main_menu


func _inject_replay_preview(page: Node) -> ReplayData:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	var replay: ReplayData = ReplayData.new()
	replay.timestamp = 1_784_761_200
	replay.mode_config_path = _CLASSIC_MODE_CONFIG_PATH
	replay.initial_seed = 35_941_119
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = 2700
	replay.actions = [
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.RIGHT,
		Vector2i.UP,
	]
	replay.final_board_snapshot = _make_preview_snapshot(topology)
	await _inject_list_item(page, _REPLAY_ITEM_SCENE, replay, "经典模式")
	return replay


func _inject_bookmark_preview(page: Node) -> void:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = 1_784_761_200
	bookmark.mode_config_path = _CLASSIC_MODE_CONFIG_PATH
	bookmark.initial_seed = 35_941_119
	bookmark.score = 1024
	bookmark.move_count = 86
	bookmark.highest_tile = 128
	bookmark.target_tile_value = 2048
	bookmark.board_snapshot = _make_preview_snapshot(topology)
	await _inject_list_item(page, _BOOKMARK_ITEM_SCENE, bookmark, "经典模式")


func _inject_list_item(
	page: Node,
	item_scene: PackedScene,
	data: Resource,
	mode_display_name: String
) -> void:
	var items_container: Node = page.find_child("ReplayItemsContainer", true, false)
	if not items_container is VBoxContainer:
		return
	for child: Node in items_container.get_children():
		child.queue_free()
	await process_frame
	var item_node: Node = item_scene.instantiate()
	items_container.add_child(item_node)
	await process_frame
	if item_node is ReplayListItem and data is ReplayData:
		var replay_item: ReplayListItem = item_node
		var replay_data: ReplayData = data
		replay_item.setup(replay_data, mode_display_name)
	elif item_node is BookmarkListItem and data is BookmarkData:
		var bookmark_item: BookmarkListItem = item_node
		var bookmark_data: BookmarkData = data
		bookmark_item.setup(bookmark_data, mode_display_name)
	var _selection_result: Variant = page.call(&"_set_selected_item", data)


func _make_preview_snapshot(topology: BoardTopology) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [
			{&"pos": Vector2i(0, 0), &"value": 2, &"definition_id": &"tile.classic.numeric"},
			{&"pos": Vector2i(1, 0), &"value": 4, &"definition_id": &"tile.classic.numeric"},
			{&"pos": Vector2i(2, 1), &"value": 16, &"definition_id": &"tile.classic.numeric"},
			{&"pos": Vector2i(3, 2), &"value": 64, &"definition_id": &"tile.classic.numeric"},
			{&"pos": Vector2i(1, 3), &"value": 128, &"definition_id": &"tile.classic.numeric"},
		],
	}


func _advance_replay_once(game_play: Node, replay: ReplayData) -> bool:
	if not is_instance_valid(game_play) or not is_instance_valid(replay):
		return false
	var direction: Vector2i = _find_available_move_direction()
	if direction == Vector2i.ZERO or replay.actions.is_empty():
		return false
	replay.actions[0] = direction

	var next_node: Node = game_play.find_child("ReplayNextButton", true, false)
	if not next_node is Button:
		return false
	var next_button: Button = next_node
	if not next_button.visible or next_button.disabled:
		return false
	next_button.pressed.emit()
	return await _wait_for_replay_step(1, 5.0)


func _find_available_move_direction() -> Vector2i:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return Vector2i.ZERO
	var model_value: Variant = gf_node.call("get_model", GridModel)
	if not model_value is GridModel:
		return Vector2i.ZERO
	var grid: GridModel = model_value
	if not is_instance_valid(grid.topology):
		return Vector2i.ZERO
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		for cell: Vector2i in grid.topology.get_active_cells():
			if grid.get_tile(cell) == null:
				continue
			var neighbor: Vector2i = cell + direction
			if grid.topology.contains_cell(neighbor) and grid.get_tile(neighbor) == null:
				return direction
	return Vector2i.ZERO


func _wait_for_replay_step(minimum_step: int, timeout_seconds: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ceili(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() <= deadline_msec:
		var gf_node: Node = root.get_node_or_null("Gf")
		if is_instance_valid(gf_node):
			var system_value: Variant = gf_node.call("get_system", ReplaySystem)
			if system_value is ReplaySystem:
				var replay_system: ReplaySystem = system_value
				if replay_system.get_current_step() >= minimum_step:
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
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save_viewport(file_name: String) -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_OUTPUT_DIRECTORY)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("[VisualReview] Cannot create output directory: %d" % directory_error)
		return
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("[VisualReview] Viewport image is unavailable: %s" % file_name)
		return
	var save_error: Error = image.save_png("%s/%s" % [_OUTPUT_DIRECTORY, file_name])
	if save_error != OK:
		push_error("[VisualReview] Cannot save %s: %d" % [file_name, save_error])


func _capture_first_merge_feedback(game_play: Node) -> void:
	var feedback_canvas: Node = game_play.find_child("BoardFeedbackCanvas", true, false)
	if not is_instance_valid(feedback_canvas):
		return
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return
	var history_value: Variant = gf_node.call("get_utility", GFCommandHistoryUtility)
	if not history_value is GFCommandHistoryUtility:
		return
	var history: GFCommandHistoryUtility = history_value
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.RIGHT,
		Vector2i.UP,
	]
	var slowest_command_usec: int = 0
	for turn_index: int in range(32):
		var started_usec: int = Time.get_ticks_usec()
		var _command_result: Variant = await history.execute_command(
			MoveCommand.new(directions[turn_index % directions.size()])
		)
		slowest_command_usec = maxi(
			slowest_command_usec,
			Time.get_ticks_usec() - started_usec
		)
		await create_timer(0.12, true, false, true).timeout
		await _settle_frames(2)
		if GFVariantData.to_bool(feedback_canvas.call("has_active_score_burst")):
			await create_timer(0.12, true, false, true).timeout
			await _settle_frames(2)
			_save_viewport("gameplay_feedback.png")
			print("[VisualReview] slowest_command_usec=%d" % slowest_command_usec)
			return
	print("[VisualReview] no merge captured; slowest_command_usec=%d" % slowest_command_usec)
