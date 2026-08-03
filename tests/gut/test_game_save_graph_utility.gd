## 验证统一玩家数据 GF Save Profile 的结构、持久化和事务语义。
extends GutTest


# --- 常量 ---

const _BOARD_KEY: String = "board.rectangle.4x4@test"
const _BOARD_SIZE: Vector2i = Vector2i(4, 4)
const _TEST_PLATFORM_STUB_SCRIPT: GDScript = preload(
	"res://tests/gut/fixtures/test_game_platform_utility_stub.gd"
)


# --- 测试用例 ---

func test_profile_has_seven_typed_feature_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var snapshot: Dictionary = save_graph.get_debug_snapshot()
	var document: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	var expected_ids: PackedStringArray = PackedStringArray([
		"achievements",
		"bookmarks",
		"custom_boards",
		"discoveries",
		"progress",
		"replays",
		"tile_blueprints",
	])

	assert_true(save_graph.is_profile_loaded(), "首次运行应完成空档加载决策。")
	assert_not_null(document, "Profile 预览必须是规范 GFSaveDocument。")
	assert_true(
		document != null
		and document.get_schema_id()
		== GameSaveGraphUtility.PROFILE_SCHEMA_ID
		and document.get_schema_version()
		== GameSaveGraphUtility.PROFILE_SCHEMA_VERSION,
		"Profile identity 应由 GFSaveProfile 根 schema 表达。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(
			snapshot,
			"section_ids"
		) == expected_ids,
		"诊断应暴露七个稳定 section 标识。"
	)
	if document != null:
		assert_true(
			document.get_section_ids() == expected_ids,
			"GFSaveProfile 文档必须直接持有七个 typed section。"
		)
		for section_id: String in expected_ids:
			var section: GFSaveSection = document.get_section(
				StringName(section_id)
			)
			assert_true(
				section != null and section.get_payload() is Dictionary,
				"%s 应由 GFSaveSectionProvider 采集严格字典。" % section_id
			)
	_dispose_setup(setup)


func test_save_load_and_flush_expose_typed_terminal_results() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var request_metadata: Dictionary = {
		&"test": "typed_terminal",
		&"nested": {&"marker": "before_request"},
	}

	var save_operation: GFSaveProfileOperation = (
		save_graph.request_save_profile(request_metadata)
	)
	GFVariantData.get_option_dictionary(
		request_metadata,
		&"nested"
	)[&"marker"] = "mutated_after_request"
	assert_true(
		not save_operation.is_completed(),
		"Profile 保存请求必须从后续 tick 开始准备，不得在提交调用栈同步采集。"
	)
	var save_result: GFSaveProfileResult = await _await_profile_operation(
		save_operation,
		setup
	)
	var saved_metadata: Dictionary = (
		save_result.get_metadata()
		if save_result != null
		else {}
	)
	assert_true(
		save_operation.is_completed()
		and save_result != null
		and save_result.get_status() == GFSaveProfileResult.STATUS_SAVED
		and GFVariantData.get_option_string(saved_metadata, &"test")
		== "typed_terminal"
		and GFVariantData.get_option_string(
			GFVariantData.get_option_dictionary(saved_metadata, &"nested"),
			&"marker"
		)
		== "before_request",
		"显式保存必须返回真实 typed saved 终态。"
	)

	var flush_operation: GFSaveProfileOperation = (
		save_graph.request_flush_profile({&"test": "barrier"})
	)
	var flush_result: GFSaveProfileResult = flush_operation.get_result()
	assert_true(
		flush_operation.is_completed()
		and flush_result != null
		and flush_result.get_status()
		== GFSaveProfileResult.STATUS_FLUSHED,
		"已持久化 generation 的 flush 应立即给出 typed flushed 终态。"
	)

	var load_operation: GFSaveProfileOperation = (
		save_graph.request_load_profile()
	)
	var load_result: GFSaveProfileResult = await _await_profile_operation(
		load_operation,
		setup
	)
	var loaded_document: GFSaveDocument = (
		load_result.get_document()
		if load_result != null
		else null
	)
	var document_metadata: Dictionary = (
		loaded_document.get_metadata()
		if loaded_document != null
		else {}
	)
	assert_true(
		load_operation.is_completed()
		and load_result != null
		and load_result.get_status() == GFSaveProfileResult.STATUS_LOADED
		and loaded_document != null
		and document_metadata.has(&"app_version")
		and not document_metadata.has(&"test")
		and not document_metadata.has(&"nested"),
		"读取必须返回 typed loaded 终态。"
	)
	_dispose_setup(setup)


func test_architecture_shutdown_quiesces_and_flushes_latest_profile_generation() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var profile_file_name: String = save_graph.get_profile_file_name()
	var save_dir_name: String = storage.save_dir_name
	var progress_data: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	var stats: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(progress_data, &"stats")
	)
	stats["quiesce_probe"] = {&"highest_score": 4242}
	assert_true(
		save_graph.queue_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			progress_data
		) == OK,
		"关闭前的最新 progress generation 必须进入 SaveGraph 队列。"
	)

	var shutdown_result: GFArchitectureShutdownResult = (
		await architecture.shutdown_async(null, 5.0)
	)
	assert_not_null(shutdown_result)
	assert_true(
		shutdown_result != null and shutdown_result.is_successful(),
		"GF 关闭计划必须等待项目 quiesce flush 后正常完成。"
	)
	assert_engine_error_count(
		0,
		"graceful shutdown 后 dispose 不得再次向已静默 Profile 提交重复 flush。"
	)

	var verifier: GFStorageUtility = GFStorageUtility.new()
	verifier.save_dir_name = save_dir_name
	verifier.allow_absolute_paths = false
	verifier.create_directories_for_nested_paths = true
	verifier.file_format = GFStorageCodec.Format.BINARY
	verifier.include_storage_metadata = true
	verifier.use_integrity_checksum = true
	var persisted: GFStorageReadResult = verifier.load_data(profile_file_name)
	assert_true(persisted.ok, "关闭完成后最新 Profile 必须可由独立 Storage 重新读取。")
	var progress_envelope: Dictionary = (
		GameSaveGraphUtility.extract_profile_section_envelope(
			persisted.payload,
			GameSaveGraphUtility.PROGRESS_SECTION_ID
		)
	)
	var persisted_stats: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(
			GFVariantData.as_dictionary(
				GFVariantData.get_option_value(progress_envelope, &"data")
			),
			&"stats"
		)
	)
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.as_dictionary(
				GFVariantData.get_option_value(
					persisted_stats,
					"quiesce_probe"
				)
			),
			&"highest_score"
		) == 4242,
		"shutdown_async 必须持久化调用时最新的 section generation。"
	)
	var cleanup_error: Error = verifier.delete_file(profile_file_name)
	assert_true(cleanup_error == OK, "关闭持久化回归夹具应可清理。")
	verifier.dispose()
	setup.clear()


func test_async_section_replace_returns_typed_persisted_result() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var candidate: Dictionary = _make_empty_progress_data()
	var caller_bytes: PackedByteArray = PackedByteArray([7])
	candidate["stats"] = {
		"classic": {
			"typed_async": true,
			"legacy_blob": caller_bytes,
		},
	}

	var operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			candidate,
			{&"test": "typed_section_success"}
		)
	)
	caller_bytes[0] = 9
	var result: GameSaveSectionResult = await _await_section_operation(
		operation,
		setup
	)

	assert_not_null(result)
	assert_true(
		result != null
		and result.is_successful()
		and result.get_status() == GameSaveSectionResult.STATUS_PERSISTED
		and result.was_candidate_applied()
		and not result.was_memory_rolled_back(),
		"异步 section 替换必须只在 GF 保存确认后发布 typed persisted。"
	)
	var persisted_progress: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	var persisted_stats: Dictionary = GFVariantData.get_option_dictionary(
		persisted_progress,
		&"stats"
	)
	var persisted_classic: Dictionary = GFVariantData.get_option_dictionary(
		persisted_stats,
		"classic"
	)
	var persisted_bytes: PackedByteArray = GFVariantData.get_option_value(
		persisted_classic,
		&"legacy_blob"
	)
	assert_true(
		GFVariantData.get_option_bool(persisted_classic, &"typed_async")
		and persisted_bytes == PackedByteArray([7]),
		"异步普通替换必须在返回前隔离调用方 PackedArray，权威图不得观察后续修改。"
	)
	_dispose_setup(setup)


func test_async_section_replace_serializes_global_immediate_lane() -> void:
	var storage: _RetryStorage = _RetryStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	storage.profile_save_errors = [ERR_BUSY, OK]

	var first: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			_make_empty_progress_data()
		)
	)
	_get_architecture(setup).tick(0.0)
	var second: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			{"items": []}
		)
	)
	var second_result: GameSaveSectionResult = second.get_result()
	assert_true(
		first.is_pending()
		and second_result != null
		and second_result.get_status() == GameSaveSectionResult.STATUS_BUSY
		and second_result.get_error_code() == ERR_BUSY,
		"全局 immediate lane 在首笔未终结时必须 typed BUSY 拒绝第二笔。"
	)

	assert_true(clock.advance_msec(100))
	_get_architecture(setup).tick(0.0)
	var first_result: GameSaveSectionResult = await _await_section_operation(
		first,
		setup
	)
	assert_true(
		first_result != null and first_result.is_successful(),
		"重试终结后首笔 section 事务应正常释放串行 lane。"
	)
	_dispose_setup(setup)


func test_known_section_save_failure_rolls_back_and_compensates() -> void:
	var storage: _RetryStorage = _RetryStorage.new()
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var baseline: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	var candidate: Dictionary = _make_empty_progress_data()
	candidate["stats"] = {"classic": {"must_rollback": true}}
	storage.profile_save_errors = [ERR_INVALID_DATA]

	var operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			candidate
		)
	)
	var result: GameSaveSectionResult = await _await_section_operation(
		operation,
		setup
	)

	assert_true(
		result != null
		and result.get_status()
		== GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK
		and result.was_candidate_applied()
		and result.was_memory_rolled_back()
		and result.get_compensation_result() != null
		and result.get_compensation_result().is_successful(),
		"已知写失败必须反向恢复快照并等待补偿写终态。"
	)
	assert_true(
		save_graph.get_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID
		) == baseline,
		"补偿完成后权威内存必须与事务前快照一致。"
	)
	_dispose_setup(setup)


func test_section_outcome_unknown_late_success_emits_reconciliation_evidence() -> void:
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	storage.hang_profile_writes = true
	var candidate: Dictionary = _make_empty_progress_data()
	candidate["stats"] = {"classic": {"late_success": true}}
	var operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			candidate
		)
	)
	await _advance_section_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	var result: GameSaveSectionResult = operation.get_result()
	assert_true(
		result != null
		and result.get_status() == GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN
		and save_graph.is_section_reconciliation_pending(),
		"deadline 耗尽但 detached 写未终结时必须保持候选并进入 reconciliation。"
	)

	var settled_evidence: Dictionary = {}
	var settle_count: Dictionary = {&"value": 0}
	var _settled_connection: int = save_graph.section_reconciliation_settled.connect(
		func(evidence: Dictionary) -> void:
			settled_evidence.assign(evidence)
			settle_count[&"value"] = GFVariantData.get_option_int(
				settle_count,
				&"value",
				0
			) + 1
	)
	storage.hang_profile_writes = false
	storage.complete_all_hanging(OK, true)
	await _await_section_reconciliation(save_graph, setup)

	assert_true(
		GFVariantData.get_option_int(settle_count, &"value", 0) == 1
		and GFVariantData.get_option_int(
			settled_evidence,
			&"transaction_id",
			0
		) == operation.get_transaction_id()
		and GFVariantData.get_option_string(
			settled_evidence,
			&"status"
		) == "late_success"
		and GFVariantData.get_option_bool(
			settled_evidence,
			&"candidate_persisted",
			false
		)
		and not GFVariantData.get_option_bool(
			settled_evidence,
			&"memory_rolled_back",
			true
		),
		"late success 必须按原 transaction_id 发布一次可解锁 UI 的完整证据。"
	)
	assert_true(
		save_graph.get_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID
		) == candidate,
		"late success 不得回滚已确认候选。"
	)
	_dispose_setup(setup)


func test_late_compensation_failure_marks_pending_before_unlock_and_flush() -> void:
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var baseline: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	storage.hang_profile_writes = true
	var candidate: Dictionary = _make_empty_progress_data()
	candidate["stats"] = {"classic": {"must_not_resurrect": true}}
	var operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			candidate
		)
	)
	await _advance_section_operation_to_outcome_unknown(
		operation,
		setup,
		storage,
		clock
	)
	storage.complete_all_hanging(ERR_CANT_CREATE, true)
	await _await_hanging_profile_write(storage, setup)
	await _advance_profile_deadlines(setup, clock)
	assert_true(
		save_graph.is_section_reconciliation_pending(),
		"原写迟到失败后，回滚补偿 outcome_unknown 应继续持有 reconciliation 锁。"
	)

	storage.hang_profile_writes = false
	storage.complete_all_hanging(ERR_CANT_CREATE, false)
	await _await_section_reconciliation(save_graph, setup)
	var settled_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(
		not save_graph.is_section_reconciliation_pending()
		and GFVariantData.get_option_bool(
			settled_snapshot,
			&"save_pending",
			false
		),
		"补偿迟到失败在解锁前必须保留新的 rollback generation 待冲刷。"
	)
	var flush_result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_flush_profile({
			&"reason": "test_reconciliation_flush",
		}),
		setup
	)
	assert_true(
		flush_result != null and flush_result.is_successful(),
		"reconciliation 解锁后立即 flush 必须重新持久化内存回滚状态。"
	)
	var persisted: GFStorageReadResult = storage.load_data(
		save_graph.get_profile_file_name()
	)
	var document: GFSaveDocument = (
		GFSaveDocument.from_dict(persisted.payload)
		if persisted.ok
		else null
	)
	var progress_section: GFSaveSection = (
		document.get_section(GameSaveGraphUtility.PROGRESS_SECTION_ID)
		if document != null
		else null
	)
	assert_true(
		progress_section != null
		and GFVariantData.as_dictionary(
			progress_section.get_payload()
		) == baseline,
		"立即 flush 后磁盘不得复活 outcome_unknown 阶段写入的候选。"
	)
	_dispose_setup(setup)


func test_transient_save_retries_follow_100_500_1500_deadlines() -> void:
	var storage: _RetryStorage = _RetryStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var architecture: GFArchitecture = _get_architecture(setup)
	var baseline_attempts: int = storage.profile_save_attempt_count
	storage.profile_save_errors = [ERR_BUSY, ERR_BUSY, ERR_BUSY, OK]

	var save_operation: GFSaveProfileOperation = (
		save_graph.request_save_profile({&"test": "bounded_retry"})
	)
	var flush_operation: GFSaveProfileOperation = (
		save_graph.request_flush_profile({&"test": "retry_barrier"})
	)
	assert_true(
		storage.profile_save_attempt_count == baseline_attempts,
		"Profile 请求调用栈不得同步准备 Provider 或启动 Storage。"
	)
	architecture.tick(0.0)
	assert_true(
		storage.profile_save_attempt_count == baseline_attempts + 1
		and not save_operation.is_completed()
		and not flush_operation.is_completed(),
		(
			"首次临时失败后 save/flush 必须保持 pending："
			+ "baseline=%d attempts=%d save_pending=%s flush_pending=%s state=%s"
		)
		% [
			baseline_attempts,
			storage.profile_save_attempt_count,
			not save_operation.is_completed(),
			not flush_operation.is_completed(),
			JSON.stringify(save_graph.get_debug_snapshot()),
		]
	)
	assert_true(clock.advance_msec(99))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 1)
	assert_true(clock.advance_msec(1))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 2)
	assert_true(clock.advance_msec(499))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 2)
	assert_true(clock.advance_msec(1))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 3)
	assert_true(clock.advance_msec(1499))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 3)
	assert_true(clock.advance_msec(1))
	architecture.tick(0.0)
	assert_true(storage.profile_save_attempt_count == baseline_attempts + 4)
	storage.wait_for_async_tasks()
	architecture.tick(0.0)

	var save_result: GFSaveProfileResult = save_operation.get_result()
	var flush_result: GFSaveProfileResult = flush_operation.get_result()
	assert_true(
		save_result != null
		and save_result.get_status() == GFSaveProfileResult.STATUS_SAVED
		and save_result.get_attempt_count() == 4
		and save_result.get_storage_request_ids().size() == 4
		and flush_result != null
		and flush_result.get_status() == GFSaveProfileResult.STATUS_FLUSHED,
		"有限重试最终成功后 save 与其 flush 屏障都必须获得 typed 终态。"
	)
	_dispose_setup(setup)


func test_late_provider_failure_rolls_back_earlier_sections() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var document: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(document)
	if document == null:
		_dispose_setup(setup)
		return

	var progress: GFSaveSection = document.get_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	var progress_payload: Dictionary = GFVariantData.as_dictionary(
		progress.get_payload()
	)
	progress_payload["stats"] = {"classic": {"changed": true}}
	var _progress_set: bool = document.set_section(
		GFSaveSection.new().configure(
			progress.get_section_id(),
			progress.get_schema_version(),
			progress_payload
		)
	)
	var replay: GFSaveSection = document.get_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID
	)
	var _replay_set: bool = document.set_section(
		GFSaveSection.new().configure(
			replay.get_section_id(),
			replay.get_schema_version(),
			{"items": [{"invalid": true}]}
		)
	)
	assert_true(
		storage.save_data(
			save_graph.get_profile_file_name(),
			document.to_dict()
		) == OK,
		"故障注入文档应成功写入。"
	)
	var load_result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_load_profile(
			{&"profile_file": save_graph.get_profile_file_name()},
			{&"reason": "test_apply_failure"}
		),
		setup
	)
	assert_true(
		load_result != null
		and load_result.get_error_code() == ERR_INVALID_DATA,
		"后期 replay provider 失败必须产生 typed apply failure。"
	)
	assert_true(
		save_graph.get_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID
		) == _make_empty_progress_data(),
		"GFSaveProfileUtility 必须回滚此前已应用的 progress provider。"
	)
	var last_load: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)
	assert_true(
		GFVariantData.get_option_string_name(last_load, "status")
		== GFSaveProfileResult.STATUS_APPLY_FAILED,
		"诊断应保留 typed apply_failed 终态。"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			last_load,
			&"failed_section_id"
		)
		== GameSaveGraphUtility.REPLAYS_SECTION_ID
		and GFVariantData.get_option_array(
			last_load,
			&"rollback_errors"
		).is_empty(),
		"失败必须发生在后期 replay provider，且此前 section 全部回滚成功。"
	)
	_dispose_setup(setup)


func test_profile_schema_v10_is_backed_up_then_reset_to_v11() -> void:
	var save_dir_name: String = (
		"gut_save_profile_v10_%s"
		% GFUuid.generate_v4().replace("-", "")
	)
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var current: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(current)
	if current == null:
		_dispose_setup(setup)
		return
	var legacy: GFSaveDocument = GFSaveDocument.new().configure(
		GameSaveGraphUtility.PROFILE_SCHEMA_ID,
		10,
		current.get_sections(),
		{&"app_version": "pre-profile-v11"}
	)
	var legacy_payload: Dictionary = legacy.to_dict()
	assert_true(
		storage.save_data(
			save_graph.get_profile_file_name(),
			legacy_payload
		) == OK,
		"v10 reset 夹具应成功写入。"
	)
	_dispose_setup(setup, false)
	storage.dispose()

	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name
	)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_storage: GFStorageUtility = _get_storage(reloaded)
	var load_result: Dictionary = GFVariantData.get_option_dictionary(
		reloaded_graph.get_debug_snapshot(),
		"last_load"
	)
	var recovery_file: String = GFVariantData.get_option_string(
		load_result,
		"recovery_file"
	)
	assert_true(
		GFVariantData.get_option_bool(
			load_result,
			"recovered_obsolete_profile"
		)
		and recovery_file.ends_with(".schema-10.save"),
		"Profile schema 迁移必须显式备份 v10，再重建 v11。"
	)
	var backup: GFStorageReadResult = reloaded_storage.load_data(
		recovery_file
	)
	assert_true(
		backup.ok and backup.payload == legacy_payload,
		"恢复备份必须逐字段保留旧文档。"
	)
	var current_result: GFStorageReadResult = reloaded_storage.load_data(
		reloaded_graph.get_profile_file_name()
	)
	var current_document: GFSaveDocument = (
		GFSaveDocument.from_dict(current_result.payload)
		if current_result.ok
		else null
	)
	assert_true(
		current_document != null
		and current_document.get_schema_version()
		== GameSaveGraphUtility.PROFILE_SCHEMA_VERSION,
		"活动 Profile 必须只写当前 v11 schema。"
	)
	assert_true(
		reloaded_storage.delete_file(recovery_file) == OK,
		"恢复备份测试文件应可清理。"
	)
	_dispose_setup(reloaded, false)


func test_future_profile_schema_is_rejected_without_reset() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var current: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(current)
	if current == null:
		_dispose_setup(setup)
		return
	var future: GFSaveDocument = GFSaveDocument.new().configure(
		GameSaveGraphUtility.PROFILE_SCHEMA_ID,
		GameSaveGraphUtility.PROFILE_SCHEMA_VERSION + 1,
		current.get_sections()
	)
	assert_true(
		storage.save_data(
			save_graph.get_profile_file_name(),
			future.to_dict()
		) == OK
	)
	var load_result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_load_profile(
			{&"profile_file": save_graph.get_profile_file_name()},
			{&"reason": "test_future_schema"}
		),
		setup
	)
	assert_true(
		load_result != null
		and load_result.get_error_code() == ERR_INVALID_DATA,
		"未来 schema 必须显式失败，禁止 reset 覆盖。"
	)
	var last_load: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)
	assert_true(
		GFVariantData.get_option_string_name(last_load, "status")
		== GFSaveProfileResult.STATUS_FUTURE_SCHEMA,
		"未来 schema 应保留 typed future_schema 证据。"
	)
	_dispose_setup(setup)


func test_old_section_account_profile_is_backed_up_then_activated() -> void:
	var save_dir_name: String = (
		"gut_save_profile_old_section_%s"
		% GFUuid.generate_v4().replace("-", "")
	)
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var document: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(document)
	if document == null:
		_dispose_setup(setup)
		return
	var bookmark_section: GFSaveSection = document.get_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	var replay_section: GFSaveSection = document.get_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID
	)
	assert_not_null(bookmark_section)
	assert_not_null(replay_section)
	if bookmark_section == null or replay_section == null:
		_dispose_setup(setup)
		return
	var _bookmark_set: bool = document.set_section(
		GFSaveSection.new().configure(
			bookmark_section.get_section_id(),
			bookmark_section.get_schema_version() - 1,
			bookmark_section.get_payload()
		)
	)
	var _replay_set: bool = document.set_section(
		GFSaveSection.new().configure(
			replay_section.get_section_id(),
			replay_section.get_schema_version() - 1,
			replay_section.get_payload()
		)
	)
	var profile_file_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			GFUuid.generate_v7(1_000_000)
		)
	)
	assert_true(
		storage.save_data(
			profile_file_name,
			document.to_dict()
		) == OK
	)
	assert_true(
		await GameSaveProfileOperationTestSupport.activate_profile(
			save_graph,
			profile_file_name,
			true,
			_get_architecture(setup),
			get_tree(),
			storage
		) == OK,
		"启动账号 Profile 时应备份并重建已知旧 section，而不是返回错误码 33。"
	)
	assert_true(
		save_graph.get_profile_file_name() == profile_file_name,
		"重建完成后账号 Profile 必须成为活动路径。"
	)
	var last_load: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)
	assert_true(
		GFVariantData.get_option_bool(
			last_load,
			"recovered_obsolete_profile"
		)
		and GFVariantData.get_option_int(
			last_load,
			"obsolete_schema_version"
		)
		== GameSaveGraphUtility.PROFILE_SCHEMA_VERSION,
		"顶层版本未变时也必须记录 section 驱动的破坏性重建。"
	)
	var recovery_file: String = GFVariantData.get_option_string(
		last_load,
		"recovery_file"
	)
	var backup: GFStorageReadResult = storage.load_data(recovery_file)
	assert_true(
		backup.ok and backup.payload == document.to_dict(),
		"重建前必须逐字段备份含旧 section 的原 Profile。"
	)
	var current_result: GFStorageReadResult = storage.load_data(
		profile_file_name
	)
	var current_document: GFSaveDocument = (
		GFSaveDocument.from_dict(current_result.payload)
		if current_result.ok
		else null
	)
	assert_true(
		current_document != null
		and current_document.get_section(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		).get_schema_version()
		== bookmark_section.get_schema_version()
		and current_document.get_section(
			GameSaveGraphUtility.REPLAYS_SECTION_ID
		).get_schema_version()
		== replay_section.get_schema_version(),
		"重建后必须立即写回当前 section schema。"
	)
	assert_true(
		storage.delete_file(recovery_file) == OK,
		"旧 section 恢复备份测试文件应可清理。"
	)
	_dispose_setup(setup)


func test_future_section_is_rejected_even_with_an_old_section() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var document: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(document)
	if document == null:
		_dispose_setup(setup)
		return
	var old_section: GFSaveSection = document.get_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	var future_section: GFSaveSection = document.get_section(
		GameSaveGraphUtility.REPLAYS_SECTION_ID
	)
	assert_not_null(old_section)
	assert_not_null(future_section)
	if old_section == null or future_section == null:
		_dispose_setup(setup)
		return
	var _old_set: bool = document.set_section(
		GFSaveSection.new().configure(
			old_section.get_section_id(),
			old_section.get_schema_version() - 1,
			old_section.get_payload()
		)
	)
	var _future_set: bool = document.set_section(
		GFSaveSection.new().configure(
			future_section.get_section_id(),
			future_section.get_schema_version() + 1,
			future_section.get_payload()
		)
	)
	var persisted_future_payload: Dictionary = document.to_dict()
	assert_true(
		storage.save_data(
			save_graph.get_profile_file_name(),
			persisted_future_payload
		) == OK
	)
	var load_result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_load_profile(
			{&"profile_file": save_graph.get_profile_file_name()},
			{&"reason": "test_future_section"}
		),
		setup
	)
	assert_true(
		load_result == null or not load_result.is_successful(),
		"任一 future section 都必须阻止 reset 覆盖。"
	)
	var last_load: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)
	assert_true(
		GFVariantData.get_option_string_name(last_load, "status")
		== GFSaveProfileResult.STATUS_FUTURE_SCHEMA
		and not GFVariantData.get_option_bool(
			last_load,
			"recovered_obsolete_profile"
		),
		"future section 必须保留 typed future_schema 证据。"
	)
	var preserved: GFStorageReadResult = storage.load_data(
		save_graph.get_profile_file_name()
	)
	assert_true(
		preserved.ok and preserved.payload == persisted_future_payload,
		"future section 文档不得被 destructive reset 改写。"
	)
	_dispose_setup(setup)




func test_high_frequency_sections_coalesce_into_one_async_profile_write() -> void:
	var setup: Dictionary = await _create_persistence_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var baseline_profile_state: Dictionary = (
		GFVariantData.get_option_dictionary(
			save_graph.get_debug_snapshot(),
			&"profile_state"
		)
	)
	var completion_counter: Dictionary = {"value": 0}
	var _completion_connection: int = save_graph.profile_save_completed.connect(
		func(_error: Error) -> void:
			completion_counter["value"] = GFVariantData.get_option_int(
				completion_counter,
				"value"
			) + 1
	)

	var progress_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		_make_empty_progress_data()
	)
	var discovery_error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		{"tile_compositions": [], "board_topologies": []}
	)
	var queued_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(progress_error == OK and discovery_error == OK, "合法高频 section 应先原子更新内存图。")
	assert_true(GFVariantData.get_option_bool(queued_snapshot, "save_pending"), "同帧更新后应只留下一个待写 Profile。")
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(
				queued_snapshot,
				&"profile_state"
			),
			&"generation"
		)
		== GFVariantData.get_option_int(
			baseline_profile_state,
			&"generation"
		),
		"静默窗口内不应提前创建 GF 保存 generation。"
	)

	save_graph.tick(1.0)
	architecture.tick(0.0)
	storage.wait_for_async_tasks()
	architecture.tick(0.0)
	var completed_snapshot: Dictionary = save_graph.get_debug_snapshot()
	var completed_profile_state: Dictionary = (
		GFVariantData.get_option_dictionary(
			completed_snapshot,
			&"profile_state"
		)
	)
	assert_true(
		GFVariantData.get_option_int(completion_counter, "value") == 1,
		"多个高频 section 必须合并成一次 GFStorageUtility 异步事务。"
	)
	assert_false(GFVariantData.get_option_bool(completed_snapshot, "save_pending"), "异步写入完成后不应残留待写状态。")
	assert_true(
		GFVariantData.get_option_int(
			completed_profile_state,
			&"generation"
		)
		== GFVariantData.get_option_int(
			baseline_profile_state,
			&"generation"
		) + 1
		and GFVariantData.get_option_int(
			completed_profile_state,
			&"persisted_generation"
		)
		== GFVariantData.get_option_int(
			completed_profile_state,
			&"generation"
		),
		"两个 section 更新应合并为一个且已持久化的 GF generation。"
	)

	_dispose_setup(setup)


func test_bookmark_save_submission_keeps_synchronous_work_bounded() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var bookmark: BookmarkData = _make_bookmark(600, 512)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 14)

	var started_usec: int = Time.get_ticks_usec()
	var operation: GameSaveSectionOperation = (
		bookmark_system.request_save_bookmark(bookmark)
	)
	var submission_usec: int = Time.get_ticks_usec() - started_usec
	var result: GameSaveSectionResult = await _await_section_operation(
		operation,
		setup
	)
	storage.wait_for_async_tasks()

	assert_true(
		result != null and result.is_successful(),
		"性能样本也必须经过真实 GF Profile 事务并成功持久化。"
	)
	assert_lt(
		submission_usec,
		75_000,
		"14 步书签的同步候选校验、Profile gather 与异步 IO 提交必须稳定低于旧路径的 130ms 级长帧。"
	)
	gut.p("bookmark_submission_usec=%d" % submission_usec, 1)
	_dispose_setup(setup)


func test_bookmark_load_cache_reuses_parse_and_returns_isolated_resources() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var bookmark: BookmarkData = _make_bookmark(610, 1024)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 2)
	bookmark.replay_actions = [Vector2i.RIGHT]
	bookmark.replay_checkpoints = [_make_replay_checkpoint(1, 1024)]
	var save_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	assert_true(
		save_result != null and save_result.is_successful(),
		"缓存回归样本必须先成功持久化。"
	)

	var before_load: Dictionary = bookmark_system.get_cache_debug_snapshot()
	var first_load: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var after_first_load: Dictionary = (
		bookmark_system.get_cache_debug_snapshot()
	)
	var second_load: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var after_second_load: Dictionary = (
		bookmark_system.get_cache_debug_snapshot()
	)

	assert_true(first_load.size() == 1 and second_load.size() == 1)
	assert_true(
		GFVariantData.get_option_int(after_first_load, &"misses")
		== GFVariantData.get_option_int(before_load, &"misses") + 1,
		"首次读取必须解析当前 Profile 的书签 section。"
	)
	assert_true(
		GFVariantData.get_option_int(after_second_load, &"misses")
		== GFVariantData.get_option_int(after_first_load, &"misses"),
		"重复读取不应再次反序列化完整书签 section。"
	)
	assert_true(
		GFVariantData.get_option_int(after_second_load, &"hits")
		== GFVariantData.get_option_int(after_first_load, &"hits") + 1,
		"重复读取必须命中书签解析缓存。"
	)
	if first_load.size() == 1 and second_load.size() == 1:
		assert_false(
			is_same(first_load[0], second_load[0]),
			"公开读取结果必须与缓存及其他调用方保持资源隔离。"
		)
		first_load[0].score = 999_999
		first_load[0].game_state_history["undo"] = []
		first_load[0].replay_checkpoints[0].score = 999_999
		assert_true(
			GFVariantData.get_option_array(
				second_load[0].game_state_history,
				"undo"
			).size() == 2,
			"一个调用方修改历史字典不得污染另一个调用方的缓存副本。"
		)
		assert_true(
			second_load[0].replay_checkpoints[0].score == 1024,
			"一个调用方修改检查点子资源不得污染另一个调用方的缓存副本。"
		)
		var third_load: Array[BookmarkData] = bookmark_system.load_bookmarks()
		assert_true(
			third_load.size() == 1
			and third_load[0].score == 1024
			and GFVariantData.get_option_array(
				third_load[0].game_state_history,
				"undo"
			).size() == 2
			and third_load[0].replay_checkpoints[0].score == 1024,
			"调用方修改返回资源不得污染后续缓存读取。"
		)
	_dispose_setup(setup)


func test_bookmark_cache_large_history_benchmark_stays_bounded() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var bookmark: BookmarkData = _make_bookmark(615, 16384)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 512)
	bookmark.game_state_history["redo"] = GFVariantData.get_option_array(
		bookmark.game_state_history,
		"undo"
	).duplicate(true)
	var submission_started_usec: int = Time.get_ticks_usec()
	var operation: GameSaveSectionOperation = (
		bookmark_system.request_save_bookmark(bookmark)
	)
	var submission_usec: int = (
		Time.get_ticks_usec() - submission_started_usec
	)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		operation,
		setup
	)
	assert_true(
		save_result != null and save_result.is_successful(),
		"大型历史基准样本必须先成功持久化。"
	)

	var memory_before: float = Performance.get_monitor(
		Performance.MEMORY_STATIC
	)
	var gather_started_usec: int = Time.get_ticks_usec()
	var section_data: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	var gather_usec: int = Time.get_ticks_usec() - gather_started_usec
	var parse_started_usec: int = Time.get_ticks_usec()
	var parsed_sample: BookmarkData = BookmarkData.from_dict(
		GFVariantData.as_dictionary(
			GFVariantData.get_option_array(section_data, "items")[0]
		)
	)
	var direct_parse_usec: int = Time.get_ticks_usec() - parse_started_usec
	var first_started_usec: int = Time.get_ticks_usec()
	var first_load: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var first_load_usec: int = Time.get_ticks_usec() - first_started_usec
	var cache_started_usec: int = Time.get_ticks_usec()
	var cached_load: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var cached_load_usec: int = Time.get_ticks_usec() - cache_started_usec
	var memory_after: float = Performance.get_monitor(
		Performance.MEMORY_STATIC
	)
	assert_true(
		parsed_sample != null
		and first_load.size() == 1
		and cached_load.size() == 1
		and GFVariantData.get_option_array(
			parsed_sample.game_state_history,
			"undo"
		).size() == BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT >> 1
		and GFVariantData.get_option_array(
			parsed_sample.game_state_history,
			"redo"
		).size() == BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT >> 1
	)
	assert_lt(
		submission_usec,
		75_000,
		"新书签最坏 64 条持久化历史必须显著低于旧路径的 300ms 级长帧。"
	)
	assert_lt(
		first_load_usec,
		20_000,
		"provider 隔离缓存快照的首次读取必须保持在一帧量级。"
	)
	assert_lt(
		cached_load_usec,
		20_000,
		"大型历史缓存命中必须保持在一帧量级，避免打开书签页产生可感知卡顿。"
	)
	gut.p(
		(
			"bookmark_cache_benchmark submission_usec=%d "
			+ "gather_usec=%d direct_parse_usec=%d "
			+ "first_cache_snapshot_usec=%d cached_duplicate_usec=%d "
			+ "static_memory_delta=%d"
		) % [
			submission_usec,
			gather_usec,
			direct_parse_usec,
			first_load_usec,
			cached_load_usec,
			int(memory_after - memory_before),
		],
		1
	)
	_dispose_setup(setup)


func test_bookmark_cache_invalidates_after_save_and_delete() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var first: BookmarkData = _make_bookmark(620, 1024)
	var first_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(first),
		setup
	)
	assert_true(first_result != null and first_result.is_successful())
	assert_true(bookmark_system.load_bookmarks().size() == 1)
	assert_true(
		GFVariantData.get_option_bool(
			bookmark_system.get_cache_debug_snapshot(),
			&"valid"
		)
	)

	var second: BookmarkData = _make_bookmark(621, 2048)
	var second_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(second),
		setup
	)
	assert_true(second_result != null and second_result.is_successful())
	assert_false(
		GFVariantData.get_option_bool(
			bookmark_system.get_cache_debug_snapshot(),
			&"valid"
		),
		"保存终态必须使旧书签缓存失效。"
	)
	var after_save: Array[BookmarkData] = bookmark_system.load_bookmarks()
	assert_true(after_save.size() == 2, "保存后重新读取必须包含新书签。")

	var delete_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_delete_bookmark(second.bookmark_id),
		setup
	)
	assert_true(delete_result != null and delete_result.is_successful())
	assert_false(
		GFVariantData.get_option_bool(
			bookmark_system.get_cache_debug_snapshot(),
			&"valid"
		),
		"删除终态必须使旧书签缓存失效。"
	)
	var after_delete: Array[BookmarkData] = bookmark_system.load_bookmarks()
	assert_true(
		after_delete.size() == 1
		and after_delete[0].bookmark_id == first.bookmark_id,
		"删除后重新读取不得返回已删除书签。"
	)
	_dispose_setup(setup)


func test_rejected_bookmark_request_keeps_authoritative_cache() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var bookmark: BookmarkData = _make_bookmark(624, 1024)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	assert_true(save_result != null and save_result.is_successful())
	assert_true(bookmark_system.load_bookmarks().size() == 1)
	var before_rejection: Dictionary = (
		bookmark_system.get_cache_debug_snapshot()
	)

	var duplicate_result: GameSaveSectionResult = (
		await _await_section_operation(
			bookmark_system.request_save_bookmark(bookmark),
			setup
		)
	)
	assert_true(
		duplicate_result != null
		and duplicate_result.get_status()
		== GameSaveSectionResult.STATUS_INVALID_REQUEST
		and not duplicate_result.was_candidate_applied(),
		"重复稳定 ID 必须形成未触碰权威内存的拒绝终态。"
	)
	var after_rejection: Dictionary = (
		bookmark_system.get_cache_debug_snapshot()
	)
	assert_true(
		GFVariantData.get_option_bool(after_rejection, &"valid")
		and GFVariantData.get_option_int(after_rejection, &"misses")
		== GFVariantData.get_option_int(before_rejection, &"misses"),
		"INVALID_REQUEST 不得清除仍代表权威内存的书签缓存。"
	)
	assert_true(
		bookmark_system.load_bookmarks().size() == 1,
		"拒绝请求后下一次读取必须继续命中原缓存。"
	)
	_dispose_setup(setup)


func test_bookmark_save_failure_restores_previous_validated_envelopes() -> void:
	var storage: _RetryStorage = _RetryStorage.new()
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		true,
		PackedByteArray(),
		storage
	)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var first: BookmarkData = _make_bookmark(625, 1024)
	var first_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(first),
		setup
	)
	assert_true(first_result != null and first_result.is_successful())
	var baseline: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)

	var second: BookmarkData = _make_bookmark(626, 2048)
	second.game_state_history = _make_bookmark_history(second, 3)
	storage.profile_save_errors = [ERR_INVALID_DATA]
	var failed_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(second),
		setup
	)

	assert_true(
		failed_result != null
		and failed_result.get_status()
		== GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK
		and failed_result.was_memory_rolled_back(),
		"书签写失败必须通过 provider envelope 快照恢复权威内存。"
	)
	assert_true(
		save_graph.get_section_data(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) == baseline,
		"书签事务回滚后必须逐字恢复此前已验证的持久化 envelope。"
	)
	var restored: Array[BookmarkData] = bookmark_system.load_bookmarks()
	assert_true(
		restored.size() == 1
		and restored[0].bookmark_id == first.bookmark_id,
		"回滚后解析缓存不得泄漏失败候选。"
	)
	_dispose_setup(setup)


func test_bookmark_cache_is_scoped_to_active_profile_id() -> void:
	var setup: Dictionary = await _create_persistence_architecture("", true)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var bookmark: BookmarkData = _make_bookmark(630, 4096)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	assert_true(save_result != null and save_result.is_successful())
	assert_true(bookmark_system.load_bookmarks().size() == 1)
	var original_profile_id: StringName = save_graph.get_active_profile_id()

	var account_id: String = GFUuid.generate_v7()
	var account_profile_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(account_id)
	)
	var switch_error: Error = await GameSaveProfileOperationTestSupport.activate_profile(
		save_graph,
		account_profile_name,
		false,
		_get_architecture(setup),
		get_tree(),
		_get_storage(setup)
	)
	assert_true(switch_error == OK, "测试 Profile 应能切换到独立空账号。")
	assert_true(
		save_graph.get_active_profile_id() != original_profile_id,
		"账号切换必须改变活动 GF Profile ID。"
	)
	assert_true(
		bookmark_system.load_bookmarks().is_empty(),
		"新账号不得复用上一账号的书签缓存。"
	)
	var switched_snapshot: Dictionary = (
		bookmark_system.get_cache_debug_snapshot()
	)
	assert_true(
		GFVariantData.get_option_string_name(
			switched_snapshot,
			&"profile_id"
		) == save_graph.get_active_profile_id(),
		"缓存身份必须跟随当前活动 Profile。"
	)
	_dispose_setup(setup)


func test_bookmark_cache_waits_for_async_profile_load_terminal() -> void:
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		true,
		PackedByteArray(),
		storage
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var first_profile_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			GFUuid.generate_v7()
		)
	)
	var second_profile_name: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			GFUuid.generate_v7()
		)
	)
	assert_true(
		await GameSaveProfileOperationTestSupport.activate_profile(
			save_graph,
			first_profile_name,
			true,
			architecture,
			get_tree(),
			storage
		) == OK,
		"异步缓存回归的第一账号 Profile 必须创建成功。"
	)
	var bookmark: BookmarkData = _make_bookmark(631, 4096)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	assert_true(save_result != null and save_result.is_successful())
	assert_true(
		await GameSaveProfileOperationTestSupport.activate_profile(
			save_graph,
			second_profile_name,
			false,
			architecture,
			get_tree(),
			storage
		) == OK,
		"异步缓存回归的第二账号 Profile 必须创建成功。"
	)
	assert_true(bookmark_system.load_bookmarks().is_empty())

	storage.hang_profile_reads = true
	var transition_state: Dictionary = {
		&"done": false,
		&"error": FAILED,
	}
	var transition_runner: Callable = func() -> void:
		var transition_error: Error = await save_graph.activate_profile_async(
			first_profile_name,
			false
		)
		transition_state[&"error"] = transition_error
		transition_state[&"done"] = true
	transition_runner.call_deferred()
	for _poll_index: int in range(120):
		architecture.tick(0.0)
		await get_tree().process_frame
		if (
			not storage.hanging_read_operations.is_empty()
			and save_graph.is_profile_loaded()
		):
			# activate_profile_async 先异步探测目标文件，再进入真正 GF Profile load。
			storage.complete_all_hanging_reads()
			continue
		if (
			not save_graph.is_profile_loaded()
			and not storage.hanging_read_operations.is_empty()
		):
			break

	assert_false(
		storage.hanging_read_operations.is_empty(),
		"账号切换必须停在目标 Profile 的异步读取窗口。"
	)
	assert_false(
		save_graph.is_profile_loaded(),
		"目标 Profile 读取终态前不得宣称已加载。"
	)
	assert_true(
		bookmark_system.load_bookmarks().is_empty(),
		"目标 Profile 读取中不得暴露默认 section。"
	)
	assert_false(
		GFVariantData.get_option_bool(
			bookmark_system.get_cache_debug_snapshot(),
			&"valid"
		),
		"读取中的默认空 section 不得进入目标 Profile 缓存。"
	)

	storage.complete_all_hanging_reads()
	for _poll_index: int in range(120):
		architecture.tick(0.0)
		await get_tree().process_frame
		if GFVariantData.get_option_bool(
			transition_state,
			&"done"
		):
			break
	assert_true(
		GFVariantData.get_option_bool(transition_state, &"done")
		and GFVariantData.get_option_int(
			transition_state,
			&"error",
			FAILED
		) == OK
		and save_graph.is_profile_loaded(),
		"目标 Profile 必须完成唯一成功终态。"
	)
	assert_false(
		GFVariantData.get_option_bool(
			bookmark_system.get_cache_debug_snapshot(),
			&"valid"
		),
		"Profile LOAD 终态必须使读取窗口内的缓存失效。"
	)
	var restored: Array[BookmarkData] = bookmark_system.load_bookmarks()
	assert_true(
		restored.size() == 1
		and restored[0].bookmark_id == bookmark.bookmark_id,
		"异步加载完成后必须重新解析目标 Profile 的真实书签。"
	)
	storage.hang_profile_reads = false
	var first_delete_error: Error = storage.delete_file(
		first_profile_name
	)
	var second_delete_error: Error = storage.delete_file(
		second_profile_name
	)
	assert_true(
		first_delete_error == OK
		or first_delete_error == ERR_FILE_NOT_FOUND
	)
	assert_true(
		second_delete_error == OK
		or second_delete_error == ERR_FILE_NOT_FOUND
	)
	_dispose_setup(setup)










func test_stats_bookmarks_and_replays_persist_in_one_graph_file() -> void:
	var save_dir_name: String = "gut_save_graph_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var setup: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var custom_board_system: CustomBoardSystem = _get_custom_board_system(setup)
	var replay_system: ReplaySystem = _get_replay_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)

	var stats_result: GameSaveSectionResult = await _await_section_operation(
		progress_stats_system.request_record_game_result(
			_make_game_result(2048, 32, 2048, 500, 2048, true)
		),
		setup
	)
	var bookmark: BookmarkData = _make_bookmark(600, 512)
	var custom_board: CustomBoardData = _make_custom_board()
	var replay: ReplayData = _make_replay(700, 2048)
	var bookmark_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	var custom_board_result: GameSaveSectionResult = await _await_section_operation(
		custom_board_system.request_save_custom_board(custom_board),
		setup
	)
	var replay_result: GameSaveSectionResult = await _await_section_operation(
		replay_system.request_save_replay(replay),
		setup
	)
	assert_true(stats_result != null and stats_result.is_successful(), "统计 section 应保存成功。")
	assert_true(bookmark_result != null and bookmark_result.is_successful(), "书签 section 应保存成功。")
	assert_true(
		custom_board_result != null and custom_board_result.is_successful(),
		"玩家棋盘 section 应保存成功。"
	)
	assert_true(replay_result != null and replay_result.is_successful(), "回放 section 应保存成功。")
	assert_true(GFUuid.is_valid(bookmark.bookmark_id, 7), "书签应获得稳定 UUID v7。")
	assert_true(GFUuid.is_valid(custom_board.custom_board_id, 7), "玩家棋盘应获得稳定 UUID v7。")
	assert_true(GFUuid.is_valid(replay.replay_id, 7), "回放应获得稳定 UUID v7。")
	var persisted_save_files: PackedStringArray = storage.list_files(
		"",
		"save",
		true
	)
	assert_true(
		persisted_save_files.size() == 2
		and persisted_save_files.has(
			save_graph.get_profile_file_name()
		)
		and persisted_save_files.has(
			LocalAccountCatalogUtility.CATALOG_FILE_NAME
		),
		"六类玩家业务 section 应只落到一个原子 Profile；设备账号索引保持独立。"
	)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(save_dir_name, true)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(reloaded)
	var reloaded_bookmarks: BookmarkSystem = _get_bookmark_system(reloaded)
	var reloaded_custom_boards: CustomBoardSystem = _get_custom_board_system(reloaded)
	var reloaded_replays: ReplaySystem = _get_replay_system(reloaded)
	assert_true(
		reloaded_graph.is_profile_loaded(),
		"重载事务应成功：%s" % _describe_load_failure(reloaded_graph)
	)
	assert_true(reloaded_progress_stats_system.get_high_score("classic", _BOARD_KEY) == 2048, "重载后应保留统计。")
	var bookmarks: Array[BookmarkData] = reloaded_bookmarks.load_bookmarks()
	var custom_boards: Array[CustomBoardData] = reloaded_custom_boards.load_custom_boards()
	var replays: Array[ReplayData] = reloaded_replays.load_replays()
	assert_true(bookmarks.size() == 1, "重载后应保留书签目录。")
	assert_true(custom_boards.size() == 1, "重载后应保留玩家棋盘目录。")
	assert_true(replays.size() == 1, "重载后应保留回放目录。")
	if bookmarks.size() == 1 and custom_boards.size() == 1 and replays.size() == 1:
		assert_true(bookmarks[0].bookmark_id == bookmark.bookmark_id, "书签稳定 ID 应跨重载保留。")
		assert_true(custom_boards[0].custom_board_id == custom_board.custom_board_id, "玩家棋盘稳定 ID 应跨重载保留。")
		assert_true(replays[0].replay_id == replay.replay_id, "回放稳定 ID 应跨重载保留。")
		assert_true(bookmarks[0].score == 512, "书签业务数据应完整恢复。")
		assert_true(custom_boards[0].display_name == "Cross Five", "玩家棋盘业务数据应完整恢复。")
		assert_true(replays[0].final_score == 2048, "回放业务数据应完整恢复。")

		var delete_bookmark_result: GameSaveSectionResult = await _await_section_operation(
			reloaded_bookmarks.request_delete_bookmark(bookmarks[0].bookmark_id),
			reloaded
		)
		var delete_custom_board_result: GameSaveSectionResult = (
			await _await_section_operation(
				reloaded_custom_boards.request_delete_custom_board(
					custom_boards[0].custom_board_id
				),
				reloaded
			)
		)
		var delete_replay_result: GameSaveSectionResult = await _await_section_operation(
			reloaded_replays.request_delete_replay(replays[0].replay_id),
			reloaded
		)
		assert_true(
			delete_bookmark_result != null
			and delete_bookmark_result.is_successful(),
			"应按稳定 ID 删除书签。"
		)
		assert_true(
			delete_custom_board_result != null
			and delete_custom_board_result.is_successful(),
			"应按稳定 ID 删除玩家棋盘。"
		)
		assert_true(
			delete_replay_result != null
			and delete_replay_result.is_successful(),
			"应按稳定 ID 删除回放。"
		)
		assert_true(reloaded_bookmarks.load_bookmarks().is_empty(), "书签删除应更新统一图。")
		assert_true(reloaded_custom_boards.load_custom_boards().is_empty(), "玩家棋盘删除应更新统一图。")
		assert_true(reloaded_replays.load_replays().is_empty(), "回放删除应更新统一图。")

	_dispose_setup(reloaded)










func test_unreadable_storage_profile_is_reset_to_current_format() -> void:
	var save_dir_name: String = "gut_save_graph_unreadable_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var legacy_bytes: PackedByteArray = _make_legacy_storage_bytes({
		"legacy_profile": true,
	})
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		legacy_bytes
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var load_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		"last_load"
	)

	assert_true(
		save_graph.is_profile_loaded(),
		"无法按当前 codec 解码的 Profile 应按项目 reset_allowed 策略重建。"
	)
	assert_true(
		GFVariantData.get_option_bool(
			load_snapshot,
			"recovered_unreadable_profile",
			false
		),
		"加载诊断应明确记录物理存储格式重建。"
	)
	assert_true(
		progress_stats_system.set_high_score("classic", _BOARD_KEY, 1024) == OK,
		"重建后业务 section 必须可以立即排队写入。"
	)
	var flush_result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_flush_profile({
			&"reason": "test_unreadable_profile_rebuild",
		}),
		setup
	)
	assert_true(
		flush_result != null and flush_result.is_successful(),
		"重建后的 Profile 应可完成 typed 冲刷。"
	)
	var persisted_result: GFStorageReadResult = storage.load_data(
		save_graph.get_profile_file_name()
	)
	assert_true(persisted_result.ok, "活动 Profile 必须已改写为当前 GFStorage 文档格式。")

	_dispose_setup(setup)






func test_bookmark_schema_rejects_removed_transient_status_field() -> void:
	var bookmark: BookmarkData = _make_bookmark(900, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(900000)
	var current_payload: Dictionary = bookmark.to_dict()

	assert_false(current_payload.has("status_message"), "瞬时 HUD 通知不得进入书签持久化 schema。")
	assert_true(
		BookmarkData.is_persisted_envelope_lightweight_valid(
			current_payload
		),
		"当前严格书签信封必须通过轻量持久化边界校验。"
	)
	assert_true(BookmarkData.from_dict(current_payload) != null, "当前严格书签 schema 应可反序列化。")

	var removed_schema_payload: Dictionary = current_payload.duplicate(true)
	removed_schema_payload["status_message"] = "legacy transient message"
	assert_false(
		BookmarkData.is_persisted_envelope_lightweight_valid(
			removed_schema_payload
		),
		"轻量信封校验也必须拒绝已移除的未知字段。"
	)
	assert_true(
		BookmarkData.from_dict(removed_schema_payload) == null,
		"已移除字段不得通过兼容分支继续进入当前书签模型。"
	)


func test_bookmark_schema_round_trips_binary_command_history_envelope() -> void:
	var bookmark: BookmarkData = _make_bookmark(899, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(899000)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 14)

	var payload: Dictionary = bookmark.to_dict()
	var history_envelope: Dictionary = GFVariantData.get_option_dictionary(
		payload,
		"game_state_history"
	)
	var restored: BookmarkData = BookmarkData.from_dict(payload)

	assert_true(
		GFVariantData.get_option_value(history_envelope, "payload")
		is PackedByteArray,
		"持久化历史必须压平为有界二进制信封，避免 GF Profile gather 递归复制完整撤回图。"
	)
	assert_not_null(restored, "二进制命令历史必须通过严格 schema 往返恢复。")
	if restored != null:
		assert_true(
			restored.game_state_history == bookmark.game_state_history,
			"二进制信封不得改变完整 undo/redo 语义。"
		)

	var corrupt_payload: Dictionary = payload.duplicate(true)
	var corrupt_envelope: Dictionary = history_envelope.duplicate(true)
	corrupt_envelope["payload"] = PackedByteArray([0xFF, 0x00, 0x7F])
	corrupt_payload["game_state_history"] = corrupt_envelope
	var corrupt_restored: BookmarkData = BookmarkData.from_dict(
		corrupt_payload
	)
	assert_engine_error(
		"Condition \"len < 4\" is true",
		"GFStorageCodec 应报告截断的二进制 Variant。"
	)
	assert_null(
		corrupt_restored,
		"损坏的历史信封必须被严格拒绝，不能降级为空历史。"
	)


func test_new_bookmark_history_keeps_recent_stack_tail_only() -> void:
	var bookmark: BookmarkData = _make_bookmark(898, 512)
	bookmark.bookmark_id = GFUuid.generate_v7(898000)
	var source_history: Dictionary = _make_bookmark_history(bookmark, 70)
	source_history["redo"] = GFVariantData.get_option_array(
		source_history,
		"undo"
	).duplicate(true)
	bookmark.game_state_history = source_history

	var bounded: BookmarkData = BookmarkData.from_dict(
		bookmark.to_persisted_candidate_envelope()
	)

	assert_not_null(bounded, "新书签的有界命令历史必须继续通过严格解码。")
	if bounded == null:
		return
	for stack_key: String in ["undo", "redo"]:
		var stack: Array = GFVariantData.get_option_array(
			bounded.game_state_history,
			stack_key
		)
		assert_true(
			stack.size() == BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT >> 1,
			"双栈非空时新书签必须为每个栈保留最近 32 条。"
		)
		assert_true(
			GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					GFVariantData.as_dictionary(stack[0]),
					"snapshot"
				),
				"move_count"
			) == 38
			and GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					GFVariantData.as_dictionary(stack[-1]),
					"snapshot"
				),
				"move_count"
			) == 69,
			"截断必须丢弃栈头最旧命令，并保持最近命令的原始顺序。"
		)

	bookmark.game_state_history = _make_bookmark_history(bookmark, 70)
	var single_stack: BookmarkData = BookmarkData.from_dict(
		bookmark.to_persisted_candidate_envelope()
	)
	assert_not_null(single_stack)
	if single_stack != null:
		var retained_undo: Array = GFVariantData.get_option_array(
			single_stack.game_state_history,
			"undo"
		)
		assert_true(
			retained_undo.size() == BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT
			and GFVariantData.get_option_array(
				single_stack.game_state_history,
				"redo"
			).is_empty()
			and GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					GFVariantData.as_dictionary(retained_undo[0]),
					"snapshot"
				),
				"move_count"
			) == 6,
			"另一栈为空时必须把全部 64 条容量用于当前栈，并继续保留最近尾部。"
		)


func test_new_bookmark_candidate_rejects_malformed_history_root() -> void:
	var malformed_histories: Array[Dictionary] = [
		{},
		{"undo": []},
		{"undo": {}, "redo": []},
		{"undo": [], "redo": {}, "unexpected": []},
	]
	for history_index: int in range(malformed_histories.size()):
		var bookmark: BookmarkData = _make_bookmark(898, 512)
		bookmark.bookmark_id = GFUuid.generate_v7(
			898100 + history_index
		)
		bookmark.game_state_history = malformed_histories[history_index]
		var candidate: Dictionary = (
			bookmark.to_persisted_candidate_envelope()
		)

		assert_false(
			BookmarkData.is_persisted_envelope_lightweight_valid(
				candidate
			),
			"有界候选路径不得把畸形历史根结构静默归一为空历史。"
		)
		assert_null(
			BookmarkData.from_dict(candidate),
			"畸形历史根结构不得进入严格书签 provider。"
		)


func test_existing_large_bookmark_history_remains_readable_without_truncation() -> void:
	var bookmark: BookmarkData = _make_bookmark(897, 1024)
	bookmark.bookmark_id = GFUuid.generate_v7(897000)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 70)

	# to_dict() 模拟升级前已经落盘的当前 schema；只有新建候选入口施加产品上限。
	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_not_null(restored, "旧的大型书签历史必须继续可读。")
	if restored != null:
		assert_true(
			GFVariantData.get_option_array(
				restored.game_state_history,
				"undo"
			).size() == 70,
			"读取旧书签不得静默截断已经持久化的命令历史。"
		)


func test_bookmark_catalog_initial_load_rejects_corrupt_history() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var bookmark: BookmarkData = _make_bookmark(896, 512)
	bookmark.bookmark_id = GFUuid.generate_v7(896000)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 3)
	var corrupt_envelope: Dictionary = bookmark.to_dict()
	var corrupt_history: Dictionary = (
		GFVariantData.get_option_dictionary(
			corrupt_envelope,
			"game_state_history"
		).duplicate(true)
	)
	var codec: GFStorageCodec = GFStorageCodec.new()
	corrupt_history["payload"] = codec.serialize_dictionary(
		{
			"undo": [{"invalid_command": true}],
			"redo": [],
		},
		GFStorageCodec.Format.BINARY
	)
	corrupt_envelope["game_state_history"] = corrupt_history

	var replace_error: Error = provider.replace_section_data({
		"items": [corrupt_envelope],
	})

	assert_true(
		replace_error == ERR_INVALID_DATA,
		"轻量 envelope 校验不得旁路 provider 对新 payload 的完整解码。"
	)
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			"items"
		).is_empty(),
		"首次加载损坏书签后 provider 必须保持默认空状态。"
	)


func test_bookmark_catalog_unchanged_envelope_reuses_validated_payload() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var bookmark: BookmarkData = _make_bookmark(897, 16384)
	bookmark.bookmark_id = GFUuid.generate_v7(897000)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 512)
	var section_data: Dictionary = {
		"items": [bookmark.to_dict()],
	}

	var first_started_usec: int = Time.get_ticks_usec()
	var first_error: Error = provider.replace_section_data(section_data)
	var first_replace_usec: int = (
		Time.get_ticks_usec() - first_started_usec
	)
	var second_started_usec: int = Time.get_ticks_usec()
	var second_error: Error = provider.replace_section_data(section_data)
	var unchanged_replace_usec: int = (
		Time.get_ticks_usec() - second_started_usec
	)
	var gather_started_usec: int = Time.get_ticks_usec()
	var gathered: Dictionary = provider.get_section_data()
	var gather_usec: int = Time.get_ticks_usec() - gather_started_usec

	assert_true(
		first_error == OK,
		"首次 provider 替换必须完整校验并成功应用大型历史。"
	)
	assert_true(
		second_error == OK,
		"相同已验证 envelope 的重复替换必须成功。"
	)
	assert_true(
		gathered == section_data,
		"provider gather 必须逐字保留规范持久化 envelope。"
	)
	assert_lt(
		unchanged_replace_usec,
		first_replace_usec,
		"完全相同的已验证 envelope 不得再次完整解码大历史。"
	)
	assert_lt(
		unchanged_replace_usec,
		50_000,
		"已验证大历史的事务替换必须稳定低于 50ms。"
	)
	assert_lt(
		gather_usec,
		50_000,
		"provider gather 必须直接复制持久化 envelope，不能重新编码大历史。"
	)
	gut.p(
		(
			"bookmark_provider_benchmark first_replace_usec=%d "
			+ "unchanged_replace_usec=%d gather_usec=%d"
		) % [
			first_replace_usec,
			unchanged_replace_usec,
			gather_usec,
		],
		1
	)


func test_bookmark_catalog_failed_change_rolls_back_to_previous_envelopes() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var existing: BookmarkData = _make_bookmark(896, 1024)
	existing.bookmark_id = GFUuid.generate_v7(896000)
	existing.game_state_history = _make_bookmark_history(existing, 3)
	var original_section: Dictionary = {
		"items": [existing.to_dict()],
	}
	assert_true(
		provider.replace_section_data(original_section) == OK,
		"回滚回归样本的初始 envelope 必须先成功应用。"
	)

	var corrupt_new: BookmarkData = _make_bookmark(895, 2048)
	corrupt_new.bookmark_id = GFUuid.generate_v7(895000)
	var corrupt_envelope: Dictionary = corrupt_new.to_dict()
	var corrupt_history: Dictionary = (
		GFVariantData.get_option_dictionary(
			corrupt_envelope,
			"game_state_history"
		).duplicate(true)
	)
	var codec: GFStorageCodec = GFStorageCodec.new()
	corrupt_history["payload"] = codec.serialize_dictionary(
		{
			"undo": [{"invalid_command": true}],
			"redo": [],
		},
		GFStorageCodec.Format.BINARY
	)
	corrupt_envelope["game_state_history"] = corrupt_history
	var failed_error: Error = provider.replace_section_data({
		"items": [
			GFVariantData.get_option_array(
				original_section,
				"items"
			)[0],
			corrupt_envelope,
		],
	})

	assert_true(
		failed_error == ERR_INVALID_DATA,
		"变化项的非法命令历史必须被完整校验拒绝。"
	)
	assert_true(
		provider.get_section_data() == original_section,
		"候选变化校验失败后必须完整保留上一份已验证 envelope 集合。"
	)


func test_bookmark_schema_migrates_v5_dictionary_history_without_profile_reset() -> void:
	var bookmark: BookmarkData = _make_bookmark(900, 384)
	bookmark.bookmark_id = GFUuid.generate_v7(900000)
	bookmark.game_state_history = _make_bookmark_history(bookmark, 6)
	var current_payload: Dictionary = bookmark.to_dict()
	var legacy_payload: Dictionary = current_payload.duplicate(true)
	legacy_payload["schema_version"] = 5
	legacy_payload["game_state_history"] = bookmark.game_state_history.duplicate(
		true
	)

	var restored: BookmarkData = BookmarkData.from_dict(legacy_payload)
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var provider_replace_error: Error = provider.replace_section_data({
		"items": [legacy_payload],
	})

	assert_not_null(
		restored,
		"v5 字典历史应在 bookmarks section 内就地读取，不能迫使整个玩家 Profile 重置。"
	)
	if restored != null:
		assert_true(
			restored.schema_version == BookmarkData.SCHEMA_VERSION,
			"载入旧条目后内存对象应立即升级到当前 schema。"
		)
		assert_true(
			restored.game_state_history == bookmark.game_state_history,
			"v5 迁移不得损失撤回或重做历史。"
		)
		var upgraded_payload: Dictionary = restored.to_dict()
		assert_true(
			GFVariantData.get_option_value(
				GFVariantData.get_option_dictionary(
					upgraded_payload,
					"game_state_history"
				),
				"payload"
			) is PackedByteArray,
			"旧条目下次保存时应原子升级为二进制历史信封。"
		)
	assert_true(
		provider_replace_error == OK,
		"provider 初载必须接受可迁移的 v5 书签。"
	)
	var provider_items: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		"items"
	)
	assert_true(
		provider_items.size() == 1
		and GFVariantData.get_option_int(
			GFVariantData.as_dictionary(provider_items[0]),
			"schema_version"
		) == BookmarkData.SCHEMA_VERSION,
		"provider 应把 v5 envelope 在内存中规范化，供下一次持久化升级。"
	)


func test_bookmark_schema_rejects_inconsistent_target_state() -> void:
	var bookmark: BookmarkData = _make_bookmark(901, 512)
	bookmark.bookmark_id = GFUuid.generate_v7(901000)
	bookmark.highest_tile = 4096
	bookmark.target_tile_value = 2048
	bookmark.target_reached = false

	assert_true(
		BookmarkData.from_dict(bookmark.to_dict()) == null,
		"最高方块已达到目标时，当前 schema 不得接受 target_reached=false。"
	)


func test_bookmark_schema_preserves_historical_target_achievement() -> void:
	var bookmark: BookmarkData = _make_bookmark(902, 1024)
	bookmark.bookmark_id = GFUuid.generate_v7(902000)
	bookmark.highest_tile = 1024
	bookmark.target_tile_value = 2048
	bookmark.target_reached = true
	bookmark.board_snapshot[&"tiles"] = [
		_make_classic_tile_snapshot(Vector2i.ZERO, 1024, 902001),
	]

	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "曾达成目标后当前最高方块降低的书签仍应有效。")
	if restored != null:
		assert_true(restored.target_reached, "显式目标达成状态必须原样恢复。")


func test_bookmark_schema_preserves_strict_replay_trace_prefix() -> void:
	var bookmark: BookmarkData = _make_bookmark(903, 64)
	bookmark.bookmark_id = GFUuid.generate_v7(903000)
	bookmark.replay_actions = [Vector2i.RIGHT, Vector2i.DOWN]
	bookmark.replay_checkpoints = [
		_make_replay_checkpoint(1, 16),
		_make_replay_checkpoint(2, 64),
	]

	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "书签必须接受与操作一一对应的严格回放前缀。")
	if restored != null:
		assert_true(restored.replay_actions == bookmark.replay_actions, "操作前缀必须原样恢复。")
		assert_true(restored.replay_checkpoints.size() == 2, "每个操作必须恢复一个 checkpoint。")
		var last_checkpoint: ReplayCheckpoint = restored.replay_checkpoints.back()
		assert_true(last_checkpoint.score == 64, "末尾 checkpoint 必须对应书签分数。")

	var incomplete_payload: Dictionary = bookmark.to_dict()
	var incomplete_checkpoints: Array = GFVariantData.get_option_array(
		incomplete_payload,
		"replay_checkpoints"
	)
	incomplete_checkpoints.pop_back()
	incomplete_payload["replay_checkpoints"] = incomplete_checkpoints
	assert_true(
		BookmarkData.from_dict(incomplete_payload) == null,
		"actions/checkpoints 数量不一致的书签必须被当前严格 schema 拒绝。"
	)


func test_bookmark_schema_requires_strict_ruleset_identity() -> void:
	var bookmark: BookmarkData = _make_bookmark(904, 128)
	bookmark.bookmark_id = GFUuid.generate_v7(904000)
	var restored: BookmarkData = BookmarkData.from_dict(bookmark.to_dict())

	assert_true(restored != null, "完整规则集身份应通过书签 schema。")
	if restored != null:
		assert_true(restored.ruleset_id == bookmark.ruleset_id, "ruleset_id 必须原样恢复。")
		assert_true(
			restored.ruleset_fingerprint == bookmark.ruleset_fingerprint,
			"规则集内容指纹必须原样恢复。"
		)

	var invalid_fingerprint_payload: Dictionary = bookmark.to_dict()
	invalid_fingerprint_payload["ruleset_fingerprint"] = "not-a-current-fingerprint"
	assert_true(
		BookmarkData.from_dict(invalid_fingerprint_payload) == null,
		"书签必须拒绝缺失严格 64 位十六进制内容指纹的规则集身份。"
	)


func test_bookmark_and_replay_preserve_generic_session_metadata() -> void:
	var bookmark: BookmarkData = _make_bookmark(905, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(905000)
	var manual_metadata: GameSessionMetadata = GameSessionMetadata.create(
		GameSessionMetadata.SEED_SOURCE_MANUAL,
		GameCompetitionEligibility.create([
			GameCompetitionEligibility.REASON_MANUAL_SEED,
		])
	)
	assert_not_null(manual_metadata)
	bookmark.session_metadata = manual_metadata.to_dict()

	var restored_bookmark: BookmarkData = BookmarkData.from_dict(
		bookmark.to_dict()
	)
	assert_not_null(restored_bookmark, "书签必须往返保存手动 seed 与资格。")
	if restored_bookmark != null:
		var bookmark_metadata: GameSessionMetadata = (
			restored_bookmark.get_session_metadata()
		)
		assert_not_null(bookmark_metadata)
		assert_true(
			bookmark_metadata.get_seed_source()
			== GameSessionMetadata.SEED_SOURCE_MANUAL
		)
		assert_true(
			bookmark_metadata.get_eligibility().has_reason(
				GameCompetitionEligibility.REASON_MANUAL_SEED
			)
		)

	var replay: ReplayData = _make_replay(906, 512)
	replay.replay_id = GFUuid.generate_v7(906000)
	replay.session_metadata = GameSessionMetadata.make_default_dict()

	var restored_replay: ReplayData = ReplayData.from_dict(replay.to_dict())
	assert_not_null(restored_replay, "回放必须往返保存随机 seed 与资格。")
	if restored_replay != null:
		var replay_metadata: GameSessionMetadata = restored_replay.get_session_metadata()
		assert_not_null(replay_metadata)
		assert_true(
			replay_metadata.get_seed_source()
			== GameSessionMetadata.SEED_SOURCE_RANDOM
		)
		assert_true(replay_metadata.get_eligibility().is_eligible())


func test_bookmark_and_replay_reject_removed_nested_contracts() -> void:
	var bookmark: BookmarkData = _make_bookmark(907, 256)
	bookmark.bookmark_id = GFUuid.generate_v7(907000)
	var legacy_bookmark: Dictionary = bookmark.to_dict()
	legacy_bookmark["schema_version"] = 3
	assert_null(BookmarkData.from_dict(legacy_bookmark))
	var bookmark_with_challenge: Dictionary = bookmark.to_dict()
	var bookmark_session: Dictionary = GFVariantData.get_option_dictionary(
		bookmark_with_challenge,
		"session_metadata"
	)
	bookmark_session["challenge"] = {}
	bookmark_with_challenge["session_metadata"] = bookmark_session
	assert_null(BookmarkData.from_dict(bookmark_with_challenge))

	var replay: ReplayData = _make_replay(907, 512)
	replay.replay_id = GFUuid.generate_v7(907001)
	var legacy_replay: Dictionary = replay.to_dict()
	legacy_replay["schema_version"] = 3
	assert_null(ReplayData.from_dict(legacy_replay))
	var replay_with_challenge: Dictionary = replay.to_dict()
	var replay_session: Dictionary = GFVariantData.get_option_dictionary(
		replay_with_challenge,
		"session_metadata"
	)
	replay_session["challenge"] = {}
	replay_with_challenge["session_metadata"] = replay_session
	assert_null(ReplayData.from_dict(replay_with_challenge))


func test_replay_schema_rejects_final_snapshot_with_different_topology() -> void:
	var replay: ReplayData = _make_replay(903, 2048)
	replay.replay_id = GFUuid.generate_v7(903000)
	replay.final_board_snapshot = _make_empty_board_snapshot(
		BoardTopology.create_rectangle(Vector2i(3, 3))
	)

	assert_true(
		ReplayData.from_dict(replay.to_dict()) == null,
		"方向操作序列无法表达拓扑变化，回放最终快照必须保持初始拓扑。"
	)


func test_replay_schema_rejects_non_cardinal_action() -> void:
	var replay: ReplayData = _make_replay(904, 2048)
	replay.replay_id = GFUuid.generate_v7(904000)
	replay.actions = [Vector2i.ZERO]

	assert_true(
		ReplayData.from_dict(replay.to_dict()) == null,
		"严格回放不得接受零向量或斜向动作。"
	)



# --- 私有/辅助方法 ---

func _await_section_operation(
	operation: GameSaveSectionOperation,
	setup: Dictionary
) -> GameSaveSectionResult:
	if operation == null:
		return null
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	for _frame: int in range(300):
		if operation.is_completed():
			break
		storage.wait_for_async_tasks()
		architecture.tick(0.0)
		await get_tree().process_frame
	return operation.get_result()


func _await_profile_operation(
	operation: GFSaveProfileOperation,
	setup: Dictionary
) -> GFSaveProfileResult:
	if operation == null:
		return null
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	for _frame: int in range(300):
		if operation.is_completed():
			break
		architecture.tick(0.0)
		storage.wait_for_async_tasks()
		architecture.tick(0.0)
		await get_tree().process_frame
	return operation.get_result()


func _advance_section_operation_to_outcome_unknown(
	operation: GameSaveSectionOperation,
	setup: Dictionary,
	storage: _HangingProfileStorage,
	clock: GFManualClock
) -> void:
	await _await_hanging_profile_write(storage, setup)
	await _advance_profile_deadlines(setup, clock)
	for _frame: int in range(120):
		if operation != null and operation.is_completed():
			break
		_get_architecture(setup).tick(0.0)
		await get_tree().process_frame
	assert_true(
		operation != null and operation.is_completed(),
		"section deadline 必须产生 typed outcome_unknown 终态。"
	)


func _advance_profile_deadlines(
	setup: Dictionary,
	clock: GFManualClock
) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	for delta_msec: int in [5_000, 100, 5_000, 500, 5_000, 1_500, 5_000]:
		assert_true(clock.advance_msec(delta_msec))
		architecture.tick(0.0)
		await get_tree().process_frame


func _await_hanging_profile_write(
	storage: _HangingProfileStorage,
	setup: Dictionary
) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	for _frame: int in range(120):
		architecture.tick(0.0)
		await get_tree().process_frame
		if not storage.hanging_operations.is_empty():
			break
	assert_false(
		storage.hanging_operations.is_empty(),
		"故障注入 Profile 写必须先进入 hanging 状态。"
	)


func _await_section_reconciliation(
	save_graph: GameSaveGraphUtility,
	setup: Dictionary
) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	for _frame: int in range(600):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
		if not save_graph.is_section_reconciliation_pending():
			break
	assert_false(
		save_graph.is_section_reconciliation_pending(),
		"section late settlement 必须在测试窗口内解除 reconciliation 锁。"
	)


func _create_persistence_architecture(
	save_dir_name: String = "",
	include_systems: bool = false,
	raw_profile_bytes: PackedByteArray = PackedByteArray(),
	storage_override: GFStorageUtility = null,
	clock_override: GFManualClock = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	var save_graph: GameSaveGraphUtility = _make_game_save_graph()
	var platform: GamePlatformUtility = _TEST_PLATFORM_STUB_SCRIPT.new()
	var account_catalog: LocalAccountCatalogUtility = (
		LocalAccountCatalogUtility.new()
	)
	var progress_stats_system: ProgressStatsSystem = null
	var bookmark_system: BookmarkSystem = null
	var custom_board_system: CustomBoardSystem = null
	var replay_system: ReplaySystem = null
	var shared_clock: GFManualClock = (
		clock_override
		if clock_override != null
		else GFManualClock.new(0, 1_000_000)
	)
	var time_utility: GFTimeUtility = GFTimeUtility.new()
	assert_true(time_utility.set_clock(shared_clock))
	var game_clock: GameClockUtility = GameClockUtility.new()
	assert_true(game_clock.set_clock(shared_clock))

	storage.save_dir_name = (
		save_dir_name
		if not save_dir_name.is_empty()
		else "gut_save_graph_%s" % GFUuid.generate_v4().replace("-", "")
	)
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	if not raw_profile_bytes.is_empty():
		var fixture_error: Error = _write_raw_storage_file(
			storage,
			GameSaveGraphUtility.PROFILE_FILE_NAME,
			raw_profile_bytes
		)
		assert_true(fixture_error == OK, "无法写入不可读 Profile 回归夹具。")

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GFTimeUtility, time_utility)
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(
		GFSaveProfileUtility,
		GFSaveProfileUtility.new()
	)
	await architecture.register_utility(
		GFBackgroundWorkUtility,
		GFBackgroundWorkUtility.new()
	)
	await architecture.register_utility(GamePlatformUtility, platform)
	await architecture.register_utility(GameClockUtility, game_clock)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(
		LocalAccountCatalogUtility,
		account_catalog
	)
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GFCommandHistoryUtility, GFCommandHistoryUtility.new())
	if include_systems:
		progress_stats_system = ProgressStatsSystem.new()
		bookmark_system = BookmarkSystem.new()
		custom_board_system = CustomBoardSystem.new()
		replay_system = ReplaySystem.new()
		await architecture.register_system(ProgressStatsSystem, progress_stats_system)
		await architecture.register_system(BookmarkSystem, bookmark_system)
		await architecture.register_system(CustomBoardSystem, custom_board_system)
		await architecture.register_system(ReplaySystem, replay_system)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "SaveGraph 测试夹具必须完成 GF 架构初始化。")
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
		"SaveGraph 测试夹具必须显式完成账号 Profile 引导。"
	)

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"platform": platform,
		"clock": shared_clock,
		"account_catalog": account_catalog,
		"profile_file_name": GFVariantData.get_option_string(
			bootstrap,
			&"profile_file_name"
		),
		"progress_stats_system": progress_stats_system,
		"bookmark_system": bookmark_system,
		"custom_board_system": custom_board_system,
		"replay_system": replay_system,
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


func _write_raw_storage_file(
	storage: GFStorageUtility,
	file_name: String,
	bytes: PackedByteArray
) -> Error:
	var directory_error: Error = storage.ensure_directory()
	if directory_error != OK:
		return directory_error
	var path: String = storage.get_storage_directory_path().path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var _store_result: Variant = file.store_buffer(bytes)
	file.close()
	return OK


func _make_legacy_storage_bytes(data: Dictionary, obfuscation_key: int = 42) -> PackedByteArray:
	var bytes: PackedByteArray = var_to_bytes(data)
	var key_byte: int = obfuscation_key & 0xff
	for index: int in range(bytes.size()):
		bytes[index] = bytes[index] ^ key_byte
	return Marshalls.raw_to_base64(bytes).to_utf8_buffer()


func _make_empty_progress_data() -> Dictionary:
	return {
		"stats": {},
		"results": [],
		"leaderboards": {},
	}


func _make_game_result(
	score: int,
	steps: int,
	max_tile: int,
	played_at: int,
	target_value: int = 0,
	target_reached: bool = false
) -> GameResultRecordedData:
	var result: GameResultRecordedData = GameResultRecordedData.create(
		&"classic",
		_BOARD_KEY,
		&"gameplay.classic",
		1,
		"a".repeat(64),
		2048,
		("%d|%d|%d|%d" % [score, steps, max_tile, played_at]).sha256_text(),
		GameCompetitionEligibility.create(),
		score,
		steps,
		max_tile,
		played_at,
		target_value,
		target_reached
	)
	assert_not_null(result, "SaveGraph 结果 fixture 必须满足严格契约。")
	return result


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	var mode_resource: Resource = load(bookmark.mode_config_path)
	if mode_resource is GameModeConfig:
		var mode_config: GameModeConfig = mode_resource
		bookmark.ruleset_id = mode_config.ruleset_id
		bookmark.ruleset_version = mode_config.ruleset_version
		bookmark.ruleset_fingerprint = GameDeterminismUtility.new().calculate_ruleset_fingerprint(
			mode_config
		)
		bookmark.rules_states = RuleSystem.capture_rule_states(mode_config.spawn_rules)
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	bookmark.initial_seed = 2048
	bookmark.rng_full_state = seed_utility.get_full_state()
	bookmark.score = score
	bookmark.board_snapshot = _make_empty_board_snapshot()
	bookmark.game_state_history = {
		"undo": [],
		"redo": [],
	}
	return bookmark


func _make_bookmark_history(
	bookmark: BookmarkData,
	count: int
) -> Dictionary:
	var topology: BoardTopology = BoardTopology.create_rectangle(_BOARD_SIZE)
	var state: Dictionary = {
		&"schema_version": GameStateSystem.STATE_SCHEMA_VERSION,
		&"board_key": topology.get_stable_key(),
		&"board_snapshot": bookmark.board_snapshot.duplicate(true),
		&"rng_full_state": bookmark.rng_full_state.duplicate(true),
		&"score": bookmark.score,
		&"move_count": 0,
		&"highest_tile": 0,
		&"ratio_resolutions": 0,
		&"target_tile_value": bookmark.target_tile_value,
		&"target_reached": false,
		&"extra_stats": {},
		&"rules_states": bookmark.rules_states.duplicate(true),
	}
	var undo: Array[Dictionary] = []
	for index: int in range(maxi(count, 0)):
		var command_state: Dictionary = state.duplicate(true)
		command_state[&"move_count"] = index
		undo.append({
			&"schema_version": MoveCommand.SERIALIZATION_SCHEMA_VERSION,
			&"direction_x": 1,
			&"direction_y": 0,
			&"snapshot": command_state,
			&"reverse_map": {},
			&"is_baseline": false,
		})
	return {
		"undo": undo,
		"redo": [],
	}


func _make_replay(timestamp: int, final_score: int) -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	var topology: BoardTopology = BoardTopology.create_rectangle(_BOARD_SIZE)
	replay.timestamp = timestamp
	replay.mode_config_path = "res://features/gameplay/resources/modes/classic_mode_config.tres"
	replay.ruleset_id = &"gameplay.classic"
	replay.ruleset_version = 1
	replay.ruleset_fingerprint = "a".repeat(64)
	replay.initial_seed = 2048
	replay.initial_board_topology = topology.to_dict()
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	replay.checkpoints = [_make_replay_checkpoint(1, final_score)]
	replay.final_board_snapshot = _make_empty_board_snapshot(topology)
	return replay


func _make_replay_checkpoint(step_index: int, score: int) -> ReplayCheckpoint:
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.new()
	checkpoint.step_index = step_index
	checkpoint.state_checksum = "b".repeat(64)
	checkpoint.board_checksum = "c".repeat(64)
	checkpoint.rng_checksum = "d".repeat(64)
	checkpoint.score = score
	return checkpoint


func _make_custom_board() -> CustomBoardData:
	var custom_board: CustomBoardData = CustomBoardData.new()
	custom_board.display_name = "Cross Five"
	custom_board.topology = BoardTopology.create_cross(2)
	return custom_board


func _make_empty_board_snapshot(topology: BoardTopology = null) -> Dictionary:
	var resolved_topology: BoardTopology = topology
	if resolved_topology == null:
		resolved_topology = BoardTopology.create_rectangle(_BOARD_SIZE)
	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": resolved_topology.to_dict(),
		&"tiles": [],
	}


func _make_classic_tile_snapshot(
	position: Vector2i,
	value: int,
	timestamp_msec: int
) -> Dictionary:
	return {
		&"schema_version": TileState.SERIALIZATION_SCHEMA_VERSION,
		&"tile_id": GFUuid.generate_v7(timestamp_msec),
		&"definition_id": &"tile.classic.numeric",
		&"value": value,
		&"capability_recipe_ids": [&"tile.recipe.classic_merge"],
		&"capability_state": {},
		&"pos": position,
	}






func _describe_load_failure(save_graph: GameSaveGraphUtility) -> String:
	var snapshot: Dictionary = save_graph.get_debug_snapshot()
	var load_result: Dictionary = GFVariantData.get_option_dictionary(snapshot, "last_load")
	return JSON.stringify({
		"error_code": GFVariantData.get_option_int(load_result, "error_code", FAILED),
		"error": GFVariantData.get_option_string(load_result, "error"),
		"errors": GFVariantData.get_option_array(load_result, "errors"),
	})


func _dispose_setup(setup: Dictionary, delete_profile: bool = true) -> void:
	var storage: GFStorageUtility = _get_storage(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	if delete_profile:
		var profile_file_name: String = save_graph.get_profile_file_name()
		if profile_file_name.is_empty():
			profile_file_name = GameSaveGraphUtility.PROFILE_FILE_NAME
		var delete_error: Error = storage.delete_file(profile_file_name)
		assert_true(delete_error == OK or delete_error == ERR_FILE_NOT_FOUND, "测试玩家数据清理应返回可预期结果。")
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


func _get_platform_stub(setup: Dictionary) -> GamePlatformUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "platform")
	if value is GamePlatformUtility:
		var platform: GamePlatformUtility = value
		return platform
	assert_true(false, "测试 setup 缺少 TestGamePlatformUtilityStub。")
	return _TEST_PLATFORM_STUB_SCRIPT.new()


func _get_progress_stats_system(setup: Dictionary) -> ProgressStatsSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "progress_stats_system")
	if value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = value
		return progress_stats_system
	assert_true(false, "测试 setup 缺少 ProgressStatsSystem。")
	return ProgressStatsSystem.new()


func _get_bookmark_system(setup: Dictionary) -> BookmarkSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "bookmark_system")
	if value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = value
		return bookmark_system
	assert_true(false, "测试 setup 缺少 BookmarkSystem。")
	return BookmarkSystem.new()


func _get_replay_system(setup: Dictionary) -> ReplaySystem:
	var value: Variant = GFVariantData.get_option_value(setup, "replay_system")
	if value is ReplaySystem:
		var replay_system: ReplaySystem = value
		return replay_system
	assert_true(false, "测试 setup 缺少 ReplaySystem。")
	return ReplaySystem.new()


func _get_custom_board_system(setup: Dictionary) -> CustomBoardSystem:
	var value: Variant = GFVariantData.get_option_value(setup, "custom_board_system")
	if value is CustomBoardSystem:
		var custom_board_system: CustomBoardSystem = value
		return custom_board_system
	assert_true(false, "测试 setup 缺少 CustomBoardSystem。")
	return CustomBoardSystem.new()


# --- 内部类 ---

class _RetryStorage extends GFStorageUtility:
	var profile_save_errors: Array[Error] = []
	var profile_save_attempt_count: int = 0
	var _next_request_id: int = 2_000_000


	## 按队列为 Profile opaque payload 写入注入可重试错误。
	## @param file_name: GFStorage 相对文件名。
	## @param transfer: 此 generation 的单所有者 payload transfer。
	func save_payload_request_async(
		file_name: String,
		transfer: GFStoragePayloadTransfer
	) -> GFStorageAsyncOperation:
		if (
			file_name == GameSaveGraphUtility.PROFILE_FILE_NAME
			or file_name.get_base_dir()
			== LocalAccountCatalogUtility.PROFILE_DIRECTORY
		):
			profile_save_attempt_count += 1
			if not profile_save_errors.is_empty():
				var scripted_error: Error = profile_save_errors.pop_front()
				if scripted_error != OK:
					var operation: GFStorageAsyncOperation = (
						GFStorageAsyncOperation.new()
					)
					var request_id: int = _next_request_id
					_next_request_id += 1
					var _operation_configured: bool = (
						operation.configure_for_framework(
							request_id,
							GFStorageAsyncOperation.OPERATION_SAVE,
							file_name
						)
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
					var attempt_error: Error = scripted_error
					if GFVariantData.get_option_bool(attempt, "ok"):
						var _attempt_configured: bool = (
							operation.configure_payload_attempt_for_framework(
								transfer,
								GFVariantData.get_option_int(
									attempt,
									"attempt_id"
								)
							)
						)
						var _attempt_finished: bool = (
							operation.finish_payload_attempt_for_framework()
						)
					else:
						attempt_error = ERR_INVALID_PARAMETER
					var result: GFStorageAsyncResult = (
						GFStorageAsyncResult.new()
					)
					var _result_configured: bool = (
						result.configure_for_framework(
							request_id,
							GFStorageAsyncOperation.OPERATION_SAVE,
							file_name,
							false,
							attempt_error,
							null,
							GFStorageAsyncResult.WriteFailureKind.IO_FAILED
						)
					)
					var _completed: bool = (
						operation.complete_for_framework(result)
					)
					return operation
		return super.save_payload_request_async(file_name, transfer)


class _HangingProfileStorage extends GFStorageUtility:
	var hang_profile_writes: bool = false
	var hang_profile_reads: bool = false
	var hanging_operations: Array[GFStorageAsyncOperation] = []
	var hanging_read_operations: Array[GFStorageAsyncOperation] = []
	var _payloads_by_request_id: Dictionary = {}
	var _read_results_by_request_id: Dictionary = {}
	var _next_request_id: int = 3_500_000
	var _next_read_request_id: int = 3_600_000


	## 挂起玩家 Profile 读取，并保留真实读取结果供迟到成功终态。
	## @param file_name: GFStorage 相对文件名。
	func load_data_request_async(
		file_name: String
	) -> GFStorageAsyncOperation:
		if not hang_profile_reads:
			return super.load_data_request_async(file_name)
		var read_result: GFStorageReadResult = super.load_data(file_name)
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_read_request_id
		_next_read_request_id += 1
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_LOAD,
			file_name
		)
		hanging_read_operations.append(operation)
		_read_results_by_request_id[request_id] = read_result
		return operation


	## 以此前捕获的真实读取结果完成全部挂起读取。
	func complete_all_hanging_reads() -> void:
		var operations: Array[GFStorageAsyncOperation] = (
			hanging_read_operations.duplicate()
		)
		hanging_read_operations.clear()
		for operation: GFStorageAsyncOperation in operations:
			if operation == null or operation.is_completed():
				continue
			var request_id: int = operation.get_request_id()
			var read_result_value: Variant = _read_results_by_request_id.get(
				request_id
			)
			var read_result: GFStorageReadResult = (
				read_result_value
				if read_result_value is GFStorageReadResult
				else null
			)
			var _erased: bool = _read_results_by_request_id.erase(
				request_id
			)
			var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
			var read_error: Error = (
				read_result.error_code
				if read_result != null
				else ERR_CANT_OPEN
			)
			var _result_configured: bool = result.configure_for_framework(
				request_id,
				GFStorageAsyncOperation.OPERATION_LOAD,
				operation.get_file_name(),
				read_result != null and read_result.ok,
				read_error,
				read_result
			)
			var _completed: bool = operation.complete_for_framework(
				result
			)


	## 挂起玩家 Profile opaque payload，并保留隔离副本供迟到终态故障注入。
	## @param file_name: GFStorage 相对文件名。
	## @param transfer: 此 generation 的单所有者 payload transfer。
	func save_payload_request_async(
		file_name: String,
		transfer: GFStoragePayloadTransfer
	) -> GFStorageAsyncOperation:
		if (
			not hang_profile_writes
			or (
				file_name != GameSaveGraphUtility.PROFILE_FILE_NAME
				and file_name.get_base_dir()
				!= LocalAccountCatalogUtility.PROFILE_DIRECTORY
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


	## 完成全部挂起写；可先真实落盘但仍报告错误，模拟不确定远端终态。
	## @param error_code: detached 请求最终报告的错误码。
	## @param persist_before_complete: 是否先把保留 payload 写入真实存储。
	func complete_all_hanging(
		error_code: Error,
		persist_before_complete: bool
	) -> void:
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
			if persist_before_complete and not payload.is_empty():
				var persist_error: Error = super.save_data(
					operation.get_file_name(),
					payload
				)
				assert(
					persist_error == OK,
					"测试故障注入 payload 必须可写入真实 GFStorage。"
				)
			var _attempt_finished: bool = (
				operation.finish_payload_attempt_for_framework()
			)
			var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
			var _result_configured: bool = result.configure_for_framework(
				request_id,
				GFStorageAsyncOperation.OPERATION_SAVE,
				operation.get_file_name(),
				error_code == OK,
				error_code
			)
			var _completed: bool = operation.complete_for_framework(result)


# --- 内部类 ---
