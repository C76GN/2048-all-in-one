## GameVirtualActionPulseUtility: 项目侧虚拟动作短脉冲适配器。
##
## GFVirtualInputSource 只拥有 press/release/clear 机制；本工具统一项目触控与 HUD
## 的“按下 → 有界延迟 → 释放”策略。同一动作在保持期内再次触发时，先结束旧
## 边沿再重新按下，确保每次 HUD 点击都能形成独立的 GF just_started；同时只
## 允许最新 token 最终释放动作。取消或场景退出时则清除来源贡献，避免留下卡住
## 的虚拟输入。
class_name GameVirtualActionPulseUtility
extends RefCounted


# --- 私有变量 ---

var _source: GFVirtualInputSource = null
var _action_tokens: Dictionary = {}
var _disposed: bool = false


# --- 公共方法 ---

## 绑定调用方拥有的 GF 虚拟输入源。
## @param source: 调用方拥有的 GF 虚拟输入源。
func configure(source: GFVirtualInputSource) -> GameVirtualActionPulseUtility:
	cancel_all()
	_source = source
	_disposed = false
	return self


## 注入一个有界虚拟动作脉冲。
##
## 调用方继续拥有 action_id 与 hold_seconds 的产品语义；本工具只保证生命周期、
## 重入与最终释放。计时器忽略暂停和 time scale，暂停菜单或慢动作不会卡住动作。
## @param action_id: 要注入的规范输入动作 ID。
## @param scene_tree: 拥有忽略暂停计时器的场景树。
## @param hold_seconds: 动作保持按下的有界秒数。
func pulse(
	action_id: StringName,
	scene_tree: SceneTree,
	hold_seconds: float
) -> bool:
	if (
		_disposed
		or action_id == &""
		or not is_instance_valid(_source)
		or not is_instance_valid(scene_tree)
	):
		return false

	var token: int = GFVariantData.get_option_int(_action_tokens, action_id) + 1
	if _action_tokens.has(action_id):
		var _released_previous_edge: bool = _source.release(action_id)
	_action_tokens[action_id] = token
	if not _source.press(action_id):
		var _removed_failed_token: bool = _action_tokens.erase(action_id)
		return false

	var release_timer: SceneTreeTimer = scene_tree.create_timer(
		maxf(hold_seconds, 0.0),
		true,
		false,
		true
	)
	var connect_error: int = _connect_release_timer(
		release_timer,
		action_id,
		token
	)
	if connect_error != OK:
		# 按下已经提交，计时器连接失败时必须在返回失败前撤销贡献；
		# 否则动作会永久保持，且 token 会伪装成仍有终态在途。
		var _released_failed_pulse: bool = _source.release(action_id)
		if GFVariantData.get_option_int(_action_tokens, action_id) == token:
			var _removed_failed_connection_token: bool = _action_tokens.erase(
				action_id
			)
		return false
	return true


## 清除当前来源的全部动作贡献，并让所有迟到计时器失效。
func cancel_all() -> void:
	_action_tokens.clear()
	if is_instance_valid(_source):
		_source.clear_all()


## 结束适配器生命周期；迟到计时器只会安全退出。
func dispose() -> void:
	cancel_all()
	_source = null
	_disposed = true


## 返回当前仍等待最终释放的动作数，用于诊断与测试。
func get_pending_action_count() -> int:
	return _action_tokens.size()


# --- 私有/辅助方法 ---

func _connect_release_timer(
	release_timer: SceneTreeTimer,
	action_id: StringName,
	token: int
) -> int:
	return release_timer.timeout.connect(
		_release_action.bind(action_id, token),
		CONNECT_ONE_SHOT
	)

func _release_action(action_id: StringName, token: int) -> void:
	if (
		_disposed
		or GFVariantData.get_option_int(_action_tokens, action_id) != token
	):
		return
	if is_instance_valid(_source):
		var _released: bool = _source.release(action_id)
	var _removed_token: bool = _action_tokens.erase(action_id)
