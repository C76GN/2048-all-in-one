## 验证移动命令记录撤回动画所需的反向位置映射。
extends GutTest


# --- 测试用例 ---

func test_grid_movement_system_builds_reverse_targets_from_animation_instructions() -> void:
	var movement_system := GridMovementSystem.new()
	var instructions: Array = []
	instructions.append({
		&"type": &"MOVE",
		&"from_grid_pos": Vector2i(2, 0),
		&"to_grid_pos": Vector2i(0, 0),
	})
	instructions.append({
		&"type": &"MERGE",
		&"from_grid_pos_consumed": Vector2i(3, 1),
		&"from_grid_pos_merged": Vector2i(2, 1),
		&"to_grid_pos": Vector2i(0, 1),
	})

	var reverse_map: Dictionary = movement_system._build_reverse_target_map(instructions)

	assert_eq(reverse_map.get("2,0"), Vector2i(0, 0), "普通移动应记录旧位置到移动后位置。")
	assert_eq(reverse_map.get("3,1"), Vector2i(0, 1), "合并中被消耗的方块应记录到合并后位置。")
	assert_eq(reverse_map.get("2,1"), Vector2i(0, 1), "合并中保留的方块应记录到合并后位置。")


func test_deserialize_preserves_reverse_targets() -> void:
	var command_data := {
		&"direction_x": -1,
		&"direction_y": 0,
		&"snapshot": {},
		&"reverse_map": {
			"1,2": Vector2i(0, 2),
		},
		&"is_baseline": false,
	}

	var command := MoveCommand.deserialize(command_data)
	var reverse_map: Dictionary = command.serialize()[&"reverse_map"]

	assert_eq(command.get_direction(), Vector2i.LEFT, "反序列化应恢复移动方向。")
	assert_eq(reverse_map.get("1,2"), Vector2i(0, 2), "反序列化应保留撤回动画映射。")


func test_records_reverse_targets_while_command_runs_inside_simple_event() -> void:
	var architecture := GFArchitecture.new()
	var grid_model := GridModel.new()
	var command_history := GFCommandHistoryUtility.new()

	architecture.register_model(GridModel, grid_model)
	architecture.register_model(GameStatusModel, GameStatusModel.new())
	architecture.register_utility(GFSeedUtility, GFSeedUtility.new())
	architecture.register_utility(GFCommandHistoryUtility, command_history)
	architecture.register_system(GameStateSystem, GameStateSystem.new())
	architecture.register_system(GridMovementSystem, GridMovementSystem.new())
	architecture.register_system(RuleSystem, RuleSystem.new())
	await architecture.init()

	grid_model.initialize(4, ClassicInteractionRule.new(), ClassicMovementRule.new())
	grid_model.place_tile(GameTileData.new(2, Tile.TileType.PLAYER), Vector2i(1, 0))
	architecture.register_simple_event(&"test_execute_move", func(_payload: Variant) -> void:
		command_history.execute_command(MoveCommand.new(Vector2i.LEFT))
	)

	architecture.send_simple_event(&"test_execute_move")

	var history := command_history.get_undo_history()
	assert_eq(history.size(), 1, "简单事件派发过程中执行的有效移动应写入命令历史。")

	var command := history[0] as MoveCommand
	var reverse_map: Dictionary = command.serialize()[&"reverse_map"]
	assert_eq(reverse_map.get("1,0"), Vector2i(0, 0), "嵌套在简单事件中执行命令时仍应记录撤回映射。")

	architecture.dispose()
