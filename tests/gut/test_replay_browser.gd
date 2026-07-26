## 验证回放事件标记、确定性跳转边界与播放页可操作性。
extends GutTest


# --- 常量 ---

const _GAME_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/game/game_play.tscn"
)
const _REPLAY_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/replays/resources/input/replay_input_context.tres"
)
const _CLASSIC_DEFINITION_PATH: String = (
	"res://features/gameplay/resources/tiles/definitions/classic_numeric_tile.tres"
)


# --- 测试用例 ---

func test_checkpoint_v2_round_trip_preserves_turn_metadata() -> void:
	var checkpoint: ReplayCheckpoint = _make_checkpoint(1, 16)
	checkpoint.metadata_available = true
	checkpoint.merge_count = 2
	checkpoint.transform_count = 1
	checkpoint.ratio_resolution_count = 1
	checkpoint.max_merge_value = 16
	checkpoint.highest_tile = 128
	checkpoint.target_reached = true

	var restored: ReplayCheckpoint = ReplayCheckpoint.from_dict(checkpoint.to_dict())

	assert_not_null(restored, "checkpoint v2 应通过严格 schema 往返。")
	if restored == null:
		return
	assert_true(restored.metadata_available, "强类型回合摘要可用性必须持久化。")
	assert_true(restored.merge_count == 2, "合并次数必须持久化。")
	assert_true(restored.transform_count == 1, "变换次数必须持久化。")
	assert_true(restored.ratio_resolution_count == 1, "连锁语义计数必须持久化。")
	assert_true(restored.max_merge_value == 16, "最大合并值必须持久化。")
	assert_true(restored.highest_tile == 128, "最高方块里程碑上下文必须持久化。")
	assert_true(restored.target_reached, "目标达成状态必须持久化。")


func test_checkpoint_rejects_obsolete_and_unknown_schemas_atomically() -> void:
	var current: Dictionary = _make_checkpoint(1, 4).to_dict()
	var obsolete: Dictionary = current.duplicate(true)
	obsolete[&"schema_version"] = ReplayCheckpoint.SCHEMA_VERSION - 1
	var unknown: Dictionary = current.duplicate(true)
	unknown[&"schema_version"] = ReplayCheckpoint.SCHEMA_VERSION + 1

	var obsolete_result: ReplayCheckpoint = ReplayCheckpoint.from_dict(obsolete)
	var unknown_result: ReplayCheckpoint = ReplayCheckpoint.from_dict(unknown)

	assert_null(obsolete_result, "旧 checkpoint schema 必须整体拒绝，不得构造降级对象。")
	assert_null(unknown_result, "未知 checkpoint schema 必须整体拒绝，不得构造部分对象。")


func test_marker_catalog_generates_merge_chain_milestone_and_failure_stably() -> void:
	var replay: ReplayData = ReplayData.new()
	replay.actions = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	var first: ReplayCheckpoint = _make_checkpoint(1, 4)
	first.metadata_available = true
	first.merge_count = 1
	first.max_merge_value = 4
	first.highest_tile = 4
	var second: ReplayCheckpoint = _make_checkpoint(2, 20)
	second.metadata_available = true
	second.merge_count = 2
	second.transform_count = 1
	second.ratio_resolution_count = 1
	second.max_merge_value = 16
	second.highest_tile = 16
	var third: ReplayCheckpoint = _make_checkpoint(3, 20)
	third.metadata_available = true
	third.highest_tile = 2048
	third.target_reached = true
	var fourth: ReplayCheckpoint = _make_checkpoint(4, 20)
	fourth.metadata_available = true
	fourth.highest_tile = 2048
	fourth.target_reached = true
	replay.checkpoints = [first, second, third, fourth]

	var markers: Array[ReplayMarker] = ReplayMarker.build_catalog(replay)
	var repeated: Array[ReplayMarker] = ReplayMarker.build_catalog(replay)

	assert_true(markers.size() == 5, "应生成两次合并、一次连锁/变换、一次里程碑和一次失败标记。")
	assert_true(_marker_kinds(markers) == [
		ReplayMarker.Kind.MERGE,
		ReplayMarker.Kind.MERGE,
		ReplayMarker.Kind.CHAIN_OR_TRANSFORM,
		ReplayMarker.Kind.MILESTONE,
		ReplayMarker.Kind.FAILURE,
	], "标记应按步数和语义优先级稳定排序。")
	assert_true(_marker_ids(markers) == _marker_ids(repeated), "同一回放反复生成的标记 ID 必须稳定。")
	assert_true(markers[2].step_index == 2, "连锁/变换标记必须定位到真实回合。")
	assert_true(markers[3].milestone_value == 2048, "里程碑必须保留达成值。")


func test_marker_catalog_does_not_infer_events_without_current_metadata() -> void:
	var replay: ReplayData = ReplayData.new()
	replay.actions = [Vector2i.LEFT, Vector2i.RIGHT]
	var first: ReplayCheckpoint = _make_checkpoint(1, 4)
	first.metadata_available = false
	var second: ReplayCheckpoint = _make_checkpoint(2, 1004)
	second.metadata_available = false
	replay.checkpoints = [first, second]

	var markers: Array[ReplayMarker] = ReplayMarker.build_catalog(replay)

	assert_true(
		ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.MERGE) == 0,
		"缺少当前强类型摘要时不得从 score delta 猜测合并语义。"
	)
	assert_true(
		ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.MILESTONE) == 0,
		"缺少当前强类型摘要时不得生成降级里程碑。"
	)
	var last_marker: ReplayMarker = markers.back()
	assert_true(last_marker.kind == ReplayMarker.Kind.FAILURE, "已保存回放末步必须有失败标记。")


func test_replay_marker_navigation_obeys_boundaries_and_oos_blocking() -> void:
	var history: GFCommandHistoryUtility = _make_history(2)
	var replay: ReplayData = _make_navigation_replay()
	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._command_history = history
	replay_system.activate_replay_mode(replay)

	assert_true(replay_system.get_current_step() == 2, "夹具应位于第 2 步。")
	var previous_index: int = replay_system.find_previous_marker_index(2)
	var next_index: int = replay_system.find_next_marker_index(2)
	assert_true(
		previous_index >= 0 and replay_system.get_marker(previous_index).step_index == 1,
		"上一标记必须严格位于当前步之前。"
	)
	assert_true(
		next_index >= 0 and replay_system.get_marker(next_index).step_index == 3,
		"下一标记必须严格位于当前步之后。"
	)
	assert_false(replay_system.jump_to_step(-1), "不得跳到负步数。")
	assert_false(replay_system.jump_to_step(5), "不得跳过回放总步数。")
	assert_true(replay_system.jump_to_step(3), "合法目标应发布确定性跳转请求。")
	assert_true(replay_system.is_jump_in_progress(), "跳转完成前应冻结其他运输控件。")
	assert_false(replay_system.can_continue_from_current_step(), "跳转处理中不得继续游玩。")

	assert_true(
		replay_system.report_oos({&"kind": &"fixture", &"step_index": 3}),
		"首个 OOS 应被记录。"
	)
	assert_false(replay_system.is_jump_in_progress(), "OOS 必须立即取消活动跳转。")
	assert_false(replay_system.jump_to_step(1), "OOS 后必须阻断所有跳转。")
	var markers: Array[ReplayMarker] = replay_system.get_markers()
	assert_true(
		ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.OOS) == 1,
		"OOS 必须进入同一标记目录且只记录首个根因。"
	)


func test_command_history_presentation_skip_reaches_same_canonical_hash() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid: GridModel = GridModel.new()
	var status: GameStatusModel = GameStatusModel.new()
	var current_game: CurrentGameModel = CurrentGameModel.new()
	var history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()

	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFCapabilityUtility, GFCapabilityUtility.new())
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(TileCompositionUtility, composition)
	await architecture.register_utility(GFCommandHistoryUtility, history)
	await architecture.register_model(GridModel, grid)
	await architecture.register_model(GameStatusModel, status)
	await architecture.register_model(CurrentGameModel, current_game)
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.register_system(GameStateSystem, GameStateSystem.new())
	await architecture.register_system(GridMovementSystem, GridMovementSystem.new())
	await architecture.init()

	var definition_value: Resource = load(_CLASSIC_DEFINITION_PATH)
	assert_true(definition_value is TileDefinition, "经典方块定义必须可加载。")
	if not definition_value is TileDefinition:
		architecture.dispose()
		return
	var definition: TileDefinition = definition_value
	var interaction: ClassicInteractionRule = ClassicInteractionRule.new()
	interaction.tile_definitions = [definition]
	interaction.default_definition_id = definition.definition_id
	assert_true(
		grid.initialize(
			BoardTopology.create_rectangle(Vector2i(4, 1)),
			interaction,
			ClassicMovementRule.new()
		),
		"哈希夹具棋盘应初始化成功。"
	)
	assert_true(grid.place_tile(composition.create_tile(definition, 2), Vector2i(0, 0)))
	assert_true(grid.place_tile(composition.create_tile(definition, 2), Vector2i(1, 0)))
	assert_true(grid.place_tile(composition.create_tile(definition, 4), Vector2i(2, 0)))
	var mode: GameModeConfig = GameModeConfig.new()
	mode.ruleset_id = &"gameplay.replay_browser_fixture"
	mode.ruleset_version = 1
	mode.interaction_rule = interaction
	mode.movement_rule = ClassicMovementRule.new()
	mode.target_tile_value = 2048
	current_game.mode_config.set_value(mode)
	var actions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT]
	var state_system: GameStateSystem = architecture.get_system(GameStateSystem)
	var baseline: MoveCommand = MoveCommand.new(Vector2i.ZERO)
	baseline.mark_as_baseline()
	assert_true(
		baseline.set_snapshot(state_system.get_full_game_state()),
		"回放跳转夹具必须建立 GF 命令历史 baseline。"
	)
	history.record(baseline)
	var replay: ReplayData = ReplayData.new()
	replay.actions = actions.duplicate()

	for direction: Vector2i in actions:
		var step_result: Variant = await history.execute_command(MoveCommand.new(direction))
		assert_true(
			step_result is TurnResult,
			"逐步播放动作必须有效。"
		)
		if step_result is TurnResult:
			var turn_result: TurnResult = step_result
			replay.checkpoints.append(
				determinism.create_checkpoint(
					replay.checkpoints.size() + 1,
					state_system.get_full_game_state(),
					mode,
					turn_result
				)
			)
	var stepped_hash: String = determinism.calculate_state_checksum(
		state_system.get_full_game_state(),
		mode
	)

	assert_true(await history.undo_last_async(), "应能撤销到第 1 步。")
	assert_true(await history.undo_last_async(), "应能撤销到初始步。")
	var replay_system: ReplaySystem = ReplaySystem.new()
	replay_system._command_history = history
	replay_system.activate_replay_mode(replay)
	assert_true(replay_system.jump_to_step(2), "应接受目标 checkpoint 的跳转请求。")
	var input_harness: ReplayInputHarness = ReplayInputHarness.new()
	input_harness.replay_system_ref = replay_system
	input_harness.determinism_ref = determinism
	input_harness.state_system_ref = state_system
	input_harness.current_game_ref = current_game
	input_harness._replay_data = replay
	var request: ReplayJumpRequestData = ReplayJumpRequestData.new(1, 2)
	var animation_utility: GameBoardAnimationUtility = GameBoardAnimationUtility.new()
	animation_utility.begin_presentation_suppression()
	var jump_succeeded: bool = await input_harness._rebuild_command_history_to_step(
		request,
		history,
		replay_system
	)
	animation_utility.end_presentation_suppression()
	assert_true(jump_succeeded, "ReplayInputSystem 应通过同一 MoveCommand 历史重建目标步。")
	assert_true(
		replay_system.notify_jump_completed(1, 2, jump_succeeded),
		"达到目标步且 hash 匹配时跳转应成功结算。"
	)
	var jumped_hash: String = determinism.calculate_state_checksum(
		state_system.get_full_game_state(),
		mode
	)

	assert_true(jumped_hash == stepped_hash, "跳过表现与逐步播放到同一步的 canonical hash 必须相同。")
	architecture.dispose()


func test_replay_scene_and_input_expose_complete_marker_focus_controls() -> void:
	var scene: Node = _GAME_SCENE.instantiate()
	var picker: OptionButton = scene.get_node_or_null(
		"ReplayControlsContainer/MarginContainer/VBoxContainer/ReplayMarkerPicker"
	) as OptionButton
	var previous_marker: Button = scene.get_node_or_null(
		"ReplayControlsContainer/MarginContainer/VBoxContainer/MarkerTransport/ReplayPrevMarkerButton"
	) as Button
	var next_marker: Button = scene.get_node_or_null(
		"ReplayControlsContainer/MarginContainer/VBoxContainer/MarkerTransport/ReplayNextMarkerButton"
	) as Button
	var eligibility_note: Label = scene.get_node_or_null(
		"ReplayControlsContainer/MarginContainer/VBoxContainer/ReplayEligibilityLabel"
	) as Label

	assert_true(picker is OptionButton, "播放页必须提供可聚焦的标记选择器。")
	assert_true(previous_marker is Button, "播放页必须提供上一标记按钮。")
	assert_true(next_marker is Button, "播放页必须提供下一标记按钮。")
	assert_true(eligibility_note is Label, "播放页必须明确展示继续游玩的资格语义。")
	if is_instance_valid(picker):
		assert_false(picker.focus_neighbor_bottom.is_empty(), "标记选择器必须接入手柄/键盘焦点链。")
		assert_true(
			picker.custom_minimum_size.y >= 44.0,
			"标记选择器必须满足触控目标最小高度。"
		)
	if is_instance_valid(previous_marker):
		assert_false(previous_marker.focus_neighbor_top.is_empty(), "上一标记按钮必须接入焦点链。")
		assert_true(
			previous_marker.custom_minimum_size.y >= 44.0,
			"上一标记按钮必须满足触控目标最小高度。"
		)
	if is_instance_valid(next_marker):
		assert_false(next_marker.focus_neighbor_bottom.is_empty(), "下一标记按钮必须接入焦点链。")
		assert_true(
			next_marker.custom_minimum_size.y >= 44.0,
			"下一标记按钮必须满足触控目标最小高度。"
		)
	scene.free()

	var action_ids: Array[StringName] = []
	for mapping: GFInputMapping in _REPLAY_INPUT_CONTEXT.mappings:
		if mapping != null and mapping.action != null:
			action_ids.append(mapping.action.action_id)
	assert_true(action_ids.has(&"replay_prev_marker"), "回放输入上下文必须提供上一标记动作。")
	assert_true(action_ids.has(&"replay_next_marker"), "回放输入上下文必须提供下一标记动作。")
	assert_false(action_ids.has(&"replay_speed_up"), "本批次不得引入倍速动作。")


# --- 私有/辅助方法 ---

func _make_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "a".repeat(64)
	checkpoint.board_checksum = "b".repeat(64)
	checkpoint.rng_checksum = "c".repeat(64)
	checkpoint.score = score
	return checkpoint


func _marker_kinds(markers: Array[ReplayMarker]) -> Array[int]:
	var result: Array[int] = []
	for marker: ReplayMarker in markers:
		result.append(marker.kind)
	return result


func _marker_ids(markers: Array[ReplayMarker]) -> Array[StringName]:
	var result: Array[StringName] = []
	for marker: ReplayMarker in markers:
		result.append(marker.marker_id)
	return result


func _make_navigation_replay() -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	replay.actions = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for index: int in range(replay.actions.size()):
		var checkpoint: ReplayCheckpoint = _make_checkpoint(index + 1, (index + 1) * 4)
		checkpoint.metadata_available = true
		checkpoint.merge_count = 1
		replay.checkpoints.append(checkpoint)
	return replay


func _make_history(player_step_count: int) -> GFCommandHistoryUtility:
	var undo: Array = [_make_move_command_data(Vector2i.ZERO, true)]
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for index: int in range(mini(player_step_count, directions.size())):
		undo.append(_make_move_command_data(directions[index], false))
	var history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	history.init()
	history.deserialize_full_history(
		{&"undo": undo, &"redo": []},
		Callable(MoveCommand, "deserialize")
	)
	return history


class ReplayInputHarness extends ReplayInputSystem:
	var replay_system_ref: ReplaySystem
	var determinism_ref: GameDeterminismUtility
	var state_system_ref: GameStateSystem
	var current_game_ref: CurrentGameModel

	func _get_replay_system() -> ReplaySystem:
		return replay_system_ref

	func _get_determinism_utility() -> GameDeterminismUtility:
		return determinism_ref

	func _get_game_state_system() -> GameStateSystem:
		return state_system_ref

	func _get_current_game_model() -> CurrentGameModel:
		return current_game_ref


func _make_move_command_data(direction: Vector2i, is_baseline: bool) -> Dictionary:
	return {
		&"schema_version": MoveCommand.SERIALIZATION_SCHEMA_VERSION,
		&"direction_x": direction.x,
		&"direction_y": direction.y,
		&"snapshot": _make_empty_game_state(),
		&"reverse_map": {},
		&"is_baseline": is_baseline,
	}


func _make_empty_game_state() -> Dictionary:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(2, 1))
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	return {
		&"schema_version": GameStateSystem.STATE_SCHEMA_VERSION,
		&"board_key": topology.get_stable_key(),
		&"board_snapshot": {
			&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
			&"topology": topology.to_dict(),
			&"tiles": [],
		},
		&"rng_full_state": seed_utility.get_full_state(),
		&"score": 0,
		&"move_count": 0,
		&"highest_tile": 0,
		&"ratio_resolutions": 0,
		&"target_tile_value": 0,
		&"target_reached": false,
		&"extra_stats": {},
		&"rules_states": {},
	}
