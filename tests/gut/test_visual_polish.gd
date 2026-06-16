## 验证第一轮视觉增强资源与 Tile 动画基础行为。
extends GutTest


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://scenes/components/tile.tscn")
const _BACKGROUND_SHADER_PATH: String = "res://resources/shaders/game_background.gdshader"
const _CLASSIC_TILE_THEME: TileColorScheme = preload("res://resources/themes/tile_schemes/classic_tile_theme.tres")


# --- 测试用例 ---

func test_game_background_shader_loads() -> void:
	var shader: Shader = load(_BACKGROUND_SHADER_PATH) as Shader

	assert_true(is_instance_valid(shader), "游戏背景 shader 应能正常加载。")


func test_tile_setup_applies_flat_pop_art_style() -> void:
	var tile: Tile = await _create_tile()

	tile.setup(2048, Tile.TileType.PLAYER, Color(0.8, 0.5, 0.2, 1.0), Color.WHITE)

	var stylebox: StyleBoxFlat = tile.background.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(stylebox, "Tile 背景应使用 StyleBoxFlat。")
	assert_eq(stylebox.shadow_size, 0, "Tile 背景应保持无阴影的平面色块。")
	assert_eq(stylebox.get_border_width(SIDE_TOP), 0, "Tile 背景应保持无描边。")
	assert_eq(stylebox.bg_color, Color(0.8, 0.5, 0.2, 1.0), "Tile 背景应直接使用实心色块。")


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
	var value_2_style: TileLevelStyle = _CLASSIC_TILE_THEME.styles[0] as TileLevelStyle
	var value_4_style: TileLevelStyle = _CLASSIC_TILE_THEME.styles[1] as TileLevelStyle

	assert_eq(
		_get_color(value_2_colors, &"bg"),
		value_2_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块背景色。"
	)
	assert_eq(
		_get_color(value_2_colors, &"font"),
		value_2_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 2 方块字体色。"
	)
	assert_eq(
		_get_color(value_4_colors, &"bg"),
		value_4_style.background_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块背景色。"
	)
	assert_eq(
		_get_color(value_4_colors, &"font"),
		value_4_style.font_color,
		"棋盘表现层不应覆盖资源中配置的 4 方块字体色。"
	)
	controller.free()


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

	assert_eq(motion_utility.bind_interactive_controls(root), 1, "UI 动效 Utility 应递归绑定按钮。")
	assert_eq(motion_utility.bind_interactive_controls(root), 0, "重复绑定不应重复连接同一按钮。")

	var button_style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(button_style, "按钮绑定后应获得统一 StyleBoxFlat。")
	assert_eq(button_style.get_border_width(SIDE_TOP), 0, "统一按钮样式应保持无描边。")
	assert_eq(button_style.shadow_size, 0, "统一按钮样式应保持无阴影。")


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

	assert_eq(motion_utility.play_children_reveal(container), 2, "列表刷新动效应只作用于可见子控件。")
	assert_lt(first_child.modulate.a, 1.0, "可见子控件应从淡入状态开始。")
	assert_lt(second_child.modulate.a, 1.0, "第二个可见子控件也应从淡入状态开始。")
	assert_eq(hidden_child.modulate.a, 1.0, "隐藏子控件不应被动效修改。")


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

	assert_eq(motion_utility.play_children_reveal(container, Vector2(20.0, 0.0)), 2, "容器子控件仍应播放淡入动效。")
	assert_eq(first_child.position, first_position, "VBoxContainer 子控件不应被动效改写位置。")
	assert_eq(second_child.position, second_position, "第二个 VBoxContainer 子控件也不应被动效改写位置。")
	assert_lt(first_child.modulate.a, 1.0, "容器子控件仍应从淡入状态开始。")


func test_board_feedback_utility_spawns_effect_nodes() -> void:
	var board_container: Node2D = Node2D.new()
	add_child_autoqfree(board_container)
	await get_tree().process_frame

	var feedback_utility: GameBoardFeedbackUtility = GameBoardFeedbackUtility.new()
	var created_count: int = feedback_utility.play_feedback(board_container, Vector2(64.0, 72.0), &"merge", "4")

	assert_gt(created_count, 1, "棋盘反馈应创建粒子和浮动文字。")
	assert_eq(board_container.get_child_count(), 1, "反馈节点应挂到棋盘容器下。")

	var feedback_root: Node2D = board_container.get_child(0) as Node2D
	assert_true(is_instance_valid(feedback_root), "反馈根节点应为 Node2D。")
	assert_eq(feedback_root.position, Vector2(64.0, 72.0), "反馈根节点应使用传入局部坐标。")
	assert_eq(feedback_root.get_child_count(), created_count, "反馈子节点数量应与返回值一致。")


# --- 私有/辅助方法 ---

func _create_tile() -> Tile:
	var tile: Tile = _TILE_SCENE.instantiate() as Tile
	add_child_autoqfree(tile)
	await get_tree().process_frame
	return tile


func _get_color(source: Dictionary, key: StringName) -> Color:
	var value: Variant = source.get(key, source.get(String(key), Color.TRANSPARENT))
	return value if value is Color else Color.TRANSPARENT
