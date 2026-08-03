## GameVirtualActionPulseUtility: 项目侧可重触发虚拟动作脉冲策略。
##
## GFVirtualInputSource 拥有定时、owner 生命周期、lease 交接与唯一终态。本适配器
## 只保留项目产品语义：同一动作仍在保持期时再次点击，必须先结束旧贡献再启动
## 新脉冲，从而让每次 HUD/触控点击都形成独立的 GF just_started 边沿。
class_name GameVirtualActionPulseUtility
extends RefCounted


# --- 私有变量 ---

var _source: GFVirtualInputSource = null
var _active_operations: Dictionary = {}
var _disposed: bool = false


# --- 公共方法 ---

## 绑定调用方拥有且已经注入 GFTimerUtility 的 GF 虚拟输入源。
## @param source: 调用方拥有的 GF 虚拟输入源。
func configure(source: GFVirtualInputSource) -> GameVirtualActionPulseUtility:
	cancel_all()
	_source = source
	_disposed = false
	return self


## 注入一个有界且可重触发的虚拟动作脉冲。
##
## owner 与脉冲终态由 GFVirtualInputSource 管理；hold_seconds 的暂停/time scale
## 语义由创建 source 时注入的 GFTimerUtility 决定。
## @param action_id: 要注入的规范输入动作 ID。
## @param owner: 持有此次脉冲的活动场景节点。
## @param hold_seconds: 动作保持按下的有界秒数。
func pulse(
	action_id: StringName,
	owner: Node,
	hold_seconds: float
) -> bool:
	if (
		_disposed
		or action_id == &""
		or not is_instance_valid(_source)
		or not is_instance_valid(owner)
		or not owner.is_inside_tree()
	):
		return false

	var previous: GFVirtualInputPulseOperation = _get_active_operation(action_id)
	if previous != null and previous.is_pending():
		# GF 的 REPLACE 是无释放的原子交接，不能生成第二个 just_started。
		# 项目点击语义要求显式结束旧 lease，再启动新的 GF 脉冲。
		if not _source.clear_action(action_id):
			return false

	var operation: GFVirtualInputPulseOperation = _source.pulse_action(
		action_id,
		true,
		maxf(hold_seconds, 0.0),
		owner,
		null,
		GFVirtualInputSource.PulseReplacementPolicy.REPLACE
	)
	if operation == null:
		return false
	if operation.is_pending():
		_active_operations[action_id] = operation
		var connect_error: int = operation.completed.connect(
			_on_pulse_completed.bind(action_id),
			CONNECT_ONE_SHOT
		)
		if connect_error != OK:
			var _cancelled_unobserved: bool = operation.cancel(
				&"project_observer_connect_failed"
			)
			var _removed_unobserved: bool = _active_operations.erase(action_id)
			return false
		return true

	return operation.get_status() == GFVirtualInputPulseOperation.Status.COMPLETED


## 清除当前来源的全部动作贡献，并让 GF 终结所有活动脉冲。
func cancel_all() -> void:
	if is_instance_valid(_source):
		_source.clear_all()
	_active_operations.clear()


## 结束适配器生命周期。
func dispose() -> void:
	cancel_all()
	_source = null
	_disposed = true


## 返回当前仍等待 GF 终态的动作数，用于诊断与测试。
func get_pending_action_count() -> int:
	_prune_completed_operations()
	return _active_operations.size()


## 返回指定动作当前由适配器追踪的 GF 类型化脉冲句柄。
## @param action_id: 规范输入动作 ID。
func get_active_operation(action_id: StringName) -> GFVirtualInputPulseOperation:
	var operation: GFVirtualInputPulseOperation = _get_active_operation(action_id)
	if operation != null and operation.is_completed():
		var _removed_completed: bool = _active_operations.erase(action_id)
		return null
	return operation


# --- 私有/辅助方法 ---

func _on_pulse_completed(
	operation: GFVirtualInputPulseOperation,
	action_id: StringName
) -> void:
	if _get_active_operation(action_id) == operation:
		var _removed: bool = _active_operations.erase(action_id)


func _prune_completed_operations() -> void:
	for action_value: Variant in _active_operations.keys():
		var action_id: StringName = GFVariantData.to_string_name(action_value)
		var operation: GFVirtualInputPulseOperation = _get_active_operation(action_id)
		if operation == null or operation.is_completed():
			var _removed: bool = _active_operations.erase(action_id)


func _get_active_operation(action_id: StringName) -> GFVirtualInputPulseOperation:
	var operation_value: Variant = GFVariantData.get_option_value(
		_active_operations,
		action_id
	)
	if operation_value is GFVirtualInputPulseOperation:
		var operation: GFVirtualInputPulseOperation = operation_value
		return operation
	return null
