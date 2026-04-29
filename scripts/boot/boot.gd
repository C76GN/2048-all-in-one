## Boot: game startup entry point.
class_name Boot
extends Node


# --- Constants ---

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")


# --- Public Methods ---

static func are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")


# --- Godot Lifecycle Methods ---

func _ready() -> void:
	await Gf.init()

	var router := Gf.get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.call_deferred("goto_scene_packed", MAIN_MENU_SCENE)
