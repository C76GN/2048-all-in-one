# scripts/ui/game_over_menu.gd

## GameOverMenu: 游戏结束菜单的UI控制器。
##
## 在游戏失败后显示，提供重来或返回主菜单的选项。
extends Control


# --- 信号 ---

## 当玩家请求重新开始游戏时发出。
signal restart_game

## 当玩家请求返回主菜单时发出。
signal return_to_main_menu


# --- @onready 变量 (节点引用) ---

@onready var _restart_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/RestartButton
@onready var _main_menu_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_restart_button.pressed.connect(_on_restart_button_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	_restart_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 信号处理函数 ---

## 响应“重来”按钮的点击事件。
func _on_restart_button_pressed() -> void:
	restart_game.emit()


## 响应“返回主界面”按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	return_to_main_menu.emit()


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_restart_button):
		_restart_button.text = tr("BTN_REPLAY_AGAIN")
	if is_instance_valid(_main_menu_button):
		_main_menu_button.text = tr("BTN_MAIN_MENU")
