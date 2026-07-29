extends GutTest


func test_profile_operation_is_untracked_on_framework_terminal() -> void:
	var tracker: GFAsyncTrackerUtility = _make_tracker()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	save_graph._async_tracker = tracker
	save_graph._signal_utility = signal_utility
	var operation: GFSaveProfileOperation = GFSaveProfileOperation.new()
	assert_true(
		operation.configure_for_framework(
			GFSaveProfileOperation.OPERATION_SAVE,
			&"test.profile",
			7,
			10
		)
	)

	var tracked_operation: GFSaveProfileOperation = (
		save_graph._track_profile_operation(operation)
	)
	assert_same(tracked_operation, operation)
	_assert_single_label(tracker, &"game_save.profile_operation")

	var result: GFSaveProfileResult = GFSaveProfileResult.new()
	result.configure_for_framework(
		true,
		GFSaveProfileResult.STATUS_SAVED,
		GFSaveProfileOperation.OPERATION_SAVE,
		&"test.profile",
		7,
		7,
		1,
		10,
		20
	)
	assert_true(operation.complete_for_framework(result))
	assert_true(operation.emit_completed_for_framework())
	assert_true(tracker.get_active_records().is_empty())

	signal_utility.dispose()
	tracker.dispose()


func test_section_operation_is_untracked_on_project_terminal() -> void:
	var tracker: GFAsyncTrackerUtility = _make_tracker()
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	save_graph._async_tracker = tracker
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	assert_true(
		operation.configure_for_utility(
			17,
			&"test.profile",
			PackedStringArray([GameSaveGraphUtility.BOOKMARKS_SECTION_ID])
		)
	)

	save_graph._track_section_operation(operation)
	_assert_single_label(tracker, &"game_save.section_operation")
	save_graph._complete_detached_section_operation(
		operation,
		GameSaveSectionResult.STATUS_BUSY,
		ERR_BUSY
	)

	assert_true(operation.is_completed())
	assert_true(tracker.get_active_records().is_empty())
	tracker.dispose()


func test_local_account_operation_is_untracked_on_typed_terminal() -> void:
	var tracker: GFAsyncTrackerUtility = _make_tracker()
	var account_system: LocalAccountSystem = LocalAccountSystem.new()
	account_system._async_tracker = tracker
	var operation: LocalAccountOperation = LocalAccountOperation.new()
	assert_true(
		operation.configure_for_system(
			LocalAccountOperation.OPERATION_SWITCH,
			"account-b"
		)
	)

	account_system._track_account_operation(operation)
	_assert_single_label(tracker, &"local_account.operation")
	account_system._complete_account_operation(
		operation,
		LocalAccountOperationResult.STATUS_BUSY,
		ERR_BUSY
	)

	assert_true(operation.is_completed())
	assert_true(tracker.get_active_records().is_empty())
	tracker.dispose()


func test_catalog_detached_storage_is_tracked_until_real_terminal() -> void:
	var tracker: GFAsyncTrackerUtility = _make_tracker()
	var catalog: LocalAccountCatalogUtility = LocalAccountCatalogUtility.new()
	catalog._async_tracker = tracker
	var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
	assert_true(
		operation.configure_for_framework(
			31,
			GFStorageAsyncOperation.OPERATION_SAVE,
			LocalAccountCatalogUtility.CATALOG_FILE_NAME
		)
	)
	catalog._track_storage_operation(operation)
	catalog._detached_storage_operations[operation.get_request_id()] = {
		&"operation": operation,
		&"payload": {},
		&"previous_active_account_id": "",
	}
	_assert_single_label(tracker, &"local_account.catalog_storage")

	var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
	assert_true(
		result.configure_for_framework(
			operation.get_request_id(),
			operation.get_operation(),
			operation.get_file_name(),
			false,
			ERR_CANT_CREATE
		)
	)
	assert_true(operation.complete_for_framework(result))
	catalog._poll_catalog_storage_operations()

	assert_true(catalog._detached_storage_operations.is_empty())
	assert_true(tracker.get_active_records().is_empty())
	tracker.dispose()


# --- 私有/辅助方法 ---

func _make_tracker() -> GFAsyncTrackerUtility:
	var tracker: GFAsyncTrackerUtility = GFAsyncTrackerUtility.new()
	tracker.tracking_enabled = true
	return tracker


func _assert_single_label(
	tracker: GFAsyncTrackerUtility,
	expected_label: StringName
) -> void:
	var records: Array[Dictionary] = tracker.get_active_records()
	assert_true(records.size() == 1)
	if records.size() != 1:
		return
	assert_true(
		GFVariantData.get_option_string_name(records[0], &"label")
		== expected_label
	)
