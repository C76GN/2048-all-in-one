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


func test_accounts_keep_independent_profiles_and_mode_summaries() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(first)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 1024) == OK)

	assert_true(accounts.create_account("第二位玩家") == OK)
	var second: LocalPlayerAccount = accounts.get_active_account()
	assert_not_null(second)
	assert_true(second.account_id != first.account_id)
	assert_true(
		progress.get_high_score(_MODE_ID, _BOARD_KEY) == 0,
		"新账号必须从独立空 Profile 开始。"
	)
	assert_true(progress.set_high_score(_MODE_ID, _BOARD_KEY, 2048) == OK)
	assert_true(accounts.switch_account(first.account_id) == OK)
	assert_true(
		progress.get_high_score(_MODE_ID, _BOARD_KEY) == 1024,
		"切回账号必须恢复其独立统计。"
	)
	var summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(first.account_id)
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
	assert_true(accounts.create_account("删除回滚账号") == OK)
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

	assert_true(
		accounts.delete_account(deleted_candidate.account_id)
		== ERR_CANT_CREATE
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


func test_device_leaderboard_uses_each_accounts_best_result() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_true(
		progress.record_game_result(
			_make_result(4096, 40, 2048, 100, 61_000),
			61_000
		)
		== OK
	)
	assert_true(
		progress.record_game_result(
			_make_result(2048, 30, 1024, 101, 42_000),
			42_000
		)
		== OK
	)

	assert_true(accounts.create_account("榜单二号") == OK)
	var second: LocalPlayerAccount = accounts.get_active_account()
	assert_true(
		progress.record_game_result(
			_make_result(8192, 50, 4096, 102, 75_000),
			75_000
		)
		== OK
	)

	var identities: Array[Dictionary] = (
		progress.get_device_leaderboard_identities()
	)
	assert_true(identities.size() == 1)
	var rows: Array[Dictionary] = progress.get_device_local_leaderboard(
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


func test_duration_stats_are_profile_scoped_and_persisted() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_true(progress.record_game_result(
		_make_result(4096, 40, 2048, 100, 61_000),
		61_000
	) == OK)
	assert_true(progress.record_game_result(
		_make_result(2048, 30, 1024, 101, 42_000),
		42_000
	) == OK)
	var summaries: Array[Dictionary] = progress.get_profile_mode_summaries(
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
	assert_true(accounts.create_account("时长隔离账号") == OK)
	assert_true(accounts.switch_account(first.account_id) == OK)
	var restored_summaries: Array[Dictionary] = (
		progress.get_profile_mode_summaries(first.account_id)
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
	storage_override: GFStorageUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	storage.save_dir_name = "gut_local_profiles_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	var clock_source: GFManualClock = GFManualClock.new(0, 1_000_000)
	var clock: GameClockUtility = GameClockUtility.new()
	assert_true(clock.set_clock(clock_source))
	var account_catalog: LocalAccountCatalogUtility = (
		LocalAccountCatalogUtility.new()
	)
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GFSaveScope.Phase.EARLY
	))
	var account_system: LocalAccountSystem = LocalAccountSystem.new()
	var progress_system: ProgressStatsSystem = ProgressStatsSystem.new()
	var platform_stub: GamePlatformUtility = (
		_TEST_PLATFORM_STUB_SCRIPT.new()
	)
	assert_not_null(platform_stub)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, GFSaveGraphUtility.new())
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
	return {
		&"architecture": architecture,
		&"storage": storage,
		&"account_catalog": account_catalog,
		&"save_graph": save_graph,
		&"account_system": account_system,
		&"progress_system": progress_system,
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


func _snapshot_accounts(
	accounts: LocalAccountSystem
) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for account: LocalPlayerAccount in accounts.get_accounts():
		snapshots.append(account.to_dict())
	return snapshots


# --- 内部类 ---

class _FailingCatalogStorage extends GFStorageUtility:
	var next_catalog_save_error: Error = OK
	var catalog_save_attempt_count: int = 0
	var last_failed_catalog_payload: Dictionary = {}


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
