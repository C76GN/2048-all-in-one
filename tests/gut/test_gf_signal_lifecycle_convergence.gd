extends GutTest


func test_custom_board_operation_completion_is_owned_and_one_shot() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var system: CustomBoardSystem = CustomBoardSystem.new()
	system._signal_utility = signal_utility
	system._disposed = false
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		operation.configure_for_utility(
			17,
			&"test.profile",
			PackedStringArray([GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID])
		)
	)
	var candidate: CustomBoardData = _make_board("candidate", "Candidate")
	var target: CustomBoardData = _make_board("", "Target")

	system._apply_saved_board_on_success(operation, candidate, target)
	assert_true(signal_utility.get_connection_count() == 1)

	var result: GameSaveSectionResult = GameSaveSectionResult.new()
	assert_true(
		result.configure_for_utility(
			operation.get_transaction_id(),
			operation.get_profile_id(),
			operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
	)
	assert_true(operation.complete_for_utility(result))
	assert_true(target.custom_board_id == candidate.custom_board_id)
	assert_true(target.display_name == candidate.display_name)
	assert_true(
		signal_utility.get_connection_count() == 0,
		"专属 operation 终态后 connect_once 必须自动解除 owner 连接。"
	)

	system.dispose()
	signal_utility.dispose()


func test_custom_board_reconciliation_ignores_other_transaction_and_disposes() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var system: CustomBoardSystem = CustomBoardSystem.new()
	system._signal_utility = signal_utility
	system._save_graph = save_graph
	system._disposed = false
	var candidate: CustomBoardData = _make_board("candidate", "Candidate")
	var target: CustomBoardData = _make_board("", "Target")

	system._apply_saved_board_after_reconciliation(42, candidate, target)
	var connection: GFSignalConnection = system._reconciliation_connection
	assert_not_null(connection)
	assert_true(connection != null and connection.is_active())

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 41,
		&"candidate_persisted": true,
	})
	assert_true(target.custom_board_id.is_empty())
	assert_true(
		connection.is_active(),
		"其他 transaction 的共享证据不得消耗目标监听。"
	)

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 42,
		&"candidate_persisted": true,
	})
	assert_true(target.custom_board_id == candidate.custom_board_id)
	assert_false(connection.is_active())
	assert_true(signal_utility.get_connection_count() == 0)

	system._apply_saved_board_after_reconciliation(73, candidate, target)
	var pending_connection: GFSignalConnection = system._reconciliation_connection
	assert_true(pending_connection != null and pending_connection.is_active())
	var pending_operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		pending_operation.configure_for_utility(
			74,
			&"test.profile",
			PackedStringArray([GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID])
		)
	)
	var late_target: CustomBoardData = _make_board("", "Late target")
	system._apply_saved_board_on_success(
		pending_operation,
		candidate,
		late_target
	)
	assert_true(signal_utility.get_connection_count() == 2)
	system.dispose()
	assert_false(pending_connection.is_active())
	assert_true(
		signal_utility.get_connection_count() == 0,
		"CustomBoardSystem.dispose 必须按 owner 清理全部迟到回调。"
	)
	var late_result: GameSaveSectionResult = GameSaveSectionResult.new()
	assert_true(
		late_result.configure_for_utility(
			pending_operation.get_transaction_id(),
			pending_operation.get_profile_id(),
			pending_operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
	)
	assert_true(pending_operation.complete_for_utility(late_result))
	assert_true(
		late_target.custom_board_id.is_empty(),
		"dispose 后的 operation 迟到终态不得回填调用方对象。"
	)
	signal_utility.dispose()


func test_tile_lab_operation_completion_is_owned_and_one_shot() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var system: TileLabSystem = TileLabSystem.new()
	system._signal_utility = signal_utility
	system._disposed = false
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		operation.configure_for_utility(
			117,
			&"test.profile",
			PackedStringArray([TileLabSaveData.SECTION_ID])
		)
	)
	var candidate: CustomTileBlueprintData = _make_blueprint(
		"candidate",
		"Candidate"
	)
	var target: CustomTileBlueprintData = _make_blueprint("", "Target")

	system._publish_saved_blueprint_on_success(operation, candidate, target)
	assert_true(signal_utility.get_connection_count() == 1)

	var result: GameSaveSectionResult = GameSaveSectionResult.new()
	assert_true(
		result.configure_for_utility(
			operation.get_transaction_id(),
			operation.get_profile_id(),
			operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
	)
	assert_true(operation.complete_for_utility(result))
	assert_true(target.blueprint_id == candidate.blueprint_id)
	assert_true(target.display_name == candidate.display_name)
	assert_true(
		signal_utility.get_connection_count() == 0,
		"专属 TileLab operation 终态后 connect_once 必须自动解除 owner 连接。"
	)

	system.dispose()
	signal_utility.dispose()


func test_tile_lab_reconciliation_ignores_other_transaction_and_disposes() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var system: TileLabSystem = TileLabSystem.new()
	system._signal_utility = signal_utility
	system._save_graph = save_graph
	system._disposed = false
	var candidate: CustomTileBlueprintData = _make_blueprint(
		"candidate",
		"Candidate"
	)
	var target: CustomTileBlueprintData = _make_blueprint("", "Target")

	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		operation.configure_for_utility(
			142,
			&"test.profile",
			PackedStringArray([TileLabSaveData.SECTION_ID])
		)
	)
	system._publish_saved_blueprint_on_success(operation, candidate, target)
	assert_true(signal_utility.get_connection_count() == 1)
	var unknown_result: GameSaveSectionResult = GameSaveSectionResult.new()
	assert_true(
		unknown_result.configure_for_utility(
			operation.get_transaction_id(),
			operation.get_profile_id(),
			operation.get_section_ids(),
			GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
			ERR_TIMEOUT,
			true,
			false
		)
	)
	assert_true(operation.complete_for_utility(unknown_result))
	var connection: GFSignalConnection = system._reconciliation_connection
	assert_not_null(connection)
	assert_true(connection != null and connection.is_active())
	assert_true(
		signal_utility.get_connection_count() == 1,
		"outcome_unknown 后只应保留共享对账监听。"
	)

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 141,
		&"candidate_persisted": true,
	})
	assert_true(target.blueprint_id.is_empty())
	assert_true(
		connection.is_active(),
		"其他 transaction 的共享证据不得消耗 TileLab 目标监听。"
	)

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 142,
		&"candidate_persisted": true,
	})
	assert_true(target.blueprint_id == candidate.blueprint_id)
	assert_false(connection.is_active())
	assert_true(signal_utility.get_connection_count() == 0)

	var late_reconciliation_target: CustomTileBlueprintData = (
		_make_blueprint("", "Late reconciliation")
	)
	system._connect_saved_blueprint_reconciliation(
		173,
		candidate,
		late_reconciliation_target
	)
	var pending_connection: GFSignalConnection = (
		system._reconciliation_connection
	)
	assert_true(pending_connection != null and pending_connection.is_active())
	var pending_operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		pending_operation.configure_for_utility(
			174,
			&"test.profile",
			PackedStringArray([TileLabSaveData.SECTION_ID])
		)
	)
	var late_operation_target: CustomTileBlueprintData = _make_blueprint(
		"",
		"Late operation"
	)
	system._publish_saved_blueprint_on_success(
		pending_operation,
		candidate,
		late_operation_target
	)
	assert_true(signal_utility.get_connection_count() == 2)

	system.dispose()
	assert_false(pending_connection.is_active())
	assert_true(
		signal_utility.get_connection_count() == 0,
		"TileLabSystem.dispose 必须按 owner 清理全部迟到回调。"
	)
	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 173,
		&"candidate_persisted": true,
	})
	assert_true(late_reconciliation_target.blueprint_id.is_empty())

	var late_result: GameSaveSectionResult = GameSaveSectionResult.new()
	assert_true(
		late_result.configure_for_utility(
			pending_operation.get_transaction_id(),
			pending_operation.get_profile_id(),
			pending_operation.get_section_ids(),
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false
		)
	)
	assert_true(pending_operation.complete_for_utility(late_result))
	assert_true(
		late_operation_target.blueprint_id.is_empty(),
		"dispose 后的 TileLab operation 迟到终态不得回填调用方对象。"
	)
	signal_utility.dispose()


func test_game_flow_waiter_keeps_listening_until_matching_transaction() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var waiter: GameFlowSystem._SectionReconciliationWaiter = (
		GameFlowSystem._SectionReconciliationWaiter.new()
	)
	var probe: _EvidenceProbe = _EvidenceProbe.new()
	var _settled_connection: Error = waiter.settled.connect(
		probe.capture
	) as Error
	assert_true(waiter.begin(save_graph, signal_utility, waiter, 42))
	var connection: GFSignalConnection = waiter._connection

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 41,
		&"candidate_persisted": true,
	})
	assert_true(probe.count == 0)
	assert_true(
		connection != null and connection.is_active(),
		"无关事务先到时 waiter 必须继续等待。"
	)

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 42,
		&"candidate_persisted": true,
	})
	assert_true(probe.count == 1)
	assert_true(
		GFVariantData.get_option_int(
			probe.last_evidence,
			&"transaction_id",
			0
		) == 42
	)
	assert_false(connection.is_active())
	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 42,
		&"candidate_persisted": true,
	})
	assert_true(probe.count == 1, "匹配终态只能发布一次。")
	signal_utility.dispose()


func test_game_flow_waiter_cancel_is_idempotent_and_disconnects() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var waiter: GameFlowSystem._SectionReconciliationWaiter = (
		GameFlowSystem._SectionReconciliationWaiter.new()
	)
	var probe: _EvidenceProbe = _EvidenceProbe.new()
	var _settled_connection: Error = waiter.settled.connect(
		probe.capture
	) as Error
	assert_true(waiter.begin(save_graph, signal_utility, waiter, 91))
	var connection: GFSignalConnection = waiter._connection

	waiter.cancel()
	waiter.cancel()
	assert_true(probe.count == 1)
	assert_true(
		GFVariantData.get_option_bool(
			probe.last_evidence,
			&"cancelled",
			false
		)
	)
	assert_false(connection.is_active())
	assert_true(signal_utility.get_connection_count() == 0)
	signal_utility.dispose()


func test_player_profile_account_operation_completion_is_one_shot() -> void:
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var dialog: _PlayerProfileDialogProbe = _PlayerProfileDialogProbe.new()
	dialog._signal_utility = signal_utility
	var operation: LocalAccountOperation = LocalAccountOperation.new()
	assert_true(
		operation.configure_for_system(
			LocalAccountOperation.OPERATION_SWITCH,
			"account-b"
		)
	)

	dialog._observe_account_operation(operation)
	assert_true(signal_utility.get_connection_count() == 1)
	var result: LocalAccountOperationResult = LocalAccountOperationResult.new()
	assert_true(
		result.configure_for_system(
			LocalAccountOperation.OPERATION_SWITCH,
			LocalAccountOperationResult.STATUS_SUCCEEDED,
			OK
		)
	)
	assert_true(operation.complete_for_system(result))
	assert_true(dialog.completion_count == 1)
	assert_true(
		signal_utility.get_connection_count() == 0,
		"账号 operation 终态后 connect_once 必须立即解除 owner 连接。"
	)

	dialog.free()
	signal_utility.dispose()


# --- 私有/辅助方法 ---

func _make_board(board_id: String, display_name: String) -> CustomBoardData:
	var board: CustomBoardData = CustomBoardData.new()
	board.custom_board_id = board_id
	board.display_name = display_name
	board.created_at = 10
	board.updated_at = 20
	board.topology = BoardTopology.create_rectangle(Vector2i(4, 4))
	return board


func _make_blueprint(
	blueprint_id: String,
	display_name: String
) -> CustomTileBlueprintData:
	var blueprint: CustomTileBlueprintData = CustomTileBlueprintData.new()
	blueprint.blueprint_id = blueprint_id
	blueprint.display_name = display_name
	blueprint.base_definition_id = &"tile.classic.numeric"
	blueprint.recipe_ids = [&"tile.recipe.classic_merge"]
	blueprint.preview_left_value = 2
	blueprint.preview_right_value = 2
	blueprint.created_at = 10
	blueprint.updated_at = 20
	return blueprint


# --- 内部类 ---

class _EvidenceProbe:
	extends RefCounted

	var count: int = 0
	var last_evidence: Dictionary = {}

	## 捕获一次对账证据。
	## @param evidence: 共享对账信号载荷。
	func capture(evidence: Dictionary) -> void:
		count += 1
		last_evidence = evidence.duplicate(true)


class _PlayerProfileDialogProbe:
	extends PlayerProfileDialog

	var completion_count: int = 0


	func _apply_account_operation_state() -> void:
		pass


	func _on_account_operation_completed(
		_result: LocalAccountOperationResult,
		operation: LocalAccountOperation
	) -> void:
		if operation == null or operation != _account_operation:
			return
		completion_count += 1
		_account_operation = null
