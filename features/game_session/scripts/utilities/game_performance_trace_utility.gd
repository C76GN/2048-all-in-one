## GamePerformanceTraceUtility: 定义项目移动卡顿轨迹的最小事件 schema 与生命周期。
##
## 轨迹只保留短期、内存内、脱敏的阶段时长和方向类别，不记录棋盘、账号、
## 存档、绝对路径或设备身份。完整事件只在显式支持报告路径中读取。
class_name GamePerformanceTraceUtility
extends GFUtility


# --- 常量 ---

const CHANNEL_MOVE_LATENCY: StringName = &"gameplay.move_latency"
const TRACE_RECIPE_ID: StringName = &"gameplay.move_latency.v2"
const LOCAL_PERFORMANCE_TRACE_SETTING_KEY: StringName = (
	&"diagnostics/local_performance_trace_enabled"
)
const _MAX_EVENTS: int = 96
const _MAX_EVENT_BUFFER_BYTES: int = 96 * 1024
const _MAX_EVENT_BYTES: int = 2048
## 性能验收证据与 96 条事件轨迹使用独立预算；两条指标都必须能容纳
## GameplayAcceptanceMatrix 要求的 120 个真实样本。
const ACCEPTANCE_MAX_SAMPLES: int = 256
const _ACCEPTANCE_FRAME_METRIC_ID: StringName = &"gameplay.frame_time_ms"
const _ACCEPTANCE_INPUT_METRIC_ID: StringName = (
	&"gameplay.input_to_primary_feedback_ms"
)
## 正常收据由 PlayerInputSystem 在 180 ms 缓冲失效或门控时显式丢弃；5 秒
## 只是主循环长期停顿时的最终安全上限。四个方向各至多保留一份。
const _MOVE_INPUT_RECEIPT_TTL_USEC: int = 5_000_000
const _MAX_PENDING_MOVE_INPUT_RECEIPTS: int = 4
const MOVE_INPUT_SOURCE_TOUCH: StringName = &"touch_swipe"
const MOVE_INPUT_SOURCE_MAPPED: StringName = &"gf_input_mapping"


# --- 私有变量 ---

var _trace: GFSessionTraceUtility
var _trace_recipe: GFSessionTraceRecipe
var _clock: GameClockUtility
var _settings: GFSettingsUtility
var _signal_utility: GFSignalUtility
var _capture_enabled: bool = false
var _game_session_available: bool = false
var _gameplay_trace_active: bool = false
var _current_is_replay_mode: bool = false
var _next_input_receipt_id: int = 1
var _pending_move_input_receipts: Dictionary = {}
var _next_attempt_id: int = 1
var _active_attempt_id: int = 0
var _active_started_usec: int = 0
var _active_input_receipt_id: int = 0
var _active_input_mapped_usec: int = 0
var _active_input_source: StringName = &""
var _active_input_timestamp_observed: bool = false
var _resolved_usec: int = 0
var _presentation_pending: bool = false
var _presentation_enqueued_usec: int = 0
var _primary_feedback_usec: int = 0
var _primary_feedback_state_committed_usec: int = 0
var _primary_feedback_presented: bool = false
var _primary_feedback_frame_serial: int = 0
var _primary_feedback_frame_connection: GFSignalConnection
var _presentation_settle_candidate_usec: int = 0
var _presentation_settled_usec: int = 0
var _command_completed: bool = false
var _acceptance_observation: GamePerformanceAcceptanceObservation
var _acceptance_frame_time_ms: GFMetricSeries
var _acceptance_input_feedback_ms: GFMetricSeries
var _acceptance_capture_active: bool = false
var _acceptance_evidence_valid: bool = false
var _acceptance_terminal_reason: StringName = &""
var _acceptance_previous_frame_usec: int = 0
var _acceptance_has_frame_baseline: bool = false


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GFSessionTraceUtility,
		GameClockUtility,
		GFSettingsUtility,
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
	_clear_acceptance_measurement()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_trace = null
	_trace_recipe = null
	_clock = null
	_settings = null
	_signal_utility = null
	_capture_enabled = false
	_game_session_available = false
	_gameplay_trace_active = false
	_current_is_replay_mode = false
	_clear_pending_move_inputs(&"disposed")
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
	# 一份验收证据只属于一局。新会话即使随后启动失败，也不得沿用旧样本。
	_clear_acceptance_measurement()
	_clear_pending_move_inputs(&"new_gameplay_trace")
	_reset_active_attempt()
	_current_is_replay_mode = is_replay_mode
	var session_id: StringName = _trace.start_session(&"", {
		"feature": "gameplay",
		"is_replay_mode": is_replay_mode,
		"retention": "memory_until_next_session_or_dispose",
	})
	_gameplay_trace_active = session_id != &""
	return _gameplay_trace_active


## 停止当前轨迹并清空尚未终结的移动尝试。
## @param reason: 终止轨迹的规范原因。
func stop_gameplay_trace(reason: StringName = &"completed") -> Dictionary:
	_clear_pending_move_inputs(reason)
	_reset_active_attempt()
	_gameplay_trace_active = false
	if _acceptance_capture_active:
		_stop_acceptance_measurement(&"gameplay_trace_stopped", true)
	if not is_instance_valid(_trace):
		return {}
	return _trace.stop_session(reason)


## 开始聚合一份已经由 diagnostics 矩阵验证的真实运行时证据。
##
## 本 Utility 不依赖 diagnostics Feature，也不自行解释 case 业务语义；它只
## 持有脱敏 Observation、帧时/首反馈两条有界 GFMetricSeries 与清理生命周期。
## @param observation: 已验证、只含公开分类事实的运行条件快照。
func begin_acceptance_measurement(
	observation: GamePerformanceAcceptanceObservation
) -> Dictionary:
	if not _capture_enabled:
		return _make_acceptance_request_result(false, &"consent_required")
	if not _gameplay_trace_active:
		return _make_acceptance_request_result(false, &"gameplay_trace_inactive")
	if _current_is_replay_mode:
		return _make_acceptance_request_result(false, &"replay_mode_not_eligible")
	if _acceptance_capture_active:
		return _make_acceptance_request_result(false, &"capture_already_active")
	if (
		observation == null
		or not observation.is_structurally_valid(ACCEPTANCE_MAX_SAMPLES)
	):
		return _make_acceptance_request_result(false, &"invalid_observation")

	_clear_acceptance_measurement()
	_acceptance_observation = GamePerformanceAcceptanceObservation.new().configure(
		observation.case_id,
		observation.to_dict(),
		observation.minimum_samples
	)
	_acceptance_frame_time_ms = _create_acceptance_series(
		_ACCEPTANCE_FRAME_METRIC_ID,
		"Player-visible frame time"
	)
	_acceptance_input_feedback_ms = _create_acceptance_series(
		_ACCEPTANCE_INPUT_METRIC_ID,
		"Input to primary feedback"
	)
	_acceptance_capture_active = true
	_acceptance_evidence_valid = true
	_acceptance_terminal_reason = &"capture_active"
	return _make_acceptance_request_result(true, &"capture_started")


## 标记一次真实玩家可见帧边界。
##
## 调用方必须传入当前根视口尺寸；尺寸漂移会使整份证据失去 case 匹配资格，
## 而不是把不同条件下的帧样本混在一起。帧时由共享 GFClock 的相邻单调
## tick 计算；首帧只建立基线，不消费会受 Engine.time_scale 影响的 delta。
## @param observed_viewport_size: 当前玩家可见帧的根视口像素尺寸。
func record_player_visible_frame(
	observed_viewport_size: Vector2i
) -> void:
	if not _acceptance_capture_active:
		return
	if (
		_acceptance_observation == null
		or not _acceptance_observation.matches_viewport(observed_viewport_size)
	):
		_stop_acceptance_measurement(&"viewport_changed", true)
		return
	var now_usec: int = _get_monotonic_usec()
	if not _acceptance_has_frame_baseline:
		_acceptance_previous_frame_usec = now_usec
		_acceptance_has_frame_baseline = true
		return
	if now_usec <= _acceptance_previous_frame_usec:
		_stop_acceptance_measurement(&"non_monotonic_frame_clock", true)
		return
	var frame_time_ms: float = (
		float(now_usec - _acceptance_previous_frame_usec) / 1000.0
	)
	_acceptance_previous_frame_usec = now_usec
	_acceptance_frame_time_ms.add_sample(
		frame_time_ms,
		_acceptance_timestamp_seconds()
	)


## 显式结束当前验收采样。只有终结后 diagnostics 才会生成通过/失败结论。
func finish_acceptance_measurement() -> Dictionary:
	if _acceptance_observation == null:
		return _make_acceptance_request_result(false, &"not_measured")
	if _acceptance_capture_active:
		_stop_acceptance_measurement(&"capture_completed", false)
	return get_acceptance_measurement_state()


func is_acceptance_measurement_active() -> bool:
	return _acceptance_capture_active


## 获取不含原始样本值的有界状态，供普通诊断与 Support Report 使用。
func get_acceptance_measurement_state() -> Dictionary:
	if _acceptance_observation == null:
		return {
			&"configured": false,
			&"active": false,
			&"eligible_for_evaluation": false,
			&"status": &"not_measured",
			&"reason": (
				&"not_measured" if _capture_enabled else &"consent_required"
			),
			&"max_samples": ACCEPTANCE_MAX_SAMPLES,
			&"frame_sample_count": 0,
			&"input_feedback_sample_count": 0,
		}
	return {
		&"configured": true,
		&"active": _acceptance_capture_active,
		&"eligible_for_evaluation": (
			not _acceptance_capture_active and _acceptance_evidence_valid
		),
		&"status": (
			&"capturing" if _acceptance_capture_active else &"captured"
		),
		&"reason": _acceptance_terminal_reason,
		&"max_samples": ACCEPTANCE_MAX_SAMPLES,
		&"frame_sample_count": _acceptance_frame_time_ms.get_sample_count(),
		&"input_feedback_sample_count": (
			_acceptance_input_feedback_ms.get_sample_count()
		),
		&"observation": _acceptance_observation.to_dict(),
	}


## 返回 diagnostics 内部评估所需的复制隔离序列；Support Report 不直接
## 序列化该对象字典，而是只接收 GameplayAcceptanceMatrix 的统计快照。
func get_acceptance_measurement_bundle() -> Dictionary:
	if (
		_acceptance_observation == null
		or _acceptance_frame_time_ms == null
		or _acceptance_input_feedback_ms == null
	):
		return {}
	return {
		&"observation": _acceptance_observation.to_dict(),
		&"frame_time_ms": _acceptance_frame_time_ms.duplicate_series(true),
		&"input_feedback_ms": (
			_acceptance_input_feedback_ms.duplicate_series(true)
		),
	}


## 在项目首次接收一个抽象移动动作时冻结单调时间戳。
##
## 触控 Controller 在调用 GF virtual pulse 前使用 `touch_swipe`；键盘和
## 手柄由 PlayerInputSystem 的 GF action_started 观察使用 `gf_input_mapping`。
## 同方向新收据会替换尚未认领的旧收据，全部收据按方向和 TTL 双重有界。
## @param action_id: GameplayInputActions 中的四向抽象动作。
## @param source: 只接受项目定义的脱敏来源类别。
## @return 收据局部递增标识；轨迹未启用或动作无效时返回 0。
func capture_move_input(
	action_id: StringName,
	source: StringName = MOVE_INPUT_SOURCE_MAPPED
) -> int:
	if (
		not _capture_enabled
		or not _gameplay_trace_active
		or not is_instance_valid(_trace)
		or not _is_move_action(action_id)
	):
		return 0
	_prune_expired_move_inputs()
	var normalized_source: StringName = _normalize_input_source(source)
	_cancel_pending_move_input_for_action(action_id, &"replaced_by_new_input")
	if _pending_move_input_receipts.size() >= _MAX_PENDING_MOVE_INPUT_RECEIPTS:
		_evict_oldest_pending_move_input()

	var receipt_id: int = _next_input_receipt_id
	_next_input_receipt_id = (
		1
		if _next_input_receipt_id >= 2_147_483_647
		else _next_input_receipt_id + 1
	)
	var received_usec: int = _get_monotonic_usec()
	_pending_move_input_receipts[action_id] = {
		&"receipt_id": receipt_id,
		&"received_usec": received_usec,
		&"mapped_usec": 0,
		&"source": normalized_source,
		&"mapped": false,
	}
	_record_event(&"move_input_received", {
		&"receipt_id": receipt_id,
		&"action_id": String(action_id),
		&"source": String(normalized_source),
	})
	return receipt_id


## 确认抽象动作已经穿过 GFInputMappingUtility 并进入 PlayerInputSystem。
##
## 触控路径会认领 Controller 预先冻结的未映射收据；键盘/手柄路径在这里
## 创建收据。新的 action_started 必须取代旧的已映射收据，不沿用缓冲期间
## 上一次同方向输入的时间。返回值只用于诊断，不参与玩法结果。
## @param action_id: 已进入 PlayerInputSystem 的 GF 抽象移动动作。
func acknowledge_move_input_mapped(action_id: StringName) -> int:
	if (
		not _capture_enabled
		or not _gameplay_trace_active
		or not is_instance_valid(_trace)
		or not _is_move_action(action_id)
	):
		return 0
	_prune_expired_move_inputs()
	var receipt: Dictionary = _get_pending_move_input(action_id)
	if receipt.is_empty() or GFVariantData.get_option_bool(receipt, &"mapped"):
		var _receipt_id: int = capture_move_input(
			action_id,
			MOVE_INPUT_SOURCE_MAPPED
		)
		receipt = _get_pending_move_input(action_id)
	if receipt.is_empty():
		return 0
	var mapped_usec: int = _get_monotonic_usec()
	receipt[&"mapped"] = true
	receipt[&"mapped_usec"] = mapped_usec
	_pending_move_input_receipts[action_id] = receipt
	_record_event(&"move_input_mapped", {
		&"receipt_id": GFVariantData.get_option_int(receipt, &"receipt_id"),
		&"input_to_mapping_usec": maxi(
			mapped_usec - GFVariantData.get_option_int(receipt, &"received_usec"),
			0
		),
	})
	return GFVariantData.get_option_int(receipt, &"receipt_id")


## 取消指定的尚未认领输入，例如 GF virtual pulse 拒绝时。
## @param receipt_id: capture_move_input_received() 返回的输入收据标识。
## @param reason: 取消该输入收据的规范原因。
func cancel_move_input_receipt(
	receipt_id: int,
	reason: StringName
) -> void:
	if receipt_id <= 0:
		return
	for action_value: Variant in _pending_move_input_receipts.keys():
		var action_id: StringName = GFVariantData.to_string_name(action_value)
		var receipt: Dictionary = _get_pending_move_input(action_id)
		if GFVariantData.get_option_int(receipt, &"receipt_id") != receipt_id:
			continue
		_record_cancelled_input_receipt(receipt, reason)
		var _erased: bool = _pending_move_input_receipts.erase(action_id)
		return


## 清除不再可能由 PlayerInputSystem 消费的输入收据。
## @param reason: 脱敏的生命周期或门控原因。
## @param preserved_action_id: 可选保留当前即将缓冲/执行的方向。
func discard_pending_move_inputs(
	reason: StringName,
	preserved_action_id: StringName = &""
) -> void:
	_clear_pending_move_inputs(reason, preserved_action_id)


## 标记输入已经通过玩法门控并即将进入命令管线。
## @param direction: 本次移动的四向输入。
## @param action_id: 与 direction 对应的 GF 抽象动作，用于一次性认领输入收据。
## @return 当前尝试的局部递增标识；轨迹未启用时返回 0。
func begin_move(direction: Vector2i, action_id: StringName = &"") -> int:
	if (
		not _capture_enabled
		or not _gameplay_trace_active
		or not is_instance_valid(_trace)
	):
		return 0
	var resolved_action_id: StringName = action_id
	if resolved_action_id == &"":
		resolved_action_id = GameplayInputActions.action_for_direction(direction)
	_prune_expired_move_inputs()
	if _active_attempt_id > 0:
		_record_event(&"move_superseded", {
			"attempt_id": _active_attempt_id,
			"elapsed_usec": _elapsed_since(_active_started_usec),
		})
		_reset_active_attempt()

	var input_receipt: Dictionary = _take_mapped_move_input(resolved_action_id)
	_clear_pending_move_inputs(&"move_attempt_superseded")
	var attempt_id: int = _next_attempt_id
	_next_attempt_id = 1 if _next_attempt_id >= 2_147_483_647 else _next_attempt_id + 1
	_active_attempt_id = attempt_id
	_active_input_receipt_id = GFVariantData.get_option_int(
		input_receipt,
		&"receipt_id"
	)
	_active_input_mapped_usec = GFVariantData.get_option_int(
		input_receipt,
		&"mapped_usec"
	)
	_active_input_source = GFVariantData.get_option_string_name(
		input_receipt,
		&"source"
	)
	_active_input_timestamp_observed = not input_receipt.is_empty()
	_active_started_usec = (
		GFVariantData.get_option_int(input_receipt, &"received_usec")
		if _active_input_timestamp_observed
		else _get_monotonic_usec()
	)
	var attempt_started_usec: int = _get_monotonic_usec()
	_record_event(&"move_requested", {
		"attempt_id": attempt_id,
		"direction": _direction_id(direction),
		"input_receipt_id": _active_input_receipt_id,
		"input_source": String(_active_input_source),
		"input_timestamp_observed": _active_input_timestamp_observed,
		"input_to_attempt_usec": maxi(
			attempt_started_usec - _active_started_usec,
			0
		),
		"mapping_to_attempt_usec": (
			maxi(attempt_started_usec - _active_input_mapped_usec, 0)
			if _active_input_mapped_usec > 0
			else 0
		),
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
		_reset_attempt_after_terminal_if_ready()
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


## 标记 BoardAnimationAction 已经提交首批可见状态，并等待实际绘制终态。
##
## 音频可以独立播放，但不结束视觉指标。只有随后匹配的一次
## RenderingServer.frame_post_draw 才会记录 input_to_primary_feedback。
## @param attempt_id: mark_presentation_enqueued 返回的移动尝试标识。
func mark_primary_feedback_state_committed(attempt_id: int) -> void:
	if (
		attempt_id <= 0
		or attempt_id != _active_attempt_id
		or not _presentation_pending
		or _primary_feedback_state_committed_usec > 0
		or _primary_feedback_presented
		or not is_instance_valid(_trace)
		or not is_instance_valid(_signal_utility)
	):
		return
	_primary_feedback_state_committed_usec = _get_monotonic_usec()
	_primary_feedback_frame_serial = (
		1
		if _primary_feedback_frame_serial >= 2_147_483_647
		else _primary_feedback_frame_serial + 1
	)
	_record_event(&"move_primary_feedback_state_committed", {
		"attempt_id": attempt_id,
		"input_to_state_commit_usec": maxi(
			_primary_feedback_state_committed_usec - _active_started_usec,
			0
		),
		"enqueue_to_state_commit_usec": (
			maxi(
				_primary_feedback_state_committed_usec - _presentation_enqueued_usec,
				0
			)
			if _presentation_enqueued_usec > 0
			else 0
		),
	})
	_primary_feedback_frame_connection = _signal_utility.connect_once(
		RenderingServer.frame_post_draw,
		Callable(self, &"_on_primary_feedback_frame_post_draw"),
		self,
		[attempt_id, _primary_feedback_frame_serial]
	)
	if (
		_primary_feedback_frame_connection == null
		or not _primary_feedback_frame_connection.is_active()
	):
		_primary_feedback_frame_connection = null
		_record_event(&"move_primary_feedback_observer_failed", {
			"attempt_id": attempt_id,
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
	_reset_attempt_after_terminal_if_ready()


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
	var snapshot: Dictionary = _trace.build_recipe_snapshot(_trace_recipe, {
		"filters": {"channel_id": CHANNEL_MOVE_LATENCY},
	})
	snapshot[&"acceptance_measurement"] = get_acceptance_measurement_state()
	return snapshot


## 获取不含完整事件载荷的运行状态。
func get_debug_snapshot() -> Dictionary:
	return {
		"available": is_instance_valid(_trace),
		"capture_enabled": _capture_enabled,
		"channel_id": CHANNEL_MOVE_LATENCY,
		"recipe_id": TRACE_RECIPE_ID,
		"max_events": _MAX_EVENTS,
		"max_event_buffer_bytes": _MAX_EVENT_BUFFER_BYTES,
		"acceptance_max_samples": ACCEPTANCE_MAX_SAMPLES,
		"active_attempt": _active_attempt_id > 0,
		"presentation_pending": _presentation_pending,
		"primary_feedback_state_committed": (
			_primary_feedback_state_committed_usec > 0
		),
		"primary_feedback_frame_pending": (
			_primary_feedback_frame_connection != null
			and _primary_feedback_frame_connection.is_active()
		),
		"primary_feedback_presented": _primary_feedback_presented,
		"pending_input_receipt_count": _pending_move_input_receipts.size(),
		"acceptance_measurement": get_acceptance_measurement_state(),
		"trace": _trace.get_debug_snapshot() if is_instance_valid(_trace) else {},
	}


# --- 私有/辅助方法 ---

func _create_acceptance_series(
	metric_id: StringName,
	label: String
) -> GFMetricSeries:
	return GFMetricSeries.new().configure(metric_id, {
		&"label": label,
		&"group": "Gameplay acceptance",
		&"visible": false,
		&"max_samples": ACCEPTANCE_MAX_SAMPLES,
		&"metadata": {
			&"unit": "milliseconds",
			&"retention": "latest_gameplay_session_memory_only",
		},
	})


func _record_acceptance_input_feedback(input_feedback_ms: float) -> void:
	if (
		not _acceptance_capture_active
		or _acceptance_input_feedback_ms == null
	):
		return
	if not is_finite(input_feedback_ms) or input_feedback_ms < 0.0:
		_stop_acceptance_measurement(&"invalid_input_feedback_sample", true)
		return
	_acceptance_input_feedback_ms.add_sample(
		input_feedback_ms,
		_acceptance_timestamp_seconds()
	)


func _acceptance_timestamp_seconds() -> float:
	return float(_get_monotonic_usec()) / 1_000_000.0


func _stop_acceptance_measurement(
	reason: StringName,
	invalidate_evidence: bool
) -> void:
	if _acceptance_observation == null:
		return
	_acceptance_capture_active = false
	_acceptance_previous_frame_usec = 0
	_acceptance_has_frame_baseline = false
	if invalidate_evidence:
		_acceptance_evidence_valid = false
	_acceptance_terminal_reason = reason


func _clear_acceptance_measurement() -> void:
	if _acceptance_frame_time_ms != null:
		_acceptance_frame_time_ms.clear()
	if _acceptance_input_feedback_ms != null:
		_acceptance_input_feedback_ms.clear()
	_acceptance_observation = null
	_acceptance_frame_time_ms = null
	_acceptance_input_feedback_ms = null
	_acceptance_capture_active = false
	_acceptance_evidence_valid = false
	_acceptance_terminal_reason = &""
	_acceptance_previous_frame_usec = 0
	_acceptance_has_frame_baseline = false


func _make_acceptance_request_result(
	accepted: bool,
	reason: StringName
) -> Dictionary:
	return {
		&"accepted": accepted,
		&"reason": reason,
		&"measurement": get_acceptance_measurement_state(),
	}

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


func _on_primary_feedback_frame_post_draw(
	attempt_id: int,
	frame_serial: int
) -> void:
	if (
		attempt_id <= 0
		or attempt_id != _active_attempt_id
		or frame_serial != _primary_feedback_frame_serial
		or _primary_feedback_state_committed_usec <= 0
		or _primary_feedback_presented
	):
		return
	_disconnect_primary_feedback_frame_wait()
	_primary_feedback_usec = _get_monotonic_usec()
	_primary_feedback_presented = true
	var input_to_primary_feedback_usec: int = maxi(
		_primary_feedback_usec - _active_started_usec,
		0
	)
	_record_event(&"move_primary_feedback_presented", {
		"attempt_id": attempt_id,
		"input_to_primary_feedback_usec": input_to_primary_feedback_usec,
		"state_commit_to_present_usec": maxi(
			_primary_feedback_usec - _primary_feedback_state_committed_usec,
			0
		),
		"enqueue_to_primary_feedback_usec": (
			maxi(_primary_feedback_usec - _presentation_enqueued_usec, 0)
			if _presentation_enqueued_usec > 0
			else 0
		),
	})
	# 没有观察到真实输入入口时仍保留阶段诊断，但拒绝写入可签署指标。
	if _active_input_timestamp_observed:
		_record_acceptance_input_feedback(
			float(input_to_primary_feedback_usec) / 1000.0
		)
	_reset_attempt_after_terminal_if_ready()



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


func _get_pending_move_input(action_id: StringName) -> Dictionary:
	var value: Variant = GFVariantData.get_option_value(
		_pending_move_input_receipts,
		action_id
	)
	if value is Dictionary:
		var receipt: Dictionary = value
		return receipt
	return {}


func _take_mapped_move_input(action_id: StringName) -> Dictionary:
	if not _is_move_action(action_id):
		return {}
	var receipt: Dictionary = _get_pending_move_input(action_id)
	if receipt.is_empty() or not GFVariantData.get_option_bool(receipt, &"mapped"):
		return {}
	var _erased: bool = _pending_move_input_receipts.erase(action_id)
	return receipt


func _clear_pending_move_inputs(
	reason: StringName,
	preserved_action_id: StringName = &""
) -> void:
	for action_value: Variant in _pending_move_input_receipts.keys():
		var action_id: StringName = GFVariantData.to_string_name(action_value)
		if action_id == preserved_action_id:
			continue
		var receipt: Dictionary = _get_pending_move_input(action_id)
		_record_cancelled_input_receipt(receipt, reason)
		var _erased: bool = _pending_move_input_receipts.erase(action_id)


func _cancel_pending_move_input_for_action(
	action_id: StringName,
	reason: StringName
) -> void:
	var receipt: Dictionary = _get_pending_move_input(action_id)
	if receipt.is_empty():
		return
	_record_cancelled_input_receipt(receipt, reason)
	var _erased: bool = _pending_move_input_receipts.erase(action_id)


func _record_cancelled_input_receipt(
	receipt: Dictionary,
	reason: StringName
) -> void:
	if receipt.is_empty():
		return
	_record_event(&"move_input_cancelled", {
		&"receipt_id": GFVariantData.get_option_int(receipt, &"receipt_id"),
		&"reason": String(reason),
		&"elapsed_usec": _elapsed_since(
			GFVariantData.get_option_int(receipt, &"received_usec")
		),
	})


func _prune_expired_move_inputs() -> void:
	var now_usec: int = _get_monotonic_usec()
	for action_value: Variant in _pending_move_input_receipts.keys():
		var action_id: StringName = GFVariantData.to_string_name(action_value)
		var receipt: Dictionary = _get_pending_move_input(action_id)
		var received_usec: int = GFVariantData.get_option_int(
			receipt,
			&"received_usec"
		)
		if (
			received_usec >= 0
			and now_usec >= received_usec
			and now_usec - received_usec <= _MOVE_INPUT_RECEIPT_TTL_USEC
		):
			continue
		_record_cancelled_input_receipt(receipt, &"input_receipt_expired")
		var _erased: bool = _pending_move_input_receipts.erase(action_id)


func _evict_oldest_pending_move_input() -> void:
	var oldest_action_id: StringName = &""
	var oldest_received_usec: int = 9_223_372_036_854_775_807
	for action_value: Variant in _pending_move_input_receipts.keys():
		var action_id: StringName = GFVariantData.to_string_name(action_value)
		var received_usec: int = GFVariantData.get_option_int(
			_get_pending_move_input(action_id),
			&"received_usec",
			9_223_372_036_854_775_807
		)
		if (
			received_usec < oldest_received_usec
			or (
				received_usec == oldest_received_usec
				and (oldest_action_id == &"" or String(action_id) < String(oldest_action_id))
			)
		):
			oldest_received_usec = received_usec
			oldest_action_id = action_id
	if oldest_action_id != &"":
		_cancel_pending_move_input_for_action(
			oldest_action_id,
			&"input_receipt_capacity"
		)


func _normalize_input_source(source: StringName) -> StringName:
	if source == MOVE_INPUT_SOURCE_TOUCH:
		return MOVE_INPUT_SOURCE_TOUCH
	return MOVE_INPUT_SOURCE_MAPPED


func _is_move_action(action_id: StringName) -> bool:
	return action_id in [
		GameplayInputActions.MOVE_UP,
		GameplayInputActions.MOVE_DOWN,
		GameplayInputActions.MOVE_LEFT,
		GameplayInputActions.MOVE_RIGHT,
	]


func _disconnect_primary_feedback_frame_wait() -> void:
	if _primary_feedback_frame_connection != null:
		_primary_feedback_frame_connection.disconnect_signal()
	_primary_feedback_frame_connection = null


func _reset_attempt_after_terminal_if_ready() -> void:
	if not _command_completed or _presentation_pending:
		return
	if (
		_primary_feedback_frame_connection != null
		and _primary_feedback_frame_connection.is_active()
	):
		return
	_reset_active_attempt()


func _reset_active_attempt() -> void:
	_disconnect_primary_feedback_frame_wait()
	_active_attempt_id = 0
	_active_started_usec = 0
	_active_input_receipt_id = 0
	_active_input_mapped_usec = 0
	_active_input_source = &""
	_active_input_timestamp_observed = false
	_resolved_usec = 0
	_presentation_pending = false
	_presentation_enqueued_usec = 0
	_primary_feedback_usec = 0
	_primary_feedback_state_committed_usec = 0
	_primary_feedback_presented = false
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


func _get_settings_utility() -> GFSettingsUtility:
	var utility_value: Object = get_utility(GFSettingsUtility)
	if utility_value is GFSettingsUtility:
		var settings: GFSettingsUtility = utility_value
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
			LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
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
	if key != LOCAL_PERFORMANCE_TRACE_SETTING_KEY:
		return
	_capture_enabled = _read_capture_enabled()
	if not _capture_enabled:
		var _summary: Dictionary = stop_gameplay_trace(&"consent_revoked")
		if is_instance_valid(_trace):
			_trace.clear()
		_clear_acceptance_measurement()
		return
	if _game_session_available:
		var _started: bool = start_gameplay_trace(_current_is_replay_mode)
