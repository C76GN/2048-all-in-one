extends GutTest


func test_settlement_evidence_accepts_only_complete_idle_snapshot() -> void:
	var profile_id: StringName = &"player.test"
	var evidence: GameSaveProfileSettlementEvidence = (
		GameSaveProfileSettlementEvidence.from_snapshot(
			_make_idle_snapshot(profile_id, 7)
		)
	)
	assert_true(evidence.is_valid())
	assert_true(evidence.is_settled_idle(profile_id))
	assert_true(evidence.confirms_persisted_generation(profile_id, 7))
	assert_false(evidence.is_settled_idle(&"player.other"))
	assert_false(evidence.confirms_persisted_generation(profile_id, 6))


func test_settlement_evidence_fails_closed_for_missing_or_wrong_types() -> void:
	var profile_id: StringName = &"player.test"
	var missing_generations: Dictionary = _make_idle_snapshot(profile_id, 7)
	assert_true(missing_generations.erase("unknown_write_generations"))
	assert_false(
		GameSaveProfileSettlementEvidence.from_snapshot(
			missing_generations
		).is_settled_idle(profile_id)
	)

	var string_queue: Dictionary = _make_idle_snapshot(profile_id, 7)
	string_queue["save_queue_size"] = "0"
	assert_false(
		GameSaveProfileSettlementEvidence.from_snapshot(
			string_queue
		).is_valid()
	)

	var mismatched_detached_count: Dictionary = _make_idle_snapshot(profile_id, 7)
	mismatched_detached_count["detached_write_count"] = 1
	assert_false(
		GameSaveProfileSettlementEvidence.from_snapshot(
			mismatched_detached_count
		).is_valid()
	)


func test_settlement_evidence_keeps_unknown_and_queued_work_fenced() -> void:
	var profile_id: StringName = &"player.test"
	var unknown: Dictionary = _make_idle_snapshot(profile_id, 7)
	unknown["write_outcome_unknown"] = true
	unknown["unknown_write_generations"] = PackedInt64Array([8])
	var unknown_evidence: GameSaveProfileSettlementEvidence = (
		GameSaveProfileSettlementEvidence.from_snapshot(unknown)
	)
	assert_true(unknown_evidence.is_valid())
	assert_false(unknown_evidence.is_settled_idle(profile_id))

	var queued: Dictionary = _make_idle_snapshot(profile_id, 7)
	queued["flush_queue_size"] = 1
	assert_false(
		GameSaveProfileSettlementEvidence.from_snapshot(
			queued
		).is_settled_idle(profile_id)
	)


# --- 私有/辅助方法 ---

func _make_idle_snapshot(
	profile_id: StringName,
	persisted_generation: int
) -> Dictionary:
	return {
		"profile_id": profile_id,
		"state": GFSaveProfileUtility.STATE_IDLE,
		"persisted_generation": persisted_generation,
		"save_queue_size": 0,
		"load_queue_size": 0,
		"flush_queue_size": 0,
		"write_outcome_unknown": false,
		"unknown_write_generations": PackedInt64Array(),
		"detached_write_count": 0,
		"detached_storage_request_ids": PackedInt64Array(),
	}
