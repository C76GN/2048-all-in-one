## 验证本地多账号 Profile、个人统计与设备榜单。
extends GutTest


const _TEST_PLATFORM_STUB_SCRIPT: GDScript = preload(
	"res://tests/gut/fixtures/test_game_platform_utility_stub.gd"
)
const _MODE_ID: String = "classic_2048"
const _BOARD_KEY: String = "board.rectangle.4x4@test"
const _RULESET_ID: StringName = &"rules.classic"
const _RULESET_FINGERPRINT: String = (
	"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)


func test_startup_bootstraps_account_profile_without_full_legacy_load() -> void:
	var storage: _LegacyProfileReadCountingStorage = (
		_LegacyProfileReadCountingStorage.new()
	)
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var active_account: LocalPlayerAccount = accounts.get_active_account()

	assert_not_null(active_account)
	assert_true(save_graph.is_profile_loaded())
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(
			active_account.account_id
		),
		"启动完成后 SaveGraph 应直接指向当前账号 Profile。"
	)
	assert_true(
		storage.legacy_profile_async_read_count == 0,
		"新安装启动不得先通过 GFSaveProfile 完整加载旧默认 Profile。"
	)
	_dispose_setup(setup)


func test_local_account_strict_shape_and_name_normalization() -> void:
	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		"  玩家\u0001一号  ",
		100
	)
	assert_not_null(account)
	assert_true(account.display_name == "玩家一号")
	assert_not_null(LocalPlayerAccount.from_dict(account.to_dict()))

	var unknown_field: Dictionary = account.to_dict()
	unknown_field[&"legacy"] = true
	assert_null(
		LocalPlayerAccount.from_dict(unknown_field),
		"本地账号身份不得接受未知字段。"
	)
	assert_true(
		LocalPlayerAccount.normalize_display_name("123456789012345678901234567")
		.length() == LocalPlayerAccount.MAX_DISPLAY_NAME_LENGTH
	)


func test_async_account_operations_expose_terminal_results_without_ui_blocking() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)

	var create_operation: LocalAccountOperation = (
		accounts.request_create_account("异步账号")
	)
	assert_true(
		create_operation.is_pending(),
		"账号请求应先返回 pending 句柄，不在 UI 回调中同步等待磁盘。"
	)
	var create_result: LocalAccountOperationResult = (
		await _await_account_operation(create_operation, setup)
	)
	assert_true(
		create_result != null and create_result.is_successful(),
		"创建账号应到达唯一 typed success 终态。"
	)
	var second: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(second)
	assert_true(second.account_id != first.account_id)

	var rename_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_rename_account(
				second.account_id,
				"异步账号已重命名"
			),
			setup,
			"重命名账号应到达唯一 typed success 终态。"
		)
	)
	assert_not_null(rename_result)
	second = accounts.get_active_account()
	assert_true(second.display_name == "异步账号已重命名")

	var switch_operation: LocalAccountOperation = (
		accounts.request_switch_account(first.account_id)
	)
	var busy_operation: LocalAccountOperation = (
		accounts.request_switch_account(second.account_id)
	)
	assert_true(
		busy_operation.is_completed()
		and busy_operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_BUSY,
		"同一时刻只允许一个账号事务。"
	)
	var switch_result: LocalAccountOperationResult = (
		await _await_account_operation(switch_operation, setup)
	)
	assert_true(
		switch_result != null
		and switch_result.is_successful()
		and accounts.get_active_account().account_id == first.account_id,
		"异步切换应在 Profile 与目录都提交后才报告成功。"
	)
	assert_true(
		not switch_result.get_profile_evidence().is_empty(),
		"账号终态应保留 GF Save Profile 证据。"
	)

	var delete_operation: LocalAccountOperation = (
		accounts.request_delete_account(second.account_id)
	)
	var delete_result: LocalAccountOperationResult = (
		await _await_account_operation(delete_operation, setup)
	)
	assert_true(
		delete_result != null
		and delete_result.is_successful()
		and accounts.get_accounts().size() == 1,
		"异步删除应在目录与孤立 Profile 清理边界后终结。"
	)
	_dispose_setup(setup)


func test_catalog_late_create_success_publishes_catalog_once_and_unblocks_ui() -> void:
	var storage: _DelayedCatalogStorage = _DelayedCatalogStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(storage, clock)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var probe: _AccountEventProbe = _get_account_event_probe(setup)
	var original: LocalPlayerAccount = accounts.get_active_account()
	watch_signals(accounts)
	watch_signals(catalog)
	storage.arm_next_catalog_write(OK)

	var operation: LocalAccountOperation = accounts.request_create_account(
		"迟到创建账号"
	)
	await _advance_catalog_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	assert_true(
		operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
	)
	assert_true(accounts.is_account_reconciliation_pending())
	var blocked: LocalAccountOperation = accounts.request_switch_account(
		original.account_id
	)
	assert_true(
		blocked.is_completed()
		and blocked.get_result().get_status()
		== LocalAccountOperationResult.STATUS_BUSY,
		"迟到终态收敛前，即使目标是目录当前账号也不得走 no-op。"
	)

	await _await_account_reconciliation(accounts, setup)
	assert_false(accounts.is_account_reconciliation_pending())
	assert_true(accounts.get_accounts().size() == 2)
	assert_true(accounts.get_active_account().account_id == original.account_id)
	assert_signal_emit_count(accounts, "active_account_changed", 0)
	assert_signal_emit_count(accounts, "account_catalog_changed", 1)
	assert_signal_emit_count(catalog, "active_account_changed", 0)
	assert_signal_emit_count(catalog, "account_catalog_changed", 1)
	assert_true(probe.active_account_event_count == 0)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"catalog_late_success_reconciled"
	)
	_dispose_setup(setup)


func test_catalog_late_switch_failure_rolls_profile_back_before_unblocking() -> void:
	var storage: _DelayedCatalogStorage = _DelayedCatalogStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(storage, clock)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var probe: _AccountEventProbe = _get_account_event_probe(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("迟到切换二号"),
			setup,
			"迟到切换测试的第二账号必须先异步创建成功。"
		)
	)
	assert_not_null(create_result)
	var second: LocalPlayerAccount = accounts.get_active_account()
	probe.reset()
	watch_signals(accounts)
	watch_signals(catalog)
	storage.arm_next_catalog_write(ERR_CANT_CREATE)

	var operation: LocalAccountOperation = accounts.request_switch_account(
		first.account_id
	)
	await _advance_catalog_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	assert_true(
		operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
	)
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(first.account_id)
		and accounts.get_active_account().account_id == second.account_id,
		"目录写真实终态未知时会暂时存在必须协调的双边状态。"
	)
	var blocked: LocalAccountOperation = accounts.request_switch_account(
		second.account_id
	)
	assert_true(
		blocked.is_completed()
		and blocked.get_result().get_status()
		== LocalAccountOperationResult.STATUS_BUSY
	)

	await _await_account_reconciliation(accounts, setup)
	assert_false(accounts.is_account_reconciliation_pending())
	assert_true(accounts.get_active_account().account_id == second.account_id)
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(second.account_id),
		"目录迟到失败后必须恢复目录权威账号的 Profile，不能保留跨账号错配。"
	)
	assert_signal_emit_count(accounts, "active_account_changed", 0)
	assert_signal_emit_count(accounts, "account_catalog_changed", 0)
	assert_signal_emit_count(catalog, "active_account_changed", 0)
	assert_signal_emit_count(catalog, "account_catalog_changed", 0)
	assert_true(probe.active_account_event_count == 0)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"catalog_late_failure_rolled_back"
	)
	_dispose_setup(setup)


func test_catalog_late_delete_active_success_publishes_one_account_change() -> void:
	var storage: _DelayedCatalogStorage = _DelayedCatalogStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(storage, clock)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var probe: _AccountEventProbe = _get_account_event_probe(setup)
	var fallback: LocalPlayerAccount = accounts.get_active_account()
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("迟到删除账号"),
			setup,
			"迟到删除测试的目标账号必须先异步创建成功。"
		)
	)
	assert_not_null(create_result)
	var deleted: LocalPlayerAccount = accounts.get_active_account()
	var deleted_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			deleted.account_id
		)
	)
	probe.reset()
	watch_signals(accounts)
	watch_signals(catalog)
	storage.arm_next_catalog_write(OK)

	var operation: LocalAccountOperation = accounts.request_delete_account(
		deleted.account_id
	)
	await _advance_catalog_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	assert_true(
		operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_CATALOG_OUTCOME_UNKNOWN
	)
	await _await_account_reconciliation(accounts, setup)

	assert_false(accounts.is_account_reconciliation_pending())
	assert_true(accounts.get_accounts().size() == 1)
	assert_true(accounts.get_active_account().account_id == fallback.account_id)
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(fallback.account_id)
	)
	assert_signal_emit_count(accounts, "active_account_changed", 1)
	assert_signal_emit_count(accounts, "account_catalog_changed", 1)
	assert_signal_emit_count(catalog, "active_account_changed", 1)
	assert_signal_emit_count(catalog, "account_catalog_changed", 1)
	assert_true(probe.active_account_event_count == 1)
	assert_true(probe.last_previous_account_id == deleted.account_id)
	assert_true(probe.last_account_id == fallback.account_id)
	var deleted_profile_read: GFStorageReadResult = storage.load_data(
		deleted_profile_file
	)
	assert_true(
		not deleted_profile_read.ok
		and deleted_profile_read.error_code == ERR_FILE_NOT_FOUND,
		"目录迟到删除成功后，协调锁必须等目标 Profile 清理完成再解除。"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"catalog_late_success_cleanup_succeeded"
	)
	_dispose_setup(setup)


func test_delete_cleanup_outcome_unknown_blocks_until_late_terminal() -> void:
	var save_graph: _TimeoutCleanupSaveGraph = (
		_TimeoutCleanupSaveGraph.new()
	)
	var setup: Dictionary = await _create_setup(null, null, save_graph)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("清理迟到账号"),
			setup,
			"清理迟到测试的第二账号必须创建成功。"
		)
	)
	assert_not_null(create_result)
	var deleted: LocalPlayerAccount = accounts.get_active_account()
	var deleted_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			deleted.account_id
		)
	)
	save_graph.arm_next_cleanup_timeout(deleted_profile_file)
	var delete_operation: LocalAccountOperation = (
		accounts.request_delete_account(deleted.account_id)
	)
	var delete_result: LocalAccountOperationResult = (
		await _await_account_operation(delete_operation, setup)
	)
	assert_true(
		delete_result != null
		and delete_result.get_status()
		== LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
		and accounts.is_account_reconciliation_pending(),
		"正常删除的 cleanup timeout 也必须建立协调锁。"
	)
	var blocked: LocalAccountOperation = accounts.request_rename_account(
		first.account_id,
		"清理未终结时不可重命名"
	)
	assert_true(
		blocked.is_completed()
		and blocked.get_result().get_status()
		== LocalAccountOperationResult.STATUS_BUSY
	)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"cleanup_outcome_unknown"
	)
	save_graph.settle_cleanup_timeout(deleted_profile_file)
	await _await_account_reconciliation(accounts, setup)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"cleanup_outcome_unknown_reconciled"
	)
	var storage_value: Variant = setup.get(&"storage")
	assert_true(storage_value is GFStorageUtility)
	var storage: GFStorageUtility = storage_value
	var deleted_profile_read: GFStorageReadResult = storage.load_data(
		deleted_profile_file
	)
	assert_true(
		not deleted_profile_read.ok
		and deleted_profile_read.error_code == ERR_FILE_NOT_FOUND
	)
	_dispose_setup(setup)


func test_cleanup_terminal_before_reconciliation_is_observed_by_tick_query() -> void:
	var save_graph: _TimeoutCleanupSaveGraph = (
		_TimeoutCleanupSaveGraph.new()
	)
	var setup: Dictionary = await _create_setup(null, null, save_graph)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("清理竞态账号"),
			setup,
			"清理竞态测试的第二账号必须创建成功。"
		)
	)
	assert_not_null(create_result)
	var deleted: LocalPlayerAccount = accounts.get_active_account()
	var deleted_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			deleted.account_id
		)
	)
	save_graph.arm_next_cleanup_timeout(deleted_profile_file, true)
	var delete_result: LocalAccountOperationResult = (
		await _await_account_operation(
			accounts.request_delete_account(deleted.account_id),
			setup
		)
	)
	assert_true(
		delete_result != null
		and delete_result.get_status()
		== LocalAccountOperationResult.STATUS_CLEANUP_OUTCOME_UNKNOWN
		and accounts.is_account_reconciliation_pending()
	)
	await _await_account_reconciliation(accounts, setup)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"cleanup_outcome_unknown_reconciled",
		"cleanup terminal 早于 reconciliation 建立时，tick 查询必须发现所有权已释放。"
	)
	_dispose_setup(setup)


func test_profile_outcome_unknown_keeps_account_and_path_until_late_settle() -> void:
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(storage, clock)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	watch_signals(accounts)
	var architecture_value: Variant = setup.get(&"architecture")
	assert_true(architecture_value is GFArchitecture)
	var architecture: GFArchitecture = architecture_value
	storage.hang_profile_writes = true
	var operation: LocalAccountOperation = accounts.request_create_account(
		"结果未知账号"
	)
	for _frame: int in range(120):
		architecture.tick(0.0)
		await get_tree().process_frame
		if not storage.hanging_operations.is_empty():
			break
	assert_false(storage.hanging_operations.is_empty())

	for delta_msec: int in [5_000, 100, 5_000, 500, 5_000, 1_500, 5_000]:
		assert_true(clock.advance_msec(delta_msec))
		architecture.tick(0.0)
		await get_tree().process_frame

	var result: LocalAccountOperationResult = operation.get_result()
	assert_not_null(result)
	assert_true(
		result != null
		and result.get_status()
		== LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN,
		"写入重试耗尽且仍有 detached 请求时必须报告专门 outcome_unknown。"
	)
	var unknown_account: LocalPlayerAccount = (
		result.get_account() if result != null else null
	)
	assert_not_null(unknown_account)
	if unknown_account == null:
		_dispose_setup(setup)
		return
	var profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			unknown_account.account_id
		)
	)
	var busy_cleanup_error: Error = await _await_profile_cleanup(
		save_graph,
		profile_file,
		setup
	)
	assert_true(
		accounts.get_accounts().size() == 2
		and busy_cleanup_error == ERR_BUSY,
		"结果未知时必须保留目录项、框架注册和路径所有权。"
	)
	assert_true(
		accounts.is_account_reconciliation_pending()
		and accounts.request_account_reconciliation() == ERR_BUSY,
		"Profile 迟到终态未收敛前必须保留账号协调锁。"
	)
	var blocked_operation: LocalAccountOperation = (
		accounts.request_rename_account(
			unknown_account.account_id,
			"不应在迟到写期间重命名"
		)
	)
	assert_true(
		blocked_operation.is_completed()
		and blocked_operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_BUSY,
		"Profile outcome_unknown 后不得接受新的账号事务。"
	)

	storage.complete_all_hanging(OK)
	await _await_account_reconciliation(accounts, setup)
	assert_true(
		GFVariantData.get_option_string_name(
			accounts.get_last_reconciliation_evidence(),
			&"status"
		)
		== &"profile_outcome_unknown_reconciled"
	)
	assert_signal_emit_count(accounts, "active_account_changed", 0)
	assert_signal_emit_count(accounts, "account_catalog_changed", 1)
	var settled_cleanup_error: Error = await _await_profile_cleanup(
		save_graph,
		profile_file,
		setup
	)
	assert_true(
		settled_cleanup_error == OK,
		"所有迟到写入终结后才允许注销并清理该 Profile 路径。"
	)
	_dispose_setup(setup)


func test_profile_reconciliation_publishes_late_active_create_once() -> void:
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_setup(storage, clock)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var probe: _AccountEventProbe = _get_account_event_probe(setup)
	var previous: LocalPlayerAccount = accounts.get_active_account()
	storage.hang_profile_writes = true
	var operation: LocalAccountOperation = accounts.request_create_account(
		"迟到激活账号"
	)
	await _advance_profile_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	var result: LocalAccountOperationResult = operation.get_result()
	var created: LocalPlayerAccount = (
		result.get_account() if result != null else null
	)
	assert_not_null(created)
	if created == null:
		_dispose_setup(setup)
		return
	assert_true(
		await _await_catalog_activation(
			catalog,
			created.account_id,
			setup
		)
		== OK
	)
	assert_true(
		catalog.get_active_account_id() == created.account_id
		and save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(
			previous.account_id
		)
	)
	probe.reset()
	watch_signals(accounts)
	storage.hang_profile_writes = false
	storage.complete_all_hanging(OK)
	await _await_account_reconciliation(accounts, setup)
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(
			created.account_id
		)
	)
	assert_signal_emit_count(accounts, "active_account_changed", 1)
	assert_signal_emit_count(accounts, "account_catalog_changed", 1)
	assert_true(
		probe.active_account_event_count == 1
		and probe.last_previous_account_id == previous.account_id
		and probe.last_account_id == created.account_id,
		"目录权威账号已是迟到创建账号时，协调成功必须只发布一次账号切换事件。"
	)
	_dispose_setup(setup)


func test_accounts_keep_independent_profiles_and_mode_summaries() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 1024) == OK)

	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("第二位玩家"),
			setup,
			"第二位玩家必须通过类型化账号事务创建成功。"
		)
	)
	assert_not_null(create_result)
	var second: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(second)
	assert_true(second.account_id != first.account_id)
	assert_true(
		progress.get_high_score(_MODE_ID, _BOARD_KEY) == 0,
		"新账号必须从独立空 Profile 开始。"
	)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 2048) == OK)
	var switch_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_switch_account(first.account_id),
			setup,
			"切回首个账号必须通过类型化账号事务成功。"
		)
	)
	assert_not_null(switch_result)
	assert_true(
		progress.get_high_score(_MODE_ID, _BOARD_KEY) == 1024,
		"切回账号必须恢复其独立统计。"
	)
	var profile_snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	var summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(
			profile_snapshot,
			first.account_id
		)
	)
	assert_true(summaries.size() == 1)
	assert_true(
		GFVariantData.get_option_int(summaries[0], &"best_score", 0)
		== 1024
	)

	_dispose_setup(setup)


func test_deleting_active_account_rolls_back_without_transient_signals() -> void:
	var storage: _FailingCatalogStorage = _FailingCatalogStorage.new()
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 1024) == OK)
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("删除回滚账号"),
			setup,
			"删除回滚测试的目标账号必须先异步创建成功。"
		)
	)
	assert_not_null(create_result)
	var deleted_candidate: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(deleted_candidate)
	assert_true(deleted_candidate.account_id != first.account_id)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 2048) == OK)

	var accounts_before: Array[Dictionary] = _snapshot_accounts(accounts)
	var profile_before: String = save_graph.get_profile_file_name()
	var catalog_save_attempts_before: int = (
		storage.catalog_save_attempt_count
	)
	watch_signals(accounts)
	watch_signals(catalog)
	storage.next_catalog_save_error = ERR_CANT_CREATE

	var delete_result: LocalAccountOperationResult = (
		await _await_account_operation(
			accounts.request_delete_account(deleted_candidate.account_id),
			setup
		)
	)
	assert_true(
		delete_result != null
		and delete_result.get_status()
		== LocalAccountOperationResult.STATUS_CATALOG_FAILED
		and delete_result.get_error_code() == ERR_CANT_CREATE
	)
	assert_true(
		accounts.get_active_account().account_id
		== deleted_candidate.account_id,
		"目录删除失败后必须恢复原当前账号。"
	)
	assert_true(
		catalog.get_active_account_id() == deleted_candidate.account_id
	)
	assert_true(save_graph.get_profile_file_name() == profile_before)
	assert_true(
		progress.get_high_score(_MODE_ID, _BOARD_KEY) == 2048,
		"Profile 回滚后必须恢复原当前账号的 section 内存状态。"
	)
	assert_true(
		storage.catalog_save_attempt_count
		== catalog_save_attempts_before + 1,
		"删除当前账号应只提交一次原子目录写入。"
	)
	assert_true(
		GFVariantData.get_option_string(
			storage.last_failed_catalog_payload,
			&"active_account_id"
		) == first.account_id,
		"故障必须发生在已切换回退账号并移除目标账号的目录提交阶段。"
	)
	var attempted_accounts: Array = GFVariantData.get_option_array(
		storage.last_failed_catalog_payload,
		&"accounts"
	)
	assert_true(attempted_accounts.size() == 1)
	if attempted_accounts.size() == 1:
		assert_true(
			GFVariantData.get_option_string(
				GFVariantData.as_dictionary(attempted_accounts[0]),
				&"account_id"
			) == first.account_id
		)
	assert_true(
		_snapshot_accounts(accounts) == accounts_before,
		"账号集合、排序和时间戳必须完整回滚。"
	)
	assert_signal_emit_count(accounts, "active_account_changed", 0)
	assert_signal_emit_count(accounts, "account_catalog_changed", 0)
	assert_signal_emit_count(catalog, "active_account_changed", 0)
	assert_signal_emit_count(catalog, "account_catalog_changed", 0)

	_dispose_setup(setup)


func test_async_delete_catalog_failure_rolls_back_without_success_signal() -> void:
	var storage: _FailingCatalogStorage = _FailingCatalogStorage.new()
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var catalog: LocalAccountCatalogUtility = _get_account_catalog(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("异步删除故障账号"),
			setup,
			"异步删除故障测试的目标账号必须先创建成功。"
		)
	)
	assert_not_null(create_result)
	var target: LocalPlayerAccount = accounts.get_active_account()
	var accounts_before: Array[Dictionary] = _snapshot_accounts(accounts)
	watch_signals(accounts)
	watch_signals(catalog)
	storage.next_catalog_save_error = ERR_CANT_CREATE

	var operation: LocalAccountOperation = accounts.request_delete_account(
		target.account_id
	)
	var result: LocalAccountOperationResult = await _await_account_operation(
		operation,
		setup
	)

	assert_not_null(result)
	assert_true(
		result != null
		and result.get_status()
		== LocalAccountOperationResult.STATUS_CATALOG_FAILED
		and result.get_error_code() == ERR_CANT_CREATE,
		"异步目录写失败必须产生 typed catalog_failed 终态。"
	)
	assert_true(
		accounts.get_active_account().account_id == target.account_id
		and _snapshot_accounts(accounts) == accounts_before,
		"异步目录失败后必须恢复原 Profile 与目录权威状态。"
	)
	assert_signal_emit_count(accounts, "active_account_changed", 0)
	assert_signal_emit_count(accounts, "account_catalog_changed", 0)
	assert_signal_emit_count(catalog, "active_account_changed", 0)
	assert_signal_emit_count(catalog, "account_catalog_changed", 0)
	assert_true(first.account_id != target.account_id)
	_dispose_setup(setup)


func test_device_leaderboard_uses_each_accounts_best_result() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var first_save: GameSaveSectionResult = await _record_game_result(
		progress,
		_make_result(4096, 40, 2048, 100, 61_000),
		setup,
		61_000
	)
	var second_save: GameSaveSectionResult = await _record_game_result(
		progress,
		_make_result(2048, 30, 1024, 101, 42_000),
		setup,
		42_000
	)
	assert_true(first_save != null and first_save.is_successful())
	assert_true(second_save != null and second_save.is_successful())

	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("榜单二号"),
			setup,
			"榜单第二账号必须通过类型化账号事务创建成功。"
		)
	)
	assert_not_null(create_result)
	var second: LocalPlayerAccount = accounts.get_active_account()
	var third_save: GameSaveSectionResult = await _record_game_result(
		progress,
		_make_result(8192, 50, 4096, 102, 75_000),
		setup,
		75_000
	)
	assert_true(third_save != null and third_save.is_successful())

	var leaderboard_snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	var identities: Array[Dictionary] = (
		progress.get_device_leaderboard_identities(
			leaderboard_snapshot
		)
	)
	assert_true(identities.size() == 1)
	var rows: Array[Dictionary] = progress.get_device_local_leaderboard(
		leaderboard_snapshot,
		identities[0]
	)
	assert_true(rows.size() == 2)
	assert_true(
		GFVariantData.get_option_string(rows[0], &"account_id")
		== second.account_id
	)
	assert_true(
		GFVariantData.get_option_string(rows[1], &"account_id")
		== first.account_id
	)
	var first_result_value: Variant = GFVariantData.get_option_value(
		rows[1],
		&"result"
	)
	assert_true(first_result_value is GameResultRecordedData)
	if first_result_value is GameResultRecordedData:
		var first_result: GameResultRecordedData = first_result_value
		assert_true(
			first_result.score == 4096,
			"每个账号只应使用自己的最佳合格成绩。"
		)

	_dispose_setup(setup)


func test_device_progress_snapshot_reads_each_inactive_profile_once() -> void:
	var storage: _CountingProfileReadStorage = (
		_CountingProfileReadStorage.new()
	)
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)
	var second_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("快照二号"),
			setup,
			"第二个快照账号应创建成功。"
		)
	)
	assert_not_null(second_result)
	var third_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("快照三号"),
			setup,
			"第三个快照账号应创建成功。"
		)
	)
	assert_not_null(third_result)
	var active: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(active)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 8192) == OK)
	storage.reset_profile_load_request_count()

	var snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	assert_false(snapshot.is_empty())
	assert_true(
		storage.profile_load_request_count == 2,
		"三个账号的设备快照只应读取两个非活动 Profile。"
	)
	var summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(snapshot, active.account_id)
	)
	assert_true(
		summaries.size() == 1
		and GFVariantData.get_option_int(
			summaries[0],
			&"best_score",
			0
		) == 8192,
		"当前账号必须使用尚未落盘也已更新的最新内存 section。"
	)
	var _first_projection: Array[Dictionary] = (
		progress.get_device_leaderboard_identities(snapshot)
	)
	var _second_projection: Array[Dictionary] = (
		progress.get_device_leaderboard_identities(snapshot)
	)
	assert_true(
		storage.profile_load_request_count == 2,
		"同一快照的重复 UI 投影不得再次读取磁盘。"
	)
	_dispose_setup(setup)


func test_device_progress_snapshot_reports_corrupt_account_as_partial() -> void:
	var storage: _CountingProfileReadStorage = (
		_CountingProfileReadStorage.new()
	)
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 1024) == OK)
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("部分快照账号"),
			setup,
			"部分快照测试账号应创建成功。"
		)
	)
	assert_not_null(create_result)
	var active: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(active)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 2048) == OK)
	var corrupt_error: Error = storage.save_data(
		LocalAccountCatalogUtility.make_profile_file_name(first.account_id),
		{&"invalid_profile": true}
	)
	assert_true(corrupt_error == OK)
	storage.reset_profile_load_request_count()

	var snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	assert_true(
		GFVariantData.get_option_bool(snapshot, &"partial", false),
		"单个非活动账号损坏时应返回 partial 快照。"
	)
	var issues: Dictionary = GFVariantData.get_option_dictionary(
		snapshot,
		&"issues_by_account_id"
	)
	assert_true(issues.has(first.account_id))
	var summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(snapshot, active.account_id)
	)
	assert_true(
		summaries.size() == 1
		and GFVariantData.get_option_int(
			summaries[0],
			&"best_score",
			0
		) == 2048,
		"损坏账号不得阻断当前账号的可用统计。"
	)
	_dispose_setup(setup)


func test_cancelled_device_progress_snapshot_ignores_late_storage_result() -> void:
	var storage: _HangingProfileReadStorage = (
		_HangingProfileReadStorage.new()
	)
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("取消快照账号"),
			setup,
			"取消快照测试账号应创建成功。"
		)
	)
	assert_not_null(create_result)
	storage.hang_profile_reads = true
	var cancel_source: GFCancellationSource = GFCancellationSource.new()
	var completion: GFAsyncCompletion = (
		progress.request_device_progress_snapshot(
			cancel_source.get_token()
		)
	)
	assert_true(completion != null and completion.is_pending())
	assert_true(
		cancel_source.cancel(
			&"test_cancelled",
			{&"reason": "lifecycle"}
		)
	)
	await get_tree().process_frame
	assert_true(
		completion.is_cancelled()
		and completion.get_cancel_reason() == &"test_cancelled"
	)
	assert_true(
		progress._snapshot_contexts.is_empty(),
		"取消后必须释放批处理和所有 GFSignalConnection。"
	)
	storage.complete_all_hanging_reads(ERR_CANT_OPEN)
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.tick(0.0)
	await get_tree().process_frame
	assert_true(
		completion.is_cancelled(),
		"迟到存储终态不得覆盖已取消快照。"
	)
	cancel_source.dispose()
	_dispose_setup(setup)


func test_device_progress_snapshot_rejects_profile_catalog_transition_window() -> void:
	var storage: _DelayedCatalogStorage = _DelayedCatalogStorage.new()
	var setup: Dictionary = await _create_setup(storage)
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("快照切换账号"),
			setup,
			"快照一致性测试的第二账号必须创建成功。"
		)
	)
	assert_not_null(create_result)
	var second: LocalPlayerAccount = accounts.get_active_account()
	storage.arm_next_catalog_write(OK)
	var switch_operation: LocalAccountOperation = (
		accounts.request_switch_account(first.account_id)
	)
	var architecture_value: Variant = setup.get(&"architecture")
	assert_true(architecture_value is GFArchitecture)
	if not (architecture_value is GFArchitecture):
		_dispose_setup(setup)
		return
	var architecture: GFArchitecture = architecture_value
	for _frame: int in range(300):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		if storage.has_delayed_catalog_write_started():
			break
	assert_true(storage.has_delayed_catalog_write_started())
	assert_true(
		save_graph.get_profile_file_name()
		== LocalAccountCatalogUtility.make_profile_file_name(
			first.account_id
		)
		and accounts.get_active_account().account_id == second.account_id,
		"测试必须命中 Profile 已切换但目录尚未提交的事务窗口。"
	)
	var completion: GFAsyncCompletion = (
		progress.request_device_progress_snapshot()
	)
	assert_true(
		completion.is_failed()
		and GFVariantData.get_option_int(
			completion.get_metadata(),
			&"error_code",
			OK
		)
		== ERR_BUSY,
		"目录账号与当前 Profile 不一致时必须拒绝快照，不能错标跨账号统计。"
	)
	var switch_result: LocalAccountOperationResult = (
		await _await_account_operation(switch_operation, setup)
	)
	assert_true(switch_result != null and switch_result.is_successful())
	_dispose_setup(setup)


func test_duration_stats_are_profile_scoped_and_persisted() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	var first_save: GameSaveSectionResult = await _record_game_result(
		progress,
		_make_result(4096, 40, 2048, 100, 61_000),
		setup,
		61_000
	)
	var second_save: GameSaveSectionResult = await _record_game_result(
		progress,
		_make_result(2048, 30, 1024, 101, 42_000),
		setup,
		42_000
	)
	assert_true(first_save != null and first_save.is_successful())
	assert_true(second_save != null and second_save.is_successful())
	var duration_snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	var summaries: Array[Dictionary] = progress.get_profile_mode_summaries(
		duration_snapshot,
		first.account_id
	)
	assert_true(summaries.size() == 1)
	assert_true(
		GFVariantData.get_option_int(
			summaries[0],
			&"best_duration_msec",
			0
		) == 42_000
	)
	assert_true(
		GFVariantData.get_option_int(
			summaries[0],
			&"average_duration_msec",
			0
		) == 51_500
	)
	var create_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_create_account("时长隔离账号"),
			setup,
			"时长隔离账号必须通过类型化账号事务创建成功。"
		)
	)
	assert_not_null(create_result)
	var switch_result: LocalAccountOperationResult = (
		await _await_successful_account_operation(
			accounts.request_switch_account(first.account_id),
			setup,
			"时长统计必须通过类型化账号事务切回首个账号。"
		)
	)
	assert_not_null(switch_result)
	var restored_snapshot: Dictionary = await _await_progress_snapshot(
		progress,
		setup
	)
	var restored_summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(
			restored_snapshot,
			first.account_id
		)
	)
	assert_true(restored_summaries.size() == 1)
	assert_true(
		GFVariantData.get_option_int(
			restored_summaries[0],
			&"total_duration_msec",
			0
		) == 103_000
	)
	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _record_game_result(
	progress: ProgressStatsSystem,
	result: GameResultRecordedData,
	setup: Dictionary,
	duration_msec: int
) -> GameSaveSectionResult:
	var operation: GameSaveSectionOperation = progress.request_record_game_result(
		result,
		duration_msec
	)
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if not (architecture_value is GFArchitecture):
		return null
	var architecture: GFArchitecture = architecture_value
	return await GameSaveSectionOperationTestSupport.await_result(
		operation,
		architecture,
		get_tree()
	)


func _await_progress_snapshot(
	progress: ProgressStatsSystem,
	setup: Dictionary
) -> Dictionary:
	if progress == null:
		return {}
	var completion: GFAsyncCompletion = (
		progress.request_device_progress_snapshot()
	)
	if completion == null:
		return {}
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		for _frame: int in range(600):
			if completion.is_completed():
				break
			architecture.tick(1.0 / 60.0)
			await get_tree().process_frame
	if not completion.is_successful():
		return {}
	var result_value: Variant = completion.get_result()
	return (
		GFVariantData.as_dictionary(result_value)
		if result_value is Dictionary
		else {}
	)


func _await_profile_cleanup(
	save_graph: GameSaveGraphUtility,
	profile_file: String,
	setup: Dictionary
) -> Error:
	var result_box: Dictionary = {&"done": false, &"error_code": int(FAILED)}
	call_deferred(
		&"_capture_profile_cleanup_result",
		save_graph,
		profile_file,
		result_box
	)
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		for _frame: int in range(600):
			if GFVariantData.get_option_bool(result_box, &"done", false):
				break
			architecture.tick(1.0 / 60.0)
			await get_tree().process_frame
	@warning_ignore("int_as_enum_without_cast")
	return GFVariantData.get_option_int(
		result_box,
		&"error_code",
		FAILED
	)


func _capture_profile_cleanup_result(
	save_graph: GameSaveGraphUtility,
	profile_file: String,
	result_box: Dictionary
) -> void:
	var cleanup_error: Error = await save_graph.delete_inactive_profile_async(
		profile_file
	)
	result_box[&"error_code"] = int(cleanup_error)
	result_box[&"done"] = true


func _await_account_operation(
	operation: LocalAccountOperation,
	setup: Dictionary
) -> LocalAccountOperationResult:
	if operation == null:
		return null
	var architecture_value: Variant = setup.get(&"architecture")
	if not (architecture_value is GFArchitecture):
		return operation.get_result()
	var architecture: GFArchitecture = architecture_value
	for _frame: int in range(600):
		if not operation.is_pending():
			break
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
	return operation.get_result()


func _await_successful_account_operation(
	operation: LocalAccountOperation,
	setup: Dictionary,
	failure_message: String
) -> LocalAccountOperationResult:
	var result: LocalAccountOperationResult = await _await_account_operation(
		operation,
		setup
	)
	assert_true(
		result != null and result.is_successful(),
		failure_message
	)
	return result


func _advance_catalog_operation_to_outcome_unknown(
	operation: LocalAccountOperation,
	setup: Dictionary,
	storage: _DelayedCatalogStorage,
	clock: GFManualClock
) -> void:
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if not (architecture_value is GFArchitecture):
		assert_true(false, "测试 setup 缺少 GFArchitecture。")
		return
	var architecture: GFArchitecture = architecture_value
	for _frame: int in range(300):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		if storage.has_delayed_catalog_write_started():
			break
	assert_true(
		storage.has_delayed_catalog_write_started(),
		"目录测试写必须先进入真实 GFStorage worker。"
	)
	assert_true(clock.advance_msec(5_000))
	for _frame: int in range(60):
		architecture.tick(0.0)
		await get_tree().process_frame
		if operation.is_completed():
			break
	assert_true(
		operation.is_completed(),
		"自定义目录 deadline 必须先产生 outcome_unknown 终态。"
	)


func _advance_profile_operation_to_outcome_unknown(
	operation: LocalAccountOperation,
	setup: Dictionary,
	storage: _HangingProfileStorage,
	clock: GFManualClock
) -> void:
	var architecture_value: Variant = setup.get(&"architecture")
	if not (architecture_value is GFArchitecture):
		assert_true(false, "测试 setup 缺少 GFArchitecture。")
		return
	var architecture: GFArchitecture = architecture_value
	for _frame: int in range(120):
		architecture.tick(0.0)
		await get_tree().process_frame
		if not storage.hanging_operations.is_empty():
			break
	assert_false(storage.hanging_operations.is_empty())
	for delta_msec: int in [5_000, 100, 5_000, 500, 5_000, 1_500, 5_000]:
		assert_true(clock.advance_msec(delta_msec))
		architecture.tick(0.0)
		await get_tree().process_frame
	assert_true(
		operation.is_completed()
		and operation.get_result().get_status()
		== LocalAccountOperationResult.STATUS_PROFILE_OUTCOME_UNKNOWN
	)


func _await_catalog_activation(
	catalog: LocalAccountCatalogUtility,
	account_id: String,
	setup: Dictionary
) -> Error:
	var result_box: Dictionary = {&"done": false, &"error_code": int(FAILED)}
	call_deferred(
		&"_capture_catalog_activation_result",
		catalog,
		account_id,
		result_box
	)
	var architecture_value: Variant = setup.get(&"architecture")
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		for _frame: int in range(600):
			if GFVariantData.get_option_bool(result_box, &"done", false):
				break
			architecture.tick(1.0 / 60.0)
			await get_tree().process_frame
	@warning_ignore("int_as_enum_without_cast")
	return GFVariantData.get_option_int(
		result_box,
		&"error_code",
		FAILED
	)


func _capture_catalog_activation_result(
	catalog: LocalAccountCatalogUtility,
	account_id: String,
	result_box: Dictionary
) -> void:
	var error_code: Error = await catalog.set_active_account_async(
		account_id,
		false
	)
	result_box[&"error_code"] = int(error_code)
	result_box[&"done"] = true


func _await_account_reconciliation(
	accounts: LocalAccountSystem,
	setup: Dictionary
) -> void:
	var architecture_value: Variant = GFVariantData.get_option_value(
		setup,
		&"architecture"
	)
	if not (architecture_value is GFArchitecture):
		assert_true(false, "测试 setup 缺少 GFArchitecture。")
		return
	var architecture: GFArchitecture = architecture_value
	for _frame: int in range(600):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		if not accounts.is_account_reconciliation_pending():
			break
	assert_false(
		accounts.is_account_reconciliation_pending(),
		"目录迟到终态必须在有界测试窗口内与 GF Profile 收敛。"
	)


func _make_result(
	score: int,
	steps: int,
	max_tile: int,
	played_at: int,
	duration_msec: int
) -> GameResultRecordedData:
	var result: GameResultRecordedData = GameResultRecordedData.create(
		StringName(_MODE_ID),
		_BOARD_KEY,
		_RULESET_ID,
		1,
		_RULESET_FINGERPRINT,
		played_at,
		("%d|%d|%d" % [score, played_at, duration_msec]).sha256_text(),
		GameCompetitionEligibility.create(),
		score,
		steps,
		max_tile,
		played_at,
		2048,
		max_tile >= 2048
	)
	assert_not_null(result)
	return result


func _create_setup(
	storage_override: GFStorageUtility = null,
	clock_override: GFManualClock = null,
	save_graph_override: GameSaveGraphUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	storage.save_dir_name = "gut_local_profiles_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	var clock_source: GFManualClock = (
		clock_override
		if clock_override != null
		else GFManualClock.new(0, 1_000_000)
	)
	var time_utility: GFTimeUtility = GFTimeUtility.new()
	assert_true(time_utility.set_clock(clock_source))
	var clock: GameClockUtility = GameClockUtility.new()
	assert_true(clock.set_clock(clock_source))
	var account_catalog: LocalAccountCatalogUtility = (
		LocalAccountCatalogUtility.new()
	)
	var save_graph: GameSaveGraphUtility = (
		save_graph_override
		if save_graph_override != null
		else GameSaveGraphUtility.new()
	)
	save_graph.auto_load_legacy_profile_on_ready = false
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GameSaveGraphUtility.SectionOrder.EARLY
	))
	var account_system: LocalAccountSystem = LocalAccountSystem.new()
	var progress_system: ProgressStatsSystem = ProgressStatsSystem.new()
	var account_event_probe: _AccountEventProbe = _AccountEventProbe.new()
	var platform_stub: GamePlatformUtility = (
		_TEST_PLATFORM_STUB_SCRIPT.new()
	)
	assert_not_null(platform_stub)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFTimeUtility, time_utility)
	await architecture.register_utility(
		GFSaveProfileUtility,
		GFSaveProfileUtility.new()
	)
	await architecture.register_utility(
		GFBackgroundWorkUtility,
		GFBackgroundWorkUtility.new()
	)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(
		GamePlatformUtility,
		platform_stub
	)
	await architecture.register_utility(GameClockUtility, clock)
	await architecture.register_utility(
		LocalAccountCatalogUtility,
		account_catalog
	)
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_system(LocalAccountSystem, account_system)
	await architecture.register_system(ProgressStatsSystem, progress_system)
	await architecture.init()
	architecture.register_event_owned(
		account_event_probe,
		ActiveLocalAccountChangedData,
		GFEventListener.from_method(
			account_event_probe,
			&"_on_active_account_changed",
			1
		)
	)
	return {
		&"architecture": architecture,
		&"storage": storage,
		&"account_catalog": account_catalog,
		&"save_graph": save_graph,
		&"account_system": account_system,
		&"progress_system": progress_system,
		&"account_event_probe": account_event_probe,
		&"clock": clock_source,
	}


func _dispose_setup(setup: Dictionary) -> void:
	var architecture_value: Variant = setup.get(&"architecture")
	var accounts_value: Variant = setup.get(&"account_system")
	var account_ids: Array[String] = []
	if accounts_value is LocalAccountSystem:
		var account_system: LocalAccountSystem = accounts_value
		for account: LocalPlayerAccount in account_system.get_accounts():
			account_ids.append(account.account_id)
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()
	var storage_value: Variant = setup.get(&"storage")
	if storage_value is GFStorageUtility:
		var storage: GFStorageUtility = storage_value
		var _catalog_delete_error: Error = storage.delete_file(
			LocalAccountCatalogUtility.CATALOG_FILE_NAME
		)
		var _legacy_delete_error: Error = storage.delete_file(
			GameSaveGraphUtility.PROFILE_FILE_NAME
		)
		for account_id: String in account_ids:
			var _profile_delete_error: Error = storage.delete_file(
				LocalAccountCatalogUtility.make_profile_file_name(account_id)
			)


func _get_account_system(setup: Dictionary) -> LocalAccountSystem:
	var value: Variant = setup.get(&"account_system")
	if value is LocalAccountSystem:
		return value
	assert_true(false, "测试 setup 缺少 LocalAccountSystem。")
	return LocalAccountSystem.new()


func _get_progress_system(setup: Dictionary) -> ProgressStatsSystem:
	var value: Variant = setup.get(&"progress_system")
	if value is ProgressStatsSystem:
		return value
	assert_true(false, "测试 setup 缺少 ProgressStatsSystem。")
	return ProgressStatsSystem.new()


func _get_account_catalog(
	setup: Dictionary
) -> LocalAccountCatalogUtility:
	var value: Variant = setup.get(&"account_catalog")
	if value is LocalAccountCatalogUtility:
		return value
	assert_true(false, "测试 setup 缺少 LocalAccountCatalogUtility。")
	return LocalAccountCatalogUtility.new()


func _get_save_graph(setup: Dictionary) -> GameSaveGraphUtility:
	var value: Variant = setup.get(&"save_graph")
	if value is GameSaveGraphUtility:
		return value
	assert_true(false, "测试 setup 缺少 GameSaveGraphUtility。")
	return GameSaveGraphUtility.new()


func _get_account_event_probe(setup: Dictionary) -> _AccountEventProbe:
	var value: Variant = setup.get(&"account_event_probe")
	if value is _AccountEventProbe:
		return value
	assert_true(false, "测试 setup 缺少账号事件探针。")
	return _AccountEventProbe.new()


func _snapshot_accounts(
	accounts: LocalAccountSystem
) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for account: LocalPlayerAccount in accounts.get_accounts():
		snapshots.append(account.to_dict())
	return snapshots


# --- 内部类 ---

class _AccountEventProbe extends RefCounted:
	var active_account_event_count: int = 0
	var last_previous_account_id: String = ""
	var last_account_id: String = ""


	func reset() -> void:
		active_account_event_count = 0
		last_previous_account_id = ""
		last_account_id = ""


	func _on_active_account_changed(
		payload: ActiveLocalAccountChangedData
	) -> void:
		if payload == null or payload.account == null:
			return
		active_account_event_count += 1
		last_previous_account_id = payload.previous_account_id
		last_account_id = payload.account.account_id


class _DelayedCatalogStorage extends GFStorageUtility:
	const _DELAY_MSEC: int = 180

	var _plan_mutex: Mutex = Mutex.new()
	var _delay_next_catalog_write: bool = false
	var _delayed_error: Error = OK
	var _delayed_write_started: bool = false


	## 安排下一次账号目录写入延迟后以指定错误码终结。
	## @param error_code: 延迟写入的真实终态错误码。
	func arm_next_catalog_write(error_code: Error) -> void:
		_plan_mutex.lock()
		_delay_next_catalog_write = true
		_delayed_error = error_code
		_delayed_write_started = false
		_plan_mutex.unlock()


	func has_delayed_catalog_write_started() -> bool:
		_plan_mutex.lock()
		var started: bool = _delayed_write_started
		_plan_mutex.unlock()
		return started


	func _save_data_thread(
		file_name: String,
		final_path: String,
		temp_path: String,
		backup_path: String,
		transaction_path: String,
		transaction_id: String,
		data: Dictionary,
		codec_options: Dictionary
	) -> Dictionary:
		var should_delay: bool = false
		var delayed_error: Error = OK
		_plan_mutex.lock()
		if (
			file_name == LocalAccountCatalogUtility.CATALOG_FILE_NAME
			and _delay_next_catalog_write
		):
			should_delay = true
			delayed_error = _delayed_error
			_delay_next_catalog_write = false
			_delayed_write_started = true
		_plan_mutex.unlock()
		if should_delay:
			OS.delay_msec(_DELAY_MSEC)
			if delayed_error != OK:
				return {&"error": delayed_error}
		return super._save_data_thread(
			file_name,
			final_path,
			temp_path,
			backup_path,
			transaction_path,
			transaction_id,
			data,
			codec_options
		)


class _FailingCatalogStorage extends GFStorageUtility:
	var next_catalog_save_error: Error = OK
	var catalog_save_attempt_count: int = 0
	var last_failed_catalog_payload: Dictionary = {}
	var _next_request_id: int = 1_000_000


	## 为账号目录写入注入一次性失败，并委托其余存储写入。
	## @param file_name: GFStorage 相对文件名。
	## @param data: 要持久化的完整数据字典。
	func save_data(file_name: String, data: Dictionary) -> Error:
		if file_name == LocalAccountCatalogUtility.CATALOG_FILE_NAME:
			catalog_save_attempt_count += 1
		if (
			file_name == LocalAccountCatalogUtility.CATALOG_FILE_NAME
			and next_catalog_save_error != OK
		):
			var scripted_error: Error = next_catalog_save_error
			next_catalog_save_error = OK
			last_failed_catalog_payload = data.duplicate(true)
			return scripted_error
		return super.save_data(file_name, data)


	## 为账号目录的请求专属异步写入注入一次性 typed 失败。
	## @param file_name: GFStorage 相对文件名。
	## @param data: 要持久化的完整数据字典。
	func save_data_request_async(
		file_name: String,
		data: Dictionary
	) -> GFStorageAsyncOperation:
		if file_name == LocalAccountCatalogUtility.CATALOG_FILE_NAME:
			catalog_save_attempt_count += 1
		if (
			file_name != LocalAccountCatalogUtility.CATALOG_FILE_NAME
			or next_catalog_save_error == OK
		):
			return super.save_data_request_async(file_name, data)
		var scripted_error: Error = next_catalog_save_error
		next_catalog_save_error = OK
		last_failed_catalog_payload = data.duplicate(true)
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_request_id
		_next_request_id += 1
		var _operation_configured: bool = (
			operation.configure_for_framework(
				request_id,
				GFStorageAsyncOperation.OPERATION_SAVE,
				file_name
			)
		)
		var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
		var _result_configured: bool = result.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_SAVE,
			file_name,
			false,
			scripted_error
		)
		var _completed: bool = operation.complete_for_framework(result)
		return operation


class _CountingProfileReadStorage extends GFStorageUtility:
	var profile_load_request_count: int = 0


	## 统计 Profile 异步读取请求。
	## @param file_name: GFStorage 相对文件名。
	func load_data_request_async(
		file_name: String
	) -> GFStorageAsyncOperation:
		if file_name.begins_with(
			LocalAccountCatalogUtility.PROFILE_DIRECTORY + "/"
		):
			profile_load_request_count += 1
		return super.load_data_request_async(file_name)


	func reset_profile_load_request_count() -> void:
		profile_load_request_count = 0


class _LegacyProfileReadCountingStorage extends GFStorageUtility:
	var legacy_profile_async_read_count: int = 0


	## 统计 GFSaveProfile 是否完整读取过旧默认 Profile。
	## @param file_name: GFStorage 相对文件名。
	func load_data_request_async(
		file_name: String
	) -> GFStorageAsyncOperation:
		if file_name == GameSaveGraphUtility.PROFILE_FILE_NAME:
			legacy_profile_async_read_count += 1
		return super.load_data_request_async(file_name)


class _HangingProfileReadStorage extends GFStorageUtility:
	var hang_profile_reads: bool = false
	var hanging_read_operations: Array[GFStorageAsyncOperation] = []
	var _next_read_request_id: int = 4_000_000


	## 按需挂起 Profile 异步读取请求。
	## @param file_name: GFStorage 相对文件名。
	func load_data_request_async(
		file_name: String
	) -> GFStorageAsyncOperation:
		if (
			not hang_profile_reads
			or not file_name.begins_with(
				LocalAccountCatalogUtility.PROFILE_DIRECTORY + "/"
			)
		):
			return super.load_data_request_async(file_name)
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_read_request_id
		_next_read_request_id += 1
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_LOAD,
			file_name
		)
		hanging_read_operations.append(operation)
		return operation


	## 以指定错误码完成全部挂起读取。
	## @param error_code: 每个读取操作的真实终态错误码。
	func complete_all_hanging_reads(error_code: Error) -> void:
		var operations: Array[GFStorageAsyncOperation] = (
			hanging_read_operations.duplicate()
		)
		hanging_read_operations.clear()
		for operation: GFStorageAsyncOperation in operations:
			if operation == null or operation.is_completed():
				continue
			var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
			var _configured: bool = result.configure_for_framework(
				operation.get_request_id(),
				GFStorageAsyncOperation.OPERATION_LOAD,
				operation.get_file_name(),
				false,
				error_code
			)
			var _completed: bool = operation.complete_for_framework(result)


class _HangingProfileStorage extends GFStorageUtility:
	var hang_profile_writes: bool = false
	var hanging_operations: Array[GFStorageAsyncOperation] = []
	var _payloads_by_request_id: Dictionary = {}
	var _next_request_id: int = 3_000_000


	## 挂起目标 Profile opaque payload 写入，其余请求委托真实 GFStorage。
	## @param file_name: GFStorage 相对文件名。
	## @param transfer: 此 generation 的单所有者 payload transfer。
	func save_payload_request_async(
		file_name: String,
		transfer: GFStoragePayloadTransfer
	) -> GFStorageAsyncOperation:
		if (
			not hang_profile_writes
			or not file_name.begins_with(
				LocalAccountCatalogUtility.PROFILE_DIRECTORY + "/"
			)
		):
			return super.save_payload_request_async(file_name, transfer)
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_request_id
		_next_request_id += 1
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_SAVE,
			file_name
		)
		var attempt: Dictionary = (
			transfer.begin_attempt_for_framework(
				get_instance_id(),
				file_name,
				_get_async_file_key(file_name),
				_get_codec_options()
			)
			if transfer != null
			else {}
		)
		if not GFVariantData.get_option_bool(attempt, "ok"):
			var invalid_result: GFStorageAsyncResult = (
				GFStorageAsyncResult.new()
			)
			var _invalid_result_configured: bool = (
				invalid_result.configure_for_framework(
					request_id,
					GFStorageAsyncOperation.OPERATION_SAVE,
					file_name,
					false,
					ERR_INVALID_PARAMETER,
					null,
					GFStorageAsyncResult.WriteFailureKind.INVALID_REQUEST
				)
			)
			var _invalid_completed: bool = (
				operation.complete_for_framework(invalid_result)
			)
			return operation
		var _attempt_configured: bool = (
			operation.configure_payload_attempt_for_framework(
				transfer,
				GFVariantData.get_option_int(attempt, "attempt_id")
			)
		)
		var payload_value: Variant = attempt.get("payload")
		if not payload_value is Dictionary:
			var _attempt_finished: bool = (
				operation.finish_payload_attempt_for_framework()
			)
			var invalid_payload_result: GFStorageAsyncResult = (
				GFStorageAsyncResult.new()
			)
			var _invalid_payload_result_configured: bool = (
				invalid_payload_result.configure_for_framework(
					request_id,
					GFStorageAsyncOperation.OPERATION_SAVE,
					file_name,
					false,
					ERR_INVALID_DATA,
					null,
					GFStorageAsyncResult.WriteFailureKind.PAYLOAD_INVALID
				)
			)
			var _invalid_payload_completed: bool = (
				operation.complete_for_framework(invalid_payload_result)
			)
			return operation
		hanging_operations.append(operation)
		var payload: Dictionary = payload_value
		_payloads_by_request_id[request_id] = payload.duplicate(true)
		return operation


	## 以指定错误码完成全部挂起的 Profile 写入。
	## @param error_code: 每个挂起操作的真实终态错误码。
	func complete_all_hanging(error_code: Error) -> void:
		var operations: Array[GFStorageAsyncOperation] = (
			hanging_operations.duplicate()
		)
		hanging_operations.clear()
		for operation: GFStorageAsyncOperation in operations:
			if operation == null or operation.is_completed():
				continue
			var request_id: int = operation.get_request_id()
			var payload: Dictionary = GFVariantData.get_option_dictionary(
				_payloads_by_request_id,
				request_id
			)
			var _erased: bool = _payloads_by_request_id.erase(request_id)
			var completion_error: Error = error_code
			if completion_error == OK:
				completion_error = (
					super.save_data(operation.get_file_name(), payload)
					if not payload.is_empty()
					else ERR_INVALID_DATA
				)
			var _attempt_finished: bool = (
				operation.finish_payload_attempt_for_framework()
			)
			var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
			var _configured: bool = result.configure_for_framework(
				request_id,
				GFStorageAsyncOperation.OPERATION_SAVE,
				operation.get_file_name(),
				completion_error == OK,
				completion_error
			)
			var _completed: bool = operation.complete_for_framework(result)


class _TimeoutCleanupSaveGraph extends GameSaveGraphUtility:
	var _timeout_cleanup_file: String = ""
	var _cleanup_timeout_pending: bool = false
	var _settle_cleanup_before_return: bool = false


	## 配置下一次指定 Profile 清理返回超时。
	## @param profile_file_name: 要模拟超时的 Profile 文件名。
	## @param settle_before_return: 返回超时前是否先发布后台清理终态。
	func arm_next_cleanup_timeout(
		profile_file_name: String,
		settle_before_return: bool = false
	) -> void:
		_timeout_cleanup_file = profile_file_name
		_cleanup_timeout_pending = true
		_settle_cleanup_before_return = settle_before_return


	## 让指定 Profile 的模拟超时清理发布迟到终态。
	## @param profile_file_name: 要完成模拟清理的 Profile 文件名。
	func settle_cleanup_timeout(profile_file_name: String) -> void:
		if profile_file_name != _timeout_cleanup_file:
			return
		_cleanup_timeout_pending = false
		profile_cleanup_task_terminal.emit(&"test-cleanup-late-terminal")


	## 返回指定 Profile 是否仍由模拟或真实清理任务持有。
	## @param profile_file_name: 待查询的 Profile 文件名。
	func is_profile_cleanup_pending(profile_file_name: String) -> bool:
		return (
			_cleanup_timeout_pending
			and profile_file_name == _timeout_cleanup_file
		) or super.is_profile_cleanup_pending(profile_file_name)


	## 模拟指定非活动 Profile 的异步删除。
	## @param profile_file_name: 要删除的 Profile 文件名。
	func delete_inactive_profile_async(
		profile_file_name: String
	) -> Error:
		if (
			_cleanup_timeout_pending
			and profile_file_name == _timeout_cleanup_file
		):
			if _settle_cleanup_before_return:
				_cleanup_timeout_pending = false
				_settle_cleanup_before_return = false
				profile_cleanup_task_terminal.emit(
					&"test-cleanup-early-terminal"
				)
			return ERR_TIMEOUT
		return await super.delete_inactive_profile_async(
			profile_file_name
		)
