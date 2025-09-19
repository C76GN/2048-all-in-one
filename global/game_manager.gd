# global/game_manager.gd

## GlobalGameManager: 负责处理全局游戏逻辑的单例脚本。
##
## 作为一个自动加载节点（Singleton），它在整个游戏生命周期中都可被访问，
## 主要用于提供场景切换和安全退出游戏等全局服务。
extends Node

# --- 公共接口 ---

## 切换到指定的场景。
##
## 此函数会安全地释放当前场景，然后加载并显示新场景。
## @param path: 目标场景的资源路径 (例如 "res://scenes/main_menu.tscn")。
func goto_scene(path: String) -> void:
	# 步骤1: 验证输入路径的有效性，防止因路径错误导致游戏崩溃。
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		push_error("错误: 场景路径必须是绝对的场景资源路径，例如 'res://scenes/my_scene.tscn'")
		return
	
	# 步骤2: 安全地释放当前场景以避免内存泄漏。
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
		# 在某些情况下，等待一帧或使用信号可以确保场景完全被释放。
		# 为防止逻辑错误，立即将引用置空。
		get_tree().current_scene = null
	
	# 步骤3: 加载并实例化新场景。
	# load() 函数会缓存资源，多次调用同一路径不会重复从磁盘加载。
	var next_scene_packed = load(path)
	if next_scene_packed == null:
		push_error("错误: 无法加载场景资源: " + path)
		return
		
	var new_scene_instance = next_scene_packed.instantiate()
	
	# 步骤4: 将新场景添加到场景树并设为当前活动场景。
	get_tree().root.add_child(new_scene_instance)
	get_tree().current_scene = new_scene_instance
	
	print("已切换到场景: ", path)


## 安全地退出整个游戏应用。
func quit_game() -> void:
	print("正在退出游戏...")
	# 调用 get_tree().quit() 是Godot中关闭游戏程序的标准方法。
	get_tree().quit()
