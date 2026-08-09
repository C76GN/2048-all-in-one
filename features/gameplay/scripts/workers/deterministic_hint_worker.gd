## DeterministicHintWorker: 在 GFBackgroundWorkUtility 线程中执行纯数据提示查询。
##
## Worker 只接收棋盘快照、稳定摘要、generation、确定性步数预算，以及一个
## 项目拥有、Mutex 同步的只读取消令牌，并只返回 Variant 字典。它不读取
## Architecture、Node、Resource、随机数或系统墙钟。
class_name DeterministicHintWorker
extends RefCounted


const DeterministicHintQueryType = preload(
	"res://features/gameplay/scripts/queries/deterministic_hint_query.gd"
)


## 创建可安全跨主线程/Worker 线程轮询的提示取消令牌。
## GFBackgroundWorkUtility 暂未把自身 cancel_requested 暴露给 worker；调用方仅为
## 这个明确的线程安全句柄启用 allow_object_payloads。
static func create_cancellation_token() -> GFCancellationToken:
	return _CooperativeCancellationToken.new()


## 从主线程请求合作式取消。
## @param token: 由 create_cancellation_token() 创建的线程安全令牌。
## @param reason: 稳定的取消原因；空值会归一化为 cancelled。
static func request_cancellation(
	token: GFCancellationToken,
	reason: StringName = &"cancelled"
) -> bool:
	if token is _CooperativeCancellationToken:
		var cooperative_token: _CooperativeCancellationToken = token
		return cooperative_token.request_cancellation(reason)
	return false


## 获取 Worker 已轮询令牌的次数，供并发取消回归建立真实握手。
## @param token: 由 create_cancellation_token() 创建的线程安全令牌。
static func get_cancellation_poll_count(token: GFCancellationToken) -> int:
	if token is _CooperativeCancellationToken:
		var cooperative_token: _CooperativeCancellationToken = token
		return cooperative_token.get_poll_count()
	return 0


## 返回 Worker 是否已经在线程内观察到取消状态。
## @param token: 由 create_cancellation_token() 创建的线程安全令牌。
static func was_cancellation_observed(token: GFCancellationToken) -> bool:
	if token is _CooperativeCancellationToken:
		var cooperative_token: _CooperativeCancellationToken = token
		return cooperative_token.was_cancellation_observed()
	return false


## @param input_data: board_snapshot、snapshot_id、generation 与 max_steps。
## @return 可跨线程边界传递的纯数据结果。
func run(input_data: Variant) -> Dictionary:
	var payload: Dictionary = GFVariantData.as_dictionary(input_data)
	var board_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		payload,
		&"board_snapshot"
	)
	var snapshot_id: String = GFVariantData.get_option_string(
		payload,
		&"snapshot_id"
	)
	var generation: int = GFVariantData.get_option_int(payload, &"generation")
	var max_steps: int = GFVariantData.get_option_int(payload, &"max_steps")
	var cancel_token: GFCancellationToken = null
	var cancel_token_value: Variant = GFVariantData.get_option_value(
		payload,
		&"cancel_token"
	)
	if cancel_token_value is GFCancellationToken:
		cancel_token = cancel_token_value
	if (
		board_snapshot.is_empty()
		or snapshot_id.is_empty()
		or generation <= 0
		or max_steps <= 0
	):
		return {
			&"generation": generation,
			&"snapshot_id": snapshot_id,
			&"result": {},
		}

	var budget: GFExecutionBudget = GFExecutionBudget.new(
		{
			&"max_steps": max_steps,
			&"cancel_token": cancel_token,
			&"metadata": {
				&"operation": &"deterministic_game_hint",
				&"snapshot_id": snapshot_id,
			},
		},
		# 后台负载不得让同一输入的结果字段随调度时机变化；此工作只使用
		# 确定性步数预算，因此用冻结单调时钟记录稳定的 0 ms 诊断值。
		GFManualClock.new()
	)
	var result: GameHintResult = DeterministicHintQueryType.new().evaluate(
		board_snapshot,
		snapshot_id,
		budget
	)
	return {
		&"generation": generation,
		&"snapshot_id": snapshot_id,
		&"result": result.to_dict() if result != null else {},
	}


# --- 内部类 ---

## 只提供轮询语义的线程安全 GFCancellationToken。
## 状态读写全部经过 Mutex；不跨线程发射 signal，也不暴露可变 metadata。
class _CooperativeCancellationToken extends GFCancellationToken:
	var _state_mutex: Mutex = Mutex.new()
	var _requested: bool = false
	var _reason: StringName = &""
	var _poll_count: int = 0
	var _cancellation_observed: bool = false


	## @param reason: 稳定的取消原因；空值会归一化为 cancelled。
	func request_cancellation(reason: StringName) -> bool:
		_state_mutex.lock()
		var changed: bool = not _requested
		if changed:
			_requested = true
			_reason = reason if reason != &"" else &"cancelled"
		_state_mutex.unlock()
		return changed


	func is_cancel_requested() -> bool:
		_state_mutex.lock()
		_poll_count += 1
		var requested: bool = _requested
		if requested:
			_cancellation_observed = true
		_state_mutex.unlock()
		return requested


	func get_cancel_reason() -> StringName:
		_state_mutex.lock()
		var reason: StringName = _reason
		_state_mutex.unlock()
		return reason


	func get_cancel_requested_msec() -> int:
		# 确定性 Worker 不读取墙钟；取消时刻只用于可选诊断，因此保持稳定零值。
		return 0


	func get_cancel_metadata() -> Dictionary:
		return {}


	func get_poll_count() -> int:
		_state_mutex.lock()
		var poll_count: int = _poll_count
		_state_mutex.unlock()
		return poll_count


	func was_cancellation_observed() -> bool:
		_state_mutex.lock()
		var observed: bool = _cancellation_observed
		_state_mutex.unlock()
		return observed


	func get_debug_snapshot() -> Dictionary:
		_state_mutex.lock()
		var snapshot: Dictionary = {
			&"cancel_requested": _requested,
			&"reason": _reason,
			&"metadata": {},
			&"cancel_requested_msec": 0,
			&"thread_safe_polling": true,
			&"poll_count": _poll_count,
			&"cancellation_observed": _cancellation_observed,
		}
		_state_mutex.unlock()
		return snapshot
