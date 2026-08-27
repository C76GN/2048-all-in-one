## LocalAccountReconciliationSaga 的 tagged state、重臂与一次性 effect 回归。
extends GutTest


func test_catalog_and_profile_factories_create_one_discriminated_state() -> void:
	var account: LocalPlayerAccount = _make_account("A", 1_000)
	var catalog_operation: LocalAccountOperation = _make_operation(
		LocalAccountOperation.OPERATION_CREATE
	)
	var catalog_saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			catalog_operation,
			account,
			"previous"
		)
	)
	assert_not_null(catalog_saga)
	assert_true(
		catalog_saga.is_catalog_compensation()
		and not catalog_saga.is_profile_alignment()
		and catalog_saga.get_kind()
		== LocalAccountReconciliationSaga.KIND_CATALOG_COMPENSATION
		and catalog_saga.get_phase()
		== LocalAccountReconciliationSaga.PHASE_WAITING
		and catalog_saga.is_waiting_for_catalog_settlement()
	)

	var profile_operation: LocalAccountOperation = _make_operation(
		LocalAccountOperation.OPERATION_SWITCH,
		account.account_id
	)
	var profile_saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_profile_alignment(
			profile_operation,
			account,
			"previous",
			&"player_data.pending"
		)
	)
	assert_not_null(profile_saga)
	assert_true(
		profile_saga.is_profile_alignment()
		and not profile_saga.is_catalog_compensation()
		and profile_saga.get_kind()
		== LocalAccountReconciliationSaga.KIND_PROFILE_ALIGNMENT
		and profile_saga.is_waiting_for_profile_settlement()
	)


func test_catalog_settlement_claims_runner_and_publication_once() -> void:
	var account: LocalPlayerAccount = _make_account("B", 2_000)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			_make_operation(LocalAccountOperation.OPERATION_CREATE),
			account,
			"previous"
		)
	)
	var result: GFStorageAsyncResult = _make_storage_result(true, OK)
	assert_true(saga.accept_catalog_settlement(result, OK, "previous", account.account_id))
	assert_true(saga.is_ready())
	assert_true(saga.begin_run())
	assert_false(saga.begin_run(), "同一 tagged state 只能授予一个 runner。")
	assert_true(saga.claim_catalog_success_publication())
	assert_false(
		saga.claim_catalog_success_publication(),
		"目录成功 publication effect 必须只能认领一次。"
	)
	assert_true(saga.complete())
	assert_false(saga.is_pending())


func test_catalog_apply_failure_remains_fail_closed() -> void:
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			_make_operation(LocalAccountOperation.OPERATION_RENAME),
			null,
			"previous"
		)
	)
	assert_true(
		saga.accept_catalog_settlement(
			_make_storage_result(true, OK),
			ERR_INVALID_DATA,
			"previous",
			"active"
		)
	)
	assert_true(
		saga.get_phase() == LocalAccountReconciliationSaga.PHASE_WAITING
		and saga.is_blocked_by_catalog_apply_failure()
	)
	assert_false(
		saga.accept_profile_settled_idle(&"player_data.unrelated"),
		"落盘成功但候选 apply 失败时不得接纳无关证据绕过栅栏。"
	)
	assert_false(saga.begin_run())


func test_profile_alignment_rebinds_exact_unknown_profile_before_retry() -> void:
	var account: LocalPlayerAccount = _make_account("C", 3_000)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_profile_alignment(
			_make_operation(
				LocalAccountOperation.OPERATION_SWITCH,
				account.account_id
			),
			account,
			"previous",
			&"player_data.first"
		)
	)
	assert_true(saga.accept_profile_settled_idle(&"player_data.first"))
	assert_true(saga.begin_run())
	assert_true(saga.wait_for_profile_settlement(&"player_data.second"))
	assert_true(
		saga.get_profile_id() == &"player_data.second"
		and saga.get_phase() == LocalAccountReconciliationSaga.PHASE_WAITING
	)
	assert_false(saga.accept_profile_settled_idle(&"player_data.first"))
	assert_false(saga.accept_profile_settled_idle(&""))
	assert_true(saga.is_waiting_for_profile_settlement())
	assert_false(saga.begin_run())
	assert_true(saga.accept_profile_settled_idle(&"player_data.second"))
	assert_true(saga.begin_run())
	assert_true(saga.complete())


func test_cleanup_is_catalog_subphase_and_requires_explicit_retry() -> void:
	var account: LocalPlayerAccount = _make_account("D", 4_000)
	var profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(account.account_id)
	)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_cleanup_compensation(
			_make_operation(
				LocalAccountOperation.OPERATION_DELETE,
				account.account_id
			),
			account,
			"previous",
			profile_file,
			account.account_id,
			FAILED
		)
	)
	assert_not_null(saga)
	assert_true(
		saga.is_catalog_compensation()
		and saga.is_cleanup_required()
		and saga.is_cleanup_only()
		and saga.is_cleanup_retry_explicit_required()
		and saga.get_phase()
		== LocalAccountReconciliationSaga.PHASE_RETRY_REQUIRED
	)
	assert_false(
		saga.accept_cleanup_terminal(profile_file),
		"确定性失败不得被 cleanup terminal 自动重臂。"
	)
	assert_true(saga.rearm_cleanup_retry())
	assert_true(saga.begin_run())
	assert_true(saga.require_cleanup_retry())
	assert_true(saga.rearm_cleanup_retry())


func test_cleanup_timeout_waits_for_terminal_before_runner() -> void:
	var account: LocalPlayerAccount = _make_account("E", 5_000)
	var profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(account.account_id)
	)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_cleanup_compensation(
			_make_operation(
				LocalAccountOperation.OPERATION_DELETE,
				account.account_id
			),
			account,
			"previous",
			profile_file,
			account.account_id,
			ERR_TIMEOUT
		)
	)
	assert_true(
		saga.is_cleanup_pending()
		and saga.get_phase() == LocalAccountReconciliationSaga.PHASE_WAITING
	)
	var other_account: LocalPlayerAccount = _make_account("Other", 5_100)
	var other_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			other_account.account_id
		)
	)
	assert_false(saga.accept_cleanup_terminal(other_profile_file))
	assert_false(saga.accept_cleanup_terminal(""))
	assert_true(saga.is_waiting_for_cleanup_terminal())
	assert_false(saga.begin_run())
	assert_true(saga.accept_cleanup_terminal(profile_file))
	assert_true(saga.begin_run())
	assert_true(saga.wait_for_cleanup_terminal())
	assert_true(saga.is_cleanup_pending())


func test_retained_create_candidate_effect_is_once_and_snapshot_isolated() -> void:
	var account: LocalPlayerAccount = _make_account("F", 6_000)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			_make_operation(LocalAccountOperation.OPERATION_CREATE),
			account,
			"previous"
		)
	)
	var snapshot: Dictionary = saga.make_state_snapshot()
	snapshot[&"operation"] = &"tampered"
	assert_true(saga.get_operation() == LocalAccountOperation.OPERATION_CREATE)
	assert_true(saga.get_retained_create_candidate_id() == account.account_id)
	assert_true(saga.mark_retained_create_candidate_published())
	assert_true(saga.get_retained_create_candidate_id().is_empty())
	assert_false(saga.mark_retained_create_candidate_published())


func test_storage_evidence_snapshot_is_deeply_copy_isolated() -> void:
	var account: LocalPlayerAccount = _make_account("Nested", 6_500)
	var saga: LocalAccountReconciliationSaga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			_make_operation(LocalAccountOperation.OPERATION_CREATE),
			account,
			"previous"
		)
	)
	assert_true(
		saga.accept_catalog_settlement(
			_make_storage_result(true, OK),
			OK,
			"previous",
			account.account_id
		)
	)
	var snapshot: Dictionary = saga.make_state_snapshot()
	var storage_result: Dictionary = snapshot[&"storage_result"]
	var read_result: Dictionary = storage_result[&"read_result"]
	read_result[&"tampered"] = true
	storage_result[&"read_result"] = read_result
	snapshot[&"storage_result"] = storage_result
	var current_storage_result: Dictionary = saga.get_storage_result()
	var current_read_result: Dictionary = GFVariantData.get_option_dictionary(
		current_storage_result,
		&"read_result"
	)
	assert_false(
		current_read_result.has(&"tampered"),
		"嵌套 storage evidence 不得通过诊断快照反向篡改 Saga。"
	)


func test_cleanup_factory_rejects_untrusted_profile_path() -> void:
	var account: LocalPlayerAccount = _make_account("G", 7_000)
	assert_null(
		LocalAccountReconciliationSaga.create_cleanup_compensation(
			_make_operation(
				LocalAccountOperation.OPERATION_DELETE,
				account.account_id
			),
			account,
			"previous",
			"profiles/other-profile.json",
			account.account_id,
			ERR_TIMEOUT
		)
	)


func test_catalog_saga_dispose_freezes_evidence_and_ignores_late_terminal() -> void:
	var account: LocalPlayerAccount = _make_account("H", 8_000)
	var accounts: LocalAccountSystem = LocalAccountSystem.new()
	accounts._reconciliation_saga = (
		LocalAccountReconciliationSaga.create_catalog_compensation(
			_make_operation(LocalAccountOperation.OPERATION_CREATE),
			account,
			"previous"
		)
	)
	accounts._last_reconciliation_evidence = {
		&"status": &"catalog_outcome_unknown",
	}
	watch_signals(accounts)
	accounts.dispose()
	var frozen: Dictionary = accounts.get_last_reconciliation_evidence()
	assert_true(
		GFVariantData.get_option_string_name(frozen, &"status")
		== &"disposed_before_reconciliation"
		and not accounts.is_account_reconciliation_pending()
	)
	accounts._on_catalog_storage_late_settled(
		_make_storage_result(true, OK),
		OK,
		"previous",
		account.account_id
	)
	accounts.tick()
	assert_true(accounts.get_last_reconciliation_evidence() == frozen)
	assert_signal_emit_count(
		accounts,
		"account_reconciliation_state_changed",
		0
	)


func test_profile_saga_dispose_freezes_evidence_and_ignores_late_idle() -> void:
	var account: LocalPlayerAccount = _make_account("I", 9_000)
	var accounts: LocalAccountSystem = LocalAccountSystem.new()
	accounts._reconciliation_saga = (
		LocalAccountReconciliationSaga.create_profile_alignment(
			_make_operation(
				LocalAccountOperation.OPERATION_SWITCH,
				account.account_id
			),
			account,
			"previous",
			&"player_data.pending"
		)
	)
	accounts._last_reconciliation_evidence = {
		&"status": &"profile_outcome_unknown",
	}
	watch_signals(accounts)
	accounts.dispose()
	var frozen: Dictionary = accounts.get_last_reconciliation_evidence()
	assert_true(
		GFVariantData.get_option_string_name(frozen, &"status")
		== &"disposed_before_profile_reconciliation"
		and not accounts.is_account_reconciliation_pending()
	)
	accounts._on_profile_state_changed(
		&"player_data.pending",
		GFSaveProfileUtility.STATE_SAVING,
		GFSaveProfileUtility.STATE_IDLE
	)
	accounts.tick()
	assert_true(accounts.get_last_reconciliation_evidence() == frozen)
	assert_signal_emit_count(
		accounts,
		"account_reconciliation_state_changed",
		0
	)


# --- 私有/辅助方法 ---

func _make_account(display_name: String, timestamp: int) -> LocalPlayerAccount:
	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		display_name,
		timestamp
	)
	assert_not_null(account)
	return account


func _make_operation(
	kind: StringName,
	target_account_id: String = ""
) -> LocalAccountOperation:
	var operation: LocalAccountOperation = LocalAccountOperation.new()
	assert_true(operation.configure_for_system(kind, target_account_id))
	return operation


func _make_storage_result(
	ok: bool,
	error_code: Error
) -> GFStorageAsyncResult:
	var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
	assert_true(
		result.configure_for_framework(
			1,
			GFStorageAsyncOperation.OPERATION_SAVE,
			"local_accounts",
			ok,
			error_code
		)
	)
	return result
