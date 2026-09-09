## 验证离开对局时自动续玩的等待、失败恢复和过期异步终态边界。
extends "res://tests/gut/support/gf_test_case.gd"


# --- 测试用例 ---

func test_return_waits_for_persistence_and_settlement_and_blocks_repeated_actions() -> void:
	var flow: ResumeFlowSpy = _make_flow()
	flow.hold_settlement = true
	await _begin_return(flow)
	assert_true(flow.bookmarks.request_count == 1)
	assert_true(flow.pause_spy.paused and flow._return_to_menu_in_progress)
	assert_true(flow.router.return_to_main_menu_count == 0)
	flow._on_resume_game_requested()
	flow._on_restart_game_requested()
	await _begin_return(flow)
	assert_true(flow.bookmarks.request_count == 1, "等待写盘时重复返回不能提交第二次续玩。")
	assert_true(flow.pause_spy.resume_count == 0 and flow.restart_count == 0)
	assert_true(flow.bookmarks.complete_pending(GameSaveSectionResult.STATUS_PERSISTED))
	await get_tree().process_frame
	assert_true(flow.settlement_count == 1)
	assert_true(flow.router.return_to_main_menu_count == 0 and flow.pause_spy.paused, "即时终态后仍须等待权威 settlement。")
	flow.settlement_released.emit(GameSaveSectionSettlementResult.from_section_result(flow.bookmarks.pending.get_result()))
	await get_tree().process_frame
	assert_true(flow.router.return_to_main_menu_count == 1)
	assert_true(flow.pause_spy.resume_count == 1 and not flow.pause_spy.paused)
	assert_false(flow._return_to_menu_in_progress)


func test_failed_resume_save_keeps_board_and_resumes_game_without_routing() -> void:
	var flow: ResumeFlowSpy = _make_flow()
	var original_board: Dictionary = flow._grid_model.get_snapshot()
	var original_actions: Array[Vector2i] = flow._player_actions.duplicate()
	await _begin_return(flow)
	assert_true(flow.bookmarks.complete_pending(GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK))
	await get_tree().process_frame
	assert_true(flow.router.return_to_main_menu_count == 0)
	assert_true(flow.pause_spy.resume_count == 1 and not flow.pause_spy.paused)
	assert_false(flow._return_to_menu_in_progress)
	assert_true(flow._grid_model.get_snapshot() == original_board)
	assert_true(flow._player_actions == original_actions)
	assert_true(flow.notification_keys.has("gameplay.resume_save_failed"))
	await _begin_return(flow)
	assert_true(flow.bookmarks.request_count == 2, "失败后玩家可以重试保存并返回。")
	assert_true(flow.bookmarks.complete_pending(GameSaveSectionResult.STATUS_PERSISTED))
	await get_tree().process_frame
	assert_true(flow.router.return_to_main_menu_count == 1)


func test_stale_operation_completion_cannot_route_or_change_new_session() -> void:
	var flow: ResumeFlowSpy = _make_flow()
	await _begin_return(flow)
	_mark_new_session(flow)
	assert_true(flow.bookmarks.complete_pending(GameSaveSectionResult.STATUS_PERSISTED))
	await get_tree().process_frame
	_assert_new_session_untouched(flow)
	assert_true(flow.settlement_count == 0, "过期的首次终态不得创建后续等待者。")


func test_stale_settlement_cannot_route_or_change_new_session() -> void:
	var flow: ResumeFlowSpy = _make_flow()
	flow.hold_settlement = true
	await _begin_return(flow)
	assert_true(flow.bookmarks.complete_pending(GameSaveSectionResult.STATUS_PERSISTED))
	await get_tree().process_frame
	assert_true(flow.settlement_count == 1)
	_mark_new_session(flow)
	flow.settlement_released.emit(GameSaveSectionSettlementResult.from_section_result(flow.bookmarks.pending.get_result()))
	await get_tree().process_frame
	_assert_new_session_untouched(flow)


func test_replay_tainted_and_inactive_sessions_return_without_overwriting_resume() -> void:
	for case_index: int in range(3):
		var flow: ResumeFlowSpy = _make_flow()
		match case_index:
			0:
				flow._is_replay_mode = true
			1:
				flow._is_game_state_tainted = true
			2:
				flow._fsm.dispose()
				flow._fsm = null
		await _begin_return(flow)
		assert_true(flow.bookmarks.request_count == 0)
		assert_true(flow.router.return_to_main_menu_count == 1)
		assert_false(flow._return_to_menu_in_progress)


# --- 私有/辅助方法 ---

func _make_flow() -> ResumeFlowSpy:
	var flow: ResumeFlowSpy = ResumeFlowSpy.new()
	flow.bookmarks = PendingResumeBookmarks.new()
	flow.pause_spy = PauseSpy.new()
	flow.router = TestSceneRouterSystemSpy.new()
	var grid: GridModel = GridModel.new()
	grid.topology = BoardTopology.create_rectangle(Vector2i(2, 1))
	flow.configure_dependencies(grid, null, null, null, flow.pause_spy, null, null, flow.router)
	flow._fsm = GFStateMachine.new(flow)
	flow._fsm.current_state_name = EventNames.STATE_PLAYING
	flow._persistence_epoch = 7
	flow._persistence_owner_active = true
	flow._player_actions = [Vector2i.LEFT, Vector2i.DOWN]
	track_gf_system(flow)
	track_gf_system(flow.bookmarks)
	track_gf_system(flow.router)
	return flow


func _begin_return(flow: ResumeFlowSpy) -> void:
	@warning_ignore("return_value_discarded")
	flow._on_return_to_main_menu_from_game.call_deferred()
	await get_tree().process_frame
	await get_tree().process_frame


func _mark_new_session(flow: ResumeFlowSpy) -> void:
	flow._persistence_epoch += 1
	flow._return_to_menu_in_progress = true
	flow._target_reached_modal_active = true
	flow.pause_spy.paused = true
	flow._player_actions = [Vector2i.UP]


func _assert_new_session_untouched(flow: ResumeFlowSpy) -> void:
	assert_true(flow.router.return_to_main_menu_count == 0)
	assert_true(flow.pause_spy.resume_count == 0 and flow.pause_spy.paused)
	assert_true(flow._return_to_menu_in_progress and flow._target_reached_modal_active)
	assert_true(flow._player_actions == [Vector2i.UP])
	assert_false(flow.notification_keys.has("gameplay.resume_save_failed"))


# --- 内部类 ---

class ResumeFlowSpy extends TestGameFlowSystemSpy:
	signal settlement_released(outcome: GameSaveSectionSettlementResult)

	var bookmarks: PendingResumeBookmarks = null
	var pause_spy: PauseSpy = null
	var router: TestSceneRouterSystemSpy = null
	var notification_keys: Array[String] = []
	var hold_settlement: bool = false
	var settlement_count: int = 0


	func _get_bookmark_system() -> BookmarkSystem:
		return bookmarks


	func _get_bookmark_comparison_state() -> Dictionary:
		return _grid_model.get_snapshot()


	func _make_current_bookmark(current_state_for_comparison: Dictionary) -> BookmarkData:
		var bookmark: BookmarkData = BookmarkData.new()
		bookmark.board_snapshot = current_state_for_comparison.duplicate(true)
		bookmark.score = 2048
		return bookmark


	func _await_section_operation_settlement(
		_operation: GameSaveSectionOperation,
		observed_result: GameSaveSectionResult = null
	) -> GameSaveSectionSettlementResult:
		settlement_count += 1
		if hold_settlement:
			var outcome: GameSaveSectionSettlementResult = await settlement_released
			return outcome
		return GameSaveSectionSettlementResult.from_section_result(observed_result)


	func _push_gameplay_notification(
		_message: String,
		_duration_seconds: float,
		_level: GFNotificationUtility.Level,
		key: String,
		_priority: int = -1
	) -> void:
		notification_keys.append(key)


class PauseSpy extends GamePauseUtility:
	var paused: bool = false
	var pause_count: int = 0
	var resume_count: int = 0


	func pause() -> bool:
		pause_count += 1
		paused = true
		return true


	func resume() -> bool:
		resume_count += 1
		paused = false
		return true


class PendingResumeBookmarks extends BookmarkSystem:
	var request_count: int = 0
	var pending: GameSaveSectionOperation = null


	## 创建由测试控制完成时刻的续玩保存操作。
	## @param _bookmark_data: 当前用例提交的冻结书签。
	func request_save_resume_game(_bookmark_data: BookmarkData) -> GameSaveSectionOperation:
		request_count += 1
		pending = GameSaveSectionOperation.new()
		var _configured: bool = pending.configure_for_utility(
			request_count, &"test.profile", PackedStringArray([String(RESUME_SECTION_ID)])
		)
		return pending


	## 使用指定持久化结果完成当前待处理操作。
	## @param status: GameSaveSectionResult 终态标识。
	func complete_pending(status: StringName) -> bool:
		if pending == null or not pending.is_pending():
			return false
		var result: GameSaveSectionResult = GameSaveSectionResult.new()
		var _configured: bool = result.configure_for_utility(
			pending.get_transaction_id(), pending.get_profile_id(), pending.get_section_ids(),
			status, OK if status == GameSaveSectionResult.STATUS_PERSISTED else ERR_CANT_CREATE,
			true, status == GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK
		)
		return pending.complete_for_utility(result)
