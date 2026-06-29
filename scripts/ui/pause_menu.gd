## PauseMenu: 游戏内暂停菜单的UI控制器。
##
## 负责处理暂停菜单的显示/隐藏，以及响应各个按钮的点击事件。
## 它通过 GF 事件系统通知系统层执行继续、重启等操作。
class_name PauseMenu
extends "res://scripts/ui/base/game_ui_controller.gd"


# --- 常量 ---

const _ROUTE_SETTINGS_MENU: StringName = &"settings_menu"


# --- @onready 变量 (节点引用) ---

@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	var _connect_result_27: int = _continue_button.pressed.connect(_on_continue_button_pressed)
	var _connect_result_28: int = _restart_button.pressed.connect(_on_restart_button_pressed)
	var _connect_result_29: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_30: int = _main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	_continue_button.grab_focus()


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


func _configure_settings_panel(panel: Node) -> void:
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if panel is SettingsMenu:
		var settings_menu: SettingsMenu = panel
		settings_menu.return_to_main_menu_on_back = false


func _get_ui_router_utility() -> GFUIRouterUtility:
	var utility_value: Object = get_utility(GFUIRouterUtility)
	if utility_value is GFUIRouterUtility:
		var ui_router: GFUIRouterUtility = utility_value
		return ui_router
	return null


# --- 信号处理函数 ---

## 响应"继续游戏"按钮的点击事件。
func _on_continue_button_pressed() -> void:
	send_simple_event(EventNames.RESUME_GAME_REQUESTED)


## 响应"重新开始"按钮的点击事件。
func _on_restart_button_pressed() -> void:
	send_simple_event(EventNames.RESTART_GAME_REQUESTED)


## 响应"返回主界面"按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)


func _on_settings_button_pressed() -> void:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if is_instance_valid(ui_router):
		var _settings_panel: Node = ui_router.push_route(_ROUTE_SETTINGS_MENU, {}, {}, _configure_settings_panel)
	else:
		push_warning("[PauseMenu] GFUIRouterUtility 未注册，无法打开设置菜单。")
