# scripts/menus/main_menu.gd

## MainMenu: 主菜单界面的UI控制器。
##
## 该脚本负责处理主菜单场景中的所有用户交互，
## 例如响应按钮点击事件，并委托 GlobalGameManager 进行场景切换或退出游戏。
class_name MainMenu
extends Control


# --- 导出变量 ---

@export var mode_selection_scene: PackedScene
@export var replay_list_scene: PackedScene
@export var bookmark_list_scene: PackedScene


# --- @onready 变量 (节点引用) ---

@onready var _start_game_button: Button = %StartGameButton
@onready var _load_bookmark_button: Button = %LoadBookmarkButton
@onready var _replays_button: Button = %ReplaysButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_start_game_button.pressed.connect(_on_start_game_button_pressed)
	_load_bookmark_button.pressed.connect(_on_load_bookmark_button_pressed)
	_replays_button.pressed.connect(_on_replays_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_quit_button.pressed.connect(_on_quit_button_pressed)

	_start_game_button.grab_focus()


# --- 信号处理函数 ---

## 响应“开始游戏”按钮的点击事件。
func _on_start_game_button_pressed() -> void:
	if is_instance_valid(mode_selection_scene):
		GlobalGameManager.goto_scene_packed(mode_selection_scene)
	else:
		push_error("MainMenu: 模式选择场景 (mode_selection_scene) 未设置。")


## 响应“读取书签”按钮的点击事件。
func _on_load_bookmark_button_pressed() -> void:
	if is_instance_valid(bookmark_list_scene):
		GlobalGameManager.goto_scene_packed(bookmark_list_scene)
	else:
		push_error("MainMenu: 书签列表场景 (bookmark_list_scene) 未设置。")


## 响应“回放列表”按钮的点击事件。
func _on_replays_button_pressed() -> void:
	if is_instance_valid(replay_list_scene):
		GlobalGameManager.goto_scene_packed(replay_list_scene)
	else:
		push_error("MainMenu: 回放列表场景 (replay_list_scene) 未设置。")


## 响应“设置”按钮的点击事件（占位功能）。
func _on_settings_button_pressed() -> void:
	print("设置按钮被按下 (功能待开发)")


## 响应“退出”按钮的点击事件。
func _on_quit_button_pressed() -> void:
	GlobalGameManager.quit_game()
