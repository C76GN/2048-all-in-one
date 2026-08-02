## ProgressStatsSystem: 负责处理游戏最高分与轻量统计数据持久化的系统。
##
## 最高分和统计作为 progress section 参与统一玩家 GFSaveProfile，设置交给 GFSettingsUtility 管理。
class_name ProgressStatsSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "ProgressStatsSystem"
const _KEY_STATS: String = "stats"
const _KEY_RESULTS: String = "results"
const _KEY_LEADERBOARDS: String = "leaderboards"
const _STAT_PLAYS: String = "plays"
const _STAT_BEST_SCORE: String = "best_score"
const _STAT_BEST_STEPS: String = "best_steps"
const _STAT_MAX_TILE: String = "max_tile"
const _STAT_TOTAL_SCORE: String = "total_score"
const _STAT_TOTAL_STEPS: String = "total_steps"
const _STAT_STEP_SAMPLES: String = "step_samples"
const _STAT_AVERAGE_SCORE: String = "average_score"
const _STAT_AVERAGE_STEPS: String = "average_steps"
const _STAT_TARGET_VALUE: String = "target_value"
const _STAT_TARGET_REACHED_COUNT: String = "target_reached_count"
const _STAT_TARGET_REACHED_RATE: String = "target_reached_rate"
const _STAT_LAST_TARGET_REACHED: String = "last_target_reached"
const _STAT_LAST_SCORE: String = "last_score"
const _STAT_LAST_STEPS: String = "last_steps"
const _STAT_LAST_MAX_TILE: String = "last_max_tile"
const _STAT_LAST_PLAYED_AT: String = "last_played_at"
const _STAT_TOTAL_DURATION_MSEC: String = "total_duration_msec"
const _STAT_DURATION_SAMPLES: String = "duration_samples"
const _STAT_BEST_DURATION_MSEC: String = "best_duration_msec"
const _STAT_AVERAGE_DURATION_MSEC: String = "average_duration_msec"
const _STAT_LAST_DURATION_MSEC: String = "last_duration_msec"
## 设备本地榜只读取本机 Profile；沿用 Profile I/O 的五秒产品预算，
## 即使调用方未提供取消令牌也必须进入 typed 终态。
const _DEFAULT_DEVICE_SNAPSHOT_TIMEOUT_SECONDS: float = 5.0


# --- 私有变量 ---

var _log: GFLogUtility
var _clock: GameClockUtility
var _save_graph: GameSaveGraphUtility
var _account_catalog: LocalAccountCatalogUtility
var _storage: GFStorageUtility
var _signal_utility: GFSignalUtility
var _disposed: bool = true
var _reconciliation_connection: GFSignalConnection = null
var _snapshot_request_serial: int = 0
var _snapshot_contexts: Dictionary = {}
var _device_snapshot_timeout_seconds: float = (
	_DEFAULT_DEVICE_SNAPSHOT_TIMEOUT_SECONDS
)


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GameSaveGraphUtility,
		GFLogUtility,
		GFSignalUtility,
		GFStorageUtility,
		LocalAccountCatalogUtility,
	]


func ready() -> void:
	_disposed = false
	_log = _get_log_utility()
	_clock = _get_clock_utility()
	_save_graph = _get_save_graph_utility()
	_account_catalog = _get_account_catalog_utility()
	_storage = _get_storage_utility()
	_signal_utility = _get_signal_utility()


func dispose() -> void:
	_disposed = true
	_disconnect_reconciliation_callback()
	for request_id_value: Variant in _snapshot_contexts.keys():
		var request_id: int = GFVariantData.to_int(request_id_value)
		var context: Dictionary = _get_snapshot_context(request_id)
		var batch: GFAsyncBatch = _get_snapshot_batch(context)
		if batch != null and not batch.is_completed():
			var _cancelled_batch: bool = batch.cancel(
				&"system_disposed",
				{&"request_id": request_id}
			)
		var completion: GFAsyncCompletion = _get_snapshot_completion(context)
		if completion != null and completion.is_pending():
			var _cancelled_completion: bool = completion.cancel(
				&"system_disposed",
				{&"request_id": request_id}
			)
	_snapshot_contexts.clear()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_log = null
	_clock = null
	_save_graph = null
	_account_catalog = null
	_storage = null
	_signal_utility = null


# --- 公共方法 ---

## 根据模式 ID 和稳定棋盘拓扑键获取最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
func get_high_score(mode_id: String, board_key: String) -> int:
	if mode_id.is_empty() or board_key.is_empty():
		return 0

	var save_data: Dictionary = _get_save_data()
	var stats_entry: Dictionary = _get_stats_entry(save_data, mode_id, board_key)
	return maxi(GFVariantData.get_option_int(stats_entry, _STAT_BEST_SCORE, 0), 0)


## 获取某个模式和棋盘拓扑的轻量统计。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
func get_game_stats(mode_id: String, board_key: String) -> Dictionary:
	if mode_id.is_empty() or board_key.is_empty():
		return _make_default_stats()

	var save_data: Dictionary = _get_save_data()
	return _normalize_stats_entry(_get_stats_entry(save_data, mode_id, board_key))


## 设置或更新一个模式在特定棋盘拓扑下的最高分。
## @param mode_id: 模式资源文件名派生出的模式标识。
## @param board_key: BoardTopology.get_stable_key() 的结果。
## @param score: 本次尝试写入的分数。
func set_high_score(mode_id: String, board_key: String, score: int) -> Error:
	if mode_id.is_empty() or board_key.is_empty():
		return ERR_INVALID_PARAMETER

	var save_data: Dictionary = _get_save_data()
	var entry: Dictionary = _normalize_stats_entry(_get_stats_entry(save_data, mode_id, board_key))
	var normalized_score: int = maxi(score, 0)
	if normalized_score <= GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0):
		return OK

	entry[_STAT_BEST_SCORE] = normalized_score
	_set_stats_entry(save_data, mode_id, board_key, entry)
	var save_error: Error = _queue_game_data(save_data)
	if save_error == OK and is_instance_valid(_log):
		_log.info(_LOG_TAG, "新纪录: mode=%s, board=%s, score=%d" % [mode_id, board_key, normalized_score])
	return save_error


## 异步事务记录规范结果。所有结果进入有界 recent results；只有比赛合格
## 结果进入本地榜。
## Debug 改写结果不投影到既有进度统计或成就。
## @param result: 已冻结并通过当前 schema 校验的规范对局结果。
## @param duration_msec: 本局从可操作开始到结束的持续时间，单位为毫秒。
func request_record_game_result(
	result: GameResultRecordedData,
	duration_msec: int = 0
) -> GameSaveSectionOperation:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return null
	if result == null or not result.is_valid() or duration_msec < 0:
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			ERR_INVALID_DATA
		)
	var strict_result: GameResultRecordedData = GameResultRecordedData.from_dict(
		result.to_dict()
	)
	if strict_result == null:
		return save_graph.make_rejected_section_operation(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			ERR_INVALID_DATA
		)

	var save_data: Dictionary = _get_save_data()
	if _has_recorded_result(save_data, strict_result.result_hash):
		return save_graph.make_successful_section_operation(
			GameSaveGraphUtility.PROGRESS_SECTION_ID
		)
	if strict_result.counts_toward_progress():
		_apply_result_to_stats(save_data, strict_result, duration_msec)
	_append_recent_result(save_data, strict_result)
	if strict_result.is_competition_eligible():
		_append_local_leaderboard_result(save_data, strict_result)

	var operation: GameSaveSectionOperation = (
		save_graph.request_replace_section_data(
			GameSaveGraphUtility.PROGRESS_SECTION_ID,
			save_data,
			{&"feature": &"progress", &"action": &"record_game_result"}
		)
	)
	if strict_result.counts_toward_progress():
		_publish_recorded_result_on_success(operation, strict_result)
	return operation


## 返回最近规范结果的只读副本，按结束时间降序、result hash 升序稳定排列。
func get_recent_results() -> Array[GameResultRecordedData]:
	var result: Array[GameResultRecordedData] = []
	for result_value: Variant in _get_results(_get_save_data()):
		if not result_value is Dictionary:
			continue
		var result_data: Dictionary = result_value
		var item: GameResultRecordedData = GameResultRecordedData.from_dict(
			result_data
		)
		if item != null:
			result.append(item)
	return result


## 查询与给定结果完全同组的本地榜。
## @param reference_result: 提供完整榜单身份的规范参考结果。
func get_local_leaderboard_for_result(
	reference_result: GameResultRecordedData
) -> Array[GameResultRecordedData]:
	if reference_result == null or not reference_result.is_valid():
		return []
	return _get_local_leaderboard_by_identity(
		reference_result.get_leaderboard_identity()
	)


## 返回给定规范结果在本地榜中的 1-based 名次；未上榜返回 0。
## @param reference_result: 要查询本地名次的规范结果。
func get_local_rank(reference_result: GameResultRecordedData) -> int:
	if reference_result == null:
		return 0
	var leaderboard: Array[GameResultRecordedData] = get_local_leaderboard_for_result(
		reference_result
	)
	for index: int in range(leaderboard.size()):
		if leaderboard[index].result_hash == reference_result.result_hash:
			return index + 1
	return 0


## 查询指定模式、拓扑与规则版本的本地榜。
## @param mode_id: 对局模式的稳定 ID。
## @param board_key: 棋盘拓扑的稳定键。
## @param ruleset_id: 玩法规则集的稳定 ID。
## @param ruleset_version: 玩法规则集版本。
## @param ruleset_fingerprint: 完整玩法内容的 SHA-256 指纹。
func get_local_leaderboard(
	mode_id: String,
	board_key: String,
	ruleset_id: StringName,
	ruleset_version: int,
	ruleset_fingerprint: String
) -> Array[GameResultRecordedData]:
	var identity: Dictionary = {
		&"mode_id": mode_id,
		&"board_key": board_key,
		&"ruleset_id": String(ruleset_id),
		&"ruleset_version": ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
	}
	return _get_local_leaderboard_by_identity(identity)


## 异步冻结此设备全部本地账号的 progress 快照。
##
## 当前账号直接读取最新内存 section；其余账号各提交一次 GFStorage 异步读取，
## 并通过 GFAsyncBatch 汇总为单一不可变结果。单个账号损坏或缺失只会把快照
## 标记为 partial，不会让其他账号的统计不可用。
## @param cancel_token: 调用方生命周期取消令牌。
func request_device_progress_snapshot(
	cancel_token: GFCancellationToken = null
) -> GFAsyncCompletion:
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	if (
		_disposed
		or not is_instance_valid(_storage)
		or not is_instance_valid(_signal_utility)
		or not is_instance_valid(_account_catalog)
		or _get_save_graph() == null
	):
		var _failed_unconfigured: bool = completion.fail(
			"Progress snapshot dependencies are unavailable.",
			{&"error_code": int(ERR_UNCONFIGURED)}
		)
		return completion
	if cancel_token != null and cancel_token.is_cancel_requested():
		var _cancelled_before_start: bool = completion.cancel(
			cancel_token.get_cancel_reason(),
			cancel_token.get_cancel_metadata()
		)
		return completion

	var accounts: Array[LocalPlayerAccount] = _account_catalog.get_accounts()
	var active_account_id: String = _account_catalog.get_active_account_id()
	if accounts.is_empty() or active_account_id.is_empty():
		var _failed_catalog: bool = completion.fail(
			"Local account catalog has no active account.",
			{&"error_code": int(ERR_DOES_NOT_EXIST)}
		)
		return completion
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var catalog_profile_file: String = (
		LocalAccountCatalogUtility.make_profile_file_name(
			active_account_id
		)
	)
	var active_profile_file: String = save_graph.get_profile_file_name()
	if active_profile_file != catalog_profile_file:
		var _failed_account_transition: bool = completion.fail(
			"Local account catalog and active Save Profile are reconciling.",
			{
				&"error_code": int(ERR_BUSY),
				&"reconciliation": true,
				&"active_account_id": active_account_id,
				&"catalog_profile_file": catalog_profile_file,
				&"active_profile_file": active_profile_file,
			}
		)
		return completion

	_snapshot_request_serial += 1
	var request_id: int = _snapshot_request_serial
	var snapshot: Dictionary = _make_empty_device_progress_snapshot(
		request_id,
		active_account_id,
		accounts
	)
	var inactive_account_ids: Array[String] = []
	for account: LocalPlayerAccount in accounts:
		if account.account_id == active_account_id:
			var active_entry: Dictionary = _get_snapshot_account_entry(
				snapshot,
				account.account_id
			)
			active_entry[&"progress"] = _get_save_data().duplicate(true)
			_set_snapshot_account_entry(
				snapshot,
				account.account_id,
				active_entry
			)
		else:
			inactive_account_ids.append(account.account_id)

	if inactive_account_ids.is_empty():
		var _completed_immediately: bool = completion.succeed(snapshot)
		return completion

	var batch: GFAsyncBatch = GFAsyncBatch.new()
	batch.completion_policy = GFAsyncBatch.CompletionPolicy.EACH
	batch.fail_fast = false
	var context: Dictionary = {
		&"request_id": request_id,
		&"completion": completion,
		&"batch": batch,
		&"snapshot": snapshot,
		&"connections": [],
	}
	_snapshot_contexts[request_id] = context
	var settled_connection: GFSignalConnection = _signal_utility.connect_once(
		batch.settled,
		Callable(self, &"_on_progress_snapshot_batch_settled").bind(
			request_id
		),
		self
	)
	_append_snapshot_connection(context, settled_connection)
	if cancel_token != null:
		var _bound_cancel_token: bool = batch.bind_cancel_token(cancel_token)

	for account_id: String in inactive_account_ids:
		var _added_item: bool = batch.add_item(
			account_id,
			{&"account_id": account_id}
		)
	var timeout_configured: bool = batch.set_timeout(
		maxf(_device_snapshot_timeout_seconds, 0.001),
		null,
		&"timeout",
		{
			&"request_id": request_id,
			&"timeout_seconds": maxf(
				_device_snapshot_timeout_seconds,
				0.001
			),
		}
	)
	if not timeout_configured:
		var _cancelled_unconfigured_timeout: bool = batch.cancel(
			&"timeout_setup_failed",
			{
				&"request_id": request_id,
				&"error_code": int(ERR_CANT_CREATE),
			}
		)
		return completion
	for account_id: String in inactive_account_ids:
		if batch.is_completed():
			break
		var operation: GFStorageAsyncOperation = _storage.load_data_request_async(
			LocalAccountCatalogUtility.make_profile_file_name(account_id)
		)
		if operation == null:
			var _marked_missing_operation: bool = batch.mark_completed(
				account_id,
				_make_progress_snapshot_issue(
					&"request_not_created",
					ERR_CANT_CREATE,
					"Storage did not create a load operation."
				)
			)
			continue
		if operation.is_completed():
			_settle_progress_snapshot_storage_result(
				operation.get_result(),
				request_id,
				account_id,
				operation.get_request_id()
			)
			continue
		var operation_connection: GFSignalConnection = (
			_signal_utility.connect_once(
				operation.completed,
				Callable(
					self,
					&"_on_progress_snapshot_storage_completed"
				).bind(
					request_id,
					account_id,
					operation.get_request_id()
				),
				self
			)
		)
		_append_snapshot_connection(context, operation_connection)
	return completion


## 从已冻结设备快照返回指定账号按模式聚合的个人统计。
## @param snapshot: request_device_progress_snapshot() 的成功结果。
## @param account_id: 要投影的本地账号 ID；空字符串表示快照中的当前账号。
func get_profile_mode_summaries(
	snapshot: Dictionary,
	account_id: String = ""
) -> Array[Dictionary]:
	var resolved_account_id: String = account_id
	if resolved_account_id.is_empty():
		resolved_account_id = GFVariantData.get_option_string(
			snapshot,
			&"active_account_id"
		)
	var save_data: Dictionary = _get_snapshot_account_progress(
		snapshot,
		resolved_account_id
	)
	if save_data.is_empty():
		return []
	return _build_mode_summaries(save_data)


## 从已冻结设备快照返回全部本地账号可用的榜单分组身份。
## @param snapshot: request_device_progress_snapshot() 的成功结果。
func get_device_leaderboard_identities(
	snapshot: Dictionary
) -> Array[Dictionary]:
	var identities_by_key: Dictionary = {}
	for account_id: String in _get_snapshot_account_order(snapshot):
		var save_data: Dictionary = _get_snapshot_account_progress(
			snapshot,
			account_id
		)
		var leaderboards: Dictionary = _get_leaderboards(save_data)
		for group_key_value: Variant in leaderboards.keys():
			var group_key: String = GFVariantData.to_text(group_key_value)
			var bucket: Dictionary = GFVariantData.get_option_dictionary(
				leaderboards,
				group_key
			)
			var identity: Dictionary = GFVariantData.get_option_dictionary(
				bucket,
				&"identity"
			)
			if (
				GameResultRecordedData.is_leaderboard_identity_valid(identity)
				and GameResultRecordedData.calculate_leaderboard_group_key(
					identity
				) == group_key
			):
				identities_by_key[group_key] = identity.duplicate(true)

	var result: Array[Dictionary] = []
	for identity_value: Variant in identities_by_key.values():
		if identity_value is Dictionary:
			result.append(GFVariantData.as_dictionary(identity_value))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_label: String = "%s|%s|%s|%010d" % [
			GFVariantData.get_option_string(left, &"mode_id"),
			GFVariantData.get_option_string(left, &"board_key"),
			GFVariantData.get_option_string(left, &"ruleset_id"),
			GFVariantData.get_option_int(left, &"ruleset_version", 0),
		]
		var right_label: String = "%s|%s|%s|%010d" % [
			GFVariantData.get_option_string(right, &"mode_id"),
			GFVariantData.get_option_string(right, &"board_key"),
			GFVariantData.get_option_string(right, &"ruleset_id"),
			GFVariantData.get_option_int(right, &"ruleset_version", 0),
		]
		return left_label < right_label
	)
	return result


## 聚合此设备全部本地账号在同一严格规则分组下的最佳成绩。
##
## 每个账号最多占一个名次，避免同一玩家用多局结果填满设备榜。
## @param snapshot: request_device_progress_snapshot() 的成功结果。
## @param identity: 模式、棋盘与规则集组成的严格排行榜分组身份。
func get_device_local_leaderboard(
	snapshot: Dictionary,
	identity: Dictionary
) -> Array[Dictionary]:
	if not GameResultRecordedData.is_leaderboard_identity_valid(identity):
		return []
	var group_key: String = GameResultRecordedData.calculate_leaderboard_group_key(
		identity
	)
	if group_key.is_empty():
		return []

	var rows: Array[Dictionary] = []
	for account_id: String in _get_snapshot_account_order(snapshot):
		var account_entry: Dictionary = _get_snapshot_account_entry(
			snapshot,
			account_id
		)
		var save_data: Dictionary = GFVariantData.get_option_dictionary(
			account_entry,
			&"progress"
		)
		var bucket: Dictionary = GFVariantData.get_option_dictionary(
			_get_leaderboards(save_data),
			group_key
		)
		if GFVariantData.get_option_dictionary(bucket, &"identity") != identity:
			continue
		var best_result: GameResultRecordedData = null
		for entry_value: Variant in GFVariantData.get_option_array(
			bucket,
			&"entries"
		):
			if not entry_value is Dictionary:
				continue
			var candidate: GameResultRecordedData = (
				GameResultRecordedData.from_dict(
					GFVariantData.as_dictionary(entry_value)
				)
			)
			if candidate != null and candidate.is_competition_eligible():
				best_result = candidate
				break
		if best_result != null:
			rows.append({
				&"rank": 0,
				&"account_id": account_id,
				&"display_name": GFVariantData.get_option_string(
					account_entry,
					&"display_name"
				),
				&"result": best_result,
			})

	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _is_device_leaderboard_row_better(left, right)
	)
	for index: int in range(rows.size()):
		rows[index][&"rank"] = index + 1
	return rows


# --- 私有方法 ---

func _make_empty_device_progress_snapshot(
	request_id: int,
	active_account_id: String,
	accounts: Array[LocalPlayerAccount]
) -> Dictionary:
	var account_order: Array[String] = []
	var accounts_by_id: Dictionary = {}
	for account: LocalPlayerAccount in accounts:
		account_order.append(account.account_id)
		accounts_by_id[account.account_id] = {
			&"account_id": account.account_id,
			&"display_name": account.display_name,
			&"last_active_at": account.last_active_at,
			&"progress": {},
		}
	return {
		&"request_id": request_id,
		&"active_account_id": active_account_id,
		&"account_order": account_order,
		&"accounts_by_id": accounts_by_id,
		&"issues_by_account_id": {},
		&"partial": false,
		&"timed_out": false,
	}


func _on_progress_snapshot_storage_completed(
	result: GFStorageAsyncResult,
	request_id: int,
	account_id: String,
	storage_request_id: int
) -> void:
	_settle_progress_snapshot_storage_result(
		result,
		request_id,
		account_id,
		storage_request_id
	)


func _settle_progress_snapshot_storage_result(
	result: GFStorageAsyncResult,
	request_id: int,
	account_id: String,
	storage_request_id: int
) -> void:
	var context: Dictionary = _get_snapshot_context(request_id)
	var batch: GFAsyncBatch = _get_snapshot_batch(context)
	if context.is_empty() or batch == null or batch.is_completed():
		return
	var outcome: Dictionary = _parse_progress_snapshot_storage_result(
		result,
		storage_request_id
	)
	var _marked_item: bool = batch.mark_completed(account_id, outcome)


func _parse_progress_snapshot_storage_result(
	result: GFStorageAsyncResult,
	storage_request_id: int
) -> Dictionary:
	if result == null or result.get_request_id() != storage_request_id:
		return _make_progress_snapshot_issue(
			&"request_identity_mismatch",
			ERR_INVALID_DATA,
			"Storage result did not match its load operation."
		)
	var read_result: GFStorageReadResult = result.get_read_result()
	if read_result == null or not read_result.ok:
		return _make_progress_snapshot_issue(
			&"storage_read_failed",
			(
				read_result.error_code
				if read_result != null
				else result.get_error_code()
			),
			(
				read_result.error
				if read_result != null
				else "Storage load did not return a typed read result."
			)
		)
	var envelope: Dictionary = GameSaveGraphUtility.extract_profile_section_envelope(
		read_result.payload,
		GameSaveGraphUtility.PROGRESS_SECTION_ID
	)
	if envelope.is_empty():
		return _make_progress_snapshot_issue(
			&"profile_schema_invalid",
			ERR_INVALID_DATA,
			"Profile does not contain a valid progress section."
		)
	var provider: GameStatsSaveData = GameStatsSaveData.new()
	var replace_error: Error = provider.replace_from_dict(envelope)
	if replace_error != OK:
		return _make_progress_snapshot_issue(
			&"progress_schema_invalid",
			replace_error,
			"Progress section failed strict schema validation."
		)
	return {
		&"ok": true,
		&"progress": provider.get_section_data(),
	}


func _on_progress_snapshot_batch_settled(
	report: Dictionary,
	request_id: int
) -> void:
	var context: Dictionary = _get_snapshot_context(request_id)
	if context.is_empty():
		return
	var completion: GFAsyncCompletion = _get_snapshot_completion(context)
	if completion == null:
		_cleanup_snapshot_context(request_id)
		return
	if GFVariantData.get_option_bool(report, &"cancelled", false):
		if GFVariantData.get_option_bool(report, &"timed_out", false):
			_complete_progress_snapshot_from_report(
				context,
				report,
				request_id,
				true
			)
			return
		var cancel_reason: StringName = GFVariantData.get_option_string_name(
			report,
			&"cancel_reason",
			&"cancelled"
		)
		if cancel_reason == &"timeout_setup_failed":
			if completion.is_pending():
				var _failed_timeout_setup: bool = completion.fail(
					"Progress snapshot timeout could not be scheduled.",
					{
						&"request_id": request_id,
						&"error_code": int(ERR_CANT_CREATE),
					}
				)
			_cleanup_snapshot_context(request_id)
			return
		if completion.is_pending():
			var _cancelled_completion: bool = completion.cancel(
				cancel_reason,
				GFVariantData.get_option_dictionary(
					report,
					&"cancel_metadata"
				)
			)
		_cleanup_snapshot_context(request_id)
		return
	_complete_progress_snapshot_from_report(
		context,
		report,
		request_id,
		false
	)


func _complete_progress_snapshot_from_report(
	context: Dictionary,
	report: Dictionary,
	request_id: int,
	timed_out: bool
) -> void:
	var completion: GFAsyncCompletion = _get_snapshot_completion(context)
	if completion == null:
		_cleanup_snapshot_context(request_id)
		return
	var snapshot: Dictionary = GFVariantData.get_option_dictionary(
		context,
		&"snapshot"
	)
	var results: Dictionary = GFVariantData.get_option_dictionary(
		report,
		&"results"
	)
	var issues: Dictionary = {}
	for account_id_value: Variant in results.keys():
		var account_id: String = GFVariantData.to_text(account_id_value)
		var outcome: Dictionary = GFVariantData.get_option_dictionary(
			results,
			account_id
		)
		if GFVariantData.get_option_bool(outcome, &"ok", false):
			var entry: Dictionary = _get_snapshot_account_entry(
				snapshot,
				account_id
			)
			entry[&"progress"] = GFVariantData.get_option_dictionary(
				outcome,
				&"progress"
			)
			_set_snapshot_account_entry(snapshot, account_id, entry)
		else:
			issues[account_id] = (
				outcome.duplicate(true)
				if not outcome.is_empty()
				else _make_progress_snapshot_issue(
					&"storage_read_timeout" if timed_out else &"storage_read_failed",
					ERR_TIMEOUT if timed_out else FAILED,
					(
						"Storage read exceeded the device snapshot timeout."
						if timed_out
						else "Storage read did not produce a typed outcome."
					)
				)
			)
	snapshot[&"issues_by_account_id"] = issues
	snapshot[&"partial"] = not issues.is_empty()
	snapshot[&"timed_out"] = timed_out
	if completion.is_pending():
		var _completed_snapshot: bool = completion.succeed(
			snapshot,
			{
				&"request_id": request_id,
				&"partial": not issues.is_empty(),
				&"issue_count": issues.size(),
				&"timed_out": timed_out,
				&"error_code": int(ERR_TIMEOUT) if timed_out else int(OK),
			}
		)
	_cleanup_snapshot_context(request_id)


func _make_progress_snapshot_issue(
	failure_kind: StringName,
	error_code: Error,
	reason: String
) -> Dictionary:
	return {
		&"ok": false,
		&"failure_kind": failure_kind,
		&"error_code": int(error_code),
		&"reason": reason,
	}


func _get_snapshot_account_order(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for account_id_value: Variant in GFVariantData.get_option_array(
		snapshot,
		&"account_order"
	):
		var account_id: String = GFVariantData.to_text(account_id_value)
		if not account_id.is_empty():
			result.append(account_id)
	return result


func _get_snapshot_account_progress(
	snapshot: Dictionary,
	account_id: String
) -> Dictionary:
	return GFVariantData.get_option_dictionary(
		_get_snapshot_account_entry(snapshot, account_id),
		&"progress"
	)


func _get_snapshot_account_entry(
	snapshot: Dictionary,
	account_id: String
) -> Dictionary:
	return GFVariantData.get_option_dictionary(
		GFVariantData.get_option_dictionary(snapshot, &"accounts_by_id"),
		account_id
	)


func _set_snapshot_account_entry(
	snapshot: Dictionary,
	account_id: String,
	entry: Dictionary
) -> void:
	var accounts_by_id: Dictionary = GFVariantData.get_option_dictionary(
		snapshot,
		&"accounts_by_id"
	)
	accounts_by_id[account_id] = entry
	snapshot[&"accounts_by_id"] = accounts_by_id


func _append_snapshot_connection(
	context: Dictionary,
	connection: GFSignalConnection
) -> void:
	if connection == null:
		return
	var connections: Array = GFVariantData.get_option_array(
		context,
		&"connections"
	)
	connections.append(connection)
	context[&"connections"] = connections


func _cleanup_snapshot_context(request_id: int) -> void:
	var context: Dictionary = _get_snapshot_context(request_id)
	for connection_value: Variant in GFVariantData.get_option_array(
		context,
		&"connections"
	):
		if connection_value is GFSignalConnection:
			var connection: GFSignalConnection = connection_value
			connection.disconnect_signal()
	var _erased_context: bool = _snapshot_contexts.erase(request_id)


func _get_snapshot_context(request_id: int) -> Dictionary:
	return GFVariantData.get_option_dictionary(
		_snapshot_contexts,
		request_id
	)


func _get_snapshot_batch(context: Dictionary) -> GFAsyncBatch:
	var batch_value: Variant = GFVariantData.get_option_value(
		context,
		&"batch"
	)
	return batch_value if batch_value is GFAsyncBatch else null


func _get_snapshot_completion(
	context: Dictionary
) -> GFAsyncCompletion:
	var completion_value: Variant = GFVariantData.get_option_value(
		context,
		&"completion"
	)
	return completion_value if completion_value is GFAsyncCompletion else null


func _build_mode_summaries(save_data: Dictionary) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	var stats: Dictionary = _get_stats(save_data)
	var mode_ids: Array[String] = []
	for mode_key: Variant in stats.keys():
		if mode_key is String:
			mode_ids.append(mode_key)
	mode_ids.sort()

	for mode_id: String in mode_ids:
		var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
		var summary: Dictionary = {
			&"mode_id": mode_id,
			&"board_count": 0,
			&"plays": 0,
			&"best_score": 0,
			&"best_steps": 0,
			&"max_tile": 0,
			&"total_score": 0,
			&"total_steps": 0,
			&"step_samples": 0,
			&"average_score": 0,
			&"average_steps": 0,
			&"target_reached_count": 0,
			&"target_reached_rate": 0,
			&"total_duration_msec": 0,
			&"duration_samples": 0,
			&"best_duration_msec": 0,
			&"average_duration_msec": 0,
			&"last_played_at": 0,
		}
		for entry_value: Variant in mode_stats.values():
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = _normalize_stats_entry(
				GFVariantData.as_dictionary(entry_value)
			)
			summary[&"board_count"] = (
				GFVariantData.get_option_int(summary, &"board_count", 0) + 1
			)
			summary[&"plays"] = (
				GFVariantData.get_option_int(summary, &"plays", 0)
				+ GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
			)
			summary[&"best_score"] = maxi(
				GFVariantData.get_option_int(summary, &"best_score", 0),
				GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0)
			)
			summary[&"best_steps"] = _minimum_positive(
				GFVariantData.get_option_int(summary, &"best_steps", 0),
				GFVariantData.get_option_int(entry, _STAT_BEST_STEPS, 0)
			)
			summary[&"max_tile"] = maxi(
				GFVariantData.get_option_int(summary, &"max_tile", 0),
				GFVariantData.get_option_int(entry, _STAT_MAX_TILE, 0)
			)
			for key: StringName in [
				&"total_score",
				&"total_steps",
				&"step_samples",
				&"target_reached_count",
				&"total_duration_msec",
				&"duration_samples",
			]:
				summary[key] = (
					GFVariantData.get_option_int(summary, key, 0)
					+ GFVariantData.get_option_int(entry, String(key), 0)
				)
			summary[&"best_duration_msec"] = _minimum_positive(
				GFVariantData.get_option_int(
					summary,
					&"best_duration_msec",
					0
				),
				GFVariantData.get_option_int(
					entry,
					_STAT_BEST_DURATION_MSEC,
					0
				)
			)
			summary[&"last_played_at"] = maxi(
				GFVariantData.get_option_int(summary, &"last_played_at", 0),
				GFVariantData.get_option_int(entry, _STAT_LAST_PLAYED_AT, 0)
			)

		var plays: int = GFVariantData.get_option_int(summary, &"plays", 0)
		summary[&"average_score"] = _rounded_average(
			GFVariantData.get_option_int(summary, &"total_score", 0),
			plays
		)
		summary[&"average_steps"] = _rounded_average(
			GFVariantData.get_option_int(summary, &"total_steps", 0),
			GFVariantData.get_option_int(summary, &"step_samples", 0)
		)
		summary[&"average_duration_msec"] = _rounded_average(
			GFVariantData.get_option_int(
				summary,
				&"total_duration_msec",
				0
			),
			GFVariantData.get_option_int(summary, &"duration_samples", 0)
		)
		summary[&"target_reached_rate"] = _rounded_average(
			GFVariantData.get_option_int(
				summary,
				&"target_reached_count",
				0
			) * 100,
			plays
		)
		summaries.append(summary)
	return summaries


static func _minimum_positive(left: int, right: int) -> int:
	if left <= 0:
		return maxi(right, 0)
	if right <= 0:
		return left
	return mini(left, right)


static func _is_device_leaderboard_row_better(
	left: Dictionary,
	right: Dictionary
) -> bool:
	var left_value: Variant = GFVariantData.get_option_value(left, &"result")
	var right_value: Variant = GFVariantData.get_option_value(right, &"result")
	if not (left_value is GameResultRecordedData and right_value is GameResultRecordedData):
		return (
			GFVariantData.get_option_string(left, &"account_id")
			< GFVariantData.get_option_string(right, &"account_id")
		)
	var left_result: GameResultRecordedData = left_value
	var right_result: GameResultRecordedData = right_value
	var left_data: Dictionary = left_result.to_dict()
	var right_data: Dictionary = right_result.to_dict()
	if _is_better_leaderboard_result_data(left_data, right_data):
		return true
	if _is_better_leaderboard_result_data(right_data, left_data):
		return false
	return (
		GFVariantData.get_option_string(left, &"account_id")
		< GFVariantData.get_option_string(right, &"account_id")
	)


func _apply_result_to_stats(
	save_data: Dictionary,
	result: GameResultRecordedData,
	duration_msec: int
) -> void:
	var entry: Dictionary = _normalize_stats_entry(
		_get_stats_entry(save_data, String(result.mode_id), result.board_key)
	)
	var previous_plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	entry[_STAT_PLAYS] = previous_plays + 1
	entry[_STAT_BEST_SCORE] = maxi(
		GFVariantData.get_option_int(entry, _STAT_BEST_SCORE, 0),
		result.score
	)
	entry[_STAT_TOTAL_SCORE] = (
		GFVariantData.get_option_int(entry, _STAT_TOTAL_SCORE, 0)
		+ result.score
	)
	if result.steps > 0:
		var best_steps: int = GFVariantData.get_option_int(
			entry,
			_STAT_BEST_STEPS,
			0
		)
		if best_steps <= 0 or result.steps < best_steps:
			entry[_STAT_BEST_STEPS] = result.steps
		entry[_STAT_TOTAL_STEPS] = (
			GFVariantData.get_option_int(entry, _STAT_TOTAL_STEPS, 0)
			+ result.steps
		)
		entry[_STAT_STEP_SAMPLES] = (
			GFVariantData.get_option_int(entry, _STAT_STEP_SAMPLES, 0)
			+ 1
		)
	entry[_STAT_MAX_TILE] = maxi(
		GFVariantData.get_option_int(entry, _STAT_MAX_TILE, 0),
		result.max_tile
	)
	entry[_STAT_LAST_SCORE] = result.score
	entry[_STAT_LAST_STEPS] = result.steps
	entry[_STAT_LAST_MAX_TILE] = result.max_tile
	entry[_STAT_LAST_PLAYED_AT] = result.played_at
	if duration_msec > 0:
		var best_duration_msec: int = GFVariantData.get_option_int(
			entry,
			_STAT_BEST_DURATION_MSEC,
			0
		)
		if best_duration_msec <= 0 or duration_msec < best_duration_msec:
			entry[_STAT_BEST_DURATION_MSEC] = duration_msec
		entry[_STAT_TOTAL_DURATION_MSEC] = (
			GFVariantData.get_option_int(
				entry,
				_STAT_TOTAL_DURATION_MSEC,
				0
			)
			+ duration_msec
		)
		entry[_STAT_DURATION_SAMPLES] = (
			GFVariantData.get_option_int(entry, _STAT_DURATION_SAMPLES, 0)
			+ 1
		)
		entry[_STAT_LAST_DURATION_MSEC] = duration_msec
	if result.target_value > 0:
		entry[_STAT_TARGET_VALUE] = result.target_value
		if result.target_reached:
			entry[_STAT_TARGET_REACHED_COUNT] = (
				GFVariantData.get_option_int(
					entry,
					_STAT_TARGET_REACHED_COUNT,
					0
				)
				+ 1
			)
		entry[_STAT_LAST_TARGET_REACHED] = result.target_reached
	_update_average_stats(entry)
	_update_target_stats(entry)
	_set_stats_entry(save_data, String(result.mode_id), result.board_key, entry)


func _append_recent_result(
	save_data: Dictionary,
	result: GameResultRecordedData
) -> void:
	var results: Array = _get_results(save_data)
	results.append(result.to_dict())
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _is_newer_result_data(left, right)
	)
	if results.size() > GameStatsSaveData.MAX_RECENT_RESULTS:
		var _resize_error_code: int = results.resize(
			GameStatsSaveData.MAX_RECENT_RESULTS
		)


func _append_local_leaderboard_result(
	save_data: Dictionary,
	result: GameResultRecordedData
) -> void:
	var group_key: String = result.get_leaderboard_group_key()
	if group_key.is_empty():
		return
	var leaderboards: Dictionary = _get_leaderboards(save_data)
	var bucket: Dictionary = {}
	var bucket_value: Variant = leaderboards.get(group_key, {})
	if bucket_value is Dictionary:
		bucket = bucket_value
	var identity: Dictionary = result.get_leaderboard_identity()
	if (
		bucket.is_empty()
		or GFVariantData.get_option_dictionary(bucket, &"identity") != identity
	):
		bucket = {
			&"identity": identity,
			&"entries": [],
		}
	var entries: Array = GFVariantData.get_option_array(bucket, &"entries")
	for index: int in range(entries.size() - 1, -1, -1):
		var entry_value: Variant = entries[index]
		if not entry_value is Dictionary:
			continue
		var entry_data: Dictionary = entry_value
		if (
			GFVariantData.get_option_string(entry_data, &"result_hash")
			== result.result_hash
		):
			entries.remove_at(index)
	entries.append(result.to_dict())
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _is_better_leaderboard_result_data(left, right)
	)
	if entries.size() > GameStatsSaveData.MAX_LEADERBOARD_ENTRIES:
		var _resize_error_code: int = entries.resize(
			GameStatsSaveData.MAX_LEADERBOARD_ENTRIES
		)
	bucket[&"entries"] = entries
	leaderboards[group_key] = bucket
	_prune_leaderboard_groups(leaderboards)


func _get_local_leaderboard_by_identity(
	identity: Dictionary
) -> Array[GameResultRecordedData]:
	var result: Array[GameResultRecordedData] = []
	var group_key: String = GameResultRecordedData.calculate_leaderboard_group_key(
		identity
	)
	if group_key.is_empty():
		return result
	var leaderboards: Dictionary = _get_leaderboards(_get_save_data())
	var bucket_value: Variant = leaderboards.get(group_key, {})
	if not bucket_value is Dictionary:
		return result
	var bucket: Dictionary = bucket_value
	if GFVariantData.get_option_dictionary(bucket, &"identity") != identity:
		return result
	for entry_value: Variant in GFVariantData.get_option_array(bucket, &"entries"):
		if not entry_value is Dictionary:
			continue
		var entry_data: Dictionary = entry_value
		var item: GameResultRecordedData = GameResultRecordedData.from_dict(
			entry_data
		)
		if item != null and item.is_competition_eligible():
			result.append(item)
	return result


func _has_recorded_result(save_data: Dictionary, result_hash: String) -> bool:
	for result_value: Variant in _get_results(save_data):
		if not result_value is Dictionary:
			continue
		var result_data: Dictionary = result_value
		if (
			GFVariantData.get_option_string(result_data, &"result_hash")
			== result_hash
		):
			return true
	return false


func _get_results(save_data: Dictionary) -> Array:
	_ensure_game_data_defaults(save_data)
	var results_value: Variant = save_data[_KEY_RESULTS]
	return results_value if results_value is Array else []


func _get_leaderboards(save_data: Dictionary) -> Dictionary:
	_ensure_game_data_defaults(save_data)
	var leaderboards_value: Variant = save_data[_KEY_LEADERBOARDS]
	return leaderboards_value if leaderboards_value is Dictionary else {}


static func _prune_leaderboard_groups(leaderboards: Dictionary) -> void:
	if leaderboards.size() <= GameStatsSaveData.MAX_LEADERBOARD_GROUPS:
		return
	var group_keys: Array[String] = []
	for group_key_value: Variant in leaderboards.keys():
		group_keys.append(str(group_key_value))
	group_keys.sort_custom(func(left: String, right: String) -> bool:
		var left_time: int = _get_bucket_latest_timestamp(
			GFVariantData.get_option_dictionary(leaderboards, left)
		)
		var right_time: int = _get_bucket_latest_timestamp(
			GFVariantData.get_option_dictionary(leaderboards, right)
		)
		if left_time != right_time:
			return left_time > right_time
		return left < right
	)
	for index: int in range(
		GameStatsSaveData.MAX_LEADERBOARD_GROUPS,
		group_keys.size()
	):
		var _was_erased: bool = leaderboards.erase(group_keys[index])


static func _get_bucket_latest_timestamp(bucket: Dictionary) -> int:
	var latest_timestamp: int = 0
	for entry_value: Variant in GFVariantData.get_option_array(bucket, &"entries"):
		if entry_value is Dictionary:
			var entry_data: Dictionary = entry_value
			latest_timestamp = maxi(
				latest_timestamp,
				GFVariantData.get_option_int(entry_data, &"played_at", 0)
			)
	return latest_timestamp


static func _is_newer_result_data(left: Dictionary, right: Dictionary) -> bool:
	var left_time: int = GFVariantData.get_option_int(left, &"played_at", 0)
	var right_time: int = GFVariantData.get_option_int(right, &"played_at", 0)
	if left_time != right_time:
		return left_time > right_time
	return GFVariantData.get_option_string(
		left,
		&"result_hash"
	) < GFVariantData.get_option_string(right, &"result_hash")


static func _is_better_leaderboard_result_data(
	left: Dictionary,
	right: Dictionary
) -> bool:
	var left_score: int = GFVariantData.get_option_int(left, &"score", 0)
	var right_score: int = GFVariantData.get_option_int(right, &"score", 0)
	if left_score != right_score:
		return left_score > right_score
	var left_max_tile: int = GFVariantData.get_option_int(left, &"max_tile", 0)
	var right_max_tile: int = GFVariantData.get_option_int(right, &"max_tile", 0)
	if left_max_tile != right_max_tile:
		return left_max_tile > right_max_tile
	var left_target: bool = GFVariantData.get_option_bool(
		left,
		&"target_reached",
		false
	)
	var right_target: bool = GFVariantData.get_option_bool(
		right,
		&"target_reached",
		false
	)
	if left_target != right_target:
		return left_target
	var left_steps: int = GFVariantData.get_option_int(left, &"steps", 0)
	var right_steps: int = GFVariantData.get_option_int(right, &"steps", 0)
	var left_step_rank: int = left_steps if left_steps > 0 else 2_147_483_647
	var right_step_rank: int = right_steps if right_steps > 0 else 2_147_483_647
	if left_step_rank != right_step_rank:
		return left_step_rank < right_step_rank
	var left_time: int = GFVariantData.get_option_int(left, &"played_at", 0)
	var right_time: int = GFVariantData.get_option_int(right, &"played_at", 0)
	if left_time != right_time:
		return left_time < right_time
	return GFVariantData.get_option_string(
		left,
		&"result_hash"
	) < GFVariantData.get_option_string(right, &"result_hash")


func _publish_recorded_result_on_success(
	operation: GameSaveSectionOperation,
	strict_result: GameResultRecordedData
) -> void:
	if operation == null:
		return
	if operation.is_completed():
		_on_recorded_result_operation_completed(
			operation.get_result(),
			strict_result
		)
	else:
		var callback: Callable = Callable(
			self,
			&"_on_recorded_result_operation_completed"
		).bind(strict_result)
		if not is_instance_valid(_signal_utility):
			return
		var _operation_connection: GFSignalConnection = (
			_signal_utility.connect_once(
				operation.completed,
				callback,
				self
			)
		)


func _on_recorded_result_operation_completed(
	result: GameSaveSectionResult,
	strict_result: GameResultRecordedData
) -> void:
	if _disposed or result == null:
		return
	if result.is_successful():
		send_event(strict_result)
		return
	if result.get_status() != GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN:
		return
	_publish_recorded_result_after_reconciliation(
		result.get_transaction_id(),
		strict_result
	)


func _publish_recorded_result_after_reconciliation(
	transaction_id: int,
	strict_result: GameResultRecordedData
) -> void:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return
	_disconnect_reconciliation_callback()
	if not is_instance_valid(_signal_utility):
		return
	var callback: Callable = Callable(
		self,
		&"_on_recorded_result_reconciliation_settled"
	).bind(transaction_id, strict_result)
	_reconciliation_connection = _signal_utility.connect_signal(
		save_graph.section_reconciliation_settled,
		callback,
		self
	)


func _on_recorded_result_reconciliation_settled(
	evidence: Dictionary,
	transaction_id: int,
	strict_result: GameResultRecordedData
) -> void:
	if (
		GFVariantData.get_option_int(
			evidence,
			&"transaction_id",
			0
		) != transaction_id
	):
		return
	_disconnect_reconciliation_callback()
	if (
		_disposed
		or not GFVariantData.get_option_bool(
			evidence,
			&"candidate_persisted",
			false
		)
	):
		return
	send_event(strict_result)


func _disconnect_reconciliation_callback() -> void:
	if _reconciliation_connection != null:
		_reconciliation_connection.disconnect_signal()
	_reconciliation_connection = null


func _queue_game_data(save_data: Dictionary) -> Error:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED
	var error: Error = save_graph.queue_section_data(
		GameSaveGraphUtility.PROGRESS_SECTION_ID,
		save_data
	)
	if error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "排队统计 Profile section 失败，错误码: %d" % error)
	return error


func _get_save_data() -> Dictionary:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var save_data: Dictionary = {}
	if save_graph != null:
		save_data = save_graph.get_section_data(GameSaveGraphUtility.PROGRESS_SECTION_ID)
	_ensure_game_data_defaults(save_data)
	return save_data


func _ensure_game_data_defaults(save_data: Dictionary) -> void:
	if not save_data.has(_KEY_STATS) or not (save_data[_KEY_STATS] is Dictionary):
		save_data[_KEY_STATS] = {}
	if not save_data.has(_KEY_RESULTS) or not (save_data[_KEY_RESULTS] is Array):
		save_data[_KEY_RESULTS] = []
	if (
		not save_data.has(_KEY_LEADERBOARDS)
		or not (save_data[_KEY_LEADERBOARDS] is Dictionary)
	):
		save_data[_KEY_LEADERBOARDS] = {}


func _get_stats(save_data: Dictionary) -> Dictionary:
	_ensure_game_data_defaults(save_data)
	var stats_value: Variant = save_data[_KEY_STATS]
	if stats_value is Dictionary:
		var stats: Dictionary = stats_value
		return stats
	return {}


func _get_mode_stats(stats: Dictionary, mode_id: String) -> Dictionary:
	var mode_stats_value: Variant = stats.get(mode_id, {})
	if mode_stats_value is Dictionary:
		var mode_stats: Dictionary = mode_stats_value
		return mode_stats

	return {}


func _get_stats_entry(save_data: Dictionary, mode_id: String, board_key: String) -> Dictionary:
	var stats: Dictionary = _get_stats(save_data)
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	var entry_value: Variant = mode_stats.get(board_key, {})
	if entry_value is Dictionary:
		var entry: Dictionary = entry_value
		return entry

	return {}


func _set_stats_entry(
	save_data: Dictionary,
	mode_id: String,
	board_key: String,
	entry: Dictionary
) -> void:
	var stats: Dictionary = _get_stats(save_data)
	var mode_stats: Dictionary = _get_mode_stats(stats, mode_id)
	mode_stats[board_key] = entry
	stats[mode_id] = mode_stats


func _normalize_stats_entry(entry: Dictionary) -> Dictionary:
	var normalized: Dictionary = _make_default_stats()
	for key: Variant in entry.keys():
		normalized[key] = entry[key]

	normalized[_STAT_PLAYS] = maxi(GFVariantData.get_option_int(normalized, _STAT_PLAYS, 0), 0)
	normalized[_STAT_BEST_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_BEST_SCORE, 0), 0)
	normalized[_STAT_BEST_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_BEST_STEPS, 0), 0)
	normalized[_STAT_MAX_TILE] = maxi(GFVariantData.get_option_int(normalized, _STAT_MAX_TILE, 0), 0)
	normalized[_STAT_LAST_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_SCORE, 0), 0)
	normalized[_STAT_LAST_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_STEPS, 0), 0)
	normalized[_STAT_LAST_MAX_TILE] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_MAX_TILE, 0), 0)
	normalized[_STAT_LAST_PLAYED_AT] = maxi(GFVariantData.get_option_int(normalized, _STAT_LAST_PLAYED_AT, 0), 0)
	normalized[_STAT_TOTAL_DURATION_MSEC] = maxi(
		GFVariantData.get_option_int(
			normalized,
			_STAT_TOTAL_DURATION_MSEC,
			0
		),
		0
	)
	normalized[_STAT_DURATION_SAMPLES] = maxi(
		GFVariantData.get_option_int(normalized, _STAT_DURATION_SAMPLES, 0),
		0
	)
	normalized[_STAT_BEST_DURATION_MSEC] = maxi(
		GFVariantData.get_option_int(
			normalized,
			_STAT_BEST_DURATION_MSEC,
			0
		),
		0
	)
	normalized[_STAT_LAST_DURATION_MSEC] = maxi(
		GFVariantData.get_option_int(
			normalized,
			_STAT_LAST_DURATION_MSEC,
			0
		),
		0
	)
	normalized[_STAT_TOTAL_SCORE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TOTAL_SCORE, 0), 0)
	normalized[_STAT_TOTAL_STEPS] = maxi(GFVariantData.get_option_int(normalized, _STAT_TOTAL_STEPS, 0), 0)
	normalized[_STAT_STEP_SAMPLES] = maxi(GFVariantData.get_option_int(normalized, _STAT_STEP_SAMPLES, 0), 0)
	normalized[_STAT_TARGET_VALUE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TARGET_VALUE, 0), 0)
	normalized[_STAT_TARGET_REACHED_COUNT] = _normalize_target_reached_count(normalized)
	normalized[_STAT_TARGET_REACHED_RATE] = maxi(GFVariantData.get_option_int(normalized, _STAT_TARGET_REACHED_RATE, 0), 0)
	normalized[_STAT_LAST_TARGET_REACHED] = GFVariantData.get_option_bool(
		normalized,
		_STAT_LAST_TARGET_REACHED,
		false
	)

	_update_average_stats(normalized)
	_update_target_stats(normalized)
	return normalized


func _make_default_stats() -> Dictionary:
	return {
		_STAT_PLAYS: 0,
		_STAT_BEST_SCORE: 0,
		_STAT_BEST_STEPS: 0,
		_STAT_MAX_TILE: 0,
		_STAT_TOTAL_SCORE: 0,
		_STAT_TOTAL_STEPS: 0,
		_STAT_STEP_SAMPLES: 0,
		_STAT_AVERAGE_SCORE: 0,
		_STAT_AVERAGE_STEPS: 0,
		_STAT_TARGET_VALUE: 0,
		_STAT_TARGET_REACHED_COUNT: 0,
		_STAT_TARGET_REACHED_RATE: 0,
		_STAT_LAST_TARGET_REACHED: false,
		_STAT_LAST_SCORE: 0,
		_STAT_LAST_STEPS: 0,
		_STAT_LAST_MAX_TILE: 0,
		_STAT_LAST_PLAYED_AT: 0,
		_STAT_TOTAL_DURATION_MSEC: 0,
		_STAT_DURATION_SAMPLES: 0,
		_STAT_BEST_DURATION_MSEC: 0,
		_STAT_AVERAGE_DURATION_MSEC: 0,
		_STAT_LAST_DURATION_MSEC: 0,
	}


static func _update_average_stats(entry: Dictionary) -> void:
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var total_score: int = GFVariantData.get_option_int(entry, _STAT_TOTAL_SCORE, 0)
	var step_samples: int = GFVariantData.get_option_int(entry, _STAT_STEP_SAMPLES, 0)
	var total_steps: int = GFVariantData.get_option_int(entry, _STAT_TOTAL_STEPS, 0)
	entry[_STAT_AVERAGE_SCORE] = _rounded_average(total_score, plays)
	entry[_STAT_AVERAGE_STEPS] = _rounded_average(total_steps, step_samples)
	entry[_STAT_AVERAGE_DURATION_MSEC] = _rounded_average(
		GFVariantData.get_option_int(entry, _STAT_TOTAL_DURATION_MSEC, 0),
		GFVariantData.get_option_int(entry, _STAT_DURATION_SAMPLES, 0)
	)


static func _update_target_stats(entry: Dictionary) -> void:
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var target_value: int = GFVariantData.get_option_int(entry, _STAT_TARGET_VALUE, 0)
	var reached_count: int = _normalize_target_reached_count(entry)
	entry[_STAT_TARGET_REACHED_COUNT] = reached_count
	if target_value <= 0 or plays <= 0:
		entry[_STAT_TARGET_REACHED_RATE] = 0
		return
	entry[_STAT_TARGET_REACHED_RATE] = _rounded_average(reached_count * 100, plays)


static func _normalize_target_reached_count(entry: Dictionary) -> int:
	var plays: int = GFVariantData.get_option_int(entry, _STAT_PLAYS, 0)
	var target_value: int = GFVariantData.get_option_int(entry, _STAT_TARGET_VALUE, 0)
	var reached_count: int = GFVariantData.get_option_int(entry, _STAT_TARGET_REACHED_COUNT, 0)
	if plays <= 0 or target_value <= 0:
		return 0
	return clampi(reached_count, 0, plays)


static func _rounded_average(total_value: int, sample_count: int) -> int:
	if sample_count <= 0:
		return 0
	var normalized_total: int = maxi(total_value, 0)
	return roundi(float(normalized_total) / float(sample_count))


func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _get_save_graph_utility()
	return _save_graph


func _get_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = utility_value
		return save_graph
	return null


func _get_account_catalog_utility() -> LocalAccountCatalogUtility:
	var utility_value: Object = get_utility(LocalAccountCatalogUtility)
	if utility_value is LocalAccountCatalogUtility:
		var account_catalog: LocalAccountCatalogUtility = utility_value
		return account_catalog
	return null


func _get_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_unix_timestamp() -> int:
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	_clock = _get_clock_utility()
	if is_instance_valid(_clock):
		return _clock.get_unix_timestamp()

	push_error("[ProgressStatsSystem] 缺少 GameClockUtility，无法记录游戏结果时间戳。")
	return 0
