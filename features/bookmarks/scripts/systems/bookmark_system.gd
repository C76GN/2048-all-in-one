## BookmarkSystem: 负责处理游戏书签（状态存档）持久化的核心系统。
##
## 负责管理并持久化游戏书签记录。
## 书签作为独立 Feature section 参与统一玩家 GFSaveProfile 事务。
class_name BookmarkSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 私有变量 ---

var _save_graph: GameSaveGraphUtility = null
var _signal_utility: GFSignalUtility = null
var _cached_bookmarks: Array[BookmarkData] = []
var _cached_profile_id: StringName = &""
var _bookmark_cache_valid: bool = false
var _bookmark_cache_hits: int = 0
var _bookmark_cache_misses: int = 0


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameSaveGraphUtility, GFSignalUtility]


func ready() -> void:
	_save_graph = _resolve_save_graph_utility()
	_signal_utility = _resolve_signal_utility()
	_invalidate_bookmark_cache()
	_bookmark_cache_hits = 0
	_bookmark_cache_misses = 0
	if not is_instance_valid(_save_graph) or not is_instance_valid(
		_signal_utility
	):
		push_error("[BookmarkSystem] SaveGraph 或 GFSignalUtility 未注册。")
		return
	_connect_save_graph_signals()


func dispose() -> void:
	_disconnect_save_graph_signals()
	_invalidate_bookmark_cache()
	_save_graph = null
	_signal_utility = null


# --- 公共方法 ---

## 异步将一个 BookmarkData 原子写入统一玩家 Profile。
## @param bookmark_data: 要保存的 BookmarkData 资源。
func request_save_bookmark(
	bookmark_data: BookmarkData
) -> GameSaveSectionOperation:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return null
	if bookmark_data == null:
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_PARAMETER
		)

	if bookmark_data.bookmark_id.is_empty():
		var timestamp_msec: int = bookmark_data.timestamp * 1000 if bookmark_data.timestamp > 0 else -1
		bookmark_data.bookmark_id = GFUuid.generate_v7(timestamp_msec)
	if not GFUuid.is_valid(bookmark_data.bookmark_id, 7):
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_DATA
		)

	var candidate_envelope: Dictionary = (
		bookmark_data.to_persisted_candidate_envelope()
	)
	if not BookmarkData.is_persisted_envelope_lightweight_valid(
		candidate_envelope
	):
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_DATA
		)
	var bookmark_envelopes: Array[Dictionary] = []
	if not _load_bookmark_envelopes(save_graph, bookmark_envelopes):
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_DATA
		)
	var candidate_id: String = GFVariantData.get_option_string(
		candidate_envelope,
		"bookmark_id"
	)
	for existing: Dictionary in bookmark_envelopes:
		if (
			GFVariantData.get_option_string(existing, "bookmark_id")
			== candidate_id
		):
			return save_graph.make_rejected_section_operation(
				GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
				ERR_ALREADY_EXISTS
			)
	bookmark_envelopes.append(candidate_envelope)
	_sort_bookmark_envelopes(bookmark_envelopes)
	var operation: GameSaveSectionOperation = save_graph.request_replace_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		{"items": bookmark_envelopes},
		{&"feature_operation": "save_bookmark"}
	)
	# request_replace_section_data() 会同步应用候选 section，再异步持久化。
	# 只有进入 pending 或已实际改变内存的终态，旧缓存才不再代表权威状态。
	_invalidate_bookmark_cache_for_operation(operation)
	return operation


## 从统一玩家数据图读取全部书签。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return []
	if not save_graph.is_profile_loaded():
		# activate_profile_async 已切换目标身份但 LOAD 尚未应用完成时，
		# provider 暂时承载默认 section；该窗口不得形成目标 Profile 缓存。
		_invalidate_bookmark_cache()
		return []

	var active_profile_id: StringName = save_graph.get_active_profile_id()
	if (
		_bookmark_cache_valid
		and _cached_profile_id == active_profile_id
	):
		_bookmark_cache_hits += 1
		return _duplicate_bookmarks(_cached_bookmarks)

	_bookmark_cache_misses += 1
	var bookmarks: Array[BookmarkData] = []
	var runtime_data: Dictionary = save_graph.get_section_runtime_cache_snapshot(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	for item_value: Variant in GFVariantData.get_option_array(
		runtime_data,
		"items"
	):
		if not item_value is BookmarkData:
			continue
		var bookmark: BookmarkData = item_value
		bookmarks.append(bookmark)
	bookmarks.sort_custom(func(left: BookmarkData, right: BookmarkData) -> bool:
		return left.bookmark_id > right.bookmark_id
	)
	_cached_bookmarks = bookmarks
	_cached_profile_id = active_profile_id
	_bookmark_cache_valid = true
	return _duplicate_bookmarks(_cached_bookmarks)


## 返回书签解析缓存诊断快照。
func get_cache_debug_snapshot() -> Dictionary:
	return {
		&"valid": _bookmark_cache_valid,
		&"profile_id": String(_cached_profile_id),
		&"bookmark_count": _cached_bookmarks.size(),
		&"hits": _bookmark_cache_hits,
		&"misses": _bookmark_cache_misses,
	}


## 根据稳定 ID 异步删除一个书签。
## @param bookmark_id: 要删除的 UUID v7 书签标识。
func request_delete_bookmark(
	bookmark_id: String
) -> GameSaveSectionOperation:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return null
	if not GFUuid.is_valid(bookmark_id, 7):
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_PARAMETER
		)

	var bookmark_envelopes: Array[Dictionary] = []
	if not _load_bookmark_envelopes(save_graph, bookmark_envelopes):
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_INVALID_DATA
		)
	var found: bool = false
	var retained: Array[Dictionary] = []
	for bookmark_envelope: Dictionary in bookmark_envelopes:
		if (
			GFVariantData.get_option_string(
				bookmark_envelope,
				"bookmark_id"
			) == bookmark_id
		):
			found = true
			continue
		retained.append(bookmark_envelope)
	if not found:
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
			ERR_DOES_NOT_EXIST
		)
	var operation: GameSaveSectionOperation = save_graph.request_replace_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		{"items": retained},
		{&"feature_operation": "delete_bookmark"}
	)
	_invalidate_bookmark_cache_for_operation(operation)
	return operation


# --- 私有/辅助方法 ---

func _load_bookmark_envelopes(
	save_graph: GameSaveGraphUtility,
	output: Array[Dictionary]
) -> bool:
	output.clear()
	if not is_instance_valid(save_graph):
		return false
	var section_data: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	)
	for item_value: Variant in GFVariantData.get_option_array(
		section_data,
		"items"
	):
		if not item_value is Dictionary:
			output.clear()
			return false
		var envelope: Dictionary = GFVariantData.as_dictionary(item_value)
		if not BookmarkData.is_persisted_envelope_lightweight_valid(
			envelope
		):
			output.clear()
			return false
		output.append(envelope)
	_sort_bookmark_envelopes(output)
	return true


func _sort_bookmark_envelopes(
	envelopes: Array[Dictionary]
) -> void:
	envelopes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (
			GFVariantData.get_option_string(left, "bookmark_id")
			> GFVariantData.get_option_string(right, "bookmark_id")
		)
	)


func _duplicate_bookmarks(
	bookmarks: Array[BookmarkData]
) -> Array[BookmarkData]:
	var result: Array[BookmarkData] = []
	for bookmark: BookmarkData in bookmarks:
		if bookmark == null:
			continue
		# 书签包含可由 UI/调用方修改的深层命令历史和检查点子资源；
		# 必须深复制才能让缓存保持只读权威副本。
		var duplicate_value: Resource = bookmark.duplicate(true)
		if duplicate_value is BookmarkData:
			var duplicate_bookmark: BookmarkData = duplicate_value
			result.append(duplicate_bookmark)
	return result


func _invalidate_bookmark_cache() -> void:
	_cached_bookmarks.clear()
	_cached_profile_id = &""
	_bookmark_cache_valid = false


func _invalidate_bookmark_cache_for_operation(
	operation: GameSaveSectionOperation
) -> void:
	if operation == null:
		return
	if operation.is_pending():
		_invalidate_bookmark_cache()
		return
	if not operation.is_completed():
		return
	var result: GameSaveSectionResult = operation.get_result()
	if _section_result_may_change_bookmarks(result):
		_invalidate_bookmark_cache()


func _section_result_may_change_bookmarks(
	result: GameSaveSectionResult
) -> bool:
	return (
		result != null
		and result.get_section_ids().has(
			String(GameSaveGraphUtility.BOOKMARKS_SECTION_ID)
		)
		and (
			result.is_successful()
			or result.was_candidate_applied()
			or result.was_memory_rolled_back()
			or result.requires_reconciliation()
		)
	)


func _connect_save_graph_signals() -> void:
	if (
		not is_instance_valid(_save_graph)
		or not is_instance_valid(_signal_utility)
	):
		return
	var _section_connection: GFSignalConnection = _signal_utility.connect_signal(
		_save_graph.section_operation_completed,
		_on_section_operation_completed,
		self
	)
	var _reconciliation_connection: GFSignalConnection = _signal_utility.connect_signal(
		_save_graph.section_reconciliation_settled,
		_on_section_reconciliation_settled,
		self
	)
	var _profile_connection: GFSignalConnection = _signal_utility.connect_signal(
		_save_graph.profile_operation_completed,
		_on_profile_operation_completed,
		self
	)


func _disconnect_save_graph_signals() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


func _on_section_operation_completed(
	result: GameSaveSectionResult
) -> void:
	if _section_result_may_change_bookmarks(result):
		_invalidate_bookmark_cache()


func _on_section_reconciliation_settled(evidence: Dictionary) -> void:
	var section_ids_value: Variant = evidence.get(
		&"section_ids",
		PackedStringArray()
	)
	if section_ids_value is PackedStringArray:
		var section_ids: PackedStringArray = section_ids_value
		if section_ids.has(
			String(GameSaveGraphUtility.BOOKMARKS_SECTION_ID)
		):
			_invalidate_bookmark_cache()


func _on_profile_operation_completed(
	result: GFSaveProfileResult
) -> void:
	if (
		result != null
		and result.get_operation()
		== GFSaveProfileOperation.OPERATION_LOAD
	):
		# LOAD 信号可能早于 GameSaveGraphUtility 把 loaded 标记设为 true；
		# 此处只负责失效，下一次 loaded gate 通过后再解析权威 section。
		_invalidate_bookmark_cache()


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	_connect_save_graph_signals()
	return _save_graph


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = utility_value
		return utility
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var utility: GFSignalUtility = utility_value
		return utility
	return null
