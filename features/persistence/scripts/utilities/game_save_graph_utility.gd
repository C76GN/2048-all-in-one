## GameSaveGraphUtility: 玩家数据 GF Save Profile 边界。
##
## 项目继续由各 Feature 拥有 section 业务字段；跨 section 的采集、异步 IO、
## generation 合并、有界重试、严格校验和事务回滚统一交给 GFSaveProfileUtility。
## 本 Utility 只拥有账号文件选择、破坏性 pre-release schema reset 和业务入口。
class_name GameSaveGraphUtility
extends GFUtility


# --- 信号 ---

## 高频业务更新已进入待持久化状态。
signal profile_save_queued()

## 保存终态通知；error 只来自已完成的 GFSaveProfileResult。
signal profile_save_completed(error: Error)

## 任一 GF Save Profile 操作的类型化终态。
signal profile_operation_completed(result: GFSaveProfileResult)
signal profile_cleanup_task_terminal(work_id: StringName)
## 任一项目 section 持久化事务的类型化终态。
signal section_operation_completed(result: GameSaveSectionResult)
## outcome_unknown 的 section 事务在 GF detached 写入收敛后发布一次证据。
signal section_reconciliation_settled(evidence: Dictionary)


# --- 常量 ---

const PROFILE_FILE_NAME: String = "player_data.save"
const PROFILE_SCHEMA_ID: StringName = &"player_data"
## GFSaveProfile 格式首次启用；旧 v10 SaveGraph 只备份后重建，不在运行时双读。
const PROFILE_SCHEMA_VERSION: int = 11
const PROGRESS_SECTION_ID: StringName = &"progress"
const BOOKMARKS_SECTION_ID: StringName = &"bookmarks"
const CUSTOM_BOARDS_SECTION_ID: StringName = &"custom_boards"
const DISCOVERIES_SECTION_ID: StringName = &"discoveries"
const ACHIEVEMENTS_SECTION_ID: StringName = &"achievements"
const REPLAYS_SECTION_ID: StringName = &"replays"

const _RECOVERY_DIRECTORY: String = "recovery"
const _REJECTED_PROFILE_ID: StringName = &"project.rejected_profile"
const _PROJECT_VERSION_SETTING: String = "application/config/version"
const _LOG_TAG: String = "GameSaveGraphUtility"
const _ASYNC_SAVE_DEBOUNCE_SECONDS: float = 0.16
const _LIFECYCLE_PRIORITY: int = -100
const _SYNC_OPERATION_TIMEOUT_MSEC: int = 20_000
const _SYNC_OPERATION_MAX_POLL_COUNT: int = 20_000
const _PROFILE_IO_TIMEOUT_MSEC: int = 5_000
const _PROFILE_DELETE_TIMEOUT_MSEC: int = 5_000
const _PROFILE_RETRY_DELAYS_MSEC: Array[int] = [
	100,
	500,
	1_500,
]

## 项目拥有的 section 应用顺序；不再借用已移除的 GFSaveScope 类型。
enum SectionOrder {
	EARLY,
	NORMAL,
	LATE,
}


# --- 公共变量 ---

## 独立使用时保持旧的默认 Profile 自动加载；多账号架构会关闭并由账号系统引导。
var auto_load_legacy_profile_on_ready: bool = true


# --- 私有变量 ---

var _section_definitions: Dictionary = {}
var _section_providers: Dictionary = {}
var _default_section_payloads: Dictionary = {}
var _profile_utility: GFSaveProfileUtility = null
var _active_profile: GFSaveProfile = null
var _active_profile_id: StringName = &""
## 保留已注册 Profile，让 GF 持有 detached/outcome_unknown 写入及路径所有权。
## 设备最多 8 个账号，连同 legacy/default Profile，集合天然有界。
var _registered_profiles: Dictionary = {}
var _storage: GFStorageUtility = null
var _background_work: GFBackgroundWorkUtility = null
var _clock: GameClockUtility = null
var _log: GFLogUtility = null
var _platform: GamePlatformUtility = null
var _signal_utility: GFSignalUtility = null
## 开发诊断能力按构建可选安装；只能通过 local lookup 探测，不能声明为生产依赖。
var _async_tracker: GFAsyncTrackerUtility = null
var _async_tracking_ids: Dictionary = {}
var _loaded: bool = false
var _last_load_result: Dictionary = {}
var _last_save_result: Dictionary = {}
var _profile_save_pending: bool = false
var _profile_save_wait_seconds: float = 0.0
var _profile_transition_in_progress: bool = false
var _platform_backgrounded: bool = false
var _profile_file_name: String = PROFILE_FILE_NAME
var _profile_delete_tasks: Dictionary = {}
var _profile_delete_workers: Dictionary = {}
var _profile_delete_deadlines: Dictionary = {}
var _profile_delete_timed_out: Dictionary = {}
var _profile_delete_waiters: Dictionary = {}
var _profile_delete_file_names: Dictionary = {}
var _profile_cleanup_paths: Dictionary = {}
var _profile_delete_serial: int = 0
var _disposing: bool = false
var _disposed: bool = false
var _profile_transition_epoch: int = 0
var _profile_transition_outcome_unknown: bool = false
var _last_profile_transition_evidence: Dictionary = {}
var _section_operation_serial: int = 0
var _pending_section_operation: GameSaveSectionOperation = null
var _pending_section_profile_id: StringName = &""
var _pending_section_ids: Dictionary = {}
var _pending_section_snapshots: Dictionary = {}
var _pending_section_applied_keys: Array[String] = []
var _pending_section_save_operation: GFSaveProfileOperation = null
var _pending_section_save_callback: Callable = Callable()
var _pending_section_compensation_operation: GFSaveProfileOperation = null
var _pending_section_compensation_callback: Callable = Callable()
var _pending_section_original_result: GFSaveProfileResult = null
var _section_reconciliation: Dictionary = {}
var _section_reconciliation_operation: GFSaveProfileOperation = null
var _section_reconciliation_callback: Callable = Callable()
var _last_section_reconciliation_evidence: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	ignore_pause = true
	ignore_time_scale = true
	lifecycle_priority = _LIFECYCLE_PRIORITY
	_compile_section_providers()


func get_required_utilities() -> Array[Script]:
	return [
		GFStorageUtility,
		GFBackgroundWorkUtility,
		GFSaveProfileUtility,
		GameClockUtility,
		GFLogUtility,
		GamePlatformUtility,
		GFSignalUtility,
	]


func ready() -> void:
	_disposing = false
	_disposed = false
	_storage = _resolve_storage_utility()
	_background_work = _resolve_background_work_utility()
	_profile_utility = _resolve_profile_utility()
	_clock = _resolve_clock_utility()
	_log = _resolve_log_utility()
	_platform = _resolve_platform_utility()
	_signal_utility = _resolve_signal_utility()
	_async_tracker = _resolve_optional_async_tracker()
	if (
		_storage == null
		or _background_work == null
		or _profile_utility == null
		or _clock == null
		or _signal_utility == null
		or _section_providers.is_empty()
	):
		_record_configuration_failure()
		return

	var _operation_connection: GFSignalConnection = _signal_utility.connect_signal(
		_profile_utility.profile_operation_completed,
		_on_profile_operation_completed,
		self
	)
	var _background_connections: Array[GFSignalConnection] = (
		_signal_utility.connect_any(
			[
				_background_work.work_completed,
				_background_work.work_failed,
				_background_work.work_cancelled,
			],
			_on_background_work_terminal,
			self
		)
	)
	if is_instance_valid(_platform):
		var _lifecycle_connection: GFSignalConnection = _signal_utility.connect_signal(
			_platform.lifecycle_event_received,
			_on_platform_lifecycle_event_received,
			self
		)

	var register_error: Error = _register_active_profile(PROFILE_FILE_NAME)
	if register_error != OK:
		_record_configuration_failure(register_error)
		return
	if not auto_load_legacy_profile_on_ready:
		return
	var load_error: Error = load_profile()
	if load_error != OK:
		_log_error("玩家 Profile 加载失败，错误码：%d。" % load_error)


## 驱动保存 debounce 与后台清理超时。
## @param delta: 自上一帧起的秒数。
func tick(delta: float = 0.0) -> void:
	_tick_profile_delete_timeouts()
	_tick_section_reconciliation()
	if not _profile_save_pending or not _loaded:
		return
	# 账号切换事务会在入口冲刷旧 Profile；事务期间新产生的更新保持
	# pending，等新 Profile 确认激活后再开始 debounce，不能在 tick 中
	# 篡改 transition 锁或把更新写进尚未提交的目标 Profile。
	if _profile_transition_in_progress:
		return
	_profile_save_wait_seconds += maxf(delta, 0.0)
	if _profile_save_wait_seconds < _ASYNC_SAVE_DEBOUNCE_SECONDS:
		return
	_profile_save_pending = false
	_profile_save_wait_seconds = 0.0
	var _operation: GFSaveProfileOperation = request_save_profile({
		&"reason": "debounced_feature_update",
	})


func dispose() -> void:
	_disposing = true
	_profile_transition_epoch += 1
	_profile_transition_in_progress = false
	var flush_error: Error = flush_pending_save()
	if flush_error != OK:
		_log_error("退出前冲刷玩家 Profile 失败，错误码：%d。" % flush_error)
	_settle_pending_section_operation_for_dispose()
	_disconnect_section_operation_callbacks()
	if is_instance_valid(_background_work):
		for task_value: Variant in _profile_delete_tasks.values():
			if not (task_value is GFBackgroundWorkTask):
				continue
			var task: GFBackgroundWorkTask = task_value
			if not task.is_finished():
				var _cancelled: bool = (
					_background_work.cancel_work(task.work_id)
				)
			profile_cleanup_task_terminal.emit(task.work_id)
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_clear_async_tracking()
	_disposed = true
	_profile_delete_tasks.clear()
	_profile_delete_workers.clear()
	_profile_delete_deadlines.clear()
	_profile_delete_timed_out.clear()
	_profile_delete_waiters.clear()
	_profile_delete_file_names.clear()
	_profile_cleanup_paths.clear()
	if _profile_utility != null:
		for profile_id_value: Variant in _registered_profiles.keys():
			var profile_id: StringName = GFVariantData.to_string_name(
				profile_id_value
			)
			if not _profile_utility.unregister_profile(profile_id):
				_log_error(
					"架构销毁时 Profile 仍有框架在途所有权：%s。"
					% String(profile_id)
				)
	_profile_utility = null
	_active_profile = null
	_active_profile_id = &""
	_registered_profiles.clear()
	_section_providers.clear()
	_section_definitions.clear()
	_default_section_payloads.clear()
	_last_load_result.clear()
	_last_save_result.clear()
	_profile_save_pending = false
	_profile_save_wait_seconds = 0.0
	_platform_backgrounded = false
	_profile_file_name = PROFILE_FILE_NAME
	_loaded = false
	_profile_transition_outcome_unknown = false
	_last_profile_transition_evidence.clear()
	_pending_section_operation = null
	_pending_section_profile_id = &""
	_pending_section_ids.clear()
	_pending_section_snapshots.clear()
	_pending_section_applied_keys.clear()
	_pending_section_save_operation = null
	_pending_section_save_callback = Callable()
	_pending_section_compensation_operation = null
	_pending_section_compensation_callback = Callable()
	_pending_section_original_result = null
	_section_reconciliation.clear()
	_section_reconciliation_operation = null
	_section_reconciliation_callback = Callable()
	_last_section_reconciliation_evidence.clear()
	_storage = null
	_background_work = null
	_signal_utility = null
	_async_tracker = null
	_clock = null
	_log = null
	_platform = null


# --- 公共方法 ---

## 在 GF init 前登记一个 Feature section。
##
## phase 仅用于保持既有项目 apply 顺序；GFSaveProfile 使用排序后的 provider 数组。
## @param section_id: Feature section 的稳定标识。
## @param provider: 拥有该 section schema 与状态的项目 Provider。
## @param phase: 项目固定 section 的应用顺序。
func register_section(
	section_id: StringName,
	provider: GameSaveSectionData,
	phase: SectionOrder = SectionOrder.NORMAL
) -> bool:
	if not _section_providers.is_empty():
		push_error("[GameSaveGraphUtility] register_section 只能在 init 前调用。")
		return false
	if section_id == &"" or provider == null:
		return false
	if provider.section_id != section_id or provider.schema_version <= 0:
		push_error(
			"[GameSaveGraphUtility] section provider 契约不匹配：%s。"
			% String(section_id)
		)
		return false
	var key: String = String(section_id)
	if _section_definitions.has(key):
		push_error("[GameSaveGraphUtility] section 重复：%s。" % key)
		return false
	_section_definitions[key] = {
		&"provider": provider,
		&"phase": int(phase),
	}
	_default_section_payloads[key] = provider.to_dict()
	return true


## 获取 section 业务数据副本。
## @param section_id: 要读取的 Feature section 标识。
func get_section_data(section_id: StringName) -> Dictionary:
	var provider: GameSaveSectionData = _get_section_provider(section_id)
	return provider.get_section_data() if provider != null else {}


## 返回 Feature provider 的隔离运行时缓存快照；该数据不进入持久化文档。
##
## 调用方拥有返回值，可安全修改或跨帧缓存，不会改写 provider 权威状态。
## @param section_id: 要读取的当前 Profile section。
func get_section_runtime_cache_snapshot(section_id: StringName) -> Dictionary:
	var provider: GameSaveSectionData = _get_section_provider(section_id)
	return (
		provider.get_runtime_section_cache_snapshot()
		if provider != null
		else {}
	)


## 返回当前玩家 Profile 的存储相对路径。
func get_profile_file_name() -> String:
	return _profile_file_name


## 返回当前 GF Profile 的运行时 ID。
func get_active_profile_id() -> StringName:
	return _active_profile_id


## 最近一次 Profile 切换是否进入“写入结果未知”终态。
##
## 调用方必须保留账号目录和 Profile 路径，等待 GF 的 detached 写收敛，
## 不能按普通失败删除文件或复用路径。
func was_last_profile_transition_outcome_unknown() -> bool:
	return _profile_transition_outcome_unknown


## 返回最近一次切换的框架类型化证据。
func get_last_profile_transition_evidence() -> Dictionary:
	return _last_profile_transition_evidence.duplicate(true)


## 返回指定 Profile 路径是否仍由后台清理任务持有。
##
## timeout 只终结等待者，不代表线程已停止；账号协调必须等本查询变为 false
## 后才能重试清理或解除路径所有权。
## @param profile_file_name: 待查询的 Profile 规范文件名。
func is_profile_cleanup_pending(profile_file_name: String) -> bool:
	if profile_file_name.is_empty() or _storage == null:
		return false
	var canonical_name: String = (
		_storage.canonicalize_data_file_name(profile_file_name)
	)
	return (
		not canonical_name.is_empty()
		and _profile_cleanup_paths.has(canonical_name)
	)


## 返回当前在途 section 事务；没有事务时返回 null。
func get_pending_section_operation() -> GameSaveSectionOperation:
	return _pending_section_operation


## 返回 outcome_unknown section 事务是否仍在等待 GF late settlement。
func is_section_reconciliation_pending() -> bool:
	return not _section_reconciliation.is_empty()


## 返回当前 reconciliation 对应的 section 事务标识；没有等待时返回 0。
func get_pending_section_reconciliation_transaction_id() -> int:
	return GFVariantData.get_option_int(
		_section_reconciliation,
		&"transaction_id",
		0
	)


## 返回最近一次 section late settlement 的隔离证据。
func get_last_section_reconciliation_evidence() -> Dictionary:
	return _last_section_reconciliation_evidence.duplicate(true)


## 请求保存当前 Profile，并返回唯一类型化终态句柄。
## @param metadata: GF Profile 操作诊断元数据。
## @param context: 传给各 section Provider 的只读采集上下文。
func request_save_profile(
	metadata: Dictionary = {},
	context: Dictionary = {}
) -> GFSaveProfileOperation:
	if (
		_profile_transition_in_progress
		or _profile_utility == null
		or _active_profile_id == &""
	):
		return _make_rejected_profile_operation(
			GFSaveProfileOperation.OPERATION_SAVE
		)
	return _request_save_active_profile(metadata, context)


## 请求加载当前 Profile，并返回唯一类型化终态句柄。
## @param context: 传给各 section Provider 的应用上下文。
## @param metadata: GF Profile 操作诊断元数据。
func request_load_profile(
	context: Dictionary = {},
	metadata: Dictionary = {}
) -> GFSaveProfileOperation:
	if (
		_profile_transition_in_progress
		or _profile_utility == null
		or _active_profile_id == &""
	):
		return _make_rejected_profile_operation(
			GFSaveProfileOperation.OPERATION_LOAD
		)
	return _track_profile_operation(
		_profile_utility.load_profile(
			_active_profile_id,
			context,
			metadata
		)
	)


## 请求等待调用时可见的最新 generation 持久化。
## @param metadata: GF Profile 刷新操作诊断元数据。
func request_flush_profile(
	metadata: Dictionary = {}
) -> GFSaveProfileOperation:
	if (
		_profile_transition_in_progress
		or _profile_utility == null
		or _active_profile_id == &""
	):
		return _make_rejected_profile_operation(
			GFSaveProfileOperation.OPERATION_FLUSH
		)
	if _profile_save_pending:
		_profile_save_pending = false
		_profile_save_wait_seconds = 0.0
		var _save_operation: GFSaveProfileOperation = _request_save_active_profile({
			&"reason": "flush_pending_generation",
		})
	return _track_profile_operation(
		_profile_utility.flush_profile(_active_profile_id, metadata)
	)


## 在架构启动期加载账号 Profile，避免先完整加载旧默认 Profile 再切换账号。
##
## 目标已存在时只加载目标；目标缺失且旧 Profile 存在时执行一次兼容迁移；
## 两者都不存在时直接用 section 默认值初始化目标 Profile。
## @param profile_file_name: 当前账号对应的 Profile 相对路径。
## @param adopt_legacy_if_missing: 目标缺失时是否迁移旧默认 Profile。
func bootstrap_profile(
	profile_file_name: String,
	adopt_legacy_if_missing: bool = true
) -> Error:
	if _disposed:
		return ERR_UNAVAILABLE
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		return ERR_BUSY
	if not _is_account_profile_file_name_valid(profile_file_name):
		return ERR_INVALID_PARAMETER
	if _profile_cleanup_paths.has(profile_file_name):
		return ERR_BUSY
	if not _is_configured():
		return ERR_UNCONFIGURED
	if _loaded:
		return activate_profile(
			profile_file_name,
			adopt_legacy_if_missing
		)
	if profile_file_name == _profile_file_name:
		return load_profile()

	var target_read: GFStorageReadResult = _storage.load_data(
		profile_file_name
	)
	var target_missing: bool = (
		not target_read.ok
		and target_read.error_code == ERR_FILE_NOT_FOUND
	)
	if target_missing and adopt_legacy_if_missing:
		var legacy_read: GFStorageReadResult = _storage.load_data(
			PROFILE_FILE_NAME
		)
		if (
			legacy_read.ok
			or legacy_read.error_code != ERR_FILE_NOT_FOUND
		):
			var legacy_load_error: Error = load_profile()
			if legacy_load_error != OK:
				return legacy_load_error
			return _adopt_current_profile(profile_file_name)

	return _bootstrap_unloaded_profile(
		profile_file_name,
		target_missing
	)


## 原子切换到另一个账号的独立 Profile。
##
## 这是架构 init/ready 启动阶段的真实终态边界：方法等待 GF 类型化
## operation 完成后才返回 OK，不会把“已排队”伪装成“已持久化”。
## @param profile_file_name: 目标账号 Profile 的存储相对路径。
## @param adopt_current_if_missing: 目标不存在时是否以当前内存 section 初始化。
func activate_profile(
	profile_file_name: String,
	adopt_current_if_missing: bool = false
) -> Error:
	if _disposed:
		return ERR_UNAVAILABLE
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		return ERR_BUSY
	if not _is_account_profile_file_name_valid(profile_file_name):
		return ERR_INVALID_PARAMETER
	if _profile_cleanup_paths.has(profile_file_name):
		return ERR_BUSY
	if profile_file_name == _profile_file_name:
		return OK
	if not _is_configured() or not _loaded:
		return ERR_UNCONFIGURED
	_profile_transition_outcome_unknown = false
	_last_profile_transition_evidence.clear()

	var flush_error: Error = flush_pending_save()
	if flush_error != OK:
		return flush_error
	var target_read: GFStorageReadResult = _storage.load_data(profile_file_name)
	var target_missing: bool = (
		not target_read.ok
		and target_read.error_code == ERR_FILE_NOT_FOUND
	)
	if (
		target_missing
		and adopt_current_if_missing
		and _profile_file_name == PROFILE_FILE_NAME
	):
		return _adopt_current_profile(profile_file_name)

	var previous_profile: GFSaveProfile = _active_profile
	var previous_profile_id: StringName = _active_profile_id
	var previous_file_name: String = _profile_file_name
	var previous_loaded: bool = _loaded
	var previous_load_result: Dictionary = _last_load_result.duplicate(true)
	var previous_save_result: Dictionary = _last_save_result.duplicate(true)
	var section_snapshots: Dictionary = _snapshot_all_sections()

	var reset_error: Error = _reset_sections_to_defaults()
	if reset_error != OK:
		return reset_error
	var register_error: Error = _register_active_profile(profile_file_name)
	if register_error != OK:
		var _restore_error: Error = _restore_all_sections(section_snapshots)
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			previous_loaded,
			previous_load_result,
			previous_save_result
		)
		return register_error

	var load_error: Error = load_profile()
	if load_error == OK and target_missing:
		load_error = save_profile()
	if load_error == OK:
		return OK

	var restore_error: Error = _restore_all_sections(section_snapshots)
	_restore_active_profile_reference(
		previous_profile,
		previous_profile_id,
		previous_file_name,
		previous_loaded,
		previous_load_result,
		previous_save_result
	)
	return load_error if restore_error == OK else restore_error


## 异步切换账号 Profile；UI 调用方应使用此入口避免主线程等待磁盘 IO。
##
## 每个 GF operation 都被等待到唯一类型化终态。事务进行时拒绝并发切换；
## 失败会恢复旧 Profile 引用和全部 section 内存快照。
## @param profile_file_name: 目标账号 Profile 的存储相对路径。
## @param adopt_current_if_missing: 目标不存在时是否以当前内存 section 初始化。
func activate_profile_async(
	profile_file_name: String,
	adopt_current_if_missing: bool = false
) -> Error:
	if _disposed:
		return ERR_UNAVAILABLE
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		return ERR_BUSY
	if not _is_account_profile_file_name_valid(profile_file_name):
		return ERR_INVALID_PARAMETER
	if _profile_cleanup_paths.has(profile_file_name):
		return ERR_BUSY
	if profile_file_name == _profile_file_name:
		return OK
	if not _is_configured() or not _loaded:
		return ERR_UNCONFIGURED
	_profile_transition_in_progress = true
	_profile_transition_epoch += 1
	_profile_transition_outcome_unknown = false
	_last_profile_transition_evidence.clear()
	var transition_epoch: int = _profile_transition_epoch
	var error: Error = await _activate_profile_async_impl(
		profile_file_name,
		adopt_current_if_missing,
		transition_epoch
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	_profile_transition_in_progress = false
	return error


## 在 GFBackgroundWorkUtility 拥有的 IO 任务中删除非当前账号 Profile。
##
## UI 账号事务等待 GFBackgroundWorkTask 到达唯一终态；任务由本 Utility
## 保留到终结，并在架构 dispose 时统一取消，避免主线程同步 delete_file。
## @param profile_file_name: 要删除的非活动账号 Profile 相对路径。
func delete_inactive_profile_async(
	profile_file_name: String
) -> Error:
	if not _is_account_profile_file_name_valid(profile_file_name):
		return ERR_INVALID_PARAMETER
	return await _delete_inactive_profile_file_async(profile_file_name)


## 首个账号确认采用独立 Profile 后，异步删除已不再活跃的 legacy 文件。
func delete_inactive_legacy_profile_async() -> Error:
	if _profile_file_name == PROFILE_FILE_NAME:
		return ERR_INVALID_PARAMETER
	return await _delete_inactive_profile_file_async(PROFILE_FILE_NAME)


## 从当前 GFSaveProfile 文档提取项目 envelope，不应用运行时状态。
## @param profile_payload: GFSaveDocument 的完整序列化字典。
## @param section_id: 要提取的 Feature section 标识。
static func extract_profile_section_envelope(
	profile_payload: Dictionary,
	section_id: StringName
) -> Dictionary:
	if section_id == &"":
		return {}
	var document: GFSaveDocument = GFSaveDocument.from_dict(profile_payload)
	if (
		document == null
		or document.get_schema_id() != PROFILE_SCHEMA_ID
		or document.get_schema_version() != PROFILE_SCHEMA_VERSION
		or not document.has_section(section_id)
	):
		return {}
	var section: GFSaveSection = document.get_section(section_id)
	if section == null or not section.get_payload() is Dictionary:
		return {}
	return {
		&"section_id": String(section_id),
		&"schema_version": section.get_schema_version(),
		&"data": GFVariantData.as_dictionary(
			section.get_payload()
		).duplicate(true),
	}


## 异步原子替换一个 section，并立即返回项目类型化句柄。
##
## @param section_id: 要替换的 Feature section 标识。
## @param data: 当前 section schema 的完整候选业务数据。
## @param metadata: 仅用于诊断的 GF Profile 保存元数据。
func request_replace_section_data(
	section_id: StringName,
	data: Dictionary,
	metadata: Dictionary = {}
) -> GameSaveSectionOperation:
	return request_replace_sections_data(
		{String(section_id): data},
		metadata
	)


## 异步原子替换多个 section；同一时刻只允许一个 immediate transaction。
##
## 已知保存失败会反向恢复内存快照并等待补偿保存；outcome_unknown 不会
## 猜测磁盘结果或回滚候选，而是锁住 Profile 切换直到 detached 写入收敛。
##
## @param sections: section 标识到完整候选业务字典的映射。
## @param metadata: 仅用于诊断的 GF Profile 保存元数据。
func request_replace_sections_data(
	sections: Dictionary,
	metadata: Dictionary = {}
) -> GameSaveSectionOperation:
	_section_operation_serial += 1
	var section_ids: PackedStringArray = _collect_requested_section_ids(
		sections
	)
	if section_ids.is_empty():
		section_ids = PackedStringArray(["invalid"])
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	var _configured: bool = operation.configure_for_utility(
		_section_operation_serial,
		_active_profile_id,
		section_ids
	)
	if _disposing or _disposed:
		_complete_detached_section_operation(
			operation,
			GameSaveSectionResult.STATUS_DISPOSED,
			ERR_UNAVAILABLE
		)
		return operation
	if sections.is_empty() or section_ids == PackedStringArray(["invalid"]):
		_complete_detached_section_operation(
			operation,
			GameSaveSectionResult.STATUS_INVALID_REQUEST,
			ERR_INVALID_PARAMETER
		)
		return operation
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		_complete_detached_section_operation(
			operation,
			GameSaveSectionResult.STATUS_BUSY,
			ERR_BUSY
		)
		return operation
	if not _is_configured() or not _loaded:
		_complete_detached_section_operation(
			operation,
			GameSaveSectionResult.STATUS_INVALID_REQUEST,
			ERR_UNCONFIGURED
		)
		return operation

	_pending_section_operation = operation
	_track_section_operation(operation)
	_pending_section_profile_id = _active_profile_id
	_pending_section_ids = {}
	for section_id: String in section_ids:
		_pending_section_ids[section_id] = true
	_pending_section_snapshots = {}
	_pending_section_applied_keys = []
	var apply_error: Error = _apply_sections_to_memory(
		sections.duplicate(true),
		_pending_section_snapshots,
		_pending_section_applied_keys
	)
	if apply_error != OK:
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_APPLY_FAILED,
			apply_error,
			false,
			false
		)
		return operation

	var save_metadata: Dictionary = metadata.duplicate(true)
	save_metadata[&"reason"] = "immediate_section_replace"
	save_metadata[&"section_transaction_id"] = (
		operation.get_transaction_id()
	)
	save_metadata[&"section_ids"] = section_ids.duplicate()
	_start_pending_section_save(save_metadata)
	return operation


## 创建一个立即拒绝且非 null 的 section 类型化句柄。
##
## Feature System 使用此入口报告候选构造失败，避免 UI 从 null 或异常文本
## 猜测终态；本方法不会触碰 provider 或启动 GF IO。
##
## @param section_id: 被拒绝请求对应的 Feature section 标识。
## @param error_code: 严格候选校验产生的 Godot Error。
func make_rejected_section_operation(
	section_id: StringName,
	error_code: Error
) -> GameSaveSectionOperation:
	_section_operation_serial += 1
	var canonical_id: String = String(section_id).strip_edges()
	if canonical_id.is_empty():
		canonical_id = "invalid"
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	var _configured: bool = operation.configure_for_utility(
		_section_operation_serial,
		_active_profile_id,
		PackedStringArray([canonical_id])
	)
	_complete_detached_section_operation(
		operation,
		GameSaveSectionResult.STATUS_INVALID_REQUEST,
		error_code
	)
	return operation


## 创建一个无需 IO 且立即成功的 section 类型化句柄。
##
## Feature System 仅可用它表达已由稳定业务键证明的幂等 no-op，例如重复
## result_hash；不能用它绕过真实持久化。
##
## @param section_id: 已确认无需改变的 Feature section 标识。
func make_successful_section_operation(
	section_id: StringName
) -> GameSaveSectionOperation:
	_section_operation_serial += 1
	var canonical_id: String = String(section_id).strip_edges()
	if canonical_id.is_empty():
		canonical_id = "invalid"
	var operation: GameSaveSectionOperation = GameSaveSectionOperation.new()
	var _configured: bool = operation.configure_for_utility(
		_section_operation_serial,
		_active_profile_id,
		PackedStringArray([canonical_id])
	)
	var result: GameSaveSectionResult = _make_section_result(
		operation,
		GameSaveSectionResult.STATUS_PERSISTED,
		OK,
		false,
		false
	)
	var _completed: bool = operation.complete_for_utility(result)
	section_operation_completed.emit(result.duplicate_result())
	return operation


## 严格更新一个 section，并把最新 generation 合并到异步写入。
## @param section_id: 要更新的 Feature section 标识。
## @param data: 该 section 的完整业务数据。
func queue_section_data(section_id: StringName, data: Dictionary) -> Error:
	return queue_sections_data({String(section_id): data})


## 合并多个高频 section 更新。
## @param sections: section 标识到完整业务数据的映射。
func queue_sections_data(sections: Dictionary) -> Error:
	if (
		_profile_transition_in_progress
		or is_section_reconciliation_pending()
		or _has_pending_section_conflict(sections)
	):
		return ERR_BUSY
	var snapshots: Dictionary = {}
	var applied_keys: Array[String] = []
	var apply_error: Error = _apply_sections_to_memory(
		sections,
		snapshots,
		applied_keys
	)
	if apply_error != OK:
		return apply_error
	_profile_save_pending = true
	_profile_save_wait_seconds = 0.0
	profile_save_queued.emit()
	return OK


## 等待实际 GF flush 终态，绝不把未完成 operation 报告为成功。
func flush_pending_save() -> Error:
	if not _is_configured():
		return OK if not _loaded else ERR_UNCONFIGURED
	var operation: GFSaveProfileOperation = request_flush_profile({
		&"reason": "explicit_persistence_boundary",
	})
	return _result_to_error(_wait_for_operation(operation))


## 生成当前规范 GFSaveProfile 文档，供诊断与测试只读检查。
func preview_profile_payload() -> Dictionary:
	if _active_profile == null:
		return {}
	var sections: Array[GFSaveSection] = []
	for provider: GameSaveSectionData in _get_ordered_providers():
		var section: GFSaveSection = provider.gather_section({
			&"reason": "preview",
		})
		if section == null:
			return {}
		sections.append(section)
	var document: GFSaveDocument = GFSaveDocument.new().configure(
		PROFILE_SCHEMA_ID,
		PROFILE_SCHEMA_VERSION,
		sections,
		_build_profile_metadata()
	)
	if not GFVariantData.get_option_bool(
		document.validate_document(),
		&"ok",
		false
	):
		return {}
	return document.to_dict()


## 保存完整玩家 Profile，并等待类型化终态。
func save_profile() -> Error:
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		return ERR_BUSY
	if not _is_configured():
		return ERR_UNCONFIGURED
	var operation: GFSaveProfileOperation = request_save_profile({
		&"reason": "explicit_save",
	})
	return _result_to_error(_wait_for_operation(operation))


## 严格加载当前玩家 Profile。
func load_profile() -> Error:
	if (
		_profile_transition_in_progress
		or _has_pending_section_transaction()
		or is_section_reconciliation_pending()
	):
		return ERR_BUSY
	_loaded = false
	if not _is_configured():
		_record_configuration_failure()
		return ERR_UNCONFIGURED
	var recovery: Dictionary = _prepare_profile_file(_profile_file_name)
	@warning_ignore("int_as_enum_without_cast")
	var recovery_error: Error = GFVariantData.get_option_int(
		recovery,
		&"error_code",
		OK
	)
	if recovery_error != OK:
		_last_load_result = recovery
		return recovery_error

	var operation: GFSaveProfileOperation = request_load_profile(
		{&"profile_file": _profile_file_name},
		{&"reason": "activate_profile"}
	)
	var result: GFSaveProfileResult = _wait_for_operation(operation)
	var error: Error = _result_to_error(result)
	_last_load_result = result.to_dict() if result != null else {
		&"ok": false,
		&"error_code": error,
		&"error": "Save Profile load did not reach a terminal result.",
	}
	if error != OK:
		return error
	_loaded = true

	if GFVariantData.get_option_bool(recovery, &"reset", false):
		var recreate_error: Error = save_profile()
		if recreate_error != OK:
			_loaded = false
			return recreate_error
		_last_load_result.merge(recovery, true)
	return OK


func is_profile_loaded() -> bool:
	return _loaded


## 返回 Profile schema、状态机和最近类型化终态。
func get_debug_snapshot() -> Dictionary:
	var profile_state: Dictionary = {}
	if _profile_utility != null and _active_profile_id != &"":
		profile_state = _profile_utility.get_profile_state_snapshot(
			_active_profile_id
		)
	return {
		&"profile_file": _profile_file_name,
		&"profile_id": String(_active_profile_id),
		&"schema_id": String(PROFILE_SCHEMA_ID),
		&"schema_version": PROFILE_SCHEMA_VERSION,
		&"loaded": _loaded,
		&"section_ids": _get_registered_section_ids(),
		&"profile_state": profile_state,
		&"last_load": _last_load_result.duplicate(true),
		&"last_save": _last_save_result.duplicate(true),
		&"save_pending": _profile_save_pending,
	}


# --- 私有/辅助方法 ---

func _delete_inactive_profile_file_async(
	profile_file_name: String
) -> Error:
	if (
		profile_file_name.is_empty()
		or profile_file_name == _profile_file_name
		or _storage == null
		or _background_work == null
		or _clock == null
	):
		return ERR_INVALID_PARAMETER
	var canonical_name: String = (
		_storage.canonicalize_data_file_name(profile_file_name)
	)
	if canonical_name.is_empty():
		return ERR_INVALID_PARAMETER
	if _profile_cleanup_paths.has(canonical_name):
		return ERR_BUSY
	var release_error: Error = _release_profile_for_cleanup(canonical_name)
	if release_error != OK:
		return release_error
	var base_path: String = "user://"
	if not _storage.save_dir_name.is_empty():
		base_path = base_path.path_join(_storage.save_dir_name)
	var profile_path: String = ProjectSettings.globalize_path(
		base_path.path_join(canonical_name)
	)
	_profile_delete_serial += 1
	var work_id: StringName = StringName(
		"profile-delete:%d:%s"
		% [_profile_delete_serial, canonical_name.sha256_text().left(12)]
	)
	var worker: ProfileFileCleanupUtility = ProfileFileCleanupUtility.new()
	var task: GFBackgroundWorkTask = _background_work.submit_io_work(
		Callable(worker, "run"),
		{
			&"paths": PackedStringArray([
				profile_path,
				profile_path + ".tmp",
				profile_path + ".bak",
				profile_path + ".txn",
			]),
		},
		Callable(),
		{
			&"id": work_id,
			&"metadata": {
				&"owner": "GameSaveGraphUtility",
				&"profile_file": canonical_name,
			},
		}
	)
	if task == null:
		return ERR_CANT_CREATE
	_profile_delete_tasks[task.work_id] = task
	_profile_delete_workers[task.work_id] = worker
	_profile_delete_waiters[task.work_id] = true
	_profile_delete_file_names[task.work_id] = canonical_name
	_profile_cleanup_paths[canonical_name] = task.work_id
	_profile_delete_deadlines[task.work_id] = (
		_clock.get_tick_msec() + _PROFILE_DELETE_TIMEOUT_MSEC
	)
	_track_profile_cleanup_task(task, canonical_name)
	while (
		not task.is_finished()
		and not _profile_delete_timed_out.has(task.work_id)
		and not _disposing
	):
		var _terminal_work_id: StringName = (
			await profile_cleanup_task_terminal
		)
	var result_error: Error = (
		_background_delete_task_to_error(task)
		if task.is_finished() or _profile_delete_timed_out.has(task.work_id)
		else ERR_UNAVAILABLE
	)
	var _waiter_erased: bool = _profile_delete_waiters.erase(task.work_id)
	if task.is_finished():
		_cleanup_profile_delete_tracking(task.work_id)
	return result_error


func _compile_section_providers() -> void:
	_section_providers.clear()
	for key: String in _get_sorted_definition_keys():
		var definition: Dictionary = GFVariantData.get_option_dictionary(
			_section_definitions,
			key
		)
		var provider: GameSaveSectionData = _get_provider_value(
			GFVariantData.get_option_value(definition, &"provider")
		)
		if provider != null:
			_section_providers[key] = provider


func _register_active_profile(profile_file_name: String) -> Error:
	if _profile_utility == null:
		return ERR_UNCONFIGURED
	var profile_id: StringName = _make_runtime_profile_id(profile_file_name)
	var registered_value: Variant = GFVariantData.get_option_value(
		_registered_profiles,
		profile_id
	)
	if registered_value is GFSaveProfile:
		var registered_profile: GFSaveProfile = registered_value
		if registered_profile.file_name != profile_file_name:
			return ERR_INVALID_DATA
		if not _is_registered_profile_idle(profile_id):
			_last_profile_transition_evidence = (
				_profile_utility.get_profile_state_snapshot(profile_id)
			)
			_profile_transition_outcome_unknown = (
				GFVariantData.get_option_bool(
					_last_profile_transition_evidence,
					&"write_outcome_unknown",
					false
				)
				or GFVariantData.get_option_int(
					_last_profile_transition_evidence,
					&"detached_write_count",
					0
				)
				> 0
			)
			return ERR_BUSY
		_active_profile = registered_profile
		_active_profile_id = profile_id
		_profile_file_name = profile_file_name
		return OK
	var profile: GFSaveProfile = _make_profile(profile_file_name)
	var report: Dictionary = _profile_utility.register_profile(profile)
	if not GFVariantData.get_option_bool(report, &"registered", false):
		_last_load_result = {
			&"ok": false,
			&"error_code": ERR_INVALID_DATA,
			&"registration": report,
		}
		return ERR_INVALID_DATA
	_registered_profiles[profile.profile_id] = profile
	_active_profile = profile
	_active_profile_id = profile.profile_id
	_profile_file_name = profile_file_name
	return OK


func _bootstrap_unloaded_profile(
	profile_file_name: String,
	target_missing: bool
) -> Error:
	var previous_profile: GFSaveProfile = _active_profile
	var previous_profile_id: StringName = _active_profile_id
	var previous_file_name: String = _profile_file_name
	var previous_load_result: Dictionary = _last_load_result.duplicate(true)
	var previous_save_result: Dictionary = _last_save_result.duplicate(true)
	var section_snapshots: Dictionary = _snapshot_all_sections()

	var reset_error: Error = _reset_sections_to_defaults()
	if reset_error != OK:
		return reset_error
	var register_error: Error = _register_active_profile(profile_file_name)
	if register_error != OK:
		var _restore_error: Error = _restore_all_sections(
			section_snapshots
		)
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			false,
			previous_load_result,
			previous_save_result
		)
		return register_error

	var load_error: Error = load_profile()
	if load_error == OK and target_missing:
		load_error = save_profile()
	if load_error == OK:
		return OK

	var restore_error: Error = _restore_all_sections(section_snapshots)
	_restore_active_profile_reference(
		previous_profile,
		previous_profile_id,
		previous_file_name,
		false,
		previous_load_result,
		previous_save_result
	)
	return load_error if restore_error == OK else restore_error


func _make_profile(profile_file_name: String) -> GFSaveProfile:
	var policy: GFSaveRecoveryPolicy = GFSaveRecoveryPolicy.new()
	policy.missing_file_action = (
		GFSaveRecoveryPolicy.ACTION_USE_CURRENT_STATE
	)
	policy.corrupt_file_action = GFSaveRecoveryPolicy.ACTION_FAIL
	policy.retry_delays_msec = PackedInt32Array(
		_PROFILE_RETRY_DELAYS_MSEC
	)
	policy.io_timeout_msec = _PROFILE_IO_TIMEOUT_MSEC

	var providers: Array[GFSaveSectionProvider] = []
	for provider: GameSaveSectionData in _get_ordered_providers():
		providers.append(provider)
	var profile: GFSaveProfile = GFSaveProfile.new()
	profile.profile_id = _make_runtime_profile_id(profile_file_name)
	profile.schema_id = PROFILE_SCHEMA_ID
	profile.file_name = profile_file_name
	profile.schema_version = PROFILE_SCHEMA_VERSION
	profile.providers = providers
	profile.recovery_policy = policy
	profile.unknown_section_policy = GFSaveProfile.UNKNOWN_SECTION_REJECT
	return profile


func _make_runtime_profile_id(profile_file_name: String) -> StringName:
	if profile_file_name == PROFILE_FILE_NAME:
		return &"player_data.default"
	return StringName("player_data.%s" % profile_file_name.get_file().get_basename())


func _is_registered_profile_idle(profile_id: StringName) -> bool:
	if _profile_utility == null or profile_id == &"":
		return false
	var snapshot: Dictionary = (
		_profile_utility.get_profile_state_snapshot(profile_id)
	)
	return (
		not snapshot.is_empty()
		and GFVariantData.get_option_string_name(
			snapshot,
			&"state"
		)
		== GFSaveProfileUtility.STATE_IDLE
		and GFVariantData.get_option_int(
			snapshot,
			&"save_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"load_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"flush_queue_size",
			0
		)
		== 0
		and GFVariantData.get_option_int(
			snapshot,
			&"detached_write_count",
			0
		)
		== 0
		and not GFVariantData.get_option_bool(
			snapshot,
			&"write_outcome_unknown",
			false
		)
	)


func _release_profile_for_cleanup(profile_file_name: String) -> Error:
	if (
		_profile_utility == null
		or profile_file_name.is_empty()
		or profile_file_name == _profile_file_name
	):
		return ERR_INVALID_PARAMETER
	var profile_id: StringName = _make_runtime_profile_id(
		profile_file_name
	)
	if not _registered_profiles.has(profile_id):
		return OK
	var snapshot: Dictionary = (
		_profile_utility.get_profile_state_snapshot(profile_id)
	)
	if not _profile_utility.unregister_profile(profile_id):
		_last_profile_transition_evidence = snapshot
		_profile_transition_outcome_unknown = (
			GFVariantData.get_option_bool(
				snapshot,
				&"write_outcome_unknown",
				false
			)
			or GFVariantData.get_option_int(
				snapshot,
				&"detached_write_count",
				0
			)
			> 0
		)
		return ERR_BUSY
	var _erased: bool = _registered_profiles.erase(profile_id)
	return OK


func _adopt_current_profile(profile_file_name: String) -> Error:
	var previous_profile: GFSaveProfile = _active_profile
	var previous_profile_id: StringName = _active_profile_id
	var previous_file_name: String = _profile_file_name
	var register_error: Error = _register_active_profile(profile_file_name)
	if register_error != OK:
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			true,
			_last_load_result,
			_last_save_result
		)
		return register_error
	var operation: GFSaveProfileOperation = request_save_profile({
		&"reason": "adopt_legacy_profile",
	})
	var result: GFSaveProfileResult = _wait_for_operation(operation)
	var save_error: Error = _result_to_error(result)
	if save_error != OK:
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			true,
			_last_load_result,
			_last_save_result
		)
		return save_error
	_loaded = true
	_last_load_result = {
		&"ok": true,
		&"error_code": OK,
		&"adopted_current_profile": true,
		&"previous_profile_file": previous_file_name,
		&"profile_file": profile_file_name,
	}
	return OK


func _activate_profile_async_impl(
	profile_file_name: String,
	adopt_current_if_missing: bool,
	transition_epoch: int
) -> Error:
	var flush_result: GFSaveProfileResult = await _await_profile_operation_async(
		_request_flush_active_profile({&"reason": "account_switch"})
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	_record_profile_transition_result(flush_result)
	var flush_error: Error = _result_to_error(flush_result)
	if flush_error != OK:
		return flush_error

	var recovery: Dictionary = await _prepare_profile_file_async(
		profile_file_name,
		transition_epoch
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	@warning_ignore("int_as_enum_without_cast")
	var recovery_error: Error = GFVariantData.get_option_int(
		recovery,
		&"error_code",
		OK
	)
	if recovery_error != OK:
		return recovery_error
	var target_missing: bool = GFVariantData.get_option_bool(
		recovery,
		&"missing",
		false
	)
	if (
		target_missing
		and adopt_current_if_missing
		and _profile_file_name == PROFILE_FILE_NAME
	):
		var adopt_error: Error = await _adopt_current_profile_async(
			profile_file_name,
			transition_epoch
		)
		if not _owns_profile_transition(transition_epoch):
			return ERR_UNAVAILABLE
		return adopt_error

	var previous_profile: GFSaveProfile = _active_profile
	var previous_profile_id: StringName = _active_profile_id
	var previous_file_name: String = _profile_file_name
	var previous_loaded: bool = _loaded
	var previous_load_result: Dictionary = _last_load_result.duplicate(true)
	var previous_save_result: Dictionary = _last_save_result.duplicate(true)
	var section_snapshots: Dictionary = _snapshot_all_sections()
	var reset_error: Error = _reset_sections_to_defaults()
	if reset_error != OK:
		return reset_error
	var register_error: Error = _register_active_profile(profile_file_name)
	if register_error != OK:
		var _restore_error: Error = _restore_all_sections(section_snapshots)
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			previous_loaded,
			previous_load_result,
			previous_save_result
		)
		return register_error

	var load_error: Error = await _load_registered_profile_async(
		recovery,
		transition_epoch
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	if load_error == OK and (
		target_missing
		or GFVariantData.get_option_bool(recovery, &"reset", false)
	):
		load_error = await _save_registered_profile_async(
			{&"reason": "initialize_account_profile"},
			transition_epoch
		)
		if not _owns_profile_transition(transition_epoch):
			return ERR_UNAVAILABLE
	if load_error == OK:
		return OK

	var restore_error: Error = _restore_all_sections(section_snapshots)
	_restore_active_profile_reference(
		previous_profile,
		previous_profile_id,
		previous_file_name,
		previous_loaded,
		previous_load_result,
		previous_save_result
	)
	return load_error if restore_error == OK else restore_error


func _adopt_current_profile_async(
	profile_file_name: String,
	transition_epoch: int
) -> Error:
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	var previous_profile: GFSaveProfile = _active_profile
	var previous_profile_id: StringName = _active_profile_id
	var previous_file_name: String = _profile_file_name
	var previous_load_result: Dictionary = _last_load_result.duplicate(true)
	var previous_save_result: Dictionary = _last_save_result.duplicate(true)
	var register_error: Error = _register_active_profile(profile_file_name)
	if register_error != OK:
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			true,
			previous_load_result,
			previous_save_result
		)
		return register_error
	var save_error: Error = await _save_registered_profile_async(
		{&"reason": "adopt_legacy_profile"},
		transition_epoch
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	if save_error != OK:
		_restore_active_profile_reference(
			previous_profile,
			previous_profile_id,
			previous_file_name,
			true,
			previous_load_result,
			previous_save_result
		)
		return save_error
	_loaded = true
	_last_load_result = {
		&"ok": true,
		&"error_code": OK,
		&"adopted_current_profile": true,
		&"previous_profile_file": previous_file_name,
		&"profile_file": profile_file_name,
	}
	return OK


func _load_registered_profile_async(
	recovery: Dictionary,
	transition_epoch: int
) -> Error:
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	_loaded = false
	var result: GFSaveProfileResult = await _await_profile_operation_async(
		_track_profile_operation(
			_profile_utility.load_profile(
				_active_profile_id,
				{&"profile_file": _profile_file_name},
				{&"reason": "activate_profile_async"}
			)
		)
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	var error: Error = _result_to_error(result)
	_record_profile_transition_result(result)
	_last_load_result = result.to_dict() if result != null else {
		&"ok": false,
		&"error_code": error,
		&"error": "Async Save Profile load did not reach a terminal result.",
	}
	if error == OK:
		_loaded = true
		if GFVariantData.get_option_bool(recovery, &"reset", false):
			_last_load_result.merge(recovery, true)
	return error


func _save_registered_profile_async(
	metadata: Dictionary,
	transition_epoch: int
) -> Error:
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	var document_metadata: Dictionary = _build_profile_metadata()
	document_metadata.merge(metadata, true)
	var result: GFSaveProfileResult = await _await_profile_operation_async(
		_track_profile_operation(
			_profile_utility.save_profile(
				_active_profile_id,
				document_metadata
			)
		)
	)
	if not _owns_profile_transition(transition_epoch):
		return ERR_UNAVAILABLE
	_record_profile_transition_result(result)
	return _result_to_error(result)


func _prepare_profile_file(profile_file_name: String) -> Dictionary:
	var read_result: GFStorageReadResult = _storage.load_data(profile_file_name)
	return _prepare_profile_file_from_read(
		profile_file_name,
		read_result
	)


func _prepare_profile_file_async(
	profile_file_name: String,
	transition_epoch: int
) -> Dictionary:
	if not _owns_profile_transition(transition_epoch):
		return _make_transition_cancelled_recovery()
	var operation: GFStorageAsyncOperation = (
		_storage.load_data_request_async(profile_file_name)
	)
	var result: GFStorageAsyncResult = await _await_storage_operation_async(
		operation
	)
	if not _owns_profile_transition(transition_epoch):
		return _make_transition_cancelled_recovery()
	if result == null or result.get_read_result() == null:
		return {
			&"ok": false,
			&"error_code": (
				result.get_error_code()
				if result != null
				else ERR_CANT_OPEN
			),
			&"error": "Profile preflight read did not return a typed result.",
		}
	var read_result: GFStorageReadResult = result.get_read_result()
	if not read_result.ok:
		if read_result.error_code == ERR_FILE_NOT_FOUND:
			return {&"ok": true, &"error_code": OK, &"missing": true}
		if not ProjectStorageRecoveryPolicy.should_reset_failed_read(
			read_result
		):
			return {
				&"ok": false,
				&"error_code": read_result.error_code,
				&"error": read_result.error,
				&"storage": read_result.to_dict(),
			}
		var corrupt_reset_error: Error = (
			await delete_inactive_profile_async(profile_file_name)
		)
		if not _owns_profile_transition(transition_epoch):
			return _make_transition_cancelled_recovery()
		if corrupt_reset_error == ERR_TIMEOUT:
			_record_cleanup_outcome_unknown(profile_file_name)
		return {
			&"ok": corrupt_reset_error == OK,
			&"error_code": corrupt_reset_error,
			&"reset": corrupt_reset_error == OK,
			&"recovered_unreadable_profile": corrupt_reset_error == OK,
			&"storage": read_result.to_dict(),
		}

	var obsolete_version: int = _get_obsolete_profile_schema_version(
		read_result.payload
	)
	if obsolete_version <= 0:
		return {&"ok": true, &"error_code": OK}
	var profile_key: String = profile_file_name.get_file().get_basename()
	var recovery_file: String = "%s/%s.schema-%d.save" % [
		_RECOVERY_DIRECTORY,
		profile_key,
		obsolete_version,
	]
	var backup_operation: GFStorageAsyncOperation = (
		_storage.save_data_request_async(
			recovery_file,
			read_result.payload
		)
	)
	var backup_result: GFStorageAsyncResult = (
		await _await_storage_operation_async(backup_operation)
	)
	if not _owns_profile_transition(transition_epoch):
		return _make_transition_cancelled_recovery()
	var backup_error: Error = (
		backup_result.get_error_code()
		if backup_result != null
		else ERR_CANT_CREATE
	)
	if backup_error != OK:
		return {
			&"ok": false,
			&"error_code": backup_error,
			&"error": "Obsolete player profile could not be backed up.",
			&"obsolete_schema_version": obsolete_version,
			&"recovery_file": recovery_file,
		}
	var reset_error: Error = await delete_inactive_profile_async(
		profile_file_name
	)
	if not _owns_profile_transition(transition_epoch):
		return _make_transition_cancelled_recovery()
	if reset_error == ERR_TIMEOUT:
		_record_cleanup_outcome_unknown(profile_file_name)
	if reset_error != OK:
		return {
			&"ok": false,
			&"error_code": reset_error,
			&"error": "Obsolete player profile could not be reset.",
			&"obsolete_schema_version": obsolete_version,
			&"recovery_file": recovery_file,
			&"backup_created": true,
		}
	return {
		&"ok": true,
		&"error_code": OK,
		&"reset": true,
		&"recovered_obsolete_profile": true,
		&"obsolete_schema_version": obsolete_version,
		&"current_schema_version": PROFILE_SCHEMA_VERSION,
		&"recovery_file": recovery_file,
	}


func _prepare_profile_file_from_read(
	profile_file_name: String,
	read_result: GFStorageReadResult
) -> Dictionary:
	if read_result == null:
		return {
			&"ok": false,
			&"error_code": ERR_CANT_OPEN,
			&"error": "Profile preflight read returned no result.",
		}
	if not read_result.ok:
		if read_result.error_code == ERR_FILE_NOT_FOUND:
			return {&"ok": true, &"error_code": OK, &"missing": true}
		if ProjectStorageRecoveryPolicy.should_reset_failed_read(read_result):
			var reset_error: Error = (
				ProjectStorageRecoveryPolicy.reset_failed_file(
					_storage,
					profile_file_name,
					read_result
				)
			)
			return {
				&"ok": reset_error == OK,
				&"error_code": reset_error,
				&"reset": reset_error == OK,
				&"recovered_unreadable_profile": reset_error == OK,
				&"storage": read_result.to_dict(),
			}
		return {
			&"ok": false,
			&"error_code": read_result.error_code,
			&"error": read_result.error,
			&"storage": read_result.to_dict(),
		}

	var obsolete_version: int = _get_obsolete_profile_schema_version(
		read_result.payload
	)
	if obsolete_version <= 0:
		return {&"ok": true, &"error_code": OK}
	var profile_key: String = profile_file_name.get_file().get_basename()
	var recovery_file: String = "%s/%s.schema-%d.save" % [
		_RECOVERY_DIRECTORY,
		profile_key,
		obsolete_version,
	]
	var backup_error: Error = _storage.save_data(
		recovery_file,
		read_result.payload
	)
	if backup_error != OK:
		return {
			&"ok": false,
			&"error_code": backup_error,
			&"error": "Obsolete player profile could not be backed up.",
			&"obsolete_schema_version": obsolete_version,
			&"recovery_file": recovery_file,
		}
	var delete_error: Error = _storage.delete_file(profile_file_name)
	if delete_error != OK:
		return {
			&"ok": false,
			&"error_code": delete_error,
			&"error": "Obsolete player profile could not be reset.",
			&"obsolete_schema_version": obsolete_version,
			&"recovery_file": recovery_file,
			&"backup_created": true,
		}
	return {
		&"ok": true,
		&"error_code": OK,
		&"reset": true,
		&"recovered_obsolete_profile": true,
		&"obsolete_schema_version": obsolete_version,
		&"current_schema_version": PROFILE_SCHEMA_VERSION,
		&"recovery_file": recovery_file,
	}


func _get_obsolete_profile_schema_version(payload: Dictionary) -> int:
	var document: GFSaveDocument = GFSaveDocument.from_dict(payload)
	if document == null:
		return 0
	if document.get_schema_id() == PROFILE_SCHEMA_ID:
		var document_version: int = document.get_schema_version()
		if document_version <= 0 or document_version > PROFILE_SCHEMA_VERSION:
			return 0
		# Future section 必须继续由 GFSaveProfileUtility 以 typed
		# future_schema 拒绝，不能因为同一文档还含旧 section 就破坏性重置。
		var has_obsolete_section: bool = false
		for provider: GameSaveSectionData in _get_ordered_providers():
			if (
				provider == null
				or not document.has_section(provider.section_id)
			):
				continue
			var section: GFSaveSection = document.get_section(
				provider.section_id
			)
			if (
				section != null
				and section.get_schema_version() > provider.schema_version
			):
				return 0
			if (
				section != null
				and section.get_schema_version() > 0
				and section.get_schema_version() < provider.schema_version
			):
				has_obsolete_section = true
		if document_version < PROFILE_SCHEMA_VERSION:
			return document_version
		# 顶层版本可能保持不变，而 Feature-owned section 独立升级。
		# 项目声明 reset_allowed 且不保留旧 schema 运行时迁移，因此将
		# 任一已知旧 section 视为整个 Profile 的破坏性升级边界。
		if has_obsolete_section:
			return document_version
		return 0
	var metadata: Dictionary = document.get_metadata()
	if (
		GFVariantData.get_option_string_name(metadata, &"schema_id")
		!= PROFILE_SCHEMA_ID
	):
		return 0
	var metadata_version: int = GFVariantData.get_option_int(
		metadata,
		&"schema_version",
		0
	)
	return (
		metadata_version
		if metadata_version > 0
		and metadata_version < PROFILE_SCHEMA_VERSION
		else 0
	)


func _snapshot_all_sections() -> Dictionary:
	var snapshots: Dictionary = {}
	for key: String in _get_registered_section_ids():
		var provider: GameSaveSectionData = _get_section_provider(
			StringName(key)
		)
		if provider != null:
			snapshots[key] = provider.to_dict()
	return snapshots


func _restore_all_sections(snapshots: Dictionary) -> Error:
	var keys: Array[String] = []
	for key_value: Variant in snapshots.keys():
		keys.append(GFVariantData.to_text(key_value))
	keys.sort()
	for key: String in keys:
		var provider: GameSaveSectionData = _get_section_provider(
			StringName(key)
		)
		if provider == null:
			return ERR_DOES_NOT_EXIST
		var restore_error: Error = provider.replace_from_dict(
			GFVariantData.get_option_dictionary(snapshots, key)
		)
		if restore_error != OK:
			return restore_error
	return OK


func _reset_sections_to_defaults() -> Error:
	return _restore_all_sections(_default_section_payloads)


func _apply_sections_to_memory(
	sections: Dictionary,
	snapshots: Dictionary,
	applied_keys: Array[String]
) -> Error:
	if not _is_configured() or not _loaded:
		return ERR_UNCONFIGURED
	if sections.is_empty():
		return ERR_INVALID_PARAMETER
	var section_keys: Array[String] = []
	var replacements: Dictionary = {}
	for key_value: Variant in sections.keys():
		var key: String = GFVariantData.to_text(key_value).strip_edges()
		if key.is_empty() or section_keys.has(key):
			return ERR_INVALID_PARAMETER
		if _get_section_provider(StringName(key)) == null:
			return ERR_DOES_NOT_EXIST
		if not sections[key_value] is Dictionary:
			return ERR_INVALID_DATA
		section_keys.append(key)
		replacements[key] = GFVariantData.as_dictionary(sections[key_value])
	section_keys.sort()
	for key: String in section_keys:
		var provider: GameSaveSectionData = _get_section_provider(
			StringName(key)
		)
		snapshots[key] = provider.to_dict()
		var replace_error: Error = provider.replace_section_data(
			GFVariantData.get_option_dictionary(replacements, key)
		)
		if replace_error != OK:
			var rollback_error: Error = _rollback_sections(
				applied_keys,
				snapshots
			)
			return replace_error if rollback_error == OK else rollback_error
		applied_keys.append(key)
	return OK


func _rollback_sections(
	applied_keys: Array[String],
	snapshots: Dictionary
) -> Error:
	var first_error: Error = OK
	for index: int in range(applied_keys.size() - 1, -1, -1):
		var key: String = applied_keys[index]
		var provider: GameSaveSectionData = _get_section_provider(
			StringName(key)
		)
		if provider == null:
			if first_error == OK:
				first_error = ERR_DOES_NOT_EXIST
			continue
		var rollback_error: Error = provider.replace_from_dict(
			GFVariantData.get_option_dictionary(snapshots, key)
		)
		if rollback_error != OK:
			if first_error == OK:
				first_error = rollback_error
			push_error(
				"[GameSaveGraphUtility] section 回滚失败：%s，错误码：%d。"
				% [key, rollback_error]
			)
	return first_error


func _collect_requested_section_ids(
	sections: Dictionary
) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var normalized_ids: Dictionary = {}
	for key_value: Variant in sections.keys():
		var section_id: String = GFVariantData.to_text(
			key_value
		).strip_edges()
		if (
			section_id.is_empty()
			or normalized_ids.has(section_id)
			or not sections[key_value] is Dictionary
		):
			return PackedStringArray()
		normalized_ids[section_id] = true
		var _appended_index: int = result.append(section_id)
	result.sort()
	return result


func _has_pending_section_transaction() -> bool:
	return (
		_pending_section_operation != null
		and _pending_section_operation.is_pending()
	)


func _has_pending_section_conflict(sections: Dictionary) -> bool:
	if not _has_pending_section_transaction():
		return false
	for section_id: String in _collect_requested_section_ids(sections):
		if _pending_section_ids.has(section_id):
			return true
	return false


func _start_pending_section_save(metadata: Dictionary) -> void:
	if not _has_pending_section_transaction():
		return
	_pending_section_save_operation = _request_save_active_profile(metadata)
	if _pending_section_save_operation == null:
		_on_pending_section_save_completed(
			null,
			null,
			_pending_section_operation.get_transaction_id()
		)
		return
	var transaction_id: int = (
		_pending_section_operation.get_transaction_id()
	)
	if _pending_section_save_operation.is_completed():
		_on_pending_section_save_completed(
			_pending_section_save_operation.get_result(),
			_pending_section_save_operation,
			transaction_id
		)
		return
	_pending_section_save_callback = Callable(
		self,
		"_on_pending_section_save_completed"
	).bind(
		_pending_section_save_operation,
		transaction_id
	)
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = _pending_section_save_operation.completed.connect(
		_pending_section_save_callback,
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		_on_pending_section_save_completed(
			null,
			_pending_section_save_operation,
			transaction_id
		)


func _on_pending_section_save_completed(
	result: GFSaveProfileResult,
	profile_operation: GFSaveProfileOperation,
	transaction_id: int
) -> void:
	if (
		not _has_pending_section_transaction()
		or _pending_section_operation.get_transaction_id()
		!= transaction_id
		or (
			profile_operation != null
			and _pending_section_save_operation != null
			and not is_same(
				_pending_section_save_operation,
				profile_operation
			)
		)
	):
		return
	_disconnect_pending_section_save_callback()
	_pending_section_save_operation = null
	var save_error: Error = _result_to_error(result)
	if result != null and result.is_successful():
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_PERSISTED,
			OK,
			true,
			false,
			result
		)
		return
	if (
		result != null
		and result.get_status()
		== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	):
		_store_pending_section_reconciliation(
			&"candidate_unknown",
			result.get_requested_generation(),
			result
		)
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
			save_error,
			true,
			false,
			result
		)
		return

	var rollback_error: Error = _rollback_sections(
		_pending_section_applied_keys,
		_pending_section_snapshots
	)
	if rollback_error != OK:
		_store_pending_section_reconciliation(
			&"rollback_failed",
			result.get_requested_generation() if result != null else 0,
			result
		)
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_ROLLBACK_FAILED,
			rollback_error,
			true,
			false,
			result
		)
		return
	_pending_section_original_result = (
		result.duplicate_result() if result != null else null
	)
	_start_pending_section_compensation(save_error)


func _start_pending_section_compensation(
	original_error: Error
) -> void:
	if not _has_pending_section_transaction():
		return
	var failed_status: String = (
		String(_pending_section_original_result.get_status())
		if _pending_section_original_result != null
		else "operation_unavailable"
	)
	_pending_section_compensation_operation = _request_save_active_profile({
		&"reason": "rollback_compensation",
		&"failed_status": failed_status,
		&"section_transaction_id": (
			_pending_section_operation.get_transaction_id()
		),
	})
	if _pending_section_compensation_operation == null:
		_profile_save_pending = true
		_profile_save_wait_seconds = 0.0
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_COMPENSATION_FAILED,
			original_error if original_error != OK else ERR_UNAVAILABLE,
			true,
			true,
			_pending_section_original_result
		)
		return
	var transaction_id: int = (
		_pending_section_operation.get_transaction_id()
	)
	if _pending_section_compensation_operation.is_completed():
		_on_pending_section_compensation_completed(
			_pending_section_compensation_operation.get_result(),
			_pending_section_compensation_operation,
			transaction_id
		)
		return
	_pending_section_compensation_callback = Callable(
		self,
		"_on_pending_section_compensation_completed"
	).bind(
		_pending_section_compensation_operation,
		transaction_id
	)
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = _pending_section_compensation_operation.completed.connect(
		_pending_section_compensation_callback,
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		_on_pending_section_compensation_completed(
			null,
			_pending_section_compensation_operation,
			transaction_id
		)


func _on_pending_section_compensation_completed(
	result: GFSaveProfileResult,
	profile_operation: GFSaveProfileOperation,
	transaction_id: int
) -> void:
	if (
		not _has_pending_section_transaction()
		or _pending_section_operation.get_transaction_id()
		!= transaction_id
		or (
			profile_operation != null
			and _pending_section_compensation_operation != null
			and not is_same(
				_pending_section_compensation_operation,
				profile_operation
			)
		)
	):
		return
	_disconnect_pending_section_compensation_callback()
	_pending_section_compensation_operation = null
	var compensation_error: Error = _result_to_error(result)
	if result != null and result.is_successful():
		var original_error: Error = _result_to_error(
			_pending_section_original_result
		)
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_SAVE_FAILED_ROLLED_BACK,
			original_error,
			true,
			true,
			_pending_section_original_result,
			result
		)
		return
	if (
		result != null
		and result.get_status()
		== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	):
		_store_pending_section_reconciliation(
			&"compensation_unknown",
			result.get_requested_generation(),
			_pending_section_original_result,
			result
		)
		_complete_pending_section_operation(
			GameSaveSectionResult.STATUS_ROLLBACK_OUTCOME_UNKNOWN,
			compensation_error,
			true,
			true,
			_pending_section_original_result,
			result
		)
		return
	_profile_save_pending = true
	_profile_save_wait_seconds = 0.0
	_complete_pending_section_operation(
		GameSaveSectionResult.STATUS_COMPENSATION_FAILED,
		compensation_error,
		true,
		true,
		_pending_section_original_result,
		result
	)


func _store_pending_section_reconciliation(
	stage: StringName,
	requested_generation: int,
	save_result: GFSaveProfileResult,
	compensation_result: GFSaveProfileResult = null
) -> void:
	_section_reconciliation = {
		&"stage": String(stage),
		&"profile_id": String(_pending_section_profile_id),
		&"requested_generation": requested_generation,
		&"transaction_id": (
			_pending_section_operation.get_transaction_id()
			if _pending_section_operation != null
			else 0
		),
		&"section_ids": PackedStringArray(
			_pending_section_ids.keys()
		),
		&"snapshots": _pending_section_snapshots.duplicate(true),
		&"applied_keys": _pending_section_applied_keys.duplicate(),
		&"save_result": (
			save_result.duplicate_result()
			if save_result != null
			else null
		),
		&"compensation_result": (
			compensation_result.duplicate_result()
			if compensation_result != null
			else null
		),
	}
	_last_section_reconciliation_evidence.clear()


func _tick_section_reconciliation() -> void:
	if (
		_section_reconciliation.is_empty()
		or _section_reconciliation_operation != null
		or _profile_utility == null
	):
		return
	var stage: StringName = GFVariantData.get_option_string_name(
		_section_reconciliation,
		&"stage"
	)
	if stage == &"rollback_failed":
		return
	var profile_id: StringName = GFVariantData.get_option_string_name(
		_section_reconciliation,
		&"profile_id"
	)
	var snapshot: Dictionary = (
		_profile_utility.get_profile_state_snapshot(profile_id)
	)
	if (
		snapshot.is_empty()
		or GFVariantData.get_option_bool(
			snapshot,
			&"write_outcome_unknown",
			false
		)
	):
		return
	var requested_generation: int = GFVariantData.get_option_int(
		_section_reconciliation,
		&"requested_generation",
		0
	)
	var persisted_generation: int = GFVariantData.get_option_int(
		snapshot,
		&"persisted_generation",
		0
	)
	if stage == &"candidate_unknown":
		if persisted_generation >= requested_generation:
			_settle_section_reconciliation(
				&"late_success",
				true,
				false,
				snapshot
			)
			return
		var applied_keys: Array[String] = []
		for key_value: Variant in GFVariantData.get_option_array(
			_section_reconciliation,
			&"applied_keys"
		):
			applied_keys.append(GFVariantData.to_text(key_value))
		var rollback_error: Error = _rollback_sections(
			applied_keys,
			GFVariantData.get_option_dictionary(
				_section_reconciliation,
				&"snapshots"
			)
		)
		if rollback_error != OK:
			_section_reconciliation[&"stage"] = "rollback_failed"
			_last_section_reconciliation_evidence = {
				&"status": "late_failure_rollback_failed",
				&"error_code": int(rollback_error),
				&"profile_state": snapshot.duplicate(true),
			}
			return
		_start_section_reconciliation_compensation(snapshot)
		return
	if stage == &"compensation_unknown":
		if persisted_generation < requested_generation:
			# 内存已回滚但 GF 仍未确认补偿 generation；解锁前保留待保存
			# 标记，确保紧随其后的 flush/账号切换重新 gather 回滚状态。
			_profile_save_pending = true
			_profile_save_wait_seconds = 0.0
		_settle_section_reconciliation(
			(
				&"late_rollback_persisted"
				if persisted_generation >= requested_generation
				else &"late_rollback_storage_failed"
			),
			false,
			true,
			snapshot
		)


func _start_section_reconciliation_compensation(
	profile_snapshot: Dictionary
) -> void:
	_section_reconciliation[&"stage"] = "late_failure_compensating"
	_section_reconciliation[&"profile_state"] = (
		profile_snapshot.duplicate(true)
	)
	_section_reconciliation_operation = _request_save_active_profile({
		&"reason": "late_outcome_rollback_compensation",
		&"section_transaction_id": GFVariantData.get_option_int(
			_section_reconciliation,
			&"transaction_id",
			0
		),
	})
	if _section_reconciliation_operation == null:
		_profile_save_pending = true
		_profile_save_wait_seconds = 0.0
		_settle_section_reconciliation(
			&"late_failure_compensation_unavailable",
			false,
			true,
			profile_snapshot
		)
		return
	if _section_reconciliation_operation.is_completed():
		_on_section_reconciliation_compensation_completed(
			_section_reconciliation_operation.get_result(),
			_section_reconciliation_operation
		)
		return
	_section_reconciliation_callback = Callable(
		self,
		"_on_section_reconciliation_compensation_completed"
	).bind(_section_reconciliation_operation)
	@warning_ignore("int_as_enum_without_cast")
	var connect_error: Error = _section_reconciliation_operation.completed.connect(
		_section_reconciliation_callback,
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		_on_section_reconciliation_compensation_completed(
			null,
			_section_reconciliation_operation
		)


func _on_section_reconciliation_compensation_completed(
	result: GFSaveProfileResult,
	profile_operation: GFSaveProfileOperation
) -> void:
	if (
		_section_reconciliation.is_empty()
		or _section_reconciliation_operation == null
		or not is_same(
			_section_reconciliation_operation,
			profile_operation
		)
	):
		return
	_disconnect_section_reconciliation_callback()
	_section_reconciliation_operation = null
	if result != null and result.is_successful():
		_settle_section_reconciliation(
			&"late_failure_rolled_back",
			false,
			true,
			result.to_dict()
		)
		return
	if (
		result != null
		and result.get_status()
		== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	):
		_section_reconciliation[&"stage"] = "compensation_unknown"
		_section_reconciliation[&"requested_generation"] = (
			result.get_requested_generation()
		)
		_section_reconciliation[&"compensation_result"] = (
			result.duplicate_result()
		)
		return
	_profile_save_pending = true
	_profile_save_wait_seconds = 0.0
	_settle_section_reconciliation(
		&"late_failure_compensation_failed",
		false,
		true,
		result.to_dict() if result != null else {}
	)


func _settle_section_reconciliation(
	status: StringName,
	candidate_persisted: bool,
	memory_rolled_back: bool,
	terminal_evidence: Dictionary
) -> void:
	var evidence: Dictionary = {
		&"status": String(status),
		&"transaction_id": GFVariantData.get_option_int(
			_section_reconciliation,
			&"transaction_id",
			0
		),
		&"profile_id": GFVariantData.get_option_string(
			_section_reconciliation,
			&"profile_id"
		),
		&"section_ids": GFVariantData.get_option_value(
			_section_reconciliation,
			&"section_ids",
			PackedStringArray()
		),
		&"candidate_persisted": candidate_persisted,
		&"memory_rolled_back": memory_rolled_back,
		&"terminal_evidence": terminal_evidence.duplicate(true),
	}
	_last_section_reconciliation_evidence = evidence.duplicate(true)
	_section_reconciliation.clear()
	_disconnect_section_reconciliation_callback()
	_section_reconciliation_operation = null
	section_reconciliation_settled.emit(evidence.duplicate(true))


func _complete_pending_section_operation(
	status: StringName,
	error_code: Error,
	candidate_applied: bool,
	memory_rolled_back: bool,
	save_result: GFSaveProfileResult = null,
	compensation_result: GFSaveProfileResult = null
) -> void:
	if _pending_section_operation == null:
		return
	var operation: GameSaveSectionOperation = _pending_section_operation
	var result: GameSaveSectionResult = _make_section_result(
		operation,
		status,
		error_code,
		candidate_applied,
		memory_rolled_back,
		save_result,
		compensation_result
	)
	_clear_pending_section_state()
	var _completed: bool = operation.complete_for_utility(result)
	_untrack_async_handle(operation)
	section_operation_completed.emit(result.duplicate_result())


func _complete_detached_section_operation(
	operation: GameSaveSectionOperation,
	status: StringName,
	error_code: Error
) -> void:
	var result: GameSaveSectionResult = _make_section_result(
		operation,
		status,
		error_code,
		false,
		false
	)
	var _completed: bool = operation.complete_for_utility(result)
	_untrack_async_handle(operation)
	section_operation_completed.emit(result.duplicate_result())


func _make_section_result(
	operation: GameSaveSectionOperation,
	status: StringName,
	error_code: Error,
	candidate_applied: bool,
	memory_rolled_back: bool,
	save_result: GFSaveProfileResult = null,
	compensation_result: GFSaveProfileResult = null
) -> GameSaveSectionResult:
	var result: GameSaveSectionResult = GameSaveSectionResult.new()
	var _configured: bool = result.configure_for_utility(
		operation.get_transaction_id(),
		operation.get_profile_id(),
		operation.get_section_ids(),
		status,
		error_code,
		candidate_applied,
		memory_rolled_back,
		save_result,
		compensation_result
	)
	return result


func _clear_pending_section_state() -> void:
	_disconnect_pending_section_save_callback()
	_disconnect_pending_section_compensation_callback()
	_pending_section_operation = null
	_pending_section_profile_id = &""
	_pending_section_ids.clear()
	_pending_section_snapshots.clear()
	_pending_section_applied_keys.clear()
	_pending_section_save_operation = null
	_pending_section_compensation_operation = null
	_pending_section_original_result = null


func _disconnect_pending_section_save_callback() -> void:
	if (
		_pending_section_save_operation != null
		and _pending_section_save_callback.is_valid()
		and _pending_section_save_operation.completed.is_connected(
			_pending_section_save_callback
		)
	):
		_pending_section_save_operation.completed.disconnect(
			_pending_section_save_callback
		)
	_pending_section_save_callback = Callable()


func _disconnect_pending_section_compensation_callback() -> void:
	if (
		_pending_section_compensation_operation != null
		and _pending_section_compensation_callback.is_valid()
		and _pending_section_compensation_operation.completed.is_connected(
			_pending_section_compensation_callback
		)
	):
		_pending_section_compensation_operation.completed.disconnect(
			_pending_section_compensation_callback
		)
	_pending_section_compensation_callback = Callable()


func _disconnect_section_reconciliation_callback() -> void:
	if (
		_section_reconciliation_operation != null
		and _section_reconciliation_callback.is_valid()
		and _section_reconciliation_operation.completed.is_connected(
			_section_reconciliation_callback
		)
	):
		_section_reconciliation_operation.completed.disconnect(
			_section_reconciliation_callback
		)
	_section_reconciliation_callback = Callable()


func _disconnect_section_operation_callbacks() -> void:
	_disconnect_pending_section_save_callback()
	_disconnect_pending_section_compensation_callback()
	_disconnect_section_reconciliation_callback()


func _settle_pending_section_operation_for_dispose() -> void:
	if not _has_pending_section_transaction():
		return
	if (
		_pending_section_save_operation != null
		and _pending_section_save_operation.is_completed()
	):
		_on_pending_section_save_completed(
			_pending_section_save_operation.get_result(),
			_pending_section_save_operation,
			_pending_section_operation.get_transaction_id()
		)
	elif (
		_pending_section_compensation_operation != null
		and _pending_section_compensation_operation.is_completed()
	):
		_on_pending_section_compensation_completed(
			_pending_section_compensation_operation.get_result(),
			_pending_section_compensation_operation,
			_pending_section_operation.get_transaction_id()
		)
	if not _has_pending_section_transaction():
		return
	var candidate_applied: bool = (
		not _pending_section_applied_keys.is_empty()
	)
	_complete_pending_section_operation(
		(
			GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN
			if candidate_applied
			else GameSaveSectionResult.STATUS_DISPOSED
		),
		ERR_TIMEOUT if candidate_applied else ERR_UNAVAILABLE,
		candidate_applied,
		false,
		_pending_section_original_result
	)


func _request_save_active_profile(
	metadata: Dictionary = {},
	context: Dictionary = {}
) -> GFSaveProfileOperation:
	if _profile_utility == null or _active_profile_id == &"":
		return _make_rejected_profile_operation(
			GFSaveProfileOperation.OPERATION_SAVE
		)
	var document_metadata: Dictionary = _build_profile_metadata()
	document_metadata.merge(metadata, true)
	return _track_profile_operation(
		_profile_utility.save_profile(
			_active_profile_id,
			document_metadata,
			context
		)
	)


func _request_flush_active_profile(
	metadata: Dictionary = {}
) -> GFSaveProfileOperation:
	if _profile_utility == null or _active_profile_id == &"":
		return _make_rejected_profile_operation(
			GFSaveProfileOperation.OPERATION_FLUSH
		)
	if _profile_save_pending:
		_profile_save_pending = false
		_profile_save_wait_seconds = 0.0
		var _save_operation: GFSaveProfileOperation = (
			_request_save_active_profile({
				&"reason": "flush_pending_generation",
			})
		)
	return _track_profile_operation(
		_profile_utility.flush_profile(_active_profile_id, metadata)
	)


func _wait_for_operation(
	operation: GFSaveProfileOperation
) -> GFSaveProfileResult:
	if operation == null:
		return null
	if _clock == null:
		return operation.get_result()
	var deadline_msec: int = (
		_clock.get_tick_msec() + _SYNC_OPERATION_TIMEOUT_MSEC
	)
	var remaining_poll_count: int = _SYNC_OPERATION_MAX_POLL_COUNT
	while (
		not operation.is_completed()
		and _clock.get_tick_msec() < deadline_msec
		and remaining_poll_count > 0
	):
		remaining_poll_count -= 1
		if _storage != null:
			# 架构 init/ready 边界只轮询 GF 公共 tick；禁止 wait_to_finish
			# 阻塞主线程，从而让 deadline 与 retry_wait 保持真实有界。
			_storage.tick(0.0)
		if _profile_utility != null:
			# 同步启动边界显式推进公共 tick，以兑现 GF 的
			# 100/500/1500ms retry_wait；不接管 singleton 生命周期。
			_profile_utility.tick(0.0)
		if not operation.is_completed():
			OS.delay_msec(1)
	if operation.is_completed():
		_untrack_async_handle(operation)
	return operation.get_result() if operation.is_completed() else null


func _await_profile_operation_async(
	operation: GFSaveProfileOperation
) -> GFSaveProfileResult:
	if operation == null:
		return null
	if operation.is_completed():
		_untrack_async_handle(operation)
		return operation.get_result()
	var result: GFSaveProfileResult = await operation.completed
	_untrack_async_handle(operation)
	return result


func _record_profile_transition_result(
	result: GFSaveProfileResult
) -> void:
	_last_profile_transition_evidence = (
		result.to_dict()
		if result != null
		else {
			&"ok": false,
			&"status": "operation_timeout",
			&"error_code": int(ERR_TIMEOUT),
		}
	)
	_profile_transition_outcome_unknown = (
		result == null
		or result.get_status()
		== GFSaveProfileResult.STATUS_OUTCOME_UNKNOWN
	)


func _record_cleanup_outcome_unknown(profile_file_name: String) -> void:
	_profile_transition_outcome_unknown = true
	_last_profile_transition_evidence = {
		&"ok": false,
		&"status": "cleanup_outcome_unknown",
		&"error_code": int(ERR_TIMEOUT),
		&"profile_file": profile_file_name,
	}


func _make_transition_cancelled_recovery() -> Dictionary:
	return {
		&"ok": false,
		&"error_code": int(ERR_UNAVAILABLE),
		&"error": "Profile transition no longer owns its epoch.",
	}


func _await_storage_operation_async(
	operation: GFStorageAsyncOperation
) -> GFStorageAsyncResult:
	if operation == null:
		return null
	if operation.is_completed():
		return operation.get_result()
	var result: GFStorageAsyncResult = await operation.completed
	return result


func _result_to_error(result: GFSaveProfileResult) -> Error:
	if result == null:
		return ERR_TIMEOUT
	if result.is_successful():
		return OK
	var error_code: Error = result.get_error_code()
	return error_code if error_code != OK else ERR_INVALID_DATA


func _on_profile_operation_completed(
	result: GFSaveProfileResult
) -> void:
	if result == null:
		return
	var snapshot: Dictionary = result.to_dict()
	if result.get_operation() == GFSaveProfileOperation.OPERATION_LOAD:
		_last_load_result = snapshot
	elif result.get_operation() == GFSaveProfileOperation.OPERATION_SAVE:
		_last_save_result = snapshot
		profile_save_completed.emit(_result_to_error(result))
	elif result.get_operation() == GFSaveProfileOperation.OPERATION_FLUSH:
		_last_save_result = snapshot
	profile_operation_completed.emit(result.duplicate_result())


func _on_platform_lifecycle_event_received(
	event: GFPlatformLifecycleEvent
) -> void:
	if event == null:
		return
	if event.is_type(GFPlatformLifecycleEvent.TYPE_FOREGROUND):
		_platform_backgrounded = false
		return
	if (
		not event.is_type(GFPlatformLifecycleEvent.TYPE_BACKGROUND)
		or _platform_backgrounded
	):
		return
	_platform_backgrounded = true
	var operation: GFSaveProfileOperation = request_flush_profile({
		&"reason": "platform_background",
	})
	if operation.is_completed():
		var result: GFSaveProfileResult = operation.get_result()
		if _result_to_error(result) != OK:
			_log_error(
				"进入后台时 Profile 冲刷失败：%s。"
				% (
					result.get_error()
					if result != null
					else "operation unavailable"
				)
			)


func _restore_active_profile_reference(
	profile: GFSaveProfile,
	profile_id: StringName,
	file_name: String,
	loaded: bool,
	load_result: Dictionary,
	save_result: Dictionary
) -> void:
	_active_profile = profile
	_active_profile_id = profile_id
	_profile_file_name = file_name
	_loaded = loaded
	_last_load_result = load_result.duplicate(true)
	_last_save_result = save_result.duplicate(true)


func _record_configuration_failure(error_code: Error = ERR_UNCONFIGURED) -> void:
	_loaded = false
	_last_load_result = {
		&"ok": false,
		&"error_code": error_code,
		&"error": "GF Save Profile dependencies or providers are unavailable.",
	}


func _make_rejected_profile_operation(
	operation_kind: StringName
) -> GFSaveProfileOperation:
	# 让 GF 生成规范 invalid_profile 终态，避免项目伪造框架 Result。
	if _profile_utility == null:
		return null
	var operation: GFSaveProfileOperation = (
		_profile_utility.save_profile(_REJECTED_PROFILE_ID)
		if operation_kind == GFSaveProfileOperation.OPERATION_SAVE
		else (
			_profile_utility.load_profile(_REJECTED_PROFILE_ID)
			if operation_kind == GFSaveProfileOperation.OPERATION_LOAD
			else _profile_utility.flush_profile(_REJECTED_PROFILE_ID)
		)
	)
	return _track_profile_operation(operation)


func _build_profile_metadata() -> Dictionary:
	return {
		&"app_version": GFVariantData.to_text(
			ProjectSettings.get_setting(_PROJECT_VERSION_SETTING, "")
		),
	}


func _is_configured() -> bool:
	return (
		not _disposed
		and _profile_utility != null
		and _storage != null
		and _active_profile != null
		and _active_profile_id != &""
		and not _section_providers.is_empty()
	)


func _owns_profile_transition(transition_epoch: int) -> bool:
	return (
		not _disposed
		and _profile_transition_in_progress
		and transition_epoch > 0
		and _profile_transition_epoch == transition_epoch
	)


func _get_ordered_providers() -> Array[GameSaveSectionData]:
	var result: Array[GameSaveSectionData] = []
	for key: String in _get_sorted_definition_keys():
		var provider: GameSaveSectionData = _get_section_provider(
			StringName(key)
		)
		if provider != null:
			result.append(provider)
	return result


func _get_sorted_definition_keys() -> Array[String]:
	var result: Array[String] = []
	for key_value: Variant in _section_definitions.keys():
		result.append(GFVariantData.to_text(key_value))
	result.sort_custom(
		func(left: String, right: String) -> bool:
			var left_phase: int = GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					_section_definitions,
					left
				),
				&"phase",
				SectionOrder.NORMAL
			)
			var right_phase: int = GFVariantData.get_option_int(
				GFVariantData.get_option_dictionary(
					_section_definitions,
					right
				),
				&"phase",
				SectionOrder.NORMAL
			)
			return (
				left < right
				if left_phase == right_phase
				else left_phase < right_phase
			)
	)
	return result


func _get_section_provider(
	section_id: StringName
) -> GameSaveSectionData:
	return _get_provider_value(
		GFVariantData.get_option_value(
			_section_providers,
			String(section_id)
		)
	)


func _get_provider_value(value: Variant) -> GameSaveSectionData:
	if value is GameSaveSectionData:
		var provider: GameSaveSectionData = value
		return provider
	return null


func _get_registered_section_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for key_value: Variant in _section_providers.keys():
		var _appended: bool = result.append(
			GFVariantData.to_text(key_value)
		)
	result.sort()
	return result


static func _is_account_profile_file_name_valid(
	profile_file_name: String
) -> bool:
	if (
		profile_file_name.is_empty()
		or profile_file_name.is_absolute_path()
		or profile_file_name.contains("\\")
		or profile_file_name.simplify_path() != profile_file_name
		or profile_file_name.get_base_dir() != "profiles"
		or profile_file_name.get_extension() != "save"
	):
		return false
	var account_id: String = profile_file_name.get_file().get_basename()
	return GFUuid.is_valid(account_id, 7)


func _background_delete_task_to_error(
	task: GFBackgroundWorkTask
) -> Error:
	if task == null:
		return ERR_CANT_CREATE
	if _profile_delete_timed_out.has(task.work_id):
		return ERR_TIMEOUT
	if task.status == GFBackgroundWorkTask.Status.CANCELLED:
		return ERR_UNAVAILABLE
	var result: Dictionary = GFVariantData.as_dictionary(task.result)
	@warning_ignore("int_as_enum_without_cast")
	var error_code: Error = GFVariantData.get_option_int(
		result,
		&"error_code",
		(
			OK
			if task.status == GFBackgroundWorkTask.Status.COMPLETED
			else ERR_CANT_CREATE
		)
	)
	if task.status != GFBackgroundWorkTask.Status.COMPLETED:
		return error_code if error_code != OK else ERR_CANT_CREATE
	return error_code


func _tick_profile_delete_timeouts() -> void:
	if _clock == null or _background_work == null:
		return
	var now_msec: int = _clock.get_tick_msec()
	for work_id_value: Variant in _profile_delete_deadlines.keys():
		var work_id: StringName = GFVariantData.to_string_name(
			work_id_value
		)
		var task_value: Variant = GFVariantData.get_option_value(
			_profile_delete_tasks,
			work_id
		)
		if not (task_value is GFBackgroundWorkTask):
			continue
		var task: GFBackgroundWorkTask = task_value
		var deadline_msec: int = GFVariantData.get_option_int(
			_profile_delete_deadlines,
			work_id,
			0
		)
		if (
			task.is_finished()
			or deadline_msec <= 0
			or now_msec < deadline_msec
			or _profile_delete_timed_out.has(work_id)
		):
			continue
		_profile_delete_timed_out[work_id] = true
		var _deadline_erased: bool = (
			_profile_delete_deadlines.erase(work_id)
		)
		var _cancelled: bool = _background_work.cancel_work(work_id)
		# 取消运行中线程只是一项请求；项目 deadline 必须立即给等待者
		# outcome-unknown 终态，GFBackgroundWorkUtility 继续持有晚完成任务。
		profile_cleanup_task_terminal.emit(work_id)


func _on_background_work_terminal(task: GFBackgroundWorkTask) -> void:
	if task == null or not _profile_delete_tasks.has(task.work_id):
		return
	if not _profile_delete_waiters.has(task.work_id):
		_cleanup_profile_delete_tracking(task.work_id)
	profile_cleanup_task_terminal.emit(task.work_id)


func _cleanup_profile_delete_tracking(work_id: StringName) -> void:
	var file_name: String = GFVariantData.get_option_string(
		_profile_delete_file_names,
		work_id
	)
	var task_value: Variant = GFVariantData.get_option_value(
		_profile_delete_tasks,
		work_id
	)
	if task_value is GFBackgroundWorkTask:
		var task: GFBackgroundWorkTask = task_value
		_untrack_async_handle(task)
	var _task_erased: bool = _profile_delete_tasks.erase(work_id)
	var _worker_erased: bool = _profile_delete_workers.erase(work_id)
	var _deadline_erased: bool = _profile_delete_deadlines.erase(work_id)
	var _timeout_erased: bool = _profile_delete_timed_out.erase(work_id)
	var _waiter_erased: bool = _profile_delete_waiters.erase(work_id)
	var _file_erased: bool = _profile_delete_file_names.erase(work_id)
	if (
		not file_name.is_empty()
		and GFVariantData.to_string_name(
			GFVariantData.get_option_value(
				_profile_cleanup_paths,
				file_name
			)
		)
		== work_id
	):
		var _path_erased: bool = _profile_cleanup_paths.erase(file_name)


func _track_profile_operation(
	operation: GFSaveProfileOperation
) -> GFSaveProfileOperation:
	if operation == null or operation.is_completed():
		return operation
	var handle_instance_id: int = operation.get_instance_id()
	var was_tracked: bool = _async_tracking_ids.has(handle_instance_id)
	var tracking_id: int = _track_async_handle(
		operation,
		&"game_save.profile_operation",
		{
			&"owner": "GameSaveGraphUtility",
			&"operation": String(operation.get_operation()),
			&"profile_id": String(operation.get_profile_id()),
			&"requested_generation": operation.get_requested_generation(),
		}
	)
	if (
		tracking_id > 0
		and not was_tracked
		and is_instance_valid(_signal_utility)
	):
		var _completion_connection: GFSignalConnection = _signal_utility.connect_once(
			operation.completed,
			_on_tracked_profile_operation_completed,
			self,
			[operation]
		)
	return operation


func _track_section_operation(
	operation: GameSaveSectionOperation
) -> void:
	if operation == null or not operation.is_pending():
		return
	var _tracking_id: int = _track_async_handle(
		operation,
		&"game_save.section_operation",
		{
			&"owner": "GameSaveGraphUtility",
			&"transaction_id": operation.get_transaction_id(),
			&"profile_id": String(operation.get_profile_id()),
			&"section_ids": operation.get_section_ids(),
		}
	)


func _track_profile_cleanup_task(
	task: GFBackgroundWorkTask,
	profile_file_name: String
) -> void:
	if task == null or task.is_finished():
		return
	var _tracking_id: int = _track_async_handle(
		task,
		&"game_save.profile_cleanup",
		{
			&"owner": "GameSaveGraphUtility",
			&"work_id": String(task.work_id),
			&"profile_file": profile_file_name,
		}
	)


func _track_async_handle(
	handle: Object,
	label: StringName,
	metadata: Dictionary
) -> int:
	if handle == null:
		return 0
	var handle_instance_id: int = handle.get_instance_id()
	if _async_tracking_ids.has(handle_instance_id):
		return GFVariantData.get_option_int(
			_async_tracking_ids,
			handle_instance_id,
			0
		)
	var tracker: GFAsyncTrackerUtility = _resolve_optional_async_tracker()
	if tracker == null:
		return 0
	var tracking_id: int = tracker.track_handle(handle, label, metadata)
	if tracking_id > 0:
		_async_tracking_ids[handle_instance_id] = tracking_id
	return tracking_id


func _untrack_async_handle(handle: Object) -> void:
	if handle == null:
		return
	var handle_instance_id: int = handle.get_instance_id()
	var tracking_id: int = GFVariantData.get_option_int(
		_async_tracking_ids,
		handle_instance_id,
		0
	)
	if tracking_id <= 0:
		return
	if is_instance_valid(_async_tracker):
		var _untracked: bool = _async_tracker.untrack_id(tracking_id)
	var _erased: bool = _async_tracking_ids.erase(handle_instance_id)


func _clear_async_tracking() -> void:
	if is_instance_valid(_async_tracker):
		for tracking_id_value: Variant in _async_tracking_ids.values():
			var tracking_id: int = GFVariantData.to_int(
				tracking_id_value
			)
			if tracking_id > 0:
				var _untracked: bool = (
					_async_tracker.untrack_id(tracking_id)
				)
	_async_tracking_ids.clear()


func _on_tracked_profile_operation_completed(
	operation: GFSaveProfileOperation,
	_result: GFSaveProfileResult
) -> void:
	_untrack_async_handle(operation)


func _log_error(message: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, message)
	else:
		push_error("[%s] %s" % [_LOG_TAG, message])


func _resolve_storage_utility() -> GFStorageUtility:
	var value: Object = get_utility(GFStorageUtility)
	if value is GFStorageUtility:
		var utility: GFStorageUtility = value
		return utility
	return null


func _resolve_background_work_utility() -> GFBackgroundWorkUtility:
	var value: Object = get_utility(GFBackgroundWorkUtility)
	if value is GFBackgroundWorkUtility:
		var utility: GFBackgroundWorkUtility = value
		return utility
	return null


func _resolve_profile_utility() -> GFSaveProfileUtility:
	var value: Object = get_utility(GFSaveProfileUtility)
	if value is GFSaveProfileUtility:
		var utility: GFSaveProfileUtility = value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	if value is GameClockUtility:
		var utility: GameClockUtility = value
		return utility
	return null


func _resolve_log_utility() -> GFLogUtility:
	var value: Object = get_utility(GFLogUtility)
	if value is GFLogUtility:
		var utility: GFLogUtility = value
		return utility
	return null


func _resolve_platform_utility() -> GamePlatformUtility:
	var value: Object = get_utility(GamePlatformUtility)
	if value is GamePlatformUtility:
		var utility: GamePlatformUtility = value
		return utility
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var value: Object = get_utility(GFSignalUtility)
	if value is GFSignalUtility:
		var utility: GFSignalUtility = value
		return utility
	return null


func _resolve_optional_async_tracker() -> GFAsyncTrackerUtility:
	if is_instance_valid(_async_tracker):
		return _async_tracker
	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return null
	# 开发诊断 Installer 并非生产依赖；local lookup 缺失时静默返回，
	# 避免 strict_dependency_lookup 把合法的发布构建当作配置错误。
	var value: Object = architecture.get_local_utility(
		GFAsyncTrackerUtility
	)
	if value is GFAsyncTrackerUtility:
		_async_tracker = value
		return _async_tracker
	return null
