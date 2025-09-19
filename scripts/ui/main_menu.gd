# scripts/ui/main_menu.gd

## MainMenu: 主菜单界面的脚本，处理按钮交互和场景切换。
extends Control

## MainMenu: 主菜单界面的脚本，处理按钮交互和场景切换。

# --- 节点引用 ---
@onready var start_game_button: Button = %StartGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	# 连接按钮的 pressed 信号到相应的处理函数
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

# --- 信号处理函数 ---

## 当“开始游戏”按钮被按下时调用。
func _on_start_game_button_pressed() -> void:
	# 通过全局游戏管理器切换到模式选择场景
	GlobalGameManager.goto_scene("res://scenes/mode_selection.tscn")

## 当“设置”按钮被按下时调用（占位功能）。
func _on_settings_button_pressed() -> void:
	print("设置按钮被按下 (功能待开发)")
	# TODO: 未来在这里实现设置界面切换逻辑
	pass # 占位，表示该函数目前无实际操作

## 当“退出”按钮被按下时调用。
func _on_quit_button_pressed() -> void:
	# 通过全局游戏管理器退出游戏
	GlobalGameManager.quit_game()
