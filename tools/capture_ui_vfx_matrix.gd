extends SceneTree


const _OUTPUT_DIRECTORY: String = "res://build/ui_vfx_matrix"
const _RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(960, 540),
	Vector2i(720, 1558),
]

var _screenshot_utility: GFScreenshotUtility = null
var _capture_count: int = 0
var _validation_errors: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[UiVfxMatrix] Capture requires rendering display mode.")
		_finish(64)
		return
	_set_resolution(_RESOLUTIONS[0])
	var boot_scene: PackedScene = load("res://app/scenes/boot.tscn")
	root.add_child(boot_scene.instantiate())
	var main_menu: Node = await _wait_for_node(&"MainMenu", 1200)
	if not is_instance_valid(main_menu):
		push_error("[UiVfxMatrix] MainMenu timeout.")
		_finish(1)
		return
	await _settle_frames(24)
	_screenshot_utility = _resolve_screenshot_utility()
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

	main_menu = await _open_route(mode_selection, &"BackButton", &"MainMenu")
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

	main_menu = await _open_route(settings_menu, &"BackButton", &"MainMenu")
	if not is_instance_valid(main_menu):
		_finish(6)
		return
	_set_resolution(_RESOLUTIONS[0])
	await _settle_frames(8)
	await _capture_celebration_variants()

	if not _validation_errors.is_empty():
		for message: String in _validation_errors:
			push_error("[UiVfxMatrix] %s" % message)
		_finish(7)
		return
	print("[UiVfxMatrix] completed captures=%d" % _capture_count)
	_finish(0)


func _capture_page_matrix(page: Node, page_id: StringName) -> void:
	for resolution: Vector2i in _RESOLUTIONS:
		_set_resolution(resolution)
		await _settle_frames(10)
		_validate_page_structure(page, page_id, resolution)
		_save_viewport(
			"%s_%dx%d.png" % [String(page_id), resolution.x, resolution.y],
			resolution
		)
	_set_resolution(_RESOLUTIONS[0])
	await _settle_frames(8)


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
	var compact: bool = GameTaskPageLayoutUtility.is_compact_layout(
		Vector2(resolution)
	)
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
			if not content_node is BoxContainer:
				_record_error("main_menu @ %s 缺少 Content。" % resolution)
			else:
				var content: BoxContainer = content_node
				if content.vertical != compact:
					_record_error("main_menu @ %s 单列策略错误。" % resolution)
			if compact and not page.find_child("MainMenuScroll", true, false) is ScrollContainer:
				_record_error("main_menu @ %s 缺少紧凑滚动容器。" % resolution)
		&"mode_selection":
			var right: Node = page.find_child("RightColumn", true, false)
			var center: Node = page.find_child("CenterColumn", true, false)
			var columns: Node = page.find_child("ColumnsContainer", true, false)
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
	DisplayServer.window_set_size(resolution)
	root.size = resolution
	root.content_scale_size = resolution


func _settle_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
	await RenderingServer.frame_post_draw


func _record_error(message: String) -> void:
	var _appended: bool = _validation_errors.append(message)


func _finish(exit_code: int) -> void:
	var _deferred_finish: Variant = call_deferred(
		&"_finish_after_cleanup",
		exit_code
	)


func _finish_after_cleanup(exit_code: int) -> void:
	_screenshot_utility = null
	for child: Node in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	GFExtensionSettings.clear_manifest_cache()
	quit(exit_code)
