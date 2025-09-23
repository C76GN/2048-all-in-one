# global/game_manager.gd

## GlobalGameManager: 负责处理全局游戏状态与核心流程控制的单例脚本。
##
## 作为一个自动加载的全局节点 (Singleton)，它在整个游戏生命周期中持续存在，
## 主要用于提供场景切换、安全退出游戏以及跨场景传递数据（如所选的游戏模式配置）等核心服务。
extends Node
var selected_mode_config_path: String

# --- 公共接口 ---

## 切换到指定的场景。
##
## 此函数会安全地释放当前场景，然后加载并显示新场景。
func goto_scene(path: String) -> void:
	# 验证输入路径的有效性。
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		push_error("错误: 场景路径必须是绝对的场景资源路径，例如 'res://scenes/my_scene.tscn'")
		return
	
	# 安全地释放当前场景以避免内存泄漏。
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null
	
	# 加载并实例化新场景。
	var next_scene_packed = load(path)
	if next_scene_packed == null:
		push_error("错误: 无法加载场景资源: " + path)
		return
		
	var new_scene_instance = next_scene_packed.instantiate()
	
	# 将新场景添加到场景树并设为当前活动场景。
	get_tree().root.add_child(new_scene_instance)
	get_tree().current_scene = new_scene_instance
	
	print("已切换到场景: ", path)

## 安全地退出整个游戏应用。
func quit_game() -> void:
	print("正在退出游戏...")
	# 调用 get_tree().quit() 是Godot中关闭游戏程序的标准方法。
	get_tree().quit()
