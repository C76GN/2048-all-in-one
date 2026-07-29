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


var _capture_write_failed: bool = false
var _slowest_command_usec: int = 0


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
	_capture_viewport("boot_loading.png")
	await create_timer(0.12, true, false, true).timeout
	if is_instance_valid(root.get_node_or_null("Boot")):
		await _settle_frames(1)
		_capture_viewport("boot_loading_progress.png")

	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[VisualReview] MainMenu timeout.")
		_request_exit(1)
		return
	await _settle_frames(60)
	_capture_viewport("main_menu.png")

	var main_start: Node = main_menu.find_child("StartGameButton", true, false)
	if main_start is Button:
		var start_button: Button = main_start
		start_button.pressed.emit()
	await create_timer(0.12, true, false, true).timeout
	await _settle_frames(2)
	_capture_viewport("scene_transition_cover.png")
	var mode_selection: Node = await _wait_for_node(&"ModeSelection", 600)
	if not is_instance_valid(mode_selection):
		push_error("[VisualReview] ModeSelection timeout.")
		_request_exit(2)
		return
	await _settle_frames(2)
	_capture_viewport("scene_transition_reveal.png")
	await _settle_frames(24)
	_capture_viewport("mode_selection.png")

	var option_value: Node = mode_selection.find_child("GridSizeOptionButton", true, false)
	if option_value is OptionButton:
		var option_button: OptionButton = option_value
		option_button.show_popup()
		await _settle_frames(4)
		_capture_viewport("mode_selection_popup.png")
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
	if not await _inject_bookmark_preview(bookmark_list):
		_request_exit(5)
		return
	await _settle_frames(12)
	_capture_viewport("bookmark_list.png")
	if not await _capture_history_delete_states(bookmark_list, "bookmark"):
		_request_exit(5)
		return

	main_menu = await _return_to_main_menu(bookmark_list)
	if not is_instance_valid(main_menu):
		_request_exit(6)
		return

	var replay_list: Node = await _open_route(main_menu, &"ReplaysButton", &"ReplayList")
	if not is_instance_valid(replay_list):
		push_error("[VisualReview] ReplayList timeout.")
		_request_exit(7)
		return
	await _settle_frames(12)
	var replay_preview: ReplayData = await _inject_replay_preview(replay_list)
	if not is_instance_valid(replay_preview):
		_request_exit(8)
		return
	await _settle_frames(12)
	_capture_viewport("replay_list.png")
	if not await _capture_history_delete_states(replay_list, "replay"):
		_request_exit(9)
		return

	var replay_game: Node = await _open_route(replay_list, &"PlayButton", &"GamePlay")
	if not is_instance_valid(replay_game):
		push_error("[VisualReview] Replay GamePlay timeout.")
		_request_exit(10)
		return
	await create_timer(0.25, true, false, true).timeout
	await _settle_frames(12)
	_capture_viewport("replay_playback.png")
	if not await _advance_replay_once(replay_game, replay_preview):
		push_error("[VisualReview] Replay did not advance after the next-step action.")
		_request_exit(11)
		return
	await _settle_frames(8)
	_capture_viewport("replay_playback_step.png")

	main_menu = await _open_route(replay_game, &"ReplayExitButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_request_exit(12)
		return
	await _settle_frames(24)

	var settings_menu: Node = await _open_route(main_menu, &"SettingsButton", &"SettingsMenu")
	if not is_instance_valid(settings_menu):
		push_error("[VisualReview] SettingsMenu timeout.")
		_request_exit(13)
		return
	if not await _capture_settings_persistence_failure(settings_menu):
		_request_exit(14)
		return
	var controls_tab: Node = settings_menu.find_child("ControlsTabButton", true, false)
	if controls_tab is Button:
		var controls_button: Button = controls_tab
		controls_button.pressed.emit()
	await _settle_frames(12)
	_capture_viewport("settings_controls.png")

	main_menu = await _return_to_main_menu(settings_menu)
	if not is_instance_valid(main_menu):
		_request_exit(15)
		return

	mode_selection = await _open_route(main_menu, &"StartGameButton", &"ModeSelection")
	if not is_instance_valid(mode_selection):
		push_error("[VisualReview] ModeSelection second pass timeout.")
		_request_exit(16)
		return
	await _settle_frames(24)

	var game_start: Node = mode_selection.find_child("StartGameButton", true, false)
	if game_start is Button:
		var start_game_button: Button = game_start
		start_game_button.pressed.emit()
	var game_play: Node = await _wait_for_node(&"GamePlay", 900)
	if not is_instance_valid(game_play):
		push_error("[VisualReview] GamePlay timeout.")
		_request_exit(17)
		return
	await create_timer(1.0, true, false, true).timeout
	await _settle_frames(60)
	if _count_painted_gameplay_tiles(game_play) <= 0:
		push_error("[VisualReview] GamePlay has logical tiles but no painted tile content.")
		_request_exit(18)
		return
	_capture_viewport("gameplay.png")
	await _settle_frames(30)
	_capture_viewport("gameplay_grid_motion.png")
	if not await _capture_gameplay_motion_frames(game_play):
		_request_exit(18)
		return
	if not await _capture_first_merge_feedback(game_play):
		_request_exit(19)
		return
	# Let the captured turn finish before the scene is freed. Exiting while the
	# board action still owns pooled tiles can race the pool's deferred reparent.
	await create_timer(0.8, true, false, true).timeout
	await _settle_frames(6)
	if _capture_write_failed:
		_request_exit(20)
		return
	_request_exit()


func _request_exit(exit_code: int = 0) -> void:
	call_deferred(&"_finish_capture", exit_code)


func _finish_capture(exit_code: int) -> void:
	var gf_node: Node = root.get_node_or_null("Gf")
	for child: Node in root.get_children():
		if child == gf_node or child is CanvasLayer:
			continue
		child.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(gf_node):
		gf_node.queue_free()
	await process_frame
	await process_frame
	GFExtensionSettings.clear_manifest_cache()
	if exit_code == 0:
		print("[VisualReview] slowest_command_usec=%d" % _slowest_command_usec)
	quit(exit_code)


func _open_route(source: Node, button_name: StringName, target_name: StringName) -> Node:
	if not is_instance_valid(source):
		return null
	var button_node: Node = source.find_child(String(button_name), true, false)
	if not button_node is Button:
		return null
	var button: Button = button_node
	if not button.is_visible_in_tree() or button.disabled:
		push_error(
			"[VisualReview] Route button %s must be visible and enabled before activation."
			% String(button_name)
		)
		return null
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
	var mode_value: Resource = load(_CLASSIC_MODE_CONFIG_PATH)
	var determinism_value: Variant = _get_gf_member(&"get_utility", GameDeterminismUtility)
	if (
		not mode_value is GameModeConfig
		or not determinism_value is GameDeterminismUtility
	):
		push_error("[VisualReview] Cannot build the strict replay preview contract.")
		return null
	var mode_config: GameModeConfig = mode_value
	var determinism: GameDeterminismUtility = determinism_value
	var replay: ReplayData = ReplayData.new()
	replay.replay_id = GFUuid.generate_v7(1_784_761_200_000)
	replay.timestamp = 1_784_761_200
	replay.mode_config_path = _CLASSIC_MODE_CONFIG_PATH
	if not replay.configure_ruleset(mode_config, determinism):
		push_error("[VisualReview] Cannot freeze the replay ruleset.")
		return null
	replay.initial_seed = 35_941_119
	replay.session_metadata = GameSessionMetadata.make_default_dict()
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = 2700
	replay.actions = [Vector2i.LEFT]
	replay.checkpoints = [_make_preview_checkpoint(1, replay.final_score)]
	replay.final_board_snapshot = _make_preview_snapshot(topology)
	if ReplayData.from_dict(replay.to_dict()) == null:
		push_error("[VisualReview] Generated replay preview does not satisfy schema v4.")
		return null
	if not await _inject_list_item(page, _REPLAY_ITEM_SCENE, replay):
		return null
	return replay


func _inject_bookmark_preview(page: Node) -> bool:
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
	return await _inject_list_item(page, _BOOKMARK_ITEM_SCENE, bookmark)


func _inject_list_item(
	page: Node,
	item_scene: PackedScene,
	data: Resource
) -> bool:
	if not page is BaseListMenu:
		push_error("[VisualReview] History preview requires BaseListMenu.")
		return false
	var list_menu: BaseListMenu = page
	var items_container: Node = page.find_child("ItemsContainer", true, false)
	if not items_container is VBoxContainer:
		push_error("[VisualReview] History page is missing its shared ItemsContainer.")
		return false
	for child: Node in items_container.get_children():
		child.queue_free()
	await process_frame
	var item_node: Node = item_scene.instantiate()
	if not item_node is Control:
		push_error("[VisualReview] Injected history item must be a Control.")
		if is_instance_valid(item_node):
			item_node.free()
		return false
	var item_control: Control = item_node
	items_container.add_child(item_node)
	await process_frame
	list_menu._setup_item(item_control, data)
	list_menu._connect_item_signals(item_control, data)
	list_menu._on_empty_state_changed(false)
	list_menu._apply_list_focus_order([item_control])
	list_menu._set_selected_item(data)
	list_menu._bind_and_reveal_list_items()
	item_control.grab_focus()
	await _settle_frames(2)
	if (
		not item_control.has_focus()
		or not is_instance_valid(list_menu._primary_button)
		or not list_menu._primary_button.is_visible_in_tree()
		or list_menu._primary_button.disabled
		or not is_instance_valid(list_menu._delete_button)
		or not list_menu._delete_button.is_visible_in_tree()
		or list_menu._delete_button.disabled
	):
		push_error(
			"[VisualReview] Injected history item did not restore populated controls and focus."
		)
		return false
	return true


func _capture_history_delete_states(page: Node, capture_prefix: String) -> bool:
	if not page is BaseListMenu:
		push_error("[VisualReview] History delete state requires BaseListMenu.")
		return false
	var list_menu: BaseListMenu = page
	list_menu._on_delete_button_pressed()
	await _settle_frames(4)

	var confirmation_node: Node = page.find_child(
		"DeleteConfirmationDialog",
		true,
		false
	)
	if not confirmation_node is ConfirmationDialog:
		push_error("[VisualReview] History page is missing delete confirmation.")
		return false
	var confirmation: ConfirmationDialog = confirmation_node
	if not confirmation.visible:
		push_error("[VisualReview] History delete confirmation did not open.")
		return false
	_capture_viewport("%s_delete_confirmation.png" % capture_prefix)
	confirmation.hide()
	list_menu._on_delete_canceled()

	list_menu._show_delete_error(ERR_CANT_CREATE)
	await _settle_frames(4)
	var error_node: Node = page.find_child("DeleteErrorDialog", true, false)
	if not error_node is AcceptDialog:
		push_error("[VisualReview] History page is missing delete failure dialog.")
		return false
	var error_dialog: AcceptDialog = error_node
	if not error_dialog.visible:
		push_error("[VisualReview] History delete failure dialog did not open.")
		return false
	_capture_viewport("%s_delete_error.png" % capture_prefix)
	error_dialog.hide()
	await _settle_frames(2)
	return true


func _capture_settings_persistence_failure(page: Node) -> bool:
	if not page is SettingsMenu:
		push_error("[VisualReview] Settings failure state requires SettingsMenu.")
		return false
	var settings_value: Variant = _get_gf_member(
		&"get_utility",
		GameSettingsUtility
	)
	if not settings_value is GameSettingsUtility:
		push_error("[VisualReview] GameSettingsUtility is unavailable.")
		return false
	var settings: GameSettingsUtility = settings_value
	var previous_blocked_error: Error = settings._persistence_blocked_error
	var previous_write_error: Error = settings._last_persistence_error
	settings._persistence_blocked_error = ERR_CANT_CREATE
	settings._last_persistence_error = ERR_CANT_CREATE

	var settings_menu: SettingsMenu = page
	settings_menu._update_persistence_status()
	await _settle_frames(4)
	var status_node: Node = page.find_child("AutoSaveLabel", true, false)
	if not status_node is Label:
		push_error("[VisualReview] Settings persistence status label is missing.")
		settings._persistence_blocked_error = previous_blocked_error
		settings._last_persistence_error = previous_write_error
		return false
	var status_label: Label = status_node
	if (
		not status_label.visible
		or status_label.text.strip_edges().is_empty()
		or status_label.text == tr("SETTINGS_AUTO_SAVE_HINT")
	):
		push_error("[VisualReview] Settings failure state still reports auto-save.")
		settings._persistence_blocked_error = previous_blocked_error
		settings._last_persistence_error = previous_write_error
		return false
	_capture_viewport("settings_save_failure.png")

	settings._persistence_blocked_error = previous_blocked_error
	settings._last_persistence_error = previous_write_error
	settings_menu._update_persistence_status()
	await _settle_frames(2)
	return true


func _make_preview_snapshot(topology: BoardTopology) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [
			_make_preview_tile(Vector2i(0, 0), 2, 1_784_761_200_001),
			_make_preview_tile(Vector2i(1, 0), 4, 1_784_761_200_002),
			_make_preview_tile(Vector2i(2, 1), 16, 1_784_761_200_003),
			_make_preview_tile(Vector2i(3, 2), 64, 1_784_761_200_004),
			_make_preview_tile(Vector2i(1, 3), 128, 1_784_761_200_005),
		],
	}


func _advance_replay_once(game_play: Node, replay: ReplayData) -> bool:
	if not is_instance_valid(game_play) or not is_instance_valid(replay):
		return false
	if not await _prepare_replay_preview_step(replay):
		return false

	var next_node: Node = game_play.find_child("ReplayNextButton", true, false)
	if not next_node is Button:
		return false
	var next_button: Button = next_node
	if not next_button.visible or next_button.disabled:
		return false
	next_button.pressed.emit()
	return await _wait_for_replay_step(1, 5.0)


## 在当前真实玩法状态中预演并撤销一步，生成与运行时完全一致的 v4 checkpoint。
func _prepare_replay_preview_step(replay: ReplayData) -> bool:
	var replay_value: Variant = _get_gf_member(&"get_system", ReplaySystem)
	var history_value: Variant = _get_gf_member(&"get_utility", GFCommandHistoryUtility)
	var animation_value: Variant = _get_gf_member(&"get_utility", GameBoardAnimationUtility)
	var determinism_value: Variant = _get_gf_member(&"get_utility", GameDeterminismUtility)
	var state_value: Variant = _get_gf_member(&"get_system", GameStateSystem)
	var current_game_value: Variant = _get_gf_member(&"get_model", CurrentGameModel)
	var grid_value: Variant = _get_gf_member(&"get_model", GridModel)
	if (
		not replay_value is ReplaySystem
		or not history_value is GFCommandHistoryUtility
		or not determinism_value is GameDeterminismUtility
		or not state_value is GameStateSystem
		or not current_game_value is CurrentGameModel
		or not grid_value is GridModel
	):
		return false
	var replay_system: ReplaySystem = replay_value
	var history: GFCommandHistoryUtility = history_value
	var determinism: GameDeterminismUtility = determinism_value
	var state_system: GameStateSystem = state_value
	var current_game: CurrentGameModel = current_game_value
	var grid: GridModel = grid_value
	var mode_value: Variant = current_game.mode_config.get_value()
	if not mode_value is GameModeConfig:
		return false
	var mode_config: GameModeConfig = mode_value
	var direction: Vector2i = _find_available_move_direction()
	if direction == Vector2i.ZERO:
		return false

	var animation_utility: GameBoardAnimationUtility = (
		animation_value
		if animation_value is GameBoardAnimationUtility
		else null
	)
	if is_instance_valid(animation_utility):
		animation_utility.begin_presentation_suppression()
	replay_system.deactivate_replay_mode()
	var turn_value: Variant = await history.execute_command(MoveCommand.new(direction))
	if not turn_value is TurnResult:
		if is_instance_valid(animation_utility):
			animation_utility.end_presentation_suppression()
		replay_system.activate_replay_mode(replay)
		return false
	var turn_result: TurnResult = turn_value
	await _settle_frames(2)
	var checkpoint: ReplayCheckpoint = determinism.create_checkpoint(
		1,
		state_system.get_full_game_state(),
		mode_config,
		turn_result
	)
	var final_snapshot: Dictionary = grid.get_snapshot()
	var undo_succeeded: bool = await history.undo_last_async()
	await _settle_frames(1)
	if is_instance_valid(animation_utility):
		animation_utility.end_presentation_suppression()
	if not undo_succeeded or not is_instance_valid(checkpoint):
		replay_system.activate_replay_mode(replay)
		return false

	replay.actions = [direction]
	replay.checkpoints = [checkpoint]
	replay.final_score = checkpoint.score
	replay.final_board_snapshot = final_snapshot
	if ReplayData.from_dict(replay.to_dict()) == null:
		replay_system.activate_replay_mode(replay)
		return false
	replay_system.activate_replay_mode(replay)
	await _settle_frames(1)
	return replay_system.get_current_step() == 0


func _make_preview_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "0".repeat(64)
	checkpoint.board_checksum = "0".repeat(64)
	checkpoint.rng_checksum = "0".repeat(64)
	checkpoint.score = score
	return checkpoint


func _make_preview_tile(
	position: Vector2i,
	value: int,
	timestamp_msec: int
) -> Dictionary:
	var tile: TileState = TileState.new(
		value,
		&"tile.classic.numeric",
		GFUuid.generate_v7(timestamp_msec)
	)
	tile.capability_recipe_ids = [&"tile.recipe.classic_merge"]
	var result: Dictionary = tile.to_dict()
	result[&"pos"] = position
	return result


func _get_gf_member(method: StringName, type_script: Script) -> Variant:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		return null
	return gf_node.call(method, type_script)


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


func _capture_viewport(file_name: String) -> void:
	if not _save_viewport(file_name):
		return


func _save_viewport(file_name: String) -> bool:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_OUTPUT_DIRECTORY)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("[VisualReview] Cannot create output directory: %d" % directory_error)
		_capture_write_failed = true
		return false
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("[VisualReview] Viewport image is unavailable: %s" % file_name)
		_capture_write_failed = true
		return false
	var save_error: Error = image.save_png("%s/%s" % [_OUTPUT_DIRECTORY, file_name])
	if save_error != OK:
		push_error("[VisualReview] Cannot save %s: %d" % [file_name, save_error])
		_capture_write_failed = true
		return false
	return true


func _capture_first_merge_feedback(_game_play: Node) -> bool:
	var gf_node: Node = root.get_node_or_null("Gf")
	if not is_instance_valid(gf_node):
		push_error("[VisualReview] GF root is unavailable for merge capture.")
		return false
	var history_value: Variant = gf_node.call("get_utility", GFCommandHistoryUtility)
	if not history_value is GFCommandHistoryUtility:
		push_error("[VisualReview] Command history is unavailable for merge capture.")
		return false
	var status_value: Variant = gf_node.call("get_model", GameStatusModel)
	if not status_value is GameStatusModel:
		push_error("[VisualReview] Game status is unavailable for merge capture.")
		return false
	var history: GFCommandHistoryUtility = history_value
	var status: GameStatusModel = status_value
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.RIGHT,
		Vector2i.UP,
	]
	var slowest_command_usec: int = 0
	for turn_index: int in range(32):
		var score_before: int = GFVariantData.to_int(status.score.get_value(), 0)
		var started_usec: int = Time.get_ticks_usec()
		var _command_result: Variant = await history.execute_command(
			MoveCommand.new(directions[turn_index % directions.size()])
		)
		slowest_command_usec = maxi(
			slowest_command_usec,
			Time.get_ticks_usec() - started_usec
		)
		var score_after: int = GFVariantData.to_int(status.score.get_value(), 0)
		await create_timer(0.08, true, false, true).timeout
		await _settle_frames(2)
		if score_after > score_before:
			if not _save_viewport("gameplay_feedback.png"):
				return false
			_slowest_command_usec = slowest_command_usec
			return true
	push_error("[VisualReview] no scoring merge captured in deterministic move cycle.")
	return false


func _capture_gameplay_motion_frames(game_play: Node) -> bool:
	var feedback_canvas_node: Node = game_play.find_child(
		"BoardFeedbackCanvas",
		true,
		false
	)
	var feedback_root_node: Node = game_play.find_child(
		"BoardFeedbackRoot",
		true,
		false
	)
	var backdrop_node: Node = game_play.find_child(
		"BoardMotionBackdrop",
		true,
		false
	)
	var board_background_node: Node = game_play.find_child(
		"BoardBackground",
		true,
		false
	)
	var background_node: Node = game_play.find_child("Background", true, false)
	var board_container_node: Node = game_play.find_child(
		"BoardContainer",
		true,
		false
	)
	var feedback_value: Variant = _get_gf_member(
		&"get_utility",
		GameBoardFeedbackUtility
	)
	if (
		not feedback_canvas_node is BoardFeedbackCanvas
		or not feedback_root_node is Node2D
		or not backdrop_node is BoardMotionBackdrop
		or not board_background_node is Control
		or not background_node is ColorRect
		or not board_container_node is Node2D
		or not feedback_value is GameBoardFeedbackUtility
	):
		push_error("[VisualReview] Gameplay motion fixture dependencies are unavailable.")
		return false

	var feedback_canvas: BoardFeedbackCanvas = feedback_canvas_node
	var feedback_root: Node2D = feedback_root_node
	var backdrop: BoardMotionBackdrop = backdrop_node
	var board_background: Control = board_background_node
	var background: ColorRect = background_node
	var board_container: Node2D = board_container_node
	var feedback: GameBoardFeedbackUtility = feedback_value
	var tile: Tile = null
	for child: Node in board_container.get_children():
		if not child is Tile:
			continue
		var candidate_tile: Tile = child
		if _is_painted_gameplay_tile(candidate_tile):
			tile = candidate_tile
			break
	if not is_instance_valid(tile):
		push_error("[VisualReview] Gameplay motion fixture could not find a painted tile.")
		return false

	var profile: GameBoardFeedbackProfile = feedback.get_profile()
	if not is_instance_valid(profile) or not is_instance_valid(profile.tile_motion_profile):
		push_error("[VisualReview] Gameplay motion fixture has no motion profile.")
		return false
	var tile_start_position: Vector2 = tile.position
	var move_offset: Vector2 = Vector2(
		-115.0 if tile_start_position.x > board_background.size.x * 0.5 else 115.0,
		0.0
	)
	var board_rect: Rect2 = Rect2(
		-board_background.size * 0.5,
		board_background.size
	)
	var _created_count: int = feedback.play_turn_feedback(
		feedback_root,
		feedback_canvas,
		background,
		Vector2i.RIGHT,
		GameBoardFeedbackUtility.FeedbackTier.HIGH_MERGE,
		board_rect,
		Color("#efb24d"),
		backdrop
	)
	var _move_tween: Tween = tile.animate_move(
		tile_start_position + move_offset,
		profile.tile_motion_profile
	)
	await create_timer(0.04, true, false, true).timeout
	await _settle_frames(2)
	if not _save_viewport("gameplay_motion_0040ms.png"):
		return false
	await create_timer(0.07, true, false, true).timeout
	await _settle_frames(2)
	if not _save_viewport("gameplay_motion_0110ms.png"):
		return false
	await create_timer(0.10, true, false, true).timeout
	await _settle_frames(2)
	if not _save_viewport("gameplay_motion_0210ms.png"):
		return false
	await create_timer(0.22, true, false, true).timeout
	await _settle_frames(2)
	if not _save_viewport("gameplay_motion_0430ms.png"):
		return false
	tile.reset_animation_state()
	tile.position = tile_start_position
	await create_timer(0.28, true, false, true).timeout
	backdrop.reset_feedback()
	await _settle_frames(3)
	return true


func _count_painted_gameplay_tiles(game_play: Node) -> int:
	var count: int = 0
	for node: Node in game_play.find_children("*", "Tile", true, false):
		if not node is Tile:
			continue
		var tile: Tile = node
		if _is_painted_gameplay_tile(tile):
			count += 1
	return count


func _is_painted_gameplay_tile(tile: Tile) -> bool:
	return (
		is_instance_valid(tile)
		and tile.is_visible_in_tree()
		and absf(tile.scale.x) > 0.1
		and absf(tile.scale.y) > 0.1
		and is_instance_valid(tile.value_label)
		and not tile.value_label.text.strip_edges().is_empty()
	)
