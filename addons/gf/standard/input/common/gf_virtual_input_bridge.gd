## GFVirtualInputBridge: InputMap 与虚拟手柄事件桥接工具。
##
## 将触屏按钮、虚拟摇杆或项目自定义输入源写入 Godot InputMap action，
## 或发送虚拟 joypad button/axis 事件。它不创建 InputMap 动作，也不绑定玩家席位。
## [br]
## @api public
## [br]
## @category runtime_service
## [br]
## @since unreleased
class_name GFVirtualInputBridge
extends RefCounted


# --- 常量 ---

const _ACTION_PRESS_REGISTRY = preload("res://addons/gf/standard/input/common/gf_input_action_press_registry.gd")


# --- 公共方法 ---

## 以指定 owner 身份按下 InputMap action。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param action_id: InputMap action 名。
## [br]
## @param owner_id: 当前虚拟输入来源的稳定 owner ID。
## [br]
## @param strength: action 强度；非有限值会被视为 0。
## [br]
## @return action 与 owner 有效时返回 true。
static func press_action(action_id: StringName, owner_id: String, strength: float = 1.0) -> bool:
	if action_id == &"" or owner_id.is_empty():
		return false
	_ACTION_PRESS_REGISTRY.press(action_id, owner_id, _normalize_strength(strength))
	return true


## 释放指定 owner 身份按下的 InputMap action。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param action_id: InputMap action 名。
## [br]
## @param owner_id: 当前虚拟输入来源的稳定 owner ID。
## [br]
## @return action 与 owner 有效时返回 true。
static func release_action(action_id: StringName, owner_id: String) -> bool:
	if action_id == &"" or owner_id.is_empty():
		return false
	_ACTION_PRESS_REGISTRY.release(action_id, owner_id)
	return true


## 释放指定 owner 持有的所有 InputMap action。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param owner_id: 当前虚拟输入来源的稳定 owner ID。
## [br]
## @return owner 有效时返回 true。
static func release_owner(owner_id: String) -> bool:
	if owner_id.is_empty():
		return false
	_ACTION_PRESS_REGISTRY.release_owner(owner_id)
	return true


## 发送虚拟手柄按钮事件。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param device_id: 虚拟手柄设备 ID。
## [br]
## @param button: 手柄按钮。
## [br]
## @param pressed: 是否按下。
static func emit_joypad_button(device_id: int, button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## 发送虚拟手柄轴事件。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param device_id: 虚拟手柄设备 ID。
## [br]
## @param axis: 手柄轴。
## [br]
## @param value: 轴值；会钳制到 -1..1，非有限值会视为 0。
static func emit_joypad_axis(device_id: int, axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = _normalize_axis_value(value)
	Input.parse_input_event(event)


## 创建稳定 owner ID。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param owner: 当前虚拟输入来源对象。
## [br]
## @param channel_id: owner 内部的通道 ID。
## [br]
## @return 稳定 owner ID；owner 无效时返回空字符串。
static func make_owner_id(owner: Object, channel_id: StringName) -> String:
	if not is_instance_valid(owner):
		return ""
	return "%d:%s" % [owner.get_instance_id(), String(channel_id)]


# --- 私有/辅助方法 ---

static func _normalize_strength(strength: float) -> float:
	if is_nan(strength) or is_inf(strength):
		return 0.0
	return clampf(strength, 0.0, 1.0)


static func _normalize_axis_value(value: float) -> float:
	if is_nan(value) or is_inf(value):
		return 0.0
	return clampf(value, -1.0, 1.0)
