## 验证 Daily Challenge 的 UTC 稳定身份和不可变比赛资格语义。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_PATH: String = (
	"res://features/gameplay/resources/modes/classic_mode_config.tres"
)


# --- 测试用例 ---

func test_daily_seed_is_stable_within_utc_day_and_changes_at_boundary() -> void:
	var manual_clock: GFManualClock = GFManualClock.new(0, 86_399_000)
	var setup: Dictionary = await _make_challenge_architecture(manual_clock)
	var challenge_utility: GameChallengeUtility = setup[&"challenge"]
	var mode_config: GameModeConfig = _load_classic_mode()
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))

	var before_midnight: GameChallengeMetadata = (
		challenge_utility.get_current_daily_challenge(mode_config, topology)
	)
	assert_not_null(before_midnight, "UTC 日挑战应能从注入时钟派生。")
	assert_true(manual_clock.set_unix_time_msec(86_399_999))
	var same_day: GameChallengeMetadata = (
		challenge_utility.get_current_daily_challenge(mode_config, topology)
	)
	assert_true(manual_clock.set_unix_time_msec(86_400_000))
	var next_day: GameChallengeMetadata = (
		challenge_utility.get_current_daily_challenge(mode_config, topology)
	)

	assert_true(
		before_midnight.get_seed() == same_day.get_seed(),
		"同一 UTC 日期必须得到相同 seed。"
	)
	assert_true(
		before_midnight.get_challenge_hash() == same_day.get_challenge_hash(),
		"同一 UTC 日期必须得到相同 challenge hash。"
	)
	assert_false(
		before_midnight.get_seed() == next_day.get_seed(),
		"UTC 换日必须改变 daily seed。"
	)
	assert_false(
		before_midnight.get_challenge_hash() == next_day.get_challenge_hash(),
		"UTC 换日必须改变 challenge hash。"
	)
	_dispose_setup(setup)


func test_daily_seed_is_restart_stable_and_uses_all_contract_parts() -> void:
	var timestamp_msec: int = 1_735_689_600_000
	var first_setup: Dictionary = await _make_challenge_architecture(
		GFManualClock.new(0, timestamp_msec)
	)
	var second_setup: Dictionary = await _make_challenge_architecture(
		GFManualClock.new(999_000, timestamp_msec)
	)
	var mode_config: GameModeConfig = _load_classic_mode()
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	var first: GameChallengeMetadata = first_setup[&"challenge"].get_current_daily_challenge(
		mode_config,
		topology
	)
	var restarted: GameChallengeMetadata = second_setup[&"challenge"].get_current_daily_challenge(
		mode_config,
		topology
	)

	assert_true(first.get_seed() == restarted.get_seed(), "跨重启 seed 必须稳定。")
	assert_true(
		first.get_challenge_hash() == restarted.get_challenge_hash(),
		"单调 tick 不得进入 Daily Challenge 身份。"
	)
	var expected_seed_result: Dictionary = GFSeedUtility.try_make_stable_seed([
		"2048.daily.challenge",
		GameChallengeUtility.DAILY_CHALLENGE_SCHEMA_VERSION,
		first.get_utc_date(),
		String(first.get_ruleset_id()),
		first.get_ruleset_version(),
		first.get_ruleset_fingerprint(),
		first.get_topology_key(),
	])
	assert_true(GFVariantData.get_option_bool(expected_seed_result, &"ok", false))
	assert_true(
		first.get_seed() == GFVariantData.get_option_int(
			expected_seed_result,
			&"seed",
			-1
		),
		"派生必须显式包含 date、schema、ruleset 和 topology。"
	)

	var changed_mode_resource: Resource = mode_config.duplicate(true)
	assert_true(changed_mode_resource is GameModeConfig)
	var changed_mode: GameModeConfig = changed_mode_resource
	changed_mode.ruleset_version += 1
	var changed_ruleset: GameChallengeMetadata = first_setup[&"challenge"].get_current_daily_challenge(
		changed_mode,
		topology
	)
	var changed_topology: GameChallengeMetadata = first_setup[&"challenge"].get_current_daily_challenge(
		mode_config,
		BoardTopology.create_rectangle(Vector2i(5, 5))
	)
	assert_false(first.get_seed() == changed_ruleset.get_seed())
	assert_false(first.get_seed() == changed_topology.get_seed())
	_dispose_setup(first_setup)
	_dispose_setup(second_setup)


func test_eligibility_snapshots_cover_required_reason_codes_without_mutation() -> void:
	var daily: GameCompetitionEligibility = GameCompetitionEligibility.create([
		GameCompetitionEligibility.REASON_DAILY,
	])
	assert_true(daily.is_eligible(), "Daily 上下文本身不得失格。")
	var disqualifying_codes: Array[StringName] = [
		GameCompetitionEligibility.REASON_DEBUG,
		GameCompetitionEligibility.REASON_REPLAY_CONTINUATION,
		GameCompetitionEligibility.REASON_BOOKMARK,
		GameCompetitionEligibility.REASON_UNDO_REDO,
		GameCompetitionEligibility.REASON_CUSTOM_BOARD,
		GameCompetitionEligibility.REASON_MANUAL_SEED,
	]
	for reason_code: StringName in disqualifying_codes:
		var changed: GameCompetitionEligibility = daily.with_reason(reason_code)
		assert_not_null(changed)
		assert_false(changed.is_eligible(), "%s 必须失格。" % reason_code)
		assert_true(changed.has_reason(reason_code))
		assert_true(daily.is_eligible(), "派生新快照不得改写原资格。")
		assert_false(daily.has_reason(reason_code), "原快照 reason codes 必须保持不变。")

	var round_trip: GameCompetitionEligibility = GameCompetitionEligibility.from_dict(
		daily.to_dict()
	)
	assert_not_null(round_trip)
	var tampered: Dictionary = daily.to_dict()
	tampered[&"eligible"] = false
	assert_null(
		GameCompetitionEligibility.from_dict(tampered),
		"持久化 eligible 必须与 reason codes 的计算结果一致。"
	)


func test_session_metadata_strictly_distinguishes_random_manual_and_daily() -> void:
	var random_metadata: GameSessionMetadata = GameSessionMetadata.create_default()
	var manual_eligibility: GameCompetitionEligibility = (
		GameCompetitionEligibility.create().with_reason(
			GameCompetitionEligibility.REASON_MANUAL_SEED
		)
	)
	var manual_metadata: GameSessionMetadata = GameSessionMetadata.create(
		GameSessionMetadata.SEED_SOURCE_MANUAL,
		null,
		manual_eligibility
	)
	var setup: Dictionary = await _make_challenge_architecture(
		GFManualClock.new(0, 1_735_689_600_000)
	)
	var challenge_utility: GameChallengeUtility = setup[&"challenge"]
	var challenge: GameChallengeMetadata = challenge_utility.get_current_daily_challenge(
		_load_classic_mode(),
		BoardTopology.create_rectangle(Vector2i(4, 4))
	)
	var daily_metadata: GameSessionMetadata = GameSessionMetadata.create(
		GameSessionMetadata.SEED_SOURCE_DAILY,
		challenge,
		GameCompetitionEligibility.create([
			GameCompetitionEligibility.REASON_DAILY,
		])
	)

	assert_not_null(random_metadata)
	assert_not_null(manual_metadata)
	assert_not_null(daily_metadata)
	assert_true(random_metadata.get_seed_source() == GameSessionMetadata.SEED_SOURCE_RANDOM)
	assert_true(manual_metadata.get_seed_source() == GameSessionMetadata.SEED_SOURCE_MANUAL)
	assert_false(manual_metadata.get_eligibility().is_eligible())
	assert_true(daily_metadata.get_seed_source() == GameSessionMetadata.SEED_SOURCE_DAILY)
	assert_true(daily_metadata.get_eligibility().is_eligible())
	assert_true(daily_metadata.get_challenge() != null)
	assert_not_null(GameSessionMetadata.from_dict(random_metadata.to_dict()))
	assert_not_null(GameSessionMetadata.from_dict(manual_metadata.to_dict()))
	assert_not_null(GameSessionMetadata.from_dict(daily_metadata.to_dict()))

	assert_null(
		GameSessionMetadata.create(
			GameSessionMetadata.SEED_SOURCE_MANUAL,
			null,
			GameCompetitionEligibility.create()
		),
		"手动 seed 来源必须携带 manual_seed reason code。"
	)
	assert_null(
		GameSessionMetadata.create(
			GameSessionMetadata.SEED_SOURCE_RANDOM,
			challenge,
			GameCompetitionEligibility.create([
				GameCompetitionEligibility.REASON_DAILY,
			])
		),
		"随机 seed 不得伪装成 Daily Challenge。"
	)
	_dispose_setup(setup)


func test_accessibility_changes_do_not_affect_competition_eligibility() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	await architecture.register_utility(GFStorageUtility, GFStorageUtility.new())
	await architecture.register_utility(GFSettingsUtility, settings)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GameAccessibilityUtility, accessibility)
	await architecture.init()
	var eligibility: GameCompetitionEligibility = GameCompetitionEligibility.create()

	accessibility.set_reduced_motion(true)
	accessibility.set_high_contrast_feedback(true)
	accessibility.set_haptics_enabled(false)
	accessibility.set_shader_effects_enabled(false)
	accessibility.set_vfx_quality(GameAccessibilityState.VfxQuality.REDUCED)

	assert_true(eligibility.is_eligible(), "无障碍偏好不得改变比赛资格。")
	assert_true(
		eligibility.get_reason_codes().is_empty(),
		"无障碍偏好不得写入失格 reason code。"
	)
	architecture.dispose()


# --- 私有/辅助方法 ---

func _make_challenge_architecture(clock: GFClock) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var clock_utility: GameClockUtility = GameClockUtility.new()
	assert_true(clock_utility.set_clock(clock))
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var challenge: GameChallengeUtility = GameChallengeUtility.new()
	await architecture.register_utility(GameClockUtility, clock_utility)
	await architecture.register_utility(GameDeterminismUtility, determinism)
	await architecture.register_utility(GameChallengeUtility, challenge)
	await architecture.init()
	return {
		&"architecture": architecture,
		&"challenge": challenge,
	}


func _load_classic_mode() -> GameModeConfig:
	var resource: Resource = load(_CLASSIC_MODE_PATH)
	assert_true(resource is GameModeConfig, "经典模式资源应可加载。")
	return resource if resource is GameModeConfig else GameModeConfig.new()


func _dispose_setup(setup: Dictionary) -> void:
	var architecture_value: Variant = setup.get(&"architecture")
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()
	setup.clear()
