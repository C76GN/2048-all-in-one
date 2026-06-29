## SceneRouterSystem: 负责全局的场景切换与路由控制。
##
## 负责管理并执行全局的场景跳转功能。
## 任何需要切换场景的模块，通过调用此系统的公共方法或发送事件来实现。
class_name SceneRouterSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SceneRouterSystem"


# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://scenes/menus/main_menu.tscn"
var _log: GFLogUtility
var _scene_utility: GFSceneUtility
var _signal_utility: GFSignalUtility
var _scene_switch_started_connection: GFSignalConnection
var _scene_load_completed_connection: GFSignalConnection
var _scene_load_failed_connection: GFSignalConnection


# --- Godot 生命周期方法 ---

func ready() -> void:
	_log = _get_log_utility()
	_scene_utility = _get_scene_utility()
	_signal_utility = _get_signal_utility()
	_connect_scene_utility_signals()

	# 可选：监听全局事件 `scene_change_requested` 以解耦调用
	register_simple_event(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)


func dispose() -> void:
	unregister_simple_event(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	unregister_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)
	_disconnect_scene_utility_signals()
	_scene_utility = null
	_signal_utility = null
	_log = null
	_scene_switch_started_connection = null
	_scene_load_completed_connection = null
	_scene_load_failed_connection = null


# --- 公共方法 ---

## 切换到指定的场景资源。
## @param scene: 待切换的场景资源 (PackedScene)。
func goto_scene_packed(scene: PackedScene) -> void:
	if not _is_scene_resource_ready(scene):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "传入的场景资源为空或不可实例化。")
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, _get_scene_resource_path(scene))
		return

	if is_instance_valid(_scene_utility) and not scene.resource_path.is_empty():
		goto_scene(scene.resource_path)
		return

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree):
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return

	if is_instance_valid(tree.current_scene):
		send_simple_event(EventNames.SCENE_WILL_CHANGE)

	var error: int = tree.change_scene_to_packed(scene)
	if error != OK:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "切换到场景失败，错误码: %d" % error)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已请求切换到场景: %s" % scene.resource_path)


## 切换到指定的场景路径。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "场景路径必须是绝对的 .tscn 资源路径: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if not ResourceLoader.exists(path, "PackedScene"):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "场景资源不存在或不是 PackedScene: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if is_instance_valid(_scene_utility):
		_scene_utility.load_scene_async(path)
		return

	var next_scene_packed: PackedScene = _load_packed_scene(path)
	if next_scene_packed == null:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "无法加载场景资源: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	goto_scene_packed(next_scene_packed)


## 快速返回到主菜单。
func return_to_main_menu() -> void:
	goto_scene(_main_menu_scene_path)


## 安全地退出整个游戏。
func quit_game() -> void:
	if is_instance_valid(_log):
		_log.info(_LOG_TAG, "正在退出游戏。")
	var tree: SceneTree = _get_scene_tree()
	if is_instance_valid(tree):
		tree.quit()


# --- 私有/辅助方法 ---

func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_scene_utility() -> GFSceneUtility:
	var utility_value: Object = get_utility(GFSceneUtility)
	if utility_value is GFSceneUtility:
		var scene_utility: GFSceneUtility = utility_value
		return scene_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_scene_tree() -> SceneTree:
	var loop_value: MainLoop = Engine.get_main_loop()
	if loop_value is SceneTree:
		var tree: SceneTree = loop_value
		return tree
	return null


func _load_packed_scene(path: String) -> PackedScene:
	var resource: Resource = ResourceLoader.load(path)
	if resource is PackedScene:
		var packed_scene: PackedScene = resource
		return packed_scene
	return null


func _connect_scene_utility_signals() -> void:
	if not is_instance_valid(_scene_utility):
		return

	if is_instance_valid(_signal_utility):
		_scene_switch_started_connection = _signal_utility.connect_signal(_scene_utility.scene_switch_started, _on_scene_switch_started, self)
		_scene_load_completed_connection = _signal_utility.connect_signal(_scene_utility.scene_load_completed, _on_scene_load_completed, self)
		_scene_load_failed_connection = _signal_utility.connect_signal(_scene_utility.scene_load_failed, _on_scene_load_failed, self)
		return

	if not _scene_utility.scene_switch_started.is_connected(_on_scene_switch_started):
		var _connect_result_134: int = _scene_utility.scene_switch_started.connect(_on_scene_switch_started)
	if not _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
		var _connect_result_136: int = _scene_utility.scene_load_completed.connect(_on_scene_load_completed)
	if not _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
		var _connect_result_138: int = _scene_utility.scene_load_failed.connect(_on_scene_load_failed)


func _disconnect_scene_utility_signals() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
		return

	if not is_instance_valid(_scene_utility):
		return

	if _scene_utility.scene_switch_started.is_connected(_on_scene_switch_started):
		_scene_utility.scene_switch_started.disconnect(_on_scene_switch_started)
	if _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
		_scene_utility.scene_load_completed.disconnect(_on_scene_load_completed)
	if _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
		_scene_utility.scene_load_failed.disconnect(_on_scene_load_failed)


func _is_scene_resource_ready(scene: PackedScene) -> bool:
	return scene != null and scene.can_instantiate()


func _get_scene_resource_path(scene: PackedScene) -> String:
	return scene.resource_path if scene != null else ""


# --- 信号处理函数 ---

func _on_scene_change_requested(scene: PackedScene) -> void:
	goto_scene_packed(scene)


func _on_return_to_main_menu_requested(_payload: Variant = null) -> void:
	return_to_main_menu()


func _on_scene_switch_started(_path: String, _previous_path: String) -> void:
	send_simple_event(EventNames.SCENE_WILL_CHANGE)


func _on_scene_load_completed(path: String, _scene: PackedScene) -> void:
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已完成异步场景加载: %s" % path)


func _on_scene_load_failed(path: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, "异步场景加载失败: %s" % path)
	send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
