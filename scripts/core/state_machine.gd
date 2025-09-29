# scripts/core/state_machine.gd

## StateMachine: 一个通用的有限状态机 (FSM) 节点。
##
## 该节点被设计为任何需要状态管理逻辑的父节点的子节点。它通过直接调用
## 父节点上约定的函数 (_enter_state, _exit_state, _process_state) 来工作，
## 实现了状态逻辑与状态机引擎的分离，保持了父节点的整洁。
class_name StateMachine
extends Node

## 当状态成功切换后发出。
## @param new_state_name: 进入的新状态的名称。
signal state_changed(new_state_name)

# --- 内部状态 ---

# 对拥有此状态机的父节点的引用。
var _parent: Node
# 当前状态的名称。
var current_state_name

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 自动获取父节点引用。
	_parent = get_parent()
	# 确保状态机在父节点准备好之后才开始工作。
	await get_parent().ready


## Godot生命周期函数：每帧调用。
func _process(delta: float) -> void:
	# 如果当前有状态，并且父节点实现了 _process_state 方法，则调用它。
	if current_state_name != null and _parent.has_method("_process_state"):
		_parent._process_state(delta, current_state_name)


## 切换到新状态。这是控制状态机的核心函数。
## @param new_state_name: 要切换到的新状态的名称。
## @param message: 一个可选的字典，用于在状态间传递数据。
func set_state(new_state_name, message: Dictionary = {}) -> void:
	# 如果要切换的状态与当前状态相同，则不执行任何操作。
	if new_state_name == current_state_name:
		return

	# 如果存在当前状态，并且父节点实现了 _exit_state 方法，则调用它。
	if current_state_name != null and _parent.has_method("_exit_state"):
		_parent._exit_state(current_state_name)

	# 更新当前状态。
	current_state_name = new_state_name
	
	# 如果父节点实现了 _enter_state 方法，则调用它，并传递消息。
	if _parent.has_method("_enter_state"):
		_parent._enter_state(current_state_name, message)
	
	# 发出状态已改变的信号。
	state_changed.emit(current_state_name)
