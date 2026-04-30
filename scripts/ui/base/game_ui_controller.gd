## GameUIController: 游戏 UI 控制器基类，为 Control 节点提供 GF 架构访问能力。
##
## 适用于菜单、弹窗等 Control 派生节点。它为 UI 层提供与 GFController 一致的
## Model/System/Utility、Command/Query 与事件接口，并在退出场景树时自动清理事件监听。
class_name GameUIController
extends Control


# --- 常量 ---

## GFNodeContext 脚本类型，用于避免循环依赖。
const GFNodeContextBase = preload("res://addons/gf/core/gf_node_context.gd")


# --- Godot 生命周期方法 ---

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _exit_tree() -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.unregister_owner_events(self)


# --- 获取方法 ---

## 获取当前 UI 所属架构；未初始化时返回 null。
func get_architecture_or_null() -> GFArchitecture:
	var context := _find_nearest_context()
	if context != null:
		var context_architecture := context.get_architecture()
		if context_architecture != null:
			return context_architecture

	return GFAutoload.get_architecture_or_null()


## 通过类型获取 Model 实例。
func get_model(model_type: Script) -> Object:
	var architecture := get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_model(model_type)


## 通过类型获取 System 实例。
func get_system(system_type: Script) -> Object:
	var architecture := get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_system(system_type)


## 通过类型获取 Utility 实例。
func get_utility(utility_type: Script) -> Object:
	var architecture := get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_utility(utility_type)


# --- 命令与查询 ---

## 向架构发送命令。
func send_command(command: Object) -> Variant:
	var architecture := get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.send_command(command)


## 执行查询并返回结果。
func send_query(query: Object) -> Variant:
	var architecture := get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.send_query(query)


# --- 事件系统 ---

## 注册类型事件监听器。
func register_event(event_type: Script, callback: Callable, priority: int = 0) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.register_event_owned(self, event_type, callback, priority)


## 注销类型事件监听器。
func unregister_event(event_type: Script, callback: Callable) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.unregister_event(event_type, callback)


## 发送类型事件。
func send_event(event_instance: Object) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.send_event(event_instance)


## 注册轻量级 StringName 事件监听器。
func register_simple_event(event_id: StringName, callback: Callable) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.register_simple_event_owned(self, event_id, callback)


## 注销轻量级 StringName 事件监听器。
func unregister_simple_event(event_id: StringName, callback: Callable) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.unregister_simple_event(event_id, callback)


## 发送轻量级 StringName 事件。
func send_simple_event(event_id: StringName, payload: Variant = null) -> void:
	var architecture := get_architecture_or_null()
	if architecture != null:
		architecture.send_simple_event(event_id, payload)


# --- 私有/辅助方法 ---

func _find_nearest_context() -> GFNodeContextBase:
	var current_node: Node = self
	while current_node != null:
		if current_node is GFNodeContextBase:
			return current_node as GFNodeContextBase
		current_node = current_node.get_parent()

	return null


# --- 虚方法 ---

## 更新 UI 文本，子类应在此实现本地化逻辑。
func _update_ui_text() -> void:
	pass
