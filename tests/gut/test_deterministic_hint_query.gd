## 验证项目级提示查询保持只读、确定性、预算边界与 HUD 绑定。
extends GutTest


# --- 常量 ---

const _HUD_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/hud.tscn"
)
const GameHintResultType = preload(
	"res://features/gameplay/scripts/data/game_hint_result.gd"
)
const DeterministicHintQueryType = preload(
	"res://features/gameplay/scripts/queries/deterministic_hint_query.gd"
)
const _GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/gameplay/resources/input/gameplay_input_context.tres"
)
const _HUD_SCRIPT_PATH: String = "res://features/gameplay/scripts/ui/hud.gd"
const _PLAYER_INPUT_SCRIPT_PATH: String = (
	"res://features/gameplay/scripts/systems/player_input_system.gd"
)
const _MODE_PATHS: PackedStringArray = [
	"res://features/gameplay/resources/modes/classic_mode_config.tres",
	"res://features/gameplay/resources/modes/step_by_step_mode_config.tres",
	"res://features/gameplay/resources/modes/ratio_mode_config.tres",
	"res://features/gameplay/resources/modes/progressive_mode_config.tres",
	"res://features/gameplay/resources/modes/fibonacci_mode_config.tres",
	"res://features/gameplay/resources/modes/lucas_fibonacci_mode_config.tres",
]


# --- 测试用例 ---

func test_hint_query_is_read_only_and_does_not_advance_authoritative_rng() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(4, 4)),
		[
			_make_tile(Vector2i(0, 0), 2, &"tile.classic.numeric", 1000),
			_make_tile(Vector2i(0, 1), 2, &"tile.classic.numeric", 1001),
			_make_tile(Vector2i(2, 3), 8, &"tile.classic.numeric", 1002),
		]
	)
	var snapshot_before: Dictionary = snapshot.duplicate(true)
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	var rng_before: Dictionary = seed_utility.get_full_state()

	var result: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		&"snapshot-read-only",
		_make_budget()
	)

	assert_true(snapshot == snapshot_before, "提示查询不得修改输入快照或其中的嵌套容器。")
	assert_true(
		seed_utility.get_full_state() == rng_before,
		"提示查询不得推进项目权威 GFSeedUtility 状态。"
	)
	assert_true(result.is_cardinal_direction(), "有效快照必须返回四向建议之一。")
	assert_true(
		result.termination_reason == GameHintResultType.TERMINATION_COMPLETED,
		"小型棋盘应在预算内完整分析。"
	)
	assert_gt(result.nodes_evaluated, 0, "结果必须报告实际评估节点数。")
	assert_false(result.explanation.is_empty(), "结果必须包含可读的主要因素解释。")
	assert_true(result.direction_scores.size() == 4, "完整结果应保留四向评分以便审计。")
	seed_utility.dispose()


func test_same_snapshot_and_budget_produce_identical_hint() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(3, 2)),
		[
			_make_tile(Vector2i(0, 0), 3, &"tile.fibonacci", 1100),
			_make_tile(Vector2i(2, 0), 5, &"tile.fibonacci", 1101),
			_make_tile(Vector2i(1, 1), 8, &"tile.fibonacci", 1102),
		]
	)
	var first: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		"snapshot-deterministic",
		_make_budget()
	)
	var second: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot.duplicate(true),
		"snapshot-deterministic",
		_make_budget()
	)

	assert_true(
		first.to_dict() == second.to_dict(),
		"相同快照、摘要和手动时钟预算必须产生逐字段相同的提示。"
	)


func test_step_deadline_and_cancellation_have_stable_termination_reasons() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(4, 4)),
		[_make_tile(Vector2i(3, 3), 2, &"tile.classic.numeric", 1200)]
	)
	var step_limited: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		"snapshot-step",
		_make_budget(1, 100)
	)
	assert_true(
		step_limited.termination_reason == GameHintResultType.TERMINATION_STEP_LIMIT,
		"max_steps 必须硬终止分析并保留 GF 稳定原因。"
	)
	assert_true(step_limited.is_cardinal_direction(), "预算降级仍必须返回四向之一。")

	var deadline_clock: GFManualClock = GFManualClock.new()
	var deadline_budget: GFExecutionBudget = GFExecutionBudget.new({
		&"max_steps": 1000,
		&"max_elapsed_msec": 5,
	}, deadline_clock)
	var _advanced: bool = deadline_clock.advance_msec(6)
	var deadline_limited: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		"snapshot-deadline",
		deadline_budget
	)
	assert_true(
		deadline_limited.termination_reason == GameHintResultType.TERMINATION_TIME_LIMIT,
		"超过硬 deadline 后不得继续扫描快照。"
	)
	assert_true(deadline_limited.elapsed_msec == 6, "结果应报告 GFExecutionBudget 的实际耗时。")

	var cancellation_source: GFCancellationSource = GFCancellationSource.new()
	var _cancelled: bool = cancellation_source.cancel(&"test_cancel")
	var cancelled: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		"snapshot-cancelled",
		GFExecutionBudget.new({
			&"max_steps": 1000,
			&"max_elapsed_msec": 100,
			&"cancel_token": cancellation_source.get_token(),
		}, GFManualClock.new())
	)
	assert_true(
		cancelled.termination_reason == GameHintResultType.TERMINATION_CANCELLED,
		"GFCancellationToken 必须在首次预算检查时终止分析。"
	)
	assert_false(
		cancelled.can_display_for("snapshot-cancelled"),
		"取消结果不得成为玩家可见建议。"
	)
	cancellation_source.dispose()


func test_freshness_rejects_result_after_snapshot_id_changes() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(2, 2)),
		[_make_tile(Vector2i(1, 1), 2, &"tile.classic.numeric", 1300)]
	)
	var result: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		snapshot,
		"snapshot-before-move",
		_make_budget()
	)

	assert_true(result.can_display_for("snapshot-before-move"))
	assert_false(
		result.can_display_for("snapshot-after-move"),
		"当前棋盘摘要变化后，旧提示不得显示或被当作可执行建议。"
	)


func test_all_six_modes_and_sparse_topology_share_generic_fallback() -> void:
	var topology: BoardTopology = BoardTopology.create_custom(
		[
			Vector2i(0, 0),
			Vector2i(2, 0),
			Vector2i(3, 0),
			Vector2i(0, 2),
			Vector2i(1, 2),
		],
		&"board.test.hint_sparse"
	)
	var snapshot: Dictionary = _make_snapshot(
		topology,
		[
			_make_tile(Vector2i(3, 0), 3, &"tile.generic.a", 1400),
			_make_tile(Vector2i(0, 2), 7, &"tile.generic.b", 1401),
		]
	)

	for mode_path: String in _MODE_PATHS:
		var mode_value: Resource = load(mode_path)
		assert_true(mode_value is GameModeConfig, "%s 应可加载为模式配置。" % mode_path)
		var result: GameHintResultType = DeterministicHintQueryType.new().evaluate(
			snapshot,
			"snapshot-generic-fallback",
			_make_budget()
		)
		assert_true(result.is_cardinal_direction(), "%s 必须获得通用四向降级。" % mode_path)
		assert_true(
			result.termination_reason == GameHintResultType.TERMINATION_COMPLETED,
			"%s 不应要求提示查询认识模式专用规则。" % mode_path
		)


func test_hud_scene_and_input_context_bind_hint_across_devices() -> void:
	var hud_root: Node = _HUD_SCENE.instantiate()
	var hint_button: Button = hud_root.get_node_or_null("%HintButton")
	var result_panel: PanelContainer = hud_root.get_node_or_null("%HintResultPanel")
	var result_label: RichTextLabel = hud_root.get_node_or_null("%HintResultLabel")
	assert_not_null(hint_button, "HUD 必须暴露可触摸的 HintButton。")
	assert_not_null(result_panel, "HUD 必须提供独立提示结果面板。")
	assert_not_null(result_label, "HUD 必须提供可读结果文本。")
	if hint_button != null:
		assert_true(hint_button.visible, "HintButton 默认必须可见。")
		assert_true(
			hint_button.custom_minimum_size.x >= 44.0
			and hint_button.custom_minimum_size.y >= 44.0,
			"触摸目标不得小于 44x44。"
		)
	if result_panel != null:
		assert_false(result_panel.visible, "没有 fresh 结果时不得显示结果面板。")
	hud_root.free()

	var input_mapping: GFInputMappingUtility = GFInputMappingUtility.new()
	input_mapping.enable_context(_GAMEPLAY_INPUT_CONTEXT, 100)
	input_mapping.handle_input_event(_make_key_event(KEY_H))
	assert_true(
		input_mapping.consume_action(GameplayInputActions.REQUEST_HINT),
		"H 键必须进入现有 gameplay 输入上下文。"
	)
	input_mapping.clear_input_state()
	input_mapping.handle_input_event(_make_joy_button(JOY_BUTTON_LEFT_SHOULDER))
	assert_true(
		input_mapping.consume_action(GameplayInputActions.REQUEST_HINT),
		"手柄左肩键必须进入同一个提示动作。"
	)

	var hud_source: String = FileAccess.get_file_as_string(_HUD_SCRIPT_PATH)
	var player_input_source: String = FileAccess.get_file_as_string(
		_PLAYER_INPUT_SCRIPT_PATH
	)
	assert_true(
		hud_source.contains(
			"_get_button_node(\"%HintButton\"): GameplayInputActions.REQUEST_HINT"
		),
		"触摸按钮必须复用 HUD 虚拟输入源，而不是直接修改棋盘。"
	)
	assert_true(
		player_input_source.contains("send_simple_event(EventNames.HINT_REQUESTED)"),
		"PlayerInputSystem 必须把统一提示动作转为只读请求事件。"
	)


# --- 私有/辅助方法 ---

func _make_budget(
	max_steps: int = DeterministicHintQueryType.DEFAULT_MAX_STEPS,
	max_elapsed_msec: int = 100
) -> GFExecutionBudget:
	return GFExecutionBudget.new({
		&"max_steps": max_steps,
		&"max_elapsed_msec": max_elapsed_msec,
	}, GFManualClock.new())


func _make_snapshot(
	topology: BoardTopology,
	tiles: Array[Dictionary]
) -> Dictionary:
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": tiles,
	}


func _make_tile(
	position: Vector2i,
	value: int,
	definition_id: StringName,
	timestamp_msec: int
) -> Dictionary:
	return {
		&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": GFUuid.generate_v7(timestamp_msec),
		&"definition_id": definition_id,
		&"value": value,
		&"capability_recipe_ids": [&"tile.recipe.hint_fixture"],
		&"capability_state": {},
		&"pos": position,
	}


func _make_key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.physical_keycode = keycode
	return event


func _make_joy_button(button_index: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.pressed = true
	event.pressure = 1.0
	event.button_index = button_index
	return event
