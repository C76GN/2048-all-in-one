## 验证 ProgressStatsSystem 的最高分和轻量统计 SaveGraph 语义。
extends GutTest


# --- 常量 ---

const _MODE_ID: String = "classic_mode_config"
const _BOARD_KEY: String = "board.rectangle.4x4@test"
const _RULESET_ID: StringName = &"rules.classic"
const _RULESET_FINGERPRINT: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


# --- 测试用例 ---

func test_set_high_score_updates_stats_without_recording_play() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var save_error: Error = progress_stats_system.set_high_score(_MODE_ID, _BOARD_KEY, 2048)

	var stats: Dictionary = progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)
	assert_true(save_error == OK, "最高分应写入 progress section。")
	assert_true(progress_stats_system.get_high_score(_MODE_ID, _BOARD_KEY) == 2048, "统计图应提供最高分。")
	assert_true(_get_stat_int(stats, "best_score") == 2048, "最高分应以 stats.best_score 为唯一真源。")
	assert_true(_get_stat_int(stats, "plays") == 0, "只写入最高分不应增加完整对局次数。")
	assert_true(_get_stat_int(stats, "average_score") == 0, "只写入最高分不应生成平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 0, "只写入最高分不应生成平均步数。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 0, "只写入最高分不应生成目标达成次数。")

	_dispose_setup(setup)


func test_reconciliation_callback_ignores_other_transaction_and_disposes() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress: ProgressStatsSystem = _get_progress_stats_system(setup)
	var strict_result: GameResultRecordedData = _make_result(
		128,
		4,
		16,
		100
	)
	progress._publish_recorded_result_after_reconciliation(
		42,
		strict_result
	)
	var connection: GFSignalConnection = progress._reconciliation_connection
	assert_true(
		connection != null and connection.is_active(),
		"Progress 应保留由 GFSignalUtility 管理的 reconciliation 连接。"
	)

	save_graph.section_reconciliation_settled.emit({
		&"transaction_id": 41,
		&"candidate_persisted": true,
	})
	await get_tree().process_frame
	assert_true(
		progress._reconciliation_connection == connection
		and connection.is_active(),
		"其他 transaction 的证据不得消耗目标监听。"
	)
	progress.dispose()
	assert_false(
		connection.is_active(),
		"System dispose 必须通过 GFSignalUtility 主动断开 reconciliation 连接。"
	)
	_dispose_setup(setup)


func test_record_game_result_updates_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var first_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(512, 20, 128, 100),
		setup
	)
	var second_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(256, 18, 256, 200),
		setup
	)

	var stats: Dictionary = progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)
	assert_true(first_result != null and first_result.is_successful(), "第一局统计应保存成功。")
	assert_true(second_result != null and second_result.is_successful(), "第二局统计应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "每次完整对局都应增加 plays。")
	assert_true(_get_stat_int(stats, "best_score") == 512, "统计应保留最佳分数。")
	assert_true(_get_stat_int(stats, "best_steps") == 18, "统计应保留最少有效步数。")
	assert_true(_get_stat_int(stats, "max_tile") == 256, "统计应保留历史最大方块。")
	assert_true(_get_stat_int(stats, "total_score") == 768, "统计应累计总分。")
	assert_true(_get_stat_int(stats, "total_steps") == 38, "统计应累计总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 2, "统计应记录有效步数样本数。")
	assert_true(_get_stat_int(stats, "average_score") == 384, "统计应计算平均分。")
	assert_true(_get_stat_int(stats, "average_steps") == 19, "统计应计算平均步数。")
	assert_true(_get_stat_int(stats, "last_score") == 256, "统计应记录最近一局分数。")
	assert_true(_get_stat_int(stats, "last_played_at") == 200, "统计应记录最近一局时间戳。")

	_dispose_setup(setup)


func test_target_rate_is_bounded_by_play_count() -> void:
	var setup: Dictionary = await _create_save_architecture({
		"stats": {
			_MODE_ID: {
				_BOARD_KEY: {
					"plays": 2,
					"target_value": 2048,
					"target_reached_count": 5,
				},
			},
		},
	})
	var stats: Dictionary = _get_progress_stats_system(setup).get_game_stats(_MODE_ID, _BOARD_KEY)

	assert_true(_get_stat_int(stats, "target_reached_count") == 2, "目标达成次数不应超过完整对局次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 100, "目标达成率应归一化到 0 到 100。")

	_dispose_setup(setup)


func test_zero_step_results_do_not_pollute_step_averages() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var zero_step_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(64, 0, 64, 100),
		setup
	)
	var normal_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(128, 10, 128, 200),
		setup
	)
	var stats: Dictionary = progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)

	assert_true(zero_step_result != null and zero_step_result.is_successful(), "零步结果应保存成功。")
	assert_true(normal_result != null and normal_result.is_successful(), "正常结果应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "零步结果仍应计入完整对局次数。")
	assert_true(_get_stat_int(stats, "best_steps") == 10, "零步结果不应成为最佳步数。")
	assert_true(_get_stat_int(stats, "total_steps") == 10, "零步结果不应污染总步数。")
	assert_true(_get_stat_int(stats, "step_samples") == 1, "零步结果不应增加步数样本。")
	assert_true(_get_stat_int(stats, "average_score") == 96, "平均分仍应按所有完整对局计算。")
	assert_true(_get_stat_int(stats, "average_steps") == 10, "平均步数只应按有效步数样本计算。")

	_dispose_setup(setup)


func test_record_game_result_tracks_target_reach_stats() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var missed_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(1024, 26, 1024, 100, 2048, false),
		setup
	)
	var reached_result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(2048, 35, 2048, 200, 2048, true),
		setup
	)
	var stats: Dictionary = progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)

	assert_true(missed_result != null and missed_result.is_successful(), "未达成局应保存成功。")
	assert_true(reached_result != null and reached_result.is_successful(), "达成局应保存成功。")
	assert_true(_get_stat_int(stats, "plays") == 2, "目标统计应以完整对局次数为分母。")
	assert_true(_get_stat_int(stats, "target_value") == 2048, "统计应记录目标方块值。")
	assert_true(_get_stat_int(stats, "target_reached_count") == 1, "统计应累计目标达成次数。")
	assert_true(_get_stat_int(stats, "target_reached_rate") == 50, "统计应计算目标达成率百分比。")
	assert_true(_get_stat_bool(stats, "last_target_reached"), "最近一局目标状态应记录为已达成。")

	_dispose_setup(setup)


func test_record_game_result_preserves_existing_higher_score() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var high_score_error: Error = progress_stats_system.set_high_score(_MODE_ID, _BOARD_KEY, 4096)
	var result: GameSaveSectionResult = await _record_game_result(
		progress_stats_system,
		_make_result(1024, 30, 512, 300),
		setup
	)
	var stats: Dictionary = progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)

	assert_true(high_score_error == OK, "已有最高分应保存成功。")
	assert_true(result != null and result.is_successful(), "后续对局应保存成功。")
	assert_true(progress_stats_system.get_high_score(_MODE_ID, _BOARD_KEY) == 4096, "较低分数不应覆盖已有最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "记录完整对局仍应增加 plays。")
	assert_true(_get_stat_int(stats, "average_score") == 1024, "平均分应基于实际得分。")
	assert_true(_get_stat_int(stats, "last_score") == 1024, "最近一局摘要应保留实际结束分数。")

	_dispose_setup(setup)


func test_stats_persist_through_gf_save_graph() -> void:
	var save_dir_name: String = "gut_progress_stats_system_%d" % Time.get_ticks_usec()
	var setup: Dictionary = await _create_save_architecture({}, save_dir_name)
	var save_result: GameSaveSectionResult = await _record_game_result(
		_get_progress_stats_system(setup),
		_make_result(1024, 24, 512, 400),
		setup
	)
	assert_true(save_result != null and save_result.is_successful(), "统计应写入 SaveGraph。")
	_dispose_setup(setup, false)

	var reloaded_setup: Dictionary = await _create_save_architecture({}, save_dir_name)
	var reloaded_progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(reloaded_setup)
	var stats: Dictionary = reloaded_progress_stats_system.get_game_stats(_MODE_ID, _BOARD_KEY)
	assert_true(reloaded_progress_stats_system.get_high_score(_MODE_ID, _BOARD_KEY) == 1024, "重新加载后应保留最高分。")
	assert_true(_get_stat_int(stats, "plays") == 1, "重新加载后应保留统计次数。")
	assert_true(_get_stat_int(stats, "average_steps") == 24, "重新加载后应保留平均步数。")
	assert_true(_get_stat_int(stats, "last_played_at") == 400, "重新加载后应保留最近时间戳。")

	_dispose_setup(reloaded_setup)


func test_local_leaderboard_only_records_eligible_results_with_stable_sort() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress: ProgressStatsSystem = _get_progress_stats_system(setup)
	var eligible: GameCompetitionEligibility = GameCompetitionEligibility.create()
	var manual: GameCompetitionEligibility = eligible.with_reason(
		GameCompetitionEligibility.REASON_MANUAL_SEED
	)
	var later_tie: GameResultRecordedData = _make_result(
		900,
		20,
		512,
		300,
		0,
		false,
		eligible
	)
	var earlier_tie: GameResultRecordedData = _make_result(
		900,
		20,
		512,
		200,
		0,
		false,
		eligible
	)
	var ineligible_high_score: GameResultRecordedData = _make_result(
		9_999,
		1,
		8192,
		100,
		0,
		false,
		manual
	)

	var later_result: GameSaveSectionResult = await _record_game_result(
		progress,
		later_tie,
		setup
	)
	var earlier_result: GameSaveSectionResult = await _record_game_result(
		progress,
		earlier_tie,
		setup
	)
	var ineligible_result: GameSaveSectionResult = await _record_game_result(
		progress,
		ineligible_high_score,
		setup
	)
	assert_true(later_result != null and later_result.is_successful())
	assert_true(earlier_result != null and earlier_result.is_successful())
	assert_true(ineligible_result != null and ineligible_result.is_successful())
	var leaderboard: Array[GameResultRecordedData] = (
		progress.get_local_leaderboard_for_result(earlier_tie)
	)
	assert_true(leaderboard.size() == 2, "本地榜只能包含比赛合格结果。")
	assert_true(
		leaderboard[0].result_hash == earlier_tie.result_hash,
		"同分、同方块、同步数时应由较早完成时间稳定决胜。"
	)
	assert_true(progress.get_local_rank(earlier_tie) == 1)
	assert_true(progress.get_local_rank(later_tie) == 2)
	assert_true(progress.get_local_rank(ineligible_high_score) == 0)
	assert_true(progress.get_recent_results().size() == 3, "失格结果仍应保留可解释审计记录。")
	assert_true(
		_get_stat_int(progress.get_game_stats(_MODE_ID, _BOARD_KEY), "plays") == 3,
		"手动 seed 仍是普通进度，只是不进入比赛榜。"
	)
	_dispose_setup(setup)


func test_debug_result_is_explained_without_polluting_progress_or_leaderboard() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress: ProgressStatsSystem = _get_progress_stats_system(setup)
	var debug_eligibility: GameCompetitionEligibility = (
		GameCompetitionEligibility.create().with_reason(
			GameCompetitionEligibility.REASON_DEBUG
		)
	)
	var debug_result: GameResultRecordedData = _make_result(
		99_999,
		1,
		65_536,
		500,
		0,
		false,
		debug_eligibility
	)

	var save_result: GameSaveSectionResult = await _record_game_result(
		progress,
		debug_result,
		setup
	)
	assert_true(save_result != null and save_result.is_successful())
	assert_true(progress.get_recent_results().size() == 1)
	assert_true(
		_get_stat_int(progress.get_game_stats(_MODE_ID, _BOARD_KEY), "plays") == 0,
		"调试改写结果不得投影到普通进度。"
	)
	assert_true(
		progress.get_local_leaderboard_for_result(debug_result).is_empty(),
		"调试改写结果不得进入本地榜。"
	)
	_dispose_setup(setup)


func test_leaderboards_are_grouped_by_topology_and_ruleset_configuration() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress: ProgressStatsSystem = _get_progress_stats_system(setup)
	var standard: GameResultRecordedData = _make_result(100, 20, 64, 100)
	var changed_ruleset: GameResultRecordedData = _make_result(
		200,
		20,
		64,
		200,
		0,
		false,
		GameCompetitionEligibility.create(),
		_BOARD_KEY,
		2
	)
	var changed_board: GameResultRecordedData = _make_result(
		300,
		20,
		64,
		300,
		0,
		false,
		GameCompetitionEligibility.create(),
		"board.rectangle.5x5@test"
	)
	var same_configuration_different_seed: GameResultRecordedData = _make_result(
		400,
		20,
		64,
		400,
		0,
		false,
		GameCompetitionEligibility.create(),
		_BOARD_KEY,
		1,
		777
	)

	for result: GameResultRecordedData in [
		standard,
		changed_ruleset,
		changed_board,
		same_configuration_different_seed,
	]:
		var save_result: GameSaveSectionResult = await _record_game_result(
			progress,
			result,
			setup
		)
		assert_true(save_result != null and save_result.is_successful())
	assert_true(progress.get_local_leaderboard_for_result(standard).size() == 2)
	assert_true(progress.get_local_leaderboard_for_result(changed_ruleset).size() == 1)
	assert_true(progress.get_local_leaderboard_for_result(changed_board).size() == 1)
	assert_true(
		progress.get_local_leaderboard_for_result(
			same_configuration_different_seed
		).size() == 2,
		"初始 seed 不属于榜单分组身份；相同配置应进入同一榜单。"
	)
	assert_false(
		standard.get_leaderboard_group_key()
		== changed_ruleset.get_leaderboard_group_key()
	)
	assert_false(
		standard.get_leaderboard_group_key()
		== changed_board.get_leaderboard_group_key()
	)
	assert_true(
		standard.get_leaderboard_group_key()
		== same_configuration_different_seed.get_leaderboard_group_key()
	)
	_dispose_setup(setup)


func test_progress_section_rejects_multiple_business_roots() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var invalid_result: GameSaveSectionResult = (
		await GameSaveSectionOperationTestSupport.await_result(
			save_graph.request_replace_section_data(
				GameSaveGraphUtility.PROGRESS_SECTION_ID,
				{
					"stats": {},
					"scores": {},
				}
			),
			_get_architecture(setup),
			get_tree()
		)
	)

	assert_true(
		invalid_result != null
		and invalid_result.get_status()
		== GameSaveSectionResult.STATUS_APPLY_FAILED
		and invalid_result.get_error_code() == ERR_INVALID_DATA,
		"progress schema 应拒绝多真源载荷。"
	)
	assert_true(
		save_graph.get_section_data(GameSaveGraphUtility.PROGRESS_SECTION_ID)
		== {
			"stats": {},
			"results": [],
			"leaderboards": {},
		},
		"非法替换不得改变内存 section。"
	)

	_dispose_setup(setup)


func test_persisted_progress_payload_has_strict_section_schema() -> void:
	var setup: Dictionary = await _create_save_architecture()
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var save_error: Error = progress_stats_system.set_high_score(_MODE_ID, _BOARD_KEY, 2048)
	var document: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	var section: GFSaveSection = (
		document.get_section(GameSaveGraphUtility.PROGRESS_SECTION_ID)
		if document != null
		else null
	)
	var data: Dictionary = (
		GFVariantData.as_dictionary(section.get_payload())
		if section != null and section.get_payload() is Dictionary
		else {}
	)

	assert_true(save_error == OK, "测试最高分应保存成功。")
	assert_true(
		section != null
		and section.get_section_id()
		== GameSaveGraphUtility.PROGRESS_SECTION_ID,
		"GFSaveSection 应声明稳定 section ID。"
	)
	assert_true(
		section != null
		and section.get_schema_version() == GameStatsSaveData.SCHEMA_VERSION,
		"GFSaveSection 应声明严格 schema 版本。"
	)
	assert_true(data.has("stats"), "progress 数据必须包含 stats 根字段。")
	assert_false(data.has("scores"), "progress 数据不得保留第二套 scores 真源。")
	assert_true(data.has("results"), "progress 数据必须包含规范结果记录。")
	assert_true(data.has("leaderboards"), "progress 数据必须包含本地榜投影。")
	assert_true(data.size() == 3, "progress 业务根字段必须保持严格。")

	_dispose_setup(setup)


# --- 私有/辅助方法 ---

func _record_game_result(
	progress: ProgressStatsSystem,
	result: GameResultRecordedData,
	setup: Dictionary,
	duration_msec: int = 0
) -> GameSaveSectionResult:
	var operation: GameSaveSectionOperation = progress.request_record_game_result(
		result,
		duration_msec
	)
	return await GameSaveSectionOperationTestSupport.await_result(
		operation,
		_get_architecture(setup),
		get_tree()
	)


func _make_result(
	score: int,
	steps: int,
	max_tile: int,
	played_at: int,
	target_value: int = 0,
	target_reached: bool = false,
	eligibility: GameCompetitionEligibility = null,
	board_key: String = _BOARD_KEY,
	ruleset_version: int = 1,
	initial_seed: int = 2048
) -> GameResultRecordedData:
	var resolved_eligibility: GameCompetitionEligibility = eligibility
	if resolved_eligibility == null:
		resolved_eligibility = GameCompetitionEligibility.create()
	var final_state_hash: String = (
		"%s|%d|%d|%d|%d|%d"
		% [board_key, score, steps, max_tile, played_at, initial_seed]
	).sha256_text()
	var result: GameResultRecordedData = GameResultRecordedData.create(
		StringName(_MODE_ID),
		board_key,
		_RULESET_ID,
		ruleset_version,
		_RULESET_FINGERPRINT,
		initial_seed,
		final_state_hash,
		resolved_eligibility,
		score,
		steps,
		max_tile,
		played_at,
		target_value,
		target_reached
	)
	assert_not_null(result, "测试结果 fixture 必须满足严格契约。")
	return result


func _create_save_architecture(
	initial_save_data: Dictionary = {},
	save_dir_name: String = ""
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var save_graph: GameSaveGraphUtility = _make_game_save_graph()
	var progress_stats_system: ProgressStatsSystem = ProgressStatsSystem.new()
	var account_catalog: LocalAccountCatalogUtility = (
		LocalAccountCatalogUtility.new()
	)

	storage.save_dir_name = save_dir_name if not save_dir_name.is_empty() else "gut_progress_stats_system_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFSaveProfileUtility,
		GFSaveProfileUtility.new()
	)
	await architecture.register_utility(
		GFBackgroundWorkUtility,
		GFBackgroundWorkUtility.new()
	)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(
		GamePlatformUtility,
		TestGamePlatformUtilityStub.new()
	)
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GameClockUtility, GameClockUtility.new())
	await architecture.register_utility(
		LocalAccountCatalogUtility,
		account_catalog
	)
	await architecture.register_system(ProgressStatsSystem, progress_stats_system)
	await architecture.init()
	var bootstrap: Dictionary = (
		await GameSaveProfileOperationTestSupport.bootstrap_account(
			save_graph,
			architecture,
			get_tree(),
			storage,
			LocalAccountCatalogUtility.make_profile_file_name(
				account_catalog.get_active_account_id()
			)
		)
	)
	var bootstrap_completion: GFAsyncCompletion = bootstrap.get(
		&"completion"
	) as GFAsyncCompletion
	assert_true(
		bootstrap_completion != null
		and bootstrap_completion.is_successful(),
		"统计测试夹具必须显式完成账号 Profile 引导。"
	)
	if not initial_save_data.is_empty():
		var normalized_initial_data: Dictionary = {
			"stats": GFVariantData.get_option_dictionary(
				initial_save_data,
				"stats"
			).duplicate(true),
			"results": GFVariantData.get_option_array(
				initial_save_data,
				"results"
			).duplicate(true),
			"leaderboards": GFVariantData.get_option_dictionary(
				initial_save_data,
				"leaderboards"
			).duplicate(true),
		}
		var seed_result: GameSaveSectionResult = (
			await GameSaveSectionOperationTestSupport.await_result(
				save_graph.request_replace_section_data(
					GameSaveGraphUtility.PROGRESS_SECTION_ID,
					normalized_initial_data
				),
				architecture,
				get_tree()
			)
		)
		assert_true(
			seed_result != null and seed_result.is_successful(),
			"测试统计初始数据应写入 progress section。"
		)

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"progress_stats_system": progress_stats_system,
		"account_catalog": account_catalog,
		"profile_file_name": GFVariantData.get_option_string(
			bootstrap,
			&"profile_file_name"
		),
	}


func _make_game_save_graph() -> GameSaveGraphUtility:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var progress_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		GameStatsSaveData.new(),
		GameSaveGraphUtility.SectionOrder.EARLY
	)
	var bookmarks_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		BookmarkCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var custom_boards_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID,
		CustomBoardCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var discoveries_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		TileDiscoverySaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var tile_blueprints_registered: bool = save_graph.register_section(
		TileLabSaveData.SECTION_ID,
		TileLabSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	)
	var achievements_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.ACHIEVEMENTS_SECTION_ID,
		AchievementSaveData.new(),
		GameSaveGraphUtility.SectionOrder.LATE
	)
	var replays_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		ReplayCatalogSaveData.new(),
		GameSaveGraphUtility.SectionOrder.LATE
	)
	assert_true(
		progress_registered
		and bookmarks_registered
		and custom_boards_registered
		and discoveries_registered
		and tile_blueprints_registered
		and achievements_registered
		and replays_registered,
		"测试 Profile section 应完整注册。"
	)
	return save_graph


func _dispose_setup(setup: Dictionary, delete_profile: bool = true) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	if delete_profile:
		var delete_error: Error = storage.delete_file(
			GFVariantData.get_option_string(
				setup,
				"profile_file_name"
			)
		)
		assert_true(delete_error == OK or delete_error == ERR_FILE_NOT_FOUND, "统计测试清理应返回可预期结果。")
		var account_catalog_delete_error: Error = storage.delete_file(
			LocalAccountCatalogUtility.CATALOG_FILE_NAME
		)
		assert_true(
			account_catalog_delete_error == OK
			or account_catalog_delete_error == ERR_FILE_NOT_FOUND,
			"统计测试的账号目录夹具应可清理。"
		)
	var architecture: GFArchitecture = _get_architecture(setup)
	architecture.dispose()
	setup.clear()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = GFVariantData.get_option_value(setup, "architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_storage(setup: Dictionary) -> GFStorageUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "storage")
	if value is GFStorageUtility:
		var storage: GFStorageUtility = value
		return storage
	assert_true(false, "测试 setup 缺少 GFStorageUtility。")
	return GFStorageUtility.new()


func _get_save_graph(setup: Dictionary) -> GameSaveGraphUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "save_graph")
	if value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = value
		return save_graph
	assert_true(false, "测试 setup 缺少 GameSaveGraphUtility。")
	return GameSaveGraphUtility.new()


func _get_progress_stats_system(setup: Dictionary) -> ProgressStatsSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "progress_stats_system")
	if value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = value
		return progress_stats_system
	assert_true(false, "测试 setup 缺少 ProgressStatsSystem。")
	return ProgressStatsSystem.new()


func _get_stat_int(stats: Dictionary, key: String) -> int:
	return GFVariantData.get_option_int(stats, key)


func _get_stat_bool(stats: Dictionary, key: String) -> bool:
	return GFVariantData.get_option_bool(stats, key)
