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


func test_manifest_backed_bookmarks_commit_and_reload_through_chunk_profiles() -> void:
	var save_dir_name: String = "gut_chunked_bookmarks_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		null,
		null,
		true
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"首次 Bookmark Manifest 提交后的有界尾块 cleanup 应先收敛。"
	)
	var observed_profile_ids: Array[StringName] = []
	var on_profile_operation: Callable = func(result: GFSaveProfileResult) -> void:
		if result != null:
			observed_profile_ids.append(result.get_profile_id())
	var connection_error: int = save_graph.profile_operation_completed.connect(
		on_profile_operation
	)
	assert_true(connection_error == OK)

	var bookmark: BookmarkData = _make_bookmark(598, 4096)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		bookmark_system.request_save_bookmark(bookmark),
		setup
	)
	if save_graph.profile_operation_completed.is_connected(on_profile_operation):
		save_graph.profile_operation_completed.disconnect(on_profile_operation)
	assert_true(
		save_result != null and save_result.is_successful(),
		"manifest-backed bookmarks 应完成 chunk staging 与 main commit。"
	)

	var preview: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(preview, "预览必须使用物理 Manifest section，而非业务 payload。")
	var bookmark_section: GFSaveSection = (
		preview.get_section(GameSaveGraphUtility.BOOKMARKS_SECTION_ID)
		if preview != null
		else null
	)
	assert_true(
		bookmark_section != null
		and bookmark_section.get_schema_version()
		== BookmarkManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		"主 Profile bookmarks section 必须采用物理 Manifest schema。"
	)
	var manifest: ChunkManifest = null
	if bookmark_section != null and bookmark_section.get_payload() is Dictionary:
		manifest = ChunkManifest.from_dict(
			GFVariantData.as_dictionary(bookmark_section.get_payload())
		)
	assert_not_null(manifest, "主 Profile 必须只暴露严格 ChunkManifest。")
	assert_false(
		GFVariantData.as_dictionary(
			bookmark_section.get_payload() if bookmark_section != null else {}
		).has(&"items"),
		"诊断预览不得把 bookmarks 业务目录重新内联进主 Profile。"
	)
	if manifest != null:
		var chunk_identity: ChunkProfileIdentity = (
			ChunkProfileRuntimeFactory.make_identity(
				save_graph.get_active_profile_id(),
				save_graph.get_profile_file_name(),
				GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
				manifest.get_bank(),
				0
			)
		)
		assert_true(
			chunk_identity != null
			and storage.load_data(chunk_identity.get_file_name()).ok,
			"Manifest 指向的首个派生 chunk Profile 必须已物理持久化。"
		)
	var signals_are_main_profile_only: bool = not observed_profile_ids.is_empty()
	for observed_profile_id: StringName in observed_profile_ids:
		if observed_profile_id != save_graph.get_active_profile_id():
			signals_are_main_profile_only = false
			break
	assert_true(
		signals_are_main_profile_only,
		"派生 chunk Profile 终态不得泄漏到 SaveGraph 的主 Profile 信号。"
	)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		null,
		null,
		true
	)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_bookmarks: Array[BookmarkData] = (
		_get_bookmark_system(reloaded).load_bookmarks()
	)
	assert_true(
		reloaded_graph.is_profile_loaded()
		and reloaded_bookmarks.size() == 1
		and reloaded_bookmarks[0].bookmark_id == bookmark.bookmark_id,
		"重启后必须先 materialize chunks，再事务应用 bookmarks 业务数据。"
	)
	_dispose_setup(reloaded)


func test_manifest_backed_replays_commit_and_reload_through_chunk_profiles() -> void:
	var save_dir_name: String = "gut_chunked_replays_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		null,
		null,
		false,
		true
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var replay_system: ReplaySystem = _get_replay_system(setup)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"首次 Replay Manifest 提交后的有界尾块 cleanup 应先收敛。"
	)
	var replay: ReplayData = _make_replay(599, 8192)
	var save_result: GameSaveSectionResult = await _await_section_operation(
		replay_system.request_save_replay(replay),
		setup
	)
	assert_true(
		save_result != null and save_result.is_successful(),
		"manifest-backed replays 应完成 chunk staging 与 main commit：%s" % (
			save_result.to_dict() if save_result != null else {}
		)
	)

	var preview: GFSaveDocument = GFSaveDocument.from_dict(
		save_graph.preview_profile_payload()
	)
	assert_not_null(preview, "预览必须使用物理 Replay Manifest section。")
	var replay_section: GFSaveSection = (
		preview.get_section(GameSaveGraphUtility.REPLAYS_SECTION_ID)
		if preview != null
		else null
	)
	assert_true(
		replay_section != null
		and replay_section.get_schema_version()
		== ReplayManifestSaveSectionProvider.PERSISTENCE_SCHEMA_VERSION,
		"主 Profile replays section 必须采用物理 Manifest schema。"
	)
	var manifest: ChunkManifest = null
	if replay_section != null and replay_section.get_payload() is Dictionary:
		manifest = ChunkManifest.from_dict(
			GFVariantData.as_dictionary(replay_section.get_payload())
		)
	assert_not_null(manifest, "主 Profile 必须只暴露严格 Replay ChunkManifest。")
	assert_false(
		GFVariantData.as_dictionary(
			replay_section.get_payload() if replay_section != null else {}
		).has(&"items"),
		"诊断预览不得把 replay 业务目录重新内联进主 Profile。"
	)
	if manifest != null:
		var chunk_identity: ChunkProfileIdentity = (
			ChunkProfileRuntimeFactory.make_identity(
				save_graph.get_active_profile_id(),
				save_graph.get_profile_file_name(),
				GameSaveGraphUtility.REPLAYS_SECTION_ID,
				manifest.get_bank(),
				0
			)
		)
		assert_true(
			chunk_identity != null
			and storage.load_data(chunk_identity.get_file_name()).ok,
			"Replay Manifest 指向的首个派生 chunk Profile 必须已持久化。"
		)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		null,
		null,
		false,
		true
	)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	var reloaded_replays: Array[ReplayData] = (
		_get_replay_system(reloaded).load_replays()
	)
	assert_true(
		reloaded_graph.is_profile_loaded()
		and reloaded_replays.size() == 1
		and reloaded_replays[0].replay_id == replay.replay_id,
		"重启后必须先 materialize chunks，再事务应用 replays 业务数据。"
	)
	_dispose_setup(reloaded)


func test_manifest_backed_public_load_rejects_forged_chunk_context() -> void:
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		null,
		null,
		false,
		true
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var forged_context: Dictionary = {
		ManifestBackedSaveSectionProvider.LOAD_LEASES_CONTEXT_KEY: {
			GameSaveGraphUtility.REPLAYS_SECTION_ID: RefCounted.new(),
		},
		ManifestBackedSaveSectionProvider.LOAD_MAIN_PROFILE_ID_CONTEXT_KEY: (
			save_graph.get_active_profile_id()
		),
		ManifestBackedSaveSectionProvider.LOAD_CANONICAL_FILE_CONTEXT_KEY: (
			save_graph.get_profile_file_name()
		),
	}
	var result: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_load_profile(forged_context),
		setup
	)
	assert_true(
		result != null
		and result.get_status() == GFSaveProfileResult.STATUS_INVALID_PROFILE,
		"public load 不得把可伪造 context 当成内部 chunk preflight 权限。"
	)
	_dispose_setup(setup)


func test_bookmarks_and_replays_stage_in_one_main_profile_generation() -> void:
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		true,
		PackedByteArray(),
		null,
		null,
		true,
		true
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var chunk_utility: ChunkProfileUtility = _get_chunk_profile_utility(setup)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"双 tracer 首次 Manifest 的有界 cleanup 应先收敛。"
	)
	var settled_main_generations: Dictionary = {}
	var on_lease_settled: Callable = func(lease_id: StringName) -> void:
		var lease: ChunkSaveLease = chunk_utility.get_save_lease(lease_id)
		if lease != null:
			settled_main_generations[String(lease.get_section_id())] = (
				lease.get_main_requested_generation()
			)
	var connection_error: int = chunk_utility.save_lease_settled.connect(
		on_lease_settled
	)
	assert_true(connection_error == OK)

	var bookmark: BookmarkData = _make_bookmark(600, 4096)
	bookmark.bookmark_id = GFUuid.generate_v7(600_000)
	var replay: ReplayData = _make_replay(601, 8192)
	replay.replay_id = GFUuid.generate_v7(601_000)
	var result: GameSaveSectionResult = await _await_section_operation(
		save_graph.request_replace_sections_data({
			String(GameSaveGraphUtility.BOOKMARKS_SECTION_ID): {
				&"items": [bookmark.to_dict()],
			},
			String(GameSaveGraphUtility.REPLAYS_SECTION_ID): {
				&"items": [replay.to_dict()],
			},
		}),
		setup
	)
	if chunk_utility.save_lease_settled.is_connected(on_lease_settled):
		chunk_utility.save_lease_settled.disconnect(on_lease_settled)
	var bookmark_generation: int = GFVariantData.get_option_int(
		settled_main_generations,
		String(GameSaveGraphUtility.BOOKMARKS_SECTION_ID),
		0
	)
	var replay_generation: int = GFVariantData.get_option_int(
		settled_main_generations,
		String(GameSaveGraphUtility.REPLAYS_SECTION_ID),
		0
	)
	assert_true(
		result != null
		and result.is_successful()
		and result.get_section_ids()
		== PackedStringArray(["bookmarks", "replays"]),
		"双 tracer 应由一次原子 section 事务提交：%s" % (
			result.to_dict() if result != null else {}
		)
	)
	assert_true(
		bookmark_generation > 0
		and bookmark_generation == replay_generation,
		"bookmarks/replays 的 lease 必须绑定同一个主 Profile generation。"
	)
	assert_true(
		_get_bookmark_system(setup).load_bookmarks().size() == 1
		and _get_replay_system(setup).load_replays().size() == 1,
		"双 tracer 成功后必须同时保留业务目录。"
	)
	_dispose_setup(setup)


func test_profile_delete_holds_path_until_two_derived_families_settle() -> void:
	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	chunk_utility.hang_next_cleanup(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		null,
		null,
		true,
		true,
		chunk_utility
	)
	assert_true(await _await_chunk_cleanup_idle(setup))
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_001)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	var result_box: Dictionary = _begin_inactive_profile_cleanup(
		save_graph,
		profile_file_name
	)
	for _frame: int in range(120):
		storage.wait_for_async_tasks()
		_get_architecture(setup).tick(0.0)
		await get_tree().process_frame
		if chunk_utility.has_pending_cleanup(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		):
			break
	assert_true(
		chunk_utility.has_pending_cleanup(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		)
		and not GFVariantData.get_option_bool(result_box, &"done", false)
		and save_graph.is_profile_cleanup_pending(profile_file_name),
		"main success 后必须继续持有 canonical path，直到 derived physical terminal。"
	)
	chunk_utility.complete_pending_cleanup(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	var cleanup_error: Error = await _await_inactive_profile_cleanup(
		result_box,
		setup
	)
	assert_true(cleanup_error == OK)
	assert_true(
		chunk_utility.cleanup_calls
		== [
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			GameSaveGraphUtility.REPLAYS_SECTION_ID,
		]
		and not save_graph.is_profile_cleanup_pending(profile_file_name),
		"所有 manifest-backed provider 必须动态遍历，并在全部终态后释放 path。"
	)
	var cleanup_debug: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		&"profile_cleanup"
	)
	var evidence: Dictionary = GFVariantData.get_option_dictionary(
		cleanup_debug,
		&"last_terminal"
	)
	assert_true(
		GFVariantData.get_option_int(evidence, &"derived_total_count", 0) == 2
		and GFVariantData.get_option_int(
			evidence,
			&"derived_completed_count",
			0
		) == 2
		and not evidence.has(&"profile_file")
		and not evidence.has(&"profile_id"),
		"复合 cleanup evidence 必须完整且不泄漏 logical identity/path。"
	)
	_dispose_setup(setup)


func test_profile_delete_timeout_keeps_path_until_late_main_and_derived() -> void:
	var storage: _ScriptedProfileDeleteStorage = (
		_ScriptedProfileDeleteStorage.new()
	)
	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		null,
		true,
		true,
		chunk_utility
	)
	assert_true(await _await_chunk_cleanup_idle(setup))
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_002)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	storage.arm_timeout(profile_file_name)
	var terminal_count: Dictionary = {&"value": 0}
	var _terminal_connection: int = save_graph.profile_cleanup_task_terminal.connect(
		func(_work_id: StringName) -> void:
			terminal_count[&"value"] = GFVariantData.get_option_int(
				terminal_count,
				&"value",
				0
			) + 1
	)
	var result_box: Dictionary = _begin_inactive_profile_cleanup(
		save_graph,
		profile_file_name
	)
	var caller_error: Error = await _await_inactive_profile_cleanup(
		result_box,
		setup
	)
	assert_true(
		caller_error == ERR_TIMEOUT
		and storage.has_pending_timeout()
		and save_graph.is_profile_cleanup_pending(profile_file_name)
		and chunk_utility.cleanup_calls.is_empty()
		and GFVariantData.get_option_int(terminal_count, &"value", 0) == 0,
		"caller timeout 必须立即返回，但不得释放 path、发 terminal 或提前删 chunks。"
	)
	storage.settle_timeout()
	for _frame: int in range(120):
		_get_architecture(setup).tick(0.0)
		await get_tree().process_frame
		if not save_graph.is_profile_cleanup_pending(profile_file_name):
			break
	assert_true(
		not save_graph.is_profile_cleanup_pending(profile_file_name)
		and chunk_utility.cleanup_calls.size() == 2
		and GFVariantData.get_option_int(terminal_count, &"value", 0) == 1,
		"迟到 main success 后必须清完全部 derived，再发布唯一 terminal。"
	)
	var evidence: Dictionary = GFVariantData.get_option_dictionary(
		GFVariantData.get_option_dictionary(
			save_graph.get_debug_snapshot(),
			&"profile_cleanup"
		),
		&"last_terminal"
	)
	assert_true(
		GFVariantData.get_option_bool(
			evidence,
			&"caller_outcome_unknown",
			false
		)
	)
	_dispose_setup(setup)


func test_legacy_profile_cleanup_does_not_expire_before_worker_acceptance() -> void:
	var storage: _RawFixtureStorage = _RawFixtureStorage.new()
	storage.async_execution_mode = (
		GFStorageUtility.AsyncExecutionMode.COOPERATIVE
	)
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	assert_true(storage.save_data(
		GameSaveGraphUtility.PROFILE_FILE_NAME,
		{&"fixture": true}
	) == OK)
	var result_box: Dictionary = _begin_legacy_profile_cleanup(save_graph)
	# deferred 调用只负责把 main delete 入队；刻意不 tick architecture，保证
	# cooperative worker 尚未接纳该维护请求。
	await get_tree().process_frame
	var cleanup_debug: Dictionary = GFVariantData.get_option_dictionary(
		save_graph.get_debug_snapshot(),
		&"profile_cleanup"
	)
	assert_true(
		GFVariantData.get_option_int(cleanup_debug, &"main_pending_count", 0)
		== 1
	)
	assert_true(clock.advance_msec(5_001))
	var cleanup_error: Error = await _await_profile_cleanup_without_forced_drain(
		result_box,
		setup
	)
	assert_true(
		cleanup_error == OK,
		"后台 legacy 维护不得因 cooperative 队列等待超过用户观察预算而取消。"
	)
	var evidence: Dictionary = GFVariantData.get_option_dictionary(
		GFVariantData.get_option_dictionary(
			save_graph.get_debug_snapshot(),
			&"profile_cleanup"
		),
		&"last_terminal"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			evidence,
			&"cleanup_kind"
		) == &"legacy_maintenance"
		and GFVariantData.get_option_bool(
			evidence,
			&"main_physical_settled",
			false
		)
		and GFVariantData.get_option_string_name(
			evidence,
			&"derived_status"
		) == &"cleaned"
		and not evidence.has(&"profile_file")
		and not evidence.has(&"profile_id")
		and not evidence.has(&"account_id"),
		"legacy terminal 必须给出分阶段且不含身份/路径的结构化证据。"
	)
	_dispose_setup(setup)


func test_user_profile_delete_preacceptance_expiry_reports_main_phase() -> void:
	var storage: _RawFixtureStorage = _RawFixtureStorage.new()
	storage.async_execution_mode = (
		GFStorageUtility.AsyncExecutionMode.COOPERATIVE
	)
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		clock
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_006)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	var result_box: Dictionary = _begin_inactive_profile_cleanup(
		save_graph,
		profile_file_name
	)
	await get_tree().process_frame
	assert_true(clock.advance_msec(5_001))
	var cleanup_error: Error = await _await_profile_cleanup_without_forced_drain(
		result_box,
		setup
	)
	assert_true(cleanup_error == ERR_SKIP)
	var evidence: Dictionary = GFVariantData.get_option_dictionary(
		GFVariantData.get_option_dictionary(
			save_graph.get_debug_snapshot(),
			&"profile_cleanup"
		),
		&"last_terminal"
	)
	assert_true(
		GFVariantData.get_option_string_name(
			evidence,
			&"cleanup_kind"
		) == &"inactive_profile_request"
		and GFVariantData.get_option_string_name(
			evidence,
			&"failure_phase"
		) == &"main_delete"
		and GFVariantData.get_option_int(
			evidence,
			&"main_caller_end_kind",
			-1
		) == int(GFStorageAsyncCallerResult.EndKind.DEADLINE_EXPIRED)
		and GFVariantData.get_option_string_name(
			evidence,
			&"main_caller_reason"
		) == &"deadline_expired"
		and GFVariantData.get_option_int(
			evidence,
			&"main_physical_settlement_kind",
			-1
		) == int(GFStorageAsyncResult.SettlementKind.CANCELLED)
		and GFVariantData.get_option_string_name(
			evidence,
			&"derived_status"
		) == &"not_started",
		"用户观察预算接纳前到期必须明确归因 main，而不是伪装 derived 失败。"
	)
	var evidence_text: String = JSON.stringify(evidence)
	assert_false(
		evidence_text.contains(profile_file_name)
		or evidence.has(&"profile_file")
		or evidence.has(&"profile_id")
		or evidence.has(&"account_id")
		or evidence.has(&"payload"),
		"cleanup evidence 不得暴露路径、账号身份或存档 payload。"
	)
	_dispose_setup(setup)


func test_profile_delete_known_main_failure_never_cleans_derived() -> void:
	var storage: _ScriptedProfileDeleteStorage = (
		_ScriptedProfileDeleteStorage.new()
	)
	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		null,
		true,
		true,
		chunk_utility
	)
	assert_true(await _await_chunk_cleanup_idle(setup))
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_003)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	storage.arm_known_failure(profile_file_name, ERR_CANT_CREATE)
	var cleanup_error: Error = await _await_inactive_profile_cleanup(
		_begin_inactive_profile_cleanup(save_graph, profile_file_name),
		setup
	)
	assert_true(
		cleanup_error == ERR_CANT_CREATE
		and chunk_utility.cleanup_calls.is_empty()
		and storage.load_data(profile_file_name).ok
		and not save_graph.is_profile_cleanup_pending(profile_file_name),
		"main known failure 必须保留 derived family，且只在确定终态后释放 path。"
	)
	_dispose_setup(setup)


func test_profile_delete_missing_chunk_utility_closes_path_ownership() -> void:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var profile_file_name: String = _make_inactive_profile_file_name(810_004)
	var main_operation: GFStorageAsyncOperation = (
		_make_completed_profile_delete_operation(
			810_004,
			profile_file_name,
			OK
		)
	)
	var saga: GameSaveProfileCleanupSaga = GameSaveProfileCleanupSaga.create(
		profile_file_name,
		&"inactive_profile_request",
		main_operation,
		false
	)
	assert_not_null(saga)
	assert_true(saga.settle_main_delete(OK))
	save_graph._profile_cleanup_paths[profile_file_name] = (
		main_operation.get_request_id()
	)
	save_graph._profile_cleanup_sagas[main_operation.get_request_id()] = saga
	var cleanup_error: Error = await save_graph._cleanup_manifest_families_async(
		saga
	)
	assert_true(saga.is_completed())
	save_graph._publish_profile_cleanup_saga_terminal(saga)
	var evidence: Dictionary = save_graph.get_last_profile_cleanup_evidence()
	assert_true(cleanup_error == ERR_UNCONFIGURED)
	assert_false(save_graph.is_profile_cleanup_pending(profile_file_name))
	assert_true(
		GFVariantData.get_option_string_name(evidence, &"status")
		== &"derived_setup_failed"
		and GFVariantData.get_option_string_name(
			evidence,
			&"derived_status"
		) == &"setup_failed",
		"缺失 ChunkProfileUtility 时必须闭合 Saga 与 canonical path ownership。"
	)


func test_profile_delete_partial_derived_failure_is_retryable_and_idempotent() -> void:
	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	chunk_utility.queue_cleanup_error(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		ERR_CANT_CREATE
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		null,
		null,
		true,
		true,
		chunk_utility
	)
	assert_true(await _await_chunk_cleanup_idle(setup))
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_004)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	var first_error: Error = await _await_inactive_profile_cleanup(
		_begin_inactive_profile_cleanup(save_graph, profile_file_name),
		setup
	)
	assert_true(
		first_error == ERR_CANT_CREATE
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) == 1
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.REPLAYS_SECTION_ID
		) == 1,
		"derived partial failure 必须继续收敛其余 provider，并聚合首错。"
	)
	var retry_error: Error = await _await_inactive_profile_cleanup(
		_begin_inactive_profile_cleanup(save_graph, profile_file_name),
		setup
	)
	assert_true(
		retry_error == OK
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) == 2
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.REPLAYS_SECTION_ID
		) == 2,
		"main NOT_FOUND 与已不存在 derived 必须支持整套幂等重试。"
	)
	_dispose_setup(setup)


func test_profile_delete_waits_existing_derived_cleanup_then_retries_busy() -> void:
	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	chunk_utility.set_external_busy(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		true
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		null,
		null,
		true,
		true,
		chunk_utility
	)
	assert_true(await _await_chunk_cleanup_idle(setup))
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var profile_file_name: String = _make_inactive_profile_file_name(810_005)
	assert_true(storage.save_data(profile_file_name, {&"fixture": true}) == OK)
	var result_box: Dictionary = _begin_inactive_profile_cleanup(
		save_graph,
		profile_file_name
	)
	for _frame: int in range(30):
		storage.wait_for_async_tasks()
		_get_architecture(setup).tick(0.0)
		await get_tree().process_frame
		if chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) > 0:
			break
	for _frame: int in range(5):
		_get_architecture(setup).tick(0.0)
		await get_tree().process_frame
	assert_true(
		chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) == 1
		and not GFVariantData.get_option_bool(result_box, &"done", false)
		and save_graph.is_profile_cleanup_pending(profile_file_name),
		(
			"typed BUSY 后必须等待既有 cleanup settlement，不得逐帧重试或释放 identity："
			+ "calls=%d done=%s pending=%s"
			% [
				chunk_utility.cleanup_call_count(
					GameSaveGraphUtility.BOOKMARKS_SECTION_ID
				),
				GFVariantData.get_option_bool(result_box, &"done", false),
				save_graph.is_profile_cleanup_pending(profile_file_name),
			]
		)
	)
	chunk_utility.set_external_busy(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		false
	)
	var cleanup_error: Error = await _await_inactive_profile_cleanup(
		result_box,
		setup
	)
	assert_true(
		cleanup_error == OK
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID
		) == 2
		and chunk_utility.cleanup_call_count(
			GameSaveGraphUtility.REPLAYS_SECTION_ID
		) == 1,
		(
			"既有 owner settlement 后必须幂等重试同 scope，再继续后续 provider："
			+ "error=%d bookmark_calls=%d replay_calls=%d"
			% [
				cleanup_error,
				chunk_utility.cleanup_call_count(
					GameSaveGraphUtility.BOOKMARKS_SECTION_ID
				),
				chunk_utility.cleanup_call_count(
					GameSaveGraphUtility.REPLAYS_SECTION_ID
				),
			]
		)
	)
	_dispose_setup(setup)


func test_obsolete_active_profile_reset_cleans_two_derived_families() -> void:
	var save_dir_name: String = "gut_chunked_active_reset_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var original: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		false,
		PackedByteArray(),
		null,
		null,
		true,
		true
	)
	assert_true(await _await_chunk_cleanup_idle(original))
	var original_graph: GameSaveGraphUtility = _get_save_graph(original)
	var original_storage: GFStorageUtility = _get_storage(original)
	var current: GFSaveDocument = GFSaveDocument.from_dict(
		original_graph.preview_profile_payload()
	)
	assert_not_null(current)
	if current == null:
		_dispose_setup(original)
		return
	var obsolete: GFSaveDocument = GFSaveDocument.new().configure(
		GameSaveGraphUtility.PROFILE_SCHEMA_ID,
		10,
		current.get_sections(),
		{&"fixture": "active_reset"}
	)
	assert_true(
		original_storage.save_data(
			original_graph.get_profile_file_name(),
			obsolete.to_dict()
		) == OK
	)
	_dispose_setup(original, false)
	original_storage.dispose()

	var chunk_utility: _ControllableChunkProfileUtility = (
		_ControllableChunkProfileUtility.new()
	)
	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		false,
		PackedByteArray(),
		null,
		null,
		true,
		true,
		chunk_utility
	)
	var reloaded_graph: GameSaveGraphUtility = _get_save_graph(reloaded)
	assert_true(
		reloaded_graph.is_profile_loaded()
		and chunk_utility.cleanup_calls
		== [
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			GameSaveGraphUtility.REPLAYS_SECTION_ID,
		],
		"active destructive reset 必须在 main delete/NOT_FOUND 后清理所有 derived，再 re-register。"
	)
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(
				reloaded_graph.get_debug_snapshot(),
				&"profile_cleanup"
			),
			&"pending_count",
			-1
		) == 0,
		"active reset 返回前不得遗留 cleanup path owner。"
	)
	_dispose_setup(reloaded)


func test_fenced_pending_bookmark_save_parks_until_settlement_before_quiesce_flush() -> void:
	var save_dir_name: String = "gut_chunked_parked_quiesce_%s" % (
		GFUuid.generate_v4().replace("-", "")
	)
	var storage: _HangingProfileStorage = _HangingProfileStorage.new()
	var clock: GFManualClock = GFManualClock.new(0, 1_000_000)
	var setup: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		storage,
		clock,
		true
	)
	var architecture: GFArchitecture = _get_architecture(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var chunk_utility: ChunkProfileUtility = _get_chunk_profile_utility(setup)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"parked 回归必须从 bootstrap cleanup 已收敛的 scope 开始。"
	)
	var baseline: BookmarkData = _make_bookmark(599, 128)
	baseline.bookmark_id = GFUuid.generate_v7(599_000)
	var baseline_result: GameSaveSectionResult = await _await_section_operation(
		_get_bookmark_system(setup).request_save_bookmark(baseline),
		setup
	)
	assert_true(
		baseline_result != null and baseline_result.is_successful(),
		"parked 回归必须先建立已可见的 baseline Manifest。"
	)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"baseline commit 的旧 bank/tail cleanup 必须在故障注入前收敛。"
	)

	var first_pending: BookmarkData = _make_bookmark(600, 256)
	first_pending.bookmark_id = GFUuid.generate_v7(600_000)
	storage.hang_profile_writes = true
	assert_true(save_graph.queue_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		{&"items": [first_pending.to_dict()]}
	) == OK)
	architecture.tick(1.0)
	await _await_hanging_profile_write(storage, setup)
	await _advance_profile_deadlines(setup, clock)
	assert_true(
		GFVariantData.get_option_int(
			chunk_utility.get_debug_snapshot(),
			&"outcome_unknown_scope_count",
			0
		) == 1,
		"旧 bookmarks generation 超时后必须形成 exact scope fence。"
	)

	# 新 dirty intent 停留在 debounce pending，尚未因一次被拒保存转 parked。
	var latest: BookmarkData = _make_bookmark(601, 512)
	latest.bookmark_id = GFUuid.generate_v7(601_000)
	assert_true(save_graph.queue_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		{&"items": [latest.to_dict()]}
	) == OK)
	var before_quiesce: Dictionary = save_graph.get_debug_snapshot()
	assert_true(
		GFVariantData.get_option_bool(before_quiesce, &"save_pending", false)
		and not GFVariantData.get_option_bool(
			before_quiesce,
			&"chunk_save_parked",
			true
		),
		"回归必须从未尝试 debounce 的 pending dirty intent 开始。"
	)
	var quiesce: GFAsyncCompletion = save_graph.begin_quiesce(
		GFAsyncScope.new()
	)
	var parked_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(
		quiesce != null
		and quiesce.is_pending()
		and GFVariantData.get_option_bool(
			parked_snapshot,
			&"chunk_save_parked",
			false
		)
		and GFVariantData.get_option_bool(
			parked_snapshot,
			&"save_pending",
			false
		),
		"quiesce 必须先 park fenced dirty intent，不得把旧 generation flush 当成成功。"
	)

	# N 迟到成功会先推进 scope basis，再触发 parked intent 的唯一次重臂。
	storage.complete_all_hanging(OK, true)
	assert_true(
		await _await_chunk_cleanup_idle(setup),
		"迟到 exact commit 必须先等旧 bank/tail cleanup fence 收敛，再重臂 dirty intent。"
	)
	await _await_hanging_profile_write(storage, setup)
	var rearmed_snapshot: Dictionary = save_graph.get_debug_snapshot()
	assert_true(
		quiesce.is_pending()
		and not GFVariantData.get_option_bool(
			rearmed_snapshot,
			&"chunk_save_parked",
			true
		)
		and storage.hanging_operations.size() == 1,
		"迟到结算后必须开始新 dirty generation；其终态前 quiesce 仍不能完成。"
	)

	storage.hang_profile_writes = false
	storage.complete_all_hanging(OK, true)
	for _frame: int in range(600):
		architecture.tick(0.0)
		storage.wait_for_async_tasks()
		await get_tree().process_frame
		if quiesce.is_completed():
			break
	assert_true(
		quiesce.is_completed() and quiesce.is_successful(),
		"quiesce 只能在重臂的最新 chunk generation 与其 flush 都已成功后完成。"
	)

	_dispose_setup(setup, false)
	var reloaded: Dictionary = await _create_persistence_architecture(
		save_dir_name,
		true,
		PackedByteArray(),
		null,
		null,
		true
	)
	var reloaded_bookmarks: Array[BookmarkData] = (
		_get_bookmark_system(reloaded).load_bookmarks()
	)
	assert_true(
		reloaded_bookmarks.size() == 1
		and reloaded_bookmarks[0].bookmark_id == latest.bookmark_id,
		"重启必须只物化 quiesce 等到的最新 parked dirty generation。"
	)
	_dispose_setup(reloaded)


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


func test_rollback_failure_keeps_mutation_closed_and_fails_quiesce_for_restart() -> void:
	var storage: _RetryStorage = _RetryStorage.new()
	var progress_provider: _RollbackFailingProgressSaveData = (
		_RollbackFailingProgressSaveData.new()
	)
	var setup: Dictionary = await _create_persistence_architecture(
		"",
		false,
		PackedByteArray(),
		storage,
		null,
		false,
		false,
		null,
		progress_provider
	)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var original_profile_file_name: String = save_graph.get_profile_file_name()
	var candidate: Dictionary = _make_empty_progress_data()
	candidate["stats"] = {"classic": {"rollback_must_fail_closed": true}}
	progress_provider.reject_next_rollback()
	storage.profile_save_errors = [ERR_INVALID_DATA]

	var failed_operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			candidate
		)
	)
	var failed_result: GameSaveSectionResult = await _await_section_operation(
		failed_operation,
		setup
	)
	assert_push_error("section 回滚失败")
	var transaction_id: int = failed_operation.get_transaction_id()
	assert_true(
		failed_result != null
		and failed_result.get_status()
		== GameSaveSectionResult.STATUS_ROLLBACK_FAILED
		and failed_result.requires_restart()
		and not failed_result.requires_reconciliation()
		and save_graph.is_section_reconciliation_pending()
		and save_graph.is_section_restart_required()
		and save_graph.get_pending_section_reconciliation_transaction_id()
		== transaction_id,
		"rollback_failed 必须永久保留原事务 reconciliation 身份。"
	)

	var architecture: GFArchitecture = _get_architecture(setup)
	for _frame: int in range(12):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
	assert_true(
		save_graph.is_section_reconciliation_pending()
		and save_graph.get_pending_section_reconciliation_transaction_id()
		== transaction_id,
		"没有可信恢复证据时，tick 不得自动释放 rollback_failed reconciliation。"
	)

	var blocked_section: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			_make_empty_progress_data()
		)
	)
	var blocked_section_result: GameSaveSectionResult = (
		blocked_section.get_result()
	)
	assert_true(
		blocked_section_result != null
		and blocked_section_result.get_status()
		== GameSaveSectionResult.STATUS_BUSY
		and save_graph.queue_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			_make_empty_progress_data()
		) == ERR_BUSY,
		"rollback_failed 期间 immediate 与 debounced section 写都必须 fail-closed。"
	)

	var rejected_save: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_save_profile({&"test": "rollback_failed_gate"}),
		setup
	)
	var rejected_load: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_load_profile({}, {&"test": "rollback_failed_gate"}),
		setup
	)
	var rejected_flush: GFSaveProfileResult = await _await_profile_operation(
		save_graph.request_flush_profile({&"test": "rollback_failed_gate"}),
		setup
	)
	assert_true(
		rejected_save != null
		and rejected_save.get_status() == GFSaveProfileResult.STATUS_INVALID_PROFILE
		and rejected_load != null
		and rejected_load.get_status() == GFSaveProfileResult.STATUS_INVALID_PROFILE
		and rejected_flush != null
		and rejected_flush.get_status() == GFSaveProfileResult.STATUS_INVALID_PROFILE,
		"未对账的 rollback_failed 状态不得再接纳 Profile save/load/flush。"
	)

	var switch_error: Error = await save_graph.activate_profile_async(
		_make_inactive_profile_file_name(2_048_777),
		true
	)
	assert_true(
		switch_error == ERR_BUSY
		and save_graph.get_profile_file_name() == original_profile_file_name,
		"rollback_failed reconciliation 未解除前不得切换或改写 Profile 身份。"
	)

	var quiesce: GFAsyncCompletion = save_graph.begin_quiesce(
		GFAsyncScope.new()
	)
	for _frame: int in range(2):
		architecture.tick(1.0 / 60.0)
		await get_tree().process_frame
	assert_true(
		quiesce != null
		and quiesce.is_completed()
		and quiesce.is_failed()
		and GFVariantData.get_option_bool(
			quiesce.get_metadata(),
			&"restart_required",
			false
		)
		and save_graph.is_section_reconciliation_pending()
		and save_graph.get_pending_section_reconciliation_transaction_id()
		== transaction_id,
		"quiesce 必须以 restart-required 失败终结，同时保留 rollback_failed 所有权栅栏。"
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


func test_profile_schema_v10_is_backed_up_then_reset_to_v13() -> void:
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
		{&"app_version": "pre-profile-v13"}
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
		"Profile schema 迁移必须显式备份 v10，再重建 v13。"
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
		"活动 Profile 必须只写当前 v13 schema。"
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


func test_v6_bookmark_history_rejects_more_than_64_commands_before_apply() -> void:
	var bookmark: BookmarkData = _make_bookmark(897, 1024)
	bookmark.bookmark_id = GFUuid.generate_v7(897000)
	bookmark.game_state_history = _make_bookmark_history(
		bookmark,
		BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT + 1
	)

	# 恶意 v6 二进制载荷可在 2 MiB 内容纳超过 64 条合法命令；完整解码后
	# 必须在逐命令语义遍历前拒绝，而不是把超额历史带入权威状态。
	var current_payload: Dictionary = bookmark.to_dict()
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	assert_true(
		BookmarkData.is_persisted_envelope_lightweight_valid(current_payload),
		"恶意样本应能通过不解码 payload 的轻量 envelope 门禁。"
	)
	assert_null(
		BookmarkData.from_dict(current_payload),
		"当前 v6 历史的 undo+redo 合计超过 64 条时必须拒绝。"
	)
	assert_true(
		provider.replace_section_data({&"items": [current_payload]})
		== ERR_INVALID_DATA,
		"provider 完整应用不得接纳超额 v6 历史。"
	)

	var legacy_payload: Dictionary = current_payload.duplicate(false)
	legacy_payload["schema_version"] = 5
	legacy_payload["game_state_history"] = bookmark.game_state_history
	assert_not_null(
		BookmarkData.from_dict(legacy_payload),
		"v5 字典历史继续使用自身 1024 条迁移边界。"
	)


func test_bookmark_history_rejects_single_command_board_over_256_cells() -> void:
	var bookmark: BookmarkData = _make_bookmark(896, 1024)
	bookmark.bookmark_id = GFUuid.generate_v7(896500)
	var oversized_history: Dictionary = _make_bookmark_history(bookmark, 1)
	var undo_value: Variant = oversized_history.get("undo")
	assert_true(undo_value is Array)
	if not undo_value is Array:
		return
	var undo: Array = undo_value
	assert_true(undo.size() == 1 and undo[0] is Dictionary)
	if undo.size() != 1 or not undo[0] is Dictionary:
		return
	var command: Dictionary = undo[0]
	var snapshot_value: Variant = command.get(&"snapshot")
	assert_true(snapshot_value is Dictionary)
	if not snapshot_value is Dictionary:
		return
	var snapshot: Dictionary = snapshot_value
	var oversized_topology: BoardTopology = BoardTopology.create_rectangle(
		Vector2i(BookmarkData.PERSISTED_BOARD_CELL_LIMIT + 1, 1)
	)
	assert_not_null(oversized_topology)
	if oversized_topology == null:
		return
	snapshot[&"board_key"] = oversized_topology.get_stable_key()
	snapshot[&"board_snapshot"] = _make_empty_board_snapshot(
		oversized_topology
	)

	var current_payload: Dictionary = bookmark.to_dict()
	var codec: GFStorageCodec = GFStorageCodec.new()
	current_payload["game_state_history"] = {
		"codec": "gf_storage_binary_v1",
		"payload": codec.serialize_dictionary(
			oversized_history,
			GFStorageCodec.Format.BINARY
		),
	}
	assert_null(
		BookmarkData.from_dict(current_payload),
		"v6 单命令快照的 active_cells 超过 256 时必须拒绝。"
	)

	var legacy_payload: Dictionary = current_payload.duplicate(false)
	legacy_payload["schema_version"] = 5
	legacy_payload["game_state_history"] = oversized_history
	assert_null(
		BookmarkData.from_dict(legacy_payload),
		"v5 迁移输入同样不得绕过每条命令的 256 格业务边界。"
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
	bookmark.game_state_history = _make_bookmark_history(
		bookmark,
		BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT
	)
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
	bookmark.game_state_history = _make_bookmark_history(
		bookmark,
		BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT + 1
	)
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
			"直接读取 v5 时仍应先完整验证其独立 legacy 边界。"
		)
		var upgraded_payload: Dictionary = (
			restored.to_persisted_candidate_envelope()
		)
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
	if provider_items.size() == 1 and provider_items[0] is Dictionary:
		var migrated_v6: BookmarkData = BookmarkData.from_dict(
			GFVariantData.as_dictionary(provider_items[0])
		)
		assert_not_null(
			migrated_v6,
			"v5 provider 迁移产物必须能被当前 v6 自身重新读取。"
		)
		if migrated_v6 != null:
			assert_true(
				GFVariantData.get_option_array(
					migrated_v6.game_state_history,
					"undo"
				).size() == BookmarkData.PERSISTED_HISTORY_TOTAL_LIMIT,
				"v5 超额历史升级为 v6 时必须只保留最近 64 条。"
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

func _begin_inactive_profile_cleanup(
	save_graph: GameSaveGraphUtility,
	profile_file_name: String
) -> Dictionary:
	var result_box: Dictionary = {
		&"done": false,
		&"error_code": int(FAILED),
	}
	call_deferred(
		&"_capture_inactive_profile_cleanup",
		save_graph,
		profile_file_name,
		result_box
	)
	return result_box


func _capture_inactive_profile_cleanup(
	save_graph: GameSaveGraphUtility,
	profile_file_name: String,
	result_box: Dictionary
) -> void:
	var cleanup_error: Error = await save_graph.delete_inactive_profile_async(
		profile_file_name
	)
	result_box[&"error_code"] = int(cleanup_error)
	result_box[&"done"] = true


func _begin_legacy_profile_cleanup(
	save_graph: GameSaveGraphUtility
) -> Dictionary:
	var result_box: Dictionary = {
		&"done": false,
		&"error_code": int(FAILED),
	}
	call_deferred(
		&"_capture_legacy_profile_cleanup",
		save_graph,
		result_box
	)
	return result_box


func _capture_legacy_profile_cleanup(
	save_graph: GameSaveGraphUtility,
	result_box: Dictionary
) -> void:
	var cleanup_error: Error = (
		await save_graph.delete_inactive_legacy_profile_async()
	)
	result_box[&"error_code"] = int(cleanup_error)
	result_box[&"done"] = true


func _await_profile_cleanup_without_forced_drain(
	result_box: Dictionary,
	setup: Dictionary,
	frame_limit: int = 600
) -> Error:
	var architecture: GFArchitecture = _get_architecture(setup)
	for _frame: int in range(frame_limit):
		if GFVariantData.get_option_bool(result_box, &"done", false):
			break
		architecture.tick(0.0)
		await get_tree().process_frame
	@warning_ignore("int_as_enum_without_cast")
	return GFVariantData.get_option_int(
		result_box,
		&"error_code",
		FAILED
	)


func _await_inactive_profile_cleanup(
	result_box: Dictionary,
	setup: Dictionary,
	frame_limit: int = 600
) -> Error:
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	for _frame: int in range(frame_limit):
		if GFVariantData.get_option_bool(result_box, &"done", false):
			break
		storage.wait_for_async_tasks()
		architecture.tick(0.0)
		await get_tree().process_frame
	@warning_ignore("int_as_enum_without_cast")
	return GFVariantData.get_option_int(
		result_box,
		&"error_code",
		FAILED
	)


func _make_inactive_profile_file_name(serial: int) -> String:
	return LocalAccountCatalogUtility.make_profile_file_name(
		GFUuid.generate_v7(serial)
	)


func _await_chunk_cleanup_idle(setup: Dictionary) -> bool:
	var architecture: GFArchitecture = _get_architecture(setup)
	var storage: GFStorageUtility = _get_storage(setup)
	var chunk_utility: ChunkProfileUtility = _get_chunk_profile_utility(setup)
	for _frame: int in range(300):
		var snapshot: Dictionary = chunk_utility.get_debug_snapshot()
		if (
			GFVariantData.get_option_int(
				snapshot,
				&"cleanup_operation_count",
				-1
			) == 0
			and GFVariantData.get_option_int(
				snapshot,
				&"cleanup_scope_count",
				-1
			) == 0
		):
			return true
		storage.wait_for_async_tasks()
		architecture.tick(0.0)
		await get_tree().process_frame
	return false


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
		storage.wait_for_async_tasks()
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
	clock_override: GFManualClock = null,
	use_chunked_bookmarks: bool = false,
	use_chunked_replays: bool = false,
	chunk_utility_override: ChunkProfileUtility = null,
	progress_provider_override: GameSaveSectionData = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else _RawFixtureStorage.new()
	)
	var save_graph: GameSaveGraphUtility = _make_game_save_graph(
		use_chunked_bookmarks,
		use_chunked_replays,
		progress_provider_override
	)
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
	if clock_override != null:
		assert_true(storage.set_async_clock_for_framework(shared_clock))

	storage.save_dir_name = (
		save_dir_name
		if not save_dir_name.is_empty()
		else "gut_save_graph_%s" % GFUuid.generate_v4().replace("-", "")
	)
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
		ChunkProfileUtility,
		(
			chunk_utility_override
			if chunk_utility_override != null
			else ChunkProfileUtility.new()
		)
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
	var bootstrap_completion_value: Variant = bootstrap.get(&"completion")
	var bootstrap_completion: GFAsyncCompletion = null
	if bootstrap_completion_value is GFAsyncCompletion:
		bootstrap_completion = bootstrap_completion_value
	assert_true(
		bootstrap_completion != null
		and bootstrap_completion.is_successful(),
		"SaveGraph 测试夹具必须显式完成账号 Profile 引导。"
	)

	return {
		"architecture": architecture,
		"storage": storage,
		"save_graph": save_graph,
		"chunk_profile_utility": architecture.get_utility(
			ChunkProfileUtility
		),
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


func _make_game_save_graph(
	use_chunked_bookmarks: bool = false,
	use_chunked_replays: bool = false,
	progress_provider_override: GameSaveSectionData = null
) -> GameSaveGraphUtility:
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	var progress_provider: GameSaveSectionData = progress_provider_override
	if progress_provider == null:
		progress_provider = GameStatsSaveData.new()
	var bookmark_data: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var bookmark_profile_provider: GFSaveSectionProvider = null
	if use_chunked_bookmarks:
		bookmark_profile_provider = BookmarkManifestSaveSectionProvider.new(
			bookmark_data
		)
	var replay_data: ReplayCatalogSaveData = ReplayCatalogSaveData.new()
	var replay_profile_provider: GFSaveSectionProvider = null
	if use_chunked_replays:
		replay_profile_provider = ReplayManifestSaveSectionProvider.new(
			replay_data
		)
	var progress_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		progress_provider,
		GameSaveGraphUtility.SectionOrder.EARLY
	)
	var bookmarks_registered: bool = save_graph.register_section(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		bookmark_data,
		GameSaveGraphUtility.SectionOrder.NORMAL,
		bookmark_profile_provider
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
		replay_data,
		GameSaveGraphUtility.SectionOrder.LATE,
		replay_profile_provider
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
	if not (storage is _RawFixtureStorage):
		return ERR_INVALID_PARAMETER
	var fixture_storage: _RawFixtureStorage = storage
	var path: String = fixture_storage.get_fixture_payload_path(file_name)
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
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


func _make_completed_profile_delete_operation(
	request_id: int,
	file_name: String,
	error_code: Error
) -> GFStorageAsyncOperation:
	var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
	assert_true(
		operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name
		)
	)
	var delete_result: GFStorageDeleteResult = GFStorageDeleteResult.new()
	assert_true(
		delete_result.configure_for_framework(
			error_code,
			(
				GFStorageDeleteResult.FailureKind.NONE
				if error_code == OK
				else GFStorageDeleteResult.FailureKind.IO_FAILED
			),
			1,
			1 if error_code == OK else 0,
			0 if error_code == OK else 1,
			(
				GFStorageDeleteResult.FamilyMember.NONE
				if error_code == OK
				else GFStorageDeleteResult.FamilyMember.FINAL
			)
		)
	)
	var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
	assert_true(
		result.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name,
			error_code == OK,
			error_code,
			null,
			GFStorageAsyncResult.WriteFailureKind.NONE,
			{},
			delete_result
		)
	)
	assert_true(operation.complete_for_framework(result))
	return operation






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


func _get_chunk_profile_utility(
	setup: Dictionary
) -> ChunkProfileUtility:
	var value: Variant = GFVariantData.get_option_value(
		setup,
		"chunk_profile_utility"
	)
	if value is ChunkProfileUtility:
		var utility: ChunkProfileUtility = value
		return utility
	assert_true(false, "测试 setup 缺少 ChunkProfileUtility。")
	return ChunkProfileUtility.new()


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

class _RawFixtureStorage extends GFStorageUtility:
	## @param file_name: 要解析的 GFStorage 相对文件名。
	func get_fixture_payload_path(file_name: String) -> String:
		if _prepare_family_for_write(file_name) != OK:
			return ""
		var descriptor: Dictionary = _make_family_descriptor(file_name)
		return GFVariantData.get_option_string(descriptor, "payload_path")


class _RollbackFailingProgressSaveData extends GameStatsSaveData:
	var _reject_rollback_once: bool = false


	func reject_next_rollback() -> void:
		_reject_rollback_once = true


	## @param payload: 要应用到测试存档 Section 的完整 envelope。
	func replace_from_dict(payload: Dictionary) -> Error:
		if _reject_rollback_once:
			_reject_rollback_once = false
			return ERR_CANT_CREATE
		return super.replace_from_dict(payload)


class _ControllableChunkProfileUtility extends ChunkProfileUtility:
	var cleanup_calls: Array[StringName] = []
	var _hang_next_sections: Dictionary = {}
	var _pending_operations: Dictionary = {}
	var _external_busy_sections: Dictionary = {}
	var _scripted_errors: Dictionary = {}
	var _next_operation_serial: int = 1


	## @param section_id: 下一次清理要保持待决的 section ID。
	func hang_next_cleanup(section_id: StringName) -> void:
		_hang_next_sections[section_id] = true


	## @param section_id: 要注入清理结果的 section ID。
	## @param error_code: 下一次清理应返回的错误码。
	func queue_cleanup_error(section_id: StringName, error_code: Error) -> void:
		var errors: Array = []
		var existing_value: Variant = _scripted_errors.get(section_id)
		if existing_value is Array:
			errors = GFVariantData.as_array(existing_value)
		errors.append(error_code)
		_scripted_errors[section_id] = errors


	## @param section_id: 要切换外部占用状态的 section ID。
	## @param busy: 是否模拟该 section 被外部操作占用。
	func set_external_busy(section_id: StringName, busy: bool) -> void:
		if busy:
			_external_busy_sections[section_id] = true
			return
		var _erased: bool = _external_busy_sections.erase(section_id)
		cleanup_operation_settled.emit(&"test.external_owner")


	## @param section_id: 要查询待决清理的 section ID。
	func has_pending_cleanup(section_id: StringName) -> bool:
		return _pending_operations.has(section_id)


	## @param section_id: 要终止待决清理的 section ID。
	## @param error_code: 测试清理的最终错误码。
	func complete_pending_cleanup(
		section_id: StringName,
		error_code: Error = OK
	) -> void:
		var value: Variant = _pending_operations.get(section_id)
		if not value is ChunkProfileCleanupOperation:
			return
		var operation: ChunkProfileCleanupOperation = value
		var result: ChunkProfileCleanupResult = _make_cleanup_result(error_code)
		var _completed: bool = operation.complete_for_persistence(result)
		var _erased: bool = _pending_operations.erase(section_id)
		cleanup_operation_settled.emit(operation.get_operation_id())


	## @param section_id: 要统计清理调用次数的 section ID。
	func cleanup_call_count(section_id: StringName) -> int:
		var count: int = 0
		for called_section_id: StringName in cleanup_calls:
			if called_section_id == section_id:
				count += 1
		return count


	## @param _main_profile_id: 此测试桩不使用的主 Profile ID。
	## @param _main_file_name: 此测试桩不使用的主 Profile 文件名。
	## @param section_id: 要按脚本结果清理的派生 section ID。
	func cleanup_derived_family_async(
		_main_profile_id: StringName,
		_main_file_name: String,
		section_id: StringName
	) -> ChunkProfileCleanupOperation:
		cleanup_calls.append(section_id)
		if _external_busy_sections.has(section_id):
			return _make_test_terminal_cleanup_operation(
				ChunkProfileCleanupResult.STATUS_BUSY,
				ERR_BUSY
			)
		if _hang_next_sections.erase(section_id):
			var pending: ChunkProfileCleanupOperation = _make_cleanup_operation()
			_pending_operations[section_id] = pending
			return pending
		var error_code: Error = OK
		var errors_value: Variant = _scripted_errors.get(section_id)
		if errors_value is Array:
			var errors: Array = GFVariantData.as_array(errors_value)
			if not errors.is_empty():
				@warning_ignore("int_as_enum_without_cast")
				error_code = GFVariantData.to_int(errors.pop_front())
			if errors.is_empty():
				var _errors_erased: bool = _scripted_errors.erase(section_id)
			else:
				_scripted_errors[section_id] = errors
		return _make_test_terminal_cleanup_operation(
			(
				ChunkProfileCleanupResult.STATUS_CLEANED
				if error_code == OK
				else ChunkProfileCleanupResult.STATUS_PARTIAL_FAILURE
			),
			error_code
		)


	## @param main_profile_id: 要查询围栏的主 Profile ID。
	## @param main_file_name: 要查询围栏的主 Profile 文件名。
	## @param section_id: 要查询围栏的 section ID。
	func is_save_scope_fenced(
		main_profile_id: StringName,
		main_file_name: String,
		section_id: StringName
	) -> bool:
		return (
			_external_busy_sections.has(section_id)
			or super.is_save_scope_fenced(
				main_profile_id,
				main_file_name,
				section_id
			)
		)


	func _make_cleanup_operation() -> ChunkProfileCleanupOperation:
		var operation: ChunkProfileCleanupOperation = (
			ChunkProfileCleanupOperation.new()
		)
		var operation_id: StringName = StringName(
			"test.cleanup.%d" % _next_operation_serial
		)
		_next_operation_serial += 1
		var _configured: bool = operation.configure_for_persistence(
			operation_id
		)
		return operation


	func _make_test_terminal_cleanup_operation(
		status: StringName,
		error_code: Error
	) -> ChunkProfileCleanupOperation:
		var operation: ChunkProfileCleanupOperation = _make_cleanup_operation()
		var _completed: bool = operation.complete_for_persistence(
			_make_cleanup_result(error_code, status)
		)
		return operation


	func _make_cleanup_result(
		error_code: Error,
		status: StringName = &""
	) -> ChunkProfileCleanupResult:
		var effective_status: StringName = status
		if effective_status == &"":
			effective_status = (
				ChunkProfileCleanupResult.STATUS_CLEANED
				if error_code == OK
				else ChunkProfileCleanupResult.STATUS_PARTIAL_FAILURE
			)
		return ChunkProfileCleanupResult.create(
			effective_status,
			error_code,
			"" if error_code == OK else "Injected cleanup failure.",
			128,
			128 if error_code == OK else 127,
			0,
			0 if error_code == OK else 1,
			0,
			0
		)


class _ScriptedProfileDeleteStorage extends _RawFixtureStorage:
	var delete_calls: Array[String] = []
	var _timeout_file_name: String = ""
	var _known_failures: Dictionary = {}
	var _pending_operation: GFStorageAsyncOperation = null
	var _pending_result: GFStorageAsyncResult = null
	var _next_request_id: int = 7_000_000


	## @param profile_file_name: 下一次删除要保持待决的 Profile 文件名。
	func arm_timeout(profile_file_name: String) -> void:
		_timeout_file_name = profile_file_name


	## @param profile_file_name: 下一次删除要模拟失败的 Profile 文件名。
	## @param error_code: 注入删除结果的错误码。
	func arm_known_failure(
		profile_file_name: String,
		error_code: Error
	) -> void:
		_known_failures[profile_file_name] = error_code


	func has_pending_timeout() -> bool:
		return _pending_operation != null and _pending_operation.is_pending()


	func settle_timeout() -> void:
		if _pending_operation == null or _pending_result == null:
			return
		var _completed: bool = _pending_operation.complete_for_framework(
			_pending_result
		)
		_pending_operation = null
		_pending_result = null
		_timeout_file_name = ""


	## @param file_name: 要按脚本结果删除的测试文件名。
	## @param options: 可选的异步删除请求选项。
	func delete_file_request_async(
		file_name: String,
		options: GFStorageAsyncRequestOptions = null
	) -> GFStorageAsyncOperation:
		delete_calls.append(file_name)
		if file_name == _timeout_file_name:
			var physical_error: Error = super.delete_file(file_name)
			var timeout_operation: GFStorageAsyncOperation = (
				_make_delete_operation(file_name, physical_error)
			)
			var effective_options: GFStorageAsyncRequestOptions = (
				options
				if options != null
				else GFStorageAsyncRequestOptions.create(self)
			)
			var _consumer_configured: bool = (
				timeout_operation.configure_consumer_for_framework(
					timeout_operation.get_request_id(),
					effective_options,
					GFClock.new(),
					Callable(self, &"_accept_test_delete_cancel")
				)
			)
			var _accepted: bool = (
				timeout_operation.mark_worker_accepted_for_framework()
			)
			var _caller_completed: bool = (
				timeout_operation.complete_caller_for_framework(
					GFStorageAsyncCallerResult.Status.OUTCOME_UNKNOWN,
					GFStorageAsyncCallerResult.EndKind.DEADLINE_EXPIRED,
					&"deadline_expired"
				)
			)
			_pending_operation = timeout_operation
			_pending_result = _make_test_delete_async_result(
				timeout_operation,
				physical_error
			)
			return timeout_operation
		if _known_failures.has(file_name):
			@warning_ignore("int_as_enum_without_cast")
			var error_code: Error = GFVariantData.get_option_int(
				_known_failures,
				file_name,
				ERR_CANT_CREATE
			)
			var _failure_erased: bool = _known_failures.erase(file_name)
			var failed_operation: GFStorageAsyncOperation = (
				_make_delete_operation(file_name, error_code)
			)
			var _failed_completed: bool = failed_operation.complete_for_framework(
				_make_test_delete_async_result(failed_operation, error_code)
			)
			return failed_operation
		return super.delete_file_request_async(file_name, options)


	func _make_delete_operation(
		file_name: String,
		_error_code: Error
	) -> GFStorageAsyncOperation:
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_request_id
		_next_request_id += 1
		var _configured: bool = operation.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_DELETE,
			file_name
		)
		return operation


	func _make_test_delete_async_result(
		operation: GFStorageAsyncOperation,
		error_code: Error
	) -> GFStorageAsyncResult:
		var delete_result: GFStorageDeleteResult = GFStorageDeleteResult.new()
		var failure_kind: GFStorageDeleteResult.FailureKind = (
			GFStorageDeleteResult.FailureKind.NONE
			if error_code == OK
			else (
				GFStorageDeleteResult.FailureKind.NOT_FOUND
				if error_code == ERR_FILE_NOT_FOUND
				else GFStorageDeleteResult.FailureKind.IO_FAILED
			)
		)
		var _delete_configured: bool = delete_result.configure_for_framework(
			error_code,
			failure_kind,
			1 if error_code == OK else 0,
			1 if error_code == OK else 0,
			0,
			(
				GFStorageDeleteResult.FamilyMember.NONE
				if error_code in [OK, ERR_FILE_NOT_FOUND]
				else GFStorageDeleteResult.FamilyMember.FAMILY_METADATA
			)
		)
		var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
		var _configured: bool = result.configure_for_framework(
			operation.get_request_id(),
			GFStorageAsyncOperation.OPERATION_DELETE,
			operation.get_file_name(),
			error_code == OK,
			error_code,
			null,
			GFStorageAsyncResult.WriteFailureKind.NONE,
			{},
			delete_result
		)
		return result


	func _accept_test_delete_cancel(
		_operation: GFStorageAsyncOperation,
		_end_kind: int,
		_reason: StringName
	) -> bool:
		return true


class _RetryStorage extends GFStorageUtility:
	var profile_save_errors: Array[Error] = []
	var profile_save_attempt_count: int = 0
	var _next_request_id: int = 2_000_000


	## 按队列为 Profile opaque payload 写入注入可重试错误。
	## @param file_name: GFStorage 相对文件名。
	## @param transfer: 此 generation 的单所有者 payload transfer。
	## @param options: 可选的异步请求选项。
	func save_payload_request_async(
		file_name: String,
		transfer: GFStoragePayloadTransfer,
		options: GFStorageAsyncRequestOptions = null
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
		return super.save_payload_request_async(file_name, transfer, options)


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
	## @param options: 可选的异步请求选项。
	func load_data_request_async(
		file_name: String,
		options: GFStorageAsyncRequestOptions = null
	) -> GFStorageAsyncOperation:
		if not hang_profile_reads:
			return super.load_data_request_async(file_name, options)
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
	## @param options: 可选的异步请求选项。
	func save_payload_request_async(
		file_name: String,
		transfer: GFStoragePayloadTransfer,
		options: GFStorageAsyncRequestOptions = null
	) -> GFStorageAsyncOperation:
		if (
			not hang_profile_writes
			or (
				file_name != GameSaveGraphUtility.PROFILE_FILE_NAME
				and file_name.get_base_dir()
				!= LocalAccountCatalogUtility.PROFILE_DIRECTORY
			)
		):
			return super.save_payload_request_async(file_name, transfer, options)
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
				error_code,
				null,
				(
					GFStorageAsyncResult.WriteFailureKind.NONE
					if error_code == OK
					else GFStorageAsyncResult.WriteFailureKind.IO_FAILED
				)
			)
			assert(
				_result_configured,
				"测试故障注入必须构造符合 GFStorage 写入终态契约的结果。"
			)
			var _completed: bool = operation.complete_for_framework(result)
			assert(
				_completed,
				"测试故障注入必须完成唯一物理终态。"
			)


# --- 内部类 ---
