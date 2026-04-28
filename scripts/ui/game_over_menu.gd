# scripts/ui/game_over_menu.gd

## GameOverMenu: 游戏结束菜单的UI控制器。
##
## 在游戏失败后显示，提供重来或返回主菜单的选项。
## 通过 GF 事件系统通知系统层执行操作。
extends GFUIController


# --- 常量 ---

## 设置菜单场景路径。
const SETTINGS_MENU_SCENE: String = "res://scenes/menus/settings_menu.tscn"


# --- @onready 变量 (节点引用) ---

@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_restart_button.pressed.connect(_on_restart_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	_restart_button.grab_focus()


# --- 信号处理函数 ---

## 响应"重来"按钮的点击事件。
func _on_restart_button_pressed() -> void:
	send_simple_event(EventNames.RESTART_GAME_REQUESTED)


## 响应"返回主界面"按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)


func _on_settings_button_pressed() -> void:
	var ui_util := get_utility(GFUIUtility) as GFUIUtility
	if ui_util:
		ui_util.push_panel(SETTINGS_MENU_SCENE, GFUIUtility.Layer.POPUP, _configure_settings_panel)


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_restart_button):
		_restart_button.text = tr("BTN_REPLAY_AGAIN")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("BTN_SETTINGS")
	if is_instance_valid(_main_menu_button):
		_main_menu_button.text = tr("BTN_MAIN_MENU")


func _configure_settings_panel(panel: Node) -> void:
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if panel is SettingsMenu:
		(panel as SettingsMenu).return_to_main_menu_on_back = false
