# scripts/ui/main_menu.gd

## MainMenu: 主菜单界面的UI控制器。
##
## 该脚本负责处理主菜单场景中的所有用户交互，
## 例如响应按钮点击事件，并委托 GlobalGameManager 进行场景切换或退出游戏。
extends Control

# --- 导出变量 ---
@export var mode_selection_scene: PackedScene
@export var replay_list_scene: PackedScene

# --- 节点引用 ---
## 对场景中各个按钮节点的引用（使用唯一名称%）。
@onready var start_game_button: Button = %StartGameButton
@onready var replays_button: Button = %ReplaysButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton


## Godot生命周期函数：当节点及其子节点进入场景树时调用。
func _ready() -> void:
	# 在此连接所有按钮的 `pressed` 信号到对应的处理函数，
	# 这是处理UI交互的标准做法。
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	replays_button.pressed.connect(_on_replays_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

# --- 信号处理函数 ---
# 以下函数在对应的按钮被按下时由信号触发。

## 响应“开始游戏”按钮的点击事件。
func _on_start_game_button_pressed() -> void:
	if mode_selection_scene:
		GlobalGameManager.goto_scene_packed(mode_selection_scene)
	else:
		push_error("Mode Selection Scene not set in MainMenu script.")

## 响应“设置”按钮的点击事件（占位功能）。
func _on_settings_button_pressed() -> void:
	print("设置按钮被按下 (功能待开发)")
	# TODO: 未来在此处实现切换到设置界面的逻辑。

## 响应“退出”按钮的点击事件。
func _on_quit_button_pressed() -> void:
	# 委托全局管理器安全地退出游戏。
	GlobalGameManager.quit_game()

## 响应“回放列表”按钮的点击事件。
func _on_replays_button_pressed() -> void:
	if replay_list_scene:
		GlobalGameManager.goto_scene_packed(replay_list_scene)
	else:
		push_error("Replay List Scene not set in MainMenu script.")
