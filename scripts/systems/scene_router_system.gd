## SceneRouterSystem: 负责全局的场景切换与路由控制。
##
## 负责管理并执行全局的场景跳转(goto_scene_packed)功能。
## 任何需要切换场景的模块，通过调用此系统的公共方法或发送事件来实现。
class_name SceneRouterSystem
extends GFSystem


# --- 常量 ---

const _LOG_TAG: String = "SceneRouterSystem"


# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://scenes/menus/main_menu.tscn"
var _log: GFLogUtility
var _scene_utility: GFSceneUtility


# --- Godot 生命周期方法 ---

func ready() -> void:
	_log = get_utility(GFLogUtility) as GFLogUtility
	_scene_utility = get_utility(GFSceneUtility) as GFSceneUtility
	if is_instance_valid(_scene_utility):
		_scene_utility.scene_load_completed.connect(_on_scene_load_completed)
		_scene_utility.scene_load_failed.connect(_on_scene_load_failed)

	# 可选：监听全局事件 `scene_change_requested` 以解耦调用
	register_simple_event(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)


func dispose() -> void:
	unregister_simple_event(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	unregister_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)
	if is_instance_valid(_scene_utility):
		if _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
			_scene_utility.scene_load_completed.disconnect(_on_scene_load_completed)
		if _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
			_scene_utility.scene_load_failed.disconnect(_on_scene_load_failed)
	_scene_utility = null
	_log = null


# --- 公共方法 ---

## 切换到指定的场景资源。
## @param scene: 待切换的场景资源 (PackedScene)。
func goto_scene_packed(scene: PackedScene) -> void:
	if not _is_scene_resource_ready(scene):
		if _log:
			_log.error(_LOG_TAG, "传入的场景资源为空或不可实例化。")
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, _get_scene_resource_path(scene))
		return

	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return

	if tree.current_scene:
		send_simple_event(EventNames.SCENE_WILL_CHANGE)

	var error := tree.change_scene_to_packed(scene)
	if error != OK:
		if _log:
			_log.error(_LOG_TAG, "切换到场景失败，错误码: %d" % error)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return
	if _log:
		_log.debug(_LOG_TAG, "已请求切换到场景: %s" % scene.resource_path)


## 切换到指定的场景路径。如果可能，请优先使用 goto_scene_packed。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		if _log:
			_log.error(_LOG_TAG, "场景路径必须是绝对的 .tscn 资源路径: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if not ResourceLoader.exists(path, "PackedScene"):
		if _log:
			_log.error(_LOG_TAG, "场景资源不存在或不是 PackedScene: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if is_instance_valid(_scene_utility):
		_scene_utility.load_scene_async(path)
		return

	var next_scene_packed := ResourceLoader.load(path) as PackedScene
	if next_scene_packed == null:
		if _log:
			_log.error(_LOG_TAG, "无法加载场景资源: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	goto_scene_packed(next_scene_packed)


## 快速返回到主菜单。
func return_to_main_menu() -> void:
	goto_scene(_main_menu_scene_path)


## 安全地退出整个游戏。
func quit_game() -> void:
	if _log:
		_log.info(_LOG_TAG, "正在退出游戏。")
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.quit()


# --- 私有/辅助方法 ---

func _is_scene_resource_ready(scene: PackedScene) -> bool:
	return scene != null and scene.can_instantiate()


func _get_scene_resource_path(scene: PackedScene) -> String:
	return scene.resource_path if scene != null else ""


# --- 信号处理函数 ---

func _on_scene_change_requested(scene: PackedScene) -> void:
	goto_scene_packed(scene)


func _on_return_to_main_menu_requested(_payload: Variant = null) -> void:
	return_to_main_menu()


func _on_scene_load_completed(path: String, _scene: PackedScene) -> void:
	send_simple_event(EventNames.SCENE_WILL_CHANGE)
	if _log:
		_log.debug(_LOG_TAG, "已完成异步场景加载: %s" % path)


func _on_scene_load_failed(path: String) -> void:
	if _log:
		_log.error(_LOG_TAG, "异步场景加载失败: %s" % path)
	send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
