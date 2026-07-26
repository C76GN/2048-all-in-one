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


func test_device_leaderboard_uses_each_accounts_best_result() -> void:
	var setup: Dictionary = await _create_setup()
	var accounts: LocalAccountSystem = _get_account_system(setup)
	var progress: ProgressStatsSystem = _get_progress_system(setup)
	var first: LocalPlayerAccount = accounts.get_active_account()
	assert_true(
		progress.record_game_result(_make_result(4096, 40, 2048, 100, 61_000))
		== OK
	)
	assert_true(
		progress.record_game_result(_make_result(2048, 30, 1024, 101, 42_000))
		== OK
	)

	assert_true(accounts.create_account("榜单二号") == OK)
	var second: LocalPlayerAccount = accounts.get_active_account()
	assert_true(
		progress.record_game_result(_make_result(8192, 50, 4096, 102, 75_000))
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


func test_result_duration_round_trip_and_legacy_migration() -> void:
	var result: GameResultRecordedData = _make_result(
		4096,
		40,
		2048,
		100,
		61_000
	)
	var restored: GameResultRecordedData = GameResultRecordedData.from_dict(
		result.to_dict()
	)
	assert_not_null(restored)
	assert_true(restored.duration_msec == 61_000)

	var legacy: Dictionary = result.to_dict()
	legacy.erase(&"duration_msec")
	legacy[&"schema_version"] = GameResultRecordedData.LEGACY_SCHEMA_VERSION
	legacy[&"result_hash"] = result._calculate_result_hash(false)
	var migrated: GameResultRecordedData = GameResultRecordedData.from_dict(legacy)
	assert_not_null(migrated)
	assert_true(migrated.duration_msec == 0)
	assert_true(
		migrated.schema_version == GameResultRecordedData.SCHEMA_VERSION
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
		max_tile >= 2048,
		duration_msec
	)
	assert_not_null(result)
	return result


func _create_setup() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
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

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFSaveGraphUtility, GFSaveGraphUtility.new())
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(
		GamePlatformUtility,
		_TEST_PLATFORM_STUB_SCRIPT.new()
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
