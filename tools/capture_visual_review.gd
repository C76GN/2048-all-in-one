extends SceneTree


const _OUTPUT_DIRECTORY: String = "res://build/visual_review"


func _init() -> void:
	call_deferred(&"_run_capture")


func _run_capture() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var boot_scene: PackedScene = load("res://app/scenes/boot.tscn")
	root.add_child(boot_scene.instantiate())

	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[VisualReview] MainMenu timeout.")
		quit(1)
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
		quit(2)
		return
	await _settle_frames(12)
	_save_viewport("mode_selection.png")

	var option_value: Node = mode_selection.find_child("GridSizeOptionButton", true, false)
	if option_value is OptionButton:
		var option_button: OptionButton = option_value
		option_button.show_popup()
		await _settle_frames(4)
		_save_viewport("mode_selection_popup.png")
		option_button.get_popup().hide()

	var game_start: Node = mode_selection.find_child("StartGameButton", true, false)
	if game_start is Button:
		var start_game_button: Button = game_start
		start_game_button.pressed.emit()
	var game_play: Node = await _wait_for_node(&"GamePlay", 900)
	if not is_instance_valid(game_play):
		push_error("[VisualReview] GamePlay timeout.")
		quit(3)
		return
	await create_timer(1.0, true, false, true).timeout
	await _settle_frames(60)
	_save_viewport("gameplay.png")
	await _capture_first_merge_feedback(game_play)
	quit()


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


func _save_viewport(file_name: String) -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_OUTPUT_DIRECTORY)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("[VisualReview] Cannot create output directory: %d" % directory_error)
		return
	var image: Image = root.get_texture().get_image()
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
