# global/game_manager.gd

# GlobalGameManager: 负责处理全局游戏逻辑，如场景切换和游戏退出。
# 作为一个自动加载节点（单例），它在整个游戏生命周期中都可访问。
extends Node

# --- 公共接口 ---

# 切换到指定的场景。
# @param path: 目标场景的资源路径 (例如 "res://scenes/main_menu.tscn")。
func goto_scene(path: String) -> void:
	# 确保提供的路径是有效的场景路径格式
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		push_error("错误: 场景路径必须是绝对的场景资源路径，例如 'res://scenes/my_scene.tscn'")
		return
	
	# 释放当前场景以避免内存泄漏。
	# Godot会自动处理子节点的释放。
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
		# 确保在释放后当前场景被置空，防止逻辑错误
		get_tree().current_scene = null
	
	# 加载并实例化新场景。
	# load() 函数会缓存资源，多次调用同一路径不会重复加载。
	var next_scene_packed = load(path)
	var new_scene_instance = next_scene_packed.instantiate()
	
	# 将新场景添加到场景树的根节点。
	get_tree().root.add_child(new_scene_instance)
	# 更新当前活动场景。
	get_tree().current_scene = new_scene_instance
	
	print("已切换到场景: ", path)


# 退出游戏应用。
func quit_game() -> void:
	print("正在退出游戏...")
	get_tree().quit()
