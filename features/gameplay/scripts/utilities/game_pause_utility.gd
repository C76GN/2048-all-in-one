## GamePauseUtility: 对局暂停状态 Adapter。
##
## 以 GFTimeUtility 为逻辑时间的唯一事实，同时同步 SceneTree 暂停状态，
## 避免 GF System 与 Godot Node 在暂停期间继续以不同时间语义运行。
class_name GamePauseUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal pause_state_changed(is_paused: bool)


# --- 私有变量 ---

var _time_utility: GFTimeUtility


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFTimeUtility]


func ready() -> void:
	_time_utility = _get_time_utility()
	if not is_instance_valid(_time_utility):
		push_error("[GamePauseUtility] 缺少 GFTimeUtility，无法统一对局暂停状态。")
		return

	var _synchronized: bool = set_paused(false)
	register_simple_event(
		EventNames.SCENE_WILL_CHANGE,
		GFEventListener.from_method(self, &"_on_scene_will_change", 1)
	)


func dispose() -> void:
	var _resumed: bool = set_paused(false)
	_time_utility = null


# --- 公共方法 ---

## 同步设置 GF 逻辑时间与 Godot 场景树暂停状态。
## @param paused: true 表示暂停，false 表示恢复。
func set_paused(paused: bool) -> bool:
	if not is_instance_valid(_time_utility):
		_time_utility = _get_time_utility()
	if not is_instance_valid(_time_utility):
		push_error("[GamePauseUtility] GFTimeUtility 不可用，拒绝修改暂停状态。")
		return false

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree):
		push_error("[GamePauseUtility] SceneTree 不可用，拒绝修改暂停状态。")
		return false

	var state_changed: bool = _time_utility.is_paused != paused or tree.paused != paused
	_time_utility.is_paused = paused
	tree.paused = paused
	if state_changed:
		pause_state_changed.emit(paused)
	return true


func pause() -> bool:
	return set_paused(true)


func resume() -> bool:
	return set_paused(false)


func is_paused() -> bool:
	if not is_instance_valid(_time_utility):
		_time_utility = _get_time_utility()
	return is_instance_valid(_time_utility) and _time_utility.is_time_paused()


func is_synchronized() -> bool:
	if not is_instance_valid(_time_utility):
		_time_utility = _get_time_utility()
	var tree: SceneTree = _get_scene_tree()
	return (
		is_instance_valid(_time_utility)
		and is_instance_valid(tree)
		and _time_utility.is_paused == tree.paused
	)


# --- 私有/辅助方法 ---

func _get_time_utility() -> GFTimeUtility:
	var utility_value: Object = get_utility(GFTimeUtility)
	if utility_value is GFTimeUtility:
		var time_utility: GFTimeUtility = utility_value
		return time_utility
	return null


func _get_scene_tree() -> SceneTree:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		return tree
	return null


func _on_scene_will_change(_payload: Variant = null) -> void:
	var _resumed: bool = resume()
