# scripts/ui/pause_menu.gd

## PauseMenu: 游戏内暂停菜单的UI控制器。
##
## 负责处理暂停菜单的显示/隐藏，以及响应各个按钮的点击事件。
## 它通过信号与主游戏场景通信，以执行继续、重启等操作。
extends Control


# --- 信号 ---

## 当玩家请求继续游戏时发出。
signal resume_game

## 当玩家确认要重新开始游戏时发出。
signal restart_game

## 当玩家请求返回主菜单时发出。
signal return_to_main_menu



# --- @onready 变量 (节点引用) ---

@onready var _continue_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/ContinueButton
@onready var _restart_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/RestartButton
@onready var _settings_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/SettingsButton
@onready var _main_menu_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	_continue_button.pressed.connect(_on_continue_button_pressed)
	_restart_button.pressed.connect(_on_restart_button_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	_continue_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 信号处理函数 ---

## 响应“继续游戏”按钮的点击事件。
func _on_continue_button_pressed() -> void:
	resume_game.emit()


## 响应“重新开始”按钮的点击事件。
func _on_restart_button_pressed() -> void:
	restart_game.emit()


## 响应“返回主界面”按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	return_to_main_menu.emit()


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_continue_button):
		_continue_button.text = tr("BTN_RESUME")
	if is_instance_valid(_restart_button):
		_restart_button.text = tr("BTN_RESTART")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("BTN_SETTINGS")
	if is_instance_valid(_main_menu_button):
		_main_menu_button.text = tr("BTN_MAIN_MENU")
