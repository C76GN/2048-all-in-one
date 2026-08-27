extends GutTest


func test_ui_operation_state_rejects_stale_tokens_and_evidence() -> void:
	var state: GameSaveSectionUiOperationState = GameSaveSectionUiOperationState.new()
	var first_token: int = state.begin({&"resource_identity": "first"})
	var current_token: int = state.begin({&"resource_identity": "current"})
	assert_false(state.finish_request(first_token))
	assert_true(state.finish_request(current_token))
	assert_false(state.finish_request(current_token), "请求终态只能被消费一次。")

	var result: GameSaveSectionResult = _make_result(
		41,
		GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
		ERR_TIMEOUT
	)
	assert_true(state.begin_reconciliation(result))
	assert_true(state.is_blocked())
	assert_true(state.is_reconciling())
	assert_true(state.settle_reconciliation({&"transaction_id": 40}).is_empty())
	assert_true(state.is_reconciling())

	var settlement: Dictionary = state.settle_reconciliation({
		&"transaction_id": 41,
		&"status": &"late_failure_rolled_back",
		&"candidate_persisted": false,
		&"memory_rolled_back": true,
	})
	assert_false(settlement.is_empty())
	assert_true(GFVariantData.get_option_bool(
		settlement,
		&"memory_rolled_back"
	))
	assert_true(state.is_busy())
	assert_false(state.is_reconciling())
	assert_true(state.finish_reconciliation(current_token))
	assert_false(state.is_blocked())
	assert_true(state.claim_reconciliation_prompt())
	assert_false(state.claim_reconciliation_prompt())


func test_ui_operation_state_only_reconciles_typed_required_statuses() -> void:
	var state: GameSaveSectionUiOperationState = GameSaveSectionUiOperationState.new()
	var token: int = state.begin()
	assert_false(state.begin_reconciliation(_make_result(
		1,
		GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
		ERR_TIMEOUT
	)), "请求仍在途时不能提前进入对账。")
	assert_true(state.finish_request(token))
	assert_false(state.begin_reconciliation(_make_result(
		1,
		GameSaveSectionResult.STATUS_PERSISTED,
		OK
	)))
	var restart_required: GameSaveSectionResult = _make_result(
		2,
		GameSaveSectionResult.STATUS_ROLLBACK_FAILED,
		ERR_CANT_CREATE
	)
	assert_false(state.begin_reconciliation(restart_required))
	assert_true(restart_required.requires_restart())
	state.invalidate()
	assert_false(state.is_blocked())
	assert_true(state.get_context().is_empty())


func test_section_result_separates_reconciliation_from_restart_required() -> void:
	for status: StringName in [
		GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
		GameSaveSectionResult.STATUS_ROLLBACK_OUTCOME_UNKNOWN,
	]:
		assert_true(
			_make_result(11, status, ERR_TIMEOUT).requires_reconciliation(),
			"终态 %s 必须保持账号/Profile 修改锁直到证据收敛。" % status
		)
	for status: StringName in [
		GameSaveSectionResult.STATUS_PERSISTED,
		GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK,
		GameSaveSectionResult.STATUS_COMPENSATION_FAILED,
	]:
		var error_code: Error = (
			OK
			if status == GameSaveSectionResult.STATUS_PERSISTED
			else FAILED
		)
		assert_false(
			_make_result(12, status, error_code).requires_reconciliation(),
			"确定性终态 %s 不得伪装成 outcome-unknown。" % status
		)
	var rollback_failed: GameSaveSectionResult = _make_result(
		13,
		GameSaveSectionResult.STATUS_ROLLBACK_FAILED,
		ERR_CANT_CREATE
	)
	assert_false(rollback_failed.requires_reconciliation())
	assert_true(
		rollback_failed.requires_restart(),
		"内存回滚失败必须是 restart-required fatal fence，而不是永不收敛的对账。"
	)


# --- 私有/辅助方法 ---

func _make_result(
	transaction_id: int,
	status: StringName,
	error_code: Error
) -> GameSaveSectionResult:
	var result: GameSaveSectionResult = GameSaveSectionResult.new()
	var configured: bool = result.configure_for_utility(
		transaction_id,
		&"test_profile",
		PackedStringArray([&"test"]),
		status,
		error_code,
		true,
		false
	)
	assert_true(configured)
	return result
