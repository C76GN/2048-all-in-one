## GameUIController: 游戏 UI 控制器基类，为 Control 节点提供 GF 架构访问能力。
##
## 适用于菜单、弹窗等 Control 派生节点。它为 UI 层提供与 GFController 一致的
## Model/System/Utility、Command/Query 与事件接口，并在退出场景树时自动清理事件监听。
class_name GameUIController
extends Control


# --- 常量 ---

## GameUiMotionUtility 脚本类型，用作 GF Utility 注册键。
const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload("res://scripts/utilities/game_ui_motion_utility.gd")
const _GF_AUTOLOAD_SCRIPT = preload("res://addons/gf/kernel/core/gf_autoload.gd")
const GFNodeContextBase = preload("res://addons/gf/kernel/core/gf_node_context.gd")


# --- Godot 生命周期方法 ---

func _enter_tree() -> void:
	call_deferred(&"_apply_default_ui_motion")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _exit_tree() -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_owner_events(self)


# --- 获取方法 ---

## 获取当前 UI 所属架构；未初始化时返回 null。
func get_architecture_or_null() -> GFArchitecture:
	var context: GFNodeContextBase = _find_nearest_context()
	if context != null:
		var context_architecture: GFArchitecture = context.get_architecture()
		if context_architecture != null:
			return context_architecture

	return _GF_AUTOLOAD_SCRIPT.get_architecture_or_null()


## 通过类型获取 Model 实例。
## @param model_type: 要查找的 Model 脚本类型。
func get_model(model_type: Script) -> Object:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_model(model_type)


## 通过类型获取 System 实例。
## @param system_type: 要查找的 System 脚本类型。
func get_system(system_type: Script) -> Object:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_system(system_type)


## 通过类型获取 Utility 实例。
## @param utility_type: 要查找的 Utility 脚本类型。
func get_utility(utility_type: Script) -> Object:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.get_utility(utility_type)


# --- 命令与查询 ---

## 向架构发送命令。
## @param command: 要执行的命令对象。
func send_command(command: Object) -> Variant:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.send_command(command)


## 执行查询并返回结果。
## @param query: 要执行的查询对象。
func send_query(query: Object) -> Variant:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.send_query(query)


# --- 事件系统 ---

## 注册类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param callback: 事件触发时调用的回调。
## @param priority: 监听器优先级。
func register_event(event_type: Script, callback: Callable, priority: int = 0) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.register_event_owned(self, event_type, callback, priority)


## 注销类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param callback: 注册时使用的回调。
func unregister_event(event_type: Script, callback: Callable) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_event(event_type, callback)


## 发送类型事件。
## @param event_instance: 要派发的事件对象。
func send_event(event_instance: Object) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.send_event(event_instance)


## 注册轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param callback: 事件触发时调用的回调。
func register_simple_event(event_id: StringName, callback: Callable) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.register_simple_event_owned(self, event_id, callback)


## 注销轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param callback: 注册时使用的回调。
func unregister_simple_event(event_id: StringName, callback: Callable) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.unregister_simple_event(event_id, callback)


## 发送轻量级 StringName 事件。
## @param event_id: 简单事件标识。
## @param payload: 可选事件载荷。
func send_simple_event(event_id: StringName, payload: Variant = null) -> void:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture != null:
		architecture.send_simple_event(event_id, payload)


# --- 虚方法 ---

## 更新 UI 文本，子类应在此实现本地化逻辑。
func _update_ui_text() -> void:
	pass


# --- 私有/辅助方法 ---

func _find_nearest_context() -> GFNodeContextBase:
	var current_node: Node = self
	while current_node != null:
		if current_node is GFNodeContextBase:
			var context: GFNodeContextBase = current_node
			return context
		current_node = current_node.get_parent()

	return null


func _apply_default_ui_motion() -> void:
	if not is_inside_tree():
		return

	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var _bound_count: int = motion_utility.bind_interactive_controls(self)
	var _intro_tween: Tween = motion_utility.play_panel_intro(self)


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(_GAME_UI_MOTION_UTILITY_SCRIPT)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null
