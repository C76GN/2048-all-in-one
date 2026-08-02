## 验证通用比赛资格和 seed 来源元数据的严格、不可变语义。
extends GutTest


func test_eligibility_snapshots_cover_reason_codes_without_mutation() -> void:
	var eligible: GameCompetitionEligibility = GameCompetitionEligibility.create()
	assert_not_null(eligible)
	assert_true(eligible.is_eligible())

	var disqualifying_codes: Array[StringName] = [
		GameCompetitionEligibility.REASON_DEBUG,
		GameCompetitionEligibility.REASON_REPLAY_CONTINUATION,
		GameCompetitionEligibility.REASON_BOOKMARK,
		GameCompetitionEligibility.REASON_UNDO_REDO,
		GameCompetitionEligibility.REASON_CUSTOM_BOARD,
		GameCompetitionEligibility.REASON_MANUAL_SEED,
	]
	for reason_code: StringName in disqualifying_codes:
		var changed: GameCompetitionEligibility = eligible.with_reason(reason_code)
		assert_not_null(changed)
		assert_false(changed.is_eligible(), "%s 必须失格。" % reason_code)
		assert_true(changed.has_reason(reason_code))
		assert_true(eligible.is_eligible(), "派生新快照不得改写原资格。")
		assert_false(eligible.has_reason(reason_code))

	var round_trip: GameCompetitionEligibility = (
		GameCompetitionEligibility.from_dict(eligible.to_dict())
	)
	assert_not_null(round_trip)
	var tampered: Dictionary = eligible.to_dict()
	tampered[&"eligible"] = false
	assert_null(
		GameCompetitionEligibility.from_dict(tampered),
		"持久化 eligible 必须与 reason codes 的计算结果一致。"
	)
	var legacy_schema: Dictionary = eligible.to_dict()
	legacy_schema[&"schema_version"] = 1
	assert_null(GameCompetitionEligibility.from_dict(legacy_schema))
	assert_null(
		GameCompetitionEligibility.create([&"daily"]),
		"已删除的业务 reason code 不得被通用资格契约接受。"
	)


func test_session_metadata_strictly_distinguishes_random_and_manual() -> void:
	var random_metadata: GameSessionMetadata = GameSessionMetadata.create_default()
	var manual_eligibility: GameCompetitionEligibility = (
		GameCompetitionEligibility.create().with_reason(
			GameCompetitionEligibility.REASON_MANUAL_SEED
		)
	)
	var manual_metadata: GameSessionMetadata = GameSessionMetadata.create(
		GameSessionMetadata.SEED_SOURCE_MANUAL,
		manual_eligibility
	)

	assert_not_null(random_metadata)
	assert_not_null(manual_metadata)
	assert_true(
		random_metadata.get_seed_source()
		== GameSessionMetadata.SEED_SOURCE_RANDOM
	)
	assert_true(
		manual_metadata.get_seed_source()
		== GameSessionMetadata.SEED_SOURCE_MANUAL
	)
	assert_true(random_metadata.get_eligibility().is_eligible())
	assert_false(manual_metadata.get_eligibility().is_eligible())
	assert_not_null(GameSessionMetadata.from_dict(random_metadata.to_dict()))
	assert_not_null(GameSessionMetadata.from_dict(manual_metadata.to_dict()))
	assert_null(
		GameSessionMetadata.create(
			GameSessionMetadata.SEED_SOURCE_MANUAL,
			GameCompetitionEligibility.create()
		),
		"手动 seed 来源必须携带 manual_seed reason code。"
	)
	assert_null(
		GameSessionMetadata.create(
			GameSessionMetadata.SEED_SOURCE_RANDOM,
			manual_eligibility
		),
		"随机 seed 不得携带 manual_seed reason code。"
	)


func test_legacy_or_extra_session_fields_are_rejected() -> void:
	var legacy: Dictionary = GameSessionMetadata.make_default_dict()
	legacy[&"schema_version"] = 1
	assert_null(GameSessionMetadata.from_dict(legacy))

	var extra_field: Dictionary = GameSessionMetadata.make_default_dict()
	extra_field[&"challenge"] = {}
	assert_null(
		GameSessionMetadata.from_dict(extra_field),
		"严格 shape 必须拒绝已删除的嵌套业务字段。"
	)


func test_legacy_result_and_challenge_identity_fields_are_rejected() -> void:
	var result: GameResultRecordedData = GameResultRecordedData.create(
		&"classic",
		"board.rectangle.4x4@test",
		&"gameplay.classic",
		1,
		"a".repeat(64),
		2048,
		"state".sha256_text(),
		GameCompetitionEligibility.create(),
		512,
		20,
		128,
		100
	)
	assert_not_null(result)

	var legacy_schema: Dictionary = result.to_dict()
	legacy_schema[&"schema_version"] = 1
	assert_null(GameResultRecordedData.from_dict(legacy_schema))

	var removed_field: Dictionary = result.to_dict()
	removed_field[&"challenge"] = {}
	assert_null(
		GameResultRecordedData.from_dict(removed_field),
		"结果严格 shape 必须拒绝已删除的 challenge 字段。"
	)

	var identity: Dictionary = result.get_leaderboard_identity()
	identity[&"challenge_key"] = "legacy"
	assert_false(
		GameResultRecordedData.is_leaderboard_identity_valid(identity),
		"配置榜身份不得兼容旧 challenge_key 分组。"
	)


func test_accessibility_changes_do_not_affect_competition_eligibility() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.auto_save_on_change = false
	settings.register_project_defaults()
	var accessibility: GameAccessibilityUtility = GameAccessibilityUtility.new()
	await architecture.register_utility(GFStorageUtility, GFStorageUtility.new())
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
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
