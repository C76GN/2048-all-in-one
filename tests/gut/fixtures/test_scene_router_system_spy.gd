## TestSceneRouterSystemSpy: 记录返回主菜单调用的场景路由测试替身。
class_name TestSceneRouterSystemSpy
extends SceneRouterSystem


var return_to_main_menu_count: int = 0


func return_to_main_menu() -> void:
	return_to_main_menu_count += 1
