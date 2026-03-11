# scripts/ui/base/gf_ui_controller.gd

class_name GFUIController
extends Control

## GFUIController: UI 控制器的基类，为 UI 提供框架能力的接口。
##
## 继承自 Control，平移了 GFController 的懒加载获取与事件转发能力，
## 并自动处理本地化翻译更新的模板逻辑。


# --- 私有变量 ---

## 懒加载缓存字典。
var _cache: Dictionary = {}


# --- Godot 生命周期方法 ---

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 获取方法 (懒加载缓存) ---

## 通过类型获取 Model 实例。
func get_model(model_type: Script) -> Object:
	if not _cache.has(model_type):
		_cache[model_type] = Gf.get_architecture().get_model(model_type)
	return _cache[model_type]


## 通过类型获取 System 实例。
func get_system(system_type: Script) -> Object:
	if not _cache.has(system_type):
		_cache[system_type] = Gf.get_architecture().get_system(system_type)
	return _cache[system_type]


## 通过类型获取 Utility 实例。
func get_utility(utility_type: Script) -> Object:
	if not _cache.has(utility_type):
		_cache[utility_type] = Gf.get_architecture().get_utility(utility_type)
	return _cache[utility_type]


# --- 命令与查询 ---

## 向架构发送命令。
func send_command(command: Object) -> Variant:
	return Gf.get_architecture().send_command(command)


## 执行查询并返回结果。
func send_query(query: Object) -> Variant:
	return Gf.get_architecture().send_query(query)


# --- 事件系统 ---

## 发送轻量级 StringName 事件。
func send_simple_event(event_id: StringName, payload: Variant = null) -> void:
	Gf.get_architecture().send_simple_event(event_id, payload)


# --- 虚方法 (需子类覆写) ---

## 更新 UI 文本，子类应在此实现本地化逻辑。
func _update_ui_text() -> void:
	pass
