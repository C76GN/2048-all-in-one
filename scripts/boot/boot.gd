## Boot: 游戏启动入口。
class_name Boot
extends Node


# --- 常量 ---

const MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu.tscn"


# --- Godot 生命周期方法 ---

func _ready() -> void:
	await Gf.init()

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.call_deferred("goto_scene", MAIN_MENU_SCENE_PATH)


# --- 公共方法 ---

static func are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")


# --- 私有/辅助方法 ---

func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = Gf.get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null
