## 验证回放过程时间带与书签冻结样张抽屉的有界、可操作 UI 合同。
extends GutTest


# --- 常量 ---

const _GAME_SCENE: PackedScene = preload(
	"res://features/game_session/scenes/game/game_play.tscn"
)
const _BOOKMARK_LIST_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
)
const _BOOKMARK_ITEM_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/ui/bookmark_list_item.tscn"
)
const _RATIO_MODE_CONFIG: GameModeConfig = preload(
	"res://features/gameplay/resources/modes/ratio_mode_config.tres"
)
const _MODE_VISUAL_PROFILE_REGISTRY: GameModeVisualProfileRegistry = preload(
	"res://features/themes/resources/themes/mode_visuals/default_mode_visual_profile_registry.tres"
)
const _REPLAY_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/game_session/resources/input/replay_input_context.tres"
)
const _ACTION_REPLAY_PREV_STEP: StringName = &"replay_prev_step"
const _ACTION_REPLAY_NEXT_STEP: StringName = &"replay_next_step"


# --- 测试用例 ---

func test_replay_timeline_keeps_marker_projection_bounded_and_semantic() -> void:
	var timeline: ReplayTimeline = ReplayTimeline.new()
	var markers: Array[ReplayMarker] = []
	for step_index: int in range(128):
		markers.append(ReplayMarker.new(ReplayMarker.Kind.MERGE, step_index))
	markers.append(ReplayMarker.new(ReplayMarker.Kind.OOS, 50))

	timeline.configure(ReplayData.MAX_STEP_COUNT + 10, markers)
	var notches: Array[Dictionary] = timeline.get_visible_notches()

	assert_lte(
		notches.size(),
		ReplayTimeline.MAX_VISIBLE_NOTCHES,
		"长回放的视觉刻度必须保持固定上界。"
	)
	assert_true(
		_has_marker_kind(notches, ReplayMarker.Kind.OOS),
		"视觉桶碰撞时必须保留 OOS 等高优先级语义。"
	)
	assert_true(
		is_equal_approx(timeline.max_value, float(ReplayData.MAX_STEP_COUNT)),
		"时间带必须复用回放业务容量边界。"
	)
	timeline.free()


func test_replay_timeline_emits_selection_without_owning_playback_state() -> void:
	var timeline: ReplayTimeline = ReplayTimeline.new()
	var requested_steps: Array[int] = []
	var _request_connection: int = timeline.step_requested.connect(
		func(step_index: int) -> void:
			requested_steps.append(step_index)
	)
	timeline.configure(12, [])
	timeline.set_progress(2)
	timeline.set_interaction_enabled(true)
	timeline.value = 7.0

	assert_true(timeline.request_selected_step())
	assert_true(requested_steps == [7], "控件只应发布选择，由 ReplaySystem 验证跳转。")
	timeline.set_interaction_enabled(false)
	assert_false(timeline.request_selected_step(), "OOS 或跳转期间必须冻结时间带交互。")
	timeline.free()


func test_replay_timeline_gui_navigation_selects_then_confirm_commits_once() -> void:
	var timeline: ReplayTimeline = ReplayTimeline.new()
	timeline.position = Vector2(24.0, 24.0)
	timeline.size = Vector2(420.0, 44.0)
	add_child_autoqfree(timeline)
	timeline.configure(12, [])
	timeline.set_progress(5)
	timeline.set_interaction_enabled(true)
	var requested_steps: Array[int] = []
	var _request_connection: int = timeline.step_requested.connect(
		func(step_index: int) -> void:
			requested_steps.append(step_index)
	)

	timeline.grab_focus()
	await get_tree().process_frame
	assert_true(timeline.has_focus(), "时间带必须先取得真实 GUI 焦点。")

	await _dispatch_key_event(KEY_LEFT)
	assert_true(
		requested_steps.is_empty() and roundi(timeline.value) == 4,
		"键盘左键只应移动候选值，不能自动提交跳转。"
	)
	await _dispatch_key_event(KEY_RIGHT)
	assert_true(
		requested_steps.is_empty() and roundi(timeline.value) == 5,
		"键盘右键只应移动候选值，不能自动提交跳转。"
	)
	await _dispatch_joy_button_event(JOY_BUTTON_DPAD_LEFT)
	assert_true(
		requested_steps.is_empty() and roundi(timeline.value) == 4,
		"手柄左导航只应移动候选值，不能进入全局 transport。"
	)
	await _dispatch_joy_button_event(JOY_BUTTON_DPAD_RIGHT)
	assert_true(
		requested_steps.is_empty() and roundi(timeline.value) == 5,
		"手柄右导航只应移动候选值，不能进入全局 transport。"
	)
	await _dispatch_key_event(KEY_RIGHT)
	await _dispatch_joy_button_event(JOY_BUTTON_A)
	await get_tree().process_frame
	assert_true(
		requested_steps == [6],
		"ui_accept 必须且只能提交一次当前候选步骤。"
	)


func test_replay_transport_context_does_not_claim_gui_navigation_or_confirm() -> void:
	var gui_events: Array[InputEvent] = [
		_make_key_event(KEY_LEFT),
		_make_key_event(KEY_RIGHT),
		_make_key_event(KEY_ENTER),
		_make_key_event(KEY_SPACE),
		_make_joy_button_event(JOY_BUTTON_DPAD_LEFT),
		_make_joy_button_event(JOY_BUTTON_DPAD_RIGHT),
		_make_joy_button_event(JOY_BUTTON_A),
		_make_joy_axis_event(JOY_AXIS_LEFT_X, -1.0),
		_make_joy_axis_event(JOY_AXIS_LEFT_X, 1.0),
	]
	for event: InputEvent in gui_events:
		assert_false(
			_context_action_matches_event(_ACTION_REPLAY_PREV_STEP, event)
			or _context_action_matches_event(_ACTION_REPLAY_NEXT_STEP, event),
			"标准 GUI 导航/确认事件不得同时映射到全局回放步进。"
		)

	assert_true(
		_context_action_matches_event(
			_ACTION_REPLAY_PREV_STEP,
			_make_physical_key_event(KEY_A)
		),
		"专用即时 transport 键 A 必须保留。"
	)
	assert_true(
		_context_action_matches_event(
			_ACTION_REPLAY_NEXT_STEP,
			_make_physical_key_event(KEY_D)
		),
		"专用即时 transport 键 D 必须保留。"
	)


func test_game_scene_preserves_exact_marker_fallback_and_touch_focus_contract() -> void:
	var scene: Node = _GAME_SCENE.instantiate()
	var timeline: ReplayTimeline = scene.find_child(
		"ReplayTimeline",
		true,
		false
	) as ReplayTimeline
	var marker_picker: OptionButton = scene.find_child(
		"ReplayMarkerPicker",
		true,
		false
	) as OptionButton

	assert_not_null(timeline, "回放播放控制必须包含过程时间带。")
	assert_not_null(marker_picker, "精确 marker 文本选择器必须继续作为可访问回退。")
	if is_instance_valid(timeline):
		assert_gte(timeline.custom_minimum_size.y, 44.0)
		assert_false(timeline.focus_neighbor_bottom.is_empty())
	assert_null(scene.find_child("ReplaySpeedButton", true, false), "不得引入不支持的倍速。")
	scene.free()


func test_bookmark_stamp_caps_board_work_at_persisted_cell_limit() -> void:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(17, 16))
	var stamp: BookmarkBoardStamp = BookmarkBoardStamp.new()
	stamp.configure({
		&"topology": topology.to_dict(),
		&"tiles": [],
	}, null)

	assert_true(
		stamp.get_rendered_cell_count() == BookmarkData.PERSISTED_BOARD_CELL_LIMIT,
		"样张即使收到超出书签 schema 的内存拓扑，也不得无界绘制。"
	)
	stamp.free()


func test_bookmark_stamp_preserves_definition_color_for_equal_ratio_values() -> void:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(2, 1))
	var stamp: BookmarkBoardStamp = BookmarkBoardStamp.new()
	var theme_utility: GameThemeUtility = GameThemeUtility.new()
	theme_utility._mode_visual_profile_registry = _MODE_VISUAL_PROFILE_REGISTRY
	stamp.configure({
		&"topology": topology.to_dict(),
		&"tiles": [
			{
				&"pos": Vector2i(0, 0),
				&"value": 4,
				&"definition_id": &"tile.ratio.base",
			},
			{
				&"pos": Vector2i(1, 0),
				&"value": 4,
				&"definition_id": &"tile.ratio.factor",
			},
		],
	}, _RATIO_MODE_CONFIG, theme_utility)

	var base_color: Variant = stamp._tile_color_by_cell.get(Vector2i(0, 0))
	var factor_color: Variant = stamp._tile_color_by_cell.get(Vector2i(1, 0))
	assert_true(base_color is Color and factor_color is Color)
	if not base_color is Color or not factor_color is Color:
		stamp.free()
		return
	var base_tile_color: Color = base_color
	var factor_tile_color: Color = factor_color
	assert_false(
		base_tile_color == factor_tile_color,
		"相同数值的 Ratio base/factor 方块必须保留各自定义的色板身份。"
	)
	stamp.free()


func test_bookmark_drawer_uses_board_first_cards_and_conventional_danger() -> void:
	var item: Node = _BOOKMARK_ITEM_SCENE.instantiate()
	var stamp: Node = item.find_child("BoardStamp", true, false)
	assert_true(stamp is BookmarkBoardStamp, "书签卡片的主要浏览对象必须是棋盘样张。")
	var score: Node = item.find_child("ScoreLabel", true, false)
	var info_column: Node = item.find_child("VBoxContainer", true, false)
	assert_true(
		score is Label
		and info_column is VBoxContainer
		and score.get_parent() == info_column,
		"分数应归入元数据列，不能横向挤压双列卡片的模式和时间文本。"
	)
	assert_gte((item as Control).custom_minimum_size.y, 180.0)
	item.free()

	var page: Node = _BOOKMARK_LIST_SCENE.instantiate()
	var grid: GridContainer = page.find_child("ItemsContainer", true, false) as GridContainer
	var delete_button: Button = page.find_child("DeleteButton", true, false) as Button
	assert_not_null(grid, "最多 16 条书签应使用有界样张抽屉网格。")
	if is_instance_valid(grid):
		assert_true(grid.columns == 2)
	assert_not_null(delete_button, "危险删除必须继续使用清楚的传统按钮。")
	page.free()


# --- 私有/辅助方法 ---

func _has_marker_kind(notches: Array[Dictionary], marker_kind: int) -> bool:
	for notch: Dictionary in notches:
		if GFVariantData.get_option_int(notch, &"kind", -1) == marker_kind:
			return true
	return false


func _dispatch_key_event(keycode: Key) -> void:
	Input.parse_input_event(_make_key_event(keycode))
	await get_tree().process_frame
	var release_event: InputEventKey = _make_key_event(keycode)
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await get_tree().process_frame


func _dispatch_joy_button_event(button_index: JoyButton) -> void:
	Input.parse_input_event(_make_joy_button_event(button_index))
	await get_tree().process_frame
	var release_event: InputEventJoypadButton = _make_joy_button_event(button_index)
	release_event.pressed = false
	release_event.pressure = 0.0
	Input.parse_input_event(release_event)
	await get_tree().process_frame


func _context_action_matches_event(action_id: StringName, event: InputEvent) -> bool:
	for mapping: GFInputMapping in _REPLAY_INPUT_CONTEXT.mappings:
		if mapping == null or mapping.get_action_id() != action_id:
			continue
		for binding: GFInputBinding in mapping.bindings:
			if binding != null and binding.matches_event(event):
				return true
	return false


func _make_key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _make_physical_key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _make_joy_button_event(button_index: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	event.pressure = 1.0
	return event


func _make_joy_axis_event(axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	return event
