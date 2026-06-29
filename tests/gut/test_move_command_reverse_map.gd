## 验证移动命令记录撤回动画所需的反向位置映射。
extends GutTest


# --- 测试用例 ---

func test_grid_movement_system_builds_reverse_targets_from_animation_instructions() -> void:
	var movement_system: GridMovementSystem = GridMovementSystem.new()
	var instructions: Array = []
	_append_dictionary(instructions, {
		&"type": &"MOVE",
		&"from_grid_pos": Vector2i(2, 0),
		&"to_grid_pos": Vector2i(0, 0),
	})
	_append_dictionary(instructions, {
		&"type": &"MERGE",
		&"from_grid_pos_consumed": Vector2i(3, 1),
		&"from_grid_pos_merged": Vector2i(2, 1),
		&"to_grid_pos": Vector2i(0, 1),
	})

	var reverse_map: Dictionary = movement_system._build_reverse_target_map(instructions)

	assert_true(_get_vector2i(reverse_map, "2,0") == Vector2i(0, 0), "普通移动应记录旧位置到移动后位置。")
	assert_true(_get_vector2i(reverse_map, "3,1") == Vector2i(0, 1), "合并中被消耗的方块应记录到合并后位置。")
	assert_true(_get_vector2i(reverse_map, "2,1") == Vector2i(0, 1), "合并中保留的方块应记录到合并后位置。")


func test_deserialize_preserves_reverse_targets() -> void:
	var command_data: Dictionary = {
		&"direction_x": -1,
		&"direction_y": 0,
		&"snapshot": {},
		&"reverse_map": {
			"1,2": Vector2i(0, 2),
		},
		&"is_baseline": false,
	}

	var command: MoveCommand = MoveCommand.deserialize(command_data)
	var command_state: Dictionary = command.serialize()
	var reverse_map: Dictionary = GFVariantData.to_dictionary(command_state.get(&"reverse_map"))

	assert_true(command.get_direction() == Vector2i.LEFT, "反序列化应恢复移动方向。")
	assert_true(_get_vector2i(reverse_map, "1,2") == Vector2i(0, 2), "反序列化应保留撤回动画映射。")


func test_records_reverse_targets_while_command_runs_inside_simple_event() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var grid_model: GridModel = GridModel.new()
	var command_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()

	await architecture.register_model(GridModel, grid_model)
	await architecture.register_model(GameStatusModel, GameStatusModel.new())
	await architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	await architecture.register_utility(GFCommandHistoryUtility, command_history)
	await architecture.register_system(GameStateSystem, GameStateSystem.new())
	await architecture.register_system(GridMovementSystem, GridMovementSystem.new())
	await architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.init()

	grid_model.initialize(4, ClassicInteractionRule.new(), ClassicMovementRule.new())
	grid_model.place_tile(GameTileData.new(2, Tile.TileType.PLAYER), Vector2i(1, 0))
	architecture.register_simple_event(&"test_execute_move", func(_payload: Variant) -> void:
		var _execute_result: Variant = await command_history.execute_command(MoveCommand.new(Vector2i.LEFT))
	)

	architecture.send_simple_event(&"test_execute_move")

	var history: Array = command_history.get_undo_history()
	assert_true(history.size() == 1, "简单事件派发过程中执行的有效移动应写入命令历史。")

	var command: MoveCommand = _get_move_command(history, 0)
	var command_state: Dictionary = command.serialize()
	var reverse_map: Dictionary = GFVariantData.to_dictionary(command_state.get(&"reverse_map"))
	assert_true(_get_vector2i(reverse_map, "1,0") == Vector2i(0, 0), "嵌套在简单事件中执行命令时仍应记录撤回映射。")

	architecture.dispose()


# --- 私有/辅助方法 ---

func _append_dictionary(target: Array, value: Dictionary) -> void:
	target.append(value)


func _get_vector2i(source: Dictionary, key: String) -> Vector2i:
	var value: Variant = source.get(key, Vector2i.ZERO)
	return value if value is Vector2i else Vector2i.ZERO


func _get_move_command(source: Array, index: int) -> MoveCommand:
	var value: Variant = source[index] if index >= 0 and index < source.size() else null
	if value is MoveCommand:
		return value
	assert_true(false, "测试历史中缺少 MoveCommand，index=%d。" % index)
	return MoveCommand.new(Vector2i.ZERO)
