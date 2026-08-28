## 强制 GFStorage cooperative executor 时，账号 Profile bootstrap 的生命周期回归。
extends GutTest


const _TEST_PLATFORM_STUB_SCRIPT: GDScript = preload(
	"res://tests/gut/fixtures/test_game_platform_utility_stub.gd"
)


func test_local_account_bootstrap_completes_with_cooperative_storage() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	storage.save_dir_name = "gut_coop_boot_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.async_execution_mode = GFStorageUtility.AsyncExecutionMode.COOPERATIVE

	var clock_source: GFManualClock = GFManualClock.new(0, 1_000_000)
	var time_utility: GFTimeUtility = GFTimeUtility.new()
	assert_true(time_utility.set_clock(clock_source))
	var game_clock: GameClockUtility = GameClockUtility.new()
	assert_true(game_clock.set_clock(clock_source))
	assert_true(storage.set_async_clock_for_framework(clock_source))

	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GameSaveGraphUtility.SectionOrder.EARLY
	))
	var account_system: LocalAccountSystem = LocalAccountSystem.new()
	var platform: GamePlatformUtility = _TEST_PLATFORM_STUB_SCRIPT.new()
	assert_not_null(platform)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFTimeUtility, time_utility)
	await architecture.register_utility(GFSaveProfileUtility, GFSaveProfileUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GamePlatformUtility, platform)
	await architecture.register_utility(GameClockUtility, game_clock)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(
		LocalAccountCatalogUtility,
		LocalAccountCatalogUtility.new()
	)
	await architecture.register_utility(ChunkProfileUtility, ChunkProfileUtility.new())
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_system(LocalAccountSystem, account_system)

	var initialized: bool = await architecture.init()
	var account: LocalPlayerAccount = account_system.get_active_account()
	assert_true(initialized, "cooperative Storage 下 architecture activation 不应 pending 或超时。")
	assert_not_null(account)
	assert_true(save_graph.is_profile_loaded())
	if account != null:
		assert_true(
			save_graph.get_profile_file_name()
			== LocalAccountCatalogUtility.make_profile_file_name(account.account_id)
		)
	assert_true(
		storage.async_execution_mode
		== GFStorageUtility.AsyncExecutionMode.COOPERATIVE
	)
	architecture.dispose()
