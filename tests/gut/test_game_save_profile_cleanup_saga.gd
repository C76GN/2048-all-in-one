extends GutTest


const _CANONICAL_NAME: String = "profiles/test-player.save"


func test_saga_rejects_unsettled_main_and_closes_zero_family_success() -> void:
	var operation: GFStorageAsyncOperation = _make_main_delete_operation(101)
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.create(
		_CANONICAL_NAME,
		&"inactive_profile_request",
		operation,
		true
	)
	assert_not_null(saga)
	assert_true(saga.has_caller_waiter())
	assert_false(saga.settle_main_delete(OK))
	assert_true(_complete_main_delete(operation, OK))
	assert_true(saga.settle_main_delete(OK))
	assert_true(saga.begin_derived_cleanup(0))
	assert_false(saga.begin_derived_cleanup(0))
	assert_true(saga.complete_derived_cleanup(OK))

	var evidence: Dictionary = saga.make_terminal_evidence()
	assert_true(GFVariantData.get_option_bool(evidence, &"ok", false))
	assert_true(
		GFVariantData.get_option_string_name(evidence, &"status")
		== &"cleaned"
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"derived_total_count", -1)
		== 0
	)
	assert_false(_dictionary_contains_text(evidence, _CANONICAL_NAME))


func test_main_failure_never_opens_derived_cleanup() -> void:
	var operation: GFStorageAsyncOperation = _make_main_delete_operation(102)
	assert_true(_complete_main_delete(operation, ERR_CANT_OPEN))
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.create(
		_CANONICAL_NAME,
		&"active_profile_reset",
		operation,
		false
	)
	assert_not_null(saga)
	assert_true(saga.settle_main_delete(ERR_CANT_OPEN))
	assert_true(saga.is_completed())
	assert_false(saga.begin_derived_cleanup(1))

	var evidence: Dictionary = saga.make_terminal_evidence()
	assert_true(
		GFVariantData.get_option_string_name(evidence, &"status")
		== &"main_failed"
	)
	assert_true(
		GFVariantData.get_option_string_name(evidence, &"derived_status")
		== &"not_started"
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"error_code", OK)
		== int(ERR_CANT_OPEN)
	)


func test_typed_derived_terminals_own_counts_busy_retry_and_evidence() -> void:
	var operation: GFStorageAsyncOperation = _make_main_delete_operation(103)
	assert_true(_complete_main_delete(operation, OK))
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.create(
		_CANONICAL_NAME,
		&"inactive_profile_request",
		operation,
		true
	)
	assert_not_null(saga)
	assert_true(saga.settle_main_delete(OK))
	assert_true(saga.begin_derived_cleanup(2))

	var busy_operation: ChunkProfileCleanupOperation = _make_derived_operation(
		&"busy",
		ChunkProfileCleanupResult.create(
			ChunkProfileCleanupResult.STATUS_BUSY,
			ERR_BUSY,
			"scope busy",
			0,
			0,
			0,
			0,
			0,
			0
		)
	)
	assert_true(saga.bind_active_derived_operation(busy_operation))
	assert_true(saga.release_busy_derived_operation())

	var failed_result: ChunkProfileCleanupResult = (
		ChunkProfileCleanupResult.create(
			ChunkProfileCleanupResult.STATUS_PARTIAL_FAILURE,
			ERR_CANT_OPEN,
			"derived family failed",
			1,
			0,
			0,
			1,
			0,
			0,
			ChunkManifest.BANK_A,
			0,
			GFStorageDeleteResult.FailureKind.IO_FAILED
		)
	)
	assert_true(
		saga.bind_active_derived_operation(
			_make_derived_operation(&"failed", failed_result)
		)
	)
	assert_true(saga.settle_derived_operation() == ERR_CANT_OPEN)

	var cleaned_result: ChunkProfileCleanupResult = (
		ChunkProfileCleanupResult.create(
			ChunkProfileCleanupResult.STATUS_CLEANED,
			OK,
			"",
			1,
			1,
			0,
			0,
			0,
			0
		)
	)
	assert_true(
		saga.bind_active_derived_operation(
			_make_derived_operation(&"cleaned", cleaned_result)
		)
	)
	assert_true(saga.settle_derived_operation() == OK)
	assert_true(saga.complete_derived_cleanup(ERR_CANT_OPEN))

	var evidence: Dictionary = saga.make_terminal_evidence()
	assert_true(
		GFVariantData.get_option_string_name(evidence, &"status")
		== &"derived_partial"
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"derived_completed_count", 0)
		== 2
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"derived_failed_count", 0)
		== 1
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"busy_retry_count", 0)
		== 1
	)
	var derived_results: Array = GFVariantData.get_option_array(
		evidence,
		&"derived_results"
	)
	assert_true(derived_results.size() == 2)
	derived_results.clear()
	assert_true(
		GFVariantData.get_option_array(
			saga.make_terminal_evidence(),
			&"derived_results"
		).size()
		== 2,
		"公开 evidence 必须与 saga 内 typed 终态隔离。"
	)


func test_dispose_cancellation_is_owned_by_active_derived_handle() -> void:
	var operation: GFStorageAsyncOperation = _make_main_delete_operation(104)
	assert_true(_complete_main_delete(operation, OK))
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.create(
		_CANONICAL_NAME,
		&"inactive_profile_request",
		operation,
		false
	)
	assert_true(saga.settle_main_delete(OK))
	assert_true(saga.begin_derived_cleanup(1))
	var derived_operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	assert_true(
		derived_operation.configure_for_persistence(&"pending-derived")
	)
	assert_true(saga.bind_active_derived_operation(derived_operation))
	assert_true(saga.request_active_derived_cancel(&"save_graph_disposed"))
	assert_true(derived_operation.is_cancel_requested())
	assert_true(
		derived_operation.get_cancel_reason() == &"save_graph_disposed"
	)


# --- 私有/辅助方法 ---

func _make_main_delete_operation(request_id: int) -> GFStorageAsyncOperation:
	var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
	var _configured: bool = operation.configure_for_framework(
		request_id,
		GFStorageAsyncOperation.OPERATION_DELETE,
		_CANONICAL_NAME
	)
	return operation


func _complete_main_delete(
	operation: GFStorageAsyncOperation,
	error_code: Error
) -> bool:
	var delete_result: GFStorageDeleteResult = GFStorageDeleteResult.new()
	var _delete_configured: bool = delete_result.configure_for_framework(
		error_code,
		(
			GFStorageDeleteResult.FailureKind.NONE
			if error_code == OK
			else GFStorageDeleteResult.FailureKind.IO_FAILED
		),
		1,
		1 if error_code == OK else 0,
		0 if error_code == OK else 1,
		(
			GFStorageDeleteResult.FamilyMember.NONE
			if error_code == OK
			else GFStorageDeleteResult.FamilyMember.FINAL
		)
	)
	var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
	var _configured: bool = result.configure_for_framework(
		operation.get_request_id(),
		GFStorageAsyncOperation.OPERATION_DELETE,
		operation.get_file_name(),
		error_code == OK,
		error_code,
		null,
		GFStorageAsyncResult.WriteFailureKind.NONE,
		{},
		delete_result
	)
	return operation.complete_for_framework(result)


func _make_derived_operation(
	operation_id: StringName,
	result: ChunkProfileCleanupResult
) -> ChunkProfileCleanupOperation:
	var operation: ChunkProfileCleanupOperation = (
		ChunkProfileCleanupOperation.new()
	)
	var _configured: bool = operation.configure_for_persistence(operation_id)
	var _completed: bool = operation.complete_for_persistence(result)
	return operation


func _dictionary_contains_text(value: Variant, expected: String) -> bool:
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		for entry: Variant in dictionary_value.values():
			if _dictionary_contains_text(entry, expected):
				return true
		return false
	if value is Array:
		for entry: Variant in value:
			if _dictionary_contains_text(entry, expected):
				return true
		return false
	return value is String and value == expected
