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


func test_hint_worker_uses_pure_snapshot_and_gf_background_work() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(4, 4)),
		[
			_make_tile(Vector2i(0, 0), 2, &"tile.classic.numeric", 1150),
			_make_tile(Vector2i(0, 1), 2, &"tile.classic.numeric", 1151),
		]
	)
	var snapshot_before: Dictionary = snapshot.duplicate(true)
	var background_work: GFBackgroundWorkUtility = GFBackgroundWorkUtility.new()
	background_work.init()
	var worker: DeterministicHintWorker = DeterministicHintWorker.new()
	var task: GFBackgroundWorkTask = background_work.submit_cpu_work(
		Callable(worker, "run"),
		{
			&"board_snapshot": snapshot,
			&"snapshot_id": "snapshot-background",
			&"generation": 7,
			&"max_steps": DeterministicHintQueryType.DEFAULT_MAX_STEPS,
		},
		Callable(),
		{&"id": &"test-gameplay-hint:7"}
	)
	for _frame: int in range(240):
		background_work.tick(0.0)
		if task.is_finished():
			break
		await get_tree().process_frame
	assert_true(task.status == GFBackgroundWorkTask.Status.COMPLETED)
	var payload: Dictionary = GFVariantData.as_dictionary(task.result)
	var result: GameHintResultType = GameHintResultType.from_dict(
		GFVariantData.get_option_dictionary(payload, &"result")
	)
	assert_not_null(result)
	assert_true(snapshot == snapshot_before, "后台提示不得修改调用方快照。")
	assert_true(
		GFVariantData.get_option_int(payload, &"generation") == 7
		and result != null
		and result.can_display_for("snapshot-background"),
		"后台结果必须携带稳定 generation，并可由主线程 freshness 复核。"
	)
	assert_true(
		result != null and result.elapsed_msec == 0,
		"纯步数预算的后台提示不得把线程调度耗时写入确定性结果。"
	)
	background_work.dispose()


func test_hint_worker_cooperatively_stops_when_background_work_is_cancelled() -> void:
	var snapshot: Dictionary = _make_snapshot(
		BoardTopology.create_rectangle(Vector2i(16, 16)),
		[_make_tile(Vector2i(15, 15), 2, &"tile.classic.numeric", 1175)]
	)
	var cancellation_token: GFCancellationToken = (
		DeterministicHintWorker.create_cancellation_token()
	)
	var worker: DeterministicHintWorker = DeterministicHintWorker.new()
	var _cancelled_before_run: bool = DeterministicHintWorker.request_cancellation(
		cancellation_token,
		&"superseded_hint"
	)
	var payload: Dictionary = worker.run({
		&"board_snapshot": snapshot,
		&"snapshot_id": "snapshot-cancelled-background",
		&"generation": 8,
		&"max_steps": 12_000,
		&"cancel_token": cancellation_token,
	})
	var result: GameHintResultType = GameHintResultType.from_dict(
		GFVariantData.get_option_dictionary(payload, &"result")
	)
	assert_not_null(result)
	assert_true(
		result != null
		and result.termination_reason == GameHintResultType.TERMINATION_CANCELLED,
		"后台 Worker 必须把共享 GFCancellationToken 绑定到执行预算并停止扫描。"
	)
	assert_true(
		result != null and result.nodes_evaluated == 0,
		"预先取消的后台提示不得继续占用任何确定性搜索步数。"
	)

	var background_work: GFBackgroundWorkUtility = GFBackgroundWorkUtility.new()
	background_work.max_threaded_tasks = 1
	background_work.init()
	var running_token: GFCancellationToken = (
		DeterministicHintWorker.create_cancellation_token()
	)
	var cancellation_probe: _CancellationProbeWorker = _CancellationProbeWorker.new()
	var cancelled_task: GFBackgroundWorkTask = background_work.submit_cpu_work(
		Callable(cancellation_probe, "run"),
		{
			&"cancel_token": running_token,
		},
		Callable(),
		{
			&"id": &"test-gameplay-hint:cancelled",
			&"allow_object_payloads": true,
		}
	)
	assert_true(
		cancelled_task.status == GFBackgroundWorkTask.Status.RUNNING,
		"取消回归必须启动一个真实 CPU 工作。"
	)
	for _frame: int in range(120):
		if DeterministicHintWorker.get_cancellation_poll_count(running_token) > 0:
			break
		await get_tree().process_frame
	assert_true(
		DeterministicHintWorker.get_cancellation_poll_count(running_token) > 0,
		"必须等 Worker 在线程内轮询一次令牌后才能请求取消。"
	)
	var _token_cancelled: bool = DeterministicHintWorker.request_cancellation(
		running_token,
		&"superseded_hint"
	)
	var _work_cancelled: bool = background_work.cancel_work(
		cancelled_task.work_id
	)
	var successor: GFBackgroundWorkTask = background_work.submit_cpu_work(
		Callable(worker, "run"),
		{
			&"board_snapshot": _make_snapshot(
				BoardTopology.create_rectangle(Vector2i(2, 2)),
				[_make_tile(Vector2i(1, 1), 2, &"tile.classic.numeric", 1176)]
			),
			&"snapshot_id": "snapshot-after-cancel",
			&"generation": 10,
			&"max_steps": 12_000,
		},
		Callable(),
		{&"id": &"test-gameplay-hint:successor"}
	)
	for _frame: int in range(240):
		background_work.tick(0.0)
		if cancelled_task.is_finished() and successor.is_finished():
			break
		await get_tree().process_frame
	assert_true(
		cancelled_task.status == GFBackgroundWorkTask.Status.CANCELLED,
		"运行中取消必须让原任务抵达唯一 cancelled 终态。"
	)
	assert_true(
		DeterministicHintWorker.was_cancellation_observed(running_token),
		"Worker 必须在线程内观察到主线程取消，而不是自然结束后被动改终态。"
	)
	assert_true(
		successor.status == GFBackgroundWorkTask.Status.COMPLETED,
		"原查询合作式退出后，单线程后台槽必须及时交给后继提示。"
	)
	background_work.dispose()


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
	assert_false(
		deadline_limited.can_display_for("snapshot-deadline"),
		"墙钟截止受设备负载影响，部分评分不得成为玩家可见的确定性建议。"
	)

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
	assert_false(
		hud_source.contains("_HINT_MAX_ELAPSED_MSEC"),
		"玩家可见提示只能由确定的步数预算决定，不能由墙钟截止选择方向。"
	)
	assert_true(
		hud_source.contains("submit_cpu_work(")
		and hud_source.contains("_background_work.cancel_work(task.work_id)")
		and hud_source.contains("DeterministicHintWorker.request_cancellation(")
		and hud_source.contains("&\"cancel_token\": _hint_cancel_token")
		and hud_source.contains("&\"allow_object_payloads\": true")
		and hud_source.contains("snapshot_id != _calculate_current_snapshot_id()")
		and hud_source.contains("_cancel_hint_query(&\"hud_state_changed\")")
		and hud_source.contains("_cancel_hint_query(&\"hud_exited\")"),
		"HUD 必须把纯快照提示交给 GF 后台工作，并在取消与主线程 freshness 复核后应用。"
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


# --- 内部类 ---

## 持续轮询生产取消令牌，直到真正观察到跨线程取消。
class _CancellationProbeWorker extends RefCounted:
	## @param input_data: 包含生产线程安全取消令牌的测试载荷。
	func run(input_data: Variant) -> Dictionary:
		var payload: Dictionary = GFVariantData.as_dictionary(input_data)
		var token_value: Variant = GFVariantData.get_option_value(
			payload,
			&"cancel_token"
		)
		if not token_value is GFCancellationToken:
			return {&"observed_cancel": false}
		var token: GFCancellationToken = token_value
		for _poll: int in range(5_000):
			if token.is_cancel_requested():
				return {&"observed_cancel": true}
			OS.delay_msec(1)
		return {&"observed_cancel": false}
