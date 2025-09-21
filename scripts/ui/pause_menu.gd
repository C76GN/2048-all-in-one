# scripts/ui/pause_menu.gd

## PauseMenu: 游戏内暂停菜单的UI控制器。
##
## 负责处理暂停菜单的显示/隐藏，以及响应各个按钮的点击事件。
## 它通过信号与主游戏场景通信，以执行继续、重启等操作。
extends Control

# --- 信号定义 ---

## 当玩家请求继续游戏时发出。
signal resume_game
## 当玩家确认要重新开始游戏时发出。
signal restart_game
## 当玩家请求返回主菜单时发出。
signal return_to_main_menu

# --- 节点引用 ---

@onready var continue_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/ContinueButton
@onready var restart_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/MainMenuButton
@onready var restart_confirm_dialog: ConfirmationDialog = $CanvasLayer/RestartConfirmDialog
@onready var canvas_layer: CanvasLayer = $CanvasLayer

func _ready() -> void:
	# 默认隐藏菜单
	canvas_layer.hide()
	
	# 连接按钮信号
	continue_button.pressed.connect(_on_continue_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	
	restart_confirm_dialog.set_flag(Window.FLAG_POPUP_WM_HINT, true)
	# 连接确认对话框的信号
	restart_confirm_dialog.confirmed.connect(_on_restart_confirm_dialog_confirmed)

# --- 公共接口 ---

## 切换菜单的可见性。
func toggle() -> void:
	canvas_layer.visible = not canvas_layer.visible

# --- 处理输入以关闭菜单 ---

## Godot输入处理函数：捕获未被UI消耗的输入事件。
func _unhandled_input(event: InputEvent) -> void:
	if canvas_layer.visible and event.is_action_pressed("ui_pause"):
		resume_game.emit()
		get_viewport().set_input_as_handled()

# --- 信号处理函数 ---

func _on_continue_button_pressed() -> void:
	resume_game.emit()

func _on_restart_button_pressed() -> void:
	# 显示确认对话框，而不是直接重启
	restart_confirm_dialog.popup_centered()

func _on_main_menu_button_pressed() -> void:
	return_to_main_menu.emit()

func _on_restart_confirm_dialog_confirmed() -> void:
	# 当用户在对话框中点击“确定”后，才发出重启信号
	restart_game.emit()
