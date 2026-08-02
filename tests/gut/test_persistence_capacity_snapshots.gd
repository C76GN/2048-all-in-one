## 验证玩家目录容量、防御上限与 GF 协作式 section 快照。
extends GutTest


func test_bookmark_catalog_keeps_newest_product_window_and_rejects_absolute_overflow() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var migration_items: Array[Dictionary] = []
	for index: int in range(32):
		migration_items.append(_make_bookmark(index).to_dict())

	assert_true(
		provider.replace_section_data({&"items": migration_items}) == OK,
		"同 schema 的旧目录可在绝对防御上限内安全收敛。"
	)
	var retained: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		&"items"
	)
	assert_true(
		retained.size() == BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
	)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(retained[0]),
			&"bookmark_id"
		) == GFVariantData.get_option_string(
			migration_items[-1],
			&"bookmark_id"
		),
		"容量迁移必须按 UUID v7 保留最新书签。"
	)

	var oversized_items: Array = []
	assert_true(
		oversized_items.resize(
			BookmarkCatalogSaveData.ABSOLUTE_MAX_BOOKMARK_COUNT + 1
		) == OK
	)
	assert_true(
		provider.replace_section_data({&"items": oversized_items})
		== ERR_INVALID_DATA,
		"超过 provider 绝对数量防御的目录必须在逐项解码前拒绝。"
	)
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			&"items"
		).size() == BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT,
		"非法超限候选不得改变已应用目录。"
	)


func test_bookmark_payload_bounds_cover_history_and_board_size() -> void:
	var bookmark: BookmarkData = _make_bookmark(500)
	var payload: Dictionary = bookmark.to_dict()
	var history_envelope: Dictionary = GFVariantData.get_option_dictionary(
		payload,
		&"game_state_history"
	).duplicate(true)
	var oversized_history: PackedByteArray = PackedByteArray()
	assert_true(
		oversized_history.resize(
			BookmarkData.MAX_HISTORY_PAYLOAD_BYTES + 1
		) == OK
	)
	history_envelope[&"payload"] = oversized_history
	payload[&"game_state_history"] = history_envelope
	assert_false(
		BookmarkData.is_persisted_envelope_lightweight_valid(payload),
		"单书签历史不得侵占 GFStorage 整体 payload 预算。"
	)

	var oversized_board: BookmarkData = _make_bookmark(501)
	var topology: BoardTopology = BoardTopology.create_rectangle(
		Vector2i(17, 16)
	)
	oversized_board.board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	assert_null(
		BookmarkData.from_dict(oversized_board.to_dict()),
		"书签不得持久化超过 256 格的命令状态边界。"
	)


func test_custom_board_catalog_keeps_newest_and_enforces_absolute_cap() -> void:
	var provider: CustomBoardCatalogSaveData = (
		CustomBoardCatalogSaveData.new()
	)
	var migration_items: Array[Dictionary] = []
	for index: int in range(80):
		migration_items.append(_make_custom_board(index).to_dict())
	assert_true(
		provider.replace_section_data({&"items": migration_items}) == OK
	)
	var retained: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		&"items"
	)
	assert_true(
		retained.size()
		== CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	)
	assert_true(
		GFVariantData.get_option_int(
			GFVariantData.as_dictionary(retained[0]),
			&"updated_at"
		) == GFVariantData.get_option_int(
			migration_items[-1],
			&"updated_at"
		),
		"自定义棋盘容量迁移必须保留最近更新项。"
	)

	var oversized_items: Array = []
	assert_true(
		oversized_items.resize(
			CustomBoardCatalogSaveData.ABSOLUTE_MAX_CUSTOM_BOARD_COUNT + 1
		) == OK
	)
	assert_true(
		provider.replace_section_data({&"items": oversized_items})
		== ERR_INVALID_DATA
	)
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			&"items"
		).size() == CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	)


func test_full_catalog_insert_pins_new_candidate_before_eviction() -> void:
	var bookmark_envelopes: Array[Dictionary] = []
	for index: int in range(BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT):
		bookmark_envelopes.append({
			&"bookmark_id": "existing-%02d" % index,
		})
	var bookmark_candidate: Dictionary = {
		&"bookmark_id": "candidate-sorts-last",
	}
	assert_true(
		BookmarkSystem._insert_new_bookmark_at_capacity(
			bookmark_envelopes,
			bookmark_candidate
		)
	)
	assert_true(
		bookmark_envelopes.size()
		== BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
	)
	assert_true(
		bookmark_envelopes.has(bookmark_candidate),
		"满容量保存必须保留本次候选，不能让排序尾部把它静默丢弃。"
	)

	var boards: Array[CustomBoardData] = []
	for index: int in range(
		CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	):
		var board: CustomBoardData = _make_custom_board(index + 1000)
		board.updated_at = 5000
		board.custom_board_id = "existing-%02d" % index
		boards.append(board)
	var board_candidate: CustomBoardData = _make_custom_board(2000)
	board_candidate.updated_at = 5000
	board_candidate.custom_board_id = "candidate-sorts-last"
	assert_true(
		CustomBoardSystem._insert_new_board_at_capacity(
			boards,
			board_candidate
		)
	)
	assert_true(
		boards.size() == CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	)
	assert_true(
		boards.has(board_candidate),
		"同秒自定义棋盘保存也必须固定保留新候选。"
	)


func test_custom_board_rejects_topology_above_persisted_cell_budget() -> void:
	var board: CustomBoardData = _make_custom_board(800)
	board.topology = BoardTopology.create_rectangle(
		Vector2i(17, 16),
		CustomBoardData.get_topology_id(board.custom_board_id)
	)
	assert_null(
		CustomBoardData.from_dict(board.to_dict()),
		"自定义棋盘 provider 必须在通用拓扑深校验前执行 256 格防御。"
	)
	var provider: CustomBoardCatalogSaveData = (
		CustomBoardCatalogSaveData.new()
	)
	assert_true(
		provider.replace_section_data({&"items": [board.to_dict()]})
		== ERR_INVALID_DATA,
		"Provider 必须在基类递归复制攻击者拓扑前执行相同边界。"
	)


func test_large_sections_prepare_snapshots_incrementally() -> void:
	var bookmark_provider: BookmarkCatalogSaveData = (
		BookmarkCatalogSaveData.new()
	)
	var bookmark_items: Array[Dictionary] = []
	for index: int in range(BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT):
		bookmark_items.append(_make_bookmark(index + 200).to_dict())
	assert_true(
		bookmark_provider.replace_section_data({&"items": bookmark_items})
		== OK
	)
	_assert_incremental_snapshot_item_count(
		bookmark_provider,
		BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
	)

	var board_provider: CustomBoardCatalogSaveData = (
		CustomBoardCatalogSaveData.new()
	)
	var board_items: Array[Dictionary] = []
	for index: int in range(
		CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	):
		board_items.append(_make_custom_board(index + 200).to_dict())
	assert_true(
		board_provider.replace_section_data({&"items": board_items}) == OK
	)
	_assert_incremental_snapshot_item_count(
		board_provider,
		CustomBoardCatalogSaveData.MAX_CUSTOM_BOARD_COUNT
	)

	var progress_provider: GameStatsSaveData = GameStatsSaveData.new()
	var stats: Dictionary = {}
	for index: int in range(GameStatsSaveData.MAX_STATS_MODE_COUNT):
		stats["mode_%03d" % index] = {
			"board": {&"plays": index},
		}
	assert_true(
		progress_provider.replace_section_data({
			&"stats": stats,
			&"results": [],
			&"leaderboards": {},
		}) == OK
	)
	var progress_operation: GFSaveSectionSnapshotOperation = (
		progress_provider.begin_save_snapshot({&"reason": "near_limit"})
	)
	assert_not_null(progress_operation)
	if progress_operation == null:
		return
	var _first_progress_unit: int = (
		progress_operation.advance_for_framework(1)
	)
	assert_true(
		progress_operation.is_pending(),
		"接近上限的 progress 快照不得在 begin 或单个 work unit 内同步完成。"
	)
	_drain_snapshot(progress_operation)
	var progress_snapshot: GFSaveSectionSnapshot = (
		progress_operation.take_snapshot_for_framework()
	)
	assert_not_null(progress_snapshot)
	if progress_snapshot != null:
		var record: Dictionary = progress_snapshot.claim_for_framework()
		assert_true(
			GFVariantData.get_option_dictionary(
				GFVariantData.get_option_dictionary(record, &"payload"),
				&"stats"
			).size() == GameStatsSaveData.MAX_STATS_MODE_COUNT
		)


func test_progress_snapshot_preserves_legacy_variants_and_freezes_request_root() -> void:
	var provider: GameStatsSaveData = GameStatsSaveData.new()
	var requested_stats: Dictionary = {
		"legacy_scalar_mode": 17,
		"classic": {
			&"legacy_flag": true,
			&"legacy_list": [1, 2, 3],
		},
	}
	assert_true(
		provider.replace_section_data({
			&"stats": requested_stats,
			&"results": [],
			&"leaderboards": {},
		}) == OK
	)
	var operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "freeze_request_root"})
	)
	assert_not_null(operation)
	if operation == null:
		return

	# begin 之后替换 provider 根状态，进行中的 snapshot 仍必须对应请求时刻。
	assert_true(
		provider.replace_section_data({
			&"stats": {"replacement": 99},
			&"results": [],
			&"leaderboards": {},
		}) == OK
	)
	_drain_snapshot(operation)
	var snapshot: GFSaveSectionSnapshot = (
		operation.take_snapshot_for_framework()
	)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var payload: Dictionary = GFVariantData.get_option_dictionary(
		record,
		&"payload"
	)
	assert_true(
		GFVariantData.get_option_dictionary(payload, &"stats")
		== requested_stats,
		"协作快照必须保留历史标量/容器叶，并冻结 begin 时的 progress 根。"
	)


func test_bookmark_snapshot_freezes_old_root_without_eager_catalog_copy() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var requested_items: Array[Dictionary] = [
		_make_bookmark(910).to_dict(),
		_make_bookmark(911).to_dict(),
	]
	assert_true(
		provider.replace_section_data({&"items": requested_items}) == OK
	)
	var operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "freeze_bookmark_root"})
	)
	assert_not_null(operation)
	if operation == null:
		return

	var replacement_items: Array[Dictionary] = [
		_make_bookmark(912).to_dict(),
	]
	assert_true(
		provider.replace_section_data({&"items": replacement_items}) == OK
	)
	_drain_snapshot(operation)
	var snapshot: GFSaveSectionSnapshot = (
		operation.take_snapshot_for_framework()
	)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var payload_items: Array = GFVariantData.get_option_array(
		GFVariantData.get_option_dictionary(record, &"payload"),
		&"items"
	)
	assert_true(payload_items.size() == requested_items.size())
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(payload_items[0]),
			&"bookmark_id"
		) == GFVariantData.get_option_string(
			requested_items[1],
			&"bookmark_id"
		),
		"替换 provider 根状态后，进行中的书签快照仍须保留请求时刻的旧根。"
	)


func test_bookmark_snapshot_cancel_and_claim_do_not_alias_provider_state() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var requested_envelope: Dictionary = _make_bookmark(915).to_dict()
	assert_true(
		provider.replace_section_data({&"items": [requested_envelope]}) == OK
	)

	var cancelled_operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "cancel_isolation"})
	)
	assert_not_null(cancelled_operation)
	if cancelled_operation == null:
		return
	assert_true(cancelled_operation.cancel_for_framework())
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			&"items"
		).size() == 1,
		"取消 Operation 只能清空自己的工作根，不能清空 provider 目录。"
	)

	var completed_operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "claim_isolation"})
	)
	_drain_snapshot(completed_operation)
	var snapshot: GFSaveSectionSnapshot = (
		completed_operation.take_snapshot_for_framework()
	)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var claimed_payload_root: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(record, &"payload")
	)
	var claimed_items: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(claimed_payload_root, &"items")
	)
	var claimed_envelope: Dictionary = GFVariantData.as_dictionary(
		claimed_items[0]
	)
	var claimed_board: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(claimed_envelope, &"board_snapshot")
	)
	claimed_board[&"snapshot_claim_mutation"] = true
	var claimed_history: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(claimed_envelope, &"game_state_history")
	)
	var provider_payload_before: PackedByteArray = GFVariantData.get_option_value(
		GFVariantData.get_option_dictionary(
			GFVariantData.as_dictionary(
				GFVariantData.get_option_array(
					provider.get_section_data(),
					&"items"
				)[0]
			),
			&"game_state_history"
		),
		&"payload"
	)
	var provider_payload_before_hex: String = provider_payload_before.hex_encode()
	var claimed_payload: PackedByteArray = GFVariantData.get_option_value(
		claimed_history,
		&"payload"
	)
	assert_false(claimed_payload.is_empty())
	if not claimed_payload.is_empty():
		claimed_payload[0] = (claimed_payload[0] + 1) % 256
		claimed_history[&"payload"] = claimed_payload
	var provider_items: Array = GFVariantData.get_option_array(
		provider.get_section_data(),
		&"items"
	)
	var provider_board: Dictionary = GFVariantData.get_option_dictionary(
		GFVariantData.as_dictionary(provider_items[0]),
		&"board_snapshot"
	)
	var provider_history: Dictionary = GFVariantData.get_option_dictionary(
		GFVariantData.as_dictionary(provider_items[0]),
		&"game_state_history"
	)
	var provider_payload: PackedByteArray = GFVariantData.get_option_value(
		provider_history,
		&"payload"
	)
	assert_false(
		provider_board.has(&"snapshot_claim_mutation"),
		"take_ownership Snapshot 的嵌套字典不得别名到 provider 权威状态。"
	)
	assert_true(
		provider_payload.hex_encode() == provider_payload_before_hex,
		"Snapshot 的 PackedByteArray 也必须显式复制后再移交所有权。"
	)


func test_bookmark_immutable_candidate_can_be_handed_off_once() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var owned_items: Array[Dictionary] = [_make_bookmark(920).to_dict()]
	var owned_section: Dictionary = {&"items": owned_items}
	assert_true(
		provider.replace_section_data_taking_ownership(owned_section) == OK
	)
	# move 契约要求调用方只重新绑定局部变量，不能 clear 已移交容器。
	owned_items = []
	owned_section = {}

	var first_candidate: Dictionary = provider.make_immutable_edit_candidate()
	var second_candidate: Dictionary = provider.make_immutable_edit_candidate()
	var first_items: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(first_candidate, &"items")
	)
	var second_items: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(second_candidate, &"items")
	)
	assert_true(first_items.size() == 1 and second_items.size() == 1)
	assert_true(
		is_same(first_items[0], second_items[0]),
		"只读编辑候选应复用 provider 内不可变 envelope，仅复制可重排的数组根。"
	)
	first_items = []
	second_items = []
	first_candidate = {}
	second_candidate = {}
	assert_true(
		GFVariantData.get_option_array(
			provider.get_section_data(),
			&"items"
		).size() == 1,
		"调用方放弃只读候选根不得改变 provider 权威状态。"
	)


func test_bookmark_transaction_rollback_candidate_freezes_old_root() -> void:
	var provider: BookmarkCatalogSaveData = BookmarkCatalogSaveData.new()
	var old_bookmark: BookmarkData = _make_bookmark(930)
	assert_true(
		provider.replace_section_data({
			&"items": [old_bookmark.to_dict()],
		}) == OK
	)
	var rollback_candidate: Dictionary = (
		provider.make_transaction_rollback_candidate()
	)
	var new_bookmark: BookmarkData = _make_bookmark(931)
	var owned_replacement: Dictionary = {
		&"items": [new_bookmark.to_dict()],
	}
	assert_true(
		provider.replace_section_data_taking_ownership(owned_replacement)
		== OK
	)
	owned_replacement = {}

	var rollback_data: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(rollback_candidate, &"data")
	)
	var rollback_items: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(rollback_data, &"items")
	)
	assert_true(rollback_items.size() == 1)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(rollback_items[0]),
			&"bookmark_id"
		) == old_bookmark.bookmark_id,
		"provider 替换根后，事务回滚候选必须仍指向请求前不可变 envelope。"
	)
	assert_true(provider.replace_from_dict(rollback_candidate) == OK)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(
				GFVariantData.get_option_array(
					provider.get_section_data(),
					&"items"
				)[0]
			),
			&"bookmark_id"
		) == old_bookmark.bookmark_id,
		"真正失败路径消费候选时必须可恢复旧 provider 状态。"
	)


func test_progress_rejects_oversized_packed_bytes_before_ownership_copy() -> void:
	var provider: GameStatsSaveData = GameStatsSaveData.new()
	var oversized_bytes: PackedByteArray = PackedByteArray()
	assert_true(
		oversized_bytes.resize(
			GameStatsSaveData.MAX_PACKED_BYTE_ARRAY_BYTES + 1
		) == OK
	)
	assert_true(
		provider.replace_section_data({
			&"stats": {
				"classic": {&"legacy_blob": oversized_bytes},
			},
			&"results": [],
			&"leaderboards": {},
		}) == ERR_INVALID_DATA,
		"单个 work unit 不得接收会造成大型同步复制的 PackedByteArray。"
	)
	assert_true(
		GFVariantData.get_option_dictionary(
			provider.get_section_data(),
			&"stats"
		).is_empty(),
		"边界拒绝不得改变 progress provider。"
	)


func test_progress_rejects_excessive_nested_value_before_snapshot() -> void:
	var provider: GameStatsSaveData = GameStatsSaveData.new()
	var nested_value: Variant = 1
	for _depth: int in range(
		GameStatsSaveData.MAX_PERSISTED_VALUE_DEPTH + 1
	):
		nested_value = {&"next": nested_value}
	assert_true(
		provider.replace_section_data({
			&"stats": {"classic": nested_value},
			&"results": [],
			&"leaderboards": {},
		}) == ERR_INVALID_DATA,
		"深度超限的历史自由值必须在递归复制前拒绝。"
	)


func test_progress_snapshot_accepts_bounded_packed_bytes_and_isolates_them() -> void:
	var provider: GameStatsSaveData = GameStatsSaveData.new()
	var bounded_bytes: PackedByteArray = PackedByteArray()
	assert_true(
		bounded_bytes.resize(GameStatsSaveData.MAX_PACKED_BYTE_ARRAY_BYTES)
		== OK
	)
	bounded_bytes[0] = 7
	assert_true(
		provider.replace_section_data({
			&"stats": {
				"classic": {&"legacy_blob": bounded_bytes},
			},
			&"results": [],
			&"leaderboards": {},
		}) == OK
	)
	var operation: GFSaveSectionSnapshotOperation = (
		provider.begin_save_snapshot({&"reason": "bounded_bytes"})
	)
	assert_not_null(operation)
	if operation == null:
		return
	bounded_bytes[0] = 9
	_drain_snapshot(operation)
	var snapshot: GFSaveSectionSnapshot = (
		operation.take_snapshot_for_framework()
	)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var payload: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(record, &"payload")
	)
	var stats: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(payload, &"stats")
	)
	var classic: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(stats, "classic")
	)
	var snapshot_bytes: PackedByteArray = GFVariantData.get_option_value(
		classic,
		&"legacy_blob"
	)
	assert_true(snapshot_bytes.size() == bounded_bytes.size())
	assert_true(
		snapshot_bytes[0] == 7,
		"provider 必须在应用时隔离调用方字节数组，快照不得观察外部后续修改。"
	)
	var provider_root_before: Dictionary = provider.get_section_data()
	var provider_stats_before: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_root_before, &"stats")
	)
	var provider_classic_before: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_stats_before, "classic")
	)
	var provider_bytes_before: PackedByteArray = GFVariantData.get_option_value(
		provider_classic_before,
		&"legacy_blob"
	)
	var provider_bytes_before_hex: String = provider_bytes_before.hex_encode()
	if not snapshot_bytes.is_empty():
		snapshot_bytes[0] = (snapshot_bytes[0] + 1) % 256
		classic[&"legacy_blob"] = snapshot_bytes
	var provider_root_after: Dictionary = provider.get_section_data()
	var provider_stats_after: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_root_after, &"stats")
	)
	var provider_classic_after: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_stats_after, "classic")
	)
	var provider_bytes_after: PackedByteArray = GFVariantData.get_option_value(
		provider_classic_after,
		&"legacy_blob"
	)
	assert_true(
		provider_bytes_after.hex_encode() == provider_bytes_before_hex,
		"Snapshot 所有权载荷中的 PackedByteArray 不得反向别名到 provider。"
	)
	provider_bytes_after[0] = (provider_bytes_after[0] + 1) % 256
	provider_classic_after[&"legacy_blob"] = provider_bytes_after
	var provider_root_final: Dictionary = provider.get_section_data()
	var provider_stats_final: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_root_final, &"stats")
	)
	var provider_classic_final: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(provider_stats_final, "classic")
	)
	var provider_bytes_final: PackedByteArray = GFVariantData.get_option_value(
		provider_classic_final,
		&"legacy_blob"
	)
	assert_true(
		provider_bytes_final.hex_encode() == provider_bytes_before_hex,
		"get_section_data() 返回值中的 PackedByteArray 不得反向修改 provider。"
	)


# --- 私有/辅助方法 ---

func _assert_incremental_snapshot_item_count(
	provider: GameSaveSectionData,
	expected_count: int
) -> void:
	var operation: GFSaveSectionSnapshotOperation = provider.begin_save_snapshot(
		{&"reason": "near_limit"}
	)
	assert_not_null(operation)
	if operation == null:
		return
	var _first_unit: int = operation.advance_for_framework(1)
	assert_true(
		operation.is_pending(),
		"接近目录上限的 provider 必须按条目分片准备 snapshot。"
	)
	_drain_snapshot(operation)
	var snapshot: GFSaveSectionSnapshot = (
		operation.take_snapshot_for_framework()
	)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var record: Dictionary = snapshot.claim_for_framework()
	var payload: Dictionary = GFVariantData.get_option_dictionary(
		record,
		&"payload"
	)
	assert_true(
		GFVariantData.get_option_array(payload, &"items").size()
		== expected_count
	)


func _drain_snapshot(operation: GFSaveSectionSnapshotOperation) -> void:
	for _step: int in range(1024):
		if not operation.is_pending():
			break
		var _consumed: int = operation.advance_for_framework(1)
	assert_true(operation.is_successful())


func _make_bookmark(index: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = index + 1
	bookmark.bookmark_id = GFUuid.generate_v7(
		bookmark.timestamp * 1000
	)
	bookmark.mode_config_path = (
		"res://features/gameplay/resources/modes/classic_mode_config.tres"
	)
	var mode_value: Resource = load(bookmark.mode_config_path)
	assert_true(mode_value is GameModeConfig)
	if mode_value is GameModeConfig:
		var mode: GameModeConfig = mode_value
		bookmark.ruleset_id = mode.ruleset_id
		bookmark.ruleset_version = mode.ruleset_version
		bookmark.ruleset_fingerprint = (
			GameDeterminismUtility.new().calculate_ruleset_fingerprint(mode)
		)
		bookmark.rules_states = RuleSystem.capture_rule_states(
			mode.spawn_rules
		)
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	bookmark.initial_seed = 2048
	bookmark.rng_full_state = seed_utility.get_full_state()
	var topology: BoardTopology = BoardTopology.create_rectangle(
		Vector2i(4, 4)
	)
	bookmark.board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	bookmark.game_state_history = {&"undo": [], &"redo": []}
	return bookmark


func _make_custom_board(index: int) -> CustomBoardData:
	var board: CustomBoardData = CustomBoardData.new()
	board.custom_board_id = GFUuid.generate_v7((index + 1) * 1000)
	board.display_name = "Board %d" % index
	board.created_at = index + 1
	board.updated_at = index + 2
	board.topology = BoardTopology.create_rectangle(
		Vector2i(4, 4),
		CustomBoardData.get_topology_id(board.custom_board_id)
	)
	return board
