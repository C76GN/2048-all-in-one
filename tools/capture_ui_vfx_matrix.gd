extends SceneTree


const _OUTPUT_DIRECTORY: String = "res://build/ui_vfx_matrix"
const _LOGICAL_DESIGN_SIZE: Vector2i = Vector2i(720, 720)
const _RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1906, 943),
	Vector2i(850, 838),
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
		_record_page_geometry(page, page_id, resolution, logical_resolution)
		_validate_page_structure(page, page_id, logical_resolution)
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
	_set_resolution(_RESOLUTIONS[0])
	await _settle_frames(8)


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
				_validate_control_rect(title_node, resolution, "main_menu 品牌标题")
			if start_node is Control:
				_validate_control_rect(start_node, resolution, "main_menu 开始游戏")
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
				_validate_control_rect(back_node, resolution, "%s 返回按钮" % page_id)
			if page_id == &"bookmark_list":
				var empty_node: Node = page.find_child("EmptyStateLabel", true, false)
				if empty_node is Control:
					_validate_control_rect(empty_node, resolution, "bookmark_list 空态")
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
		_validate_control_rect(back_node, resolution, "%s 返回按钮" % label)


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
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution))
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
		"StartGameButton",
		"BackButton",
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
	file.store_string(JSON.stringify(_geometry_records, "\t"))
	file.close()
	var validation_file: FileAccess = FileAccess.open(
		_OUTPUT_DIRECTORY.path_join("validation_report.json"),
		FileAccess.WRITE
	)
	if validation_file == null:
		return
	validation_file.store_string(JSON.stringify(Array(_validation_errors), "\t"))
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
