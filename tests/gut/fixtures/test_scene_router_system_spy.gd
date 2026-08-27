## TestSceneRouterSystemSpy: 记录返回主菜单调用的场景路由测试替身。
class_name TestSceneRouterSystemSpy
extends GameSceneRouterPort


var return_to_main_menu_count: int = 0
var restart_current_scene_count: int = 0


func get_required_utilities() -> Array[Script]:
	return []


func ready() -> void:
	pass


func return_to_main_menu() -> void:
	return_to_main_menu_count += 1


func restart_current_scene() -> void:
	restart_current_scene_count += 1
