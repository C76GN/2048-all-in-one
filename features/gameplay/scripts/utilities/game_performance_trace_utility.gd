## GamePerformanceTraceUtility: 定义项目移动卡顿轨迹的最小事件 schema 与生命周期。
##
## 轨迹只保留短期、内存内、脱敏的阶段时长和方向类别，不记录棋盘、账号、
## 存档、绝对路径或设备身份。完整事件只在显式支持报告路径中读取。
class_name GamePerformanceTraceUtility
extends GFUtility


# --- 常量 ---

const CHANNEL_MOVE_LATENCY: StringName = &"gameplay.move_latency"
const TRACE_RECIPE_ID: StringName = &"gameplay.move_latency.v1"
const _MAX_EVENTS: int = 96
const _MAX_EVENT_BUFFER_BYTES: int = 96 * 1024
const _MAX_EVENT_BYTES: int = 2048


# --- 私有变量 ---

var _trace: GFSessionTraceUtility
var _trace_recipe: GFSessionTraceRecipe
var _clock: GameClockUtility
var _settings: GameSettingsUtility
var _signal_utility: GFSignalUtility
var _capture_enabled: bool = false
var _game_session_available: bool = false
var _current_is_replay_mode: bool = false
var _next_attempt_id: int = 1
var _active_attempt_id: int = 0
var _active_started_usec: int = 0
var _resolved_usec: int = 0
var _presentation_pending: bool = false
var _presentation_enqueued_usec: int = 0
var _primary_feedback_usec: int = 0
var _primary_feedback_started: bool = false
var _presentation_settle_candidate_usec: int = 0
var _presentation_settled_usec: int = 0
var _command_completed: bool = false


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GFSessionTraceUtility,
		GameClockUtility,
		GameSettingsUtility,
		GFSignalUtility,
	]


func ready() -> void:
	_trace = _get_trace_utility()
	_clock = _get_clock_utility()
	_settings = _get_settings_utility()
	_signal_utility = _get_signal_utility()
	if (
		not is_instance_valid(_trace)
		or not is_instance_valid(_clock)
		or not is_instance_valid(_settings)
		or not is_instance_valid(_signal_utility)
	):
		push_error("[GamePerformanceTraceUtility] 本地性能轨迹依赖未完整安装。")
		return
	_trace_recipe = _create_trace_recipe()
	var recipe_result: Dictionary = _trace.apply_recipe(_trace_recipe)
	if not GFVariantData.get_option_bool(recipe_result, "ok"):
		push_error(
			"[GamePerformanceTraceUtility] 无法应用移动延迟轨迹配方：%s。"
			% GFVariantData.get_option_string(
				recipe_result,
				"error_code",
				"unknown"
			)
		)
		_trace_recipe = null
		return
	_capture_enabled = _read_capture_enabled()
	if not _capture_enabled:
		_trace.clear()
	var _settings_connection: GFSignalConnection = _signal_utility.connect_signal(
		_settings.setting_changed,
		Callable(self, &"_on_setting_changed"),
		self
	)

	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready", 1))
	register_simple_event(
		EventNames.SCENE_WILL_CHANGE,
		GFEventListener.from_method(self, &"_on_scene_will_change", 1)
	)


func dispose() -> void:
	var _summary: Dictionary = stop_gameplay_trace(&"disposed")
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_trace = null
	_trace_recipe = null
	_clock = null
	_settings = null
	_signal_utility = null
	_capture_enabled = false
	_game_session_available = false
	_current_is_replay_mode = false
	_reset_active_attempt()


# --- 公共方法 ---

## 显式开始一局短期本地诊断轨迹。
## @param is_replay_mode: 当前会话是否为回放模式。
func start_gameplay_trace(is_replay_mode: bool) -> bool:
	if (
		not _capture_enabled
		or not is_instance_valid(_trace)
		or not is_instance_valid(_trace_recipe)
	):
		return false
	_reset_active_attempt()
	var session_id: StringName = _trace.start_session(&"", {
		"feature": "gameplay",
		"is_replay_mode": is_replay_mode,
		"retention": "memory_until_next_session_or_dispose",
	})
	return session_id != &""


## 停止当前轨迹并清空尚未终结的移动尝试。
## @param reason: 终止轨迹的规范原因。
func stop_gameplay_trace(reason: StringName = &"completed") -> Dictionary:
	_reset_active_attempt()
	if not is_instance_valid(_trace):
		return {}
	return _trace.stop_session(reason)


## 标记输入已经通过玩法门控并即将进入命令管线。
## @param direction: 本次移动的四向输入。
## @return 当前尝试的局部递增标识；轨迹未启用时返回 0。
func begin_move(direction: Vector2i) -> int:
	if not _capture_enabled or not is_instance_valid(_trace):
		return 0
	if _active_attempt_id > 0:
		_record_event(&"move_superseded", {
			"attempt_id": _active_attempt_id,
			"elapsed_usec": _elapsed_since(_active_started_usec),
		})
		_reset_active_attempt()

	var attempt_id: int = _next_attempt_id
	_next_attempt_id = 1 if _next_attempt_id >= 2_147_483_647 else _next_attempt_id + 1
	_active_attempt_id = attempt_id
	_active_started_usec = _get_monotonic_usec()
	_record_event(&"move_requested", {
		"attempt_id": attempt_id,
		"direction": _direction_id(direction),
	})
	return attempt_id


## 标记移动命令完成；无效移动在此成为终态。
## @param attempt_id: begin_move 返回的移动尝试标识。
## @param effective: 该移动是否实际改变棋盘。
func complete_move(attempt_id: int, effective: bool) -> void:
	if attempt_id <= 0 or attempt_id != _active_attempt_id:
		return
	_resolved_usec = _get_monotonic_usec()
	_command_completed = true
	_record_event(&"move_command_completed", {
		"attempt_id": attempt_id,
		"effective": effective,
		"input_to_command_usec": _elapsed_since(_active_started_usec),
	})
	if not effective:
		_reset_active_attempt()
	elif _presentation_pending:
		return
	elif _presentation_settle_candidate_usec > 0:
		_commit_presentation_settled(
			_presentation_settle_candidate_usec
		)
		_reset_active_attempt()
	else:
		_record_event(&"move_presentation_missing", {
			"attempt_id": attempt_id,
			"elapsed_usec": _elapsed_since(_active_started_usec),
		})
		_reset_active_attempt()


## 标记有效移动的首个表现批次已进入 GF 命名动作队列。
## @param queue_was_busy: 入队前表现队列是否已有待执行动作。
## @return 与该表现动作绑定的移动尝试标识；没有活动尝试时返回 0。
func mark_presentation_enqueued(queue_was_busy: bool) -> int:
	if _active_attempt_id <= 0 or not is_instance_valid(_trace):
		return 0
	if _presentation_pending or _presentation_settled_usec > 0:
		return 0
	_presentation_pending = true
	# 同步 drain 只形成候选终点；同一命令后续生成批次会重新打开 pending，
	# 并把完整回合终点延后。首个入队指标仍只记录一次。
	_presentation_settle_candidate_usec = 0
	if _presentation_enqueued_usec <= 0:
		_presentation_enqueued_usec = _get_monotonic_usec()
		_record_event(&"move_presentation_enqueued", {
			"attempt_id": _active_attempt_id,
			"queue_was_busy": queue_was_busy,
			"input_to_enqueue_usec": maxi(
				_presentation_enqueued_usec - _active_started_usec,
				0
			),
		})
	return _active_attempt_id


## 标记与移动尝试绑定的 BoardAnimationAction 已真正开始执行。
##
## 入队不等同于玩家已经看到或听到反馈；该指标只在主表现动作进入
## execute() 后记录，并对同一次尝试保持幂等。
## @param attempt_id: mark_presentation_enqueued 返回的移动尝试标识。
func mark_primary_feedback_started(attempt_id: int) -> void:
	if (
		attempt_id <= 0
		or attempt_id != _active_attempt_id
		or not _presentation_pending
		or _primary_feedback_started
		or not is_instance_valid(_trace)
	):
		return
	_primary_feedback_usec = _get_monotonic_usec()
	_primary_feedback_started = true
	_record_event(&"move_primary_feedback_started", {
		"attempt_id": attempt_id,
		"input_to_primary_feedback_usec": maxi(
			_primary_feedback_usec - _active_started_usec,
			0
		),
		"enqueue_to_primary_feedback_usec": (
			maxi(_primary_feedback_usec - _presentation_enqueued_usec, 0)
			if _presentation_enqueued_usec > 0
			else 0
		),
	})


## 标记当前移动关联的棋盘表现队列已排空。
func mark_presentation_settled() -> void:
	if not _presentation_pending or _active_attempt_id <= 0:
		return
	var now_usec: int = _get_monotonic_usec()
	_presentation_pending = false
	_presentation_settle_candidate_usec = now_usec
	if not _command_completed:
		return
	_commit_presentation_settled(now_usec)
	_reset_active_attempt()


## 标记表现被重定向、场景退出或显式清空，而不是错误地记为正常完成。
## @param reason: 取消表现的规范原因。
func cancel_presentation(reason: StringName) -> void:
	if (
		_active_attempt_id <= 0
		or (
			not _presentation_pending
			and _presentation_settle_candidate_usec <= 0
		)
	):
		return
	_record_event(&"move_presentation_cancelled", {
		"attempt_id": _active_attempt_id,
		"reason": String(reason),
		"elapsed_usec": _elapsed_since(_active_started_usec),
	})
	_reset_active_attempt()


## 构建支持报告使用的有界轨迹；不会包含账号或棋盘业务状态。
func build_support_snapshot() -> Dictionary:
	if (
		not _capture_enabled
		or not is_instance_valid(_trace)
		or not is_instance_valid(_trace_recipe)
	):
		return _make_unavailable_snapshot()
	return _trace.build_recipe_snapshot(_trace_recipe, {
		"filters": {"channel_id": CHANNEL_MOVE_LATENCY},
	})


## 获取不含完整事件载荷的运行状态。
func get_debug_snapshot() -> Dictionary:
	return {
		"available": is_instance_valid(_trace),
		"capture_enabled": _capture_enabled,
		"channel_id": CHANNEL_MOVE_LATENCY,
		"recipe_id": TRACE_RECIPE_ID,
		"max_events": _MAX_EVENTS,
		"max_event_buffer_bytes": _MAX_EVENT_BUFFER_BYTES,
		"active_attempt": _active_attempt_id > 0,
		"presentation_pending": _presentation_pending,
		"primary_feedback_started": _primary_feedback_started,
		"trace": _trace.get_debug_snapshot() if is_instance_valid(_trace) else {},
	}


# --- 私有/辅助方法 ---

func _commit_presentation_settled(now_usec: int) -> void:
	_presentation_settled_usec = now_usec
	_record_event(&"move_presentation_settled", {
		"attempt_id": _active_attempt_id,
		"input_to_settled_usec": maxi(now_usec - _active_started_usec, 0),
		"command_to_settled_usec": (
			maxi(now_usec - _resolved_usec, 0)
			if _resolved_usec > 0
			else 0
		),
	})



func _create_trace_recipe() -> GFSessionTraceRecipe:
	var channel: GFSessionTraceChannelDefinition = (
		GFSessionTraceChannelDefinition.new()
	)
	var _channel_configured: GFSessionTraceChannelDefinition = (
		channel.configure(CHANNEL_MOVE_LATENCY, {
			"enabled": true,
			"include_in_snapshot": true,
			"max_events": _MAX_EVENTS,
			"max_event_bytes": _MAX_EVENT_BYTES,
			"metadata": {
				"feature": "gameplay",
				"purpose": "local_move_latency_diagnosis",
				"retention": "latest_session_memory_only",
			},
		})
	)
	var channels: Array[GFSessionTraceChannelDefinition] = [channel]
	var recipe: GFSessionTraceRecipe = GFSessionTraceRecipe.new()
	var _recipe_configured: GFSessionTraceRecipe = recipe.configure(
		TRACE_RECIPE_ID,
		channels,
		[],
		{
			"max_events": _MAX_EVENTS,
			"max_event_buffer_bytes": _MAX_EVENT_BUFFER_BYTES,
			"max_event_bytes": _MAX_EVENT_BYTES,
			"redaction_profile": GFReportValueCodec.REDACTION_PROFILE_PRIVACY,
			"snapshot_limit": _MAX_EVENTS,
			"include_context": true,
			"include_channel_catalog": false,
			"include_provider_catalog": false,
			"metadata": {
				"feature": "gameplay",
				"purpose": "local_move_latency_diagnosis",
			},
		}
	)
	return recipe


func _record_event(event_id: StringName, payload: Dictionary) -> void:
	if not _capture_enabled or not is_instance_valid(_trace):
		return
	var _result: Dictionary = _trace.record_event(
		CHANNEL_MOVE_LATENCY,
		event_id,
		payload
	)


func _reset_active_attempt() -> void:
	_active_attempt_id = 0
	_active_started_usec = 0
	_resolved_usec = 0
	_presentation_pending = false
	_presentation_enqueued_usec = 0
	_primary_feedback_usec = 0
	_primary_feedback_started = false
	_presentation_settle_candidate_usec = 0
	_presentation_settled_usec = 0
	_command_completed = false


func _elapsed_since(started_usec: int) -> int:
	if started_usec <= 0:
		return 0
	return maxi(_get_monotonic_usec() - started_usec, 0)


func _get_monotonic_usec() -> int:
	if not is_instance_valid(_clock):
		return 0
	return _clock.get_clock().get_monotonic_usec()


func _direction_id(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return &"up"
		Vector2i.DOWN:
			return &"down"
		Vector2i.LEFT:
			return &"left"
		Vector2i.RIGHT:
			return &"right"
		_:
			return &"unknown"


func _make_unavailable_snapshot() -> Dictionary:
	return {
		"ok": true,
		"available": false,
		"reason": (
			"Local performance trace capture is disabled."
			if not _capture_enabled
			else "GFSessionTraceUtility is unavailable."
		),
	}


func _get_trace_utility() -> GFSessionTraceUtility:
	var utility_value: Object = get_utility(GFSessionTraceUtility)
	if utility_value is GFSessionTraceUtility:
		var trace_utility: GFSessionTraceUtility = utility_value
		return trace_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock_utility: GameClockUtility = utility_value
		return clock_utility
	return null


func _get_settings_utility() -> GameSettingsUtility:
	var utility_value: Object = get_utility(GameSettingsUtility)
	if utility_value is GameSettingsUtility:
		var settings: GameSettingsUtility = utility_value
		return settings
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _read_capture_enabled() -> bool:
	if not is_instance_valid(_settings):
		return false
	return GFVariantData.to_bool(
		_settings.get_value(
			GameSettingsUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
			false
		),
		false
	)


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	if is_instance_valid(data):
		_game_session_available = true
		_current_is_replay_mode = data.is_replay_mode
		if _capture_enabled:
			var _started: bool = start_gameplay_trace(data.is_replay_mode)


func _on_scene_will_change(_payload: Variant = null) -> void:
	_game_session_available = false
	var _summary: Dictionary = stop_gameplay_trace(&"scene_change")


func _on_setting_changed(
	key: StringName,
	_old_value: Variant,
	_new_value: Variant
) -> void:
	if key != GameSettingsUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY:
		return
	_capture_enabled = _read_capture_enabled()
	if not _capture_enabled:
		var _summary: Dictionary = stop_gameplay_trace(&"consent_revoked")
		if is_instance_valid(_trace):
			_trace.clear()
		return
	if _game_session_available:
		var _started: bool = start_gameplay_trace(_current_is_replay_mode)
