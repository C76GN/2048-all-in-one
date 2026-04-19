# scripts/systems/scene_router_system.gd

## SceneRouterSystem: 负责全局的场景切换与路由控制。
##
## 负责管理并执行全局的场景跳转(goto_scene_packed)功能。
## 任何需要切换场景的模块，通过调用此系统的公共方法或发送事件来实现。
class_name SceneRouterSystem
extends GFSystem

# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://scenes/menus/main_menu.tscn"
var _log: GFLogUtility


# --- Godot 生命周期方法 ---

func ready() -> void:
	_log = get_utility(GFLogUtility) as GFLogUtility

	# 可选：监听全局事件 `scene_change_requested` 以解耦调用
	Gf.listen_simple(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	Gf.listen_simple(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)


func dispose() -> void:
	Gf.unlisten_simple(EventNames.SCENE_CHANGE_REQUESTED, _on_scene_change_requested)
	Gf.unlisten_simple(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, _on_return_to_main_menu_requested)


# --- 公共方法 ---

## 切换到指定的场景资源。
## @param scene: 待切换的场景资源 (PackedScene)。
func goto_scene_packed(scene: PackedScene) -> void:
	if scene == null:
		if _log: _log.error("SceneRouterSystem", "错误: 传入的场景资源为空。")
		return
		
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return
		
	if tree.current_scene:
		# 在释放旧场景之前，发送同步清理事件，
		# 让当前场景的节点立即断开所有 GF 事件监听
		Gf.send_simple_event(EventNames.SCENE_WILL_CHANGE)
		tree.current_scene.queue_free()
		tree.current_scene = null

	var new_scene_instance: Node = scene.instantiate()
	tree.root.add_child.call_deferred(new_scene_instance)
	tree.set.call_deferred("current_scene", new_scene_instance)
	if _log: _log.info("SceneRouterSystem", "已请求切换到场景: %s" % scene.resource_path)


## 切换到指定的场景路径。如果可能，请优先使用 goto_scene_packed。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		if _log: _log.error("SceneRouterSystem", "错误: 场景路径必须是绝对的场景资源路径，例如 'res://scenes/my_scene.tscn'")
		return
		
	var next_scene_packed := ResourceLoader.load(path) as PackedScene
	if next_scene_packed == null:
		if _log: _log.error("SceneRouterSystem", "错误: 无法加载场景资源: %s" % path)
		return
		
	goto_scene_packed(next_scene_packed)


## 快速返回到主菜单。
func return_to_main_menu() -> void:
	goto_scene(_main_menu_scene_path)


## 安全地退出整个游戏。
func quit_game() -> void:
	if _log: _log.info("SceneRouterSystem", "正在退出游戏...")
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.quit()


# --- 信号处理函数 ---

func _on_scene_change_requested(scene: PackedScene) -> void:
	goto_scene_packed(scene)


func _on_return_to_main_menu_requested(_payload: Variant = null) -> void:
	return_to_main_menu()
