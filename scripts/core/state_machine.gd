# scripts/core/state_machine.gd

## StateMachine: 一个通用的有限状态机 (FSM) 节点。
##
## 该节点使用状态对象模式，通过子节点管理不同的游戏状态。
class_name StateMachine
extends Node


# --- 信号 ---

## 当状态成功切换后发出。
## @param new_state_name: 进入的新状态的名称。
signal state_changed(new_state_name: String)


# --- 私有变量 ---

## 当前状态对象。
var current_state: GameState

## 所有状态的字典，键为状态名称。
var _states: Dictionary = {}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	for child in get_children():
		if child is GameState:
			_states[child.name] = child
			child.game_play = get_parent()


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)


# --- 公共方法 ---

## 切换到新状态。
## @param state_name: 要切换到的新状态的名称。
## @param msg: 一个可选的字典，用于在状态间传递数据。
func change_state(state_name: String, msg: Dictionary = {}) -> void:
	if not _states.has(state_name):
		return

	if current_state:
		current_state.exit()

	current_state = _states[state_name]
	current_state.enter(msg)
	state_changed.emit(state_name)


## 获取状态机当前的状态名称。
## @return: 当前状态的名称。
func get_current_state() -> String:
	if current_state:
		return current_state.name
	return ""
