## 验证第一轮视觉增强资源与 Tile 动画基础行为。
extends GutTest


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://scenes/components/tile.tscn")
const _GAME_OVER_SCENE: PackedScene = preload("res://scenes/ui/game_over_menu.tscn")
const _TARGET_REACHED_SCENE: PackedScene = preload("res://scenes/ui/target_reached_menu.tscn")
const _BOOKMARK_ITEM_SCENE: PackedScene = preload("res://scenes/ui/bookmark_list_item.tscn")
const _REPLAY_ITEM_SCENE: PackedScene = preload("res://scenes/ui/replay_list_item.tscn")
const _BACKGROUND_SHADER_PATH: String = "res://resources/shaders/game_background.gdshader"
const _VISUAL_STYLE_DOC_PATH: String = "res://docs/VISUAL_STYLE.md"
const _CLASSIC_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/classic_tile_theme.tres")
const _FIBONACCI_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/fibonacci_tile_theme.tres")
const _LUCAS_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/lucas_tile_theme.tres")
const _RED_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/red_tile_theme.tres")
const _BLUE_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/blue_tile_theme.tres")
const _MIN_TILE_TEXT_CONTRAST: float = 3.0


# --- 测试用例 ---

func test_game_background_shader_loads() -> void:
	var shader: Shader = _load_shader(_BACKGROUND_SHADER_PATH)

	assert_true(is_instance_valid(shader), "游戏背景 shader 应能正常加载。")


func test_game_background_shader_keeps_soft_texture_defaults() -> void:
	var shader_text: String = _read_text(_BACKGROUND_SHADER_PATH)

	_assert_shader_float_default_in_range(shader_text, "grain_strength", 0.008, 0.020)
	_assert_shader_float_default_in_range(shader_text, "stipple_strength", 0.000, 0.006)
	_assert_shader_float_default_in_range(shader_text, "scanline_strength", 0.000, 0.008)
	_assert_shader_float_default_in_range(shader_text, "glow_strength", 0.000, 0.100)
	_assert_shader_float_default_in_range(shader_text, "pulse_speed", 0.000, 0.080)


func test_visual_style_document_records_indie_texture_direction() -> void:
	var text: String = _read_text(_VISUAL_STYLE_DOC_PATH)
	var missing_terms: Array[String] = []
	for term: String in [
		"柔和肌理扁平独立游戏",
		"不是像素风",
		"grain_strength",
		"stipple_strength",
		"resources/themes/tile_schemes",
		"GameUiMotionUtility",
	]:
		if not text.contains(term):
			_append_string(missing_terms, term)

	assert_true(
		missing_terms.is_empty(),
		"视觉规范文档应固定柔和独立游戏方向和关键落地点，缺少：\n%s" % _join_lines(missing_terms)
	)


func test_tile_setup_applies_flat_textured_style() -> void:
	var tile: Tile = await _create_tile()

	tile.setup(2048, Tile.TileType.PLAYER, Color(0.8, 0.5, 0.2, 1.0), Color.WHITE)

	var stylebox: StyleBoxFlat = _get_stylebox_flat(tile.background, &"panel")
	assert_not_null(stylebox, "Tile 背景应使用 StyleBoxFlat。")
	assert_true(stylebox.shadow_size == 0, "Tile 背景应保持无阴影的平面色块。")
	assert_true(stylebox.get_border_width(SIDE_TOP) == 0, "Tile 背景应保持无描边。")
	assert_true(stylebox.bg_color == Color(0.8, 0.5, 0.2, 1.0), "Tile 背景应直接使用实心色块。")


func test_game_board_controller_uses_configured_tile_scheme_colors() -> void:
	var controller: GameBoardController = GameBoardController.new()
	var grid_model: GridModel = GridModel.new()
	grid_model.interaction_rule = ClassicInteractionRule.new()
	controller.model = grid_model
	controller.color_schemes = {
		Tile.TileType.PLAYER: _CLASSIC_TILE_THEME,
	}

	var value_2_colors: Dictionary = controller._get_tile_colors(2, Tile.TileType.PLAYER)
	var value_4_colors: Dictionary = controller._get_tile_colors(4, Tile.TileType.PLAYER)
	var value_2_style: TileLevelStyle = _get_tile_level_style(_CLASSIC_TILE_THEME, 0)
	var value_4_style: TileLevelStyle = _get_tile_level_style(_CLASSIC_TILE_THEME, 1)

	assert_true(
		_get_color(value_2_colors, &"bg") == value_2_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块背景色。"
	)
	assert_true(
		_get_color(value_2_colors, &"font") == value_2_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块字体色。"
	)
	assert_true(
		_get_color(value_4_colors, &"bg") == value_4_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块背景色。"
	)
	assert_true(
		_get_color(value_4_colors, &"font") == value_4_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块字体色。"
	)
	controller.free()


func test_tile_color_schemes_keep_large_number_text_readable() -> void:
	var issues: Array[String] = []
	_collect_tile_scheme_contrast_issues("classic", _CLASSIC_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("fibonacci", _FIBONACCI_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("lucas", _LUCAS_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("red", _RED_TILE_THEME, issues)
	_collect_tile_scheme_contrast_issues("blue", _BLUE_TILE_THEME, issues)

	assert_true(
		issues.is_empty(),
		"方块主题的数字文字应保持至少 %.1f:1 的大字号对比度，避免柔和色板牺牲可读性：\n%s" % [
			_MIN_TILE_TEXT_CONTRAST,
			_join_lines(issues),
		]
	)


func test_tile_visual_animations_return_live_tweens() -> void:
	var tile: Tile = await _create_tile()
	tile.setup(2, Tile.TileType.PLAYER, Color(0.9, 0.75, 0.45, 1.0), Color.BLACK)

	var spawn_tween: Tween = tile.animate_spawn()
	assert_true(is_instance_valid(spawn_tween) and spawn_tween.is_valid(), "生成动画应返回有效 Tween。")

	tile.reset_animation_state()
	var move_tween: Tween = tile.animate_move(Vector2(48.0, 32.0))
	assert_true(is_instance_valid(move_tween) and move_tween.is_valid(), "移动动画应返回有效 Tween。")

	tile.reset_animation_state()
	var merge_tween: Tween = tile.animate_merge()
	assert_true(is_instance_valid(merge_tween) and merge_tween.is_valid(), "合并动画应返回有效 Tween。")

	tile.reset_animation_state()
	var transform_tween: Tween = tile.animate_transform()
	assert_true(is_instance_valid(transform_tween) and transform_tween.is_valid(), "转化动画应返回有效 Tween。")

	tile.reset_animation_state()

func test_ui_motion_utility_binds_buttons_recursively_once() -> void:
	var root: Control = Control.new()
	var container: VBoxContainer = VBoxContainer.new()
	var button: Button = Button.new()
	root.add_child(container)
	container.add_child(button)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()

	assert_true(motion_utility.bind_interactive_controls(root) == 1, "UI 动效 Utility 应递归绑定按钮。")
	assert_true(motion_utility.bind_interactive_controls(root) == 0, "重复绑定不应重复连接同一按钮。")

	var button_style: StyleBoxFlat = _get_stylebox_flat(button, &"normal")
	assert_not_null(button_style, "按钮绑定后应获得统一 StyleBoxFlat。")
	assert_true(button_style.get_border_width(SIDE_TOP) == 0, "统一按钮样式应保持无描边。")
	assert_true(button_style.shadow_size == 0, "统一按钮样式应保持无阴影。")


func test_ui_motion_utility_reveals_panel_with_tween() -> void:
	var panel: Control = Control.new()
	panel.position = Vector2(12.0, 20.0)
	panel.scale = Vector2.ONE
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()
	var tween: Tween = motion_utility.play_panel_intro(panel)

	assert_true(is_instance_valid(tween) and tween.is_valid(), "面板入场应返回有效 Tween。")
	assert_gt(panel.position.y, 20.0, "面板入场起点应带有轻微下移。")
	assert_lt(panel.modulate.a, 1.0, "面板入场起点应先淡入。")


func test_ui_motion_utility_reveals_visible_children_only() -> void:
	var container: VBoxContainer = VBoxContainer.new()
	var first_child: Button = Button.new()
	var second_child: Label = Label.new()
	var hidden_child: Button = Button.new()
	hidden_child.visible = false
	container.add_child(first_child)
	container.add_child(second_child)
	container.add_child(hidden_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()

	assert_true(motion_utility.play_children_reveal(container) == 2, "列表刷新动效应只作用于可见子控件。")
	assert_lt(first_child.modulate.a, 1.0, "可见子控件应从淡入状态开始。")
	assert_lt(second_child.modulate.a, 1.0, "第二个可见子控件也应从淡入状态开始。")
	assert_true(hidden_child.modulate.a == 1.0, "隐藏子控件不应被动效修改。")


func test_ui_motion_utility_does_not_move_container_managed_children() -> void:
	var container: VBoxContainer = VBoxContainer.new()
	var first_child: Label = Label.new()
	var second_child: Label = Label.new()
	first_child.text = "A"
	second_child.text = "B"
	container.add_child(first_child)
	container.add_child(second_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var first_position: Vector2 = first_child.position
	var second_position: Vector2 = second_child.position
	var motion_utility: GameUiMotionUtility = GameUiMotionUtility.new()

	assert_true(motion_utility.play_children_reveal(container, Vector2(20.0, 0.0)) == 2, "容器子控件仍应播放淡入动效。")
	assert_true(first_child.position == first_position, "VBoxContainer 子控件不应被动效改写位置。")
	assert_true(second_child.position == second_position, "第二个 VBoxContainer 子控件也不应被动效改写位置。")
	assert_lt(first_child.modulate.a, 1.0, "容器子控件仍应从淡入状态开始。")


func test_game_over_menu_contains_result_summary_labels() -> void:
	var panel: Control = _instantiate_control(_GAME_OVER_SCENE)
	assert_true(is_instance_valid(panel), "游戏结束场景应能实例化为 Control。")
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var title_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(title_node is Label, "游戏结束菜单应包含标题 Label。")
	assert_true(summary_node is Label, "游戏结束菜单应包含结算摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(
			summary_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"结算摘要应允许自动换行，避免窄屏溢出。"
		)


func test_game_over_menu_summary_uses_safe_format_fallback() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.score.set_value(8192)
	status_model.move_count.set_value(42)
	status_model.highest_tile.set_value(2048)
	status_model.high_score.set_value(16384)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.init()

	var context: _TestArchitectureContext = _TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_GAME_OVER_SCENE)
	assert_true(is_instance_valid(panel), "游戏结束场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(summary_node is Label, "游戏结束菜单应包含结算摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(summary_label.text.contains("8192"), "结算摘要应显示本局分数。")
		assert_true(summary_label.text.contains("42"), "结算摘要应显示本局步数。")
		assert_true(summary_label.text.contains("2048"), "结算摘要应显示本局最大方块。")
		assert_true(summary_label.text.contains("16384"), "结算摘要应显示历史最高分。")
	architecture.dispose()


func test_game_text_format_utility_uses_safe_fallbacks() -> void:
	var fallback: String = "%s | %s %d | %s %dx%d"
	var missing_key_text: String = GameTextFormatUtility.format_template(
		"MISSING_BOOKMARK_INFO_FORMAT",
		fallback,
		["2026-06-19", "分数", 128, "尺寸", 4, 4]
	)
	var malformed_text: String = GameTextFormatUtility.format_template(
		"%s | %s",
		fallback,
		["2026-06-19", "分数", 256, "尺寸", 5, 5]
	)
	var translated_text: String = GameTextFormatUtility.format_template(
		"%s / %s %d / %s %dx%d",
		fallback,
		["2026-06-19", "分数", 512, "尺寸", 6, 6]
	)
	var percent_text: String = GameTextFormatUtility.format_template(
		"目标达成率 %d%%",
		"目标达成率 %d%%",
		[73]
	)

	assert_true(missing_key_text.contains("128"), "缺失翻译 key 时 fallback 应保留分数。")
	assert_true(missing_key_text.contains("4x4"), "缺失翻译 key 时 fallback 应保留棋盘尺寸。")
	assert_true(malformed_text.contains("256"), "占位符数量不匹配时 fallback 应保留分数。")
	assert_true(malformed_text.contains("5x5"), "占位符数量不匹配时 fallback 应保留棋盘尺寸。")
	assert_true(translated_text.contains("512"), "合法翻译格式串应正常保留数值。")
	assert_true(translated_text.contains("6x6"), "合法翻译格式串应正常保留棋盘尺寸。")
	assert_true(percent_text.contains("73%"), "合法格式串中的 %% 应作为转义百分号处理。")


func test_target_reached_menu_contains_non_forced_choice_controls() -> void:
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var title_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	var message_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/MessageLabel")
	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	var continue_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/ContinueButton")
	var restart_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/RestartButton")
	var main_menu_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/MainMenuButton")

	assert_true(title_node is Label, "目标达成菜单应包含标题 Label。")
	assert_true(message_node is Label, "目标达成菜单应包含说明 Label。")
	assert_true(summary_node is Label, "目标达成菜单应包含本局目标摘要 Label。")
	assert_true(continue_node is Button, "目标达成菜单应提供继续挑战按钮。")
	assert_true(restart_node is Button, "目标达成菜单应提供重新开始按钮。")
	assert_true(main_menu_node is Button, "目标达成菜单应提供返回主界面按钮。")
	if message_node is Label:
		var message_label: Label = message_node
		assert_true(
			message_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"目标达成说明应允许自动换行，避免窄屏溢出。"
		)
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(
			summary_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
			"目标达成摘要应允许自动换行，避免窄屏溢出。"
		)


func test_target_reached_menu_summary_uses_status_model() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.set_target_state(2048, true)
	status_model.score.set_value(8192)
	status_model.move_count.set_value(23)
	status_model.highest_tile.set_value(4096)
	await architecture.register_model(GameStatusModel, status_model)
	await architecture.init()

	var context: _TestArchitectureContext = _TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var summary_node: Node = panel.get_node_or_null("CenterContainer/VBoxContainer/SummaryLabel")
	assert_true(summary_node is Label, "目标达成菜单应包含本局目标摘要 Label。")
	if summary_node is Label:
		var summary_label: Label = summary_node
		assert_true(summary_label.text.contains("2048"), "目标摘要应显示目标方块值。")
		assert_true(summary_label.text.contains("8192"), "目标摘要应显示当前分数。")
		assert_true(summary_label.text.contains("23"), "目标摘要应显示当前步数。")
		assert_true(summary_label.text.contains("4096"), "目标摘要应显示当前最大方块。")
	architecture.dispose()


func test_target_reached_menu_buttons_emit_flow_events() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.init()
	var emitted_events: Dictionary = {
		&"resume": 0,
		&"restart": 0,
		&"main_menu": 0,
	}
	architecture.register_simple_event(EventNames.RESUME_GAME_REQUESTED, func(_payload: Variant) -> void:
		emitted_events[&"resume"] = GFVariantData.to_int(emitted_events.get(&"resume", 0), 0) + 1
	)
	architecture.register_simple_event(EventNames.RESTART_GAME_REQUESTED, func(_payload: Variant) -> void:
		emitted_events[&"restart"] = GFVariantData.to_int(emitted_events.get(&"restart", 0), 0) + 1
	)
	architecture.register_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED, func(_payload: Variant) -> void:
		emitted_events[&"main_menu"] = GFVariantData.to_int(emitted_events.get(&"main_menu", 0), 0) + 1
	)

	var context: _TestArchitectureContext = _TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel: Control = _instantiate_control(_TARGET_REACHED_SCENE)
	assert_true(is_instance_valid(panel), "目标达成场景应能实例化为 Control。")
	context.add_child(panel)
	await get_tree().process_frame

	_press_button(panel, "CenterContainer/VBoxContainer/ContinueButton")
	_press_button(panel, "CenterContainer/VBoxContainer/RestartButton")
	_press_button(panel, "CenterContainer/VBoxContainer/MainMenuButton")

	assert_true(_get_event_count(emitted_events, &"resume") == 1, "继续挑战按钮应请求恢复游戏。")
	assert_true(_get_event_count(emitted_events, &"restart") == 1, "重新开始按钮应请求重启当前局。")
	assert_true(_get_event_count(emitted_events, &"main_menu") == 1, "返回主界面按钮应请求从游戏内返回主菜单。")
	architecture.dispose()


func test_board_feedback_utility_spawns_effect_nodes() -> void:
	var board_container: Node2D = Node2D.new()
	add_child_autoqfree(board_container)
	await get_tree().process_frame

	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	var created_count: int = feedback_utility.play_feedback(board_container, Vector2(64.0, 72.0), &"merge", "4")

	assert_gt(created_count, 1, "棋盘反馈应创建粒子和浮动文字。")
	assert_true(board_container.get_child_count() == 1, "反馈节点应挂到棋盘容器下。")

	var feedback_root: Node2D = _get_node2d_child(board_container, 0)
	assert_true(is_instance_valid(feedback_root), "反馈根节点应为 Node2D。")
	assert_true(feedback_root.position == Vector2(64.0, 72.0), "反馈根节点应使用传入局部坐标。")
	assert_true(feedback_root.get_child_count() == created_count, "反馈子节点数量应与返回值一致。")


# --- 私有/辅助方法 ---

func _create_tile() -> Tile:
	var tile: Tile = _instantiate_tile(_TILE_SCENE)
	if not is_instance_valid(tile):
		assert_true(false, "Tile 场景应能实例化为 Tile。")
		return null
	add_child_autoqfree(tile)
	await get_tree().process_frame
	return tile


func _load_shader(path: String) -> Shader:
	var resource: Resource = load(path)
	if resource is Shader:
		var shader: Shader = resource
		return shader
	return null


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _assert_shader_float_default_in_range(
	shader_text: String,
	uniform_name: String,
	min_value: float,
	max_value: float
) -> void:
	var default_value: float = _get_shader_float_default(shader_text, uniform_name, -1.0)
	assert_true(
		default_value >= min_value and default_value <= max_value,
		"%s 默认值 %.3f 应保持在 %.3f 到 %.3f，避免背景变粗糙或刺眼。" % [
			uniform_name,
			default_value,
			min_value,
			max_value,
		]
	)


func _get_shader_float_default(shader_text: String, uniform_name: String, fallback: float) -> float:
	var prefix: String = "uniform float %s " % uniform_name
	var lines: PackedStringArray = shader_text.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if not line.begins_with(prefix):
			continue
		return _parse_shader_default_float(line, fallback)
	return fallback


func _parse_shader_default_float(line: String, fallback: float) -> float:
	var equals_index: int = line.find("=")
	if equals_index == -1:
		return fallback
	var semicolon_index: int = line.find(";", equals_index)
	if semicolon_index == -1:
		semicolon_index = line.length()
	var value_text: String = line.substr(equals_index + 1, semicolon_index - equals_index - 1).strip_edges()
	if not value_text.is_valid_float():
		return fallback
	return float(value_text)


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_stylebox_flat(control: Control, name: StringName) -> StyleBoxFlat:
	var stylebox: StyleBox = control.get_theme_stylebox(name)
	if stylebox is StyleBoxFlat:
		var flat_stylebox: StyleBoxFlat = stylebox
		return flat_stylebox
	return null


func _get_tile_level_style(theme: TileColorScheme, index: int) -> TileLevelStyle:
	if not is_instance_valid(theme):
		return null
	if index < 0 or index >= theme.styles.size():
		return null
	return theme.styles[index]


func _collect_tile_scheme_contrast_issues(
	scheme_name: String,
	scheme: TileColorScheme,
	issues: Array[String]
) -> void:
	if not is_instance_valid(scheme):
		_append_string(issues, "%s 主题资源应能加载。" % scheme_name)
		return

	for index: int in range(scheme.styles.size()):
		var style: TileLevelStyle = _get_tile_level_style(scheme, index)
		if not is_instance_valid(style):
			_append_string(issues, "%s[%d] 应配置 TileLevelStyle。" % [scheme_name, index])
			continue

		var contrast_ratio: float = _get_contrast_ratio(style.background_color, style.font_color)
		if contrast_ratio < _MIN_TILE_TEXT_CONTRAST:
			_append_string(
				issues,
				"%s[%d] 文字对比度 %.2f 低于 %.2f。" % [
					scheme_name,
					index,
					contrast_ratio,
					_MIN_TILE_TEXT_CONTRAST,
				]
			)


func _get_contrast_ratio(left: Color, right: Color) -> float:
	var left_luminance: float = _get_relative_luminance(left)
	var right_luminance: float = _get_relative_luminance(right)
	var lighter: float = left_luminance
	var darker: float = right_luminance
	if right_luminance > left_luminance:
		lighter = right_luminance
		darker = left_luminance
	return (lighter + 0.05) / (darker + 0.05)


func _get_relative_luminance(color: Color) -> float:
	return (
		_get_linear_channel(color.r) * 0.2126
		+ _get_linear_channel(color.g) * 0.7152
		+ _get_linear_channel(color.b) * 0.0722
	)


func _get_linear_channel(value: float) -> float:
	if value <= 0.03928:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _get_node2d_child(parent: Node, index: int) -> Node2D:
	if not is_instance_valid(parent):
		return null
	if index < 0 or index >= parent.get_child_count():
		return null
	var child: Node = parent.get_child(index)
	if child is Node2D:
		var child_node2d: Node2D = child
		return child_node2d
	return null


func _instantiate_tile(scene: PackedScene) -> Tile:
	var instance: Node = scene.instantiate()
	if instance is Tile:
		var tile: Tile = instance
		return tile
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _instantiate_control(scene: PackedScene) -> Control:
	var instance: Node = scene.instantiate()
	if instance is Control:
		var control: Control = instance
		return control
	if is_instance_valid(instance):
		instance.queue_free()
	return null


func _get_color(source: Dictionary, key: StringName) -> Color:
	var value: Variant = source.get(key, source.get(String(key), Color.TRANSPARENT))
	return value if value is Color else Color.TRANSPARENT


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		_append_packed_string(packed, line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _append_packed_string(target: PackedStringArray, value: String) -> void:
	var _append_result: bool = target.append(value)


func _press_button(root: Control, path: NodePath) -> void:
	var node: Node = root.get_node_or_null(path)
	if node is Button:
		var button: Button = node
		button.pressed.emit()


func _get_event_count(events: Dictionary, key: StringName) -> int:
	return GFVariantData.to_int(events.get(key, 0), 0)


# --- 内部类 ---

class _TestArchitectureContext:
	extends GFNodeContext

	var test_architecture: GFArchitecture

	func _enter_tree() -> void:
		pass

	func _exit_tree() -> void:
		test_architecture = null

	func get_architecture() -> GFArchitecture:
		return test_architecture
