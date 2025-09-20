# scripts/ui/game_over_menu.gd

## GameOverMenu: 游戏结束菜单的UI控制器。
##
## 在游戏失败后显示，提供重来或返回主菜单的选项。
extends Control

# --- 信号定义 ---

signal restart_game
signal return_to_main_menu

# --- 节点引用 ---

@onready var restart_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/MainMenuButton
@onready var canvas_layer: CanvasLayer = $CanvasLayer


func _ready() -> void:
	close() # 默认关闭菜单
	restart_button.pressed.connect(func(): restart_game.emit())
	main_menu_button.pressed.connect(func(): return_to_main_menu.emit())

# --- 公共接口 ---

## 打开菜单。
func open() -> void:
	canvas_layer.show()

## 关闭菜单。
func close() -> void:
	canvas_layer.hide()
