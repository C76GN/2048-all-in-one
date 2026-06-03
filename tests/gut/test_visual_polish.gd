## 验证第一轮视觉增强资源与 Tile 动画基础行为。
extends GutTest


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://scenes/components/tile.tscn")
const _BACKGROUND_SHADER_PATH: String = "res://resources/shaders/game_background.gdshader"
const _GAME_UI_MOTION_UTILITY_SCRIPT = preload("res://scripts/utilities/game_ui_motion_utility.gd")
const _GAME_BOARD_FEEDBACK_UTILITY_SCRIPT = preload("res://scripts/utilities/game_board_feedback_utility.gd")


# --- 测试用例 ---

func test_game_background_shader_loads() -> void:
	var shader := load(_BACKGROUND_SHADER_PATH) as Shader

	assert_true(is_instance_valid(shader), "游戏背景 shader 应能正常加载。")


func test_tile_setup_applies_polished_style() -> void:
	var tile: Tile = await _create_tile()

	tile.setup(2048, Tile.TileType.PLAYER, Color(0.8, 0.5, 0.2, 1.0), Color.WHITE)

	var stylebox := tile.background.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(stylebox, "Tile 背景应使用 StyleBoxFlat。")
	assert_gt(stylebox.shadow_size, 0, "Tile 背景应带阴影。")
	assert_gt(stylebox.get_border_width(SIDE_TOP), 0, "Tile 背景应带轻微描边。")


func test_tile_visual_animations_return_live_tweens() -> void:
	var tile: Tile = await _create_tile()
	tile.setup(2, Tile.TileType.PLAYER, Color(0.9, 0.75, 0.45, 1.0), Color.BLACK)

	var spawn_tween := tile.animate_spawn()
	assert_true(is_instance_valid(spawn_tween) and spawn_tween.is_valid(), "生成动画应返回有效 Tween。")

	tile.reset_animation_state()
	var move_tween := tile.animate_move(Vector2(48.0, 32.0))
	assert_true(is_instance_valid(move_tween) and move_tween.is_valid(), "移动动画应返回有效 Tween。")

	tile.reset_animation_state()
	var merge_tween := tile.animate_merge()
	assert_true(is_instance_valid(merge_tween) and merge_tween.is_valid(), "合并动画应返回有效 Tween。")

	tile.reset_animation_state()
	var transform_tween := tile.animate_transform()
	assert_true(is_instance_valid(transform_tween) and transform_tween.is_valid(), "转化动画应返回有效 Tween。")

	tile.reset_animation_state()

func test_ui_motion_utility_binds_buttons_recursively_once() -> void:
	var root := Control.new()
	var container := VBoxContainer.new()
	var button := Button.new()
	root.add_child(container)
	container.add_child(button)
	add_child_autoqfree(root)
	await get_tree().process_frame

	var motion_utility = _GAME_UI_MOTION_UTILITY_SCRIPT.new()

	assert_eq(motion_utility.bind_interactive_controls(root), 1, "UI 动效 Utility 应递归绑定按钮。")
	assert_eq(motion_utility.bind_interactive_controls(root), 0, "重复绑定不应重复连接同一按钮。")


func test_ui_motion_utility_reveals_panel_with_tween() -> void:
	var panel := Control.new()
	panel.position = Vector2(12.0, 20.0)
	panel.scale = Vector2.ONE
	add_child_autoqfree(panel)
	await get_tree().process_frame

	var motion_utility = _GAME_UI_MOTION_UTILITY_SCRIPT.new()
	var tween: Tween = motion_utility.play_panel_intro(panel)

	assert_true(is_instance_valid(tween) and tween.is_valid(), "面板入场应返回有效 Tween。")
	assert_gt(panel.position.y, 20.0, "面板入场起点应带有轻微下移。")
	assert_lt(panel.modulate.a, 1.0, "面板入场起点应先淡入。")


func test_ui_motion_utility_reveals_visible_children_only() -> void:
	var container := VBoxContainer.new()
	var first_child := Button.new()
	var second_child := Label.new()
	var hidden_child := Button.new()
	hidden_child.visible = false
	container.add_child(first_child)
	container.add_child(second_child)
	container.add_child(hidden_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var motion_utility = _GAME_UI_MOTION_UTILITY_SCRIPT.new()

	assert_eq(motion_utility.play_children_reveal(container), 2, "列表刷新动效应只作用于可见子控件。")
	assert_lt(first_child.modulate.a, 1.0, "可见子控件应从淡入状态开始。")
	assert_lt(second_child.modulate.a, 1.0, "第二个可见子控件也应从淡入状态开始。")
	assert_eq(hidden_child.modulate.a, 1.0, "隐藏子控件不应被动效修改。")


func test_ui_motion_utility_does_not_move_container_managed_children() -> void:
	var container := VBoxContainer.new()
	var first_child := Label.new()
	var second_child := Label.new()
	first_child.text = "A"
	second_child.text = "B"
	container.add_child(first_child)
	container.add_child(second_child)
	add_child_autoqfree(container)
	await get_tree().process_frame

	var first_position: Vector2 = first_child.position
	var second_position: Vector2 = second_child.position
	var motion_utility = _GAME_UI_MOTION_UTILITY_SCRIPT.new()

	assert_eq(motion_utility.play_children_reveal(container, Vector2(20.0, 0.0)), 2, "容器子控件仍应播放淡入动效。")
	assert_eq(first_child.position, first_position, "VBoxContainer 子控件不应被动效改写位置。")
	assert_eq(second_child.position, second_position, "第二个 VBoxContainer 子控件也不应被动效改写位置。")
	assert_lt(first_child.modulate.a, 1.0, "容器子控件仍应从淡入状态开始。")


func test_board_feedback_utility_spawns_effect_nodes() -> void:
	var board_container := Node2D.new()
	add_child_autoqfree(board_container)
	await get_tree().process_frame

	var feedback_utility = _GAME_BOARD_FEEDBACK_UTILITY_SCRIPT.new()
	var created_count: int = feedback_utility.play_feedback(board_container, Vector2(64.0, 72.0), &"merge", "4")

	assert_gt(created_count, 1, "棋盘反馈应创建粒子和浮动文字。")
	assert_eq(board_container.get_child_count(), 1, "反馈节点应挂到棋盘容器下。")

	var feedback_root := board_container.get_child(0) as Node2D
	assert_true(is_instance_valid(feedback_root), "反馈根节点应为 Node2D。")
	assert_eq(feedback_root.position, Vector2(64.0, 72.0), "反馈根节点应使用传入局部坐标。")
	assert_eq(feedback_root.get_child_count(), created_count, "反馈子节点数量应与返回值一致。")


# --- 私有/辅助方法 ---

func _create_tile() -> Tile:
	var tile := _TILE_SCENE.instantiate() as Tile
	add_child_autoqfree(tile)
	await get_tree().process_frame
	return tile
