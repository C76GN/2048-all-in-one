# scripts/core/state_machine.gd

## StateMachine: 一个通用的有限状态机 (FSM) 节点。
##
## 该节点被设计为任何需要状态管理逻辑的父节点的子节点。它通过直接调用
## 父节点上约定的函数 (_enter_state, _exit_state, _process_state) 来工作，
## 实现了状态逻辑与状态机引擎的分离，保持了父节点的整洁。
class_name StateMachine
extends Node


# --- 信号 ---

## 当状态成功切换后发出。
## @param new_state_name: 进入的新状态的名称。
signal state_changed(new_state_name: Variant)


# --- 私有变量 ---

## 对拥有此状态机的父节点的引用。
var _parent: Node

## 当前状态的名称。
var _current_state_name: Variant


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_parent = get_parent()
	await get_parent().ready


func _process(delta: float) -> void:
	if _current_state_name != null and _parent.has_method("_process_state"):
		_parent._process_state(delta, _current_state_name)


# --- 公共方法 ---

## 切换到新状态。这是控制状态机的核心函数。
## @param new_state_name: 要切换到的新状态的名称。
## @param message: 一个可选的字典，用于在状态间传递数据。
func set_state(new_state_name: Variant, message: Dictionary = {}) -> void:
	if new_state_name == _current_state_name:
		return

	if _current_state_name != null and _parent.has_method("_exit_state"):
		_parent._exit_state(_current_state_name)

	_current_state_name = new_state_name

	if _parent.has_method("_enter_state"):
		_parent._enter_state(_current_state_name, message)

	state_changed.emit(_current_state_name)


## 获取状态机当前的状态。
## @return: 当前状态的名称。
func get_current_state() -> Variant:
	return _current_state_name
